import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/orcamento_provider.dart';
import '../repositories/orcamento_repository.dart';
import '../theme/app_theme.dart';

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
    default:
      return status;
  }
}

Color _statusColor(String status) {
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
    default:
      return AppTheme.textSecondary;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
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
      final Map<String, ItemOrcamentoData> itensPorChave = {};

      for (final item in itens) {
        final materialId = item['materialId'] as int;
        final materialData = item['material'] as Map<String, dynamic>?;
        final fornecedorId = item['fornecedorId'] as int?;
        final fornecedorData = item['fornecedor'] as Map<String, dynamic>?;
        final especifico = materialData?['especifico'] as bool? ?? false;

        final chave = especifico
            ? 'esp_${materialId}_${(item['descricaoItem'] as String? ?? '').trim().toLowerCase()}'
            : 'mat_$materialId';

        if (!itensPorChave.containsKey(chave)) {
          itensPorChave[chave] = ItemOrcamentoData(
            materialId: materialId,
            materialNome: materialData?['nome'] as String? ?? '',
            materialUnidade: materialData?['unidade'] as String?,
            materialCategoria: materialData?['categoria'] as String?,
            materialMedida: materialData?['medida'] as String?,
            materialEspessura: materialData?['espessura'] as String?,
            materialIdentificador: materialData?['identificador'] as String?,
            materialEspecifico: especifico,
            descricao: item['descricaoItem'] as String?,
            quantidade: double.tryParse(item['quantidade'].toString()) ?? 1,
            precos: {},
            modoOrcamento: (item['usarM2'] as bool? ?? false)
                ? ModoOrcamento.metroQuadrado
                : ModoOrcamento.unitario,
          );
        }

        if (fornecedorId != null && fornecedorData != null) {
          itensPorChave[chave]!.precos[fornecedorId] =
              PrecoFornecedorData(
            fornecedorNome:
                fornecedorData['nomeFantasia'] as String? ?? '',
            preco: item['precoUnitario'] != null
                ? double.tryParse(item['precoUnitario'].toString())
                : null,
            precoM2: item['precoM2'] != null
                ? double.tryParse(item['precoM2'].toString())
                : null,
          );

          if (item['selecionado'] as bool? ?? false) {
            itensPorChave[chave]!.fornecedorSelecionado = fornecedorId;
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
            content: Text('Erro ao reabrir orçamento: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _carregando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ────────────────────────────────────────────────────
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new,
                      size: 18, color: AppTheme.textSecondary),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: const BorderSide(color: AppTheme.divider),
                  ),
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
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_salvos.length + _aprovados.length + _rejeitados.length + _cancelados.length} '
                      '${(_salvos.length + _aprovados.length + _rejeitados.length + _cancelados.length) == 1 ? 'orçamento' : 'orçamentos'} no histórico',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh,
                      size: 18, color: AppTheme.textSecondary),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: const BorderSide(color: AppTheme.divider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Abas ─────────────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                    bottom: BorderSide(color: AppTheme.divider)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 2,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  Tab(text: 'Salvos (${_salvos.length})'),
                  Tab(text: 'Aprovados (${_aprovados.length})'),
                  Tab(text: 'Rejeitados (${_rejeitados.length})'),
                  Tab(text: 'Cancelados (${_cancelados.length})'),
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
                              const Icon(Icons.error_outline,
                                  size: 48, color: AppTheme.error),
                              const SizedBox(height: 16),
                              Text('Erro: $_erro',
                                  style: const TextStyle(
                                      color: AppTheme.error)),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _carregar,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Tentar novamente'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary),
                              ),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            // ── Salvos ────────────────────────────────────
                            _buildLista(
                              lista: _salvos,
                              emptyMessage: 'Nenhum orçamento salvo',
                              emptyIcon: Icons.save_outlined,
                              emptyColor: AppTheme.success,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(
                                orcamento: orc,
                                onReabrir: () => _reabrirOrcamento(orc),
                              ),
                            ),

                            // ── Aprovados ─────────────────────────────────
                            _buildLista(
                              lista: _aprovados,
                              emptyMessage: 'Nenhum orçamento aprovado',
                              emptyIcon: Icons.check_circle_outline,
                              emptyColor: AppTheme.success,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(orcamento: orc),
                            ),

                            // ── Rejeitados ────────────────────────────────
                            _buildLista(
                              lista: _rejeitados,
                              emptyMessage: 'Nenhum orçamento rejeitado',
                              emptyIcon: Icons.cancel_outlined,
                              emptyColor: AppTheme.warning,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(orcamento: orc),
                            ),

                            // ── Cancelados ────────────────────────────────
                            _buildLista(
                              lista: _cancelados,
                              emptyMessage: 'Nenhum orçamento cancelado',
                              emptyIcon: Icons.delete_outline,
                              emptyColor: AppTheme.error,
                              itemBuilder: (orc) =>
                                  _OrcamentoHistoricoCard(orcamento: orc),
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
  }) {
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  ?.copyWith(color: AppTheme.textPrimary),
            ),
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

  const _OrcamentoHistoricoCard({
    required this.orcamento,
    this.onReabrir,
  });

  @override
  State<_OrcamentoHistoricoCard> createState() =>
      _OrcamentoHistoricoCardState();
}

