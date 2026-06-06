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
import '../repositories/fornecedor_repository.dart';
import '../repositories/orcamento_repository.dart';

import '../theme/app_theme.dart';

// ─── Scroll Behavior ─────────────

class _HorizontalScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
  };
}

// ─── Scroll Metrics Notifier ──────────────────────────────────────────────────

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

// ─── Formatters ───────────────────────────────

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

// ─── Helpers ──────────────────────────────────

String _brl(double? v) {
  if (v == null || v == 0) return '—';
  return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

// ─── Page ─────────────────────────────────────

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
  final _tabelaHScrollCtrl = ScrollController();
  final _tabelaVScrollCtrl = ScrollController();
  Timer? _debounceMatBusca;
  late final _ScrollMetricsNotifier _tabelaHScrollHintNotifier;

  List<MaterialModel> _resultadosBusca = [];
  bool _buscando = false;
  bool _mostrarResultados = false;
  bool _salvando = false;
  String _ordemTotais = 'unitario';

  @override
  void initState() {
    super.initState();
    _tabelaHScrollHintNotifier = _ScrollMetricsNotifier();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FornecedorProvider>().carregar();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _tabelaHScrollCtrl.hasClients) {
          _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
        }
      });
    });
    _tabelaHScrollCtrl.addListener(() {
      _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
    });
  }

  @override
  void dispose() {
    _debounceMatBusca?.cancel();
    _searchIdCtrl.dispose();
    _searchNomeCtrl.dispose();
    _searchIdentificadorCtrl.dispose();
    _searchMedidaCtrl.dispose();
    _searchEspCtrl.dispose();
    _tabelaHScrollCtrl.dispose();
    _tabelaVScrollCtrl.dispose();
    _tabelaHScrollHintNotifier.dispose();
    super.dispose();
  }

  void _agendarBuscaMateriais() {
    _debounceMatBusca?.cancel();
    _debounceMatBusca = Timer(
      const Duration(milliseconds: 400),
      _executarBuscaMateriais,
    );
  }

  Future<void> _executarBuscaMateriais() async {
    final id = _searchIdCtrl.text.trim();
    final nome = _searchNomeCtrl.text.trim();
    final identificador = _searchIdentificadorCtrl.text.trim();
    final medida = _searchMedidaCtrl.text.trim();
    final esp = _searchEspCtrl.text.trim();

    final algumFiltro = id.isNotEmpty || nome.isNotEmpty ||
        identificador.isNotEmpty || medida.isNotEmpty || esp.isNotEmpty;

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
      final idsJaAdicionados = provider.tabAtual?.itens
              .where((i) => !i.materialEspecifico)
              .map((i) => i.materialId)
              .toSet() ??
          {};
      setState(() {
        _resultadosBusca = todos
            .where((m) => m.especifico || !idsJaAdicionados.contains(m.id))
            .toList();
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
      materialEspecifico: material.especifico,
      precos: precos,
    ));
    _searchIdCtrl.clear();
    _searchNomeCtrl.clear();
    _searchIdentificadorCtrl.clear();
    _searchMedidaCtrl.clear();
    _searchEspCtrl.clear();
    setState(() { _resultadosBusca = []; _mostrarResultados = false; });
  }

  Future<void> _vincularFornecedores(int itemIndex) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || itemIndex >= tab.itens.length) return;
    final item = tab.itens[itemIndex];
    final fornecedores = context.read<FornecedorProvider>().fornecedores;
    final idsJaVinculados = item.precos.keys.toSet();

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

    final result = await showDialog<Map<String, double?>>(
      context: context,
      builder: (ctx) => _DialogEditarPreco(
        fornecedorNome: pf.fornecedorNome,
        materialNome: item.materialNome,
        precoAtual: pf.preco,
        precoM2Atual: pf.precoM2,
      ),
    );
    if (result == null) return;

    final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
    novosPrecos[fornecedorId] = PrecoFornecedorData(
      fornecedorNome: pf.fornecedorNome,
      preco: result['preco'],
      precoM2: result['precoM2'],
    );
    provider.atualizarItemParcial(item.itemId, precos: novosPrecos);

    setState(() => _salvando = true);
    try {
      await FornecedorRepository().atualizarPreco(fornecedorId, item.materialId, {
        if (result['preco'] != null) 'preco': result['preco'],
        if (result['precoM2'] != null) 'precoMetroQuadrado': result['precoM2'],
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _salvarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um material para salvar.')),
      );
      return;
    }

    final tituloCtrl = TextEditingController(text: tab.titulo);
    final novoTitulo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        bool vazio = false;
        return AlertDialog(
          title: Text(tab.servidorId != null ? 'Atualizar Orçamento' : 'Salvar Orçamento',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nome do orçamento:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
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
      for (final item in tabAtualizado.itens) {
        if (item.precos.isEmpty) {
          await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false, 'descricaoItem': item.descricao});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'descricaoItem': item.descricao});
          }
        }
      }
      if (!mounted) return;
      provider.fecharAbaAposOperacao();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento #$orcId salvo com sucesso!'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppTheme.error));
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
          title: const Text('Enviar para Aprovação', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nome do orçamento:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),
              TextField(
                controller: tituloCtrl, autofocus: true, inputFormatters: [_NoCommaFormatter()],
                decoration: InputDecoration(hintText: 'Ex: Orçamento Obra Abril', isDense: true, errorText: null),
                onChanged: (_) { if (vazio && tituloCtrl.text.trim().isNotEmpty) { setSt(() => vazio = false); } },
              ),
              const SizedBox(height: 14),
              const Text('Após o envio, aguarde Admin/Gerente aprovar antes de gerar a Ordem de Compra.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
      for (final item in tab.itens) {
        if (item.precos.isEmpty) {
          await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false, 'descricaoItem': item.descricao});
        } else {
          for (final entry in item.precos.entries) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'descricaoItem': item.descricao});
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _aprovarOrcamento(int id, String titulo) async {
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
    // Captura provider e tab antes dos awaits para evitar uso de BuildContext
    // após gaps assíncronos (use_build_context_synchronously).
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    try {
      // Sincroniza os itens (com fornecedor selecionado atualizado) antes de
      // aprovar, garantindo que qualquer seleção feita no editor chegue ao banco.
      if (tab != null) {
        final repo = OrcamentoRepository();
        await repo.limparItens(id);
        for (final item in tab.itens) {
          if (item.precos.isEmpty) {
            await repo.adicionarItem(id, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false, 'descricaoItem': item.descricao});
          } else {
            for (final entry in item.precos.entries) {
              await repo.adicionarItem(id, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'descricaoItem': item.descricao});
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao aprovar: $e'), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e'), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
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
      final pdfBytes = await OrcamentoRepository().gerarPdf({'titulo': tab.titulo, 'itens': tab.itens.map((i) => i.toJson()).toList()});
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
            Text(
              'Serão geradas ${porFornecedor.length} ${porFornecedor.length == 1 ? "OC" : "OCs"}, uma por fornecedor:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(fornecedorNomes, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar e Gerar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _salvando = true);
    final repo = OrcamentoRepository();

    int orcId;
    try {
      if (tab.servidorId != null) {
        // Orçamento já existe no servidor — sempre sincroniza os itens com o
        // estado atual do provider (inclui fornecedorSelecionado atualizado).
        orcId = tab.servidorId!;
        await repo.limparItens(orcId);
        for (final item in tab.itens) {
          if (item.precos.isEmpty) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false, 'descricaoItem': item.descricao});
          } else {
            for (final entry in item.precos.entries) {
              await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'descricaoItem': item.descricao});
            }
          }
        }
      } else {
        // Orçamento ainda não existe no servidor — cria e insere os itens.
        final criado = await repo.criar(tab.titulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': tab.titulo});
        for (final item in tab.itens) {
          if (item.precos.isEmpty) {
            await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': null, 'quantidade': item.quantidade, 'precoUnitario': null, 'precoM2': null, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': false, 'descricaoItem': item.descricao});
          } else {
            for (final entry in item.precos.entries) {
              await repo.adicionarItem(orcId, {'materialId': item.materialId, 'fornecedorId': entry.key, 'quantidade': item.quantidade, 'precoUnitario': entry.value.preco, 'precoM2': entry.value.precoM2, 'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado, 'selecionado': item.fornecedorSelecionado == entry.key, 'descricaoItem': item.descricao});
            }
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao sincronizar itens: $e'), backgroundColor: AppTheme.error));
      if (mounted) setState(() => _salvando = false);
      return;
    }

   try {
      final result = await repo.gerarOrdemCompra(orcId);
      if (!mounted) return;

      if (result['pronto'] == true) {
        provider.fecharAbaAposOperacao();
        if (!mounted) return;

        final ocsCriadas = result['ocsCriadas'] as List?;
        final qtdOCs = ocsCriadas?.length ?? porFornecedor.length;
        final primeiraOcId = ocsCriadas?.isNotEmpty == true
            ? (ocsCriadas!.first['id'] as int?)
            : null;

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '$qtdOCs ${qtdOCs == 1 ? "OC gerada" : "OCs geradas"} com sucesso!',
          ),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 3),
        ));

        // Navega para a página de Ordens de Compra e abre a primeira OC criada
        context.go('/ordem-compra', extra: primeiraOcId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao gerar OC: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  bool _podeGerarOC(List<ItemOrcamentoData> itens) {
    if (itens.isEmpty) return false;
    if (!itens.every((i) => i.fornecedorSelecionado != null)) return false;
    for (final item in itens) {
      if (item.materialEspecifico && (item.descricao == null || item.descricao!.trim().isEmpty)) return false;
    }
    return true;
  }

  int _fornecedoresSelecionados(List<ItemOrcamentoData> itens) =>
      itens.where((i) => i.fornecedorSelecionado != null).map((i) => i.fornecedorSelecionado!).toSet().length;

  Set<int> _todosFornecedoresIds(List<ItemOrcamentoData> itens) {
    final ids = <int>{};
    for (final item in itens) { ids.addAll(item.precos.keys); }
    return ids;
  }

  void _aplicarSugestaoOtimizada(List<ItemOrcamentoData> itens) {
    final provider = context.read<OrcamentoProvider>();
    final ordenarPorM2 = _ordemTotais == 'm2';
    for (final item in itens) {
      if (item.precos.isEmpty) continue;
      double? menorValor; int? fornEscolhido; ModoOrcamento? modoEscolhido;
      for (final entry in item.precos.entries) {
        if (ordenarPorM2) {
          if (entry.value.precoM2 != null && (menorValor == null || entry.value.precoM2! < menorValor)) { menorValor = entry.value.precoM2; fornEscolhido = entry.key; modoEscolhido = ModoOrcamento.metroQuadrado; }
        } else {
          if (entry.value.preco != null && (menorValor == null || entry.value.preco! < menorValor)) { menorValor = entry.value.preco; fornEscolhido = entry.key; modoEscolhido = ModoOrcamento.unitario; }
        }
      }
      if (fornEscolhido != null && modoEscolhido != null) provider.atualizarItemParcial(item.itemId, fornecedorSelecionado: fornEscolhido, modoOrcamento: modoEscolhido);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sugestão de orçamento otimizado aplicada!'), backgroundColor: AppTheme.success));
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
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.textSecondary),
              tooltip: 'Voltar',
            ),
            title: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...abas.asMap().entries.map((entry) {
                          final i = entry.key;
                          final aba = entry.value;
                          final ativa = i == abaAtiva;
                          final temConteudo = aba.itens.isNotEmpty || aba.servidorId != null;
                          return GestureDetector(
                            onTap: () => provider.selecionarAba(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: ativa ? AppTheme.primary : AppTheme.background,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: ativa ? AppTheme.primary : AppTheme.divider),
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
                                    constraints: const BoxConstraints(maxWidth: 140),
                                    child: Text(
                                      aba.titulo,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: ativa ? FontWeight.w700 : FontWeight.w500,
                                        color: ativa ? Colors.white : AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () {
                                      provider.fecharAba(i);
                                      if (provider.abas.isEmpty) Navigator.of(context).pop();
                                    },
                                    child: Icon(Icons.close, size: 13, color: ativa ? Colors.white.withValues(alpha: 0.8) : AppTheme.textHint),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        GestureDetector(
                          onTap: () { provider.adicionarAba(); provider.atualizarFlagsTab(modoEdicao: true); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.divider)),
                            child: const Icon(Icons.add, size: 16, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_salvando) ...[
                  const SizedBox(width: 12),
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                ],
              ],
            ),
            bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppTheme.divider)),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: tab == null
                ? const Center(child: Text('Nenhuma aba aberta', style: TextStyle(color: AppTheme.textHint)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBarraAcoes(provider, itens, tab),
                      const SizedBox(height: 12),
                      _buildSelecaoMateriais(provider, itens),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 1,
                        child: itens.isEmpty ? _buildEmptyState() : _buildConteudo(provider, itens),
                      ),
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
    final matEspSemDesc = itens.where((i) => i.materialEspecifico && (i.descricao == null || i.descricao!.trim().isEmpty)).length;
    final mostrarBotaoAprovar = tab.aguardandoAprovacao;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.divider)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(children: [
              const Icon(Icons.shopping_cart_outlined, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Flexible(child: Text(
                '${itens.length} ${itens.length == 1 ? 'material' : 'materiais'} — $fornsSel ${fornsSel == 1 ? 'fornecedor selecionado' : 'fornecedores selecionados'}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                overflow: TextOverflow.ellipsis,
              )),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: ClipRect(
            child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(onPressed: _salvarOrcamento, icon: const Icon(Icons.save_outlined, size: 15), label: const Text('Salvar', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success, side: const BorderSide(color: AppTheme.success), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10))),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _cancelarOrcamento, icon: const Icon(Icons.delete_outline, size: 15), label: const Text('Cancelar', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10))),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: itens.isEmpty ? null : _exportarPdf, icon: const Icon(Icons.picture_as_pdf_outlined, size: 15), label: const Text('Exportar PDF', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textSecondary, side: const BorderSide(color: AppTheme.divider), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10))),
              const SizedBox(width: 8),
              if (mostrarBotaoAprovar)
                OutlinedButton.icon(
                  onPressed: itens.isEmpty ? null : () async { final sid = provider.tabAtual?.servidorId; if (sid == null) return; await _aprovarOrcamento(sid, provider.tabAtual?.titulo ?? ''); },
                  icon: const Icon(Icons.check_circle_outline, size: 15),
                  label: const Text('Aprovar', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success, side: const BorderSide(color: AppTheme.success), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                )
              else if (!tab.modoGerarOC)
                Tooltip(
                  message: tab.jaFinalizado ? 'Orçamento já aprovado/não aprovado. Reabra para reenviar.' : '',
                  child: OutlinedButton.icon(
                    onPressed: (itens.isEmpty || tab.jaFinalizado) ? null : _enviarParaAprovacao,
                    icon: const Icon(Icons.send_outlined, size: 15),
                    label: const Text('Enviar para Aprovação', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(foregroundColor: tab.jaFinalizado ? AppTheme.textHint : AppTheme.warning, side: BorderSide(color: tab.jaFinalizado ? AppTheme.divider : AppTheme.warning), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                  ),
                ),
              const SizedBox(width: 8),
              if (tab.modoGerarOC)
                Tooltip(
                  message: podeGerar ? 'Gerar Ordens de Compra (1 por fornecedor)' : matEspSemDesc > 0 ? 'Preencha a descrição dos materiais específicos' : 'Selecione um fornecedor para cada material',
                  child: FilledButton.icon(
                    onPressed: podeGerar ? () => _gerarOrdemCompra(itens) : null,
                    icon: const Icon(Icons.shopping_cart_checkout, size: 16),
                    label: Text('Gerar OC (${_fornecedoresSelecionados(itens)} forn.)', style: const TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  ),
                ),
            ]),
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
          Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.inventory_2_outlined, size: 40, color: AppTheme.primary)),
          const SizedBox(height: 20),
          Text('Nenhum material adicionado', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Busque um material acima para começar o orçamento.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSelecaoMateriais(OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            const Icon(Icons.inventory_2_outlined, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            const Text('Selecionar Materiais', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            if (itens.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(20)), child: Text('${itens.length} selecionados', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
            ],
            const Spacer(),
            if (itens.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  for (final item in List.from(itens)) {
                    provider.removerItem(item.itemId);
                  }
                },
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Limpar', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: _searchIdCtrl,
                decoration: InputDecoration(labelText: 'ID', prefixIcon: const Icon(Icons.tag, size: 14, color: AppTheme.textHint), isDense: true,
                  suffixIcon: _buscando && _searchIdCtrl.text.isNotEmpty ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))) : null),
                keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _agendarBuscaMateriais(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchNomeCtrl, inputFormatters: [_NoCommaFormatter()],
                decoration: InputDecoration(labelText: 'Nome do material', isDense: true,
                  prefixIcon: _buscando && _searchNomeCtrl.text.isNotEmpty ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))) : const Icon(Icons.search, size: 16, color: AppTheme.textHint)),
                onChanged: (_) => _agendarBuscaMateriais(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(controller: _searchIdentificadorCtrl, inputFormatters: [_NoCommaFormatter()], decoration: const InputDecoration(labelText: 'Identificador', prefixIcon: Icon(Icons.qr_code_outlined, size: 14, color: AppTheme.textHint), isDense: true), onChanged: (_) => _agendarBuscaMateriais()),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(controller: _searchMedidaCtrl, inputFormatters: [_NoCommaFormatter()], decoration: const InputDecoration(labelText: 'Medida', prefixIcon: Icon(Icons.straighten_outlined, size: 14, color: AppTheme.textHint), isDense: true), onChanged: (_) => _agendarBuscaMateriais()),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(controller: _searchEspCtrl, inputFormatters: [_NoCommaFormatter()], decoration: const InputDecoration(labelText: 'Espessura', prefixIcon: Icon(Icons.layers_outlined, size: 14, color: AppTheme.textHint), isDense: true), onChanged: (_) => _agendarBuscaMateriais()),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Limpar filtros', icon: const Icon(Icons.filter_alt_off, size: 17, color: AppTheme.textHint), visualDensity: VisualDensity.compact,
              onPressed: () { _searchIdCtrl.clear(); _searchNomeCtrl.clear(); _searchIdentificadorCtrl.clear(); _searchMedidaCtrl.clear(); _searchEspCtrl.clear(); setState(() { _resultadosBusca = []; _mostrarResultados = false; }); },
            ),
          ]),
        ),
        if (_mostrarResultados && (_buscando || _resultadosBusca.isNotEmpty))
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.divider), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 4))]),
            child: _buscando
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
                : _resultadosBusca.isEmpty
                    ? const Padding(padding: EdgeInsets.all(16), child: Row(children: [Icon(Icons.search_off, size: 16, color: AppTheme.textHint), SizedBox(width: 8), Text('Nenhum material encontrado.', style: TextStyle(color: AppTheme.textHint, fontSize: 13))]))
                    : Material(
                        color: AppTheme.surface,
                        child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _resultadosBusca.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
                        itemBuilder: (ctx, i) {
                          final m = _resultadosBusca[i];
                          final sub = [m.categoria, m.medida, m.espessura, m.identificador, m.unidade].where((s) => s != null && s.isNotEmpty).join(' · ');
                          return ListTile(
                            dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            title: Row(children: [
                              Expanded(child: Text(m.nome, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
                              if (m.especifico) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)), child: const Text('Específico', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.primary))),
                            ]),
                            subtitle: sub.isNotEmpty ? Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)) : null,
                            trailing: _StatusChip(status: m.status),
                            onTap: () => _adicionarMaterial(m),
                          );
                        },
                      ),
          ),
        ),
        if (itens.isNotEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            constraints: const BoxConstraints(maxHeight: 80),
            child: SingleChildScrollView(
              child: Wrap(spacing: 8, runSpacing: 6, children: itens.asMap().entries.map((e) {
                final item = e.value;
                return _MaterialChip(nome: item.materialNome, selecionado: item.fornecedorSelecionado != null, especifico: item.materialEspecifico, descricao: item.descricao, onRemover: () => provider.removerItem(item.itemId));
              }).toList()),
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
          height: showHint ? 28 : 0,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            border: Border(
              bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.15)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (canScrollLeft) ...[
                Icon(Icons.chevron_left, size: 16, color: AppTheme.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 2),
              ],
              Icon(Icons.drag_indicator, size: 14, color: AppTheme.primary.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(
                canScrollLeft && canScrollRight
                    ? 'Deslize para ver fornecedores e Melhor Preço'
                    : canScrollRight
                        ? 'Deslize para ver fornecedores e Melhor Preço →'
                        : '← Melhor Preço e demais colunas',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primary.withValues(alpha: 0.75),
                ),
              ),
              if (canScrollRight) ...[
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 16, color: AppTheme.primary.withValues(alpha: 0.7)),
              ],
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
      if (mounted && _tabelaHScrollCtrl.hasClients) {
        _tabelaHScrollHintNotifier.update(_tabelaHScrollCtrl);
      }
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
      nomeFornComTodos = itens.expand((i) => i.precos.entries)
          .where((e) => e.key == fornComTodos)
          .map((e) => e.value.fornecedorNome)
          .firstOrNull;
    }

    const double colMaterial = 180;
    const double colQtd = 60;
    const double colFornMin = 120;
    const double colMelhor = 120;

    // Largura total da tabela inteira (tudo dentro do scroll horizontal)
    final double totalWidth = colMaterial + 1 + colQtd + 1 + 12
        + (colFornMin * todosFornIds.length)
        + todosFornIds.length.toDouble()
        + 1 + colMelhor;

    // ── Helpers de célula ──────────────────────────────────────────────────────

    Widget cabecalho() => Container(
      color: AppTheme.surfaceVariant,
      child: Row(children: [
        SizedBox(
          width: colMaterial,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text('Material',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          ),
        ),
        Container(width: 1, color: AppTheme.divider),
        SizedBox(
          width: colQtd,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('Qtd',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
          ),
        ),
        Container(width: 1, color: AppTheme.divider),
        const SizedBox(width: 12),
        ...todosFornIds.map((fId) {
          final nome = itens
              .expand((i) => i.precos.entries)
              .where((e) => e.key == fId)
              .map((e) => e.value.fornecedorNome)
              .firstOrNull ?? 'Fornecedor';
          final isLast = fId == todosFornIds.last;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: colFornMin,
              child: Center(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(nome,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                  textAlign: TextAlign.center, softWrap: true),
              )),
            ),
            if (!isLast) Container(width: 1, height: 20, color: AppTheme.divider),
          ]);
        }),
        Container(width: 1, height: 20, color: AppTheme.divider),
        SizedBox(
          width: colMelhor,
          child: const Center(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('Melhor Preço',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
              textAlign: TextAlign.center),
          )),
        ),
      ]),
    );

    Widget totais() => Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 1.5)),
      ),
      child: Row(children: [
        SizedBox(
          width: colMaterial,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text('Total por Fornecedor',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          ),
        ),
        Container(width: 1, color: AppTheme.divider),
        SizedBox(width: colQtd),
        Container(width: 1, color: AppTheme.divider),
        const SizedBox(width: 12),
        ...todosFornIds.map((fId) {
          final total = totaisForn[fId] ?? 0;
          final cob = cobertura[fId] ?? 0;
          final isMenorTotal = todosFornIds.isNotEmpty && total > 0 &&
              total == todosFornIds.map((id) => totaisForn[id] ?? double.infinity).reduce((a, b) => a < b ? a : b);
          final semPrecoCount = itens.length - cob;
          final isLast = fId == todosFornIds.last;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: colFornMin, child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(total > 0 ? _brl(total) : '—',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isMenorTotal ? AppTheme.success : AppTheme.textPrimary),
                  textAlign: TextAlign.center),
                Text('$cob/${itens.length} mat.',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isMenorTotal ? AppTheme.success : AppTheme.textSecondary),
                  textAlign: TextAlign.center),
                if (semPrecoCount > 0)
                  Text('$semPrecoCount sem preço', style: const TextStyle(fontSize: 9, color: AppTheme.warning, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
              ]),
            )),
            if (!isLast) Container(width: 1, height: 36, color: AppTheme.divider),
          ]);
        }),
        Container(width: 1, height: 36, color: AppTheme.divider),
        SizedBox(width: colMelhor, child: Center(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(materiaisComMelhor > 0 ? _brl(totalMelhor) : '—',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center),
            Text('$materiaisComMelhor/${itens.length} mat.',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center),
          ]),
        ))),
      ]),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Barra de título (não rola) ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.divider))),
          child: Row(children: [
            const Text('Comparativo de Preços', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const Spacer(),
            const Text('Orçar por', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            const SizedBox(width: 6),
            _OrdemTotaisBtn(label: 'Unit.', icon: Icons.straighten, ativo: _ordemTotais == 'unitario', onTap: () => setState(() => _ordemTotais = 'unitario')),
            const SizedBox(width: 4),
            _OrdemTotaisBtn(label: 'M²', icon: Icons.grid_4x4, ativo: _ordemTotais == 'm2', onTap: () => setState(() => _ordemTotais = 'm2')),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _aplicarSugestaoOtimizada(itens),
              icon: const Icon(Icons.auto_awesome, size: 13),
              label: const Text('Sugestão Otimizada', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary, side: const BorderSide(color: AppTheme.primary), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            ),
          ]),
        ),

        _buildScrollHint(),

        // ── Área principal: UM único scroll horizontal ─────────────────────────
        // Cabeçalho (pinned) + linhas (scroll vertical) + totais (pinned)
        // tudo compartilha o mesmo SingleChildScrollView horizontal
        Expanded(
          child: ScrollConfiguration(
            behavior: _HorizontalScrollBehavior(),
            child: Scrollbar(
              controller: _tabelaHScrollCtrl,
              child: SingleChildScrollView(
                controller: _tabelaHScrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: totalWidth,
                  child: Column(
                    children: [
                      // Cabeçalho — não rola verticalmente
                      cabecalho(),
                      const Divider(height: 1, color: AppTheme.divider),

                      // Linhas — rolam verticalmente
                      Expanded(
                        child: ListView.separated(
                          controller: _tabelaVScrollCtrl,
                          itemCount: itens.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
                          itemBuilder: (ctx, idx) {
                            final item = itens[idx];
                            final isSelected = item.fornecedorSelecionado != null;
                            final melhor = melhorPorMaterial[idx];
                            const double iconX = 18;
                            const double padH = 6;
                            final double textWidth = colMaterial - iconX - padH * 2;

                            return Container(
                              color: isSelected
                                  ? Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.05), AppTheme.surface)
                                  : AppTheme.surface,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Coluna: Material
                                  SizedBox(
                                    width: colMaterial,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: padH, vertical: 8),
                                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        GestureDetector(
                                          onTap: () => provider.removerItem(item.itemId),
                                          child: const Padding(
                                            padding: EdgeInsets.only(top: 1, right: 3),
                                            child: Icon(Icons.close, size: 14, color: AppTheme.textHint),
                                          ),
                                        ),
                                        SizedBox(
                                          width: textWidth,
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Expanded(child: Text(item.materialNome,
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                                softWrap: true)),
                                              if (item.materialEspecifico)
                                                Container(
                                                  margin: const EdgeInsets.only(left: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
                                                  child: const Text('ESP', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                                                ),
                                            ]),
                                            if ([item.materialCategoria, item.materialMedida, item.materialEspessura, item.materialIdentificador].any((s) => s != null && s.isNotEmpty))
                                              Text(
                                                [item.materialCategoria, item.materialMedida, item.materialEspessura, item.materialIdentificador].where((s) => s != null && s.isNotEmpty).join(' · '),
                                                style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary),
                                                softWrap: true,
                                              ),
                                            if (item.materialEspecifico)
                                              TextField(
                                                controller: TextEditingController(text: item.descricao),
                                                decoration: InputDecoration(hintText: 'Descrição *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)), contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                                                style: const TextStyle(fontSize: 10),
                                                onChanged: (d) => provider.atualizarItemParcial(item.itemId, descricao: d),
                                              ),
                                            const SizedBox(height: 4),
                                            GestureDetector(
                                              onTap: () => _vincularFornecedores(idx),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary.withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                                                ),
                                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                                  Icon(Icons.person_add_outlined, size: 13, color: AppTheme.primary),
                                                  SizedBox(width: 4),
                                                  Text('Adicionar fornecedor', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                                                ]),
                                              ),
                                            ),
                                          ]),
                                        ),
                                      ]),
                                    ),
                                  ),
                                  Container(width: 1, color: AppTheme.divider),
                                  // Coluna: Qtd
                                  Container(
                                    width: colQtd,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    child: _QuantidadeField(
                                      value: item.quantidade,
                                      onChanged: (q) => provider.atualizarItemParcial(item.itemId, quantidade: q),
                                    ),
                                  ),
                                  Container(width: 1, color: AppTheme.divider),
                                  const SizedBox(width: 12),
                                  // Colunas: fornecedores
                                  ...todosFornIds.map((fId) {
                                    final pf = item.precos[fId];
                                    final isLast = fId == todosFornIds.last;
                                    if (pf == null) {
                                      return Row(mainAxisSize: MainAxisSize.min, children: [
                                        SizedBox(width: colFornMin, child: Center(child: Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(color: AppTheme.surfaceVariant, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.divider)),
                                          child: const Text('Não tem', style: TextStyle(fontSize: 10, color: AppTheme.textHint, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                                        ))),
                                        if (!isLast) Container(width: 1, color: AppTheme.divider),
                                      ]);
                                    }
                                    final preco = usarM2 ? (pf.precoM2 ?? pf.preco) : pf.preco;
                                    final total = preco != null ? preco * item.quantidade : null;
                                    final isMenorNaLinha = melhor != null && preco != null && preco == melhor;
                                    final isSelectedForn = item.fornecedorSelecionado == fId;
                                    return Row(mainAxisSize: MainAxisSize.min, children: [
                                      GestureDetector(
                                        onTap: () {
                                          if (isSelectedForn) {
                                            provider.atualizarItemParcial(item.itemId, clearFornecedor: true);
                                          } else {
                                            provider.atualizarItemParcial(item.itemId, fornecedorSelecionado: fId);
                                          }
                                        },
                                        child: SizedBox(width: colFornMin, child: Center(child: Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: isSelectedForn ? AppTheme.primary.withValues(alpha: 0.1) : isMenorNaLinha ? AppTheme.success.withValues(alpha: 0.07) : null,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isSelectedForn ? AppTheme.primary.withValues(alpha: 0.4) : isMenorNaLinha ? AppTheme.success.withValues(alpha: 0.3) : Colors.transparent),
                                          ),
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                            preco != null
                                                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                    if (isMenorNaLinha) const Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.arrow_downward, size: 10, color: AppTheme.success)),
                                                    Flexible(child: Text(
                                                      usarM2 ? '${_brl(preco)}/m²' : _brl(preco),
                                                      style: TextStyle(fontSize: 13, fontWeight: isMenorNaLinha ? FontWeight.w700 : FontWeight.w500, color: isMenorNaLinha ? AppTheme.success : AppTheme.textPrimary),
                                                      overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                                                  ])
                                                : const Text('Sem preço', style: TextStyle(fontSize: 10, color: AppTheme.textHint, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                                            if (total != null)
                                              Text(_brl(total), style: TextStyle(fontSize: 11, color: isMenorNaLinha ? AppTheme.success.withValues(alpha: 0.8) : AppTheme.textSecondary), textAlign: TextAlign.center),
                                            GestureDetector(
                                              onTap: () => _editarPreco(idx, fId),
                                              child: const Text('editar', style: TextStyle(fontSize: 10, color: AppTheme.primary, decoration: TextDecoration.underline), textAlign: TextAlign.center),
                                            ),
                                            if (isSelectedForn)
                                              const Row(mainAxisSize: MainAxisSize.min, children: [
                                                Icon(Icons.check_circle, size: 10, color: AppTheme.primary),
                                                SizedBox(width: 2),
                                                Text('Escolhido', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                                              ]),
                                          ]),
                                        ))),
                                      ),
                                      if (!isLast) Container(width: 1, color: AppTheme.divider),
                                    ]);
                                  }),
                                  // Coluna: Melhor Preço
                                  Container(width: 1, color: AppTheme.divider),
                                  SizedBox(width: colMelhor, child: Center(child: melhor != null
                                    ? Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                          Text(_brl(melhor), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary), textAlign: TextAlign.center),
                                          Text(_brl(melhor * item.quantidade), style: TextStyle(fontSize: 10, color: AppTheme.primary.withValues(alpha: 0.7)), textAlign: TextAlign.center),
                                        ]))
                                    : const Text('—', style: TextStyle(fontSize: 12, color: AppTheme.textHint), textAlign: TextAlign.center),
                                  )),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      // Totais — não rolam verticalmente
                      totais(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        if (diferenca != null && diferenca > 0 && nomeFornComTodos != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              border: Border(top: BorderSide(color: AppTheme.warning.withValues(alpha: 0.4), width: 1.5)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
              const SizedBox(width: 8),
              Flexible(child: Text(
                'Comprando tudo de "$nomeFornComTodos" (${_brl(menorTotalComTodos)}) vs melhor por item separado (${_brl(totalMelhor)}): diferença de ${_brl(diferenca)} a mais.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.warning),
              )),
            ]),
          )
        else if (diferenca != null && diferenca <= 0 && nomeFornComTodos != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.06),
              border: Border(top: BorderSide(color: AppTheme.success.withValues(alpha: 0.2))),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, size: 14, color: AppTheme.success),
              const SizedBox(width: 8),
              Flexible(child: Text(
                '"$nomeFornComTodos" já é o mais vantajoso com ${_brl(menorTotalComTodos)} — mesmo comprando tudo de um único fornecedor.',
                style: const TextStyle(fontSize: 11, color: AppTheme.success),
              )),
            ]),
          ),
      ]),
    );
  }
}

