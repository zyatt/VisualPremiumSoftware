import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/material_model.dart';
import '../providers/material_provider.dart';
import '../theme/app_theme.dart';

/// Formata qualquer entrada de texto para maiúsculas em tempo real
/// e remove caracteres acentuados / diacríticos.
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
    // Ajusta a seleção caso o comprimento mude
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

/// Permite apenas dígitos e um único separador decimal (ponto ou vírgula → ponto).
class _DecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Substitui vírgula por ponto
    var texto = newValue.text.replaceAll(',', '.');
    // Remove qualquer caractere que não seja dígito ou ponto
    texto = texto.replaceAll(RegExp(r'[^\d.]'), '');
    // Garante no máximo um ponto decimal
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

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  final _buscaCtrl   = TextEditingController();
  final _buscaIdCtrl = TextEditingController();
  String _statusFiltro    = '';
  String _categoriaFiltro = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<MaterialProvider>();
      p.carregar();
      p.carregarCategorias();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    _buscaIdCtrl.dispose();
    super.dispose();
  }

  void _aplicarFiltros() {
    context.read<MaterialProvider>().carregar(
          busca:     _buscaCtrl.text,
          categoria: _categoriaFiltro,
          status:    _statusFiltro,
          id:        _buscaIdCtrl.text.trim(),
        );
  }

  void _onBuscaChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), _aplicarFiltros);
  }

  Future<void> _abrirFormMaterial([MaterialModel? material]) async {
    final salvou = await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MaterialFormDialog(material: material),
    );

    if (!mounted) return;

    if (salvou == true) {
      final p = context.read<MaterialProvider>();
      p.carregarCategorias();
      _aplicarFiltros();
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
      content: Text(
          ok ? '"${m.nome}" desativado.' : context.read<MaterialProvider>().erro ?? 'Erro'),
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
      content: Text(
          ok ? '"${m.nome}" reativado.' : context.read<MaterialProvider>().erro ?? 'Erro'),
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
      content: Text(
          ok ? '"${m.nome}" excluído.' : context.read<MaterialProvider>().erro ?? 'Erro'),
      backgroundColor: AppTheme.error,
    ));
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
                      'Gerencie os materiais em estoque',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
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
                // Busca por nome/material
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Buscar material...',
                      prefixIcon: Icon(Icons.search, color: AppTheme.textHint, size: 20),
                      isDense: true,
                    ),
                    onChanged:   _onBuscaChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                // Filtro status
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFiltro.isEmpty ? null : _statusFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      isDense: true,
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
                const SizedBox(width: 12),
                // Filtro categoria
                Consumer<MaterialProvider>(
                  builder: (_, p, __) {
                    // Garante que o valor selecionado existe na lista atual;
                    // se não existir (p.ex. após limpar filtros), usa null.
                    final valorValido = p.categorias.contains(_categoriaFiltro)
                        ? _categoriaFiltro
                        : '';
                    return SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('cat_${p.categorias.join('|')}'),
                        initialValue: valorValido.isEmpty ? null : valorValido,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('TODAS')),
                          for (final cat in p.categorias)
                            DropdownMenuItem(value: cat, child: Text(cat)),
                        ],
                        onChanged: (v) {
                          setState(() => _categoriaFiltro = v ?? '');
                          _aplicarFiltros();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off, color: scheme.onSurfaceVariant),
                  onPressed: () {
                    _buscaCtrl.clear();
                    _buscaIdCtrl.clear();
                    setState(() {
                      _statusFiltro    = '';
                      _categoriaFiltro = '';
                    });
                    context.read<MaterialProvider>().carregar();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Tabela ──────────────────────────────────────────────────────
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
                            onPressed: () => provider.carregar(),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                            ),
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
                          const Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: AppTheme.textHint,
                          ),
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

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: _TabelaMateriais(
                        materiais:         provider.materiais,
                        onEditar:          _abrirFormMaterial,
                        onDesativar:       _desativar,
                        onReativar:        _reativar,
                        onExcluir:         _excluir,
                        onVerFornecedores: _abrirPrecosFornecedores,
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
// Cabeçalho de seção
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Tabela de materiais
// ─────────────────────────────────────────────────────────────────────────────
class _TabelaMateriais extends StatelessWidget {
  final List<MaterialModel> materiais;
  final void Function(MaterialModel) onEditar;
  final void Function(MaterialModel) onDesativar;
  final void Function(MaterialModel) onReativar;
  final void Function(MaterialModel) onExcluir;
  final void Function(MaterialModel) onVerFornecedores;

  const _TabelaMateriais({
    required this.materiais,
    required this.onEditar,
    required this.onDesativar,
    required this.onReativar,
    required this.onExcluir,
    required this.onVerFornecedores,
  });

  static const _columnWidths = {
    0: FixedColumnWidth(56),   // ID
    1: FlexColumnWidth(2.0),   // Material
    2: FlexColumnWidth(1.0),   // Categoria
    3: FlexColumnWidth(0.9),   // Unid.
    4: FlexColumnWidth(0.8),   // Medida
    5: FlexColumnWidth(0.7),   // Esp.
    6: FlexColumnWidth(0.6),   // Qtd
    7: FlexColumnWidth(0.6),   // Mín
    8: FlexColumnWidth(0.9),   // Valor
    9: FlexColumnWidth(0.9),   // Valor m²
    10: FlexColumnWidth(0.8),  // Status
    11: FlexColumnWidth(1.2),  // Ações
  };

  TableRow get _cabecalho => TableRow(
        decoration: const BoxDecoration(color: AppTheme.surfaceVariant),
        children: [
          _th('ID'),
          _th('Material'),
          _th('Categoria'),
          _th('Unidade'),
          _th('Medida'),
          _th('Espessura'),
          _th('Estoque atual'),
          _th('Estoque mínimo'),
          _th('Valor'),
          _th('Valor m²'),
          _th('Status'),
          _th('Ações'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final confirmados = materiais.where((m) => m.estoqueConfirmado).toList();
    final naoConfirm  = materiais.where((m) => !m.estoqueConfirmado).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Seção: Aguardando confirmação ───────────────────────────────────
        _SectionHeader(
          icon: Icons.pending_outlined,
          label: 'Aguardando confirmação de estoque',
          count: naoConfirm.length,
          color: AppTheme.warning,
        ),
        if (naoConfirm.isEmpty)
          const _EmptySection(message: 'Nenhum material pendente de confirmação.')
        else
          Table(
            border: const TableBorder(
              horizontalInside: BorderSide(color: AppTheme.divider, width: 0.8),
              verticalInside:   BorderSide(color: AppTheme.divider, width: 0.5),
              bottom:           BorderSide(color: AppTheme.divider, width: 0.8),
            ),
            columnWidths: _columnWidths,
            children: [
              _cabecalho,
              for (final m in naoConfirm) _buildRow(context, m),
            ],
          ),

        const SizedBox(height: 24),

        // ── Seção: Estoque confirmado ───────────────────────────────────────
        _SectionHeader(
          icon: Icons.verified_outlined,
          label: 'Estoque confirmado',
          count: confirmados.length,
          color: AppTheme.success,
        ),
        if (confirmados.isEmpty)
          const _EmptySection(message: 'Nenhum material com estoque confirmado.')
        else
          Table(
            border: const TableBorder(
              horizontalInside: BorderSide(color: AppTheme.divider, width: 0.8),
              verticalInside:   BorderSide(color: AppTheme.divider, width: 0.5),
              bottom:           BorderSide(color: AppTheme.divider, width: 0.8),
            ),
            columnWidths: _columnWidths,
            children: [
              _cabecalho,
              for (final m in confirmados) _buildRow(context, m),
            ],
          ),
      ],
    );
  }

  TableRow _buildRow(BuildContext context, MaterialModel m) {
    final inativo = !m.ativo;

    // Linha inteira ofuscada quando inativo
    Widget wrapOpacity(Widget child) =>
        inativo ? Opacity(opacity: 0.45, child: child) : child;

    // Wrapper que abre edição ao clicar com hover laranja
    Widget clickable(Widget child) => _HoverEditCell(
          enabled: !inativo,
          onTap: inativo ? null : () => onEditar(m),
          child: child,
        );

    return TableRow(
      decoration: BoxDecoration(
        color: inativo
            ? AppTheme.surfaceVariant.withValues(alpha: 0.4)
            : AppTheme.surface,
      ),
      children: [
        // ID
        _td(clickable(wrapOpacity(
          Padding(
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
          ),
        ))),
        // Nome
        _td(clickable(
          wrapOpacity(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
          ),
        )),
        _td(clickable(wrapOpacity(_cell(m.categoria ?? '—')))),
        _td(clickable(wrapOpacity(_cell(m.unidade ?? '—')))),
        _td(clickable(wrapOpacity(_cell(m.medida ?? '—')))),
        _td(clickable(wrapOpacity(_cell(m.espessura ?? '—')))),
        _td(clickable(wrapOpacity(_cell(m.quantidade
            .toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2))))),
        _td(clickable(wrapOpacity(_cell(m.estoqueMinimo
            .toStringAsFixed(m.estoqueMinimo % 1 == 0 ? 0 : 2))))),
        // Valor unitário (mediano entre fornecedores — clicável separado, NÃO abre editar)
        _td(wrapOpacity(_ValorMedianoCell(
          valor: m.precoMediano,
          temFornecedores: m.fornecedorMateriais.isNotEmpty,
          onTap: () => onVerFornecedores(m),
        ))),
        // Valor m² (mediano — clicável separado, NÃO abre editar)
        _td(wrapOpacity(_ValorMedianoCell(
          valor: m.precoM2Mediano,
          temFornecedores: m.fornecedorMateriais.isNotEmpty,
          onTap: () => onVerFornecedores(m),
        ))),
        // Status badge
        _td(clickable(wrapOpacity(Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Center(child: _StatusBadge(status: m.status)),
        )))),
        // Ações (não ofuscadas — sempre visíveis para o usuário agir)
        _td(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!inativo) ...[
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: AppTheme.textSecondary,
                  onPressed: () => onEditar(m),
                ),
                IconButton(
                  tooltip: 'Desativar',
                  icon: const Icon(Icons.block, size: 18),
                  color: AppTheme.warning,
                  onPressed: () => onDesativar(m),
                ),
              ],
              if (inativo) ...[
                IconButton(
                  tooltip: 'Reativar material',
                  icon: const Icon(Icons.restore, size: 18),
                  color: AppTheme.success,
                  onPressed: () => onReativar(m),
                ),
                IconButton(
                  tooltip: 'Excluir permanentemente',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppTheme.error,
                  onPressed: () => onExcluir(m),
                ),
              ],
            ],
          ),
        )),
      ],
    );
  }

  static Widget _th(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      );

  static Widget _td(Widget child) => child;

  static Widget _cell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Célula genérica clicável com hover laranja (abre editar)
