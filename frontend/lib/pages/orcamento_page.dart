import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/material_model.dart';
import '../models/fornecedor_model.dart';
import '../providers/material_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/orcamento_provider.dart';
import '../repositories/fornecedor_repository.dart';
import '../repositories/orcamento_repository.dart';
import '../repositories/ordem_compra_repository.dart';
import '../theme/app_theme.dart';
import 'orcamento_historico_page.dart';
import 'ordem_compra_page.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _brl(double? v) {
  if (v == null || v == 0) return '—';
  return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class OrcamentoPage extends StatefulWidget {
  const OrcamentoPage({super.key});

  @override
  State<OrcamentoPage> createState() => _OrcamentoPageState();
}

class _OrcamentoPageState extends State<OrcamentoPage> {
  List<MaterialModel> _resultadosBusca = [];
  bool _buscando = false;
  bool _salvandoPreco = false;
  bool _mostrarResultados = false;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FornecedorProvider>().carregar();
    });
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _mostrarResultados = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Busca de materiais ────────────────────────────────────────────────────────

  Future<void> _buscarMateriais(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _resultadosBusca = [];
        _mostrarResultados = false;
      });
      return;
    }
    setState(() {
      _buscando = true;
      _mostrarResultados = true;
    });
    try {
      await context.read<MaterialProvider>().carregar(busca: query.trim());
      if (!mounted) return;
      final todos = context.read<MaterialProvider>().materiais;
      final provider = context.read<OrcamentoProvider>();
      final idsJaAdicionados =
          provider.tabAtual?.itens.map((i) => i.materialId).toSet() ?? {};
      setState(() {
        _resultadosBusca =
            todos.where((m) => !idsJaAdicionados.contains(m.id)).toList();
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
    _searchCtrl.clear();
    setState(() {
      _resultadosBusca = [];
      _mostrarResultados = false;
    });
  }

  // ── Vincular fornecedores ─────────────────────────────────────────────────────

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
    provider.atualizarItemParcial(item.materialId, precos: novosPrecos);

    final repo = FornecedorRepository();
    for (final fId in selecionados) {
      if (!idsJaVinculados.contains(fId)) {
        try {
          await repo.vincularMaterial(fId, {'materialId': item.materialId});
        } catch (_) {}
      }
    }
  }

  // ── Editar preço ──────────────────────────────────────────────────────────────

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
    provider.atualizarItemParcial(item.materialId, precos: novosPrecos);

    setState(() => _salvandoPreco = true);
    try {
      await FornecedorRepository().atualizarPreco(
        fornecedorId,
        item.materialId,
        {
          if (result['preco'] != null) 'preco': result['preco'],
          if (result['precoM2'] != null) 'precoMetroQuadrado': result['precoM2'],
        },
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  // ── Gerar OC ─────────────────────────────────────────────────────────────────

  Future<void> _gerarOrdemCompra() async {
    final provider = context.read<OrcamentoProvider>();
    final itens = provider.tabAtual?.itens ?? [];
    final opcao = await showDialog<String>(
      context: context,
      builder: (ctx) => _DialogOpcaoOC(itens: itens),
    );
    if (opcao == null) return;

    if (opcao == 'nova') {
      await _criarNovaOC(itens);
    } else {
      await _adicionarOCExistente(itens);
    }
  }

  // ── Exportar PDF ─────────────────────────────────────────────────────────────

  Future<void> _exportarPdf() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Adicione ao menos um material antes de exportar.')),
      );
      return;
    }

    setState(() => _salvandoPreco = true); // reusa o indicador de loading

    try {
      // Serializa os dados da aba atual para enviar ao backend
      final dadosOrcamento = {
        'titulo': tab.titulo,
        'itens': tab.itens.map((item) => item.toJson()).toList(),
      };

      final pdfBytes =
          await OrcamentoRepository().gerarPdf(dadosOrcamento);

      // Nome de arquivo: orcamento(DD-MM-AAAA).pdf
      final hoje = DateTime.now();
      final dataStr =
          '${hoje.day.toString().padLeft(2, '0')}-'
          '${hoje.month.toString().padLeft(2, '0')}-'
          '${hoje.year}';
      final nomeArquivo = 'orcamento($dataStr).pdf';

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$nomeArquivo');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (Platform.isWindows) {
        await Process.run('explorer', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF exportado com sucesso!'),
            backgroundColor: AppTheme.success,
          ),
        );
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
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  Future<void> _criarNovaOC(List<ItemOrcamentoData> itens) async {
    // Em vez de criar a OC diretamente, navega para a tela de nova OC
    // passando os materiais e quantidades do orçamento como pré-carga.
    // O usuário preenche OS e demais dados antes de salvar.

    // Resolve o FornecedorModel a partir do id selecionado no orçamento.
    // Como _podeGerarOC garante que todos os itens têm o mesmo fornecedor,
    // basta pegar o id do primeiro item.
    final fornecedorId = itens.first.fornecedorSelecionado!;
    final fornecedores = context.read<FornecedorProvider>().fornecedores;
    final FornecedorModel? fornecedorInicial = fornecedores.cast<FornecedorModel?>()
        .firstWhere((f) => f?.id == fornecedorId, orElse: () => null);

    // Monta os itens pré-carregados a partir da seleção do orçamento.
    final itensPre = itens.map((item) {
      final fId = item.fornecedorSelecionado!;
      final pf = item.precos[fId]!;
      // Usa modoOrcamento como fonte da verdade para usarM2; só recorre à
      // existência do precoM2 como fallback quando o modo não foi definido.
      final usarM2 = item.modoOrcamento == ModoOrcamento.metroQuadrado
          || (item.modoOrcamento == null && pf.precoM2 != null && pf.precoM2! > 0);
      return ItemPreCarregadoOC(
        materialId:         item.materialId,
        materialNome:       item.materialNome,
        quantidade:         item.quantidade,
        precoUnitario:      pf.preco ?? 0,
        precoMetroQuadrado: pf.precoM2,
        usarM2:             usarM2,
      );
    }).toList();

    final criou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NovaOrdemCompraPage(
          itensPreCarregados: itensPre,
          fornecedorInicial:  fornecedorInicial,
        ),
      ),
    );

    if (criou == true && mounted) {
      context.read<OrcamentoProvider>().limparAba();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ordem de compra criada com sucesso!'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _adicionarOCExistente(List<ItemOrcamentoData> itens) async {
    List<dynamic> ocsEmAndamento = [];
    try {
      final repo = OrdemCompraRepository();
      final todas = await repo.listar();
      ocsEmAndamento = todas.where((o) => o['status'] == 'EM_ANDAMENTO').toList();
    } catch (_) {}

    if (!mounted) return;

    if (ocsEmAndamento.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nenhuma OC em andamento encontrada. Crie uma nova OC.')),
      );
      return;
    }

    final ocSelecionada = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _DialogSelecionarOC(ocs: ocsEmAndamento),
    );
    if (ocSelecionada == null) return;

    if (!mounted) return;

    // Adiciona diretamente, sem solicitar dados adicionais.
    try {
      final repo = OrdemCompraRepository();
      final ocId = ocSelecionada['id'] as int;

      for (final item in itens) {
        final fId = item.fornecedorSelecionado!;
        final pf = item.precos[fId]!;
        final usarM2 = item.modoOrcamento == ModoOrcamento.metroQuadrado
            || (item.modoOrcamento == null && pf.precoM2 != null && pf.precoM2! > 0);
        await repo.adicionarItem(ocId, {
          'materialId': item.materialId,
          'numeroOS': 'OS-GERAL',
          'quantidade': item.quantidade,
          'precoUnitario': pf.preco ?? 0,
          'precoMetroQuadrado': pf.precoM2,
          'usarM2': usarM2,
        });
      }

      if (mounted) {
        context.read<OrcamentoProvider>().limparAba();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Itens adicionados à OC #${ocSelecionada['id']} com sucesso!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar à OC: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  // ── Salvar / Descartar ────────────────────────────────────────────────────────

  Future<void> _salvarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    if (provider.tabAtual == null || provider.tabAtual!.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um material para salvar.')),
      );
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salvar Orçamento',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          'O orçamento "${provider.tabAtual!.titulo}" será salvo no histórico e esta aba será fechada.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    provider.salvarOrcamento();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orçamento salvo no histórico!'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _descartarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogDescartarOrcamento(),
    );
    if (motivo == null) return;
    provider.descartarOrcamento(motivo);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orçamento descartado.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Totais ────────────────────────────────────────────────────────────────────

  Map<int, Map<String, dynamic>> _calcularTotaisPorFornecedor(
      List<ItemOrcamentoData> itens) {
    final Map<int, Map<String, dynamic>> totais = {};
    for (final item in itens) {
      for (final entry in item.precos.entries) {
        final fId = entry.key;
        final pf = entry.value;
        if (!totais.containsKey(fId)) {
          totais[fId] = {
            'nome': pf.fornecedorNome,
            'total': 0.0,   // sempre soma unitário, independente do modo
            'totalM2': 0.0, // sempre soma m², independente do modo
            'totalEfetivo': 0.0, // mantido por compatibilidade (= total unitário)
            'materiais': 0,
            'temTodosPrecos': true,
          };
        }
        totais[fId]!['materiais'] = (totais[fId]!['materiais'] as int) + 1;

        // Total unitário: sempre soma preco * quantidade (não depende do modo)
        if (pf.preco != null) {
          totais[fId]!['total'] =
              (totais[fId]!['total'] as double) + pf.preco! * item.quantidade;
          totais[fId]!['totalEfetivo'] =
              (totais[fId]!['totalEfetivo'] as double) + pf.preco! * item.quantidade;
        } else {
          totais[fId]!['temTodosPrecos'] = false;
        }

        // Total m²: sempre soma precoM2 * quantidade (não depende do modo)
        if (pf.precoM2 != null) {
          totais[fId]!['totalM2'] =
              (totais[fId]!['totalM2'] as double) + pf.precoM2! * item.quantidade;
        }
      }
    }
    return totais;
  }

  double? _mediaPreco(ItemOrcamentoData item) {
    final precos =
        item.precos.values.map((p) => p.preco).whereType<double>().toList();
    if (precos.isEmpty) return null;
    return precos.reduce((a, b) => a + b) / precos.length;
  }

  double? _mediaPrecoM2(ItemOrcamentoData item) {
    final precos =
        item.precos.values.map((p) => p.precoM2).whereType<double>().toList();
    if (precos.isEmpty) return null;
    return precos.reduce((a, b) => a + b) / precos.length;
  }

  Set<int> _todosFornecedoresIds(List<ItemOrcamentoData> itens) {
    final ids = <int>{};
    for (final item in itens) {
      ids.addAll(item.precos.keys);
    }
    return ids;
  }

  bool _podeGerarOC(List<ItemOrcamentoData> itens) {
    if (itens.isEmpty) return false;
    // Todos devem ter fornecedor selecionado E deve ser o MESMO fornecedor
    if (!itens.every((i) => i.fornecedorSelecionado != null)) return false;
    final ids = itens.map((i) => i.fornecedorSelecionado!).toSet();
    return ids.length == 1;
  }

  int _fornecedoresSelecionados(List<ItemOrcamentoData> itens) {
    return itens
        .where((i) => i.fornecedorSelecionado != null)
        .map((i) => i.fornecedorSelecionado!)
        .toSet()
        .length;
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<OrcamentoProvider>(
      builder: (context, provider, _) {
        if (!provider.carregado) {
          return const Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }

        final tab = provider.tabAtual;
        final itens = tab?.itens ?? [];

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(provider),
                const SizedBox(height: 12),
                _buildAbas(provider),
                const SizedBox(height: 16),
                _buildSelecaoMateriais(provider, itens),
                const SizedBox(height: 16),
                if (itens.isNotEmpty) ...[
                  _buildBarraAcoes(provider, itens),
                  const SizedBox(height: 16),
                ],
                Expanded(
                  child: itens.isEmpty
                      ? _buildEmptyState()
                      : _buildConteudo(provider, itens),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────────

  Widget _buildHeader(OrcamentoProvider provider) {
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
                  ?.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Orçar e comparar valores entre fornecedores',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const Spacer(),
        // Botão Histórico
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const OrcamentoHistoricoPage()),
          ),
          icon: const Icon(Icons.history, size: 16),
          label: const Text('Histórico', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            side: const BorderSide(color: AppTheme.divider),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        if (_salvandoPreco) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primary),
          ),
        ],
      ],
    );
  }

  // ── Abas ──────────────────────────────────────────────────────────────────────

  Widget _buildAbas(OrcamentoProvider provider) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: provider.abas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final aba = provider.abas[i];
                final ativa = i == provider.abaAtiva;
                return GestureDetector(
                  onTap: () => provider.selecionarAba(i),
                  onDoubleTap: () => _renomearAba(context, provider, i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: ativa
                          ? AppTheme.primary
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ativa
                            ? AppTheme.primary
                            : AppTheme.divider,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          aba.titulo,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ativa
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                        if (aba.itens.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: ativa
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${aba.itens.length}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: ativa
                                    ? Colors.white
                                    : AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => provider.fecharAba(i),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: ativa
                                ? Colors.white.withValues(alpha: 0.8)
                                : AppTheme.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Botão adicionar aba
          Tooltip(
            message: 'Novo orçamento',
            child: InkWell(
              onTap: provider.adicionarAba,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: const Icon(Icons.add,
                    size: 18, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renomearAba(
      BuildContext context, OrcamentoProvider provider, int index) async {
    final ctrl =
        TextEditingController(text: provider.abas[index].titulo);
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear orçamento',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Nome', isDense: true),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary),
            onPressed: () =>
                Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Renomear'),
          ),
        ],
      ),
    );
    if (novo != null && novo.isNotEmpty) {
      provider.renomearAba(index, novo);
    }
  }

  // ── Seleção de Materiais ──────────────────────────────────────────────────────

  Widget _buildSelecaoMateriais(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Selecionar Materiais',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (itens.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${itens.length} selecionados',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (itens.isNotEmpty)
                  TextButton.icon(
                    onPressed: provider.limparAba,
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Limpar',
                        style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: 'Buscar material para adicionar...',
                prefixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary),
                        ),
                      )
                    : const Icon(Icons.search,
                        size: 18, color: AppTheme.textHint),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _resultadosBusca = [];
                            _mostrarResultados = false;
                          });
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: _buscarMateriais,
            ),
          ),

          if (_mostrarResultados &&
              (_buscando || _resultadosBusca.isNotEmpty))
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 4)),
                ],
              ),
              child: _buscando
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.primary)),
                    )
                  : _resultadosBusca.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.search_off,
                                  size: 16,
                                  color: AppTheme.textHint),
                              SizedBox(width: 8),
                              Text('Nenhum material encontrado.',
                                  style: TextStyle(
                                      color: AppTheme.textHint,
                                      fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _resultadosBusca.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppTheme.divider),
                          itemBuilder: (ctx, i) {
                            final m = _resultadosBusca[i];
                            final sub = [
                              m.categoria,
                              m.medida,
                              m.espessura,
                              m.identificador,
                              m.unidade
                            ]
                                .where(
                                    (s) => s != null && s.isNotEmpty)
                                .join(' · ');
                            return ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 2),
                              title: Text(
                                m.nome,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary),
                              ),
                              subtitle: sub.isNotEmpty
                                  ? Text(sub,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color:
                                              AppTheme.textSecondary))
                                  : null,
                              trailing: _StatusChip(
                                  status: m.status),
                              onTap: () => _adicionarMaterial(m),
                            );
                          },
                        ),
            ),

          if (itens.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: itens.asMap().entries.map((e) {
                  final item = e.value;
                  final selecionado =
                      item.fornecedorSelecionado != null;
                  return _MaterialChip(
                    nome: item.materialNome,
                    selecionado: selecionado,
                    onRemover: () =>
                        provider.removerItem(item.materialId),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Barra de ações ────────────────────────────────────────────────────────────

  Widget _buildBarraAcoes(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    final podeGerar = _podeGerarOC(itens);
    final fornsSel = _fornecedoresSelecionados(itens);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${itens.length} ${itens.length == 1 ? 'material' : 'materiais'} — '
                    '$fornsSel ${fornsSel == 1 ? 'fornecedor selecionado' : 'fornecedores selecionados'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Salvar
                OutlinedButton.icon(
                  onPressed: _salvarOrcamento,
                  icon: const Icon(Icons.save_outlined, size: 15),
                  label: const Text('Salvar', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.success,
                    side: const BorderSide(color: AppTheme.success),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),

                // Descartar
                OutlinedButton.icon(
                  onPressed: _descartarOrcamento,
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),

                OutlinedButton.icon(
                  onPressed: itens.isEmpty ? null : _exportarPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                  label: const Text('Exportar PDF',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.divider),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),

                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.message_outlined, size: 15),
                  label: const Text('Solicitar Orçamento',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: podeGerar
                      ? 'Gerar Ordem de Compra'
                      : 'Selecione o MESMO fornecedor para todos os materiais',
                  child: FilledButton.icon(
                    onPressed: podeGerar ? _gerarOrdemCompra : null,
                    icon: const Icon(Icons.shopping_cart_checkout, size: 16),
                    label: Text(
                      'Gerar OC (${itens.length})',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.request_quote_outlined,
                size: 36, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhum material adicionado',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use a busca acima para adicionar materiais ao orçamento\ne comparar valores entre fornecedores.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Conteúdo ──────────────────────────────────────────────────────────────────

  Widget _buildConteudo(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return ListView(
      children: [
        ...itens.asMap().entries.map(
            (e) => _buildItemCard(provider, e.key, e.value, itens)),
        const SizedBox(height: 16),
        if (_todosFornecedoresIds(itens).isNotEmpty)
          _buildTabelaComparativa(provider, itens),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Item card ─────────────────────────────────────────────────────────────────

  Widget _buildItemCard(OrcamentoProvider provider, int index,
      ItemOrcamentoData item, List<ItemOrcamentoData> todosItens) {
    final usarM2 = item.modoOrcamento == ModoOrcamento.metroQuadrado;
    final allFornIds = item.precos.keys.toList();

    // Calcular menores preços antes do sort para usá-los na ordenação
    final menorPreco = allFornIds
        .map((id) => item.precos[id]?.preco)
        .whereType<double>()
        .fold<double?>(
            null, (min, v) => min == null || v < min ? v : min);

    final menorPrecoM2 = allFornIds
        .map((id) => item.precos[id]?.precoM2)
        .whereType<double>()
        .fold<double?>(
            null, (min, v) => min == null || v < min ? v : min);

    allFornIds.sort((a, b) {
      final aMenorUnit = menorPreco != null && item.precos[a]?.preco == menorPreco;
      final aMenorM2   = menorPrecoM2 != null && item.precos[a]?.precoM2 == menorPrecoM2;
      final bMenorUnit = menorPreco != null && item.precos[b]?.preco == menorPreco;
      final bMenorM2   = menorPrecoM2 != null && item.precos[b]?.precoM2 == menorPrecoM2;
      final aAmbos = aMenorUnit && aMenorM2;
      final bAmbos = bMenorUnit && bMenorM2;
      if (aAmbos && !bAmbos) return -1;
      if (bAmbos && !aAmbos) return 1;
      final pa = usarM2
          ? (item.precos[a]?.precoM2 ?? double.infinity)
          : (item.precos[a]?.preco ?? double.infinity);
      final pb = usarM2
          ? (item.precos[b]?.precoM2 ?? double.infinity)
          : (item.precos[b]?.preco ?? double.infinity);
      return pa.compareTo(pb);
    });

    final media = _mediaPreco(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho do card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      size: 16, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.materialNome,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if ([
                        item.materialCategoria,
                        item.materialMedida,
                        item.materialEspessura,
                        item.materialIdentificador,
                        item.materialUnidade
                      ].any((s) => s != null && s.isNotEmpty))
                        Text(
                          [
                            item.materialCategoria,
                            item.materialMedida,
                            item.materialEspessura,
                            item.materialIdentificador,
                            item.materialUnidade
                          ]
                              .where(
                                  (s) => s != null && s.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
                // Quantidade
                Row(
                  children: [
                    const Text('Quantidade',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: _QuantidadeField(
                        value: item.quantidade,
                        onChanged: (v) => provider
                            .atualizarItemParcial(item.materialId,
                                quantidade: v),
                      ),
                    ),
                    if (item.materialUnidade != null &&
                        item.materialUnidade!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(item.materialUnidade!,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
                const SizedBox(width: 12),
                if (item.modoOrcamento == ModoOrcamento.unitario &&
                    media != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bar_chart,
                            size: 12,
                            color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Média unitária. ${_brl(media)}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ] else if (item.modoOrcamento ==
                        ModoOrcamento.metroQuadrado &&
                    _mediaPrecoM2(item) != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.square_foot,
                            size: 12,
                            color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Média m² ${_brl(_mediaPrecoM2(item))}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                _StatusChip(status: item.materialStatus ?? ''),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Remover material',
                  color: AppTheme.textHint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  onPressed: () =>
                      provider.removerItem(item.materialId),
                ),
              ],
            ),
          ),

          if (allFornIds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: AppTheme.textHint),
                  SizedBox(width: 8),
                  Text(
                    'Nenhum fornecedor vinculado. Clique em "Adicionar Fornecedor" para comparar valores.',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      const Text(
                        'Orçar por:',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      _ModoButton(
                        label: 'Unidade',
                        icon: Icons.tag,
                        selecionado: item.modoOrcamento ==
                            ModoOrcamento.unitario,
                        onTap: () => provider.atualizarItemParcial(
                          item.materialId,
                          modoOrcamento: item.modoOrcamento ==
                                  ModoOrcamento.unitario
                              ? null
                              : ModoOrcamento.unitario,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ModoButton(
                        label: 'm²',
                        icon: Icons.square_foot,
                        selecionado: item.modoOrcamento ==
                            ModoOrcamento.metroQuadrado,
                        onTap: () => provider.atualizarItemParcial(
                          item.materialId,
                          modoOrcamento: item.modoOrcamento ==
                                  ModoOrcamento.metroQuadrado
                              ? null
                              : ModoOrcamento.metroQuadrado,
                        ),
                      ),
                    ],
                  ),
                ),

                if (item.modoOrcamento != null) ...[
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 24),
                        const Expanded(
                          child: Text('Fornecedor',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary)),
                        ),
                        if (item.modoOrcamento ==
                            ModoOrcamento.unitario) ...[
                          const SizedBox(
                            width: 110,
                            child: Text('Valor Unitário',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                          const SizedBox(
                            width: 120,
                            child: Text('Total',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                        ] else ...[
                          const SizedBox(
                            width: 110,
                            child: Text('Valor m²',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                          const SizedBox(
                            width: 120,
                            child: Text('Total m²',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                        ],
                        const SizedBox(width: 80),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.divider),
                  ...allFornIds.map((fId) {
                    final pf = item.precos[fId]!;
                    // Destaque verde independente do modo ativo
                    final isMenorPreco =
                        menorPreco != null &&
                        pf.preco != null &&
                        pf.preco == menorPreco;
                    final isMenorPrecoM2Efetivo =
                        menorPrecoM2 != null &&
                        pf.precoM2 != null &&
                        pf.precoM2 == menorPrecoM2;
                    final isSelected =
                        item.fornecedorSelecionado == fId;

                    return _FornecedorRow(
                      fornecedorNome: pf.fornecedorNome,
                      preco: pf.preco,
                      precoM2: pf.precoM2,
                      quantidade: item.quantidade,
                      isMenorPreco: isMenorPreco,
                      isMenorPrecoM2: isMenorPrecoM2Efetivo,
                      isSelected: isSelected,
                      modoOrcamento: item.modoOrcamento!,
                      onSelect: () => provider.atualizarItemParcial(
                        item.materialId,
                        fornecedorSelecionado: isSelected ? null : fId,
                        clearFornecedor: isSelected,
                      ),
                      onEditarPreco: () => _editarPreco(index, fId),
                    );
                  }),
                ],
              ],
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.person_add_outlined,
                      size: 14),
                  label: const Text('Adicionar Fornecedor',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _vincularFornecedores(index),
                ),
                const Spacer(),
                if (item.fornecedorSelecionado != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:
                          AppTheme.statusOk.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppTheme.statusOk
                              .withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            size: 12, color: AppTheme.statusOk),
                        const SizedBox(width: 5),
                        Text(
                          'Escolhido: ${item.precos[item.fornecedorSelecionado!]?.fornecedorNome}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.statusOk,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tabela comparativa ────────────────────────────────────────────────────────

  Widget _buildTabelaComparativa(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    final totais = _calcularTotaisPorFornecedor(itens);
    if (totais.isEmpty) return const SizedBox.shrink();

    final sortedIds = totais.keys.toList()
      ..sort((a, b) {
        final ta = totais[a]!['totalEfetivo'] as double;
        final tb = totais[b]!['totalEfetivo'] as double;
        if (ta == 0 && tb == 0) return 0;
        if (ta == 0) return 1;
        if (tb == 0) return -1;
        return ta.compareTo(tb);
      });

    final valoresEfetivos = sortedIds
        .map((id) => totais[id]!['totalEfetivo'] as double)
        .where((v) => v > 0)
        .toList();

    final menorTotal =
        valoresEfetivos.isNotEmpty ? valoresEfetivos.first : null;

    final valoresM2Validos = sortedIds
        .map((id) => totais[id]!['totalM2'] as double)
        .where((v) => v > 0)
        .toList();

    final menorTotalM2 = valoresM2Validos.isNotEmpty
        ? valoresM2Validos.reduce((a, b) => a < b ? a : b)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bar_chart, size: 16, color: AppTheme.primary),
                SizedBox(width: 8),
                Text(
                  'Totais por Fornecedor',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '— soma dos valores em todos os materiais',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                    child: Text('Fornecedor',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary))),
                SizedBox(
                    width: 80,
                    child: Text('Materiais',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary))),
                SizedBox(
                    width: 130,
                    child: Text('Total Unitário',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary))),
                SizedBox(
                    width: 130,
                    child: Text('Total m²',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary))),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          ...sortedIds.asMap().entries.map((entry) {
            final rank = entry.key;
            final fId = entry.value;
            final t = totais[fId]!;
            final total = t['total'] as double;
            final totalM2 = t['totalM2'] as double;
            final totalEfetivo = t['totalEfetivo'] as double;
            final mats = t['materiais'] as int;
            final temTodos = t['temTodosPrecos'] as bool;
            final isMelhor =
                menorTotal != null && totalEfetivo == menorTotal && totalEfetivo > 0;
            final isMelhorM2 = menorTotalM2 != null &&
                totalM2 == menorTotalM2 &&
                totalM2 > 0;
            final diff = (menorTotal != null && totalEfetivo > 0 && !isMelhor)
                ? totalEfetivo - menorTotal
                : null;
            final diffM2 =
                (menorTotalM2 != null && totalM2 > 0 && !isMelhorM2)
                    ? totalM2 - menorTotalM2
                    : null;

            return _TabelaComparativaRow(
              rank: rank + 1,
              nome: t['nome'] as String,
              total: total,
              totalM2: totalM2,
              materiais: mats,
              isMelhor: isMelhor,
              isMelhorM2: isMelhorM2,
              diff: diff,
              diffM2: diffM2,
              temTodosPrecos: temTodos,
            );
          }),
          if ((menorTotal != null && menorTotal > 0) ||
              (menorTotalM2 != null && menorTotalM2 > 0))
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (menorTotal != null && menorTotal > 0)
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: AppTheme.statusOk),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary),
                            children: [
                              const TextSpan(
                                  text: 'Melhor total unitário: '),
                              TextSpan(
                                text:
                                    '${totais[sortedIds.first]!['nome']} com ${_brl(menorTotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.statusOk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (menorTotalM2 != null && menorTotalM2 > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.square_foot,
                            size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary),
                            children: [
                              const TextSpan(
                                  text: 'Melhor total m²: '),
                              TextSpan(
                                text: () {
                                  final bestId = sortedIds.firstWhere(
                                    (id) =>
                                        (totais[id]!['totalM2']
                                            as double) ==
                                        menorTotalM2,
                                    orElse: () => sortedIds.first,
                                  );
                                  return '${totais[bestId]!['nome']} com ${_brl(menorTotalM2)}';
                                }(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          if (!_podeGerarOC(itens) && itens.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: AppTheme.primary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Selecione um fornecedor em cada material para habilitar o botão "Gerar OC".',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets (reutilizados) ───────────────────────────────────────────────

class _MaterialChip extends StatelessWidget {
  final String nome;
  final bool selecionado;
  final VoidCallback onRemover;

  const _MaterialChip({
    required this.nome,
    required this.selecionado,
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
              child:
                  Icon(Icons.check_circle, size: 11, color: AppTheme.statusOk),
            ),
          Text(
            nome,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  selecionado ? AppTheme.statusOk : AppTheme.primary,
            ),
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

class _ModoButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selecionado;
  final VoidCallback onTap;

  const _ModoButton({
    required this.label,
    required this.icon,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado ? AppTheme.primary : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selecionado ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    selecionado ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
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
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _QuantidadeField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _QuantidadeField(
      {required this.value, required this.onChanged});

  @override
  State<_QuantidadeField> createState() => _QuantidadeFieldState();
}

class _QuantidadeFieldState extends State<_QuantidadeField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value
            .toStringAsFixed(widget.value % 1 == 0 ? 0 : 2));
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
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
      ],
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
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

class _FornecedorRow extends StatelessWidget {
  final String fornecedorNome;
  final double? preco;
  final double? precoM2;
  final double quantidade;
  final bool isMenorPreco;
  final bool isMenorPrecoM2;
  final bool isSelected;
  final ModoOrcamento modoOrcamento;
  final VoidCallback onSelect;
  final VoidCallback onEditarPreco;

  const _FornecedorRow({
    required this.fornecedorNome,
    this.preco,
    this.precoM2,
    required this.quantidade,
    required this.isMenorPreco,
    required this.isMenorPrecoM2,
    required this.isSelected,
    required this.modoOrcamento,
    required this.onSelect,
    required this.onEditarPreco,
  });

  @override
  Widget build(BuildContext context) {
    final totalUnit = preco != null ? preco! * quantidade : null;
    final totalM2v = precoM2 != null ? precoM2! * quantidade : null;
    final isUnit = modoOrcamento == ModoOrcamento.unitario;

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.04)
              : null,
          border: const Border(
            top: BorderSide(color: AppTheme.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color:
                  isSelected ? AppTheme.primary : AppTheme.textHint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fornecedorNome,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: isUnit
                  ? (preco != null
                      ? Text(_brl(preco),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPreco
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isMenorPreco
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textHint)))
                  : (precoM2 != null
                      ? Text(_brl(precoM2),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPrecoM2
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isMenorPrecoM2
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textHint))),
            ),
            SizedBox(
              width: 120,
              child: isUnit
                  ? (totalUnit != null
                      ? Text(_brl(totalUnit),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPreco
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isMenorPreco
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textHint)))
                  : (totalM2v != null
                      ? Text(_brl(totalM2v),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPrecoM2
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isMenorPrecoM2
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textHint))),
            ),
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onEditarPreco,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(
                          color: AppTheme.divider),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Editar'),
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

class _TabelaComparativaRow extends StatelessWidget {
  final int rank;
  final String nome;
  final double total;
  final double totalM2;
  final int materiais;
  final bool isMelhor;
  final bool isMelhorM2;
  final double? diff;
  final double? diffM2;
  final bool temTodosPrecos;

  const _TabelaComparativaRow({
    required this.rank,
    required this.nome,
    required this.total,
    required this.totalM2,
    required this.materiais,
    required this.isMelhor,
    required this.isMelhorM2,
    this.diff,
    this.diffM2,
    required this.temTodosPrecos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (isMelhor)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.emoji_events,
                        size: 16, color: AppTheme.statusOk),
                  )
                else
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(right: 8),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surfaceVariant,
                    ),
                    child: Text(
                      '$rank°',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                Flexible(
                  child: Text(
                    nome,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (!temTodosPrecos)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message:
                          'Valor de algum material não informado',
                      child: Icon(Icons.warning_amber_rounded,
                          size: 13, color: AppTheme.warning),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: Text('$materiais mat.',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary)),
          ),
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  total > 0 ? _brl(total) : '—',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isMelhor ? FontWeight.w700 : FontWeight.w500,
                    color: isMelhor
                        ? AppTheme.statusOk
                        : AppTheme.textPrimary,
                  ),
                ),
                if (diff != null)
                  Text('+${_brl(diff)}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.statusCritico)),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  totalM2 > 0 ? _brl(totalM2) : '—',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isMelhorM2 ? FontWeight.w700 : FontWeight.w500,
                    color: isMelhorM2 ? AppTheme.statusOk : AppTheme.textPrimary,
                  ),
                ),
                if (diffM2 != null)
                  Text('+${_brl(diffM2)}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.statusCritico)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Diálogos ─────────────────────────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    final disponiveis = widget.fornecedores
        .where((f) => !widget.idsJaVinculados.contains(f.id))
        .toList();

    return AlertDialog(
      title: Text('Adicionar Fornecedores — ${widget.materialNome}',
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: disponiveis.isEmpty
              ? const Text(
                  'Todos os fornecedores já estão vinculados a este material.',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: disponiveis.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1, color: AppTheme.divider),
                  itemBuilder: (ctx, i) {
                    final f = disponiveis[i];
                    return CheckboxListTile(
                      dense: true,
                      title: Text(f.nomeFantasia,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: f.cnpj != null
                          ? Text(f.cnpj!,
                              style: const TextStyle(fontSize: 11))
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
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary),
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
        style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
          style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary),
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
      title: const Text('Descartar Orçamento',
          style:
              TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Este orçamento será movido para o histórico como descartado.',
            style:
                TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Motivo do descarte *',
              hintText: 'Explique o motivo pelo qual está descartando...',
              isDense: true,
              errorText: _vazio ? 'Informe o motivo do descarte' : null,
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
          style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error),
          onPressed: () {
            if (_ctrl.text.trim().isEmpty) {
              setState(() => _vazio = true);
              return;
            }
            Navigator.pop(context, _ctrl.text.trim());
          },
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _DialogOpcaoOC extends StatelessWidget {
  final List<ItemOrcamentoData> itens;
  const _DialogOpcaoOC({required this.itens});

  @override
  Widget build(BuildContext context) {
    final fornecedores = itens
        .where((i) => i.fornecedorSelecionado != null)
        .map((i) =>
            i.precos[i.fornecedorSelecionado!]?.fornecedorNome ?? '')
        .toSet();

    return AlertDialog(
      title: const Text('Gerar Ordem de Compra',
          style:
              TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${itens.length} ${itens.length == 1 ? 'material' : 'materiais'} selecionados · '
            '${fornecedores.length} ${fornecedores.length == 1 ? 'fornecedor' : 'fornecedores'}',
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary),
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
          style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary),
          onPressed: () => Navigator.pop(context, 'nova'),
          child: const Text('Criar nova OC'),
        ),
      ],
    );
  }
}


class _DialogSelecionarOC extends StatelessWidget {
  final List<dynamic> ocs;
  const _DialogSelecionarOC({required this.ocs});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar OC existente',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: ocs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (ctx, i) {
              final oc = ocs[i] as Map<String, dynamic>;
              final fornNome =
                  oc['fornecedor']?['nomeFantasia'] ?? '—';
              final valorTotal =
                  double.tryParse(oc['valorTotal']?.toString() ?? '0') ??
                      0;
              return InkWell(
                onTap: () => Navigator.pop(context, oc),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      // Número grande e destacado
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '#${oc['id']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fornNome,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Total: ${_brl(valorTotal)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: AppTheme.textHint),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}