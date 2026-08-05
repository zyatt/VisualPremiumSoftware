import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/fornecedor_model.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/orcamento_provider.dart';
import '../providers/robo_helper_provider.dart';
import '../repositories/orcamento_repository.dart';
import '../theme/app_theme.dart';
import 'orcamento_historico_page.dart';
import 'orcamento_editor_page.dart';

// ─── Log de diagnóstico (rastreável em produção) ─────────────────────────────
// Mesmo padrão usado em orcamento_editor_page.dart: dev.log() em vez de
// print() porque fica disponível mesmo em build release e já carrega
// timestamp. Use grep por "OrcamentoPage" no log do app para filtrar.
void _logOrc(String mensagem, {Object? erro, StackTrace? stack, int? level}) {
  dev.log(
    mensagem,
    time: DateTime.now(),
    name: 'OrcamentoPage',
    error: erro,
    stackTrace: stack,
    level: level ?? 0,
  );
}

/// Converte um valor vindo de JSON (pode ser String, int, double ou null)
/// para double de forma segura, sem lançar exceção de cast.
double? _parseDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final str = value.toString().trim();
  if (str.isEmpty) return null;
  return double.tryParse(str);
}

/// Formata a dimensão (largura x comprimento) de um material como "50x1.27m",
/// mesma convenção usada em [OrcamentoEditorPage] (comprimento x largura,
/// minúsculo). Retorna null se largura/comprimento não estiverem cadastrados.
String? _materialDimensaoFormatada(double? largura, double? comprimento) {
  if (largura == null || comprimento == null || largura <= 0 || comprimento <= 0) return null;
  String fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  return '${fmt(comprimento)}x${fmt(largura)}m';
}

/// Remove prefixos como "Exception:", "HttpException:" que o Dart adiciona
/// automaticamente ao fazer e.toString() em exceções. Quando o erro é de
/// conexão (sem internet / servidor fora do ar), retorna uma mensagem
/// amigável contextualizada com a ação que estava sendo feita.
String _mensagemErro(Object e, {required String acao}) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Erro ao $acao: Verifique a conexão com o servidor.';
  }
  final msg = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
  return 'Erro ao $acao: $msg';
}

// Detecta se o erro veio de uma validação de status no backend (ex: outro
// usuário já aprovou/rejeitou/enviou este orçamento antes desta ação ser
// confirmada). Textos exatos lançados por orcamento.service.js.
bool _isErroDeStatusDesatualizado(Object e) {
  final raw = e.toString();
  return raw.contains('Apenas orçamentos abertos podem ser enviados') ||
      raw.contains('Apenas orçamentos aguardando aprovação podem ser aprovados') ||
      raw.contains('Apenas orçamentos aguardando aprovação podem ser rejeitados') ||
      raw.contains('Apenas orçamentos aprovados');
}
// ─── Formatters ───────────────────────────────

/// Bloqueia a digitação de vírgula em campos de texto livre (busca, título, descrição, etc.)
class _NoCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.contains(',')) {
      return oldValue;
    }
    return newValue;
  }
}

Widget _badgeContagem(int contagem) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$contagem',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.primary,
      ),
    ),
  );
}

class OrcamentoPage extends StatefulWidget {
  const OrcamentoPage({super.key});

  static bool abrirEditorAoEntrar = false;

  @override
  State<OrcamentoPage> createState() => _OrcamentoPageState();
}

