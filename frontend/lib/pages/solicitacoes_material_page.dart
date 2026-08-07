import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/material_model.dart';
import '../models/solicitacao_material_model.dart';
import '../providers/solicitacao_material_provider.dart';
import '../providers/material_provider.dart';
import '../providers/orcamento_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';
import '../utils/api_client.dart';
import '../pages/controle_estoque_page.dart' show MaterialFormDialog, formatarUnidadeExibicao, formatarMedidaOuDimensoes, formatarQuantidade;
import '../pages/orcamento_page.dart';
import '../pages/historico_solicitacoes_page.dart' hide formatarUnidadeExibicao;
import '../widgets/escolher_usuario_chat_dialog.dart';
import '../providers/robo_helper_provider.dart';

class _UpperCaseFormatter extends TextInputFormatter {
  static final _acentos = {
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'Ç': 'C', 'ç': 'c',
    'Ñ': 'N', 'ñ': 'n',
  };

  static String _removerAcentos(String s) =>
      s.split('').map((c) => _acentos[c] ?? c).join();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove vírgulas antes de qualquer outra transformação
    final semVirgula = newValue.text.replaceAll(',', '');
    final texto = _removerAcentos(semVirgula).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

/// Formatter para os campos Medida e Espessura:
/// - remove acentuação e força maiúsculas (igual ao _UpperCaseFormatter)
/// - converte vírgula em ponto
/// - permite apenas 1 ponto POR NÚMERO (bloqueia pontos repetidos/seguidos
///   dentro do mesmo número, ex.: "1..5" ou "1.2.3"), mas preserva múltiplos
///   números na mesma medida, ex.: "2.44x1.22m" (dois números, um ponto cada)
class _MedidaEspessuraFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1) Vírgula -> ponto
    var texto = newValue.text.replaceAll(',', '.');

    // 2) Remove acentos e força minúsculas
    texto = _UpperCaseFormatter._removerAcentos(texto).toLowerCase();

    // 3) Para cada bloco de dígitos+pontos (um "número"), permite apenas o
    //    primeiro ponto e remove os demais. Não mexe no que não é dígito/ponto
    //    (letras, "x", espaços, etc.), preservando a separação entre números.
    texto = texto.replaceAllMapped(RegExp(r'[\d.]+'), (m) {
      final partes = m.group(0)!.split('.');
      if (partes.length > 2) {
        return '${partes[0]}.${partes.sublist(1).join('')}';
      }
      return m.group(0)!;
    });

    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

/// Formata um valor de espessura garantindo o sufixo "mm" sem duplicar.
/// Dados antigos podem já ter sido salvos com "mm"/"MM" digitado manualmente
/// (ex.: "2MM", "2 mm"); removemos esse sufixo antes de reanexar o nosso.
String? formatarEspessuraComSufixo(String? valor) {
  final v = valor?.trim();
  if (v == null || v.isEmpty) return null;
  final numero = v.replaceAll(RegExp(r'\s*mm\s*$', caseSensitive: false), '').trim();
  if (numero.isEmpty) return null;
  return '${numero}mm';
}