// ─── Sub-widgets (reutilizados) ───────────────────────────────────────────────

class _MaterialChip extends StatelessWidget {
  final String nome;
  final bool selecionado;
  final bool especifico;
  final String? descricao;
  final VoidCallback onRemover;

  const _MaterialChip({
    required this.nome,
    required this.selecionado,
    required this.especifico,
    this.descricao,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selecionado
            ? AppTheme.statusOk.withValues(alpha: 0.08)
            : AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selecionado
              ? AppTheme.statusOk.withValues(alpha: 0.4)
              : AppTheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selecionado)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, size: 11, color: AppTheme.statusOk),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nome,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selecionado ? AppTheme.statusOk : AppTheme.primary,
                    ),
                  ),
                  if (especifico) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'ESP',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (especifico && descricao != null && descricao!.isNotEmpty)
                Text(
                  descricao!,
                  style: TextStyle(
                    fontSize: 10,
                    color: selecionado
                        ? AppTheme.statusOk.withValues(alpha: 0.8)
                        : AppTheme.primary.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemover,
            child: Icon(
              Icons.close,
              size: 13,
              color: selecionado
                  ? AppTheme.statusOk.withValues(alpha: 0.7)
                  : AppTheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
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
        bg = AppTheme.surfaceVariant;
        fg = AppTheme.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
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
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
      ],
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        isDense: true,
        filled: true,
        fillColor: AppTheme.surface,
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
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
                prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textHint),
                suffixIcon: _filtro.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppTheme.textHint),
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
              constraints: const BoxConstraints(maxHeight: 280),
              child: disponiveis.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                          'Todos os fornecedores já estão vinculados a este material.',
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    )
                  : filtrados.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              const Icon(Icons.search_off, size: 16, color: AppTheme.textHint),
                              const SizedBox(width: 8),
                              Text(
                                'Nenhum fornecedor encontrado para "$_filtro".',
                                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: AppTheme.divider),
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
  final double? precoM2Atual;

  const _DialogEditarPreco({
    required this.fornecedorNome,
    required this.materialNome,
    this.precoAtual,
    this.precoM2Atual,
  });

  @override
  State<_DialogEditarPreco> createState() => _DialogEditarPrecoState();
}

class _DialogEditarPrecoState extends State<_DialogEditarPreco> {
  late final TextEditingController _precoCtrl;
  late final TextEditingController _precoM2Ctrl;

  @override
  void initState() {
    super.initState();
    _precoCtrl = TextEditingController(
        text: widget.precoAtual != null
            ? widget.precoAtual!.toStringAsFixed(2)
            : '');
    _precoM2Ctrl = TextEditingController(
        text: widget.precoM2Atual != null
            ? widget.precoM2Atual!.toStringAsFixed(2)
            : '');
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
    _precoM2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Editar Preço — ${widget.fornecedorNome}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.materialNome,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
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
            const SizedBox(height: 12),
            TextField(
              controller: _precoM2Ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Preço por m² (R\$)',
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
            final precoM2 = double.tryParse(
                _precoM2Ctrl.text.replaceAll(',', '.'));
            Navigator.pop(context, {
              'preco': preco,
              'precoM2': precoM2,
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
      title: const Text('Cancelar Orçamento',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Este orçamento será movido para o histórico como cancelado.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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

class _OrdemTotaisBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool ativo;
  final VoidCallback onTap;

  const _OrdemTotaisBtn({
    required this.label,
    required this.icon,
    required this.ativo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: ativo ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ativo ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}