class _OrcamentoPageState extends State<OrcamentoPage>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;

  // ── Dados server-side ─────────────────────────────────────────────────────
  List<dynamic> _aguardandoAprovacao = [];
  List<dynamic> _aprovados = [];
  List<dynamic> _naoAprovados = [];
  bool _carregandoAprovacao = false;
  String? _erroAprovacao;

  bool _salvandoPreco = false;
  // (flags de edição foram movidos para OrcamentoTab no provider)

  // Modo de ordenação da tabela de totais por fornecedor

  // _abaVisivel controla a visibilidade do editor inline (quando usado)

  // ── Robô assistente: tour "Como criar um orçamento" ───────────────────────
  // Este tour é especial: começa aqui (destaque no botão "Novo Orçamento")
  // mas continua dentro do OrcamentoEditorPage, aberto via Navigator.push
  // por CIMA desta página (não troca de rota do RoboHelperProvider — ver
  // comentário em _registrarAjudaRobo). Por isso a tela do editor registra
  // as próprias paradas na MESMA rota '/orcamento' desta página, e o botão
  // "Novo Orçamento" abaixo apenas garante que uma aba/editor esteja aberto
  // quando o tour chega nessa parada.
  final _tourKeyNovoOrcamento = GlobalKey();

  @override
  void initState() {
    super.initState();
    _logOrc('initState');
    _mainTabController = TabController(length: 3, vsync: this);
    _mainTabController.addListener(() {
      if (_mainTabController.indexIsChanging) return;
      _carregarOrcamentosServidor(origem: 'trocaDeTabPrincipal');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FornecedorProvider>().carregar();
      _carregarOrcamentosServidor(origem: 'initState');
      context.read<RoboHelperProvider>().notificarRota('/orcamento');
    });
  }

  @override
  void dispose() {
    _logOrc('dispose');
    _mainTabController.dispose();
    try {
      context.read<RoboHelperProvider>().encerrarTour();
      context.read<RoboHelperProvider>().limparOpcoes('/orcamento');
    } catch (_) {}
    super.dispose();
  }

  // Evita empurrar o OrcamentoEditorPage mais de uma vez enquanto o tour
  // navega rapidamente entre a 1ª e a 2ª parada (ex.: clique duplo em
  // "Próximo"). Mesmo padrão de guarda usado em fornecedores_page.dart e
  // solicitacoes_material_page.dart para os dialogs abertos pelo tour.
  bool _editorTourAberto = false;

  /// Abre (ou reaproveita) o OrcamentoEditorPage para o tour continuar lá
  /// dentro — chamado pelo `aoEntrar` da 2ª parada do tour "Como criar um
  /// orçamento". Equivalente a tocar no botão "Novo Orçamento", mas
  /// disparado programaticamente pelo tour (o highlight nunca clica no
  /// widget de baixo — ver _HighlightOverlay em robo_helper_widget.dart).
  ///
  /// IMPORTANTE: este Future NÃO pode esperar o Navigator.push inteiro
  /// (ou seja, até o editor ser fechado/popado). O RoboHelperProvider
  /// (proximaParada/paradaAnterior) faz `await parada.aoEntrar?.call()`
  /// e, enquanto esse await não resolve, mantém `_navegando = true` —
  /// bloqueando Próximo/Anterior. Como antes aguardávamos o
  /// Navigator.push inteiro, o tour ficava travado na parada do campo
  /// Nome pelo tempo inteiro que o editor estivesse aberto — só "Fechar"
  /// funcionava, porque encerrarTour() não passa por esse guard. Agora
  /// só aguardamos o suficiente para o editor montar (garantindo que a
  /// próxima key já exista na árvore) e tratamos o retorno do editor
  /// (_aoVoltarDoEditor) de forma desacoplada, via .then(), sem bloquear
  /// o tour.
  Future<void> _abrirEditorTour() async {
    if (_editorTourAberto) return;
    _editorTourAberto = true;
    final p = context.read<OrcamentoProvider>();
    p.adicionarAba(criadaPeloTour: true);
    final pushFuture = Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
    );
    // Quando o editor for eventualmente fechado (usuário concluindo o
    // tour, cancelando, ou saindo antes), trata o retorno normalmente —
    // mas sem travar o aoEntrar/tour enquanto isso não acontece.
    pushFuture.then((resultado) async {
      if (mounted) _editorTourAberto = false;
      if (mounted) await _aoVoltarDoEditor(resultado);
    });
    // Em vez de um delay fixo (que falhava sempre que a transição de rota
    // demorasse mais que o esperado — animação de push do MaterialPageRoute
    // é ~300ms — deixando o overlay escurecer a tela sem achar
    // criarOrcamentoTourKeyCampoNome, porque tentou medir a key antes do
    // editor terminar de montar), aguardamos ativamente a key do campo
    // Nome passar a existir na árvore, checando a cada frame. Isso cobre
    // tanto o caso rápido (poucos frames) quanto o mais lento (device/
    // build mais pesado) sem nunca esperar mais que o necessário.
    const tentativasMax = 30; // ~30 frames (até a transição normal terminar)
    for (var i = 0; i < tentativasMax; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (criarOrcamentoTourKeyBlocoFiltros.currentContext != null) break;
    }
  }

  Future<void> _fecharEditorTourSeAberto() async {
    if (!_editorTourAberto) return;
    _editorTourAberto = false;
    // Fecha a aba criada pelo tour antes de fechar o editor — mesma
    // lógica de _onRoboHelperPaginaChanged no editor, mas disparada aqui
    // quando o Anterior é clicado na 2ª parada (blocoFiltros), que ainda
    // está nesta página (rota '/orcamento'). Sem isso, o editor fecha mas
    // a aba criada automaticamente pelo tour fica aberta, vazia.
    try {
      context.read<OrcamentoProvider>().fecharAbaAposOperacao();
    } catch (_) {}
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// Registra no RoboHelperProvider a opção de ajuda contextual desta
  /// página. Chamado a cada build (barato) para garantir que a primeira
  /// parada sempre aponte para a key correta. As demais paradas (dentro do
  /// OrcamentoEditorPage) são ANEXADAS a esta mesma opção pelo próprio
  /// editor, assim que ele é montado — ver `_anexarParadasDoEditorAoTour`
  /// em orcamento_editor_page.dart. Isso funciona porque o editor é aberto
  /// via Navigator.push (não troca a rota do RoboHelperProvider, que
  /// continua '/orcamento' o tempo todo) e o overlay do tour usa
  /// `isActive` (não `isCurrent`) para decidir se o alvo ainda é válido —
  /// então o tour sobrevive à navegação para a tela de cima.
  void _registrarAjudaRobo() {
    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isCurrent) return;

    final helper = context.read<RoboHelperProvider>();

    // Preserva paradas extras já anexadas por OrcamentoEditorPage
    // (_anexarParadasDoEditorAoTour). Como o editor é empurrado por CIMA
    // desta página via Navigator.push, esta página continua montada e seu
    // build (logo, este postFrameCallback) continua rodando em segundo
    // plano. Se sempre reescrevêssemos a opção só com as 2 paradas base,
    // toda vez que esta página rebuildasse depois do editor já ter
    // anexado o restante, a lista voltaria a ter só 2 paradas — e o tour
    // ficaria preso na 2ª (campo Nome), sempre mostrando "Concluir" ali,
    // porque _anexarParadasDoEditorAoTour desiste de reanexar quando
    // encontra MAIS que as 2 paradas base (evita duplicar/perder o
    // RoboTourStop em que o usuário estiver no meio do tour) — só que
    // aqui o problema é o oposto: menos que o esperado, nunca mais.
    final opcoesAtuais = helper.opcoesAtuais;
    final opcaoExistente =
        opcoesAtuais.where((o) => o.titulo == 'Como criar um orçamento').firstOrNull;

    // CRÍTICO: se o editor já anexou as paradas extras (opção com mais de
    // 2 paradas), esta página NÃO deve reescrever a opção enquanto o tour
    // estiver ativo E o passo atual já estiver dentro do território do
    // editor (índice >= 2). Antes desta guarda, este método rodava a cada
    // build desta página (que continua rebuildando em segundo plano
    // mesmo com o editor empurrado por cima, ex.: por notificações do
    // OrcamentoProvider) e SEMPRE chamava helper.registrarOpcoes(...) de
    // novo, mesmo already-correto. Isso por si não apagava as paradas
    // extras (paradasExtras as preservava), mas cada chamada é uma
    // reescrita completa da lista + um notifyListeners() — e se essa
    // reescrita corresse EXATAMENTE durante a janela em que
    // RoboHelperProvider.paradaAnterior() está no meio de um `await
    // aoSair(...)` (lendo `helper.opcoesAtuais` OUTRA vez logo depois,
    // em `_paradaEm`), a alternância entre "lista antiga" e "lista recém
    // reconstruída" podia fazer `_paradaEm(novoIndice)` observar um
    // estado intermediário mais curto que o esperado, levando o provider
    // a concluir (erroneamente) que a lista "encolheu" e encerrar o tour
    // (`_encerrarTourInterno()`) — fechando o editor e a aba, exatamente
    // o bug relatado ao clicar "Anterior" na parada "primeiroFornecedorDialog".
    // Pular a reescrita aqui enquanto o editor already possui e está
    // gerenciando as paradas extras elimina essa fonte de corrida: quem
    // manda na opção nesse momento é só o editor
    // (_anexarParadasDoEditorAoTour), nunca esta página.
    final editorJaAnexouExtras =
        opcaoExistente != null && opcaoExistente.paradas.length > 2;
    final tourDentroDoEditor = helper.tourAtivo && helper.passoAtual >= 2;
    if (editorJaAnexouExtras && tourDentroDoEditor) return;

    final paradasExtras = editorJaAnexouExtras
        ? opcaoExistente.paradas.sublist(2)
        : const <RoboTourStop>[];

    helper.registrarOpcoes('/orcamento', [
      RoboHelpOption(
        titulo: 'Como criar um orçamento',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyNovoOrcamento,
            texto: 'Toque aqui para começar um novo orçamento de compras.',
          ),
          RoboTourStop(
            key: () => criarOrcamentoTourKeyBlocoFiltros,
            texto: 'Use estes campos para filtrar o material desejado: '
                'nome, identificador, medida, comprimento, largura ou '
                'espessura.',
            aoEntrar: _abrirEditorTour,
            aoSair: _fecharEditorTourSeAberto,
          ),
          ...paradasExtras,
        ],
        // Garante que encerrar o tour (ESC, "Fechar" ou "Concluir") a
        // partir de QUALQUER parada dentro do editor (3ª em diante — ver
        // orcamento_editor_page.dart) também feche o editor e devolva o
        // usuário para esta página. Sem isto, o aoSair de cada parada só
        // fechava o dialog daquela parada específica (fornecedor ou
        // preço), deixando o editor inteiro aberto na tela.
        aoEncerrar: _fecharEditorTourSeAberto,
      ),
    ]);
  }

  // ── Retorno do editor de orçamento ───────────────────────────────────────────
  // Chamado sempre que o OrcamentoEditorPage é fechado (Navigator.pop). Se o
  // orçamento foi enviado para aprovação, foca a aba "Aguardando Aprovação"
  // (índice 0); se foi aprovado, foca a aba "Aprovados" (índice 1) — sempre
  // antes de recarregar os dados do servidor, para que o usuário veja
  // imediatamente o orçamento que acabou de mexer.
  Future<void> _aoVoltarDoEditor(dynamic resultado) async {
    if (!mounted) return;
    int? abaAlvo;
    if (resultado == 'enviadoParaAprovacao') {
      abaAlvo = 0;
    } else if (resultado == 'aprovado') {
      abaAlvo = 1;
    }
    if (abaAlvo != null && _mainTabController.index != abaAlvo) {
      _mainTabController.animateTo(abaAlvo);
    }
    await _carregarOrcamentosServidor(origem: 'voltaDoEditor');
  }

  // ── Carregar orçamentos do servidor ──────────────────────────────────────────

  Future<void> _carregarOrcamentosServidor({String origem = 'manual'}) async {
    if (!mounted) return;
    if (_carregandoAprovacao) {
      // Já existe um carregamento em andamento (ex: o listener de troca de
      // aba do TabController disparou quase ao mesmo tempo que o
      // postFrameCallback do initState, ou o usuário clicou em "Atualizar"
      // mais de uma vez seguida). Evita empilhar requisições idênticas.
      _logOrc('carregarOrcamentosServidor[$origem]: ignorado (já existe um carregamento em andamento)');
      return;
    }
    final inicio = DateTime.now();
    _logOrc('carregarOrcamentosServidor[$origem]: iniciando (3 GETs: AGUARDANDO_APROVACAO/APROVADO/NAO_APROVADO)');
    setState(() {
      _carregandoAprovacao = true;
      _erroAprovacao = null;
    });
    try {
      final repo = OrcamentoRepository();
      final aguardando = await repo.listar(status: 'AGUARDANDO_APROVACAO');
      final aprovados = await repo.listar(status: 'APROVADO');
      final naoAprovados = await repo.listar(status: 'NAO_APROVADO');
      if (!mounted) {
        _logOrc('carregarOrcamentosServidor[$origem]: resposta chegou mas widget já foi desmontado, ignorando');
        return;
      }
      _logOrc('carregarOrcamentosServidor[$origem]: sucesso em ${DateTime.now().difference(inicio).inMilliseconds}ms '
          '(aguardando=${aguardando.length}, aprovados=${aprovados.length}, naoAprovados=${naoAprovados.length})');
      setState(() {
        _aguardandoAprovacao = aguardando;
        _aprovados = aprovados;
        _naoAprovados = naoAprovados;
      });
    } catch (e, st) {
      _logOrc('carregarOrcamentosServidor[$origem]: ERRO após ${DateTime.now().difference(inicio).inMilliseconds}ms',
          erro: e, stack: st, level: 1000);
      if (mounted) setState(() => _erroAprovacao = _mensagemErro(e, acao: 'carregar orçamentos'));
    } finally {
      _logOrc('carregarOrcamentosServidor[$origem]: finally, mounted=$mounted');
      if (mounted) setState(() => _carregandoAprovacao = false);
    }
  }

  // ── Enviar para aprovação ─────────────────────────────────────────────────────


  // ── Aprovar orçamento ─────────────────────────────────────────────────────────

  Future<void> _aprovarOrcamento(int id, String titulo) async {
    _logOrc('aprovarOrcamento(lista): botão clicado orcamentoId=$id titulo="$titulo"');
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar Orçamento',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text(
          'Deseja aprovar este orçamento?\n\n'
          'Após a aprovação, o usuário Compras poderá gerar uma Ordem de Compra.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    _logOrc('aprovarOrcamento(lista): diálogo fechado, resultado=$confirmar orcamentoId=$id');
    if (confirmar != true) return;

    final inicio = DateTime.now();
    try {
      _logOrc('aprovarOrcamento(lista): chamando PATCH /orcamentos/$id/aprovar');
      await OrcamentoRepository().aprovar(id);
      _logOrc('aprovarOrcamento(lista): sucesso em ${DateTime.now().difference(inicio).inMilliseconds}ms orcamentoId=$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$id aprovado com sucesso!'),
          backgroundColor: AppTheme.success,
        ),
      );
      if (_mainTabController.index != 1) {
        _mainTabController.animateTo(1);
      }
      await _carregarOrcamentosServidor(origem: 'aposAprovar');
    } catch (e, st) {
      _logOrc('aprovarOrcamento(lista): ERRO após ${DateTime.now().difference(inicio).inMilliseconds}ms orcamentoId=$id',
          erro: e, stack: st, level: 1000);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isErroDeStatusDesatualizado(e)
                  ? 'O status deste orçamento mudou (outra pessoa já alterou). A lista foi atualizada.'
                  : _mensagemErro(e, acao: 'aprovar orçamento'),
            ),
            backgroundColor: AppTheme.error,
          ),
        );
        if (_isErroDeStatusDesatualizado(e)) {
          await _carregarOrcamentosServidor(origem: 'erroAprovar');
        }
      }
    }
  }

  // ── Rejeitar orçamento ────────────────────────────────────────────────────────

  Future<void> _rejeitarOrcamento(int id, String titulo) async {
    final motivoCtrl = TextEditingController();
    bool mostrarErro = false;
    
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Rejeitar Orçamento',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informe o motivo da rejeição do orçamento "$titulo":',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Motivo *',
                  isDense: true,
                  errorText: mostrarErro && motivoCtrl.text.trim().isEmpty
                      ? 'O motivo é obrigatório'
                      : null,
                ),
                onChanged: (_) {
                  if (mostrarErro) {
                    setSt(() => mostrarErro = false);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () {
                if (motivoCtrl.text.trim().isEmpty) {
                  setSt(() => mostrarErro = true);
                  return;
                }
                Navigator.pop(ctx, motivoCtrl.text.trim());
              },
              child: const Text('Rejeitar'),
            ),
          ],
        ),
      ),
    );
    if (motivo == null || motivo.isEmpty) return;

    try {
      await OrcamentoRepository().rejeitar(id, motivo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$id rejeitado.'),
          backgroundColor: AppTheme.error,
        ),
      );
      await _carregarOrcamentosServidor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isErroDeStatusDesatualizado(e)
                  ? 'O status deste orçamento mudou (outra pessoa já alterou). A lista foi atualizada.'
                  : _mensagemErro(e, acao: 'rejeitar orçamento'),
            ),
            backgroundColor: AppTheme.error,
          ),
        );
        if (_isErroDeStatusDesatualizado(e)) {
          await _carregarOrcamentosServidor();
        }
      }
    }
  }

  // ── Gerar OC a partir de orçamento aprovado ───────────────────────────────────
  // Abre o orçamento no editor com modoGerarOC=true para que a OC seja gerada
  // de lá, após o usuário selecionar os fornecedores desejados.

  Future<void> _gerarOCDeOrcamentoAprovado(Map<String, dynamic> orc) async {
    final provider = context.read<OrcamentoProvider>();
    final orcId = orc['id'] as int;

    // Se já existe uma aba aberta com esse servidorId, apenas navega para ela
    final abaExistente = provider.ativarAbaExistente(orcId);
    if (abaExistente >= 0) {
      if (mounted) {
        final resultado = await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
        );
        await _aoVoltarDoEditor(resultado);
      }
      return;
    }

    setState(() => _salvandoPreco = true);
    try {
      // Busca o orçamento completo sem alterar o status no servidor
      final orcamentoCompleto = await OrcamentoRepository().buscarPorId(orcId);
      final itens = (orcamentoCompleto['itens'] as List? ?? []);

      final Map<int, ItemOrcamentoData> itensPorChave = {};

      for (final item in itens) {
        final materialId = item['materialId'] as int;
        final materialData = item['material'] as Map<String, dynamic>?;
        final fornecedorId = item['fornecedorId'] as int?;
        final fornecedorData = item['fornecedor'] as Map<String, dynamic>?;

        if (!itensPorChave.containsKey(materialId)) {
          itensPorChave[materialId] = ItemOrcamentoData(
            materialId: materialId,
            materialNome: materialData?['nome'] as String? ?? '',
            materialUnidade: materialData?['unidade'] as String?,
            materialMedida: materialData?['medida'] as String?,
            materialEspessura: materialData?['espessura'] as String?,
            materialIdentificador: materialData?['identificador'] as String?,
            materialCategoria: materialData?['categoria'] as String?,
            quantidade: double.tryParse(item['quantidade'].toString()) ?? 1,
            qtdUnidade: item['qtdUnidade'] != null ? double.tryParse(item['qtdUnidade'].toString()) : null,
            precos: {},
          );
        }

        if (fornecedorId != null && fornecedorData != null) {
          itensPorChave[materialId]!.precos[fornecedorId] = PrecoFornecedorData(
            fornecedorNome: fornecedorData['nomeFantasia'] as String? ?? '',
            preco: item['precoUnitario'] != null
                ? double.tryParse(item['precoUnitario'].toString())
                : null,
            observacao: item['observacao'] as String?,
          );

          if (item['selecionado'] as bool? ?? false) {
            itensPorChave[materialId]!.fornecedorSelecionado = fornecedorId;
          }
        }
      }

      if (!mounted) return;

      provider.adicionarItensEmLote(
        orcamentoCompleto['titulo'] as String? ?? 'Orçamento #$orcId',
        itensPorChave.values.toList(),
      );

      provider.setServidorIdTab(orcId);
      provider.setFornecedoresOcultosTab(
        (orcamentoCompleto['fornecedoresOcultos'] as List? ?? []).map((e) => e as int).toList(),
      );
      provider.definirModoPrecificacao(orcamentoCompleto['modoPrecificacao'] as String? ?? 'UNIDADE');
      // jaFinalizado=true mantém o orçamento somente-leitura, modoGerarOC=true
      // exibe o botão "Gerar OC" no editor.
      provider.atualizarFlagsTab(jaFinalizado: true, modoGerarOC: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$orcId aberto. Selecione os fornecedores e gere a OC.'),
          backgroundColor: AppTheme.success,
        ),
      );

      final resultado = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
      );
      await _aoVoltarDoEditor(resultado);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'abrir orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  // ── Reabrir orçamento ─────────────────────────────────────────────────────────

  Future<void> _reabrirOrcamento(Map<String, dynamic> orc) async {
    final provider = context.read<OrcamentoProvider>();
    final orcId = orc['id'] as int;

    // Se já existe uma aba aberta com esse servidorId, apenas navega para ela
    final abaExistente = provider.ativarAbaExistente(orcId);
    if (abaExistente >= 0) {
      if (mounted) {
        final resultado = await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
        );
        await _aoVoltarDoEditor(resultado);
      }
      return;
    }

    setState(() => _salvandoPreco = true);
    try {
      // Busca o orçamento completo SEM alterar o status no servidor
      final orcamentoCompleto =
          await OrcamentoRepository().buscarPorId(orcId);

      final itens = (orcamentoCompleto['itens'] as List? ?? []);

      // Agrupa por materialId: cada material vira 1 ItemOrcamentoData com N precos
      // (um por fornecedor).
      final Map<int, ItemOrcamentoData> itensPorChave = {};

      for (final item in itens) {
        final materialId = item['materialId'] as int;
        final materialData = item['material'] as Map<String, dynamic>?;
        final fornecedorId = item['fornecedorId'] as int?;
        final fornecedorData = item['fornecedor'] as Map<String, dynamic>?;

        if (!itensPorChave.containsKey(materialId)) {
          itensPorChave[materialId] = ItemOrcamentoData(
            materialId: materialId,
            materialNome: materialData?['nome'] as String? ?? '',
            materialUnidade: materialData?['unidade'] as String?,
            materialMedida: materialData?['medida'] as String?,
            materialEspessura: materialData?['espessura'] as String?,
            materialIdentificador: materialData?['identificador'] as String?,
            materialCategoria: materialData?['categoria'] as String?,
            quantidade: double.tryParse(item['quantidade'].toString()) ?? 1,
            qtdUnidade: item['qtdUnidade'] != null ? double.tryParse(item['qtdUnidade'].toString()) : null,
            precos: {},
          );
        }

        if (fornecedorId != null && fornecedorData != null) {
          itensPorChave[materialId]!.precos[fornecedorId] = PrecoFornecedorData(
            fornecedorNome: fornecedorData['nomeFantasia'] as String? ?? '',
            preco: item['precoUnitario'] != null
                ? double.tryParse(item['precoUnitario'].toString())
                : null,
            observacao: item['observacao'] as String?,
          );

          if (item['selecionado'] as bool? ?? false) {
            itensPorChave[materialId]!.fornecedorSelecionado = fornecedorId;
          }
        }
      }

      if (!mounted) return;

      provider.adicionarItensEmLote(
        orcamentoCompleto['titulo'] as String? ?? 'Orçamento #$orcId',
        itensPorChave.values.toList(),
      );

      provider.setServidorIdTab(orcId);
      provider.setFornecedoresOcultosTab(
        (orcamentoCompleto['fornecedoresOcultos'] as List? ?? []).map((e) => e as int).toList(),
      );
      provider.definirModoPrecificacao(orcamentoCompleto['modoPrecificacao'] as String? ?? 'UNIDADE');

      final statusReaberto = orc['status'] as String? ?? '';
      provider.atualizarFlagsTab(
        aguardandoAprovacao: statusReaberto == 'AGUARDANDO_APROVACAO',
        jaFinalizado: statusReaberto == 'APROVADO' || statusReaberto == 'NAO_APROVADO',
        modoGerarOC: statusReaberto == 'APROVADO',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$orcId carregado para edição.'),
          backgroundColor: AppTheme.success,
        ),
      );

      // Navega para o editor
      final resultado = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
      );
      await _aoVoltarDoEditor(resultado);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'carregar orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  // ── Baixar PDF do orçamento (sem abrir o editor) ──────────────────────────────
  // Busca o orçamento completo (mesma lógica de agrupamento de _reabrirOrcamento)
  // e envia para o serviço de geração de PDF, abrindo o arquivo em seguida.

  Future<void> _baixarPdfOrcamento(Map<String, dynamic> orc) async {
    final orcId = orc['id'] as int;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );
    try {
      final orcamentoCompleto = await OrcamentoRepository().buscarPorId(orcId);
      final itens = (orcamentoCompleto['itens'] as List? ?? []);

      final Map<int, ItemOrcamentoData> itensPorChave = {};
      for (final item in itens) {
        final materialId = item['materialId'] as int;
        final materialData = item['material'] as Map<String, dynamic>?;
        final fornecedorId = item['fornecedorId'] as int?;
        final fornecedorData = item['fornecedor'] as Map<String, dynamic>?;

        if (!itensPorChave.containsKey(materialId)) {
          itensPorChave[materialId] = ItemOrcamentoData(
            materialId: materialId,
            materialNome: materialData?['nome'] as String? ?? '',
            materialUnidade: materialData?['unidade'] as String?,
            materialMedida: materialData?['medida'] as String?,
            materialEspessura: materialData?['espessura'] as String?,
            materialIdentificador: materialData?['identificador'] as String?,
            materialCategoria: materialData?['categoria'] as String?,
            quantidade: double.tryParse(item['quantidade'].toString()) ?? 1,
            qtdUnidade: item['qtdUnidade'] != null ? double.tryParse(item['qtdUnidade'].toString()) : null,
            precos: {},
          );
        }

        if (fornecedorId != null && fornecedorData != null) {
          itensPorChave[materialId]!.precos[fornecedorId] = PrecoFornecedorData(
            fornecedorNome: fornecedorData['nomeFantasia'] as String? ?? '',
            preco: item['precoUnitario'] != null
                ? double.tryParse(item['precoUnitario'].toString())
                : null,
            observacao: item['observacao'] as String?,
          );
          if (item['selecionado'] as bool? ?? false) {
            itensPorChave[materialId]!.fornecedorSelecionado = fornecedorId;
          }
        }
      }

      final fornecedoresOcultos =
          (orcamentoCompleto['fornecedoresOcultos'] as List? ?? [])
              .map((e) => e as int)
              .toList();
      final ocultosSet = fornecedoresOcultos.toSet();

      // Remove preços de fornecedores ocultos, mesmo tratamento do editor
      // (_itensParaPdf), para que o PDF reflita o que o usuário está vendo.
      final itensParaPdf = itensPorChave.values.map((item) {
        final json = item.toJson();
        if (ocultosSet.isNotEmpty) {
          final precos = Map<String, dynamic>.from(json['precos'] as Map);
          precos.removeWhere((fIdStr, _) => ocultosSet.contains(int.parse(fIdStr)));
          json['precos'] = precos;
          if (item.fornecedorSelecionado != null &&
              ocultosSet.contains(item.fornecedorSelecionado)) {
            json['fornecedorSelecionado'] = null;
          }
        }
        return json;
      }).toList();

      final pdfBytes = await OrcamentoRepository().gerarPdf({
        'titulo': orcamentoCompleto['titulo'] as String? ?? 'Orçamento #$orcId',
        'itens': itensParaPdf,
        'fornecedoresOcultos': fornecedoresOcultos,
        'modoPrecificacao': orcamentoCompleto['modoPrecificacao'] as String? ?? 'UNIDADE',
      });

      final hoje = DateTime.now();
      final dataStr = '${hoje.day.toString().padLeft(2, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.year}';
      final file = File(
          '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}orcamento_${orcId}_($dataStr).pdf');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (Platform.isWindows) {
        await Process.run('explorer', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _registrarAjudaRobo();
    });
    return Consumer<OrcamentoProvider>(
      builder: (context, provider, _) {
        if (!provider.carregado) {
          return Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }

        // ── Abertura automática do editor (orçamento criado pelo Estoque) ──
        // Se alguém sinalizou abrirEditorAoEntrar (ex.: Estoque acabou de
        // chamar adicionarItensEmLote e navegou para /orcamento), e já existe
        // pelo menos uma aba aberta, pula direto para o editor em vez de
        // mostrar a lista de aprovação.
        if (OrcamentoPage.abrirEditorAoEntrar && provider.abas.isNotEmpty) {
          OrcamentoPage.abrirEditorAoEntrar = false;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final resultado = await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
            );
            await _aoVoltarDoEditor(resultado);
          });
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho global ─────────────────────────────────────
                _buildHeader(),
                const SizedBox(height: 12),

                // ── Conteúdo: sempre o painel de aprovação ────────────────
                Expanded(child: _buildPainelAprovacao()),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Guias de orçamentos ──────────────────────────────────────────────────────


  // ── Painel de aprovação (exibido quando a aba ativa está vazia) ──────────────

  Widget _buildPainelAprovacao() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: TabBar(
            controller: _mainTabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Aguardando Aprovação'),
                    const SizedBox(width: 6),
                    _badgeContagem(_aguardandoAprovacao.length),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Aprovados'),
                    const SizedBox(width: 6),
                    _badgeContagem(_aprovados.length),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Não Aprovados'),
                    const SizedBox(width: 6),
                    _badgeContagem(_naoAprovados.length),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _mainTabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildListaAprovacao(
                lista: _aguardandoAprovacao,
                emptyMessage: 'Nenhum orçamento aguardando aprovação',
                emptyIcon: Icons.pending_outlined,
                statusColor: AppTheme.warning,
                mostrarAcoes: true,
              ),
              _buildListaAprovacao(
                lista: _aprovados,
                emptyMessage: 'Nenhum orçamento aprovado',
                emptyIcon: Icons.check_circle_outline,
                statusColor: AppTheme.success,
              ),
              _buildListaAprovacao(
                lista: _naoAprovados,
                emptyMessage: 'Nenhum orçamento não aprovado',
                emptyIcon: Icons.cancel_outlined,
                statusColor: AppTheme.error,
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orçamento',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            SizedBox(height: 2),
            Text(
              'Orçar e comparar valores entre fornecedores',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),

        const Spacer(),

        // Botão Orçamentos em andamento
        Consumer<OrcamentoProvider>(
          builder: (context, provider, _) {
            final temAbas = provider.abas.isNotEmpty;
            return Tooltip(
              message: temAbas
                  ? 'Ver orçamentos abertos em edição'
                  : 'Nenhum orçamento aberto no momento',
              child: OutlinedButton.icon(
                onPressed: temAbas
                    ? () async {
                        final resultado = await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const OrcamentoEditorPage()),
                        );
                        await _aoVoltarDoEditor(resultado);
                      }
                    : null,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.edit_note, size: 16),
                    if (temAbas)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                            color: AppTheme.warning,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${provider.abas.length}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                label: Text(
                  'Aberto',
                  style: TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: temAbas ? AppTheme.warning : Theme.of(context).colorScheme.outline,
                  side: BorderSide(
                      color: temAbas ? AppTheme.warning : Theme.of(context).colorScheme.outlineVariant),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ).copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
              ),
            );
          },
        ),

        const SizedBox(width: 12),

        Tooltip(
          key: _tourKeyNovoOrcamento,
          message: 'Criar um novo orçamento de compra',
          child: FilledButton.icon(
            onPressed: () async {
              final p = context.read<OrcamentoProvider>();
              p.adicionarAba();
              p.atualizarFlagsTab(modoEdicao: true);
              final resultado = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
              );
              await _aoVoltarDoEditor(resultado);
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text(
              'Novo Orçamento',
              style: TextStyle(fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
          ),
        ),

        const SizedBox(width: 12),

        Tooltip(
          message: 'Ver histórico de orçamentos finalizados',
          child: OutlinedButton.icon(
            onPressed: () async {
              final resultado = await Navigator.of(context).push<dynamic>(
                MaterialPageRoute(
                  builder: (_) => const OrcamentoHistoricoPage(),
                ),
              );

              if (!mounted) return;

              if (resultado is Map &&
                  resultado['reabrirServidorId'] != null) {
                // A reabertura já configura a aba no provider via _reabrirOrcamento
              }
            },
            icon: Icon(Icons.history, size: 16),
            label: Text(
              'Histórico',
              style: TextStyle(fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
            ).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
          ),
        ),

        SizedBox(width: 12),

        IconButton(
          onPressed: () => _carregarOrcamentosServidor(origem: 'botaoAtualizarManual'),
          icon: Icon(
            Icons.refresh,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          tooltip: 'Atualizar lista de orçamentos',
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
        ),

        if (_salvandoPreco) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  // ignore: unused_element
  Widget _buildHeaderEdicao(OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () {
            context.read<OrcamentoProvider>().atualizarFlagsTab(
              aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);
            context.read<OrcamentoProvider>().fecharAbaAposOperacao();
          },
          icon: Icon(Icons.arrow_back_ios_new, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.tabAtual?.titulo ?? 'Orçamento',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            SizedBox(height: 2),
            Text(
              'Orçar e comparar valores entre fornecedores',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const Spacer(),
        if (_salvandoPreco) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
          ),
        ],
      ],
    );
  }

  Widget _buildListaAprovacao({
    required List<dynamic> lista,
    required String emptyMessage,
    required IconData emptyIcon,
    required Color statusColor,
    bool mostrarAcoes = false,
  }) {
    if (_carregandoAprovacao) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_erroAprovacao != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: AppTheme.error),
            SizedBox(height: 12),
            Text(
              'Erro ao carregar orçamentos',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              _erroAprovacao!.contains(': ')
                  ? _erroAprovacao!.substring(_erroAprovacao!.indexOf(': ') + 2)
                  : _erroAprovacao!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _carregarOrcamentosServidor,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            ),
          ],
        ),
      );
    }

    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(emptyIcon, size: 36, color: statusColor),
            ),
            SizedBox(height: 20),
            Text(
              emptyMessage,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: 'Atualizar lista de orçamentos',
              child: TextButton.icon(
                onPressed: () => _carregarOrcamentosServidor(origem: 'botaoAtualizarManual'),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Atualizar'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primary)
                    .copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: lista.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final orc = lista[i] as Map<String, dynamic>;
              return _OrcamentoAprovacaoCard(
                orcamento: orc,
                statusColor: statusColor,
                mostrarAcoes: mostrarAcoes,
                onTap: () => _reabrirOrcamento(orc),
                onAbrirPdf: () => _baixarPdfOrcamento(orc),
                onAprovar: mostrarAcoes
                    ? () => _aprovarOrcamento(orc['id'] as int, orc['titulo'] as String? ?? '')
                    : null,
                onRejeitar: mostrarAcoes
                    ? () => _rejeitarOrcamento(orc['id'] as int, orc['titulo'] as String? ?? '')
                    : null,
                onReabrir: () => _reabrirOrcamento(orc),
                onGerarOC: orc['status'] == 'APROVADO' ? () => _gerarOCDeOrcamentoAprovado(orc) : null,
              );
            },
          ),
        ),
      ],
    );
  }






}

