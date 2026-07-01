import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/producao_model.dart';
import '../providers/producao_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

/// Formata um valor monetário com até 6 casas decimais, removendo zeros
/// à direita desnecessários (mínimo 2 casas). Ex.: 1.5 → "R$ 1,50";
/// 0.000125 → "R$ 0,000125"; 1.234560 → "R$ 1,23456".
String _brl6(double v) {
  final s6 = v.toStringAsFixed(6);
  final trimmed = s6.replaceAll(RegExp(r'0+$'), '');
  final partes = trimmed.split('.');
  final dec = partes.length > 1 ? partes[1] : '';
  final decFinal = dec.length < 2 ? dec.padRight(2, '0') : dec;
  return 'R\$ ${partes[0].replaceAll('.', ',')},$decFinal';
}

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

// Sentinels para categorias especiais
const _kCategoriaGeral        = '__GERAL__';
const _kCategoriaSemCategoria = '__SEM_CATEGORIA__';

// Sentinels para identificadores especiais
const _kIdentificadorTodos           = '__TODOS__';
const _kIdentificadorSemIdentificador = '__SEM_IDENTIFICADOR__';

class ProducaoPage extends StatefulWidget {
  const ProducaoPage({super.key});

  @override
  State<ProducaoPage> createState() => _ProducaoPageState();
}

class _ProducaoPageState extends State<ProducaoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProducaoProvider>().carregarCategorias();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: EdgeInsets.all(24),
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
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Solicitação e controle de materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    context.read<ProducaoProvider>().carregarCategorias();
                    context.read<ProducaoProvider>().carregarHistorico();
                  },
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
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
                  Tab(text: 'Estoque'),
                  Tab(text: 'Histórico'),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _EstoqueTab(),
                  _HistoricoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ABA ESTOQUE — grade de categorias
// ─────────────────────────────────────────────────────────────────────

class _EstoqueTab extends StatefulWidget {
  const _EstoqueTab();

  @override
  State<_EstoqueTab> createState() => _EstoqueTabState();
}

class _EstoqueTabState extends State<_EstoqueTab> {
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria    = '';

  static IconData _iconePara(String categoria) {
    final c = categoria.toUpperCase();
    if (c.contains('LONA'))      return Icons.straighten;
    if (c.contains('BANNER'))    return Icons.flag;
    if (c.contains('VINIL'))     return Icons.layers;
    if (c.contains('PERFIL'))    return Icons.square_foot;
    if (c.contains('TINTA'))     return Icons.format_paint;
    if (c.contains('PAPEL'))     return Icons.description;
    if (c.contains('ACESSORIO')) return Icons.handyman;
    if (c.contains('COLA'))      return Icons.water_drop;
    if (c.contains('TECIDO'))    return Icons.texture;
    if (c.contains('MADEIRA'))   return Icons.foundation;
    if (c.contains('METAL'))     return Icons.hardware;
    return Icons.inventory_2;
  }

  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  @override
  void dispose() {
    _filtroCategoriaCtrl.dispose();
    super.dispose();
  }

