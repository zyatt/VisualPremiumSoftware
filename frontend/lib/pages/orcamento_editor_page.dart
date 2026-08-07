import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/material_model.dart';
import '../models/fornecedor_model.dart';
import '../providers/material_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/orcamento_provider.dart';
import '../providers/ordem_compra_provider.dart';
import '../providers/robo_helper_provider.dart';
import '../repositories/fornecedor_repository.dart';
import '../repositories/orcamento_repository.dart';
import '../rotas/app_router.dart';
import '../utils/api_client.dart' show OrcamentoTravadoException;
import '../widgets/escolher_usuario_chat_dialog.dart';

import '../theme/app_theme.dart';

void _logOrc(String mensagem, {Object? erro, StackTrace? stack, int? level}) {
  dev.log(
    mensagem,
    time: DateTime.now(),
    name: 'OrcamentoEditor',
    error: erro,
    stackTrace: stack,
    level: level ?? 0,
  );
}

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

bool _isErroDeStatusDesatualizado(Object e) {
  final raw = e.toString();
  return raw.contains('Apenas orçamentos abertos podem ser enviados') ||
      raw.contains('Apenas orçamentos aguardando aprovação podem ser aprovados') ||
      raw.contains('Apenas orçamentos aguardando aprovação podem ser rejeitados') ||
      raw.contains('Apenas orçamentos aprovados');
}

// Detecta um 404 do servidor para este orçamento — geralmente significa
// que ele já foi excluído por outra guia/usuário (ou é resíduo de dados
// locais salvos antes de uma correção anterior a esta versão do app: uma
// aba antiga em SharedPreferences apontando para um servidorId que não
// existe mais). Nesse caso a guia deve se autolimpar em vez de ficar presa
// mostrando erro indefinidamente — ver `_tratarOrcamentoNaoEncontrado`.
bool _isErroOrcamentoNaoEncontrado(Object e) {
  final raw = e.toString();
  return raw.contains('Orçamento não encontrado');
}

class _HorizontalScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
  };
}

class _ScrollMetricsNotifier extends ValueNotifier<ScrollMetrics> {
  _ScrollMetricsNotifier() : super(_emptyMetrics());

  static ScrollMetrics _emptyMetrics() => FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 0,
    pixels: 0,
    viewportDimension: 0,
    axisDirection: AxisDirection.right,
    devicePixelRatio: 1,
  );

  void update(ScrollController ctrl) {
    if (ctrl.hasClients) {
      value = ctrl.position;
    }
  }
}

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

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _DecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(',', '.');

    text = text.replaceAll(RegExp(r'[^\d.]'), '');

    text = text.replaceAll(RegExp(r'\.{2,}'), '.');

    final primeiroPonto = text.indexOf('.');
    if (primeiroPonto != -1) {
      text = text.substring(0, primeiroPonto + 1) +
          text.substring(primeiroPonto + 1).replaceAll('.', '');
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

String _brl(double? v) {
  if (v == null || v == 0) return '—';
  return 'R\$ ${_formatarPreco(v)}';
}

String _formatQtd(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString().replaceAll('.', ',');
}

String _formatQtdComUnidade(double v, String? unidade) {
  final u = _formatarUnidadeExibicao(unidade).toLowerCase();
  return u.isEmpty ? _formatQtd(v) : '${_formatQtd(v)} $u';
}

String? _materialDimensaoFormatada(double? largura, double? comprimento) {
  if (largura == null || comprimento == null || largura <= 0 || comprimento <= 0) return null;
  String fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  return '${fmt(comprimento)}x${fmt(largura)}m';
}

String? _formatarEspessura(String? esp) {
  if (esp == null) return null;
  final v = esp.trim();
  if (v.isEmpty) return v;
  if (v.toLowerCase().endsWith('mm')) return v;
  return '${v}mm';
}

String _formatarUnidadeExibicao(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return '';
  final u = unidade.trim().toUpperCase();
  switch (u) {
    case 'UNIDADE': return 'Unidade';
    case 'M/L':     return 'm/l';
    case 'M':       return 'm';
    case 'ML':      return 'ml';
    case 'M²':
    case 'M2':      return 'm²';
    case 'KG':      return 'Kg';
    case 'G':       return 'g';
    default:        return unidade;
  }
}

String _unidadeDescricaoCompleta(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return '';
  final u = unidade.trim().toUpperCase();
  switch (u) {
    case 'M/L':     return 'm/l (metro linear)';
    case 'M':       return 'm (metro)';
    case 'ML':      return 'ml (mililitro)';
    case 'M²':
    case 'M2':      return 'm² (metro quadrado)';
    case 'G':       return 'g (grama)';
    case 'KG':      return 'kg (quilograma)';
    case 'UNIDADE':
    case 'UN':
    case 'UNID':    return 'unidade';
    default:        return unidade.toLowerCase();
  }
}

/// Fecha o editor de forma segura: se houver algo para desempilhar, faz
/// pop() (opcionalmente com [result]); caso contrário navega para a tela de
/// Orçamento em vez de chamar pop() às cegas. Chamar Navigator.pop() quando
/// a pilha já está vazia (ex: rota única após deep link, ou uma corrida em
/// que outra chamada já fez pop durante um `await` anterior) dispara a
/// assertion 'currentConfiguration.isNotEmpty' do go_router e deixa o
/// Navigator em estado inconsistente (trava subsequente em dispose/build).
void _fecharEditorComSeguranca(BuildContext context, [Object? result]) {
  if (!context.mounted) return;
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop(result);
  } else {
    GoRouter.of(context).go('/orcamento');
  }
}

_OrcamentoEditorPageState? _editorStateAtivo;

GlobalKey get criarOrcamentoTourKeyBlocoFiltros =>
    _editorStateAtivo?._tourKeys.blocoFiltros ?? GlobalKey();

VoidCallback? criarOrcamentoTourAoAbrirEditor;

class _TourKeys {
  final campoNome                = GlobalKey();
  final blocoFiltros             = GlobalKey();
  final primeiroResultadoDropdown = GlobalKey();
  final primeiroResultado        = GlobalKey();
  final botaoAdicionarFornecedor = GlobalKey();
  final buscaFornecedorDialog    = GlobalKey();
  final primeiroFornecedorDialog = GlobalKey();
  final editarPreco              = GlobalKey();
  final camposPrecoEDisponibilidadeDialog = GlobalKey();
  final celulaFornecedor         = GlobalKey();
  final campoQuantidadeMaterial1 = GlobalKey();
  final campoQtdUnidadeMaterial2 = GlobalKey();
  final botaoOrcarPor            = GlobalKey();
  final botaoEnviarParaAprovacao = GlobalKey();
}

class OrcamentoEditorPage extends StatefulWidget {
  const OrcamentoEditorPage({super.key});

  @override
  State<OrcamentoEditorPage> createState() => _OrcamentoEditorPageState();
}

class _OrcamentoEditorPageState extends State<OrcamentoEditorPage> with WidgetsBindingObserver {

  final _tourKeys = _TourKeys();

  final _searchNomeCtrl = TextEditingController();
  final _searchIdentificadorCtrl = TextEditingController();
  final _searchMedidaCtrl = TextEditingController();
  final _searchComprimentoCtrl = TextEditingController();
  final _searchLarguraCtrl = TextEditingController();
  final _searchEspCtrl = TextEditingController();
  final _abasScrollCtrl = ScrollController();
  final _tabelaHScrollCtrl = ScrollController();
  final _pageScrollCtrl = ScrollController();
  Timer? _debounceMatBusca;

  Timer? _autoSyncTimer;

  // ── Trava de edição colaborativa ────────────────────────────────────────
  // Regra de negócio: um orçamento está "em edição" se e somente se a guia
  // (aba) correspondente estiver ATIVA (selecionada) na tela de algum
  // usuário agora. Trocar de guia — mesmo sem sair do editor — libera a
  // edição daquele orçamento; abrir/selecionar uma guia tenta assumir a
  // edição no servidor. Por isso só pode haver, no máximo, UM orçamento
  // travado por ESTA instância do editor a qualquer momento (o da aba
  // ativa) — não é mais um Set: guias que ficam abertas mas não estão
  // selecionadas não devem segurar trava nenhuma.
  //
  // `_servidorIdComTravaAtiva` é o servidorId que este editor efetivamente
  // detém no servidor agora (renovado pelo heartbeat em
  // _sincronizarStatusServidor). `_aquisicaoTravaEmAndamento` evita chamadas
  // concorrentes de _garantirTravaAbaAtiva (ex: SSE e troca manual de aba
  // quase simultâneas) tentando travar/destravar ao mesmo tempo.
  int? _servidorIdComTravaAtiva;
  bool _aquisicaoTravaEmAndamento = false;

  // Referência ao provider (não o BuildContext) para remover o listener de
  // tempo real com segurança em dispose() — o BuildContext pode não estar
  // mais válido nesse ponto (mesmo padrão usado em OrcamentoPage).
  OrcamentoProvider? _orcamentoProviderRef;

  bool _syncing = false;
  late final _ScrollMetricsNotifier _abasScrollHintNotifier;
  late final _ScrollMetricsNotifier _tabelaHScrollHintNotifier;

  int? _abaRenomeando;
  TextEditingController? _renomeCtrl;
  final _renomeFocusNode = FocusNode();

  List<MaterialModel> _resultadosBusca = [];
  bool _buscando = false;
  bool _mostrarResultados = false;
  bool _salvando = false;

  final Set<String> _itensSelecionados = {};
  final Set<String> _materiaisParaBulk = {};

  RoboHelperProvider? _roboHelperPagina;

  bool _dialogFornecedorTourAberto = false;
  bool _dialogFornecedorTourEmTransicao = false;

  Future<List<int>?>? _futureDialogFornecedorTour;

  Future<Map<String, dynamic>?>? _futureDialogPrecoTour;
  bool _dialogPrecoTourAberto = false;
  bool _dialogPrecoTourEmTransicao = false;

  bool _materialTourAdicionado = false;

  bool _tourEntrouNoEditor = false;

  String? _itemIdTourFake;

  String? _itemIdTourFake2;

  bool _mostrarResultadoFakeNoDropdown = false;

  static const _fornecedorIdTourFake = -999999;

  static String _textoMaterial(dynamic item) {
    final partes = <String>[item.materialNome as String];
    final medida = item.materialMedida as String?;
    final esp    = _formatarEspessura(item.materialEspessura as String?);
    final dimensao = item.materialDimensaoFormatada as String?;
    if (medida != null && medida.isNotEmpty) partes.add(medida);
    if (esp    != null && esp.isNotEmpty)    partes.add(esp);
    if (dimensao != null) partes.add(dimensao);
    return partes.join(' · ');
  }