// ─── Campo de descrição com controller persistente ───────────────────────────

class _DescricaoField extends StatefulWidget {
  final String? valorInicial;
  final ValueChanged<String> onChanged;

  const _DescricaoField({
    required this.valorInicial,
    required this.onChanged,
  });

  @override
  State<_DescricaoField> createState() => _DescricaoFieldState();
}

class _DescricaoFieldState extends State<_DescricaoField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.valorInicial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:_ctrl,
      maxLines: 2,
      inputFormatters: [_NoCommaFormatter()],
      decoration: InputDecoration(
        hintText: 'Descrição',
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        errorText: _ctrl.text.trim().isEmpty ? 'Descrição obrigatória' : null,
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
    );
  }
}

// ─── Card de orçamento para aprovação ────────────────────────────────────────

class _OrcamentoAprovacaoCard extends StatefulWidget {
  final Map<String, dynamic> orcamento;
  final Color statusColor;
  final bool mostrarAcoes;
  final VoidCallback? onTap;
  final VoidCallback? onAbrirPdf;
  final VoidCallback? onAprovar;
  final VoidCallback? onRejeitar;
  final VoidCallback? onReabrir;
  final VoidCallback? onGerarOC;

  const _OrcamentoAprovacaoCard({
    required this.orcamento,
    required this.statusColor,
    this.mostrarAcoes = false,
    this.onTap,
    this.onAbrirPdf,
    this.onAprovar,
    this.onRejeitar,
    this.onReabrir,
    this.onGerarOC,
  });

