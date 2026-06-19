import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ordem_compra_model.dart';
import '../providers/ordem_compra_provider.dart';
import '../theme/app_theme.dart';

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
        if (isInicio) {
          _dataInicio = d;
        } else {
          _dataFim    = d;
        }
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<OrdemCompraProvider>(builder: (_, p, __) {
              final total = p.finalizadas.length + p.canceladas.length;
              return Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Histórico de Ordens',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '$total ${total == 1 ? 'ordem' : 'ordens'} no histórico',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Spacer(),
                  IconButton(
                    onPressed: () => context.read<OrdemCompraProvider>().carregar(),
                    icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    tooltip: 'Atualizar',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nº OC, fornecedor, empresa ou OS…',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                      suffixIcon: _filtroBusca.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  size: 18, color: Theme.of(context).colorScheme.outline),
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
                _DateFilterBtn(
                  label: _dataInicio != null
                      ? _formatData(_dataInicio!)
                      : 'De',
                  icon: Icons.calendar_today_outlined,
                  active: _dataInicio != null,
                  onTap: () => _selecionarData(isInicio: true),
                ),
                const SizedBox(width: 8),
                _DateFilterBtn(
                  label: _dataFim != null ? _formatData(_dataFim!) : 'Até',
                  icon: Icons.calendar_month_outlined,
                  active: _dataFim != null,
                  onTap: () => _selecionarData(isInicio: false),
                ),
                SizedBox(width: 8),
                if (_filtroBusca.isNotEmpty ||
                    _dataInicio != null ||
                    _dataFim != null)
                  IconButton.outlined(
                    tooltip: 'Limpar filtros',
                    icon: Icon(Icons.filter_alt_off),
                    onPressed: _limparFiltros,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border:
                    Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    final partes = prov.erro!.split(': ');
                    final subtitulo = partes.length > 1
                        ? partes.sublist(1).join(': ')
                        : prov.erro!;
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          SizedBox(height: 12),
                          Text(
                            'Erro ao carregar histórico',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            subtitulo,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () =>
                                context.read<OrdemCompraProvider>().carregar(),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary),
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
      label: Text(label, style: TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
        side: BorderSide(
          color: active ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
        ),
        backgroundColor:
            active ? AppTheme.primary.withValues(alpha: 0.06) : null,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

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
            Icon(emptyIcon, size: 52, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 12),
            Text(emptyMessage,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
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

  /// Formata preço unitário com até 6 casas decimais,
  /// removendo zeros à direita (ex: 0,500000 → 0,5 / 0,010000 → 0,01).
  String _moedaUnitario(double v) {
    final s = v.toStringAsFixed(6);
    final trimmed = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return 'R\$ ${trimmed.replaceAll('.', ',')}';
  }

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
                ? Color(0xFFFF9800).withValues(alpha: 0.06)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                          Row(children: [
                            Expanded(
                              child: Text(
                                'OC #${o.id} — ${o.fornecedorNome ?? 'Fornecedor'}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Theme.of(context).colorScheme.onSurface,
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

                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
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
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.onVerDetalhes,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Ver detalhes',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(width: 3),
                                    Icon(Icons.open_in_new,
                                        size: 13,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant),
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

                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _expandido
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.inventory_2_outlined,
                                  size: 14, color: AppTheme.primary),
                              SizedBox(width: 5),
                              Text(
                                'Itens (${o.itens.length})',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ]),
                            SizedBox(height: 10),

                            ...o.itens.map((item) => Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Theme.of(context).colorScheme.outlineVariant),
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
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                            if (item.descricaoItem != null &&
                                                item.descricaoItem!.isNotEmpty) ...[
                                              SizedBox(height: 2),
                                              Text(
                                                item.descricaoItem!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
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
                                                    'Quantidade: ${_fmtNum(item.quantidade)}'),
                                                _itemChipDestaque(
                                                    Icons.attach_money,
                                                    'Unitário: ${_moedaUnitario(item.precoUnitario)}',
                                                    ativo: !item.usarM2),
                                                if (item.precoMetroQuadrado != null)
                                                  _itemChipDestaque(
                                                      Icons.square_foot,
                                                      'm²: ${_moedaUnitario(item.precoMetroQuadrado!)}',
                                                      ativo: item.usarM2),
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
                                  Text('Total',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface)),
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
          Icon(icon, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
          SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _itemChipDestaque(IconData icon, String label, {required bool ativo}) {
    if (!ativo) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
        SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppTheme.primary),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}

class _HistoricoDetalhePage extends StatelessWidget {
  final OrdemCompraModel ordem;
  const _HistoricoDetalhePage({required this.ordem});

  String _formatData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _moeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  /// Formata preço unitário com até 6 casas decimais,
  /// removendo zeros à direita (ex: 0,500000 → 0,5 / 0,010000 → 0,01).
  String _moedaUnitario(double v) {
    final s = v.toStringAsFixed(6);
    final trimmed = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return 'R\$ ${trimmed.replaceAll('.', ',')}';
  }

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(children: [
          Text(
            'OC #${o.id}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurface),
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
          _secaoCard(context, 'Informações Gerais', Icons.info_outline, [
            _infoRow(context, Icons.business_outlined, 'Fornecedor',
                o.fornecedorNome ?? '—'),
            _infoRow(context, Icons.person_outline, 'Requisitante',
                o.requisitante.isEmpty ? '—' : o.requisitante),
            _infoRow(context, Icons.apartment_outlined, 'Empresa', o.empresa ?? '—'),
            _infoRow(context, Icons.calendar_today_outlined, 'Data',
                _formatData(o.data)),
            _infoRow(context, Icons.payment_outlined, 'Forma de Pagamento',
                o.formaPagamento ?? '—'),
            _infoRow(context, Icons.schedule_outlined, 'Prazo de Pagamento',
                o.prazoPagamento ?? '—'),
            if (o.observacoes != null && o.observacoes!.isNotEmpty)
              _infoRow(context, Icons.notes_outlined, 'Observações', o.observacoes!),
          ]),
          const SizedBox(height: 16),

          if (o.numerosOS.isNotEmpty) ...[
            _secaoCard(context, 'Números de OS', Icons.assignment_outlined, [
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
            SizedBox(height: 16),
          ],

          _secaoCard(context, 'Itens (${o.itens.length})', Icons.inventory_2_outlined,
              [
            ...o.itens.map((item) => Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(item.materialNome,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface)),
                        ),
                        Text(
                          _moeda(item.precoTotal),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: statusColor),
                        ),
                      ]),
                      if (item.descricaoItem != null &&
                          item.descricaoItem!.isNotEmpty) ...[
                        SizedBox(height: 3),
                        Text(
                          item.descricaoItem!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        _itemChip(context, Icons.assignment_outlined,
                            'OS: ${item.numeroOS}'),
                        _itemChip(context, Icons.format_list_numbered,
                            'Quantidade: ${_fmtNum(item.quantidade)}'),
                        _itemChipDestaque(context, Icons.attach_money,
                            'Unitário: ${_moedaUnitario(item.precoUnitario)}',
                            ativo: !item.usarM2),
                        if (item.precoMetroQuadrado != null)
                          _itemChipDestaque(context, Icons.square_foot,
                              'm²: ${_moedaUnitario(item.precoMetroQuadrado!)}',
                              ativo: item.usarM2),
                      ]),
                    ],
                  ),
                )),

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
                    Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface)),
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
          BuildContext context, String titulo, IconData icon, List<Widget> children) =>
      Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: AppTheme.primary),
              SizedBox(width: 6),
              Text(titulo,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface)),
            ]),
            SizedBox(height: 12),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _infoRow(BuildContext context, IconData icon, String label, String value) => Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: Theme.of(context).colorScheme.outline),
          SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface)),
          ),
        ]),
      );

  Widget _itemChip(BuildContext context, IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
        SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);

  Widget _itemChipDestaque(BuildContext context, IconData icon, String label, {required bool ativo}) {
    if (!ativo) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
        SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppTheme.primary),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}