import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/orcamento_venda_model.dart';
import '../models/produto_model.dart';
import '../providers/orcamento_venda_provider.dart';
import '../models/material_model.dart';
import '../providers/material_provider.dart';
import '../providers/produto_provider.dart';
import '../providers/usuario_provider.dart';
import '../models/fornecedor_model.dart';
import '../providers/fornecedor_provider.dart';
import '../repositories/configuracao_repository.dart';
import '../theme/app_theme.dart';
import '../pages/controle_estoque_page.dart' show formatarEspessuraComSufixo;

String _formatarUnidade(String unidade) {
  final trimmed = unidade.trim();
  if (trimmed.toLowerCase() == 'unidade') return 'Unidade';
  return trimmed.toLowerCase();
}

class OrcamentoVendaPage extends StatefulWidget {
  const OrcamentoVendaPage({super.key});

  @override
  State<OrcamentoVendaPage> createState() => _OrcamentoVendaPageState();
}

class _OrcamentoVendaPageState extends State<OrcamentoVendaPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _buscaCtrl = TextEditingController();
  String _filtroBusca = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrcamentoVendaProvider>().carregar();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaCtrl.dispose();
    super.dispose();
  }

  String get _roleUsuario =>
      context.read<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';

  bool get _podeEscrever =>
      ['ADMIN', 'GERENTE', 'ORCAMENTISTA'].contains(_roleUsuario);

  bool get _podeAprovar =>
      ['ADMIN', 'GERENTE'].contains(_roleUsuario);

  List<OrcamentoVendaModel> _filtrar(List<OrcamentoVendaModel> lista) {
    final q = _filtroBusca.trim().toLowerCase();
    if (q.isEmpty) return lista;
    return lista.where((o) =>
        o.numero.toLowerCase().contains(q) ||
        (o.clienteNome?.toLowerCase().contains(q) ?? false)).toList();
  }

  Future<void> _abrirEditor(OrcamentoVendaModel? inicial) async {
    final prov    = context.read<OrcamentoVendaProvider>();
    final prodProv = context.read<ProdutoProvider>();
    final fornecedorProv = context.read<FornecedorProvider>();
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: prov),
            ChangeNotifierProvider.value(value: prodProv),
            ChangeNotifierProvider.value(value: fornecedorProv),
          ],
          child: OrcamentoVendaEditorPage(inicial: inicial),
        ),
      ),
    );
    if (resultado == true && mounted) {
      context.read<OrcamentoVendaProvider>().recarregar();
    }
  }

  Future<void> _confirmarExclusao(OrcamentoVendaModel ov) async {
    final theme = Theme.of(context);
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Excluir orçamento?',
                    style: GoogleFonts.raleway(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'O orçamento "${ov.numero}" será excluído permanentemente.',
                  style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancelar', style: GoogleFonts.nunito()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Excluir', style: GoogleFonts.nunito()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirma != true || !mounted) return;
    final prov = context.read<OrcamentoVendaProvider>();
    final ok   = await prov.excluir(ov.id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(prov.erro ?? 'Erro ao excluir'),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _alterarStatus(OrcamentoVendaModel ov, {required bool aprovar}) async {
    final prov = context.read<OrcamentoVendaProvider>();
    final ok   = aprovar ? await prov.aprovar(ov.id) : await prov.reprovar(ov.id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(prov.erro ?? 'Erro ao alterar status'),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orçamentos de Venda',
                      style: (isMobile
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineMedium)
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Consumer<OrcamentoVendaProvider>(
                      builder: (_, p, __) {
                        final total = p.orcamentos.length;
                        return Text(
                          '$total ${total == 1 ? 'orçamento' : 'orçamentos'} no total',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        );
                      },
                    ),
                  ],
                ),
                const Spacer(),
                if (_podeEscrever)
                  Tooltip(
                    message: 'Criar um novo orçamento de venda',
                    child: FilledButton.icon(
                      onPressed: () => _abrirEditor(null),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(isMobile ? 'Novo' : 'Novo Orçamento',
                          style: GoogleFonts.nunito(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                const SizedBox(width: 12),
                Consumer<OrcamentoVendaProvider>(
                  builder: (_, p, __) => IconButton(
                    onPressed: p.carregando ? null : p.recarregar,
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Atualizar',
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(
                          color: theme.colorScheme.outlineVariant),
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _buscaCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por número ou cliente',
                prefixIcon: Icon(Icons.search,
                    color: theme.colorScheme.outline, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                suffixIcon: _filtroBusca.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            size: 18, color: theme.colorScheme.outline),
                        onPressed: () {
                          _buscaCtrl.clear();
                          setState(() => _filtroBusca = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _filtroBusca = v),
            ),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                    bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 2,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'Em Andamento'),
                  Tab(text: 'Aprovados'),
                  Tab(text: 'Não Aprovados'),
                ],
              ),
            ),

            Expanded(
              child: Consumer<OrcamentoVendaProvider>(
                builder: (context, prov, _) {
                  if (prov.carregando) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
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
                          Text('Erro ao carregar orçamentos',
                              style: GoogleFonts.raleway(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(prov.erro!,
                              style: GoogleFonts.nunito(
                                  color: theme.colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center),
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

                  final emAndamento = _filtrar(prov.orcamentos
                      .where((o) => o.status == 'EM_ANDAMENTO')
                      .toList());
                  final aprovados = _filtrar(prov.orcamentos
                      .where((o) => o.status == 'APROVADO')
                      .toList());
                  final naoAprovados = _filtrar(prov.orcamentos
                      .where((o) => o.status == 'NAO_APROVADO')
                      .toList());

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _OrcamentoList(
                        orcamentos:   emAndamento,
                        emptyMessage: 'Nenhum orçamento em andamento',
                        podeEscrever: _podeEscrever,
                        podeAprovar:  _podeAprovar,
                        onTap:        (ov) => _abrirEditor(ov),
                        onExcluir:    (ov) => _confirmarExclusao(ov),
                        onAprovar:    (ov) => _alterarStatus(ov, aprovar: true),
                        onReprovar:   (ov) => _alterarStatus(ov, aprovar: false),
                        mostrarAcoes: true,
                      ),
                      _OrcamentoList(
                        orcamentos:   aprovados,
                        emptyMessage: 'Nenhum orçamento aprovado',
                        podeEscrever: _podeEscrever,
                        podeAprovar:  _podeAprovar,
                        onTap:        (ov) => _abrirEditor(ov),
                        onExcluir:    (ov) => _confirmarExclusao(ov),
                        onAprovar:    (ov) => _alterarStatus(ov, aprovar: true),
                        onReprovar:   (ov) => _alterarStatus(ov, aprovar: false),
                        mostrarAcoes: false,
                      ),
                      _OrcamentoList(
                        orcamentos:   naoAprovados,
                        emptyMessage: 'Nenhum orçamento não aprovado',
                        podeEscrever: _podeEscrever,
                        podeAprovar:  _podeAprovar,
                        onTap:        (ov) => _abrirEditor(ov),
                        onExcluir:    (ov) => _confirmarExclusao(ov),
                        onAprovar:    (ov) => _alterarStatus(ov, aprovar: true),
                        onReprovar:   (ov) => _alterarStatus(ov, aprovar: false),
                        mostrarAcoes: false,
                      ),
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

class _OrcamentoList extends StatelessWidget {
  final List<OrcamentoVendaModel> orcamentos;
  final String emptyMessage;
  final bool podeEscrever;
  final bool podeAprovar;
  final bool mostrarAcoes;
  final ValueChanged<OrcamentoVendaModel> onTap;
  final ValueChanged<OrcamentoVendaModel> onExcluir;
  final ValueChanged<OrcamentoVendaModel> onAprovar;
  final ValueChanged<OrcamentoVendaModel> onReprovar;

  const _OrcamentoList({
    required this.orcamentos,
    required this.emptyMessage,
    required this.podeEscrever,
    required this.podeAprovar,
    required this.mostrarAcoes,
    required this.onTap,
    required this.onExcluir,
    required this.onAprovar,
    required this.onReprovar,
  });

  @override
  Widget build(BuildContext context) {
    if (orcamentos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.request_quote_outlined,
                size: 52,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(emptyMessage,
                style: GoogleFonts.nunito(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: orcamentos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _OrcamentoCard(
        orcamento:    orcamentos[i],
        podeEscrever: podeEscrever,
        podeAprovar:  podeAprovar,
        mostrarAcoes: mostrarAcoes,
        onTap:        () => onTap(orcamentos[i]),
        onExcluir:    () => onExcluir(orcamentos[i]),
        onAprovar:    () => onAprovar(orcamentos[i]),
        onReprovar:   () => onReprovar(orcamentos[i]),
      ),
    );
  }
}

class _OrcamentoCard extends StatelessWidget {
  final OrcamentoVendaModel orcamento;
  final bool podeEscrever;
  final bool podeAprovar;
  final bool mostrarAcoes;
  final VoidCallback onTap;
  final VoidCallback onExcluir;
  final VoidCallback onAprovar;
  final VoidCallback onReprovar;

  const _OrcamentoCard({
    required this.orcamento,
    required this.podeEscrever,
    required this.podeAprovar,
    required this.mostrarAcoes,
    required this.onTap,
    required this.onExcluir,
    required this.onAprovar,
    required this.onReprovar,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final ov          = orcamento;
    final emAndamento = ov.status == 'EM_ANDAMENTO';

    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.request_quote_rounded,
                  size: 20, color: AppTheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(ov.numero,
                          style: GoogleFonts.raleway(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface)),
                      const SizedBox(width: 8),
                      _StatusBadge(status: ov.status),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (ov.clienteNome != null && ov.clienteNome!.isNotEmpty)
                    Text(ov.clienteNome!,
                        style: GoogleFonts.nunito(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6))),
                  Text(
                    '${ov.itens.length} produto(s) · ${_fmtBrl(ov.valorTotal)}',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
            if (mostrarAcoes && podeAprovar && emAndamento) ...[
              _IconBtn(
                icon: Icons.check_circle_outline_rounded,
                tooltip: 'Aprovar',
                color: const Color(0xFF15803D),
                onTap: onAprovar,
              ),
              _IconBtn(
                icon: Icons.cancel_outlined,
                tooltip: 'Reprovar',
                color: AppTheme.error,
                onTap: onReprovar,
              ),
            ],
            if (podeEscrever)
              _IconBtn(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Excluir',
                color: AppTheme.error,
                onTap: onExcluir,
              ),
            _IconBtn(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Abrir',
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

class OrcamentoVendaEditorPage extends StatefulWidget {
  final OrcamentoVendaModel? inicial;

  const OrcamentoVendaEditorPage({super.key, this.inicial});

  @override
  State<OrcamentoVendaEditorPage> createState() =>
      _OrcamentoVendaEditorPageState();
}

class _OrcamentoVendaEditorPageState extends State<OrcamentoVendaEditorPage> {

  final _numeroCtrl  = TextEditingController();
  final _obsCtrl     = TextEditingController();

  int?   _clienteId;
  String _clienteNome = '';

  final _clienteBuscaCtrl = TextEditingController();
  List<Map<String, dynamic>> _clientesSugeridos = [];
  bool _buscandoClientes = false;
  Timer? _debounceCliente;
  final _clienteLayerLink = LayerLink();
  OverlayEntry? _clienteOverlay;

  _ItemRascunho? _item;
  bool _salvando = false;

  List<MarkupFaixa> _faixasMarkup = [];
  double? get _percentualMarkupAtual {
    if (_faixasMarkup.isEmpty) return null;
    final custo = _item?.subtotal ?? 0;
    for (final f in _faixasMarkup) {
      if (custo >= f.valorMin && (f.valorMax == null || custo <= f.valorMax!)) {
        return f.percentual;
      }
    }
    return _faixasMarkup.last.percentual;
  }

  double get _totalComMarkup {
    final custo = _item?.subtotal ?? 0;
    final pct = _percentualMarkupAtual;
    if (pct == null || pct <= 0) return custo;
    return custo * (1 + pct / 100);
  }

  final _produtoBuscaCtrl = TextEditingController();
  String _produtoBusca    = '';

  bool get _isEdit => widget.inicial != null;

  @override
  void initState() {
    super.initState();
    final ov = widget.inicial;
    if (ov != null) {
      _numeroCtrl.text = ov.numero;
      _obsCtrl.text    = ov.observacao ?? '';
      _clienteNome     = ov.clienteNome ?? '';
      _clienteBuscaCtrl.text = _clienteNome;

      if (ov.itens.isNotEmpty) {
        final item = ov.itens.first;
        _item = _ItemRascunho(
          produtoId:        item.produtoId,
          produtoNome:      item.produtoNome,
          produtoCategoria: item.produtoCategoria,
          materiais: item.materiais.map((m) => _MaterialRascunho(
            materialId:      m.materialId,
            nome:            m.material.nome,
            unidade:         m.material.unidade,
            medida:          m.material.medida,
            espessura:       m.material.espessura,
            identificador:   m.material.identificador,
            custoUnitario:   m.material.precoMedio ?? m.precoMedio,
            precoM2:         m.material.precoMedioM2,
            precoUnidadeMedida: m.material.precoUnidadeMedidaMediano,
            qtdCtrl:         TextEditingController(text: _fmtQtd(m.quantidade)),
            refLargura:      m.material.largura,
            refComprimento:  m.material.comprimento,
            ultimoValorPago: m.material.ultimoValorPago,
            larguraCtrl:     m.largura != null
                ? TextEditingController(text: _fmtQtd(m.largura!))
                : null,
            comprimentoCtrl: m.comprimento != null
                ? TextEditingController(text: _fmtQtd(m.comprimento!))
                : null,
          )..precoManualSelecionado = m.precoUnitario).toList(),
        );
      }
    }

    _produtoBuscaCtrl.addListener(() {
      setState(() => _produtoBusca = _produtoBuscaCtrl.text);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prodProv = context.read<ProdutoProvider>();
      if (prodProv.produtos.isEmpty) {
        await prodProv.carregar(ativo: true);
      }

      try {
        final faixas = await ConfiguracaoRepository().listarFaixas();
        if (mounted) setState(() => _faixasMarkup = faixas);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _obsCtrl.dispose();
    _clienteBuscaCtrl.dispose();
    _produtoBuscaCtrl.dispose();
    _debounceCliente?.cancel();
    _fecharOverlayCliente();
    _item?.dispose();
    super.dispose();
  }

  void _onClienteChanged(String valor) {

    setState(() {
      _clienteId   = null;
      _clienteNome = valor.trim();
    });
    _debounceCliente?.cancel();
    if (valor.trim().isEmpty) {
      _fecharOverlayCliente();
      return;
    }
    _debounceCliente = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _buscandoClientes = true);
      final prov      = context.read<OrcamentoVendaProvider>();
      final resultado = await prov.listarClientes(busca: valor.trim());
      if (!mounted) return;
      setState(() {
        _clientesSugeridos = resultado;
        _buscandoClientes  = false;
      });
      if (resultado.isNotEmpty) _abrirOverlayCliente();
    });
  }

  void _selecionarCliente(Map<String, dynamic> c) {
    setState(() {
      _clienteId   = c['id'] as int?;
      _clienteNome = c['nome'] as String? ?? '';
    });
    _clienteBuscaCtrl.text = _clienteNome;
    _clienteBuscaCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _clienteNome.length));
    _fecharOverlayCliente();
  }

  void _abrirOverlayCliente() {
    _fecharOverlayCliente();
    final overlay  = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _clienteOverlay = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _clienteLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 48),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _clientesSugeridos.length,
                itemBuilder: (_, i) {
                  final c = _clientesSugeridos[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, size: 18),
                    title: Text(c['nome'] as String? ?? '',
                        style: GoogleFonts.nunito(fontSize: 13)),
                    onTap: () => _selecionarCliente(c),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_clienteOverlay!);
  }

  void _fecharOverlayCliente() {
    _clienteOverlay?.remove();
    _clienteOverlay = null;
  }

  List<_MaterialRascunho> _materiaisDeProducto(ProdutoModel produto) {
    return produto.materiais.map((pm) => _MaterialRascunho(
          materialId:     pm.materialId,
          nome:           pm.material.nome,
          unidade:        pm.material.unidade,
          medida:         pm.material.medida,
          espessura:      pm.material.espessura,
          identificador:  pm.material.identificador,
          custoUnitario:  pm.material.precoMedio,
          precoM2:        pm.material.precoMedioM2,
          precoUnidadeMedida: pm.material.precoUnidadeMedidaMediano,
          qtdCtrl:        TextEditingController(),
          refLargura:     pm.material.largura,
          refComprimento: pm.material.comprimento,
          ultimoValorPago: pm.material.ultimoValorPago,
          larguraCtrl:     (pm.material.largura != null && pm.material.largura! > 0)
              ? TextEditingController(text: _fmtQtd(pm.material.largura!))
              : null,
          comprimentoCtrl: (pm.material.comprimento != null && pm.material.comprimento! > 0)
              ? TextEditingController(text: _fmtQtd(pm.material.comprimento!))
              : null,
        )).toList();
  }

  void _selecionarProduto(ProdutoModel produto) {
    setState(() {
      _item?.dispose();
      _item = _ItemRascunho(
        produtoId:        produto.id,
        produtoNome:      produto.nome,
        produtoCategoria: produto.categoria,
        materiais:        _materiaisDeProducto(produto),
      );
    });
  }

  void _removerItem() {
    setState(() {
      _item?.dispose();
      _item = null;
    });
  }

  void _adicionarMaterialExtra() async {
    if (_item == null) return;
    final todosIds = _item!.materiais.map((m) => m.materialId).toSet();

    final selecionado = await showDialog<MaterialModel>(
      context: context,
      builder: (_) => _SelecionarMaterialDialog(idsExcluidos: todosIds),
    );
    if (selecionado == null || !mounted) return;

    final novoMaterial = _MaterialRascunho(
      materialId:      selecionado.id,
      nome:            selecionado.nome,
      unidade:         selecionado.unidade,
      medida:          selecionado.medida,
      espessura:       selecionado.espessura,
      identificador:   selecionado.identificador,
      custoUnitario:   selecionado.precoMediano,
      precoM2:         selecionado.precoM2Mediano,
      precoUnidadeMedida: selecionado.precoRefUnidadeMedida,
      qtdCtrl:         TextEditingController(),
      refLargura:      selecionado.largura,
      refComprimento:  selecionado.comprimento,
      ultimoValorPago: selecionado.ultimoValorPago,
      larguraCtrl:     (selecionado.largura != null && selecionado.largura! > 0)
          ? TextEditingController(text: _fmtQtd(selecionado.largura!))
          : null,
      comprimentoCtrl: (selecionado.comprimento != null && selecionado.comprimento! > 0)
          ? TextEditingController(text: _fmtQtd(selecionado.comprimento!))
          : null,
    );

    setState(() {
      _item!.materiais.add(novoMaterial);
    });

    // Materiais adicionados avulsamente (sem vínculo original com o
    // produto) podem não trazer preço médio pré-calculado do backend.
    // Busca a média de preços dos fornecedores para os 3 campos (base,
    // m² e unidade de medida) e preenche automaticamente, para que o
    // material extra entre com o mesmo padrão dos demais — preenchendo
    // os campos "padrão" (não os *ManualSelecionado*), para que o texto
    // não fique destacado em laranja como se tivesse sido escolhido
    // manualmente. O destaque só deve aparecer se o usuário de fato
    // trocar o preço depois, clicando e selecionando outro fornecedor.
    if (!mounted) return;
    await _preencherPrecoPadraoMaterialExtra(
      context: context,
      mat: novoMaterial,
    );
    if (!mounted) return;
    setState(() {});
  }

  bool _validar() {
    if (_numeroCtrl.text.trim().isEmpty) {
      _snack('Informe o número do orçamento.');
      return false;
    }
    if (_clienteNome.trim().isEmpty) {
      _snack('Informe o nome do cliente.');
      return false;
    }

    if (_item == null) {
      _snack('Adicione um produto ao orçamento.');
      return false;
    }
    for (final m in _item!.materiais) {
      if (m.qtdCtrl.text.trim().isEmpty) {
        _snack('Preencha a quantidade de "${m.nome}".');
        return false;
      }
      final v = double.tryParse(m.qtdCtrl.text.replaceAll(',', '.'));
      if (v == null || v < 0) {
        _snack('Quantidade inválida para "${m.nome}".');
        return false;
      }
    }
    return true;
  }

  void _snack(String msg, {bool erro = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: erro ? AppTheme.error : const Color(0xFF15803D),
    ));
  }

  Future<void> _salvar() async {
    if (!_validar()) return;
    setState(() => _salvando = true);

    final payload = <String, dynamic>{
      'numero': _numeroCtrl.text.trim(),
      'clienteNome': _clienteNome.trim(),
      'clienteId': _clienteId,
      'observacao': _obsCtrl.text.trim().isEmpty
          ? null
          : _obsCtrl.text.trim(),
      'itens': [
        {
          'produtoId': _item!.produtoId,
          'quantidade': 1,
          'materiais': _item!.materiais.map((m) => {
            'materialId':    m.materialId,
            'quantidade':    m.quantidade,

            'precoUnitario': m.precoUnitarioCalculado,

            'precoMedio':    m.precoExibido,
            'largura':       m._largura,
            'comprimento':   m._comprimento,
          }).toList(),
        }
      ],
    };
    final prov = context.read<OrcamentoVendaProvider>();

    if (_isEdit) {

      final editPayload = {
        'observacao': payload['observacao'],
        'itens':      payload['itens'],
      };
      final ok = await prov.atualizar(widget.inicial!.id, editPayload);
      setState(() => _salvando = false);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
        _snack('Orçamento atualizado com sucesso.', erro: false);
      } else {
        _snack(prov.erro ?? 'Erro ao atualizar orçamento.');
      }
    } else {
      final ov = await prov.criar(payload);
      setState(() => _salvando = false);
      if (!mounted) return;
      if (ov != null) {
        Navigator.pop(context, true);
        _snack('Orçamento ${ov.numero} criado com sucesso.', erro: false);
      } else {
        _snack(prov.erro ?? 'Erro ao criar orçamento.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leadingWidth: 100,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _BotaoVoltarOrcamento(
              onTap: () {
                if (!isMobile && _item != null) {
                  _removerItem();
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit
                  ? 'Editar Orçamento ${widget.inicial!.numero}'
                  : 'Novo Orçamento de Venda',
              style: GoogleFonts.raleway(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
            if (_isEdit && (widget.inicial!.clienteNome?.isNotEmpty ?? false))
              Text(
                widget.inicial!.clienteNome!,
                style: GoogleFonts.nunito(
                    fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: _isEdit ? 'Salvar alterações do orçamento' : 'Criar novo orçamento de venda',
              child: FilledButton(
                onPressed: _salvando ? null : _salvar,
                style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary)
                    .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                child: _salvando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isEdit ? 'Salvar' : 'Criar Orçamento',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),

      body: isMobile
          ? _buildFormulario(cs, isMobile: true)
          : (_item == null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _PainelProdutos(
                      buscaCtrl:         _produtoBuscaCtrl,
                      busca:             _produtoBusca,
                      produtoSelecionado: _item?.produtoId,
                      onSelecionar:      _selecionarProduto,
                    ),

                    VerticalDivider(
                        width: 1,
                        color: cs.outline.withValues(alpha: 0.15)),

                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 40,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              'Selecione um produto para começar',
                              style: GoogleFonts.nunito(
                                  fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : _buildFormulario(cs, isMobile: false)),
    );
  }

  Widget _buildFormulario(ColorScheme cs, {required bool isMobile}) {
    return ListView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      children: [

        _SectionLabel('Dados do orçamento'),
        const SizedBox(height: 10),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            SizedBox(
              width: 160,
              child: _Campo(
                label:    'Nº do Orçamento',
                ctrl:     _numeroCtrl,
                hint:     'Nº do Orçamento',
                enabled:  !_isEdit,
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: _CampoClienteAutocomplete(
                buscaCtrl:        _clienteBuscaCtrl,
                clienteId:        _clienteId,
                layerLink:        _clienteLayerLink,
                buscando:         _buscandoClientes,
                onChanged:        _onClienteChanged,
                onFocusLost:      _fecharOverlayCliente,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _Campo(
          label:    'Observação',
          ctrl:     _obsCtrl,
          hint:     'Anotações opcionais',
          maxLines: 2,
        ),

        const SizedBox(height: 28),

        if (isMobile) ...[
          Row(
            children: [
              const _SectionLabel('Produto'),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () async {
                  final prodProv = context.read<ProdutoProvider>();
                  if (prodProv.produtos.isEmpty) {
                    await prodProv.carregar(ativo: true);
                  }
                  if (!mounted) return;
                  final selecionado = await showDialog<ProdutoModel>(
                    context: context,
                    builder: (_) => _SelecionarProdutoDialog(
                      produtos: prodProv.produtos.where((p) => p.ativo).toList(),
                    ),
                  );
                  if (selecionado != null) _selecionarProduto(selecionado);
                },
                icon: Icon(
                    _item == null ? Icons.add_rounded : Icons.swap_horiz_rounded,
                    size: 16),
                label: Text(
                    _item == null ? 'Selecionar Produto' : 'Trocar produto',
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ] else ...[
          const _SectionLabel('Produto selecionado'),
          const SizedBox(height: 10),
        ],

        if (_item == null)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
            ),
            child: Center(
              child: Text(
                isMobile
                    ? 'Nenhum produto selecionado.\nClique em "Selecionar Produto" acima.'
                    : 'Nenhum produto selecionado.\nClique em um produto na coluna à esquerda.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                    fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          _ItemRascunhoCard(
            key:           ValueKey(_item!.produtoId),
            item:          _item!,
            onRemover:     _removerItem,
            onAddMaterial: _adicionarMaterialExtra,
            onQtdChanged:  () => setState(() {}),
          ),

        const SizedBox(height: 28),

        Builder(builder: (context) {
          final subtotalLocal  = _item?.subtotal ?? 0;
          final markupPct      = _percentualMarkupAtual;
          final totalComMarkup = _totalComMarkup;

          final valorExibido = totalComMarkup;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total estimado',
                        style: GoogleFonts.nunito(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                    if (markupPct != null && markupPct > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Custo: ${_fmtBrl(subtotalLocal)}  ·  Markup: ${markupPct.toStringAsFixed(0)}%',
                        style: GoogleFonts.nunito(
                            fontSize: 10,
                            color: AppTheme.primary.withValues(alpha: 0.65)),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                Text(
                  _fmtBrl(valorExibido),
                  style: GoogleFonts.raleway(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 80),
      ],
    );
  }
}

class _PainelProdutos extends StatelessWidget {
  final TextEditingController buscaCtrl;
  final String busca;
  final int? produtoSelecionado;
  final ValueChanged<ProdutoModel> onSelecionar;

  const _PainelProdutos({
    required this.buscaCtrl,
    required this.busca,
    required this.produtoSelecionado,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 280,
      child: Column(
        children: [

          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            color: cs.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Produtos',
                    style: GoogleFonts.raleway(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 8),

                TextField(
                  controller: buscaCtrl,
                  style: GoogleFonts.nunito(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar produto',
                    hintStyle: GoogleFonts.nunito(
                        fontSize: 12, color: cs.onSurfaceVariant),
                    prefixIcon: Icon(Icons.search,
                        size: 16, color: cs.onSurfaceVariant),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: cs.outline.withValues(alpha: 0.35)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: cs.outline.withValues(alpha: 0.35)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    suffixIcon: busca.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                size: 14, color: cs.onSurfaceVariant),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => buscaCtrl.clear(),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: Consumer<ProdutoProvider>(
              builder: (_, prodProv, __) {
                if (prodProv.carregando) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 2));
                }

                final q = busca.trim().toLowerCase();
                final lista = prodProv.produtos.where((p) {
                  if (!p.ativo) return false;
                  if (q.isEmpty) return true;
                  return p.nome.toLowerCase().contains(q) ||
                      (p.categoria?.toLowerCase().contains(q) ?? false);
                }).toList();

                if (lista.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        busca.isEmpty
                            ? 'Nenhum produto cadastrado.'
                            : 'Nenhum produto encontrado.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: lista.length,
                  itemBuilder: (_, i) {
                    final p          = lista[i];
                    final selecionado = p.id == produtoSelecionado;

                    return InkWell(
                      onTap: () => onSelecionar(p),
                      mouseCursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: selecionado
                              ? AppTheme.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selecionado
                                ? AppTheme.primary.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: selecionado
                                    ? AppTheme.primary.withValues(alpha: 0.15)
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                selecionado
                                    ? Icons.check_rounded
                                    : Icons.category_outlined,
                                size: 14,
                                color: selecionado
                                    ? AppTheme.primary
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.nome,
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontWeight: selecionado
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: selecionado
                                            ? AppTheme.primary
                                            : cs.onSurface,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  if (p.categoria != null)
                                    Text(p.categoria!,
                                        style: GoogleFonts.nunito(
                                            fontSize: 10,
                                            color: cs.onSurfaceVariant),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoClienteAutocomplete extends StatelessWidget {
  final TextEditingController buscaCtrl;
  final int? clienteId;
  final LayerLink layerLink;
  final bool buscando;
  final ValueChanged<String> onChanged;
  final VoidCallback onFocusLost;

  const _CampoClienteAutocomplete({
    required this.buscaCtrl,
    required this.clienteId,
    required this.layerLink,
    required this.buscando,
    required this.onChanged,
    required this.onFocusLost,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Cliente',
                style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant)),
            const SizedBox(width: 6),

            if (clienteId != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 11, color: Color(0xFF15803D)),
                    const SizedBox(width: 3),
                    Text('Selecionado',
                        style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF15803D))),
                  ],
                ),
              )
            else
              Text('Digite o nome do cliente',
                  style: GoogleFonts.nunito(
                      fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 4),
        CompositedTransformTarget(
          link: layerLink,
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) {
                Future.delayed(
                    const Duration(milliseconds: 200), onFocusLost);
              }
            },
            child: TextFormField(
              controller: buscaCtrl,
              onChanged: onChanged,
              style: GoogleFonts.nunito(fontSize: 13, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Digitar nome do cliente',
                hintStyle: GoogleFonts.nunito(
                    fontSize: 12, color: cs.onSurfaceVariant),
                prefixIcon: const Icon(Icons.person_search_outlined,
                    size: 18, color: AppTheme.primary),
                suffixIcon: buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                      )
                    : null,
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
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: cs.surface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemRascunhoCard extends StatelessWidget {
  final _ItemRascunho item;
  final VoidCallback onRemover;
  final VoidCallback onAddMaterial;
  final VoidCallback onQtdChanged;

  const _ItemRascunhoCard({
    super.key,
    required this.item,
    required this.onRemover,
    required this.onAddMaterial,
    required this.onQtdChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.category_rounded,
                      size: 14, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.produtoNome,
                      style: GoogleFonts.raleway(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                Text(
                  _fmtBrl(item.subtotal),
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Remover produto',
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: cs.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemover,
                    style: IconButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          LayoutBuilder(
            builder: (context, constraints) {
              const larguraColunasFixas = 100 + 
                  14 +                          
                  100 +                         
                  4 +                           
                  100 +                         
                  44 +                          
                  80 +                          
                  8 +                           
                  80 +                          
                  8 +                           
                  120 +                         
                  8 +                           
                  100;                          
              const paddingHorizontal = 24.0;
              const larguraMinimaMaterial = 220.0;

              final larguraMaterial = (constraints.maxWidth -
                      paddingHorizontal -
                      larguraColunasFixas)
                  .clamp(larguraMinimaMaterial, double.infinity);

              final precisaScroll = larguraMaterial == larguraMinimaMaterial &&
                  (constraints.maxWidth - paddingHorizontal - larguraColunasFixas) <
                      larguraMinimaMaterial;

              final tabela = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: larguraMaterial,
                          child: Text('Material',
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),

                        SizedBox(
                          width: 100,
                          child: Text('Comprimento',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),

                        const SizedBox(width: 14),

                        SizedBox(
                          width: 100,
                          child: Text('Largura',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),
                        const SizedBox(width: 4),

                        SizedBox(
                          width: 100,
                          child: Text('Quantidade',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),

                        const SizedBox(width: 44),

                        SizedBox(
                          width: 80,
                          child: Text('Preço',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),
                        const SizedBox(width: 8),

                        SizedBox(
                          width: 80,
                          child: Text('Preço m²',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),
                        const SizedBox(width: 8),

                        SizedBox(
                          width: 120,
                          child: Text('Preço (m/l, ml, g)',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),
                        const SizedBox(width: 8),

                        SizedBox(
                          width: 100,
                          child: Text('Subtotal',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ),

                  for (final m in item.materiais)
                    _MaterialLinhaRascunho(
                      mat: m,
                      onQtdChanged: onQtdChanged,
                      larguraMaterial: larguraMaterial,
                    ),
                ],
              );

              if (!precisaScroll) return tabela;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: larguraMinimaMaterial +
                        larguraColunasFixas +
                        paddingHorizontal,
                  ),
                  child: tabela,
                ),
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: 'Adicionar outro material a este produto',
                child: TextButton.icon(
                  onPressed: onAddMaterial,
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: Text('Adicionar material',
                      style: GoogleFonts.nunito(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialLinhaRascunho extends StatelessWidget {
  final _MaterialRascunho mat;
  final VoidCallback onQtdChanged;
  final double larguraMaterial;

  const _MaterialLinhaRascunho({
    required this.mat,
    required this.onQtdChanged,
    this.larguraMaterial = 220,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget campoNumerico({
      required TextEditingController ctrl,
      required String hint,
      double width = 72,
    }) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: ctrl,
            onChanged: (_) => onQtdChanged(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 12),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.nunito(
                  fontSize: 11, color: cs.onSurfaceVariant),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: cs.outline.withValues(alpha: 0.35)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: cs.outline.withValues(alpha: 0.35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: cs.surfaceContainerLow,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Row(
        children: [

          SizedBox(
            width: larguraMaterial,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mat.nome,
                    style: GoogleFonts.nunito(fontSize: 12, color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ([
                        mat.identificador,
                        (mat.medida != null && mat.medida!.isNotEmpty)
                            ? mat.medida
                            : _medidaFromDimensoes(mat.refComprimento, mat.refLargura),
                        mat.espessura,
                      ].any((v) => v != null && v.isNotEmpty))
                    Text(
                      [
                        if (mat.identificador != null && mat.identificador!.isNotEmpty)
                          mat.identificador!,
                        if (mat.medida != null && mat.medida!.isNotEmpty)
                          mat.medida!
                        else if (_medidaFromDimensoes(mat.refComprimento, mat.refLargura) != null)
                          _medidaFromDimensoes(mat.refComprimento, mat.refLargura)!,
                        if (formatarEspessuraComSufixo(mat.espessura) != null)
                          formatarEspessuraComSufixo(mat.espessura)!,
                      ].join(' · '),
                      style: GoogleFonts.nunito(
                          fontSize: 10, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),

          SizedBox(
            width: 100,
            child: mat.temDimensoes
                ? campoNumerico(
                    ctrl: mat.comprimentoCtrl,
                    hint: 'Comprimento',
                    width: 100,
                  )
                : null,
          ),

          SizedBox(
            width: 14,
            child: mat.temDimensoes
                ? Center(
                    child: Text('×',
                        style: GoogleFonts.nunito(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  )
                : null,
          ),

          SizedBox(
            width: 100,
            child: mat.temDimensoes
                ? campoNumerico(
                    ctrl: mat.larguraCtrl,
                    hint: 'Largura',
                    width: 100,
                  )
                : null,
          ),
          const SizedBox(width: 4),

          SizedBox(
            width: 100,
            child: campoNumerico(
              ctrl: mat.qtdCtrl,
              hint: 'Quantidade',
              width: 100,
            ),
          ),

          SizedBox(
            width: 44,
            child: mat.unidade != null && mat.unidade!.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      _formatarUnidade(mat.unidade!),
                      style: GoogleFonts.nunito(
                          fontSize: 10, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                  )
                : null,
          ),

          SizedBox(
            width: 80,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final resultado = await showDialog<_PrecoFornecedorSelecionado>(
                  context: context,
                  builder: (_) => _PrecosFornecedoresDialog(materialId: mat.materialId),
                );
                if (resultado != null) {
                  mat.precoManualSelecionado = resultado.preco;
                  mat.origemPrecoManual = resultado.origem;
                  if (!context.mounted) return;
                  if (resultado.fornecedorId != null) {
                    await _sincronizarPrecosFornecedor(
                      context: context,
                      mat: mat,
                      fornecedorId: resultado.fornecedorId!,
                      origem: resultado.origem,
                      campoOrigem: _CampoPreco.base,
                    );
                  } else if (resultado.origem == 'Média' ||
                      resultado.origem == 'Mediana') {
                    await _sincronizarPrecosEstatistica(
                      context: context,
                      mat: mat,
                      estatistica: resultado.origem,
                      campoOrigem: _CampoPreco.base,
                    );
                  }
                  onQtdChanged();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  mat.precoExibido != null
                      ? _fmtBrl(mat.precoExibido!)
                      : '—',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: mat.precoManualSelecionado != null
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: mat.precoManualSelecionado != null
                        ? AppTheme.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          SizedBox(
            width: 80,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final resultado = await showDialog<_PrecoFornecedorSelecionado>(
                  context: context,
                  builder: (_) => _PrecosFornecedoresDialog(
                    materialId: mat.materialId,
                    campo: _CampoPreco.m2,
                    titulo: 'Preços por m² dos Fornecedores',
                    comprimentoReferencia: mat.refComprimento,
                    larguraReferencia: mat.refLargura,
                  ),
                );
                if (resultado != null) {
                  mat.precoM2ManualSelecionado = resultado.preco;
                  mat.origemPrecoM2Manual = resultado.origem;
                  if (!context.mounted) return;
                  if (resultado.fornecedorId != null) {
                    await _sincronizarPrecosFornecedor(
                      context: context,
                      mat: mat,
                      fornecedorId: resultado.fornecedorId!,
                      origem: resultado.origem,
                      campoOrigem: _CampoPreco.m2,
                    );
                  } else if (resultado.origem == 'Média' ||
                      resultado.origem == 'Mediana') {
                    await _sincronizarPrecosEstatistica(
                      context: context,
                      mat: mat,
                      estatistica: resultado.origem,
                      campoOrigem: _CampoPreco.m2,
                    );
                  }
                  onQtdChanged();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  mat.precoM2Exibido != null
                      ? _fmtBrl(mat.precoM2Exibido!)
                      : '—',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: mat.precoM2ManualSelecionado != null
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: mat.precoM2ManualSelecionado != null
                        ? AppTheme.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          SizedBox(
            width: 120,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final resultado = await showDialog<_PrecoFornecedorSelecionado>(
                  context: context,
                  builder: (_) => _PrecosFornecedoresDialog(
                    materialId: mat.materialId,
                    campo: _CampoPreco.unidadeMedida,
                    titulo: 'Preços por Unidade de Medida dos Fornecedores',
                    comprimentoReferencia: mat.refComprimento,
                  ),
                );
                if (resultado != null) {
                  mat.precoUnidadeMedidaManualSelecionado = resultado.preco;
                  mat.origemPrecoUnidadeMedidaManual = resultado.origem;
                  if (!context.mounted) return;
                  if (resultado.fornecedorId != null) {
                    await _sincronizarPrecosFornecedor(
                      context: context,
                      mat: mat,
                      fornecedorId: resultado.fornecedorId!,
                      origem: resultado.origem,
                      campoOrigem: _CampoPreco.unidadeMedida,
                    );
                  } else if (resultado.origem == 'Média' ||
                      resultado.origem == 'Mediana') {
                    await _sincronizarPrecosEstatistica(
                      context: context,
                      mat: mat,
                      estatistica: resultado.origem,
                      campoOrigem: _CampoPreco.unidadeMedida,
                    );
                  }
                  onQtdChanged();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  mat.precoUnidadeMedidaExibido != null
                      ? _fmtBrl(mat.precoUnidadeMedidaExibido!)
                      : '—',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: mat.precoUnidadeMedidaManualSelecionado != null
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: mat.precoUnidadeMedidaManualSelecionado != null
                        ? AppTheme.primary
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          SizedBox(
            width: 100,
            child: Text(
              mat.precoUnitarioCalculado != null && mat.qtdCtrl.text.isNotEmpty
                  ? _fmtBrl(mat.subtotal)
                  : '—',
              textAlign: TextAlign.right,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: mat.qtdCtrl.text.isNotEmpty
                    ? cs.onSurface
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
        ),

        if (mat.areaSobraM2 != null && mat.custoSobra != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE8A000).withValues(alpha: 0.35)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.content_cut_rounded,
                      size: 12, color: Color(0xFF92400E)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Sobra: ${_fmtM2(mat.areaSobraM2!)} m² '
                      '(${_fmtQtd(mat.refLargura!)} × ${_fmtQtd(mat.refComprimento!)} '
                      '− ${_fmtQtd(mat.larguraDigitada!)} × ${_fmtQtd(mat.comprimentoDigitado!)})',
                      style: GoogleFonts.nunito(
                          fontSize: 10,
                          color: const Color(0xFF92400E)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmtBrl(mat.custoSobra!),
                    style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF92400E)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _sincronizarPrecosFornecedor({
  required BuildContext context,
  required _MaterialRascunho mat,
  required int fornecedorId,
  required String origem,
  required _CampoPreco campoOrigem,
}) async {
  try {
    final prov = context.read<FornecedorProvider>();
    final lista = await prov.listarPorMaterial(mat.materialId);
    FornecedorMaterialVinculoModel? vinculo;
    for (final f in lista) {
      if (f.id != fornecedorId) continue;
      for (final m in f.materiais) {
        if (m.materialId == mat.materialId) {
          vinculo = m;
          break;
        }
      }
      break;
    }
    if (vinculo == null) return;

    double? comprimentoRef() {
      if (vinculo!.materialComprimento != null &&
          vinculo.materialComprimento! > 0) {
        return vinculo.materialComprimento;
      }
      return mat.refComprimento;
    }

    double? larguraRef() {
      if (vinculo!.materialLargura != null && vinculo.materialLargura! > 0) {
        return vinculo.materialLargura;
      }
      return mat.refLargura;
    }

    double? area() {
      final c = comprimentoRef();
      final l = larguraRef();
      if (c == null || c <= 0 || l == null || l <= 0) return null;
      return c * l;
    }

    if (campoOrigem != _CampoPreco.base) {
      double? precoBase;
      if (vinculo.preco > 0) precoBase = vinculo.preco;
      if (precoBase != null && precoBase > 0) {
        mat.precoManualSelecionado = precoBase;
        mat.origemPrecoManual = origem;
      }
    }

    if (campoOrigem != _CampoPreco.m2) {
      double? precoM2;
      if (vinculo.precoMetroQuadrado > 0) {
        precoM2 = vinculo.precoMetroQuadrado;
      } else {
        final a = area();
        if (vinculo.preco > 0 && a != null && a > 0) {
          precoM2 = vinculo.preco / a;
        }
      }
      if (precoM2 != null && precoM2 > 0) {
        mat.precoM2ManualSelecionado = precoM2;
        mat.origemPrecoM2Manual = origem;
      }
    }

    if (campoOrigem != _CampoPreco.unidadeMedida) {
      double? precoUnidade;
      if (vinculo.precoUnidadeMedida > 0) {
        precoUnidade = vinculo.precoUnidadeMedida;
      } else {
        final c = comprimentoRef();
        if (vinculo.preco > 0 && c != null && c > 0) {
          precoUnidade = vinculo.preco / c;
        }
      }
      if (precoUnidade != null && precoUnidade > 0) {
        mat.precoUnidadeMedidaManualSelecionado = precoUnidade;
        mat.origemPrecoUnidadeMedidaManual = origem;
      }
    }
  } catch (_) {
  }
}

// Preenche os campos de preço "padrão" (custoUnitario, precoM2,
// precoUnidadeMedida) de um material extra recém-adicionado, usando a
// média de preços dos fornecedores. Diferente de
// _sincronizarPrecosEstatistica, NÃO grava em *ManualSelecionado*, para
// que o valor apareça com o texto normal (não laranja) — o destaque
// laranja deve ficar reservado apenas para quando o usuário escolhe
// manualmente um preço através do diálogo de fornecedores.
Future<void> _preencherPrecoPadraoMaterialExtra({
  required BuildContext context,
  required _MaterialRascunho mat,
}) async {
  try {
    final prov = context.read<FornecedorProvider>();
    final lista = await prov.listarPorMaterial(mat.materialId);

    final vinculos = lista
        .expand((f) => f.materiais.where((m) => m.materialId == mat.materialId))
        .toList();
    if (vinculos.isEmpty) return;

    double? comprimentoRef(FornecedorMaterialVinculoModel v) {
      if (v.materialComprimento != null && v.materialComprimento! > 0) {
        return v.materialComprimento;
      }
      return mat.refComprimento;
    }

    double? larguraRef(FornecedorMaterialVinculoModel v) {
      if (v.materialLargura != null && v.materialLargura! > 0) {
        return v.materialLargura;
      }
      return mat.refLargura;
    }

    double? area(FornecedorMaterialVinculoModel v) {
      final c = comprimentoRef(v);
      final l = larguraRef(v);
      if (c == null || c <= 0 || l == null || l <= 0) return null;
      return c * l;
    }

    double? calcularMedia(_CampoPreco campo) {
      final precos = vinculos.map((v) {
        switch (campo) {
          case _CampoPreco.base:
            return v.preco > 0 ? v.preco : 0.0;
          case _CampoPreco.m2:
            if (v.precoMetroQuadrado > 0) return v.precoMetroQuadrado;
            final a = area(v);
            if (v.preco > 0 && a != null && a > 0) return v.preco / a;
            return 0.0;
          case _CampoPreco.unidadeMedida:
            if (v.precoUnidadeMedida > 0) return v.precoUnidadeMedida;
            final c = comprimentoRef(v);
            if (v.preco > 0 && c != null && c > 0) return v.preco / c;
            return 0.0;
        }
      }).where((p) => p > 0).toList();

      if (precos.isEmpty) return null;
      return precos.reduce((a, b) => a + b) / precos.length;
    }

    if (mat.custoUnitario == null || mat.custoUnitario! <= 0) {
      final v = calcularMedia(_CampoPreco.base);
      if (v != null) mat.custoUnitario = v;
    }
    if (mat.precoM2 == null || mat.precoM2! <= 0) {
      final v = calcularMedia(_CampoPreco.m2);
      if (v != null) mat.precoM2 = v;
    }
    if (mat.precoUnidadeMedida == null || mat.precoUnidadeMedida! <= 0) {
      final v = calcularMedia(_CampoPreco.unidadeMedida);
      if (v != null) mat.precoUnidadeMedida = v;
    }
  } catch (_) {
  }
}

Future<void> _sincronizarPrecosEstatistica({
  required BuildContext context,
  required _MaterialRascunho mat,
  required String estatistica,
  required _CampoPreco campoOrigem,
}) async {
  try {
    final prov = context.read<FornecedorProvider>();
    final lista = await prov.listarPorMaterial(mat.materialId);

    final vinculos = lista
        .expand((f) => f.materiais.where((m) => m.materialId == mat.materialId))
        .toList();
    if (vinculos.isEmpty) return;

    double? comprimentoRef(FornecedorMaterialVinculoModel v) {
      if (v.materialComprimento != null && v.materialComprimento! > 0) {
        return v.materialComprimento;
      }
      return mat.refComprimento;
    }

    double? larguraRef(FornecedorMaterialVinculoModel v) {
      if (v.materialLargura != null && v.materialLargura! > 0) {
        return v.materialLargura;
      }
      return mat.refLargura;
    }

    double? area(FornecedorMaterialVinculoModel v) {
      final c = comprimentoRef(v);
      final l = larguraRef(v);
      if (c == null || c <= 0 || l == null || l <= 0) return null;
      return c * l;
    }

    double? calcular(_CampoPreco campo) {
      final precos = vinculos.map((v) {
        switch (campo) {
          case _CampoPreco.base:
            return v.preco > 0 ? v.preco : 0.0;
          case _CampoPreco.m2:
            if (v.precoMetroQuadrado > 0) return v.precoMetroQuadrado;
            final a = area(v);
            if (v.preco > 0 && a != null && a > 0) return v.preco / a;
            return 0.0;
          case _CampoPreco.unidadeMedida:
            if (v.precoUnidadeMedida > 0) return v.precoUnidadeMedida;
            final c = comprimentoRef(v);
            if (v.preco > 0 && c != null && c > 0) return v.preco / c;
            return 0.0;
        }
      }).where((p) => p > 0).toList();

      if (precos.isEmpty) return null;
      if (estatistica == 'Mediana') {
        precos.sort();
        final n = precos.length;
        return n.isOdd
            ? precos[n ~/ 2]
            : (precos[n ~/ 2 - 1] + precos[n ~/ 2]) / 2;
      }
      return precos.reduce((a, b) => a + b) / precos.length;
    }

    if (campoOrigem != _CampoPreco.base) {
      final v = calcular(_CampoPreco.base);
      if (v != null) {
        mat.precoManualSelecionado = v;
        mat.origemPrecoManual = estatistica;
      }
    }
    if (campoOrigem != _CampoPreco.m2) {
      final v = calcular(_CampoPreco.m2);
      if (v != null) {
        mat.precoM2ManualSelecionado = v;
        mat.origemPrecoM2Manual = estatistica;
      }
    }
    if (campoOrigem != _CampoPreco.unidadeMedida) {
      final v = calcular(_CampoPreco.unidadeMedida);
      if (v != null) {
        mat.precoUnidadeMedidaManualSelecionado = v;
        mat.origemPrecoUnidadeMedidaManual = estatistica;
      }
    }
  } catch (_) {
  }
}

class _PrecoFornecedorSelecionado {
  final double preco;
  final String origem;
  final int? fornecedorId;
  const _PrecoFornecedorSelecionado({
    required this.preco,
    required this.origem,
    this.fornecedorId,
  });
}

enum _CampoPreco { base, m2, unidadeMedida }

class _PrecosFornecedoresDialog extends StatefulWidget {
  final int materialId;
  final _CampoPreco campo;
  final String titulo;
  final double? comprimentoReferencia;
  final double? larguraReferencia;

  const _PrecosFornecedoresDialog({
    required this.materialId,
    this.campo = _CampoPreco.base,
    this.titulo = 'Preços dos Fornecedores',
    this.comprimentoReferencia,
    this.larguraReferencia,
  });

  @override
  State<_PrecosFornecedoresDialog> createState() =>
      _PrecosFornecedoresDialogState();
}

class _PrecosFornecedoresDialogState extends State<_PrecosFornecedoresDialog> {
  bool _carregando = true;
  String? _erro;
  List<FornecedorModel> _fornecedores = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final prov = context.read<FornecedorProvider>();
      final lista = await prov.listarPorMaterial(widget.materialId);
      if (!mounted) return;
      setState(() {
        _fornecedores = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar preços dos fornecedores.';
        _carregando = false;
      });
    }
  }

  double? _comprimentoParaCalculo(FornecedorMaterialVinculoModel m) {
    if (m.materialComprimento != null && m.materialComprimento! > 0) {
      return m.materialComprimento;
    }
    return widget.comprimentoReferencia;
  }

  double? _larguraParaCalculo(FornecedorMaterialVinculoModel m) {
    if (m.materialLargura != null && m.materialLargura! > 0) {
      return m.materialLargura;
    }
    return widget.larguraReferencia;
  }

  double? _areaParaCalculo(FornecedorMaterialVinculoModel m) {
    final comp = _comprimentoParaCalculo(m);
    final larg = _larguraParaCalculo(m);
    if (comp == null || comp <= 0 || larg == null || larg <= 0) return null;
    return comp * larg;
  }

  double _precoDoVinculo(FornecedorMaterialVinculoModel m) {
    switch (widget.campo) {
      case _CampoPreco.m2:
        if (m.precoMetroQuadrado > 0) return m.precoMetroQuadrado;
        final area = _areaParaCalculo(m);
        if (m.preco > 0 && area != null && area > 0) {
          return m.preco / area;
        }
        return 0;
      case _CampoPreco.unidadeMedida:
        if (m.precoUnidadeMedida > 0) return m.precoUnidadeMedida;
        final comp = _comprimentoParaCalculo(m);
        if (m.preco > 0 && comp != null && comp > 0) {
          return m.preco / comp;
        }
        return 0;
      case _CampoPreco.base:
        return m.preco;
    }
  }

  bool _isPrecoCalculado(FornecedorMaterialVinculoModel m) {
    switch (widget.campo) {
      case _CampoPreco.m2:
        if (m.precoMetroQuadrado > 0) return false;
        final area = _areaParaCalculo(m);
        return m.preco > 0 && area != null && area > 0;
      case _CampoPreco.unidadeMedida:
        if (m.precoUnidadeMedida > 0) return false;
        final comp = _comprimentoParaCalculo(m);
        return m.preco > 0 && comp != null && comp > 0;
      case _CampoPreco.base:
        return false;
    }
  }

  List<double> get _precosValidos => _fornecedores
      .expand((f) => f.materiais.where((m) => m.materialId == widget.materialId))
      .map(_precoDoVinculo)
      .where((p) => p > 0)
      .toList();

  double? get _media {
    final precos = _precosValidos;
    if (precos.isEmpty) return null;
    return precos.reduce((a, b) => a + b) / precos.length;
  }

  double? get _mediana {
    final precos = List<double>.from(_precosValidos)..sort();
    if (precos.isEmpty) return null;
    final n = precos.length;
    if (n.isOdd) return precos[n ~/ 2];
    return (precos[n ~/ 2 - 1] + precos[n ~/ 2]) / 2;
  }

  void _selecionar(double preco, String origem, {int? fornecedorId}) {
    Navigator.pop(
      context,
      _PrecoFornecedorSelecionado(
        preco: preco,
        origem: origem,
        fornecedorId: fornecedorId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(
              titulo: widget.titulo,
              icon: Icons.storefront_rounded,
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _carregando
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _erro != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(_erro!,
                                style: GoogleFonts.nunito(
                                    fontSize: 13, color: AppTheme.error)),
                          )
                        : _precosValidos.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'Nenhum fornecedor com preço cadastrado para este material.',
                                  style: GoogleFonts.nunito(
                                      fontSize: 13, color: cs.onSurfaceVariant),
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _SectionLabel('Estatísticas'),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _EstatisticaCard(
                                            label: 'Média',
                                            valor: _media,
                                            icon: Icons.stacked_line_chart_rounded,
                                            onTap: _media != null
                                                ? () => _selecionar(_media!, 'Média')
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _EstatisticaCard(
                                            label: 'Mediana',
                                            valor: _mediana,
                                            icon: Icons.horizontal_rule_rounded,
                                            onTap: _mediana != null
                                                ? () => _selecionar(_mediana!, 'Mediana')
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    const _SectionLabel('Fornecedores'),
                                    const SizedBox(height: 8),
                                    for (final f in _fornecedores)
                                      for (final m in f.materiais.where((m) =>
                                          m.materialId == widget.materialId &&
                                          _precoDoVinculo(m) > 0))
                                        _FornecedorPrecoLinha(
                                          fornecedor: f,
                                          vinculo: m,
                                          precoExibido: _precoDoVinculo(m),
                                          calculado: _isPrecoCalculado(m),
                                          campo: widget.campo,
                                          onSelecionar: () => _selecionar(
                                              _precoDoVinculo(m), f.nomeFantasia,
                                              fornecedorId: f.id),
                                        ),
                                  ],
                                ),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstatisticaCard extends StatelessWidget {
  final String label;
  final double? valor;
  final IconData icon;
  final VoidCallback? onTap;

  const _EstatisticaCard({
    required this.label,
    required this.valor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Usar este valor no orçamento',
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant)),
                    Text(
                      valor != null ? _fmtBrl(valor!) : '—',
                      style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary),
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

class _FornecedorPrecoLinha extends StatelessWidget {
  final FornecedorModel fornecedor;
  final FornecedorMaterialVinculoModel vinculo;
  final double precoExibido;
  final bool calculado;
  final _CampoPreco campo;
  final VoidCallback onSelecionar;

  const _FornecedorPrecoLinha({
    required this.fornecedor,
    required this.vinculo,
    required this.precoExibido,
    this.calculado = false,
    this.campo = _CampoPreco.base,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onSelecionar,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.storefront_rounded,
                  size: 13, color: AppTheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fornecedor.nomeFantasia,
                      style: GoogleFonts.nunito(
                          fontSize: 12, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (fornecedor.tipoFornecedor != null &&
                      fornecedor.tipoFornecedor!.isNotEmpty)
                    Text(fornecedor.tipoFornecedor!,
                        style: GoogleFonts.nunito(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                  if (calculado)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calculate_outlined,
                            size: 11,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
                        const SizedBox(width: 3),
                        Text(
                            campo == _CampoPreco.m2
                                ? 'calculado (preço ÷ área)'
                                : 'calculado (preço ÷ comprimento)',
                            style: GoogleFonts.nunito(
                                fontSize: 9,
                                fontStyle: FontStyle.italic,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.8))),
                      ],
                    ),
                ],
              ),
            ),
            Text(
              _fmtBrl(precoExibido),
              style: GoogleFonts.nunito(
                  fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SelecionarProdutoDialog extends StatefulWidget {
  final List<ProdutoModel> produtos;

  const _SelecionarProdutoDialog({required this.produtos});

  @override
  State<_SelecionarProdutoDialog> createState() =>
      _SelecionarProdutoDialogState();
}

class _SelecionarProdutoDialogState extends State<_SelecionarProdutoDialog> {
  final _buscaCtrl = TextEditingController();
  late List<ProdutoModel> _filtrados;

  @override
  void initState() {
    super.initState();
    _filtrados = widget.produtos;
    _buscaCtrl.addListener(_filtrar);
  }

  void _filtrar() {
    final q = _buscaCtrl.text.toLowerCase();
    setState(() {
      _filtrados = q.isEmpty
          ? widget.produtos
          : widget.produtos
              .where((p) =>
                  p.nome.toLowerCase().contains(q) ||
                  (p.categoria?.toLowerCase().contains(q) ?? false))
              .toList();
    });
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          children: [
            _DialogHeader(
              titulo:  'Selecionar Produto',
              icon:    Icons.category_rounded,
              onClose: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _buscaCtrl,
                autofocus: true,
                style: GoogleFonts.nunito(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar produto',
                  hintStyle: GoogleFonts.nunito(
                      fontSize: 13, color: cs.onSurfaceVariant),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: cs.onSurfaceVariant),
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
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                ),
              ),
            ),
            Expanded(
              child: _filtrados.isEmpty
                  ? Center(
                      child: Text('Nenhum produto encontrado.',
                          style: GoogleFonts.nunito(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      itemCount: _filtrados.length,
                      itemBuilder: (_, i) {
                        final p = _filtrados[i];
                        return ListTile(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.category_rounded,
                                size: 14, color: AppTheme.primary),
                          ),
                          title: Text(p.nome,
                              style: GoogleFonts.nunito(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: p.categoria != null
                              ? Text(p.categoria!,
                                  style: GoogleFonts.nunito(fontSize: 11))
                              : null,
                          onTap: () => Navigator.pop(context, p),
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

class _SelecionarMaterialDialog extends StatefulWidget {
  final Set<int> idsExcluidos;

  const _SelecionarMaterialDialog({this.idsExcluidos = const {}});

  @override
  State<_SelecionarMaterialDialog> createState() =>
      _SelecionarMaterialDialogState();
}

class _SelecionarMaterialDialogState
    extends State<_SelecionarMaterialDialog> {
  final _buscaCtrl         = TextEditingController();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _buscar());
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
        _resultados = prov.materiais
            .where((m) => !widget.idsExcluidos.contains(m.id))
            .toList();
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
            _DialogHeader(
              titulo:  'Selecionar Material',
              icon:    Icons.inventory_2_outlined,
              onClose: () => Navigator.pop(context),
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
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                              if (m.unidade != null && m.unidade!.trim().isNotEmpty)
                                _formatarUnidade(m.unidade!.trim()),
                            ].join(' · ');
                            final custoUnitario = m.precoMediano;

                            return Material(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => Navigator.pop(context, m),
                                mouseCursor: SystemMouseCursors.click,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: cs.outlineVariant),
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
                                      if (custoUnitario != null)
                                        Text(
                                          _fmtBrl(custoUnitario),
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurfaceVariant),
                                        ),
                                      const SizedBox(width: 6),
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

class _BotaoVoltarOrcamento extends StatefulWidget {
  final VoidCallback onTap;

  const _BotaoVoltarOrcamento({required this.onTap});

  @override
  State<_BotaoVoltarOrcamento> createState() => _BotaoVoltarOrcamentoState();
}

class _BotaoVoltarOrcamentoState extends State<_BotaoVoltarOrcamento> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: 'Voltar',
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.primary.withValues(alpha: 0.08),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: _hovered ? 0.9 : 0.5),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Voltar',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
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

class _MaterialRascunho {
  final int materialId;
  final String nome;
  final String? unidade;
  final String? medida;
  final String? espessura;
  final String? identificador;
  double? custoUnitario;
  double? precoM2;
  double? precoUnidadeMedida;

  double? precoManualSelecionado;
  String? origemPrecoManual;
  double? precoM2ManualSelecionado;
  String? origemPrecoM2Manual;
  double? precoUnidadeMedidaManualSelecionado;
  String? origemPrecoUnidadeMedidaManual;

  final TextEditingController qtdCtrl;

  final double? refLargura;
  final double? refComprimento;

  final double? ultimoValorPago;

  final TextEditingController larguraCtrl;
  final TextEditingController comprimentoCtrl;

  _MaterialRascunho({
    required this.materialId,
    required this.nome,
    this.unidade,
    this.medida,
    this.espessura,
    this.identificador,
    this.custoUnitario,
    this.precoM2,
    this.precoUnidadeMedida,
    required this.qtdCtrl,
    this.refLargura,
    this.refComprimento,
    this.ultimoValorPago,
    TextEditingController? larguraCtrl,
    TextEditingController? comprimentoCtrl,
  })  : larguraCtrl  = larguraCtrl  ?? TextEditingController(),
        comprimentoCtrl = comprimentoCtrl ?? TextEditingController();

  bool get temDimensoes =>
      refLargura != null && refLargura! > 0 &&
      refComprimento != null && refComprimento! > 0;

  double get quantidade =>
      double.tryParse(qtdCtrl.text.replaceAll(',', '.')) ?? 0;

  double? get _largura =>
      double.tryParse(larguraCtrl.text.replaceAll(',', '.'));
  double? get _comprimento =>
      double.tryParse(comprimentoCtrl.text.replaceAll(',', '.'));

  double? get larguraDigitada  => _largura;
  double? get comprimentoDigitado => _comprimento;

  double? get custoPorM2 {
    if (!temDimensoes) return null;
    if (precoM2ManualSelecionado != null && precoM2ManualSelecionado! > 0) {
      return precoM2ManualSelecionado;
    }
    if (precoM2 != null && precoM2! > 0) return precoM2;
    final custo = _custoUnitarioEfetivo;
    if (custo == null || custo <= 0) return null;
    return custo / (refLargura! * refComprimento!);
  }

  double? get _precoUnidadeMedidaEfetivo {
    if (precoUnidadeMedidaManualSelecionado != null &&
        precoUnidadeMedidaManualSelecionado! > 0) {
      return precoUnidadeMedidaManualSelecionado;
    }
    return precoUnidadeMedida;
  }
  
  bool get _vendidoPorUnidadeMedida =>
      unidade != null && unidade!.trim().toLowerCase() != 'unidade';

  double? get _custoUnitarioEfetivo {
    if (custoUnitario != null && custoUnitario! > 0) return custoUnitario;
    if (ultimoValorPago != null && ultimoValorPago! > 0) return ultimoValorPago;
    return null;
  }

  double? get precoUnitarioCalculado {
    if (_vendidoPorUnidadeMedida) {
      // Materiais vendidos por unidade de medida (m/l, ml, g) SEMPRE usam
      // o preço por unidade de medida para compor o subtotal. Mesmo que
      // esse preço ainda não esteja definido (ex: material adicionado
      // avulso ao orçamento, sem vínculo original com o produto), não se
      // deve cair para o "Preço" simples/custo unitário como fallback:
      // isso fazia o subtotal ser calculado com um preço diferente do
      // exibido na coluna "Preço (m/l, ml, g)", que ficava vazia.
      return _precoUnidadeMedidaEfetivo;
    }
    final l = _largura;
    final c = _comprimento;
    if (temDimensoes && l != null && l > 0 && c != null && c > 0) {
      final cpm2 = custoPorM2;
      if (cpm2 != null) return cpm2 * l * c;
    }
    if (precoManualSelecionado != null && precoManualSelecionado! > 0) {
      return precoManualSelecionado;
    }
    return _custoUnitarioEfetivo;
  }

  double? get precoExibido =>
      (precoManualSelecionado != null && precoManualSelecionado! > 0)
          ? precoManualSelecionado
          : _custoUnitarioEfetivo;

  double? get precoM2Exibido {
    if (precoM2ManualSelecionado != null && precoM2ManualSelecionado! > 0) {
      return precoM2ManualSelecionado;
    }
    if (precoM2 != null && precoM2! > 0) return precoM2;
    return custoPorM2;
  }

  double? get precoUnidadeMedidaExibido =>
      (precoUnidadeMedidaManualSelecionado != null &&
              precoUnidadeMedidaManualSelecionado! > 0)
          ? precoUnidadeMedidaManualSelecionado
          : precoUnidadeMedida;

  double get subtotal => quantidade * (precoUnitarioCalculado ?? 0);

  double? get areaSobraM2 {
    if (!temDimensoes) return null;
    final l = _largura;
    final c = _comprimento;
    if (l == null || l <= 0 || c == null || c <= 0) return null;
    final areaRef    = refLargura! * refComprimento!;
    final areaCortada = l * c;
    if (areaCortada >= areaRef) return null;
    return areaRef - areaCortada;
  }

  double? get custoSobra {
    final sobra = areaSobraM2;
    if (sobra == null) return null;
    final cpm2 = custoPorM2;
    if (cpm2 == null || cpm2 <= 0) return null;
    return sobra * cpm2;
  }

  void dispose() {
    qtdCtrl.dispose();
    larguraCtrl.dispose();
    comprimentoCtrl.dispose();
  }
}

class _ItemRascunho {
  final int produtoId;
  final String produtoNome;
  final String? produtoCategoria;
  final List<_MaterialRascunho> materiais;

  _ItemRascunho({
    required this.produtoId,
    required this.produtoNome,
    this.produtoCategoria,
    required this.materiais,
  });

  double get subtotal => materiais.fold(0, (s, m) => s + m.subtotal);

  void dispose() {
    for (final m in materiais) {
      m.dispose();
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, cor) = switch (status) {
      'APROVADO'     => ('Aprovado', const Color(0xFF15803D)),
      'NAO_APROVADO' => ('Não aprovado', AppTheme.error),
      _              => ('Em andamento', const Color(0xFF2563EB)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: GoogleFonts.nunito(
              fontSize: 10, fontWeight: FontWeight.w700, color: cor)),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final IconData icon;
  final VoidCallback onClose;

  const _DialogHeader({
    required this.titulo,
    required this.icon,
    required this.onClose,
  }) : subtitulo = null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: cs.outline.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
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
                Text(titulo,
                    style: GoogleFonts.raleway(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                if (subtitulo != null && subtitulo!.isNotEmpty)
                  Text(subtitulo!,
                      style: GoogleFonts.nunito(
                          fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Tooltip(
            message: 'Fechar',
            child: IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 20, color: cs.onSurfaceVariant),
              onPressed: onClose,
              style: IconButton.styleFrom()
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            ),
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
  final bool enabled;

  const _Campo({
    required this.label,
    required this.ctrl,
    this.hint,
    this.maxLines = 1,
    this.enabled  = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.nunito(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          maxLines:   maxLines,
          enabled:    enabled,
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
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: cs.outline.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
            filled: true,
            fillColor: enabled ? cs.surface : cs.surfaceContainerLow,
          ),
        ),
      ],
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
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

String _fmtBrl(double v) {
  final dec = v.toStringAsFixed(2).split('.')[1];

  final intPart = v.truncate().abs().toString();
  final buf = StringBuffer();
  int cnt = 0;
  for (int i = intPart.length - 1; i >= 0; i--) {
    if (cnt > 0 && cnt % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
    cnt++;
  }
  final sinal = v < 0 ? '-' : '';
  return '${sinal}R\$ ${buf.toString().split('').reversed.join('')},$dec';
}

String _fmtQtd(double v) =>
    v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

String? _medidaFromDimensoes(double? comprimento, double? largura) {
  if (comprimento == null || largura == null) return null;
  if (comprimento <= 0 || largura <= 0) return null;
  return '${_fmtQtd(comprimento)}x${_fmtQtd(largura)}m';
}

String _fmtM2(double v) {
  final dec = v.toStringAsFixed(2).split('.')[1];
  return '${v.truncate()},$dec';
}