  void _navegarParaCategoria({
    required String categoriaId,
    required String categoriaLabel,
    required Color cor,
    required IconData icone,
  }) {
    // Geral e Sem categoria não possuem tela de identificadores —
    // navegam diretamente para a listagem de materiais.
    final pularIdentificadores =
        categoriaId == _kCategoriaGeral ||
        categoriaId == _kCategoriaSemCategoria;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => pularIdentificadores
            ? _ProducaoCategoriaPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
              )
            : _ProducaoIdentificadorPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
              ),
      ),
    ).then((_) {
      if (mounted) {
        final p = context.read<ProducaoProvider>();
        // Só recarrega se já tinha carregado com sucesso — evita que o retorno
        // da navegação sobrescreva um estado de erro e cause rebuild espúrio.
        if (p.categoriasCarregadas) p.carregarCategorias();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),

        SizedBox(
          width: 360,
          child: TextField(
            controller: _filtroCategoriaCtrl,
            decoration: InputDecoration(
              hintText:   'Buscar categoria...',
              prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
              isDense:    true,
              suffixIcon: _filtroCategoria.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _filtroCategoriaCtrl.clear();
                        setState(() => _filtroCategoria = '');
                      },
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _filtroCategoria = v.trim().toLowerCase()),
          ),
        ),
        const SizedBox(height: 20),

        Expanded(
          child: SingleChildScrollView(
            child: Consumer<ProducaoProvider>(
              builder: (_, provider, __) {
                if (provider.carregandoCategorias && !provider.categoriasCarregadas) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                  );
                }

                if (provider.erroCategorias != null && !provider.categoriasCarregadas) {
                  return SizedBox(
                    height: 300,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          SizedBox(height: 12),
                          Text(
                            'Erro ao carregar categorias',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            provider.erroCategorias!,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => provider.carregarCategorias(),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Só exibe categorias fixas se o servidor já respondeu com sucesso
                final servidorOk = provider.categoriasCarregadas;

                bool corresponde(String label) =>
                    _filtroCategoria.isEmpty ||
                    label.toLowerCase().contains(_filtroCategoria);

                final cards = <Widget>[
                  if (servidorOk && corresponde('Geral'))
                    _CategoriaCardProducao(
                      categoria: 'Geral',
                      cor:       const Color(0xFF5E35B1),
                      icone:     Icons.grid_view_rounded,
                      onTap: () => _navegarParaCategoria(
                        categoriaId:    _kCategoriaGeral,
                        categoriaLabel: 'Geral',
                        cor:            const Color(0xFF5E35B1),
                        icone:          Icons.grid_view_rounded,
                      ),
                    ),
                  if (servidorOk && corresponde('Sem categoria'))
                    _CategoriaCardProducao(
                      categoria: 'Sem categoria',
                      cor:       const Color(0xFF546E7A),
                      icone:     Icons.help_outline,
                      onTap: () => _navegarParaCategoria(
                        categoriaId:    _kCategoriaSemCategoria,
                        categoriaLabel: 'Sem categoria',
                        cor:            const Color(0xFF546E7A),
                        icone:          Icons.help_outline,
                      ),
                    ),
                  for (int i = 0; i < provider.categorias.length; i++)
                    if (corresponde(provider.categorias[i]))
                      _CategoriaCardProducao(
                        categoria: provider.categorias[i],
                        cor:       _cores[i % _cores.length],
                        icone:     _iconePara(provider.categorias[i]),
                        onTap: () => _navegarParaCategoria(
                          categoriaId:    provider.categorias[i],
                          categoriaLabel: provider.categorias[i],
                          cor:            _cores[i % _cores.length],
                          icone:          _iconePara(provider.categorias[i]),
                        ),
                      ),
                ];

                if (cards.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
                          SizedBox(height: 16),
                          Text(
                            _filtroCategoria.isNotEmpty
                                ? 'Nenhuma categoria encontrada'
                                : 'Nenhuma categoria cadastrada',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return GridView.count(
                  crossAxisCount:   4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing:  16,
                  childAspectRatio: 1.0,
                  shrinkWrap:       true,
                  physics:          const NeverScrollableScrollPhysics(),
                  children:         cards,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// CARD DE CATEGORIA
// ─────────────────────────────────────────────────────────────────────────────

class _CategoriaCardProducao extends StatefulWidget {
  final String     categoria;
  final Color      cor;
  final IconData   icone;
  final VoidCallback onTap;

  const _CategoriaCardProducao({
    required this.categoria,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_CategoriaCardProducao> createState() => _CategoriaCardProducaoState();
}

class _CategoriaCardProducaoState extends State<_CategoriaCardProducao> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ativo = _hovered;
    return MouseRegion(
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo ? widget.cor.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo ? widget.cor : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
                ? [BoxShadow(color: widget.cor.withValues(alpha: 0.20), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icone, color: widget.cor, size: 28),
              ),
              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  widget.categoria,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ativo ? widget.cor : Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE IDENTIFICADORES (nível 2 da hierarquia: categoria → identificador)
// ─────────────────────────────────────────────

class _ProducaoIdentificadorPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;

  const _ProducaoIdentificadorPage({
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
  });

  @override
  State<_ProducaoIdentificadorPage> createState() => _ProducaoIdentificadorPageState();
}

class _ProducaoIdentificadorPageState extends State<_ProducaoIdentificadorPage> {
  final _filtroCtrl = TextEditingController();
  String _filtro = '';
  bool _carregando = true;
  List<dynamic> _materiais = [];

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral)        return null;
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  static const _cores = [
    Color(0xFF1E88E5), Color(0xFF00897B), Color(0xFFE53935),
    Color(0xFFF4511E), Color(0xFF8E24AA), Color(0xFF039BE5),
    Color(0xFF43A047), Color(0xFFFFB300), Color(0xFF6D4C41),
    Color(0xFF546E7A), Color(0xFFD81B60), Color(0xFF5E35B1),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      await context.read<ProducaoProvider>().carregarMateriais(
        categoria: _categoriaParaProvider(),
      );
      if (!mounted) return;
      setState(() {
        _materiais = context.read<ProducaoProvider>().materiais;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<String?> _identificadoresUnicos() {
    final set = <String?>{};
    for (final m in _materiais) {
      final ident = m.identificador as String?;
      set.add(ident?.trim().isNotEmpty == true ? ident!.trim() : null);
    }
    final lista = set.toList();
    lista.sort((a, b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    });
    return lista;
  }

  int _contarMateriais(String? identificador) {
    if (identificador == null) {
      return _materiais.where((m) {
        final ident = m.identificador as String?;
        return ident == null || ident.trim().isEmpty;
      }).length;
    }
    return _materiais.where((m) => (m.identificador as String?)?.trim() == identificador).length;
  }

  void _navegarParaIdentificador({
    required String identificadorId,
    required String? identificadorReal,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProducaoCategoriaPage(
          categoriaId:                 widget.categoriaId,
          categoriaLabel:              widget.categoriaLabel,
          cor:                         widget.cor,
          icone:                       widget.icone,
          identificadorFiltro:         identificadorReal,
          identificadorLabel:          identificadorId == _kIdentificadorTodos
              ? null
              : identificadorId == _kIdentificadorSemIdentificador
                  ? 'Sem identificador'
                  : identificadorId,
          mostrarBotaoIdentificadores: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        SizedBox(width: 6),
                        Text(
                          'Categorias',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.cor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icone, color: widget.cor, size: 20),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.categoriaLabel,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Selecione um identificador para ver os materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  onPressed: _carregar,
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Campo de busca ────────────────────────────────────────────────
            SizedBox(
              width: 360,
              child: TextField(
                controller: _filtroCtrl,
                decoration: InputDecoration(
                  hintText:   'Buscar identificador...',
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
                  isDense:    true,
                  suffixIcon: _filtro.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _filtroCtrl.clear();
                            setState(() => _filtro = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 20),

            // ── Grid de identificadores ───────────────────────────────────────
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _buildGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final identificadores = _identificadoresUnicos();

    bool corresponde(String label) =>
        _filtro.isEmpty || label.toLowerCase().contains(_filtro);

    final cards = <Widget>[];

    // Card "Todos"
    if (corresponde('todos')) {
      cards.add(_IdentificadorCardProducao(
        label:      'Todos',
        quantidade: _materiais.length,
        cor:        widget.cor,
        icone:      Icons.grid_view_rounded,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   _kIdentificadorTodos,
          identificadorReal: null,
        ),
      ));
    }

    // Identificadores reais
    for (int i = 0; i < identificadores.length; i++) {
      final ident = identificadores[i];
      final label = ident ?? 'Sem identificador';
      if (!corresponde(label)) continue;
      final cor = ident == null ? const Color(0xFF546E7A) : _cores[i % _cores.length];
      cards.add(_IdentificadorCardProducao(
        label:      label,
        quantidade: _contarMateriais(ident),
        cor:        cor,
        icone:      ident == null ? Icons.help_outline : Icons.qr_code,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   ident ?? _kIdentificadorSemIdentificador,
          identificadorReal: ident,
        ),
      ));
    }

    if (cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 16),
            Text(
              'Nenhum identificador encontrado',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: GridView.count(
        crossAxisCount:   4,
        crossAxisSpacing: 16,
        mainAxisSpacing:  16,
        childAspectRatio: 1.0,
        shrinkWrap:       true,
        physics:          const NeverScrollableScrollPhysics(),
        children:         cards,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CARD DE IDENTIFICADOR
// ─────────────────────────────────────────────

class _IdentificadorCardProducao extends StatefulWidget {
  final String     label;
  final int        quantidade;
  final Color      cor;
  final IconData   icone;
  final VoidCallback onTap;

  const _IdentificadorCardProducao({
    required this.label,
    required this.quantidade,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_IdentificadorCardProducao> createState() => _IdentificadorCardProducaoState();
}

class _IdentificadorCardProducaoState extends State<_IdentificadorCardProducao> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ativo = _hovered;
    return MouseRegion(
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo ? widget.cor.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo ? widget.cor : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
                ? [BoxShadow(color: widget.cor.withValues(alpha: 0.20), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icone, color: widget.cor, size: 28),
              ),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ativo ? widget.cor : Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${widget.quantidade} ${widget.quantidade == 1 ? "material" : "materiais"}',
                style: TextStyle(
                  fontSize: 11,
                  color: ativo ? widget.cor.withValues(alpha: 0.8) : Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PÁGINA DE MATERIAIS POR CATEGORIA
// ─────────────────────────────────────────────────────────────────────────────

class _ProducaoCategoriaPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String?  identificadorFiltro;
  final String?  identificadorLabel;
  final bool     mostrarBotaoIdentificadores;

  const _ProducaoCategoriaPage({
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    this.identificadorFiltro,
    this.identificadorLabel,
    this.mostrarBotaoIdentificadores = false,
  });

  @override
  State<_ProducaoCategoriaPage> createState() => _ProducaoCategoriaPageState();
}

class _ProducaoCategoriaPageState extends State<_ProducaoCategoriaPage> {
  final _buscaCtrl         = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  String  _statusFiltro    = '';
  Timer?  _debounce;

  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral)        return null;
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  @override
  void initState() {
    super.initState();
    if (widget.identificadorFiltro != null) {
      _identificadorCtrl.text = widget.identificadorFiltro!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarFiltros());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  void _aplicarFiltros() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _paginaAtual = 0);
      context.read<ProducaoProvider>().carregarMateriais(
            busca:         _buscaCtrl.text.trim(),
            categoria:     _categoriaParaProvider(),
            status:        _statusFiltro.isEmpty ? null : _statusFiltro,
            identificador: _identificadorCtrl.text.trim(),
            medida:        _medidaCtrl.text.trim(),
            espessura:     _espessuraCtrl.text.trim(),
          );
    });
  }

  void _limparFiltros() {
    _buscaCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _espessuraCtrl.clear();
    setState(() => _statusFiltro = '');
    context.read<ProducaoProvider>().carregarMateriais(categoria: _categoriaParaProvider());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        SizedBox(width: 6),
                        Text(
                          widget.mostrarBotaoIdentificadores
                              ? widget.categoriaLabel
                              : 'Categorias',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.mostrarBotaoIdentificadores && widget.identificadorLabel != null) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.outline),
                  ),
                  Text(
                    widget.identificadorLabel!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.cor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icone, color: widget.cor, size: 22),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.categoriaLabel,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Solicitação e controle de materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  onPressed: _aplicarFiltros,
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: InputDecoration(
                      hintText:   'Buscar material...',
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense:    true,
                    ),
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFiltro.isEmpty ? '' : _statusFiltro,
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
                    onChanged: (v) {
                      setState(() => _statusFiltro = v ?? '');
                      _aplicarFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off, color: scheme.onSurfaceVariant),
                  onPressed: _limparFiltros,
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: InputDecoration(
                      hintText:   'Identificador...',
                      prefixIcon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: InputDecoration(
                      hintText:   'Medida...',
                      prefixIcon: Icon(Icons.straighten, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: InputDecoration(
                      hintText:   'Espessura...',
                      prefixIcon: Icon(Icons.layers, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
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
                  if (provider.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          SizedBox(height: 12),
                          Text(
                            'Erro ao carregar materiais',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            provider.erro!.contains(': ')
                                ? provider.erro!.substring(
                                    provider.erro!.indexOf(': ') + 2)
                                : provider.erro!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => provider.carregarMateriais(),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    );
                  }
                  if (provider.materiais.isEmpty) {
                    return Center(
                      child: Text(
                        'Nenhum material encontrado',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
                            child: _TabelaMateriais(
                              materiais: paginados,
                              mostrarCategoria: widget.categoriaId == _kCategoriaGeral,
                            ),
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
        ),
      ),
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
  final bool mostrarCategoria;

  const _TabelaMateriais({
    required this.materiais,
    this.mostrarCategoria = true,
  });

  static const List<_ColDef> _todosColsDef = [
    _ColDef(label: 'ID',            fixed: 56),
    _ColDef(label: 'Identificador', flex: 0.7),
    _ColDef(label: 'Material',      flex: 2.0),
    _ColDef(label: 'Categoria',     flex: 1.0),
    _ColDef(label: 'Unidade',       flex: 0.9),
    _ColDef(label: 'Medida',        flex: 0.8),
    _ColDef(label: 'Espessura',     flex: 0.7),
    _ColDef(label: 'Estoque atual', flex: 0.7),
    _ColDef(label: 'Disponível',    flex: 0.7),
    _ColDef(label: 'Status',        flex: 0.8),
  ];

  List<_ColDef> get _cols => mostrarCategoria
      ? _todosColsDef
      : _todosColsDef.where((c) => c.label != 'Categoria').toList();

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  Widget _cabecalho(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            for (final col in _cols)
              _colWrap(
                col,
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    col.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cols = _cols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _cabecalho(context),
        for (int i = 0; i < materiais.length; i++) ...[
          if (i > 0)
            Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
          _LinhaMateria(
            material: materiais[i],
            cols: cols,
            mostrarCategoria: mostrarCategoria,
          ),
        ],
        if (materiais.isNotEmpty)
          Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
      ],
    );
  }
}

class _LinhaMateria extends StatefulWidget {
  final MaterialProducaoModel material;
  final List<_ColDef> cols;
  final bool mostrarCategoria;

  const _LinhaMateria({
    required this.material,
    required this.cols,
    this.mostrarCategoria = true,
  });

  @override
  State<_LinhaMateria> createState() => _LinhaMateriaState();
}

class _LinhaMateriaState extends State<_LinhaMateria> {
  bool _hovered = false;

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  Widget _cell(String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
        ),
      );

  Widget _vDivider() => VerticalDivider(
        width: 1, thickness: 0.5, color: Theme.of(context).colorScheme.outlineVariant,
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
        ? Color(0xFF009800).withValues(alpha: 0.10)
        : Theme.of(context).colorScheme.surface;

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
                _colWrap(cols[0], Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    '${m.id}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )),
                _vDivider(),

                _colWrap(cols[1], _cell(m.identificador?.isNotEmpty == true ? m.identificador! : '—')),
                _vDivider(),

                _colWrap(cols[2], Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    m.nome,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                )),
                _vDivider(),

                if (widget.mostrarCategoria) ...[
                  _colWrap(cols[3], _cell(m.categoria ?? '—')),
                  _vDivider(),
                ],

                _colWrap(cols[widget.mostrarCategoria ? 4 : 3], _cell(m.unidade ?? '—')),
                _vDivider(),

                _colWrap(cols[widget.mostrarCategoria ? 5 : 4], _cell(m.medida ?? '—')),
                _vDivider(),

                _colWrap(cols[widget.mostrarCategoria ? 6 : 5], _cell(m.espessura ?? '—')),
                _vDivider(),

                _colWrap(cols[widget.mostrarCategoria ? 7 : 6], _cell(
                  m.quantidade.toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2),
                )),
                _vDivider(),

                _colWrap(cols[widget.mostrarCategoria ? 8 : 7], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    disponivel.toStringAsFixed(disponivel % 1 == 0 ? 0 : 2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _corStatus(context, m.statusReal),
                    ),
                  ),
                )),
                _vDivider(),

                _colWrap(cols[widget.mostrarCategoria ? 9 : 8], Center(
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

  Color _corStatus(BuildContext context, String status) {
    switch (status) {
      case 'OK':      return AppTheme.statusOk;
      case 'LIMITE':  return AppTheme.statusBaixo;
      case 'CRITICO': return AppTheme.statusCritico;
      default:        return Theme.of(context).colorScheme.outline;
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
      default:        cor = Theme.of(context).colorScheme.outline;
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
// ─────────────────────────────────────────────

class _SolicitarMaterialDialog extends StatefulWidget {
  final MaterialProducaoModel material;
  const _SolicitarMaterialDialog({required this.material});

  @override
  State<_SolicitarMaterialDialog> createState() =>
      _SolicitarMaterialDialogState();
}

class _SolicitarMaterialDialogState extends State<_SolicitarMaterialDialog> {
  final _formKey     = GlobalKey<FormState>();
  final _osCtrl      = TextEditingController();
  final _qtdCtrl     = TextEditingController();
  final _obsCtrl     = TextEditingController();
  final _larguraCtrl = TextEditingController();
  final _alturaCtrl  = TextEditingController();
  bool  _enviando         = false;
  bool  _modoDimensional  = false;
  String? _erro;

  @override
  void dispose() {
    _osCtrl.dispose();
    _qtdCtrl.dispose();
    _obsCtrl.dispose();
    _larguraCtrl.dispose();
    _alturaCtrl.dispose();
    super.dispose();
  }

  /// True se a unidade do material é metro linear (m, m/l, ml, etc.).
  bool get _eMetroLinear {
    final u = widget.material.unidade?.toLowerCase().trim() ?? '';
    return const {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'}.contains(u);
  }

  /// True se o material é UNIDADE (chapa/peça) e tem largura + comprimento
  /// cadastrados.
  bool get _podeInformarDimensao {
    final m = widget.material;
    if (_eMetroLinear) return false;
    return (m.unidade?.toUpperCase() == 'UNIDADE') &&
        m.largura != null && m.largura! > 0 &&
        m.comprimento != null && m.comprimento! > 0;
  }

  /// Custo por m² sugerido para este material (gravado ou derivado do
  /// custo unitário / área da chapa).
  double? get _custoM2Sugerido {
    final m = widget.material;
    final custoM2Gravado = m.ultimoValorPagoM2;
    if (custoM2Gravado != null && custoM2Gravado > 0) return custoM2Gravado;

    final larg = m.largura;
    final comp = m.comprimento;
    if (larg != null && comp != null && larg > 0 && comp > 0) {
      final pu = m.ultimoValorPago;
      if (pu != null && pu > 0) return pu / (larg * comp);
    }
    return null;
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    final os = _osCtrl.text.trim();
    
    final qtd = _modoDimensional 
        ? 1.0 
        : double.tryParse(_qtdCtrl.text.replaceAll(',', '.'));

    if (qtd == null || qtd <= 0) {
      setState(() => _erro = 'Quantidade inválida');
      return;
    }

    setState(() { _enviando = true; _erro = null; });

    double? largUsada;
    double? compUsado;
    if (_modoDimensional && _podeInformarDimensao) {
      final l = double.tryParse(_larguraCtrl.text.replaceAll(',', '.'));
      final c = double.tryParse(_alturaCtrl.text.replaceAll(',', '.'));
      if (l != null && l > 0 && c != null && c > 0) {
        largUsada = l;
        compUsado = c;
      }
    }

    final ok = await context.read<ProducaoProvider>().criarSolicitacao(
          materialId:          widget.material.id,
          quantidadeReservada: qtd,
          numeroOS:            os,
          larguraUsada:        largUsada,
          comprimentoUsado:    compUsado,
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
    final m = widget.material;
    final disponivel = m.quantidade + m.emUso;
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (detalhes.isNotEmpty) ...[
                SizedBox(height: 2),
                Text(
                  detalhes.join(' · '),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),

              TextFormField(
                controller: _osCtrl,
                autofocus: true,
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

              Builder(builder: (_) {
                final m = widget.material;
                if (!_podeInformarDimensao) {
                  return const SizedBox.shrink();
                }
                final largura     = m.largura!;
                final comprimento = m.comprimento!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setState(() {
                        _modoDimensional = !_modoDimensional;
                        if (_modoDimensional) {
                          _qtdCtrl.text = '1';
                          _larguraCtrl.clear();
                          _alturaCtrl.clear();
                        } else {
                          _larguraCtrl.clear();
                          _alturaCtrl.clear();
                          _qtdCtrl.clear();
                        }
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _modoDimensional
                                  ? Icons.toggle_on
                                  : Icons.toggle_off_outlined,
                              size: 20,
                              color: _modoDimensional
                                  ? AppTheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Informar dimensão usada',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _modoDimensional
                                    ? AppTheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Chapa ${_fmt(comprimento)}×${_fmt(largura)} m',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_modoDimensional) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _alturaCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Comprimento usado (m)',
                                isDense:    true,
                                suffixText: '/ ${_fmt(comprimento)} m',
                                suffixStyle: TextStyle(
                                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('×',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _larguraCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Largura usada (m)',
                                isDense:    true,
                                suffixText: '/ ${_fmt(largura)} m',
                                suffixStyle: TextStyle(
                                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),

                      Builder(builder: (_) {
                        final comp = double.tryParse(
                            _alturaCtrl.text.replaceAll(',', '.'));
                        final larg = double.tryParse(
                            _larguraCtrl.text.replaceAll(',', '.'));
                        if (larg == null || larg <= 0 ||
                            comp == null || comp <= 0) {
                          return const SizedBox.shrink();
                        }
                        final areaUsada   = larg * comp;
                        final areaTotal   = largura * comprimento;
                        final areaRetalho = double.parse(
                            (areaTotal - areaUsada).toStringAsFixed(4));
                        final temRetalho  = areaRetalho > 0.0001;

                        final custoM2 = _custoM2Sugerido;
                        final custoProporcional =
                            (custoM2 != null && custoM2 > 0)
                                ? custoM2 * areaUsada
                                : null;

                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.20)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calculate_outlined,
                                  size: 14, color: AppTheme.primary),
                              SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    children: [
                                      TextSpan(text: 'Área usada: '),
                                      TextSpan(
                                        text: '${_fmt(areaUsada)} m²',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context).colorScheme.onSurface),
                                      ),
                                      if (temRetalho) ...[
                                        TextSpan(text: '  ·  Retalho: '),
                                        TextSpan(
                                          text: '${_fmt(areaRetalho)} m²',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.success),
                                        ),
                                      ],
                                      if (custoProporcional != null) ...[
                                        TextSpan(text: '  ·  Custo: '),
                                        TextSpan(
                                          text: _brl6(custoProporcional),
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.error),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 4),
                  ],
                );
              }),

              TextFormField(
                controller: _qtdCtrl,
                decoration: InputDecoration(
                  labelText: 'Quantidade *',
                  isDense:   true,
                  suffixText: unidade,
                  helperText: _modoDimensional
                      ? 'Bloqueado: quantidade fixa em 1'
                      : null,
                  helperStyle: TextStyle(
                      fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                readOnly: _modoDimensional,
                validator: (v) {
                  if (_erro != null) return _erro;
                  final qtd =
                      double.tryParse((v ?? '').replaceAll(',', '.'));
                  if (qtd == null || qtd <= 0) return 'Quantidade inválida';
                  return null;
                },
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
              ),
              SizedBox(height: 8),
              Text(
                'Disponível: ${disponivel.toStringAsFixed(disponivel % 1 == 0 ? 0 : 2)} $unidade',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _obsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  isDense:   true,
                ),
                maxLines: 2,
              ),

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
          onPressed: _enviando ? null : _confirmar,
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

// ─────────────────────────────────────────────
// ABA HISTÓRICO
// ─────────────────────────────────────────────────────────────────────────

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
        SizedBox(height: 16),
        TextField(
          controller: _buscaCtrl,
          decoration: InputDecoration(
            hintText:   'Buscar por OS ou usuário...',
            prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
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
                return Center(
                  child: Text(
                    'Nenhuma saída registrada',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
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

// ─────────────────────────────────────────────
// CARD DO HISTÓRICO
// ─────────────────────────────────────────────

class _HistoricoCard extends StatelessWidget {
  final SolicitacaoProducaoModel solicitacao;
  const _HistoricoCard({required this.solicitacao});

  // Datas já chegam convertidas para fuso local via .toLocal() no model.

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
    final data   = s.finalizadoEm ?? s.atualizadoEm;
    final dataStr = '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year} '
        '${data.hour.toString().padLeft(2, '0')}:'
        '${data.minute.toString().padLeft(2, '0')}';

    final detalhes = <String>[];
    if (s.materialIdentificador != null&& s.materialIdentificador!.isNotEmpty) {
      detalhes.add(s.materialIdentificador!);
    }
    if (s.materialMedida != null) detalhes.add(s.materialMedida!);
    if (s.materialEspessura != null) detalhes.add(s.materialEspessura!);

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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    s.materialNome,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (detalhes.isNotEmpty)
                    Text(
                      detalhes.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  Text(
                    'Usuário: ${s.usuarioNome}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  dataStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
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

// ─────────────────────────────────────────────
// PAGINAÇÃO
// ─────────────────────────────────────────────

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
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Exibindo $inicio–$fim de $totalItens',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              SizedBox(width: 4),
              for (final p in paginas) ...[
                if (p == -1)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
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
              color: enabled ? Theme.of(context).colorScheme.outlineVariant : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.outline,
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
            color: ativa ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '${numero + 1}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: ativa ? FontWeight.w700 : FontWeight.w400,
            color: ativa ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}