import 'dart:async';
import 'dart:io';
import 'historico_material_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/material_model.dart';
import '../providers/estoque_provider.dart';
import '../providers/material_provider.dart';
import '../providers/orcamento_provider.dart';
import '../repositories/estoque_repository.dart';
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
    // Remove vírgulas antes de qualquer outra transformação
    final semVirgula = newValue.text.replaceAll(',', '');
    final texto = _removerAcentos(semVirgula).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

/// Bloqueia a digitação de vírgula em campos de texto livre (busca, descrição, etc.)
class _NoCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.contains(',')) {
      return oldValue;
    }
    return newValue;
  }
}

class _DecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(',', '.');
    texto = texto.replaceAll(RegExp(r'[^\d.]'), '');
    final partes = texto.split('.');
    if (partes.length > 2) {
      texto = '${partes[0]}.${partes.sublist(1).join('')}';
    }
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TELA PRINCIPAL: busca + grade de categorias + tabela inline
// ─────────────────────────────────────────────────────────────────────────────

// Sentinel para cards especiais
const _kCategoriaGeral       = '__GERAL__';
const _kCategoriaSemCategoria = '__SEM_CATEGORIA__';

class EstoquePage extends StatefulWidget {
  final String roleUsuario;
  const EstoquePage({super.key, required this.roleUsuario});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  // ── Filtro de categorias ───────────────────────────────────────────────────
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria    = '';

