import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import '../repositories/fornecedor_repository.dart';
import '../repositories/orcamento_repository.dart';
import '../rotas/app_router.dart';

import '../theme/app_theme.dart';

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

String _brl(double? v) {
  if (v == null || v == 0) return '—';
  return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

class OrcamentoEditorPage extends StatefulWidget {
  const OrcamentoEditorPage({super.key});

  @override
  State<OrcamentoEditorPage> createState() => _OrcamentoEditorPageState();
}

class _OrcamentoEditorPageState extends State<OrcamentoEditorPage> {
  final _searchIdCtrl = TextEditingController();
  final _searchNomeCtrl = TextEditingController();
  final _searchIdentificadorCtrl = TextEditingController();
  final _searchMedidaCtrl = TextEditingController();
  final _searchEspCtrl = TextEditingController();
  final _abasScrollCtrl = ScrollController();
  final _tabelaHScrollCtrl = ScrollController();
  final _pageScrollCtrl = ScrollController();
  Timer? _debounceMatBusca;
  late final _ScrollMetricsNotifier _abasScrollHintNotifier;
  late final _ScrollMetricsNotifier _tabelaHScrollHintNotifier;

  List<MaterialModel> _resultadosBusca = [];
  bool _buscando = false;
  bool _mostrarResultados = false;
  bool _salvando = false;
  String _ordemTotais = 'unitario';

  final Set<String> _itensSelecionados = {};
  final Set<String> _materiaisParaBulk = {};

  static String _textoMaterial(dynamic item) {
    final partes = <String>[item.materialNome as String];
    final medida = item.materialMedida as String?;
    final esp    = item.materialEspessura as String?;
    if (medida != null && medida.isNotEmpty) partes.add(medida);
    if (esp    != null && esp.isNotEmpty)    partes.add(esp);
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
    _abasScrollHintNotifier = _ScrollMetricsNotifier();
    _tabelaHScrollHintNotifier = _ScrollMetricsNotifier();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sincronizarStatusServidor();
      context.read<FornecedorProvider>().carregar();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _tabelaHScrollCtrl.hasClients) {
          _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
        }
        if (mounted && _abasScrollCtrl.hasClients) {
          _abasScrollHintNotifier.update(_abasScrollCtrl);
        }
      });
    });
    _tabelaHScrollCtrl.addListener(() {
      if (mounted) _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
    });
    _abasScrollCtrl.addListener(() {
      if (mounted) _abasScrollHintNotifier.update(_abasScrollCtrl);
    });
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
    _debounceMatBusca?.cancel();
    _searchIdCtrl.dispose();
    _searchNomeCtrl.dispose();
    _searchIdentificadorCtrl.dispose();
    _searchMedidaCtrl.dispose();
    _searchEspCtrl.dispose();
    _abasScrollCtrl.dispose();
    _tabelaHScrollCtrl.dispose();
    _pageScrollCtrl.dispose();
    _abasScrollHintNotifier.dispose();
    _tabelaHScrollHintNotifier.dispose();
    super.dispose();
  }

  void _agendarBuscaMateriais() {
    _debounceMatBusca?.cancel();
    _debounceMatBusca = Timer(const Duration(milliseconds: 400), _executarBuscaMateriais);
  }

  Future<void> _executarBuscaMateriais() async {
    final id = _searchIdCtrl.text.trim();
    final nome = _searchNomeCtrl.text.trim();
    final identificador = _searchIdentificadorCtrl.text.trim();
    final medida = _searchMedidaCtrl.text.trim();
    final esp = _searchEspCtrl.text.trim();

    final algumFiltro = id.isNotEmpty || nome.isNotEmpty || identificador.isNotEmpty || medida.isNotEmpty || esp.isNotEmpty;

    if (!algumFiltro) {
      setState(() { _resultadosBusca = []; _mostrarResultados = false; });
      return;
    }
    setState(() { _buscando = true; _mostrarResultados = true; });
    try {
      await context.read<MaterialProvider>().carregar(
        busca: nome.isNotEmpty ? nome : '',
        id: id.isNotEmpty ? id : '',
        identificador: identificador.isNotEmpty ? identificador : '',
        medida: medida.isNotEmpty ? medida : '',
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
        precoM2: fm.precoMetroQuadrado > 0 ? fm.precoMetroQuadrado : null,
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
      precos: precos,
    ));
    _searchIdCtrl.clear();
    _searchNomeCtrl.clear();
    _searchIdentificadorCtrl.clear();
    _searchMedidaCtrl.clear();
    _searchEspCtrl.clear();
    setState(() { _resultadosBusca = []; _mostrarResultados = false; });
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

    // Recarrega a lista de fornecedores do servidor antes de abrir o diálogo,
    // garantindo que fornecedores cadastrados por outros usuários apareçam
    // (e que vínculos novos não sejam erroneamente exibidos como "já vinculados").
    await context.read<FornecedorProvider>().carregar();
    if (!mounted) return;

    final fornecedores = context.read<FornecedorProvider>().fornecedores;

    // Busca do servidor os fornecedores já vinculados a ESTE material específico.
    // Usar só item.precos.keys não é suficiente: o cache local pode ter IDs de
    // outro material (situação que ocorreu com ABS ACO ESCOVADO PRATA vs DOURADO).
    final vinculadosNoServidor =
        await context.read<FornecedorProvider>().listarPorMaterial(item.materialId);
    if (!mounted) return;

    // União: já está no orçamento local OU já está vinculado ao material no servidor.
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
        observacaoAtual: pf.observacao,
      ),
    );
    if (result == null) return;

    final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
    novosPrecos[fornecedorId] = PrecoFornecedorData(
      fornecedorNome: pf.fornecedorNome,
      preco: result['preco'] as double?,
      precoM2: pf.precoM2, // mantém o precoM2 existente intocado
      observacao: result['observacao'] as String?,
    );
    provider.atualizarItemParcial(item.itemId, precos: novosPrecos);

    setState(() => _salvando = true);
    try {
      await FornecedorRepository().atualizarPreco(fornecedorId, item.materialId, {
        if (result['preco'] != null) 'preco': result['preco'],
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Garante que a lista de fornecedores ocultos da aba esteja persistida no
  /// servidor para o orçamento [orcId]. Necessário porque, enquanto o
  /// orçamento ainda não existe no banco (servidorId nulo), o usuário pode
  /// ocultar fornecedores só localmente — ao salvar pela primeira vez, essa
  /// lista precisa ser enviada para já nascer compartilhada com outros
  /// usuários. Para orçamentos já existentes, as ocultações já são
  /// persistidas individualmente em `_alternarFornecedorOculto`, então isto
  /// é apenas uma garantia idempotente (reenviar o mesmo id não tem efeito).
  Future<void> _sincronizarFornecedoresOcultos(int orcId, OrcamentoTab tab) async {
    if (tab.fornecedoresOcultos.isEmpty) return;
    final repo = OrcamentoRepository();
    for (final fornecedorId in tab.fornecedoresOcultos) {
      await repo.definirFornecedorOculto(orcId, fornecedorId, true);
    }
  }

  Future<void> _salvarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos um material para salvar.')));
      return;
    }

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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
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
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});
        await repo.limparItens(orcId);
      } else {
        final criado = await repo.criar(novoTitulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});
      }
      final tabAtualizado = provider.tabAtual!;
      await _sincronizarFornecedoresOcultos(orcId, tabAtualizado);
      for (final item in tabAtualizado.itens) {
        if (item.precos.isEmpty) {
          await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
          }
        }
      }
      if (!mounted) return;
      provider.fecharAbaAposOperacao();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento #$orcId salvo com sucesso!'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'salvar orçamento')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _enviarParaAprovacao() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos um material antes de enviar para aprovação.')));
      return;
    }

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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
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
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});
        await repo.limparItens(orcId);
      } else {
        final criado = await repo.criar(novoTitulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});
      }
      await _sincronizarFornecedoresOcultos(orcId, tab);
      for (final item in tab.itens) {
        if (item.precos.isEmpty) {
          await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
          }
        }
      }
      await repo.enviarParaAprovacao(orcId);
      provider.limparAba();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento #$orcId enviado para aprovação com sucesso!'), backgroundColor: AppTheme.success));
      provider.atualizarFlagsTab(aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'enviar para aprovação')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _aprovarOrcamento(int id, String titulo) async {
    final provider = context.read<OrcamentoProvider>();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar Orçamento', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('Deseja aprovar este orçamento?\n\nApós a aprovação, o usuário Compras poderá gerar uma Ordem de Compra.', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.success), onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprovar')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _salvando = true);
    final tab = provider.tabAtual;
    try {
      if (tab != null) {
        final repo = OrcamentoRepository();
        await repo.limparItens(id);
        for (final item in tab.itens) {
         if (item.precos.isEmpty) {
          await repo.adicionarItem(id, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(id, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
          }
        }
        }
      }
      await OrcamentoRepository().aprovar(id);
      if (!mounted) return;
      provider.atualizarFlagsTab(aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);
      provider.fecharAbaAposOperacao();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento #$id aprovado com sucesso!'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'aprovar orçamento')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _sincronizarStatusServidor() async {
    final provider = context.read<OrcamentoProvider>();
    final sid = provider.tabAtual?.servidorId;
    if (sid == null) return;
    try {
      final orc = await OrcamentoRepository().buscarPorId(sid);
      if (!mounted) return;
      final status = orc['status'] as String? ?? '';
      provider.atualizarFlagsTab(
        aguardandoAprovacao: status == 'AGUARDANDO_APROVACAO',
        jaFinalizado: status == 'APROVADO' || status == 'NAO_APROVADO',
        modoGerarOC: status == 'APROVADO',
      );
    } catch (_) {}
  }

  Future<void> _salvarAoFecharAba(int index) async {
    final provider = context.read<OrcamentoProvider>();
    final abas = provider.abas;
    if (index < 0 || index >= abas.length) {
      provider.fecharAba(index);
      return;
    }
    final aba = abas[index];
    final sid = aba.servidorId;

    if (sid != null && aba.itens.isNotEmpty) {
      try {
        final repo = OrcamentoRepository();
        await repo.limparItens(sid);
        for (final item in aba.itens) {
          if (item.precos.isEmpty) {
            await repo.adicionarItem(sid, {
              'materialId': item.materialId,
              'fornecedorId': null,
              'quantidade': item.quantidade,
              'precoUnitario': null,
              'precoM2': null,
              'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado,
              'selecionado': false,
            });
          } else {
            for (final entry in item.precos.entries) {
              await repo.adicionarItem(sid, {
                'materialId': item.materialId,
                'fornecedorId': entry.key,
                'quantidade': item.quantidade,
                'precoUnitario': entry.value.preco,
                'precoM2': entry.value.precoM2,
                'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado,
                'selecionado': item.fornecedorSelecionado == entry.key,
                'observacao': entry.value.observacao,
              });
            }
          }
        }
      } catch (_) {
        // Falha silenciosa — fecha a aba de qualquer jeito
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Não')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    setState(() => _salvando = true);
    try {
      if (temServidorId) await OrcamentoRepository().cancelar(tab!.servidorId!);
      provider.fecharAbaAposOperacao();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(temServidorId ? 'Orçamento #${tab!.servidorId} cancelado.' : 'Rascunho descartado.'),
        backgroundColor: AppTheme.error,
      ));
      provider.atualizarFlagsTab(aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'cancelar orçamento')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Monta a lista de itens para envio ao serviço de PDF, removendo os preços
  /// de fornecedores ocultos. Um fornecedor oculto não deve aparecer na
  /// matriz do PDF nem entrar em nenhum cálculo de melhor preço/total — sem
  /// isso, o filtro de "ocultar" feito na tela não se refletiria no PDF
  /// gerado, já que o serviço de PDF só conhece o que é enviado no payload.
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

  Future<void> _exportarPdf() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos um material antes de exportar.')));
      return;
    }
    setState(() => _salvando = true);
    try {
      final pdfBytes = await OrcamentoRepository().gerarPdf({
        'titulo': tab.titulo,
        'itens': _itensParaPdf(tab),
        'fornecedoresOcultos': tab.fornecedoresOcultos,
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensagemErro(e, acao: 'exportar PDF')), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _gerarOrdemCompra(List<ItemOrcamentoData> itens) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null) return;

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
    try {
      if (tab.servidorId != null) {
        orcId = tab.servidorId!;
        await _sincronizarFornecedoresOcultos(orcId, tab);
        await repo.limparItens(orcId);
        for (final item in tab.itens) {
        if (item.precos.isEmpty) {
          await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
          }
        }
        }
      } else {
        final criado = await repo.criar(tab.titulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': tab.titulo});
        await _sincronizarFornecedoresOcultos(orcId, tab);
        for (final item in tab.itens) {
          if (item.precos.isEmpty) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false});
          } else {
            for (final entry in item.precos.entries) {
              await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'observacao': entry.value.observacao});
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
      final result = await repo.gerarOrdemCompra(orcId);
      if (!mounted) return;

      if (result['pronto'] == true) {
        final ocsCriadas = result['ocsCriadas'] as List?;
        final qtdOCs = ocsCriadas?.length ?? porFornecedor.length;
        final primeiraOcId = ocsCriadas?.isNotEmpty == true ? (ocsCriadas!.first['id'] as int?) : null;

        // Fecha a aba antes de navegar para que, ao voltar para /orcamento-compras,
        // o usuário veja o painel de aprovação/lista — não o editor sem abas.
        provider.fecharAbaAposOperacao();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$qtdOCs ${qtdOCs == 1 ? "OC gerada" : "OCs geradas"} com sucesso!'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 3),
        ));

        // Sempre sinaliza primeiro: cobre o caso de primeira visita à página
        // (initState ainda não rodou e a key abaixo ainda não está anexada).
        if (primeiraOcId != null && mounted) {
          context.read<OrdemCompraProvider>().sinalizarOcParaAbrir(primeiraOcId);
        }

        context.go('/ordem-compra');

        // Caso a página de Ordem de Compra já esteja viva (StatefulShellRoute
        // preserva estado entre navegações), nem initState nem
        // didChangeDependencies são re-executados só porque trocamos de branch.
        // Chamamos o método diretamente pela GlobalKey para recarregar a lista
        // e abrir os detalhes da OC certa de forma síncrona e confiável —
        // inclusive fechando os detalhes de outra OC que estivessem abertos.
        if (primeiraOcId != null) {
          final state = ordemCompraPageKey.currentState;
          if (state != null) {
            // Página já montada: consome o sinal nós mesmos (evita reabertura)
            // e chamamos diretamente, sem depender de lifecycle hooks.
            context.read<OrdemCompraProvider>().consumirOcPendente();
            await state.abrirOcPorId(primeiraOcId);
          }
          // Se state for null, é a primeira visita: o initState da página vai
          // consumir o sinal já setado acima através do postFrameCallback.
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

  /// IDs de fornecedores presentes nos itens, EXCLUINDO os ocultados na aba
  /// ativa. Usado pela matriz, totais, melhor preço e payload do PDF — ou
  /// seja, em todo lugar que não deve "ver" um fornecedor oculto.
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

  /// Oculta ou reexibe um fornecedor na visualização deste orçamento (matriz,
  /// totais, melhor preço e PDF). Não remove o fornecedor nem nenhum item ou
  /// preço — é reversível e fica salvo no orçamento, visível para qualquer
  /// usuário que o abrir depois (inclusive após enviar para aprovação).
  Future<void> _alternarFornecedorOculto(int fornecedorId, bool oculto) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null) return;

    // Atualiza localmente de imediato para resposta instantânea na UI.
    provider.definirFornecedorOcultoLocal(fornecedorId, oculto);

    // Se ocultando um fornecedor que estava selecionado em algum item, limpa
    // a seleção desses itens — um fornecedor oculto não pode permanecer
    // "escolhido" para fins de geração de OC.
    if (oculto) {
      for (final item in List.of(tab.itens)) {
        if (item.fornecedorSelecionado == fornecedorId) {
          provider.atualizarItemParcial(item.itemId, clearFornecedor: true);
        }
      }
    }

    // Persiste no servidor apenas se o orçamento já existe lá. Se ainda é um
    // rascunho local (servidorId nulo), a lista será enviada junto ao salvar.
    if (tab.servidorId != null) {
      try {
        await OrcamentoRepository().definirFornecedorOculto(tab.servidorId!, fornecedorId, oculto);
      } catch (e) {
        if (!mounted) return;
        // Reverte o estado local se o servidor não confirmar, para não ficar
        // dessincronizado entre os usuários.
        provider.definirFornecedorOcultoLocal(fornecedorId, !oculto);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mensagemErro(e, acao: oculto ? 'ocultar fornecedor' : 'reexibir fornecedor')),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }

  /// Mostra a lista de fornecedores ocultos do orçamento, com opção de
  /// reexibir cada um. É o único jeito de reverter uma ocultação, já que a
  /// coluna do fornecedor desaparece da matriz assim que ele é ocultado.
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
                        trailing: TextButton.icon(
                          onPressed: () async {
                            await _alternarFornecedorOculto(fId, false);
                            setSt(() {});
                          },
                          icon: const Icon(Icons.visibility_outlined, size: 14),
                          label: const Text('Reexibir', style: TextStyle(fontSize: 12)),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        );
      }),
    );
  }

  void _aplicarSugestaoOtimizada(List<ItemOrcamentoData> itens) {
    final provider = context.read<OrcamentoProvider>();
    final ocultos = provider.tabAtual?.fornecedoresOcultos.toSet() ?? const <int>{};
    final ordenarPorM2 = _ordemTotais == 'm2';
    for (final item in itens) {
      if (item.precos.isEmpty) continue;
      double? menorValor; int? fornEscolhido; ModoOrcamento? modoEscolhido;
      for (final entry in item.precos.entries) {
        if (ocultos.contains(entry.key)) continue;
        if (ordenarPorM2) {
          if (entry.value.precoM2 != null && (menorValor == null || entry.value.precoM2! < menorValor)) { menorValor = entry.value.precoM2; fornEscolhido = entry.key; modoEscolhido = ModoOrcamento.metroQuadrado; }
        } else {
          if (entry.value.preco != null && (menorValor == null || entry.value.preco! < menorValor)) { menorValor = entry.value.preco; fornEscolhido = entry.key; modoEscolhido = ModoOrcamento.unitario; }
        }
      }
      if (fornEscolhido != null && modoEscolhido != null) provider.atualizarItemParcial(item.itemId, fornecedorSelecionado: fornEscolhido, modoOrcamento: modoEscolhido);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sugestão de orçamento otimizado aplicada!'), backgroundColor: AppTheme.success));
  }

  @override
  Widget build(BuildContext context) {
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
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.arrow_back_ios_new, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
              tooltip: 'Voltar',
            ),
            title: Row(
              children: [
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
                                  _searchIdCtrl.clear();
                                  _searchNomeCtrl.clear();
                                  _searchIdentificadorCtrl.clear();
                                  _searchMedidaCtrl.clear();
                                  _searchEspCtrl.clear();
                                  _resultadosBusca = [];
                                  _mostrarResultados = false;
                                });
                                provider.selecionarAba(i);
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
                                    ConstrainedBox(
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
                                    SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () async {
                                        await _salvarAoFecharAba(i);
                                        if (provider.abas.isEmpty) Navigator.of(context).pop();
                                      },
                                      child: Icon(Icons.close, size: 13, color: ativa ? Colors.white.withValues(alpha: 0.8) : Theme.of(context).colorScheme.outline),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          GestureDetector(
                            onTap: () {
                              provider.adicionarAba();
                              provider.atualizarFlagsTab(modoEdicao: true);
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
              : SingleChildScrollView(
                  controller: _pageScrollCtrl,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBarraAcoes(provider, itens, tab),
                      const SizedBox(height: 8),
                      _buildSelecaoMateriais(provider, itens),
                      const SizedBox(height: 8),
                      itens.isEmpty ? _buildEmptyState() : _buildConteudo(provider, itens),
                      const SizedBox(height: 16),
                    ],
                  ),
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

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('${itens.length} mat. · $fornsSel forn.', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          OutlinedButton.icon(onPressed: _salvarOrcamento, icon: Icon(Icons.save_outlined, size: iconSize), label: Text('Salvar', style: btnStyle12), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success, side: const BorderSide(color: AppTheme.success), padding: btnPad)),
          OutlinedButton.icon(onPressed: _cancelarOrcamento, icon: Icon(Icons.delete_outline, size: iconSize), label: Text('Cancelar', style: btnStyle12), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: BorderSide(color: AppTheme.error), padding: btnPad)),
          OutlinedButton.icon(onPressed: itens.isEmpty ? null : _exportarPdf, icon: Icon(Icons.picture_as_pdf_outlined, size: iconSize), label: Text('PDF', style: btnStyle12), style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant, side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant), padding: btnPad)),
          OutlinedButton.icon(
            onPressed: _sincronizarStatusServidor,
            icon: Icon(Icons.refresh, size: iconSize),
            label: Text('Atualizar', style: btnStyle12),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              padding: btnPad,
            ),
          ),
          if (mostrarBotaoAprovar)
            OutlinedButton.icon(
              onPressed: itens.isEmpty ? null : () async { final sid = provider.tabAtual?.servidorId; if (sid == null) return; await _aprovarOrcamento(sid, provider.tabAtual?.titulo ?? ''); },
              icon: Icon(Icons.check_circle_outline, size: iconSize),
              label: Text('Aprovar', style: btnStyle12),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success, side: const BorderSide(color: AppTheme.success), padding: btnPad),
            )
          else if (!tab.modoGerarOC)
            Tooltip(
              message: tab.jaFinalizado ? 'Orçamento já aprovado/não aprovado. Reabra para reenviar.' : '',
              child: OutlinedButton.icon(
                onPressed: (itens.isEmpty || tab.jaFinalizado) ? null : _enviarParaAprovacao,
                icon: Icon(Icons.send_outlined, size: iconSize),
                label: Text('Enviar para aprovação', style: btnStyle12),
                style: OutlinedButton.styleFrom(foregroundColor: tab.jaFinalizado ? Theme.of(context).colorScheme.outline : AppTheme.warning, side: BorderSide(color: tab.jaFinalizado ? Theme.of(context).colorScheme.outlineVariant : AppTheme.warning), padding: btnPad),
              ),
            ),
          if (tab.modoGerarOC)
            Tooltip(
              message: podeGerar ? 'Gerar Ordens de Compra' : 'Selecione um fornecedor para cada material',
              child: FilledButton.icon(
                onPressed: podeGerar ? () => _gerarOrdemCompra(itens) : null,
                icon: const Icon(Icons.shopping_cart_checkout, size: iconSize),
                label: Text('Gerar OC (${_fornecedoresSelecionados(itens)})', style: btnStyle12),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: btnPad),
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
          Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(24)), child: Icon(Icons.inventory_2_outlined, size: 40, color: AppTheme.primary)),
          SizedBox(height: 20),
          Text('Nenhum material adicionado', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          SizedBox(height: 8),
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
                TextButton.icon(
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
                  ),
                ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _searchIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'ID',
                    prefixIcon: const Icon(Icons.tag, size: 13),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    suffixIcon:
                        _buscando && _searchIdCtrl.text.isNotEmpty
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
                            : null,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (_) => _agendarBuscaMateriais(),
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchNomeCtrl,
                  inputFormatters: [_NoCommaFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Nome',
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
                  onChanged: (_) => _agendarBuscaMateriais(),
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchIdentificadorCtrl,
                  inputFormatters: [_NoCommaFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Identif.',
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
                  onChanged: (_) => _agendarBuscaMateriais(),
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
                  onChanged: (_) => _agendarBuscaMateriais(),
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchEspCtrl,
                  inputFormatters: [_NoCommaFormatter()],
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
                  onChanged: (_) => _agendarBuscaMateriais(),
                ),
              ),

              const SizedBox(width: 4),

              IconButton.outlined(
                tooltip: 'Limpar filtros',
                icon: Icon(
                  Icons.filter_alt_off,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  _searchIdCtrl.clear();
                  _searchNomeCtrl.clear();
                  _searchIdentificadorCtrl.clear();
                  _searchMedidaCtrl.clear();
                  _searchEspCtrl.clear();

                  setState(() {
                    _resultadosBusca = [];
                    _mostrarResultados = false;
                  });
                },
                style: IconButton.styleFrom(
                  side: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
        if (_mostrarResultados && (_buscando || _resultadosBusca.isNotEmpty))
          Container(
            constraints: BoxConstraints(maxHeight: 200),
            margin: EdgeInsets.fromLTRB(10, 0, 10, 10),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 3))]),
            child: _buscando
                ? Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
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
                          final sub = [m.categoria, m.medida, m.espessura, m.identificador, m.unidade].where((s) => s != null && s.isNotEmpty).join(' · ');
                          return ListTile(
                            dense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            title: Row(children: [
                              Expanded(child: Text(m.nome, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),

                            ]),
                            subtitle: sub.isNotEmpty ? Text(sub, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)) : null,
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
                canScrollLeft && canScrollRight ? 'Deslize para ver fornecedores' : canScrollRight ? 'Deslize para ver fornecedores →' : '← Melhor Preço',
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
    final usarM2 = _ordemTotais == 'm2';

    Map<int, double> totaisForn = {};
    Map<int, int> cobertura = {};
    for (final fId in fornIdsRaw) {
      double soma = 0;
      int cnt = 0;
      for (final item in itens) {
        final pf = item.precos[fId];
        if (pf != null) {
          final preco = usarM2 ? (pf.precoM2 ?? pf.preco) : pf.preco;
          if (preco != null) {
            soma += preco * item.quantidade;
            cnt++;
          }
        }
      }
      totaisForn[fId] = soma;
      cobertura[fId] = cnt;
    }

    final todosFornIds = List<int>.from(fornIdsRaw)
      ..sort((a, b) {
        final ta = totaisForn[a] ?? 0;
        final tb = totaisForn[b] ?? 0;
        if (ta == 0 && tb == 0) return 0;
        if (ta == 0) return 1;
        if (tb == 0) return -1;
        return ta.compareTo(tb);
      });

    List<double?> melhorPorMaterial = itens.map((item) {
      double? menor;
      for (final fId in todosFornIds) {
        final pf = item.precos[fId];
        if (pf == null) continue;
        final preco = usarM2 ? (pf.precoM2 ?? pf.preco) : pf.preco;
        if (preco != null && (menor == null || preco < menor)) menor = preco;
      }
      return menor;
    }).toList();

    double totalMelhor = 0;
    int materiaisComMelhor = 0;
    for (int i = 0; i < itens.length; i++) {
      final m = melhorPorMaterial[i];
      if (m != null) {
        totalMelhor += m * itens[i].quantidade;
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
    double colQtd = 58;
    double colFornMin = 120;
    double colMelhor = 120;

    final double scrollableWidth = 12 + (colFornMin * todosFornIds.length) + todosFornIds.length.toDouble() + 1 + colMelhor;

    // ── Cabecalho fixo (Material + Qtd) ──────────────────────────────────────
    Widget cabecalhoFixo() => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(children: [
        SizedBox(width: colMaterial, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text('Material', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colQtd, child: Padding(padding: EdgeInsets.symmetric(horizontal: 3, vertical: 6), child: Text('Qtd', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center))),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
      ]),
    );

    // ── Cabecalho scrollável (fornecedores + melhor preço) ────────────────────
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
                  InkWell(
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


    // ── Totais fixo ───────────────────────────────────────────────────────────
    Widget totaisFixo() => Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5))),
      child: Row(children: [
        SizedBox(width: colMaterial, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text('Total por Fornecedor', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)))),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        SizedBox(width: colQtd),
        Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
      ]),
    );

    // ── Totais scrollável ─────────────────────────────────────────────────────
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

    // ── Row builder para coluna fixa ──────────────────────────────────────────
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
                GestureDetector(
                  onTap: () => provider.removerItem(item.itemId),
                  child: Padding(padding: const EdgeInsets.only(top: 1, right: 3), child: Icon(Icons.close, size: 13, color: Theme.of(context).colorScheme.outline)),
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
                      if ([item.materialMedida, item.materialEspessura, item.materialIdentificador].any((s) => s != null && s.isNotEmpty))
                        Text([item.materialMedida, item.materialEspessura, item.materialIdentificador].where((s) => s != null && s.isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), softWrap: true),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
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
                  ]),
                ),
              ]),
            ),
          ),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Container(
            width: colQtd,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            child: _QuantidadeField(key: ValueKey('qtd_${item.itemId}'), value: item.quantidade, onChanged: (q) => provider.atualizarItemParcial(item.itemId, quantidade: q)),
          ),
          Container(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        ]),
      );
    }

    // ── Row builder para coluna scrollável (fornecedores) ─────────────────────
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
            final preco = usarM2 ? (pf.precoM2 ?? pf.preco) : pf.preco;
            final total = preco != null ? preco * item.quantidade : null;
            final isMenorNaLinha = melhor != null && preco != null && preco == melhor;
            final isSelectedForn = item.fornecedorSelecionado == fId;
            return Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
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
                            Flexible(child: Text(usarM2 ? '${_brl(preco)}/m²' : _brl(preco), style: TextStyle(fontSize: 11, fontWeight: isMenorNaLinha ? FontWeight.w700 : FontWeight.w500, color: isMenorNaLinha ? AppTheme.success : Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                          ])
                        : Text('Sem preço', style: TextStyle(fontSize: 9, color: AppTheme.warning, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                    if (total != null) Text(_brl(total), style: TextStyle(fontSize: 10, color: isMenorNaLinha ? AppTheme.success.withValues(alpha: 0.8) : Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                    if (pf.observacao != null && pf.observacao!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(pf.observacao!, style: TextStyle(fontSize: 8, color: AppTheme.warning, fontStyle: FontStyle.italic), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    GestureDetector(onTap: () => _editarPreco(idx, fId), child: const Text('editar', style: TextStyle(fontSize: 9, color: AppTheme.primary, decoration: TextDecoration.underline), textAlign: TextAlign.center)),
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
                  Text(_brl(melhor * item.quantidade), style: TextStyle(fontSize: 9, color: AppTheme.primary.withValues(alpha: 0.7)), textAlign: TextAlign.center),
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
                FilledButton.icon(
                  onPressed: _adicionarFornecedoresBulk,
                  icon: const Icon(Icons.add_business, size: 12),
                  label: Text('Adicionar Fornecedores (${_materiaisParaBulk.length})', style: TextStyle(fontSize: 10)),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
                TextButton(
                  onPressed: () => setState(() => _materiaisParaBulk.clear()),
                  style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                  child: Text('Limpar', style: TextStyle(fontSize: 10)),
                ),
              ],
              if (_itensSelecionados.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: () => _copiarSelecionados(itens),
                  icon: const Icon(Icons.copy_all, size: 12),
                  label: Text('Copiar ${_itensSelecionados.length}', style: TextStyle(fontSize: 10)),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
                TextButton(
                  onPressed: () => setState(() => _itensSelecionados.clear()),
                  style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                  child: Text('Limpar', style: TextStyle(fontSize: 10)),
                ),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Orçar por', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  _OrdemTotaisBtn(label: 'Unit.', icon: Icons.straighten, ativo: _ordemTotais == 'unitario', onTap: () => setState(() => _ordemTotais = 'unitario')),
                  const SizedBox(width: 3),
                  _OrdemTotaisBtn(label: 'M²', icon: Icons.grid_4x4, ativo: _ordemTotais == 'm2', onTap: () => setState(() => _ordemTotais = 'm2')),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () => _aplicarSugestaoOtimizada(itens),
                icon: const Icon(Icons.auto_awesome, size: 12),
                label: const Text('Sugestão', style: TextStyle(fontSize: 10)),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary, side: const BorderSide(color: AppTheme.primary), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
              if (provider.tabAtual?.fornecedoresOcultos.isNotEmpty ?? false)
                OutlinedButton.icon(
                  onPressed: () => _gerenciarFornecedoresOcultos(itens),
                  icon: const Icon(Icons.visibility_off_outlined, size: 12),
                  label: Text('Ocultos (${provider.tabAtual!.fornecedoresOcultos.length})', style: const TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.outline, side: BorderSide(color: Theme.of(context).colorScheme.outline), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
            ],
          ),
        ),
        _buildScrollHint(),
        // ── Tabela: scroll horizontal único, linhas com altura sincronizada ────
        ScrollConfiguration(
          behavior: _HorizontalScrollBehavior(),
          child: Scrollbar(
            controller: _tabelaHScrollCtrl,
            child: SingleChildScrollView(
              controller: _tabelaHScrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: colMaterial + 1 + colQtd + 1 + scrollableWidth,
                child: Column(children: [
                  // Cabeçalho completo numa única Row
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      cabecalhoFixo(),
                      cabecalhoScroll(),
                    ]),
                  ),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                  // Corpo: lista vertical com cada linha unindo fixo + scrollável
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
                  // Linha de totais completa numa única Row
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
  const _QuantidadeField({super.key, required this.value, required this.onChanged});

  @override
  State<_QuantidadeField> createState() => _QuantidadeFieldState();
}

class _QuantidadeFieldState extends State<_QuantidadeField> {
  late TextEditingController _ctrl;
  bool _editando = false;

  String _formatValue(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

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
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)), isDense: true, filled: true, fillColor: Theme.of(context).colorScheme.surface),
      style: const TextStyle(fontSize: 11),
      onTap: () => setState(() => _editando = true),
      onChanged: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        if (parsed != null && parsed > 0) widget.onChanged(parsed);
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
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

  const _DialogVincularFornecedores({required this.fornecedores, required this.idsJaVinculados, required this.materialNome});

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

  @override
  Widget build(BuildContext context) {
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.primary), onPressed: _selecionados.isEmpty ? null : () => Navigator.pop(context, _selecionados.toList()), child: const Text('Adicionar')),
      ],
    );
  }
}

class _DialogEditarMaterial extends StatefulWidget {
  final String fornecedorNome;
  final String materialNome;
  final double? precoAtual;
  final String? observacaoAtual;

  const _DialogEditarMaterial({
    required this.fornecedorNome,
    required this.materialNome,
    this.precoAtual,
    this.observacaoAtual,
  });

  @override
  State<_DialogEditarMaterial> createState() => _DialogEditarMaterialState();
}

class _DialogEditarMaterialState extends State<_DialogEditarMaterial> {
  late final TextEditingController _precoCtrl;
  late final TextEditingController _observacaoCtrl;

  @override
  void initState() {
    super.initState();
    _precoCtrl = TextEditingController(
      text: widget.precoAtual != null ? widget.precoAtual!.toStringAsFixed(2) : '',
    );
    _observacaoCtrl = TextEditingController(text: widget.observacaoAtual ?? '');
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
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
            TextField(
              controller: _precoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              decoration: const InputDecoration(labelText: 'Preço (R\$)', prefixText: 'R\$ ', isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacaoCtrl,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Disponibilidade / Observação',
                hintText: 'Ex: Em falta, prazo 5 dias, sob consulta…',
                isDense: true,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () {
            final preco = double.tryParse(_precoCtrl.text.replaceAll(',', '.'));
            final obs = _observacaoCtrl.text.trim().isEmpty ? null : _observacaoCtrl.text.trim();
            Navigator.pop(context, {'preco': preco, 'observacao': obs});
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
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

class _OrdemTotaisBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool ativo;
  final VoidCallback onTap;

  const _OrdemTotaisBtn({required this.label, required this.icon, required this.ativo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: ativo ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: ativo ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant),
            SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ativo ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
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