import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/fornecedor_model.dart';
import '../providers/fornecedor_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Formatters
// ─────────────────────────────────────────────────────────────────────────────

/// Converte para maiúsculas e remove acentos/diacríticos em tempo real.
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
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

/// Permite apenas dígitos e um único separador decimal (vírgula → ponto).
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
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}


class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove tudo que não for número
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Limita a 14 dígitos
    if (digits.length > 14) {
      digits = digits.substring(0, 14);
    }

    String formatted = '';

    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) {
        formatted += '.';
      } else if (i == 8) {
        formatted += '/';
      } else if (i == 12) {
        formatted += '-';
      }

      formatted += digits[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Página principal
// ─────────────────────────────────────────────────────────────────────────────
class FornecedoresPage extends StatefulWidget {
  const FornecedoresPage({super.key});

  @override
  State<FornecedoresPage> createState() => _FornecedoresPageState();
}

class _FornecedoresPageState extends State<FornecedoresPage> {
  final _buscaCtrl   = TextEditingController();
  final _buscaIdCtrl = TextEditingController();
  String _tipoFiltro = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FornecedorProvider>().carregar();
    });
  }

  void _onBuscaChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), _aplicarFiltros);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    _buscaIdCtrl.dispose();
    super.dispose();
  }

  void _abrirFormulario({FornecedorModel? fornecedor}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _FornecedorDialog(
        fornecedor: fornecedor,
        onRemover:  fornecedor != null ? _confirmarRemover : null,
      ),
    ).then((salvou) {
      if (salvou == true) _aplicarFiltros();
    });
  }

  void _aplicarFiltros() {
    context.read<FornecedorProvider>().carregar(
          busca: _buscaCtrl.text,
          tipo: _tipoFiltro,
          id: _buscaIdCtrl.text.trim(),
        );
  }

  void _abrirVincularPorMaterial() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _VincularPorMaterialDialog(
        onSalvo: () => context.read<FornecedorProvider>().recarregar(),
      ),
    );
  }

  void _abrirMateriais(FornecedorModel fornecedor) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MateriaisDialog(fornecedor: fornecedor),
    );
  }

  Future<void> _confirmarRemover(FornecedorModel f) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remover fornecedor'),
        content: Text(
          'Deseja remover "${f.nomeFantasia}"? Esta ação desativará o registro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final prov = context.read<FornecedorProvider>();
    final sucesso = await prov.remover(f.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          sucesso ? 'Fornecedor removido.' : prov.erro ?? 'Erro ao remover.'),
      backgroundColor: sucesso ? AppTheme.success : AppTheme.error,
    ));
    if (sucesso) _aplicarFiltros();
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
            // ── Cabeçalho ───────────────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fornecedores',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gerencie fornecedores e seus materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _abrirVincularPorMaterial,
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: const Text('Vincular por Material'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _abrirFormulario(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo Fornecedor'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Filtros ─────────────────────────────────────────────────────
            Row(
              children: [
                // Busca por ID
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _buscaIdCtrl,
                    decoration: const InputDecoration(
                      hintText: 'ID...',
                      prefixIcon: Icon(Icons.tag, color: AppTheme.textHint, size: 18),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome, vendedor ou CNPJ…',
                      prefixIcon: const Icon(Icons.search,
                          color: AppTheme.textHint, size: 20),
                      isDense: true,
                      suffixIcon: ValueListenableBuilder(
                        valueListenable: _buscaCtrl,
                        builder: (_, v, __) => v.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _buscaCtrl.clear();
                                  _aplicarFiltros();
                                },
                                color: AppTheme.textHint,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    onChanged: _onBuscaChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                Consumer<FornecedorProvider>(
                  builder: (_, p, __) {
                    final tipos = p.tipos;
                    return SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('tipo_${tipos.join('|')}'),
                        initialValue: _tipoFiltro.isEmpty ? null : _tipoFiltro,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('TODOS', overflow: TextOverflow.ellipsis)),
                          for (final t in tipos)
                            DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) {
                          setState(() => _tipoFiltro = v ?? '');
                          _aplicarFiltros();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off,
                      color: scheme.onSurfaceVariant),
                  onPressed: () {
                    _buscaCtrl.clear();
                    _buscaIdCtrl.clear();
                    setState(() => _tipoFiltro = '');
                    context.read<FornecedorProvider>().carregar();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Conteúdo ────────────────────────────────────────────────────
            Expanded(
              child: Consumer<FornecedorProvider>(
                builder: (_, prov, __) {
                  if (prov.carregando) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    );
                  }
                  if (prov.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          const SizedBox(height: 12),
                          Text(
                            prov.erro!,
                            style: const TextStyle(
                                color: AppTheme.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: prov.recarregar,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    );
                  }
                  if (prov.fornecedores.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _buscaCtrl.text.isNotEmpty || _tipoFiltro.isNotEmpty || _buscaIdCtrl.text.isNotEmpty
                                ? Icons.search_off_outlined
                                : Icons.storefront_outlined,
                            size: 64,
                            color: AppTheme.textHint,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _buscaCtrl.text.isNotEmpty || _tipoFiltro.isNotEmpty || _buscaIdCtrl.text.isNotEmpty
                                ? 'Nenhum fornecedor encontrado'
                                : 'Nenhum fornecedor cadastrado',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _buscaCtrl.text.isNotEmpty || _tipoFiltro.isNotEmpty || _buscaIdCtrl.text.isNotEmpty
                                ? 'Tente um termo diferente.'
                                : 'Clique em "Novo Fornecedor" para começar.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppTheme.textHint),
                          ),
                        ],
                      ),
                    );
                  }

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: _TabelaFornecedores(
                        fornecedores: prov.fornecedores,
                        onEditar: (f) => _abrirFormulario(fornecedor: f),
                        onRemover: _confirmarRemover,
                        onMateriais: _abrirMateriais,
                      ),
                    ),
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
//  Tabela de fornecedores
// ─────────────────────────────────────────────────────────────────────────────

class _ColDef {
  final String label;
  final double? fixed;
  final double? flex;
  const _ColDef({required this.label, this.fixed, this.flex});
}

class _TabelaFornecedores extends StatelessWidget {
  final List<FornecedorModel> fornecedores;
  final void Function(FornecedorModel) onEditar;
  final void Function(FornecedorModel) onRemover;
  final void Function(FornecedorModel) onMateriais;

  const _TabelaFornecedores({
    required this.fornecedores,
    required this.onEditar,
    required this.onRemover,
    required this.onMateriais,
  });

  static const List<_ColDef> _cols = [
    _ColDef(label: 'ID',           fixed: 56),
    _ColDef(label: 'NOME FANTASIA',flex: 2.2),
    _ColDef(label: 'RAZÃO SOCIAL', flex: 1.8),
    _ColDef(label: 'CNPJ',         flex: 1.4),
    _ColDef(label: 'WHATSAPP',     flex: 1.2),
    _ColDef(label: 'VENDEDOR',     flex: 1.4),
    _ColDef(label: 'TIPO',         flex: 1.0),
    _ColDef(label: 'MATERIAIS',    flex: 0.9),
    // Ações removidas — excluir está no formulário de edição
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
        for (int i = 0; i < fornecedores.length; i++) ...[
          if (i > 0)
            const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
          _LinhaFornecedor(
            fornecedor:  fornecedores[i],
            cols:        _cols,
            onEditar:    onEditar,
            onRemover:   onRemover,
            onMateriais: onMateriais,
          ),
        ],
        const Divider(height: 0, thickness: 0.8, color: AppTheme.divider),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Linha da tabela de fornecedores
// ─────────────────────────────────────────────────────────────────────────────
class _LinhaFornecedor extends StatefulWidget {
  final FornecedorModel fornecedor;
  final List<_ColDef> cols;
  final void Function(FornecedorModel) onEditar;
  final void Function(FornecedorModel) onRemover;
  final void Function(FornecedorModel) onMateriais;

  const _LinhaFornecedor({
    required this.fornecedor,
    required this.cols,
    required this.onEditar,
    required this.onRemover,
    required this.onMateriais,
  });

  @override
  State<_LinhaFornecedor> createState() => _LinhaFornecedorState();
}

class _LinhaFornecedorState extends State<_LinhaFornecedor> {
  bool _hovered = false;

  // onHover é chamado a cada movimento do mouse dentro da região,
  // inclusive sobre filhos interativos — nunca interrompido, sem piscar.
  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  static Widget _cell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
        ),
      );

  static Widget _vDivider() => const VerticalDivider(
        width: 1, thickness: 0.5, color: AppTheme.divider,
      );

  @override
  Widget build(BuildContext context) {
    final f    = widget.fornecedor;
    final cols = widget.cols;

    final bgColor = _hovered
        ? const Color(0xFFFF9800).withValues(alpha: 0.10)
        : AppTheme.surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit:  _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEditar(f),
        child: ColoredBox(
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── ID ────────────────────────────────────────────────────────
                _colWrap(cols[0], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    '${f.id}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                )),
                _vDivider(),
                // ── Nome Fantasia ─────────────────────────────────────────────
                _colWrap(cols[1], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    f.nomeFantasia,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                )),
                _vDivider(),
                // ── Razão Social ──────────────────────────────────────────────
                _colWrap(cols[2], _cell(f.razaoSocial ?? '—')),
                _vDivider(),
                // ── CNPJ ─────────────────────────────────────────────────────
                _colWrap(cols[3], _cell(f.cnpj != null ? f.cnpjFormatado : '—')),
                _vDivider(),
                // ── WhatsApp ──────────────────────────────────────────────────
                _colWrap(cols[4], _cell(f.telefone != null ? f.telefoneFormatado : '—')),
                _vDivider(),
                // ── Vendedor ──────────────────────────────────────────────────
                _colWrap(cols[5], _cell(f.nomeVendedor ?? '—')),
                _vDivider(),
                // ── Tipo ──────────────────────────────────────────────────────
                _colWrap(cols[6], _cell(f.tipoFornecedor ?? '—')),
                _vDivider(),
                // ── Materiais — hover extra próprio ───────────────────────────
                _colWrap(cols[7], _MateriaisCell(
                  count: f.materiais.length,
                  onTap: () => widget.onMateriais(f),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Célula de materiais com hover extra (badge azul ao passar o mouse)
// ─────────────────────────────────────────────────────────────────────────────
class _MateriaisCell extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const _MateriaisCell({required this.count, required this.onTap});

  @override
  State<_MateriaisCell> createState() => _MateriaisCellState();
}

class _MateriaisCellState extends State<_MateriaisCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showHover = _hovered;
    final label     = widget.count == 0 ? 'Ver' : '${widget.count}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // onHover do filho não cancela o onHover da linha pai
      onHover: (_) { if (!_hovered) setState(() => _hovered = true); },
      onExit:  (_) { if (_hovered)  setState(() => _hovered = false); },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              decoration: BoxDecoration(
                color: showHover
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: showHover ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: showHover ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
//  sem InkWell/IconButton — não interfere no fundo da linha
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
        // onHover do ícone não cancela o onHover da linha pai
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

class _FornecedorDialog extends StatefulWidget {
  final FornecedorModel? fornecedor;
  final void Function(FornecedorModel)? onRemover;
  const _FornecedorDialog({this.fornecedor, this.onRemover});

  @override
  State<_FornecedorDialog> createState() => _FornecedorDialogState();
}

class _FornecedorDialogState extends State<_FornecedorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeFantasiaCtrl;
  late final TextEditingController _razaoSocialCtrl;
  late final TextEditingController _cnpjCtrl;
  late final TextEditingController _telefoneCtrl;
  late final TextEditingController _nomeVendedorCtrl;
  late final TextEditingController _tipoCtrl;

  bool _salvando = false;
  String? _erroDialog;

  bool get _editando => widget.fornecedor != null;

  // Formatter de telefone: aceita exatamente 10 dígitos (DDD 2 + número 8).
  // Formato de exibição: (42) 9999-9999
  // NOTA: O backend armazena 10 dígitos. Celulares com 9º dígito NÃO são
  // suportados pelo sistema — apenas fixos/comerciais de 8 dígitos.
  static String _formatarTelefone(String digits) {
    if (digits.length <= 2) return digits;
    if (digits.length <= 6) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    }
    if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return digits;
  }

  @override
  void initState() {
    super.initState();
    final f = widget.fornecedor;
    _nomeFantasiaCtrl = TextEditingController(text: f?.nomeFantasia ?? '');
    _razaoSocialCtrl = TextEditingController(text: f?.razaoSocial ?? '');
    _cnpjCtrl = TextEditingController(text: f?.cnpj ?? '');
    // Ao editar, exibe o telefone já formatado
    _telefoneCtrl = TextEditingController(
      text: f?.telefone != null ? _formatarTelefone(f!.telefone!) : '',
    );
    _nomeVendedorCtrl = TextEditingController(text: f?.nomeVendedor ?? '');
    _tipoCtrl = TextEditingController(text: f?.tipoFornecedor ?? '');
  }

  @override
  void dispose() {
    _nomeFantasiaCtrl.dispose();
    _razaoSocialCtrl.dispose();
    _cnpjCtrl.dispose();
    _telefoneCtrl.dispose();
    _nomeVendedorCtrl.dispose();
    _tipoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    final telefoneSomenteDigitos =
        _telefoneCtrl.text.replaceAll(RegExp(r'\D'), '');

    final dados = {
      'nomeFantasia': _nomeFantasiaCtrl.text.trim(),
      'razaoSocial': _razaoSocialCtrl.text.trim().isEmpty
          ? null
          : _razaoSocialCtrl.text.trim(),
      'cnpj': _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '').isEmpty
          ? null
          : _cnpjCtrl.text.replaceAll(RegExp(r'\D'), ''),
      'telefone': telefoneSomenteDigitos.isEmpty ? null : telefoneSomenteDigitos,
      'nomeVendedor': _nomeVendedorCtrl.text.trim().isEmpty
          ? null
          : _nomeVendedorCtrl.text.trim(),
      'tipoFornecedor': _tipoCtrl.text.trim().isEmpty
          ? null
          : _tipoCtrl.text.trim(),
    };

    final prov = context.read<FornecedorProvider>();
    final bool sucesso = _editando
        ? await prov.atualizar(widget.fornecedor!.id, dados)
        : await prov.criar(dados);

    if (!mounted) return;
    setState(() => _salvando = false);

    if (sucesso) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            _editando ? 'Fornecedor atualizado.' : 'Fornecedor criado.'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      setState(() => _erroDialog = prov.erro ?? 'Erro ao salvar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(_editando ? 'Editar fornecedor' : 'Novo fornecedor'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner de erro
                if (_erroDialog != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _erroDialog!,
                            style: const TextStyle(
                                color: AppTheme.error, fontSize: 13),
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _erroDialog = null),
                          child: const Icon(Icons.close,
                              color: AppTheme.error, size: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Nome fantasia
                TextFormField(
                  controller: _nomeFantasiaCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Nome fantasia *'),
                  inputFormatters: [_UpperCaseFormatter()],
                  onChanged: (_) {
                    if (_erroDialog != null) {
                      setState(() => _erroDialog = null);
                    }
                  },
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Nome Fantasia é obrigatório'
                      : null,
                ),
                const SizedBox(height: 12),

                // Razão social
                TextFormField(
                  controller: _razaoSocialCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Razão social'),
                  inputFormatters: [_UpperCaseFormatter()],
                ),
                const SizedBox(height: 12),

                // CNPJ + Telefone
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cnpjCtrl,
                      decoration: const InputDecoration(
                        labelText: 'CNPJ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        _CnpjInputFormatter(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _telefoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'WhatsAPP',
                        // DDD (2) + número (8) = 10 dígitos, sem 9º dígito
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        // Permite somente dígitos e os caracteres de formatação
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[\d() \-]')),
                        LengthLimitingTextInputFormatter(14), // (42) 9999-9999
                        _TelefoneFormatter(),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        if (digits.length != 10) {
                          return 'Use DDD (2) + 8 dígitos: (42) 9999-9999';
                        }
                        return null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // Vendedor + Tipo
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nomeVendedorCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Nome do vendedor'),
                      inputFormatters: [_UpperCaseFormatter()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _tipoCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Tipo de fornecedor'),
                      inputFormatters: [_UpperCaseFormatter()],
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_editando && widget.onRemover != null) ...[
          TextButton.icon(
            onPressed: _salvando
                ? null
                : () {
                    Navigator.of(context).pop(false);
                    widget.onRemover!(widget.fornecedor!);
                  },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Remover'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
          ),
          const Spacer(),
        ],
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
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
    );
  }
}

/// Formata o telefone em tempo real no padrão (42) 9999-9999 (10 dígitos).
/// Remove qualquer 9º dígito extra que o usuário tente digitar.
class _TelefoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Extrai apenas os dígitos e limita a 10
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 10 ? digits.substring(0, 10) : digits;

    String formatted;
    if (d.isEmpty) {
      formatted = '';
    } else if (d.length <= 2) {
      formatted = '($d';
    } else if (d.length <= 6) {
      formatted = '(${d.substring(0, 2)}) ${d.substring(2)}';
    } else {
      formatted =
          '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Diálogo de materiais vinculados (substituiu o BottomSheet)
// ─────────────────────────────────────────────────────────────────────────────
class _MateriaisDialog extends StatefulWidget {
  final FornecedorModel fornecedor;
  const _MateriaisDialog({required this.fornecedor});

  @override
  State<_MateriaisDialog> createState() => _MateriaisDialogState();
}

class _MateriaisDialogState extends State<_MateriaisDialog> {
  late FornecedorModel _fornecedor;

  @override
  void initState() {
    super.initState();
    _fornecedor = widget.fornecedor;
  }

  Future<void> _recarregar() async {
    final prov = context.read<FornecedorProvider>();
    final atualizado = await prov.buscarPorId(_fornecedor.id);
    if (atualizado != null && mounted) {
      setState(() => _fornecedor = atualizado);
    }
  }

  Future<void> _desvincular(FornecedorMaterialVinculoModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Desvincular material'),
        content: Text(
            'Remover "${m.materialNome ?? 'material'}" deste fornecedor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final prov = context.read<FornecedorProvider>();
      final sucesso =
          await prov.desvincularMaterial(_fornecedor.id, m.materialId);
      if (sucesso) await _recarregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              sucesso ? 'Material desvinculado.' : prov.erro ?? 'Erro'),
          backgroundColor: sucesso ? AppTheme.success : AppTheme.error,
        ));
      }
    }
  }

  void _abrirVincularOuEditar({FornecedorMaterialVinculoModel? vinculo}) {
    showDialog(
      context: context,
      builder: (_) => _VinculoMaterialDialog(
        fornecedorId: _fornecedor.id,
        vinculo: vinculo,
        materiaisVinculados: _fornecedor.materiais
            .where((m) => m.ativo)
            .map((m) => m.materialId)
            .toSet(),
        onSalvo: _recarregar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final materiais = _fornecedor.materiais;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: SizedBox(
        width: 600,
        height: 520,
        child: Column(
          children: [
            // Cabeçalho
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Materiais vinculados',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fornecedor.nomeFantasia,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _abrirVincularOuEditar(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Vincular'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.divider),

            // Lista
            Expanded(
              child: materiais.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 48, color: AppTheme.textHint),
                          SizedBox(height: 12),
                          Text(
                            'Nenhum material vinculado',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: materiais.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _VinculoCard(
                        vinculo: materiais[i],
                        onEditar: () =>
                            _abrirVincularOuEditar(vinculo: materiais[i]),
                        onDesvincular: () => _desvincular(materiais[i]),
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
//  Card de vínculo material–fornecedor
// ─────────────────────────────────────────────────────────────────────────────
class _VinculoCard extends StatefulWidget {
  final FornecedorMaterialVinculoModel vinculo;
  final VoidCallback onEditar;
  final VoidCallback onDesvincular;

  const _VinculoCard({
    required this.vinculo,
    required this.onEditar,
    required this.onDesvincular,
  });

  @override
  State<_VinculoCard> createState() => _VinculoCardState();
}

class _VinculoCardState extends State<_VinculoCard> {
  bool _hovered = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vinculo;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit: _onExit,
      child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFFFF9800).withValues(alpha: 0.08)
                : AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // ── Área clicável (abre editor) ───────────────────────────────
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onEditar,
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.category_outlined,
                              color: AppTheme.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.descricaoCompleta,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _PriceTag(label: 'Valor:', valor: v.preco),
                                  const SizedBox(width: 10),
                                  _PriceTag(label: 'Valor m²:', valor: v.precoMetroQuadrado),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Botão desvincular ─────────────────────────────────────────
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDesvincular,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.link_off, size: 18, color: AppTheme.error),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}



class _PriceTag extends StatelessWidget {
  final String label;
  final double valor;
  const _PriceTag({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: 'R\$ ${valor.toStringAsFixed(2)}',
            style: const TextStyle(
                color: AppTheme.success, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Diálogo de vínculo / edição de valor — com autocomplete de material
// ─────────────────────────────────────────────────────────────────────────────
class _VinculoMaterialDialog extends StatefulWidget {
  final int fornecedorId;
  final FornecedorMaterialVinculoModel? vinculo;
  final Set<int> materiaisVinculados;
  final Future<void> Function() onSalvo;

  const _VinculoMaterialDialog({
    required this.fornecedorId,
    this.vinculo,
    this.materiaisVinculados = const {},
    required this.onSalvo,
  });

  @override
  State<_VinculoMaterialDialog> createState() => _VinculoMaterialDialogState();
}

class _VinculoMaterialDialogState extends State<_VinculoMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _materialIdCtrl = TextEditingController();
  final _materialNomeCtrl = TextEditingController();
  final _materialMedidaCtrl = TextEditingController();
  final _materialEspessuraCtrl = TextEditingController();
  final _precoCtrl = TextEditingController();
  final _precoM2Ctrl = TextEditingController();
  bool _salvando = false;

  // Resultado da busca de materiais para autocomplete
  List<Map<String, dynamic>> _sugestoes = [];
  bool _buscandoMateriais = false;
  // Material selecionado via autocomplete
  int? _materialIdSelecionado;
  // Indica que o ID digitado não existe na base
  bool _idNaoEncontrado = false;
  // Debounce para busca por ID
  Timer? _debounceId;
  // Flag para suprimir listeners durante atribuições programáticas
  bool _ignorarListeners = false;

  bool get _editando => widget.vinculo != null;

  @override
  void initState() {
    super.initState();
    if (_editando) {
      final v = widget.vinculo!;
      _materialIdCtrl.text = v.materialId.toString();
      _materialNomeCtrl.text = v.materialNome ?? v.descricaoCompleta;
      _materialMedidaCtrl.text = v.materialMedida ?? '';
      _materialEspessuraCtrl.text = v.materialEspessura ?? '';
      _materialIdSelecionado = v.materialId;
      _precoCtrl.text = v.preco.toStringAsFixed(2);
      _precoM2Ctrl.text = v.precoMetroQuadrado.toStringAsFixed(2);
    }

    _materialIdCtrl.addListener(_onIdChanged);
    _materialNomeCtrl.addListener(_onNomeChanged);
    _materialMedidaCtrl.addListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.addListener(_onFiltroAdicionalChanged);
  }

  @override
  void dispose() {
    _debounceId?.cancel();
    _materialIdCtrl.removeListener(_onIdChanged);
    _materialNomeCtrl.removeListener(_onNomeChanged);
    _materialMedidaCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialIdCtrl.dispose();
    _materialNomeCtrl.dispose();
    _materialMedidaCtrl.dispose();
    _materialEspessuraCtrl.dispose();
    _precoCtrl.dispose();
    _precoM2Ctrl.dispose();
    super.dispose();
  }

  /// Limpa todos os campos de material e reseta o estado de seleção.
  void _limparSelecaoMaterial() {
    _debounceId?.cancel();
    _ignorarListeners = true;
    _materialIdCtrl.text        = '';
    _materialNomeCtrl.text      = '';
    _materialMedidaCtrl.text    = '';
    _materialEspessuraCtrl.text = '';
    _ignorarListeners = false;
    setState(() {
      _sugestoes             = [];
      _materialIdSelecionado = null;
      _idNaoEncontrado       = false;
    });
  }

  // Busca materiais pelo ID digitado — com debounce e busca por ID exato
  void _onIdChanged() {
    if (_ignorarListeners) return;
    final texto = _materialIdCtrl.text.trim();

    // Apagar o ID limpa todos os campos
    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialNomeCtrl.text      = '';
      _materialMedidaCtrl.text    = '';
      _materialEspessuraCtrl.text = '';
      _ignorarListeners = false;
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
      return;
    }

    // Se o ID digitado coincide com o material já selecionado, não faz nada.
    final idDigitadoAgora = int.tryParse(texto);
    if (idDigitadoAgora != null && idDigitadoAgora == _materialIdSelecionado) return;

    // Limpa seleção e erro enquanto o usuário digita
    if (_materialIdSelecionado != null || _idNaoEncontrado) {
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
    }

    _debounceId?.cancel();
    _debounceId = Timer(const Duration(milliseconds: 500), () async {
      final idDigitado = int.tryParse(texto);
      if (idDigitado == null || !mounted) return;

      setState(() {
        _buscandoMateriais = true;
        _sugestoes         = [];
      });

      try {
        final prov  = context.read<FornecedorProvider>();
        final lista = await prov.buscarMateriais(idPrefix: texto);

        if (!mounted) return;

        final match = lista
            .where((m) => int.tryParse(m['id'].toString()) == idDigitado)
            .toList();

        if (match.isNotEmpty) {
          _selecionarMaterial(match.first);
        } else {
          _ignorarListeners = true;
          _materialNomeCtrl.text = '';
          _ignorarListeners = false;
          setState(() {
            _sugestoes       = [];
            _idNaoEncontrado = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _idNaoEncontrado = false);
      } finally {
        if (mounted) setState(() => _buscandoMateriais = false);
      }
    });
  }

  // Busca materiais pelo nome digitado; apagar nome limpa todos os campos
  void _onNomeChanged() {
    if (_ignorarListeners) return;
    final texto = _materialNomeCtrl.text.trim();

    // Apagar o nome limpa todos os campos
    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialIdCtrl.text        = '';
      _materialMedidaCtrl.text    = '';
      _materialEspessuraCtrl.text = '';
      _ignorarListeners = false;
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
      return;
    }

    // Material já selecionado: nome é read-only, não relança busca
    if (_materialIdSelecionado != null) return;
    _buscarMateriais(nomePrefix: texto);
  }

  // Filtro de medida/espessura: apaga ID (mantém nome), relança busca com filtros atuais
  void _onFiltroAdicionalChanged() {
    if (_ignorarListeners) return;
    // Se material já selecionado, desfaz apenas a seleção mas preserva o nome
    if (_materialIdSelecionado != null) {
      _ignorarListeners = true;
      _materialIdCtrl.text = '';
      _ignorarListeners = false;
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
    }
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    } else {
      setState(() => _sugestoes = []);
    }
  }

  // Ao focar em medida ou espessura, dispara busca imediata para abrir o dropdown
  void _onFiltroAdicionalFocus() {
    if (_materialIdSelecionado != null) return;
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    }
  }


  Future<void> _buscarMateriais({String? idPrefix, String? nomePrefix}) async {
    setState(() => _buscandoMateriais = true);
    try {
      final prov  = context.read<FornecedorProvider>();
      final lista = await prov.buscarMateriais(
        idPrefix:  idPrefix,
        nomePrefix: nomePrefix,
        medida:    _materialMedidaCtrl.text.trim().isEmpty ? null : _materialMedidaCtrl.text.trim(),
        espessura: _materialEspessuraCtrl.text.trim().isEmpty ? null : _materialEspessuraCtrl.text.trim(),
      );
      if (mounted) setState(() => _sugestoes = lista);
    } catch (_) {
      if (mounted) setState(() => _sugestoes = []);
    } finally {
      if (mounted) setState(() => _buscandoMateriais = false);
    }
  }

  void _selecionarMaterial(Map<String, dynamic> material) {
    final id        = material['id']        as int;
    final nome      = material['nome']      as String? ?? '';
    final medida    = material['medida']    as String?;
    final espessura = material['espessura'] as String?;

    _ignorarListeners = true;
    _materialIdCtrl.text        = id.toString();
    _materialNomeCtrl.text      = nome;
    _materialMedidaCtrl.text    = medida    ?? '';
    _materialEspessuraCtrl.text = espessura ?? '';
    _ignorarListeners = false;

    setState(() {
      _materialIdSelecionado = id;
      _idNaoEncontrado       = false;
      _sugestoes             = [];
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);

    final prov = context.read<FornecedorProvider>();

    double? parsePreco(String text) {
      final v = text.trim().replaceAll(',', '.');
      return v.isEmpty ? null : double.tryParse(v);
    }

    final dados = {
      'preco': parsePreco(_precoCtrl.text),
      'precoMetroQuadrado': parsePreco(_precoM2Ctrl.text),
    };

    bool sucesso;
    if (_editando) {
      sucesso = await prov.atualizarPreco(
          widget.fornecedorId, widget.vinculo!.materialId, dados);
    } else {
      sucesso = await prov.vincularMaterial(widget.fornecedorId, {
        'materialId': _materialIdSelecionado ?? int.parse(_materialIdCtrl.text),
        ...dados,
      });
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    if (sucesso) {
      await widget.onSalvo();
      if (mounted) Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(prov.erro ?? 'Erro ao salvar'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(_editando ? 'Editar valor' : 'Vincular material'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Seleção de material (apenas no modo criação) ───────────────
              if (!_editando) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Campo ID
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: _materialIdCtrl,
                        decoration: InputDecoration(
                          labelText: 'ID *',
                          isDense: true,
                          suffixIcon: _buscandoMateriais
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primary),
                                  ),
                                )
                              : _materialIdSelecionado != null
                                  ? const Icon(Icons.check_circle,
                                      color: AppTheme.success, size: 18)
                                  : _idNaoEncontrado
                                      ? const Icon(Icons.error_outline,
                                          color: AppTheme.error, size: 18)
                                      : null,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Obrigatório';
                          }
                          if (_idNaoEncontrado) {
                            return 'ID não encontrado';
                          }
                          if (_materialIdSelecionado == null) {
                            return 'Aguarde a validação';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Campo Nome (autocomplete)
                    Expanded(
                      child: TextFormField(
                        controller: _materialNomeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nome do material *',
                          isDense: true,
                          suffixIcon: _buscandoMateriais
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primary),
                                  ),
                                )
                              : _materialIdSelecionado != null
                                  ? const Icon(Icons.check_circle,
                                      color: AppTheme.success, size: 18)
                                  : null,
                        ),
                        inputFormatters: [_UpperCaseFormatter()],
                        validator: (v) {
                          if (_materialIdSelecionado == null &&
                              (v == null || v.trim().isEmpty)) {
                            return 'Selecione um material pelo nome ou ID';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),

                // ── Filtros adicionais: Medida e Espessura ─────────────────
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _materialMedidaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Medida',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.straighten_outlined,
                            size: 16,
                            color: AppTheme.textHint,
                          ),
                        ),
                        inputFormatters: [_UpperCaseFormatter()],
                        onTap: _onFiltroAdicionalFocus,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: TextFormField(
                        controller: _materialEspessuraCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Espessura',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.layers_outlined,
                            size: 16,
                            color: AppTheme.textHint,
                          ),
                        ),
                        inputFormatters: [_UpperCaseFormatter()],
                        onTap: _onFiltroAdicionalFocus,
                      ),
                    ),

                    const SizedBox(width: 8),

                    TextButton.icon(
                      onPressed: _limparSelecaoMaterial,
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Limpar'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),

                // Lista de sugestões
                if (_sugestoes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.divider),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _sugestoes.length,
                      itemBuilder: (_, i) {
                        final m = _sugestoes[i];
                        final medida    = m['medida']    as String?;
                        final espessura = m['espessura'] as String?;
                        final detalhe = [
                          if (medida    != null && medida.isNotEmpty)    medida,
                          if (espessura != null && espessura.isNotEmpty) espessura,
                        ].join(' · ');

                        final jaVinculado = widget.materiaisVinculados
                            .contains(m['id'] as int);

                        return InkWell(
                          onTap: jaVinculado ? null : () => _selecionarMaterial(m),
                          child: Opacity(
                            opacity: jaVinculado ? 0.45 : 1.0,
                            child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${m['id']}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m['nome'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (detalhe.isNotEmpty)
                                        Text(
                                          detalhe,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (jaVinculado)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.textHint
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Já vinculado',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],

              // ── Valores ─────────────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _precoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Valor (R\$)',
                      prefixText: 'R\$ ',
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalInputFormatter()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _precoM2Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Valor m² (R\$)',
                      prefixText: 'R\$ ',
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalInputFormatter()],
                  ),
                ),
              ]),
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
          onPressed: _salvando ? null : _salvar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: _salvando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
//  Diálogo "Vincular por Material" — seleciona um material e vincula/atualiza
//  preços em múltiplos fornecedores ao mesmo tempo.
// ─────────────────────────────────────────────────────────────────────────────

/// Dados mutáveis de um fornecedor na lista de vínculo.
class _FornecedorVinculoEntry {
  final FornecedorModel fornecedor;
  bool selecionado;
  final TextEditingController precoCtrl;
  final TextEditingController precoM2Ctrl;
  /// Se já havia vínculo ativo com o material selecionado.
  final bool jaVinculado;

  _FornecedorVinculoEntry({
    required this.fornecedor,
    required this.selecionado,
    required this.precoCtrl,
    required this.precoM2Ctrl,
    this.jaVinculado = false,
  });

  void dispose() {
    precoCtrl.dispose();
    precoM2Ctrl.dispose();
  }
}

class _VincularPorMaterialDialog extends StatefulWidget {
  final Future<void> Function() onSalvo;
  const _VincularPorMaterialDialog({required this.onSalvo});

  @override
  State<_VincularPorMaterialDialog> createState() =>
      _VincularPorMaterialDialogState();
}

class _VincularPorMaterialDialogState
    extends State<_VincularPorMaterialDialog> {
  // ── Busca de material ────────────────────────────────────────────────────
  final _materialIdCtrl       = TextEditingController();
  final _materialNomeCtrl     = TextEditingController();
  final _materialMedidaCtrl   = TextEditingController();
  final _materialEspessuraCtrl = TextEditingController();

  int?   _materialIdSelecionado;
  bool   _buscandoMaterial  = false;
  bool   _idNaoEncontrado   = false;
  bool   _ignorarListeners  = false;
  List<Map<String, dynamic>> _sugestoes = [];
  Timer? _debounceId;

  // ── Lista de fornecedores ────────────────────────────────────────────────
  List<_FornecedorVinculoEntry> _entradas = [];
  bool _carregandoFornecedores = false;

  // ── Salvamento ───────────────────────────────────────────────────────────
  bool _salvando = false;

  // ── Busca de fornecedor para adicionar (overlay dropdown) ───────────────
  final _buscaFornecedorCtrl  = TextEditingController();
  final _buscaFornecedorFocus = FocusNode();
  final _buscaLayerLink       = LayerLink();
  OverlayEntry? _overlayEntry;
  List<FornecedorModel> _sugestoesFornecedor = [];
  bool _buscandoFornecedor = false;
  Timer? _debounceFornecedor;

  @override
  void initState() {
    super.initState();
    _materialIdCtrl.addListener(_onIdChanged);
    _materialNomeCtrl.addListener(_onNomeChanged);
    _materialMedidaCtrl.addListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.addListener(_onFiltroAdicionalChanged);
    _buscaFornecedorCtrl.addListener(_onBuscaFornecedorChanged);
    _buscaFornecedorFocus.addListener(_onBuscaFornecedorFocusChanged);
    _carregarFornecedores();
  }

  @override
  void dispose() {
    _debounceId?.cancel();
    _debounceFornecedor?.cancel();
    _materialIdCtrl.removeListener(_onIdChanged);
    _materialNomeCtrl.removeListener(_onNomeChanged);
    _materialMedidaCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.removeListener(_onFiltroAdicionalChanged);
    _buscaFornecedorCtrl.removeListener(_onBuscaFornecedorChanged);
    _buscaFornecedorFocus.removeListener(_onBuscaFornecedorFocusChanged);
    _overlayEntry?.remove();
    _overlayEntry = null;
    _materialIdCtrl.dispose();
    _materialNomeCtrl.dispose();
    _materialMedidaCtrl.dispose();
    _materialEspessuraCtrl.dispose();
    _buscaFornecedorCtrl.dispose();
    _buscaFornecedorFocus.dispose();
    for (final e in _entradas) {
      e.dispose();
    }
    super.dispose();
  }

  // ── Inicializa sem carregar fornecedores (aguarda seleção de material) ───
  Future<void> _carregarFornecedores() async {
    // Nada a fazer na abertura do dialog; a lista fica vazia até um material ser selecionado.
  }

  // ── Overlay helpers ─────────────────────────────────────────────────────
  void _mostrarOverlay() {
    _fecharOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (_) => _BuscaFornecedorOverlay(
        layerLink:  _buscaLayerLink,
        sugestoes:  _sugestoesFornecedor,
        carregando: _buscandoFornecedor,
        onSelecionar: _adicionarFornecedorDoOverlay,
        onFechar:   _fecharOverlay,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _fecharOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _atualizarOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _onBuscaFornecedorFocusChanged() {
    if (_buscaFornecedorFocus.hasFocus) {
      // Ao focar, já dispara busca (mesmo campo vazio) para listar todos
      _dispararBuscaFornecedor(_buscaFornecedorCtrl.text.trim());
    } else {
      // Pequeno delay para permitir cliques dentro do overlay
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_buscaFornecedorFocus.hasFocus) {
          _fecharOverlay();
        }
      });
    }
  }

  // ── Busca fornecedores pelo nome para adicionar ──────────────────────────
  void _onBuscaFornecedorChanged() {
    if (_materialIdSelecionado == null) return;
    _dispararBuscaFornecedor(_buscaFornecedorCtrl.text.trim());
  }

  /// Dispara a busca de fornecedores; [texto] vazio lista todos.
  void _dispararBuscaFornecedor(String texto) {
    if (_materialIdSelecionado == null) return;

    _debounceFornecedor?.cancel();

    // Mostra overlay imediatamente com loading
    if (_overlayEntry == null) _mostrarOverlay();

    _debounceFornecedor = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _buscandoFornecedor = true);
      _atualizarOverlay();
      try {
        final prov = context.read<FornecedorProvider>();
        // busca vazia (null) retorna todos os fornecedores disponíveis
        final lista = await prov.buscarFornecedores(
            busca: texto.isEmpty ? null : texto);
        if (!mounted) return;
        final idsExistentes = _entradas.map((e) => e.fornecedor.id).toSet();
        setState(() {
          _sugestoesFornecedor =
              lista.where((f) => !idsExistentes.contains(f.id)).toList();
          _buscandoFornecedor = false;
        });
        if (_overlayEntry == null) {
          _mostrarOverlay();
        } else {
          _atualizarOverlay();
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _sugestoesFornecedor = [];
            _buscandoFornecedor  = false;
          });
          _atualizarOverlay();
        }
      }
    });
  }

  /// Clique no overlay → adiciona direto à lista de entradas e mantém overlay aberto.
  void _adicionarFornecedorDoOverlay(FornecedorModel f) {
    setState(() {
      _entradas.add(_FornecedorVinculoEntry(
        fornecedor:  f,
        selecionado: true,
        precoCtrl:   TextEditingController(),
        precoM2Ctrl: TextEditingController(),
        jaVinculado: false,
      ));
      // Remove das sugestões para não aparecer de novo no overlay
      _sugestoesFornecedor.removeWhere((s) => s.id == f.id);
    });
    // Mantém overlay aberto para selecionar mais
    _atualizarOverlay();
  }

  // ── Carrega fornecedores vinculados ao material selecionado via API ───────
  Future<void> _carregarFornecedoresDoMaterial(int materialId) async {
    setState(() => _carregandoFornecedores = true);
    try {
      final prov = context.read<FornecedorProvider>();
      final lista = await prov.listarPorMaterial(materialId);
      if (!mounted) return;
      _reconstruirEntradas(lista, materialTrocou: true);
    } finally {
      if (mounted) setState(() => _carregandoFornecedores = false);
    }
  }

  /// Reconstrói `_entradas` com a lista de fornecedores fornecida.
  /// Quando [materialTrocou] é true, ignora preços/seleção anteriores e
  /// preenche com os dados do vínculo existente para o material atual.
  void _reconstruirEntradas(
    List<FornecedorModel> fornecedores, {
    bool materialTrocou = false,
  }) {
    // Quando material trocou, descarta tudo e começa do zero
    if (materialTrocou) {
      for (final e in _entradas) {
        e.dispose();
      }
      _entradas = [];
    }

    // índice por id para recuperar entradas antigas (só útil quando material NÃO trocou)
    final antigos = {for (final e in _entradas) e.fornecedor.id: e};

    final novas = <_FornecedorVinculoEntry>[];
    for (final f in fornecedores) {
      // Vínculo existente com o material atual (já vem na lista retornada pela API)
      FornecedorMaterialVinculoModel? vinculo;
      if (_materialIdSelecionado != null) {
        try {
          vinculo = f.materiais.firstWhere(
            (m) => m.materialId == _materialIdSelecionado && m.ativo,
          );
        } catch (_) {
          vinculo = null;
        }
      }

      final antigo = antigos[f.id];
      final jaVinculado = vinculo != null;

      // Quando material trocou: sempre usa o vínculo existente (ou vazio).
      // Quando é o mesmo material: preserva digitação do usuário se houver.
      String precoInicial   = '';
      String precoM2Inicial = '';
      if (!materialTrocou && antigo != null && antigo.precoCtrl.text.isNotEmpty) {
        precoInicial   = antigo.precoCtrl.text;
        precoM2Inicial = antigo.precoM2Ctrl.text;
      } else if (jaVinculado) {
        precoInicial   = vinculo.preco.toStringAsFixed(2);
        precoM2Inicial = vinculo.precoMetroQuadrado.toStringAsFixed(2);
      }

      novas.add(_FornecedorVinculoEntry(
        fornecedor: f,
        // Pré-seleciona se já estava vinculado
        selecionado: materialTrocou ? jaVinculado : (antigo?.selecionado ?? jaVinculado),
        precoCtrl:   TextEditingController(text: precoInicial),
        precoM2Ctrl: TextEditingController(text: precoM2Inicial),
        jaVinculado: jaVinculado,
      ));

      // Descarta o antigo (novo controlador criado acima)
      if (!materialTrocou) antigo?.dispose();
    }

    _entradas = novas;
  }

  /// Limpa todos os campos de material, reseta seleção e descarta entradas.
  void _limparSelecaoMaterial() {
    _debounceId?.cancel();
    _ignorarListeners = true;
    _materialIdCtrl.text        = '';
    _materialNomeCtrl.text      = '';
    _materialMedidaCtrl.text    = '';
    _materialEspessuraCtrl.text = '';
    _ignorarListeners = false;
    for (final e in _entradas) { e.dispose(); }
    setState(() {
      _sugestoes             = [];
      _materialIdSelecionado = null;
      _idNaoEncontrado       = false;
      _entradas              = [];
    });
  }

  // ── Listeners de busca de material ──────────────────────────────────────
  void _onIdChanged() {
    if (_ignorarListeners) return;
    final texto = _materialIdCtrl.text.trim();

    // Apagar o ID limpa todos os campos e a lista de fornecedores
    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialNomeCtrl.text      = '';
      _materialMedidaCtrl.text    = '';
      _materialEspessuraCtrl.text = '';
      _ignorarListeners = false;
      for (final e in _entradas) { e.dispose(); }
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
        _entradas              = [];
      });
      return;
    }

    // Se o ID digitado coincide com o material já selecionado, não faz nada.
    final idDigitadoAgora = int.tryParse(texto);
    if (idDigitadoAgora != null && idDigitadoAgora == _materialIdSelecionado) return;

    if (_materialIdSelecionado != null || _idNaoEncontrado) {
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
    }

    _debounceId?.cancel();
    _debounceId = Timer(const Duration(milliseconds: 500), () async {
      final idDigitado = int.tryParse(texto);
      if (idDigitado == null || !mounted) return;
      setState(() {
        _buscandoMaterial = true;
        _sugestoes        = [];
      });
      try {
        final prov  = context.read<FornecedorProvider>();
        final lista = await prov.buscarMateriais(idPrefix: texto);
        if (!mounted) return;
        final match =
            lista.where((m) => int.tryParse(m['id'].toString()) == idDigitado).toList();
        if (match.isNotEmpty) {
          _selecionarMaterial(match.first);
        } else {
          _ignorarListeners = true;
          _materialNomeCtrl.text = '';
          _ignorarListeners = false;
          setState(() {
            _sugestoes       = [];
            _idNaoEncontrado = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _idNaoEncontrado = false);
      } finally {
        if (mounted) setState(() => _buscandoMaterial = false);
      }
    });
  }

  void _onNomeChanged() {
    if (_ignorarListeners) return;
    final texto = _materialNomeCtrl.text.trim();

    // Apagar o nome limpa todos os campos e a lista de fornecedores
    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialIdCtrl.text        = '';
      _materialMedidaCtrl.text    = '';
      _materialEspessuraCtrl.text = '';
      _ignorarListeners = false;
      for (final e in _entradas) { e.dispose(); }
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
        _entradas              = [];
      });
      return;
    }

    // Material já selecionado: nome é read-only, não relança busca
    if (_materialIdSelecionado != null) return;
    _buscarMateriais(nomePrefix: texto);
  }

  // Filtro de medida/espessura: apaga ID (mantém nome), relança busca com filtros atuais
  void _onFiltroAdicionalChanged() {
    if (_ignorarListeners) return;
    // Se material já selecionado, desfaz apenas a seleção mas preserva o nome e descarta entradas
    if (_materialIdSelecionado != null) {
      _ignorarListeners = true;
      _materialIdCtrl.text = '';
      _ignorarListeners = false;
      for (final e in _entradas) { e.dispose(); }
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
        _entradas              = [];
      });
    }
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    } else {
      setState(() => _sugestoes = []);
    }
  }

  // Ao focar em medida ou espessura, dispara busca imediata para abrir o dropdown
  void _onFiltroAdicionalFocus() {
    if (_materialIdSelecionado != null) return;
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    }
  }

  Future<void> _buscarMateriais({String? idPrefix, String? nomePrefix}) async {
    setState(() => _buscandoMaterial = true);
    try {
      final prov  = context.read<FornecedorProvider>();
      final lista = await prov.buscarMateriais(
        idPrefix: idPrefix,
        nomePrefix: nomePrefix,
        medida: _materialMedidaCtrl.text.trim().isEmpty ? null : _materialMedidaCtrl.text.trim(),
        espessura: _materialEspessuraCtrl.text.trim().isEmpty ? null : _materialEspessuraCtrl.text.trim(),
      );
      if (mounted) setState(() => _sugestoes = lista);
    } catch (_) {
      if (mounted) setState(() => _sugestoes = []);
    } finally {
      if (mounted) setState(() => _buscandoMaterial = false);
    }
  }

  void _selecionarMaterial(Map<String, dynamic> material) {
    final id        = material['id']        as int;
    final nome      = material['nome']      as String? ?? '';
    final medida    = material['medida']    as String?;
    final espessura = material['espessura'] as String?;

    _ignorarListeners = true;
    _materialIdCtrl.text        = id.toString();
    _materialNomeCtrl.text      = nome;
    _materialMedidaCtrl.text    = medida    ?? '';
    _materialEspessuraCtrl.text = espessura ?? '';
    _ignorarListeners = false;

    _materialIdSelecionado = id;

    setState(() {
      _idNaoEncontrado = false;
      _sugestoes       = [];
    });

    // Busca via API somente os fornecedores vinculados a este material
    _carregarFornecedoresDoMaterial(id);
  }

  // ── Salvamento em lote ───────────────────────────────────────────────────
  Future<void> _salvar() async {
    if (_materialIdSelecionado == null) return;

    if (_entradas.isEmpty) return;

    setState(() => _salvando = true);

    double? parsePreco(String text) {
      final v = text.trim().replaceAll(',', '.');
      return v.isEmpty ? null : double.tryParse(v);
    }

    final prov   = context.read<FornecedorProvider>();
    int sucessos = 0;
    int falhas   = 0;

    for (final entrada in _entradas) {
      final dados = {
        'materialId': _materialIdSelecionado,
        'preco':               parsePreco(entrada.precoCtrl.text),
        'precoMetroQuadrado':  parsePreco(entrada.precoM2Ctrl.text),
      };
      final ok = await prov.vincularMaterial(entrada.fornecedor.id, dados);
      if (ok) {
        sucessos++;
      } else {
        falhas++;
      }
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    await widget.onSalvo();

    if (mounted) {
      final msg = falhas == 0
          ? '$sucessos fornecedor(es) vinculado(s) com sucesso.'
          : '$sucessos vinculado(s), $falhas com erro.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: falhas == 0 ? AppTheme.success : AppTheme.error,
      ));
      Navigator.of(context).pop();
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: SizedBox(
        width: 720,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cabeçalho ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vincular por Material',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Selecione um material e vincule a vários fornecedores',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.divider),

            // ── Seleção de material ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Material',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ID
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _materialIdCtrl,
                          decoration: InputDecoration(
                            labelText: 'ID',
                            isDense: true,
                            suffixIcon: _buscandoMaterial
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primary),
                                    ),
                                  )
                                : _materialIdSelecionado != null
                                    ? const Icon(Icons.check_circle,
                                        color: AppTheme.success, size: 18)
                                    : _idNaoEncontrado
                                        ? const Icon(Icons.error_outline,
                                            color: AppTheme.error, size: 18)
                                        : null,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Nome (autocomplete)
                      Expanded(
                        child: TextField(
                          controller: _materialNomeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Nome do material',
                            isDense: true,
                            suffixIcon: _buscandoMaterial
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primary),
                                    ),
                                  )
                                : _materialIdSelecionado != null
                                    ? const Icon(Icons.check_circle,
                                        color: AppTheme.success, size: 18)
                                    : null,
                          ),
                          inputFormatters: [_UpperCaseFormatter()],
                        ),
                      ),
                    ],
                  ),

                  // ── Filtros adicionais: Medida e Espessura ────────────────
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _materialMedidaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Medida',
                            isDense: true,
                            prefixIcon: Icon(Icons.straighten_outlined,
                                size: 16, color: AppTheme.textHint),
                          ),
                          inputFormatters: [_UpperCaseFormatter()],
                          onTap: _onFiltroAdicionalFocus,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _materialEspessuraCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Espessura',
                            isDense: true,
                            prefixIcon: Icon(Icons.layers_outlined,
                                size: 16, color: AppTheme.textHint),
                          ),
                          inputFormatters: [_UpperCaseFormatter()],
                          onTap: _onFiltroAdicionalFocus,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _limparSelecaoMaterial,
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text('Limpar'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  // Sugestões de material
                  if (_sugestoes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.divider),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _sugestoes.length,
                        itemBuilder: (_, i) {
                          final m         = _sugestoes[i];
                          final medida    = m['medida']    as String?;
                          final espessura = m['espessura'] as String?;
                          final detalhe   = [
                            if (medida    != null && medida.isNotEmpty)    medida,
                            if (espessura != null && espessura.isNotEmpty) espessura,
                          ].join(' · ');
                          return InkWell(
                            onTap: () => _selecionarMaterial(m),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '#${m['id']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(m['nome'] ?? '',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.textPrimary),
                                            overflow: TextOverflow.ellipsis),
                                        if (detalhe.isNotEmpty)
                                          Text(detalhe,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppTheme.textSecondary),
                                              overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),

            const Divider(height: 1, color: AppTheme.divider),

            // ── Cabeçalho da tabela de fornecedores ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Fornecedores',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      // (sem seleção múltipla — todos os itens da lista serão salvos)
                    ],
                  ),
                  // ── Campo para adicionar fornecedor via overlay ─────────
                  if (_materialIdSelecionado != null) ...[
                    const SizedBox(height: 8),
                    CompositedTransformTarget(
                      link: _buscaLayerLink,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _buscaFornecedorCtrl,
                        builder: (_, val, __) => TextField(
                          controller:  _buscaFornecedorCtrl,
                          focusNode:   _buscaFornecedorFocus,
                          onTap:       () {
                            // Ao tocar no campo, já carrega sugestões
                            _dispararBuscaFornecedor(_buscaFornecedorCtrl.text.trim());
                          },
                          decoration: InputDecoration(
                            hintText: 'Buscar fornecedor para adicionar…',
                            isDense: true,
                            prefixIcon: const Icon(Icons.person_search_outlined,
                                size: 16, color: AppTheme.textHint),
                            suffixIcon: _buscandoFornecedor
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primary),
                                    ),
                                  )
                                : val.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        color: AppTheme.textHint,
                                        onPressed: () {
                                          _buscaFornecedorCtrl.clear();
                                          setState(() => _sugestoesFornecedor = []);
                                          _fecharOverlay();
                                        },
                                      )
                                    : null,
                          ),
                        ),
                      ),
                    ),
                    // (sem chips pendentes — seleção já vai direto para a lista)
                  ],
                ],
              ),
            ),

            // ── Lista de fornecedores ───────────────────────────────────────
            Expanded(
              child: _carregandoFornecedores
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    )
                  : _entradas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _materialIdSelecionado == null
                                    ? Icons.category_outlined
                                    : Icons.storefront_outlined,
                                size: 40,
                                color: AppTheme.textHint,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _materialIdSelecionado == null
                                    ? 'Selecione um material para ver os fornecedores vinculados.'
                                    : 'Nenhum fornecedor vinculado ainda.',
                                style: const TextStyle(color: AppTheme.textSecondary),
                                textAlign: TextAlign.center,
                              ),
                              if (_materialIdSelecionado != null) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'Use o campo acima para buscar e adicionar fornecedores.',
                                  style: TextStyle(
                                    color: AppTheme.textHint,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _entradas.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final entrada = _entradas[i];
                            return _FornecedorVinculoTile(
                              entrada:   entrada,
                              onRemover: () {
                                final f = entrada.fornecedor;
                                setState(() {
                                  _entradas.removeAt(i);
                                  // Recoloca na lista de sugestões se o overlay estiver aberto
                                  if (_overlayEntry != null) {
                                    _sugestoesFornecedor.insert(0, f);
                                  }
                                });
                                entrada.dispose();
                                _atualizarOverlay();
                              },
                            );
                          },
                        ),
            ),

            const Divider(height: 1, color: AppTheme.divider),

            // ── Rodapé ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              child: Row(
                children: [
                  if (_materialIdSelecionado != null && _entradas.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '${_entradas.length} fornecedor(es)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_salvando ||
                            _materialIdSelecionado == null ||
                            _entradas.isEmpty)
                        ? null
                        : _salvar,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                    child: _salvando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Salvar vínculos'),
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
//  Overlay dropdown de busca de fornecedor — clique direto adiciona à lista
// ─────────────────────────────────────────────────────────────────────────────
class _BuscaFornecedorOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final List<FornecedorModel> sugestoes;
  final bool carregando;
  final void Function(FornecedorModel) onSelecionar;
  final VoidCallback onFechar;

  const _BuscaFornecedorOverlay({
    required this.layerLink,
    required this.sugestoes,
    required this.carregando,
    required this.onSelecionar,
    required this.onFechar,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tap fora fecha
        Positioned.fill(
          child: GestureDetector(
            onTap: onFechar,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link:             layerLink,
          showWhenUnlinked: false,
          offset:           const Offset(0, 40),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation:    8,
              borderRadius: BorderRadius.circular(10),
              color:        AppTheme.surface,
              child: Container(
                width:       500,
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: carregando && sugestoes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                      )
                    : sugestoes.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Nenhum fornecedor encontrado.',
                              style: TextStyle(color: AppTheme.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding:    EdgeInsets.zero,
                            itemCount:  sugestoes.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: AppTheme.divider),
                            itemBuilder: (_, i) {
                              final f = sugestoes[i];
                              return InkWell(
                                onTap: () => onSelecionar(f),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 11),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.add_circle_outline,
                                        size: 18,
                                        color: AppTheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              f.nomeFantasia,
                                              style: const TextStyle(
                                                fontSize:   13,
                                                fontWeight: FontWeight.w600,
                                                color:      AppTheme.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (f.tipoFornecedor != null ||
                                                f.nomeVendedor   != null)
                                              Text(
                                                [
                                                  if (f.tipoFornecedor != null)
                                                    f.tipoFornecedor!,
                                                  if (f.nomeVendedor != null)
                                                    f.nomeVendedor!,
                                                ].join(' · '),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color:    AppTheme.textSecondary,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tile de fornecedor dentro do VincularPorMaterialDialog
// ─────────────────────────────────────────────────────────────────────────────
class _FornecedorVinculoTile extends StatefulWidget {
  final _FornecedorVinculoEntry entrada;
  final VoidCallback? onRemover;

  const _FornecedorVinculoTile({
    required this.entrada,
    this.onRemover,
  });

  @override
  State<_FornecedorVinculoTile> createState() => _FornecedorVinculoTileState();
}

class _FornecedorVinculoTileState extends State<_FornecedorVinculoTile> {
  @override
  Widget build(BuildContext context) {
    final e = widget.entrada;
    final f = e.fornecedor;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // ── Info do fornecedor ────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          f.nomeFantasia,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (e.jaVinculado) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'já vinculado',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (f.tipoFornecedor != null || f.nomeVendedor != null)
                    Text(
                      [
                        if (f.tipoFornecedor != null) f.tipoFornecedor!,
                        if (f.nomeVendedor   != null) f.nomeVendedor!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ── Campos de preço — sempre visíveis ─────────────────────────
            SizedBox(
              width: 110,
              child: TextField(
                controller: e.precoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor (R\$)',
                  prefixText: 'R\$ ',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_DecimalInputFormatter()],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: e.precoM2Ctrl,
                decoration: const InputDecoration(
                  labelText: 'Valor m²',
                  prefixText: 'R\$ ',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_DecimalInputFormatter()],
              ),
            ),

            // ── Botão remover ─────────────────────────────────────────────
            if (widget.onRemover != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Remover',
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                color: AppTheme.error,
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRemover,
              ),
            ],
          ],
        ),
      ),
    );
  }
}