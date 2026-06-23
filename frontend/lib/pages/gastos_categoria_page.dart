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

const _corGasto    = Color(0xFFE53935);
const _corEstoque  = Color(0xFF1E88E5);
const _corVeiculo  = Color(0xFFF4511E);
const _corPositivo = Color(0xFF43A047);

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
  late final TabController _tabCtrl = TabController(length: 3, vsync: this);

  DateTime? _dataInicio;
  DateTime? _dataFim;
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
    final prov = context.read<GastosCategoriaProvider>();
    prov.carregarEstoque();
    prov.carregarGastos();
    prov.carregarMensal();
    context.read<VeiculoProvider>().carregarGastos();
    context.read<VeiculoProvider>().carregarResumoAnual(ano: _anoSelecionado);
  }

  void _aplicarFiltros() {
    context.read<GastosCategoriaProvider>().carregarGastos(
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text('Acesso restrito',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text('Apenas administradores podem visualizar esta página.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final matProvider = context.watch<GastosCategoriaProvider>();
    final veiProvider = context.watch<VeiculoProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface)),
                    const SizedBox(height: 2),
                    Text('Estoque atual, gastos e veículos',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    matProvider.carregarEstoque();
                    matProvider.recarregarGastos();
                    veiProvider.carregarGastos(
                        dataInicio: _dataInicio, dataFim: _dataFim);
                    veiProvider.carregarResumoAnual(ano: _anoSelecionado);
                  },
                  icon: Icon(Icons.refresh,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(
                        color:
                            Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Filtro de período (só afeta Gastos e Veículos) ────────────
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
                        foregroundColor:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),

            // ── Resumo global (3 números compactos no topo) ───────────────
            if (!matProvider.carregandoEstoque &&
                !matProvider.carregandoGastos &&
                !veiProvider.carregandoGastos)
              _ResumoGeralGlobal(
                totalEstoque:  matProvider.totalValorEstoque,
                totalGastos:   matProvider.totalGastos,
                totalVeiculos: veiProvider.totalGastosGeral,
              ),

            const SizedBox(height: 16),

            // ── Abas ──────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color:        Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: TabBar(
                controller:           _tabCtrl,
                indicatorSize:        TabBarIndicatorSize.tab,
                indicatorColor:       AppTheme.primary,
                labelColor:           AppTheme.primary,
                unselectedLabelColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Estoque'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Gastos'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_car_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Veículos'),
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
                  // ─── ABA ESTOQUE ─────────────────────────────────────
                  _AbaEstoque(provider: matProvider),

                  // ─── ABA GASTOS ──────────────────────────────────────
                  _AbaGastos(
                    provider:  matProvider,
                    temFiltro: _temFiltro,
                  ),

                  // ─── ABA VEÍCULOS ────────────────────────────────────
                  _AbaVeiculos(
                    provider:      veiProvider,
                    anoSelecionado: _anoSelecionado,
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
// Resumo global (3 cards compactos no topo)
// ─────────────────────────────────────────────────────────────────────────────

class _ResumoGeralGlobal extends StatelessWidget {
  final double totalEstoque;
  final double totalGastos;
  final double totalVeiculos;

  const _ResumoGeralGlobal({
    required this.totalEstoque,
    required this.totalGastos,
    required this.totalVeiculos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color:        Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.bar_chart_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text('Resumo',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant)),
          const Spacer(),
          _TotalBadge(
            label: 'Valor em estoque',
            valor: totalEstoque,
            cor:   _corEstoque,
            icone: Icons.inventory_2_rounded,
          ),
          const SizedBox(width: 24),
          _TotalBadge(
            label: 'Gastos (materiais)',
            valor: totalGastos,
            cor:   _corGasto,
            icone: Icons.category_rounded,
          ),
          const SizedBox(width: 24),
          _TotalBadge(
            label: 'Gastos (veículos)',
            valor: totalVeiculos,
            cor:   _corVeiculo,
            icone: Icons.directions_car_rounded,
          ),
          const SizedBox(width: 24),
          _TotalBadge(
            label: 'Total geral',
            valor: totalGastos + totalVeiculos,
            cor:   _corPositivo,
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
                style: TextStyle(
                    fontSize: 11,
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant)),
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
// ABA 1 — ESTOQUE ATUAL
// ═════════════════════════════════════════════════════════════════════════════

class _AbaEstoque extends StatefulWidget {
  final GastosCategoriaProvider provider;
  const _AbaEstoque({required this.provider});

  @override
  State<_AbaEstoque> createState() => _AbaEstoqueState();
}

class _AbaEstoqueState extends State<_AbaEstoque> {
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = widget.provider;

    if (prov.carregandoEstoque) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (prov.erroEstoque != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            Text('Erro ao carregar estoque',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 4),
            Text(prov.erroEstoque!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: prov.carregarEstoque,
              icon:  const Icon(Icons.refresh, size: 18),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }

    if (prov.estoque.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 56,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('Nenhum material ativo encontrado',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }

    final busca = _busca.trim().toLowerCase();
    final comIndice = prov.estoque.asMap().entries.toList();
    final filtradas = busca.isEmpty
        ? comIndice
        : comIndice
            .where((e) =>
                e.value.categoriaLabel.toLowerCase().contains(busca) ||
                e.value.materiais.any((m) =>
                    m.nome.toLowerCase().contains(busca)))
            .toList();

    // Total de materiais sem custo cadastrado
    final semCusto = prov.estoque
        .expand((c) => c.materiais)
        .where((m) => m.semCusto)
        .length;

    return CustomScrollView(
      slivers: [
        // Card de resumo
        SliverToBoxAdapter(
          child: _ResumoEstoque(
            totalValor: prov.totalValorEstoque,
            semCusto:   semCusto,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Título + busca
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text('Valor por categoria',
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.2,
                    )),
                const Spacer(),
                SizedBox(
                  width: 240,
                  height: 36,
                  child: TextField(
                    controller: _buscaCtrl,
                    onChanged:  (v) => setState(() => _busca = v),
                    style: TextStyle(
                        fontSize: 13,
                        color:
                            Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      isDense:  true,
                      hintText: 'Filtrar por categoria ou material...',
                      hintStyle: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline),
                      prefixIcon: Icon(Icons.search,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline),
                      prefixIconConstraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                      suffixIcon: _busca.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline),
                              onPressed: () {
                                _buscaCtrl.clear();
                                setState(() => _busca = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      filled:     true,
                      fillColor:
                          Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppTheme.primary, width: 1.5)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (filtradas.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                    'Nenhuma categoria encontrada para "$_busca"',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final entry = filtradas[i];
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: i < filtradas.length - 1 ? 12 : 0),
                  child: _EstoqueCategoriaCard(
                    categoria: entry.value,
                    cor:       _corCategoria(entry.key),
                    busca:     busca,
                  ),
                );
              },
              childCount: filtradas.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class _ResumoEstoque extends StatelessWidget {
  final double totalValor;
  final int    semCusto;

  const _ResumoEstoque(
      {required this.totalValor, required this.semCusto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_rounded,
              size: 16, color: _corEstoque),
          const SizedBox(width: 8),
          Text('Total em estoque',
              style: TextStyle(
                  fontSize: 13,
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant)),
          const Spacer(),
          if (semCusto > 0)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Tooltip(
                message:
                    '$semCusto ${semCusto == 1 ? 'material sem' : 'materiais sem'} custo cadastrado — valor subestimado',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.orange.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '$semCusto sem custo',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade600),
                    ),
                  ],
                ),
              ),
            ),
          Text(_brl(totalValor),
              style: TextStyle(
                fontSize:   20,
                fontWeight: FontWeight.w800,
                color:      _corEstoque,
              )),
        ],
      ),
    );
  }
}

class _EstoqueCategoriaCard extends StatefulWidget {
  final EstoqueCategoriaModel categoria;
  final Color                 cor;
  final String                busca;

  const _EstoqueCategoriaCard({
    required this.categoria,
    required this.cor,
    required this.busca,
  });

  @override
  State<_EstoqueCategoriaCard> createState() =>
      _EstoqueCategoriaCardState();
}

class _EstoqueCategoriaCardState extends State<_EstoqueCategoriaCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final cat      = widget.categoria;
    final cor      = widget.cor;
    final materiais = widget.busca.isNotEmpty
        ? cat.materiais
            .where((m) =>
                m.nome.toLowerCase().contains(widget.busca) ||
                (m.identificador ?? '')
                    .toLowerCase()
                    .contains(widget.busca))
            .toList()
        : cat.materiais;

    return Container(
      decoration: BoxDecoration(
        color:        Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // ── Cabeçalho da categoria ──────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
                bottom: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: cor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cat.categoriaLabel,
                      style: TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${cat.qtdMateriais} ${cat.qtdMateriais == 1 ? 'material' : 'materiais'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _brl(cat.totalValor),
                    style: TextStyle(
                        fontSize:   15,
                        fontWeight: FontWeight.w700,
                        color:      _corEstoque),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expandido
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),

          // ── Materiais (expandido) ───────────────────────────────────
          if (_expandido) ...[
            Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant),
            // Cabeçalho da tabela
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(flex: 3, child: _HeaderCol('Material')),
                  const _HeaderCol('Qtd', align: TextAlign.right),
                  const SizedBox(width: 8),
                  const _HeaderCol('Custo unit.',
                      align: TextAlign.right),
                  const SizedBox(width: 8),
                  const _HeaderColWide('Valor total',
                      align: TextAlign.right),
                ],
              ),
            ),
            Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5)),
            ...materiais.asMap().entries.map((e) {
              return _LinhaEstoque(
                material: e.value,
                ultimo:   e.key == materiais.length - 1,
              );
            }),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _LinhaEstoque extends StatelessWidget {
  final EstoqueMaterialModel material;
  final bool                 ultimo;

  const _LinhaEstoque(
      {required this.material, required this.ultimo});

  @override
  Widget build(BuildContext context) {
    final m = material;
    final detalhes = [
      if (m.identificador != null && m.identificador!.isNotEmpty)
        m.identificador!,
      if (m.medida    != null && m.medida!.isNotEmpty)    m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
    ].join(' · ');

    final temCustoM2 =
        m.ultimoValorPagoM2 != null && m.ultimoValorPagoM2! > 0;
    final temCustoUnit =
        m.ultimoValorPago != null && m.ultimoValorPago! > 0;
    final custo = temCustoUnit
        ? m.ultimoValorPago!
        : temCustoM2
            ? m.ultimoValorPagoM2!
            : null;
    final sufixoCusto =
        (!temCustoUnit && temCustoM2) ? '/m²' : '';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nome,
                        style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w500,
                          color:
                              Theme.of(context).colorScheme.onSurface,
                        )),
                    if (detalhes.isNotEmpty)
                      Text(detalhes,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  ],
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '${_fmtQtd(m.quantidade)} ${m.unidade ?? ''}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: Text(
                  custo != null
                      ? 'R\$ ${custo.toStringAsFixed(2).replaceAll('.', ',')}$sufixoCusto'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: custo != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: m.semCusto
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 13,
                              color: Colors.orange.shade500),
                          const SizedBox(width: 3),
                          Text('sem custo',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade600)),
                        ],
                      )
                    : Text(
                        _brl(m.valorTotal),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                          color:      _corEstoque,
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (!ultimo)
          Divider(
              height: 1,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4)),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ABA 2 — GASTOS (OS FECHADAS, ORIGEM OC)