// ─────────────────────────────────────────────────────────────────────────────
class _HoverEditCell extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback? onTap;

  const _HoverEditCell({
    required this.child,
    required this.enabled,
    this.onTap,
  });

  @override
  State<_HoverEditCell> createState() => _HoverEditCellState();
}

class _HoverEditCellState extends State<_HoverEditCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) { if (widget.enabled) setState(() => _hovered = true); },
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _hovered
              ? const Color(0xFFFF9800).withValues(alpha: 0.10)
              : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Célula clicável que exibe o valor intermediário dos fornecedores.
class _ValorMedianoCell extends StatefulWidget {
  final double? valor;
  final bool temFornecedores;
  final VoidCallback onTap;

  const _ValorMedianoCell({
    required this.valor,
    required this.temFornecedores,
    required this.onTap,
  });

  @override
  State<_ValorMedianoCell> createState() => _ValorMedianoCellState();
}

class _ValorMedianoCellState extends State<_ValorMedianoCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.valor != null && widget.valor! > 0;
    final label = hasValue ? 'R\$ ${widget.valor!.toStringAsFixed(2)}' : '—';
    final canTap = widget.temFornecedores;

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) { if (canTap) setState(() => _hovered = true); },
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: canTap ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFFFF9800).withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _hovered
                      ? const Color(0xFFE65100)
                      : (hasValue ? AppTheme.textPrimary : AppTheme.textHint),
                  fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
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
// Badge de status
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Dialog: preços por fornecedor
// ─────────────────────────────────────────────────────────────────────────────
class _PrecosFornecedoresDialog extends StatelessWidget {
  final MaterialModel material;
  const _PrecosFornecedoresDialog({required this.material});