  void _copiarSelecionados(List<dynamic> itens) {
    final sel = itens.where((i) => _itensSelecionados.contains(i.itemId as String)).toList();
    if (sel.isEmpty) return;
    final texto = sel.map(_textoMaterial).join('\n');
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${sel.length} ${sel.length == 1 ? 'material copiado' : 'materiais copiados'}'),
      duration: const Duration(seconds: 2),
      backgroundColor: AppTheme.primary,
    ));
    setState(() => _itensSelecionados.clear());
  }

  @override
  void initState() {
    super.initState();

    _editorStateAtivo = this;
    WidgetsBinding.instance.addObserver(this);
    _abasScrollHintNotifier = _ScrollMetricsNotifier();
    _tabelaHScrollHintNotifier = _ScrollMetricsNotifier();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sincronizarStatusServidor(origem: 'initState');
      context.read<FornecedorProvider>().carregar();

      // Sempre revalida/assume a trava da aba ativa ao abrir o editor,
      // mesmo que a aba já tivesse sido marcada como "não somente-leitura"
      // antes (ex: reabrir uma aba que já existia localmente após ter
      // clicado em "Voltar" — o dispose() anterior já destravou no
      // servidor, então a flag local não é mais confiável). Nunca assume
      // que ainda detém a trava só porque a aba não está marcada como
      // somenteLeitura: só _garantirTravaAbaAtiva, que efetivamente chama o
      // servidor, pode confirmar isso.
      _garantirTravaAbaAtiva(origem: 'initState');

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _tabelaHScrollCtrl.hasClients) {
          _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
        }
        if (mounted && _abasScrollCtrl.hasClients) {
          _abasScrollHintNotifier.update(_abasScrollCtrl);
        }
      });

      final helper = context.read<RoboHelperProvider>();
      _roboHelperPagina = helper;
      _roboHelperPagina!.addListener(_onRoboHelperPaginaChanged);

      helper.definirTelaSobreposta(true);
    });
    _tabelaHScrollCtrl.addListener(() {
      if (mounted) _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
    });
    _abasScrollCtrl.addListener(() {
      if (mounted) _abasScrollHintNotifier.update(_abasScrollCtrl);
    });

    _logOrc('initState: iniciando _autoSyncTimer (30s)');
    _iniciarAutoSyncTimer();

    // Escuta o provider para reagir em tempo real (via SSE) a mudanças
    // feitas por OUTRO usuário no mesmo orçamento (edição de item) ou a
    // alguém assumindo/liberando a trava de edição — sem isso, o editor só
    // saberia dessas mudanças no próximo ciclo do _autoSyncTimer (até 30s).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _orcamentoProviderRef = context.read<OrcamentoProvider>();
        _orcamentoProviderRef!.addListener(_onProviderTempoRealChanged);
      }
    });
  }

  int _ultimoMudancaExternaTrigger = 0;
  int _ultimoTravaExternaTrigger = 0;
  int _ultimoServidorIdTravadoTrigger = 0;
  int _ultimoEdicaoLocalTrigger = 0;
  Timer? _autoSaveDebounce;

  void _onProviderTempoRealChanged() {
    if (!mounted) return;
    final provider = _orcamentoProviderRef ?? context.read<OrcamentoProvider>();
    final sidAtual = provider.tabAtual?.servidorId;

    // ── Edição local do próprio usuário (qtd/preço/fornecedor etc): agenda
    // um auto-save debounced para propagar a mudança via SSE a quem estiver
    // só visualizando este orçamento em tempo real. Sem isso, a persistência
    // só acontecia ao fechar a aba ou no timer de 30s (que só sincroniza
    // status, não os itens) — daí a tela de quem só olha ficar "parada".
    if (provider.edicaoLocalTrigger != _ultimoEdicaoLocalTrigger) {
      _ultimoEdicaoLocalTrigger = provider.edicaoLocalTrigger;
      if (sidAtual != null && provider.tabAtual?.somenteLeitura != true) {
        _autoSaveDebounce?.cancel();
        _autoSaveDebounce = Timer(const Duration(milliseconds: 1200), () {
          if (!mounted) return;
          final tab = provider.tabAtual;
          if (tab == null || tab.servidorId != sidAtual) return;
          _persistirItensDaAba(sidAtual, tab).then((_) {
            if (mounted) provider.marcarAbaAtivaComoSalva();
          }).catchError((e) {
            _logOrc('auto-save debounced: erro ao persistir orcamentoId=$sidAtual', erro: e);
          });
        });
      }
    }

    // ── A criação assíncrona do orçamento no servidor (disparada por
    // OrcamentoProvider._novaAba ao clicar em "Novo Orçamento") terminou e
    // a trava foi assumida com sucesso PARA O PRÓPRIO USUÁRIO. No momento
    // em que este editor abriu (initState), a aba ainda não tinha
    // servidorId, então a trava ainda não tinha como ser registrada aqui —
    // sem este listener, o evento SSE 'orcamento_travado' que chega logo em
    // seguida (mesma trava, vista pelo lado do broadcast) seria
    // interpretado como "outro usuário assumiu a edição" e o editor
    // viraria somente-leitura por engano, mesmo sendo o próprio criador.
    if (provider.servidorIdTravadoTrigger != _ultimoServidorIdTravadoTrigger) {
      _ultimoServidorIdTravadoTrigger = provider.servidorIdTravadoTrigger;
      final idTravado = provider.servidorIdTravadoRecente;
      if (idTravado != null && idTravado == sidAtual) {
        _servidorIdComTravaAtiva = idTravado;
      }
    }

    // ── Outro usuário alterou itens/preços do orçamento que está aberto
    // aqui agora: recarrega os dados do servidor imediatamente (mesma
    // lógica do auto-sync de 30s, só que disparada na hora).
    if (provider.mudancaExternaTrigger != _ultimoMudancaExternaTrigger) {
      _ultimoMudancaExternaTrigger = provider.mudancaExternaTrigger;
      if (sidAtual != null && provider.mudancaExternaOrcamentoId == sidAtual) {
        _sincronizarStatusServidor(origem: 'mudancaExternaSSE');
        _recarregarItensDoServidor(sidAtual);
      }
    }

    // ── Alguém assumiu ou liberou a trava de um orçamento aberto aqui.
    if (provider.travaExternaTrigger != _ultimoTravaExternaTrigger) {
      _ultimoTravaExternaTrigger = provider.travaExternaTrigger;
      final travaOrcId = provider.travaExternaOrcamentoId;
      if (travaOrcId != null && travaOrcId == sidAtual && mounted) {
        final euAindaDetenho = _servidorIdComTravaAtiva == travaOrcId;
        final agoraTravado = provider.travaExternaUsuarioNome != null;

        if (agoraTravado && !euAindaDetenho) {
          // Outro usuário assumiu a edição — este editor passa a ser
          // somente-leitura a partir de agora, mesmo já estando aberto.
          provider.atualizarFlagsTab(somenteLeitura: true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${provider.travaExternaUsuarioNome} começou a editar este orçamento. '
                'A tela virou somente visualização.'),
            backgroundColor: AppTheme.warning,
          ));
        } else if (!agoraTravado && provider.tabAtual?.somenteLeitura == true) {
          // A pessoa que estava editando saiu. Como a regra é "a guia ativa
          // sempre tenta deter a edição", tentamos assumir automaticamente
          // agora — sem exigir que o usuário reabra a página. Se der certo,
          // a aba volta a ser editável; se outra pessoa for mais rápida, o
          // 409 dentro de _garantirTravaAbaAtiva mantém somente-leitura.
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('O orçamento não está mais sendo editado por ninguém. Assumindo a edição...'),
            backgroundColor: AppTheme.primary,
          ));
          _garantirTravaAbaAtiva(origem: 'travaLiberadaPorOutroUsuario');
        }
      }
    }
  }

  /// Recarrega os itens de [orcamentoId] a partir do servidor e substitui os
  /// da aba correspondente, preservando a mesma lógica de agrupamento por
  /// material usada em OrcamentoPage._reabrirOrcamento. Usado quando outro
  /// usuário altera o orçamento enquanto este editor está com ele aberto.
  Future<void> _recarregarItensDoServidor(int orcamentoId) async {
    final provider = context.read<OrcamentoProvider>();
    try {
      final orcamentoCompleto = await OrcamentoRepository().buscarPorId(orcamentoId);
      if (!mounted) return;
      // Só substitui se a aba correspondente ainda está ativa (evita
      // sobrescrever se o usuário já trocou de aba/orçamento nesse meio-tempo).
      if (provider.tabAtual?.servidorId != orcamentoId) return;

      // Atualização remota (outro usuário, ou outra guia/sessão do mesmo
      // orçamento) sempre prevalece sobre o rascunho local deste editor,
      // mesmo que existam edições locais ainda não salvas — o servidor é a
      // fonte da verdade. Isso pode descartar silenciosamente algo que o
      // usuário estava digitando aqui; é intencional (decisão de produto).
      final itensRemotos = (orcamentoCompleto['itens'] as List? ?? []);
      final Map<int, ItemOrcamentoData> itensPorChave = {};
      for (final item in itensRemotos) {
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
            preco: item['precoUnitario'] != null ? double.tryParse(item['precoUnitario'].toString()) : null,
            observacao: item['observacao'] as String?,
          );
          if (item['selecionado'] as bool? ?? false) {
            itensPorChave[materialId]!.fornecedorSelecionado = fornecedorId;
          }
        }
      }

      provider.substituirItensTab(itensPorChave.values.toList());
      provider.setFornecedoresOcultosTab(
        (orcamentoCompleto['fornecedoresOcultos'] as List? ?? []).map((e) => e as int).toList(),
      );

      // Sincroniza o título também: sem isso, quando outro usuário renomeia
      // o orçamento (ex.: pela página "Em Aberto"), a guia aberta neste
      // editor continuava mostrando o nome antigo indefinidamente, mesmo
      // recebendo o evento SSE e recarregando itens. O título só é editado
      // aqui via diálogo que já salva no servidor imediatamente
      // (renomearAba + atualizarOrcamento), então é seguro sempre adotar o
      // valor do servidor como fonte da verdade neste ponto.
      final tituloRemoto = orcamentoCompleto['titulo'] as String?;
      final abaIndex = provider.abas.indexWhere((a) => a.servidorId == orcamentoId);
      if (tituloRemoto != null &&
          tituloRemoto.isNotEmpty &&
          abaIndex != -1 &&
          provider.abas[abaIndex].titulo != tituloRemoto) {
        provider.renomearAba(abaIndex, tituloRemoto);
      }

      // O conteúdo local acabou de ser substituído pelo que veio do
      // servidor (evento SSE de outro usuário) — não há mais "alteração
      // local não salva" para avisar em relação a esse novo baseline.
      provider.marcarAbaAtivaComoSalva();
    } catch (e) {
      _logOrc('_recarregarItensDoServidor: erro ao recarregar orcamentoId=$orcamentoId', erro: e);
    }
  }

  void _iniciarAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sincronizarStatusServidor(origem: 'timer30s');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logOrc('didChangeAppLifecycleState: $state');
    if (state == AppLifecycleState.resumed) {
      _iniciarAutoSyncTimer();
      _sincronizarStatusServidor(origem: 'lifecycleResumed');
      // App pode ter ficado em segundo plano tempo suficiente para a trava
      // expirar no servidor (TRAVA_DURACAO_MS = 60s sem heartbeat) e outro
      // usuário ter assumido a edição nesse meio-tempo. Revalida a trava da
      // aba ativa ao retomar em vez de assumir que ainda é dono.
      _garantirTravaAbaAtiva(origem: 'lifecycleResumed');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
    }
  }

  void _scrollAbasEsquerda() {
    if (!_abasScrollCtrl.hasClients) return;
    final destino = (_abasScrollCtrl.position.pixels - 120).clamp(0.0, _abasScrollCtrl.position.maxScrollExtent);
    _abasScrollCtrl.animateTo(destino, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _scrollAbasDireita() {
    if (!_abasScrollCtrl.hasClients) return;
    final destino = (_abasScrollCtrl.position.pixels + 120).clamp(0.0, _abasScrollCtrl.position.maxScrollExtent);
    _abasScrollCtrl.animateTo(destino, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _logOrc('dispose: cancelando _autoSyncTimer e liberando controllers');

    if (_editorStateAtivo == this) _editorStateAtivo = null;
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _autoSaveDebounce?.cancel();
    try {
      _orcamentoProviderRef?.removeListener(_onProviderTempoRealChanged);
    } catch (_) {}

    // Libera no servidor a trava de edição que este editor detém agora (só
    // pode haver uma: a da aba ativa), para que outro usuário possa
    // assumir imediatamente em vez de esperar os até 60s de expiração
    // automática. Fire-and-forget: não bloqueia o dispose, e falha aqui é
    // inofensiva (a trava expira sozinha de qualquer forma).
    final travaAtual = _servidorIdComTravaAtiva;
    if (travaAtual != null) {
      OrcamentoRepository().destravar(travaAtual).catchError((e) {
        _logOrc('dispose: falha ao destravar orcamentoId=$travaAtual (expira sozinha)', erro: e);
      });
    }
    _servidorIdComTravaAtiva = null;

    _debounceMatBusca?.cancel();
    _searchNomeCtrl.dispose();
    _searchIdentificadorCtrl.dispose();
    _searchMedidaCtrl.dispose();
    _searchComprimentoCtrl.dispose();
    _searchLarguraCtrl.dispose();
    _searchEspCtrl.dispose();
    _abasScrollCtrl.dispose();
    _tabelaHScrollCtrl.dispose();
    _pageScrollCtrl.dispose();
    _abasScrollHintNotifier.dispose();
    _tabelaHScrollHintNotifier.dispose();
    _renomeCtrl?.dispose();
    _renomeFocusNode.dispose();
    _roboHelperPagina?.removeListener(_onRoboHelperPaginaChanged);

    final helperAoFechar = _roboHelperPagina;
    final opcoesAoFechar = helperAoFechar?.opcoesAtuais;
    final opcaoAtualAoFechar = opcoesAoFechar
        ?.where((o) => o.titulo == 'Como criar um orçamento')
        .firstOrNull;
    final paradasBaseParaTruncar =
        (opcaoAtualAoFechar != null && opcaoAtualAoFechar.paradas.length > 2)
            ? opcaoAtualAoFechar.paradas.sublist(0, 2)
            : null;
    if (helperAoFechar != null) {
      scheduleMicrotask(() {
        helperAoFechar.definirTelaSobreposta(false);

        if (paradasBaseParaTruncar != null) {
          helperAoFechar.registrarOpcoes('/orcamento', [
            RoboHelpOption(
              titulo: 'Como criar um orçamento',
              paradas: paradasBaseParaTruncar,
            ),
          ]);
        }
      });
    }
    super.dispose();
  }

  void _onRoboHelperPaginaChanged() {
    if (!mounted) return;
    if (_roboHelperPagina!.tourAtivo) return;

    if (_dialogFornecedorTourAberto) {
      _dialogFornecedorTourAberto = false;
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    if (_dialogPrecoTourAberto) {
      _dialogPrecoTourAberto = false;
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    _removerSimulacaoDoTour();
    _materialTourAdicionado = false;
    _mostrarResultadoFakeNoDropdown = false;

    if (_tourEntrouNoEditor) {
      _tourEntrouNoEditor = false;
      final provider = context.read<OrcamentoProvider>();
      provider.fecharAbaAposOperacao();
      _fecharEditorComSeguranca(context);
    }
  }

  void _removerSimulacaoDoTour() {
    final itemId = _itemIdTourFake;
    _itemIdTourFake = null;
    if (itemId != null) {
      try {
        context.read<OrcamentoProvider>().removerItem(itemId);
      } catch (_) {

      }
    }

    final itemId2 = _itemIdTourFake2;
    _itemIdTourFake2 = null;
    if (itemId2 != null) {
      try {
        context.read<OrcamentoProvider>().removerItem(itemId2);
      } catch (_) {}
    }
  }

  void _agendarBuscaMateriais() {
    _debounceMatBusca?.cancel();
    _debounceMatBusca = Timer(const Duration(milliseconds: 400), _executarBuscaMateriais);
  }

  Future<void> _executarBuscaMateriais() async {
    final nome = _searchNomeCtrl.text.trim();
    final identificador = _searchIdentificadorCtrl.text.trim();
    final medida = _searchMedidaCtrl.text.trim();
    final comprimento = _searchComprimentoCtrl.text.trim();
    final largura = _searchLarguraCtrl.text.trim();
    final esp = _searchEspCtrl.text.trim();

    final algumFiltro = nome.isNotEmpty || identificador.isNotEmpty || medida.isNotEmpty ||
        comprimento.isNotEmpty || largura.isNotEmpty || esp.isNotEmpty;

    if (!algumFiltro) {
      setState(() { _resultadosBusca = []; _mostrarResultados = false; });
      return;
    }
    setState(() { _buscando = true; _mostrarResultados = true; });
    try {
      await context.read<MaterialProvider>().carregar(
        busca: nome.isNotEmpty ? nome : '',
        identificador: identificador.isNotEmpty ? identificador : '',
        medida: medida.isNotEmpty ? medida : '',
        comprimento: comprimento.isNotEmpty ? comprimento : '',
        largura: largura.isNotEmpty ? largura : '',
        espessura: esp.isNotEmpty ? esp : '',
        ativo: true,
      );
      if (!mounted) return;
      final todos = context.read<MaterialProvider>().materiais;
      final provider = context.read<OrcamentoProvider>();
      final idsJaAdicionados = provider.tabAtual?.itens.map((i) => i.materialId).toSet() ?? {};
      setState(() {
        _resultadosBusca = todos.where((m) => !idsJaAdicionados.contains(m.id)).toList();
      });
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _adicionarMaterial(MaterialModel material) {
    final provider = context.read<OrcamentoProvider>();
    final precos = <int, PrecoFornecedorData>{};
    for (final fm in material.fornecedorMateriais) {
      precos[fm.fornecedorId] = PrecoFornecedorData(
        fornecedorNome: fm.fornecedorNome,
        preco: fm.preco > 0 ? fm.preco : null,
      );
    }
    provider.adicionarItem(ItemOrcamentoData(
      materialId: material.id,
      materialNome: material.nome,
      materialUnidade: material.unidade,
      materialCategoria: material.categoria,
      materialMedida: material.medida,
      materialEspessura: material.espessura,
      materialIdentificador: material.identificador,
      materialStatus: material.status,
      materialLargura: material.largura,
      materialComprimento: material.comprimento,
      estoqueMinimo: material.estoqueMinimo,
      precos: precos,
    ));
    _searchNomeCtrl.clear();
    _searchIdentificadorCtrl.clear();
    _searchMedidaCtrl.clear();
    _searchComprimentoCtrl.clear();
    _searchLarguraCtrl.clear();
    _searchEspCtrl.clear();
    setState(() { _resultadosBusca = []; _mostrarResultados = false; });
  }

  Future<void> _mostrarCardFakeNoDropdown() async {

    _tourEntrouNoEditor = true;
    if (_materialTourAdicionado || _itemIdTourFake != null) return;
    try {

      setState(() {
        _mostrarResultados = true;
        _mostrarResultadoFakeNoDropdown = true;
      });
    } catch (_) {}
  }

  Future<void> _inserirMaterialTourFakeNaTabela() async {
    if (_materialTourAdicionado || _itemIdTourFake != null) return;
    final provider = context.read<OrcamentoProvider>();
    try {

      if (!mounted) return;
      if (_materialTourAdicionado || _itemIdTourFake != null) return;

      final antes = provider.tabAtual?.itens.length ?? 0;
      provider.adicionarItem(ItemOrcamentoData(
        materialId: _materialIdTourFake,
        materialNome: 'MATERIAL EXEMPLO',
        materialUnidade: 'Unidade',
        materialCategoria: '',
        materialMedida: null,
        materialEspessura: '2',
        materialIdentificador: '',
        materialStatus: null,
        materialLargura: 1.0,
        materialComprimento: 2.0,
        estoqueMinimo: null,
        precos: const {},
      ));

      provider.adicionarItem(ItemOrcamentoData(
        materialId: _materialIdTourFake2,
        materialNome: 'ADESIVO',
        materialUnidade: 'm/l',
        materialCategoria: '',
        materialMedida: '50x1,27m',
        materialEspessura: '0.08',
        materialIdentificador: '',
        materialStatus: null,
        estoqueMinimo: 50.0,
        precos: const {},
      ));
      _searchNomeCtrl.clear();
      if (!mounted) return;
      setState(() {
        _resultadosBusca = [];
        _mostrarResultados = false;
        _mostrarResultadoFakeNoDropdown = false;
      });

      final itens = provider.tabAtual?.itens ?? const [];
      if (itens.length > antes) {

        _itemIdTourFake = itens[itens.length - 2].itemId;
        _itemIdTourFake2 = itens.last.itemId;
      }
      _materialTourAdicionado = true;
    } catch (_) {

    }
  }

  Future<void> _fecharDropdownTourFakeSeAberto() async {
    if (!mounted) return;
    setState(() {
      _resultadosBusca = [];
      _mostrarResultados = false;
      _mostrarResultadoFakeNoDropdown = false;
    });
  }

  Future<void> _voltarParaDropdownDoMaterialFake() async {
    if (_itemIdTourFake == null) return;
    try {
      context.read<OrcamentoProvider>().removerItem(_itemIdTourFake!);
      _itemIdTourFake = null;
      if (_itemIdTourFake2 != null) {
        try { context.read<OrcamentoProvider>().removerItem(_itemIdTourFake2!); } catch (_) {}
        _itemIdTourFake2 = null;
      }
      _materialTourAdicionado = false;

      setState(() {
        _mostrarResultados = true;
        _mostrarResultadoFakeNoDropdown = true;
      });
    } catch (_) {}
    return;
  }

  static const _materialIdTourFake = -999999;
  static const _materialIdTourFake2 = -999998;

  Future<void> _aguardarFramesReais({int quantidade = 3}) async {
    for (var i = 0; i < quantidade; i++) {
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!completer.isCompleted) completer.complete();
      });

      SchedulerBinding.instance.scheduleFrame();
      await completer.future.timeout(
        const Duration(milliseconds: 200),
        onTimeout: () {},
      );
    }
  }

  Future<void> _abrirDialogFornecedorTour() async {
    if (_dialogFornecedorTourAberto || _dialogFornecedorTourEmTransicao) return;

    await _aguardarFramesReais();
    if (!mounted || _dialogFornecedorTourAberto || _dialogFornecedorTourEmTransicao) return;
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) return;

    final itemId = _itemIdTourFake;
    if (itemId == null) return;
    final item = tab.itens.where((i) => i.itemId == itemId).firstOrNull;
    if (item == null) return;

    await context.read<FornecedorProvider>().carregar();
    if (!mounted) return;
    final fornecedores = context.read<FornecedorProvider>().fornecedores;
    final vinculadosNoServidor =
        await context.read<FornecedorProvider>().listarPorMaterial(item.materialId);
    if (!mounted) return;
    final idsJaVinculados = {
      ...item.precos.keys,
      ...vinculadosNoServidor.map((f) => f.id),
    };

    _dialogFornecedorTourAberto = true;
    _dialogFornecedorTourEmTransicao = true;
    final future = showDialog<List<int>>(
      context: context,

      barrierDismissible: !_dialogFornecedorTourAberto,
      builder: (_) => _DialogVincularFornecedores(
        fornecedores: fornecedores,
        idsJaVinculados: idsJaVinculados,
        materialNome: item.materialNome,
        ehTourAssistente: true,
      ),
    );
    _futureDialogFornecedorTour = future;
    future.then((selecionados) async {

      final aindaEhODialogAtual = identical(_futureDialogFornecedorTour, future);
      if (mounted && aindaEhODialogAtual) _dialogFornecedorTourAberto = false;
      if (selecionados == null || selecionados.isEmpty || !mounted) return;
      final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
      for (final fId in selecionados) {
        if (novosPrecos.containsKey(fId)) continue;

        if (fId == _fornecedorIdTourFake) {
          novosPrecos[fId] = PrecoFornecedorData(fornecedorNome: 'Fornecedor Exemplo');
          continue;
        }
        FornecedorModel? f;
        for (final cand in fornecedores) {
          if (cand.id == fId) { f = cand; break; }
        }
        if (f == null) continue;
        novosPrecos[fId] = PrecoFornecedorData(fornecedorNome: f.nomeFantasia);
      }
      provider.atualizarItemParcial(item.itemId, precos: novosPrecos);
      final repo = FornecedorRepository();
      for (final fId in selecionados) {

        if (fId == _fornecedorIdTourFake) continue;
        if (!idsJaVinculados.contains(fId)) {
          try { await repo.vincularMaterial(fId, {'materialId': item.materialId}); } catch (_) {}
        }
      }
      if (identical(_futureDialogFornecedorTour, future)) {
        _futureDialogFornecedorTour = null;
      }
    });

    await _aguardarFramesReais(quantidade: 1);
    _dialogFornecedorTourEmTransicao = false;
  }

  Future<void> _fecharDialogFornecedorTourSeAberto() async {
    if (!_dialogFornecedorTourAberto || _dialogFornecedorTourEmTransicao) return;
    _dialogFornecedorTourAberto = false;
    _dialogFornecedorTourEmTransicao = true;

    Navigator.of(context, rootNavigator: true)
        .maybePop<List<int>>([_fornecedorIdTourFake]);

    await _aguardarFramesReais();
    _dialogFornecedorTourEmTransicao = false;
  }

  Future<void> _abrirDialogPrecoTour() async {
    if (_dialogPrecoTourAberto || _dialogPrecoTourEmTransicao) return;

    await _aguardarFramesReais();
    if (!mounted || _dialogPrecoTourAberto || _dialogPrecoTourEmTransicao) return;
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) return;

    final itemId = _itemIdTourFake;
    if (itemId == null) return;
    final item = tab.itens.where((i) => i.itemId == itemId).firstOrNull;
    if (item == null) return;
    if (item.precos.isEmpty) return;
    final fornecedorId = item.precos.keys.first;
    final pf = item.precos[fornecedorId]!;

    _dialogPrecoTourAberto = true;
    _dialogPrecoTourEmTransicao = true;
    final future = showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: !_dialogPrecoTourAberto,
      builder: (_) => _DialogEditarMaterial(
        fornecedorNome: pf.fornecedorNome,
        materialNome: item.materialNome,
        precoAtual: pf.preco,
        precoMetroQuadradoAtual: pf.precoMetroQuadrado,
        observacaoAtual: pf.observacao,
        areaM2PorUnidade: item.areaM2PorUnidade,
        tourKeyCamposPrecoEDisponibilidade: _tourKeys.camposPrecoEDisponibilidadeDialog,
      ),
    );
    _futureDialogPrecoTour = future;
    future.then((result) {

      final aindaEhODialogAtual = identical(_futureDialogPrecoTour, future);
      if (mounted && aindaEhODialogAtual) _dialogPrecoTourAberto = false;
      if (result == null || !mounted) return;
      final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
      novosPrecos[fornecedorId] = PrecoFornecedorData(
        fornecedorNome: pf.fornecedorNome,
        preco: result['preco'] as double?,
        precoMetroQuadrado: result['precoMetroQuadrado'] as double?,
        observacao: result['observacao'] as String?,
      );
      provider.atualizarItemParcial(item.itemId, precos: novosPrecos);
      if (identical(_futureDialogPrecoTour, future)) {
        _futureDialogPrecoTour = null;
      }
    });

    await _aguardarFramesReais(quantidade: 1);
    _dialogPrecoTourEmTransicao = false;
  }

  Future<void> _fecharDialogPrecoTourSeAberto() async {
    if (!_dialogPrecoTourAberto || _dialogPrecoTourEmTransicao) return;
    _dialogPrecoTourAberto = false;
    _dialogPrecoTourEmTransicao = true;
    await Navigator.of(context, rootNavigator: true).maybePop<Map<String, dynamic>>(
      const {'preco': 99.9, 'observacao': null},
    );
    _dialogPrecoTourEmTransicao = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> _fecharDialogPrecoSemSalvar() async {
    if (!_dialogPrecoTourAberto || _dialogPrecoTourEmTransicao) return;
    _dialogPrecoTourAberto = false;
    _dialogPrecoTourEmTransicao = true;

    await Navigator.of(context, rootNavigator: true).maybePop<Map<String, dynamic>>();
    _dialogPrecoTourEmTransicao = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    _resetarPrecoFornecedorFake();
  }

  void _resetarPrecoFornecedorFake() {
    final itemId = _itemIdTourFake;
    if (itemId == null) return;
    try {
      final provider = context.read<OrcamentoProvider>();
      final tab = provider.tabAtual;
      if (tab == null) return;
      final item = tab.itens.where((i) => i.itemId == itemId).firstOrNull;
      if (item == null || item.precos.isEmpty) return;
      final fornecedorId = item.precos.keys.first;
      final pf = item.precos[fornecedorId]!;
      final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
      novosPrecos[fornecedorId] = PrecoFornecedorData(
        fornecedorNome: pf.fornecedorNome,
        preco: null,
        observacao: null,
      );
      provider.atualizarItemParcial(itemId, precos: novosPrecos);
    } catch (_) {}
  }

  Future<void> _desvincularFornecedorFakeEVoltarParaDialog() async {

    final itemId = _itemIdTourFake;
    if (itemId != null) {
      try {
        final provider = context.read<OrcamentoProvider>();
        final tab = provider.tabAtual;
        if (tab != null) {
          final item = tab.itens.where((i) => i.itemId == itemId).firstOrNull;
          if (item != null) {
            final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos)
              ..remove(_fornecedorIdTourFake);
            provider.atualizarItemParcial(itemId, precos: novosPrecos);
          }
        }
      } catch (_) {}
    }

    await _abrirDialogFornecedorTour();
  }

  Future<void> _reabrirDialogPrecoAoVoltar() async {
    _resetarPrecoFornecedorFake();
    await _abrirDialogPrecoTour();
  }

  Future<void> _fecharDialogFornecedorSemVincular() async {
    if (!_dialogFornecedorTourAberto || _dialogFornecedorTourEmTransicao) return;
    _dialogFornecedorTourAberto = false;
    _dialogFornecedorTourEmTransicao = true;

    Navigator.of(context, rootNavigator: true).maybePop<List<int>>();

    await _aguardarFramesReais();
    _dialogFornecedorTourEmTransicao = false;
  }

  void _anexarParadasDoEditorAoTour() {
    final rota = ModalRoute.of(context);
    if (rota == null || !rota.isCurrent) return;

    final helper = context.read<RoboHelperProvider>();
    final opcoesAtuais = helper.opcoesAtuais;
    final opcaoBase = opcoesAtuais.where((o) => o.titulo == 'Como criar um orçamento').firstOrNull;

    const totalParadasBase = 2;
    if (opcaoBase == null || opcaoBase.paradas.length < totalParadasBase) return;
    if (opcaoBase.paradas.length > totalParadasBase) return;

    final paradasBase = opcaoBase.paradas;

    helper.registrarOpcoes('/orcamento', [
      RoboHelpOption(
        titulo: 'Como criar um orçamento',
        paradas: [

          ...paradasBase,
          RoboTourStop(
            key: () => _tourKeys.primeiroResultadoDropdown,
            texto: 'Ao encontrar o material desejado na lista de '
                'sugestões, toque nele para adicioná-lo ao orçamento.',
            aoEntrar: _mostrarCardFakeNoDropdown,
            aoSair: _fecharDropdownTourFakeSeAberto,
          ),
          RoboTourStop(
            key: () => _tourKeys.botaoAdicionarFornecedor,
            texto: 'Com o material adicionado, toque aqui para vincular '
                'fornecedores a ele e poder comparar preços.',
            aoEntrar: _inserirMaterialTourFakeNaTabela,
            aoSair: _voltarParaDropdownDoMaterialFake,
          ),
          RoboTourStop(
            key: () => _tourKeys.buscaFornecedorDialog,
            texto: 'Busque pelo nome do fornecedor que deseja adicionar.',

            aoEntrar: _abrirDialogFornecedorTour,

            aoSair: _fecharDialogFornecedorSemVincular,
          ),
          RoboTourStop(
            key: () => _tourKeys.primeiroFornecedorDialog,
            texto: 'Marque um ou mais fornecedores e toque em "Adicionar".',
          ),
          RoboTourStop(
            key: () => _tourKeys.campoQuantidadeMaterial1,
            texto: 'Aqui você informa a quantidade deste material. Como '
                'a unidade dele é "Unidade", não existe o campo '
                '"Quantidade por Unidade" — ele só aparece para materiais '
                'medidos em m/l, g, ml, etc., como no material logo abaixo.',

            aoEntrar: _fecharDialogFornecedorTourSeAberto,

            aoSair: _desvincularFornecedorFakeEVoltarParaDialog,
          ),
          RoboTourStop(
            key: () => _tourKeys.campoQtdUnidadeMaterial2,
            texto: 'Para materiais como este (m/l, g, ml, etc.), informe '
                'aqui a quantidade de m/l, g, ml, etc. que vem em cada '
                'unidade/embalagem — esse valor é repassado para a Ordem '
                'de Compra ao gerá-la.',
          ),
          RoboTourStop(
            key: () => _tourKeys.editarPreco,
            texto: 'O fornecedor aparece como "Sem preço" até você '
                'informar o valor — toque em "editar" para cadastrá-lo.',

          ),
          RoboTourStop(
            key: () => _tourKeys.camposPrecoEDisponibilidadeDialog,
            texto: 'Informe o preço e a disponibilidade (opcional) '
                'deste fornecedor para o material e toque em "Salvar".',
            aoEntrar: _abrirDialogPrecoTour,

            aoSair: _fecharDialogPrecoSemSalvar,
          ),
          RoboTourStop(
            key: () => _tourKeys.celulaFornecedor,
            texto: 'Agora, toque no preço do fornecedor desejado para '
                'escolhê-lo como o fornecedor deste material no orçamento.',

            aoEntrar: _fecharDialogPrecoTourSeAberto,

            aoSair: _reabrirDialogPrecoAoVoltar,
          ),
          RoboTourStop(
            key: () => _tourKeys.botaoOrcarPor,
            texto: 'Aqui você pode escolher a forma de orçamento: por '
                'Unidade (preço por peça/rolo) ou por Metro Linear.',
          ),
          RoboTourStop(
            key: () => _tourKeys.botaoEnviarParaAprovacao,
            texto: 'Pronto! Agora é só tocar em "Enviar para aprovação" '
                'para concluir o orçamento.',
          ),
        ],
      ),
    ]);
  }

  Future<void> _adicionarFornecedoresBulk() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || _materiaisParaBulk.isEmpty) return;

    final materiaisSelecionados = tab.itens.where((i) => _materiaisParaBulk.contains(i.itemId)).toList();
    final fornecedores = context.read<FornecedorProvider>().fornecedores;

    final fornecedoresIds = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _DialogSelecionarFornecedoresBulk(
        fornecedores: fornecedores,
        qtdMateriais: materiaisSelecionados.length,
      ),
    );

    if (fornecedoresIds == null || fornecedoresIds.isEmpty) return;

    final repo = FornecedorRepository();
    for (final item in materiaisSelecionados) {
      final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
      for (final fId in fornecedoresIds) {
        if (!novosPrecos.containsKey(fId)) {
          final f = fornecedores.firstWhere((f) => f.id == fId);
          novosPrecos[fId] = PrecoFornecedorData(fornecedorNome: f.nomeFantasia);
          try {
            await repo.vincularMaterial(fId, {'materialId': item.materialId});
          } catch (_) {}
        }
      }
      provider.atualizarItemParcial(item.itemId, precos: novosPrecos);
    }

    setState(() => _materiaisParaBulk.clear());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${fornecedoresIds.length} fornecedor${fornecedoresIds.length > 1 ? 'es' : ''} adicionado${fornecedoresIds.length > 1 ? 's' : ''} a ${materiaisSelecionados.length} materi${materiaisSelecionados.length > 1 ? 'ais' : 'al'}'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  Future<void> _vincularFornecedores(int itemIndex) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || itemIndex >= tab.itens.length) return;
    final item = tab.itens[itemIndex];

    await context.read<FornecedorProvider>().carregar();
    if (!mounted) return;

    final fornecedores = context.read<FornecedorProvider>().fornecedores;

    final vinculadosNoServidor =
        await context.read<FornecedorProvider>().listarPorMaterial(item.materialId);
    if (!mounted) return;

    final idsJaVinculados = {
      ...item.precos.keys,
      ...vinculadosNoServidor.map((f) => f.id),
    };

    final selecionados = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _DialogVincularFornecedores(
        fornecedores: fornecedores,
        idsJaVinculados: idsJaVinculados,
        materialNome: item.materialNome,
      ),
    );
    if (selecionados == null || selecionados.isEmpty) return;

    final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
    for (final fId in selecionados) {
      if (!novosPrecos.containsKey(fId)) {
        final f = fornecedores.firstWhere((f) => f.id == fId);
        novosPrecos[fId] = PrecoFornecedorData(fornecedorNome: f.nomeFantasia);
      }
    }
    provider.atualizarItemParcial(item.itemId, precos: novosPrecos);

    final repo = FornecedorRepository();
    for (final fId in selecionados) {
      if (!idsJaVinculados.contains(fId)) {
        try { await repo.vincularMaterial(fId, {'materialId': item.materialId}); } catch (_) {}
      }
    }
  }

  Future<void> _editarPreco(int itemIndex, int fornecedorId) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || itemIndex >= tab.itens.length) return;
    final item = tab.itens[itemIndex];
    final pf = item.precos[fornecedorId]!;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _DialogEditarMaterial(
        fornecedorNome: pf.fornecedorNome,
        materialNome: item.materialNome,
        precoAtual: pf.preco,
        precoMetroQuadradoAtual: pf.precoMetroQuadrado,
        observacaoAtual: pf.observacao,
        areaM2PorUnidade: item.areaM2PorUnidade,
      ),
    );
    if (result == null) return;

    final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
    novosPrecos[fornecedorId] = PrecoFornecedorData(
      fornecedorNome: pf.fornecedorNome,
      preco: result['preco'] as double?,
      precoMetroQuadrado: result['precoMetroQuadrado'] as double?,
      observacao: result['observacao'] as String?,
    );
    provider.atualizarItemParcial(item.itemId, precos: novosPrecos);

    setState(() => _salvando = true);
    try {
      await FornecedorRepository().atualizarPreco(fornecedorId, item.materialId, {
        if (result['preco'] != null) 'preco': result['preco'],
        if (result['precoMetroQuadrado'] != null) 'precoMetroQuadrado': result['precoMetroQuadrado'],
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _sincronizarFornecedoresOcultos(int orcId, OrcamentoTab tab) async {
    if (tab.fornecedoresOcultos.isEmpty) return;
    final repo = OrcamentoRepository();
    // Cópia defensiva pelo mesmo motivo do snapshot em _persistirItensDaAba:
    // evita "Concurrent modification" se a lista for trocada por um evento
    // SSE durante os awaits abaixo.
    final ocultosSnapshot = List<int>.of(tab.fornecedoresOcultos);
    for (final fornecedorId in ocultosSnapshot) {
      await repo.definirFornecedorOculto(orcId, fornecedorId, true);
    }
  }

  /// Persiste os itens de [tab] no orçamento [orcId], substituindo o que
  /// estiver salvo no servidor pelo estado local atual. Extraído de
  /// `_salvarOrcamento` para ser reaproveitado pelo auto-save silencioso
  /// (`_salvarSilenciosamenteAoSair`), que precisa da mesma lógica de
  /// persistência mas sem diálogo de nome e sem fechar a aba.
  Future<void> _persistirItensDaAba(int orcId, OrcamentoTab tab) async {
    final repo = OrcamentoRepository();
    await _sincronizarFornecedoresOcultos(orcId, tab);

    // Cópia defensiva: montar a lista roda síncrono, mas o PUT abaixo é um
    // await, e nesse meio-tempo um evento SSE (_onProviderTempoRealChanged)
    // pode disparar substituirItensTab() na mesma lista, causando
    // "Concurrent modification during iteration" se iterássemos a lista viva.
    final itensSnapshot = List<ItemOrcamentoData>.of(tab.itens);

    // Antes: limparItens() (DELETE de tudo) + N x adicionarItem(), cada um
    // emitindo seu próprio evento SSE 'orcamento_item_alterado'. Isso fazia
    // quem estivesse só VISUALIZANDO o mesmo orçamento receber uma rajada de
    // N+1 eventos, incluindo um estado intermediário em que o orçamento
    // ficava momentaneamente SEM NENHUM item (logo após o limpar, antes do
    // primeiro item voltar) — causando a tela "piscar" ou, em caso de queda
    // de rede no meio da sequência, ficar de fato dessincronizada/incompleta.
    //
    // Agora: um único PUT atômico no backend (delete + insert em uma
    // transação, 1 evento SSE só com o resultado final). Quem está
    // visualizando recebe direto o estado final consistente.
    final itensPayload = <Map<String, dynamic>>[];
    for (final item in itensSnapshot) {
      if (item.precos.isEmpty) {
        itensPayload.add({
          'materialId': item.materialId,
          'fornecedorId': null,
          'quantidade': item.quantidade,
          'qtdUnidade': item.qtdUnidade,
          'precoUnitario': null,
          'selecionado': false,
        });
      } else {
        for (final entry in item.precos.entries) {
          itensPayload.add({
            'materialId': item.materialId,
            'fornecedorId': entry.key,
            'quantidade': item.quantidade,
            'qtdUnidade': item.qtdUnidade,
            'precoUnitario': entry.value.preco,
            'selecionado': item.fornecedorSelecionado == entry.key,
            'observacao': entry.value.observacao,
          });
        }
      }
    }

    await repo.substituirItens(orcId, itensPayload);
  }

  /// Auto-save silencioso disparado ao clicar em "Voltar": persiste o
  /// rascunho atual no servidor (criando o orçamento se ainda não existir),
  /// sem diálogo de nome e sem fechar a aba — diferente de `_salvarOrcamento`,
  /// que é o fluxo explícito de "Salvar"/"Enviar para aprovação". Isso evita
  /// que material adicionado ou título alterado localmente se perca quando o
  /// usuário sai do editor sem clicar em "Salvar" e depois reabre a mesma
  /// guia (nesse caso ela é reidratada a partir do servidor).
  ///
  /// Falhas de rede aqui não bloqueiam a navegação: o usuário ainda consegue
  /// voltar mesmo se o servidor estiver indisponível, só que nesse caso as
  /// alterações locais continuam existindo apenas na aba (SharedPreferences)
  /// até a próxima tentativa de salvar.
  Future<void> _salvarSilenciosamenteAoSair() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) return;

    // Mesmo cuidado que _salvarOrcamento: espera qualquer criação inicial em
    // voo terminar antes de decidir entre criar ou atualizar, para não
    // duplicar o orçamento no servidor.
    await provider.aguardarCriacaoInicial();

    try {
      final repo = OrcamentoRepository();
      int orcId;
      final eraNovo = tab.servidorId == null;
      if (!eraNovo) {
        orcId = tab.servidorId!;
        await repo.atualizarOrcamento(orcId, {'titulo': tab.titulo, 'modoPrecificacao': tab.modoPrecificacao});
      } else {
        final criado = await repo.criar(tab.titulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': tab.titulo, 'modoPrecificacao': tab.modoPrecificacao});
      }

      final tabAtual = provider.tabAtual;
      // A aba pode ter sido fechada enquanto as chamadas acima estavam em
      // voo (ex.: usuário clicou rápido em "Voltar" mais de uma vez) — nesse
      // caso não há mais estado local para persistir itens.
      if (tabAtual == null || tabAtual.id != tab.id) return;

      if (eraNovo) {
        tabAtual.servidorId = orcId;
        tabAtual.criadorId = provider.usuarioAtualId;
        try {
          await repo.travar(orcId);
        } catch (_) {
          // Sem trava não bloqueia o auto-save; o heartbeat normal do
          // editor tenta de novo se a aba for reaberta depois.
        }
      }

      await _persistirItensDaAba(orcId, tabAtual);
      provider.salvarAbasAgora();
      provider.marcarAbaAtivaComoSalva();
    } catch (e) {
      debugPrint('OrcamentoEditorPage._salvarSilenciosamenteAoSair erro: $e');
    }
  }

  /// Ponto único chamado pelo botão "Voltar" do editor. Salva silenciosamente
  /// qualquer alteração local pendente e sai, sem exibir diálogo de
  /// confirmação.
  Future<void> _aoClicarVoltar() async {
    // Diálogo "Salvar alterações?" removido: agora sempre salva
    // silenciosamente ao sair, sem perguntar ao usuário.
    await _salvarSilenciosamenteAoSair();
    if (!mounted) return;

    // Nunca chame pop() sem checar canPop(): se esta rota for a única na
    // pilha (ex: deep link direto para o editor, ou um pop concorrente já
    // aconteceu durante o await acima), pop() lança uma assertion do
    // go_router ('currentConfiguration.isNotEmpty') que corrompe o estado do
    // Navigator e derruba o app. Quando não há mais nada para voltar,
    // navegamos explicitamente para a tela de Orçamento em vez de tentar
    // pop().
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      GoRouter.of(context).go('/orcamento');
    }
  }

  Future<void> _salvarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos um material para salvar.')));
      return;
    }

    // Se a aba acabou de ser aberta, pode existir um POST /orcamentos
    // inicial ainda em voo (ver OrcamentoProvider._novaAba) — espera ele
    // terminar antes de decidir entre criar (servidorId nulo) ou atualizar,
    // para não duplicar o orçamento no servidor.
    await provider.aguardarCriacaoInicial();
    if (!mounted) return;

    final tituloCtrl = TextEditingController(text: tab.titulo);
    final novoTitulo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        bool vazio = false;
        return AlertDialog(
          title: Text(tab.servidorId != null ? 'Atualizar Orçamento' : 'Salvar Orçamento', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Nome do orçamento:', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              TextField(
                controller: tituloCtrl,
                autofocus: true,
                inputFormatters: [_NoCommaFormatter()],
                decoration: InputDecoration(hintText: 'Ex: Orçamento Obra Abril', isDense: true, errorText: null),
                onChanged: (_) { if (vazio && tituloCtrl.text.trim().isNotEmpty) { setSt(() => vazio = false); } },
              ),
            ]),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.success).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () { if (tituloCtrl.text.trim().isEmpty) { setSt(() => vazio = true); return; } Navigator.pop(ctx, tituloCtrl.text.trim()); },
              child: Text(tab.servidorId != null ? 'Atualizar' : 'Salvar'),
            ),
          ],
        );
      }),
    );
    if (novoTitulo == null) return;

    provider.renomearAba(provider.abaAtiva, novoTitulo);
    setState(() => _salvando = true);
    try {
      final repo = OrcamentoRepository();
      int orcId;
      if (tab.servidorId != null) {
        orcId = tab.servidorId!;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo, 'modoPrecificacao': tab.modoPrecificacao});
      } else {
        final criado = await repo.criar(novoTitulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo, 'modoPrecificacao': tab.modoPrecificacao});
      }
      final tabAtualizado = provider.tabAtual!;
      // Usa o mesmo _persistirItensDaAba (PUT atômico, 1 evento SSE só) do
      // auto-save ao sair — ver comentário lá para o motivo de não usar mais
      // limparItens() + N x adicionarItem() aqui.
      await _persistirItensDaAba(orcId, tabAtualizado);
      if (!mounted) return;
      if (_servidorIdComTravaAtiva == orcId) _servidorIdComTravaAtiva = null;
      provider.fecharAbaAposOperacao();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento #$orcId salvo com sucesso!'), backgroundColor: AppTheme.success));
      _fecharEditorComSeguranca(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'salvar orçamento')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _iniciarRenomeacaoAba(int index) {
    final provider = context.read<OrcamentoProvider>();
    final aba = provider.abas[index];
    setState(() {
      _abaRenomeando = index;
      _renomeCtrl?.dispose();
      _renomeCtrl = TextEditingController(text: aba.titulo);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _renomeFocusNode.requestFocus();
      _renomeCtrl?.selection = TextSelection(baseOffset: 0, extentOffset: _renomeCtrl!.text.length);
    });
  }

  Future<void> _confirmarRenomeacaoAba(int index) async {
    final provider = context.read<OrcamentoProvider>();
    final novoTitulo = _renomeCtrl?.text.trim() ?? '';
    setState(() => _abaRenomeando = null);
    if (novoTitulo.isEmpty || index < 0 || index >= provider.abas.length) return;

    final aba = provider.abas[index];
    if (novoTitulo == aba.titulo) return;

    provider.renomearAba(index, novoTitulo);

    final servidorId = aba.servidorId;
    if (servidorId != null) {
      try {
        await OrcamentoRepository().atualizarOrcamento(servidorId, {'titulo': novoTitulo});
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'renomear orçamento')), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _enviarParaAprovacao() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos um material antes de enviar para aprovação.')));
      return;
    }

    // Mesmo motivo do _salvarOrcamento: evita duplicar o orçamento no
    // servidor se o POST inicial (ver OrcamentoProvider._novaAba) ainda
    // não retornou.
    await provider.aguardarCriacaoInicial();
    if (!mounted) return;

    final tituloCtrl = TextEditingController(text: tab.titulo);
    final novoTitulo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        bool vazio = false;
        return AlertDialog(
          title: Text('Enviar para Aprovação', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Nome do orçamento:', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              TextField(
                controller: tituloCtrl, autofocus: true, inputFormatters: [_NoCommaFormatter()],
                decoration: InputDecoration(hintText: 'Ex: Orçamento Obra Abril', isDense: true, errorText: null),
                onChanged: (_) { if (vazio && tituloCtrl.text.trim().isNotEmpty) { setSt(() => vazio = false); } },
              ),
              SizedBox(height: 14),
              Text('Após o envio, aguarde Admin/Gerente aprovar antes de gerar a Ordem de Compra.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () { if (tituloCtrl.text.trim().isEmpty) { setSt(() => vazio = true); return; } Navigator.pop(ctx, tituloCtrl.text.trim()); },
              child: const Text('Enviar para Aprovação'),
            ),
          ],
        );
      }),
    );
    if (novoTitulo == null) return;

    provider.renomearAba(provider.abaAtiva, novoTitulo);
    setState(() => _salvando = true);
    try {
      final repo = OrcamentoRepository();
      int orcId;
      final sid = provider.tabAtual?.servidorId;
      if (sid != null) {
        orcId = sid;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo, 'modoPrecificacao': tab.modoPrecificacao});
        await repo.limparItens(orcId);
      } else {
        final criado = await repo.criar(novoTitulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo, 'modoPrecificacao': tab.modoPrecificacao});
      }
      await _sincronizarFornecedoresOcultos(orcId, tab);
      // Cópia defensiva: o loop abaixo faz vários awaits sequenciais (um
      // POST por item/fornecedor), e nesse meio-tempo um evento SSE
      // (_onProviderTempoRealChanged) pode disparar substituirItensTab() na
      // mesma lista — outro usuário só visualizando este orçamento recebe
      // esses eventos normalmente. Iterar a lista viva de `tab.itens`
      // nessas condições lança "Concurrent modification during iteration"
      // (mesmo cuidado já tomado em `_persistirItensDaAba`).
      final itensSnapshot = List<ItemOrcamentoData>.of(tab.itens);
      for (final item in itensSnapshot) {
        if (item.precos.isEmpty) {
          await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': null, 'selecionado': false});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': entry.value.preco, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
          }
        }
      }
      await repo.enviarParaAprovacao(orcId);
      if (_servidorIdComTravaAtiva == orcId) _servidorIdComTravaAtiva = null;
      provider.limparAba();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento #$orcId enviado para aprovação com sucesso!'), backgroundColor: AppTheme.success));
      provider.atualizarFlagsTab(aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);

      _fecharEditorComSeguranca(context, 'enviadoParaAprovacao');
    } catch (e) {
      if (mounted) {
        if (_isErroDeStatusDesatualizado(e)) {
          await _sincronizarStatusServidor(origem: 'erroEnviarAprovacao');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('O status deste orçamento mudou (outra pessoa já enviou ou aprovou). A tela foi atualizada.'),
              backgroundColor: AppTheme.error,
            ));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'enviar para aprovação')), backgroundColor: AppTheme.error));
        }
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _aprovarOrcamento(int id, String titulo) async {
    _logOrc('aprovarOrcamento: botão clicado orcamentoId=$id titulo="$titulo"');
    final provider = context.read<OrcamentoProvider>();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar Orçamento', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('Deseja aprovar este orçamento?\n\nApós a aprovação, o usuário Compras poderá gerar uma Ordem de Compra.', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    _logOrc('aprovarOrcamento: diálogo de confirmação fechado, resultado=$confirmar orcamentoId=$id');
    if (confirmar != true) return;

    setState(() => _salvando = true);
    final inicio = DateTime.now();
    final tab = provider.tabAtual;
    try {
      if (tab != null) {
        final repo = OrcamentoRepository();
        _logOrc('aprovarOrcamento: salvando modo de precificação orcamentoId=$id modo=${tab.modoPrecificacao}');
        await repo.atualizarOrcamento(id, {'modoPrecificacao': tab.modoPrecificacao});
        _logOrc('aprovarOrcamento: limpando itens no servidor orcamentoId=$id');
        await repo.limparItens(id);
        _logOrc('aprovarOrcamento: regravando ${tab.itens.length} itens orcamentoId=$id');
        // Cópia defensiva: mesmo motivo do fluxo de "Enviar para aprovação"
        // (ver comentário em _enviarParaAprovacao) — evita "Concurrent
        // modification during iteration" se um evento SSE mutar tab.itens
        // durante os awaits deste loop.
        final itensSnapshot = List<ItemOrcamentoData>.of(tab.itens);
        for (final item in itensSnapshot) {
         if (item.precos.isEmpty) {
          await repo.adicionarItem(id, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': null, 'selecionado': false});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(id, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': entry.value.preco, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
          }
        }
        }
      } else {
        _logOrc('aprovarOrcamento: AVISO tabAtual é null, pulando regravação de itens orcamentoId=$id', level: 900);
      }
      _logOrc('aprovarOrcamento: chamando PATCH /orcamentos/$id/aprovar');
      await OrcamentoRepository().aprovar(id);
      _logOrc('aprovarOrcamento: sucesso em ${DateTime.now().difference(inicio).inMilliseconds}ms orcamentoId=$id');
      if (!mounted) {
        _logOrc('aprovarOrcamento: sucesso no servidor mas widget já desmontado orcamentoId=$id', level: 900);
        return;
      }
      provider.atualizarFlagsTab(aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);
      provider.fecharAbaAposOperacao();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento #$id aprovado com sucesso!'), backgroundColor: AppTheme.success));

      _fecharEditorComSeguranca(context, 'aprovado');
    } catch (e, st) {
      _logOrc('aprovarOrcamento: ERRO após ${DateTime.now().difference(inicio).inMilliseconds}ms orcamentoId=$id',
          erro: e, stack: st, level: 1000);
      if (mounted) {
        if (_isErroDeStatusDesatualizado(e)) {
          await _sincronizarStatusServidor(origem: 'erroAprovar');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('O status deste orçamento mudou (outra pessoa já aprovou ou alterou). A tela foi atualizada.'),
              backgroundColor: AppTheme.error,
            ));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'aprovar orçamento')), backgroundColor: AppTheme.error));
        }
      }
    } finally {
      _logOrc('aprovarOrcamento: finally, liberando _salvando orcamentoId=$id mounted=$mounted');
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Garante que a trava de edição no servidor reflete exatamente a guia
  /// (aba) ativa agora nesta instância do editor:
  ///  1. Se este editor detém a trava de um orçamento que NÃO é mais o da
  ///     aba ativa (usuário trocou de guia), libera essa trava primeiro.
  ///  2. Se a aba ativa tem servidorId e este editor ainda não detém a
  ///     trava dela, tenta assumir a edição no servidor.
  ///     - Sucesso: aba fica editável (somenteLeitura = false, a menos que
  ///       já estivesse marcada assim por outro motivo, ex: usuário não é
  ///       o criador em um fluxo que exige isso).
  ///     - 409 (outro usuário já editando): aba vira somente-leitura e
  ///       mostramos quem está editando, sem interromper o usuário com um
  ///       diálogo bloqueante — ele só não conseguirá alterar nada até a
  ///       outra pessoa soltar a edição (aviso chega via SSE
  ///       'orcamento_destravado').
  ///     - Outro erro (rede etc.): não trava, mas também não bloqueia a UI;
  ///       a próxima tentativa (troca de aba, heartbeat, retomada do app)
  ///       tenta de novo.
  ///
  /// Chamado em: abrir o editor (initState), trocar de aba, uma aba recém
  /// criada terminar de salvar no servidor (servidorId chega depois),
  /// retomar o app (lifecycle resumed) e reconectar após queda de SSE.
  Future<void> _garantirTravaAbaAtiva({String origem = 'manual'}) async {
    if (!mounted) return;
    if (_aquisicaoTravaEmAndamento) return;
    _aquisicaoTravaEmAndamento = true;
    try {
      final provider = context.read<OrcamentoProvider>();
      final tab = provider.tabAtual;
      final sidAtivo = tab?.servidorId;

      // 1) Libera a trava anterior se ela não pertence mais à aba ativa.
      if (_servidorIdComTravaAtiva != null && _servidorIdComTravaAtiva != sidAtivo) {
        final antigo = _servidorIdComTravaAtiva!;
        _servidorIdComTravaAtiva = null;
        try {
          await OrcamentoRepository().destravar(antigo);
          _logOrc('_garantirTravaAbaAtiva[$origem]: liberou trava orcamentoId=$antigo (troca de aba)');
        } catch (e) {
          _logOrc('_garantirTravaAbaAtiva[$origem]: falha ao liberar trava orcamentoId=$antigo (expira sozinha)', erro: e);
        }
      }

      if (sidAtivo == null) return; // rascunho ainda sem servidorId, nada a travar

      if (_servidorIdComTravaAtiva == sidAtivo) return; // já é dono, nada a fazer

      // Mesmo que a aba esteja marcada como somenteLeitura (ex: foi aberta
      // via _abrirOrcamentoEmAberto enquanto outra pessoa editava), ainda
      // tentamos travar aqui: se a outra pessoa já soltou a edição nesse
      // meio-tempo, o usuário deve poder assumi-la ao voltar para esta aba
      // em vez de ficar preso em somente-leitura para sempre. Se falhar
      // (409), a aba simplesmente continua somente-leitura — comportamento
      // correto.

      try {
        await OrcamentoRepository().travar(sidAtivo);
        _servidorIdComTravaAtiva = sidAtivo;
        if (!mounted) return;
        if (provider.tabAtual?.servidorId == sidAtivo && provider.tabAtual!.somenteLeitura) {
          provider.atualizarFlagsTab(somenteLeitura: false);
        }
        _logOrc('_garantirTravaAbaAtiva[$origem]: assumiu trava orcamentoId=$sidAtivo');
      } on OrcamentoTravadoException catch (e) {
        _logOrc('_garantirTravaAbaAtiva[$origem]: orcamentoId=$sidAtivo já travado por ${e.travaUsuarioNome}');
        if (!mounted) return;
        if (provider.tabAtual?.servidorId == sidAtivo && !provider.tabAtual!.somenteLeitura) {
          provider.atualizarFlagsTab(somenteLeitura: true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${e.travaUsuarioNome ?? 'Outro usuário'} está editando este orçamento agora. Você está em modo visualização.'),
            backgroundColor: AppTheme.warning,
          ));
        }
      } catch (e) {
        _logOrc('_garantirTravaAbaAtiva[$origem]: erro de rede/servidor ao travar orcamentoId=$sidAtivo, tentará de novo depois', erro: e);
      }
    } finally {
      _aquisicaoTravaEmAndamento = false;
    }
  }

  Future<void> _sincronizarStatusServidor({String origem = 'manual'}) async {
    final provider = context.read<OrcamentoProvider>();
    final sid = provider.tabAtual?.servidorId;

    if (_syncing) {
      _logOrc('sincronizarStatusServidor[$origem]: ignorado (já existe uma sincronização em andamento) orcamentoId=$sid');
      return;
    }
    _syncing = true;
    final inicio = DateTime.now();
    try {

      if (sid != null) {
        _logOrc('sincronizarStatusServidor[$origem]: iniciando GET /orcamentos/$sid');

        final orc = await OrcamentoRepository().buscarPorId(sid);
        if (!mounted) {
          _logOrc('sincronizarStatusServidor[$origem]: resposta chegou mas widget já foi desmontado, ignorando orcamentoId=$sid');
          return;
        }
        final status = orc['status'] as String? ?? '';
        _logOrc('sincronizarStatusServidor[$origem]: sucesso em ${DateTime.now().difference(inicio).inMilliseconds}ms '
            'orcamentoId=$sid status=$status');
        provider.atualizarFlagsTab(
          aguardandoAprovacao: status == 'AGUARDANDO_APROVACAO',
          jaFinalizado: status == 'APROVADO' || status == 'NAO_APROVADO',
          modoGerarOC: status == 'APROVADO',
        );

        // Renova a trava de edição (heartbeat) se este editor é quem a
        // detém. Não travamos aqui pela primeira vez — isso é feito ao
        // abrir o orçamento (ver _abrirOrcamentoEmAberto na page e
        // _garantirTravaAbaAtiva abaixo) — só mantemos viva a que já temos.
        if (status == 'ABERTO' && _servidorIdComTravaAtiva == sid) {
          try {
            await OrcamentoRepository().heartbeatTrava(sid);
          } catch (_) {
            // Falha aqui é inofensiva por si só (o próximo ciclo tenta de
            // novo); se a trava realmente expirou e outro usuário assumiu,
            // o evento SSE 'orcamento_travado' avisa este editor de qualquer forma.
          }
        }
      } else {
        _logOrc('sincronizarStatusServidor[$origem]: aba sem servidorId (rascunho ainda não salvo) — '
            'pulando sync de status, mas atualizando dados dos materiais mesmo assim');
      }

      if (!mounted) return;
      final materialProvider = context.read<MaterialProvider>();
      await materialProvider.carregar();
      if (!mounted) return;
      provider.atualizarDadosMateriaisDosItens(materialProvider.materiais);
    } catch (e, st) {
      // Resíduo de dados locais (guia salva em SharedPreferences apontando
      // para um servidorId que não existe mais no banco — ex: uma aba que
      // ficou aberta de antes de uma correção de exclusão, ou o orçamento
      // foi excluído por outra guia/usuário enquanto esta ficava aberta).
      // Em vez de deixar a guia presa mostrando erro a cada 30s
      // indefinidamente, fecha ela sozinha e avisa o usuário.
      if (_isErroOrcamentoNaoEncontrado(e) && sid != null) {
        _logOrc('sincronizarStatusServidor[$origem]: orcamentoId=$sid não existe mais no servidor — fechando guia automaticamente', erro: e, level: 500);
        if (_servidorIdComTravaAtiva == sid) _servidorIdComTravaAtiva = null;
        if (mounted) {
          final provider2 = context.read<OrcamentoProvider>();
          final idx = provider2.abas.indexWhere((a) => a.servidorId == sid);
          if (idx >= 0) {
            provider2.fecharAba(idx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Este orçamento já foi excluído. A guia foi fechada.'),
              backgroundColor: AppTheme.warning,
            ));
            // Se essa era a última guia, sai do editor (mesmo padrão usado
            // ao fechar a última guia pelo "x" — ver o onTap do botão de
            // fechar guia mais abaixo neste arquivo).
            if (provider2.abas.isEmpty && mounted) {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.pop();
              } else {
                GoRouter.of(context).go('/orcamento');
              }
            }
          }
        }
        return;
      }
      _logOrc('sincronizarStatusServidor[$origem]: ERRO orcamentoId=$sid', erro: e, stack: st, level: 1000);
    } finally {
      _syncing = false;
    }
  }

  /// Chamado ao clicar no "x" de uma guia.
  ///
  /// Em qualquer um dos dois casos abaixo, se houver alterações locais
  /// ainda não persistidas (`houveAlteracaoNaAbaAtiva`), pergunta primeiro
  /// se deve salvar — independentemente de quem edita ser ou não o criador.
  ///
  /// Comportamento depende de quem é o dono do orçamento na aba:
  /// - Se o usuário atual é o CRIADOR (ou é um rascunho local ainda sem
  ///   servidorId, que só pode ser dele mesmo): fechar a guia EXCLUI o
  ///   orçamento — perguntamos primeiro (e antes disso, se houver edição
  ///   pendente, oferecemos salvar), e só com confirmação de exclusão é que
  ///   ele é removido (cancelado + excluído no servidor) e a guia fecha.
  /// - Se o usuário atual NÃO é o criador (ex: abriu a guia de outra
  ///   pessoa pela seção "Em Aberto" para visualizar ou continuar uma
  ///   aprovação): fecha sem tocar no orçamento no servidor — ele continua
  ///   existindo para o dono original. Isso também vale quando a aba está
  ///   em modo somente-leitura (sinal de que a trava de edição já indicou
  ///   que o orçamento é de outra pessoa).
  Future<void> _salvarAoFecharAba(int index) async {
    final provider = context.read<OrcamentoProvider>();
    final abas = provider.abas;
    if (index < 0 || index >= abas.length) {
      provider.fecharAba(index);
      return;
    }
    final aba = abas[index];
    final sid = aba.servidorId;

    // Um rascunho local sem servidorId só pode ser meu (nenhum outro
    // usuário consegue ver/abrir uma aba que só existe no meu
    // SharedPreferences). Para um orçamento já salvo no servidor, o dono é
    // `aba.criadorId` — se ainda não foi preenchido por algum motivo E a
    // aba não está em modo somente-leitura, assumimos que é meu por
    // segurança de UX (mas o backend valida de verdade em cancelar/excluir).
    final ehDonoDoOrcamento = sid == null
        ? true
        : provider.souCriadorDe(aba.criadorId) || (aba.criadorId == null && !aba.somenteLeitura);

    if (!ehDonoDoOrcamento || aba.somenteLeitura) {
      // Não é meu orçamento (ou estou aqui só em modo leitura). Se houver
      // alterações locais ainda não salvas nesta aba — mesma checagem usada
      // pelo botão "Voltar" (ver `_aoClicarVoltar`, também sem distinguir
      // dono/não-dono) — perguntamos antes de fechar, em vez de simplesmente
      // descartar o que foi feito sem avisar.
      final precisaSalvar = !aba.somenteLeitura &&
          provider.tabAtual?.id == aba.id &&
          provider.houveAlteracaoNaAbaAtiva;

      if (precisaSalvar) {
        // Diálogo "Salvar alterações?" removido: salva silenciosamente
        // antes de fechar a guia, sem perguntar ao usuário.
        await _salvarSilenciosamenteAoSair();
        if (!mounted) return;
      }

      // Fecha a guia sem excluir nada no servidor — o orçamento continua
      // existindo para o dono original. IMPORTANTE: mesmo não sendo o
      // criador, é perfeitamente normal este usuário estar com a TRAVA DE
      // EDIÇÃO deste orçamento (ex: abriu pela seção "Em Aberto" e assumiu a
      // edição via _garantirTravaAbaAtiva) — "dono" (criador) e "quem está
      // editando agora" são conceitos diferentes. Por isso sempre tentamos
      // destravar no servidor aqui, não só limpar a referência local: sem
      // isso, a guia fecha mas o orçamento continua marcado como "em
      // edição" por este usuário para todo mundo até a trava expirar
      // sozinha (60s).
      if (sid != null && _servidorIdComTravaAtiva == sid) {
        _servidorIdComTravaAtiva = null;
        OrcamentoRepository().destravar(sid).catchError((e) {
          _logOrc('_salvarAoFecharAba: falha ao destravar orcamentoId=$sid ao fechar guia de terceiro (expira sozinha)', erro: e);
        });
      }
      provider.fecharAba(index);
      return;
    }

    // Sou o dono e o orçamento já existe no servidor (sid != null): fechar a
    // guia leva à exclusão permanente logo abaixo. Se ainda houver edições
    // locais não persistidas (ex.: item alterado nos últimos instantes,
    // antes do debounce de auto-save disparar), oferece salvar antes de
    // decidir sobre excluir — evita que um "Excluir orçamento" apague
    // silenciosamente uma mudança que o usuário não tinha intenção de
    // descartar junto com o orçamento inteiro.
    if (sid != null &&
        provider.tabAtual?.id == aba.id &&
        provider.houveAlteracaoNaAbaAtiva) {
      // Diálogo "Salvar alterações?" removido: salva silenciosamente antes
      // de seguir para a pergunta de exclusão abaixo.
      await _salvarSilenciosamenteAoSair();
      if (!mounted) return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fechar guia',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          sid != null
              ? 'Ao fechar esta guia, o orçamento "${aba.titulo}" será excluído '
                'permanentemente e não poderá ser recuperado.\n\n'
                'Deseja continuar?'
              : 'Este rascunho ainda não foi salvo no servidor. '
                'Ao fechar a guia ele será descartado.\n\n'
                'Deseja continuar?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(sid != null ? 'Excluir orçamento' : 'Descartar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    if (sid != null) {
      try {
        final repo = OrcamentoRepository();
        // O backend só permite DELETE em orçamentos CANCELADO/NAO_APROVADO/
        // CONVERTIDO (ver orcamento.service.js:excluir) — um orçamento
        // ABERTO precisa ser cancelado antes de poder ser excluído de fato.
        // Ambas as chamadas passam pelo backend com o usuário autenticado
        // do token, que valida de novo a propriedade (ver
        // orcamento.service.js:cancelar/excluir) — a checagem no app é só
        // para não mostrar a opção incorretamente, a validação real é lá.
        await repo.cancelar(sid);
        await repo.excluir(sid);
        if (_servidorIdComTravaAtiva == sid) _servidorIdComTravaAtiva = null;
      } catch (e) {
        // 404 "não encontrado" aqui significa que o orçamento JÁ FOI
        // excluído (por outra guia, por outro usuário, ou é resíduo de uma
        // guia salva localmente antes desta correção existir). O resultado
        // que o usuário queria — "esse orçamento não existe mais" — já é
        // verdade, então tratamos como sucesso e fechamos a guia numa boa,
        // em vez de bloquear com uma mensagem de erro sem saída.
        if (_isErroOrcamentoNaoEncontrado(e)) {
          _logOrc('_salvarAoFecharAba: orcamentoId=$sid já não existia (guia obsoleta) — fechando mesmo assim', erro: e);
          if (_servidorIdComTravaAtiva == sid) _servidorIdComTravaAtiva = null;
        } else {
          _logOrc('_salvarAoFecharAba: falha ao excluir orcamentoId=$sid', erro: e, level: 1000);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_mensagemErro(e, acao: 'excluir orçamento')),
              backgroundColor: AppTheme.error,
            ));
          }
          // Não fecha a guia se a exclusão falhou por outro motivo — evita
          // perder a referência a um orçamento que ainda existe no servidor.
          return;
        }
      }
    }

    provider.fecharAba(index);
  }

  Future<void> _cancelarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    final temServidorId = tab?.servidorId != null;
    if (temServidorId) {
      final motivo = await showDialog<String>(context: context, builder: (_) => const _DialogDescartarOrcamento());
      if (motivo == null) return;
    } else {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar Orçamento', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: const Text('Este orçamento ainda não foi salvo no servidor.\nDeseja descartar o rascunho?', style: TextStyle(fontSize: 13)),
          actions: [
            TextButton(style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)), onPressed: () => Navigator.pop(ctx, false), child: const Text('Não')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    setState(() => _salvando = true);
    try {
      if (temServidorId) {
        await OrcamentoRepository().cancelar(tab!.servidorId!);
        if (_servidorIdComTravaAtiva == tab.servidorId!) _servidorIdComTravaAtiva = null;
      }
      provider.fecharAbaAposOperacao();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(temServidorId ? 'Orçamento #${tab!.servidorId} cancelado.' : 'Rascunho descartado.'),
        backgroundColor: AppTheme.error,
      ));
      provider.atualizarFlagsTab(aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);
      _fecharEditorComSeguranca(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'cancelar orçamento')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  List<Map<String, dynamic>> _itensParaPdf(OrcamentoTab tab) {
    final ocultos = tab.fornecedoresOcultos.toSet();
    if (ocultos.isEmpty) return tab.itens.map((i) => i.toJson()).toList();

    return tab.itens.map((item) {
      final json = item.toJson();
      final precos = Map<String, dynamic>.from(json['precos'] as Map);
      precos.removeWhere((fIdStr, _) => ocultos.contains(int.parse(fIdStr)));
      json['precos'] = precos;
      if (item.fornecedorSelecionado != null && ocultos.contains(item.fornecedorSelecionado)) {
        json['fornecedorSelecionado'] = null;
      }
      return json;
    }).toList();
  }

  // ── Encaminhar orçamento para chat ────────────────────────────────────────
  // Disponível em qualquer status (aberto, aguardando aprovação, aprovado,
  // não aprovado etc.) desde que o orçamento já exista no servidor — antes
  // de salvo não há um id estável para o destinatário abrir depois. O card
  // no chat (EncaminhamentoChatCard) mostra o resumo abaixo e, ao ser
  // tocado, leva o destinatário direto para este orçamento na tela
  // "Orç. Compras" (ver OrcamentoProvider.solicitarAberturaOrcamento).
  String _statusAtualTab(OrcamentoTab tab) {
    if (tab.jaFinalizado) {
      // jaFinalizado cobre tanto APROVADO quanto NAO_APROVADO; usamos
      // modoGerarOC (só ligado para orçamentos aprovados) para distinguir.
      return tab.modoGerarOC ? 'APROVADO' : 'NAO_APROVADO';
    }
    if (tab.aguardandoAprovacao) return 'AGUARDANDO_APROVACAO';
    return 'ABERTO';
  }

  String _statusLabelParaEncaminhamento(String status) {
    switch (status) {
      case 'AGUARDANDO_APROVACAO':
        return 'Aguardando Aprovação';
      case 'APROVADO':
        return 'Aprovado';
      case 'NAO_APROVADO':
        return 'Não Aprovado';
      default:
        return 'Aberto';
    }
  }

  Future<void> _encaminharOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null) return;

    final servidorId = tab.servidorId;
    if (servidorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salve o orçamento antes de encaminhá-lo para o chat.')),
      );
      return;
    }

    final status = _statusAtualTab(tab);
    final dados = {
      'orcamentoId': servidorId,
      'titulo': tab.titulo,
      'status': status,
      'statusLabel': _statusLabelParaEncaminhamento(status),
      'quantidadeMateriais': tab.itens.length,
    };

    final enviado = await encaminharParaChat(context, tipo: 'orcamento', dados: dados);
    if (!mounted || !enviado) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Orçamento encaminhado no chat.')),
    );
  }

  Future<void> _exportarPdf() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos um material antes de exportar.')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );
    try {
      final pdfBytes = await OrcamentoRepository().gerarPdf({
        'titulo': tab.titulo,
        'itens': _itensParaPdf(tab),
        'fornecedoresOcultos': tab.fornecedoresOcultos,
        'modoPrecificacao': tab.modoPrecificacao,
      });
      final hoje = DateTime.now();
      final dataStr = '${hoje.day.toString().padLeft(2, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.year}';
      final file = File('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}orcamento($dataStr).pdf');
      await file.writeAsBytes(pdfBytes, flush: true);
      if (Platform.isWindows) { await Process.run('explorer', [file.path]); }
      else if (Platform.isMacOS) { await Process.run('open', [file.path]); }
      else { await Process.run('xdg-open', [file.path]); }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF exportado com sucesso!'), backgroundColor: AppTheme.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: AppTheme.error));
    }
  }

  Future<void> _gerarOrdemCompra(List<ItemOrcamentoData> itens) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null) return;

    // Mesmo motivo do _salvarOrcamento/_enviarParaAprovacao.
    await provider.aguardarCriacaoInicial();
    if (!mounted) return;

    final Map<int, List<ItemOrcamentoData>> porFornecedor = {};
    for (final item in itens) {
      final fId = item.fornecedorSelecionado!;
      porFornecedor.putIfAbsent(fId, () => []).add(item);
    }

    final fornecedorNomes = porFornecedor.entries.map((e) {
      final nome = e.value.first.precos[e.key]?.fornecedorNome ?? 'Fornecedor #${e.key}';
      return '  • $nome (${e.value.length} ${e.value.length == 1 ? "item" : "itens"})';
    }).join('\n');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerar Ordens de Compra', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Serão geradas ${porFornecedor.length} ${porFornecedor.length == 1 ? "OC" : "OCs"}, uma por fornecedor:', style: TextStyle(fontSize: 13)),
            SizedBox(height: 10),
            Text(fornecedorNomes, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.primary), onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar e Gerar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _salvando = true);
    final repo = OrcamentoRepository();

    int orcId;
    // Cópia defensiva: mesmo motivo do fluxo de "Enviar para aprovação"
    // (ver comentário em _enviarParaAprovacao) — evita "Concurrent
    // modification during iteration" se um evento SSE mutar tab.itens
    // durante os awaits dos loops abaixo.
    final itensSnapshot = List<ItemOrcamentoData>.of(tab.itens);
    try {
      if (tab.servidorId != null) {
        orcId = tab.servidorId!;
        await repo.atualizarOrcamento(orcId, {'modoPrecificacao': tab.modoPrecificacao});
        await _sincronizarFornecedoresOcultos(orcId, tab);
        await repo.limparItens(orcId);
        for (final item in itensSnapshot) {
        if (item.precos.isEmpty) {
          await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': null, 'selecionado': false});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': entry.value.preco, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
          }
        }
        }
      } else {
        final criado = await repo.criar(tab.titulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': tab.titulo, 'modoPrecificacao': tab.modoPrecificacao});
        await _sincronizarFornecedoresOcultos(orcId, tab);
        for (final item in itensSnapshot) {
          if (item.precos.isEmpty) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': null, 'selecionado': false});
          } else {
            for (final entry in item.precos.entries) {
              await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'qtdUnidade': item.qtdUnidade, 'precoUnitario': entry.value.preco, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
            }
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'sincronizar itens')), backgroundColor: AppTheme.error));
      if (mounted) setState(() => _salvando = false);
      return;
    }

    try {
      final result = await repo.gerarOrdemCompra(orcId, modoPreco: tab.modoPrecificacao);
      if (!mounted) return;

      if (result['pronto'] == true) {
        final ocsCriadas = result['ocsCriadas'] as List?;
        final qtdOCs = ocsCriadas?.length ?? porFornecedor.length;
        final primeiraOcId = ocsCriadas?.isNotEmpty == true ? (ocsCriadas!.first['id'] as int?) : null;

        if (_servidorIdComTravaAtiva == orcId) _servidorIdComTravaAtiva = null;
        provider.fecharAbaAposOperacao();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$qtdOCs ${qtdOCs == 1 ? "OC gerada" : "OCs geradas"} com sucesso!'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 3),
        ));

        if (primeiraOcId != null && mounted) {
          context.read<OrdemCompraProvider>().sinalizarOcParaAbrir(primeiraOcId);
        }

        context.go('/ordem-compra');

        if (primeiraOcId != null) {
          final state = ordemCompraPageKey.currentState;
          if (state != null) {

            context.read<OrdemCompraProvider>().consumirOcPendente();
            await state.abrirOcPorId(primeiraOcId);
          }

        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'gerar OC')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  bool _podeGerarOC(List<ItemOrcamentoData> itens) {
    if (itens.isEmpty) return false;
    final ocultos = context.read<OrcamentoProvider>().tabAtual?.fornecedoresOcultos.toSet() ?? const <int>{};
    return itens.every((i) => i.fornecedorSelecionado != null && !ocultos.contains(i.fornecedorSelecionado));
  }

  int _fornecedoresSelecionados(List<ItemOrcamentoData> itens) =>
      itens.where((i) => i.fornecedorSelecionado != null).map((i) => i.fornecedorSelecionado!).toSet().length;

  Set<int> _todosFornecedoresIds(List<ItemOrcamentoData> itens) {
    final ocultos = context.read<OrcamentoProvider>().tabAtual?.fornecedoresOcultos.toSet() ?? const <int>{};
    final ids = <int>{};
    for (final item in itens) {
      for (final fId in item.precos.keys) {
        if (!ocultos.contains(fId)) ids.add(fId);
      }
    }
    return ids;
  }

  Future<void> _alternarFornecedorOculto(int fornecedorId, bool oculto) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null) return;

    provider.definirFornecedorOcultoLocal(fornecedorId, oculto);

    if (oculto) {
      for (final item in List.of(tab.itens)) {
        if (item.fornecedorSelecionado == fornecedorId) {
          provider.atualizarItemParcial(item.itemId, clearFornecedor: true);
        }
      }
    }

    if (tab.servidorId != null) {
      try {
        await OrcamentoRepository().definirFornecedorOculto(tab.servidorId!, fornecedorId, oculto);
      } catch (e) {
        if (!mounted) return;

        provider.definirFornecedorOcultoLocal(fornecedorId, !oculto);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mensagemErro(e, acao: oculto ? 'ocultar fornecedor' : 'reexibir fornecedor')),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }

  Future<void> _gerenciarFornecedoresOcultos(List<ItemOrcamentoData> itens) async {
    final provider = context.read<OrcamentoProvider>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        final ocultos = provider.tabAtual?.fornecedoresOcultos ?? const <int>[];
        return AlertDialog(
          title: const Text('Fornecedores ocultos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 340,
            child: ocultos.isEmpty
                ? const Text('Nenhum fornecedor oculto.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: ocultos.map((fId) {
                      final nome = itens
                              .expand((i) => i.precos.entries)
                              .where((e) => e.key == fId)
                              .map((e) => e.value.fornecedorNome)
                              .firstOrNull ??
                          'Fornecedor #$fId';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(nome, style: const TextStyle(fontSize: 13)),
                        trailing: Tooltip(
                          message: 'Reexibir fornecedor',
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: TextButton.icon(
                              onPressed: () async {
                                await _alternarFornecedorOculto(fId, false);
                                setSt(() {});
                              },
                              icon: const Icon(Icons.visibility_outlined, size: 14),
                              label: const Text('Reexibir', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            Tooltip(
              message: 'Fechar',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _aplicarSugestaoOtimizada(List<ItemOrcamentoData> itens) {
    final provider = context.read<OrcamentoProvider>();
    final ocultos = provider.tabAtual?.fornecedoresOcultos.toSet() ?? const <int>{};
    for (final item in itens) {
      if (item.precos.isEmpty) continue;
      double? menorValor; int? fornEscolhido;
      for (final entry in item.precos.entries) {
        if (ocultos.contains(entry.key)) continue;
        if (entry.value.preco != null && (menorValor == null || entry.value.preco! < menorValor)) { menorValor = entry.value.preco; fornEscolhido = entry.key; }
      }
      if (fornEscolhido != null) provider.atualizarItemParcial(item.itemId, fornecedorSelecionado: fornEscolhido);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sugestão de orçamento otimizado aplicada!'), backgroundColor: AppTheme.success));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _anexarParadasDoEditorAoTour();
    });
    return Consumer<OrcamentoProvider>(
      builder: (context, provider, _) {
        final abas = provider.abas;
        final abaAtiva = provider.abaAtiva;
        final tab = provider.tabAtual;
        final itens = tab?.itens ?? [];

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: Row(
              children: [
                _BotaoVoltar(
                  label: 'Voltar',
                  tooltip: 'Voltar',
                  // Dono do orçamento: continua salvando silenciosamente ao
                  // sair (sem diálogo), como antes — ver
                  // _salvarSilenciosamenteAoSair. Quando quem edita NÃO é o
                  // criador e há alterações locais não salvas, pergunta
                  // explicitamente "salvar alterações?" em vez de decidir
                  // por conta própria — ver _aoClicarVoltar.
                  onTap: _aoClicarVoltar,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: _HorizontalScrollBehavior(),
                    child: SingleChildScrollView(
                      controller: _abasScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...abas.asMap().entries.map((entry) {
                            final i = entry.key;
                            final aba = entry.value;
                            final ativa = i == abaAtiva;
                            final temConteudo = aba.itens.isNotEmpty || aba.servidorId != null;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _itensSelecionados.clear();
                                  _materiaisParaBulk.clear();
                                  _searchNomeCtrl.clear();
                                  _searchIdentificadorCtrl.clear();
                                  _searchMedidaCtrl.clear();
                                  _searchEspCtrl.clear();
                                  _resultadosBusca = [];
                                  _mostrarResultados = false;
                                });
                                provider.selecionarAba(i);
                                // Regra de negócio: só a aba ATIVA pode
                                // deter a edição no servidor. Trocar de aba
                                // libera a trava da aba anterior e tenta
                                // assumir a da nova aba ativa agora.
                                _garantirTravaAbaAtiva(origem: 'trocaDeAba');
                                _sincronizarStatusServidor(origem: 'trocaDeAba');
                              },
                              child: AnimatedContainer(
                                duration: Duration(milliseconds: 150),
                                margin: EdgeInsets.only(right: 4),
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: ativa ? AppTheme.primary : Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: ativa ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (temConteudo)
                                      Container(
                                        width: 6, height: 6,
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: ativa ? Colors.white.withValues(alpha: 0.8) : AppTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    if (_abaRenomeando == i)
                                      ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: 140),
                                        child: IntrinsicWidth(
                                          child: TextField(
                                            controller: _renomeCtrl,
                                            focusNode: _renomeFocusNode,
                                            autofocus: true,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: ativa ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                            ),
                                            cursorColor: ativa ? Colors.white : AppTheme.primary,
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding: EdgeInsets.zero,
                                              border: InputBorder.none,
                                              isCollapsed: true,
                                            ),
                                            onSubmitted: (_) => _confirmarRenomeacaoAba(i),
                                            onTapOutside: (_) => _confirmarRenomeacaoAba(i),
                                            onEditingComplete: () => _confirmarRenomeacaoAba(i),
                                          ),
                                        ),
                                      )
                                    else
                                      GestureDetector(
                                        onDoubleTap: () => _iniciarRenomeacaoAba(i),
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Tooltip(
                                            message: 'Clique duas vezes para renomear',
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(maxWidth: 140),
                                              child: Text(
                                                aba.titulo,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: ativa ? FontWeight.w700 : FontWeight.w500,
                                                  color: ativa ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Fechar guia',
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () async {
                                            await _salvarAoFecharAba(i);
                                            if (!context.mounted) return;
                                            if (provider.abas.isEmpty) {
                                              _fecharEditorComSeguranca(context);
                                            } else {
                                              // Fechar uma guia pode reindexar
                                              // qual aba fica ativa (ex:
                                              // fechou a guia ativa e outra
                                              // assumiu o lugar) — garante que
                                              // a trava do servidor
                                              // acompanha a nova aba ativa.
                                              _garantirTravaAbaAtiva(origem: 'fecharAba');
                                            }
                                          },
                                          child: Icon(Icons.close, size: 13, color: ativa ? Colors.white.withValues(alpha: 0.8) : Theme.of(context).colorScheme.outline),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          Tooltip(
                            message: 'Adicionar nova guia',
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  provider.adicionarAba();
                                  provider.atualizarFlagsTab(modoEdicao: true);
                                  // Nova aba vira a ativa imediatamente — libera
                                  // a trava da aba anterior (a nova ainda não
                                  // tem servidorId, então não há nada a
                                  // travar aqui; a trava dela é assumida
                                  // pelo próprio provider assim que o POST de
                                  // criação retornar, ver _criarOrcamentoNoServidorImpl).
                                  _garantirTravaAbaAtiva(origem: 'novaAba');
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted && _abasScrollCtrl.hasClients) _abasScrollHintNotifier.update(_abasScrollCtrl);
                                    if (mounted) setState(() {});
                                  });
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  margin: EdgeInsets.only(left: 2),
                                  decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                                  child: Icon(Icons.add, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<ScrollMetrics>(
                  valueListenable: _abasScrollHintNotifier,
                  builder: (_, metrics, __) {
                    final podeEsquerda = metrics.pixels > 0;
                    final podeDireita = metrics.maxScrollExtent > 0 && metrics.pixels < metrics.maxScrollExtent;
                    if (!podeEsquerda && !podeDireita) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 4),
                        _TabNavBtn(icon: Icons.chevron_left, enabled: podeEsquerda, onTap: _scrollAbasEsquerda),
                        _TabNavBtn(icon: Icons.chevron_right, enabled: podeDireita, onTap: _scrollAbasDireita),
                      ],
                    );
                  },
                ),
                if (_salvando) ...[
                  SizedBox(width: 12),
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                ],
              ],
            ),
            bottom: PreferredSize(preferredSize: Size.fromHeight(1), child: Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          body: tab == null
              ? Center(child: Text('Nenhuma aba aberta', style: TextStyle(color: Theme.of(context).colorScheme.outline)))
              : Column(
                  children: [
                    if (tab.somenteLeitura)
                      Container(
                        width: double.infinity,
                        color: AppTheme.warning.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.visibility_outlined, size: 16, color: AppTheme.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Somente visualização — este orçamento está sendo editado por outra pessoa agora.',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.warning),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBarraAcoes(provider, itens, tab),
                          const SizedBox(height: 8),
                          IgnorePointer(
                            ignoring: tab.somenteLeitura,
                            child: Opacity(
                              opacity: tab.somenteLeitura ? 0.5 : 1,
                              child: _buildSelecaoMateriais(provider, itens),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IgnorePointer(
                        // Em modo somente-leitura (orçamento travado por outro
                        // usuário), a tabela de itens/preços fica visível mas
                        // não interativa. Os botões da barra de ações (salvar,
                        // adicionar item, enviar aprovação etc.) já são
                        // desabilitados individualmente logo abaixo em
                        // _buildBarraAcoes/_buildSelecaoMateriais (ficam fora
                        // deste IgnorePointer de propósito, para o Tooltip de
                        // "somente leitura" continuar aparecendo ao passar o
                        // mouse).
                        ignoring: tab.somenteLeitura,
                        child: itens.isEmpty
                            ? _buildEmptyState()
                            : SingleChildScrollView(
                                controller: _pageScrollCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: _buildConteudo(provider, itens),
                              ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildBarraAcoes(OrcamentoProvider provider, List<ItemOrcamentoData> itens, OrcamentoTab tab) {
    final podeGerar = _podeGerarOC(itens);
    final fornsSel = _fornecedoresSelecionados(itens);
    final mostrarBotaoAprovar = tab.aguardandoAprovacao;

    const btnPad = EdgeInsets.symmetric(horizontal: 8, vertical: 5);
    const btnStyle12 = TextStyle(fontSize: 11);
    const iconSize = 13.0;

    final outline = Theme.of(context).colorScheme.outlineVariant;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    const iconOnlySize = 16.0;

    Widget iconOnlyBtn({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
      Color? color,
    }) {
      return Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 34,
          height: 34,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: iconOnlySize),
            color: color ?? onSurfaceVariant,
            disabledColor: onSurfaceVariant.withValues(alpha: 0.35),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: outline)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 14, color: onSurfaceVariant),
              const SizedBox(width: 5),
              Text('${itens.length} materiais · $fornsSel fornecedores', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: onSurfaceVariant)),
            ],
          ),

          const SizedBox(width: 12),

          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [

              Tooltip(
                message: 'Renomear orçamento',
                child: OutlinedButton.icon(
                  onPressed: () => _iniciarRenomeacaoAba(provider.abaAtiva),
                  icon: Icon(Icons.edit_outlined, size: iconSize),
                  label: Text('Renomear', style: btnStyle12),
                  style: OutlinedButton.styleFrom(foregroundColor: onSurfaceVariant, side: BorderSide(color: outline), padding: btnPad).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Baixar PDF do orçamento',
                child: OutlinedButton.icon(
                  onPressed: itens.isEmpty ? null : _exportarPdf,
                  icon: Icon(Icons.picture_as_pdf_outlined, size: iconSize),
                  label: Text('PDF', style: btnStyle12),
                  style: OutlinedButton.styleFrom(foregroundColor: onSurfaceVariant, side: BorderSide(color: outline), padding: btnPad).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ),

              const SizedBox(width: 8),
              Tooltip(
                message: tab.servidorId == null
                    ? 'Salve o orçamento antes de encaminhar'
                    : 'Encaminhar orçamento no chat',
                child: OutlinedButton.icon(
                  onPressed: tab.servidorId == null ? null : _encaminharOrcamento,
                  icon: Icon(Icons.forward_outlined, size: iconSize),
                  label: Text('Encaminhar', style: btnStyle12),
                  style: OutlinedButton.styleFrom(foregroundColor: onSurfaceVariant, side: BorderSide(color: outline), padding: btnPad).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(height: 22, child: VerticalDivider(width: 1, color: outline)),
              ),

              Tooltip(
                message: tab.somenteLeitura ? 'Somente visualização' : 'Cancelar orçamento',
                child: OutlinedButton.icon(
                  onPressed: tab.somenteLeitura ? null : _cancelarOrcamento,
                  icon: Icon(Icons.delete_outline, size: iconSize),
                  label: Text('Cancelar', style: btnStyle12),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)), padding: btnPad).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: tab.somenteLeitura ? 'Somente visualização' : 'Salvar orçamento',
                child: OutlinedButton.icon(
                  onPressed: tab.somenteLeitura ? null : _salvarOrcamento,
                  icon: Icon(Icons.save_outlined, size: iconSize),
                  label: Text('Salvar', style: btnStyle12),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success, side: BorderSide(color: AppTheme.success), padding: btnPad).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ),
              const SizedBox(width: 8),

              if (tab.modoGerarOC)
                Tooltip(
                  message: tab.somenteLeitura
                      ? 'Somente visualização'
                      : (podeGerar ? 'Gerar Ordens de Compra' : 'Selecione um fornecedor para cada material'),
                  child: FilledButton.icon(
                    onPressed: (tab.somenteLeitura || !podeGerar) ? null : () => _gerarOrdemCompra(itens),
                    icon: const Icon(Icons.shopping_cart_checkout, size: iconSize),
                    label: Text('Gerar OC (${_fornecedoresSelecionados(itens)})', style: btnStyle12),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: btnPad).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                )
              else if (mostrarBotaoAprovar)
                Tooltip(
                  message: tab.somenteLeitura ? 'Somente visualização' : 'Aprovar orçamento',
                  child: FilledButton.icon(
                    onPressed: (tab.somenteLeitura || itens.isEmpty) ? null : () async { final sid = provider.tabAtual?.servidorId; if (sid == null) return; await _aprovarOrcamento(sid, provider.tabAtual?.titulo ?? ''); },
                    icon: Icon(Icons.check_circle_outline, size: iconSize),
                    label: Text('Aprovar', style: btnStyle12),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, padding: btnPad).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                )
              else
                Tooltip(
                  message: tab.somenteLeitura
                      ? 'Somente visualização'
                      : (tab.jaFinalizado ? 'Orçamento já aprovado/não aprovado. Reabra para reenviar.' : 'Enviar orçamento para aprovação'),
                  child: FilledButton.icon(
                    key: _tourKeys.botaoEnviarParaAprovacao,
                    onPressed: (itens.isEmpty || tab.jaFinalizado || tab.somenteLeitura) ? null : _enviarParaAprovacao,
                    icon: Icon(Icons.send_outlined, size: iconSize),
                    label: Text('Enviar para aprovação', style: btnStyle12),
                    style: FilledButton.styleFrom(
                      backgroundColor: tab.jaFinalizado ? Theme.of(context).colorScheme.surfaceContainerHighest : AppTheme.warning,
                      foregroundColor: tab.jaFinalizado ? onSurfaceVariant : Colors.white,
                      padding: btnPad,
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(height: 22, child: VerticalDivider(width: 1, color: outline)),
              ),

              iconOnlyBtn(
                tooltip: 'Atualizar dados do orçamento',
                icon: Icons.refresh,
                onPressed: () => _sincronizarStatusServidor(origem: 'botaoAtualizarManual'),
              ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 88, height: 88, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(24)), child: Icon(Icons.inventory_2_outlined, size: 42, color: AppTheme.primary)),
          const SizedBox(height: 22),
          Text('Nenhum material adicionado', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text('Busque um material acima para começar o orçamento.', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

 Widget _buildSelecaoMateriais(
  OrcamentoProvider provider,
  List<ItemOrcamentoData> itens,
) {
  return Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 15,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'Selecionar Materiais',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (itens.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${itens.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (itens.isNotEmpty)
                Tooltip(
                  message: 'Limpar materiais selecionados',
                  child: TextButton.icon(
                    onPressed: () {
                      for (final item in List.from(itens)) {
                        provider.removerItem(item.itemId);
                      }
                    },
                    icon: const Icon(Icons.close, size: 13),
                    label: const Text(
                      'Limpar',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
            ],
          ),
        ),

        KeyedSubtree(
          key: _tourKeys.blocoFiltros,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: _tourKeys.campoNome,
                  controller: _searchNomeCtrl,

                  autofocus: !context.watch<RoboHelperProvider>().tourAtivo,
                  inputFormatters: [_NoCommaFormatter(), _UpperCaseFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Nome do material',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    prefixIcon:
                        _buscando && _searchNomeCtrl.text.isNotEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.search,
                                size: 15,
                              ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _agendarBuscaMateriais();
                  },
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchIdentificadorCtrl,
                  inputFormatters: [_NoCommaFormatter(), _UpperCaseFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Identificador',
                    prefixIcon: Icon(
                      Icons.qr_code_outlined,
                      size: 13,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _agendarBuscaMateriais();
                  },
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchMedidaCtrl,
                  inputFormatters: [_NoCommaFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Medida',
                    prefixIcon: Icon(
                      Icons.straighten_outlined,
                      size: 13,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _agendarBuscaMateriais();
                  },
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchComprimentoCtrl,
                  inputFormatters: [_DecimalInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Comprimento',
                    suffixText: 'm',
                    prefixIcon: Icon(
                      Icons.height,
                      size: 13,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _agendarBuscaMateriais();
                  },
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchLarguraCtrl,
                  inputFormatters: [_DecimalInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Largura',
                    suffixText: 'm',
                    prefixIcon: Icon(
                      Icons.width_normal,
                      size: 13,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _agendarBuscaMateriais();
                  },
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchEspCtrl,
                  inputFormatters: [_DecimalInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Espessura',
                    prefixIcon: Icon(
                      Icons.layers_outlined,
                      size: 13,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _agendarBuscaMateriais();
                  },
                ),
              ),

              const SizedBox(width: 4),

              Builder(
                builder: (context) {
                  final temFiltro = _searchNomeCtrl.text.isNotEmpty ||
                      _searchIdentificadorCtrl.text.isNotEmpty ||
                      _searchMedidaCtrl.text.isNotEmpty ||
                      _searchComprimentoCtrl.text.isNotEmpty ||
                      _searchLarguraCtrl.text.isNotEmpty ||
                      _searchEspCtrl.text.isNotEmpty;
                  return IconButton.outlined(
                    tooltip: 'Limpar filtros',
                    icon: Icon(
                      Icons.filter_alt_off,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: temFiltro
                        ? () {
                            _searchNomeCtrl.clear();
                            _searchIdentificadorCtrl.clear();
                            _searchMedidaCtrl.clear();
                            _searchComprimentoCtrl.clear();
                            _searchLarguraCtrl.clear();
                            _searchEspCtrl.clear();

                            setState(() {
                              _resultadosBusca = [];
                              _mostrarResultados = false;
                            });
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
          ),
        ),
        if (_mostrarResultados &&
            (_buscando || _resultadosBusca.isNotEmpty || _mostrarResultadoFakeNoDropdown))
          Container(
            constraints: BoxConstraints(maxHeight: 200),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 10),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 3))]),
            child: _buscando
                ? Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
                : _mostrarResultadoFakeNoDropdown
                    ? Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: ListTile(
                          key: _tourKeys.primeiroResultadoDropdown,
                          dense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          title: RichText(
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                              children: const [
                                TextSpan(text: 'MATERIAL EXEMPLO', style: TextStyle(fontWeight: FontWeight.w600)),
                                TextSpan(text: ' • 2x1m • 2mm • Unidade', style: TextStyle(fontWeight: FontWeight.w400)),
                              ],
                            ),
                          ),
                          trailing: const _StatusChip(status: ''),
                          onTap: null,
                        ),
                      )
                    : _resultadosBusca.isEmpty
                    ? Padding(padding: EdgeInsets.all(14), child: Row(children: [Icon(Icons.search_off, size: 15, color: Theme.of(context).colorScheme.outline), SizedBox(width: 6), Text('Nenhum material encontrado.', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12))]))
                    : Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _resultadosBusca.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                        itemBuilder: (ctx, i) {
                          final m = _resultadosBusca[i];
                          final medidaOuDimensao = (m.medida != null && m.medida!.isNotEmpty)
                              ? m.medida
                              : _materialDimensaoFormatada(m.largura, m.comprimento);
                          final sub = [medidaOuDimensao, _formatarEspessura(m.espessura)].where((s) => s != null && s.isNotEmpty).join(' • ');
                          return ListTile(
                            key: i == 0 ? _tourKeys.primeiroResultado : null,
                            dense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            title: RichText(
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                children: [
                                  if (m.identificador != null && m.identificador!.isNotEmpty)
                                    TextSpan(text: '${m.identificador}  ·  ', style: const TextStyle(fontWeight: FontWeight.w400)),
                                  TextSpan(text: m.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (sub.isNotEmpty)
                                    TextSpan(text: ' • $sub', style: const TextStyle(fontWeight: FontWeight.w400)),
                                ],
                              ),
                            ),
                            trailing: _StatusChip(status: m.status),
                            onTap: () => _adicionarMaterial(m),
                          );
                        },
                      ),
          ),
        ),

      ]),
    );
  }

  Widget _buildScrollHint() {
    return ValueListenableBuilder<ScrollMetrics>(
      valueListenable: _tabelaHScrollHintNotifier,
      builder: (context, metrics, _) {
        final canScrollLeft = metrics.pixels > 4;
        final canScrollRight = metrics.maxScrollExtent > 0 && metrics.pixels < metrics.maxScrollExtent - 4;
        final showHint = canScrollLeft || canScrollRight;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: showHint ? 24 : 0,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            border: Border(bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.15))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (canScrollLeft) ...[Icon(Icons.chevron_left, size: 14, color: AppTheme.primary.withValues(alpha: 0.7)), const SizedBox(width: 2)],
              Icon(Icons.drag_indicator, size: 13, color: AppTheme.primary.withValues(alpha: 0.5)),
              const SizedBox(width: 3),
              Text(
                canScrollLeft && canScrollRight ? 'Clique e arraste para ver fornecedores' : canScrollRight ? 'Clique e arraste para ver fornecedores →' : '← Melhor Preço',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.primary.withValues(alpha: 0.75)),
              ),
              if (canScrollRight) ...[const SizedBox(width: 2), Icon(Icons.chevron_right, size: 14, color: AppTheme.primary.withValues(alpha: 0.7))],
            ],
          ),
        );
      },
    );
  }

  Widget _buildConteudo(OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return _buildTabelaMatriz(provider, itens);
  }

  Widget _buildTabelaMatriz(OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tabelaHScrollCtrl.hasClients) _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
    });
    final fornIdsRaw = _todosFornecedoresIds(itens).toList();

    final orcarPorMetroLinear = provider.tabAtual?.orcarPorMetroLinear ?? false;
    double fatorItem(ItemOrcamentoData item) {
      if (!orcarPorMetroLinear) return 1;
      final q = item.qtdUnidade;
      return (q != null && q > 0) ? q : 1;
    }

    Map<int, double> totaisForn = {};
    Map<int, int> cobertura = {};
    for (final fId in fornIdsRaw) {
      double soma = 0;
      int cnt = 0;
      for (final item in itens) {
        final pf = item.precos[fId];
        if (pf != null) {
          final preco = pf.preco;
          if (preco != null) {
            soma += preco * item.quantidade * fatorItem(item);
            cnt++;
          }
        }
      }
      totaisForn[fId] = soma;
      cobertura[fId] = cnt;
    }

    Map<int, String> nomesForn = {};
    for (final fId in fornIdsRaw) {
      final nome = itens
          .expand((i) => i.precos.entries)
          .where((e) => e.key == fId)
          .map((e) => e.value.fornecedorNome)
          .firstOrNull;
      nomesForn[fId] = nome ?? 'Fornecedor #$fId';
    }

    final todosFornIds = List<int>.from(fornIdsRaw)
      ..sort((a, b) => nomesForn[a]!.toLowerCase().compareTo(nomesForn[b]!.toLowerCase()));

    List<double?> melhorPorMaterial = itens.map((item) {
      double? menor;
      for (final fId in todosFornIds) {
        final pf = item.precos[fId];
        if (pf == null) continue;
        final preco = pf.preco;
        if (preco != null && (menor == null || preco < menor)) menor = preco;
      }
      return menor;
    }).toList();

    double totalMelhor = 0;
    int materiaisComMelhor = 0;
    for (int i = 0; i < itens.length; i++) {
      final m = melhorPorMaterial[i];
      if (m != null) {
        totalMelhor += m * itens[i].quantidade * fatorItem(itens[i]);
        materiaisComMelhor++;
      }
    }

    int maxCobertura = cobertura.values.fold(0, (a, b) => b > a ? b : a);
    int? fornComTodos;
    double? menorTotalComTodos;
    for (final fId in todosFornIds) {
      if ((cobertura[fId] ?? 0) == maxCobertura) {
        final t = totaisForn[fId] ?? 0;
        if (menorTotalComTodos == null || t < menorTotalComTodos) {
          menorTotalComTodos = t;
          fornComTodos = fId;
        }
      }
    }

    double? diferenca;
    String? nomeFornComTodos;
    if (fornComTodos != null && menorTotalComTodos != null && materiaisComMelhor == itens.length) {
      diferenca = menorTotalComTodos - totalMelhor;
      nomeFornComTodos = itens.expand((i) => i.precos.entries).where((e) => e.key == fornComTodos).map((e) => e.value.fornecedorNome).firstOrNull;
    }

    const double colMaterial = 200;
    const double colQtdMin = 70;
    double colQtd = 90;
    double colQtdUnidade = 100;
    double colFornMin = 120;
    double colMelhor = 120;

    final double scrollableWidth = 12 + (colFornMin * todosFornIds.length) + todosFornIds.length.toDouble() + 1 + colMelhor;

    Widget cabecalhoFixo() => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(children: [
        SizedBox(width: colMaterial, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text('Material', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Tooltip(
          message: 'Quantidade mínima em estoque (configurada no módulo de estoque)',
          child: SizedBox(width: colQtdMin, child: Padding(padding: EdgeInsets.symmetric(horizontal: 3, vertical: 6), child: Text('Estoque mínimo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center))),
        ),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colQtd, child: Padding(padding: EdgeInsets.symmetric(horizontal: 3, vertical: 6), child: Text('Quantidade', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center))),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Tooltip(
          message: 'Quantidade por unidade (ex: m/l por lona). Só se aplica a materiais cuja unidade não é "Unidade" — repassado para a Ordem de Compra ao gerar.',
          child: SizedBox(width: colQtdUnidade, child: Padding(padding: EdgeInsets.symmetric(horizontal: 3, vertical: 6), child: Text('Quantidade por Unidade', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center))),
        ),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
      ]),
    );

    Widget cabecalhoScroll() => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(children: [
        const SizedBox(width: 12),
        ...todosFornIds.map((fId) {
          final nome = itens.expand((i) => i.precos.entries).where((e) => e.key == fId).map((e) => e.value.fornecedorNome).firstOrNull ?? 'Fornecedor';
          final isLast = fId == todosFornIds.last;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: colFornMin,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(nome, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center, softWrap: true),
                  Tooltip(
                    message: 'Ocultar fornecedor',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _alternarFornecedorOculto(fId, true),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.visibility_off_outlined, size: 11, color: Theme.of(context).colorScheme.outline),
                            const SizedBox(width: 2),
                            Text('ocultar', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            if (!isLast) Container(width: 1, height: 18, color: Theme.of(context).colorScheme.outlineVariant),
          ]);
        }),
        Container(width: 1, height: 18, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colMelhor, child: Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 3, vertical: 6), child: Text('Melhor Preço', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center)))),
      ]),
    );

    Widget totaisFixo() => Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5))),
      child: Row(children: [
        SizedBox(width: colMaterial, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text('Total por Fornecedor', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)))),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colQtdMin),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colQtd),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colQtdUnidade),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
      ]),
    );

    Widget totaisScroll() => Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5))),
      child: Row(children: [
        const SizedBox(width: 12),
        ...todosFornIds.map((fId) {
          final total = totaisForn[fId] ?? 0;
          final cob = cobertura[fId] ?? 0;
          final isMenorTotal = todosFornIds.isNotEmpty && total > 0 && total == todosFornIds.map((id) => totaisForn[id] ?? double.infinity).reduce((a, b) => a < b ? a : b);
          final semPrecoCount = itens.length - cob;
          final isLast = fId == todosFornIds.last;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: colFornMin, child: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text(total > 0 ? _brl(total) : '—', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isMenorTotal ? AppTheme.success : Theme.of(context).colorScheme.onSurface), textAlign: TextAlign.center),
              Text('$cob/${itens.length}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isMenorTotal ? AppTheme.success : Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              if (semPrecoCount > 0) Text('$semPrecoCount sem preço', style: TextStyle(fontSize: 8, color: AppTheme.warning, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ]))),
            if (!isLast) Container(width: 1, height: 32, color: Theme.of(context).colorScheme.outlineVariant),
          ]);
        }),
        Container(width: 1, height: 32, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colMelhor, child: Center(child: Container(margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6), padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3))), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(materiaisComMelhor > 0 ? _brl(totalMelhor) : '—', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center),
          Text('$materiaisComMelhor/${itens.length}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center),
        ])))),
      ]),
    );

    Widget itemFixo(int idx) {
      final item = itens[idx];
      final isSelected = item.fornecedorSelecionado != null;
      return Container(
        color: isSelected ? Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.05), Theme.of(context).colorScheme.surface) : Theme.of(context).colorScheme.surface,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: colMaterial,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Tooltip(
                  message: 'Remover material',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => provider.removerItem(item.itemId),
                      child: Padding(padding: const EdgeInsets.only(top: 1, right: 3), child: Icon(Icons.close, size: 13, color: Theme.of(context).colorScheme.outline)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Checkbox(
                    value: _itensSelecionados.contains(item.itemId),
                    onChanged: (v) => setState(() {
                      if (v == true) { _itensSelecionados.add(item.itemId); _materiaisParaBulk.add(item.itemId); }
                      else { _itensSelecionados.remove(item.itemId); _materiaisParaBulk.remove(item.itemId); }
                    }),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.2),
                    activeColor: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Flexible(child: Text(item.materialNome, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), softWrap: true)),
                      if ([item.materialMedida, item.materialDimensaoFormatada, item.materialEspessura, item.materialIdentificador].any((s) => s != null && s.isNotEmpty))
                        Text([item.materialMedida ?? item.materialDimensaoFormatada, _formatarEspessura(item.materialEspessura), item.materialIdentificador].where((s) => s != null && s.isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), softWrap: true),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: 'Adicionar fornecedor a este material',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            key: idx == 0 ? _tourKeys.botaoAdicionarFornecedor : null,
                            onTap: () => _vincularFornecedores(idx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(5), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3))),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.person_add_outlined, size: 11, color: AppTheme.primary),
                                SizedBox(width: 3),
                                Text('Adicionar Fornecedor', style: TextStyle(fontSize: 9, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Tooltip(
            message: item.estoqueMinimo != null
                ? 'Estoque mínimo: ${_formatQtdComUnidade(item.estoqueMinimo!, item.materialUnidade)}'
                : 'Estoque mínimo não definido',
            child: Container(
              width: colQtdMin,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
              child: Text(
                item.estoqueMinimo != null
                    ? _formatQtdComUnidade(item.estoqueMinimo!, item.materialUnidade)
                    : '—',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: item.estoqueMinimo != null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Container(
            width: colQtd,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            child: _QuantidadeField(key: ValueKey('qtd_${item.itemId}'), tourKey: idx == 0 ? _tourKeys.campoQuantidadeMaterial1 : null, value: item.quantidade, onChanged: (q) => provider.atualizarItemParcial(item.itemId, quantidade: q)),
          ),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Container(
            width: colQtdUnidade,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            child: item.precisaQtdUnidade
                ? Tooltip(
                    message: _unidadeDescricaoCompleta(item.materialUnidade).isEmpty
                        ? 'Qtd por unidade'
                        : '${_unidadeDescricaoCompleta(item.materialUnidade)} por unidade',
                    child: _QtdUnidadeField(
                      key: ValueKey('qtdUnidade_${item.itemId}'),
                      tourKey: idx == 1 ? _tourKeys.campoQtdUnidadeMaterial2 : null,
                      value: item.qtdUnidade,
                      unidade: item.materialUnidade,
                      onChanged: (q) => provider.atualizarItemParcial(item.itemId, qtdUnidade: q),
                    ),
                  )
                : Text('—', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline), textAlign: TextAlign.center),
          ),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        ]),
      );
    }

    Widget itemScroll(int idx) {
      final item = itens[idx];
      final isSelected = item.fornecedorSelecionado != null;
      final melhor = melhorPorMaterial[idx];
      return Container(
        color: isSelected ? Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.05), Theme.of(context).colorScheme.surface) : Theme.of(context).colorScheme.surface,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(width: 12),
          ...todosFornIds.map((fId) {
            final pf = item.precos[fId];
            final isLast = fId == todosFornIds.last;
            if (pf == null) {
              return Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: colFornMin, child: Center(child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(3), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                  child: Text('Não tem', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                ))),
                if (!isLast) Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
              ]);
            }
            final preco = pf.preco;
            final total = preco != null ? preco * item.quantidade * fatorItem(item) : null;
            // Preço m² salvo tem prioridade; se ausente (ex.: item vindo do
            // servidor antes de o preço m² ter sido informado, ou digitado
            // só o preço unitário), deriva a partir do preço e da área por
            // unidade, quando disponível.
            final precoM2 = pf.precoMetroQuadrado ??
                ((preco != null && item.areaM2PorUnidade != null && item.areaM2PorUnidade! > 0)
                    ? preco / item.areaM2PorUnidade!
                    : null);
            final isMenorNaLinha = melhor != null && preco != null && preco == melhor;
            final isSelectedForn = item.fornecedorSelecionado == fId;
            final ehPrimeiraCelulaTour = idx == 0 && fId == todosFornIds.first;
            return Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                key: ehPrimeiraCelulaTour ? _tourKeys.celulaFornecedor : null,
                onTap: () {
                  if (isSelectedForn) { provider.atualizarItemParcial(item.itemId, clearFornecedor: true); }
                  else { provider.atualizarItemParcial(item.itemId, fornecedorSelecionado: fId); }
                },
                child: SizedBox(width: colFornMin, child: Center(child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelectedForn ? AppTheme.primary.withValues(alpha: 0.1) : isMenorNaLinha ? AppTheme.success.withValues(alpha: 0.07) : null,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: isSelectedForn ? AppTheme.primary.withValues(alpha: 0.4) : isMenorNaLinha ? AppTheme.success.withValues(alpha: 0.3) : Colors.transparent),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    preco != null
                        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            if (isMenorNaLinha) const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.arrow_downward, size: 9, color: AppTheme.success)),
                            Flexible(child: Text(_brl(preco), style: TextStyle(fontSize: 11, fontWeight: isMenorNaLinha ? FontWeight.w700 : FontWeight.w500, color: isMenorNaLinha ? AppTheme.success : Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                          ])
                        : Text('Sem preço', style: TextStyle(fontSize: 9, color: AppTheme.warning, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                    if (precoM2 != null) Text('${_brl(precoM2)}/m²', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8)), textAlign: TextAlign.center),
                    if (total != null) Text(_brl(total), style: TextStyle(fontSize: 10, color: isMenorNaLinha ? AppTheme.success.withValues(alpha: 0.8) : Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                    if (pf.observacao != null && pf.observacao!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(pf.observacao!, style: TextStyle(fontSize: 8, color: AppTheme.warning, fontStyle: FontStyle.italic), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        key: ehPrimeiraCelulaTour ? _tourKeys.editarPreco : null,
                        onTap: () => _editarPreco(idx, fId),
                        child: const Text(
                          'editar',
                          style: TextStyle(
                            fontSize: 9,
                            color: AppTheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    if (isSelectedForn) const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 9, color: AppTheme.primary), SizedBox(width: 2), Text('Escolhido', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppTheme.primary))]),
                  ]),
                ))),
              ),
              if (!isLast) Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
            ]);
          }),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          SizedBox(width: colMelhor, child: Center(child: melhor != null
            ? Container(
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(5), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text(_brl(melhor), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center),
                  Text(_brl(melhor * item.quantidade * fatorItem(item)), style: TextStyle(fontSize: 9, color: AppTheme.primary.withValues(alpha: 0.7)), textAlign: TextAlign.center),
                ]))
            : Text('—', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline), textAlign: TextAlign.center),
          )),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Comparativo de Preços', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (_materiaisParaBulk.isNotEmpty) ...[
                Tooltip(
                  message: 'Adicionar fornecedores aos materiais selecionados',
                  child: FilledButton.icon(
                    onPressed: _adicionarFornecedoresBulk,
                    icon: const Icon(Icons.add_business, size: 12),
                    label: Text('Adicionar Fornecedores (${_materiaisParaBulk.length})', style: TextStyle(fontSize: 10)),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
                Tooltip(
                  message: 'Limpar seleção de materiais',
                  child: TextButton(
                    onPressed: () => setState(() => _materiaisParaBulk.clear()),
                    style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    child: Text('Limpar', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
              if (_itensSelecionados.isNotEmpty) ...[
                Tooltip(
                  message: 'Copiar itens selecionados',
                  child: FilledButton.icon(
                    onPressed: () => _copiarSelecionados(itens),
                    icon: const Icon(Icons.copy_all, size: 12),
                    label: Text('Copiar ${_itensSelecionados.length}', style: TextStyle(fontSize: 10)),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
                Tooltip(
                  message: 'Limpar seleção de itens',
                  child: TextButton(
                    onPressed: () => setState(() => _itensSelecionados.clear()),
                    style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    child: Text('Limpar', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
              Tooltip(
                message: 'Define como os preços dos fornecedores são interpretados no comparativo e na OC gerada',
                child: IntrinsicWidth(child: SizedBox(
                  key: _tourKeys.botaoOrcarPor,
                  height: 30,
                  child: PopupMenuButton<String>(
                    onSelected: (modo) => provider.definirModoPrecificacao(modo),
                    itemBuilder: (ctx) => [
                      CheckedPopupMenuItem(
                        value: 'UNIDADE',
                        checked: !orcarPorMetroLinear,
                        mouseCursor: SystemMouseCursors.click,
                        child: const Text('Unidade (preço por peça/rolo)', style: TextStyle(fontSize: 12)),
                      ),
                      CheckedPopupMenuItem(
                        value: 'METRO_LINEAR',
                        checked: orcarPorMetroLinear,
                        mouseCursor: SystemMouseCursors.click,
                        child: const Text('Metro Linear (preço por m/l)', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.primary),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.straighten, size: 12, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text('Orçar por: ${orcarPorMetroLinear ? "Metro Linear" : "Unidade"}', style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                          const Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.primary),
                        ]),
                      ),
                    ),
                  ),
                )),
              ),
              Tooltip(
                message: 'Aplicar sugestão de orçamento otimizado',
                child: IntrinsicWidth(child: SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    onPressed: () => _aplicarSugestaoOtimizada(itens),
                    icon: const Icon(Icons.auto_awesome, size: 12),
                    label: const Text('Sugestão de melhor preço', style: TextStyle(fontSize: 10)),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary, side: const BorderSide(color: AppTheme.primary), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                )),
              ),
              if (provider.tabAtual?.fornecedoresOcultos.isNotEmpty ?? false)
                Tooltip(
                  message: 'Ver fornecedores ocultos',
                  child: OutlinedButton.icon(
                    onPressed: () => _gerenciarFornecedoresOcultos(itens),
                    icon: const Icon(Icons.visibility_off_outlined, size: 12),
                    label: Text('Ocultos (${provider.tabAtual!.fornecedoresOcultos.length})', style: const TextStyle(fontSize: 10)),
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.outline, side: BorderSide(color: Theme.of(context).colorScheme.outline), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
            ],
          ),
        ),
        _buildScrollHint(),

        ScrollConfiguration(
          behavior: _HorizontalScrollBehavior(),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Scrollbar(
            controller: _tabelaHScrollCtrl,
            child: SingleChildScrollView(
              controller: _tabelaHScrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: colMaterial + 1 + colQtdMin + 1 + colQtd + 1 + colQtdUnidade + 1 + scrollableWidth,
                child: Column(children: [

                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      cabecalhoFixo(),
                      cabecalhoScroll(),
                    ]),
                  ),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

                  SizedBox(
                    height: 500,
                    child: ListView.separated(
                      itemCount: itens.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                      itemBuilder: (ctx, idx) => IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          itemFixo(idx),
                          itemScroll(idx),
                        ]),
                      ),
                    ),
                  ),

                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      totaisFixo(),
                      totaisScroll(),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          ),
        ),
        if (diferenca != null && diferenca > 0 && nomeFornComTodos != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              border: Border(top: BorderSide(color: AppTheme.warning.withValues(alpha: 0.4), width: 1.5)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: AppTheme.warning),
              const SizedBox(width: 6),
              Flexible(child: Text('Comprando tudo de "$nomeFornComTodos" (${_brl(menorTotalComTodos)}) vs melhor por item (${_brl(totalMelhor)}): diferença de ${_brl(diferenca)} a mais.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.warning))),
            ]),
          )
        else if (diferenca != null && diferenca <= 0 && nomeFornComTodos != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.06), border: Border(top: BorderSide(color: AppTheme.success.withValues(alpha: 0.2)))),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, size: 13, color: AppTheme.success),
              const SizedBox(width: 6),
              Flexible(child: Text('"$nomeFornComTodos" já é o mais vantajoso com ${_brl(menorTotalComTodos)} — mesmo comprando tudo de um único fornecedor.', style: const TextStyle(fontSize: 10, color: AppTheme.success))),
            ]),
          ),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status) {
      case 'OK':
        bg = AppTheme.statusOk.withValues(alpha: 0.1);
        fg = AppTheme.statusOk;
      case 'LIMITE':
        bg = AppTheme.statusBaixo.withValues(alpha: 0.1);
        fg = AppTheme.statusBaixo;
      case 'CRITICO':
        bg = AppTheme.statusCritico.withValues(alpha: 0.1);
        fg = AppTheme.statusCritico;
      default:
        bg = Theme.of(context).colorScheme.surfaceContainerHighest;
        fg = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _QuantidadeField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  final GlobalKey? tourKey;
  const _QuantidadeField({super.key, required this.value, required this.onChanged, this.tourKey});

  @override
  State<_QuantidadeField> createState() => _QuantidadeFieldState();
}

