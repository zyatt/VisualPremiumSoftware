import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/produto_model.dart';
import '../models/material_model.dart';
import '../providers/produto_provider.dart';
import '../providers/material_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';
import '../pages/controle_estoque_page.dart' show formatarEspessuraComSufixo;

class ProdutoPage extends StatefulWidget {
  const ProdutoPage({super.key});

  @override
  State<ProdutoPage> createState() => _ProdutoPageState();
}

class _ProdutoPageState extends State<ProdutoPage> {
  final _buscaCtrl = TextEditingController();
  String? _categoriaFiltro;
  bool? _ativoFiltro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<ProdutoProvider>();
      prov.carregar();
      prov.carregarCategorias();
    });
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _aplicarFiltros() {
    context.read<ProdutoProvider>().carregar(
          busca:     _buscaCtrl.text.trim(),
          categoria: _categoriaFiltro,
          ativo:     _ativoFiltro,
        );
  }

  String get _roleUsuario =>
      context.read<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ??
      '';

  bool get _podeEscrever =>
      _roleUsuario == 'ADMIN' || _roleUsuario == 'GERENTE';

  @override
  Widget build(BuildContext context) {
    final prov  = context.watch<ProdutoProvider>();
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [

          _PageHeader(
            podeEscrever: _podeEscrever,
            onNovo: () => _abrirFormulario(context),
            onAtualizar: _aplicarFiltros,
          ),

          _FiltroBar(
            buscaCtrl:       _buscaCtrl,
            categorias:      prov.categorias,
            categoriaFiltro: _categoriaFiltro,
            ativoFiltro:     _ativoFiltro,
            onBuscaChanged:  (_) => _aplicarFiltros(),
            onCategoriaChanged: (v) {
              setState(() => _categoriaFiltro = v);
              _aplicarFiltros();
            },
            onAtivoChanged: (v) {
              setState(() => _ativoFiltro = v);
              _aplicarFiltros();
            },
            onLimpar: () {
              setState(() {
                _buscaCtrl.clear();
                _categoriaFiltro = null;
                _ativoFiltro = null;
              });
              context.read<ProdutoProvider>().carregar();
            },
          ),

          if (prov.erro != null)
            _ErroBanner(mensagem: prov.erro!, onDismiss: prov.limparErro),

          const SizedBox(height: 16),

          Expanded(
            child: prov.carregando
                ? const Center(child: CircularProgressIndicator())
                : prov.produtos.isEmpty
                    ? _EstadoVazio(filtrado: _buscaCtrl.text.isNotEmpty ||
                        _categoriaFiltro != null)
                    : isWide
                        ? _TabelaProdutos(
                            produtos:     prov.produtos,
                            podeEscrever: _podeEscrever,
                            onEditar:     (p) => _abrirFormulario(context, produto: p),
                            onDetalhe:    (p) => _abrirDetalhe(context, p),
                          )
                        : _ListaMobileProdutos(
                            produtos:     prov.produtos,
                            podeEscrever: _podeEscrever,
                            onEditar:     (p) => _abrirFormulario(context, produto: p),
                            onDetalhe:    (p) => _abrirDetalhe(context, p),
                          ),
          ),
        ],
      ),
    );
  }

  void _abrirFormulario(BuildContext context, {ProdutoModel? produto}) {
    showDialog(
      context: context,
      builder: (_) => _ProdutoFormDialog(
        produto: produto,
        onDesativar: produto != null ? (p) => _toggleAtivo(context, p) : null,
        onReativar:  produto != null ? (p) => _toggleAtivo(context, p) : null,
        onExcluir:   produto != null ? (p) => _confirmarExclusao(context, p) : null,
      ),
    );
  }

  void _abrirDetalhe(BuildContext context, ProdutoModel produto) {
    showDialog(
      context: context,
      builder: (_) => _ProdutoDetalheDialog(produto: produto),
    );
  }

  Future<void> _toggleAtivo(BuildContext context, ProdutoModel p) async {
    final prov = context.read<ProdutoProvider>();
    final ok = p.ativo
        ? await prov.desativar(p.id)
        : await prov.reativar(p.id);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prov.erro ?? 'Erro ao alterar status'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _confirmarExclusao(BuildContext context, ProdutoModel p) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text('Excluir produto?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          'O produto "${p.nome}" será excluído permanentemente.\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirma != true || !context.mounted) return;

    final prov = context.read<ProdutoProvider>();
    final ok   = await prov.excluir(p.id);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prov.erro ?? 'Erro ao excluir produto'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}