  /// Calcula os índices dos fornecedores que compõem o valor intermediário.
  /// Ímpar: 1 índice central. Par: 2 índices do meio (a média é exibida no resumo).
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
    final idxsMediano = _indicesMediano(ordenados);

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
                  // ── Resumo do valor intermediário ───────────────────────
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

                  // ── Cabeçalho da lista ───────────────────────────────────
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

                  // ── Linhas dos fornecedores ──────────────────────────────
                  ...List.generate(ordenados.length, (i) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FornecedorPrecoRow(
                          item:        ordenados[i],
                          menorPreco:  i == 0 && ordenados[i].preco > 0,
                          isMediano:   idxsMediano.contains(i),
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
  final bool menorPreco;
  final bool isMediano;
  const _FornecedorPrecoRow({
    required this.item,
    required this.menorPreco,
    this.isMediano = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: isMediano
          ? BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: isMediano ? 6.0 : 0.0),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (menorPreco)
                  const Tooltip(
                    message: 'Menor preço',
                    child: Icon(Icons.star, size: 14, color: AppTheme.warning),
                  ),
                if (isMediano && !menorPreco)
                  const Tooltip(
                    message: 'Valor intermediário (exibido na tabela)',
                    child: Icon(Icons.radio_button_checked, size: 14, color: AppTheme.primary),
                  ),
                if (menorPreco || isMediano) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.fornecedorNome.isEmpty ? '—' : item.fornecedorNome,
                    style: TextStyle(
                      fontWeight: (menorPreco || isMediano) ? FontWeight.w700 : FontWeight.normal,
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              item.preco > 0 ? 'R\$ ${item.preco.toStringAsFixed(2)}' : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isMediano
                    ? AppTheme.primary
                    : menorPreco
                        ? AppTheme.success
                        : AppTheme.textPrimary,
                fontWeight: (menorPreco || isMediano) ? FontWeight.w700 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              item.precoMetroQuadrado > 0
                  ? 'R\$ ${item.precoMetroQuadrado.toStringAsFixed(2)}'
                  : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: isMediano ? AppTheme.primary : AppTheme.textPrimary,
                fontWeight: isMediano ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog: formulário de criação / edição de material
// ─────────────────────────────────────────────────────────────────────────────
class _MaterialFormDialog extends StatefulWidget {
  final MaterialModel? material;
  const _MaterialFormDialog({this.material});

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog; // mensagem de erro exibida DENTRO do dialog

  late final TextEditingController _nome;
  late final TextEditingController _unidade;
  late final TextEditingController _categoria;
  late final TextEditingController _medida;
  late final TextEditingController _espessura;
  late final TextEditingController _quantidade;
  late final TextEditingController _estoqueMinimo;

  bool get _editando => widget.material != null;
  late bool _estoqueConfirmado;

  @override
  void initState() {
    super.initState();
    final m        = widget.material;
    _estoqueConfirmado = m?.estoqueConfirmado ?? false;
    _nome          = TextEditingController(text: m?.nome ?? '');
    _unidade       = TextEditingController(text: m?.unidade ?? '');
    _categoria     = TextEditingController(text: m?.categoria ?? '');
    _medida        = TextEditingController(text: m?.medida ?? '');
    _espessura     = TextEditingController(text: m?.espessura ?? '');
    _quantidade    = TextEditingController(
        text: m != null ? m.quantidade.toString() : '0');
    _estoqueMinimo = TextEditingController(
        text: m != null ? m.estoqueMinimo.toString() : '0');
  }

  @override
  void dispose() {
    for (final c in [
      _nome, _unidade, _categoria, _medida, _espessura,
      _quantidade, _estoqueMinimo,
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
      'unidade':       _unidade.text.trim().isEmpty ? null : _unidade.text.trim(),
      'categoria':     _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
      'medida':        _medida.text.trim().isEmpty ? null : _medida.text.trim(),
      'espessura':     _espessura.text.trim().isEmpty ? null : _espessura.text.trim(),
      'quantidade':    double.tryParse(_quantidade.text) ?? 0,
      'estoqueMinimo': double.tryParse(_estoqueMinimo.text) ?? 0,
      'estoqueConfirmado': _estoqueConfirmado,
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
      // Mostra o erro dentro do próprio dialog — não fecha, não usa SnackBar
      setState(() => _erroDialog = provider.erro ?? 'Erro ao salvar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editando ? 'Editar Material' : 'Novo Material'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Banner de erro ───────────────────────────────────────
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
                // Nome (obrigatório)
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
                // Linha: Categoria + Unidade
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
                // Linha: Medida + Espessura
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
                // Linha: Quantidade + Estoque mínimo
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
                // Estoque confirmado (toggle)
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
              ],
            ),
          ),
        ),
      ),
      actions: [
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