class _OrcamentoHistoricoCardState
    extends State<_OrcamentoHistoricoCard> {
  bool _expandido = false;

  // Agrupa os itens por material (mesmo material com múltiplos fornecedores
  // vira um único grupo). Retorna lista de grupos onde cada grupo contém
  // as linhas do servidor referentes ao mesmo material.
  List<List<Map<String, dynamic>>> _agruparItensPorMaterial(
      List<dynamic> itens) {
    final Map<String, List<Map<String, dynamic>>> grupos = {};
    for (final raw in itens) {
      final item = raw as Map<String, dynamic>;
      final materialId = item['materialId']?.toString() ?? '';
      final especifico =
          (item['material'] as Map<String, dynamic>?)?['especifico'] as bool? ??
              false;
      // Materiais específicos são agrupados por materialId + descricaoItem,
      // pois cada combinação (material + descrição) representa um item distinto,
      // mas todos os fornecedores desse item devem aparecer juntos.
      // Usamos normalização para evitar quebras por espaços extras.
      final chave = especifico
          ? 'esp_${materialId}_${(item['descricaoItem'] as String? ?? '').trim().toLowerCase()}'
          : 'mat_$materialId';
      grupos.putIfAbsent(chave, () => []).add(item);
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho do card ───────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
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
                      color: _statusColor(status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      status == 'ABERTO'
                          ? Icons.save_outlined
                          : status == 'APROVADO'
                              ? Icons.check_circle_outline
                              : status == 'AGUARDANDO_APROVACAO'
                                  ? Icons.pending_outlined
                                  : Icons.cancel_outlined,
                      size: 20,
                      color: _statusColor(status),
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _statusColor(status)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor(status),
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (criadoEm != null) ...[
                              const Text(
                                ' · ',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                              Text(
                                _dataFormatada(criadoEm),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
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
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Chevron expandir
                  AnimatedRotation(
                    turns: _expandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        size: 20, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
          ),

          // ── Itens expandidos (agrupados por material) ───────────────────
          if (_expandido && grupos.isNotEmpty) ...[
            const Divider(height: 1, color: AppTheme.divider),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Materiais cotados',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...grupos.map((grupo) => _buildGrupoMaterial(grupo)),
                ],
              ),
            ),
          ],
          if (_expandido && grupos.isEmpty) ...[
            const Divider(height: 1, color: AppTheme.divider),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nenhum material neste orçamento.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textHint),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Constrói o card de um grupo de material (similar ao visual da página principal).
  /// Um grupo = mesmo material com N linhas de fornecedores.
  Widget _buildGrupoMaterial(List<Map<String, dynamic>> grupo) {
    final primeiroItem = grupo.first;
    final materialData =
        primeiroItem['material'] as Map<String, dynamic>?;
    final materialNome = materialData?['nome'] as String? ??
        'Material #${primeiroItem['materialId']}';
    final materialMedida = materialData?['medida'] as String?;
    final materialEspessura = materialData?['espessura'] as String?;
    final materialIdentificador = materialData?['identificador'] as String?;
    final materialUnidade = materialData?['unidade'] as String?;
    final especifico = materialData?['especifico'] as bool? ?? false;
    final quantidade =
        double.tryParse(primeiroItem['quantidade']?.toString() ?? '1') ?? 1;

    // Subtítulo com atributos extras do material (medida · espessura · identificador)
    final subPartes = [
      materialMedida,
      materialEspessura,
      materialIdentificador,
    ].where((s) => s != null && s.isNotEmpty).join(' · ');

    // Descrição do item (só para materiais específicos)
    final descricaoItem = especifico
        ? primeiroItem['descricaoItem'] as String?
        : null;

    // Calcula média de preços unitários (excluindo nulos)
    final precos = grupo
        .map((i) => i['precoUnitario'] != null
            ? double.tryParse(i['precoUnitario'].toString())
            : null)
        .whereType<double>()
        .toList();
    final mediaPreco =
        precos.isNotEmpty ? precos.reduce((a, b) => a + b) / precos.length : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              materialNome,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (especifico)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Específico',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (descricaoItem != null && descricaoItem.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          descricaoItem,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (subPartes.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subPartes,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Qtd: ${quantidade % 1 == 0 ? quantidade.toInt().toString() : quantidade.toString()}',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          if (materialUnidade != null &&
                              materialUnidade.isNotEmpty) ...[
                            Text(
                              ' $materialUnidade',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                          if (mediaPreco != null) ...[
                            const Spacer(),
                            const Icon(Icons.bar_chart,
                                size: 11, color: AppTheme.textHint),
                            const SizedBox(width: 3),
                            Text(
                              'Média ${_brl(mediaPreco)}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textHint),
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
            const Divider(height: 1, color: AppTheme.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: const [
                  Expanded(
                    child: Text(
                      'Fornecedor',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textHint),
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
                          color: AppTheme.textHint),
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
                          color: AppTheme.textHint),
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
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: selecionado
                        ? AppTheme.primary.withValues(alpha: 0.25)
                        : AppTheme.divider,
                  ),
                ),
                child: Row(
                  children: [
                    if (selecionado)
                      const Icon(Icons.check_circle,
                          size: 13, color: AppTheme.primary)
                    else
                      const Icon(Icons.circle_outlined,
                          size: 13, color: AppTheme.textHint),
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
                              : AppTheme.textPrimary,
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
                              : AppTheme.textPrimary,
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
                              : AppTheme.textPrimary,
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