class _PageHeader extends StatelessWidget {
  final bool podeEscrever;
  final VoidCallback onNovo;
  final VoidCallback onAtualizar;

  const _PageHeader({
    required this.podeEscrever,
    required this.onNovo,
    required this.onAtualizar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Produtos',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                'Fichas técnicas com lista de materiais',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const Spacer(),
          if (podeEscrever) ...[
            Tooltip(
              message: 'Cadastrar novo produto',
              child: FilledButton.icon(
                onPressed: onNovo,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo produto'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              ),
            ),
            const SizedBox(width: 10),
          ],
          IconButton(
            onPressed: onAtualizar,
            icon: Icon(Icons.refresh, size: 18, color: cs.onSurfaceVariant),
            tooltip: 'Atualizar',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              side: BorderSide(color: cs.outlineVariant),
            ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
    );
  }
}

class _FiltroBar extends StatelessWidget {
  final TextEditingController buscaCtrl;
  final List<String> categorias;
  final String? categoriaFiltro;
  final bool? ativoFiltro;
  final ValueChanged<String> onBuscaChanged;
  final ValueChanged<String?> onCategoriaChanged;
  final ValueChanged<bool?> onAtivoChanged;
  final VoidCallback onLimpar;

  const _FiltroBar({
    required this.buscaCtrl,
    required this.categorias,
    required this.categoriaFiltro,
    required this.ativoFiltro,
    required this.onBuscaChanged,
    required this.onCategoriaChanged,
    required this.onAtivoChanged,
    required this.onLimpar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final temFiltro = buscaCtrl.text.isNotEmpty ||
        categoriaFiltro != null ||
        ativoFiltro != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: buscaCtrl,
              onChanged: onBuscaChanged,
              decoration: InputDecoration(
                hintText: 'Nome do produto',
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.outline),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (categorias.isNotEmpty) ...[
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: DropdownButtonFormField<String?>(
                  initialValue: categoriaFiltro,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    isDense: true,
                  ),
                  hint: const Text('Todas'),
                  icon: const Icon(Icons.arrow_drop_down),
                  mouseCursor: SystemMouseCursors.click,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('Todas')),
                    ),
                    ...categorias.map((c) => DropdownMenuItem(
                          value: c,
                          child: MouseRegion(cursor: SystemMouseCursors.click, child: Text(c)),
                        )),
                  ],
                  onChanged: onCategoriaChanged,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: DropdownButtonFormField<bool?>(
                initialValue: ativoFiltro,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                ),
                hint: const Text('Todos'),
                icon: const Icon(Icons.arrow_drop_down),
                mouseCursor: SystemMouseCursors.click,
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('Todos')),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('Ativos')),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('Inativos')),
                  ),
                ],
                onChanged: onAtivoChanged,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(
            tooltip: 'Limpar filtros',
            icon: Icon(Icons.filter_alt_off, color: cs.onSurfaceVariant),
            onPressed: temFiltro ? onLimpar : null,
            style: IconButton.styleFrom(
              side: BorderSide(color: cs.outline),
            ).copyWith(
              mouseCursor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return SystemMouseCursors.basic;
                }
                return SystemMouseCursors.click;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErroBanner extends StatelessWidget {
  final String mensagem;
  final VoidCallback onDismiss;

  const _ErroBanner({required this.mensagem, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(mensagem,
                style: TextStyle(
                    color: AppTheme.error, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 14, color: AppTheme.error),
            tooltip: 'Fechar',
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  final bool filtrado;
  const _EstadoVazio({required this.filtrado});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.category_outlined,
              size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            filtrado ? 'Nenhum produto encontrado' : 'Nenhum produto cadastrado',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant),
          ),
          if (filtrado) ...[
            const SizedBox(height: 6),
            Text(
              'Tente ajustar os filtros de busca',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabelaProdutos extends StatefulWidget {
  final List<ProdutoModel> produtos;
  final bool podeEscrever;
  final ValueChanged<ProdutoModel> onEditar;
  final ValueChanged<ProdutoModel> onDetalhe;

  const _TabelaProdutos({
    required this.produtos,
    required this.podeEscrever,
    required this.onEditar,
    required this.onDetalhe,
  });

  @override
  State<_TabelaProdutos> createState() => _TabelaProdutosState();
}

class _TabelaProdutosState extends State<_TabelaProdutos> {
  int? _hoveredId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(2),
            2: FixedColumnWidth(90),
            3: FlexColumnWidth(3),
            4: FixedColumnWidth(70),
          },
          children: [

            TableRow(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
              ),
              children: const [
                _ThCell('Nome'),
                _ThCell('Categoria'),
                _ThCell('Materiais', align: TextAlign.center),
                _ThCell('Descrição'),
                _ThCell('Status', align: TextAlign.center),
              ],
            ),
            ...widget.produtos.map((p) => _buildRow(context, p)),
          ],
        ),
      ),
    );
  }

  TableRow _buildRow(BuildContext context, ProdutoModel p) {
    final cs      = Theme.of(context).colorScheme;
    final hovered = _hoveredId == p.id;

    final bgColor = hovered
        ? AppTheme.primary.withValues(alpha: 0.07)
        : p.ativo
            ? null
            : cs.surfaceContainerLow.withValues(alpha: 0.4);

    final Color textColorPadrao =
        p.ativo ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.5);
    final Color textColorSecundario =
        p.ativo ? cs.onSurfaceVariant : cs.onSurfaceVariant.withValues(alpha: 0.5);

    void handleTap() {
      widget.podeEscrever ? widget.onEditar(p) : widget.onDetalhe(p);
    }

    Widget wrapCell(Widget child, {Alignment align = Alignment.centerLeft}) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredId = p.id),
        onExit: (_) => setState(() {
          if (_hoveredId == p.id) _hoveredId = null;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: handleTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            alignment: align,
            child: child,
          ),
        ),
      );
    }

    return TableRow(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
            bottom:
                BorderSide(color: cs.outline.withValues(alpha: 0.08))),
      ),
      children: [
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: wrapCell(Text(
            p.nome,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColorPadrao,
              decoration: p.ativo ? null : TextDecoration.lineThrough,
            ),
          )),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: wrapCell(
            p.categoria != null
                ? _Chip(
                    label: p.categoria!,
                    color: p.ativo
                        ? AppTheme.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.6),
                  )
                : Text('—',
                    style: TextStyle(fontSize: 12, color: textColorSecundario)),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: wrapCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${p.materiais.length}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColorPadrao),
              ),
            ),
            align: Alignment.center,
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: wrapCell(
            p.descricao != null && p.descricao!.trim().isNotEmpty
                ? Text(
                    p.descricao!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: textColorSecundario),
                  )
                : Text('—',
                    style: TextStyle(fontSize: 12, color: textColorSecundario)),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: wrapCell(_StatusBadge(ativo: p.ativo), align: Alignment.center),
        ),
      ],
    );
  }
}