// ═════════════════════════════════════════════════════════════════════════════

class _AbaGastos extends StatefulWidget {
  final GastosCategoriaProvider provider;
  final bool                    temFiltro;

  const _AbaGastos(
      {required this.provider, required this.temFiltro});

  @override
  State<_AbaGastos> createState() => _AbaGastosState();
}

class _AbaGastosState extends State<_AbaGastos> {
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = widget.provider;

    if (prov.carregandoGastos) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (prov.erroGastos != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            Text('Erro ao carregar gastos',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 4),
            Text(prov.erroGastos!,
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: prov.recarregarGastos,
              icon:  const Icon(Icons.refresh, size: 18),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }
    if (prov.gastos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined,
                size: 56,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('Nenhum gasto encontrado',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 4),
            Text(
              widget.temFiltro
                  ? 'Tente ajustar o período'
                  : 'Ainda não há OS fechadas com saídas originadas em OC',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final busca = _busca.trim().toLowerCase();
    final comIndice = prov.gastos.asMap().entries.toList();
    final filtradas = busca.isEmpty
        ? comIndice
        : comIndice
            .where((e) =>
                e.value.categoriaLabel.toLowerCase().contains(busca))
            .toList();

    return CustomScrollView(
      slivers: [
        // Resumo
        SliverToBoxAdapter(
          child: _ResumoGastos(totalGasto: prov.totalGastos),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // Gráfico mensal
        SliverToBoxAdapter(
          child: _GraficoMensal(provider: prov),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Título + busca
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text('Gastos por categoria',
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                      letterSpacing: 0.2,
                    )),
                const Spacer(),
                SizedBox(
                  width: 240,
                  height: 36,
                  child: TextField(
                    controller: _buscaCtrl,
                    onChanged:  (v) => setState(() => _busca = v),
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface),
                    decoration: InputDecoration(
                      isDense:  true,
                      hintText: 'Filtrar por categoria...',
                      hintStyle: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.outline),
                      prefixIcon: Icon(Icons.search,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.outline),
                      prefixIconConstraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                      suffixIcon: _busca.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline),
                              onPressed: () {
                                _buscaCtrl.clear();
                                setState(() => _busca = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      filled:    true,
                      fillColor:
                          Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppTheme.primary, width: 1.5)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (filtradas.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 40,
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text(
                        'Nenhuma categoria encontrada para "$_busca"',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final entry = filtradas[i];
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: i < filtradas.length - 1 ? 12 : 0),
                  child: _GastoCategoriaCard(
                    gasto: entry.value,
                    cor:   _corCategoria(entry.key),
                  ),
                );
              },
              childCount: filtradas.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class _ResumoGastos extends StatelessWidget {
  final double totalGasto;

  const _ResumoGastos({required this.totalGasto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.category_rounded, size: 16, color: _corGasto),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total gasto em materiais (OS fechadas)',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  'Apenas saídas cuja quantidade foi coberta por entrada via Ordem de Compra',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(_brl(totalGasto),
              style: TextStyle(
                  fontSize:   20,
                  fontWeight: FontWeight.w800,
                  color:      _corGasto)),
        ],
      ),
    );
  }
}

class _GastoCategoriaCard extends StatefulWidget {
  final GastoCategoriaModel gasto;
  final Color               cor;

  const _GastoCategoriaCard(
      {required this.gasto, required this.cor});

  @override
  State<_GastoCategoriaCard> createState() =>
      _GastoCategoriaCardState();
}

class _GastoCategoriaCardState extends State<_GastoCategoriaCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final gasto = widget.gasto;
    final cor   = widget.cor;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _expandido = !_expandido),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
                bottom: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: cor, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(gasto.categoriaLabel,
                        style: TextStyle(
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface,
                        )),
                  ),
                  Text(
                    '${gasto.materiais.length} ${gasto.materiais.length == 1 ? 'material' : 'materiais'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant),
                  ),
                  const SizedBox(width: 16),
                  Text(_brl(gasto.totalGasto),
                      style: TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w700,
                          color:      _corGasto)),
                  const SizedBox(width: 8),
                  Icon(
                    _expandido
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expandido) ...[
            Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: const [
                  Expanded(
                      flex: 3,
                      child: _HeaderCol('Material')),
                  _HeaderCol('Qtd gasta',
                      align: TextAlign.right),
                  SizedBox(width: 8),
                  _HeaderColWide('Gasto total',
                      align: TextAlign.right),
                ],
              ),
            ),
            Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5)),
            ...gasto.materiais.asMap().entries.map((e) {
              return _LinhaGasto(
                material: e.value,
                ultimo:   e.key == gasto.materiais.length - 1,
              );
            }),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _LinhaGasto extends StatelessWidget {
  final GastoMaterialModel material;
  final bool               ultimo;

  const _LinhaGasto(
      {required this.material, required this.ultimo});

  @override
  Widget build(BuildContext context) {
    final m = material;
    final detalhes = [
      if (m.identificador != null && m.identificador!.isNotEmpty)
        m.identificador!,
      if (m.medida    != null && m.medida!.isNotEmpty)    m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
    ].join(' · ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nome,
                        style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface,
                        )),
                    if (detalhes.isNotEmpty)
                      Text(detalhes,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  ],
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  m.qtdGasta > 0
                      ? '${_fmtQtd(m.qtdGasta)} ${m.unidade ?? ''}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: Text(_brl(m.totalGasto),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color:      _corGasto,
                    )),
              ),
            ],
          ),
        ),
        if (!ultimo)
          Divider(
              height: 1,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gráfico de barras — gastos mensais
// ─────────────────────────────────────────────────────────────────────────────

class _GraficoMensal extends StatefulWidget {
  final GastosCategoriaProvider provider;
  const _GraficoMensal({required this.provider});

  @override
  State<_GraficoMensal> createState() => _GraficoMensalState();
}

class _GraficoMensalState extends State<_GraficoMensal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double>   _animacao;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700));
    _animacao =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    if (widget.provider.mensal.isNotEmpty) _animCtrl.forward();
  }

  @override
  void didUpdateWidget(_GraficoMensal old) {
    super.didUpdateWidget(old);
    if (widget.provider.mensal.isNotEmpty &&
        old.provider.mensal.isEmpty) {
      _animCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _trocarAno(int delta) {
    _animCtrl.forward(from: 0);
    widget.provider
        .carregarMensal(ano: widget.provider.anoMensal + delta);
  }

  @override
  Widget build(BuildContext context) {
    final prov   = widget.provider;
    final mensal = prov.mensal;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Gastos por mês',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600)),
              const Spacer(),
              _AnoSelector(
                ano:        prov.anoMensal,
                onAnterior: () => _trocarAno(-1),
                onProximo: prov.anoMensal < DateTime.now().year
                    ? () => _trocarAno(1)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: _corGasto, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('Gasto real (saídas via OC)',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant)),
          ]),
          const SizedBox(height: 16),
          if (prov.carregandoMensal)
            const SizedBox(
                height: 160,
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary)))
          else if (prov.erroMensal != null)
            SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 36, color: AppTheme.error),
                    const SizedBox(height: 8),
                    Text('Erro ao carregar gráfico',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () =>
                          prov.carregarMensal(ano: prov.anoMensal),
                      icon:  const Icon(Icons.refresh, size: 16),
                      label: const Text('Tentar novamente',
                          style: TextStyle(fontSize: 13)),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8)),
                    ),
                  ],
                ),
              ),
            )
          else if (mensal.isEmpty ||
              mensal.every((m) => m.totalGasto == 0))
            SizedBox(
              height: 160,
              child: Center(
                  child: Text('Sem dados para este ano',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .outline))),
            )
          else
            AnimatedBuilder(
              animation: _animacao,
              builder: (_, __) => _BarChart(
                dados:        mensal,
                progresso:    _animacao.value,
                hoveredIndex: _hoveredIndex,
                onHover: (i) => setState(() => _hoveredIndex = i),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnoSelector extends StatelessWidget {
  final int           ano;
  final VoidCallback  onAnterior;
  final VoidCallback? onProximo;

  const _AnoSelector({
    required this.ano,
    required this.onAnterior,
    required this.onProximo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavBtn(icon: Icons.chevron_left, onTap: onAnterior),
        const SizedBox(width: 4),
        Text('$ano',
            style: TextStyle(
                fontSize:   14,
                fontWeight: FontWeight.w700,
                color:
                    Theme.of(context).colorScheme.onSurface)),
        const SizedBox(width: 4),
        _NavBtn(icon: Icons.chevron_right, onTap: onProximo),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData      icon;
  final VoidCallback? onTap;
  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(6),
        child: Opacity(
          opacity: onTap != null ? 1.0 : 0.3,
          child: Icon(icon,
              size: 20,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

class _BarChart extends StatelessWidget {
  final List<GastoMensalModel> dados;
  final double                 progresso;
  final int?                   hoveredIndex;
  final ValueChanged<int?>     onHover;

  const _BarChart({
    required this.dados,
    required this.progresso,
    required this.hoveredIndex,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = dados.fold(
        0.0, (mx, d) => d.totalGasto > mx ? d.totalGasto : mx);

    const double chartHeight = 160.0;
    const double labelHeight = 24.0;
    const double totalHeight = chartHeight + labelHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final barWidth   = totalWidth / dados.length;

        return SizedBox(
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Barras
              Positioned(
                top: 0, left: 0, right: 0,
                height: chartHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(dados.length, (i) {
                    final d       = dados[i];
                    final frac    = maxVal > 0
                        ? d.totalGasto / maxVal
                        : 0.0;
                    final hovered = hoveredIndex == i;
                    final altBar  = chartHeight * frac * progresso;

                    return Expanded(
                      child: MouseRegion(
                        onEnter: (_) => onHover(i),
                        onExit:  (_) => onHover(null),
                        child: GestureDetector(
                          onTapDown: (_) => onHover(i),
                          child: SizedBox(
                            height: chartHeight,
                            child: Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                if (altBar > 0)
                                  Positioned(
                                    bottom: 0,
                                    left: 2, right: 2,
                                    height: altBar,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: _corGasto.withValues(
                                            alpha: hovered
                                                ? 1.0
                                                : 0.8),
                                        borderRadius:
                                            const BorderRadius
                                                .vertical(
                                                top: Radius
                                                    .circular(4)),
                                      ),
                                    ),
                                  ),
                                if (altBar == 0)
                                  Positioned(
                                    bottom: 0,
                                    left: 2, right: 2,
                                    height: 3,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                        borderRadius:
                                            BorderRadius.circular(
                                                2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Rótulos dos meses
              Positioned(
                bottom: 0, left: 0, right: 0,
                height: labelHeight,
                child: Row(
                  children: List.generate(dados.length, (i) {
                    final d       = dados[i];
                    final hovered = hoveredIndex == i;
                    return Expanded(
                      child: Center(
                        child: Text(d.label,
                            style: TextStyle(
                              fontSize:   10,
                              fontWeight: hovered
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: hovered
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .outline,
                            )),
                      ),
                    );
                  }),
                ),
              ),

              // Tooltip
              if (hoveredIndex != null)
                Builder(builder: (context) {
                  final i    = hoveredIndex!;
                  final d    = dados[i];
                  const tipW = 160.0;
                  double left =
                      barWidth * i + barWidth / 2 - tipW / 2;
                  left = left.clamp(
                      0.0,
                      (totalWidth - tipW)
                          .clamp(0.0, double.infinity));
                  return Positioned(
                    top:  0,
                    left: left,
                    child: IgnorePointer(
                        child: _TooltipBar(dado: d)),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _TooltipBar extends StatelessWidget {
  final GastoMensalModel dado;
  const _TooltipBar({required this.dado});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset:     const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${dado.label} ${dado.ano}',
              style: TextStyle(
                  fontSize:   11,
                  fontWeight: FontWeight.w700,
                  color:
                      Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: _corGasto,
                      shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Gasto: ${_brl(dado.totalGasto)}',
                  style: TextStyle(
                    fontSize:   11,
                    fontWeight: FontWeight.w600,
                    color:      _corGasto,
                    overflow:   TextOverflow.ellipsis,
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

// ═════════════════════════════════════════════════════════════════════════════
// ABA 3 — VEÍCULOS (mantida igual à versão anterior)
// ═════════════════════════════════════════════════════════════════════════════

class _AbaVeiculos extends StatelessWidget {
  final VeiculoProvider   provider;
  final int               anoSelecionado;
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
          _ResumoAnualCard(
            provider:       provider,
            anoSelecionado: anoSelecionado,
            onAnoChanged:   onAnoChanged,
          ),
          const SizedBox(height: 20),
          if (provider.gastos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_car_outlined,
                        size: 56,
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text('Nenhum gasto com veículos encontrado',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline)),
                  ],
                ),
              ),
            )
          else ...[
            Text('Gastos por veículo',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
            const SizedBox(height: 12),
            ...provider.gastos.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GastoVeiculoCard(
                  gasto: e.value,
                  cor:   _corCategoria(e.key),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

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
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 18, color: _corVeiculo),
              const SizedBox(width: 8),
              Text('Gastos anuais com veículos',
                  style: TextStyle(
                    fontSize:   14,
                    fontWeight: FontWeight.w700,
                    color:
                        Theme.of(context).colorScheme.onSurface,
                  )),
              const Spacer(),
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        onAnoChanged(anoSelecionado - 1),
                    icon: const Icon(Icons.chevron_left, size: 20),
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    padding:     EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                  Text('$anoSelecionado',
                      style: TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w700,
                        color:
                            Theme.of(context).colorScheme.onSurface,
                      )),
                  IconButton(
                    onPressed:
                        anoSelecionado < DateTime.now().year
                            ? () =>
                                onAnoChanged(anoSelecionado + 1)
                            : null,
                    icon: const Icon(Icons.chevron_right, size: 20),
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    padding:     EdgeInsets.zero,
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
                        color: AppTheme.primary,
                        strokeWidth: 2)))
          else if (resumo == null || resumo.totalAnual == 0)
            SizedBox(
              height: 80,
              child: Center(
                child: Text('Sem gastos em $anoSelecionado',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .outline,
                        fontSize: 13)),
              ),
            )
          else ...[
            Row(
              children: [
                Text('Total em $anoSelecionado:',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
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
            _GraficoMensalVeiculo(porMes: resumo.porMes),
          ],
        ],
      ),
    );
  }
}

class _GraficoMensalVeiculo extends StatelessWidget {
  final List<ResumoMensalVeiculoModel> porMes;
  const _GraficoMensalVeiculo({required this.porMes});

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (m.totalGasto > 0)
                    Text(
                      'R\$${m.totalGasto / 1000 >= 1 ? '${(m.totalGasto / 1000).toStringAsFixed(1)}k' : m.totalGasto.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 8,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 600),
                    height: 90 * frac,
                    decoration: BoxDecoration(
                      color: _corVeiculo.withValues(
                          alpha: 0.85),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.label,
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context)
                          .colorScheme
                          .outline,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GastoVeiculoCard extends StatefulWidget {
  final GastoVeiculoModel gasto;
  final Color             cor;

  const _GastoVeiculoCard(
      {required this.gasto, required this.cor});

  @override
  State<_GastoVeiculoCard> createState() =>
      _GastoVeiculoCardState();
}

class _GastoVeiculoCardState extends State<_GastoVeiculoCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final g   = widget.gasto;
    final cor = widget.cor;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _expandido = !_expandido),
            borderRadius: const BorderRadius.vertical(
                top:    Radius.circular(12),
                bottom: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: cor,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Icon(Icons.directions_car_rounded,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(g.nome,
                            style: TextStyle(
                              fontSize:   14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                            )),
                        Text(g.placa,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )),
                      ],
                    ),
                  ),
                  Text(_brl(g.totalGasto),
                      style: TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w700,
                          color:      _corVeiculo)),
                  const SizedBox(width: 8),
                  Icon(
                    _expandido
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Theme.of(context)
                        .colorScheme
                        .outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expandido && g.servicos.isNotEmpty) ...[
            Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant),
            ...g.servicos.asMap().entries.map((e) {
              final item = e.value;
              final titulo = item.descricao != null && item.descricao!.isNotEmpty
                  ? item.descricao!
                  : labelTipo(item.tipo);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(titulo,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface)),
                              Text(labelTipo(item.tipo),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Text(_fmtData(item.dataEnvio),
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const SizedBox(width: 16),
                        Text(_brl(item.valor),
                            style: TextStyle(
                              fontSize:   13,
                              fontWeight: FontWeight.w600,
                              color:      _corVeiculo,
                            )),
                      ],
                    ),
                  ),
                  if (e.key < g.servicos.length - 1)
                    Divider(
                        height: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.5)),
                ],
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
// Widgets auxiliares compartilhados
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCol extends StatelessWidget {
  final String    text;
  final TextAlign align;
  const _HeaderCol(this.text,
      {this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 70,
        child: Text(text,
            textAlign: align,
            style: TextStyle(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      );
}

class _HeaderColWide extends StatelessWidget {
  final String    text;
  final TextAlign align;
  const _HeaderColWide(this.text,
      {this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 110,
        child: Text(text,
            textAlign: align,
            style: TextStyle(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Seletor de data
// ─────────────────────────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String                 label;
  final DateTime?              value;
  final DateTime               firstDate;
  final DateTime               lastDate;
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
      onTap:        () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: hasValue
                ? AppTheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today,
                size:  16,
                color: hasValue
                    ? AppTheme.primary
                    : Theme.of(context).colorScheme.outline),
            const SizedBox(width: 6),
            Text(
              hasValue
                  ? '$label: ${_fmtData(value)}'
                  : label,
              style: TextStyle(
                fontSize:   13,
                color:      hasValue
                    ? AppTheme.primary
                    : Theme.of(context).colorScheme.outline,
                fontWeight: hasValue
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            if (hasValue) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onCleared,
                child: Icon(Icons.close,
                    size: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}