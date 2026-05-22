import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/orcamento_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            // ── Cabeçalho ──────────────────────────────────────────────────
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
                    Consumer<OrcamentoProvider>(
                      builder: (_, p, __) {
                        final total = p.historicoSalvos.length +
                            p.historicoDescartados.length;
                        return Text(
                          '$total ${total == 1 ? 'orçamento' : 'orçamentos'} no histórico',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textSecondary),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Abas ───────────────────────────────────────────────────────
            Consumer<OrcamentoProvider>(
              builder: (_, p, __) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border:
                        Border(bottom: BorderSide(color: AppTheme.divider)),
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
                      Tab(text: 'Salvos (${p.historicoSalvos.length})'),
                      Tab(
                          text:
                              'Cancelados (${p.historicoDescartados.length})'),
                    ],
                  ),
                );
              },
            ),

            // ── Conteúdo ───────────────────────────────────────────────────
            Expanded(
              child: Consumer<OrcamentoProvider>(
                builder: (context, provider, _) {
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _OrcamentoLista(
                        entradas: provider.historicoSalvos,
                        tipo: StatusOrcamentoHistorico.salvo,
                        emptyMessage: 'Nenhum orçamento salvo',
                        emptyIcon: Icons.save_outlined,
                        onReabrir: (entry) {
                          provider.reabrirOrcamento(entry);
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Orçamento "${entry.titulo}" reaberto em nova aba.'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        },
                      ),
                      _OrcamentoLista(
                        entradas: provider.historicoDescartados,
                        tipo: StatusOrcamentoHistorico.descartado,
                        emptyMessage: 'Nenhum orçamento cancelado',
                        emptyIcon: Icons.delete_outline,
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
}

// ─── Lista ────────────────────────────────────────────────────────────────────

class _OrcamentoLista extends StatelessWidget {
  final List<OrcamentoHistoricoEntry> entradas;
  final StatusOrcamentoHistorico tipo;
  final String emptyMessage;
  final IconData emptyIcon;
  final void Function(OrcamentoHistoricoEntry)? onReabrir;

  const _OrcamentoLista({
    required this.entradas,
    required this.tipo,
    required this.emptyMessage,
    required this.emptyIcon,
    this.onReabrir,
  });

  @override
  Widget build(BuildContext context) {
    if (entradas.isEmpty) {
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
              child: Icon(emptyIcon, size: 36, color: AppTheme.primary),
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
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      itemCount: entradas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final entry = entradas[i];
        return _OrcamentoCard(
          entry: entry,
          onReabrir: onReabrir != null ? () => onReabrir!(entry) : null,
          onVerDetalhes: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _OrcamentoDetalhePage(entry: entry),
            ),
          ),
        );
      },
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _OrcamentoCard extends StatelessWidget {
  final OrcamentoHistoricoEntry entry;
  final VoidCallback? onReabrir;
  final VoidCallback onVerDetalhes;

  const _OrcamentoCard({
    required this.entry,
    required this.onVerDetalhes,
    this.onReabrir,
  });

  @override
  Widget build(BuildContext context) {
    final salvo = entry.status == StatusOrcamentoHistorico.salvo;
    final statusColor = salvo ? AppTheme.success : AppTheme.error;
    final statusLabel = salvo ? 'Salvo' : 'Cancelado';
    final statusIcon =
        salvo ? Icons.check_circle_outline : Icons.cancel_outlined;
    final fornecedores = <String>{};
    for (final item in entry.itens) {
      for (final pf in item.precos.values) {
        fornecedores.add(pf.fornecedorNome);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(
                    color: statusColor.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Icon(statusIcon, size: 18, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.titulo,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _dataFormatada(entry.criadoEm),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textHint),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Corpo
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Stat(
                      icon: Icons.inventory_2_outlined,
                      label: 'Materiais',
                      value: '${entry.itens.length}',
                    ),
                    const SizedBox(width: 24),
                    _Stat(
                      icon: Icons.store_outlined,
                      label: 'Fornecedores',
                      value: '${fornecedores.length}',
                    ),
                  ],
                ),

                // Motivo descarte
                if (!salvo && entry.motivoDescarte != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: AppTheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Motivo do cancelamento',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.error,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                entry.motivoDescarte!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Ações
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: () async {
                        final confirmar = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Excluir orçamento',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                            content: Text(
                              'Deseja excluir permanentemente "${entry.titulo}" do histórico?',
                              style: const TextStyle(fontSize: 13),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.error),
                                onPressed: () =>
                                    Navigator.pop(ctx, true),
                                child: const Text('Excluir'),
                              ),
                            ],
                          ),
                        );
                        if (confirmar == true && context.mounted) {
                          context
                              .read<OrcamentoProvider>()
                              .excluirDoHistorico(entry.id);
                        }
                      },
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppTheme.error),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AppTheme.error.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      tooltip: 'Excluir do histórico',
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onVerDetalhes,
                      icon: const Icon(Icons.visibility_outlined,
                          size: 14),
                      label: const Text('Ver detalhes',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side:
                            const BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                      ),
                    ),
                    if (onReabrir != null) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: onReabrir,
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Reabrir',
                            style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
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
    );
  }
}