class _ThCell extends StatelessWidget {
  final String text;
  final TextAlign align;
  const _ThCell(this.text, {this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text.toUpperCase(),
        textAlign: align,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ListaMobileProdutos extends StatelessWidget {
  final List<ProdutoModel> produtos;
  final bool podeEscrever;
  final ValueChanged<ProdutoModel> onEditar;
  final ValueChanged<ProdutoModel> onDetalhe;

  const _ListaMobileProdutos({
    required this.produtos,
    required this.podeEscrever,
    required this.onEditar,
    required this.onDetalhe,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: produtos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _CardMobileProduto(
        produto:      produtos[i],
        podeEscrever: podeEscrever,
        onEditar:     () => onEditar(produtos[i]),
        onDetalhe:    () => onDetalhe(produtos[i]),
      ),
    );
  }
}

class _CardMobileProduto extends StatelessWidget {
  final ProdutoModel produto;
  final bool podeEscrever;
  final VoidCallback onEditar;
  final VoidCallback onDetalhe;

  const _CardMobileProduto({
    required this.produto,
    required this.podeEscrever,
    required this.onEditar,
    required this.onDetalhe,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final p     = produto;
    final custo = p.custoEstimado;

    return InkWell(
      onTap: onDetalhe,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: p.ativo
                ? cs.outline.withValues(alpha: 0.15)
                : cs.outline.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [

            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.ativo
                    ? AppTheme.primary.withValues(alpha: 0.1)
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.category_rounded,
                size: 18,
                color: p.ativo ? AppTheme.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nome,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.ativo ? cs.onSurface : cs.onSurfaceVariant,
                      decoration:
                          p.ativo ? null : TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (p.categoria != null)
                        _Chip(label: p.categoria!, color: AppTheme.primary, small: true),
                      if (p.categoria != null) const SizedBox(width: 6),
                      Text(
                        '${p.materiais.length} mat.',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (custo != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _fmtBrl(custo),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            _StatusBadge(ativo: p.ativo),
            if (podeEscrever) ...[
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.edit_rounded,
                tooltip: 'Editar',
                color: AppTheme.primary,
                onTap: onEditar,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProdutoDetalheDialog extends StatelessWidget {
  final ProdutoModel produto;
  const _ProdutoDetalheDialog({required this.produto});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p  = produto;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              _DialogHeader(
                titulo: p.nome,
                subtitulo: p.categoria,
                icon: Icons.category_rounded,
                onClose: () => Navigator.pop(context),
                trailing: _StatusBadge(ativo: p.ativo),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p.descricao != null && p.descricao!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            p.descricao!,
                            style: TextStyle(
                                fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      _SectionLabel('Lista de materiais (${p.materiais.length})'),
                      const SizedBox(height: 8),

                      if (p.materiais.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Nenhum material vinculado',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        ...p.materiais.map((pm) => _MaterialItemTile(pm: pm)),

                      if (p.custoEstimado != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.attach_money_rounded,
                                  size: 16, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Custo estimado total',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _fmtBrl(p.custoEstimado!),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    onPressed: () => Navigator.pop(context),
                    child: Text('Fechar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialItemTile extends StatelessWidget {
  final ProdutoMaterialModel pm;
  const _MaterialItemTile({required this.pm});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final mat = pm.material;
    final ref = mat.precoRef;
    final subtotal = ref != null ? pm.quantidade * ref : null;

    final partes = <String>[];
    if (mat.categoria != null && mat.categoria!.isNotEmpty) partes.add(mat.categoria!);
    if (mat.medida    != null && mat.medida!.isNotEmpty) {
      partes.add(mat.medida!);
    } else {
      final medidaCalc = _medidaFromDimensoes(mat.comprimento, mat.largura);
      if (medidaCalc != null) partes.add(medidaCalc);
    }
    if (mat.espessura != null && mat.espessura!.isNotEmpty) partes.add(mat.espessura!);
    final sub = partes.join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                size: 15, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mat.nome,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                if (pm.observacao != null && pm.observacao!.isNotEmpty)
                  Text(
                    pm.observacao!,
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_fmtQtd(pm.quantidade)} ${mat.unidade ?? ''}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface),
              ),
              if (subtotal != null)
                Text(
                  _fmtBrl(subtotal),
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600),
                )
              else
                Text(
                  ref != null ? '${_fmtBrl(ref)}/un' : 'sem preço',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProdutoFormDialog extends StatefulWidget {
  final ProdutoModel? produto;
  final ValueChanged<ProdutoModel>? onDesativar;
  final ValueChanged<ProdutoModel>? onReativar;
  final ValueChanged<ProdutoModel>? onExcluir;

  const _ProdutoFormDialog({
    this.produto,
    this.onDesativar,
    this.onReativar,
    this.onExcluir,
  });

  @override
  State<_ProdutoFormDialog> createState() => _ProdutoFormDialogState();
}

class _ProdutoFormDialogState extends State<_ProdutoFormDialog> {
  final _formKey     = GlobalKey<FormState>();
  final _nomeCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _catCtrl     = TextEditingController();
  bool  _salvando    = false;

  final List<_MaterialEntrada> _materiais = [];

  bool get _editando => widget.produto != null;

  @override
  void initState() {
    super.initState();
    final p = widget.produto;
    if (p != null) {
      _nomeCtrl.text = p.nome;
      _descCtrl.text = p.descricao ?? '';
      _catCtrl.text  = p.categoria ?? '';
      _materiais.addAll(
        p.materiais.map((pm) => _MaterialEntrada(
          materialId:    pm.materialId,
          nomeExibicao:  pm.material.nome,
          observacao:    pm.observacao ?? '',
          medida:        pm.material.medida,
          espessura:     pm.material.espessura,
          identificador: pm.material.identificador,
          comprimento:   pm.material.comprimento,
          largura:       pm.material.largura,
        )),
      );
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    _catCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);

    final dados = <String, dynamic>{
      'nome':      _nomeCtrl.text.trim(),
      'descricao': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'categoria': _catCtrl.text.trim().isEmpty  ? null : _catCtrl.text.trim(),
      'materiais': _materiais
          .map((m) => {
                'materialId': m.materialId,
                'quantidade': 1,
                'observacao': m.observacao.isEmpty ? null : m.observacao,
              })
          .toList(),
    };

    final prov = context.read<ProdutoProvider>();
    final ok = _editando
        ? await prov.atualizar(widget.produto!.id, dados)
        : await prov.criar(dados);

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editando ? 'Produto atualizado!' : 'Produto cadastrado!',
          ),
          backgroundColor: const Color(0xFF15803D),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prov.erro ?? 'Erro ao salvar'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _adicionarMaterial(int id, String nome,
      {String? medida, String? espessura, String? identificador,
      double? comprimento, double? largura}) {

    if (_materiais.any((m) => m.materialId == id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material já adicionado')),
      );
      return;
    }
    setState(() {
      _materiais.add(_MaterialEntrada(
        materialId:    id,
        nomeExibicao:  nome,
        observacao:    '',
        medida:        medida,
        espessura:     espessura,
        identificador: identificador,
        comprimento:   comprimento,
        largura:       largura,
      ));
    });
  }

  void _removerMaterial(int index) {
    setState(() => _materiais.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(
                titulo:   _editando ? 'Editar produto' : 'Novo produto',
                icon:     _editando ? Icons.edit_rounded : Icons.add_rounded,
                onClose:  () => Navigator.pop(context),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        _Campo(
                          label: 'Nome *',
                          ctrl:  _nomeCtrl,
                          hint:  'Nome do Produto',
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Nome é obrigatório'
                                  : null,
                        ),
                        const SizedBox(height: 12),

                        _Campo(
                          label: 'Categoria',
                          ctrl:  _catCtrl,
                          hint:  'Categoria do Produto',
                        ),
                        const SizedBox(height: 12),

                        _Campo(
                          label:  'Descrição',
                          ctrl:   _descCtrl,
                          hint:   'Observações sobre o produto',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            _SectionLabel('Materiais'),
                            const Spacer(),
                            _BuscaMaterialBtn(
                              onSelecionado: _adicionarMaterial,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (_materiais.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 20),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.2),
                                  style: BorderStyle.solid),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Nenhum material adicionado',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                          )
                        else
                          ...List.generate(_materiais.length, (i) {
                            final m = _materiais[i];
                            return _MaterialFormRow(
                              entrada:   m,
                              onRemover: () => _removerMaterial(i),
                              onChanged: (obs) {
                                setState(() {
                                  _materiais[i] = _MaterialEntrada(
                                    materialId:   m.materialId,
                                    nomeExibicao: m.nomeExibicao,
                                    observacao:   obs,
                                  );
                                });
                              },
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ),

              const Divider(height: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    if (_editando) ...[
                      if (widget.produto!.ativo && widget.onDesativar != null)
                        TextButton.icon(
                          onPressed: _salvando
                              ? null
                              : () {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                  widget.onDesativar!(widget.produto!);
                                },
                          icon: const Icon(Icons.visibility_off_rounded,
                              size: 16),
                          label: Text('Desativar'),
                          style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFD97706))
                              .copyWith(mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click)),
                        ),
                      if (!widget.produto!.ativo && widget.onReativar != null)
                        TextButton.icon(
                          onPressed: _salvando
                              ? null
                              : () {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                  widget.onReativar!(widget.produto!);
                                },
                          icon: const Icon(Icons.visibility_rounded, size: 16),
                          label: Text('Reativar'),
                          style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF15803D))
                              .copyWith(mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click)),
                        ),
                      if (!widget.produto!.ativo && widget.onExcluir != null)
                        TextButton.icon(
                          onPressed: _salvando
                              ? null
                              : () {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                  widget.onExcluir!(widget.produto!);
                                },
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 16),
                          label: Text('Excluir'),
                          style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.error)
                              .copyWith(mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click)),
                        ),
                    ],
                    const Spacer(),
                    Tooltip(
                      message: 'Cancelar sem salvar',
                      child: TextButton(
                        style: TextButton.styleFrom().copyWith(
                            mouseCursor: WidgetStateProperty.all(
                                SystemMouseCursors.click)),
                        onPressed:
                            _salvando ? null : () => Navigator.pop(context),
                        child: Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _editando ? 'Salvar alterações' : 'Cadastrar produto',
                      child: FilledButton.icon(
                        onPressed: _salvando ? null : _salvar,
                        icon: _salvando
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.save_rounded, size: 15),
                        label: Text(
                          _editando ? 'Salvar alterações' : 'Cadastrar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ).copyWith(mouseCursor: WidgetStateProperty.all(
                            SystemMouseCursors.click)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialEntrada {
  final int materialId;
  final String nomeExibicao;
  final String observacao;
  final String? medida;
  final String? espessura;
  final String? identificador;
  final double? comprimento;
  final double? largura;

  const _MaterialEntrada({
    required this.materialId,
    required this.nomeExibicao,
    required this.observacao,
    this.medida,
    this.espessura,
    this.identificador,
    this.comprimento,
    this.largura,
  });
}

class _MaterialFormRow extends StatefulWidget {
  final _MaterialEntrada entrada;
  final VoidCallback onRemover;
  final void Function(String obs) onChanged;

  const _MaterialFormRow({
    required this.entrada,
    required this.onRemover,
    required this.onChanged,
  });

  @override
  State<_MaterialFormRow> createState() => _MaterialFormRowState();
}

class _MaterialFormRowState extends State<_MaterialFormRow> {
  late final TextEditingController _obsCtrl;

  @override
  void initState() {
    super.initState();
    _obsCtrl = TextEditingController(text: widget.entrada.observacao);
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(_obsCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final detalhes = [
      if (widget.entrada.identificador != null &&
          widget.entrada.identificador!.trim().isNotEmpty)
        widget.entrada.identificador!.trim(),
      if (widget.entrada.medida != null && widget.entrada.medida!.trim().isNotEmpty)
        widget.entrada.medida!.trim()
      else if (_medidaFromDimensoes(widget.entrada.comprimento, widget.entrada.largura) != null)
        _medidaFromDimensoes(widget.entrada.comprimento, widget.entrada.largura)!,
      if (formatarEspessuraComSufixo(widget.entrada.espessura) != null)
        formatarEspessuraComSufixo(widget.entrada.espessura)!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [

          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.entrada.nomeExibicao,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                if (detalhes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detalhes,
                    style: TextStyle(
                        fontSize: 10.5, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _obsCtrl,
                onChanged: (_) => _notify(),
                style: TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 7),
                  hintText: 'Observação',
                  hintStyle: TextStyle(fontSize: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: cs.outline.withValues(alpha: 0.4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: cs.surface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                size: 16, color: AppTheme.error),
            tooltip: 'Remover',
            onPressed: widget.onRemover,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
    );
  }
}

class _BuscaMaterialBtn extends StatelessWidget {
  final void Function(int id, String nome,
      {String? medida, String? espessura, String? identificador,
      double? comprimento, double? largura}) onSelecionado;
  const _BuscaMaterialBtn({required this.onSelecionado});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Adicionar material ao produto',
      child: OutlinedButton.icon(
        onPressed: () => _abrirBusca(context),
        icon: const Icon(Icons.add_rounded, size: 14),
        label: Text('Adicionar material',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
      ),
    );
  }

  void _abrirBusca(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _BuscaMaterialDialog(
        onSelecionado: (id, nome,
            {medida, espessura, identificador, comprimento, largura}) {
          Navigator.pop(ctx);
          onSelecionado(id, nome,
              medida: medida,
              espessura: espessura,
              identificador: identificador,
              comprimento: comprimento,
              largura: largura);
        },
      ),
    );
  }
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
    final semVirgula = newValue.text.replaceAll(',', '');
    final texto = _removerAcentos(semVirgula).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _MedidaEspessuraFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(',', '.');
    texto = _UpperCaseFormatter._removerAcentos(texto).toLowerCase();
    texto = texto.replaceAllMapped(RegExp(r'[\d.]+'), (m) {
      final partes = m.group(0)!.split('.');
      if (partes.length > 2) {
        return '${partes[0]}.${partes.sublist(1).join('')}';
      }
      return m.group(0)!;
    });
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _EspessuraFormatter extends TextInputFormatter {
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

class _BuscaMaterialDialog extends StatefulWidget {
  final void Function(int id, String nome,
      {String? medida, String? espessura, String? identificador,
      double? comprimento, double? largura}) onSelecionado;
  const _BuscaMaterialDialog({required this.onSelecionado});

  @override
  State<_BuscaMaterialDialog> createState() => _BuscaMaterialDialogState();
}

class _BuscaMaterialDialogState extends State<_BuscaMaterialDialog> {
  final _buscaCtrl        = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _comprimentoCtrl   = TextEditingController();
  final _larguraCtrl       = TextEditingController();
  final _espessuraCtrl     = TextEditingController();

  Timer? _debounceTimer;
  bool _carregando = false;
  List<MaterialModel> _resultados = [];

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _comprimentoCtrl.dispose();
    _larguraCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() => _carregando = true);
    final prov = context.read<MaterialProvider>();
    await prov.carregar(
      busca:         _buscaCtrl.text.trim(),
      identificador: _identificadorCtrl.text.trim(),
      medida:        _medidaCtrl.text.trim(),
      comprimento:   _comprimentoCtrl.text.trim(),
      largura:       _larguraCtrl.text.trim(),
      espessura:     _espessuraCtrl.text.trim(),
      ativo:         true,
    );
    if (mounted) {
      setState(() {
        _resultados = prov.materiais;
        _carregando = false;
      });
    }
  }

  void _agendarBusca() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), _buscar);
  }

  bool get _temFiltro =>
      _buscaCtrl.text.isNotEmpty ||
      _identificadorCtrl.text.isNotEmpty ||
      _medidaCtrl.text.isNotEmpty ||
      _comprimentoCtrl.text.isNotEmpty ||
      _larguraCtrl.text.isNotEmpty ||
      _espessuraCtrl.text.isNotEmpty;

  void _limparFiltros() {
    _buscaCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _comprimentoCtrl.clear();
    _larguraCtrl.clear();
    _espessuraCtrl.clear();
    _buscar();
  }

  InputDecoration _decor(BuildContext context, {
    required String hint,
    required IconData icon,
    String? sufixo,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      suffixText: sufixo,
      prefixIcon: Icon(icon, size: 18, color: cs.outline),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Selecionar Material',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ],
              ),
            ),
            const Divider(height: 0),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _buscaCtrl,
                    autofocus: true,
                    inputFormatters: [_UpperCaseFormatter()],
                    style: TextStyle(fontSize: 13),
                    decoration: _decor(context,
                        hint: 'Nome do material',
                        icon: Icons.search_rounded),
                    onChanged: (_) => _agendarBusca(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _identificadorCtrl,
                          inputFormatters: [_UpperCaseFormatter()],
                          style: TextStyle(fontSize: 13),
                          decoration: _decor(context,
                              hint: 'Identificador',
                              icon: Icons.qr_code_rounded),
                          onChanged: (_) => _agendarBusca(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _medidaCtrl,
                          inputFormatters: [_MedidaEspessuraFormatter()],
                          style: TextStyle(fontSize: 13),
                          decoration: _decor(context,
                              hint: 'Medida', icon: Icons.straighten_rounded),
                          onChanged: (_) => _agendarBusca(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Limpar filtros',
                        icon: Icon(Icons.filter_alt_off, color: cs.onSurfaceVariant),
                        onPressed: _temFiltro ? _limparFiltros : null,
                        style: IconButton.styleFrom(
                          side: BorderSide(color: cs.outline),
                        ).copyWith(
                          mouseCursor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.disabled)) {
                              return SystemMouseCursors.basic;
                            }
                            return SystemMouseCursors.click;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _comprimentoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [_EspessuraFormatter()],
                          style: TextStyle(fontSize: 13),
                          decoration: _decor(context,
                              hint: 'Comprimento',
                              icon: Icons.height_rounded,
                              sufixo: 'm'),
                          onChanged: (_) => _agendarBusca(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _larguraCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [_EspessuraFormatter()],
                          style: TextStyle(fontSize: 13),
                          decoration: _decor(context,
                              hint: 'Largura',
                              icon: Icons.width_normal_rounded,
                              sufixo: 'm'),
                          onChanged: (_) => _agendarBusca(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _espessuraCtrl,
                          inputFormatters: [_EspessuraFormatter()],
                          style: TextStyle(fontSize: 13),
                          decoration: _decor(context,
                              hint: 'Espessura',
                              icon: Icons.layers_rounded,
                              sufixo: 'mm'),
                          onChanged: (_) => _agendarBusca(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 0),

            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _resultados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 40, color: cs.outline),
                              const SizedBox(height: 10),
                              Text('Nenhum material encontrado',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemCount: _resultados.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final m = _resultados[i];
                            final identificador =
                                (m.identificador != null &&
                                        m.identificador!.trim().isNotEmpty)
                                    ? m.identificador!.trim()
                                    : null;
                            final detalhes = [
                              if (m.medida != null && m.medida!.trim().isNotEmpty)
                                m.medida!.trim()
                              else if (_medidaFromDimensoes(m.comprimento, m.largura) != null)
                                _medidaFromDimensoes(m.comprimento, m.largura)!,
                              if (formatarEspessuraComSufixo(m.espessura) != null)
                                formatarEspessuraComSufixo(m.espessura)!,
                            ].join(' · ');

                            return Material(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                mouseCursor: SystemMouseCursors.click,
                                onTap: () => widget.onSelecionado(
                                    m.id, m.nome,
                                    medida: m.medida,
                                    espessura: m.espessura,
                                    identificador: m.identificador,
                                    comprimento: m.comprimento,
                                    largura: m.largura),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: cs.outlineVariant),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                            Icons.inventory_2_rounded,
                                            size: 16,
                                            color: AppTheme.primary),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: cs.onSurface),
                                            children: [
                                              if (identificador != null)
                                                TextSpan(
                                                    text: '$identificador · '),
                                              TextSpan(text: m.nome),
                                              if (detalhes.isNotEmpty)
                                                TextSpan(
                                                  text: ' · $detalhes',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      color: cs
                                                          .onSurfaceVariant),
                                                ),
                                            ],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(Icons.chevron_right_rounded,
                                          size: 18, color: cs.outline),
                                    ],
                                  ),
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

class _DialogHeader extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final IconData icon;
  final VoidCallback onClose;
  final Widget? trailing;

  const _DialogHeader({
    required this.titulo,
    this.subtitulo,
    required this.icon,
    required this.onClose,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitulo != null && subtitulo!.isNotEmpty)
                  Text(
                    subtitulo!,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: Icon(Icons.close_rounded,
                size: 20, color: cs.onSurfaceVariant),
            tooltip: 'Fechar',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? hint;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Campo({
    required this.label,
    required this.ctrl,
    this.hint,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool ativo;
  const _StatusBadge({required this.ativo});

  @override
  Widget build(BuildContext context) {
    final cor = ativo ? const Color(0xFF15803D) : const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        ativo ? 'Ativo' : 'Inativo',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool small;

  const _Chip({required this.label, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 5 : 7, vertical: small ? 1 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

String _fmtBrl(double v) {
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  final parts = s.split(',');
  final intPart = parts[0];
  final dec = parts[1];
  final buf = StringBuffer();
  int cnt = 0;
  for (int i = intPart.length - 1; i >= 0; i--) {
    if (cnt > 0 && cnt % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
    cnt++;
  }
  return 'R\$ ${buf.toString().split('').reversed.join('')},$dec';
}

String _fmtQtd(double v) =>
    v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

String? _medidaFromDimensoes(double? comprimento, double? largura) {
  if (comprimento == null || largura == null) return null;
  if (comprimento <= 0 || largura <= 0) return null;
  return '${_fmtQtd(comprimento)}x${_fmtQtd(largura)}m';
}