/// Formatter para o campo Espessura: aceita apenas dígitos, ponto e vírgula
/// (vírgula é convertida em ponto), bloqueando letras e qualquer outro
/// caractere.
class _EspessuraFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(',', '.');
    texto = texto.replaceAll(RegExp(r'[^\d.]'), '');
    final partes = texto.split('.');
    if (partes.length > 2) {
      texto = '${partes[0]}.${partes.sublist(1).join('')}';
    }
    final sel = newValue.selection.copyWith(
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class SolicitacoesMaterialPage extends StatefulWidget {
  const SolicitacoesMaterialPage({super.key});

  @override
  State<SolicitacoesMaterialPage> createState() =>
      _SolicitacoesMaterialPageState();
}

class _SolicitacoesMaterialPageState extends State<SolicitacoesMaterialPage>
    with SingleTickerProviderStateMixin {
  final _buscaCtrl = TextEditingController();
  String _andamentoFiltro = '';
  Timer? _debounceTimer;
  late TabController _tabController;

  // ── Robô assistente: tour "Como fazer uma solicitação?" ──────────────────
  final _tourKeyNovaSolicitacao = GlobalKey();
  final _criarSolicitacaoTourKeys = _CriarSolicitacaoTourKeys();
  RoboHelperProvider? _roboHelperPagina;
  // Evita reabrir/refechar o dialog "Nova Solicitação" (ou o seletor de
  // material dentro dele) mais de uma vez enquanto o tour navega entre
  // paradas rapidamente — mesmo padrão usado em fornecedores_page.dart.
  bool _dialogTourAberto = false;
  bool _seletorTourAberto = false;
  // Flags de transição SEPARADAS por camada de dialog — usar uma única
  // flag compartilhada fazia o _abrirSeletorTour() ser bloqueado pelo
  // _dialogTourEmTransicao ainda ligado pelo _abrirDialogTour() anterior
  // (o addPostFrameCallback que o desliga só roda no frame seguinte, e o
  // tour já tinha avançado pro próximo passo antes disso), fazendo o
  // dialog "Selecionar Material" simplesmente não abrir durante o tour.
  bool _dialogTourEmTransicao = false;
  bool _seletorTourEmTransicao = false;

  // ── Robô assistente: tour "Como adicionar materiais a uma solicitação
  // existente" ──────────────────────────────────────────────────────────
  // Keys do card em destaque na listagem do tour "Como adicionar materiais a
  // uma solicitação existente". IMPORTANTE: usamos DUAS GlobalKeys distintas
  // (fictício vs. linha real) em vez de reutilizar a mesma — o Flutter proíbe
  // que a mesma GlobalKey seja usada por dois elementos montados ao mesmo
  // tempo, e como `_tourExibirCardFicticio` é setado de forma assíncrona
  // (dentro de `aoEntrar`), havia uma janela de frames em que o card
  // fictício E a primeira linha real da lista (recém-chegada do provider)
  // tentavam existir simultaneamente com a mesma key. Isso corrompia o
  // Element daquela posição, deixando o GestureDetector/MouseRegion "preso"
  // até um rebuild completo — exatamente o sintoma relatado de linhas que
  // param de responder a clique/hover depois de exclusões rápidas.
  final _tourKeyCardSolicitacaoFicticio = GlobalKey();
  final _tourKeyCardSolicitacaoReal = GlobalKey();
  // Key que o RoboTourStop efetivamente usa: aponta pra uma das duas acima,
  // trocada apenas depois que uma delas garantidamente saiu da árvore.
  GlobalKey get _tourKeyCardSolicitacao =>
      _tourExibirCardFicticio ? _tourKeyCardSolicitacaoFicticio : _tourKeyCardSolicitacaoReal;
  final _tourKeyAdicionarMateriaisExistente = GlobalKey();
  bool _tourExibirCardFicticio = false;

  // ── Robô assistente: tour "Como atender uma solicitação" ────────────────
  // Keys do primeiro card COMPRADO/ESTOQUE (dentro do dialog de
  // visualização) e do dropdown de andamento (na tabela) — só fazem
  // sentido no primeiro item/linha, igual ao padrão de
  // _tourKeyCardSolicitacao acima.
  final _tourKeyComprado = GlobalKey();
  final _tourKeyEstoque = GlobalKey();
  final _tourKeyAndamento = GlobalKey<_StatusBadgeEditavelState>();
  // Solicitação simulada em memória (nunca enviada ao backend) usada como
  // substituta de uma solicitação real quando a lista "Em Andamento" está
  // vazia — apenas para o tour "Como adicionar materiais a uma solicitação
  // existente" poder dar highlight e abrir o dialog de verdade.
  SolicitacaoMaterialModel? _solicitacaoTourFake;
  bool _dialogVisualizarTourAberto = false;
  bool _dialogVisualizarTourEmTransicao = false;
  // Controla o scroll da aba "Em Andamento" — usado pelo tour pra sempre
  // voltar ao topo da lista antes de dar highlight na primeira linha.
  final _scrollEmAndamento = ScrollController();

  // ── Robô assistente: tour "Como orçar materiais solicitados" ────────────
  // Keys da aba "Materiais Solicitados": o seletor "Agrupar por", o
  // primeiro material listado (sempre o primeiro item do primeiro grupo,
  // independente do modo de agrupamento ativo) e o botão "Orçar
  // selecionados".
  final _tourKeyAgruparPorMateriaisSolicitados = GlobalKey();
  final _tourKeyPrimeiroMaterialSolicitado = GlobalKey();
  final _tourKeyOrcarSelecionadosMateriaisSolicitados = GlobalKey();

  // ── Paginação (independente por aba) ─────────────────────────────────────
  static const int _itensPorPagina = 50;
  int _paginaEmAndamento = 0;
  int _paginaFinalizadas = 0;

  // ── Totais globais (sem filtro) ──────────────────────────────────────────
  // Capturados na primeira carga (sem busca/andamento) e atualizados sempre
  // que o usuário limpa todos os filtros.
  int _totalItensGlobal     = 0;
  int _totalResolvidosGlobal = 0;
  bool _totaisGlobaisCarregados = false;

  // Evita disparar a busca+abertura da solicitação pendente (vinda de um
  // encaminhamento no chat) mais de uma vez enquanto ela ainda está em
  // andamento — o build() roda de novo a cada frame do
  // addPostFrameCallback abaixo, mas o id só é consumido do provider depois
  // que a busca termina.
  bool _abrindoSolicitacaoPendente = false;

  // Guardamos a referência ao provider (não o BuildContext) para poder
  // remover o listener com segurança em dispose(). Nunca se deve chamar
  // context.read<T>() dentro de dispose(): se a página estiver sendo
  // desmontada porque o usuário deslogou/trocou de usuário (o que destrói
  // toda a árvore do StatefulShellRoute no mesmo frame em que o provider
  // dá notifyListeners() em resetarConexao()), o elemento já pode estar
  // inativo nesse ponto — e o lookup do InheritedWidget feito por
  // context.read() lança "Looking up a deactivated widget's ancestor is
  // unsafe". Capturar a referência em didChangeDependencies() (chamado
  // logo após initState, com o context ainda garantidamente ativo) evita
  // esse lookup tardio.
  SolicitacaoMaterialProvider? _solicitacaoProviderRef;

  // Nota: quem controla "página aberta" (badge, marcar como visualizado)
  // é o AppShell — via SolicitacaoMaterialProvider.definirPaginaVisivel(),
  // baseado na rota atual — e não o ciclo de vida deste State. Essa página
  // vive dentro de um StatefulShellBranch (IndexedStack) e não é destruída
  // ao trocar de aba, então didChangeDependencies()/dispose() aqui não são
  // um sinal confiável de "entrei"/"saí" da tela.
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await context.read<SolicitacaoMaterialProvider>().carregar();
        if (!mounted) return;
        _atualizarTotaisGlobais();
        final helper = context.read<RoboHelperProvider>();
        helper.notificarRota('/solicitacoes-material');
        _roboHelperPagina = helper;
        _roboHelperPagina!.addListener(_onRoboHelperPaginaChanged);
      }
    });

    // Escuta o provider diretamente (em vez de depender só de
    // context.watch() dentro de build()) para a abertura pendente vinda de
    // um encaminhamento no chat. Motivo: esta página vive dentro de um
    // IndexedStack/StatefulShellBranch (ver nota acima) e, em produção,
    // context.go('/solicitacoes-material') pode apenas trocar qual branch
    // está visível sem necessariamente reconstruir esta página no mesmo
    // frame em que solicitarAberturaSolicitacao() chama notifyListeners() —
    // um addListener aqui garante que reagimos ao evento assim que ele
    // ocorre, independente de esta página estar prestes a (re)construir por
    // conta própria. Sem isso, o valor ficava "parado" no provider até
    // algo mais (ex.: o botão Atualizar) forçar um rebuild que finalmente
    // o lesse dentro de build().
    context.read<SolicitacaoMaterialProvider>().addListener(_onProviderChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Captura a referência do provider aqui, e não em dispose(): neste
    // ponto o context está garantidamente ativo (didChangeDependencies só
    // roda com o elemento montado), então o lookup do InheritedWidget é
    // seguro. Guardamos o objeto do provider (não o context) para usar em
    // dispose() sem precisar de um novo lookup na árvore.
    _solicitacaoProviderRef = context.read<SolicitacaoMaterialProvider>();
  }

  void _onProviderChanged() {
    _tentarAbrirSolicitacaoPendente();
  }

  // Rede de segurança: se o tour terminar (ESC, "Fechar", ou trocou de
  // dica) enquanto um dialog aberto pelo próprio tour ainda está na tela,
  // garante que ele seja fechado e que as flags voltem a false — senão a
  // próxima tentativa de abrir o mesmo dialog fica bloqueada pelo guard.
  void _onRoboHelperPaginaChanged() {
    if (!mounted) return;
    if (_roboHelperPagina!.tourAtivo) return;

    // Quantos dialogs o tour pode ter empilhado simultaneamente (ex.:
    // "Nova Solicitação" com o "Selecionar Material" aberto por cima).
    // Contamos as flags ativas ANTES de zerá-las para saber quantos
    // maybePop() precisamos disparar.
    final dialogsAbertosPeloTour = [
      _seletorTourAberto,
      _dialogTourAberto,
      _dialogVisualizarTourAberto,
    ].where((aberto) => aberto).length;

    _seletorTourAberto = false;
    _dialogTourAberto = false;
    _dialogVisualizarTourAberto = false;

    if (dialogsAbertosPeloTour > 0) {
      // IMPORTANTE: maybePop() é assíncrono — disparar as N chamadas em
      // sequência sem aguardar cada uma resolver faz com que a pilha do
      // Navigator ainda não tenha sido atualizada entre uma chamada e
      // outra (ou faz pops concorrentes se atropelarem), deixando
      // dialogs empilhados (ex.: "Selecionar Material" sobre "Nova
      // Solicitação") sem fechar todos ao apertar ESC. Por isso
      // aguardamos cada pop terminar antes de disparar o próximo.
      () async {
        final navigator = Navigator.of(context, rootNavigator: true);
        for (var i = 0; i < dialogsAbertosPeloTour; i++) {
          if (!mounted) return;
          final fechou = await navigator.maybePop();
          // Se não havia mais nada pra fechar, para de tentar.
          if (!fechou) break;
        }
      }();
    }

    if (_tourExibirCardFicticio) {
      setState(() => _tourExibirCardFicticio = false);
    }
  }

  @override
  void dispose() {
    // Usa a referência guardada em didChangeDependencies() em vez de
    // context.read() aqui — ver comentário no campo _solicitacaoProviderRef
    // para o motivo (evita "Looking up a deactivated widget's ancestor is
    // unsafe" quando a página é desmontada junto com uma troca de
    // usuário/logout).
    _solicitacaoProviderRef?.removeListener(_onProviderChanged);
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    _tabController.dispose();
    _scrollEmAndamento.dispose();
    _roboHelperPagina?.removeListener(_onRoboHelperPaginaChanged);
    try {
      context.read<RoboHelperProvider>().encerrarTour();
      context.read<RoboHelperProvider>().limparOpcoes('/solicitacoes-material');
    } catch (_) {}
    super.dispose();
  }

  /// Consome `solicitacaoParaAbrirPendente` (se houver) e abre o diálogo de
  /// visualização. Chamado tanto pelo listener direto do provider
  /// (_onProviderChanged) quanto, redundantemente, pelo próprio build()
  /// abaixo — o que ocorrer primeiro processa o id; a flag
  /// _abrindoSolicitacaoPendente evita disparo duplicado entre as duas vias.
  void _tentarAbrirSolicitacaoPendente() {
    if (!mounted) return;
    final provider = context.read<SolicitacaoMaterialProvider>();
    final solicitacaoPendenteId = provider.solicitacaoParaAbrirPendente;
    if (solicitacaoPendenteId == null || _abrindoSolicitacaoPendente) return;

    _abrindoSolicitacaoPendente = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      provider.consumirSolicitacaoParaAbrirPendente();
      final solicitacao = await provider.buscarPorId(solicitacaoPendenteId);
      _abrindoSolicitacaoPendente = false;
      if (!mounted || !context.mounted) return;
      if (solicitacao == null) {
        // buscarPorId falhou (rede, token expirado, solicitação excluída
        // etc.) — em produção isso é bem mais comum que em dev (rede
        // local/rápida), e sem este aviso o usuário só via a troca de aba
        // acontecer sem nenhum diálogo abrir, sem nenhuma pista do motivo.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              provider.erro ?? 'Não foi possível abrir a solicitação.',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
      _abrirFormSolicitacao(solicitacao);
    });
  }

  void _aplicarFiltros() {
    context.read<SolicitacaoMaterialProvider>().carregar(
          busca: _buscaCtrl.text.trim(),
          andamento: _andamentoFiltro.isEmpty ? null : _andamentoFiltro,
        );
    setState(() {
      _paginaEmAndamento = 0;
      _paginaFinalizadas = 0;
    });
    // Quando não há filtro ativo, a lista resultante é a global — captura os totais
    final semFiltro = _buscaCtrl.text.trim().isEmpty && _andamentoFiltro.isEmpty;
    if (semFiltro) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _atualizarTotaisGlobais());
    }
  }

  /// Captura os totais globais a partir da lista atual do provider.
  /// Deve ser chamado apenas quando não há filtros ativos.
  void _atualizarTotaisGlobais() {
    if (!mounted) return;
    final sols = context.read<SolicitacaoMaterialProvider>().solicitacoes;
    if (sols.isEmpty && _totaisGlobaisCarregados) return;
    final itens      = sols.fold<int>(0, (s, sol) => s + sol.totalMateriais);
    final resolvidos = sols.fold<int>(0, (s, sol) => s + sol.totalResolvidos);
    setState(() {
      _totalItensGlobal     = itens;
      _totalResolvidosGlobal = resolvidos;
      _totaisGlobaisCarregados = true;
    });
  }

  /// Abre a página de histórico geral de solicitações (todos os materiais de
  /// todas as OS, em ordem cronológica). Ao tocar em um item lá, a página de
  /// histórico marca a solicitação correspondente como "pendente de abertura"
  /// no provider e fecha — esta tela, que já observa esse estado via
  /// `_tentarAbrirSolicitacaoPendente`, então abre o diálogo automaticamente.
  Future<void> _abrirHistoricoSolicitacoes() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoricoSolicitacoesPage()),
    );
  }

  Future<void> _abrirFormSolicitacao([SolicitacaoMaterialModel? solicitacao]) async {
    final Widget dialog = solicitacao == null
        ? const _CriarSolicitacaoDialog()
        : _VisualizarSolicitacaoDialog(solicitacao: solicitacao);
    
    final salvou = await showDialog<bool>(
      context: context,
      builder: (_) => dialog,
    );
    if (salvou == true && mounted) {
      await context.read<SolicitacaoMaterialProvider>().carregar();
      // Se não há filtros ativos, a lista atual é a global — atualiza os totais
      final semFiltro = _buscaCtrl.text.trim().isEmpty && _andamentoFiltro.isEmpty;
      if (semFiltro) _atualizarTotaisGlobais();
    }
  }

  /// Abre o dialog "Nova Solicitação" já com um item de material inicial
  /// (simulando o clique em "Adicionar Material") e com as GlobalKeys do
  /// tour vinculadas — usado apenas pelo tour do robô assistente.
  Future<void> _abrirDialogTour() async {
    if (_dialogTourAberto || _dialogTourEmTransicao) return;
    _dialogTourAberto = true;
    _dialogTourEmTransicao = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogTourEmTransicao = false;
    });
    showDialog<bool>(
      context: context,
      // Enquanto o tour do robô guia este formulário, o balão de dica fica
      // fora do dialog (numa camada acima dele, no Overlay raiz), e o
      // GestureDetector de tela cheia do robô (que avança o tour a cada
      // toque) fica por baixo do balão mas por CIMA do barrier do dialog.
      // Se o barrier continuar dismissible, qualquer clique do usuário
      // tentando interagir com a dica (ex.: os botões Anterior/Próximo)
      // vaza pro barrier e fecha o formulário sem querer — foi isso que
      // fazia o tour "pular" direto da parada do botão "Nova Solicitação"
      // pro campo Observação: o dialog fechava e reabria no meio do tour,
      // perdendo os passos intermediários. Mesmo padrão usado em estoque.
      barrierDismissible: !_dialogTourAberto,
      builder: (_) => _CriarSolicitacaoDialog(
        tourKeys: _criarSolicitacaoTourKeys,
        abrirComItemInicial: true,
      ),
    ).then((salvou) {
      if (mounted) _dialogTourAberto = false;
      if (salvou == true && mounted) {
        context.read<SolicitacaoMaterialProvider>().carregar();
      }
    });
    // Aguarda um frame para o dialog começar a montar antes de o provider
    // tentar medir a key em destaque.
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Fecha o dialog "Nova Solicitação" aberto pelo tour, aguardando a
  /// animação de saída terminar antes de retornar — evita que a parada
  /// seguinte/anterior tente medir keys enquanto ele ainda está visível.
  /// IMPORTANTE: rootNavigator:true porque showDialog abre no Navigator
  /// raiz; sem isso maybePop() poparia a rota da página em vez do dialog.
  Future<void> _fecharDialogTourSeAberto() async {
    if (!_dialogTourAberto || _dialogTourEmTransicao) return;
    _dialogTourAberto = false;
    _dialogTourEmTransicao = true;
    await Navigator.of(context, rootNavigator: true).maybePop();
    _dialogTourEmTransicao = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// Abre o dialog "Selecionar Material" por cima do "Nova Solicitação",
  /// já indo direto para a categoria "TODOS", com as keys do tour.
  Future<void> _abrirSeletorTour() async {
    if (_seletorTourAberto || _seletorTourEmTransicao) return;
    _seletorTourAberto = true;
    _seletorTourEmTransicao = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seletorTourEmTransicao = false;
    });
    showDialog<MaterialModel>(
      context: context,
      // Mesmo motivo do dialog "Nova Solicitação" em _abrirDialogTour: o
      // GestureDetector de tela cheia do robô fica acima do barrier deste
      // dialog enquanto o tour está ativo, e um barrier dismissible deixa
      // cliques nos botões da dica vazarem e fecharem o seletor sem querer.
      barrierDismissible: !_seletorTourAberto,
      builder: (_) => _SeletorMaterialDialog(
        tourKeys: _criarSolicitacaoTourKeys.seletorMaterial,
        abrirTodosAutomaticamente: true,
      ),
    ).then((_) {
      if (mounted) _seletorTourAberto = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Fecha o "Selecionar Material" aberto pelo tour, para voltar ao
  /// "Nova Solicitação" por baixo dele (ex.: botão "Anterior").
  Future<void> _fecharSeletorTourSeAberto() async {
    if (!_seletorTourAberto || _seletorTourEmTransicao) return;
    _seletorTourAberto = false;
    _seletorTourEmTransicao = true;
    await Navigator.of(context, rootNavigator: true).maybePop();
    _seletorTourEmTransicao = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// Monta (apenas em memória, sem tocar o backend) uma solicitação
  /// fictícia "em andamento" para o tour "Como adicionar materiais a uma
  /// solicitação existente" poder dar highlight e abrir o dialog de
  /// verdade. Antes, quando a lista estava vazia, essa etapa criava uma
  /// solicitação real no servidor só pra servir de demonstração — o que
  /// não faz sentido, já que a intenção é apenas simular a existência de
  /// uma solicitação para a dica funcionar, não gerar dado real. Agora,
  /// se não houver nenhuma solicitação em andamento, geramos um
  /// [SolicitacaoMaterialModel] fake (guardado em [_solicitacaoTourFake])
  /// usando um material real já carregado (só para exibição/nome), e o
  /// dialog de visualização do tour passa a aceitar esse fake como
  /// alternativa a uma solicitação vinda do provider.
  Future<void> _garantirSolicitacaoTourExistente() async {
    final provider = context.read<SolicitacaoMaterialProvider>();
    final temEmAndamento =
        provider.solicitacoes.any((s) => s.andamento != 'FINALIZADO');
    if (temEmAndamento) {
      _solicitacaoTourFake = null;
      return;
    }

    try {
      // Precisa de um material real para o item de demonstração — usa o
      // primeiro disponível já carregado no MaterialProvider (carregando
      // a primeira página, sem filtros, se ainda não houver nada em
      // memória).
      final materialProvider = context.read<MaterialProvider>();
      var materiais = materialProvider.materiais;
      if (materiais.isEmpty) {
        await materialProvider.carregar();
        if (!mounted) return;
        materiais = materialProvider.materiais;
      }
      if (materiais.isEmpty) {
        // Sem nenhum material cadastrado no sistema não há como montar uma
        // solicitação de demonstração — mantém o fallback do card fictício.
        _solicitacaoTourFake = null;
        return;
      }
      final materialDemo = materiais.first;
      final agora = DateTime.now();

      final itemFake = ItemSolicitacaoModel(
        id: -1,
        solicitacaoId: -1,
        materialId: materialDemo.id,
        materialNome: materialDemo.nome,
        materialUnidade: materialDemo.unidade,
        materialIdentificador: materialDemo.identificador,
        materialMedida: materialDemo.medida,
        materialEspessura: materialDemo.espessura,
        materialLargura: materialDemo.largura,
        materialComprimento: materialDemo.comprimento,
        materialCategoria: materialDemo.categoria,
        materialQuantidadeEstoque: materialDemo.quantidade,
        quantidade: 1,
        observacao: null,
        imagemUrl: null,
        comprado: false,
        estoque: false,
        criadoEm: agora,
      );

      if (mounted) {
        setState(() {
          _solicitacaoTourFake = SolicitacaoMaterialModel(
            id: -1,
            numeroOS: 'DEMONSTRACAO',
            nomeCliente: 'Cliente',
            dataNecessidade: agora.add(const Duration(days: 7)),
            andamento: 'EM_ANDAMENTO',
            observacao: 'Solicitação de exemplo usada apenas nesta dica — '
                'nada é salvo.',
            // Não usamos o usuário logado aqui de propósito: esse campo é
            // só exibido no dialog de visualização e o valor real não
            // importa nesta simulação (é descartado ao sair do tour).
            usuarioId: 0,
            usuarioNome: 'Visual Premium',
            criadoEm: agora,
            atualizadoEm: agora,
            itens: [itemFake],
            adicionais: const [],
          );
        });
      }
    } catch (_) {
      // Falhou silenciosamente (ex.: material indisponível) — o chamador
      // cai de volta pro card fictício.
      _solicitacaoTourFake = null;
    }
  }

  /// Abre o dialog "Solicitação OS ..." (visualização) por cima da listagem
  /// e dá highlight no botão "Adicionar Materiais" — usado apenas pelo tour
  /// do robô assistente. Se existir alguma solicitação em andamento, abre a
  /// primeira delas (a mesma que está com o card em destaque); senão abre o
  /// card fictício com uma solicitação de demonstração.
  Future<void> _abrirDialogVisualizarTour() async {
    if (_dialogVisualizarTourAberto || _dialogVisualizarTourEmTransicao) return;
    _dialogVisualizarTourAberto = true;
    _dialogVisualizarTourEmTransicao = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogVisualizarTourEmTransicao = false;
    });

    final emAndamento = context
        .read<SolicitacaoMaterialProvider>()
        .solicitacoes
        .where((s) => s.andamento != 'FINALIZADO')
        .toList()
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

    // Usa a primeira solicitação real "em andamento" se houver; senão cai
    // para a solicitação simulada (montada em _garantirSolicitacaoTourExistente,
    // nunca enviada ao backend) para que o tour continue funcionando mesmo
    // sem nenhuma solicitação de verdade.
    final solicitacaoParaAbrir =
        emAndamento.isNotEmpty ? emAndamento.first : _solicitacaoTourFake;

    if (solicitacaoParaAbrir == null) {
      // Nem solicitação real nem simulada disponível (ex.: nenhum material
      // cadastrado no sistema) — mantém o card fictício em destaque com o
      // texto orientando o usuário.
      _dialogVisualizarTourAberto = false;
      _dialogVisualizarTourEmTransicao = false;
      return;
    }

    showDialog<bool>(
      context: context,
      barrierDismissible: !_dialogVisualizarTourAberto,
      builder: (_) => _VisualizarSolicitacaoDialog(
        solicitacao: solicitacaoParaAbrir,
        tourKeyAdicionarMateriais: _tourKeyAdicionarMateriaisExistente,
        tourKeyComprado: _tourKeyComprado,
        tourKeyEstoque: _tourKeyEstoque,
      ),
    ).then((salvou) {
      if (mounted) _dialogVisualizarTourAberto = false;
      if (salvou == true && mounted) {
        context.read<SolicitacaoMaterialProvider>().carregar();
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Fecha o dialog de visualização aberto pelo tour, aguardando a animação
  /// de saída terminar antes de retornar.
  Future<void> _fecharDialogVisualizarTourSeAberto() async {
    if (!_dialogVisualizarTourAberto || _dialogVisualizarTourEmTransicao) return;
    _dialogVisualizarTourAberto = false;
    _dialogVisualizarTourEmTransicao = true;
    await Navigator.of(context, rootNavigator: true).maybePop();
    _dialogVisualizarTourEmTransicao = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// Registra no RoboHelperProvider as opções de ajuda contextual desta
  /// página. Chamado a cada build (barato — é só uma atribuição de lista)
  /// pra garantir que as opções sempre apontem para as keys corretas.
  void _registrarAjudaRobo() {
    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isCurrent) return;

    final helper = context.read<RoboHelperProvider>();
    final k = _criarSolicitacaoTourKeys;
    helper.registrarOpcoes('/solicitacoes-material', [
      RoboHelpOption(
        titulo: 'Como fazer uma solicitação',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyNovaSolicitacao,
            texto: 'Toque aqui para abrir o formulário de uma nova '
                'solicitação de material.',
            aoEntrar: () async {
              // Voltando pra este passo (botão "Anterior" vindo de dentro
              // do dialog), fecha tudo que o tour tiver aberto — senão o
              // botão fica escondido atrás do(s) dialog(s).
              await _fecharSeletorTourSeAberto();
              await _fecharDialogTourSeAberto();
            },
          ),
          RoboTourStop(
            key: () => k.numeroOS,
            texto: 'Número da OS (Ordem de Serviço) vinculada a essa '
                'solicitação — obrigatório.',
            aoEntrar: _abrirDialogTour,
          ),
          RoboTourStop(
            key: () => k.cliente,
            texto: 'Nome do cliente dessa OS — obrigatório.',
          ),
          RoboTourStop(
            key: () => k.dataNecessidade,
            texto: 'Data em que o material precisa estar disponível.',
          ),
          RoboTourStop(
            key: () => k.observacao,
            texto: 'Observação geral da solicitação (opcional).',
          ),
          RoboTourStop(
            key: () => k.adicionarMaterial,
            texto: 'Toque aqui para adicionar um material à solicitação — '
                'você pode adicionar quantos precisar.',
          ),
          RoboTourStop(
            key: () => k.material,
            texto: 'Toque para escolher o material desejado.',
            aoEntrar: _fecharSeletorTourSeAberto,
          ),
          RoboTourStop(
            key: () => k.seletorMaterial.filtros,
            texto: 'Use a busca por nome ou os filtros de identificador, '
                'medida, comprimento, largura e espessura para encontrar '
                'o material mais rápido.',
            aoEntrar: _abrirSeletorTour,
          ),
          RoboTourStop(
            key: () => k.quantidade,
            texto: 'Depois de escolher o material, informe a quantidade '
                'necessária.',
            aoEntrar: () async {
              // Volta pro "Nova Solicitação" com o material já selecionado
              // (o seletor fecha sozinho ao tocar num material — aqui só
              // garantimos que a flag/estado fiquem consistentes caso o
              // usuário tenha voltado de um passo anterior).
              await _fecharSeletorTourSeAberto();
              await _abrirDialogTour();
            },
          ),
          RoboTourStop(
            key: () => k.observacaoMaterial,
            texto: 'Observação específica desse material (opcional).',
          ),
          RoboTourStop(
            key: () => k.anexarImagem,
            texto: 'Toque aqui para anexar uma imagem de referência desse '
                'material.',
          ),
        ],
      ),
      RoboHelpOption(
        titulo: 'Como adicionar materiais a uma solicitação existente',
        paradas: [
          RoboTourStop(
            // IMPORTANTE: passar o GETTER (função), não o valor já resolvido.
            // _tourKeyCardSolicitacao decide entre a key real e a fictícia
            // com base em _tourExibirCardFicticio — e esse flag só é ligado
            // DENTRO do aoEntrar abaixo, de forma assíncrona (depois que
            // _garantirSolicitacaoTourExistente() roda). Se a key fosse
            // resolvida aqui (no momento em que esta lista de paradas é
            // construída em _registrarAjudaRobo(), com o flag ainda false),
            // o RoboTourStop ficaria preso apontando pra
            // _tourKeyCardSolicitacaoReal — que nunca chega a existir na
            // árvore quando cai no card fictício — e o highlight/dica nunca
            // apareceriam, mesmo com o card "DEMONSTRAÇÃO" visível na tela.
            key: () => _tourKeyCardSolicitacao,
            texto: 'Selecione uma solicitação para abrir e adicionar mais '
                'materiais a ela.',
            aoEntrar: () async {
              await _fecharDialogVisualizarTourSeAberto();
              // Esse tour só faz sentido na aba "Em Andamento" — se o
              // usuário estiver em "Finalizadas", troca automaticamente.
              if (_tabController.index != 0) {
                _tabController.animateTo(0);
              }
              // Sempre volta pra primeira página e pro topo da lista, pra
              // garantir que a primeira solicitação (a que vai receber o
              // highlight) esteja visível.
              setState(() => _paginaEmAndamento = 0);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollEmAndamento.hasClients) {
                  _scrollEmAndamento.jumpTo(0);
                }
              });
              // Se não existir nenhuma solicitação em andamento, cria uma
              // de verdade pra o tour poder abrir o dialog real no passo
              // seguinte (em vez de só escurecer a tela e não fazer nada).
              await _garantirSolicitacaoTourExistente();
              final temSolicitacaoEmAndamento = mounted &&
                  context
                      .read<SolicitacaoMaterialProvider>()
                      .solicitacoes
                      .any((s) => s.andamento != 'FINALIZADO');
              if (!temSolicitacaoEmAndamento && mounted) {
                setState(() => _tourExibirCardFicticio = true);
              }
            },
          ),
          RoboTourStop(
            key: () => _tourKeyAdicionarMateriaisExistente,
            texto: 'Toque aqui para adicionar mais materiais a esta '
                'solicitação.',
            aoEntrar: _abrirDialogVisualizarTour,
          ),
        ],
      ),
      RoboHelpOption(
        titulo: 'Como atender uma solicitação',
        paradas: [
          RoboTourStop(
            // Mesmo motivo do comentário na parada equivalente do tour
            // "Como adicionar materiais a uma solicitação existente": a key
            // precisa ser passada como GETTER, pois _tourKeyCardSolicitacao
            // só resolve pra o card fictício/real corretamente depois que
            // o aoEntrar abaixo roda.
            key: () => _tourKeyCardSolicitacao,
            texto: 'Selecione uma solicitação para abrir e atendê-la.',
            aoEntrar: () async {
              await _fecharDialogVisualizarTourSeAberto();
              // Esse tour só faz sentido na aba "Em Andamento" — se o
              // usuário estiver em "Finalizadas", troca automaticamente.
              if (_tabController.index != 0) {
                _tabController.animateTo(0);
              }
              // Sempre volta pra primeira página e pro topo da lista, pra
              // garantir que a primeira solicitação (a que vai receber o
              // highlight) esteja visível.
              setState(() => _paginaEmAndamento = 0);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollEmAndamento.hasClients) {
                  _scrollEmAndamento.jumpTo(0);
                }
              });
              // Se não existir nenhuma solicitação em andamento, cria uma
              // fictícia (só em memória) pra o tour poder abrir o dialog
              // real no passo seguinte.
              await _garantirSolicitacaoTourExistente();
              final temSolicitacaoEmAndamento = mounted &&
                  context
                      .read<SolicitacaoMaterialProvider>()
                      .solicitacoes
                      .any((s) => s.andamento != 'FINALIZADO');
              if (!temSolicitacaoEmAndamento && mounted) {
                setState(() => _tourExibirCardFicticio = true);
              }
            },
          ),
          RoboTourStop(
            key: () => _tourKeyComprado,
            texto: 'Assim que o material chegar, toque em "Comprado" para '
                'confirmar a compra — ou em "Estoque" se ele já estiver '
                'disponível no seu estoque.',
            aoEntrar: _abrirDialogVisualizarTour,
          ),
          RoboTourStop(
            key: () => _tourKeyAndamento,
            texto: 'Depois de marcar os materiais, use o menu de '
                'andamento da solicitação para indicar em que etapa ela '
                'está.',
            aoEntrar: () async {
              // Fecha o dialog de visualização (aberto na parada anterior)
              // para revelar a linha da solicitação na tabela por trás dele
              // — é nela que o botão de andamento em destaque vive.
              await _fecharDialogVisualizarTourSeAberto();
              // Aguarda o dialog terminar de fechar e a tabela assentar
              // antes de seguir, senão o highlight pode medir a posição do
              // botão still-transitioning.
              await Future<void>.delayed(const Duration(milliseconds: 120));
            },
          ),
          RoboTourStop(
            key: () => _tourKeyAndamento,
            texto: 'Toque para abrir as opções e escolha: mantenha em '
                '"EM ANDAMENTO" enquanto ainda está providenciando os '
                'materiais, ou mude para "EM NEGOCIAÇÃO" se estiver '
                'negociando prazo ou valores com o fornecedor.',
            aoEntrar: () async {
              // Espera o frame atual terminar de assentar (a linha da
              // tabela precisa estar remontada após o passo anterior
              // fechar o dialog) e só então chama showButtonMenu() —
              // chamar isso com o State ainda não montado faz
              // currentState vir null e o menu simplesmente não abre,
              // sem erro nenhum.
              await Future<void>.delayed(const Duration(milliseconds: 200));
              if (!mounted) return;
              await WidgetsBinding.instance.endOfFrame;
              if (!mounted) return;
              final estado = _tourKeyAndamento.currentState;
              if (estado == null) {
                // Ainda não montou — tenta mais uma vez após outro frame
                // em vez de desistir silenciosamente.
                await Future<void>.delayed(const Duration(milliseconds: 200));
                if (!mounted) return;
              }
              _tourKeyAndamento.currentState?.abrirMenuTour();
            },
          ),
        ],
      ),
      RoboHelpOption(
        titulo: 'Como orçar materiais solicitados',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyAgruparPorMateriaisSolicitados,
            texto: 'Aqui você pode agrupar os materiais solicitados por '
                'categoria, OS, necessidade ou status — escolha a forma '
                'que for mais fácil de visualizar.',
            aoEntrar: () async {
              // Esse tour só faz sentido na aba "Materiais Solicitados" —
              // troca automaticamente pra ela.
              if (_tabController.index != 2) {
                _tabController.animateTo(2);
              }
              // Aguarda a troca de aba (e a TabBarView) assentarem antes
              // de medir a posição do seletor "Agrupar por".
              await Future<void>.delayed(const Duration(milliseconds: 150));
            },
          ),
          RoboTourStop(
            key: () => _tourKeyPrimeiroMaterialSolicitado,
            texto: 'Selecione os materiais que deseja orçar marcando a '
                'caixinha ao lado de cada um.',
          ),
          RoboTourStop(
            key: () => _tourKeyOrcarSelecionadosMateriaisSolicitados,
            texto: 'Depois de selecionar os materiais desejados, toque '
                'aqui para gerar um orçamento com eles.',
          ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // ── Abertura pendente vinda de um encaminhamento no chat ────────────────
    // Ao tocar no card de uma solicitação (ou material de uma solicitação)
    // encaminhado no chat, o provider guarda o id aqui. A escuta principal
    // acontece via addListener em initState (mais confiável em produção —
    // ver comentário lá); este watch() é apenas uma rede de segurança
    // redundante para quando build() roda por outro motivo enquanto ainda
    // há um id pendente não consumido.
    context.watch<SolicitacaoMaterialProvider>().solicitacaoParaAbrirPendente;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tentarAbrirSolicitacaoPendente());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _registrarAjudaRobo();
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitações de Material',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gerenciar solicitações de materiais',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Criar uma nova solicitação de material',
                  child: KeyedSubtree(
                    key: _tourKeyNovaSolicitacao,
                    child: FilledButton.icon(
                      onPressed: () => _abrirFormSolicitacao(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nova Solicitação'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Ver histórico geral de solicitações',
                  child: OutlinedButton.icon(
                    onPressed: _abrirHistoricoSolicitacoes,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Histórico'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _aplicarFiltros,
                  icon: Icon(Icons.refresh, size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Banner de totais globais (independente de filtro) ────────────
            if (_totaisGlobaisCarregados && _totalItensGlobal > 0) ...[
              _BannerTotaisGlobais(
                totalItens:      _totalItensGlobal,
                totalResolvidos: _totalResolvidosGlobal,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por material, OS ou cliente',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final temFiltro = _buscaCtrl.text.isNotEmpty || _andamentoFiltro.isNotEmpty;
                    return IconButton.outlined(
                      tooltip: 'Limpar filtros',
                      icon: Icon(Icons.filter_alt_off,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: temFiltro
                          ? () {
                              _buscaCtrl.clear();
                              setState(() => _andamentoFiltro = '');
                              _aplicarFiltros();
                            }
                          : null,
                      style: IconButton.styleFrom(
                        side: BorderSide(color: Theme.of(context).colorScheme.outline),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.disabled)) {
                            return SystemMouseCursors.basic;
                          }
                          return SystemMouseCursors.click;
                        }),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Consumer<SolicitacaoMaterialProvider>(
              builder: (_, provider, __) {
                final emAndamento = provider.solicitacoes
                    .where((s) => s.andamento != 'FINALIZADO')
                    .toList()
                  ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
                final finalizadas = provider.solicitacoes
                    .where((s) => s.andamento == 'FINALIZADO')
                    .toList()
                  ..sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                        bottom: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppTheme.primary,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    indicatorColor: AppTheme.primary,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    tabs: [
                      Tab(
                        text: provider.carregando
                            ? 'Em Andamento'
                            : 'Em Andamento (${emAndamento.length})',
                      ),
                      Tab(
                        text: provider.carregando
                            ? 'Finalizadas'
                            : 'Finalizadas (${finalizadas.length})',
                      ),
                      Tab(
                        text: provider.carregando
                            ? 'Materiais Solicitados'
                            : 'Materiais Solicitados (${emAndamento.fold<int>(0, (soma, s) => soma + s.totalMateriais)})',
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: Consumer<SolicitacaoMaterialProvider>(
                builder: (_, provider, __) {
                  if (provider.carregando) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }
                  if (provider.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
                          const SizedBox(height: 12),
                          Text('Erro ao carregar solicitações',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(provider.erro!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _aplicarFiltros,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                                .copyWith(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (provider.solicitacoes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text('Nenhuma solicitação encontrada',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    );
                  }
                  final emAndamento = provider.solicitacoes
                      .where((s) => s.andamento != 'FINALIZADO')
                      .toList()
                    ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
                  final finalizadas = provider.solicitacoes
                      .where((s) => s.andamento == 'FINALIZADO')
                      .toList()
                    ..sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLista(emAndamento, 'Nenhuma solicitação em andamento', _Aba.emAndamento),
                      _buildLista(finalizadas, 'Nenhuma solicitação finalizada', _Aba.finalizadas),
                      MateriaisSolicitadosView(
                        solicitacoes: emAndamento,
                        tourKeyAgruparPor: _tourKeyAgruparPorMateriaisSolicitados,
                        tourKeyPrimeiroMaterial: _tourKeyPrimeiroMaterialSolicitado,
                        tourKeyOrcarSelecionados: _tourKeyOrcarSelecionadosMateriaisSolicitados,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista(
      List<SolicitacaoMaterialModel> lista, String mensagemVazia, _Aba aba) {
    // Card fictício do tour "Como adicionar materiais a uma solicitação
    // existente": só aparece na aba Em Andamento, e apenas quando não há
    // nenhuma solicitação real disponível para dar highlight.
    final mostrarCardFicticio =
        _tourExibirCardFicticio && aba == _Aba.emAndamento && lista.isEmpty;

    // Quando existe uma solicitação fake montada (_solicitacaoTourFake, veja
    // _garantirSolicitacaoTourExistente), mostramos ela na própria tabela —
    // igual a uma linha real — em vez do card genérico "Selecione uma
    // solicitação". Isso evita a solicitação "DEMONSTRAÇÃO" aparecer do nada
    // só no dialog do passo seguinte do tour: agora o passo 1 (lista) e o
    // passo 2 (dialog) mostram consistentemente a mesma solicitação fake.
    // O card genérico continua existindo como fallback para o caso raro em
    // que não há nenhum material cadastrado no sistema para montar o fake.
    if (mostrarCardFicticio && _solicitacaoTourFake != null) {
      return SingleChildScrollView(
        controller: _scrollEmAndamento,
        padding: const EdgeInsets.only(top: 16),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: _TabelaSolicitacoes(
            solicitacoes: [_solicitacaoTourFake!],
            onAbrir: (_) => _abrirDialogVisualizarTour(),
            tourKeyPrimeiraLinha: _tourKeyCardSolicitacaoFicticio,
            tourKeyAndamentoPrimeiraLinha: _tourKeyAndamento,
          ),
        ),
      );
    }

    if (lista.isEmpty) {
      return Center(
        child: mostrarCardFicticio
            ? _CardSolicitacaoFicticio(tourKey: _tourKeyCardSolicitacaoFicticio)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(mensagemVazia,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
      );
    }

    final paginaAtual = aba == _Aba.emAndamento ? _paginaEmAndamento : _paginaFinalizadas;
    final totalPaginas = (lista.length / _itensPorPagina).ceil();
    final paginaSegura = paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
    final inicio = paginaSegura * _itensPorPagina;
    final fim = (inicio + _itensPorPagina).clamp(0, lista.length);
    final paginados = lista.sublist(inicio, fim);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: aba == _Aba.emAndamento ? _scrollEmAndamento : null,
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: _TabelaSolicitacoes(
                solicitacoes: paginados,
                onAbrir: _abrirFormSolicitacao,
                tourKeyPrimeiraLinha:
                    aba == _Aba.emAndamento ? _tourKeyCardSolicitacaoReal : null,
                tourKeyAndamentoPrimeiraLinha:
                    aba == _Aba.emAndamento ? _tourKeyAndamento : null,
              ),
            ),
          ),
        ),
        if (totalPaginas > 1) ...[
          const SizedBox(height: 12),
          _BarraPaginacao(
            paginaAtual: paginaSegura,
            totalPaginas: totalPaginas,
            totalItens: lista.length,
            itensPorPagina: _itensPorPagina,
            onPaginaChanged: (p) => setState(() {
              if (aba == _Aba.emAndamento) {
                _paginaEmAndamento = p;
              } else {
                _paginaFinalizadas = p;
              }
            }),
          ),
        ],
      ],
    );
  }
}

enum _Aba { emAndamento, finalizadas }

class _BarraPaginacao extends StatelessWidget {
  final int paginaAtual;
  final int totalPaginas;
  final int totalItens;
  final int itensPorPagina;
  final void Function(int) onPaginaChanged;

  const _BarraPaginacao({
    required this.paginaAtual,
    required this.totalPaginas,
    required this.totalItens,
    required this.itensPorPagina,
    required this.onPaginaChanged,
  });

  List<int> _paginas() {
    if (totalPaginas <= 7) return List.generate(totalPaginas, (i) => i);
    final Set<int> vis = {0, totalPaginas - 1, paginaAtual};
    if (paginaAtual > 0) vis.add(paginaAtual - 1);
    if (paginaAtual < totalPaginas - 1) vis.add(paginaAtual + 1);
    final sorted = vis.toList()..sort();
    final List<int> result = [];
    for (int i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) result.add(-1);
      result.add(sorted[i]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final inicio = paginaAtual * itensPorPagina + 1;
    final fim = ((paginaAtual + 1) * itensPorPagina).clamp(0, totalItens);
    final paginas = _paginas();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Exibindo $inicio–$fim de $totalItens solicitações',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BotaoPagina(
                icon: Icons.chevron_left,
                tooltip: 'Página anterior',
                enabled: paginaAtual > 0,
                onTap: () => onPaginaChanged(paginaAtual - 1),
              ),
              const SizedBox(width: 4),
              for (final p in paginas) ...[
                if (p == -1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  )
                else
                  _BotaoNumeroPagina(
                    numero: p,
                    ativa: p == paginaAtual,
                    onTap: () => onPaginaChanged(p),
                  ),
                const SizedBox(width: 4),
              ],
              _BotaoPagina(
                icon: Icons.chevron_right,
                tooltip: 'Próxima página',
                enabled: paginaAtual < totalPaginas - 1,
                onTap: () => onPaginaChanged(paginaAtual + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotaoPagina extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _BotaoPagina({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? Theme.of(context).colorScheme.outlineVariant
                  : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _BotaoNumeroPagina extends StatelessWidget {
  final int numero;
  final bool ativa;
  final VoidCallback onTap;

  const _BotaoNumeroPagina({
    required this.numero,
    required this.ativa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: ativa ? null : onTap,
      mouseCursor: ativa ? SystemMouseCursors.basic : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: ativa ? AppTheme.primary : Colors.transparent,
          border: Border.all(
            color: ativa ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '${numero + 1}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: ativa ? FontWeight.w700 : FontWeight.w400,
            color: ativa ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

String _resolverUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = ApiClient.baseUrl.replaceAll(RegExp(r'/$'), '');
  if (base.isEmpty) {
    throw StateError(
      'ApiClient.baseUrl está vazio ao montar a URL da imagem "$url". '
      'Verifique se o .env foi carregado.',
    );
  }
  return '$base$url';
}

// ═══════════════════════════════════════════════════════════════════════════
// BANNER DE TOTAIS GLOBAIS
// ═══════════════════════════════════════════════════════════════════════════

class _BannerTotaisGlobais extends StatelessWidget {
  final int totalItens;
  final int totalResolvidos;

  const _BannerTotaisGlobais({
    required this.totalItens,
    required this.totalResolvidos,
  });

  @override
  Widget build(BuildContext context) {
    final pendentes  = totalItens - totalResolvidos;
    final todosOk    = pendentes == 0 && totalItens > 0;
    final progresso  = totalItens == 0 ? 0.0 : totalResolvidos / totalItens;
    final corPrimary = todosOk ? const Color(0xFF15803D) : AppTheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: corPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: corPrimary.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            todosOk ? Icons.check_circle_outline : Icons.pending_actions_outlined,
            size: 20,
            color: corPrimary,
          ),
          const SizedBox(width: 12),
          // Texto principal
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total de materiais: $totalItens',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: corPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                todosOk
                    ? 'Todos resolvidos ✓'
                    : '$totalResolvidos/$totalItens resolvidos  ·  $pendentes pendente${pendentes == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Barra de progresso
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progresso,
                backgroundColor: corPrimary.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(corPrimary),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Percentual
          Text(
            '${(progresso * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: corPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TABELA DE SOLICITAÇÕES
// ═══════════════════════════════════════════════════════════════════════════

class _TabelaSolicitacoes extends StatelessWidget {
  final List<SolicitacaoMaterialModel> solicitacoes;
  final void Function(SolicitacaoMaterialModel) onAbrir;
  /// Usado apenas pelo tour do robô assistente: dá highlight na primeira
  /// linha da tabela (a solicitação que o tour vai abrir em seguida).
  final GlobalKey? tourKeyPrimeiraLinha;
  /// Usado apenas pelo tour "Como atender uma solicitação": dá highlight
  /// no dropdown de andamento da primeira linha e permite abri-lo
  /// programaticamente.
  final GlobalKey<_StatusBadgeEditavelState>? tourKeyAndamentoPrimeiraLinha;

  const _TabelaSolicitacoes({
    required this.solicitacoes,
    required this.onAbrir,
    this.tourKeyPrimeiraLinha,
    this.tourKeyAndamentoPrimeiraLinha,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: const Row(
            children: [
              Expanded(flex: 1, child: _CabecalhoColuna(label: 'OS')),
              Expanded(flex: 2, child: _CabecalhoColuna(label: 'Cliente')),
              Expanded(flex: 1, child: _CabecalhoColuna(label: 'Solicitante')),
              Expanded(flex: 2, child: _CabecalhoColuna(label: 'Materiais')),
              Expanded(flex: 1, child: _CabecalhoColuna(label: 'Solicitação')),
              Expanded(flex: 1, child: _CabecalhoColuna(label: 'Necessidade')),
              Expanded(flex: 1, child: _CabecalhoColuna(label: 'Andamento')),
            ],
          ),
        ),
        Divider(height: 0, thickness: 0.8,
            color: Theme.of(context).colorScheme.outlineVariant),
        for (int i = 0; i < solicitacoes.length; i++) ...[
          if (i > 0)
            Divider(height: 0, thickness: 0.8,
                color: Theme.of(context).colorScheme.outlineVariant),
          _LinhaSolicitacao(
            solicitacao: solicitacoes[i],
            onAbrir: onAbrir,
            tourKey: i == 0 ? tourKeyPrimeiraLinha : null,
            tourKeyAndamento: i == 0 ? tourKeyAndamentoPrimeiraLinha : null,
          ),
        ],
      ],
    );
  }
}

class _CabecalhoColuna extends StatelessWidget {
  final String label;
  const _CabecalhoColuna({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, textAlign: TextAlign.center,
        style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

class _LinhaSolicitacao extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;
  final void Function(SolicitacaoMaterialModel) onAbrir;
  final GlobalKey? tourKey;
  /// Key aplicada ao badge/dropdown de andamento desta linha — usada apenas
  /// pelo tour "Como atender uma solicitação" para dar highlight nele e
  /// abrir o menu programaticamente.
  final GlobalKey<_StatusBadgeEditavelState>? tourKeyAndamento;

  const _LinhaSolicitacao({
    required this.solicitacao,
    required this.onAbrir,
    this.tourKey,
    this.tourKeyAndamento,
  });

  @override
  State<_LinhaSolicitacao> createState() => _LinhaSolicitacaoState();
}

class _LinhaSolicitacaoState extends State<_LinhaSolicitacao> {
  bool _hovered = false;

  String _formatarData(DateTime data) => DateFormat('dd/MM/yyyy').format(data);

  @override
  Widget build(BuildContext context) {
    final sol = widget.solicitacao;
    final bgColor = _hovered
        ? const Color(0x00ff9800).withValues(alpha: 0.10)
        : Theme.of(context).colorScheme.surface;

    return KeyedSubtree(
      // IMPORTANTE: nunca usar UniqueKey() aqui — isso gera uma key NOVA a
      // cada build(), fazendo o Flutter descartar e remontar o State desta
      // linha (perdendo _hovered e, em rebuilds concorrentes, o hit-test do
      // GestureDetector) toda vez que o provider notifica a lista. Usamos
      // ValueKey(sol.numeroOS + data) como identificador estável da linha
      // entre rebuilds (mesma solicitação = mesma key = mesmo Element).
      key: widget.tourKey ??
          ValueKey('${sol.numeroOS}_${sol.dataSolicitacao.millisecondsSinceEpoch}'),
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onAbrir(sol),
        child: ColoredBox(
          color: bgColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 1,
                  child: Text(sol.numeroOS, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 2,
                  child: Text(sol.nomeCliente, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 1,
                  child: Text(sol.usuarioNome, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${sol.totalMateriais} ${sol.totalMateriais == 1 ? 'material' : 'materiais'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      LinearProgressIndicator(
                        value: sol.totalMateriais == 0 ? 0 : sol.totalResolvidos / sol.totalMateriais,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          sol.todosComprados ? AppTheme.success : AppTheme.primary,
                        ),
                        minHeight: 4,
                      ),
                      const SizedBox(height: 2),
                      Text('${sol.totalResolvidos}/${sol.totalMateriais} resolvidos',
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(_formatarData(sol.dataSolicitacao),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  flex: 1,
                  child: Text(_formatarData(sol.dataNecessidade),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  flex: 1,
                  child: Center(
                    child: _StatusBadgeEditavel(
                      key: widget.tourKeyAndamento,
                      solicitacao: sol,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Card de demonstração exibido apenas durante o tour do robô assistente
/// "Como adicionar materiais a uma solicitação existente", quando não há
/// nenhuma solicitação real em andamento pra dar highlight. Não abre nada
/// ao tocar — apenas ilustra onde um card real apareceria.
class _CardSolicitacaoFicticio extends StatelessWidget {
  final GlobalKey tourKey;
  const _CardSolicitacaoFicticio({required this.tourKey});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: tourKey,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 420,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 40, color: AppTheme.primary),
              const SizedBox(height: 12),
              Text(
                'Selecione uma solicitação',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Toque em qualquer solicitação da lista para abri-la e '
                'adicionar mais materiais.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadgeEditavel extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;
  const _StatusBadgeEditavel({super.key, required this.solicitacao});

  @override
  State<_StatusBadgeEditavel> createState() => _StatusBadgeEditavelState();
}

class _StatusBadgeEditavelState extends State<_StatusBadgeEditavel> {
  bool _salvando = false;
  // Key interna do PopupMenuButton — usada apenas pelo tour do robô
  // assistente para localizar o BuildContext do botão e abrir o menu
  // programaticamente (simulando o clique do usuário), sem precisar de
  // showMenu manual com posição calculada à mão.
  final _popupKey = GlobalKey<PopupMenuButtonState<String>>();

  /// NOTA: este badge NÃO abre mais o dropdown de verdade durante o tour
  /// (via showButtonMenu()/showMenu()). O balão e o overlay escurecido do
  /// tour são promovidos para o Overlay RAIZ (ver
  /// `RoboHelperWidget._sincronizarOverlay`), e uma rota de PopupMenu
  /// aberta a partir do `context` deste botão pode acabar entrando num
  /// Overlay/Navigator "de baixo" — o menu fica logicamente aberto mas
  /// visualmente atrás do tour. Em vez disso, o passo do tour usa
  /// `RoboTourStop.opcoesMenu` para desenhar um mini-menu ILUSTRATIVO na
  /// mesma camada do robô (ver `_MiniMenuDica` em robo_helper_widget.dart)
  /// — visualmente idêntico ao dropdown real, sempre visível, sem
  /// depender de qual Navigator um showMenu() escolheria.
  ///
  /// Mantido como no-op (em vez de removido) para não quebrar chamadas
  /// antigas por engano; o tour não chama mais isto.
  void abrirMenuTour() {}

  ({Color bg, Color fg, String label}) _estilo(String status) {
    switch (status) {
      case 'EM_ANDAMENTO':
        return (
          bg: const Color(0xFFD97706).withValues(alpha: 0.1),
          fg: const Color(0xFFD97706),
          label: 'EM ANDAMENTO',
        );
      case 'EM_NEGOCIACAO':
        return (
          bg: const Color(0xFF2563EB).withValues(alpha: 0.1),
          fg: const Color(0xFF2563EB),
          label: 'EM NEGOCIAÇÃO',
        );
      case 'FINALIZADO':
        return (
          bg: const Color(0xFF15803D).withValues(alpha: 0.1),
          fg: const Color(0xFF15803D),
          label: 'FINALIZADO',
        );
      default:
        return (
          bg: Theme.of(context).colorScheme.surfaceContainerHighest,
          fg: Theme.of(context).colorScheme.onSurfaceVariant,
          label: status,
        );
    }
  }

  Future<void> _alterarStatus(String novoStatus) async {
    final sol = widget.solicitacao;
    if (novoStatus == sol.andamento) return;

    if (novoStatus == 'FINALIZADO' && !sol.todosComprados) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Não é possível finalizar: existem materiais ainda não marcados como comprados ou retirados do estoque.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.atualizar(sol.id, {'andamento': novoStatus});
    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Andamento atualizado'), backgroundColor: AppTheme.success),
      );
    } else {
      final mensagem = provider.erro ?? 'Erro ao atualizar andamento';
      provider.limparErro();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagem), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sol = widget.solicitacao;
    final estilo = _estilo(sol.andamento);

    if (_salvando) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
      );
    }

    return PopupMenuButton<String>(
      key: _popupKey,
      tooltip: 'Alterar andamento',
      offset: const Offset(0, 32),
      onSelected: _alterarStatus,
      itemBuilder: (ctx) => [
        _itemMenu(ctx, 'EM_ANDAMENTO', sol),
        _itemMenu(ctx, 'EM_NEGOCIACAO', sol),
        _itemMenu(ctx, 'FINALIZADO', sol),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: estilo.bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(estilo.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: estilo.fg)),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 14, color: estilo.fg),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _itemMenu(
      BuildContext ctx, String status, SolicitacaoMaterialModel sol) {
    final estilo = _estilo(status);
    final bloqueado = status == 'FINALIZADO' && !sol.todosComprados;
    final selecionado = status == sol.andamento;
    return PopupMenuItem<String>(
      value: status,
      enabled: !selecionado,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: estilo.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              estilo.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                color: bloqueado
                    ? Theme.of(ctx).colorScheme.outline
                    : Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
          ),
          if (bloqueado)
            Tooltip(
              message: 'Finalize apenas com todos os materiais comprados ou em estoque',
              child: Icon(Icons.lock_outline, size: 14,
                  color: Theme.of(ctx).colorScheme.outline),
            )
          else if (selecionado)
            Icon(Icons.check, size: 14, color: estilo.fg),
        ],
      ),
    );
  }
}

class _ItemMaterialCriacao {
  MaterialModel? material;
  final TextEditingController quantidadeCtrl = TextEditingController();
  final TextEditingController observacaoCtrl = TextEditingController();
  final FocusNode quantidadeFocus = FocusNode();
  File? imagem;
  /// Usada para localizar e scrollar até este item quando ele falha na
  /// validação ao clicar em "Criar".
  final GlobalKey cardKey = GlobalKey();

  void dispose() {
    quantidadeCtrl.dispose();
    observacaoCtrl.dispose();
    quantidadeFocus.dispose();
  }
}

/// GlobalKeys usadas pelo tour do robô assistente dentro do dialog
/// "Nova Solicitação".
class _CriarSolicitacaoTourKeys {
  final numeroOS          = GlobalKey();
  final cliente           = GlobalKey();
  final dataNecessidade   = GlobalKey();
  final observacao        = GlobalKey();
  final adicionarMaterial = GlobalKey();
  final material          = GlobalKey();
  final quantidade        = GlobalKey();
  final observacaoMaterial = GlobalKey();
  final anexarImagem      = GlobalKey();
  final seletorMaterial   = _SeletorMaterialTourKeys();
}

class _CriarSolicitacaoDialog extends StatefulWidget {
  final _CriarSolicitacaoTourKeys? tourKeys;
  /// Usado pelo tour do robô assistente: já nasce com um item de material
  /// adicionado, simulando o clique em "Adicionar Material", para poder
  /// destacar os campos do card sem esperar uma interação real do usuário.
  final bool abrirComItemInicial;

  const _CriarSolicitacaoDialog({
    this.tourKeys,
    this.abrirComItemInicial = false,
  });

  @override
  State<_CriarSolicitacaoDialog> createState() => _CriarSolicitacaoDialogState();
}

class _CriarSolicitacaoDialogState extends State<_CriarSolicitacaoDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog;

  final _numeroOSCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _observacaoCtrl = TextEditingController();
  DateTime _dataNecessidade = DateTime.now().add(const Duration(days: 1));

  final List<_ItemMaterialCriacao> _itens = [];

  // ── Verificação de OS em tempo real (debounce) ──────────────────────────
  Timer? _debounceOS;
  int _checagemOSSeq = 0;
  bool _verificandoOS = false;
  String? _erroOS;
  String? _ultimaOSVerificada;

  @override
  void initState() {
    super.initState();
    _numeroOSCtrl.addListener(_onNumeroOSChanged);
    if (widget.abrirComItemInicial) {
      // Simula o clique em "Adicionar Material" pro tour do robô assistente
      // já poder destacar os campos do card sem depender de uma interação
      // real do usuário.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _itens.isEmpty) _adicionarItem();
      });
    }
  }

  void _onNumeroOSChanged() {
    final texto = _numeroOSCtrl.text.trim();

    _debounceOS?.cancel();

    if (texto.isEmpty) {
      setState(() {
        _erroOS = null;
        _verificandoOS = false;
        _ultimaOSVerificada = null;
      });
      return;
    }

    if (texto == _ultimaOSVerificada) return;

    setState(() => _verificandoOS = true);

    _debounceOS = Timer(const Duration(milliseconds: 500), () {
      _verificarOS(texto);
    });
  }

  Future<void> _verificarOS(String numeroOS) async {
    final minhaChamada = ++_checagemOSSeq;
    try {
      final repo = context.read<SolicitacaoMaterialProvider>().repository;
      final resultado = await repo.verificarOSExiste(numeroOS);

      // Ignora resultado se o texto já mudou ou outra checagem mais nova
      // já foi disparada enquanto esta estava em andamento.
      if (!mounted || minhaChamada != _checagemOSSeq) return;
      if (_numeroOSCtrl.text.trim() != numeroOS) return;

      setState(() {
        _verificandoOS = false;
        _ultimaOSVerificada = numeroOS;
        _erroOS = resultado.existe
            ? 'Já existe uma solicitação para a OS "$numeroOS"'
                '${resultado.nomeCliente != null ? ' (${resultado.nomeCliente})' : ''}.'
            : null;
      });
    } catch (_) {
      // Falha de rede na checagem não deve travar o usuário — a validação
      // definitiva ainda ocorre no backend ao clicar em "Criar".
      if (!mounted || minhaChamada != _checagemOSSeq) return;
      setState(() => _verificandoOS = false);
    }
  }

  @override
  void dispose() {
    _debounceOS?.cancel();
    _numeroOSCtrl.removeListener(_onNumeroOSChanged);
    _numeroOSCtrl.dispose();
    _clienteCtrl.dispose();
    _observacaoCtrl.dispose();
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  void _adicionarItem() {
    setState(() => _itens.insert(0, _ItemMaterialCriacao()));
  }

  void _removerItem(int index) {
    if (_itens.length == 1) return;
    setState(() {
      _itens[index].dispose();
      _itens.removeAt(index);
    });
  }

  Future<void> _cadastrarMaterialGlobal(BuildContext context) async {
    final criou = await showDialog<bool>(
      context: context,
      builder: (_) => const MaterialFormDialog(),
    );
    if (criou == true && context.mounted) {
      await context.read<MaterialProvider>().carregarCategorias();
    }
  }

  /// Scrolla a lista de materiais até o card do [item] informado, usado
  /// para levar o usuário direto até o item que falhou na validação.
  void _scrollAteItem(_ItemMaterialCriacao item) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = item.cardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_erroOS != null) {
      setState(() => _erroDialog = _erroOS);
      return;
    }
    if (_verificandoOS) {
      // Ainda checando a OS: aguarda a checagem terminar antes de prosseguir.
      setState(() => _erroDialog = 'Aguarde, verificando o número da OS...');
      return;
    }

    // Valida se todos os itens têm material e quantidade
    for (int i = 0; i < _itens.length; i++) {
      final item = _itens[i];
      item.quantidadeCtrl.text = item.quantidadeCtrl.text.trim();
      item.observacaoCtrl.text = item.observacaoCtrl.text.trim();

      if (item.material == null) {
        setState(() => _erroDialog = 'Selecione o material do item ${i + 1}');
        _scrollAteItem(item);
        return;
      }
      if (item.quantidadeCtrl.text.isEmpty ||
          double.tryParse(item.quantidadeCtrl.text) == null) {
        setState(() => _erroDialog = 'Informe a quantidade do item ${i + 1}');
        _scrollAteItem(item);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          item.quantidadeFocus.requestFocus();
        });
        return;
      }
    }

    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    final dados = {
      'numeroOS': _numeroOSCtrl.text.trim(),
      'nomeCliente': _clienteCtrl.text.trim(),
      'dataNecessidade': _dataNecessidade.toIso8601String(),
      'observacao': _observacaoCtrl.text.trim().isEmpty ? null : _observacaoCtrl.text.trim(),
    };

    final itens = _itens.map((item) => {
      'materialId': item.material!.id,
      'quantidade': double.parse(item.quantidadeCtrl.text),
      'observacao': item.observacaoCtrl.text.trim().isEmpty ? null : item.observacaoCtrl.text.trim(),
    }).toList();

    final imagensPorIndice = <int, File>{};
    for (int i = 0; i < _itens.length; i++) {
      if (_itens[i].imagem != null) {
        imagensPorIndice[i] = _itens[i].imagem!;
      }
    }

    try {
      final provider = context.read<SolicitacaoMaterialProvider>();
      final ok = await provider.criarSemCarregar(dados, itens: itens, imagensPorIndice: imagensPorIndice);

      if (!mounted) return;

      if (ok) {
        // Primeiro sai do dialog, depois recarrega a lista
        Navigator.of(context, rootNavigator: true).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitação criada'),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        setState(() {
          _salvando = false;
          _erroDialog = provider.erroLocal ?? 'Erro ao criar solicitação. Verifique os dados e tente novamente.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erroDialog = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1040,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Text('Nova Solicitação', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            if (_erroDialog != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: _ErroBanner(
                  mensagem: _erroDialog!,
                  onDismiss: () => setState(() => _erroDialog = null),
                ),
              ),
            // Corpo em 2 seções: dados da solicitação (esquerda, largura
            // fixa) e materiais (direita, ocupa o espaço restante e rola
            // de forma independente) — evita o dialog crescer verticalmente
            // sem controle a cada material adicionado.
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    height: constraints.maxHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Seção esquerda: dados da solicitação ──────────
                        SizedBox(
                          width: 320,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  KeyedSubtree(
                                    key: widget.tourKeys?.numeroOS,
                                    child: TextFormField(
                                      controller: _numeroOSCtrl,
                                      autofocus: widget.tourKeys == null,
                                      decoration: InputDecoration(
                                        labelText: 'Número OS *',
                                        errorText: _erroOS,
                                        errorMaxLines: 3,
                                        suffixIcon: _verificandoOS
                                            ? const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                      strokeWidth: 2),
                                                ),
                                              )
                                            : (_erroOS == null &&
                                                    _ultimaOSVerificada != null &&
                                                    _ultimaOSVerificada ==
                                                        _numeroOSCtrl.text.trim())
                                                ? const Icon(Icons.check_circle,
                                                    color: AppTheme.success, size: 20)
                                                : null,
                                      ),
                                      textCapitalization: TextCapitalization.characters,
                                      inputFormatters: [_UpperCaseFormatter()],
                                      validator: (v) => v == null || v.trim().isEmpty
                                          ? 'Número OS é obrigatório'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  KeyedSubtree(
                                    key: widget.tourKeys?.cliente,
                                    child: TextFormField(
                                      controller: _clienteCtrl,
                                      decoration: const InputDecoration(labelText: 'Nome Cliente *'),
                                      textCapitalization: TextCapitalization.words,
                                      validator: (v) => v == null || v.trim().isEmpty
                                          ? 'Nome do cliente é obrigatório'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  KeyedSubtree(
                                    key: widget.tourKeys?.dataNecessidade,
                                    child: _DatePickerField(
                                      label: 'Data Necessidade *',
                                      value: _dataNecessidade,
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                                      onChanged: (d) => setState(() => _dataNecessidade = d),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  KeyedSubtree(
                                    key: widget.tourKeys?.observacao,
                                    child: TextFormField(
                                      controller: _observacaoCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Observação',
                                        alignLabelWithHint: true,
                                      ),
                                      maxLines: 4,
                                      textCapitalization: TextCapitalization.sentences,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        // ── Seção direita: materiais ───────────────────────
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                                child: Row(
                                  children: [
                                    Text('Materiais',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 8),
                                    if (_itens.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('${_itens.length}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.primary)),
                                      ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () => _cadastrarMaterialGlobal(context),
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Cadastrar material'),
                                      style: TextButton.styleFrom(
                                              foregroundColor: AppTheme.primary)
                                          .copyWith(
                                        mouseCursor: WidgetStateProperty.all(
                                            SystemMouseCursors.click),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Adicionar um novo material à solicitação',
                                      child: KeyedSubtree(
                                        key: widget.tourKeys?.adicionarMaterial,
                                        child: FilledButton.tonalIcon(
                                          onPressed: _adicionarItem,
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('Adicionar Material'),
                                          style: FilledButton.styleFrom().copyWith(
                                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: _itens.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.inventory_2_outlined,
                                                size: 40,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Nenhum material adicionado ainda',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            TextButton.icon(
                                              onPressed: _adicionarItem,
                                              icon: const Icon(Icons.add, size: 18),
                                              label: const Text('Adicionar Material'),
                                              style: TextButton.styleFrom(
                                                      foregroundColor: AppTheme.primary)
                                                  .copyWith(
                                                mouseCursor: WidgetStateProperty.all(
                                                    SystemMouseCursors.click),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                                        itemCount: _itens.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                                        itemBuilder: (context, index) {
                                          final item = _itens[index];
                                          // O tour só destaca os campos do
                                          // PRIMEIRO item — os demais (se o
                                          // usuário já tiver adicionado mais)
                                          // não recebem keys, evitando
                                          // GlobalKeys duplicadas na árvore.
                                          final ehPrimeiro = index == 0;
                                          return _ItemMaterialCard(
                                            key: item.cardKey,
                                            index: index,
                                            item: item,
                                            onRemover: _itens.length > 1
                                                ? () => _removerItem(index)
                                                : null,
                                            tourKeyMaterial:
                                                ehPrimeiro ? widget.tourKeys?.material : null,
                                            tourKeyQuantidade:
                                                ehPrimeiro ? widget.tourKeys?.quantidade : null,
                                            tourKeyObservacao: ehPrimeiro
                                                ? widget.tourKeys?.observacaoMaterial
                                                : null,
                                            tourKeyAnexarImagem: ehPrimeiro
                                                ? widget.tourKeys?.anexarImagem
                                                : null,
                                            seletorTourKeys:
                                                ehPrimeiro ? widget.tourKeys?.seletorMaterial : null,
                                            abrirSeletorAutomaticamente: false,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Cancelar e fechar sem salvar',
                    child: TextButton(
                      onPressed: _salvando ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Criar a solicitação de material',
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                      child: _salvando
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Criar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemMaterialCard extends StatelessWidget {
  final int index;
  final _ItemMaterialCriacao item;
  final VoidCallback? onRemover;
  /// Preenchidas só pelo tour do robô assistente, para destacar o campo
  /// "Material" do item e as keys usadas dentro do dialog de seleção.
  final GlobalKey? tourKeyMaterial;
  final GlobalKey? tourKeyQuantidade;
  final GlobalKey? tourKeyObservacao;
  final GlobalKey? tourKeyAnexarImagem;
  final _SeletorMaterialTourKeys? seletorTourKeys;
  final bool abrirSeletorAutomaticamente;

  const _ItemMaterialCard({
    super.key,
    required this.index,
    required this.item,
    this.onRemover,
    this.tourKeyMaterial,
    this.tourKeyQuantidade,
    this.tourKeyObservacao,
    this.tourKeyAnexarImagem,
    this.seletorTourKeys,
    this.abrirSeletorAutomaticamente = false,
  });

  Future<void> _selecionarMaterial(BuildContext context) async {
    final material = await showDialog<MaterialModel>(
      context: context,
      builder: (_) => _SeletorMaterialDialog(
        tourKeys: seletorTourKeys,
        abrirTodosAutomaticamente: abrirSeletorAutomaticamente,
      ),
    );
    if (material != null) {
      item.material = material;
      (context as Element).markNeedsBuild();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        item.quantidadeFocus.requestFocus();
        item.quantidadeCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: item.quantidadeCtrl.text.length,
        );
      });
    }
  }

  Future<void> _selecionarImagem(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      if (await file.exists()) {
        item.imagem = file;
        (context as Element).markNeedsBuild();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Item ${index + 1}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                ),
                const Spacer(),
                if (onRemover != null)
                  IconButton(
                    onPressed: onRemover,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remover item',
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: KeyedSubtree(
                    key: tourKeyMaterial,
                    child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                    onTap: () => _selecionarMaterial(context),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Material *',
                        suffixIcon: item.material != null
                            ? const Icon(Icons.check_circle, color: AppTheme.success, size: 20)
                            : const Icon(Icons.arrow_drop_down),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Builder(builder: (context) {
                            final m = item.material;
                            final corTexto = m != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.onSurfaceVariant;
                            if (m == null) {
                              return Text(
                                'Selecionar material',
                                style: TextStyle(fontSize: 14, color: corTexto),
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                            final medidaFmt = formatarMedidaOuDimensoes(
                              medida:      m.medida,
                              largura:     m.largura,
                              comprimento: m.comprimento,
                            );
                            final infoAoLado = [
                              if (m.identificador != null && m.identificador!.isNotEmpty) m.identificador!,
                              medidaFmt,
                              formatarEspessuraComSufixo(m.espessura),
                            ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
                            return Text.rich(
                              TextSpan(
                                style: TextStyle(fontSize: 14, color: corTexto),
                                children: [
                                  TextSpan(text: m.nome),
                                  if (infoAoLado.isNotEmpty)
                                    TextSpan(text: ' · $infoAoLado'),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            );
                          }),
                          if (item.material != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Estoque: ${formatarQuantidade(item.material!.quantidade)} ${formatarUnidadeExibicao(item.material!.unidade)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ),
                  ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                    key: tourKeyQuantidade,
                    child: TextFormField(
                      controller: item.quantidadeCtrl,
                      focusNode: item.quantidadeFocus,
                      decoration: const InputDecoration(labelText: 'Quantidade *'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: tourKeyObservacao,
              child: TextFormField(
                controller: item.observacaoCtrl,
                decoration: const InputDecoration(labelText: 'Observação'),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.imagem != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(item.imagem!, width: 60, height: 60, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Imagem anexada',
                        style: TextStyle(fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      item.imagem = null;
                      (context as Element).markNeedsBuild();
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Remover'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.error).copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ] else
                  Expanded(
                    child: KeyedSubtree(
                      key: tourKeyAnexarImagem,
                      child: OutlinedButton.icon(
                        onPressed: () => _selecionarImagem(context),
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                        label: const Text('Anexar imagem'),
                        style: OutlinedButton.styleFrom().copyWith(
                          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG: VISUALIZAR/EDITAR SOLICITAÇÃO
// ═══════════════════════════════════════════════════════════════════════════

class _VisualizarSolicitacaoDialog extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;
  /// Usado apenas pelo tour do robô assistente para dar highlight no botão
  /// "Adicionar Materiais" depois que este dialog abre.
  final GlobalKey? tourKeyAdicionarMateriais;
  /// Usadas apenas pelo tour "Como atender uma solicitação" para dar
  /// highlight nos botões COMPRADO/ESTOQUE do primeiro material da lista.
  final GlobalKey? tourKeyComprado;
  final GlobalKey? tourKeyEstoque;

  const _VisualizarSolicitacaoDialog({
    required this.solicitacao,
    this.tourKeyAdicionarMateriais,
    this.tourKeyComprado,
    this.tourKeyEstoque,
  });

  @override
  State<_VisualizarSolicitacaoDialog> createState() =>
      _VisualizarSolicitacaoDialogState();
}

class _VisualizarSolicitacaoDialogState extends State<_VisualizarSolicitacaoDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _salvando = false;
  bool _houveMudanca = false;
  String? _erroDialog;
  late SolicitacaoMaterialModel _solicitacaoAtual;

  // Marcações de status (comprado/pendente/estoque) feitas na tela mas ainda
  // não persistidas. Chave: "item:<id>" ou "adicional:<id>" — Valor: novo
  // status desejado ('PENDENTE' | 'COMPRADO' | 'ESTOQUE').
  final Map<String, String> _statusPendentes = {};

  bool get _temAlteracoesNaoSalvas => _statusPendentes.isNotEmpty;

  // Edição do cabeçalho (ADMIN ou criador da solicitação)
  late final TextEditingController _numeroOSCtrl;
  late final TextEditingController _clienteCtrl;
  late final TextEditingController _observacaoCtrl;
  late DateTime _dataNecessidade;
  late String _andamento;

  MaterialProvider? _materialProviderRef;
  bool _recarregandoPorMaterial = false;

  @override
  void initState() {
    super.initState();
    _solicitacaoAtual = widget.solicitacao;
    _tabCtrl = TabController(length: 3, vsync: this);
    
    _numeroOSCtrl = TextEditingController(text: _solicitacaoAtual.numeroOS);
    _clienteCtrl = TextEditingController(text: _solicitacaoAtual.nomeCliente);
    _observacaoCtrl = TextEditingController(text: _solicitacaoAtual.observacao ?? '');
    _dataNecessidade = _solicitacaoAtual.dataNecessidade;
    _andamento = _solicitacaoAtual.andamento;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Solicitação simulada do tour (id negativo) não existe no backend —
      // não faz sentido buscar logs dela.
      if (_solicitacaoAtual.id >= 0) {
        context.read<SolicitacaoMaterialProvider>().carregarLogs(_solicitacaoAtual.id);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Escuta o MaterialProvider: se um material desta solicitação for
    // editado em outra tela (ex.: Estoque) enquanto este dialog já está
    // aberto, o nome/dados do material exibidos aqui ficariam desatualizados
    // até fechar e reabrir. Recarregando a solicitação a cada notificação do
    // MaterialProvider, os dados do material ficam em dia automaticamente.
    final novoProvider = context.read<MaterialProvider>();
    if (!identical(_materialProviderRef, novoProvider)) {
      _materialProviderRef?.removeListener(_onMateriaisAlterados);
      _materialProviderRef = novoProvider;
      _materialProviderRef!.addListener(_onMateriaisAlterados);
    }
  }

  void _onMateriaisAlterados() {
    if (!mounted || _recarregandoPorMaterial || _solicitacaoAtual.id < 0) return;
    _recarregandoPorMaterial = true;
    _recarregarSolicitacao().whenComplete(() => _recarregandoPorMaterial = false);
  }

  @override
  void dispose() {
    _materialProviderRef?.removeListener(_onMateriaisAlterados);
    _tabCtrl.dispose();
    _numeroOSCtrl.dispose();
    _clienteCtrl.dispose();
    _observacaoCtrl.dispose();
    super.dispose();
  }

  bool get _ehAdmin {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    return usuario?.role.trim().toUpperCase() == 'ADMIN' || usuario?.role.trim().toUpperCase() == 'GERENTE';
  }

  // Cabeçalho (aba Dados) pode ser editado pelo ADMIN ou pelo criador da solicitação.
  bool get _podeEditarCabecalho {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    if (usuario == null) return false;
    final ehAdmin = usuario.role.trim().toUpperCase() == 'ADMIN' || usuario.role.trim().toUpperCase() == 'GERENTE';
    final ehCriador = usuario.id.toString() == _solicitacaoAtual.usuarioId.toString();
    return ehAdmin || ehCriador;
  }

  bool get _podeAdicionarMateriais {
    // Solicitação simulada pelo tour (nunca existe no backend) — sempre
    // permite mostrar/destacar o botão, já que nenhuma ação real de
    // "adicionar materiais" chegará a ser persistida a partir dela.
    if (_solicitacaoAtual.id < 0) return true;
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    if (usuario == null) return false;
    final ehAdmin = usuario.role.trim().toUpperCase() == 'ADMIN' || usuario.role.trim().toUpperCase() == 'GERENTE';
    final ehCriador = usuario.id.toString() == _solicitacaoAtual.usuarioId.toString();
    return ehAdmin || ehCriador;
  }

  // Exclusão da solicitação: ADMIN ou o próprio criador podem excluir.
  bool get _podeExcluir {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    if (usuario == null) return false;
    final ehAdmin = usuario.role.trim().toUpperCase() == 'ADMIN' || usuario.role.trim().toUpperCase() == 'GERENTE';
    final ehCriador = usuario.id.toString() == _solicitacaoAtual.usuarioId.toString();
    return ehAdmin || ehCriador;
  }

  // Registra/desfaz uma alteração local de status (não chama a API ainda).
  // statusOriginal/novoStatus: 'PENDENTE' | 'COMPRADO' | 'ESTOQUE'.
  void _alterarStatusLocal(String tipo, int id, String statusOriginal, String novoStatus) {
    final chave = '$tipo:$id';
    setState(() {
      if (novoStatus == statusOriginal) {
        _statusPendentes.remove(chave);
      } else {
        _statusPendentes[chave] = novoStatus;
      }
    });
  }

  // Persiste todas as marcações pendentes no backend. Retorna true se tudo ok.
  Future<bool> _persistirComprasPendentes() async {
    final provider = context.read<SolicitacaoMaterialProvider>();
    final pendentes = Map<String, String>.from(_statusPendentes);

    for (final entry in pendentes.entries) {
      final partes = entry.key.split(':');
      final tipo = partes[0];
      final id = int.parse(partes[1]);
      final status = entry.value;
      try {
        if (tipo == 'item') {
          if (status == 'ESTOQUE') {
            await provider.marcarItemEstoque(id, estoque: true);
          } else {
            await provider.marcarItemComprado(id, comprado: status == 'COMPRADO');
          }
        } else {
          if (status == 'ESTOQUE') {
            await provider.marcarAdicionalEstoque(id, estoque: true);
          } else {
            await provider.marcarAdicionalComprado(id, comprado: status == 'COMPRADO');
          }
        }
      } catch (e) {
        if (mounted) {
          final mensagem = 'Erro ao salvar materiais: ${e.toString().replaceFirst('Exception: ', '')}';
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Erro ao salvar'),
              content: Text(mensagem),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom().copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return false;
      }
    }

    if (mounted) {
      setState(() {
        _statusPendentes.clear();
        _houveMudanca = true;
      });
    }
    await _recarregarSolicitacao();
    // Sincroniza _andamento local com o valor retornado pelo backend
    // (pode ter sido auto-finalizado se todos os itens foram marcados como comprados/estoque)
    if (mounted) {
      setState(() => _andamento = _solicitacaoAtual.andamento);
    }
    return true;
  }

  // Ponto único de fechamento do diálogo (X, "Fechar", ESC, clique fora).
  // Se houver marcações não salvas, pede confirmação antes de fechar.
  Future<void> _tentarFechar() async {
    if (!_temAlteracoesNaoSalvas) {
      Navigator.pop(context, _houveMudanca ? true : null);
      return;
    }

    final decisao = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterações não salvas'),
        content: const Text(
          'Você marcou materiais como comprado, estoque ou pendente, mas ainda não salvou. '
          'Deseja salvar essas alterações antes de fechar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'salvar'),
            style: FilledButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (!mounted || decisao == null) return;

    if (decisao == 'salvar') {
      setState(() => _salvando = true);
      final ok = await _persistirComprasPendentes();
      if (!mounted) return;
      setState(() => _salvando = false);
      if (ok) {
        Navigator.pop(context, true);
      }
      // Se falhar, o diálogo permanece aberto com o erro exibido.
    } else if (decisao == 'cancelar') {
      setState(() => _statusPendentes.clear());
      Navigator.pop(context, _houveMudanca ? true : null);
    }
  }

  Future<void> _recarregarSolicitacao() async {
    try {
      final provider = context.read<SolicitacaoMaterialProvider>();
      final atualizada = await provider.repository.buscarPorId(_solicitacaoAtual.id);
      if (mounted) {
        setState(() {
          _solicitacaoAtual = atualizada;
          _houveMudanca = true;
        });
      }
    } catch (e) {
      debugPrint('Erro ao recarregar solicitação: $e');
    }
  }

  Future<void> _salvarCabecalho() async {
    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    // Primeiro persiste marcações de comprado/pendente (qualquer usuário com permissão de marcar).
    if (_temAlteracoesNaoSalvas) {
      final ok = await _persistirComprasPendentes();
      if (!ok || !mounted) {
        if (mounted) setState(() => _salvando = false);
        return;
      }
    }

    // Cabeçalho (Dados) só pode ser alterado por ADMIN ou pelo criador da solicitação.
    if (!_podeEditarCabecalho) {
      if (!mounted) return;
      setState(() => _salvando = false);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Alterações salvas'), backgroundColor: AppTheme.success),
      );
      return;
    }

    // Valida se pode finalizar
    if (_andamento == 'FINALIZADO' && !_solicitacaoAtual.todosComprados) {
      setState(() => _erroDialog = 
        'Não é possível finalizar: existem materiais ainda não marcados como comprados ou retirados do estoque.');
      setState(() => _salvando = false);
      return;
    }

    final dados = {
      'numeroOS': _numeroOSCtrl.text.trim(),
      'nomeCliente': _clienteCtrl.text.trim(),
      'dataNecessidade': _dataNecessidade.toIso8601String(),
      'andamento': _andamento,
      'observacao': _observacaoCtrl.text.trim().isEmpty ? null : _observacaoCtrl.text.trim(),
    };

    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.atualizar(_solicitacaoAtual.id, dados);

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitação atualizada'), backgroundColor: AppTheme.success),
      );
    } else {
      // Captura a mensagem antes de limpar o erro no provider para evitar
      // que o notifyListeners() do provider exiba o erro na página por trás
      // do dialog (Consumer na SolicitacoesMaterialPage).
      final mensagem = provider.erro ?? 'Erro ao salvar';
      provider.limparErro();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Não foi possível salvar'),
          content: Text(mensagem),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _adicionarMateriais() async {
    final salvou = await showDialog<bool>(
      context: context,
      builder: (_) => _AdicionarMateriaisDialog(solicitacao: _solicitacaoAtual),
    );
    if (salvou == true && mounted) {
      setState(() => _houveMudanca = true);
      await _recarregarSolicitacao();
    }
  }

  Future<void> _excluirSolicitacao() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Solicitação'),
        content: Text(
          'Tem certeza que deseja excluir a solicitação OS ${_solicitacaoAtual.numeroOS}? Esta ação não pode ser desfeita.',
        ),
        actions: [
          Tooltip(
            message: 'Cancelar e manter a solicitação',
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: const Text('Cancelar'),
            ),
          ),
          Tooltip(
            message: 'Excluir permanentemente esta solicitação',
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: const Text('Excluir'),
            ),
          ),
        ],
      ),
    );

    if (confirma != true || !mounted) return;

    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.excluir(_solicitacaoAtual.id);

    if (!mounted) return;

    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitação excluída'), backgroundColor: AppTheme.success),
      );
    } else {
      final mensagemErro = provider.erro ?? 'Erro ao excluir';
      provider.limparErro();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erro ao excluir'),
          content: Text(mensagemErro),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _reabrirSolicitacao() async {
    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.atualizar(_solicitacaoAtual.id, {'andamento': 'EM_ANDAMENTO'});
    if (!mounted) return;
    if (ok) {
      await _recarregarSolicitacao();
      setState(() => _andamento = 'EM_ANDAMENTO');
    } else {
      final mensagem = provider.erro ?? 'Erro ao reabrir solicitação';
      provider.limparErro();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erro'),
          content: Text(mensagem),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  void _mostrarErro(String titulo, Object e) {
    if (!mounted) return;
    final mensagem = e.toString().replaceFirst('Exception: ', '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _encaminharSolicitacao() async {
    final dados = {
      'solicitacaoId': _solicitacaoAtual.id,
      'numeroOS': _solicitacaoAtual.numeroOS,
      'nomeCliente': _solicitacaoAtual.nomeCliente,
      'dataNecessidade': _solicitacaoAtual.dataNecessidade.toIso8601String(),
    };
    final enviado = await encaminharParaChat(context, tipo: 'solicitacao', dados: dados);
    if (!mounted || !enviado) return;
    // O mini chat flutuante já foi acionado (expandido, com a conversa do
    // destinatário aberta) por encaminharParaChat — aqui só fechamos esta
    // solicitação para o usuário já cair direto na conversa.
    Navigator.of(context).pop(_houveMudanca ? true : null);
  }

  Future<void> _encaminharMaterial(String tipo, int id) async {
    final item = tipo == 'item'
        ? _solicitacaoAtual.itens.firstWhere((i) => i.id == id)
        : null;
    final adicional = tipo == 'adicional'
        ? _solicitacaoAtual.adicionais.firstWhere((a) => a.id == id)
        : null;

    final dados = {
      'solicitacaoId': _solicitacaoAtual.id,
      'numeroOS': _solicitacaoAtual.numeroOS,
      'materialNome': item?.materialNome ?? adicional!.materialNome,
      'quantidade': item?.quantidade ?? adicional!.quantidade,
      'unidade': item?.materialUnidade ?? adicional?.materialUnidade,
      'identificador': item?.materialIdentificador ?? adicional?.materialIdentificador,
      'medida': item?.materialMedida ?? adicional?.materialMedida,
      'espessura': item?.materialEspessura ?? adicional?.materialEspessura,
      'largura': item?.materialLargura ?? adicional?.materialLargura,
      'comprimento': item?.materialComprimento ?? adicional?.materialComprimento,
    };

    final enviado = await encaminharParaChat(context, tipo: 'material', dados: dados);
    if (!mounted || !enviado) return;
    Navigator.of(context).pop(_houveMudanca ? true : null);
  }

  Future<void> _editarMaterial(
    String tipo,
    int id,
    double quantidadeAtual,
    String? observacaoAtual,
  ) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditarMaterialDialog(
        quantidadeAtual: quantidadeAtual,
        observacaoAtual: observacaoAtual,
      ),
    );
    if (resultado == null || !mounted) return;

    final provider = context.read<SolicitacaoMaterialProvider>();
    try {
      if (tipo == 'item') {
        await provider.atualizarItem(
          id,
          quantidade: resultado['quantidade'] as double,
          observacao: resultado['observacao'] as String?,
        );
      } else {
        await provider.atualizarAdicional(
          id,
          quantidade: resultado['quantidade'] as double,
          observacao: resultado['observacao'] as String?,
        );
      }
      if (mounted) setState(() => _houveMudanca = true);
      await _recarregarSolicitacao();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitação atualizada'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao editar material', e);
    }
  }

  Future<void> _excluirMaterial(String tipo, int id, String materialNome) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Material'),
        content: Text('Tem certeza que deseja remover "$materialNome" desta solicitação?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    final provider = context.read<SolicitacaoMaterialProvider>();
    try {
      if (tipo == 'item') {
        await provider.excluirItem(id);
      } else {
        await provider.excluirAdicional(id);
      }
      if (mounted) setState(() => _houveMudanca = true);
      await _recarregarSolicitacao();
    } catch (e) {
      _mostrarErro('Erro ao remover material', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_temAlteracoesNaoSalvas,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _tentarFechar();
        }
      },
      child: Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Solicitação OS ${_solicitacaoAtual.numeroOS}',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          'Cliente: ${_solicitacaoAtual.nomeCliente}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _encaminharSolicitacao,
                    icon: const Icon(Icons.ios_share_outlined, size: 20),
                    tooltip: 'Enviar para chat',
                    style: IconButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _tentarFechar,
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ],
              ),
            ),
            // Abas
            TabBar(
              controller: _tabCtrl,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              indicatorColor: AppTheme.primary,
              tabs: const [
                Tab(text: 'Materiais'),
                Tab(text: 'Dados'),
                Tab(text: 'Histórico'),
              ],
            ),
            const Divider(height: 0),
            Flexible(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // Aba Materiais
                  _AbaMateriaisSolicitacao(
                    solicitacao: _solicitacaoAtual,
                    statusPendentes: _statusPendentes,
                    onAlterarStatus: _alterarStatusLocal,
                    onReabrirSolicitacao: _ehAdmin ? _reabrirSolicitacao : null,
                    podeEditarMaterial: _podeEditarCabecalho,
                    onEditarMaterial: _editarMaterial,
                    onExcluirMaterial: _excluirMaterial,
                    onEncaminharMaterial: _encaminharMaterial,
                    tourKeyComprado: widget.tourKeyComprado,
                    tourKeyEstoque: widget.tourKeyEstoque,
                  ),
                  // Aba Dados
                  _AbaDadosSolicitacao(
                    solicitacao: _solicitacaoAtual,
                    numeroOSCtrl: _numeroOSCtrl,
                    clienteCtrl: _clienteCtrl,
                    observacaoCtrl: _observacaoCtrl,
                    dataNecessidade: _dataNecessidade,
                    andamento: _andamento,
                    onDataNecessidadeChanged: (d) => setState(() => _dataNecessidade = d),
                    onAndamentoChanged: (a) => setState(() => _andamento = a),
                    ehAdmin: _podeEditarCabecalho,
                    erroDialog: _erroDialog,
                    onDismissErro: () => setState(() => _erroDialog = null),
                  ),
                  // Aba Histórico
                  _AbaHistorico(solicitacaoId: _solicitacaoAtual.id),
                ],
              ),
            ),
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (_podeAdicionarMateriais)
                  Tooltip(
                    message: 'Adicionar mais materiais a esta solicitação',
                    child: KeyedSubtree(
                      key: widget.tourKeyAdicionarMateriais ?? UniqueKey(),
                      child: FilledButton.icon(
                        onPressed: _adicionarMateriais,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Adicionar Materiais'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                        ).copyWith(
                          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_podeExcluir)
                    Tooltip(
                      message: 'Excluir esta solicitação',
                      child: OutlinedButton.icon(
                        onPressed: _excluirSolicitacao,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Excluir'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                        ).copyWith(
                          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Tooltip(
                    message: 'Fechar esta solicitação',
                    child: TextButton(
                      onPressed: _tentarFechar,
                      style: TextButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                      child: const Text('Fechar'),
                    ),
                  ),
                  if (_podeEditarCabecalho || _temAlteracoesNaoSalvas) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Salvar as alterações desta solicitação',
                      child: FilledButton(
                        onPressed: _salvando ? null : _salvarCabecalho,
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
                          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                        child: _salvando
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Salvar'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Aba Materiais ────────────────────────────────────────────────────────────

class _AbaMateriaisSolicitacao extends StatelessWidget {
  final SolicitacaoMaterialModel solicitacao;
  // Chave: "item:<id>" ou "adicional:<id>" — Valor: status pendente
  // ('PENDENTE' | 'COMPRADO' | 'ESTOQUE') ainda não persistido.
  final Map<String, String> statusPendentes;
  final void Function(String tipo, int id, String statusOriginal, String novoStatus) onAlterarStatus;
  final VoidCallback? onReabrirSolicitacao;
  final bool podeEditarMaterial;
  final Future<void> Function(String tipo, int id, double quantidadeAtual, String? observacaoAtual) onEditarMaterial;
  final Future<void> Function(String tipo, int id, String materialNome) onExcluirMaterial;
  final Future<void> Function(String tipo, int id) onEncaminharMaterial;
  /// Usadas apenas pelo tour "Como atender uma solicitação" para dar
  /// highlight nos botões COMPRADO/ESTOQUE do primeiro material listado.
  final GlobalKey? tourKeyComprado;
  final GlobalKey? tourKeyEstoque;

  const _AbaMateriaisSolicitacao({
    required this.solicitacao,
    required this.statusPendentes,
    required this.onAlterarStatus,
    this.onReabrirSolicitacao,
    required this.podeEditarMaterial,
    required this.onEditarMaterial,
    required this.onExcluirMaterial,
    required this.onEncaminharMaterial,
    this.tourKeyComprado,
    this.tourKeyEstoque,
  });

  @override
  Widget build(BuildContext context) {
    final itensOriginais = solicitacao.itens;
    final adicionais = solicitacao.adicionais;

    if (itensOriginais.isEmpty && adicionais.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('Nenhum material solicitado',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (itensOriginais.isNotEmpty) ...[
          Text('Materiais Originais',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...itensOriginais.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final ehPrimeiroDaLista = index == 0;
            final chave = 'item:${item.id}';
            final pendente = statusPendentes.containsKey(chave);
            final statusEfetivo = statusPendentes[chave] ?? item.statusCompra;
            return _MaterialCard(
              tourKeyComprado: ehPrimeiroDaLista ? tourKeyComprado : null,
              tourKeyEstoque: ehPrimeiroDaLista ? tourKeyEstoque : null,
              tipo: 'item',
              id: item.id,
              materialNome: item.materialNome,
              materialUnidade: item.materialUnidade,
              materialIdentificador: item.materialIdentificador,
              materialMedida: item.materialMedida,
              materialEspessura: item.materialEspessura,
              materialLargura: item.materialLargura,
              materialComprimento: item.materialComprimento,
              materialCategoria: item.materialCategoria,
              materialEstoque: item.materialQuantidadeEstoque,
              quantidade: item.quantidade,
              observacao: item.observacao,
              imagemUrl: item.imagemUrl,
              status: statusEfetivo,
              pendente: pendente,
              compradoEm: item.compradoEm,
              compradoPorNome: item.compradoPorNome,
              estoqueEm: item.estoqueEm,
              estoquePorNome: item.estoquePorNome,
              criadoEm: item.criadoEm,
              editadoEm: item.editadoEm,
              editadoPorNome: item.editadoPorNome,
              andamento: solicitacao.andamento,
              onSelecionarStatus: (novoStatus) =>
                  onAlterarStatus('item', item.id, item.statusCompra, novoStatus),
              onReabrirSolicitacao: onReabrirSolicitacao,
              podeEditar: podeEditarMaterial,
              onEditar: () => onEditarMaterial('item', item.id, item.quantidade, item.observacao),
              onExcluir: () => onExcluirMaterial('item', item.id, item.materialNome),
              onEncaminhar: () => onEncaminharMaterial('item', item.id),
            );
          }),
        ],
        if (adicionais.isNotEmpty) ...[
          if (itensOriginais.isNotEmpty) const SizedBox(height: 24),
          Text('Materiais Adicionais',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...adicionais.asMap().entries.map((entry) {
            final index = entry.key;
            final ad = entry.value;
            // Só é o "primeiro material da lista" se não houver nenhum
            // item original antes dele (senão o highlight já foi aplicado
            // ao primeiro item original acima).
            final ehPrimeiroDaLista = index == 0 && itensOriginais.isEmpty;
            final chave = 'adicional:${ad.id}';
            final pendente = statusPendentes.containsKey(chave);
            final statusEfetivo = statusPendentes[chave] ?? ad.statusCompra;
            return _MaterialCard(
              tourKeyComprado: ehPrimeiroDaLista ? tourKeyComprado : null,
              tourKeyEstoque: ehPrimeiroDaLista ? tourKeyEstoque : null,
              tipo: 'adicional',
              id: ad.id,
              materialNome: ad.materialNome,
              materialUnidade: ad.materialUnidade,
              materialIdentificador: ad.materialIdentificador,
              materialMedida: ad.materialMedida,
              materialEspessura: ad.materialEspessura,
              materialLargura: ad.materialLargura,
              materialComprimento: ad.materialComprimento,
              materialCategoria: ad.materialCategoria,
              materialEstoque: ad.materialQuantidadeEstoque,
              quantidade: ad.quantidade,
              observacao: ad.observacao,
              imagemUrl: ad.imagemUrl,
              status: statusEfetivo,
              pendente: pendente,
              compradoEm: ad.compradoEm,
              compradoPorNome: ad.compradoPorNome,
              estoqueEm: ad.estoqueEm,
              estoquePorNome: ad.estoquePorNome,
              criadoEm: ad.adicionadoEm,
              adicionadoPorNome: ad.adicionadoPorNome,
              editadoEm: ad.editadoEm,
              editadoPorNome: ad.editadoPorNome,
              andamento: solicitacao.andamento,
              onSelecionarStatus: (novoStatus) =>
                  onAlterarStatus('adicional', ad.id, ad.statusCompra, novoStatus),
              onReabrirSolicitacao: onReabrirSolicitacao,
              podeEditar: podeEditarMaterial,
              onEditar: () => onEditarMaterial('adicional', ad.id, ad.quantidade, ad.observacao),
              onExcluir: () => onExcluirMaterial('adicional', ad.id, ad.materialNome),
              onEncaminhar: () => onEncaminharMaterial('adicional', ad.id),
            );
          }),
        ],
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final String tipo; // 'item' ou 'adicional'
  final int id;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final double? materialLargura;
  final double? materialComprimento;
  final String? materialCategoria;
  final double materialEstoque;
  final double quantidade;
  final String? observacao;
  final String? imagemUrl;
  final String status; // valor efetivo: 'PENDENTE' | 'COMPRADO' | 'ESTOQUE' (já considera alteração pendente não salva)
  final bool pendente; // true quando há alteração local ainda não persistida
  final DateTime? compradoEm;
  final String? compradoPorNome;
  final DateTime? estoqueEm;
  final String? estoquePorNome;
  final DateTime criadoEm;
  final String? adicionadoPorNome;
  final DateTime? editadoEm;
  final String? editadoPorNome;
  final String andamento;
  final ValueChanged<String> onSelecionarStatus;
  final VoidCallback? onReabrirSolicitacao;
  final bool podeEditar;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final VoidCallback onEncaminhar;
  /// Usadas apenas pelo tour "Como atender uma solicitação" para dar
  /// highlight nos botões COMPRADO/ESTOQUE deste card.
  final GlobalKey? tourKeyComprado;
  final GlobalKey? tourKeyEstoque;

  /// Rótulo de medida/dimensão a ser exibido ao lado do nome.
  /// Se houver medida cadastrada, mostra só a medida (evita repetir com
  /// largura/comprimento). Caso contrário, se houver largura e comprimento,
  /// mostra "COMPRIMENTOxLARGURAM" (ex.: "5X1.22M").
  String? get _medidaOuDimensao {
    final temMedida = materialMedida != null && materialMedida!.trim().isNotEmpty;
    if (temMedida) return materialMedida!.trim();

    final temDimensoes = materialLargura != null &&
        materialComprimento != null &&
        materialLargura! > 0 &&
        materialComprimento! > 0;
    if (temDimensoes) {
      String fmt(double v) {
        if (v % 1 == 0) return v.toStringAsFixed(0);
        var s = v.toStringAsFixed(2);
        if (s.endsWith('0')) s = s.substring(0, s.length - 1);
        if (s.endsWith('.')) s = s.substring(0, s.length - 1);
        return s;
      }
      return '${fmt(materialComprimento!)}x${fmt(materialLargura!)}m';
    }

    final temApenasComprimento = materialComprimento != null && materialComprimento! > 0;
    final temApenasLargura     = materialLargura     != null && materialLargura!     > 0;
    if (temApenasComprimento || temApenasLargura) {
      String fmt(double v) {
        if (v % 1 == 0) return v.toStringAsFixed(0);
        var s = v.toStringAsFixed(2);
        if (s.endsWith('0')) s = s.substring(0, s.length - 1);
        if (s.endsWith('.')) s = s.substring(0, s.length - 1);
        return s;
      }
      return '${fmt(temApenasComprimento ? materialComprimento! : materialLargura!)}m';
    }
    return null;
  }

  const _MaterialCard({
    required this.tipo,
    required this.id,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.materialLargura,
    this.materialComprimento,
    this.materialCategoria,
    required this.materialEstoque,
    required this.quantidade,
    this.observacao,
    this.imagemUrl,
    required this.status,
    required this.pendente,
    this.compradoEm,
    this.compradoPorNome,
    this.estoqueEm,
    this.estoquePorNome,
    required this.criadoEm,
    this.adicionadoPorNome,
    this.editadoEm,
    this.editadoPorNome,
    required this.andamento,
    required this.onSelecionarStatus,
    this.onReabrirSolicitacao,
    required this.podeEditar,
    required this.onEditar,
    required this.onExcluir,
    required this.onEncaminhar,
    this.tourKeyComprado,
    this.tourKeyEstoque,
  });

  // Mostra o aviso de solicitação finalizada (com opção de reabrir para ADMIN)
  // e retorna true se a ação deve ser bloqueada.
  bool _bloqueadoPorFinalizacao(BuildContext context) {
    if (andamento != 'FINALIZADO') return false;

    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    final ehAdmin = usuario?.role.trim().toUpperCase() == 'ADMIN' || usuario?.role.trim().toUpperCase() == 'GERENTE';

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitação finalizada'),
        content: const Text(
          'Esta solicitação está finalizada. Para alterar os itens, reabra-a primeiro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          if (ehAdmin)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Reabrir'),
            ),
        ],
      ),
    ).then((reabrir) {
      if (reabrir == true) onReabrirSolicitacao?.call();
    });
    return true;
  }

  void _handleEditar(BuildContext context) {
    if (_bloqueadoPorFinalizacao(context)) return;
    onEditar();
  }

  void _handleExcluir(BuildContext context) {
    if (_bloqueadoPorFinalizacao(context)) return;
    onExcluir();
  }

  // botaoStatus: status correspondente ao botão clicado ('COMPRADO' ou 'ESTOQUE').
  // Se o status já está ativo, o clique desmarca (volta para PENDENTE) —
  // caso contrário, seleciona o novo status (a troca é mutuamente exclusiva:
  // marcar ESTOQUE desmarca COMPRADO e vice-versa).
  void _handleSelecionarStatus(BuildContext context, String botaoStatus) {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    final ehAdmin = usuario?.role.trim().toUpperCase() == 'ADMIN' || usuario?.role.trim().toUpperCase() == 'GERENTE';
    final estaAtivo = status == botaoStatus;
    final novoStatus = estaAtivo ? 'PENDENTE' : botaoStatus;

    // Bloqueia qualquer alteração se a solicitação está FINALIZADA
    if (_bloqueadoPorFinalizacao(context)) return;

    // Só é restrito a ADMIN/GERENTE desmarcar ou trocar um item que JÁ está
    // marcado como COMPRADO ou ESTOQUE e essa marcação já foi persistida
    // (pendente == false). Marcar um item que ainda está PENDENTE (nunca foi
    // comprado/retirado do estoque) é livre para qualquer usuário com acesso
    // à tela, independente de já ter vindo do backend ou não.
    final alterandoValorJaSalvo =
        (status == 'COMPRADO' || status == 'ESTOQUE') && !pendente;
    if (alterandoValorJaSalvo && !ehAdmin) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ação não permitida'),
          content: const Text('Apenas administradores podem alterar um item já salvo como comprado ou estoque.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    onSelecionarStatus(novoStatus);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Coluna: Material ──────────────────────────────────────
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              (materialIdentificador != null && materialIdentificador!.isNotEmpty)
                                  ? '$materialIdentificador · $materialNome'
                                  : materialNome,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                              softWrap: true,
                            ),
                          ),
                          if (tipo == 'adicional') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_circle_outline,
                                      size: 11, color: Color(0xFF0D9488)),
                                  SizedBox(width: 3),
                                  Text('EXTRA',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0D9488),
                                        letterSpacing: 0.3,
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_medidaOuDimensao != null ||
                          (materialEspessura != null &&
                              materialEspessura!.trim().isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_medidaOuDimensao != null)
                                Text(
                                  _medidaOuDimensao!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (_medidaOuDimensao != null &&
                                  materialEspessura != null &&
                                  materialEspessura!.trim().isNotEmpty)
                                Text(
                                  '•',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              if (materialEspessura != null &&
                                  materialEspessura!.trim().isNotEmpty)
                                Text(
                                  formatarEspessuraComSufixo(materialEspessura)!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ── Coluna: Quantidade solicitada ─────────────────────────
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Qtd. solicitada',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatarQuantidade(quantidade)}${materialUnidade != null ? ' ${formatarUnidadeExibicao(materialUnidade)}' : ''}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ── Coluna: Estoque atual ─────────────────────────────────
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estoque atual',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatarQuantidade(materialEstoque)}${materialUnidade != null ? ' ${formatarUnidadeExibicao(materialUnidade)}' : ''}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // ── Coluna: Pendente + ações ───────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Agrupa COMPRADO + ESTOQUE numa única key para que o tour
                    // "Como atender uma solicitação" dê highlight nos dois
                    // botões juntos (ambos resolvem a mesma solicitação, o
                    // usuário escolhe qual usar conforme o caso).
                    Column(
                      key: tourKeyComprado,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _StatusToggle(
                          ativo: status == 'COMPRADO',
                          pendente: pendente && status == 'COMPRADO',
                          label: 'COMPRADO',
                          iconeAtivo: Icons.check_circle,
                          iconeInativo: Icons.radio_button_unchecked,
                          cor: AppTheme.success,
                          onTap: () => _handleSelecionarStatus(context, 'COMPRADO'),
                        ),
                        const SizedBox(height: 6),
                        _StatusToggle(
                          key: tourKeyEstoque,
                          ativo: status == 'ESTOQUE',
                          pendente: pendente && status == 'ESTOQUE',
                          label: 'ESTOQUE',
                          iconeAtivo: Icons.inventory_2,
                          iconeInativo: Icons.inventory_2_outlined,
                          cor: const Color(0xFF7C3AED),
                          onTap: () => _handleSelecionarStatus(context, 'ESTOQUE'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _IconActionButton(
                          icon: Icons.ios_share_outlined,
                          tooltip: 'Encaminhar este material no chat',
                          color: AppTheme.primary,
                          onTap: onEncaminhar,
                        ),
                        if (podeEditar) ...[
                          const SizedBox(width: 8),
                          _IconActionButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Editar quantidade e observação',
                            onTap: () => _handleEditar(context),
                          ),
                          const SizedBox(width: 8),
                          _IconActionButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Remover este material',
                            color: AppTheme.error,
                            onTap: () => _handleExcluir(context),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (observacao != null && observacao!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Observação: $observacao',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
            ],
            if (imagemUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(_resolverUrl(imagemUrl!),
                    height: 100, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                          height: 100,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Center(child: Icon(Icons.broken_image)),
                        )),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                // Adicionais: funde data e autor em uma chip roxa
                if (tipo == 'adicional' && adicionadoPorNome != null)
                  _InfoChip(
                    icon: Icons.add_circle_outline,
                    label:
                        'Adicionado em ${DateFormat('dd/MM/yyyy HH:mm').format(criadoEm)} por $adicionadoPorNome',
                    color: const Color(0xFF0D9488),
                  )
                else ...[
                  _InfoChip(
                    icon: Icons.schedule,
                    label:
                        'Adicionado em ${DateFormat('dd/MM/yyyy HH:mm').format(criadoEm)}',
                  ),
                  if (adicionadoPorNome != null)
                    _InfoChip(
                      icon: Icons.person_outline,
                      label: 'Por $adicionadoPorNome',
                    ),
                ],
                if (editadoEm != null)
                  _InfoChip(
                    icon: Icons.edit_outlined,
                    label:
                        'Editado em ${DateFormat('dd/MM/yyyy HH:mm').format(editadoEm!)}${editadoPorNome != null ? ' por $editadoPorNome' : ''}',
                    color: const Color(0xFFB45309),
                  ),
                if (status == 'COMPRADO' && compradoEm != null)
                  _InfoChip(
                    icon: Icons.shopping_cart,
                    label:
                        'Comprado em ${DateFormat('dd/MM/yyyy HH:mm').format(compradoEm!)}',
                    color: AppTheme.success,
                  ),
                if (status == 'COMPRADO' && compradoPorNome != null)
                  _InfoChip(
                    icon: Icons.person,
                    label: 'Por $compradoPorNome',
                    color: AppTheme.success,
                  ),
                if (status == 'ESTOQUE' && estoqueEm != null)
                  _InfoChip(
                    icon: Icons.inventory_2,
                    label:
                        'Retirado do estoque em ${DateFormat('dd/MM/yyyy HH:mm').format(estoqueEm!)}',
                    color: const Color(0xFF7C3AED),
                  ),
                if (status == 'ESTOQUE' && estoquePorNome != null)
                  _InfoChip(
                    icon: Icons.person,
                    label: 'Por $estoquePorNome',
                    color: const Color(0xFF7C3AED),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusToggle extends StatefulWidget {
  final bool ativo;
  final bool pendente;
  final String label;
  final IconData iconeAtivo;
  final IconData iconeInativo;
  final Color cor;
  final VoidCallback onTap;

  const _StatusToggle({
    super.key,
    required this.ativo,
    required this.label,
    required this.iconeAtivo,
    required this.iconeInativo,
    required this.cor,
    required this.onTap,
    this.pendente = false,
  });

  @override
  State<_StatusToggle> createState() => _StatusToggleState();
}

class _StatusToggleState extends State<_StatusToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ativo = widget.ativo;

    final corBase = ativo
        ? widget.cor
        : Theme.of(context).colorScheme.outline;
    final corFundo = ativo
        ? widget.cor.withValues(alpha: _hovered ? 0.22 : 0.15)
        : (_hovered
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
            : Theme.of(context).colorScheme.surfaceContainerHighest);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: corFundo,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: corBase,
              width: _hovered ? 1.5 : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: corBase.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ativo ? widget.iconeAtivo : widget.iconeInativo,
                size: 16,
                color: ativo
                    ? widget.cor
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Text(
                ativo ? widget.label : widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ativo
                      ? widget.cor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.pendente) ...[
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.cor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  State<_IconActionButton> createState() => _IconActionButtonState();
}

class _IconActionButtonState extends State<_IconActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cor = widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.transparent,
          mouseCursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hovered ? cor.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? cor.withValues(alpha: 0.4) : Colors.transparent,
              ),
            ),
            child: Icon(widget.icon, size: 16, color: cor),
          ),
        ),
      ),
    );
  }
}

// ─── Diálogo de edição de quantidade/observação de um material ──────────────
class _EditarMaterialDialog extends StatefulWidget {
  final double quantidadeAtual;
  final String? observacaoAtual;

  const _EditarMaterialDialog({
    required this.quantidadeAtual,
    this.observacaoAtual,
  });

  @override
  State<_EditarMaterialDialog> createState() => _EditarMaterialDialogState();
}

class _EditarMaterialDialogState extends State<_EditarMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantidadeCtrl;
  late final TextEditingController _observacaoCtrl;

  @override
  void initState() {
    super.initState();
    final qtd = widget.quantidadeAtual;
    _quantidadeCtrl = TextEditingController(
      text: formatarQuantidade(qtd),
    );
    _observacaoCtrl = TextEditingController(text: widget.observacaoAtual ?? '');
  }

  @override
  void dispose() {
    _quantidadeCtrl.dispose();
    _observacaoCtrl.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_formKey.currentState!.validate()) return;
    final quantidade = double.parse(_quantidadeCtrl.text.replaceAll(',', '.'));
    final observacao = _observacaoCtrl.text.trim();
    Navigator.pop(context, {
      'quantidade': quantidade,
      'observacao': observacao.isEmpty ? null : observacao,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Material'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _quantidadeCtrl,
              decoration: const InputDecoration(labelText: 'Quantidade'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              validator: (v) {
                final valor = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                if (valor == null || valor <= 0) return 'Informe uma quantidade válida';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _observacaoCtrl,
              decoration: const InputDecoration(
                labelText: 'Observação',
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom().copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: chipColor)),
        ],
      ),
    );
  }
}

// ─── Aba Dados ────────────────────────────────

class _AbaDadosSolicitacao extends StatelessWidget {
  final SolicitacaoMaterialModel solicitacao;
  final TextEditingController numeroOSCtrl;
  final TextEditingController clienteCtrl;
  final TextEditingController observacaoCtrl;
  final DateTime dataNecessidade;
  final String andamento;
  final ValueChanged<DateTime> onDataNecessidadeChanged;
  final ValueChanged<String> onAndamentoChanged;
  final bool ehAdmin;
  final String? erroDialog;
  final VoidCallback onDismissErro;

  const _AbaDadosSolicitacao({
    required this.solicitacao,
    required this.numeroOSCtrl,
    required this.clienteCtrl,
    required this.observacaoCtrl,
    required this.dataNecessidade,
    required this.andamento,
    required this.onDataNecessidadeChanged,
    required this.onAndamentoChanged,
    required this.ehAdmin,
    this.erroDialog,
    required this.onDismissErro,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (erroDialog != null) ...[
            _ErroBanner(mensagem: erroDialog!, onDismiss: onDismissErro),
            const SizedBox(height: 16),
          ],
          if (!ehAdmin) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 16, color: Color(0xFF1E88E5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Apenas o criador da solicitação ou um administrador pode editar os dados.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF1E88E5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Consumer<SolicitacaoMaterialProvider>(
            builder: (_, prov, __) {
              if (prov.logs.isEmpty) return const SizedBox.shrink();
              // Logs vêm ordenados do mais recente para o mais antigo.
              final ultimo = prov.logs.first;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _InfoChip(
                  icon: Icons.edit_note,
                  label:
                      'Editado em ${DateFormat('dd/MM/yyyy HH:mm').format(ultimo.editadoEm)} por ${ultimo.editorNome}',
                  color: AppTheme.primary,
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: numeroOSCtrl,
                  readOnly: !ehAdmin,
                  decoration: const InputDecoration(labelText: 'Número OS'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperCaseFormatter()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: clienteCtrl,
                  readOnly: !ehAdmin,
                  decoration: const InputDecoration(labelText: 'Nome Cliente'),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: DateFormat('dd/MM/yyyy HH:mm').format(solicitacao.dataSolicitacao),
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Data Solicitação',
              suffixIcon: Icon(Icons.lock_outline, size: 16,
                  color: Theme.of(context).colorScheme.outline),
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (ehAdmin)
            _DatePickerField(
              label: 'Data Necessidade',
              value: dataNecessidade,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              onChanged: onDataNecessidadeChanged,
            )
          else
            TextFormField(
              initialValue: DateFormat('dd/MM/yyyy').format(dataNecessidade),
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Data Necessidade'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: andamento,
            decoration: const InputDecoration(labelText: 'Andamento', isDense: true),
            items: const [
              DropdownMenuItem(value: 'EM_ANDAMENTO', child: Text('EM ANDAMENTO')),
              DropdownMenuItem(value: 'EM_NEGOCIACAO', child: Text('EM NEGOCIAÇÃO')),
              DropdownMenuItem(value: 'FINALIZADO', child: Text('FINALIZADO')),
            ],
            onChanged: ehAdmin ? (v) => onAndamentoChanged(v!) : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: observacaoCtrl,
            readOnly: !ehAdmin,
            decoration: const InputDecoration(
              labelText: 'Observação',
              alignLabelWithHint: true,
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          Text('Solicitante: ${solicitacao.usuarioNome}',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─── Aba Histórico ────────────────────────────────────────────────────────

/// Formata número sem arredondar/cortar a precisão real do valor.
/// Ex: 5 -> "5", 3.696 -> "3.696" (não "3.70").
String _fmtNumeroLog(num v) {
  final d = v.toDouble();
  return formatarQuantidade(d);
}

/// Quantidade + unidade a partir do snapshot de material salvo no log
/// (ex: "25 m/l", "1 unidade"). Retorna null se não houver quantidade.
String? _qtdComUnidadeLog(Map<String, dynamic> depois) {
  final qtd = depois['quantidade'];
  if (qtd == null) return null;
  final qtdNum = qtd is num ? qtd : num.tryParse(qtd.toString());
  if (qtdNum == null) return null;
  final unidade = depois['materialUnidade']?.toString().trim();
  final qtdFmt = _fmtNumeroLog(qtdNum);
  return unidade != null && unidade.isNotEmpty ? '$qtdFmt $unidade' : qtdFmt;
}

/// Nome + detalhes (medida/espessura) de um material do log, sem a
/// quantidade — ex: "ACRILICO TESTE2 (2MM)".
String _formatarMaterialLogNome(Map material) {
  final nome = material['materialNome']?.toString().trim();
  if (nome == null || nome.isEmpty) return '';

  final detalhesPartes = <String>[];
  final medida = material['materialMedida']?.toString().trim();
  if (medida != null && medida.isNotEmpty) detalhesPartes.add(medida);
  final espessura = formatarEspessuraComSufixo(material['materialEspessura']?.toString());
  if (espessura != null) detalhesPartes.add(espessura);

  if (detalhesPartes.isEmpty) return nome;
  return '$nome (${detalhesPartes.join(' · ')})';
}

/// Quantidade/unidade de um material do log, já formatada — ex: "2 UNIDADE".
String? _formatarMaterialLogQtd(Map material) {
  return _qtdComUnidadeLog(material.cast<String, dynamic>());
}

/// Linha de material do histórico: nome+detalhes em destaque e a
/// quantidade em cinza, separados por espaço.
Widget _linhaMaterialLog(Map material, {Color corNome = AppTheme.success}) {
  final nome = _formatarMaterialLogNome(material);
  final qtd = _formatarMaterialLogQtd(material);
  return RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: nome,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: corNome,
          ),
        ),
        if (qtd != null && qtd.isNotEmpty)
          TextSpan(
            text: '  $qtd',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.grey,
            ),
          ),
      ],
    ),
  );
}

class _AbaHistorico extends StatelessWidget {
  final int solicitacaoId;
  const _AbaHistorico({required this.solicitacaoId});

  static const _camposLabel = {
    'numeroOS': 'Número OS',
    'nomeCliente': 'Cliente',
    'dataNecessidade': 'Data Necessidade',
    'andamento': 'Andamento',
    'observacao': 'Observação',
  };

  String _fmt(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    try {
      final d = DateTime.parse(s).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(d);
    } catch (_) {}
    return s.isEmpty ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SolicitacaoMaterialProvider>(
      builder: (_, prov, __) {
        if (prov.carregandoLogs) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (prov.logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                Text('Nenhuma edição registrada',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: prov.logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final log = prov.logs[i];
            final excluido  = log.depois['excluido'] == true;
            final criada    = log.depois['criada'] == true;
            final adicionado = log.depois['adicionado'] == true;
            final eventoEspecial = excluido || criada || adicionado;

            final campos = <String>[];
            if (!eventoEspecial) {
              for (final key in log.depois.keys) {
                final antes = log.antes[key]?.toString();
                final depois = log.depois[key]?.toString();
                if (antes != depois) campos.add(key);
              }
            }

            // Lista de materiais no evento de criação — um item por linha
            // (nome + detalhes + quantidade/unidade), sem vírgulas.
            final materiaisCriacaoLista = criada && log.depois['materiais'] is List
                ? (log.depois['materiais'] as List)
                    .whereType<Map>()
                    .where((m) => _formatarMaterialLogNome(m).isNotEmpty)
                    .toList()
                : const <Map>[];

            // Material único do evento de adição extra — mesmo formato usado
            // na lista de criação (nome + detalhes em destaque, quantidade em cinza).
            final materialAdicionadoNome =
                adicionado ? _formatarMaterialLogNome(log.depois) : null;

            // Título da entrada: identifica a ação além de quem a realizou —
            // não basta mostrar só o nome do usuário.
            final tituloEntrada = criada
                ? 'Solicitação criada por ${log.editorNome}'
                : adicionado
                    ? 'Material extra adicionado por ${log.editorNome}'
                    : excluido
                        ? 'Material removido por ${log.editorNome}'
                        : log.editorNome;

            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          excluido
                              ? Icons.delete_outline
                              : criada
                                  ? Icons.add_circle_outline
                                  : adicionado
                                      ? Icons.playlist_add
                                      : Icons.edit_note,
                          size: 16,
                          color: excluido ? AppTheme.error : AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(tituloEntrada,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                        Text(DateFormat('dd/MM/yyyy HH:mm').format(log.editadoEm),
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    // Para o evento de material extra adicionado, o nome do
                    // material já aparece na linha de detalhe logo abaixo —
                    // repeti-lo aqui em itálico só duplicaria a informação.
                    if (!adicionado && log.item != null && log.item!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        log.item!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (excluido) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 0),
                      const SizedBox(height: 8),
                      Text(
                        'Material removido da solicitação',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.error,
                        ),
                      ),
                    ],
                    if (criada) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 0),
                      const SizedBox(height: 8),
                      if (materiaisCriacaoLista.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final material in materiaisCriacaoLista)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: _linhaMaterialLog(material),
                              ),
                          ],
                        )
                      else
                        const Text(
                          'Solicitação criada',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                    ],
                    if (adicionado) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 0),
                      const SizedBox(height: 8),
                      materialAdicionadoNome != null && materialAdicionadoNome.isNotEmpty
                          ? _linhaMaterialLog(log.depois)
                          : const Text(
                              'Material adicionado à solicitação',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.success,
                              ),
                            ),
                    ],
                    if (campos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 0),
                      const SizedBox(height: 8),
                      ...campos.map((campo) {
                        final label = _camposLabel[campo] ?? campo;
                        final antes = _fmt(log.antes[campo]);
                        final depois = _fmt(log.depois[campo]);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(label,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                              ),
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 10,
                                  runSpacing: 3,
                                  children: [
                                    RichText(
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                        children: [
                                          const TextSpan(
                                              text: 'antes: ',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.error)),
                                          TextSpan(text: antes),
                                        ],
                                      ),
                                    ),
                                    RichText(
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                        children: [
                                          const TextSpan(
                                              text: 'depois: ',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.success)),
                                          TextSpan(text: depois),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG: ADICIONAR MATERIAIS (adicional)
// ═══════════════════════════════════════════════════════════════════════════

class _AdicionarMateriaisDialog extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;

  const _AdicionarMateriaisDialog({required this.solicitacao});

  @override
  State<_AdicionarMateriaisDialog> createState() => _AdicionarMateriaisDialogState();
}

class _AdicionarMateriaisDialogState extends State<_AdicionarMateriaisDialog> {
  bool _salvando = false;
  String? _erroDialog;

  final List<_ItemMaterialCriacao> _itens = [];

  @override
  void dispose() {
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  void _adicionarItem() {
    setState(() => _itens.insert(0, _ItemMaterialCriacao()));
  }

  void _removerItem(int index) {
    if (_itens.length == 1) return;
    setState(() {
      _itens[index].dispose();
      _itens.removeAt(index);
    });
  }

  Future<void> _cadastrarMaterialGlobal(BuildContext context) async {
    final criou = await showDialog<bool>(
      context: context,
      builder: (_) => const MaterialFormDialog(),
    );
    if (criou == true && context.mounted) {
      await context.read<MaterialProvider>().carregarCategorias();
    }
  }

  /// Scrolla a lista de materiais até o card do [item] informado.
  void _scrollAteItem(_ItemMaterialCriacao item) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = item.cardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  Future<void> _salvar() async {
    for (int i = 0; i < _itens.length; i++) {
      final item = _itens[i];
      item.quantidadeCtrl.text = item.quantidadeCtrl.text.trim();
      item.observacaoCtrl.text = item.observacaoCtrl.text.trim();

      if (item.material == null) {
        setState(() => _erroDialog = 'Selecione o material do item ${i + 1}');
        _scrollAteItem(item);
        return;
      }
      if (item.quantidadeCtrl.text.isEmpty ||
          double.tryParse(item.quantidadeCtrl.text) == null) {
        setState(() => _erroDialog = 'Informe a quantidade do item ${i + 1}');
        _scrollAteItem(item);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          item.quantidadeFocus.requestFocus();
        });
        return;
      }
    }

    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    final itens = _itens.map((item) => {
      'materialId': item.material!.id,
      'quantidade': double.parse(item.quantidadeCtrl.text),
      'observacao': item.observacaoCtrl.text.trim().isEmpty
          ? null
          : item.observacaoCtrl.text.trim(),
    }).toList();

    final imagensPorIndice = <int, File>{};
    for (int i = 0; i < _itens.length; i++) {
      if (_itens[i].imagem != null) {
        imagensPorIndice[i] = _itens[i].imagem!;
      }
    }

    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.adicionarMateriais(
      widget.solicitacao.id,
      itens: itens,
      imagensPorIndice: imagensPorIndice,
    );

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Materiais adicionados'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() => _erroDialog = provider.erro ?? 'Erro ao adicionar materiais');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adicionar Materiais',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text('OS ${widget.solicitacao.numeroOS}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erroDialog != null) ...[
                      _ErroBanner(
                        mensagem: _erroDialog!,
                        onDismiss: () => setState(() => _erroDialog = null),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Text('Materiais',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _cadastrarMaterialGlobal(context),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Cadastrar material'),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.primary)
                              .copyWith(
                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Adicionar um novo material à solicitação',
                          child: TextButton.icon(
                            onPressed: _adicionarItem,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Adicionar Material'),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.primary)
                                .copyWith(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._itens.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ItemMaterialCard(
                          key: item.cardKey,
                          index: index,
                          item: item,
                          onRemover: _itens.length > 1 ? () => _removerItem(index) : null,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Cancelar e fechar sem salvar',
                    child: TextButton(
                      onPressed: _salvando ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Adicionar os materiais à solicitação',
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                      child: _salvando
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Adicionar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS AUXILIARES
// ═══════════════════════════════════════════

class _ErroBanner extends StatelessWidget {
  final String mensagem;
  final VoidCallback onDismiss;
  const _ErroBanner({required this.mensagem, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensagem,
                style: const TextStyle(color: AppTheme.error, fontSize: 13)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: AppTheme.error, size: 16),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime value;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onChanged;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: firstDate ?? DateTime(2020),
            lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) onChanged(picked);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat('dd/MM/yyyy').format(value),
                style: const TextStyle(fontSize: 14)),
            const Icon(Icons.calendar_today, size: 16),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SELETOR DE MATERIAL (reutilizado do código original)
// ═══════════════════════════════════════════

const _kSelCategoriaGeral = '__GERAL__';
const _kSelCategoriaSemCategoria = '__SEM_CATEGORIA__';

/// GlobalKeys usadas pelo tour do robô assistente dentro do dialog
/// "Selecionar Material" (aberto a partir de um item da Nova Solicitação).
class _SeletorMaterialTourKeys {
  final filtrarCategorias = GlobalKey();
  final cardTodos         = GlobalKey();
  final buscaNome         = GlobalKey();
  final identificador     = GlobalKey();
  final medida            = GlobalKey();
  final comprimento       = GlobalKey();
  final largura           = GlobalKey();
  final espessura         = GlobalKey();
  final primeiroMaterial  = GlobalKey();
  /// Envolve busca por nome + todos os campos de filtro (identificador,
  /// medida, comprimento, largura, espessura) — usado pra destacar tudo
  /// de uma vez com uma única dica, em vez de campo a campo.
  final filtros           = GlobalKey();
}

class _SeletorMaterialDialog extends StatefulWidget {
  final _SeletorMaterialTourKeys? tourKeys;
  final bool abrirTodosAutomaticamente;

  const _SeletorMaterialDialog({
    this.tourKeys,
    this.abrirTodosAutomaticamente = false,
  });

  @override
  State<_SeletorMaterialDialog> createState() => _SeletorMaterialDialogState();
}

class _SeletorMaterialDialogState extends State<_SeletorMaterialDialog> {
  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0x00ffb300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  String? _categoriaSelecionada;
  String _categoriaLabel = '';
  Color _categoriaCor = AppTheme.primary;
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria = '';
  final _buscaCtrl = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl = TextEditingController();
  final _comprimentoCtrl = TextEditingController();
  final _larguraCtrl = TextEditingController();
  final _espessuraCtrl = TextEditingController();
  String _statusFiltro = '';
  Timer? _debounceTimer;
  bool _carregandoMateriais = false;
  List<MaterialModel> _materiais = [];
  String? _identificadorSelecionado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<MaterialProvider>().carregarCategorias();
      // Durante o tour do robô assistente, abre direto a categoria "TODOS"
      // pra já cair na lista de materiais e destacar os campos de filtro.
      if (widget.abrirTodosAutomaticamente && mounted) {
        await _abrirCategoria(_kSelCategoriaGeral, 'TODOS', AppTheme.primary);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filtroCategoriaCtrl.dispose();
    _buscaCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _comprimentoCtrl.dispose();
    _larguraCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  String? _categoriaParaProvider(String categoriaId) {
    if (categoriaId == _kSelCategoriaGeral) return null;
    if (categoriaId == _kSelCategoriaSemCategoria) return '';
    return categoriaId;
  }

  Future<void> _abrirCategoria(String id, String label, Color cor) async {
    setState(() {
      _categoriaSelecionada = id;
      _categoriaLabel = label;
      _categoriaCor = cor;
      _identificadorSelecionado = null;
      _filtroCategoria = '';
      _filtroCategoriaCtrl.clear();
      _buscaCtrl.clear();
      _identificadorCtrl.clear();
      _medidaCtrl.clear();
      _comprimentoCtrl.clear();
      _larguraCtrl.clear();
      _espessuraCtrl.clear();
      _statusFiltro = '';
      _carregandoMateriais = true;
      _materiais = [];
    });
    await _carregarMateriais();
  }

  Future<void> _carregarMateriais() async {
    final prov = context.read<MaterialProvider>();
    await prov.carregar(
      busca: _buscaCtrl.text.trim(),
      identificador: _identificadorCtrl.text.trim(),
      medida: _medidaCtrl.text.trim(),
      comprimento: _comprimentoCtrl.text.trim(),
      largura: _larguraCtrl.text.trim(),
      espessura: _espessuraCtrl.text.trim(),
      status: _statusFiltro,
      categoria: _categoriaParaProvider(_categoriaSelecionada!),
    );
    if (mounted) {
      setState(() {
        _materiais = prov.materiais;
        _carregandoMateriais = false;
      });
    }
  }

  bool get _categoriaTemIdentificadores {
    if (_categoriaSelecionada == _kSelCategoriaGeral ||
        _categoriaSelecionada == _kSelCategoriaSemCategoria) {
      return false;
    }
    return _materiais.any(
        (m) => m.identificador != null && m.identificador!.trim().isNotEmpty);
  }

  void _aplicarFiltrosMateriais() {
    setState(() => _carregandoMateriais = true);
    _carregarMateriais();
  }

  Future<void> _cadastrarMaterial(BuildContext context) async {
    final criou = await showDialog<bool>(
      context: context,
      builder: (_) => const MaterialFormDialog(),
    );
    if (criou == true && context.mounted) {
      await context.read<MaterialProvider>().carregarCategorias();
      if (_categoriaSelecionada != null) {
        _aplicarFiltrosMateriais();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  if (_categoriaSelecionada != null)
                    IconButton(
                      onPressed: () {
                        if (_identificadorSelecionado != null &&
                            _categoriaTemIdentificadores) {
                          setState(() {
                            _identificadorSelecionado = null;
                            _identificadorCtrl.clear();
                            _buscaCtrl.clear();
                            _medidaCtrl.clear();
                            _comprimentoCtrl.clear();
                            _larguraCtrl.clear();
                            _espessuraCtrl.clear();
                            _filtroCategoria = '';
                            _filtroCategoriaCtrl.clear();
                          });
                          _aplicarFiltrosMateriais();
                        } else {
                          setState(() => _categoriaSelecionada = null);
                        }
                      },
                      icon: const Icon(Icons.arrow_back, size: 20),
                      tooltip: _identificadorSelecionado != null &&
                              _categoriaTemIdentificadores
                          ? 'Voltar aos identificadores'
                          : 'Voltar às categorias',
                      style: IconButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _categoriaSelecionada == null
                          ? 'Selecionar Material'
                          : _identificadorSelecionado != null
                              ? '$_categoriaLabel › ${_identificadorSelecionado == "__SEM__" ? "Sem identificador" : _identificadorSelecionado == "__TODOS__" ? "Todos" : _identificadorSelecionado}'
                              : _categoriaLabel,
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cadastrar material',
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: () => _cadastrarMaterial(context),
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 0),
            Expanded(
              child: _categoriaSelecionada == null
                  ? _buildGridCategorias(context)
                  : _buildListaMateriais(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCategorias(BuildContext context) {
    return Consumer<MaterialProvider>(
      builder: (_, prov, __) {
        if (prov.carregando) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }

        final todasCategorias = prov.categorias;
        final categoriasVisiveis = _filtroCategoria.isEmpty
            ? todasCategorias
            : todasCategorias
                .where((c) =>
                    c.toLowerCase().contains(_filtroCategoria.toLowerCase()))
                .toList();

        final categorias = <Map<String, dynamic>>[
          {'id': _kSelCategoriaGeral, 'label': 'TODOS', 'icon': Icons.grid_view_rounded},
          ...categoriasVisiveis.map((c) => {
                'id': c,
                'label': c.toUpperCase(),
                'icon': Icons.category_rounded,
              }),
          if (_filtroCategoria.isEmpty)
            {'id': _kSelCategoriaSemCategoria, 'label': 'SEM CATEGORIA', 'icon': Icons.label_off_rounded},
        ];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: KeyedSubtree(
                key: widget.tourKeys?.filtrarCategorias,
                child: TextField(
                  controller: _filtroCategoriaCtrl,
                  inputFormatters: [_UpperCaseFormatter()],
                  decoration: InputDecoration(
                    hintText: 'Filtrar categorias...',
                    prefixIcon: Icon(Icons.search, size: 18,
                        color: Theme.of(context).colorScheme.outline),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filtroCategoria = v),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.6,
                ),
                itemCount: categorias.length,
                itemBuilder: (_, i) {
                  final cat = categorias[i];
                  final cor = _cores[i % _cores.length];
                  final ehTodos = cat['id'] == _kSelCategoriaGeral;
                  return _CategoriaCardSeletor(
                    key: ehTodos ? widget.tourKeys?.cardTodos : null,
                    label: cat['label'] as String,
                    cor: cor,
                    icone: cat['icon'] as IconData,
                    onTap:() => _abrirCategoria(
                        cat['id'] as String,
                        cat['label'] as String,
                        cor),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListaMateriais(BuildContext context) {
    if (!_carregandoMateriais &&
        _materiais.isNotEmpty &&
        _categoriaTemIdentificadores &&
        _identificadorSelecionado == null) {
      return _buildGridIdentificadores(context);
    }

    return Column(
      children: [
        KeyedSubtree(
          key: widget.tourKeys?.filtros,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: KeyedSubtree(
                      key: widget.tourKeys?.buscaNome,
                      child: TextField(
                        controller: _buscaCtrl,
                        inputFormatters: [_UpperCaseFormatter()],
                        decoration: InputDecoration(
                          hintText: 'Nome do material',
                          prefixIcon: Icon(Icons.search, size: 18,
                              color: Theme.of(context).colorScheme.outline),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                              const Duration(milliseconds: 350),
                              _aplicarFiltrosMateriais);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: widget.tourKeys?.identificador,
                      child: TextField(
                        controller: _identificadorCtrl,
                        inputFormatters: [_UpperCaseFormatter()],
                        decoration: InputDecoration(
                          hintText: 'Identificador',
                          prefixIcon: Icon(Icons.qr_code, size: 18,
                              color: Theme.of(context).colorScheme.outline),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                              const Duration(milliseconds: 350),
                              _aplicarFiltrosMateriais);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KeyedSubtree(
                      key: widget.tourKeys?.medida,
                      child: TextField(
                        controller: _medidaCtrl,
                        inputFormatters: [_MedidaEspessuraFormatter()],
                        decoration: InputDecoration(
                          hintText: 'Medida',
                          prefixIcon: Icon(Icons.straighten, size: 18,
                              color: Theme.of(context).colorScheme.outline),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                              const Duration(milliseconds: 350),
                              _aplicarFiltrosMateriais);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Limpar filtros',
                    icon: Icon(Icons.filter_alt_off, size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: (_buscaCtrl.text.isNotEmpty ||
                            _identificadorCtrl.text.isNotEmpty ||
                            _medidaCtrl.text.isNotEmpty ||
                            _comprimentoCtrl.text.isNotEmpty ||
                            _larguraCtrl.text.isNotEmpty ||
                            _espessuraCtrl.text.isNotEmpty)
                        ? () {
                            _buscaCtrl.clear();
                            _identificadorCtrl.clear();
                            _medidaCtrl.clear();
                            _comprimentoCtrl.clear();
                            _larguraCtrl.clear();
                            _espessuraCtrl.clear();
                            setState(() {
                              _statusFiltro = '';
                              _identificadorSelecionado = null;
                            });
                            _aplicarFiltrosMateriais();
                          }
                        : null,
                    style: IconButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return SystemMouseCursors.basic;
                        }
                        return SystemMouseCursors.click;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: widget.tourKeys?.comprimento,
                      child: TextField(
                        controller: _comprimentoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_EspessuraFormatter()],
                        decoration: InputDecoration(
                          hintText: 'Comprimento',
                          suffixText: 'm',
                          prefixIcon: Icon(Icons.height, size: 18,
                              color: Theme.of(context).colorScheme.outline),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                              const Duration(milliseconds: 350),
                              _aplicarFiltrosMateriais);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KeyedSubtree(
                      key: widget.tourKeys?.largura,
                      child: TextField(
                        controller: _larguraCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_EspessuraFormatter()],
                        decoration: InputDecoration(
                          hintText: 'Largura',
                          suffixText: 'm',
                          prefixIcon: Icon(Icons.width_normal, size: 18,
                              color: Theme.of(context).colorScheme.outline),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                              const Duration(milliseconds: 350),
                              _aplicarFiltrosMateriais);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KeyedSubtree(
                      key: widget.tourKeys?.espessura,
                      child: TextField(
                        controller: _espessuraCtrl,
                        inputFormatters: [_EspessuraFormatter()],
                        decoration: InputDecoration(
                          hintText: 'Espessura',
                          suffixText: 'mm',
                          prefixIcon: Icon(Icons.layers, size: 18,
                              color: Theme.of(context).colorScheme.outline),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                              const Duration(milliseconds: 350),
                              _aplicarFiltrosMateriais);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
        const Divider(height: 0),
        if (!_carregandoMateriais && _materiais.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Material',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                Text(
                  'Estoque atual',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 26),
              ],
            ),
          ),
        Expanded(
          child: _carregandoMateriais
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _materiais.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text('Nenhum material encontrado',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: _materiais.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _MaterialItemSeletor(
                        key: i == 0 ? widget.tourKeys?.primeiroMaterial : null,
                        material: _materiais[i],
                        cor: _categoriaCor,
                        onTap: () => Navigator.of(context, rootNavigator: true)
                            .pop(_materiais[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildGridIdentificadores(BuildContext context) {
    final Map<String, List<MaterialModel>> grupos = {};
    for (final m in _materiais) {
      final key = (m.identificador != null && m.identificador!.trim().isNotEmpty)
          ? m.identificador!.trim().toUpperCase()
          : '__SEM__';
      grupos.putIfAbsent(key, () => []).add(m);
    }

    final chaves = grupos.keys.toList()..sort();
    if (chaves.remove('__SEM__')) chaves.add('__SEM__');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _filtroCategoriaCtrl,
            inputFormatters: [_UpperCaseFormatter()],
            decoration: InputDecoration(
              hintText: 'Filtrar identificadores...',
              prefixIcon: Icon(Icons.search, size: 18,
                  color: Theme.of(context).colorScheme.outline),
              isDense: true,
              suffixIcon: _filtroCategoria.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _filtroCategoriaCtrl.clear();
                        setState(() => _filtroCategoria = '');
                      })
                  : null,
            ),
            onChanged: (v) => setState(() => _filtroCategoria = v),
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: Builder(builder: (context) {
            final filtrados = _filtroCategoria.isEmpty
                ? chaves
                : chaves
                    .where((k) =>
                        k.toLowerCase().contains(_filtroCategoria.toLowerCase()))
                    .toList();

            if (filtrados.isEmpty) {
              return Center(
                child: Text('Nenhum identificador encontrado',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              );
            }

            final totalMateriais = _materiais.length;
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.6,
              ),
              itemCount: filtrados.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return _CategoriaCardSeletor(
                    label: 'TODOS\n$totalMateriais ${totalMateriais == 1 ? 'material' : 'materiais'}',
                    cor: AppTheme.primary,
                    icone: Icons.apps_outlined,
                    onTap: () {
                      setState(() {
                        _identificadorSelecionado = '__TODOS__';
                        _identificadorCtrl.clear();
                      });
                      _aplicarFiltrosMateriais();
                    },
                  );
                }
                final key = filtrados[i - 1];
                final label = key == '__SEM__' ? 'SEM IDENTIFICADOR' : key;
                final qtd = grupos[key]!.length;
                final cor = _cores[(i - 1) % _cores.length];
                return _CategoriaCardSeletor(
                  label: '$label\n$qtd ${qtd == 1 ? 'material' : 'materiais'}',
                  cor: cor,
                  icone: Icons.label_outline,
                  onTap: () {
                    setState(() {
                      _identificadorSelecionado = key;
                      _identificadorCtrl.text = key == '__SEM__' ? '' : key;
                    });
                    _aplicarFiltrosMateriais();
                  },
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class _CategoriaCardSeletor extends StatefulWidget {
  final String label;
  final Color cor;
  final IconData icone;
  final VoidCallback onTap;

  const _CategoriaCardSeletor({
    super.key,
    required this.label,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_CategoriaCardSeletor> createState() => _CategoriaCardSeletorState();
}

class _CategoriaCardSeletorState extends State<_CategoriaCardSeletor> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ativo = _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo
                ? widget.cor.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ativo ? widget.cor : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icone, color: widget.cor, size: 24),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ativo
                          ? widget.cor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialItemSeletor extends StatefulWidget {
  final MaterialModel material;
  final Color cor;
  final VoidCallback onTap;

  const _MaterialItemSeletor({
    super.key,
    required this.material,
    required this.cor,
    required this.onTap,
  });

  @override
  State<_MaterialItemSeletor> createState() => _MaterialItemSeletorState();
}

class _MaterialItemSeletorState extends State<_MaterialItemSeletor> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final medidaFmt = formatarMedidaOuDimensoes(
      medida:      m.medida,
      largura:     m.largura,
      comprimento: m.comprimento,
    );
    final espessuraFmt = formatarEspessuraComSufixo(m.espessura);
    final identificador = (m.identificador != null && m.identificador!.trim().isNotEmpty)
        ? m.identificador!.trim()
        : null;
    final detalhes = [medidaFmt, espessuraFmt]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.cor.withValues(alpha: 0.10)
                : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? widget.cor.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.inventory_2, color: widget.cor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    children: [
                      if (identificador != null)
                        TextSpan(text: '$identificador · '),
                      TextSpan(text: m.nome),
                      if (detalhes.isNotEmpty)
                        TextSpan(text: ' · $detalhes'),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${formatarQuantidade(m.quantidade)} ${formatarUnidadeExibicao(m.unidade)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18,
                  color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────
// ABA "MATERIAIS SOLICITADOS": agrupamento por categoria + por nome parecido
// (ex.: "METALON 1234 bla blabla" sem categoria e "METALON bla bla bla"
// com categoria caem no mesmo grupo, e o grupo herda a categoria correta)
// ─────────────────────────────────────────────────────────────────────────
/// Um material "achatado", vindo de um item original OU de um adicional,
/// junto com o contexto da OS de onde ele veio.
class MaterialAchatadoSolicitado {
  final int materialId;
  final String nome;
  final String? categoria;
  final String? identificador;
  final String? medidaOuDimensao;
  final String? espessura;
  final String? unidade;
  final double quantidade;
  final bool resolvido; // comprado || estoque
  final String status; // 'PENDENTE' | 'COMPRADO' | 'ESTOQUE'
  final int solicitacaoId;
  final String numeroOS;
  final String nomeCliente;
  final String solicitanteNome;
  final DateTime dataSolicitacao;
  final DateTime dataNecessidade;

  MaterialAchatadoSolicitado({
    required this.materialId,
    required this.nome,
    required this.categoria,
    required this.identificador,
    required this.medidaOuDimensao,
    this.espessura,
    required this.unidade,
    required this.quantidade,
    required this.resolvido,
    required this.status,
    required this.solicitacaoId,
    required this.numeroOS,
    required this.nomeCliente,
    required this.solicitanteNome,
    required this.dataSolicitacao,
    required this.dataNecessidade,
  });

  /// Chave estável do material dentro de uma solicitação/adicional — usada
  /// para reconhecer o "mesmo" item entre rebuilds, já que a lista achatada
  /// é reconstruída a cada build() (novas instâncias). Combina a
  /// solicitação, o material e o momento em que foi adicionado (item
  /// original vs. adicional na mesma solicitação nunca coincidem nesse
  /// horário).
  @override
  bool operator ==(Object other) =>
      other is MaterialAchatadoSolicitado &&
      other.solicitacaoId == solicitacaoId &&
      other.materialId == materialId &&
      other.dataSolicitacao == dataSolicitacao;

  @override
  int get hashCode => Object.hash(solicitacaoId, materialId, dataSolicitacao);
}

/// Um grupo de materiais "equivalentes" (mesmo material na prática, com
/// possíveis diferenças de nome/categoria) dentro de uma categoria.
class GrupoMaterialSolicitado {
  /// Nome de exibição do grupo — o nome mais "completo/frequente" entre os
  /// materiais agrupados.
  final String nomeExibicao;
  final String? categoria;
  final List<MaterialAchatadoSolicitado> materiais;

  GrupoMaterialSolicitado({
    required this.nomeExibicao,
    required this.categoria,
    required this.materiais,
  });

  int get totalOcorrencias => materiais.length;
  int get totalPendentes => materiais.where((m) => !m.resolvido).length;
  int get totalResolvidos => materiais.where((m) => m.resolvido).length;

  /// Nomes/variações distintas que caíram nesse grupo (pra deixar visível
  /// pro usuário que, por ex., "METALON 1234" e "METALON bla" foram
  /// unificados).
  List<String> get variacoesDeNome =>
      materiais.map((m) => m.nome.trim()).toSet().toList()..sort();
}

/// Uma categoria com seus grupos de materiais.
class CategoriaAgrupada {
  final String categoria; // 'SEM CATEGORIA' quando nenhum item tem categoria
  final List<GrupoMaterialSolicitado> grupos;

  CategoriaAgrupada({required this.categoria, required this.grupos});

  int get totalMateriais =>
      grupos.fold(0, (soma, g) => soma + g.totalOcorrencias);
  int get totalPendentes =>
      grupos.fold(0, (soma, g) => soma + g.totalPendentes);
}

// ─────────────────────────────────────────────────────────────────────────
// ALGORITMO DE AGRUPAMENTO
// ─────────────────────────────────────────────────────────────────────────

const Map<String, String> _acentosMap = {
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
  'Ç': 'C', 'Ñ': 'N',
};

String _semAcentos(String s) {
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    buffer.write(_acentosMap[ch] ?? ch);
  }
  return buffer.toString();
}

/// Palavras genéricas demais para servirem de "assinatura" do material
/// (não ajudam a diferenciar nem a agrupar).
const Set<String> _stopwords = {
  'DE', 'DA', 'DO', 'E', 'PARA', 'COM', 'SEM', 'A', 'O', 'MM', 'CM', 'M',
};

/// Verifica se um token é "numérico/medida" (ex.: "1234", "20X20", "3/4",
/// "2.44X1.22M") — esses tokens ajudam a diferenciar variantes (medida
/// diferente), mas NÃO devem contar pra decidir se dois materiais são
/// diferentes o suficiente pra não agrupar; na prática servem só de
/// informação extra a mostrar.
bool _pareceMedidaOuCodigo(String token) {
  if (token.isEmpty) return false;
  final temDigito = RegExp(r'\d').hasMatch(token);
  if (!temDigito) return false;
  // Ex.: "1234", "20X20", "3/4", "2.44X1.22M", "M8"
  return RegExp(r'^[0-9]+([.,/X][0-9]+)*[A-Z]{0,3}$').hasMatch(token) ||
      RegExp(r'^[A-Z]{1,2}[0-9]+$').hasMatch(token);
}

/// Normaliza um nome de material para comparação: sem acento, maiúsculo,
/// espaços colapsados.
String _normalizar(String nome) {
  var s = _semAcentos(nome.toUpperCase());
  s = s.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Extrai a "assinatura" de um nome: o conjunto de palavras significativas
/// (ignorando stopwords e tokens de medida/código), na ORDEM em que
/// aparecem, mas usado como conjunto para comparação de similaridade.
/// Isso é o que permite que "METALON 1234 BLA BLABLA" e
/// "METALON BLA BLA BLA" sejam vistos como o mesmo material-base: os dois
/// têm a mesma palavra "forte" no começo (METALON) e conjuntos de palavras
/// com grande sobreposição, mesmo com medidas/códigos diferentes no meio.
List<String> _palavrasChave(String nomeNormalizado) {
  return nomeNormalizado
      .split(' ')
      .where((w) => w.isNotEmpty)
      .where((w) => !_stopwords.contains(w))
      .where((w) => !_pareceMedidaOuCodigo(w))
      .toList();
}

/// Similaridade de Jaccard entre dois conjuntos de palavras-chave.
double _similaridadeJaccard(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final setA = a.toSet();
  final setB = b.toSet();
  final inter = setA.intersection(setB).length;
  final uniao = setA.union(setB).length;
  if (uniao == 0) return 0;
  return inter / uniao;
}

/// Dois materiais são considerados "o mesmo, na prática" quando:
///  - a primeira palavra-chave (geralmente o "tipo" do material, ex.:
///    METALON, CHAPA, PARAFUSO) é igual — isso evita agrupar coisas
///    totalmente diferentes só por causa de palavras soltas em comum; E
///  - a similaridade de Jaccard entre as palavras-chave é >= o limiar.
bool _mesmoMaterial(List<String> chaveA, List<String> chaveB,
    {double limiar = 0.5}) {
  if (chaveA.isEmpty || chaveB.isEmpty) return false;
  if (chaveA.first != chaveB.first) return false;
  return _similaridadeJaccard(chaveA, chaveB) >= limiar;
}

/// Achata itens + adicionais de uma lista de solicitações em uma lista
/// única de materiais.
List<MaterialAchatadoSolicitado> _achatarMateriais(
    List<SolicitacaoMaterialModel> solicitacoes) {
  final resultado = <MaterialAchatadoSolicitado>[];
  for (final s in solicitacoes) {
    for (final item in s.itens) {
      resultado.add(MaterialAchatadoSolicitado(
        materialId: item.materialId,
        nome: item.materialNome,
        categoria: (item.materialCategoria?.trim().isEmpty ?? true)
            ? null
            : item.materialCategoria!.trim(),
        identificador: item.materialIdentificador,
        medidaOuDimensao: item.medidaOuDimensao,
        espessura: item.materialEspessura,
        unidade: item.materialUnidade,
        quantidade: item.quantidade,
        resolvido: item.resolvido,
        status: item.statusCompra,
        solicitacaoId: s.id,
        numeroOS: s.numeroOS,
        nomeCliente: s.nomeCliente,
        solicitanteNome: s.usuarioNome,
        dataSolicitacao: item.criadoEm,
        dataNecessidade: s.dataNecessidade,
      ));
    }
    for (final ad in s.adicionais) {
      resultado.add(MaterialAchatadoSolicitado(
        materialId: ad.materialId,
        nome: ad.materialNome,
        categoria: (ad.materialCategoria?.trim().isEmpty ?? true)
            ? null
            : ad.materialCategoria!.trim(),
        identificador: ad.materialIdentificador,
        medidaOuDimensao: ad.medidaOuDimensao,
        espessura: ad.materialEspessura,
        unidade: ad.materialUnidade,
        quantidade: ad.quantidade,
        resolvido: ad.resolvido,
        status: ad.statusCompra,
        solicitacaoId: s.id,
        numeroOS: s.numeroOS,
        nomeCliente: s.nomeCliente,
        solicitanteNome: s.usuarioNome,
        dataSolicitacao: ad.adicionadoEm,
        dataNecessidade: s.dataNecessidade,
      ));
    }
  }
  return resultado;
}

/// Ponto de entrada principal: recebe as solicitações em andamento e
/// devolve a lista de categorias já agrupadas e ordenadas (mais materiais
/// pendentes primeiro).
///
/// Regra de agrupamento (resolve o problema descrito):
///  1. Materiais são comparados pelo NOME (ignorando categoria) usando a
///     assinatura de palavras-chave.
///  2. Se dois (ou mais) materiais são considerados "o mesmo", eles formam
///     um único grupo — mesmo que estejam com categorias diferentes ou um
///     deles sem categoria.
///  3. A categoria final do grupo é a categoria mais frequente entre os
///     materiais do grupo (ou 'SEM CATEGORIA' se nenhum tiver).
///     Ou seja: um material sem categoria "herda" a categoria do grupo ao
///     qual foi associado por similaridade de nome.
List<CategoriaAgrupada> agruparMateriaisSolicitados(
    List<SolicitacaoMaterialModel> solicitacoesEmAndamento) {
  final materiais = _achatarMateriais(solicitacoesEmAndamento);

  // 1) Agrupa por similaridade de nome (independente de categoria).
  final grupos = <List<MaterialAchatadoSolicitado>>[];
  final chavesPorGrupo = <List<String>>[];

  for (final m in materiais) {
    final chave = _palavrasChave(_normalizar(m.nome));
    int? indiceEncontrado;
    for (var i = 0; i < grupos.length; i++) {
      if (_mesmoMaterial(chave, chavesPorGrupo[i])) {
        indiceEncontrado = i;
        break;
      }
    }
    if (indiceEncontrado != null) {
      grupos[indiceEncontrado].add(m);
      // Amplia a assinatura do grupo com a união das palavras-chave, para
      // que o grupo continue "pegando" variações levemente diferentes
      // conforme mais materiais entram (ex.: um 3º nome que é parecido com
      // o 2º mas não tanto com o 1º).
      chavesPorGrupo[indiceEncontrado] = {
        ...chavesPorGrupo[indiceEncontrado],
        ...chave,
      }.toList();
    } else {
      grupos.add([m]);
      chavesPorGrupo.add(chave);
    }
  }

  // 2) Para cada grupo, decide a categoria "vencedora" e o nome de
  // exibição (nome mais longo/completo, que tende a ser o mais descritivo).
  final gruposMontados = grupos.map((materiaisDoGrupo) {
    final contagemCategorias = <String, int>{};
    for (final m in materiaisDoGrupo) {
      if (m.categoria != null) {
        contagemCategorias[m.categoria!] =
            (contagemCategorias[m.categoria!] ?? 0) + 1;
      }
    }
    String? categoriaVencedora;
    var maiorContagem = 0;
    contagemCategorias.forEach((cat, qtd) {
      if (qtd > maiorContagem) {
        maiorContagem = qtd;
        categoriaVencedora = cat;
      }
    });

    final nomeExibicao = materiaisDoGrupo
        .map((m) => m.nome.trim())
        .reduce((a, b) => b.length > a.length ? b : a);

    return GrupoMaterialSolicitado(
      nomeExibicao: nomeExibicao,
      categoria: categoriaVencedora,
      materiais: materiaisDoGrupo,
    );
  }).toList();

  // 3) Organiza os grupos dentro de suas categorias.
  final porCategoria = <String, List<GrupoMaterialSolicitado>>{};
  for (final g in gruposMontados) {
    final chave = g.categoria ?? 'SEM CATEGORIA';
    porCategoria.putIfAbsent(chave, () => []).add(g);
  }

  final categorias = porCategoria.entries
      .map((e) => CategoriaAgrupada(categoria: e.key, grupos: e.value))
      .toList();

  // Ordena: categorias com mais pendências primeiro; 'SEM CATEGORIA' vai
  // sempre por último, já que é a "gaveta" que precisa de atenção do
  // cadastro, não uma categoria real.
  categorias.sort((a, b) {
    if (a.categoria == 'SEM CATEGORIA') return 1;
    if (b.categoria == 'SEM CATEGORIA') return -1;
    return b.totalPendentes.compareTo(a.totalPendentes);
  });

  for (final cat in categorias) {
    cat.grupos.sort((a, b) => b.totalPendentes.compareTo(a.totalPendentes));
  }

  return categorias;
}

// ─────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────

enum _ColunaOrdenavel { os, adicionado, necessidade, status }

const List<String> _ordemStatus = ['PENDENTE', 'COMPRADO', 'ESTOQUE'];

/// Como a listagem "Materiais Solicitados" está agrupada no momento.
/// O usuário escolhe pelos botões no topo da view.
enum _ModoAgrupamento { categoria, os, necessidade, status }

extension on _ModoAgrupamento {
  String get rotulo {
    switch (this) {
      case _ModoAgrupamento.categoria:
        return 'CATEGORIA';
      case _ModoAgrupamento.os:
        return 'OS';
      case _ModoAgrupamento.necessidade:
        return 'NECESSIDADE';
      case _ModoAgrupamento.status:
        return 'STATUS';
    }
  }

  IconData get icone {
    switch (this) {
      case _ModoAgrupamento.categoria:
        return Icons.label_outline;
      case _ModoAgrupamento.os:
        return Icons.assignment_outlined;
      case _ModoAgrupamento.necessidade:
        return Icons.event_outlined;
      case _ModoAgrupamento.status:
        return Icons.flag_outlined;
    }
  }
}

/// Um grupo genérico de materiais (usado por qualquer modo de agrupamento,
/// não só por categoria).
class _GrupoGenerico {
  final String titulo;
  final List<MaterialAchatadoSolicitado> materiais;
  const _GrupoGenerico({required this.titulo, required this.materiais});

  int get totalMateriais => materiais.length;
  int get totalPendentes => materiais.where((m) => !m.resolvido).length;
}

/// Data "de necessidade" truncada pro início do dia, usada como chave de
/// agrupamento (2 horários no mesmo dia caem no mesmo grupo).
DateTime _diaSemHora(DateTime d) => DateTime(d.year, d.month, d.day);

/// Reagrupa a lista já achatada de materiais de acordo com o modo escolhido
/// pelo usuário. Quando o modo é "categoria", delega pro agrupamento por
/// similaridade de nome já existente (agruparMateriaisSolicitados); nos
/// demais modos, agrupa de forma simples pela chave correspondente.
List<_GrupoGenerico> _agruparPorModo(
  List<SolicitacaoMaterialModel> solicitacoes,
  _ModoAgrupamento modo,
) {
  if (modo == _ModoAgrupamento.categoria) {
    final categorias = agruparMateriaisSolicitados(solicitacoes);
    return categorias
        .map((cat) => _GrupoGenerico(
              titulo: cat.categoria,
              materiais: cat.grupos.expand((g) => g.materiais).toList(),
            ))
        .toList();
  }

  final materiais = _achatarMateriais(solicitacoes);
  final formatoData = DateFormat('dd/MM/yyyy');
  final porChave = <String, List<MaterialAchatadoSolicitado>>{};
  final tituloPorChave = <String, String>{};

  for (final m in materiais) {
    String chave;
    String titulo;
    switch (modo) {
      case _ModoAgrupamento.os:
        chave = m.numeroOS;
        titulo = 'OS ${m.numeroOS} · ${m.nomeCliente}';
        break;
      case _ModoAgrupamento.necessidade:
        final dia = _diaSemHora(m.dataNecessidade);
        chave = dia.toIso8601String();
        titulo = formatoData.format(dia);
        break;
      case _ModoAgrupamento.status:
        chave = m.status;
        titulo = _statusVisual(m.status).label;
        break;
      case _ModoAgrupamento.categoria:
        chave = '';
        titulo = '';
        break;
    }
    porChave.putIfAbsent(chave, () => []).add(m);
    tituloPorChave[chave] = titulo;
  }

  final grupos = porChave.entries
      .map((e) => _GrupoGenerico(titulo: tituloPorChave[e.key]!, materiais: e.value))
      .toList();

  switch (modo) {
    case _ModoAgrupamento.os:
      grupos.sort((a, b) {
        if (a.totalPendentes != b.totalPendentes) {
          return b.totalPendentes.compareTo(a.totalPendentes);
        }
        return a.titulo.compareTo(b.titulo);
      });
      break;
    case _ModoAgrupamento.necessidade:
      grupos.sort((a, b) => a.materiais.first.dataNecessidade
          .compareTo(b.materiais.first.dataNecessidade));
      break;
    case _ModoAgrupamento.status:
      grupos.sort((a, b) => _ordemStatus
          .indexOf(a.materiais.first.status)
          .compareTo(_ordemStatus.indexOf(b.materiais.first.status)));
      break;
    case _ModoAgrupamento.categoria:
      break;
  }

  return grupos;
}

class MateriaisSolicitadosView extends StatefulWidget {
  final List<SolicitacaoMaterialModel> solicitacoes;
  /// Usadas apenas pelo tour "Como orçar materiais solicitados" para dar
  /// highlight no seletor "Agrupar por", no primeiro material listado e
  /// no botão "Orçar selecionados".
  final GlobalKey? tourKeyAgruparPor;
  final GlobalKey? tourKeyPrimeiroMaterial;
  final GlobalKey? tourKeyOrcarSelecionados;

  const MateriaisSolicitadosView({
    super.key,
    required this.solicitacoes,
    this.tourKeyAgruparPor,
    this.tourKeyPrimeiroMaterial,
    this.tourKeyOrcarSelecionados,
  });

  @override
  State<MateriaisSolicitadosView> createState() => _MateriaisSolicitadosViewState();
}

class _MateriaisSolicitadosViewState extends State<MateriaisSolicitadosView> {
  _ColunaOrdenavel? _coluna;
  bool _crescente = true;
  _ModoAgrupamento _modoAgrupamento = _ModoAgrupamento.categoria;

  /// Materiais (pendentes) selecionados pra enviar pra orçamento — mesmo
  /// padrão do "Orçar filtrados" (estoque) e "Orçar selecionados" (alertas
  /// de estoque no AppShell).
  final Set<MaterialAchatadoSolicitado> _selecionados = {};
  bool _orcandoSelecionados = false;

  void _alternarOrdenacao(_ColunaOrdenavel coluna) {
    setState(() {
      if (_coluna == coluna) {
        _crescente = !_crescente;
      } else {
        _coluna = coluna;
        _crescente = true;
      }
    });
  }

  void _toggleSelecao(MaterialAchatadoSolicitado m) {
    setState(() {
      if (_selecionados.contains(m)) {
        _selecionados.remove(m);
        return;
      }
      // Evita selecionar o mesmo material (mesmo materialId) mais de uma
      // vez — mesmo que apareça em OS/linhas diferentes, pra orçamento só
      // faz sentido entrar uma vez.
      final jaSelecionadoEmOutraLinha =
          _selecionados.any((s) => s.materialId == m.materialId);
      if (jaSelecionadoEmOutraLinha) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${m.nome} já está selecionado.'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      _selecionados.add(m);
    });
  }

  void _selecionarTodos(List<_GrupoGenerico> grupos) {
    final todosOsMateriais = grupos.expand((g) => g.materiais).toList();
    setState(() {
      final todosJaSelecionados =
          todosOsMateriais.isNotEmpty && todosOsMateriais.every(_selecionados.contains);
      if (todosJaSelecionados) {
        _selecionados.removeWhere(todosOsMateriais.contains);
      } else {
        // Ao selecionar tudo, mantém só a primeira ocorrência de cada
        // materialId — o mesmo material solicitado em OSs diferentes não
        // precisa (nem deve) entrar mais de uma vez no orçamento.
        final idsJaVistos = _selecionados.map((s) => s.materialId).toSet();
        for (final m in todosOsMateriais) {
          if (idsJaVistos.add(m.materialId)) {
            _selecionados.add(m);
          }
        }
      }
    });
  }

  bool _mesmoValor(String? a, String? b) {
    final ta = (a ?? '').trim().toUpperCase();
    final tb = (b ?? '').trim().toUpperCase();
    if (ta.isEmpty || tb.isEmpty) return true; // campo não informado → não restringe
    return ta == tb;
  }

  /// Envia os materiais selecionados pra um novo orçamento — replica o
  /// fluxo de "Orçar filtrados"/"Orçar selecionados" já usado em Estoque e
  /// nos Alertas de Estoque: casa cada material selecionado com o
  /// [MaterialModel] real (via materialId, com fallback por atributos),
  /// monta os [ItemOrcamentoData] com os preços por fornecedor já
  /// cadastrados, e navega para o editor de orçamento.
  Future<void> _orcarSelecionados() async {
    if (_selecionados.isEmpty || _orcandoSelecionados) return;
    setState(() => _orcandoSelecionados = true);

    try {
      final materialProvider = context.read<MaterialProvider>();
      // A página de Solicitações não carrega o MaterialProvider por conta
      // própria (só quem visita Estoque faz isso) — sem isso, a lista de
      // materiais fica vazia e nenhum item é localizado. Carrega sob
      // demanda aqui, uma única vez, antes de tentar casar os
      // selecionados.
      if (materialProvider.materiais.isEmpty) {
        await materialProvider.carregar();
        if (!mounted) return;
      }

      final todos = materialProvider.materiais;
      final itens = <ItemOrcamentoData>[];
      final naoEncontrados = <String>[];
      final jaAdicionados = <int>{};

      for (final m in _selecionados) {
        MaterialModel? encontrado;
        for (final mat in todos) {
          if (mat.id == m.materialId) {
            encontrado = mat;
            break;
          }
        }
        // Fallback: caso o materialId não bata (ex.: material
        // recadastrado), tenta localizar por atributos, igual ao "Orçar
        // selecionados" dos alertas de estoque.
        encontrado ??= todos.cast<MaterialModel?>().firstWhere(
              (mat) =>
                  mat != null &&
                  _mesmoValor(mat.nome, m.nome) &&
                  _mesmoValor(mat.categoria, m.categoria) &&
                  _mesmoValor(mat.identificador, m.identificador),
              orElse: () => null,
            );

        if (encontrado == null) {
          naoEncontrados.add(m.nome);
          continue;
        }
        if (!jaAdicionados.add(encontrado.id)) continue; // evita duplicar

        final precos = <int, PrecoFornecedorData>{};
        for (final fm in encontrado.fornecedorMateriais) {
          precos[fm.fornecedorId] = PrecoFornecedorData(
            fornecedorNome: fm.fornecedorNome,
            preco: fm.preco > 0 ? fm.preco : null,
          );
        }

        itens.add(ItemOrcamentoData(
          materialId: encontrado.id,
          materialNome: encontrado.nome,
          materialUnidade: encontrado.unidade,
          materialCategoria: encontrado.categoria,
          materialMedida: encontrado.medida,
          materialEspessura: encontrado.espessura,
          materialIdentificador: encontrado.identificador,
          materialStatus: encontrado.status,
          materialLargura: encontrado.largura,
          materialComprimento: encontrado.comprimento,
          estoqueMinimo: encontrado.estoqueMinimo,
          precos: precos,
        ));
      }

      if (!mounted) return;

      if (itens.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível localizar os materiais selecionados.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      final titulo = itens.length == 1
          ? 'Orç. ${itens.first.materialNome}'
          : 'Orç. materiais solicitados (${itens.length})';

      context.read<OrcamentoProvider>().adicionarItensEmLote(titulo, itens);

      if (naoEncontrados.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${naoEncontrados.length} material(is) não encontrado(s) e não foram incluídos: ${naoEncontrados.join(', ')}',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }

      setState(() => _selecionados.clear());

      // Ao entrar em /orcamento, abre direto no editor (aba "abertos") com
      // este orçamento recém-criado, em vez da lista de aprovação.
      OrcamentoPage.abrirEditorAoEntrar = true;
      context.go('/orcamento');
    } finally {
      if (mounted) setState(() => _orcandoSelecionados = false);
    }
  }

  int _comparar(MaterialAchatadoSolicitado a, MaterialAchatadoSolicitado b) {
    int resultado;
    switch (_coluna) {
      case _ColunaOrdenavel.os:
        final numA = int.tryParse(a.numeroOS);
        final numB = int.tryParse(b.numeroOS);
        resultado = (numA != null && numB != null)
            ? numA.compareTo(numB)
            : a.numeroOS.compareTo(b.numeroOS);
        break;
      case _ColunaOrdenavel.adicionado:
        resultado = a.dataSolicitacao.compareTo(b.dataSolicitacao);
        break;
      case _ColunaOrdenavel.necessidade:
        resultado = a.dataNecessidade.compareTo(b.dataNecessidade);
        break;
      case _ColunaOrdenavel.status:
        resultado = _ordemStatus.indexOf(a.status).compareTo(_ordemStatus.indexOf(b.status));
        break;
      case null:
        // Ordenação padrão: pendentes primeiro, depois por necessidade mais próxima.
        if (a.resolvido != b.resolvido) return a.resolvido ? 1 : -1;
        return a.dataNecessidade.compareTo(b.dataNecessidade);
    }
    return _crescente ? resultado : -resultado;
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _agruparPorModo(widget.solicitacoes, _modoAgrupamento);
    final totalMateriais = grupos.fold<int>(0, (soma, g) => soma + g.materiais.length);
    final todosSelecionados = totalMateriais > 0 &&
        grupos.expand((g) => g.materiais).every(_selecionados.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeyAgruparPor,
                  child: _SeletorAgrupamento(
                    modoAtivo: _modoAgrupamento,
                    onSelecionar: (modo) => setState(() => _modoAgrupamento = modo),
                  ),
                ),
              ),
              if (totalMateriais > 0) ...[
                TextButton.icon(
                  onPressed: () => _selecionarTodos(grupos),
                  icon: Icon(
                    todosSelecionados
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                  ),
                  label: Text(todosSelecionados
                      ? 'Desmarcar todos'
                      : 'Selecionar todos'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
                const SizedBox(width: 4),
                KeyedSubtree(
                  key: widget.tourKeyOrcarSelecionados,
                  child: OutlinedButton.icon(
                    onPressed: (_selecionados.isEmpty || _orcandoSelecionados)
                        ? null
                        : _orcarSelecionados,
                    icon: _orcandoSelecionados
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary),
                          )
                        : const Icon(Icons.request_quote, size: 16),
                    label: Text(_selecionados.isEmpty
                        ? 'Orçar selecionados'
                        : 'Orçar selecionados (${_selecionados.length})'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: grupos.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum material pendente nas solicitações em andamento',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: grupos.length,
                  itemBuilder: (context, index) {
                    final grupo = grupos[index];
                    final semCategoria = _modoAgrupamento == _ModoAgrupamento.categoria &&
                        grupo.titulo == 'SEM CATEGORIA';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                semCategoria
                                    ? Icons.label_off_outlined
                                    : _modoAgrupamento.icone,
                                size: 18,
                                color: semCategoria ? AppTheme.error : AppTheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                grupo.titulo,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: semCategoria
                                      ? AppTheme.error
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _TabelaMateriaisCategoria(
                            materiais: [...grupo.materiais]..sort(_comparar),
                            colunaAtiva: _coluna,
                            crescente: _crescente,
                            onOrdenar: _alternarOrdenacao,
                            selecionados: _selecionados,
                            onToggleSelecao: _toggleSelecao,
                            // Só o primeiro material do primeiro grupo
                            // recebe a key do tour "Como orçar materiais
                            // solicitados" — é sempre o primeiro item
                            // visível na lista, independente do modo de
                            // agrupamento ativo.
                            tourKeyPrimeiraLinha:
                                index == 0 ? widget.tourKeyPrimeiroMaterial : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Botões de segmento no topo da view, pra escolher por qual critério os
/// materiais devem ser agrupados (categoria, OS, necessidade ou status).
class _SeletorAgrupamento extends StatelessWidget {
  final _ModoAgrupamento modoAtivo;
  final void Function(_ModoAgrupamento) onSelecionar;

  const _SeletorAgrupamento({
    required this.modoAtivo,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    final corBorda = Theme.of(context).colorScheme.outlineVariant;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Agrupar por:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              border: Border.all(color: corBorda),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _ModoAgrupamento.values.map((modo) {
                final ativo = modo == modoAtivo;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color: ativo
                        ? AppTheme.primary.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () => onSelecionar(modo),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              modo.icone,
                              size: 14,
                              color: ativo
                                  ? AppTheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              modo.rotulo,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: ativo
                                    ? AppTheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cor/ícone/rótulo de cada status de compra, reaproveitado na tabela.
class _StatusVisual {
  final Color cor;
  final IconData icone;
  final String label;
  const _StatusVisual(this.cor, this.icone, this.label);
}

_StatusVisual _statusVisual(String status) {
  switch (status) {
    case 'COMPRADO':
      return const _StatusVisual(AppTheme.success, Icons.shopping_cart, 'COMPRADO');
    case 'ESTOQUE':
      return const _StatusVisual(Colors.blue, Icons.inventory_2, 'ESTOQUE');
    default:
      return const _StatusVisual(AppTheme.primary, Icons.schedule, 'PENDENTE');
  }
}

/// Formata "quantidade + unidade" com espaço e unidade no padrão de
/// exibição correto (ex.: "2 unidade"), em vez de grudado e em maiúsculas.
String _formatarQuantidadeUnidade(double quantidade, String? unidade) {
  final qtd = formatarQuantidade(quantidade);
  if (unidade == null || unidade.trim().isEmpty) return qtd;
  return '$qtd ${formatarUnidadeExibicao(unidade)}';
}

class _TabelaMateriaisCategoria extends StatelessWidget {
  final List<MaterialAchatadoSolicitado> materiais;
  final _ColunaOrdenavel? colunaAtiva;
  final bool crescente;
  final void Function(_ColunaOrdenavel) onOrdenar;
  final Set<MaterialAchatadoSolicitado> selecionados;
  final void Function(MaterialAchatadoSolicitado) onToggleSelecao;
  /// Usada apenas pelo tour "Como orçar materiais solicitados" para dar
  /// highlight na primeira linha desta tabela (só é passada pra tabela do
  /// primeiro grupo — ver `MateriaisSolicitadosView`).
  final GlobalKey? tourKeyPrimeiraLinha;

  const _TabelaMateriaisCategoria({
    required this.materiais,
    required this.colunaAtiva,
    required this.crescente,
    required this.onOrdenar,
    required this.selecionados,
    required this.onToggleSelecao,
    this.tourKeyPrimeiraLinha,
  });

  @override
  Widget build(BuildContext context) {
    final corBorda = Theme.of(context).colorScheme.outlineVariant;
    final formatoData = DateFormat('dd/MM/yyyy');

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: corBorda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho da tabela ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(bottom: BorderSide(color: corBorda)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 32),
                const Expanded(flex: 3, child: _CelulaCabecalho('MATERIAL')),
                Expanded(
                  flex: 3,
                  child: _CelulaCabecalho(
                    'OS',
                    coluna: _ColunaOrdenavel.os,
                    colunaAtiva: colunaAtiva,
                    crescente: crescente,
                    onTap: onOrdenar,
                  ),
                ),
                const Expanded(flex: 2, child: _CelulaCabecalho('SOLICITANTE')),
                const Expanded(flex: 2, child: _CelulaCabecalho('QTD. SOLICITADA')),
                Expanded(
                  flex: 2,
                  child: _CelulaCabecalho(
                    'ADICIONADO',
                    coluna: _ColunaOrdenavel.adicionado,
                    colunaAtiva: colunaAtiva,
                    crescente: crescente,
                    onTap: onOrdenar,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _CelulaCabecalho(
                    'NECESSIDADE',
                    coluna: _ColunaOrdenavel.necessidade,
                    colunaAtiva: colunaAtiva,
                    crescente: crescente,
                    onTap: onOrdenar,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _CelulaCabecalho(
                    'STATUS',
                    coluna: _ColunaOrdenavel.status,
                    colunaAtiva: colunaAtiva,
                    crescente: crescente,
                    onTap: onOrdenar,
                  ),
                ),
              ],
            ),
          ),
          // ── Linhas ────────────────────────────────────────────────────────
          ...materiais.asMap().entries.map((entry) {
            final ultima = entry.key == materiais.length - 1;
            final m = entry.value;
            final visual = _statusVisual(m.status);
            final detalhes = [
              if (m.identificador != null && m.identificador!.trim().isNotEmpty)
                m.identificador!.trim(),
              if (m.medidaOuDimensao != null) m.medidaOuDimensao!,
              if (formatarEspessuraComSufixo(m.espessura) != null)
                formatarEspessuraComSufixo(m.espessura)!,
            ].join(' · ');

            final selecionado = selecionados.contains(m);
            final primeira = entry.key == 0;

            return KeyedSubtree(
              key: primeira ? tourKeyPrimeiraLinha : null,
              child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () => onToggleSelecao(m),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selecionado ? AppTheme.primary.withValues(alpha: 0.06) : null,
                border: ultima ? null : Border(bottom: BorderSide(color: corBorda)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Checkbox(
                      value: selecionado,
                      onChanged: (_) => onToggleSelecao(m),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.nome,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                        if (detalhes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(detalhes,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('OS ${m.numeroOS}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                        Text(m.nomeCliente,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      m.solicitanteNome,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _formatarQuantidadeUnidade(m.quantidade, m.unidade),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      formatoData.format(m.dataSolicitacao),
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      formatoData.format(m.dataNecessidade),
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: visual.cor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(visual.icone, size: 13, color: visual.cor),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              visual.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: visual.cor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CelulaCabecalho extends StatelessWidget {
  final String texto;
  final _ColunaOrdenavel? coluna;
  final _ColunaOrdenavel? colunaAtiva;
  final bool crescente;
  final void Function(_ColunaOrdenavel)? onTap;

  const _CelulaCabecalho(
    this.texto, {
    this.coluna,
    this.colunaAtiva,
    this.crescente = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final corPadrao = Theme.of(context).colorScheme.onSurfaceVariant;
    final ativa = coluna != null && coluna == colunaAtiva;
    final cor = ativa ? AppTheme.primary : corPadrao;

    final conteudo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            texto,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: cor,
            ),
          ),
        ),
        if (coluna != null) ...[
          const SizedBox(width: 2),
          Icon(
            ativa
                ? (crescente ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.unfold_more,
            size: 12,
            color: ativa ? AppTheme.primary : corPadrao.withValues(alpha: 0.5),
          ),
        ],
      ],
    );

    if (coluna == null || onTap == null) return conteudo;

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => onTap!(coluna!),
      child: conteudo,
    );
  }
}