class _QuantidadeFieldState extends State<_QuantidadeField> {
  late TextEditingController _ctrl;
  bool _editando = false;

  String _formatValue(double v) => _formatarPreco(v).replaceAll(RegExp(r',00$'), '');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatValue(widget.value));
  }

  @override
  void didUpdateWidget(_QuantidadeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editando && oldWidget.value != widget.value) {
      final novoTexto = _formatValue(widget.value);
      if (_ctrl.text != novoTexto) {
        _ctrl.text = novoTexto;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.tourKey,
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_PrecoInputFormatter()],
      decoration: InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)), isDense: true, filled: true, fillColor: Theme.of(context).colorScheme.surface),
      style: const TextStyle(fontSize: 11),
      onTap: () => setState(() => _editando = true),
      onChanged: (v) {
        final parsed = _parsePreco(v);
        // Antes exigia `parsed > 0`, então digitar "0" ou apagar o campo
        // nunca chamava widget.onChanged — a quantidade zerada nunca era
        // persistida nem propagada para quem estivesse só visualizando o
        // mesmo orçamento (ver OrcamentoProvider._sinalizarEdicaoLocal).
        // Aceita >= 0; string vazia (parsed == null) mantém o valor atual
        // até o usuário digitar algo, evitando disparo com campo em branco.
        if (parsed != null && parsed >= 0) widget.onChanged(parsed);
      },
      onEditingComplete: () {
        setState(() => _editando = false);
        FocusScope.of(context).unfocus();
      },
      onSubmitted: (_) => setState(() => _editando = false),
    );
  }
}