  @override
  State<_OrcamentoAprovacaoCard> createState() => _OrcamentoAprovacaoCardState();
}

class _OrcamentoAprovacaoCardState extends State<_OrcamentoAprovacaoCard> {
  bool _hovered = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final orcamento = widget.orcamento;
    final statusColor = widget.statusColor;
    final mostrarAcoes = widget.mostrarAcoes;
    final onAprovar = widget.onAprovar;
    final onRejeitar = widget.onRejeitar;
    final onReabrir = widget.onReabrir;
    final onGerarOC = widget.onGerarOC;
    final onAbrirPdf = widget.onAbrirPdf;
    final titulo = orcamento['titulo'] as String? ?? 'Orçamento';
    final itens = (orcamento['itens'] as List? ?? []);
    
    // Materiais únicos (não duplicados por fornecedor), com descrição para
    // exibição na lista (nome + medida/espessura/identificador), no mesmo
    // padrão usado no card de Ordem de Compra.
    final Map<int, String> materiaisUnicos = {};
    for (final item in itens) {
      final materialId = item['materialId'] as int?;
      if (materialId == null || materiaisUnicos.containsKey(materialId)) continue;
      final materialData = item['material'] as Map<String, dynamic>?;
      final nomeBase = (materialData?['nome'] as String? ?? '').isNotEmpty
          ? materialData!['nome'] as String
          : 'Material excluído';
      final medida = materialData?['medida'] as String?;
      final medidaOuDimensao = (medida != null && medida.isNotEmpty)
          ? medida
          : _materialDimensaoFormatada(
              _parseDoubleOrNull(materialData?['largura']),
              _parseDoubleOrNull(materialData?['comprimento']),
            );
      final espessura = materialData?['espessura'] as String?;
      final espessuraFormatada = (espessura != null && espessura.isNotEmpty)
          ? (espessura.toLowerCase().endsWith('mm') ? espessura : '${espessura}mm')
          : null;
      final identificador = materialData?['identificador'] as String?;
      final partes = <String>[
        if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
        if (espessuraFormatada != null) espessuraFormatada,
      ];
      final nomeComPartes =
          partes.isEmpty ? nomeBase : '$nomeBase · ${partes.join(' · ')}';
      materiaisUnicos[materialId] = (identificador != null && identificador.isNotEmpty)
          ? '$identificador · $nomeComPartes'
          : nomeComPartes;
    }
    