  // ── Ícones e cores ─────────────────────────────────────────────────────────
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MaterialProvider>().carregarCategorias();
    });
  }

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
            ? EstoqueCategoriaPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
                roleUsuario:    widget.roleUsuario,
              )
            : EstoqueIdentificadorPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
                roleUsuario:    widget.roleUsuario,
              ),
      ),
    ).then((_) {
      // Recarrega categorias ao voltar (pode ter sido criada/removida alguma)
      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estoque',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Selecione uma categoria para ver os materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => context.read<MaterialProvider>().carregarCategorias(),
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

            // ── Campo de busca de categorias ───────────────────────────────
            SizedBox(
              width: 360,
              child: TextField(
                controller: _filtroCategoriaCtrl,
                inputFormatters: [_NoCommaFormatter()],
                decoration: InputDecoration(
                  hintText:   'Buscar categoria...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textHint, size: 20),
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

            // ── Grid de categorias ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Consumer<MaterialProvider>(
                  builder: (_, provider, __) {
                    if (provider.carregando && provider.categorias.isEmpty) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                      );
                    }

                    final especiais = <_CardEspecialData>[
                      const _CardEspecialData(
                        id:    _kCategoriaGeral,
                        label: 'Geral',
                        icone: Icons.grid_view_rounded,
                        cor:   Color(0xFF5E35B1),
                      ),
                      const _CardEspecialData(
                        id:    _kCategoriaSemCategoria,
                        label: 'Sem categoria',
                        icone: Icons.help_outline,
                        cor:   Color(0xFF546E7A),
                      ),
                    ];

                    bool corresponde(String label) =>
                        _filtroCategoria.isEmpty ||
                        label.toLowerCase().contains(_filtroCategoria);

                    final todosCards = <Widget>[
                      for (final esp in especiais)
                        if (corresponde(esp.label))
                          _CategoriaCardCompact(
                            categoria: esp.label,
                            cor:       esp.cor,
                            icone:     esp.icone,
                            onTap: () => _navegarParaCategoria(
                              categoriaId:    esp.id,
                              categoriaLabel: esp.label,
                              cor:            esp.cor,
                              icone:          esp.icone,
                            ),
                          ),
                      for (int i = 0; i < provider.categorias.length; i++)
                        if (corresponde(provider.categorias[i]))
                          _CategoriaCardCompact(
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

                    if (todosCards.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.search_off,
                                  size: 64, color: AppTheme.textHint),
                              const SizedBox(height: 16),
                              Text(
                                _filtroCategoria.isNotEmpty
                                    ? 'Nenhuma categoria encontrada'
                                    : 'Nenhuma categoria cadastrada',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: AppTheme.textSecondary),
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
                      children:         todosCards,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG DE SELEÇÃO DE STATUS PARA EXPORTAR PDF
// ─────────────────────────────────────────────────────────────────────────────

class _ExportarPdfDialog extends StatefulWidget {
  const _ExportarPdfDialog();

  @override
  State<_ExportarPdfDialog> createState() => _ExportarPdfDialogState();
}

class _ExportarPdfDialogState extends State<_ExportarPdfDialog> {
  String _statusSelecionado = 'TODOS';

  static const _opcoes = [
    ('TODOS',   'Todos os status',   Icons.list_alt,          AppTheme.primary),
    ('OK',      'OK',                Icons.check_circle,       Color(0xFF15803D)),
    ('LIMITE',  'Limite',            Icons.warning_amber,      Color(0xFFD97706)),
    ('CRITICO', 'Crítico',           Icons.error_outline,      Color(0xFFDC2626)),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.picture_as_pdf, color: AppTheme.primary, size: 22),
          SizedBox(width: 10),
          Text('Exportar PDF de Estoque'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione quais materiais deseja incluir no relatório:',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ..._opcoes.map((opcao) {
              final (valor, label, icone, cor) = opcao;
              final selecionado = _statusSelecionado == valor;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _statusSelecionado = valor),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: selecionado
                          ? cor.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selecionado
                            ? cor
                            : AppTheme.textHint.withValues(alpha: 0.25),
                        width: selecionado ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icone, size: 18, color: selecionado ? cor : AppTheme.textSecondary),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selecionado ? FontWeight.w700 : FontWeight.w400,
                            color: selecionado ? cor : AppTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (selecionado)
                          Icon(Icons.check, size: 16, color: cor),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_statusSelecionado),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Exportar'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE IDENTIFICADORES (nível 2 da hierarquia: categoria → identificador)
// ─────────────────────────────────────────────────────────────────────────────

const _kIdentificadorTodos       = '__TODOS__';
const _kIdentificadorSemIdentificador = '__SEM_IDENTIFICADOR__';

class EstoqueIdentificadorPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String   roleUsuario;

  const EstoqueIdentificadorPage({
    super.key,
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    required this.roleUsuario,
  });

  @override
  State<EstoqueIdentificadorPage> createState() => _EstoqueIdentificadorPageState();
}

class _EstoqueIdentificadorPageState extends State<EstoqueIdentificadorPage> {
  final _filtroCtrl = TextEditingController();
  String _filtro = '';
  bool _carregando = true;
  List<MaterialModel> _materiais = [];

  // ── Helpers de ícone / cor para identificadores ──────────────────────────
  static const _cores = [
    Color(0xFF1E88E5), Color(0xFF00897B), Color(0xFFE53935),
    Color(0xFFF4511E), Color(0xFF8E24AA), Color(0xFF039BE5),
    Color(0xFF43A047), Color(0xFFFFB300), Color(0xFF6D4C41),
    Color(0xFF546E7A), Color(0xFFD81B60), Color(0xFF5E35B1),
  ];

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral)        return null;
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

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
      await context.read<MaterialProvider>().buscarSugestoes(
        '',
        limite: 9999,
      );
      // buscarSugestoes não filtra por categoria; fazemos aqui no client:
      // Melhor usar o repo diretamente via provider.carregar e capturar o resultado.
      // Mas como não temos acesso direto, usamos o provider normalmente.
      if (!mounted) return;
      // Carrega tudo da categoria no provider para extrair identificadores
      await context.read<MaterialProvider>().carregar(
        categoria: _categoriaParaProvider(),
      );
      if (!mounted) return;
      setState(() {
        _materiais = context.read<MaterialProvider>().materiais;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Extrai identificadores únicos dos materiais (null → sem identificador).
  List<String?> _identificadoresUnicos() {
    final set = <String?>{};
    for (final m in _materiais) {
      set.add(m.identificador?.trim().isNotEmpty == true ? m.identificador!.trim() : null);
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
      return _materiais.where((m) =>
        m.identificador == null || m.identificador!.trim().isEmpty).length;
    }
    return _materiais.where((m) =>
      m.identificador?.trim() == identificador).length;
  }

  void _navegarParaIdentificador({
    required String identificadorId,
    required String? identificadorReal,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EstoqueCategoriaPage(
          categoriaId:          widget.categoriaId,
          categoriaLabel:       widget.categoriaLabel,
          cor:                  widget.cor,
          icone:                widget.icone,
          identificadorFiltro:  identificadorReal,
          identificadorLabel:   identificadorId == _kIdentificadorTodos
              ? null
              : identificadorId == _kIdentificadorSemIdentificador
                  ? 'Sem identificador'
                  : identificadorId,
          mostrarBotaoIdentificadores: true,
          roleUsuario: widget.roleUsuario,
        ),
      ),
    );
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
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.divider),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 18, color: AppTheme.textSecondary),
                        SizedBox(width: 6),
                        Text(
                          'Categorias',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
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
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.categoriaLabel,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Selecione um identificador para ver os materiais',
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

            // ── Campo de busca ────────────────────────────────────────────────
            SizedBox(
              width: 360,
              child: TextField(
                controller: _filtroCtrl,
                inputFormatters: [_NoCommaFormatter()],
                decoration: InputDecoration(
                  hintText:   'Buscar identificador...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textHint, size: 20),
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
      cards.add(_IdentificadorCard(
        label:       'Todos',
        quantidade:  _materiais.length,
        cor:         widget.cor,
        icone:       Icons.grid_view_rounded,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   _kIdentificadorTodos,
          identificadorReal: null, // sem filtro de identificador
        ),
      ));
    }

    // Identificadores reais
    for (int i = 0; i < identificadores.length; i++) {
      final ident = identificadores[i];
      final label = ident ?? 'Sem identificador';
      if (!corresponde(label)) continue;
      final cor = ident == null
          ? const Color(0xFF546E7A)
          : _cores[i % _cores.length];
      cards.add(_IdentificadorCard(
        label:       label,
        quantidade:  _contarMateriais(ident),
        cor:         cor,
        icone:       ident == null ? Icons.help_outline : Icons.qr_code,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   ident ?? _kIdentificadorSemIdentificador,
          identificadorReal: ident, // null = sem identificador
        ),
      ));
    }

    if (cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text(
              'Nenhum identificador encontrado',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppTheme.textSecondary),
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

// ─────────────────────────────────────────────────────────────────────────────
// CARD DE IDENTIFICADOR
// ─────────────────────────────────────────────────────────────────────────────

class _IdentificadorCard extends StatefulWidget {
  final String   label;
  final int      quantidade;
  final Color    cor;
  final IconData icone;
  final VoidCallback onTap;

  const _IdentificadorCard({
    required this.label,
    required this.quantidade,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_IdentificadorCard> createState() => _IdentificadorCardState();
}

class _IdentificadorCardState extends State<_IdentificadorCard> {
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
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo
                ? widget.cor.withValues(alpha: 0.12)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo
                  ? widget.cor
                  : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
                ? [
                    BoxShadow(
                      color: widget.cor.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
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
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ativo ? widget.cor : AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.quantidade} ${widget.quantidade == 1 ? "material" : "materiais"}',
                style: TextStyle(
                  fontSize: 11,
                  color: ativo
                      ? widget.cor.withValues(alpha: 0.8)
                      : AppTheme.textHint,
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

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE MATERIAIS POR CATEGORIA
// ─────────────────────────────────────────────────────────────────────────────

class EstoqueCategoriaPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String?  buscaInicial;
  /// Quando não-null, filtra automaticamente pelo identificador escolhido na
  /// página anterior (EstoqueIdentificadorPage). String vazia = sem identificador.
  /// null especial vindo de _kIdentificadorTodos = sem filtro de identificador.
  final String?  identificadorFiltro;
  /// Rótulo do identificador para exibir no breadcrumb (null = sem filtro).
  final String?  identificadorLabel;
  /// Se true, exibe breadcrumb de volta à tela de identificadores.
  final bool     mostrarBotaoIdentificadores;
  final String   roleUsuario;

  const EstoqueCategoriaPage({
    super.key,
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    this.buscaInicial,
    this.identificadorFiltro,
    this.identificadorLabel,
    this.mostrarBotaoIdentificadores = false,
    required this.roleUsuario,
  });

  @override
  State<EstoqueCategoriaPage> createState() => _EstoqueCategoriaPageState();
}

class _EstoqueCategoriaPageState extends State<EstoqueCategoriaPage> {
  late final TextEditingController _buscaCtrl;
  final _buscaIdCtrl       = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  String _statusFiltro         = '';
  bool   _somenteFornecedor    = false;
  Timer? _debounceTimer;

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
    _buscaCtrl = TextEditingController(text: widget.buscaInicial ?? '');
    // Pré-preenche o filtro de identificador vindo da página anterior
    if (widget.identificadorFiltro != null) {
      _identificadorCtrl.text = widget.identificadorFiltro!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarFiltros());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    _buscaIdCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  void _aplicarFiltros() {
    setState(() => _paginaAtual = 0);
    context.read<MaterialProvider>().carregar(
          busca:         _buscaCtrl.text,
          categoria:     _categoriaParaProvider(),
          status:        _statusFiltro,
          id:            _buscaIdCtrl.text.trim(),
          identificador: _identificadorCtrl.text.trim(),
          medida:        _medidaCtrl.text.trim(),
          espessura:     _espessuraCtrl.text.trim(),
          // somenteFornecedor é filtrado localmente pelo _somenteFornecedor bool
        );
  }

  /// Recarrega a lista mantendo a página e o scroll atuais.
  /// Usar após editar/desativar/reativar um material.
  void _recarregarSemResetarPagina() {
    context.read<MaterialProvider>().carregar(
          busca:         _buscaCtrl.text,
          categoria:     _categoriaParaProvider(),
          status:        _statusFiltro,
          id:            _buscaIdCtrl.text.trim(),
          identificador: _identificadorCtrl.text.trim(),
          medida:        _medidaCtrl.text.trim(),
          espessura:     _espessuraCtrl.text.trim(),
        );
  }

  // ── Ações de material ──────────────────────────────────────────────────────

  void _abrirHistoricoPrecos(MaterialModel material) {
    showDialog(
      context: context,
      builder: (_) => _HistoricoPrecoDialog(material: material),
    );
  }

  Future<void> _abrirFormMaterial([MaterialModel? material]) async {
    final isCompras = widget.roleUsuario == 'COMPRAS';
    if (isCompras && material != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para editar materiais.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    final salvou = await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MaterialFormDialog(
        material:    material,
        onDesativar: (!isCompras && material != null) ? _desativar : null,
        onReativar:  (!isCompras && material != null) ? _reativar  : null,
        onExcluir:   (!isCompras && material != null) ? _excluir   : null,
      ),
    );
    if (!mounted) return;
    if (salvou == true) {
      context.read<MaterialProvider>().carregarCategorias();
      _recarregarSemResetarPagina();
    }
  }

  void _abrirPrecosFornecedores(MaterialModel material) {
    showDialog(
      context: context,
      builder: (_) => _PrecosFornecedoresDialog(material: material),
    );
  }

  Future<void> _desativar(MaterialModel m) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Desativar material'),
        content: Text(
          'Deseja desativar "${m.nome}"?\n\nSe ele estiver vinculado a ordens em andamento, a operação será bloqueada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final ok = await context.read<MaterialProvider>().desativar(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '"${m.nome}" desativado.' : context.read<MaterialProvider>().erro ?? 'Erro'),
      backgroundColor: ok ? AppTheme.warning : AppTheme.error,
    ));
  }

  Future<void> _reativar(MaterialModel m) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reativar material'),
        content: Text('Deseja reativar "${m.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Reativar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final ok = await context.read<MaterialProvider>().reativar(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '"${m.nome}" reativado.' : context.read<MaterialProvider>().erro ?? 'Erro'),
      backgroundColor: ok ? AppTheme.success : AppTheme.error,
    ));
  }

  Future<void> _excluir(MaterialModel m) async {
    if (m.ativo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Desative o material antes de excluí-lo.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir material'),
        content: Text('Tem certeza que deseja excluir "${m.nome}" permanentemente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final ok = await context.read<MaterialProvider>().excluir(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '"${m.nome}" excluído.' : context.read<MaterialProvider>().erro ?? 'Erro'),
      backgroundColor: AppTheme.error,
    ));
  }

  Future<void> _exportarPdf() async {
    // ── 1. Pedir ao usuário qual status deseja exportar ─────────────────────
    final statusEscolhido = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return const _ExportarPdfDialog();
      },
    );
    if (statusEscolhido == null) return; // cancelou

    // ── 2. Mostrar progresso ────────────────────────────────────────────────
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 3),
        backgroundColor: AppTheme.primary,
      ),
    );

    final String? catParam = widget.categoriaId == _kCategoriaGeral
        ? null
        : widget.categoriaId == _kCategoriaSemCategoria
            ? ''
            : widget.categoriaId;

    // 'TODOS' → não passa status (backend interpreta como sem filtro)
    final String? statusParam =
        statusEscolhido == 'TODOS' ? null : statusEscolhido;

    try {
      final bytes = await EstoqueRepository().baixarPdf(
        categoria: catParam,
        status:    statusParam,
      );

      // Valida que a resposta é realmente um PDF
      if (bytes.length < 4 ||
          bytes[0] != 0x25 || bytes[1] != 0x50 ||
          bytes[2] != 0x44 || bytes[3] != 0x46) {
        throw Exception('O servidor não retornou um PDF válido. Verifique o console do backend.');
      }

      final catLabel = widget.categoriaId == _kCategoriaGeral
          ? 'GERAL'
          : widget.categoriaId == _kCategoriaSemCategoria
              ? 'SEM_CATEGORIA'
              : widget.categoriaId.toUpperCase().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final stLabel  = statusParam ?? 'TODOS';
      final fileName = 'estoque_${catLabel}_$stLabel.pdf';

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (Platform.isWindows) {
        // 'start' abre com o programa padrão associado ao .pdf no Windows
        await Process.run('cmd', ['/c', 'start', '', file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Orçar materiais filtrados ──────────────────────────────────────────────
  Future<void> _orcarFiltrados() async {
    final materiais = context.read<MaterialProvider>().materiais;
    if (materiais.isEmpty) return;

    // Monta os itens para o orçamento com os dados de preço de cada material
    final itens = materiais.map((m) {
      final precos = <int, PrecoFornecedorData>{};
      for (final fm in m.fornecedorMateriais) {
        precos[fm.fornecedorId] = PrecoFornecedorData(
          fornecedorNome: fm.fornecedorNome,
          preco:   fm.preco > 0 ? fm.preco : null,
          precoM2: fm.precoMetroQuadrado > 0 ? fm.precoMetroQuadrado : null,
        );
      }
      return ItemOrcamentoData(
        materialId:            m.id,
        materialNome:          m.nome,
        materialUnidade:       m.unidade,
        materialCategoria:     m.categoria,
        materialMedida:        m.medida,
        materialEspessura:     m.espessura,
        materialIdentificador: m.identificador,
        materialStatus:        m.status,
        materialEspecifico:    m.especifico,
        precos:                precos,
      );
    }).toList();

    // Monta um título descritivo baseado nos filtros ativos
    final partes = <String>[];
    if (widget.categoriaId != _kCategoriaGeral &&
        widget.categoriaId != _kCategoriaSemCategoria) {
      partes.add(widget.categoriaLabel);
    }
    if (_medidaCtrl.text.trim().isNotEmpty) {
      partes.add(_medidaCtrl.text.trim());
    }
    if (_espessuraCtrl.text.trim().isNotEmpty) {
      partes.add(_espessuraCtrl.text.trim());
    }
    if (_buscaCtrl.text.trim().isNotEmpty) {
      partes.add(_buscaCtrl.text.trim());
    }
    final titulo = partes.isNotEmpty
        ? 'Orç. ${partes.join(' · ')}'
        : 'Orç. ${widget.categoriaLabel}';

    if (!mounted) return;
    context.read<OrcamentoProvider>().adicionarItensEmLote(titulo, itens);

    context.go('/orcamento');
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cor    = widget.cor;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho com botão voltar ──────────────────────────────────
            Row(
              children: [
                // Botão voltar
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.divider),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back, size: 18, color: AppTheme.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          widget.mostrarBotaoIdentificadores
                              ? widget.categoriaLabel
                              : 'Categorias',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Ícone da categoria
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icone, color: cor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Breadcrumb: Categoria › Identificador (se veio da tela de identificadores)
                    if (widget.mostrarBotaoIdentificadores && widget.identificadorLabel != null)
                      Row(
                        children: [
                          Text(
                            widget.categoriaLabel,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textHint),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.chevron_right, size: 14, color: AppTheme.textHint),
                          ),
                          Text(
                            widget.identificadorLabel!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: cor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    Text(
                      widget.mostrarBotaoIdentificadores && widget.identificadorLabel != null
                          ? widget.identificadorLabel!
                          : widget.categoriaLabel,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Materiais desta categoria',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                // ▼ NOVO — botão Histórico à esquerda do Orçar filtrados
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HistoricoMaterialPage(),
                    ),
                  ),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Histórico'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                // ── fim da adição ──────────────────────────────────────────
                Consumer<MaterialProvider>(
                  builder: (_, mp, __) {
                    final temMateriais = !mp.carregando && mp.materiais.isNotEmpty;
                    return Tooltip(
                      message: temMateriais
                          ? 'Criar orçamento com os ${mp.materiais.length} material(is) filtrado(s)'
                          : 'Nenhum material filtrado',
                      child: OutlinedButton.icon(
                        onPressed: temMateriais ? _orcarFiltrados : null,
                        icon: const Icon(Icons.request_quote, size: 18),
                        label: Text(
                          temMateriais
                              ? 'Orçar filtrados (${mp.materiais.length})'
                              : 'Orçar filtrados',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E88E5),
                          side: BorderSide(
                            color: temMateriais
                                ? const Color(0xFF1E88E5)
                                : AppTheme.textHint,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _exportarPdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Exportar Estoque (PDF)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE85D04),
                    side: const BorderSide(color: Color(0xFFE85D04)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _abrirFormMaterial(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo Material'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _aplicarFiltros,
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

            // ── Filtros linha 1 ────────────────────────────────────────────
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _buscaIdCtrl,
                    decoration: const InputDecoration(
                      hintText:   'ID...',
                      prefixIcon: Icon(Icons.tag, color: AppTheme.textHint, size: 18),
                      isDense:    true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    inputFormatters: [_NoCommaFormatter()],
                    decoration: const InputDecoration(
                      hintText:   'Buscar material...',
                      prefixIcon: Icon(Icons.search, color: AppTheme.textHint, size: 20),
                      isDense:    true,
                    ),
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFiltro.isEmpty ? null : _statusFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      isDense:   true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '',        child: Text('TODOS')),
                      DropdownMenuItem(value: 'OK',      child: Text('OK')),
                      DropdownMenuItem(value: 'LIMITE',  child: Text('LIMITE')),
                      DropdownMenuItem(value: 'CRITICO', child: Text('CRITICO')),
                      DropdownMenuItem(value: 'INATIVO', child: Text('INATIVO')),
                    ],
                    onChanged: (v) {
                      setState(() => _statusFiltro = v ?? '');
                      _aplicarFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Com fornecedor'),
                  avatar: Icon(
                    Icons.store_outlined,
                    size: 16,
                    color: _somenteFornecedor ? AppTheme.primary : AppTheme.textHint,
                  ),
                  selected: _somenteFornecedor,
                  onSelected: (v) {
                    setState(() => _somenteFornecedor = v);
                    _aplicarFiltros();
                  },
                  selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                  checkmarkColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: _somenteFornecedor ? AppTheme.primary : AppTheme.textSecondary,
                    fontWeight: _somenteFornecedor ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: _somenteFornecedor
                        ? AppTheme.primary
                        : AppTheme.textHint.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off, color: scheme.onSurfaceVariant),
                  onPressed: () {
                    _buscaCtrl.clear();
                    _buscaIdCtrl.clear();
                    _identificadorCtrl.clear();
                    _medidaCtrl.clear();
                    _espessuraCtrl.clear();
                    setState(() {
                      _statusFiltro      = '';
                      _somenteFornecedor = false;
                    });
                    context.read<MaterialProvider>().carregar(
                          categoria: _categoriaParaProvider(),
                        );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Filtros linha 2 ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: const InputDecoration(
                      hintText:   'Identificador...',
                      prefixIcon: Icon(Icons.qr_code, color: AppTheme.textHint, size: 18),
                      isDense:    true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: const InputDecoration(
                      hintText:   'Medida...',
                      prefixIcon: Icon(Icons.straighten, color: AppTheme.textHint, size: 18),
                      isDense:    true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: const InputDecoration(
                      hintText:   'Espessura...',
                      prefixIcon: Icon(Icons.layers, color: AppTheme.textHint, size: 18),
                      isDense:    true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Tabela ─────────────────────────────────────────────────────
            Expanded(
              child: Consumer<MaterialProvider>(
                builder: (_, provider, __) {
                  if (provider.carregando) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    );
                  }
                  if (provider.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                          const SizedBox(height: 12),
                          Text(
                            provider.erro!,
                            style: const TextStyle(color: AppTheme.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _aplicarFiltros,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    );
                  }
                  if (provider.materiais.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 64, color: AppTheme.textHint),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum material encontrado',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Clique em "Novo Material" para adicionar.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppTheme.textHint),
                          ),
                        ],
                      ),
                    );
                  }

                  final todos        = provider.materiais;
                  final totalPaginas = (todos.length / _itensPorPagina).ceil();
                  final paginaSegura = _paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
                  final inicio       = paginaSegura * _itensPorPagina;
                  final fim          = (inicio + _itensPorPagina).clamp(0, todos.length);
                  final paginados    = todos.sublist(inicio, fim);

                  final mostrarCat = widget.categoriaId == _kCategoriaGeral ||
                                     widget.categoriaId == _kCategoriaSemCategoria;
                  return Column(
                    children: [
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: _TabelaMateriais(
                            materiais:            paginados,
                            onEditar:             _abrirFormMaterial,
                            onVerFornecedores:    _abrirPrecosFornecedores,
                            onVerHistoricoPrecos: _abrirHistoricoPrecos,
                            mostrarCategoria:     mostrarCat,
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

// Dados de um card especial (Geral / Sem categoria)
class _CardEspecialData {
  final String id;
  final String label;
  final IconData icone;
  final Color cor;
  const _CardEspecialData({
    required this.id,
    required this.label,
    required this.icone,
    required this.cor,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD COMPACTO DE CATEGORIA (horizontal scroll)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoriaCardCompact extends StatefulWidget {
  final String categoria;
  final Color cor;
  final IconData icone;
  final VoidCallback onTap;

  const _CategoriaCardCompact({
    required this.categoria,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_CategoriaCardCompact> createState() => _CategoriaCardCompactState();
}

class _CategoriaCardCompactState extends State<_CategoriaCardCompact> {
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
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo
                ? widget.cor.withValues(alpha: 0.12)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo
                  ? widget.cor
                  : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
                ? [
                    BoxShadow(
                      color: widget.cor.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  widget.categoria,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ativo ? widget.cor : AppTheme.textPrimary,
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
            'Exibindo $inicio–$fim de $totalItens materiais',
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border(
          left: BorderSide(color: color, width: 3),
          bottom: BorderSide(color: color.withValues(alpha: 0.2), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String message;
  const _EmptySection({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.divider, width: 0.8),
        ),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 13, color: AppTheme.textHint),
        ),
      ),
    );
  }
}

class _TabelaMateriais extends StatefulWidget {
  final List<MaterialModel> materiais;
  final void Function(MaterialModel) onEditar;
  final void Function(MaterialModel) onVerFornecedores;
  final void Function(MaterialModel) onVerHistoricoPrecos;
  final bool mostrarCategoria;
 
  const _TabelaMateriais({
    required this.materiais,
    required this.onEditar,
    required this.onVerFornecedores,
    required this.onVerHistoricoPrecos,
    this.mostrarCategoria = true,
  });

  static const List<_ColDef> _colsBase = [
    _ColDef(label: 'ID',                          fixed: 56,  sortKey: 'id'),
    _ColDef(label: 'Identificador',               flex: 0.7,  sortKey: 'identificador'),
    _ColDef(label: 'Material',                    flex: 2.0,  sortKey: 'nome'),
    _ColDef(label: 'Categoria',                   flex: 1.0,  sortKey: 'categoria'),
    _ColDef(label: 'Medida',                      flex: 0.8,  sortKey: 'medida'),
    _ColDef(label: 'Espessura',                   flex: 0.7,  sortKey: 'espessura'),
    _ColDef(label: 'Largura',                     flex: 0.7,  sortKey: 'largura'),
    _ColDef(label: 'Comprimento',                 flex: 0.8,  sortKey: 'comprimento'),
    _ColDef(label: 'Estoque atual',               flex: 0.6,  sortKey: 'quantidade'),
    _ColDef(label: 'Estoque mínimo',              flex: 0.6,  sortKey: 'estoqueMinimo'),
    _ColDef(label: 'Unidade',                     flex: 0.9,  sortKey: 'unidade'),
    _ColDef(label: 'Valor Intermediário',         flex: 0.9,  sortKey: 'precoMediano'),
    _ColDef(label: 'Valor m² Intermediário',      flex: 0.9,  sortKey: 'precoM2Mediano'),
    _ColDef(label: 'Custo (Últimas compras)',     flex: 0.9,  sortKey: 'ultimoValorPago'),
    _ColDef(label: 'Custo m² (Últimas compras)',  flex: 0.9,  sortKey: 'ultimoValorPagoM2'),
    _ColDef(label: 'Status',                      flex: 0.8,  sortKey: 'status'),
    _ColDef(label: '',                             fixed: 40),
  ];

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  @override
  State<_TabelaMateriais> createState() => _TabelaMateriaisState();
}

class _TabelaMateriaisState extends State<_TabelaMateriais> {
  String? _colunaOrdem;
  bool    _crescente = true;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<_ColDef> get _cols => widget.mostrarCategoria
      ? _TabelaMateriais._colsBase
      : _TabelaMateriais._colsBase.where((c) => c.label != 'Categoria').toList();

  List<MaterialModel> _ordenar(List<MaterialModel> lista) {
    if (_colunaOrdem == null) return lista;
    final sorted = [...lista];
    sorted.sort((a, b) {
      dynamic va, vb;
      switch (_colunaOrdem) {
        case 'id':               va = a.id;               vb = b.id;               break;
        case 'identificador':    va = a.identificador;    vb = b.identificador;    break;
        case 'nome':             va = a.nome;             vb = b.nome;             break;
        case 'categoria':        va = a.categoria;        vb = b.categoria;        break;
        case 'medida':           va = a.medida;           vb = b.medida;           break;
        case 'espessura':        va = a.espessura;        vb = b.espessura;        break;
        case 'largura':          va = a.largura;          vb = b.largura;          break;
        case 'comprimento':      va = a.comprimento;      vb = b.comprimento;      break;
        case 'quantidade':       va = a.quantidade;       vb = b.quantidade;       break;
        case 'estoqueMinimo':    va = a.estoqueMinimo;    vb = b.estoqueMinimo;    break;
        case 'unidade':          va = a.unidade;          vb = b.unidade;          break;
        case 'precoMediano':     va = a.precoMediano;     vb = b.precoMediano;     break;
        case 'precoM2Mediano':   va = a.precoM2Mediano;   vb = b.precoM2Mediano;   break;
        case 'ultimoValorPago':  va = a.ultimoValorPago;  vb = b.ultimoValorPago;  break;
        case 'ultimoValorPagoM2':va = a.ultimoValorPagoM2;vb = b.ultimoValorPagoM2;break;
        case 'status':           va = a.status;           vb = b.status;           break;
        default:                 return 0;
      }
      if (va == null && vb == null) return 0;
      if (va == null) return _crescente ? 1 : -1;
      if (vb == null) return _crescente ? -1 : 1;
      final cmp = va is num
          ? (va).compareTo(vb as num)
          : va.toString().toLowerCase().compareTo(vb.toString().toLowerCase());
      return _crescente ? cmp : -cmp;
    });
    return sorted;
  }

  void _toggleOrdem(String sortKey) {
    setState(() {
      if (_colunaOrdem == sortKey) {
        _crescente = !_crescente;
      } else {
        _colunaOrdem = sortKey;
        _crescente   = true;
      }
    });
  }

  Widget _cabecalho() => Container(
        color: AppTheme.surfaceVariant,
        child: Row(
          children: [
            for (final col in _cols)
              _TabelaMateriais._colWrap(
                col,
                col.sortKey != null
                    ? _CabecalhoOrdenavel(
                        label:    col.label,
                        ativo:    _colunaOrdem == col.sortKey,
                        crescente: _crescente,
                        onTap:    () => _toggleOrdem(col.sortKey!),
                      )
                    : Padding(
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
    final confirmados = _ordenar(widget.materiais.where((m) =>  m.estoqueConfirmado).toList());
    final naoConfirm  = _ordenar(widget.materiais.where((m) => !m.estoqueConfirmado).toList());

    // Corpo rolável (sem o cabeçalho — ele fica fixo acima)
    Widget corpoRolavel = SingleChildScrollView(
      controller: _scrollCtrl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SectionHeader(
            icon:  Icons.pending_outlined,
            label: 'Aguardando confirmação de estoque',
            count: naoConfirm.length,
            color: AppTheme.warning,
          ),
          if (naoConfirm.isEmpty)
            const _EmptySection(message: 'Nenhum material pendente de confirmação.')
          else ...[
            for (int i = 0; i < naoConfirm.length; i++) ...[
              if (i > 0)
                const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
              _LinhaMateria(
                material:             naoConfirm[i],
                cols:                 _cols,
                onEditar:             widget.onEditar,
                onVerFornecedores:    widget.onVerFornecedores,
                onVerHistoricoPrecos: widget.onVerHistoricoPrecos,
                mostrarCategoria:     widget.mostrarCategoria,
              ),
            ],
            const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
          ],

          const SizedBox(height: 24),

          _SectionHeader(
            icon:  Icons.verified_outlined,
            label: 'Estoque confirmado',
            count: confirmados.length,
            color: AppTheme.success,
          ),
          if (confirmados.isEmpty)
            const _EmptySection(message: 'Nenhum material com estoque confirmado.')
          else ...[
            for (int i = 0; i < confirmados.length; i++) ...[
              if (i > 0)
                const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
              _LinhaMateria(
                material:             confirmados[i],
                cols:                 _cols,
                onEditar:             widget.onEditar,
                onVerFornecedores:    widget.onVerFornecedores,
                onVerHistoricoPrecos: widget.onVerHistoricoPrecos,
                mostrarCategoria:     widget.mostrarCategoria,
              ),
            ],
            const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho fixo — não entra no scroll
        _cabecalho(),
        const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
        // Corpo rolável ocupa o espaço restante
        Expanded(child: corpoRolavel),
      ],
    );
  }
}

class _ColDef {
  final String  label;
  final double? fixed;
  final double? flex;
  /// Identificador de ordenação; null = coluna não ordenável
  final String? sortKey;
  const _ColDef({required this.label, this.fixed, this.flex, this.sortKey});
}

// ─────────────────────────────────────────────────────────────────────────────
// CABEÇALHO ORDENÁVEL
// ─────────────────────────────────────────────────────────────────────────────

class _CabecalhoOrdenavel extends StatelessWidget {
  final String label;
  final bool   ativo;
  final bool   crescente;
  final VoidCallback onTap;

  const _CabecalhoOrdenavel({
    required this.label,
    required this.ativo,
    required this.crescente,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Layout idêntico ao cabeçalho original — só adiciona clique e ícone de seta
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: ativo ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
              // Ícone pequeno no canto superior direito, sem afetar o layout do texto
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  ativo
                      ? (crescente
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded)
                      : Icons.unfold_more_rounded,
                  size: 12,
                  color: ativo ? AppTheme.primary : AppTheme.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaMateria extends StatefulWidget {
  final MaterialModel material;
  final List<_ColDef> cols;
  final void Function(MaterialModel) onEditar;
  final void Function(MaterialModel) onVerFornecedores;
  final void Function(MaterialModel) onVerHistoricoPrecos;
  final bool mostrarCategoria;
 
  const _LinhaMateria({
    required this.material,
    required this.cols,
    required this.onEditar,
    required this.onVerFornecedores,
    required this.onVerHistoricoPrecos,
    this.mostrarCategoria = true,
  });
 
  @override
  State<_LinhaMateria> createState() => _LinhaMateriaState();
}
 
class _LinhaMateriaState extends State<_LinhaMateria> {
  bool _hovered  = false;
  bool _expandido = false; // apenas para materiais específicos
 
  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }
 
  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }
 
  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);
 
  static Widget _cell(String text, {bool inativo = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: inativo ? AppTheme.textHint : AppTheme.textPrimary,
          ),
        ),
      );
 
  // ── Linha principal (pai) ──────────────────────────────────────────────────
  Widget _buildLinhaRaiz(BuildContext context) {
    final m       = widget.material;
    final inativo = !m.ativo;
    final cols    = widget.cols;
 
    final bgColor = _hovered
        ? const Color(0xFFFF9800).withValues(alpha: 0.10)
        : inativo
            ? AppTheme.surfaceVariant.withValues(alpha: 0.4)
            : AppTheme.surface;
 
    Widget maybeOpacity(Widget child) =>
        inativo ? Opacity(opacity: 0.45, child: child) : child;
 
    Widget valorCell(double? valor, bool temFornecedores) => _ValorCell(
          valor: valor,
          temFornecedores: temFornecedores,
          onTap: () => widget.onVerFornecedores(m),
        );
 
    // Coluna de "Estoque atual" para material específico:
    // mostra a soma dos filhos + botão de seta para expandir/recolher
    Widget estoqueAtualCell() {
      if (m.especifico) {
        final total = m.quantidadeTotal;
        final label = total.toStringAsFixed(total % 1 == 0 ? 0 : 2);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(width: 4),
              // Seta clicável separada para expandir/recolher
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expandido = !_expandido),
                child: Tooltip(
                  message: _expandido ? 'Recolher variações' : 'Expandir variações',
                  child: AnimatedRotation(
                    turns: _expandido ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      size: 18,
                      color: Color(0xFFE85D04),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return maybeOpacity(_cell(
        m.quantidade.toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2),
        inativo: inativo,
      ));
    }
 
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit:  _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEditar(m),
        child: ColoredBox(
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ID
                _colWrap(cols[0], maybeOpacity(Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    '${m.id}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: inativo ? AppTheme.textHint : AppTheme.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ))),
                _vDivider(),
 
                // Identificador
                _colWrap(cols[1], maybeOpacity(_cell(m.identificador ?? '—', inativo: inativo))),
                _vDivider(),
 
                // Nome
                _colWrap(cols[2], maybeOpacity(Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          m.nome,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: inativo ? AppTheme.textHint : AppTheme.textPrimary,
                            decoration: inativo ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))),
                _vDivider(),
 
                // Categoria (apenas em Geral / Sem categoria)
                if (widget.mostrarCategoria) ...[
                  _colWrap(cols[3], maybeOpacity(_cell(m.categoria ?? '—', inativo: inativo))),
                  _vDivider(),
                ],
 
                // Medida
                _colWrap(cols[widget.mostrarCategoria ? 4 : 3], maybeOpacity(_cell(m.medida ?? '—', inativo: inativo))),
                _vDivider(),
 
                // Espessura
                _colWrap(cols[widget.mostrarCategoria ? 5 : 4], maybeOpacity(_cell(m.espessura ?? '—', inativo: inativo))),
                _vDivider(),
 
                // Largura
                _colWrap(cols[widget.mostrarCategoria ? 6 : 5], maybeOpacity(_cell(m.largura != null ? m.largura!.toStringAsFixed((m.largura! % 1 == 0 ? 0 : 2).toInt()) : '—', inativo: inativo))),
                _vDivider(),
 
                // Comprimento
                _colWrap(cols[widget.mostrarCategoria ? 7 : 6], maybeOpacity(_cell(m.comprimento != null ? m.comprimento!.toStringAsFixed((m.comprimento! % 1 == 0 ? 0 : 2).toInt()) : '—', inativo: inativo))),
                _vDivider(),
 
                // Estoque atual (com lógica especial para específico)
                _colWrap(cols[widget.mostrarCategoria ? 8 : 7], estoqueAtualCell()),
                _vDivider(),
 
                // Estoque mínimo
                _colWrap(cols[widget.mostrarCategoria ? 9 : 8], maybeOpacity(_cell(
                  m.estoqueMinimo.toStringAsFixed(m.estoqueMinimo % 1 == 0 ? 0 : 2),
                  inativo: inativo,
                ))),
                _vDivider(),
 
                // Unidade
                _colWrap(cols[widget.mostrarCategoria ? 10 : 9], maybeOpacity(_cell(m.unidade ?? '—', inativo: inativo))),
                _vDivider(),
 
                // Valor intermediário
                _colWrap(cols[widget.mostrarCategoria ? 11 : 10], maybeOpacity(valorCell(
                  m.precoMediano,
                  m.fornecedorMateriais.isNotEmpty,
                ))),
                _vDivider(),
 
                // Valor m² intermediário
                _colWrap(cols[widget.mostrarCategoria ? 12 : 11], maybeOpacity(valorCell(
                  m.precoM2Mediano,
                  m.fornecedorMateriais.isNotEmpty,
                ))),
                _vDivider(),
 
                // Custo última compra
                _colWrap(cols[widget.mostrarCategoria ? 13 : 12], maybeOpacity(_CustoCell(
                  valor:       m.ultimoValorPago,
                  temHistorico: true,
                  onTap:       () => widget.onVerHistoricoPrecos(m),
                ))),
                _vDivider(),
 
                // Custo m² última compra
                _colWrap(cols[widget.mostrarCategoria ? 14 : 13], maybeOpacity(_CustoCell(
                  valor:       m.ultimoValorPagoM2,
                  temHistorico: true,
                  onTap:       () => widget.onVerHistoricoPrecos(m),
                ))),
                _vDivider(),
 
                // Status
                _colWrap(cols[widget.mostrarCategoria ? 15 : 14], maybeOpacity(Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: _StatusBadge(status: m.status),
                  ),
                ))),

                // botão Histórico de audit por material
                _colWrap(
                  cols[widget.mostrarCategoria ? 16 : 15],
                  Center(
                    child: IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HistoricoMaterialPage(
                            materialIdInicial:   m.id,
                            materialNomeInicial: m.nome,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.history, size: 18),
                      tooltip: 'Histórico deste material',
                      color: const Color(0xFF7C3AED),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final m = widget.material;
 
    if (!m.especifico) {
      // Comportamento original para materiais não-específicos
      return _buildLinhaRaiz(context);
    }
 
    // Material específico: linha pai + filhos expansíveis
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLinhaRaiz(context),
 
        // Painel de filhos
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expandido
              ? Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE85D04).withValues(alpha: 0.03),
                    border: Border(
                      left: BorderSide(
                        color: const Color(0xFFE85D04).withValues(alpha: 0.4),
                        width: 3,
                      ),
                      bottom: const BorderSide(
                        color: AppTheme.divider,
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: m.filhosEspecificos.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                          child: Text(
                            'Nenhum estoque registrado ainda. '
                            'Finalize uma Ordem de Compra com este material para criar entradas.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textHint,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Divider(height: 0, thickness: 0.5, color: AppTheme.divider),
                            for (int i = 0; i < m.filhosEspecificos.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 0,
                                  thickness: 0.5,
                                  color: AppTheme.divider,
                                ),
                              _LinhaFilhoEspecifico(
                                filho:                m.filhosEspecificos[i],
                                pai:                  m,
                                cols:                 widget.cols,
                                onVerHistoricoPrecos: widget.onVerHistoricoPrecos,
                                mostrarCategoria:     widget.mostrarCategoria,
                              ),
                            ],
                          ],
                        ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
 
  static Widget _vDivider() => const VerticalDivider(
        width: 1, thickness: 0.5, color: AppTheme.divider,
      );
}

class _LinhaFilhoEspecifico extends StatefulWidget {
  final EstoqueEspecificoModel filho;
  final MaterialModel pai;
  final List<_ColDef> cols;
  final void Function(MaterialModel) onVerHistoricoPrecos;
  final bool mostrarCategoria;
 
  const _LinhaFilhoEspecifico({
    required this.filho,
    required this.pai,
    required this.cols,
    required this.onVerHistoricoPrecos,
    this.mostrarCategoria = true,
  });
 
  @override
  State<_LinhaFilhoEspecifico> createState() => _LinhaFilhoEspecificoState();
}
 
class _LinhaFilhoEspecificoState extends State<_LinhaFilhoEspecifico> {
  bool _hovered = false;
 
  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  static Widget _vDivider() => const VerticalDivider(
        width: 1, thickness: 0.5, color: AppTheme.divider,
      );

  static Widget _emptyCell() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context) {
    final filho = widget.filho;
    final pai   = widget.pai;
    final cols  = widget.cols;

    final qtd      = filho.quantidade;
    final qtdLabel = qtd.toStringAsFixed(qtd % 1 == 0 ? 0 : 2);

    final Color qtdColor = qtd <= 0
        ? AppTheme.error
        : qtd < 3
            ? AppTheme.warning
            : AppTheme.success;

    final bgColor = _hovered
        ? const Color(0xFFE85D04).withValues(alpha: 0.06)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,          // <-- cursor de mão
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(                    // <-- clique → dialog
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          // Verifica se a descrição deste filho está em uso em alguma OS em
          // andamento. Impede renomear uma variação que já foi movimentada
          // e ainda está aberta no Controle de Estoque.
          final estoqueProvider = context.read<EstoqueProvider>();
          final descricaoBloqueada = estoqueProvider.relacoesOS
              .where((r) => r.status == 'EM_ANDAMENTO')
              .any((r) => r.movimentacoes.any((m) =>
                  m.materialId == filho.materialId &&
                  (m.descricaoItem?.toUpperCase().trim() ==
                      filho.descricao.toUpperCase().trim())));

          await showDialog<bool>(
            context: context,
            builder: (_) => _EditarFilhoEspecificoDialog(
              filho:              filho,
              pai:                pai,
              descricaoBloqueada: descricaoBloqueada,
            ),
          );
          // O provider já recarrega internamente ao salvar;
          // não precisa de ação extra aqui.
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // col[0]: ID — ícone de sub-item
                _colWrap(cols[0], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Center(
                    child: Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: const Color(0xFFE85D04).withValues(alpha: 0.6),
                    ),
                  ),
                )),
                _vDivider(),

                // col[1]: Identificador — vazio
                _colWrap(cols[1], _emptyCell()),
                _vDivider(),

                // col[2]: Nome → descrição do filho + ícones de ação no hover
                _colWrap(cols[2], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          filho.descricao,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
                _vDivider(),

                // col Categoria (apenas em Geral / Sem categoria) + Medida + Espessura: vazios
                if (widget.mostrarCategoria) ...[
                  _colWrap(cols[3], _emptyCell()),
                  _vDivider(),
                ],
                _colWrap(cols[widget.mostrarCategoria ? 4 : 3], _emptyCell()),
                _vDivider(),
                _colWrap(cols[widget.mostrarCategoria ? 5 : 4], _emptyCell()),
                _vDivider(),

                // col Estoque atual do filho
                _colWrap(cols[widget.mostrarCategoria ? 6 : 5], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Center(
                    child: Text(
                      qtdLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: qtdColor,
                      ),
                    ),
                  ),
                )),
                _vDivider(),

                // col Estoque mínimo — vazio
                _colWrap(cols[widget.mostrarCategoria ? 7 : 6], _emptyCell()),
                _vDivider(),

                // col Unidade — vazio
                _colWrap(cols[widget.mostrarCategoria ? 8 : 7], _emptyCell()),
                _vDivider(),

                // col Valor Intermediário + m²: vazios
                _colWrap(cols[widget.mostrarCategoria ? 9 : 8],  _emptyCell()),
                _vDivider(),
                _colWrap(cols[widget.mostrarCategoria ? 10 : 9], _emptyCell()),
                _vDivider(),

                // col Custo última compra do filho
                _colWrap(cols[widget.mostrarCategoria ? 11 : 10], _CustoCell(
                  valor:        filho.ultimoValorPago,
                  temHistorico: filho.ultimoValorPago != null,
                  onTap:        () => widget.onVerHistoricoPrecos(pai),
                )),
                _vDivider(),

                // col Custo m² última compra do filho
                _colWrap(cols[widget.mostrarCategoria ? 12 : 11], _CustoCell(
                  valor:        filho.ultimoValorPagoM2,
                  temHistorico: filho.ultimoValorPagoM2 != null,
                  onTap:        () => widget.onVerHistoricoPrecos(pai),
                )),
                _vDivider(),

                // col Status — vazio
                _colWrap(cols[widget.mostrarCategoria ? 13 : 12], _emptyCell()),
                // col Histórico — vazio
                _colWrap(cols[widget.mostrarCategoria ? 14 : 13], _emptyCell()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ValorCell extends StatefulWidget {
  final double? valor;
  final bool temFornecedores;
  final VoidCallback onTap;

  const _ValorCell({
    required this.valor,
    required this.temFornecedores,
    required this.onTap,
  });

  @override
  State<_ValorCell> createState() => _ValorCellState();
}

class _ValorCellState extends State<_ValorCell> {
  bool _hovered = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.valor != null && widget.valor! > 0;
    final label    = hasValue ? 'R\$ ${widget.valor!.toStringAsFixed(2)}' : '—';
    final canTap   = widget.temFornecedores;
    final showHover = canTap && _hovered;

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: _onHover,
      onExit: _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap ? widget.onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: showHover
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: showHover
                    ? AppTheme.primary
                    : hasValue ? AppTheme.textPrimary : AppTheme.textHint,
                fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String tooltip;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (_) { if (!_hovered) setState(() => _hovered = true); },
        onExit:  (_) { if (_hovered)  setState(() => _hovered = false); },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.12)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: 18, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'OK'      => ('OK',      AppTheme.statusOk),
      'LIMITE'  => ('LIMITE',  AppTheme.statusBaixo),
      'CRITICO' => ('CRITICO', AppTheme.statusCritico),
      'INATIVO' => ('INATIVO', AppTheme.textHint),
      _         => ('—',       AppTheme.textHint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _PrecosFornecedoresDialog extends StatelessWidget {
  final MaterialModel material;
  const _PrecosFornecedoresDialog({required this.material});

  static Set<int> _indicesMediano(List<FornecedorMaterialModel> ordenados) {
    final validos = ordenados.where((f) => f.preco > 0).toList();
    if (validos.isEmpty) return {};
    final n = validos.length;
    if (n % 2 != 0) return {n ~/ 2};
    return {n ~/ 2 - 1, n ~/ 2};
  }

  @override
  Widget build(BuildContext context) {
    final lista     = material.fornecedorMateriais;
    final ordenados = [...lista]..sort((a, b) => a.preco.compareTo(b.preco));
    _indicesMediano(ordenados);

    final temMediano  = material.precoMediano != null && material.precoMediano! > 0;
    final temM2       = material.precoM2Mediano != null && material.precoM2Mediano! > 0;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Preços — ${material.nome}'),
      content: SizedBox(
        width: 500,
        child: lista.isEmpty
            ? const Text('Nenhum fornecedor vinculado a este material.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (temMediano || temM2)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.analytics_outlined, size: 16, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 4,
                              children: [
                                const Text(
                                  'Valor intermediário exibido na tabela:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                if (temMediano)
                                  RichText(
                                    text: TextSpan(
                                      style: const TextStyle(fontSize: 12),
                                      children: [
                                        const TextSpan(
                                          text: 'Valor: ',
                                          style: TextStyle(color: AppTheme.textSecondary),
                                        ),
                                        TextSpan(
                                          text: 'R\$ ${material.precoMediano!.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (temM2)
                                  RichText(
                                    text: TextSpan(
                                      style: const TextStyle(fontSize: 12),
                                      children: [
                                        const TextSpan(
                                          text: 'Valor m²: ',
                                          style: TextStyle(color: AppTheme.textSecondary),
                                        ),
                                        TextSpan(
                                          text: 'R\$ ${material.precoM2Mediano!.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w700,
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

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Fornecedor',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          'Valor',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          'Valor m²',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 12),

                  ...List.generate(ordenados.length, (i) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FornecedorPrecoRow(
                          item: ordenados[i],

                          destacarValor:
                              material.precoMediano != null &&
                              ordenados[i].preco == material.precoMediano,

                          destacarValorM2:
                              material.precoM2Mediano != null &&
                              ordenados[i].precoMetroQuadrado ==
                                  material.precoM2Mediano,
                        ),
                        if (i < ordenados.length - 1)
                          const Divider(height: 1, color: AppTheme.divider),
                      ],
                    );
                  }),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _FornecedorPrecoRow extends StatelessWidget {
  final FornecedorMaterialModel item;

  final bool destacarValor;
  final bool destacarValorM2;

  const _FornecedorPrecoRow({
    required this.item,
    this.destacarValor = false,
    this.destacarValorM2 = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.fornecedorNome.isEmpty ? '—' : item.fornecedorNome,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: destacarValor
                    ? const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      )
                    : EdgeInsets.zero,
                decoration: destacarValor
                    ? BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      )
                    : null,
                child: Text(
                  item.preco > 0
                      ? 'R\$ ${item.preco.toStringAsFixed(2)}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: destacarValor
                        ? AppTheme.primary
                        : AppTheme.textPrimary,
                    fontWeight: destacarValor
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: destacarValorM2
                    ? const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      )
                    : EdgeInsets.zero,
                decoration: destacarValorM2
                    ? BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      )
                    : null,
                child: Text(
                  item.precoMetroQuadrado > 0
                      ? 'R\$ ${item.precoMetroQuadrado.toStringAsFixed(2)}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: destacarValorM2
                        ? AppTheme.primary
                        : AppTheme.textPrimary,
                    fontWeight: destacarValorM2
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row clicável do painel lateral de fornecedores no _MaterialFormDialog
// Ao clicar fecha o dialog e navega para a página de orçamento com o material
// ─────────────────────────────────────────────────────────────────────────────
class _FornecedorPainelRow extends StatefulWidget {
  final FornecedorMaterialModel fm;
  final MaterialModel           material;
  final bool                    isMediano;
  final bool                    showDivider;

  const _FornecedorPainelRow({
    required this.fm,
    required this.material,
    required this.isMediano,
    required this.showDivider,
  });

  @override
  State<_FornecedorPainelRow> createState() => _FornecedorPainelRowState();
}

class _FornecedorPainelRowState extends State<_FornecedorPainelRow> {
  bool _hovered = false;

  void _irParaOrcamento() {
    // Fecha o dialog primeiro
    Navigator.of(context, rootNavigator: true).pop(false);
    // Adiciona o material ao orçamento via provider e navega
    context.read<OrcamentoProvider>().adicionarMaterialDireto(
      material:   widget.material,
      fornecedor: widget.fm,
    );
    context.go('/orcamento');
  }

  @override
  Widget build(BuildContext context) {
    final fm = widget.fm;
    final temPrecoUnit = fm.preco > 0;
    final temPrecoM2   = fm.precoMetroQuadrado > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (_) { if (!_hovered) setState(() => _hovered = true); },
          onExit:  (_) { if (_hovered)  setState(() => _hovered = false); },
          child: GestureDetector(
            onTap: _irParaOrcamento,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              color: _hovered
                  ? AppTheme.primary.withValues(alpha: 0.07)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  // Nome do fornecedor
                  Expanded(
                    child: Row(
                      children: [
                        if (widget.isMediano) ...[
                          const Tooltip(
                            message: 'Preço mediano',
                            child: Icon(Icons.show_chart,
                                size: 12, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            fm.fornecedorNome.isEmpty ? '—' : fm.fornecedorNome,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: _hovered
                                  ? AppTheme.primary
                                  : AppTheme.textPrimary,
                              fontWeight: widget.isMediano
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Preço unitário
                  SizedBox(
                    width: 68,
                    child: Text(
                      temPrecoUnit
                          ? 'R\$ ${fm.preco.toStringAsFixed(2)}'
                          : '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: temPrecoUnit
                            ? (_hovered ? AppTheme.primary : AppTheme.textPrimary)
                            : AppTheme.textHint,
                        fontWeight: temPrecoUnit ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                  // Preço m²
                  SizedBox(
                    width: 68,
                    child: Text(
                      temPrecoM2
                          ? 'R\$ ${fm.precoMetroQuadrado.toStringAsFixed(2)}'
                          : '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: temPrecoM2
                            ? (_hovered ? AppTheme.primary : AppTheme.textPrimary)
                            : AppTheme.textHint,
                        fontWeight: temPrecoM2 ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.showDivider)
          const Divider(height: 0, thickness: 0.4, color: AppTheme.divider),
      ],
    );
  }
}

class _EditarFilhoEspecificoDialog extends StatefulWidget {
  final EstoqueEspecificoModel filho;
  final MaterialModel pai;
  final bool descricaoBloqueada;

  const _EditarFilhoEspecificoDialog({
    required this.filho,
    required this.pai,
    this.descricaoBloqueada = false,
  });

  @override
  State<_EditarFilhoEspecificoDialog> createState() =>
      _EditarFilhoEspecificoDialogState();
}

class _EditarFilhoEspecificoDialogState extends State<_EditarFilhoEspecificoDialog> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _qtdCtrl;
  bool _salvando   = false;
  bool _excluindo  = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _descCtrl   = TextEditingController(text: widget.filho.descricao);
    _qtdCtrl = TextEditingController(
      text: widget.filho.quantidade.toStringAsFixed(
        widget.filho.quantidade % 1 == 0 ? 0 : 2,
      ),
    );
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtdCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final novaDesc = _descCtrl.text.trim();
    if (novaDesc.isEmpty) {
      setState(() => _erro = 'A descrição não pode ser vazia.');
      return;
    }
    // Garante que a descrição não mudou se estiver bloqueada por OS em andamento
    if (widget.descricaoBloqueada &&
        novaDesc.toUpperCase() != widget.filho.descricao.toUpperCase()) {
      setState(() => _erro =
          'Não é possível renomear uma variação com OS em andamento.');
      return;
    }
    setState(() { _salvando = true; _erro = null; });

    final novaQtd = double.tryParse(_qtdCtrl.text.replaceAll(',', '.'));

    final ok = await context.read<MaterialProvider>().atualizarFilhoEspecifico(
      widget.pai.id,
      widget.filho.id,
      descricao:  novaDesc != widget.filho.descricao ? novaDesc : null,
      quantidade: novaQtd,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _salvando = false;
        _erro = context.read<MaterialProvider>().erro ?? 'Erro ao salvar.';
      });
    }
  }

  Future<void> _excluir() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir variação'),
        content: Text(
          'Tem certeza que deseja excluir a variação "${widget.filho.descricao}"?\n\n'
          'O estoque desta variação (${widget.filho.quantidade.toStringAsFixed(widget.filho.quantidade % 1 == 0 ? 0 : 2)} '
          '${widget.pai.unidade ?? ''}) será removido permanentemente.',
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
    if (confirmar != true || !mounted) return;
    setState(() { _excluindo = true; _erro = null; });

    final ok = await context.read<MaterialProvider>().excluirFilhoEspecifico(
      widget.pai.id,
      widget.filho.id,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _excluindo = false;
        _erro = context.read<MaterialProvider>().erro ?? 'Erro ao excluir.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pai = widget.pai;

    return AlertDialog(
      title: Row(
        children: [
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Editar variação', style: TextStyle(fontSize: 16)),
                Text(
                  pai.nome,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Estoque atual (somente leitura) ───────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE85D04).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFE85D04).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 16, color: Color(0xFFE85D04)),
                  const SizedBox(width: 8),
                  const Text(
                    'Estoque atual: ',
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  Text(
                    () {
                      final q = widget.filho.quantidade;
                      return '${q.toStringAsFixed(q % 1 == 0 ? 0 : 2)} ${pai.unidade ?? ''}';
                    }(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE85D04),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Quantidade em estoque',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _qtdCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_DecimalInputFormatter()],
              decoration: InputDecoration(
                hintText: '0',
                isDense:  true,
                suffixText: widget.pai.unidade ?? '',
              ),
            ),
            const SizedBox(height: 16),

            // ── Descrição ──────────────────────────────────────────────────
            const Text(
              'Descrição / nome da variação',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            if (widget.descricaoBloqueada) ...[
              // Campo somente leitura — há OS em andamento usando esta variação
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.textHint.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 15, color: AppTheme.textHint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.filho.descricao,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 13, color: AppTheme.textHint),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Este material possui OS em andamento. O nome não pode ser alterado.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _descCtrl,
                autofocus:  true,
                inputFormatters: [_NoCommaFormatter()],
                decoration: const InputDecoration(
                  hintText: 'Ex: Tinta Branca Fosca 18L',
                  isDense:  true,
                ),
                onSubmitted: (_) => _salvar(),
              ),
            ],
            const SizedBox(height: 16),

            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(
                _erro!,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // Botão excluir (esquerda)
        TextButton.icon(
          onPressed: (_salvando || _excluindo) ? null : _excluir,
          icon: _excluindo
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.error),
                )
              : const Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
          label: const Text('Excluir', style: TextStyle(color: AppTheme.error)),
        ),
        const Spacer(),
        TextButton(
          onPressed: (_salvando || _excluindo) ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: (_salvando || _excluindo) ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, size: 16),
          label: const Text('Salvar'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE85D04),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _MaterialFormDialog extends StatefulWidget {
  final MaterialModel? material;
  final void Function(MaterialModel)? onDesativar;
  final void Function(MaterialModel)? onReativar;
  final void Function(MaterialModel)? onExcluir;
  const _MaterialFormDialog({this.material, this.onDesativar, this.onReativar, this.onExcluir});

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog;

  late final TextEditingController _nome;
  late final TextEditingController _identificador;
  late final TextEditingController _unidade;
  late final TextEditingController _categoria;
  late final TextEditingController _medida;
  late final TextEditingController _espessura;
  late final TextEditingController _largura;
  late final TextEditingController _comprimento;
  late final TextEditingController _quantidade;
  late final TextEditingController _estoqueMinimo;

  bool get _editando => widget.material != null;
  late bool _estoqueConfirmado;
  late bool _especifico;

  @override
  void initState() {
    super.initState();
    final m        = widget.material;
    _estoqueConfirmado = m?.estoqueConfirmado ?? false;
    _especifico        = m?.especifico ?? false;
    _nome          = TextEditingController(text: m?.nome ?? '');
    _identificador = TextEditingController(text: m?.identificador ?? '');
    _unidade       = TextEditingController(text: m?.unidade ?? '');
    _categoria     = TextEditingController(text: m?.categoria ?? '');
    _medida        = TextEditingController(text: m?.medida ?? '');
    _espessura     = TextEditingController(text: m?.espessura ?? '');
    _largura       = TextEditingController(text: m?.largura != null ? m!.largura!.toStringAsFixed((m.largura! % 1 == 0 ? 0 : 4).toInt()) : '');
    _comprimento   = TextEditingController(text: m?.comprimento != null ? m!.comprimento!.toStringAsFixed((m.comprimento! % 1 == 0 ? 0 : 4).toInt()) : '');
    _quantidade    = TextEditingController(
        text: m != null ? m.quantidade.toString() : '0');
    _estoqueMinimo = TextEditingController(
        text: m != null ? m.estoqueMinimo.toString() : '0');
  }

  @override
  void dispose() {
    for (final c in [
      _nome, _identificador, _unidade, _categoria, _medida, _espessura,
      _largura, _comprimento, _quantidade, _estoqueMinimo,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _salvando = true; _erroDialog = null; });

    final dados = {
      'nome':          _nome.text.trim(),
      'identificador': _identificador.text.trim().isEmpty ? null : _identificador.text.trim(),
      'unidade':       _unidade.text.trim().isEmpty ? null : _unidade.text.trim(),
      'categoria':     _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
      'medida':        _medida.text.trim().isEmpty ? null : _medida.text.trim(),
      'espessura':     _espessura.text.trim().isEmpty ? null : _espessura.text.trim(),
      'largura':       _largura.text.trim().isEmpty ? null : double.tryParse(_largura.text.trim()),
      'comprimento':   _comprimento.text.trim().isEmpty ? null : double.tryParse(_comprimento.text.trim()),
      'quantidade':    double.tryParse(_quantidade.text) ?? 0,
      'estoqueMinimo': double.tryParse(_estoqueMinimo.text) ?? 0,
      'estoqueConfirmado': _estoqueConfirmado,
      'especifico': _especifico,
    };

    final provider = context.read<MaterialProvider>();
    final bool ok;
    if (_editando) {
      ok = await provider.atualizar(widget.material!.id, dados);
    } else {
      ok = await provider.criar(dados);
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      Navigator.of(context, rootNavigator: true).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_editando ? 'Material atualizado.' : 'Material criado.'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      setState(() => _erroDialog = provider.erro ?? 'Erro ao salvar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final material      = widget.material;
    final fornecedores  = material?.fornecedorMateriais ?? <FornecedorMaterialModel>[];
    final temFornecedor = _editando && fornecedores.isNotEmpty;

    // ── Painel de formulário (sempre presente) ────────────────────────────
    Widget formPanel = Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_erroDialog != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _erroDialog!,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _erroDialog = null),
                      child: const Icon(Icons.close, color: AppTheme.error, size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome *'),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseFormatter()],
              onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nome é obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _identificador,
              decoration: const InputDecoration(
                labelText: 'Identificador',
              ),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseFormatter()],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperCaseFormatter()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _unidade,
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperCaseFormatter()],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _medida,
                  decoration: const InputDecoration(labelText: 'Medida'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperCaseFormatter()],
                  onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _espessura,
                  decoration: const InputDecoration(labelText: 'Espessura'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperCaseFormatter()],
                  onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _largura,
                  decoration: const InputDecoration(labelText: 'Largura (m)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _comprimento,
                  decoration: const InputDecoration(labelText: 'Comprimento (m)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _quantidade,
                  decoration: const InputDecoration(labelText: 'Quantidade'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty || double.tryParse(v) == null)
                          ? 'Número inválido'
                          : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _estoqueMinimo,
                  decoration:
                      const InputDecoration(labelText: 'Estoque mínimo'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty || double.tryParse(v) == null)
                          ? 'Número inválido'
                          : null,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _estoqueConfirmado = !_estoqueConfirmado),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      _estoqueConfirmado
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _estoqueConfirmado ? AppTheme.success : AppTheme.textHint,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estoque confirmado',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _estoqueConfirmado
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          _estoqueConfirmado
                              ? 'A quantidade atual foi verificada fisicamente'
                              : 'Quantidade ainda não verificada fisicamente',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _especifico = !_especifico),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      _especifico
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _especifico ? AppTheme.primary : AppTheme.textHint,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Material específico',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _especifico
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          _especifico
                              ? 'Exigirá descrição personalizada na ordem de compra'
                              : 'Material genérico (sem descrição adicional na OC)',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // ── Painel lateral de fornecedores (apenas no modo edição) ────────────
    Widget? fornecedorPanel;
    if (temFornecedor) {
      final ordenados = [...fornecedores]
        ..sort((a, b) => a.preco.compareTo(b.preco));

      fornecedorPanel = Container(
        width: 260,
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: const BorderRadius.only(
            topRight:    Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border(
            left: BorderSide(color: AppTheme.divider.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho do painel
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.store_outlined, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Fornecedores (${fornecedores.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),

            // Cabeçalho das colunas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: const [
                  Expanded(
                    child: Text(
                      'Fornecedor',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppTheme.textHint),
                    ),
                  ),
                  SizedBox(
                    width: 68,
                    child: Text(
                      'Unit.',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppTheme.textHint),
                    ),
                  ),
                  SizedBox(
                    width: 68,
                    child: Text(
                      'm²',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppTheme.textHint),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0, thickness: 0.5, color: AppTheme.divider),

            // Lista de fornecedores clicáveis
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(ordenados.length, (i) {
                    final fm = ordenados[i];
                    final isMediano = material!.precoMediano != null &&
                        fm.preco == material.precoMediano;

                    return _FornecedorPainelRow(
                      fm:           fm,
                      material:     material,
                      isMediano:    isMediano,
                      showDivider:  i < ordenados.length - 1,
                    );
                  }),
                ),
              ),
            ),

            // Dica de clique
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: AppTheme.textHint),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Clique em um fornecedor para criar um orçamento com este material.',
                      style: TextStyle(fontSize: 10, color: AppTheme.textHint),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Dialog com layout condicional ─────────────────────────────────────
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:  temFornecedor ? 840 : 560,
          maxHeight: 680,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Título ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    _editando ? 'Editar Material' : 'Novo Material',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 0),

            // ── Corpo: formulário + painel lateral ────────────────────────
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Formulário
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: formPanel,
                    ),
                  ),
                  // Painel lateral (se houver fornecedores)
                  if (fornecedorPanel != null) fornecedorPanel,
                ],
              ),
            ),

            // ── Ações ─────────────────────────────────────────────────────
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (_editando) ...[
                    if (widget.material!.ativo && widget.onDesativar != null)
                      TextButton.icon(
                        onPressed: _salvando
                            ? null
                            : () {
                                Navigator.of(context, rootNavigator: true).pop(false);
                                widget.onDesativar!(widget.material!);
                              },
                        icon: const Icon(Icons.block, size: 16),
                        label: const Text('Desativar'),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.warning),
                      ),
                    if (!widget.material!.ativo && widget.onReativar != null)
                      TextButton.icon(
                        onPressed: _salvando
                            ? null
                            : () {
                                Navigator.of(context, rootNavigator: true).pop(false);
                                widget.onReativar!(widget.material!);
                              },
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Reativar'),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.success),
                      ),
                    if (!widget.material!.ativo && widget.onExcluir != null)
                      TextButton.icon(
                        onPressed: _salvando
                            ? null
                            : () {
                                Navigator.of(context, rootNavigator: true).pop(false);
                                widget.onExcluir!(widget.material!);
                              },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Excluir'),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                      ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: _salvando ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _salvando ? null : _salvar,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                    child: _salvando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_editando ? 'Salvar' : 'Criar'),
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

class _CustoCell extends StatefulWidget {
  final double? valor;
  final bool temHistorico;
  final VoidCallback onTap;

  const _CustoCell({
    required this.valor,
    required this.temHistorico,
    required this.onTap,
  });

  @override
  State<_CustoCell> createState() => _CustoCellState();
}

class _CustoCellState extends State<_CustoCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hasValue  = widget.valor != null && widget.valor! > 0;
    final label     = hasValue ? 'R\$ ${widget.valor!.toStringAsFixed(2)}' : '—';
    final showHover = widget.temHistorico && _hovered;

    return MouseRegion(
      cursor: widget.temHistorico ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: (_) { if (!_hovered) setState(() => _hovered = true); },
      onExit:  (_) { if (_hovered)  setState(() => _hovered = false); },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.temHistorico ? widget.onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: showHover
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasValue && showHover)
                  const Padding(
                    padding: EdgeInsets.only(right: 0),
                  ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: showHover
                        ? AppTheme.primary
                        : hasValue
                            ? AppTheme.textPrimary
                            : AppTheme.textHint,
                        fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
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

class _HistoricoPrecoDialog extends StatefulWidget {
  final MaterialModel material;
  const _HistoricoPrecoDialog({required this.material});

  @override
  State<_HistoricoPrecoDialog> createState() => _HistoricoPrecoDialogState();
}

class _HistoricoPrecoDialogState extends State<_HistoricoPrecoDialog> {
  List<HistoricoPrecoModel> _historico = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await context
          .read<MaterialProvider>()
          .listarHistoricoPrecos(widget.material.id);
      if (mounted) setState(() { _historico = lista; _carregando = false; });
    } catch (e) {
      if (mounted) setState(() { _erro = e.toString(); _carregando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final ultimoHistorico = _historico.isNotEmpty ? _historico.first : null;
    final ultimoUsarM2    = ultimoHistorico?.usarM2 ?? false;
    // Usa o valor do próprio registro de histórico (já ordenado por criadoEm desc),
    // evitando depender de material.ultimoValorPago que pode ficar desatualizado.
    final ultimoCusto   = ultimoHistorico?.precoUnitario;
    final ultimoCustoM2 = ultimoHistorico?.precoM2;
    final temCusto   = !ultimoUsarM2 && ultimoCusto   != null && ultimoCusto   > 0;
    final temCustoM2 =  ultimoUsarM2 && ultimoCustoM2 != null && ultimoCustoM2 > 0;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: [
          const Icon(Icons.history, size: 20, color: Color(0xFFE85D04)),
          const SizedBox(width: 8),
          Expanded(child: Text('Histórico de Compras — ${m.nome}')),
        ],
      ),
      content: SizedBox(
        width: 700,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (temCusto || temCustoM2)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE85D04).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE85D04).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 16, color: Color(0xFFE85D04)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 4,
                        children: [
                          const Text(
                            'Último custo registrado:',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          if (temCusto)
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12),
                                children: [
                                  const TextSpan(
                                    text: 'Custo: ',
                                    style: TextStyle(color: AppTheme.textSecondary),
                                  ),
                                  TextSpan(
                                    text: 'R\$ ${ultimoCusto.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Color(0xFFE85D04),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (temCustoM2)
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12),
                                children: [
                                  const TextSpan(
                                    text: 'Custo m²: ',
                                    style: TextStyle(color: AppTheme.textSecondary),
                                  ),
                                  TextSpan(
                                    text: 'R\$ ${ultimoCustoM2.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Color(0xFFE85D04),
                                      fontWeight: FontWeight.w700,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.divider, width: 0.8)),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Fornecedor',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'OC #',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      'Qtd',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Custo unit.',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Custo m²',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Total',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'Data',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFE85D04))),
              )
            else if (_erro != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(_erro!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                ),
              )
            else if (_historico.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Nenhum custo registrado.\nO histórico é criado automaticamente ao finalizar uma Ordem de Compra.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textHint),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_historico.length, (i) {
                      final h = _historico[i];
                      final isUltimo = i == 0;
                      final data = h.dataOrdem ?? h.criadoEm;
                      final dataStr =
                          '${data.day.toString().padLeft(2, '0')}/'
                          '${data.month.toString().padLeft(2, '0')}/'
                          '${data.year}';

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                            decoration: isUltimo
                                ? BoxDecoration(
                                    color: const Color(0xFFE85D04).withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(6),
                                  )
                                : null,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      if (isUltimo) ...[
                                        const Tooltip(
                                          message: 'Custo atual (mais recente)',
                                          child: Icon(Icons.radio_button_checked,
                                              size: 13, color: Color(0xFFE85D04)),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: Text(
                                          h.fornecedorNome,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isUltimo
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                            color: isUltimo
                                                ? AppTheme.textPrimary
                                                : AppTheme.textSecondary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    h.ordemCompraId != null ? '#${h.ordemCompraId}' : '—',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    h.quantidade.toStringAsFixed(
                                        h.quantidade % 1 == 0 ? 0 : 2),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUltimo ? FontWeight.w700 : FontWeight.normal,
                                      color: isUltimo
                                          ? AppTheme.textPrimary
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    !h.usarM2 && h.precoUnitario > 0
                                        ? 'R\$ ${h.precoUnitario.toStringAsFixed(2)}'
                                        : '—',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUltimo
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      color: isUltimo
                                          ? const Color(0xFFE85D04)
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    h.usarM2 && h.precoM2 != null && h.precoM2! > 0
                                        ? 'R\$ ${h.precoM2!.toStringAsFixed(2)}'
                                        : '—',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isUltimo
                                          ? const Color(0xFFE85D04)
                                          : AppTheme.textPrimary,
                                      fontWeight: isUltimo
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    'R\$ ${h.total.toStringAsFixed(2)}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUltimo ? FontWeight.w700 : FontWeight.normal,
                                      color: isUltimo
                                          ? const Color(0xFFE85D04)
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    dataStr,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < _historico.length - 1)
                            const Divider(height: 1, color: AppTheme.divider),
                        ],
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}