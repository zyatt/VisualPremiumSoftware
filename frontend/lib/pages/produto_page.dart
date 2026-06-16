import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/produto_model.dart';
import '../models/material_model.dart';
import '../providers/produto_provider.dart';
import '../providers/material_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

// ─── Página principal ────────────────────────────────────────────────────────

class ProdutoPage extends StatefulWidget {
  const ProdutoPage({super.key});

  @override
  State<ProdutoPage> createState() => _ProdutoPageState();
}

class _ProdutoPageState extends State<ProdutoPage> {
  final _buscaCtrl = TextEditingController();
  String? _categoriaFiltro;
  bool? _ativoFiltro; // null = todos

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
    final cs    = Theme.of(context).colorScheme;
    final prov  = context.watch<ProdutoProvider>();
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Cabeçalho ────────────────────────────────────────────────────
          _PageHeader(
            podeEscrever: _podeEscrever,
            onNovo: () => _abrirFormulario(context),
          ),

          // ── Barra de filtros ─────────────────────────────────────────────
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

          // ── Erro ──────────────────────────────────────────────────────────
          if (prov.erro != null)
            _ErroBanner(mensagem: prov.erro!, onDismiss: prov.limparErro),

          // ── Lista ─────────────────────────────────────────────────────────
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
                            onToggleAtivo: (p) => _toggleAtivo(context, p),
                            onExcluir:    (p) => _confirmarExclusao(context, p),
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
      barrierDismissible: false,
      builder: (_) => _ProdutoFormDialog(produto: produto),
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
            style: GoogleFonts.raleway(fontWeight: FontWeight.w700)),
        content: Text(
          'O produto "${p.nome}" será excluído permanentemente.\n'
          'Esta ação não pode ser desfeita.',
          style: GoogleFonts.nunito(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: GoogleFonts.nunito()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Excluir', style: GoogleFonts.nunito()),
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

// ─── Cabeçalho ───────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final bool podeEscrever;
  final VoidCallback onNovo;

  const _PageHeader({required this.podeEscrever, required this.onNovo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.category_rounded,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produtos',
                  style: GoogleFonts.raleway(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Fichas técnicas com lista de materiais',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (podeEscrever)
            FilledButton.icon(
              onPressed: onNovo,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('Novo produto', style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Barra de filtros ─────────────────────────────────────────────────────────

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border:
            Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.1))),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Busca
          SizedBox(
            width: 220,
            height: 36,
            child: TextField(
              controller: buscaCtrl,
              onChanged: onBuscaChanged,
              style: GoogleFonts.nunito(fontSize: 13, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Buscar por nome…',
                hintStyle: GoogleFonts.nunito(
                    fontSize: 13, color: cs.onSurfaceVariant),
                prefixIcon:
                    Icon(Icons.search_rounded, size: 16, color: cs.onSurfaceVariant),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: cs.surface,
              ),
            ),
          ),

          // Categoria
          if (categorias.isNotEmpty)
            _FiltroDropdown<String?>(
              value: categoriaFiltro,
              hint: 'Categoria',
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                ...categorias.map((c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: onCategoriaChanged,
            ),

          // Status
          _FiltroDropdown<bool?>(
            value: ativoFiltro,
            hint: 'Status',
            items: const [
              DropdownMenuItem(value: null,  child: Text('Todos')),
              DropdownMenuItem(value: true,  child: Text('Ativos')),
              DropdownMenuItem(value: false, child: Text('Inativos')),
            ],
            onChanged: onAtivoChanged,
          ),

          // Limpar
          if (temFiltro)
            TextButton.icon(
              onPressed: onLimpar,
              icon: const Icon(Icons.clear_rounded, size: 14),
              label:
                  Text('Limpar', style: GoogleFonts.nunito(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
        ],
      ),
    );
  }
}

class _FiltroDropdown<T> extends StatelessWidget {
  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FiltroDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint,
              style: GoogleFonts.nunito(
                  fontSize: 12, color: cs.onSurfaceVariant)),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item.value,
                    child: DefaultTextStyle(
                      style: GoogleFonts.nunito(
                          fontSize: 12, color: cs.onSurface),
                      child: item.child,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
          isDense: true,
          style: GoogleFonts.nunito(fontSize: 12, color: cs.onSurface),
          dropdownColor: cs.surface,
          icon: Icon(Icons.expand_more_rounded,
              size: 16, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ─── Banner de erro ───────────────────────────────────────────────────────────

class _ErroBanner extends StatelessWidget {
  final String mensagem;
  final VoidCallback onDismiss;

  const _ErroBanner({required this.mensagem, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
                style: GoogleFonts.nunito(
                    color: AppTheme.error, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 14, color: AppTheme.error),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─── Estado vazio ─────────────────────────────────────────────────────────────

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
            style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant),
          ),
          if (filtrado) ...[
            const SizedBox(height: 6),
            Text(
              'Tente ajustar os filtros de busca',
              style: GoogleFonts.nunito(
                  fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Tabela (wide) ────────────────────────────────────────────────────────────

class _TabelaProdutos extends StatelessWidget {
  final List<ProdutoModel> produtos;
  final bool podeEscrever;
  final ValueChanged<ProdutoModel> onEditar;
  final ValueChanged<ProdutoModel> onToggleAtivo;
  final ValueChanged<ProdutoModel> onExcluir;
  final ValueChanged<ProdutoModel> onDetalhe;

  const _TabelaProdutos({
    required this.produtos,
    required this.podeEscrever,
    required this.onEditar,
    required this.onToggleAtivo,
    required this.onExcluir,
    required this.onDetalhe,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(50),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(2),
            3: FixedColumnWidth(90),
            4: FlexColumnWidth(2),
            5: FixedColumnWidth(70),
            6: FixedColumnWidth(120),
          },
          children: [
            // Cabeçalho
            TableRow(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
              ),
              children: [
                _ThCell('ID'),
                _ThCell('Nome'),
                _ThCell('Categoria'),
                _ThCell('Materiais', align: TextAlign.center),
                _ThCell('Custo estimado'),
                _ThCell('Status', align: TextAlign.center),
                _ThCell('Ações', align: TextAlign.center),
              ],
            ),
            ...produtos.map((p) => _buildRow(context, p)),
          ],
        ),
      ),
    );
  }

  TableRow _buildRow(BuildContext context, ProdutoModel p) {
    final cs   = Theme.of(context).colorScheme;
    final custo = p.custoEstimado;

    return TableRow(
      decoration: BoxDecoration(
        color: p.ativo ? null : cs.surfaceContainerLow.withValues(alpha: 0.5),
        border: Border(
            bottom:
                BorderSide(color: cs.outline.withValues(alpha: 0.08))),
      ),
      children: [
        _TdCell(
          child: Text(
            '#${p.id}',
            style: GoogleFonts.nunito(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600),
          ),
        ),
        _TdCell(
          child: InkWell(
            onTap: () => onDetalhe(p),
            borderRadius: BorderRadius.circular(4),
            child: Text(
              p.nome,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: p.ativo ? cs.onSurface : cs.onSurfaceVariant,
                decoration: p.ativo ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ),
        _TdCell(
          child: p.categoria != null
              ? _Chip(
                  label: p.categoria!,
                  color: AppTheme.primary,
                )
              : Text('—',
                  style: GoogleFonts.nunito(
                      fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        _TdCell(
          align: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${p.materiais.length}',
              style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
          ),
        ),
        _TdCell(
          child: custo != null
              ? Text(
                  _fmtBrl(custo),
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                )
              : Text('—',
                  style: GoogleFonts.nunito(
                      fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        _TdCell(
          align: Alignment.center,
          child: _StatusBadge(ativo: p.ativo),
        ),
        _TdCell(
          align: Alignment.center,
          child: podeEscrever
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBtn(
                      icon: Icons.edit_rounded,
                      tooltip: 'Editar',
                      color: AppTheme.primary,
                      onTap: () => onEditar(p),
                    ),
                    _IconBtn(
                      icon: p.ativo
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      tooltip: p.ativo ? 'Desativar' : 'Reativar',
                      color: p.ativo
                          ? const Color(0xFFD97706)
                          : const Color(0xFF15803D),
                      onTap: () => onToggleAtivo(p),
                    ),
                    if (!p.ativo)
                      _IconBtn(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Excluir',
                        color: AppTheme.error,
                        onTap: () => onExcluir(p),
                      ),
                  ],
                )
              : IconButton(
                  icon: const Icon(Icons.visibility_rounded, size: 15),
                  tooltip: 'Ver detalhes',
                  onPressed: () => onDetalhe(p),
                  visualDensity: VisualDensity.compact,
                  color: AppTheme.primary,
                ),
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
        style: GoogleFonts.nunito(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TdCell extends StatelessWidget {
  final Widget child;
  final Alignment align;
  const _TdCell({required this.child, this.align = Alignment.centerLeft});

  @override
  Widget build(BuildContext context) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: child,
        ),
      ),
    );
  }
}

// ─── Lista mobile ─────────────────────────────────────────────────────────────

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
            // Ícone
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
            // Conteúdo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nome,
                    style: GoogleFonts.nunito(
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
                        style: GoogleFonts.nunito(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (custo != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _fmtBrl(custo),
                          style: GoogleFonts.nunito(
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
            // Ações
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

// ─── Dialog de detalhe ────────────────────────────────────────────────────────

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
              // Header
              _DialogHeader(
                titulo: p.nome,
                subtitulo: p.categoria,
                icon: Icons.category_rounded,
                onClose: () => Navigator.pop(context),
                trailing: _StatusBadge(ativo: p.ativo),
              ),

              // Corpo
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
                            style: GoogleFonts.nunito(
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
                              style: GoogleFonts.nunito(
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
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _fmtBrl(p.custoEstimado!),
                                style: GoogleFonts.nunito(
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

              // Rodapé
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Fechar', style: GoogleFonts.nunito()),
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
    if (mat.medida    != null && mat.medida!.isNotEmpty)    partes.add(mat.medida!);
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
                  style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: GoogleFonts.nunito(
                        fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                if (pm.observacao != null && pm.observacao!.isNotEmpty)
                  Text(
                    pm.observacao!,
                    style: GoogleFonts.nunito(
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
                style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface),
              ),
              if (subtotal != null)
                Text(
                  _fmtBrl(subtotal),
                  style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600),
                )
              else
                Text(
                  ref != null ? '${_fmtBrl(ref)}/un' : 'sem preço',
                  style: GoogleFonts.nunito(
                      fontSize: 10, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Dialog de formulário (criar / editar) ────────────────────────────────────

class _ProdutoFormDialog extends StatefulWidget {
  final ProdutoModel? produto;
  const _ProdutoFormDialog({this.produto});

  @override
  State<_ProdutoFormDialog> createState() => _ProdutoFormDialogState();
}

class _ProdutoFormDialogState extends State<_ProdutoFormDialog> {
  final _formKey     = GlobalKey<FormState>();
  final _nomeCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _catCtrl     = TextEditingController();
  bool  _salvando    = false;

  // Materiais sendo montados para o produto
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
          materialId:   pm.materialId,
          nomeExibicao: pm.material.nome,
          quantidade:   pm.quantidade,
          observacao:   pm.observacao ?? '',
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
                'quantidade': m.quantidade,
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
            style: GoogleFonts.nunito(),
          ),
          backgroundColor: const Color(0xFF15803D),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prov.erro ?? 'Erro ao salvar',
              style: GoogleFonts.nunito()),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _adicionarMaterial(int id, String nome) {
    // Evita duplicatas
    if (_materiais.any((m) => m.materialId == id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material já adicionado')),
      );
      return;
    }
    setState(() {
      _materiais.add(_MaterialEntrada(
          materialId: id, nomeExibicao: nome, quantidade: 1, observacao: ''));
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
        constraints: const BoxConstraints(maxWidth: 620),
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
                        // Nome
                        _Campo(
                          label: 'Nome *',
                          ctrl:  _nomeCtrl,
                          hint:  'Ex: Porta de Vidro 2100×900',
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Nome é obrigatório'
                                  : null,
                        ),
                        const SizedBox(height: 12),

                        // Categoria
                        _Campo(
                          label: 'Categoria',
                          ctrl:  _catCtrl,
                          hint:  'Ex: Vidraçaria, Esquadria…',
                        ),
                        const SizedBox(height: 12),

                        // Descrição
                        _Campo(
                          label:  'Descrição',
                          ctrl:   _descCtrl,
                          hint:   'Observações sobre o produto…',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 20),

                        // Materiais
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
                              style: GoogleFonts.nunito(
                                  color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                          )
                        else
                          ...List.generate(_materiais.length, (i) {
                            final m = _materiais[i];
                            return _MaterialFormRow(
                              entrada:   m,
                              onRemover: () => _removerMaterial(i),
                              onChanged: (qtd, obs) {
                                setState(() {
                                  _materiais[i] = _MaterialEntrada(
                                    materialId:   m.materialId,
                                    nomeExibicao: m.nomeExibicao,
                                    quantidade:   qtd,
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

              // Botões
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _salvando ? null : () => Navigator.pop(context),
                      child: Text('Cancelar',
                          style: GoogleFonts.nunito()),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
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
                        style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
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

// ─── Linha de material no formulário ─────────────────────────────────────────

class _MaterialEntrada {
  final int materialId;
  final String nomeExibicao;
  final double quantidade;
  final String observacao;

  const _MaterialEntrada({
    required this.materialId,
    required this.nomeExibicao,
    required this.quantidade,
    required this.observacao,
  });
}

class _MaterialFormRow extends StatefulWidget {
  final _MaterialEntrada entrada;
  final VoidCallback onRemover;
  final void Function(double qtd, String obs) onChanged;

  const _MaterialFormRow({
    required this.entrada,
    required this.onRemover,
    required this.onChanged,
  });

  @override
  State<_MaterialFormRow> createState() => _MaterialFormRowState();
}

class _MaterialFormRowState extends State<_MaterialFormRow> {
  late final TextEditingController _qtdCtrl;
  late final TextEditingController _obsCtrl;

  @override
  void initState() {
    super.initState();
    _qtdCtrl = TextEditingController(
        text: _fmtQtd(widget.entrada.quantidade));
    _obsCtrl = TextEditingController(text: widget.entrada.observacao);
  }

  @override
  void dispose() {
    _qtdCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final qtd = double.tryParse(_qtdCtrl.text.replaceAll(',', '.')) ??
        widget.entrada.quantidade;
    widget.onChanged(qtd, _obsCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          // Nome
          Expanded(
            flex: 3,
            child: Text(
              widget.entrada.nomeExibicao,
              style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Qtd
          SizedBox(
            width: 70,
            height: 32,
            child: TextField(
              controller: _qtdCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _notify(),
              style: GoogleFonts.nunito(fontSize: 12),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 7),
                hintText: 'Qtd',
                hintStyle: GoogleFonts.nunito(fontSize: 11),
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
          const SizedBox(width: 8),
          // Obs
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _obsCtrl,
                onChanged: (_) => _notify(),
                style: GoogleFonts.nunito(fontSize: 11),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 7),
                  hintText: 'Observação',
                  hintStyle: GoogleFonts.nunito(fontSize: 11),
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
          // Remover
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                size: 16, color: AppTheme.error),
            tooltip: 'Remover',
            onPressed: widget.onRemover,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─── Busca de material (autocomplete) ────────────────────────────────────────

class _BuscaMaterialBtn extends StatelessWidget {
  final void Function(int id, String nome) onSelecionado;
  const _BuscaMaterialBtn({required this.onSelecionado});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _abrirBusca(context),
      icon: const Icon(Icons.add_rounded, size: 14),
      label: Text('Adicionar material',
          style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _abrirBusca(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _BuscaMaterialDialog(
        onSelecionado: (id, nome) {
          Navigator.pop(ctx);
          onSelecionado(id, nome);
        },
      ),
    );
  }
}

class _BuscaMaterialDialog extends StatefulWidget {
  final void Function(int id, String nome) onSelecionado;
  const _BuscaMaterialDialog({required this.onSelecionado});

  @override
  State<_BuscaMaterialDialog> createState() => _BuscaMaterialDialogState();
}

class _BuscaMaterialDialogState extends State<_BuscaMaterialDialog> {
  final _ctrl = TextEditingController();
  List<MaterialModel> _resultados = [];
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String q) async {
    setState(() => _buscando = true);
    final lista = await context
        .read<MaterialProvider>()
        .buscarSugestoes(q, limite: 20, apenasAtivos: true);
    if (mounted) setState(() { _resultados = lista; _buscando = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 480),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    'Buscar material',
                    style: GoogleFonts.raleway(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Busca
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _buscar,
                style: GoogleFonts.nunito(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Digite o nome…',
                  hintStyle: GoogleFonts.nunito(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Resultados
            Expanded(
              child: _buscando
                  ? const Center(child: CircularProgressIndicator())
                  : _resultados.isEmpty
                      ? Center(
                          child: Text('Nenhum material encontrado',
                              style: GoogleFonts.nunito(
                                  color: cs.onSurfaceVariant, fontSize: 13)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          itemCount: _resultados.length,
                          itemBuilder: (_, i) {
                            final m = _resultados[i];
                            final sub = [
                              if (m.categoria != null) m.categoria!,
                              if (m.medida    != null) m.medida!,
                              if (m.espessura != null) m.espessura!,
                            ].join(' · ');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.inventory_2_outlined,
                                  size: 16, color: AppTheme.primary),
                              title: Text(m.nome,
                                  style: GoogleFonts.nunito(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: sub.isNotEmpty
                                  ? Text(sub,
                                      style: GoogleFonts.nunito(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant))
                                  : null,
                              trailing: Text(
                                m.unidade ?? '',
                                style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant),
                              ),
                              onTap: () =>
                                  widget.onSelecionado(m.id, m.nome),
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

// ─── Widgets compartilhados ───────────────────────────────────────────────────

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
                  style: GoogleFonts.raleway(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitulo != null && subtitulo!.isNotEmpty)
                  Text(
                    subtitulo!,
                    style: GoogleFonts.nunito(
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
                size: 17, color: cs.onSurfaceVariant),
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
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
      style: GoogleFonts.nunito(
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
          style: GoogleFonts.nunito(
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
          style: GoogleFonts.nunito(fontSize: 13, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                GoogleFonts.nunito(fontSize: 12, color: cs.onSurfaceVariant),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: cs.outline.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: cs.outline.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppTheme.error, width: 1.5),
            ),
            filled: true,
            fillColor: cs.surface,
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
        style: GoogleFonts.nunito(
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
        style: GoogleFonts.nunito(
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
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

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
    v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);