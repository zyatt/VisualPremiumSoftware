import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/orcamento_provider.dart';
import '../repositories/orcamento_repository.dart';
import '../theme/app_theme.dart';

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

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _brl(double? v) {
  if (v == null || v == 0) return '—';
  return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

String _dataFormatada(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final a = dt.year;
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$d/$m/$a às $h:$min';
}

String _statusLabel(String status) {
  switch (status) {
    case 'ABERTO':
      return 'Salvo';
    case 'AGUARDANDO_APROVACAO':
      return 'Aguardando Aprovação';
    case 'APROVADO':
      return 'Aprovado';
    case 'NAO_APROVADO':
      return 'Não Aprovado';
    case 'CANCELADO':
      return 'Cancelado';
    case 'CONVERTIDO':
      return 'Convertido em OC';
    default:
      return status;
  }
}

Color _statusColor(BuildContext context, String status) {
  switch (status) {
    case 'ABERTO':
      return AppTheme.success;
    case 'AGUARDANDO_APROVACAO':
      return AppTheme.warning;
    case 'APROVADO':
      return AppTheme.success;
    case 'NAO_APROVADO':
      return AppTheme.warning;
    case 'CANCELADO':
      return AppTheme.error;
    case 'CONVERTIDO':
      return const Color(0xFF0288D1);
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class OrcamentoHistoricoPage extends StatefulWidget {
  const OrcamentoHistoricoPage({super.key});

  @override
  State<OrcamentoHistoricoPage> createState() =>
      _OrcamentoHistoricoPageState();
}

class _OrcamentoHistoricoPageState extends State<OrcamentoHistoricoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _carregando = true;
  String? _erro;
  List<dynamic> _salvos = [];
  List<dynamic> _aprovados = [];
  List<dynamic> _rejeitados = [];
  List<dynamic> _cancelados = [];
  List<dynamic> _convertidos = [];

  // ── Busca por material ────────────────────────────────────────────────────
  final TextEditingController _buscaController = TextEditingController();
  String _buscaMaterial = '';

  List<dynamic> get _salvosFiltered      => _filtrar(_salvos);
  List<dynamic> get _aprovadosFiltered   => _filtrar(_aprovados);
  List<dynamic> get _rejeitadosFiltered  => _filtrar(_rejeitados);
  List<dynamic> get _canceladosFiltered  => _filtrar(_cancelados);
  List<dynamic> get _convertidosFiltered => _filtrar(_convertidos);

  List<dynamic> _filtrar(List<dynamic> lista) {
    final q = _buscaMaterial.trim().toLowerCase();
    if (q.isEmpty) return lista;
    return lista.where((orc) {
      final itens = (orc['itens'] as List? ?? []);
      return itens.any((item) {
        final nome = (item['material']?['nome'] as String? ?? '').toLowerCase();
        return nome.contains(q);
      });
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final repo = OrcamentoRepository();
      final todos = await repo.listarHistorico();
      if (!mounted) return;
      setState(() {
        _salvos = todos
            .where((o) =>
                o['status'] == 'ABERTO' ||
                o['status'] == 'AGUARDANDO_APROVACAO')
            .toList();
        _aprovados =
            todos.where((o) => o['status'] == 'APROVADO').toList();
        _rejeitados =
            todos.where((o) => o['status'] == 'NAO_APROVADO').toList();
        _cancelados =
            todos.where((o) => o['status'] == 'CANCELADO').toList();
        _convertidos =
            todos.where((o) => o['status'] == 'CONVERTIDO').toList();
      });
    } catch (e) {
      if (mounted) setState(() => _erro = _mensagemErro(e, acao: 'carregar histórico'));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // Reabrir orçamento salvo (ABERTO) para edição
  Future<void> _reabrirOrcamento(Map<String, dynamic> orc) async {
    setState(() => _carregando = true);
    try {
      final repo = OrcamentoRepository();
      final orcamentoCompleto = await repo.buscarPorId(orc['id'] as int);
      if (!mounted) return;

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
            precos: {},
          );
        }

        if (fornecedorId != null && fornecedorData != null) {
          itensPorChave[materialId]!.precos[fornecedorId] =
              PrecoFornecedorData(
            fornecedorNome:
                fornecedorData['nomeFantasia'] as String? ?? '',
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

      final provider = context.read<OrcamentoProvider>();
      provider.adicionarItensEmLote(
        orcamentoCompleto['titulo'] as String? ??
            'Orçamento #${orc['id']}',
        itensPorChave.values.toList(),
      );
      provider.setServidorIdTab(orc['id'] as int);

      if (!mounted) return;
      Navigator.of(context).pop({'reabrirServidorId': orc['id'] as int});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Orçamento #${orc['id']} carregado para edição.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'reabrir orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _carregando = false);
      }
    }
  }


  // ── Excluir orçamento (cancelado / rejeitado / convertido) ───────────────
  Future<void> _excluirOrcamento(Map<String, dynamic> orc) async {
    final id = orc['id'] as int;
    final titulo = orc['titulo'] as String? ?? 'Orçamento #$id';

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir orçamento'),
        content: Text(
          'Tem certeza que deseja excluir "$titulo"?\n\nEsta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    setState(() => _carregando = true);
    try {
      await OrcamentoRepository().excluir(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento "$titulo" excluído.'),
          backgroundColor: AppTheme.error,
        ),
      );
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'excluir orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _carregando = false);
      }
    }
  }

  // ── PDF para orçamento convertido ────────────────────────────────────────
  Future<void> _exportarPdfConvertido(Map<String, dynamic> orc) async {
    setState(() => _carregando = true);
    try {
      final repo = OrcamentoRepository();
      final completo = await repo.buscarPorId(orc['id'] as int);

      // Monta payload idêntico ao do editor.
      // IMPORTANTE: no banco, cada fornecedor cotado pra um material vira
      // uma linha própria em `itens` (constraint orcamentoId+materialId+
      // fornecedorId). Se não agrupar por materialId aqui, o mesmo material
      // aparece duplicado/triplicado no PDF — uma vez por fornecedor, cada
      // uma com só 1 preço preenchido — em vez de uma linha só com todos os
      // fornecedores comparados lado a lado.
      final itensRaw = (completo['itens'] as List? ?? []);
      final Map<int, Map<String, dynamic>> itensPorMaterial = {};

      for (final raw in itensRaw) {
        final item = raw as Map<String, dynamic>;
        final materialId = item['materialId'] as int;
        final fornecedorId = item['fornecedorId'];
        final precoUnitario = item['precoUnitario'] != null
            ? double.tryParse(item['precoUnitario'].toString())
            : null;
        final fornecedorNome =
            (item['fornecedor'] as Map<String, dynamic>?)?['nomeFantasia']
                as String? ??
                '';

        final existente = itensPorMaterial[materialId];
        if (existente == null) {
          itensPorMaterial[materialId] = {
            'materialId': item['materialId'],
            'materialNome': item['material']?['nome'] ?? '',
            'materialUnidade': item['material']?['unidade'],
            'materialCategoria': item['material']?['categoria'],
            'materialMedida': item['material']?['medida'],
            'materialEspessura': item['material']?['espessura'],
            'materialIdentificador': item['material']?['identificador'],
            'quantidade': double.tryParse(item['quantidade'].toString()) ?? 1,
            'fornecedorSelecionado':
                (item['selecionado'] as bool? ?? false) ? fornecedorId : null,
            'precos': <String, dynamic>{},
          };
        } else if (item['selecionado'] as bool? ?? false) {
          existente['fornecedorSelecionado'] = fornecedorId;
        }

        if (fornecedorId != null) {
          (itensPorMaterial[materialId]!['precos']
                  as Map<String, dynamic>)['$fornecedorId'] =
              {
            'fornecedorNome': fornecedorNome,
            'preco': precoUnitario,
          };
        }
      }

      final itens = itensPorMaterial.values.toList();

      final titulo = completo['titulo'] as String? ?? 'Orçamento';
      final fornecedoresOcultos =
          (completo['fornecedoresOcultos'] as List? ?? [])
              .map((e) => e as int)
              .toList();

      final pdfBytes = await repo.gerarPdf({
        'titulo': titulo,
        'itens': itens,
        'fornecedoresOcultos': fornecedoresOcultos,
      });

      final hoje = DateTime.now();
      final dataStr =
          '${hoje.day.toString().padLeft(2, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.year}';
      final file = File(
          '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}orcamento($dataStr).pdf');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (Platform.isWindows) {
        await Process.run('explorer', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('PDF exportado com sucesso!'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mensagemErro(e, acao: 'exportar PDF')),
          backgroundColor: AppTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ────────────────────────────────────────────────────
            Row(
              children: [
                _BotaoVoltar(
                  label: 'Voltar',
                  tooltip: 'Voltar',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Histórico de Orçamentos',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_salvosFiltered.length + _aprovadosFiltered.length + _rejeitadosFiltered.length + _canceladosFiltered.length + _convertidosFiltered.length} '
                      '${(_salvosFiltered.length + _aprovadosFiltered.length + _rejeitadosFiltered.length + _canceladosFiltered.length + _convertidosFiltered.length) == 1 ? 'orçamento' : 'orçamentos'} no histórico',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: _carregar,
                  icon: Icon(Icons.refresh,
                      size: 18, color: cs.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  mouseCursor: SystemMouseCursors.click,
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Busca por material ────────────────────────────────────────
            TextField(
              controller: _buscaController,
              onChanged: (v) => setState(() => _buscaMaterial = v),
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Buscar por nome do material...',
                hintStyle: TextStyle(fontSize: 13, color: cs.outline),
                prefixIcon: Icon(Icons.search, size: 18, color: cs.outline),
                suffixIcon: _buscaMaterial.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 16, color: cs.outline),
                        onPressed: () {
                          _buscaController.clear();
                          setState(() => _buscaMaterial = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: cs.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Abas ─────────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                    bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 2,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  Tab(text: 'Salvos (${_salvosFiltered.length})'),
                  Tab(text: 'Aprovados (${_aprovadosFiltered.length})'),
                  Tab(text: 'Rejeitados (${_rejeitadosFiltered.length})'),
                  Tab(text: 'Cancelados (${_canceladosFiltered.length})'),
                  Tab(text: 'Convertidos (${_convertidosFiltered.length})'),
                ],
              ),
            ),

            // ── Conteúdo ──────────────────────────────────────────────────────
            Expanded(
              child: _carregando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : _erro != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_outlined,
                                  size: 48, color: AppTheme.error),
                              const SizedBox(height: 12),
                              Text(
                                'Erro ao carregar histórico',
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _erro!.contains(': ')
                                    ? _erro!.substring(_erro!.indexOf(': ') + 2)
                                    : _erro!,
                                style: TextStyle(
                                    color: cs.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _carregar,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Tentar novamente'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary)
                                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                              ),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            // ── Salvos ────────────────────────────────────
                            _buildLista(
                              lista: _salvosFiltered,
                              emptyMessage: _buscaMaterial.isNotEmpty
                                  ? 'Nenhum orçamento salvo com esse material'
                                  : 'Nenhum orçamento salvo',
                              emptyIcon: Icons.save_outlined,
                              emptyColor: AppTheme.success,
                              buscaMaterial: _buscaMaterial,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(
                                orcamento: orc,
                                buscaMaterial: _buscaMaterial,
                                onReabrir: () => _reabrirOrcamento(orc),
                              ),
                            ),

                            // ── Aprovados ─────────────────────────────────
                            _buildLista(
                              lista: _aprovadosFiltered,
                              emptyMessage: _buscaMaterial.isNotEmpty
                                  ? 'Nenhum orçamento aprovado com esse material'
                                  : 'Nenhum orçamento aprovado',
                              emptyIcon: Icons.check_circle_outline,
                              emptyColor: AppTheme.success,
                              buscaMaterial: _buscaMaterial,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(
                                orcamento: orc,
                                buscaMaterial: _buscaMaterial,
                              ),
                            ),

                            // ── Rejeitados ────────────────────────────────
                            _buildLista(
                              lista: _rejeitadosFiltered,
                              emptyMessage: _buscaMaterial.isNotEmpty
                                  ? 'Nenhum orçamento rejeitado com esse material'
                                  : 'Nenhum orçamento rejeitado',
                              emptyIcon: Icons.cancel_outlined,
                              emptyColor: AppTheme.warning,
                              buscaMaterial: _buscaMaterial,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(
                                orcamento: orc,
                                buscaMaterial: _buscaMaterial,
                                onExcluir: () => _excluirOrcamento(orc),
                              ),
                            ),

                            // ── Cancelados ────────────────────────────────
                            _buildLista(
                              lista: _canceladosFiltered,
                              emptyMessage: _buscaMaterial.isNotEmpty
                                  ? 'Nenhum orçamento cancelado com esse material'
                                  : 'Nenhum orçamento cancelado',
                              emptyIcon: Icons.delete_outline,
                              emptyColor: AppTheme.error,
                              buscaMaterial: _buscaMaterial,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(
                                orcamento: orc,
                                buscaMaterial: _buscaMaterial,
                                onExcluir: () => _excluirOrcamento(orc),
                              ),
                            ),

                            // ── Convertidos ───────────────────────────────
                            _buildLista(
                              lista: _convertidosFiltered,
                              emptyMessage: _buscaMaterial.isNotEmpty
                                  ? 'Nenhum orçamento convertido com esse material'
                                  : 'Nenhum orçamento convertido em OC',
                              emptyIcon: Icons.shopping_cart_checkout,
                              emptyColor: const Color(0xFF0288D1),
                              buscaMaterial: _buscaMaterial,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(
                                orcamento: orc,
                                buscaMaterial: _buscaMaterial,
                                onVerPdf: () => _exportarPdfConvertido(orc),
                                onExcluir: () => _excluirOrcamento(orc),
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

  Widget _buildLista({
    required List<dynamic> lista,
    required String emptyMessage,
    required IconData emptyIcon,
    required Color emptyColor,
    required Widget Function(Map<String, dynamic>) itemBuilder,
    String buscaMaterial = '',
  }) {
    final cs = Theme.of(context).colorScheme;
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (buscaMaterial.isNotEmpty) ...[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.search_off, size: 36, color: cs.outline),
              ),
              const SizedBox(height: 20),
              Text(
                emptyMessage,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: cs.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tente buscar por outro nome',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ] else ...[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: emptyColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(emptyIcon, size: 36, color: emptyColor),
              ),
              const SizedBox(height: 20),
              Text(
                emptyMessage,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: cs.onSurface),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 16),
      itemCount: lista.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) =>
          itemBuilder(lista[i] as Map<String, dynamic>),
    );
  }
}

// ─── Card do histórico ────────────────────────────────────────────────────────

class _OrcamentoHistoricoCard extends StatefulWidget {
  final Map<String, dynamic> orcamento;
  final VoidCallback? onReabrir;
  final VoidCallback? onVerPdf;
  final VoidCallback? onExcluir;
  final String buscaMaterial;

  const _OrcamentoHistoricoCard({
    required this.orcamento,
    this.onReabrir,
    this.onVerPdf,
    this.onExcluir,
    this.buscaMaterial = '',
  });

  @override
  State<_OrcamentoHistoricoCard> createState() =>
      _OrcamentoHistoricoCardState();
}

class _OrcamentoHistoricoCardState
    extends State<_OrcamentoHistoricoCard> {
  bool _expandido = false;

  @override
  void initState() {
    super.initState();
    // Auto-expande se há busca ativa (mostra logo os materiais encontrados)
    if (widget.buscaMaterial.isNotEmpty) _expandido = true;
  }

  @override
  void didUpdateWidget(_OrcamentoHistoricoCard old) {
    super.didUpdateWidget(old);
    if (old.buscaMaterial != widget.buscaMaterial) {
      setState(() => _expandido = widget.buscaMaterial.isNotEmpty);
    }
  }

  // Verifica se o nome do material do grupo contém a busca
  bool _grupoCorresponde(List<Map<String, dynamic>> grupo) {
    final q = widget.buscaMaterial.trim().toLowerCase();
    if (q.isEmpty) return false;
    final nome = (grupo.first['material']?['nome'] as String? ?? '').toLowerCase();
    return nome.contains(q);
  }

  // Agrupa os itens por material (mesmo material com múltiplos fornecedores
  // vira um único grupo). Retorna lista de grupos onde cada grupo contém
  // as linhas do servidor referentes ao mesmo material.
  List<List<Map<String, dynamic>>> _agruparItensPorMaterial(
      List<dynamic> itens) {
    final Map<String, List<Map<String, dynamic>>> grupos = {};
    for (final raw in itens) {
      final item = raw as Map<String, dynamic>;
      final materialId = item['materialId']?.toString() ?? '';
      grupos.putIfAbsent(materialId, () => []).add(item);
    }
    return grupos.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final orc = widget.orcamento;
    final status = orc['status'] as String? ?? 'ABERTO';
    final titulo = orc['titulo'] as String? ?? 'Orçamento #${orc['id']}';
    final criadoEm = orc['criadoEm'] != null
        ? DateTime.tryParse(orc['criadoEm'].toString())
        : null;
    final itens = (orc['itens'] as List? ?? []);
    final motivoRejeicao = orc['motivoRejeicao'] as String?;

    // Conta materiais únicos (não duplicados por fornecedor)
    final grupos = _agruparItensPorMaterial(itens);
    final totalMateriais = grupos.length;
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context, status);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho do card ───────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Ícone de status
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      status == 'ABERTO'
                          ? Icons.save_outlined
                          : status == 'APROVADO'
                              ? Icons.check_circle_outline
                              : status == 'AGUARDANDO_APROVACAO'
                                  ? Icons.pending_outlined
                                  : status == 'CONVERTIDO'
                                      ? Icons.shopping_cart_checkout
                                      : Icons.cancel_outlined,
                      size: 20,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                titulo,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              '$totalMateriais ${totalMateriais == 1 ? 'material' : 'materiais'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (criadoEm != null) ...[
                              Text(
                                ' · ',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant),
                              ),
                              Text(
                                _dataFormatada(criadoEm),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Motivo de cancelamento / rejeição
                        if ((status == 'CANCELADO' || status == 'NAO_APROVADO') &&
                            motivoRejeicao != null &&
                            motivoRejeicao.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 12, color: AppTheme.error),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Motivo: $motivoRejeicao',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.error,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botão reabrir (só para salvos/abertos)
                  if (widget.onReabrir != null) ...[
                    FilledButton.icon(
                      onPressed: widget.onReabrir,
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Editar',
                          style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        enabledMouseCursor: SystemMouseCursors.click,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Botão PDF (só para convertidos)
                  if (widget.onVerPdf != null) ...[
                    OutlinedButton.icon(
                      onPressed: widget.onVerPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                      label: const Text('PDF',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0288D1),
                        side: const BorderSide(color: Color(0xFF0288D1)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        enabledMouseCursor: SystemMouseCursors.click,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Botão excluir (cancelados, rejeitados, convertidos)
                  if (widget.onExcluir != null) ...[
                    IconButton(
                      onPressed: widget.onExcluir,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Excluir orçamento',
                      mouseCursor: SystemMouseCursors.click,
                      style: IconButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        backgroundColor:
                            AppTheme.error.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        side: BorderSide(
                            color: AppTheme.error.withValues(alpha: 0.25)),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Chevron expandir
                  AnimatedRotation(
                    turns: _expandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 20, color: cs.outline),
                  ),
                ],
              ),
            ),
          ),

          // ── Itens expandidos (agrupados por material) ───────────────────
          if (_expandido && grupos.isNotEmpty) ...[
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Materiais cotados',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (widget.buscaMaterial.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${grupos.where(_grupoCorresponde).length} encontrado(s)',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...grupos.map((grupo) => _buildGrupoMaterial(grupo, destacado: _grupoCorresponde(grupo))),
                ],
              ),
            ),
          ],
          if (_expandido && grupos.isEmpty) ...[
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nenhum material neste orçamento.',
                style: TextStyle(
                    fontSize: 12, color: cs.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Constrói o card de um grupo de material (similar ao visual da página principal).
  /// Um grupo = mesmo material com N linhas de fornecedores.
  /// [destacado] indica se este grupo corresponde ao filtro de busca atual.
  Widget _buildGrupoMaterial(List<Map<String, dynamic>> grupo, {bool destacado = false}) {
    final primeiroItem = grupo.first;
    final materialData =
        primeiroItem['material'] as Map<String, dynamic>?;
    final materialNome = materialData?['nome'] as String? ??
        'Material #${primeiroItem['materialId']}';
    final materialUnidade = materialData?['unidade'] as String?;
    final quantidade =
        double.tryParse(primeiroItem['quantidade']?.toString() ?? '1') ?? 1;

    // Calcula média de preços unitários (excluindo nulos)
    final precos = grupo
        .map((i) => i['precoUnitario'] != null
            ? double.tryParse(i['precoUnitario'].toString())
            : null)
        .whereType<double>()
        .toList();
    final mediaPreco =
        precos.isNotEmpty ? precos.reduce((a, b) => a + b) / precos.length : null;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: destacado
            ? AppTheme.primary.withValues(alpha: 0.04)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: destacado
              ? AppTheme.primary.withValues(alpha: 0.35)
              : cs.outlineVariant,
          width: destacado ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho do material ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      size: 14, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        materialNome,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Qtd: ${quantidade % 1 == 0 ? quantidade.toInt().toString() : quantidade.toString()}',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                          if (materialUnidade != null &&
                              materialUnidade.isNotEmpty) ...[
                            Text(
                              ' $materialUnidade',
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                          if (mediaPreco != null) ...[
                            const Spacer(),
                            Icon(Icons.bar_chart,
                                size: 11, color: cs.outline),
                            const SizedBox(width: 3),
                            Text(
                              'Média ${_brl(mediaPreco)}',
                              style: TextStyle(
                                  fontSize: 11, color: cs.outline),
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

          // ── Tabela de fornecedores ────────────────────────────────────────
          if (grupo.any((i) => i['fornecedor'] != null)) ...[
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fornecedor',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.outline),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Valor Unit.',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.outline),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Total',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.outline),
                    ),
                  ),
                ],
              ),
            ),
            ...grupo.where((i) => i['fornecedor'] != null).map((item) {
              final fornecedorNome =
                  (item['fornecedor'] as Map<String, dynamic>?)?['nomeFantasia']
                          as String? ??
                      '—';
              final selecionado = item['selecionado'] as bool? ?? false;
              final precoUnitario = item['precoUnitario'] != null
                  ? double.tryParse(item['precoUnitario'].toString())
                  : null;
              final total = precoUnitario != null
                  ? precoUnitario * quantidade
                  : null;

              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: selecionado
                      ? AppTheme.primary.withValues(alpha: 0.06)
                      : cs.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: selecionado
                        ? AppTheme.primary.withValues(alpha: 0.25)
                        : cs.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    if (selecionado)
                      const Icon(Icons.check_circle,
                          size: 13, color: AppTheme.primary)
                    else
                      Icon(Icons.circle_outlined,
                          size: 13, color: cs.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fornecedorNome,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selecionado
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selecionado
                              ? AppTheme.primary
                              : cs.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _brl(precoUnitario),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: selecionado
                              ? AppTheme.primary
                              : cs.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _brl(total),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selecionado
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selecionado
                              ? AppTheme.primary
                              : cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

// ── Botão "voltar" com hover, cursor de mão e tooltip ───────────────────────
// Mesmo padrão usado no cabeçalho das páginas de estoque / histórico de material.
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
    final scheme = Theme.of(context).colorScheme;
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
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? _accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              border: Border.all(
                color: _hovered
                    ? _accent.withValues(alpha: 0.6)
                    : scheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: _hovered ? _accent : scheme.onSurfaceVariant,
                ),
                SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: _hovered ? _accent : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
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