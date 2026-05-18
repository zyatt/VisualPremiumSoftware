import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ordem_compra_model.dart';
import '../providers/ordem_compra_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA PRINCIPAL DE HISTÓRICO
// ─────────────────────────────────────────────────────────────────────────────

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _buscaCtrl = TextEditingController();
  String _filtroBusca = '';

  DateTime? _dataInicio;
  DateTime? _dataFim;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrdemCompraProvider>().carregar();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  List<OrdemCompraModel> _filtrar(List<dynamic> lista) {
    return lista.map((o) {
      return o is OrdemCompraModel
          ? o
          : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
    }).where((o) {
      final q = _filtroBusca.trim().toLowerCase();
      if (q.isNotEmpty) {
        final matchId       = o.id.toString().contains(q);
        final matchFornec   = (o.fornecedorNome ?? '').toLowerCase().contains(q);
        final matchEmpresa  = (o.empresa ?? '').toLowerCase().contains(q);
        final matchOS       = o.numerosOS.any((os) => os.toLowerCase().contains(q));
        if (!matchId && !matchFornec && !matchEmpresa && !matchOS) return false;
      }
      if (_dataInicio != null && o.data.isBefore(_dataInicio!)) return false;
      if (_dataFim != null && o.data.isAfter(_dataFim!.add(const Duration(days: 1)))) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.data.compareTo(a.data));
  }

  Future<void> _selecionarData({required bool isInicio}) async {
    final inicial = isInicio ? (_dataInicio ?? DateTime.now()) : (_dataFim ?? DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (d != null) {
      setState(() {
        if (isInicio) _dataInicio = d;
        else          _dataFim    = d;
      });
    }
  }

  void _limparFiltros() {
    setState(() {
      _buscaCtrl.clear();
      _filtroBusca = '';
      _dataInicio  = null;
      _dataFim     = null;
    });
  }

  String _formatData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ─────────────────────────────────────────────────────
            Consumer<OrdemCompraProvider>(builder: (_, p, __) {
              final total = p.finalizadas.length + p.canceladas.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Histórico de Ordens',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$total ${total == 1 ? 'ordem' : 'ordens'} no histórico',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              );
            }),
            const SizedBox(height: 20),

            // ── Filtros ───────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nº OC, fornecedor, empresa ou OS…',
                      prefixIcon: const Icon(Icons.search,
                          color: AppTheme.textHint, size: 20),
                      isDense: true,
                      suffixIcon: _filtroBusca.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  size: 18, color: AppTheme.textHint),
                              onPressed: () {
                                _buscaCtrl.clear();
                                setState(() => _filtroBusca = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300),
                          () => setState(() => _filtroBusca = v));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Data início
                _DateFilterBtn(
                  label: _dataInicio != null
                      ? _formatData(_dataInicio!)
                      : 'De',
                  icon: Icons.calendar_today_outlined,
                  active: _dataInicio != null,
                  onTap: () => _selecionarData(isInicio: true),
                ),
                const SizedBox(width: 8),
                // Data fim
                _DateFilterBtn(
                  label: _dataFim != null ? _formatData(_dataFim!) : 'Até',
                  icon: Icons.calendar_month_outlined,
                  active: _dataFim != null,
                  onTap: () => _selecionarData(isInicio: false),
                ),
                const SizedBox(width: 8),
                // Limpar filtros
                if (_filtroBusca.isNotEmpty ||
                    _dataInicio != null ||
                    _dataFim != null)
                  IconButton.outlined(
                    tooltip: 'Limpar filtros',
                    icon: const Icon(Icons.filter_alt_off),
                    onPressed: _limparFiltros,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Abas ──────────────────────────────────────────────────────────
            Container(
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
                tabs: const [
                  Tab(text: 'Finalizadas'),
                  Tab(text: 'Canceladas'),
                ],
              ),
            ),

            // ── Listas ────────────────────────────────────────────────────────
            Expanded(
              child: Consumer<OrdemCompraProvider>(
                builder: (context, prov, _) {
                  if (prov.carregando) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    );
                  }
                  if (prov.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppTheme.error, size: 48),
                          const SizedBox(height: 12),
                          Text(prov.erro!,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: prov.carregar,
                            child: const Text('Tentar novamente',
                                style:
                                    TextStyle(color: AppTheme.primary)),
                          ),
                        ],
                      ),
                    );
                  }

                  final finalizadas = _filtrar(prov.finalizadas);
                  final canceladas  = _filtrar(prov.canceladas);

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _HistoricoList(
                        ordens: finalizadas,
                        statusColor: AppTheme.success,
                        emptyMessage: 'Nenhuma ordem finalizada encontrada',
                        emptyIcon: Icons.check_circle_outline,
                      ),
                      _HistoricoList(
                        ordens: canceladas,
                        statusColor: AppTheme.error,
                        emptyMessage: 'Nenhuma ordem cancelada encontrada',
                        emptyIcon: Icons.cancel_outlined,
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

// ─────────────────────────────────────────────────────────────────────────────
// BOTÃO DE FILTRO DE DATA
// ─────────────────────────────────────────────────────────────────────────────

class _DateFilterBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _DateFilterBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? AppTheme.primary : AppTheme.textSecondary,
        side: BorderSide(
          color: active ? AppTheme.primary : AppTheme.divider,
        ),
        backgroundColor:
            active ? AppTheme.primary.withValues(alpha: 0.06) : null,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LISTA DE HISTÓRICO
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricoList extends StatelessWidget {
  final List<OrdemCompraModel> ordens;
  final Color statusColor;
  final String emptyMessage;
  final IconData emptyIcon;

  const _HistoricoList({
    required this.ordens,
    required this.statusColor,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (ordens.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 52, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text(emptyMessage,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: ordens.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _HistoricoCard(
        ordem: ordens[i],
        statusColor: statusColor,
        onVerDetalhes: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _HistoricoDetalhePage(ordem: ordens[i]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD DE HISTÓRICO (expansível)
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricoCard extends StatefulWidget {
  final OrdemCompraModel ordem;
  final Color statusColor;
  final VoidCallback onVerDetalhes;

  const _HistoricoCard({
    required this.ordem,
    required this.statusColor,
    required this.onVerDetalhes,
  });

  @override
  State<_HistoricoCard> createState() => _HistoricoCardState();
}

class _HistoricoCardState extends State<_HistoricoCard> {
  bool _hovered   = false;
  bool _expandido = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  String _formatData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final o = widget.ordem;
    final cor = widget.statusColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit: _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expandido = !_expandido),
        child: Container(
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFFFF9800).withValues(alpha: 0.06)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Barra colorida + linha principal ─────────────────────────
                Stack(
                  children: [
                    Positioned(
                        left: 0, top: 0, bottom: 0, width: 4,
                        child: ColoredBox(color: cor)),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 20, right: 16, top: 14, bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Título + total
                          Row(children: [
                            Expanded(
                              child: Text(
                                'OC #${o.id} — ${o.fornecedorNome ?? 'Fornecedor'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              _moeda(o.valorTotal),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: cor,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),

                          // Meta-info linha
                          Wrap(
                            spacing: 14,
                            runSpacing: 4,
                            children: [
                              if (o.requisitante.isNotEmpty)
                                _chip(Icons.person_outline, o.requisitante),
                              _chip(Icons.calendar_today_outlined,
                                  _formatData(o.data)),
                              if (o.empresa != null)
                                _chip(Icons.business_outlined, o.empresa!),
                              _chip(Icons.inventory_2_outlined,
                                  '${o.itens.length} ${o.itens.length == 1 ? 'item' : 'itens'}'),
                            ],
                          ),

                          // Números de OS
                          if (o.numerosOS.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              children: o.numerosOS
                                  .map((os) => _osBadge(os))
                                  .toList(),
                            ),
                          ],

                          const SizedBox(height: 10),

                          // Botões ação
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Expandir / recolher itens
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(
                                    () => _expandido = !_expandido),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _expandido
                                          ? 'Recolher itens'
                                          : 'Ver itens',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      _expandido
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      size: 16,
                                      color: AppTheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Ver detalhes completo
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.onVerDetalhes,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Ver detalhes',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(Icons.open_in_new,
                                        size: 13,
                                        color: AppTheme.textSecondary),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Itens expandidos ─────────────────────────────────────────
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _expandido
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, color: AppTheme.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Cabeçalho da seção
                            Row(children: [
                              const Icon(Icons.inventory_2_outlined,
                                  size: 14, color: AppTheme.primary),
                              const SizedBox(width: 5),
                              Text(
                                'Itens (${o.itens.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 10),

                            // Lista de itens
                            ...o.itens.map((item) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppTheme.divider),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.materialNome,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 3,
                                              children: [
                                                _itemChip(
                                                    Icons.assignment_outlined,
                                                    'OS: ${item.numeroOS}'),
                                                _itemChip(
                                                    Icons.format_list_numbered,
                                                    'Qtd: ${_fmtNum(item.quantidade)}'),
                                                _itemChip(
                                                    Icons.attach_money,
                                                    'Unit: ${_moeda(item.precoUnitario)}'),
                                                if (item.precoMetroQuadrado !=
                                                    null)
                                                  _itemChip(
                                                      Icons.square_foot,
                                                      'm²: ${_moeda(item.precoMetroQuadrado!)}'),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        _moeda(item.precoTotal),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: cor,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),

                            // Total
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: cor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: AppTheme.textPrimary)),
                                  Text(
                                    _moeda(o.valorTotal),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: cor),
                                  ),
                                ],
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
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ],
      );

  Widget _osBadge(String os) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(os,
            style: const TextStyle(
                fontSize: 11,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600)),
      );

  Widget _itemChip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textHint),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ],
      );

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE DETALHE COMPLETO
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricoDetalhePage extends StatelessWidget {
  final OrdemCompraModel ordem;
  const _HistoricoDetalhePage({required this.ordem});

  String _formatData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final o = ordem;
    final Color statusColor;
    final String statusLabel;
    switch (o.status) {
      case 'FINALIZADO':
        statusColor = AppTheme.success;
        statusLabel = 'Finalizada';
        break;
      case 'CANCELADO':
        statusColor = AppTheme.error;
        statusLabel = 'Cancelada';
        break;
      default:
        statusColor = AppTheme.primary;
        statusLabel = 'Em Andamento';
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(children: [
          Text(
            'OC #${o.id}',
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12),
            ),
          ),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Informações Gerais ─────────────────────────────────────────────
          _secaoCard('Informações Gerais', Icons.info_outline, [
            _infoRow(Icons.business_outlined, 'Fornecedor',
                o.fornecedorNome ?? '—'),
            _infoRow(Icons.person_outline, 'Requisitante',
                o.requisitante.isEmpty ? '—' : o.requisitante),
            _infoRow(Icons.apartment_outlined, 'Empresa', o.empresa ?? '—'),
            _infoRow(Icons.calendar_today_outlined, 'Data',
                _formatData(o.data)),
            _infoRow(Icons.payment_outlined, 'Forma de Pagamento',
                o.formaPagamento ?? '—'),
            _infoRow(Icons.schedule_outlined, 'Prazo de Pagamento',
                o.prazoPagamento ?? '—'),
            if (o.observacoes != null && o.observacoes!.isNotEmpty)
              _infoRow(Icons.notes_outlined, 'Observações', o.observacoes!),
          ]),
          const SizedBox(height: 16),

          // ── Números de OS ──────────────────────────────────────────────────
          if (o.numerosOS.isNotEmpty) ...[
            _secaoCard('Números de OS', Icons.assignment_outlined, [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: o.numerosOS
                    .map((os) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(os,
                              style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          // ── Itens ──────────────────────────────────────────────────────────
          _secaoCard('Itens (${o.itens.length})', Icons.inventory_2_outlined,
              [
            ...o.itens.map((item) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(item.materialNome,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary)),
                        ),
                        Text(
                          _moeda(item.precoTotal),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: statusColor),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        _itemChip(Icons.assignment_outlined,
                            'OS: ${item.numeroOS}'),
                        _itemChip(Icons.format_list_numbered,
                            'Qtd: ${_fmtNum(item.quantidade)}'),
                        _itemChip(Icons.attach_money,
                            'Unit: ${_moeda(item.precoUnitario)}'),
                        if (item.precoMetroQuadrado != null)
                          _itemChip(Icons.square_foot,
                              'm²: ${_moeda(item.precoMetroQuadrado!)}'),
                      ]),
                    ],
                  ),
                )),

            // Total
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.textPrimary)),
                    Text(
                      _moeda(o.valorTotal),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: statusColor),
                    ),
                  ]),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _secaoCard(
          String titulo, IconData icon, List<Widget> children) =>
      Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.textPrimary)),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.divider),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: AppTheme.textHint),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary)),
          ),
        ]),
      );

  Widget _itemChip(IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppTheme.textHint),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
      ]);
}