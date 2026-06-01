import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/producao_model.dart';
import '../providers/producao_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

class _UpperCaseFormatter extends TextInputFormatter {
  static final _acentos = {
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'Ç': 'C', 'ç': 'c',
    'Ñ': 'N', 'ñ': 'n',
  };
  static String _removerAcentos(String s) =>
      s.split('').map((c) => _acentos[c] ?? c).join();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final texto = _removerAcentos(newValue.text).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset:   newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class ProducaoPage extends StatefulWidget {
  const ProducaoPage({super.key});

  @override
  State<ProducaoPage> createState() => _ProducaoPageState();
}

class _ProducaoPageState extends State<ProducaoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Filtros da aba Estoque ─────────────────────────────────────────────────
  final _buscaCtrl         = TextEditingController();
  final _buscaIdCtrl       = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  String? _categoriaFiltro;
  String  _statusFiltro    = '';
  Timer?  _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProducaoProvider>().carregarCategorias();
      context.read<ProducaoProvider>().carregarMateriais();
      context.read<ProducaoProvider>().carregarHistorico();
    });
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      context.read<ProducaoProvider>().carregarHistorico();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _buscaCtrl.dispose();
    _buscaIdCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _aplicarFiltros() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<ProducaoProvider>().carregarMateriais(
            busca:         _buscaCtrl.text.trim(),
            categoria:     _categoriaFiltro,
            status:        _statusFiltro.isEmpty ? null : _statusFiltro,
            id:            _buscaIdCtrl.text.trim(),
            identificador: _identificadorCtrl.text.trim(),
            medida:        _medidaCtrl.text.trim(),
            espessura:     _espessuraCtrl.text.trim(),
          );
    });
  }

  void _limparFiltros() {
    _buscaCtrl.clear();
    _buscaIdCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _espessuraCtrl.clear();
    setState(() {
      _categoriaFiltro = null;
      _statusFiltro    = '';
    });
    context.read<ProducaoProvider>().carregarMateriais();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Produção',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Solicitação e controle de materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    context.read<ProducaoProvider>().carregarCategorias();
                    context.read<ProducaoProvider>().carregarMateriais();
                    context.read<ProducaoProvider>().carregarHistorico();
                  },
                  icon: const Icon(Icons.refresh, size: 18, color: AppTheme.textSecondary),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: const BorderSide(color: AppTheme.divider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Container(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(bottom: BorderSide(color: AppTheme.divider)),
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
                  Tab(text: 'Estoque'),
                  Tab(text: 'Histórico'),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _EstoqueTab(
                    buscaCtrl:         _buscaCtrl,
                    buscaIdCtrl:       _buscaIdCtrl,
                    identificadorCtrl: _identificadorCtrl,
                    medidaCtrl:        _medidaCtrl,
                    espessuraCtrl:     _espessuraCtrl,
                    categoriaFiltro:   _categoriaFiltro,
                    statusFiltro:      _statusFiltro,
                    scheme:            scheme,
                    onCategoriaChanged: (v) {
                      setState(() => _categoriaFiltro = v);
                      _aplicarFiltros();
                    },
                    onStatusChanged: (v) {
                      setState(() => _statusFiltro = v ?? '');
                      _aplicarFiltros();
                    },
                    onBuscaChanged:    (_) => _aplicarFiltros(),
                    onDebounce:        _aplicarFiltros,
                    onLimpar:          _limparFiltros,
                  ),
                  const _HistoricoTab(),
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
// ABA ESTOQUE
// ─────────────────────────────────────────────────────────────────────────────

class _EstoqueTab extends StatefulWidget {
  final TextEditingController buscaCtrl;
  final TextEditingController buscaIdCtrl;
  final TextEditingController identificadorCtrl;
  final TextEditingController medidaCtrl;
  final TextEditingController espessuraCtrl;
  final String?               categoriaFiltro;
  final String                statusFiltro;
  final ColorScheme           scheme;
  final void Function(String?) onCategoriaChanged;
  final void Function(String?) onStatusChanged;
  final void Function(String)  onBuscaChanged;
  final VoidCallback           onDebounce;
  final VoidCallback           onLimpar;

  const _EstoqueTab({
    required this.buscaCtrl,
    required this.buscaIdCtrl,
    required this.identificadorCtrl,
    required this.medidaCtrl,
    required this.espessuraCtrl,
    required this.categoriaFiltro,
    required this.statusFiltro,
    required this.scheme,
    required this.onCategoriaChanged,
    required this.onStatusChanged,
    required this.onBuscaChanged,
    required this.onDebounce,
    required this.onLimpar,
  });

  @override
  State<_EstoqueTab> createState() => _EstoqueTabState();
}

class _EstoqueTabState extends State<_EstoqueTab> {
  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),

        // ── Linha 1: ID · Busca · Categoria · Status · Limpar ───────────────
        Row(
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: widget.buscaIdCtrl,
                decoration: const InputDecoration(
                  hintText:   'ID...',
                  prefixIcon: Icon(Icons.tag, color: AppTheme.textHint, size: 18),
                  isDense:    true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => widget.onDebounce(),
                onSubmitted: (_) => widget.onDebounce(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: TextField(
                controller: widget.buscaCtrl,
                decoration: const InputDecoration(
                  hintText:   'Buscar material...',
                  prefixIcon: Icon(Icons.search, color: AppTheme.textHint, size: 20),
                  isDense:    true,
                ),
                onChanged: widget.onBuscaChanged,
                onSubmitted: (_) => widget.onDebounce(),
              ),
            ),
            const SizedBox(width: 12),
            Consumer<ProducaoProvider>(
              builder: (_, provider, __) {
                final opcoes = ['Todas', ...provider.categorias];
                return SizedBox(
                  width: 200,
                  child: Autocomplete<String>(
                    initialValue: TextEditingValue(
                      text: widget.categoriaFiltro ?? 'Todas',
                    ),
                    optionsBuilder: (TextEditingValue v) {
                      if (v.text.isEmpty) return opcoes;
                      return opcoes.where((o) =>
                          o.toLowerCase().contains(v.text.toLowerCase()));
                    },
                    fieldViewBuilder: (context, ctrl, focusNode, onSubmit) {
                      return TextField(
                        controller: ctrl,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          hintText: 'Buscar categoria...',
                          prefixIcon: Icon(Icons.category_outlined,
                              color: AppTheme.textHint, size: 18),
                          isDense: true,
                        ),
                        onSubmitted: (_) => onSubmit(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 260,
                              maxHeight: 240,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (_, i) {
                                final opt = options.elementAt(i);
                                return InkWell(
                                  onTap: () => onSelected(opt),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    child: Text(
                                      opt,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                    onSelected: (value) {
                      widget.onCategoriaChanged(
                          value == 'Todas' ? null : value);
                    },
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: widget.statusFiltro.isEmpty ? '' : widget.statusFiltro,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  isDense:   true,
                ),
                items: const [
                  DropdownMenuItem(value: '',        child: Text('Todos')),
                  DropdownMenuItem(value: 'OK',      child: Text('OK')),
                  DropdownMenuItem(value: 'LIMITE',  child: Text('Limite')),
                  DropdownMenuItem(value: 'CRITICO', child: Text('Crítico')),
                ],
                onChanged: widget.onStatusChanged,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Limpar filtros',
              icon: Icon(Icons.filter_alt_off, color: widget.scheme.onSurfaceVariant),
              onPressed: widget.onLimpar,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Linha 2: Identificador · Medida · Espessura ──────────────────────
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.identificadorCtrl,
                decoration: const InputDecoration(
                  hintText:   'Identificador...',
                  prefixIcon: Icon(Icons.qr_code, color: AppTheme.textHint, size: 18),
                  isDense:    true,
                ),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseFormatter()],
                onChanged: (_) => widget.onDebounce(),
                onSubmitted: (_) => widget.onDebounce(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.medidaCtrl,
                decoration: const InputDecoration(
                  hintText:   'Medida...',
                  prefixIcon: Icon(Icons.straighten, color: AppTheme.textHint, size: 18),
                  isDense:    true,
                ),
                onChanged: (_) => widget.onDebounce(),
                onSubmitted: (_) => widget.onDebounce(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.espessuraCtrl,
                decoration: const InputDecoration(
                  hintText:   'Espessura...',
                  prefixIcon: Icon(Icons.layers, color: AppTheme.textHint, size: 18),
                  isDense:    true,
                ),
                onChanged: (_) => widget.onDebounce(),
                onSubmitted: (_) => widget.onDebounce(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Expanded(
          child: Consumer<ProducaoProvider>(
            builder: (_, provider, __) {
              if (provider.carregandoMateriais) {
                return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary));
              }
              if (provider.materiais.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhum material encontrado',
                    style: TextStyle(color: AppTheme.textHint),
                  ),
                );
              }

              final todos        = provider.materiais;
              final totalPaginas = (todos.length / _itensPorPagina).ceil();
              final paginaSegura = _paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
              final inicio       = paginaSegura * _itensPorPagina;
              final fim          = (inicio + _itensPorPagina).clamp(0, todos.length);
              final paginados    = todos.sublist(inicio, fim);

              return Column(
                children: [
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        child: _TabelaMateriais(materiais: paginados),
                      ),
                    ),
                  ),
                  if (totalPaginas > 1) ...[
                    const SizedBox(height: 12),
                    _BarraPaginacao(
                      paginaAtual:     paginaSegura,
                      totalPaginas:    totalPaginas,
                      totalItens:      todos.length,
                      itensPorPagina:  _itensPorPagina,
                      onPaginaChanged: (p) => setState(() => _paginaAtual = p),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABELA DE MATERIAIS
// ─────────────────────────────────────────────────────────────────────────────

class _ColDef {
  final String label;
  final double? fixed;
  final double? flex;
  const _ColDef({required this.label, this.fixed, this.flex});
}

class _TabelaMateriais extends StatelessWidget {
  final List<MaterialProducaoModel> materiais;

  const _TabelaMateriais({required this.materiais});

  static const List<_ColDef> _cols = [
    _ColDef(label: 'ID',            fixed: 56),
    _ColDef(label: 'Identificador', flex: 0.7),
    _ColDef(label: 'Material',      flex: 2.0),
    _ColDef(label: 'Categoria',     flex: 1.0),
    _ColDef(label: 'Unidade',       flex: 0.9),
    _ColDef(label: 'Medida',        flex: 0.8),
    _ColDef(label: 'Espessura',     flex: 0.7),
    _ColDef(label: 'Estoque atual', flex: 0.7),
    _ColDef(label: 'Em uso',        flex: 0.6),
    _ColDef(label: 'Disponível',    flex: 0.7),
    _ColDef(label: 'Status',        flex: 0.8),
  ];

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  Widget _cabecalho() => Container(
        color: AppTheme.surfaceVariant,
        child: Row(
          children: [
            for (final col in _cols)
              _colWrap(
                col,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    col.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _cabecalho(),
        for (int i = 0; i < materiais.length; i++) ...[
          if (i > 0)
            const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
          _LinhaMateria(material: materiais[i], cols: _cols),
        ],
        if (materiais.isNotEmpty)
          const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
      ],
    );
  }
}

class _LinhaMateria extends StatefulWidget {
  final MaterialProducaoModel material;
  final List<_ColDef> cols;

  const _LinhaMateria({required this.material, required this.cols});

  @override
  State<_LinhaMateria> createState() => _LinhaMateriaState();
}

class _LinhaMateriaState extends State<_LinhaMateria> {
  bool _hovered = false;

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  static Widget _cell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
        ),
      );

  static Widget _vDivider() => const VerticalDivider(
        width: 1, thickness: 0.5, color: AppTheme.divider,
      );

  void _abrirSolicitacao(BuildContext context) {
    final role = context.read<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    if (role == 'COMPRAS') return;
    showDialog(
      context: context,
      builder: (_) => _SolicitarMaterialDialog(material: widget.material),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m          = widget.material;
    final cols       = widget.cols;
    final disponivel = m.quantidade + m.emUso;

    final role       = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    final podeOperar = role != 'COMPRAS';

    final bgColor = _hovered && podeOperar
        ? const Color(0xFFFF9800).withValues(alpha: 0.10)
        : AppTheme.surface;

    return MouseRegion(
      cursor: podeOperar ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: podeOperar ? () => _abrirSolicitacao(context) : null,
        child: ColoredBox(
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ID
                _colWrap(cols[0], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    '${m.id}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                )),
                _vDivider(),

                // Identificador
                _colWrap(cols[1], _cell(m.identificador?.isNotEmpty == true ? m.identificador! : '—')),
                _vDivider(),

                // Nome
                _colWrap(cols[2], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    m.nome,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                )),
                _vDivider(),

                // Categoria
                _colWrap(cols[3], _cell(m.categoria ?? '—')),
                _vDivider(),

                // Unidade
                _colWrap(cols[4], _cell(m.unidade ?? '—')),
                _vDivider(),

                // Medida
                _colWrap(cols[5], _cell(m.medida ?? '—')),
                _vDivider(),

                // Espessura
                _colWrap(cols[6], _cell(m.espessura ?? '—')),
                _vDivider(),

                // Estoque atual
                _colWrap(cols[7], _cell(
                  m.quantidade.toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2),
                )),
                _vDivider(),

                // Em uso
                _colWrap(cols[8], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    m.emUso > 0
                        ? m.emUso.toStringAsFixed(m.emUso % 1 == 0 ? 0 : 2)
                        : '—',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: m.emUso > 0 ? AppTheme.warning : AppTheme.textHint,
                      fontWeight: m.emUso > 0 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                )),
                _vDivider(),

                // Disponível
                _colWrap(cols[9], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    disponivel.toStringAsFixed(disponivel % 1 == 0 ? 0 : 2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _corStatus(m.statusReal),
                    ),
                  ),
                )),
                _vDivider(),

                // Status
                _colWrap(cols[10], Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: _StatusBadge(status: m.statusReal),
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _corStatus(String status) {
    switch (status) {
      case 'OK':      return AppTheme.statusOk;
      case 'LIMITE':  return AppTheme.statusBaixo;
      case 'CRITICO': return AppTheme.statusCritico;
      default:        return AppTheme.textHint;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color cor;
    switch (status) {
      case 'OK':      cor = AppTheme.statusOk;      break;
      case 'LIMITE':  cor = AppTheme.statusBaixo;   break;
      case 'CRITICO': cor = AppTheme.statusCritico; break;
      default:        cor = AppTheme.textHint;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG — SOLICITAR MATERIAL (baixa imediata)
// ─────────────────────────────────────────────────────────────────────────────

class _SolicitarMaterialDialog extends StatefulWidget {
  final MaterialProducaoModel material;
  const _SolicitarMaterialDialog({required this.material});

  @override
  State<_SolicitarMaterialDialog> createState() =>
      _SolicitarMaterialDialogState();
}

class _SolicitarMaterialDialogState extends State<_SolicitarMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _osCtrl  = TextEditingController();
  final _qtdCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool  _enviando = false;
  String? _erro;

  FilhoEspecificoProducaoModel? _filhoSelecionado;

  @override
  void initState() {
    super.initState();
    final filhos = widget.material.filhosEspecificos;
    if (filhos.length == 1) _filhoSelecionado = filhos.first;
  }

  @override
  void dispose() {
    _osCtrl.dispose();
    _qtdCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.material.especifico && _filhoSelecionado == null) {
      setState(() => _erro = 'Selecione a variação do material');
      return;
    }

    final os  = _osCtrl.text.trim();
    final qtd = double.tryParse(_qtdCtrl.text.replaceAll(',', '.'));

    if (qtd == null || qtd <= 0) {
      setState(() => _erro = 'Quantidade inválida');
      return;
    }

    setState(() { _enviando = true; _erro = null; });

    final ok = await context.read<ProducaoProvider>().criarSolicitacao(
          materialId:          widget.material.id,
          descricaoItem:       _filhoSelecionado?.descricao,
          quantidadeReservada: qtd,
          numeroOS:            os,
        );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material baixado com sucesso'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() =>
          _erro = context.read<ProducaoProvider>().erro ?? 'Erro ao solicitar');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m      = widget.material;
    final filhos = m.filhosEspecificos;

    final disponivel = m.especifico && _filhoSelecionado != null
        ? _filhoSelecionado!.quantidade
        : m.quantidade;
    final unidade = m.unidade ?? '';

    final detalhes = <String>[];
    if (m.identificador != null && m.identificador!.isNotEmpty) {
      detalhes.add(m.identificador!);
    }
    if (m.medida != null) detalhes.add(m.medida!);
    if (m.espessura != null) detalhes.add(m.espessura!);

    return AlertDialog(
      title: const Text('Solicitar Material'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.nome,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (detalhes.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  detalhes.join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
              const SizedBox(height: 16),

              // ── Número da OS ─────────────────────────────────────────────
              TextFormField(
                controller: _osCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número da OS *',
                  isDense:   true,
                ),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseFormatter()],
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Informe a OS' : null,
              ),
              const SizedBox(height: 12),

              // ── Variação (material específico) ───────────────────────────
              if (m.especifico) ...[
                if (filhos.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.statusCritico.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.statusCritico.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppTheme.statusCritico),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Nenhuma variação em estoque para este material.',
                            style: TextStyle(
                              fontSize: 12, color: AppTheme.statusCritico),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  DropdownButtonFormField<FilhoEspecificoProducaoModel>(
                    initialValue: _filhoSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Variação *',
                      isDense:   true,
                    ),
                    isExpanded: true,
                    items: filhos.map((f) {
                      final qtdStr = f.quantidade.toStringAsFixed(
                          f.quantidade % 1 == 0 ? 0 : 2);
                      return DropdownMenuItem(
                        value: f,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                f.descricao,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$qtdStr $unidade',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (f) => setState(() {
                      _filhoSelecionado = f;
                      _erro = null;
                    }),
                    validator: (_) => _filhoSelecionado == null
                        ? 'Selecione a variação'
                        : null,
                  ),
                  if (_filhoSelecionado != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Disponível: ${_filhoSelecionado!.quantidade.toStringAsFixed(_filhoSelecionado!.quantidade % 1 == 0 ? 0 : 2)} $unidade',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
              ],

              // ── Quantidade ───────────────────────────────────────────────
              if (!m.especifico || filhos.isNotEmpty) ...[
                TextFormField(
                  controller: _qtdCtrl,
                  decoration: InputDecoration(
                    labelText: 'Quantidade *',
                    isDense:   true,
                    suffixText: unidade,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (_erro != null) return _erro;
                    final qtd =
                        double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (qtd == null || qtd <= 0) return 'Quantidade inválida';
                    if (m.especifico && _filhoSelecionado != null) {
                      if (qtd > _filhoSelecionado!.quantidade) {
                        return 'Máximo disponível: ${_filhoSelecionado!.quantidade.toStringAsFixed(2)} $unidade';
                      }
                    }
                    return null;
                  },
                  onChanged: (_) {
                    if (_erro != null) setState(() => _erro = null);
                  },
                ),
                if (!m.especifico) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Disponível: ${disponivel.toStringAsFixed(disponivel % 1 == 0 ? 0 : 2)} $unidade',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                ],
                const SizedBox(height: 12),

                // ── Observação ─────────────────────────────────────────────
                TextFormField(
                  controller: _obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                    isDense:   true,
                  ),
                  maxLines: 2,
                ),
              ],

              // ── Erro geral ───────────────────────────────────────────────
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(
                  _erro!,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.statusCritico),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (m.especifico && filhos.isEmpty) || _enviando
              ? null
              : _confirmar,
          child: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Confirmar Saída'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABA HISTÓRICO
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricoTab extends StatefulWidget {
  const _HistoricoTab();

  @override
  State<_HistoricoTab> createState() => _HistoricoTabState();
}

class _HistoricoTabState extends State<_HistoricoTab> {
  final _buscaCtrl = TextEditingController();
  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        TextField(
          controller: _buscaCtrl,
          decoration: const InputDecoration(
            hintText:   'Buscar por OS ou usuário...',
            prefixIcon: Icon(Icons.search, color: AppTheme.textHint, size: 20),
            isDense:    true,
          ),
          onChanged: (v) {
            setState(() => _paginaAtual = 0);
            context
                .read<ProducaoProvider>()
                .carregarHistorico(busca: v.trim());
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Consumer<ProducaoProvider>(
            builder: (_, provider, __) {
              if (provider.carregandoHistorico) {
                return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary));
              }
              if (provider.historico.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhuma saída registrada',
                    style: TextStyle(color: AppTheme.textHint),
                  ),
                );
              }

              final todos        = provider.historico;
              final totalPaginas = (todos.length / _itensPorPagina).ceil();
              final paginaSegura = _paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
              final inicio       = paginaSegura * _itensPorPagina;
              final fim          = (inicio + _itensPorPagina).clamp(0, todos.length);
              final paginados    = todos.sublist(inicio, fim);

              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: paginados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = paginados[i];
                        return _HistoricoCard(solicitacao: s);
                      },
                    ),
                  ),
                  if (totalPaginas > 1) ...[
                    const SizedBox(height: 12),
                    _BarraPaginacao(
                      paginaAtual:     paginaSegura,
                      totalPaginas:    totalPaginas,
                      totalItens:      todos.length,
                      itensPorPagina:  _itensPorPagina,
                      onPaginaChanged: (p) => setState(() => _paginaAtual = p),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD DO HISTÓRICO
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricoCard extends StatelessWidget {
  final SolicitacaoProducaoModel solicitacao;
  const _HistoricoCard({required this.solicitacao});

  static DateTime _toBrasilia(DateTime utc) =>
      utc.toUtc().subtract(const Duration(hours: 3));

  Future<void> _confirmarExclusao(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro'),
        content: Text(
          'Excluir o histórico da OS ${solicitacao.numeroOS}?\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true || !context.mounted) return;

    final ok = await context
        .read<ProducaoProvider>()
        .excluirHistorico(solicitacao.id);

    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<ProducaoProvider>().erro ?? 'Erro ao excluir',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s      = solicitacao;
    final data   = _toBrasilia(s.finalizadoEm ?? s.atualizadoEm);
    final dataStr = '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year} '
        '${data.hour.toString().padLeft(2, '0')}:'
        '${data.minute.toString().padLeft(2, '0')}';

    final detalhes = <String>[];
    if (s.materialIdentificador != null && s.materialIdentificador!.isNotEmpty) {
      detalhes.add(s.materialIdentificador!);
    }
    if (s.materialMedida != null) detalhes.add(s.materialMedida!);
    if (s.materialEspessura != null) detalhes.add(s.materialEspessura!);

    // Verificar role para mostrar botão de exclusão
    final role = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    final podeExcluir = role == 'ADMIN' || role == 'GERENTE';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: AppTheme.success, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OS ${s.numeroOS}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    s.materialNome,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (detalhes.isNotEmpty)
                    Text(
                      detalhes.join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  if (s.descricaoItem != null)
                    Text(
                      s.descricaoItem!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (s.baixas.isNotEmpty && s.baixas.last.observacao != null)
                    Text(
                      s.baixas.last.observacao!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  Text(
                    'Usuário: ${s.usuarioNome}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${s.quantidadeUsada.toStringAsFixed(s.quantidadeUsada % 1 == 0 ? 0 : 2)} ${s.materialUnidade ?? ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  dataStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textHint,
                  ),
                ),
                if (podeExcluir) ...[
                  const SizedBox(height: 4),
                  Tooltip(
                    message: 'Excluir registro',
                    child: InkWell(
                      onTap: () => _confirmarExclusao(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppTheme.error.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGINAÇÃO
// ─────────────────────────────────────────────────────────────────────────────

class _BarraPaginacao extends StatelessWidget {
  final int paginaAtual;
  final int totalPaginas;
  final int totalItens;
  final int itensPorPagina;
  final void Function(int) onPaginaChanged;

  const _BarraPaginacao({
    required this.paginaAtual,
    required this.totalPaginas,
    required this.totalItens,
    required this.itensPorPagina,
    required this.onPaginaChanged,
  });

  List<int> _paginas() {
    if (totalPaginas <= 7) return List.generate(totalPaginas, (i) => i);
    final Set<int> vis = {0, totalPaginas - 1, paginaAtual};
    if (paginaAtual > 0) vis.add(paginaAtual - 1);
    if (paginaAtual < totalPaginas - 1) vis.add(paginaAtual + 1);
    final sorted = vis.toList()..sort();
    final List<int> result = [];
    for (int i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) result.add(-1);
      result.add(sorted[i]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final inicio  = paginaAtual * itensPorPagina + 1;
    final fim     = ((paginaAtual + 1) * itensPorPagina).clamp(0, totalItens);
    final paginas = _paginas();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Exibindo $inicio–$fim de $totalItens',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BotaoPagina(
                icon: Icons.chevron_left,
                tooltip: 'Página anterior',
                enabled: paginaAtual > 0,
                onTap: () => onPaginaChanged(paginaAtual - 1),
              ),
              const SizedBox(width: 4),
              for (final p in paginas) ...[
                if (p == -1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: AppTheme.textHint)),
                  )
                else
                  _BotaoNumeroPagina(
                    numero: p,
                    ativa: p == paginaAtual,
                    onTap: () => onPaginaChanged(p),
                  ),
                const SizedBox(width: 4),
              ],
              _BotaoPagina(
                icon: Icons.chevron_right,
                tooltip: 'Próxima página',
                enabled: paginaAtual < totalPaginas - 1,
                onTap: () => onPaginaChanged(paginaAtual + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotaoPagina extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _BotaoPagina({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? AppTheme.divider : AppTheme.divider.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AppTheme.textSecondary : AppTheme.textHint,
          ),
        ),
      ),
    );
  }
}

class _BotaoNumeroPagina extends StatelessWidget {
  final int numero;
  final bool ativa;
  final VoidCallback onTap;

  const _BotaoNumeroPagina({
    required this.numero,
    required this.ativa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: ativa ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: ativa ? AppTheme.primary : Colors.transparent,
          border: Border.all(
            color: ativa ? AppTheme.primary : AppTheme.divider,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '${numero + 1}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: ativa ? FontWeight.w700 : FontWeight.w400,
            color: ativa ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}