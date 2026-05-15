import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/material_model.dart';
import '../providers/material_provider.dart';
import '../theme/app_theme.dart';

/// Formata qualquer entrada de texto para maiúsculas em tempo real.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  final _buscaCtrl = TextEditingController();
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
    super.dispose();
  }

  void _aplicarFiltros() {
    context.read<MaterialProvider>().carregar(
          busca:     _buscaCtrl.text,
          categoria: _categoriaFiltro,
          status:    _statusFiltro,
        );
  }

  void _onBuscaChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), _aplicarFiltros);
  }

  void _abrirFormMaterial([MaterialModel? material]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MaterialFormDialog(material: material),
    ).then((salvou) { if (salvou == true) _aplicarFiltros(); });
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
                      DropdownMenuItem(value: '',        child: Text('Todos')),
                      DropdownMenuItem(value: 'OK',      child: Text('OK')),
                      DropdownMenuItem(value: 'LIMITE',  child: Text('Limite')),
                      DropdownMenuItem(value: 'CRITICO', child: Text('Crítico')),
                      DropdownMenuItem(value: 'INATIVO', child: Text('Inativo')),
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
                  builder: (_, p, __) => SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _categoriaFiltro.isEmpty ? null : _categoriaFiltro,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Todas')),
                        for (final cat in p.categorias)
                          DropdownMenuItem(value: cat, child: Text(cat)),
                      ],
                      onChanged: (v) {
                        setState(() => _categoriaFiltro = v ?? '');
                        _aplicarFiltros();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off, color: scheme.onSurfaceVariant),
                  onPressed: () {
                    _buscaCtrl.clear();
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

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.0), // Nome
        1: FlexColumnWidth(1.0), // Categoria
        2: FlexColumnWidth(0.9), // Unid.
        3: FlexColumnWidth(0.8), // Medida
        4: FlexColumnWidth(0.7), // Espessura
        5: FlexColumnWidth(0.6), // Qtd
        6: FlexColumnWidth(0.6), // Mín
        7: FlexColumnWidth(0.9), // Valor
        8: FlexColumnWidth(0.9), // Valor m²
        9: FlexColumnWidth(0.8), // Status
        10: FlexColumnWidth(1.2), // Ações
      },
      children: [
        // Cabeçalho
        TableRow(
          decoration: const BoxDecoration(color: AppTheme.surfaceVariant),
          children: [
            _th('Material'),
            _th('Categoria'),
            _th('Unid.'),
            _th('Medida'),
            _th('Esp.'),
            _th('Qtd'),
            _th('Mín'),
            _th('Valor'),
            _th('Valor m²'),
            _th('Status'),
            _th('Ações'),
          ],
        ),
        // Linhas
        for (final m in materiais) _buildRow(context, m),
      ],
    );
  }

  TableRow _buildRow(BuildContext context, MaterialModel m) {
    final inativo = !m.ativo;

    // Linha inteira ofuscada quando inativo
    Widget wrapOpacity(Widget child) =>
        inativo ? Opacity(opacity: 0.45, child: child) : child;

    return TableRow(
      decoration: BoxDecoration(
        color: inativo
            ? AppTheme.surfaceVariant.withValues(alpha: 0.4)
            : AppTheme.surface,
        border: const Border(
          bottom: BorderSide(color: AppTheme.divider, width: 0.8),
        ),
      ),
      children: [
        // Nome
        _td(
          wrapOpacity(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    m.nome,
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
          ),
          ),
        ),
        _td(wrapOpacity(_cell(m.categoria ?? '—'))),
        _td(wrapOpacity(_cell(m.unidade ?? '—'))),
        _td(wrapOpacity(_cell(m.medida ?? '—'))),
        _td(wrapOpacity(_cell(m.espessura ?? '—'))),
        _td(wrapOpacity(_cell(m.quantidade
            .toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2)))),
        _td(wrapOpacity(_cell(m.estoqueMinimo
            .toStringAsFixed(m.estoqueMinimo % 1 == 0 ? 0 : 2)))),
        // Valor unitário
        _td(wrapOpacity(_cell(
          m.valor != null ? 'R\$ ${m.valor!.toStringAsFixed(2)}' : '—',
        ))),
        // Valor m²
        _td(wrapOpacity(_cell(
          m.valorMetroQuadrado != null
              ? 'R\$ ${m.valorMetroQuadrado!.toStringAsFixed(2)}'
              : '—',
        ))),
        // Status badge
        _td(wrapOpacity(Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: _StatusBadge(status: m.status),
        ))),
        // Ações (não ofuscadas — sempre visíveis para o usuário agir)
        _td(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      );

  static Widget _td(Widget child) => child;

  static Widget _cell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
        ),
      );
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
      'LIMITE'  => ('Limite',  AppTheme.statusBaixo),
      'CRITICO' => ('Crítico', AppTheme.statusCritico),
      'INATIVO' => ('Inativo', AppTheme.textHint),
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

  @override
  Widget build(BuildContext context) {
    final lista     = material.fornecedorMateriais;
    final ordenados = [...lista]..sort((a, b) => a.preco.compareTo(b.preco));

    return AlertDialog(
      title: Text('Preços — ${material.nome}'),
      content: SizedBox(
        width: 480,
        child: lista.isEmpty
            ? const Text('Nenhum fornecedor vinculado a este material.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cabeçalho
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
                        width: 110,
                        child: Text(
                          'Valor',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          'Valor m²',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  ...List.generate(ordenados.length, (i) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FornecedorPrecoRow(
                          item:       ordenados[i],
                          menorPreco: i == 0,
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
  const _FornecedorPrecoRow({required this.item, required this.menorPreco});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
                if (menorPreco) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.fornecedorNome.isEmpty ? '—' : item.fornecedorNome,
                    style: TextStyle(
                      fontWeight:
                          menorPreco ? FontWeight.w700 : FontWeight.normal,
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              'R\$ ${item.preco.toStringAsFixed(2)}',
              style: TextStyle(
                color:      menorPreco ? AppTheme.success : AppTheme.textPrimary,
                fontWeight: menorPreco ? FontWeight.w700  : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              item.precoMetroQuadrado > 0
                  ? 'R\$ ${item.precoMetroQuadrado.toStringAsFixed(2)}'
                  : '—',
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
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
  late final TextEditingController _valor;
  late final TextEditingController _valorM2;

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
    _valor  = TextEditingController(
        text: m?.valor != null ? m!.valor.toString() : '');
    _valorM2 = TextEditingController(
        text: m?.valorMetroQuadrado != null
            ? m!.valorMetroQuadrado.toString()
            : '');
  }

  @override
  void dispose() {
    for (final c in [
      _nome, _unidade, _categoria, _medida, _espessura,
      _quantidade, _estoqueMinimo, _valor, _valorM2,
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
      if (_valor.text.isNotEmpty) 'valor': double.tryParse(_valor.text),
      if (_valorM2.text.isNotEmpty)
        'valorMetroQuadrado': double.tryParse(_valorM2.text),
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
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          double.tryParse(v ?? '') == null
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
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          double.tryParse(v ?? '') == null
                              ? 'Número inválido'
                              : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _valor,
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$)',
                        prefixText: 'R\$ ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _valorM2,
                      decoration: const InputDecoration(
                        labelText: 'Valor m² (R\$)',
                        prefixText: 'R\$ ',
                      ),
                      keyboardType: TextInputType.number,
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