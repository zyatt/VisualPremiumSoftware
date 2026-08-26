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
import '../utils/api_client.dart' show OrcamentoTravadoException;
import 'orcamento_historico_page.dart';
import 'orcamento_editor_page.dart';

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

double? _parseDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final str = value.toString().trim();
  if (str.isEmpty) return null;
  return double.tryParse(str);
}

String? _materialDimensaoFormatada(double? largura, double? comprimento) {
  if (largura == null || comprimento == null || largura <= 0 || comprimento <= 0) return null;
  String fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  return '${fmt(comprimento)}x${fmt(largura)}m';
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

bool _isErroOrcamentoNaoEncontrado(Object e) {
  final raw = e.toString();
  return raw.contains('Orçamento não encontrado');
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

  List<dynamic> _aguardandoAprovacao = [];
  List<dynamic> _aprovados = [];
  List<dynamic> _naoAprovados = [];
  bool _carregandoAprovacao = false;
  String? _erroAprovacao;

  int? _usuarioSelecionadoEmAberto;

  bool _salvandoPreco = false;

  final _tourKeyNovoOrcamento = GlobalKey();
  final _tourKeyAbaAguardandoAprovacao = GlobalKey();
  final _tourKeyCardAprovarFake = GlobalKey();
  final _tourKeyAbaAprovados = GlobalKey();
  final _tourKeyCardGerarOCFake = GlobalKey();

  bool _mostrarCardAprovacaoFakeNoTour = false;
  bool _mostrarCardGerarOCFakeNoTour = false;

  OrcamentoProvider? _orcamentoProviderRef;
  bool _ajudaRoboJaAgendadaNesteFrame = false;

  @override
  void initState() {
    super.initState();
    _logOrc('initState');
    _mainTabController = TabController(length: 4, vsync: this);
    _mainTabController.addListener(() {
      if (_mainTabController.indexIsChanging) return;
      if (_mainTabController.index != 0) {

        setState(() => _usuarioSelecionadoEmAberto = null);
      }
      _carregarOrcamentosServidor(origem: 'trocaDeTabPrincipal');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FornecedorProvider>().carregar();
      _carregarOrcamentosServidor(origem: 'initState');

      context.read<OrcamentoProvider>().carregarOrcamentosAbertos();
      context.read<RoboHelperProvider>().notificarRota('/orcamento');
    });

    context.read<OrcamentoProvider>().addListener(_onOrcamentoProviderChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _orcamentoProviderRef = context.read<OrcamentoProvider>();
  }

  void _onOrcamentoProviderChanged() {
    _tentarAbrirOrcamentoPendente();
  }

  bool _abrindoOrcamentoPendente = false;

  void _tentarAbrirOrcamentoPendente() {
    if (!mounted) return;
    final provider = context.read<OrcamentoProvider>();
    final orcamentoPendenteId = provider.orcamentoParaAbrirPendente;
    if (orcamentoPendenteId == null || _abrindoOrcamentoPendente) return;

    _abrindoOrcamentoPendente = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      provider.consumirOrcamentoParaAbrirPendente();
      try {
        final orcamentoCompleto = await OrcamentoRepository().buscarPorId(orcamentoPendenteId);
        if (!mounted) return;
        await _reabrirOrcamento({
          'id': orcamentoCompleto['id'],
          'status': orcamentoCompleto['status'],
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_mensagemErro(e, acao: 'abrir orçamento encaminhado')),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      } finally {
        _abrindoOrcamentoPendente = false;
      }
    });
  }

  @override
  void dispose() {
    _logOrc('dispose');
    _mainTabController.dispose();
    try {
      _orcamentoProviderRef?.removeListener(_onOrcamentoProviderChanged);
    } catch (_) {}
    try {
      context.read<RoboHelperProvider>().encerrarTour();
      context.read<RoboHelperProvider>().limparOpcoes('/orcamento');
    } catch (_) {}
    super.dispose();
  }

  bool _editorTourAberto = false;

  Future<void> _abrirEditorTour() async {
    if (_editorTourAberto) return;
    _editorTourAberto = true;
    tourQueAbriuEditorAtivo = 'Como criar um orçamento';
    final p = context.read<OrcamentoProvider>();
    p.adicionarAba(criadaPeloTour: true);
    final pushFuture = Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
    );

    pushFuture.then((resultado) async {
      if (mounted) _editorTourAberto = false;
      if (mounted) await _aoVoltarDoEditor(resultado);
    });

    const tentativasMax = 30;
    for (var i = 0; i < tentativasMax; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (criarOrcamentoTourKeyBlocoFiltros.currentContext != null) break;
    }
  }

  Future<void> _fecharEditorTourSeAberto() async {
    if (!_editorTourAberto) return;
    _editorTourAberto = false;
    tourQueAbriuEditorAtivo = null;

    try {
      context.read<OrcamentoProvider>().fecharAbaAposOperacao();
    } catch (_) {}
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> _mostrarCardAprovacaoFakeTour() async {
    if (mounted) setState(() => _mostrarCardAprovacaoFakeNoTour = true);
  }

  Future<void> _esconderCardAprovacaoFakeTour() async {
    if (mounted) setState(() => _mostrarCardAprovacaoFakeNoTour = false);
  }

  Map<String, dynamic> _itemFakeAprovacaoTour() {
    return {
      '_fakeTour': true,
      'id': -1,
      'titulo': '#EXEMPLO — orçamento de exemplo',
      'status': 'AGUARDANDO_APROVACAO',
      'criadoEm': DateTime.now().toIso8601String(),
      'criador': {'nome': 'Exemplo'},
      'itens': const [],
    };
  }

  Future<void> _abrirEditorTourAprovacao() async {
    if (_editorTourAberto) return;
    _editorTourAberto = true;
    tourQueAbriuEditorAtivo = 'Como aprovar um orçamento';
    final p = context.read<OrcamentoProvider>();
    p.adicionarAba(criadaPeloTour: true);
    p.atualizarFlagsTab(aguardandoAprovacao: true);
    final pushFuture = Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
    );

    pushFuture.then((resultado) async {
      if (mounted) _editorTourAberto = false;
      if (mounted) await _aoVoltarDoEditor(resultado);
    });

    const tentativasMax = 30;
    for (var i = 0; i < tentativasMax; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (editorTourEstaMontado()) break;
    }
    await inserirItemFakeParaAprovacaoNoEditorAtivo();
    for (var i = 0; i < tentativasMax; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (aprovarOrcamentoTourKeyBotaoAprovar.currentContext != null) break;
    }
  }

  Future<void> _mostrarCardGerarOCFakeTour() async {
    if (mounted) setState(() => _mostrarCardGerarOCFakeNoTour = true);
  }

  Future<void> _esconderCardGerarOCFakeTour() async {
    if (mounted) setState(() => _mostrarCardGerarOCFakeNoTour = false);
  }

  Map<String, dynamic> _itemFakeGerarOCTour() {
    return {
      '_fakeTour': true,
      'id': -1,
      'titulo': '#EXEMPLO — orçamento de exemplo',
      'status': 'APROVADO',
      'criadoEm': DateTime.now().toIso8601String(),
      'criador': {'nome': 'Exemplo'},
      'itens': const [],
    };
  }

  Future<void> _abrirEditorTourGerarOC() async {
    if (_editorTourAberto) return;
    _editorTourAberto = true;
    tourQueAbriuEditorAtivo = 'Como gerar uma Ordem de Compra';
    final p = context.read<OrcamentoProvider>();
    p.adicionarAba(criadaPeloTour: true);
    p.atualizarFlagsTab(jaFinalizado: true, modoGerarOC: true);
    final pushFuture = Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
    );

    pushFuture.then((resultado) async {
      if (mounted) _editorTourAberto = false;
      if (mounted) await _aoVoltarDoEditor(resultado);
    });

    const tentativasMax = 30;
    for (var i = 0; i < tentativasMax; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (editorTourEstaMontado()) break;
    }
    await inserirItemFakeParaGerarOCNoEditorAtivo();
    for (var i = 0; i < tentativasMax; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (gerarOCTourKeyBotaoGerarOC.currentContext != null) break;
    }
  }

  void _registrarAjudaRobo() {
    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isCurrent) return;

    final helper = context.read<RoboHelperProvider>();

    final opcoesAtuais = helper.opcoesAtuais;
    final opcaoExistente =
        opcoesAtuais.where((o) => o.titulo == 'Como criar um orçamento').firstOrNull;

    final editorJaAnexouExtras =
        opcaoExistente != null && opcaoExistente.paradas.length > 2;
    final tourDentroDoEditor = helper.tourAtivo && helper.passoAtual >= 2;
    if (editorJaAnexouExtras && tourDentroDoEditor) return;

    final paradasExtras = editorJaAnexouExtras
        ? opcaoExistente.paradas.sublist(2)
        : const <RoboTourStop>[];

    // Preserva genericamente qualquer opção que a listagem não conhece
    // (ex.: as registradas pelo editor, como "renomear" e "buscar
    // material"), em vez de checar título por título — assim, novas
    // opções que o editor vier a anexar no futuro não somem por a
    // listagem não ter sido atualizada para reconhecê-las.
    // IMPORTANTE: exclui também os títulos que a própria listagem recria
    // logo abaixo ("aprovar" e "gerar OC") — do contrário eles ficam
    // duplicados a cada chamada, pois entrariam tanto via
    // opcoesDoEditorPreservadas quanto via sua recriação explícita.
    const titulosFixosDaListagem = {
      'Como criar um orçamento',
      'Como aprovar um orçamento',
      'Como gerar uma Ordem de Compra',
    };
    final opcoesDoEditorPreservadas = opcoesAtuais
        .where((o) => !titulosFixosDaListagem.contains(o.titulo))
        .toList();

    _logOrc('_registrarAjudaRobo(listagem): rodando — opcoesDoEditorPreservadas='
        '${opcoesDoEditorPreservadas.map((o) => o.titulo).toList()}');

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

        aoEncerrar: _fecharEditorTourSeAberto,
      ),
      ...opcoesDoEditorPreservadas,
      RoboHelpOption(
        titulo: 'Como aprovar um orçamento',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyAbaAguardandoAprovacao,
            texto: 'Orçamentos enviados para aprovação aparecem aqui, na '
                'aba "Aguardando Aprovação".',
            aoEntrar: () async {
              if (_mainTabController.index != 1) {
                _mainTabController.animateTo(1);
                await Future<void>.delayed(const Duration(milliseconds: 300));
              }
              await _mostrarCardAprovacaoFakeTour();
            },
          ),
          RoboTourStop(
            key: () => _tourKeyCardAprovarFake,
            texto: 'Toque em "Aprovar" para aprovar o orçamento diretamente '
                'pela lista.',
            aoSair: _esconderCardAprovacaoFakeTour,
          ),
          RoboTourStop(
            key: () => aprovarOrcamentoTourKeyBotaoAprovar,
            texto: 'Você também pode abrir o orçamento para conferir os '
                'materiais e valores antes de tocar em "Aprovar" aqui '
                'dentro.',
            aoEntrar: _abrirEditorTourAprovacao,
            aoSair: _fecharEditorTourSeAberto,
          ),
        ],
        aoEncerrar: () async {
          await _esconderCardAprovacaoFakeTour();
          await _fecharEditorTourSeAberto();
        },
      ),
      RoboHelpOption(
        titulo: 'Como gerar uma Ordem de Compra',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyAbaAprovados,
            texto: 'Orçamentos aprovados aparecem aqui, na aba '
                '"Aprovados".',
            aoEntrar: () async {
              if (_mainTabController.index != 2) {
                _mainTabController.animateTo(2);
                await Future<void>.delayed(const Duration(milliseconds: 300));
              }
              await _mostrarCardGerarOCFakeTour();
            },
          ),
          RoboTourStop(
            key: () => _tourKeyCardGerarOCFake,
            texto: 'Toque em "Gerar OC" para gerar a Ordem de Compra '
                'diretamente pela lista.',
            aoSair: _esconderCardGerarOCFakeTour,
          ),
          RoboTourStop(
            key: () => gerarOCTourKeyBotaoGerarOC,
            texto: 'Você também pode abrir o orçamento para conferir os '
                'fornecedores selecionados antes de tocar em "Gerar OC" '
                'aqui dentro.',
            aoEntrar: _abrirEditorTourGerarOC,
            aoSair: _fecharEditorTourSeAberto,
          ),
        ],
        aoEncerrar: () async {
          await _esconderCardGerarOCFakeTour();
          await _fecharEditorTourSeAberto();
        },
      ),
    ]);
  }

  Future<void> _aoVoltarDoEditor(dynamic resultado) async {
    if (!mounted) return;
    int? abaAlvo;
    if (resultado == 'enviadoParaAprovacao') {
      abaAlvo = 1;
    } else if (resultado == 'aprovado') {
      abaAlvo = 2;
    }
    if (abaAlvo != null && _mainTabController.index != abaAlvo) {
      _mainTabController.animateTo(abaAlvo);
    }
    await _carregarOrcamentosServidor(origem: 'voltaDoEditor');
    if (mounted) {
      await context.read<OrcamentoProvider>().carregarOrcamentosAbertos();
    }
  }

  Future<void> _carregarOrcamentosServidor({String origem = 'manual'}) async {
    if (!mounted) return;
    if (_carregandoAprovacao) {

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
              style: TextButton.styleFrom().copyWith(
                  mouseCursor:
                      WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success)
                .copyWith(
                    mouseCursor:
                        WidgetStateProperty.all(SystemMouseCursors.click)),
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

  Future<void> _rejeitarOrcamento(int id, String titulo) async {
    final motivoCtrl = TextEditingController();
    bool mostrarErro = false;

    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Row(
            children: [
              const Expanded(
                child: Text('Rejeitar Orçamento',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Fechar',
                style: IconButton.styleFrom().copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              ),
            ],
          ),
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
                  labelText: 'Motivo',
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
                style: TextButton.styleFrom().copyWith(
                    mouseCursor:
                        WidgetStateProperty.all(SystemMouseCursors.click)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                  .copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click)),
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

  Future<void> _gerarOCDeOrcamentoAprovado(Map<String, dynamic> orc) async {
    final provider = context.read<OrcamentoProvider>();
    final orcId = orc['id'] as int;

    final abaExistente = await provider.ativarAbaExistenteAsync(orcId);
    if (abaExistente >= 0) {
      await _sincronizarAbaExistenteComServidor(orcId);
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
      provider.setCriadorIdTab(
        orcamentoCompleto['criadorId'] as int? ??
            (orcamentoCompleto['criador'] as Map?)?['id'] as int?,
      );
      provider.setFornecedoresOcultosTab(
        (orcamentoCompleto['fornecedoresOcultos'] as List? ?? []).map((e) => e as int).toList(),
      );
      provider.definirModoPrecificacao(orcamentoCompleto['modoPrecificacao'] as String? ?? 'UNIDADE');

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

  Future<void> _sincronizarAbaExistenteComServidor(int orcId) async {
    final provider = context.read<OrcamentoProvider>();
    if (provider.houveAlteracaoNaAbaAtiva) return;

    try {
      final orcamentoCompleto = await OrcamentoRepository().buscarPorId(orcId);
      if (!mounted) return;
      if (provider.tabAtual?.servidorId != orcId) return;

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

      final tituloRemoto = orcamentoCompleto['titulo'] as String?;
      final abaIndex = provider.abas.indexWhere((a) => a.servidorId == orcId);
      if (tituloRemoto != null &&
          tituloRemoto.isNotEmpty &&
          abaIndex != -1 &&
          provider.abas[abaIndex].titulo != tituloRemoto) {
        provider.renomearAba(abaIndex, tituloRemoto);
      }

      provider.marcarAbaAtivaComoSalva();
    } catch (e) {
      debugPrint('_sincronizarAbaExistenteComServidor: erro ao sincronizar orcamentoId=$orcId: $e');

    }
  }

  Future<void> _reabrirOrcamento(Map<String, dynamic> orc, {bool somenteLeitura = false}) async {
    final provider = context.read<OrcamentoProvider>();
    final orcId = orc['id'] as int;

    final abaExistente = await provider.ativarAbaExistenteAsync(orcId);
    if (abaExistente >= 0) {
      await _sincronizarAbaExistenteComServidor(orcId);
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

      final orcamentoCompleto =
          await OrcamentoRepository().buscarPorId(orcId);

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
      provider.setCriadorIdTab(
        orcamentoCompleto['criadorId'] as int? ??
            (orcamentoCompleto['criador'] as Map?)?['id'] as int?,
      );
      provider.setFornecedoresOcultosTab(
        (orcamentoCompleto['fornecedoresOcultos'] as List? ?? []).map((e) => e as int).toList(),
      );
      provider.definirModoPrecificacao(orcamentoCompleto['modoPrecificacao'] as String? ?? 'UNIDADE');

      provider.marcarAbaAtivaComoSalva();

      final statusReaberto = orc['status'] as String? ?? '';
      provider.atualizarFlagsTab(
        aguardandoAprovacao: statusReaberto == 'AGUARDANDO_APROVACAO',
        jaFinalizado: statusReaberto == 'APROVADO' || statusReaberto == 'NAO_APROVADO',
        modoGerarOC: statusReaberto == 'APROVADO',
        somenteLeitura: somenteLeitura,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$orcId carregado para edição.'),
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
            content: Text(_mensagemErro(e, acao: 'carregar orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

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
    if (!_ajudaRoboJaAgendadaNesteFrame) {
      _ajudaRoboJaAgendadaNesteFrame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ajudaRoboJaAgendadaNesteFrame = false;
        if (!mounted) return;
        final rota = ModalRoute.of(context);
        if (rota == null || !rota.isCurrent) return;
        // Segunda checagem, um microtask depois: garante que nenhuma rota
        // nova (ex.: o editor) tenha sido empilhada por cima entre o
        // agendamento deste callback e sua execução — evita a corrida em
        // que a listagem sobrescreve as opções do editor (buscar
        // material) por rodar seu build() logo antes do push terminar.
        //
        // Em vez de chamar ModalRoute.of(context) de novo depois do gap
        // assíncrono (o que exigiria usar `context` após um `await`/
        // microtask), guardamos a referência à rota já obtida acima e
        // apenas reconsultamos seu próprio `isCurrent` — isso não requer
        // `context` nenhum, então não há BuildContext atravessando o gap.
        Future.microtask(() {
          if (!mounted) return;
          if (!rota.isCurrent) return;
          _registrarAjudaRobo();
        });
      });
    }
    _tentarAbrirOrcamentoPendente();
    return Consumer<OrcamentoProvider>(
      builder: (context, provider, _) {
        if (!provider.carregado) {
          return Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }

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

                _buildHeader(),
                const SizedBox(height: 16),

                Expanded(child: _buildPainelAprovacao()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPainelEmAberto() {
    return Consumer<OrcamentoProvider>(
      builder: (context, provider, _) {
        if (provider.carregandoOrcamentosAbertos && provider.orcamentosAbertos.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.erroOrcamentosAbertos != null && provider.orcamentosAbertos.isEmpty) {
          return _buildErroCarregamento(
            provider.erroOrcamentosAbertos!,
            onRetry: () => provider.carregarOrcamentosAbertos(),
          );
        }

        final porUsuario = provider.orcamentosAbertosPorUsuario;

        if (porUsuario.isEmpty) {
          return _buildEstadoVazio(
            icon: Icons.folder_open_outlined,
            statusColor: AppTheme.primary,
            emptyMessage: 'Nenhum orçamento em aberto no momento',
            onRetry: () => provider.carregarOrcamentosAbertos(),
          );
        }

        final selecionadoAindaValido = _usuarioSelecionadoEmAberto != null &&
            porUsuario.any((e) => e.key == _usuarioSelecionadoEmAberto);
        if (_usuarioSelecionadoEmAberto != null && !selecionadoAindaValido) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _usuarioSelecionadoEmAberto = null);
          });
        }

        if (_usuarioSelecionadoEmAberto != null && selecionadoAindaValido) {
          final entrada = porUsuario.firstWhere((e) => e.key == _usuarioSelecionadoEmAberto);
          return _buildListaOrcamentosDoUsuario(entrada.value);
        }

        return _buildGradeUsuariosEmAberto(porUsuario);
      },
    );
  }

  Widget _buildGradeUsuariosEmAberto(List<MapEntry<int, List<OrcamentoAbertoInfo>>> porUsuario) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 116,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: porUsuario.length,
      itemBuilder: (ctx, i) {
        final entrada = porUsuario[i];
        final orcamentos = entrada.value;
        final provider = context.read<OrcamentoProvider>();
        final ehEuMesmo = entrada.key == provider.usuarioAtualId;

        final nome = orcamentos.first.criadorNome ??
            (ehEuMesmo ? provider.usuarioAtualNome : null) ??
            'Usuário #${entrada.key}';
        final emEdicaoAgora = orcamentos.any((o) => o.emEdicaoPorOutro(provider.usuarioAtualId));

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _usuarioSelecionadoEmAberto = entrada.key),
          mouseCursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                      child: Text(
                        nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary),
                      ),
                    ),
                    const Spacer(),
                    if (emEdicaoAgora)
                      Tooltip(
                        message: 'Há um orçamento sendo editado agora',
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  '${orcamentos.length} ${orcamentos.length == 1 ? 'orçamento' : 'orçamentos'}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListaOrcamentosDoUsuario(List<OrcamentoAbertoInfo> orcamentos) {
    final provider = context.read<OrcamentoProvider>();
    final ehEuMesmo = orcamentos.isNotEmpty && orcamentos.first.criadorId == provider.usuarioAtualId;
    final nome = orcamentos.first.criadorNome ??
        (ehEuMesmo ? provider.usuarioAtualNome : null) ??
        'Usuário';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _usuarioSelecionadoEmAberto = null),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: Text('Todos os usuários', style: const TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primary)
              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
        ),
        const SizedBox(height: 4),
        Text(
          'Orçamentos em aberto de $nome',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: orcamentos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final orc = orcamentos[i];
              final souCriador = context.read<OrcamentoProvider>().souCriadorDe(orc.criadorId);
              return _OrcamentoEmAbertoCard(
                info: orc,
                onTap: () => _abrirOrcamentoEmAberto(orc),
                onAbrirPdf: () => _baixarPdfOrcamentoAberto(orc),
                onEnviarAprovacao: () => _enviarParaAprovacaoEmAberto(orc),
                onExcluir: souCriador ? () => _excluirOrcamentoEmAberto(orc) : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEstadoVazio({
    required IconData icon,
    required Color statusColor,
    required String emptyMessage,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 36, color: statusColor),
          ),
          const SizedBox(height: 20),
          Text(
            emptyMessage,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: 'Atualizar lista',
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Atualizar'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary)
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErroCarregamento(String erro, {required VoidCallback onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 36, color: AppTheme.error),
          const SizedBox(height: 16),
          Text(erro, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirOrcamentoEmAberto(OrcamentoAbertoInfo info) async {
    final provider = context.read<OrcamentoProvider>();

    final abaExistente = await provider.ativarAbaExistenteAsync(info.id);
    if (abaExistente >= 0) {
      bool somenteLeituraAbaExistente = false;
      try {
        await OrcamentoRepository().travar(info.id);
      } on OrcamentoTravadoException catch (e) {
        if (!mounted) return;
        final continuar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Orçamento em edição',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            content: Text(
              '${e.travaUsuarioNome ?? 'Outro usuário'} está editando este orçamento agora.\n\n'
              'Você pode abrir para visualizar, mas não poderá editar até que a pessoa termine.',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Abrir para visualizar'),
              ),
            ],
          ),
        );
        if (continuar != true) return;
        somenteLeituraAbaExistente = true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_mensagemErro(e, acao: 'abrir orçamento')),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }

      provider.atualizarFlagsTab(somenteLeitura: somenteLeituraAbaExistente);
      await _sincronizarAbaExistenteComServidor(info.id);
      if (mounted) {
        final resultado = await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
        );
        await _aoVoltarDoEditor(resultado);
      }
      return;
    }

    bool somenteLeitura = false;
    try {
      await OrcamentoRepository().travar(info.id);
    } on OrcamentoTravadoException catch (e) {
      if (!mounted) return;
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Orçamento em edição',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Text(
            '${e.travaUsuarioNome ?? 'Outro usuário'} está editando este orçamento agora.\n\n'
            'Você pode abrir para visualizar, mas não poderá editar até que a pessoa termine.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Abrir para visualizar'),
            ),
          ],
        ),
      );
      if (continuar != true) return;
      somenteLeitura = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'abrir orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    await _reabrirOrcamento({'id': info.id, 'status': 'ABERTO'}, somenteLeitura: somenteLeitura);
  }

  Future<void> _baixarPdfOrcamentoAberto(OrcamentoAbertoInfo info) async {
    try {
      final orcamentoCompleto = await OrcamentoRepository().buscarPorId(info.id);
      if (!mounted) return;
      await _baixarPdfOrcamento(orcamentoCompleto);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'gerar PDF do orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _enviarParaAprovacaoEmAberto(OrcamentoAbertoInfo info) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar para Aprovação',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          'Deseja enviar o orçamento "${info.titulo}" para aprovação?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final provider = context.read<OrcamentoProvider>();
    try {
      await OrcamentoRepository().enviarParaAprovacao(info.id);

      final idx = provider.ativarAbaExistente(info.id);
      if (idx >= 0) provider.fecharAba(idx);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento "${info.titulo}" enviado para aprovação!'),
          backgroundColor: AppTheme.success,
        ),
      );
      if (_mainTabController.index != 1) {
        _mainTabController.animateTo(1);
      }
      await provider.carregarOrcamentosAbertos();
      await _carregarOrcamentosServidor(origem: 'aposEnviarAprovacaoEmAberto');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isErroDeStatusDesatualizado(e)
                  ? 'O status deste orçamento mudou (outra pessoa já alterou). A lista foi atualizada.'
                  : _mensagemErro(e, acao: 'enviar orçamento para aprovação'),
            ),
            backgroundColor: AppTheme.error,
          ),
        );
        if (_isErroDeStatusDesatualizado(e)) {
          await provider.carregarOrcamentosAbertos();
        }
      }
    }
  }

  Future<void> _excluirOrcamentoEmAberto(OrcamentoAbertoInfo info) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Orçamento',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          'Tem certeza que deseja excluir o orçamento "${info.titulo}"?\n\n'
          'Essa ação não pode ser desfeita.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final provider = context.read<OrcamentoProvider>();
    try {
      final repo = OrcamentoRepository();
      await repo.cancelar(info.id);
      await repo.excluir(info.id);

      final idx = provider.ativarAbaExistente(info.id);
      if (idx >= 0) provider.fecharAba(idx);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento "${info.titulo}" excluído.'),
          backgroundColor: AppTheme.success,
        ),
      );
      await provider.carregarOrcamentosAbertos();
    } catch (e) {
      if (_isErroOrcamentoNaoEncontrado(e)) {

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Este orçamento já havia sido excluído.'),
            backgroundColor: AppTheme.warning,
          ),
        );
        await provider.carregarOrcamentosAbertos();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'excluir orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

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
                    const Text('Em Aberto'),
                    const SizedBox(width: 6),
                    Consumer<OrcamentoProvider>(
                      builder: (context, provider, _) =>
                          _badgeContagem(provider.orcamentosAbertos.length),
                    ),
                  ],
                ),
              ),
              Tab(
                key: _tourKeyAbaAguardandoAprovacao,
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
                key: _tourKeyAbaAprovados,
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
              _buildPainelEmAberto(),
              _buildListaAprovacao(
                lista: _mostrarCardAprovacaoFakeNoTour
                    ? [_itemFakeAprovacaoTour(), ..._aguardandoAprovacao]
                    : _aguardandoAprovacao,
                emptyMessage: 'Nenhum orçamento aguardando aprovação',
                emptyIcon: Icons.pending_outlined,
                statusColor: AppTheme.warning,
                mostrarAcoes: true,
              ),
              _buildListaAprovacao(
                lista: _mostrarCardGerarOCFakeNoTour
                    ? [_itemFakeGerarOCTour(), ..._aprovados]
                    : _aprovados,
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
            const SizedBox(height: 2),
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

              }
            },
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

        const SizedBox(width: 10),

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
                    const Icon(Icons.edit_note, size: 18),
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
                label: const Text('Aberto'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: temAbas ? AppTheme.warning : Theme.of(context).colorScheme.onSurface,
                  side: BorderSide(
                      color: temAbas ? AppTheme.warning : Theme.of(context).colorScheme.outlineVariant),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ).copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
              ),
            );
          },
        ),

        const SizedBox(width: 10),

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
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Novo Orçamento'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
          ),
        ),

        const SizedBox(width: 12),

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
              final ehCardFakeAprovacao = mostrarAcoes &&
                  _mostrarCardAprovacaoFakeNoTour &&
                  i == 0 &&
                  orc['_fakeTour'] == true;
              final ehCardFakeGerarOC = _mostrarCardGerarOCFakeNoTour &&
                  i == 0 &&
                  orc['_fakeTour'] == true;
              final ehCardFakeDoTour = ehCardFakeAprovacao || ehCardFakeGerarOC;
              return _OrcamentoAprovacaoCard(
                orcamento: orc,
                statusColor: statusColor,
                mostrarAcoes: mostrarAcoes,
                chaveBotaoAprovar: ehCardFakeAprovacao ? _tourKeyCardAprovarFake : null,
                chaveBotaoGerarOC: ehCardFakeGerarOC ? _tourKeyCardGerarOCFake : null,
                onTap: ehCardFakeDoTour ? null : () => _reabrirOrcamento(orc),
                onAbrirPdf: ehCardFakeDoTour ? null : () => _baixarPdfOrcamento(orc),
                onAprovar: mostrarAcoes && !ehCardFakeDoTour
                    ? () => _aprovarOrcamento(orc['id'] as int, orc['titulo'] as String? ?? '')
                    : (ehCardFakeAprovacao ? () {} : null),
                onRejeitar: mostrarAcoes && !ehCardFakeDoTour
                    ? () => _rejeitarOrcamento(orc['id'] as int, orc['titulo'] as String? ?? '')
                    : null,
                onReabrir: ehCardFakeDoTour ? null : () => _reabrirOrcamento(orc),
                onGerarOC: orc['status'] == 'APROVADO' && !ehCardFakeDoTour
                    ? () => _gerarOCDeOrcamentoAprovado(orc)
                    : (ehCardFakeGerarOC ? () {} : null),
              );
            },
          ),
        ),
      ],
    );
  }

}

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
  final Key? chaveBotaoAprovar;
  final Key? chaveBotaoGerarOC;

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
    this.chaveBotaoAprovar,
    this.chaveBotaoGerarOC,
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
                          key: widget.chaveBotaoAprovar,
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
                          key: widget.chaveBotaoGerarOC,
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
      title: Row(
        children: [
          Expanded(
            child: Text('Adicionar Fornecedores — ${widget.materialNome}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Fechar',
            style: IconButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
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
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Editar Preço — ${widget.fornecedorNome}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Fechar',
            style: IconButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
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
      title: Row(
        children: [
          Expanded(
            child: Text('Cancelar Orçamento',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Fechar',
            style: IconButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
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
              labelText: 'Motivo do cancelamento',
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

class _OrcamentoEmAbertoCard extends StatefulWidget {
  final OrcamentoAbertoInfo info;
  final VoidCallback onTap;

  final VoidCallback? onAbrirPdf;
  final VoidCallback? onEnviarAprovacao;
  final VoidCallback? onExcluir;

  const _OrcamentoEmAbertoCard({
    required this.info,
    required this.onTap,
    this.onAbrirPdf,
    this.onEnviarAprovacao,
    this.onExcluir,
  });

  @override
  State<_OrcamentoEmAbertoCard> createState() => _OrcamentoEmAbertoCardState();
}

class _OrcamentoEmAbertoCardState extends State<_OrcamentoEmAbertoCard> {
  bool _hovered = false;

  String _formatDataCardAberto(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final emEdicaoPorOutro =
        info.emEdicaoPorOutro(context.watch<OrcamentoProvider>().usuarioAtualId);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hovered
                ? AppTheme.primary.withValues(alpha: 0.05)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              children: [
                Positioned(
                  left: 0, top: 0, bottom: 0, width: 4,
                  child: ColoredBox(color: AppTheme.primary),
                ),
                if (widget.onExcluir != null && info.travaUsuarioId == null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Tooltip(
                      message: 'Excluir orçamento',
                      child: IconButton(
                        onPressed: widget.onExcluir,
                        icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                        style: IconButton.styleFrom().copyWith(
                          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: widget.onExcluir != null && info.travaUsuarioId == null ? 44 : 16,
                    top: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${info.id} — ${info.titulo}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (info.criadoEm != null || info.criadorNome != null) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.calendar_today_outlined,
                                          size: 13,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          [
                                            if (info.criadoEm != null)
                                              'Criado em ${_formatDataCardAberto(info.criadoEm!)}',
                                            if (info.criadorNome != null) 'por ${info.criadorNome}',
                                          ].join(' '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (emEdicaoPorOutro)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                        color: AppTheme.success, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Em edição por ${info.travaUsuarioNome ?? '...'}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.success),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (info.materiais.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: info.materiais.map((m) {
                            final nomeBase = m.nome.isNotEmpty ? m.nome : 'Material excluído';
                            final medidaOuDimensao = (m.medida != null && m.medida!.isNotEmpty)
                                ? m.medida
                                : _materialDimensaoFormatada(m.largura, m.comprimento);
                            final espessuraFormatada = (m.espessura != null && m.espessura!.isNotEmpty)
                                ? (m.espessura!.toLowerCase().endsWith('mm') ? m.espessura : '${m.espessura}mm')
                                : null;
                            final partes = <String>[
                              if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
                              if (espessuraFormatada != null) espessuraFormatada,
                            ];
                            final nomeComPartes =
                                partes.isEmpty ? nomeBase : '$nomeBase · ${partes.join(' · ')}';
                            final desc = (m.identificador != null && m.identificador!.isNotEmpty)
                                ? '${m.identificador} · $nomeComPartes'
                                : nomeComPartes;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                desc,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.onAbrirPdf != null) ...[
                            Tooltip(
                              message: 'Baixar PDF do orçamento',
                              child: OutlinedButton.icon(
                                onPressed: widget.onAbrirPdf,
                                icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                                label: const Text('PDF', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ).copyWith(
                                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Tooltip(
                            message: 'Abrir orçamento para edição',
                            child: OutlinedButton.icon(
                              onPressed: widget.onTap,
                              icon: const Icon(Icons.edit_outlined, size: 14),
                              label: const Text('Abrir', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: const BorderSide(color: AppTheme.primary),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ).copyWith(
                                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                              ),
                            ),
                          ),
                          if (widget.onEnviarAprovacao != null) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Enviar orçamento para aprovação',
                              child: FilledButton.icon(
                                onPressed: emEdicaoPorOutro ? null : widget.onEnviarAprovacao,
                                icon: const Icon(Icons.send_outlined, size: 14),
                                label: const Text('Enviar p/ Aprovação', style: TextStyle(fontSize: 12)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
}