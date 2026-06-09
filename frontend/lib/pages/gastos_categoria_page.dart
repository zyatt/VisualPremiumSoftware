import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/gastos_categoria_model.dart';
import '../models/veiculo_model.dart';
import '../providers/gastos_categoria_provider.dart';
import '../providers/veiculo_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _brl(double v) =>
    v == 0 ? '—' : 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

String _fmtQtd(double q) =>
    q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

const _corEntrada = Color(0xFF1E88E5);
const _corSaida   = Color(0xFFE53935);
const _corVeiculo = Color(0xFFF4511E);

const _coresCat = [
  Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
  Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
  Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
  Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
];

Color _corCategoria(int index) => _coresCat[index % _coresCat.length];

// ═════════════════════════════════════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class GastosCategoriaPage extends StatefulWidget {
  const GastosCategoriaPage({super.key});

  @override
  State<GastosCategoriaPage> createState() => _GastosCategoriaPageState();
}

class _GastosCategoriaPageState extends State<GastosCategoriaPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl =
      TabController(length: 2, vsync: this);

  DateTime? _dataInicio;
  DateTime? _dataFim;

  // Para o resumo anual de veículos
  int _anoSelecionado = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarAcessoECarregar();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _verificarAcessoECarregar() {
    final role = context
            .read<UsuarioProvider>()
            .usuarioLogado
            ?.role
            .trim()
            .toUpperCase() ??
        '';
    if (role != 'ADMIN') return;
    context.read<GastosCategoriaProvider>().carregar();
    context.read<VeiculoProvider>().carregarGastos();
    context.read<VeiculoProvider>().carregarResumoAnual(ano: _anoSelecionado);
  }

  void _aplicarFiltros() {
    context.read<GastosCategoriaProvider>().carregar(
          dataInicio: _dataInicio,
          dataFim:    _dataFim,
        );
    context.read<VeiculoProvider>().carregarGastos(
          dataInicio: _dataInicio,
          dataFim:    _dataFim,
        );
  }

  bool get _temFiltro => _dataInicio != null || _dataFim != null;

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim    = null;
    });
    _aplicarFiltros();
  }

  @override
  Widget build(BuildContext context) {
    final role = context
            .watch<UsuarioProvider>()
            .usuarioLogado
            ?.role
            .trim()
            .toUpperCase() ??
        '';

    if (role != 'ADMIN') {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppTheme.textHint),
              const SizedBox(height: 16),
              Text('Acesso restrito',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text('Apenas administradores podem visualizar esta página.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    final matProvider = context.watch<GastosCategoriaProvider>();
    final veiProvider = context.watch<VeiculoProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ─────────────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gastos',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Materiais e veículos — visão geral de gastos',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    matProvider.recarregar();
                    veiProvider.carregarGastos(
                        dataInicio: _dataInicio, dataFim: _dataFim);
                    veiProvider.carregarResumoAnual(ano: _anoSelecionado);
                  },
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

            // ── Filtro de período ──────────────────────────────────────────
            Row(
              children: [
                _DatePickerField(
                  label:     'De',
                  value:     _dataInicio,
                  firstDate: DateTime(2020),
                  lastDate:  _dataFim ?? DateTime.now(),
                  onPicked: (d) {
                    setState(() => _dataInicio = d);
                    _aplicarFiltros();
                  },
                  onCleared: () {
                    setState(() => _dataInicio = null);
                    _aplicarFiltros();
                  },
                ),
                const SizedBox(width: 12),
                _DatePickerField(
                  label:     'até',
                  value:     _dataFim,
                  firstDate: _dataInicio ?? DateTime(2020),
                  lastDate:  DateTime.now(),
                  onPicked: (d) {
                    setState(() => _dataFim = d);
                    _aplicarFiltros();
                  },
                  onCleared: () {
                    setState(() => _dataFim = null);
                    _aplicarFiltros();
                  },
                ),
                if (_temFiltro) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _limparFiltros,
                    icon:  const Icon(Icons.filter_alt_off, size: 16),
                    label: const Text('Limpar filtro'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary),
                  ),
                ],
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),

            // ── Resumo geral (totais de ambas abas) ───────────────────────
            if (!matProvider.carregando &&
                !veiProvider.carregandoGastos &&
                (matProvider.categorias.isNotEmpty ||
                    veiProvider.gastos.isNotEmpty))
              _ResumoGeralGlobal(
                totalMateriais: matProvider.totalSaidaGeral +
                    matProvider.totalEntradaGeral,
                totalVeiculos: veiProvider.totalGastosGeral,
              ),

            const SizedBox(height: 16),

            // ── Abas ──────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color:        AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppTheme.divider),
              ),
              child: TabBar(
                controller:        _tabCtrl,
                indicatorSize:     TabBarIndicatorSize.tab,
                indicatorColor:    AppTheme.primary,
                labelColor:        AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                dividerColor:      Colors.transparent,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.category_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('Materiais'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_car_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('Veículos'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Conteúdo das abas ─────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // ─── ABA MATERIAIS ──────────────────────────────────────
                  _AbaMateirais(
                    provider: matProvider,
                    temFiltro: _temFiltro,
                  ),

                  // ─── ABA VEÍCULOS ───────────────────────────────────────
                  _AbaVeiculos(
                    provider:         veiProvider,
                    anoSelecionado:    _anoSelecionado,
                    onAnoChanged: (ano) {
                      setState(() => _anoSelecionado = ano);
                      veiProvider.carregarResumoAnual(ano: ano);
                    },
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

// ─────────────────────────────────────────────────────────────────────────────
// Resumo global (cards compactos no topo)
// ─────────────────────────────────────────────────────────────────────────────

class _ResumoGeralGlobal extends StatelessWidget {
  final double totalMateriais;
  final double totalVeiculos;

  const _ResumoGeralGlobal({
    required this.totalMateriais,
    required this.totalVeiculos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        border:       Border.all(color: AppTheme.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.bar_chart_rounded,
              size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text('Totais gerais',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary)),
          const Spacer(),
          _TotalBadge(
            label: 'Materiais',
            valor: totalMateriais,
            cor:   _corEntrada,
            icone: Icons.category_rounded,
          ),
          const SizedBox(width: 24),
          _TotalBadge(
            label: 'Veículos',
            valor: totalVeiculos,
            cor:   _corVeiculo,
            icone: Icons.directions_car_rounded,
          ),
          const SizedBox(width: 24),
          _TotalBadge(
            label: 'Total geral',
            valor: totalMateriais + totalVeiculos,
            cor:   const Color(0xFF43A047),
            icone: Icons.attach_money_rounded,
          ),
        ],
      ),
    );
  }
}

class _TotalBadge extends StatelessWidget {
  final String   label;
  final double   valor;
  final Color    cor;
  final IconData icone;

  const _TotalBadge({
    required this.label,
    required this.valor,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 14, color: cor),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary)),
            Text(_brl(valor),
                style: TextStyle(
                    fontSize:   15,
                    fontWeight: FontWeight.w700,
                    color:      cor)),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Aba Materiais
// ═════════════════════════════════════════════════════════════════════════════

class _AbaMateirais extends StatelessWidget {
  final GastosCategoriaProvider provider;
  final bool                    temFiltro;

  const _AbaMateirais({required this.provider, required this.temFiltro});

  @override
  Widget build(BuildContext context) {
    if (provider.carregando) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (provider.erro != null) {
      return Center(
          child: Text('Erro: ${provider.erro}',
              style: const TextStyle(color: AppTheme.error)));
    }
    if (provider.categorias.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined,
                size: 56, color: AppTheme.textHint.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('Nenhum dado encontrado',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppTheme.textHint)),
            const SizedBox(height: 4),
            Text(
              temFiltro
                  ? 'Tente ajustar o período'
                  : 'Ainda não há OS fechadas com movimentações',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textHint.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );
    }

    // Totalizadores da aba
    return Column(
      children: [
        _ResumoMateirais(
          totalEntrada: provider.totalEntradaGeral,
          totalSaida:   provider.totalSaidaGeral,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount:       provider.categorias.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _CategoriaCard(
              gasto: provider.categorias[i],
              cor:   _corCategoria(i),
              index: i,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResumoMateirais extends StatelessWidget {
  final double totalEntrada;
  final double totalSaida;

  const _ResumoMateirais(
      {required this.totalEntrada, required this.totalSaida});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        border:       Border.all(color: AppTheme.divider),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Text('Subtotais materiais',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const Spacer(),
          _TotalBadge(
            label: 'Entradas',
            valor: totalEntrada,
            cor:   _corEntrada,
            icone: Icons.arrow_downward_rounded,
          ),
          const SizedBox(width: 20),
          _TotalBadge(
            label: 'Saídas',
            valor: totalSaida,
            cor:   _corSaida,
            icone: Icons.arrow_upward_rounded,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Aba Veículos
// ═════════════════════════════════════════════════════════════════════════════

class _AbaVeiculos extends StatelessWidget {
  final VeiculoProvider provider;
  final int             anoSelecionado;
  final ValueChanged<int> onAnoChanged;

  const _AbaVeiculos({
    required this.provider,
    required this.anoSelecionado,
    required this.onAnoChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (provider.carregandoGastos) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Resumo anual ───────────────────────────────────────────────
          _ResumoAnualCard(
            provider:       provider,
            anoSelecionado: anoSelecionado,
            onAnoChanged:   onAnoChanged,
          ),
          const SizedBox(height: 20),

          // ── Lista por veículo ──────────────────────────────────────────
          if (provider.gastos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_car_outlined,
                        size: 56,
                        color: AppTheme.textHint.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text('Nenhum gasto com veículos encontrado',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppTheme.textHint)),
                  ],
                ),
              ),
            )
          else ...[
            Text('Gastos por veículo',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            ...provider.gastos.asMap().entries.map((e) {
              final i = e.key;
              final g = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GastoVeiculoCard(
                  gasto: g,
                  cor:   _corCategoria(i),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ── Resumo anual com gráfico de barras mensal ─────────────────────────────────

class _ResumoAnualCard extends StatelessWidget {
  final VeiculoProvider   provider;
  final int               anoSelecionado;
  final ValueChanged<int> onAnoChanged;

  const _ResumoAnualCard({
    required this.provider,
    required this.anoSelecionado,
    required this.onAnoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final resumo = provider.resumoAnual;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        border:       Border.all(color: AppTheme.divider),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho com seletor de ano
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 18, color: _corVeiculo),
              const SizedBox(width: 8),
              Text('Gastos anuais com veículos',
                  style: const TextStyle(
                    fontSize:   14,
                    fontWeight: FontWeight.w700,
                    color:      AppTheme.textPrimary,
                  )),
              const Spacer(),
              // Seletor de ano
              Row(
                children: [
                  IconButton(
                    onPressed: () => onAnoChanged(anoSelecionado - 1),
                    icon: const Icon(Icons.chevron_left, size: 20),
                    color:   AppTheme.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                  Text(
                    '$anoSelecionado',
                    style: const TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w700,
                      color:      AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: anoSelecionado < DateTime.now().year
                        ? () => onAnoChanged(anoSelecionado + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right, size: 20),
                    color:   AppTheme.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (provider.carregandoResumo)
            const SizedBox(
              height: 80,
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2)),
            )
          else if (resumo == null || resumo.totalAnual == 0)
            SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  'Sem gastos em $anoSelecionado',
                  style: const TextStyle(
                      color: AppTheme.textHint, fontSize: 13),
                ),
              ),
            )
          else ...[
            // Total do ano
            Row(
              children: [
                Text('Total em $anoSelecionado:',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
                const SizedBox(width: 8),
                Text(_brl(resumo.totalAnual),
                    style: TextStyle(
                      fontSize:   18,
                      fontWeight: FontWeight.w800,
                      color:      _corVeiculo,
                    )),
              ],
            ),
            const SizedBox(height: 16),

            // Gráfico de barras mensal
            _GraficoMensal(porMes: resumo.porMes),
          ],
        ],
      ),
    );
  }
}

class _GraficoMensal extends StatelessWidget {
  final List<ResumoMensalVeiculoModel> porMes;

  const _GraficoMensal({required this.porMes});

  @override
  Widget build(BuildContext context) {
    if (porMes.isEmpty) return const SizedBox.shrink();
    final maxVal = porMes
        .map((m) => m.totalGasto)
        .fold(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: porMes.map((m) {
          final frac = maxVal > 0 ? m.totalGasto / maxVal : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (m.totalGasto > 0)
                    Text(
                      'R\$${(m.totalGasto / 1000 >= 1 ? '${(m.totalGasto / 1000).toStringAsFixed(1)}k' : m.totalGasto.toStringAsFixed(0))}',
                      style: TextStyle(
                          fontSize: 9,
                          color:    _corVeiculo.withValues(alpha: 0.8)),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height:   (frac * 72).clamp(2.0, 72.0),
                    decoration: BoxDecoration(
                      color:        m.totalGasto > 0
                          ? _corVeiculo
                          : AppTheme.divider,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(m.label,
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textSecondary),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Card de gasto por veículo (expansível) ────────────────────────────────────

class _GastoVeiculoCard extends StatefulWidget {
  final GastoVeiculoModel gasto;
  final Color             cor;

  const _GastoVeiculoCard({required this.gasto, required this.cor});

  @override
  State<_GastoVeiculoCard> createState() => _GastoVeiculoCardState();
}

class _GastoVeiculoCardState extends State<_GastoVeiculoCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final g   = widget.gasto;
    final cor = widget.cor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        border:       Border.all(
          color: _expandido ? cor.withValues(alpha: 0.4) : AppTheme.divider,
          width: _expandido ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(14),
              topRight:    const Radius.circular(14),
              bottomLeft:  Radius.circular(_expandido ? 0 : 14),
              bottomRight: Radius.circular(_expandido ? 0 : 14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color:        cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.directions_car_rounded,
                        color: cor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.nome,
                            style: const TextStyle(
                              fontSize:   15,
                              fontWeight: FontWeight.w700,
                              color:      AppTheme.textPrimary,
                            )),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color:        cor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: cor.withValues(alpha: 0.2)),
                              ),
                              child: Text(g.placa,
                                  style: TextStyle(
                                    fontSize:   11,
                                    fontWeight: FontWeight.w700,
                                    color:      cor,
                                    letterSpacing: 1,
                                  )),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${g.qtdServicos} ${g.qtdServicos == 1 ? 'serviço' : 'serviços'}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:        _corVeiculo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _corVeiculo.withValues(alpha: 0.25)),
                    ),
                    child: Text(_brl(g.totalGasto),
                        style: const TextStyle(
                          fontSize:   14,
                          fontWeight: FontWeight.w700,
                          color:      _corVeiculo,
                        )),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns:    _expandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (_expandido) ...[
            const Divider(height: 1, color: AppTheme.divider),
            _TabelaServicos(servicos: g.servicos, cor: cor),
          ],
        ],
      ),
    );
  }
}

class _TabelaServicos extends StatelessWidget {
  final List<GastoServicoModel> servicos;
  final Color                   cor;

  const _TabelaServicos({required this.servicos, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...servicos.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color:        cor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          _iconeTipo(s.tipo),
                          color: cor,
                          size:  16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(labelTipo(s.tipo),
                                style: const TextStyle(
                                  fontSize:   13,
                                  fontWeight: FontWeight.w600,
                                  color:      AppTheme.textPrimary,
                                )),
                            if (s.descricao != null &&
                                s.descricao!.isNotEmpty)
                              Text(s.descricao!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary)),
                            Text(
                              s.dataRetirada != null
                                  ? '${_fmtData(s.dataEnvio)} → ${_fmtData(s.dataRetirada)}'
                                  : 'Envio: ${_fmtData(s.dataEnvio)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Text(_brl(s.valor),
                          style: const TextStyle(
                            fontSize:   13,
                            fontWeight: FontWeight.w700,
                            color:      _corVeiculo,
                          )),
                    ],
                  ),
                ),
                if (i < servicos.length - 1)
                  const Divider(height: 1, color: AppTheme.divider),
              ],
            );
          }),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Total do veículo:',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(width: 8),
              Text(
                _brl(servicos.fold(0.0, (s, m) => s + m.valor)),
                style: const TextStyle(
                  fontSize:   14,
                  fontWeight: FontWeight.w800,
                  color:      _corVeiculo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _iconeTipo(String tipo) {
  switch (tipo) {
    case 'MANUTENCAO': return Icons.build_rounded;
    case 'LIMPEZA':    return Icons.cleaning_services_rounded;
    case 'REVISAO':    return Icons.fact_check_rounded;
    case 'PNEU':       return Icons.tire_repair_rounded;
    default:           return Icons.miscellaneous_services_rounded;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Card de categoria de material (reutilizado da versão anterior)
// ═════════════════════════════════════════════════════════════════════════════

class _CategoriaCard extends StatefulWidget {
  final GastoCategoriaModel gasto;
  final Color               cor;
  final int                 index;

  const _CategoriaCard({
    required this.gasto,
    required this.cor,
    required this.index,
  });

  @override
  State<_CategoriaCard> createState() => _CategoriaCardState();
}

class _CategoriaCardState extends State<_CategoriaCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final g   = widget.gasto;
    final cor = widget.cor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        border:       Border.all(
          color: _expandido ? cor.withValues(alpha: 0.4) : AppTheme.divider,
          width: _expandido ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: _expandido
            ? [
                BoxShadow(
                  color:      cor.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset:     const Offset(0, 4),
                )
              ]
            : [],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(14),
              topRight:    const Radius.circular(14),
              bottomLeft:  Radius.circular(_expandido ? 0 : 14),
              bottomRight: Radius.circular(_expandido ? 0 : 14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color:        cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.category_rounded, color: cor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.categoriaLabel,
                            style: const TextStyle(
                              fontSize:   15,
                              fontWeight: FontWeight.w700,
                              color:      AppTheme.textPrimary,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          '${g.materiais.length} '
                          '${g.materiais.length == 1 ? 'material' : 'materiais'}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _PillValor(
                    label: 'Entrada',
                    valor: g.totalEntrada,
                    cor:   _corEntrada,
                    icone: Icons.arrow_downward_rounded,
                  ),
                  const SizedBox(width: 12),
                  _PillValor(
                    label: 'Saída',
                    valor: g.totalSaida,
                    cor:   _corSaida,
                    icone: Icons.arrow_upward_rounded,
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns:    _expandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (_expandido) ...[
            const Divider(height: 1, color: AppTheme.divider),
            _TabelaMateriais(materiais: g.materiais, cor: cor),
          ],
        ],
      ),
    );
  }
}

class _PillValor extends StatelessWidget {
  final String   label;
  final double   valor;
  final Color    cor;
  final IconData icone;

  const _PillValor({
    required this.label,
    required this.valor,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:        cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 12, color: cor),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: cor.withValues(alpha: 0.8))),
              Text(_brl(valor),
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      cor,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabelaMateriais extends StatelessWidget {
  final List<GastoMaterialModel> materiais;
  final Color                    cor;

  const _TabelaMateriais({required this.materiais, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('Material',
                      style: TextStyle(
                        fontSize:   11,
                        fontWeight: FontWeight.w600,
                        color:      AppTheme.textSecondary,
                      )),
                ),
                _HeaderCol('Qtd. Entrada', align: TextAlign.right),
                const SizedBox(width: 8),
                _HeaderCol('Valor Entrada',
                    cor: _corEntrada, align: TextAlign.right),
                const SizedBox(width: 16),
                _HeaderCol('Qtd. Saída', align: TextAlign.right),
                const SizedBox(width: 8),
                _HeaderCol('Valor Saído',
                    cor: _corSaida, align: TextAlign.right),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 4),
          ...materiais.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            return _LinhaMateria(
              material: m,
              cor:      cor,
              ultimo:   i == materiais.length - 1,
            );
          }),
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text('Subtotal',
                    style: TextStyle(
                      fontSize:   12,
                      fontWeight: FontWeight.w600,
                      color:      AppTheme.textSecondary,
                    )),
              ),
              const SizedBox(width: 70),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(
                  _brl(materiais.fold(
                      0.0, (s, m) => s + m.totalEntrada)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      _corEntrada,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const SizedBox(width: 70),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(
                  _brl(materiais.fold(0.0, (s, m) => s + m.totalSaida)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      _corSaida,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCol extends StatelessWidget {
  final String    text;
  final Color?    cor;
  final TextAlign align;

  const _HeaderCol(this.text, {this.cor, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cor != null ? 100 : 70,
      child: Text(text,
          textAlign: align,
          style: TextStyle(
            fontSize:   11,
            fontWeight: FontWeight.w600,
            color:      cor ?? AppTheme.textSecondary,
          )),
    );
  }
}

class _LinhaMateria extends StatelessWidget {
  final GastoMaterialModel material;
  final Color              cor;
  final bool               ultimo;

  const _LinhaMateria({
    required this.material,
    required this.cor,
    required this.ultimo,
  });

  @override
  Widget build(BuildContext context) {
    final m        = material;
    final detalhes = [
      if (m.identificador != null && m.identificador!.isNotEmpty)
        m.identificador!,
      if (m.medida    != null && m.medida!.isNotEmpty)    m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
    ].join(' · ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nome,
                        style: const TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w500,
                          color:      AppTheme.textPrimary,
                        )),
                    if (detalhes.isNotEmpty)
                      Text(detalhes,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  m.qtdEntrada > 0
                      ? '${_fmtQtd(m.qtdEntrada)} ${m.unidade ?? ''}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: m.qtdEntrada > 0
                        ? AppTheme.textPrimary
                        : AppTheme.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(_brl(m.totalEntrada),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: m.totalEntrada > 0
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: m.totalEntrada > 0
                          ? _corEntrada
                          : AppTheme.textHint,
                    )),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 70,
                child: Text(
                  m.qtdSaida > 0
                      ? '${_fmtQtd(m.qtdSaida)} ${m.unidade ?? ''}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: m.qtdSaida > 0
                        ? AppTheme.textPrimary
                        : AppTheme.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(_brl(m.totalSaida),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: m.totalSaida > 0
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: m.totalSaida > 0
                          ? _corSaida
                          : AppTheme.textHint,
                    )),
              ),
            ],
          ),
        ),
        if (!ultimo)
          const Divider(height: 1, color: AppTheme.divider),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seletor de data
// ─────────────────────────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String             label;
  final DateTime?          value;
  final DateTime           firstDate;
  final DateTime           lastDate;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback           onCleared;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onPicked,
    required this.onCleared,
  });

  Future<void> _pick(BuildContext context) async {
    final now     = DateTime.now();
    final initial = value != null
        ? (value!.isAfter(lastDate) ? lastDate : value!)
        : (now.isBefore(lastDate) ? now : lastDate);
    final picked = await showDatePicker(
      context:     context,
      initialDate: initial,
      firstDate:   firstDate,
      lastDate:    lastDate,
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:        AppTheme.surface,
          border:       Border.all(
            color: hasValue ? AppTheme.primary : AppTheme.divider,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today,
                size:  16,
                color: hasValue ? AppTheme.primary : AppTheme.textHint),
            const SizedBox(width: 6),
            Text(
              hasValue
                  ? '$label: ${_fmtData(value)}'
                  : label,
              style: TextStyle(
                fontSize:   13,
                color:      hasValue ? AppTheme.primary : AppTheme.textHint,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (hasValue) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onCleared,
                child: const Icon(Icons.close,
                    size: 14, color: AppTheme.textHint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}