    final criadoEm = orcamento['criadoEm'] != null
        ? DateTime.tryParse(orcamento['criadoEm'] as String)
        : null;
    final criadorNome = orcamento['criador']?['nome'] as String?;
    final aprovadoEm = orcamento['aprovadoEm'] != null
        ? DateTime.tryParse(orcamento['aprovadoEm'] as String)
        : null;
    final aprovadorNome = orcamento['aprovador']?['nome'] as String?;
    final motivoRejeicao = orcamento['motivoRejeicao'] as String?;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit: _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hovered
                ? Color(0xFFFF9800).withValues(alpha: 0.06)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              // Barra colorida lateral esquerda (mesmo padrão do card de OC)
              Positioned(
                left: 0, top: 0, bottom: 0, width: 4,
                child: ColoredBox(color: statusColor),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 16, top: 16, bottom: 16),
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '#${orcamento['id']} — $titulo',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (criadoEm != null)
                  _chip(
                    Icons.calendar_today_outlined,
                    [
                      'Criado em ${_formatDataCard(criadoEm)}',
                      if (criadorNome != null) 'por $criadorNome',
                    ].join(' '),
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                if (aprovadoEm != null)
                  _chip(
                    motivoRejeicao != null ? Icons.cancel_outlined : Icons.check_circle_outline,
                    [
                      '${motivoRejeicao != null ? 'Não aprovado' : 'Aprovado'} em ${_formatDataCard(aprovadoEm)}',
                      if (aprovadorNome != null) 'por $aprovadorNome',
                    ].join(' '),
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            if (materiaisUnicos.isNotEmpty) ...[
              const SizedBox(height: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: materiaisUnicos.values
                    .map((desc) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            desc,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],

                if (motivoRejeicao != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: AppTheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Motivo da rejeição',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.error,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                motivoRejeicao,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Aba "Aguardando Aprovação": PDF + Reabrir + Rejeitar + Aprovar
                    if (mostrarAcoes) ...[
                      if (onAbrirPdf != null) ...[
                        Tooltip(
                          message: 'Baixar PDF do orçamento',
                          child: OutlinedButton.icon(
                            onPressed: onAbrirPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                            label: const Text('PDF', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ).copyWith(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Tooltip(
                        message: 'Reabrir orçamento para edição',
                        child: OutlinedButton.icon(
                          onPressed: onReabrir,
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text('Reabrir', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ).copyWith(
                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Rejeitar orçamento',
                        child: OutlinedButton.icon(
                          onPressed: onRejeitar,
                          icon: const Icon(Icons.close, size: 14),
                          label: const Text('Rejeitar',
                              style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ).copyWith(
                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Aprovar orçamento',
                        child: FilledButton.icon(
                          onPressed: onAprovar,
                          icon: const Icon(Icons.check, size: 14),
                          label: const Text('Aprovar',
                              style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ).copyWith(
                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                    ]
                    // Aba "Aprovados": PDF + Gerar OC
                    else if (onGerarOC != null) ...[
                      if (onAbrirPdf != null) ...[
                        Tooltip(
                          message: 'Baixar PDF do orçamento',
                          child: OutlinedButton.icon(
                            onPressed: onAbrirPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                            label: const Text('PDF', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ).copyWith(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Tooltip(
                        message: 'Gerar Ordem de Compra a partir deste orçamento',
                        child: FilledButton.icon(
                          onPressed: onGerarOC,
                          icon: const Icon(Icons.shopping_cart_checkout, size: 14),
                          label: const Text('Gerar OC',
                              style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ).copyWith(
                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                    ]
                    // Demais abas (Não Aprovados, etc.): PDF + Reabrir
                    else ...[
                      if (onAbrirPdf != null) ...[
                        Tooltip(
                          message: 'Baixar PDF do orçamento',
                          child: OutlinedButton.icon(
                            onPressed: onAbrirPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                            label: const Text('PDF', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ).copyWith(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Tooltip(
                        message: 'Reabrir orçamento para edição',
                        child: FilledButton.icon(
                          onPressed: onReabrir,
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text('Reabrir', style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ).copyWith(
                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDataCard(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─── Sub-widgets (reutilizados) ───────────────────────────────────────────────

class _QuantidadeField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _QuantidadeField({required this.value, required this.onChanged});

  @override
  State<_QuantidadeField> createState() => _QuantidadeFieldState();
}

class _QuantidadeFieldState extends State<_QuantidadeField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value.toStringAsFixed(widget.value % 1 == 0 ? 0 : 2));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
      ],
      decoration: InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        if (parsed != null && parsed > 0) widget.onChanged(parsed);
      },
    );
  }
}

class _DialogVincularFornecedores extends StatefulWidget {
  final List<FornecedorModel> fornecedores;
  final Set<int> idsJaVinculados;
  final String materialNome;

  const _DialogVincularFornecedores({
    required this.fornecedores,
    required this.idsJaVinculados,
    required this.materialNome,
  });

  @override
  State<_DialogVincularFornecedores> createState() =>
      _DialogVincularFornecedoresState();
}

class _DialogVincularFornecedoresState
    extends State<_DialogVincularFornecedores> {
  final Set<int> _selecionados = {};
  final _buscaCtrl = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disponiveis = widget.fornecedores
        .where((f) => !widget.idsJaVinculados.contains(f.id))
        .toList();

    final filtrados = _filtro.isEmpty
        ? disponiveis
        : disponiveis
            .where((f) =>
                f.nomeFantasia.toLowerCase().contains(_filtro.toLowerCase()) ||
                (f.cnpj != null && f.cnpj!.contains(_filtro)))
            .toList();

    return AlertDialog(
      title: Text('Adicionar Fornecedores — ${widget.materialNome}',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _buscaCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar fornecedor...',
                prefixIcon: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.outline),
                suffixIcon: _filtro.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.outline),
                        onPressed: () {
                          _buscaCtrl.clear();
                          setState(() => _filtro = '');
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            if (_selecionados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 13, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${_selecionados.length} selecionado${_selecionados.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 280),
              child: disponiveis.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                          'Todos os fornecedores já estão vinculados a este material.',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  : filtrados.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              Icon(Icons.search_off, size: 16, color: Theme.of(context).colorScheme.outline),
                              SizedBox(width: 8),
                              Text(
                                'Nenhum fornecedor encontrado para "$_filtro".',
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                          itemBuilder: (ctx, i) {
                            final f = filtrados[i];
                            return CheckboxListTile(
                              dense: true,
                              title: Text(f.nomeFantasia,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: f.cnpj != null
                                  ? Text(f.cnpj!, style: const TextStyle(fontSize: 11))
                                  : null,
                              value: _selecionados.contains(f.id),
                              activeColor: AppTheme.primary,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selecionados.add(f.id);
                                } else {
                                  _selecionados.remove(f.id);
                                }
                              }),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _selecionados.isEmpty
              ? null
              : () => Navigator.pop(context, _selecionados.toList()),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

class _DialogEditarPreco extends StatefulWidget {
  final String fornecedorNome;
  final String materialNome;
  final double? precoAtual;

  const _DialogEditarPreco({
    required this.fornecedorNome,
    required this.materialNome,
  }) : precoAtual = null;

  @override
  State<_DialogEditarPreco> createState() => _DialogEditarPrecoState();
}

class _DialogEditarPrecoState extends State<_DialogEditarPreco> {
  late final TextEditingController _precoCtrl;

  @override
  void initState() {
    super.initState();
    _precoCtrl = TextEditingController(
        text: widget.precoAtual != null
            ? widget.precoAtual!.toStringAsFixed(2)
            : '');
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Editar Preço — ${widget.fornecedorNome}',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.materialNome,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: _precoCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Preço unitário (R\$)',
                prefixText: 'R\$ ',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () {
            final preco = double.tryParse(
                _precoCtrl.text.replaceAll(',', '.'));
            Navigator.pop(context, {
              'preco': preco,
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _DialogDescartarOrcamento extends StatefulWidget {
  const _DialogDescartarOrcamento();

  @override
  State<_DialogDescartarOrcamento> createState() =>
      _DialogDescartarOrcamentoState();
}

class _DialogDescartarOrcamentoState
    extends State<_DialogDescartarOrcamento> {
  final _ctrl = TextEditingController();
  bool _vazio = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cancelar Orçamento',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Este orçamento será movido para o histórico como cancelado.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Motivo do cancelamento *',
              hintText: 'Explique o motivo pelo qual está cancelando...',
              isDense: true,
              errorText: _vazio ? 'Informe o motivo do cancelamento' : null,
            ),
            onChanged: (_) {
              if (_vazio && _ctrl.text.trim().isNotEmpty) {
                setState(() => _vazio = false);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: () {
            if (_ctrl.text.trim().isEmpty) {
              setState(() => _vazio = true);
              return;
            }
            Navigator.pop(context, _ctrl.text.trim());
          },
          child: const Text('Cancelar Orçamento'),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _DialogOpcaoOC extends StatelessWidget {
  final List<ItemOrcamentoData> itens;
  const _DialogOpcaoOC({required this.itens});

  @override
  Widget build(BuildContext context) {
    final fornecedores = itens
        .where((i) => i.fornecedorSelecionado != null)
        .map((i) => i.precos[i.fornecedorSelecionado!]?.fornecedorNome ?? '')
        .toSet();

    return AlertDialog(
      title: const Text('Gerar Ordem de Compra',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${itens.length} ${itens.length == 1 ? 'material' : 'materiais'} selecionados · '
            '${fornecedores.length} ${fornecedores.length == 1 ? 'fornecedor' : 'fornecedores'}',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const Text('Como deseja gerar a OC?',
              style: TextStyle(fontSize: 13)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, 'existente'),
          child: const Text('Adicionar a OC existente'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () => Navigator.pop(context, 'nova'),
          child: const Text('Criar nova OC'),
        ),
      ],
    );
  }
}