class _QtdUnidadeField extends StatefulWidget {
  final double? value;
  final String? unidade;
  final ValueChanged<double?> onChanged;

  final GlobalKey? tourKey;
  const _QtdUnidadeField({super.key, required this.value, this.unidade, required this.onChanged, this.tourKey});

  @override
  State<_QtdUnidadeField> createState() => _QtdUnidadeFieldState();
}

class _QtdUnidadeFieldState extends State<_QtdUnidadeField> {
  late TextEditingController _ctrl;
  bool _editando = false;

  String _formatValue(double? v) {
    if (v == null) return '';
    if (v % 1 == 0) return _formatarPreco(v).replaceAll(RegExp(r',00$'), '');
    return _formatarPreco(v);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatValue(widget.value));
  }

  @override
  void didUpdateWidget(_QtdUnidadeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editando && oldWidget.value != widget.value) {
      final novoTexto = _formatValue(widget.value);
      if (_ctrl.text != novoTexto) {
        _ctrl.text = novoTexto;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unidade = widget.unidade?.trim();
    return TextField(
      key: widget.tourKey,
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_PrecoInputFormatter()],
      decoration: InputDecoration(
        hintText: '0.000',
        suffixIcon: (unidade != null && unidade.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1,
                  child: Text(
                    unidade.toLowerCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
      style: const TextStyle(fontSize: 11),
      onTap: () => setState(() => _editando = true),
      onChanged: (v) {
        if (v.trim().isEmpty) {

          widget.onChanged(0);
          return;
        }
        final parsed = _parsePreco(v);
        if (parsed != null) widget.onChanged(parsed);
      },
      onEditingComplete: () {
        setState(() => _editando = false);
        FocusScope.of(context).unfocus();
      },
      onSubmitted: (_) => setState(() => _editando = false),
    );
  }
}

class _DialogSelecionarFornecedoresBulk extends StatefulWidget {
  final List<FornecedorModel> fornecedores;
  final int qtdMateriais;

  const _DialogSelecionarFornecedoresBulk({required this.fornecedores, required this.qtdMateriais});

  @override
  State<_DialogSelecionarFornecedoresBulk> createState() => _DialogSelecionarFornecedoresBulkState();
}

class _DialogSelecionarFornecedoresBulkState extends State<_DialogSelecionarFornecedoresBulk> {
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
    final filtrados = _filtro.isEmpty
        ? widget.fornecedores
        : widget.fornecedores.where((f) => f.nomeFantasia.toLowerCase().contains(_filtro.toLowerCase()) || (f.cnpj != null && f.cnpj!.contains(_filtro))).toList();

    return AlertDialog(
      title: Text('Adicionar Fornecedores a ${widget.qtdMateriais} Materiais', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
                prefixIcon: Icon(Icons.search, size: 18),
                suffixIcon: _filtro.isNotEmpty ? IconButton(icon: Icon(Icons.close, size: 16), onPressed: () { _buscaCtrl.clear(); setState(() => _filtro = ''); }) : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            if (_selecionados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.check_circle, size: 13, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text('${_selecionados.length} selecionado${_selecionados.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                ]),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 280),
              child: filtrados.isEmpty
                  ? Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Row(children: [Icon(Icons.search_off, size: 16), SizedBox(width: 8), Text('Nenhum fornecedor encontrado.', style: TextStyle(fontSize: 13))]))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) => Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final f = filtrados[i];
                        return CheckboxListTile(
                          dense: true,
                          mouseCursor: SystemMouseCursors.click,
                          title: Text(f.nomeFantasia, style: const TextStyle(fontSize: 13)),
                          subtitle: f.cnpj != null ? Text(f.cnpj!, style: const TextStyle(fontSize: 11)) : null,
                          value: _selecionados.contains(f.id),
                          activeColor: AppTheme.primary,
                          onChanged: (v) => setState(() {
                            if (v == true) { _selecionados.add(f.id); } else { _selecionados.remove(f.id); }
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
          style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          onPressed: _selecionados.isEmpty ? null : () => Navigator.pop(context, _selecionados.toList()),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

class _DialogVincularFornecedores extends StatefulWidget {
  final List<FornecedorModel> fornecedores;
  final Set<int> idsJaVinculados;
  final String materialNome;

  final bool ehTourAssistente;

  const _DialogVincularFornecedores({
    required this.fornecedores,
    required this.idsJaVinculados,
    required this.materialNome,
    this.ehTourAssistente = false,
  });

  @override
  State<_DialogVincularFornecedores> createState() => _DialogVincularFornecedoresState();
}

class _DialogVincularFornecedoresState extends State<_DialogVincularFornecedores> {
  final Set<int> _selecionados = {};
  final _buscaCtrl = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  static const _nomeFornecedorDemo = 'FORNECEDOR EXEMPLO';
  static const _cnpjFornecedorDemo = '00.000.000/0000-00';

  static const _fornecedorIdTourFake = -999999;

  @override
  Widget build(BuildContext context) {

    if (widget.ehTourAssistente) {
      final selecionadoDemo = _selecionados.contains(_fornecedorIdTourFake);
      return AlertDialog(
        title: Text('Adicionar Fornecedores — ${widget.materialNome}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: _editorStateAtivo?._tourKeys.buscaFornecedorDialog,
                controller: _buscaCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar fornecedor...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filtro = v),
              ),
              const SizedBox(height: 8),
              if (_selecionados.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [const Icon(Icons.check_circle, size: 13, color: AppTheme.primary), const SizedBox(width: 6), Text('${_selecionados.length} selecionado', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary))])),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CheckboxListTile(
                      key: _editorStateAtivo?._tourKeys.primeiroFornecedorDialog,
                      dense: true,
                      mouseCursor: SystemMouseCursors.click,
                      title: const Text(_nomeFornecedorDemo, style: TextStyle(fontSize: 13)),
                      subtitle: const Text(_cnpjFornecedorDemo, style: TextStyle(fontSize: 11)),
                      value: selecionadoDemo,
                      activeColor: AppTheme.primary,
                      onChanged: (v) => setState(() {
                        if (v == true) { _selecionados.add(_fornecedorIdTourFake); } else { _selecionados.remove(_fornecedorIdTourFake); }
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: _selecionados.isEmpty ? null : () => Navigator.pop(context, _selecionados.toList()),
            child: const Text('Adicionar'),
          ),
        ],
      );
    }

    final disponiveis = widget.fornecedores.where((f) => !widget.idsJaVinculados.contains(f.id)).toList();
    final filtrados = _filtro.isEmpty ? disponiveis : disponiveis.where((f) => f.nomeFantasia.toLowerCase().contains(_filtro.toLowerCase()) || (f.cnpj != null && f.cnpj!.contains(_filtro))).toList();

    return AlertDialog(
      title: Text('Adicionar Fornecedores — ${widget.materialNome}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
                prefixIcon: Icon(Icons.search, size: 18),
                suffixIcon: _filtro.isNotEmpty ? IconButton(icon: Icon(Icons.close, size: 16), onPressed: () { _buscaCtrl.clear(); setState(() => _filtro = ''); }) : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            if (_selecionados.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [const Icon(Icons.check_circle, size: 13, color: AppTheme.primary), const SizedBox(width: 6), Text('${_selecionados.length} selecionado${_selecionados.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary))])),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 280),
              child: disponiveis.isEmpty
                  ? Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Todos os fornecedores já estão vinculados.', style: TextStyle(fontSize: 13)))
                  : filtrados.isEmpty
                      ? Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Row(children: [Icon(Icons.search_off, size: 16), SizedBox(width: 8), Text('Nenhum fornecedor encontrado.', style: TextStyle(fontSize: 13))]))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) => Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final f = filtrados[i];
                            return CheckboxListTile(
                              dense: true,
                              mouseCursor: SystemMouseCursors.click,
                              title: Text(f.nomeFantasia, style: const TextStyle(fontSize: 13)),
                              subtitle: f.cnpj != null ? Text(f.cnpj!, style: const TextStyle(fontSize: 11)) : null,
                              value: _selecionados.contains(f.id),
                              activeColor: AppTheme.primary,
                              onChanged: (v) => setState(() {
                                if (v == true) { _selecionados.add(f.id); } else { _selecionados.remove(f.id); }
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
          style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          onPressed: _selecionados.isEmpty ? null : () => Navigator.pop(context, _selecionados.toList()),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

/// Formatter para campos de preço em BRL: aplica separador de milhar (ponto)
/// na parte inteira em tempo real enquanto o usuário digita, usando vírgula
/// como separador decimal (padrão brasileiro). Ex.: digitar "1000" exibe
/// "1.000"; digitar "1000,5" exibe "1.000,5".
class _PrecoInputFormatter extends TextInputFormatter {
  static String _aplicarMilhar(String digitosInteiros) {
    final buffer = StringBuffer();
    for (int i = 0; i < digitosInteiros.length; i++) {
      if (i > 0 && (digitosInteiros.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digitosInteiros[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text;

    final cursorPos = newValue.selection.end.clamp(0, texto.length);
    final antesDoCursor = texto.substring(0, cursorPos);
    final digitosAntesCursor =
        antesDoCursor.replaceAll(RegExp(r'[^\d,]'), '').length;

    texto = texto.replaceAll(RegExp(r'[^\d,]'), '');

    final partes = texto.split(',');
    String inteiro = partes[0];
    String? decimais = partes.length > 1 ? partes.sublist(1).join('') : null;
    if (decimais != null && decimais.length > 2) {
      decimais = decimais.substring(0, 2);
    }

    inteiro = inteiro.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    final inteiroFormatado = _aplicarMilhar(inteiro);
    final textoFormatado = decimais != null
        ? '$inteiroFormatado,$decimais'
        : (texto.contains(',') ? '$inteiroFormatado,' : inteiroFormatado);

    int novoOffset = 0;
    int contador = 0;
    for (int i = 0; i < textoFormatado.length; i++) {
      if (contador >= digitosAntesCursor) break;
      if (textoFormatado[i] != '.') contador++;
      novoOffset = i + 1;
    }
    novoOffset = novoOffset.clamp(0, textoFormatado.length);

    return TextEditingValue(
      text: textoFormatado,
      selection: TextSelection.collapsed(offset: novoOffset),
    );
  }
}

/// Converte o texto de um campo formatado com [_PrecoInputFormatter]
/// (ex.: "1.000,50") para um double (1000.5).
double? _parsePreco(String texto) {
  final v = texto.trim();
  if (v.isEmpty) return null;
  final semMilhar = v.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(semMilhar);
}

/// Formata um valor monetário no padrão brasileiro, com separador de
/// milhar (ponto) e duas casas decimais (vírgula). Ex.: 1000.0 -> '1.000,00'.
String _formatarPreco(num valor) {
  final partes = valor.toStringAsFixed(2).split('.');
  final inteiro = partes[0];
  final decimais = partes[1];
  final negativo = inteiro.startsWith('-');
  final digitos = negativo ? inteiro.substring(1) : inteiro;

  final buffer = StringBuffer();
  for (int i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digitos[i]);
  }

  return '${negativo ? '-' : ''}${buffer.toString()},$decimais';
}

class _DialogEditarMaterial extends StatefulWidget {
  final String fornecedorNome;
  final String materialNome;
  final double? precoAtual;
  final double? precoMetroQuadradoAtual;
  final String? observacaoAtual;

  /// Área (m²) de uma unidade deste material — usada para converter entre
  /// preço unitário e preço por m². Quando `null` (material sem largura ou
  /// sem comprimento/qtdUnidade cadastrados), o campo "Preço m²" fica
  /// desabilitado, pois não há como calcular a conversão.
  final double? areaM2PorUnidade;

  final GlobalKey? tourKeyCamposPrecoEDisponibilidade;

  const _DialogEditarMaterial({
    required this.fornecedorNome,
    required this.materialNome,
    this.precoAtual,
    this.precoMetroQuadradoAtual,
    this.observacaoAtual,
    this.areaM2PorUnidade,
    this.tourKeyCamposPrecoEDisponibilidade,
  });

  @override
  State<_DialogEditarMaterial> createState() => _DialogEditarMaterialState();
}

class _DialogEditarMaterialState extends State<_DialogEditarMaterial> {
  late final TextEditingController _precoCtrl;
  late final TextEditingController _precoM2Ctrl;
  late final TextEditingController _observacaoCtrl;

  // Evita loop de sincronização: quando um campo atualiza o outro
  // programaticamente, o listener do campo atualizado não deve, por sua
  // vez, tentar atualizar o primeiro de volta.
  bool _sincronizando = false;

  bool get _temArea => widget.areaM2PorUnidade != null && widget.areaM2PorUnidade! > 0;

  @override
  void initState() {
    super.initState();
    _precoCtrl = TextEditingController(
      text: widget.precoAtual != null ? _formatarPreco(widget.precoAtual!) : '',
    );
    _precoM2Ctrl = TextEditingController(
      text: widget.precoMetroQuadradoAtual != null
          ? _formatarPreco(widget.precoMetroQuadradoAtual!)
          : '',
    );
    _observacaoCtrl = TextEditingController(text: widget.observacaoAtual ?? '');

    _precoCtrl.addListener(_aoAlterarPreco);
    _precoM2Ctrl.addListener(_aoAlterarPrecoM2);
  }

  void _aoAlterarPreco() {
    if (_sincronizando || !_temArea) return;
    final preco = _parsePreco(_precoCtrl.text);
    _sincronizando = true;
    if (preco == null) {
      _precoM2Ctrl.clear();
    } else {
      final precoM2 = preco / widget.areaM2PorUnidade!;
      _precoM2Ctrl.text = _formatarPreco(precoM2);
    }
    _sincronizando = false;
  }

  void _aoAlterarPrecoM2() {
    if (_sincronizando || !_temArea) return;
    final precoM2 = _parsePreco(_precoM2Ctrl.text);
    _sincronizando = true;
    if (precoM2 == null) {
      _precoCtrl.clear();
    } else {
      final preco = precoM2 * widget.areaM2PorUnidade!;
      _precoCtrl.text = _formatarPreco(preco);
    }
    _sincronizando = false;
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
    _precoM2Ctrl.dispose();
    _observacaoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar Material — ${widget.fornecedorNome}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.materialNome, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Column(
              key: widget.tourKeyCamposPrecoEDisponibilidade,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: TextField(
                    controller: _precoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_PrecoInputFormatter()],
                    decoration: const InputDecoration(labelText: 'Preço (R\$)', prefixText: 'R\$ ', isDense: true),
                  ),
                ),
                const SizedBox(height: 12),
                Tooltip(
                  message: _temArea
                      ? 'Preencher aqui calcula o Preço (R\$) automaticamente, e vice-versa.'
                      : 'Preencha a largura e o comprimento (ou qtd/unidade) deste material para que este campo seja calculado automaticamente com o Preço (R\$).',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: TextField(
                      controller: _precoM2Ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_PrecoInputFormatter()],
                      decoration: const InputDecoration(labelText: 'Preço m² (R\$)', prefixText: 'R\$ ', isDense: true),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: TextField(
                    controller: _observacaoCtrl,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Disponibilidade / Observação',
                      isDense: true,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)), onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          onPressed: () {
            final preco = _parsePreco(_precoCtrl.text);
            final precoM2 = _parsePreco(_precoM2Ctrl.text);
            final obs = _observacaoCtrl.text.trim().isEmpty ? null : _observacaoCtrl.text.trim();
            Navigator.pop(context, {'preco': preco, 'precoMetroQuadrado': precoM2, 'observacao': obs});
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
  State<_DialogDescartarOrcamento> createState() => _DialogDescartarOrcamentoState();
}

class _DialogDescartarOrcamentoState extends State<_DialogDescartarOrcamento> {
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
      title: Text('Cancelar Orçamento', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Este orçamento será movido para o histórico como cancelado.', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
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

class _TabNavBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _TabNavBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Icon(icon, size: 14, color: enabled ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

class _BotaoVoltar extends StatefulWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _BotaoVoltar({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_BotaoVoltar> createState() => _BotaoVoltarState();
}

class _BotaoVoltarState extends State<_BotaoVoltar> {
  bool _hovered = false;
  static const _accent = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? _accent.withValues(alpha: 0.15)
                  : _accent.withValues(alpha: 0.08),
              border: Border.all(
                color: _accent.withValues(alpha: _hovered ? 0.9 : 0.5),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: _accent,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}