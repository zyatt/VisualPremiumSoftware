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
import '../repositories/configuracao_repository.dart';
import '../theme/app_theme.dart';

// ─── Página principal ─────────────────────────────────────────────────────────

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
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: prov),
            ChangeNotifierProvider.value(value: prodProv),
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
            // ── Cabeçalho ──────────────────────────────────────────────────
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
                  FilledButton.icon(
                    onPressed: () => _abrirEditor(null),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(isMobile ? 'Novo' : 'Novo Orçamento',
                        style: GoogleFonts.nunito(fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
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
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Busca ──────────────────────────────────────────────────────
            TextField(
              controller: _buscaCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por número ou cliente...',
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

            // ── Abas ───────────────────────────────────────────────────────
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

            // ── Listas ─────────────────────────────────────────────────────
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

// ─── Lista de orçamentos por aba ──────────────────────────────────────────────

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

// ─── Card de orçamento ────────────────────────────────────────────────────────

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

// ─── Página de editor ─────────────────────────────────────────────────────────
//
// Layout em duas colunas:
//   Esquerda  (280 px) → painel de produtos com busca e clique para selecionar
//   Direita   (flex)   → formulário (número*, cliente*, observação, materiais, total)
//
// Correções aplicadas:
//   1. clienteId é enviado no payload (não apenas clienteNome) para que o
//      backend conecte corretamente a relação Cliente no Prisma.
//   2. Campo "Nº do Orçamento" é editável e obrigatório (sem auto-geração).
//   3. Produtos ficam na coluna esquerda – busca + clique para selecionar.

class OrcamentoVendaEditorPage extends StatefulWidget {
  final OrcamentoVendaModel? inicial;

  const OrcamentoVendaEditorPage({super.key, this.inicial});

  @override
  State<OrcamentoVendaEditorPage> createState() =>
      _OrcamentoVendaEditorPageState();
}

class _OrcamentoVendaEditorPageState extends State<OrcamentoVendaEditorPage> {
  // ── Controladores do formulário ────────────────────────────────────────────
  final _numeroCtrl  = TextEditingController();
  final _obsCtrl     = TextEditingController();

  // ── Estado do cliente selecionado ──────────────────────────────────────────
  // Armazenamos tanto o id quanto o nome para exibição e envio ao backend.
  int?   _clienteId;
  String _clienteNome = '';

  // ── Busca de clientes (autocomplete) ──────────────────────────────────────
  final _clienteBuscaCtrl = TextEditingController();
  List<Map<String, dynamic>> _clientesSugeridos = [];
  bool _buscandoClientes = false;
  Timer? _debounceCliente;
  final _clienteLayerLink = LayerLink();
  OverlayEntry? _clienteOverlay;

  // ── Produto selecionado ────────────────────────────────────────────────────
  _ItemRascunho? _item;
  bool _salvando = false;

  // ── Markup: faixas carregadas da API ──────────────────────────────────────
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

  // ── Busca de produtos (painel esquerdo) ───────────────────────────────────
  final _produtoBuscaCtrl = TextEditingController();
  String _produtoBusca    = '';

  bool get _isEdit => widget.inicial != null;

  // ── Ciclo de vida ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final ov = widget.inicial;
    if (ov != null) {
      _numeroCtrl.text = ov.numero;
      _obsCtrl.text    = ov.observacao ?? '';
      _clienteNome     = ov.clienteNome ?? '';
      _clienteBuscaCtrl.text = _clienteNome;
      // clienteId não está exposto no model atual; será enviado null na edição
      // (o backend não altera o cliente na rota PUT conforme service.js)

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
            custoUnitario:   m.material.ultimoValorPago
                ?? m.material.precoMedio
                ?? m.precoMedio,
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
          )).toList(),
        );
      }
    }

    _produtoBuscaCtrl.addListener(() {
      setState(() => _produtoBusca = _produtoBuscaCtrl.text);
    });

    // Carrega produtos na abertura da página
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prodProv = context.read<ProdutoProvider>();
      if (prodProv.produtos.isEmpty) {
        await prodProv.carregar(ativo: true);
      }
      // Carrega faixas de markup para exibição em tempo real
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

  // ── Autocomplete de cliente ────────────────────────────────────────────────

  void _onClienteChanged(String valor) {
    // Ao digitar, limpa a seleção confirmada
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

  // ── Produto ────────────────────────────────────────────────────────────────

  List<_MaterialRascunho> _materiaisDeProducto(ProdutoModel produto) {
    return produto.materiais.map((pm) => _MaterialRascunho(
          materialId:     pm.materialId,
          nome:           pm.material.nome,
          unidade:        pm.material.unidade,
          medida:         pm.material.medida,
          espessura:      pm.material.espessura,
          identificador:  pm.material.identificador,
          custoUnitario:  pm.material.ultimoValorPago ?? pm.material.precoMedio,
          qtdCtrl:        TextEditingController(),
          refLargura:     pm.material.largura,
          refComprimento: pm.material.comprimento,
          ultimoValorPago: pm.material.ultimoValorPago,
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

    // Usa MaterialProvider para buscar TODOS os materiais do estoque
    final matProv = context.read<MaterialProvider>();
    if (matProv.materiais.isEmpty) {
      await matProv.carregar(ativo: true);
    }
    if (!mounted) return;

    final disponiveis = matProv.materiais
        .where((m) => m.ativo && !todosIds.contains(m.id))
        .toList();

    if (disponiveis.isEmpty) return;

    final selecionado = await showDialog<MaterialModel>(
      context: context,
      builder: (_) => _SelecionarMaterialDialog(materiais: disponiveis),
    );
    if (selecionado == null || !mounted) return;

    setState(() {
      _item!.materiais.add(_MaterialRascunho(
        materialId:      selecionado.id,
        nome:            selecionado.nome,
        unidade:         selecionado.unidade,
        medida:          selecionado.medida,
        espessura:       selecionado.espessura,
        identificador:   selecionado.identificador,
        custoUnitario:   selecionado.ultimoValorPago ?? selecionado.precoMediano,
        qtdCtrl:         TextEditingController(),
        refLargura:      selecionado.largura,
        refComprimento:  selecionado.comprimento,
        ultimoValorPago: selecionado.ultimoValorPago,
      ));
    });
  }

  // ── Validação e salvamento ─────────────────────────────────────────────────

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

    // ── Payload correto:
    //    • numero     → obrigatório, digitado pelo usuário
    //    • clienteId  → FK para a tabela Cliente (corrige o salvamento)
    //    • observacao → opcional
    //    • itens      → lista de produtos com materiais
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
            // precoUnitario = custo da peça com dimensões informadas (ou custo bruto)
            'precoUnitario': m.precoUnitarioCalculado,
            // precoMedio = custo bruto da unidade (fallback no backend para _decomporCustos)
            'precoMedio':    m.custoUnitario,
            'largura':       m._largura,
            'comprimento':   m._comprimento,
          }).toList(),
        }
      ],
    };
    final prov = context.read<OrcamentoVendaProvider>();

    if (_isEdit) {
      // Na edição não reenvia numero/clienteId (backend ignora, mas não quebra)
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

  // ── Build ──────────────────────────────────────────────────────────────────

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: () => Navigator.pop(context),
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
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary),
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
        ],
      ),

      // ── Corpo: coluna esquerda (produtos) + coluna direita (formulário) ───
      body: isMobile
          ? _buildFormulario(cs, isMobile: true)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Painel esquerdo: catálogo de produtos ──────────────────
                _PainelProdutos(
                  buscaCtrl:         _produtoBuscaCtrl,
                  busca:             _produtoBusca,
                  produtoSelecionado: _item?.produtoId,
                  onSelecionar:      _selecionarProduto,
                ),

                // Divisor vertical
                VerticalDivider(
                    width: 1,
                    color: cs.outline.withValues(alpha: 0.15)),

                // ── Formulário à direita ───────────────────────────────────
                Expanded(
                  child: _buildFormulario(cs, isMobile: false),
                ),
              ],
            ),
    );
  }

  // ── Formulário (coluna direita / tela inteira no mobile) ──────────────────

  Widget _buildFormulario(ColorScheme cs, {required bool isMobile}) {
    return ListView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      children: [
        // ── Dados básicos ──────────────────────────────────────────────────
        _SectionLabel('Dados do orçamento'),
        const SizedBox(height: 10),

        // Linha 1: Nº orçamento (obrigatório, editável) + Cliente
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Número — obrigatório, preenchido pelo usuário
            SizedBox(
              width: 160,
              child: _Campo(
                label:    'Nº do Orçamento *',
                ctrl:     _numeroCtrl,
                hint:     'Nº do Orçamento...',
                enabled:  !_isEdit, // número não pode ser alterado na edição
              ),
            ),
            const SizedBox(width: 12),

            // Cliente com autocomplete
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
          hint:     'Anotações opcionais...',
          maxLines: 2,
        ),

        const SizedBox(height: 28),

        // ── Produto selecionado (no mobile mostra o botão de selecionar) ───
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

        // Card do produto / placeholder
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

        // ── Total ──────────────────────────────────────────────────────────
        Builder(builder: (context) {
          final subtotalLocal  = _item?.subtotal ?? 0;
          final markupPct      = _percentualMarkupAtual;
          final totalComMarkup = _totalComMarkup;

          // Em edição sem mudanças locais ainda exibimos o valorTotal do servidor,
          // mas assim que o usuário alterar qualquer campo passamos a calcular local.
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

// ─── Painel esquerdo: catálogo de produtos ────────────────────────────────────

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
          // Cabeçalho do painel
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
                // Campo de busca
                TextField(
                  controller: buscaCtrl,
                  style: GoogleFonts.nunito(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar produto...',
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

          // Lista de produtos
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

// ─── Campo de autocomplete de cliente ────────────────────────────────────────

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
            Text('Cliente *',
                style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant)),
            const SizedBox(width: 6),
            // Indicador visual de cliente confirmado
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
                hintText: 'Digitar nome do cliente...',
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

// ─── Card de item no editor ───────────────────────────────────────────────────

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
          // Cabeçalho
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
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: cs.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemover,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Cabeçalho de colunas
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('Material',
                      style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)),
                ),
                // Larg. — mesma largura do campoNumerico (72) + padding (4 cada lado)
                SizedBox(
                  width: 80,
                  child: Text('Larg.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)),
                ),
                // Separador ×
                const SizedBox(width: 14),
                // Comp. — mesma largura do campoNumerico (72) + padding (4 cada lado)
                SizedBox(
                  width: 80,
                  child: Text('Comp.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)),
                ),
                const SizedBox(width: 4),
                // Qtd. — mesma largura do campoNumerico (72) + padding (4 cada lado)
                SizedBox(
                  width: 80,
                  child: Text('Qtd.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)),
                ),
                // Espaço da unidade
                const SizedBox(width: 34),
                // Custo unit.
                SizedBox(
                  width: 90,
                  child: Text('Custo unit.',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                // Subtotal
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

          // Linhas de materiais
          for (final m in item.materiais)
            _MaterialLinhaRascunho(mat: m, onQtdChanged: onQtdChanged),

          // Botão material extra
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Linha de material (campos de dimensão + quantidade) ──────────────────────

class _MaterialLinhaRascunho extends StatelessWidget {
  final _MaterialRascunho mat;
  final VoidCallback onQtdChanged;

  const _MaterialLinhaRascunho({
    required this.mat,
    required this.onQtdChanged,
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
          // Nome + detalhes do material
          Expanded(
            flex: 3,
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
                if ([mat.identificador, mat.medida, mat.espessura]
                    .any((v) => v != null && v.isNotEmpty))
                  Text(
                    [
                      if (mat.identificador != null && mat.identificador!.isNotEmpty)
                        mat.identificador!,
                      if (mat.medida != null && mat.medida!.isNotEmpty)
                        mat.medida!,
                      if (mat.espessura != null && mat.espessura!.isNotEmpty)
                        mat.espessura!,
                    ].join(' · '),
                    style: GoogleFonts.nunito(
                        fontSize: 10, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Campos de dimensão — sempre exibidos; cálculo por m² só é aplicado
          // quando o material tem dimensões de referência cadastradas.
          campoNumerico(
            ctrl: mat.larguraCtrl,
            hint: 'Larg.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('×',
                style: GoogleFonts.nunito(
                    fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          campoNumerico(
            ctrl: mat.comprimentoCtrl,
            hint: 'Comp.',
          ),
          const SizedBox(width: 4),

          // Campo quantidade
          campoNumerico(
            ctrl: mat.qtdCtrl,
            hint: 'Qtd.',
          ),

          // Unidade — largura fixa para não deslocar colunas seguintes
          SizedBox(
            width: 34,
            child: mat.unidade != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      mat.unidade!,
                      style: GoogleFonts.nunito(
                          fontSize: 10, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : null,
          ),

          // Custo unitário (custo bruto da unidade/chapa)
          SizedBox(
            width: 90,
            child: Text(
              mat.custoUnitario != null
                  ? _fmtBrl(mat.custoUnitario!)
                  : '—',
              textAlign: TextAlign.right,
              style: GoogleFonts.nunito(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Subtotal
          SizedBox(
            width: 100,
            child: Text(
              mat.custoUnitario != null && mat.qtdCtrl.text.isNotEmpty
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

        // ── Linha de sobra ────────────────────────────────────────────────
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
                children: [
                  const Icon(Icons.content_cut_rounded,
                      size: 12, color: Color(0xFF92400E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Sobra: ${_fmtM2(mat.areaSobraM2!)} m² '
                      '(${_fmtQtd(mat.refLargura!)} × ${_fmtQtd(mat.refComprimento!)} '
                      '− ${_fmtQtd(mat.larguraDigitada!)} × ${_fmtQtd(mat.comprimentoDigitado!)})',
                      style: GoogleFonts.nunito(
                          fontSize: 10,
                          color: const Color(0xFF92400E)),
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

// ─── Dialog selecionar produto (fallback mobile) ──────────────────────────────

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
                  hintText: 'Buscar produto...',
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

// ─── Dialog selecionar material extra ────────────────────────────────────────

class _SelecionarMaterialDialog extends StatefulWidget {
  final List<MaterialModel> materiais;

  const _SelecionarMaterialDialog({required this.materiais});

  @override
  State<_SelecionarMaterialDialog> createState() =>
      _SelecionarMaterialDialogState();
}

class _SelecionarMaterialDialogState
    extends State<_SelecionarMaterialDialog> {
  late List<MaterialModel> _filtrados;
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtrados = widget.materiais;
    _buscaCtrl.addListener(_filtrar);
  }

  void _filtrar() {
    final q = _buscaCtrl.text.toLowerCase();
    setState(() {
      _filtrados = q.isEmpty
          ? widget.materiais
          : widget.materiais.where((m) {
              return m.nome.toLowerCase().contains(q) ||
                  (m.identificador?.toLowerCase().contains(q) ?? false) ||
                  (m.medida?.toLowerCase().contains(q) ?? false) ||
                  (m.categoria?.toLowerCase().contains(q) ?? false);
            }).toList();
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
              titulo:  'Selecionar Material',
              icon:    Icons.inventory_2_outlined,
              onClose: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _buscaCtrl,
                autofocus: true,
                style: GoogleFonts.nunito(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por nome, código ou medida...',
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
                      child: Text('Nenhum material encontrado',
                          style: GoogleFonts.nunito(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      itemCount: _filtrados.length,
                      itemBuilder: (_, i) {
                        final m = _filtrados[i];
                        final detalhes = [
                          if (m.identificador != null && m.identificador!.isNotEmpty)
                            m.identificador!,
                          if (m.medida != null && m.medida!.isNotEmpty) m.medida!,
                          if (m.espessura != null && m.espessura!.isNotEmpty)
                            m.espessura!,
                          if (m.unidade != null && m.unidade!.isNotEmpty) m.unidade!,
                        ].join(' · ');
                        final custoUnitario =
                            m.ultimoValorPago ?? m.precoMediano;
                        return ListTile(
                          dense: true,
                          title: Text(m.nome,
                              style: GoogleFonts.nunito(fontSize: 13)),
                          subtitle: detalhes.isNotEmpty
                              ? Text(detalhes,
                                  style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant))
                              : null,
                          trailing: custoUnitario != null
                              ? Text(
                                  _fmtBrl(custoUnitario),
                                  style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant),
                                )
                              : null,
                          onTap: () => Navigator.pop(context, m),
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

// ─── Rascunhos internos ───────────────────────────────────────────────────────

class _MaterialRascunho {
  final int materialId;
  final String nome;
  final String? unidade;
  final String? medida;
  final String? espessura;
  final String? identificador;
  /// Custo bruto da unidade/chapa (nunca o precoUnitario calculado).
  final double? custoUnitario;
  final TextEditingController qtdCtrl;

  // Dimensões de referência da chapa (do cadastro do material)
  final double? refLargura;
  final double? refComprimento;
  // Custo da chapa inteira (último valor pago)
  final double? ultimoValorPago;

  // Campos de dimensão preenchidos pelo usuário no orçamento
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
    required this.qtdCtrl,
    this.refLargura,
    this.refComprimento,
    this.ultimoValorPago,
    TextEditingController? larguraCtrl,
    TextEditingController? comprimentoCtrl,
  })  : larguraCtrl  = larguraCtrl  ?? TextEditingController(),
        comprimentoCtrl = comprimentoCtrl ?? TextEditingController();

  /// True quando o material tem dimensões de referência cadastradas —
  /// ativa os campos de largura/comprimento no orçamento.
  bool get temDimensoes =>
      refLargura != null && refLargura! > 0 &&
      refComprimento != null && refComprimento! > 0;

  double get quantidade =>
      double.tryParse(qtdCtrl.text.replaceAll(',', '.')) ?? 0;

  double? get _largura =>
      double.tryParse(larguraCtrl.text.replaceAll(',', '.'));
  double? get _comprimento =>
      double.tryParse(comprimentoCtrl.text.replaceAll(',', '.'));

  /// Públicos para uso no widget de exibição de sobra.
  double? get larguraDigitada  => _largura;
  double? get comprimentoDigitado => _comprimento;

  /// Custo por m² calculado a partir das dimensões de referência e último custo.
  double? get custoPorM2 {
    if (!temDimensoes) return null;
    final custo = ultimoValorPago ?? custoUnitario;
    if (custo == null || custo <= 0) return null;
    return custo / (refLargura! * refComprimento!);
  }

  /// Preço unitário de 1 peça com as dimensões informadas pelo usuário.
  /// Se o usuário não preencheu as dimensões, usa custoUnitario diretamente.
  double? get precoUnitarioCalculado {
    final l = _largura;
    final c = _comprimento;
    if (temDimensoes && l != null && l > 0 && c != null && c > 0) {
      final cpm2 = custoPorM2;
      if (cpm2 != null) return cpm2 * l * c;
    }
    return custoUnitario;
  }

  double get subtotal => quantidade * (precoUnitarioCalculado ?? 0);

  /// Área da sobra em m²: (área da chapa de referência) − (área cortada pelo usuário).
  /// Só existe quando o material tem dimensões de referência E o usuário preencheu
  /// as dimensões da peça desejada.
  double? get areaSobraM2 {
    if (!temDimensoes) return null;
    final l = _largura;
    final c = _comprimento;
    if (l == null || l <= 0 || c == null || c <= 0) return null;
    final areaRef    = refLargura! * refComprimento!;
    final areaCortada = l * c;
    if (areaCortada >= areaRef) return null; // sem sobra
    return areaRef - areaCortada;
  }

  /// Custo monetário da sobra (parte que vai para o lixo).
  double? get custoSobra {
    final sobra = areaSobraM2;
    if (sobra == null) return null;
    final cpm2 = custoPorM2;
    if (cpm2 == null || cpm2 <= 0) return null;
    return sobra * cpm2 * quantidade;
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

// ─── Widgets de apoio ─────────────────────────────────────────────────────────

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
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _fmtBrl(double v) {
  // Usa até 5 casas decimais, remove zeros à direita, mantém mínimo 2
  String dec = v.toStringAsFixed(5).split('.')[1];
  while (dec.length > 2 && dec.endsWith('0')) {
    dec = dec.substring(0, dec.length - 1);
  }
  // ✅ CORREÇÃO: truncate() garante que a parte inteira nunca é arredondada
  final intPart = v.truncate().toString();
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

String _fmtM2(double v) {
  // Exibe até 4 casas, remove zeros à direita, mantém mínimo 2
  String dec = v.toStringAsFixed(4).split('.')[1];
  while (dec.length > 2 && dec.endsWith('0')) {
    dec = dec.substring(0, dec.length - 1);
  }
  return '${v.truncate()},$dec';
}