// ─── Stat widget ──────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Stat(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.textHint),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textHint)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Detalhe page ─────────────────────────────────────────────────────────────

class _OrcamentoDetalhePage extends StatelessWidget {
  final OrcamentoHistoricoEntry entry;

  const _OrcamentoDetalhePage({required this.entry});

  @override
  Widget build(BuildContext context) {
    final salvo = entry.status == StatusOrcamentoHistorico.salvo;
    final statusColor = salvo ? AppTheme.success : AppTheme.error;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ────────────────────────────────────────────────
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.titulo,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dataFormatada(entry.criadoEm),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    salvo ? 'Salvo' : 'Cancelado',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<OrcamentoProvider>(
                  builder: (context, provider, _) => IconButton(
                    onPressed: () async {
                      final confirmar = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Excluir orçamento',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          content: Text(
                            'Deseja excluir permanentemente "${entry.titulo}" do histórico?',
                            style: const TextStyle(fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, false),
                                child: const Text('Cancelar')),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.error),
                              onPressed: () =>
                                  Navigator.pop(ctx, true),
                              child: const Text('Excluir'),
                            ),
                          ],
                        ),
                      );
                      if (confirmar == true && context.mounted) {
                        provider.excluirDoHistorico(entry.id);
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppTheme.error),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          AppTheme.error.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    tooltip: 'Excluir do histórico',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Motivo descarte ─────────────────────────────────────────
            if (!salvo && entry.motivoDescarte != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppTheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Motivo do cancelamento',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.motivoDescarte!,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Resumo ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                children: [
                  _Stat(
                    icon: Icons.inventory_2_outlined,
                    label: 'Materiais',
                    value: '${entry.itens.length}',
                  ),
                  if (salvo) ...[
                    const Spacer(),
                    Consumer<OrcamentoProvider>(
                      builder: (context, provider, _) =>
                          FilledButton.icon(
                        onPressed: () {
                          provider.reabrirOrcamento(entry);
                          Navigator.of(context)
                            ..pop()
                            ..pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Orçamento "${entry.titulo}" reaberto em nova aba.'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        },
                        icon:
                            const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Reabrir em nova aba',
                            style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Lista de itens ─────────────────────────────────────────
            Expanded(
              child: entry.itens.isEmpty
                  ? const Center(
                      child: Text(
                          'Nenhum material neste orçamento.',
                          style:
                              TextStyle(color: AppTheme.textHint)))
                  : ListView.separated(
                      itemCount: entry.itens.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final item = entry.itens[i];
                        return _DetalheItemCard(item: item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Item card de detalhe ─────────────────────────────────────────────────────

class _DetalheItemCard extends StatelessWidget {
  final ItemOrcamentoData item;

  const _DetalheItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final fIds = item.precos.keys.toList();
    fIds.sort((a, b) {
      final pa = item.precos[a]?.preco ?? double.infinity;
      final pb = item.precos[b]?.preco ?? double.infinity;
      return pa.compareTo(pb);
    });

    final menorPreco = fIds
        .map((id) => item.precos[id]?.preco)
        .whereType<double>()
        .fold<double?>(
            null, (min, v) => min == null || v < min ? v : min);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      size: 15, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.materialNome,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (item.descricao != null &&
                          item.descricao!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.descricao!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  'Qtd: ${item.quantidade % 1 == 0 ? item.quantidade.toInt() : item.quantidade}'
                  '${item.materialUnidade != null ? ' ${item.materialUnidade}' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (fIds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Sem fornecedores vinculados.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textHint)),
            )
          else
            ...fIds.map((fId) {
              final pf = item.precos[fId]!;
              final isSelecionado =
                  item.fornecedorSelecionado == fId;
              final isMelhorPreco =
                  pf.preco != null && pf.preco == menorPreco;

              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelecionado
                      ? AppTheme.primary.withValues(alpha: 0.05)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                        color:
                            AppTheme.divider.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    if (isSelecionado)
                      const Icon(Icons.check_circle,
                          size: 14, color: AppTheme.primary)
                    else
                      const Icon(Icons.circle_outlined,
                          size: 14, color: AppTheme.textHint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pf.fornecedorNome,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelecionado
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelecionado
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    if (isMelhorPreco && fIds.length > 1)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Menor preço',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.success),
                        ),
                      ),
                    Text(
                      pf.preco != null
                          ? _brl(pf.preco! * item.quantidade)
                          : '—',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isMelhorPreco
                            ? AppTheme.success
                            : AppTheme.textPrimary,
                      ),
                    ),
                    if (pf.preco != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${_brl(pf.preco)}/un)',
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textHint),
                      ),
                    ],
                    if (pf.precoM2 != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_brl(pf.precoM2)}/m²',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}