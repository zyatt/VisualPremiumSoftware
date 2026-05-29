import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/ordem_compra_model.dart';
import '../models/fornecedor_model.dart';
import '../providers/ordem_compra_provider.dart';
import '../providers/estoque_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../repositories/ordem_compra_repository.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────

class OrdemCompraPage extends StatefulWidget {
  /// Quando informado, abre automaticamente os detalhes desta OC ao entrar na página.
  final int? ocIdParaAbrir;

  const OrdemCompraPage({super.key, this.ocIdParaAbrir});

  @override
  State<OrdemCompraPage> createState() => _OrdemCompraPageState();
}

class _OrdemCompraPageState extends State<OrdemCompraPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _buscaNumeroCtrl = TextEditingController();
  String _filtroBuscaNumero = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<OrdemCompraProvider>();
      await provider.carregar();
      // Garante que o status das OS está atualizado para o bloqueio de finalização
      if (mounted) {
        await context.read<EstoqueProvider>().carregarRelacoesOS();
      }
      if (!mounted) return;

      // Se veio do orçamento com um ID de OC, abre os detalhes automaticamente
      final idAlvo = widget.ocIdParaAbrir;
      if (idAlvo != null) {
        final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
        final raw = todas.cast<dynamic>().firstWhere(
          (o) {
            final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
            return m.id == idAlvo;
          },
          orElse: () => null,
        );
        if (raw != null && mounted) {
          _verDetalhes(context, raw);
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaNumeroCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _filtrar(List<dynamic> lista) {
    final q = _filtroBuscaNumero.trim();
    if (q.isEmpty) return lista;
    return lista.where((o) {
      final raw = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
      return raw.id.toString().contains(q);
    }).toList();
  }

  Future<void> _abrirCriacaoOC() async {
    final resultado = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => const NovaOrdemCompraPage()),
    );
    // resultado pode ser OrdemCompraModel (novo fluxo) ou bool true (fallback)
    if (resultado != null && mounted) {
      context.read<OrdemCompraProvider>().carregar();
    }
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
            // ── Cabeçalho ──────────────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ordens de Compra',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Consumer<OrdemCompraProvider>(
                      builder: (_, p, __) {
                        final total = p.emAndamento.length + p.finalizadas.length + p.canceladas.length;
                        return Text(
                          '$total ${total == 1 ? 'ordem' : 'ordens'} no total',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textSecondary),
                        );
                      },
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _abrirCriacaoOC,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nova OC'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => context.read<OrdemCompraProvider>().carregar(),
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

            // ── Busca por número da OC ──────────────────────────────────────
            TextField(
              controller: _buscaNumeroCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar pelo número da OC...',
                prefixIcon: const Icon(Icons.tag, color: AppTheme.textHint, size: 18),
                isDense: true,
                suffixIcon: _filtroBuscaNumero.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: AppTheme.textHint),
                        onPressed: () {
                          _buscaNumeroCtrl.clear();
                          setState(() => _filtroBuscaNumero = '');
                        },
                      )
                    : null,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => setState(() => _filtroBuscaNumero = v),
            ),
            const SizedBox(height: 16),

            // ── Abas ───────────────────────────────────────────────────────
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
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'Em Andamento'),
                  Tab(text: 'Finalizadas'),
                  Tab(text: 'Canceladas'),
                ],
              ),
            ),

            // ── Lista ──────────────────────────────────────────────────────
            Expanded(
              child: Consumer<OrdemCompraProvider>(
                builder: (context, provider, _) {
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
                          const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                          const SizedBox(height: 12),
                          Text(provider.erro!),
                          TextButton(
                            onPressed: () => provider.carregar(),
                            child: const Text('Tentar novamente',
                                style: TextStyle(color: AppTheme.primary)),
                          ),
                        ],
                      ),
                    );
                  }

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _OcList(
                        ordens: _filtrar(provider.emAndamento),
                        statusColor: AppTheme.primary,
                        emptyMessage: 'Nenhuma ordem em andamento',
                        onFinalizar: (id) => _confirmarFinalizar(context, provider, id),
                        onCancelar: (id) => _confirmarCancelar(context, provider, id),
                        onEditar: (ordem) => _abrirEdicao(context, ordem),
                        onAbrirPdf: (ordem) => _abrirPdf(ordem),
                        onTap: (ordem) => _verDetalhes(context, ordem),
                        mostrarAcoes: true,
                      ),
                      _OcList(
                        ordens: _filtrar(provider.finalizadas),
                        statusColor: AppTheme.success,
                        emptyMessage: 'Nenhuma ordem finalizada',
                        onTap: (ordem) => _verDetalhes(context, ordem),
                        onReverter: (id) => _confirmarReverter(context, provider, id),
                        onAbrirPdf: (ordem) => _abrirPdf(ordem),
                        mostrarAcoes: false,
                        mostrarReverter: true,
                      ),
                      _OcList(
                        ordens: _filtrar(provider.canceladas),
                        statusColor: AppTheme.error,
                        emptyMessage: 'Nenhuma ordem cancelada',
                        onTap: (ordem) => _verDetalhes(context, ordem),
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

  void _verDetalhes(BuildContext context, dynamic ordem) async {
    final model = ordem is OrdemCompraModel
        ? ordem
        : OrdemCompraModel.fromJson(ordem as Map<String, dynamic>);
    final recarregar = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrdemCompraDetalhePage(ordem: model)),
    );
    if (recarregar == true && mounted) {
      // ignore: use_build_context_synchronously
      context.read<OrdemCompraProvider>().carregar();
    }
  }

  /// Exibe dialog de bloqueio quando uma ou mais OS da OC já estão fechadas.
  void _mostrarDialogOSFechada(BuildContext context, List<String> osBloqueadas) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_outline, color: AppTheme.error, size: 22),
          SizedBox(width: 8),
          Text('OS Fechada', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não é possível finalizar esta OC porque ${osBloqueadas.length == 1 ? 'a seguinte OS já foi fechada' : 'as seguintes OS já foram fechadas'} no controle de estoque:',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: osBloqueadas.map((os) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                ),
                child: Text(os, style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13)),
              )).toList(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Para prosseguir, reabra essa OS no controle de estoque antes de finalizar a OC.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _confirmarFinalizar(
      BuildContext context, OrdemCompraProvider provider, int id) {
    final ordem = provider.emAndamento.firstWhere(
      (o) {
        final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
        return m.id == id;
      },
      orElse: () => null,
    );
    if (ordem != null) {
      final model = ordem is OrdemCompraModel ? ordem : OrdemCompraModel.fromJson(ordem as Map<String, dynamic>);
      if (model.itens.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não é possível finalizar uma OC sem itens.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      // ── Verifica OS fechadas ──────────────────────────────────────────────
      final osFechadas = context.read<EstoqueProvider>().numerosOSFechadas;
      final osBloqueadas = model.numerosOS
          .where((os) => osFechadas.contains(os))
          .toList();
      if (osBloqueadas.isNotEmpty) {
        _mostrarDialogOSFechada(context, osBloqueadas);
        return;
      }
      // ─────────────────────────────────────────────────────────────────────
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Ordem'),
        content: const Text(
            'Ao finalizar, os itens serão adicionados ao estoque. Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.finalizar(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Ordem finalizada com sucesso!'),
                      backgroundColor: AppTheme.success),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
  }

  void _confirmarCancelar(
      BuildContext context, OrdemCompraProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Ordem'),
        content: const Text(
            'Tem certeza que deseja cancelar esta ordem de compra?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Voltar',
                  style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.cancelar(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Ordem cancelada.'),
                      backgroundColor: AppTheme.error),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Cancelar OC'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirPdf(OrdemCompraModel ordem) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );
    try {
      final bytes = await OrdemCompraRepository().baixarPdf(ordem.id);

      // Monta nome: "OC_42_FORNECEDOR NOME.pdf" → sanitiza caracteres inválidos
      final fornecedor = (ordem.fornecedorNome ?? 'FORNECEDOR')
          .toUpperCase()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = 'OC_${ordem.id}_$fornecedor.pdf';

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      // Abre o arquivo no visualizador/navegador padrão do sistema
      if (Platform.isWindows) {
        await Process.run('explorer', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _abrirEdicao(BuildContext context, dynamic ordem) async {
    final model = ordem is OrdemCompraModel
        ? ordem
        : OrdemCompraModel.fromJson(ordem as Map<String, dynamic>);
    final atualizado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditarOrdemCompraPage(ordem: model)),
    );
    if (atualizado == true && mounted) {
      // ignore: use_build_context_synchronously
      context.read<OrdemCompraProvider>().carregar();
    }
  }

  void _confirmarReverter(
      BuildContext context, OrdemCompraProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverter Ordem Finalizada'),
        content: const Text(
            'Esta ação irá desfazer a finalização: os itens serão removidos do estoque e a ordem voltará para "Em Andamento". Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Voltar',
                  style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await provider.reverter(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Ordem revertida para Em Andamento.'),
                        backgroundColor: AppTheme.primary),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIST WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _OcList extends StatelessWidget {
  final List<dynamic> ordens;
  final Color statusColor;
  final String emptyMessage;
  final void Function(dynamic)? onTap;
  final void Function(int)? onFinalizar;
  final void Function(int)? onCancelar;
  final void Function(dynamic)? onEditar;
  final void Function(int)? onReverter;
  final void Function(OrdemCompraModel)? onAbrirPdf;
  final bool mostrarAcoes;
  final bool mostrarReverter;

  const _OcList({
    required this.ordens,
    required this.statusColor,
    required this.emptyMessage,
    this.onTap,
    this.onFinalizar,
    this.onCancelar,
    this.onEditar,
    this.onReverter,
    this.onAbrirPdf,
    required this.mostrarAcoes,
    this.mostrarReverter = false,
  });

  @override
  Widget build(BuildContext context) {
    if (ordens.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text(emptyMessage,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: ordens.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        try {
          final raw = ordens[i];
          final model = raw is OrdemCompraModel
              ? raw
              : OrdemCompraModel.fromJson(raw as Map<String, dynamic>);
          return _OcCard(
            ordem: model,
            statusColor: statusColor,
            mostrarAcoes: mostrarAcoes,
            mostrarReverter: mostrarReverter,
            onTap: () => onTap?.call(model),
            onFinalizar: () => onFinalizar?.call(model.id),
            onCancelar: () => onCancelar?.call(model.id),
            onEditar: () => onEditar?.call(model),
            onReverter: () => onReverter?.call(model.id),
            onAbrirPdf: () => onAbrirPdf?.call(model),
          );
        } catch (e) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.error)),
            child: Text('Erro ao carregar ordem: $e', style: const TextStyle(color: AppTheme.error, fontSize: 12)),
          );
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD
// ─────────────────────────────────────────────────────────────────────────────

class _OcCard extends StatefulWidget {
  final OrdemCompraModel ordem;
  final Color statusColor;
  final bool mostrarAcoes;
  final bool mostrarReverter;
  final VoidCallback onTap;
  final VoidCallback onFinalizar;
  final VoidCallback onCancelar;
  final VoidCallback? onEditar;
  final VoidCallback? onReverter;
  final VoidCallback? onAbrirPdf;

  const _OcCard({
    required this.ordem,
    required this.statusColor,
    required this.mostrarAcoes,
    this.mostrarReverter = false,
    required this.onTap,
    required this.onFinalizar,
    required this.onCancelar,
    this.onEditar,
    this.onReverter,
    this.onAbrirPdf,
  });

  @override
  State<_OcCard> createState() => _OcCardState();
}

class _OcCardState extends State<_OcCard> {
  bool _hovered = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final ordem = widget.ordem;
    final statusColor = widget.statusColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit: _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFFFF9800).withValues(alpha: 0.06)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              // Barra colorida lateral esquerda
              Positioned(
                left: 0, top: 0, bottom: 0, width: 4,
                child: ColoredBox(color: statusColor),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 16, top: 16, bottom: 16),
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'OC #${ordem.id} — ${ordem.fornecedorNome ?? 'Fornecedor'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  _formatMoeda(ordem.valorTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(Icons.person_outline, ordem.requisitante,
                    AppTheme.textSecondary),
                _chip(Icons.calendar_today_outlined, _formatData(ordem.data),
                    AppTheme.textSecondary),
                if (ordem.empresa != null)
                  _chip(Icons.business_outlined, ordem.empresa!,
                      AppTheme.textSecondary),
              ],
            ),
            if (ordem.numerosOS.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: ordem.numerosOS
                    .map((os) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(os,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
            if (widget.mostrarAcoes) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onAbrirPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.divider),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onEditar,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onCancelar,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.onFinalizar,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Finalizar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.mostrarReverter) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onAbrirPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.divider),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onReverter,
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Reverter'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      side: const BorderSide(color: Color(0xFFB45309)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  String _formatData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatMoeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE DETALHE DA OC
// ─────────────────────────────────────────────────────────────────────────────

class OrdemCompraDetalhePage extends StatefulWidget {
  final OrdemCompraModel ordem;
  const OrdemCompraDetalhePage({super.key, required this.ordem});
  @override
  State<OrdemCompraDetalhePage> createState() => OrdemCompraDetalhePageState();
}

class OrdemCompraDetalhePageState extends State<OrdemCompraDetalhePage> {
  late OrdemCompraModel _ordem;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _ordem = widget.ordem;
  }

  Future<void> _confirmarFinalizar() async {
    // ── Verifica OS fechadas antes de abrir o diálogo de confirmação ─────────
    final osFechadas = context.read<EstoqueProvider>().numerosOSFechadas;
    final osBloqueadas = _ordem.numerosOS
        .where((os) => osFechadas.contains(os))
        .toList();
    if (osBloqueadas.isNotEmpty) {
      if (!mounted) return;
      showDialog(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.lock_outline, color: AppTheme.error, size: 22),
            SizedBox(width: 8),
            Text('OS Fechada', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Não é possível finalizar esta OC porque ${osBloqueadas.length == 1 ? 'a seguinte OS já foi fechada' : 'as seguintes OS já foram fechadas'} no controle de estoque:',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: osBloqueadas.map((os) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Text(os, style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13)),
                )).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Para prosseguir, reabra essa OS no controle de estoque antes de finalizar a OC.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Ordem'),
        content: const Text('Ao finalizar, os itens serão adicionados ao estoque. Confirmar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppTheme.success), child: const Text('Finalizar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _processando = true);
    // ignore: use_build_context_synchronously
    final provider = context.read<OrdemCompraProvider>();
    try {
      await provider.finalizar(_ordem.id);
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordem finalizada com sucesso!'), backgroundColor: AppTheme.success));
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _confirmarCancelar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Ordem'),
        content: const Text('Tem certeza que deseja cancelar esta ordem de compra?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar', style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppTheme.error), child: const Text('Cancelar OC')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _processando = true);
    // ignore: use_build_context_synchronously
    final provider = context.read<OrdemCompraProvider>();
    try {
      await provider.cancelar(_ordem.id);
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordem cancelada.'), backgroundColor: AppTheme.error));
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _confirmarReverter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverter Ordem Finalizada'),
        content: const Text('Esta ação irá desfazer a finalização: os itens serão removidos do estoque e a ordem voltará para "Em Andamento". Confirmar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar', style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _processando = true);
    // ignore: use_build_context_synchronously
    final provider = context.read<OrdemCompraProvider>();
    try {
      await provider.reverter(_ordem.id);
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordem revertida para Em Andamento.'), backgroundColor: AppTheme.primary));
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _abrirEdicao() async {
    final atualizado = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _EditarOrdemCompraPage(ordem: _ordem)));
    if (atualizado == true && mounted) {
      await context.read<OrdemCompraProvider>().carregar();
      if (!mounted) return;
      final provider = context.read<OrdemCompraProvider>();
      final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
      final raw = todas.firstWhere((o) {
        final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
        return m.id == _ordem.id;
      }, orElse: () => _ordem);
      if (mounted) setState(() { _ordem = raw; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final emAndamento = _ordem.status == 'EM_ANDAMENTO';
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ──────────────────────────────────────────────────
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
                        Text('Ordens de Compra', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text('OC #${_ordem.id}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
                const SizedBox(width: 10),
                _statusBadge(_ordem.status),
                const Spacer(),
                IconButton(
                  onPressed: _recarregar,
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
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
        children: [
          _secaoCard('Informações Gerais', Icons.info_outline, [
            _infoRow(Icons.business_outlined, 'Fornecedor', _ordem.fornecedorNome ?? '—'),
            _infoRow(Icons.person_outline, 'Requisitante', _ordem.requisitante.isEmpty ? '—' : _ordem.requisitante),
            _infoRow(Icons.apartment_outlined, 'Empresa', _ordem.empresa ?? '—'),
            _infoRow(Icons.calendar_today_outlined, 'Data', _formatData(_ordem.data)),
            _infoRow(Icons.payment_outlined, 'Forma de Pagamento', _ordem.formaPagamento ?? '—'),
            _infoRow(Icons.schedule_outlined, 'Prazo de Pagamento', _ordem.prazoPagamento ?? '—'),
            if (_ordem.observacoes != null && _ordem.observacoes!.isNotEmpty)
              _infoRow(Icons.notes_outlined, 'Observações', _ordem.observacoes!),
          ]),
          const SizedBox(height: 16),
          if (_ordem.numerosOS.isNotEmpty) ...[
            _secaoCard('Números de OS', Icons.assignment_outlined, [
              Wrap(spacing: 6, runSpacing: 6, children: _ordem.numerosOS.map((os) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                child: Text(os, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
              )).toList()),
            ]),
            const SizedBox(height: 16),
          ],
          _secaoCard('Itens (${_ordem.itens.length})', Icons.inventory_2_outlined, [
            ..._ordem.itens.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.surfaceVariant, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.divider)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.materialNome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
                        if (item.descricaoItem != null && item.descricaoItem!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.descricaoItem!,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text('R\$ ${item.precoTotal.toStringAsFixed(2).replaceAll('.', ',')}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primary)),
                ]),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _itemChip(Icons.assignment_outlined, 'OS: ${item.numeroOS}'),
                    _itemChip(
                      Icons.format_list_numbered,
                      item.usarM2
                          ? 'Qtd (m²): ${item.quantidade}'
                          : 'Qtd: ${item.quantidade}',
                    ),
                   _itemChipDestaque(
                      Icons.attach_money,
                      item.precoUnitario > 0
                          ? 'Unitário: R\$ ${item.precoUnitario.toStringAsFixed(2).replaceAll('.', ',')}'
                          : 'Unitário: —',
                      ativo: !item.usarM2,
                    ),
                    _itemChipDestaque(
                      Icons.square_foot,
                      item.precoMetroQuadrado != null && item.precoMetroQuadrado! > 0
                          ? 'm²: R\$ ${item.precoMetroQuadrado!.toStringAsFixed(2).replaceAll('.', ',')}'
                          : 'm²: —',
                      ativo: item.usarM2,
                    ),
                  ],
                ),
              ]),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                Text('R\$ ${_ordem.valorTotal.toStringAsFixed(2).replaceAll('.', ',')}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.primary)),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          if (emAndamento) ...[
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _processando ? null : _confirmarCancelar,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancelar OC'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error), padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(
                onPressed: _processando ? null : _confirmarFinalizar,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Finalizar OC'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.success, padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _processando ? null : _abrirEdicao,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar Ordem de Compra'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary, side: const BorderSide(color: AppTheme.primary), padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
            const SizedBox(height: 24),
          ],
          if (_ordem.status == 'FINALIZADO') ...[
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _processando ? null : _confirmarReverter,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Reverter Finalização'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                side: const BorderSide(color: Color(0xFFB45309)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )),
            const SizedBox(height: 24),
          ],
        ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recarregar() async {
    await context.read<OrdemCompraProvider>().carregar();
    if (!mounted) return;
    final provider = context.read<OrdemCompraProvider>();
    final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
    final atualizada = todas.cast<OrdemCompraModel>().where((o) => o.id == _ordem.id).firstOrNull;
    if (atualizada != null && mounted) setState(() => _ordem = atualizada);
  }

  Widget _secaoCard(String titulo, IconData icon, List<Widget> children) => Container(
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.divider)),
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 16, color: AppTheme.primary), const SizedBox(width: 6), Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary))]),
      const SizedBox(height: 12),
      const Divider(height: 1, color: AppTheme.divider),
      const SizedBox(height: 12),
      ...children,
    ]),
  );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: AppTheme.textHint),
      const SizedBox(width: 8),
      SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary))),
    ]),
  );

  Widget _itemChip(IconData icon, String label) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textHint),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemChipDestaque(
    IconData icon,
    String label, {
    required bool ativo,
  }) {
    if (!ativo) {
      return SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.textHint),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return IntrinsicHeight(
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.primary),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg, fg; String label;
    switch (status) {
      case 'EM_ANDAMENTO': bg = AppTheme.primary.withValues(alpha: 0.10); fg = AppTheme.primary; label = 'Em Andamento'; break;
      case 'FINALIZADO': bg = const Color(0xFFF0FDF4); fg = AppTheme.success; label = 'Finalizada'; break;
      default: bg = const Color(0xFFFEF2F2); fg = AppTheme.error; label = 'Cancelada';
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)), child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)));
  }

  String _formatData(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE EDIÇÃO DA OC
// ─────────────────────────────────────────────────────────────────────────────

class _EditarOrdemCompraPage extends StatefulWidget {
  final OrdemCompraModel ordem;
  const _EditarOrdemCompraPage({required this.ordem});
  @override
  State<_EditarOrdemCompraPage> createState() => _EditarOrdemCompraPageState();
}

class _EditarOrdemCompraPageState extends State<_EditarOrdemCompraPage> {
  late DateTime _data;
  late final TextEditingController _requisitanteCtrl;
  late final TextEditingController _formaPagamentoCtrl;
  late final TextEditingController _prazoPagamentoCtrl;
  late final TextEditingController _observacoesCtrl;
  late String? _empresa;
  late List<String> _numerosOS;
  late List<_ItemRascunho> _itens;
  FornecedorModel? _fornecedor;
  bool _salvando = false;

  List<FornecedorMaterialVinculoModel> get _materiaisDoFornecedor =>
      _fornecedor?.materiais ?? [];

  @override
  void initState() {
    super.initState();
    _data = widget.ordem.data;
    _empresa = widget.ordem.empresa;
    _numerosOS = List<String>.from(widget.ordem.numerosOS);
    _itens = widget.ordem.itens.map((i) => _ItemRascunho(
      materialId: i.materialId,
      materialNome: i.materialNome,
      descricaoItem: i.descricaoItem,
      materialEspecifico: i.materialEspecifico,
      numeroOS: i.numeroOS,
      quantidade: i.quantidade,
      precoUnitario: i.precoUnitario,
      precoMetroQuadrado: i.precoMetroQuadrado,
      usarM2: i.usarM2,
    )).toList();
    _requisitanteCtrl = TextEditingController(text: widget.ordem.requisitante);
    _formaPagamentoCtrl = TextEditingController(text: widget.ordem.formaPagamento ?? '');
    _prazoPagamentoCtrl = TextEditingController(text: widget.ordem.prazoPagamento ?? '');
    _observacoesCtrl = TextEditingController(text: widget.ordem.observacoes ?? '');
    _carregarFornecedor();
  }

  Future<void> _carregarFornecedor() async {
    final f = await context.read<FornecedorProvider>().buscarPorId(widget.ordem.fornecedorId);
    if (mounted) {
      setState(() {
        _fornecedor = f;
        // Reavalia materialEspecifico com base no vínculo real do fornecedor,
        // garantindo que itens específicos sem descrição prévia exibam o campo.
        if (f != null) {
          for (final item in _itens) {
            final vinculo = f.materiais.cast<FornecedorMaterialVinculoModel?>().firstWhere(
              (m) => m?.materialId == item.materialId,
              orElse: () => null,
            );
            if (vinculo != null) {
              item.materialEspecifico = vinculo.materialEspecifico;
            }
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _requisitanteCtrl.dispose();
    _formaPagamentoCtrl.dispose();
    _prazoPagamentoCtrl.dispose();
    _observacoesCtrl.dispose();
    super.dispose();
  }

  Future<void> _selecionarFornecedor() async {
    final provider = context.read<FornecedorProvider>();
    final selected = await showDialog<FornecedorModel>(
      context: context,
      builder: (_) => _FornecedorPicker(provider: provider),
    );
    if (selected != null) {
      final completo = await provider.buscarPorId(selected.id);
      if (mounted) {
        setState(() {
        _fornecedor = completo ?? selected;
        _itens.clear();
      });
      }
    }
  }

  Future<void> _selecionarData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _data = d);
  }

  void _adicionarItem(FornecedorMaterialVinculoModel vinculo) {
    final osAuto = _numerosOS.length == 1 ? _numerosOS.first : '';
    setState(() {
      _itens.add(_ItemRascunho(
        materialId:         vinculo.materialId,
        materialNome:       vinculo.descricaoCompleta,
        materialEspecifico: vinculo.materialEspecifico,
        numeroOS:           osAuto,
        quantidade:         1,
        precoUnitario:      vinculo.preco,
        precoMetroQuadrado:
            vinculo.precoMetroQuadrado > 0 ? vinculo.precoMetroQuadrado : null,
        usarM2:             false,
      ));
    });
  }

  void _removerItem(int idx) => setState(() => _itens.removeAt(idx));

  void _showAdicionarItem() {
    showDialog(
      context: context,
      builder: (_) => _MaterialPickerDialog(
        materiais: _materiaisDoFornecedor,
        onConfirmar: (lista) {
          for (final v in lista) {
            _adicionarItem(v);
          }
        },
      ),
    );
  }

  Future<void> _salvar() async {
    if (_fornecedor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um fornecedor.'), backgroundColor: AppTheme.error));
      return;
    }
    if (_numerosOS.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos um número de OS.'), backgroundColor: AppTheme.error));
        return;
     }
    for (final item in _itens) {
      if (item.numeroOS.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atribua uma OS para todos os itens.'), backgroundColor: AppTheme.error));
        return;
      }
    }
    for (final item in _itens) {
      if (item.usarM2) {
        if (item.precoMetroQuadrado == null || item.precoMetroQuadrado! <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preencha o preço m² de todos os itens.'),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }
      } else {
        if (item.precoUnitario <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preencha o preço unitário de todos os itens.'),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }
      }
    }
    setState(() => _salvando = true);
    try {
      await context.read<OrdemCompraProvider>().atualizar(widget.ordem.id, {
        'data': _data.toUtc().toIso8601String(),
        'fornecedorId': _fornecedor!.id,
        'requisitante': _requisitanteCtrl.text.trim(),
        'formaPagamento': _formaPagamentoCtrl.text.trim().isEmpty ? null : _formaPagamentoCtrl.text.trim(),
        'prazoPagamento': _prazoPagamentoCtrl.text.trim().isEmpty ? null : _prazoPagamentoCtrl.text.trim(),
        'observacoes': _observacoesCtrl.text.trim().isEmpty ? null : _observacoesCtrl.text.trim(),
        'empresa': _empresa,
        'numerosOS': _numerosOS,
        'itens': _itens.map((i) => {
          'materialId': i.materialId,
          'descricaoItem': i.descricaoItem,
          'numeroOS': i.numeroOS,
          'quantidade': i.quantidade,
          'precoUnitario': i.usarM2 ? null : i.precoUnitario,
          'precoMetroQuadrado': i.usarM2 ? i.precoMetroQuadrado : null,
          'usarM2': i.usarM2,
        }).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordem atualizada com sucesso!'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 14),
    filled: true, fillColor: AppTheme.surfaceVariant,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.divider)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.divider)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
  );

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTheme.textSecondary,
    ),
  );

  Widget _card({ required String titulo, String? subtitulo, required List<Widget> children, Widget? trailing }) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.divider)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textPrimary)),
            if (subtitulo != null) ...[
              const SizedBox(height: 2),
              Text(subtitulo, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ])),
          if (trailing != null) trailing,
        ]),
        if (children.isNotEmpty) ...[const SizedBox(height: 14), ...children],
      ]),
    );
  }

  Widget _empresaOption(String value, String label) {
    final selected = _empresa == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _empresa = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.06) : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider, width: selected ? 1.5 : 1),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? AppTheme.primary : AppTheme.textSecondary)),
            const SizedBox(height: 6),
            Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? AppTheme.primary : AppTheme.textHint, size: 20),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary), onPressed: () => Navigator.of(context).pop()),
        title: Text('Editar OC #${widget.ordem.id}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16), child: FilledButton(
            onPressed: _salvando ? null : _salvar,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _salvando ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w700)),
          )),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Dados gerais ────────────────────────────────────────────────────
        _card(titulo: 'Dados da Ordem de Compra', children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Número da OC'),
              InputDecorator(
                decoration: _deco('').copyWith(
                  prefixIcon: const Icon(Icons.tag, size: 18, color: AppTheme.textHint),
                  suffixText: 'Fixo',
                  suffixStyle: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                child: Text('#${widget.ordem.id}', style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Data'),
              InkWell(
                onTap: _selecionarData,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: _deco('').copyWith(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.textHint)),
                  child: Text(
                    '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                  ),
                ),
              ),
            ])),
          ]),
          const SizedBox(height: 14),

          _label('Fornecedor'),
          InkWell(
            onTap: _selecionarFornecedor,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _deco('Buscar fornecedor...').copyWith(prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textHint)),
              child: Text(
                _fornecedor?.nomeFantasia ?? widget.ordem.fornecedorNome ?? '',
                style: TextStyle(fontSize: 14, color: _fornecedor == null ? AppTheme.textHint : AppTheme.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 14),

          _label('Requisitante'),
          TextFormField(controller: _requisitanteCtrl, decoration: _deco('Nome do requisitante')),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Forma de Pagamento'),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: TextFormField(
                        controller: _formaPagamentoCtrl,
                        decoration: _deco(
                          'Ex: Boleto, À Vista, Crédito...',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Prazo de Pagamento'),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: TextFormField(
                        controller: _prazoPagamentoCtrl,
                        decoration: _deco(
                          'Ex: 30 dias, 15/30/45...',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _label('Observações'),
          TextFormField(controller: _observacoesCtrl, decoration: _deco('Observações gerais'), maxLines: 3),
        ]),
        const SizedBox(height: 16),

        // ── Empresa ──────────────────────────────────────────────────────────
        _card(
          titulo: 'Empresa',
          subtitulo: 'Selecione a empresa que irá efetuar a ordem de compra.',
          children: [
            Row(children: [
              _empresaOption('VISUAL PREMIUM', 'Visual Premium'),
              const SizedBox(width: 12),
              _empresaOption('VISUAL GUINDASTE', 'Visual Guindaste'),
            ]),
          ],
        ),
        const SizedBox(height: 16),

        // ── Números de OS ─────────────────────────────────────────────────────
        _OsInputSection(
          numerosOS: _numerosOS,
          onChanged: () {
            setState(() {
              // Se agora existe mais de uma OS,
              // força o usuário a selecionar novamente
              if (_numerosOS.length > 1) {
                for (final item in _itens) {
                  item.numeroOS = '';
                }
              }
            });
          },    
        ),
        const SizedBox(height: 16),

        // ── Itens ─────────────────────────────────────────────────────────────
        _card(
          titulo: 'Itens (${_itens.length})',
          trailing: _fornecedor != null && _materiaisDoFornecedor.isNotEmpty
              ? FilledButton.icon(
                  onPressed: _showAdicionarItem,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Adicionar Item'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                )
              : null,
          children: [
            if (_fornecedor == null)
              const Text('Selecione um fornecedor para adicionar itens.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))
            else if (_materiaisDoFornecedor.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Text('Este fornecedor não possui materiais vinculados.',
                    style: TextStyle(color: Color(0xFF92400E), fontSize: 13)),
              )
            else if (_itens.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: const Center(
                  child: Text(
                    'Nenhum item adicionado. Você pode salvar a OC sem itens.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else ...[
              ..._itens.asMap().entries.map((e) => _ItemFormCard(
                key: ValueKey(e.key),
                item: e.value,
                numerosOS: _numerosOS,
                onRemover: () => _removerItem(e.key),
                onChanged: () => setState(() {}),
              )),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    Text(
                      'R\$ ${_itens.fold(0.0, (s, i) => s + i.precoTotal).toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _salvando ? null : _salvar,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: _salvando
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Salvar Alterações', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE CRIAÇÃO DE NOVA OC (navegação dedicada)
// ─────────────────────────────────────────────────────────────────────────────

/// Dados de um item de orçamento a serem pré-carregados na nova OC.
class ItemPreCarregadoOC {
  final int materialId;
  final String materialNome;
  final double quantidade;
  final double precoUnitario;
  final bool materialEspecifico;
  final double? precoMetroQuadrado;
  final bool usarM2;
  final String? descricao;

  ItemPreCarregadoOC({
    required this.materialId,
    required this.materialNome,
    required this.quantidade,
    required this.precoUnitario,
    this.precoMetroQuadrado,
    this.usarM2 = false,
    this.descricao,
    this.materialEspecifico = false,
  });
}

class NovaOrdemCompraPage extends StatefulWidget {
  /// Quando vindo do orçamento, lista de itens pré-carregados.
  final List<ItemPreCarregadoOC> itensPreCarregados;
  /// Quando vindo do orçamento, fornecedor já selecionado.
  final FornecedorModel? fornecedorInicial;

  const NovaOrdemCompraPage({
    super.key,
    this.itensPreCarregados = const [],
    this.fornecedorInicial,
  });

  @override
  State<NovaOrdemCompraPage> createState() => NovaOrdemCompraPageState();
}

class NovaOrdemCompraPageState extends State<NovaOrdemCompraPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = OrdemCompraRepository();

  DateTime _data = DateTime.now();
  FornecedorModel? _fornecedor;
  final _requisitanteCtrl    = TextEditingController();
  final _formaPagamentoCtrl  = TextEditingController();
  final _prazoPagamentoCtrl  = TextEditingController();
  final _observacoesCtrl     = TextEditingController();
  String? _empresa;
  final List<String> _numerosOS = [];
  final List<_ItemRascunho> _itens = [];
  bool _salvando = false;
  int? _proximoId;

  List<FornecedorMaterialVinculoModel> get _materiaisDoFornecedor =>
      _fornecedor?.materiais ?? [];

  @override
  void initState() {
    super.initState();
    _carregarProximoId();

    // Pré-preencher fornecedor e itens quando vindo do orçamento
    if (widget.fornecedorInicial != null) {
      _fornecedor = widget.fornecedorInicial;
    }
    for (final item in widget.itensPreCarregados) {
      _itens.add(_ItemRascunho(
        materialId:         item.materialId,
        materialNome:       item.materialNome,
        materialEspecifico: item.materialEspecifico,
        numeroOS:           '',
        quantidade:         item.quantidade,
        precoUnitario:      item.precoUnitario,
        precoMetroQuadrado: item.precoMetroQuadrado,
        usarM2:             item.usarM2,
        descricaoItem:      item.descricao,
      ));
    }
  }

  Future<void> _carregarProximoId() async {
    final id = await _repo.proximoId();
    if (mounted) setState(() => _proximoId = id);
  }

  @override
  void dispose() {
    _requisitanteCtrl.dispose();
    _formaPagamentoCtrl.dispose();
    _prazoPagamentoCtrl.dispose();
    _observacoesCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fornecedor == null) {
      _showErro('Selecione um fornecedor.');
      return;
    }
    if (_empresa == null) {
      _showErro('Selecione a empresa.');
      return;
    }

    if (_numerosOS.isEmpty) {
      _showErro('Adicione ao menos um número de OS.');
      return;
    }

    for (final item in _itens) {
      if (item.numeroOS.isEmpty) {
        _showErro('Atribua uma OS para todos os itens.');
        return;
      }
    }
    for (final item in _itens) {
      if (item.usarM2) {
        if (item.precoMetroQuadrado == null || item.precoMetroQuadrado! <= 0) {
          _showErro('Preencha o preço m² de todos os itens.');
          return;
        }
      } else {
        if (item.precoUnitario <= 0) {
          _showErro('Preencha o preço unitário de todos os itens.');
          return;
        }
      }
    }

    setState(() => _salvando = true);
    try {
      await context.read<OrdemCompraProvider>().criar({
        'data': _data.toUtc().toIso8601String(),
        'fornecedorId': _fornecedor!.id,
        'requisitante': _requisitanteCtrl.text.trim(),
        'formaPagamento': _formaPagamentoCtrl.text.trim().isEmpty
            ? null
            : _formaPagamentoCtrl.text.trim(),
        'prazoPagamento': _prazoPagamentoCtrl.text.trim().isEmpty
            ? null
            : _prazoPagamentoCtrl.text.trim(),
        'observacoes': _observacoesCtrl.text.trim().isEmpty
            ? null
            : _observacoesCtrl.text.trim(),
        'empresa': _empresa,
        'numerosOS': _numerosOS,
        'itens': _itens
            .map((i) => {
                  'materialId': i.materialId,
                  'descricaoItem': i.descricaoItem,
                  'numeroOS': i.numeroOS,
                  'quantidade': i.quantidade,
                  'precoUnitario': i.usarM2 ? null : i.precoUnitario,
                  'precoMetroQuadrado': i.usarM2 ? i.precoMetroQuadrado : null,
                  'usarM2': i.usarM2,
                })
            .toList(),
      });

      if (!mounted) return;

      // Recarrega a lista para obter o model da OC recém-criada
      final provider = context.read<OrdemCompraProvider>();
      await provider.carregar();

      if (!mounted) return;

      OrdemCompraModel? ocCriada;
      // Busca pelo ID esperado (carregado antes de salvar)
      if (_proximoId != null) {
        final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
        final raw = todas.cast<dynamic>().firstWhere(
          (o) {
            if (o == null) return false;
            final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
            return m.id == _proximoId;
          },
          orElse: () => null,
        );
        if (raw != null) {
          ocCriada = raw is OrdemCompraModel
              ? raw
              : OrdemCompraModel.fromJson(raw as Map<String, dynamic>);
        }
      }
      // Fallback: a mais recente em andamento
      ocCriada ??= provider.emAndamento.isNotEmpty
          ? (provider.emAndamento.first is OrdemCompraModel
              ? provider.emAndamento.first as OrdemCompraModel
              : OrdemCompraModel.fromJson(provider.emAndamento.first as Map<String, dynamic>))
          : null;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ordem de compra criada com sucesso!'),
            backgroundColor: AppTheme.success),
      );
      // Retorna o OrdemCompraModel para que o chamador possa navegar para detalhes
      Navigator.of(context).pop(ocCriada ?? true);
    } catch (e) {
      _showErro(e.toString());
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _showErro(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.error));
  }

  void _adicionarItem(FornecedorMaterialVinculoModel vinculo) {
    // Se há exatamente 1 OS cadastrada, preenche automaticamente
    final osAuto = _numerosOS.length == 1 ? _numerosOS.first : '';
    setState(() {
      _itens.add(_ItemRascunho(
        materialId:         vinculo.materialId,
        materialNome:       vinculo.descricaoCompleta,
        materialEspecifico: vinculo.materialEspecifico,
        numeroOS:           osAuto,
        quantidade:         1,
        precoUnitario:      vinculo.preco,
        precoMetroQuadrado:
            vinculo.precoMetroQuadrado > 0 ? vinculo.precoMetroQuadrado : null,
        usarM2:             false,
      ));
    });
  }

  void _removerItem(int idx) {
    setState(() => _itens.removeAt(idx));
  }

  Future<void> _selecionarFornecedor() async {
    final provider = context.read<FornecedorProvider>();
    final selected = await showDialog<FornecedorModel>(
      context: context,
      builder: (_) => _FornecedorPicker(provider: provider),
    );
    if (selected != null) {
      final completo = await provider.buscarPorId(selected.id);
      if (mounted) {
        setState(() {
          _fornecedor = completo ?? selected;
          _itens.clear();
        });
      }
    }
  }

  Future<void> _selecionarData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _data = d);
  }

  void _showAdicionarItem() {
    final disponiveis = _materiaisDoFornecedor;
    showDialog(
      context: context,
      builder: (_) => _MaterialPickerDialog(
        materiais: disponiveis,
        onConfirmar: (lista) {
          for (final v in lista) {
            _adicionarItem(v);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.itensPreCarregados.isNotEmpty
              ? 'Nova OC — do Orçamento'
              : 'Nova Ordem de Compra',
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppTheme.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _salvando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Criar OC',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Banner: itens vindos do orçamento ──────────────────────────
            if (widget.itensPreCarregados.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.itensPreCarregados.length} '
                        '${widget.itensPreCarregados.length == 1 ? 'item importado' : 'itens importados'} '
                        'do orçamento. Adicione o número de OS e salve.',
                        style: const TextStyle(fontSize: 13, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // ── Dados da OC ────────────────────────────────────────────────
            _card(
              titulo: 'Dados da Ordem de Compra',
              children: [
                // Número OC (automático) + Data lado a lado
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Número da OC'),
                          InputDecorator(
                            decoration: _deco('').copyWith(
                              prefixIcon: const Icon(Icons.tag,
                                  size: 18, color: AppTheme.textHint),
                              suffixText: 'Automático',
                              suffixStyle: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                            child: Text(
                              _proximoId != null ? '$_proximoId' : '—',
                              style: TextStyle(
                                color: _proximoId != null ? AppTheme.textPrimary : AppTheme.textHint,
                                fontSize: 14,
                              )
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Data'),
                          InkWell(
                            onTap: _selecionarData,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: _deco('').copyWith(
                                suffixIcon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                    color: AppTheme.textHint),
                              ),
                              child: Text(
                                '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Fornecedor
                _label('Fornecedor principal'),
                InkWell(
                  onTap: _selecionarFornecedor,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: _deco('Buscar fornecedor...').copyWith(
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: AppTheme.textHint),
                    ),
                    child: Text(
                      _fornecedor?.nomeFantasia ?? '',
                      style: TextStyle(
                          fontSize: 14,
                          color: _fornecedor == null
                              ? AppTheme.textHint
                              : AppTheme.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Requisitante
                _label('Requisitante'),
                TextFormField(
                  controller: _requisitanteCtrl,
                  decoration: _deco('Nome do requisitante'),
                ),
                const SizedBox(height: 14),

                // Forma de Pagamento + Prazo lado a lado
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Forma de Pagamento'),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 48,
                            child: TextFormField(
                              controller: _formaPagamentoCtrl,
                              decoration: _deco(
                                'Ex: Boleto, À Vista, Crédito...',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Prazo de Pagamento'),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 48,
                            child: TextFormField(
                              controller: _prazoPagamentoCtrl,
                              decoration: _deco(
                                'Ex: 30 dias, 15/30/45...',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Observações
                _label('Observações'),
                TextFormField(
                  controller: _observacoesCtrl,
                  decoration: _deco('Observações gerais'),
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Empresa ────────────────────────────────────────────────────
            _card(
              titulo: 'Empresa',
              subtitulo:
                  'Selecione a empresa que aparecerá no cabeçalho da Ordem de Compra:',
              children: [
                Row(
                  children: [
                    _empresaOption('VISUAL PREMIUM', 'Visual Premium'),
                    const SizedBox(width: 12),
                    _empresaOption('VISUAL GUINDASTE', 'Visual Guindaste'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Números de OS ──────────────────────────────────────────────
            _OsInputSection(
              numerosOS: _numerosOS,
              onChanged: () {
                setState(() {
                  // Se agora existe mais de uma OS,
                  // força o usuário a selecionar novamente
                  if (_numerosOS.length > 1) {
                    for (final item in _itens) {
                      item.numeroOS = '';
                    }
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // ── Itens ──────────────────────────────────────────────────────
            _card(
              titulo: 'Itens',
              trailing: _fornecedor != null &&
                      _materiaisDoFornecedor.isNotEmpty
                  ? FilledButton.icon(
                      onPressed: _showAdicionarItem,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Adicionar Item'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    )
                  : null,
              children: [
                if (_fornecedor == null)
                  _aviso(
                      'Selecione um fornecedor para ver os materiais disponíveis.')
                else if (_materiaisDoFornecedor.isEmpty)
                  _aviso('Este fornecedor não possui materiais vinculados.')
                else if (_itens.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: const Center(
                      child: Text(
                          'Nenhum item adicionado. Você pode salvar a OC sem itens.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  ),
                ..._itens.asMap().entries.map((e) {
                  final idx = e.key;
                  final item = e.value;
                  return _ItemFormCard(
                    key: ValueKey('${item.materialId}_$idx'),
                    item: item,
                    numerosOS: _numerosOS,
                    onRemover: () => _removerItem(idx),
                    onChanged: () => setState(() {}),
                  );
                }),
                if (_itens.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                        Text(
                          'R\$ ${_itens.fold(0.0, (s, i) => s + i.precoTotal).toStringAsFixed(2).replaceAll('.', ',')}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),

            // ── Botão salvar (rodapé) ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _salvando ? null : _salvar,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _salvando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Criar Ordem de Compra',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card({
    required String titulo,
    String? subtitulo,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppTheme.textPrimary)),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitulo,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...children,
          ],
        ],
      ),
    );
  }

  Widget _empresaOption(String value, String label) {
    final selected = _empresa == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _empresa = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.06)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: selected ? AppTheme.primary : AppTheme.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aviso(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFCD34D)),
        ),
        child: Text(msg,
            style: const TextStyle(
                color: Color(0xFF92400E), fontSize: 13)),
      );

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTheme.textSecondary,
    ),
  );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppTheme.textHint, fontSize: 14),
        filled: true,
        fillColor: AppTheme.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO DE NÚMEROS DE OS (campos fixos + botão +)
// ─────────────────────────────────────────────────────────────────────────────

class _OsInputSection extends StatefulWidget {
  final List<String> numerosOS;
  final VoidCallback onChanged;

  const _OsInputSection({required this.numerosOS, required this.onChanged});

  @override
  State<_OsInputSection> createState() => _OsInputSectionState();
}

class _OsInputSectionState extends State<_OsInputSection> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    // Cria os 3 campos padrão aqui dentro (não na declaração da classe)
    _controllers = [
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
    ];
    // Se já há valores pré-existentes (modo edição), preenche os campos
    for (int i = 0; i < widget.numerosOS.length; i++) {
      if (i < _controllers.length) {
        _controllers[i].text = widget.numerosOS[i];
      } else {
        _controllers.add(TextEditingController(text: widget.numerosOS[i]));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _sincronizar() {
    final novos = _controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    widget.numerosOS
      ..clear()
      ..addAll(novos);
    // Adia o setState do pai para depois do frame atual, evitando
    // "setState called during build"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged();
    });
  }

  void _adicionarCampo() {
    setState(() => _controllers.add(TextEditingController()));
  }

  void _removerCampo(int idx) {
    setState(() {
      _controllers[idx].dispose();
      _controllers.removeAt(idx);
    });
    _sincronizar();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 14),
        filled: true,
        fillColor: AppTheme.surfaceVariant,
        prefixIcon: const Icon(Icons.assignment_outlined, size: 18, color: AppTheme.textHint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final hasValue = _controllers.any((c) => c.text.trim().isNotEmpty);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: !hasValue ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.divider,
          width: !hasValue ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Números de OS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textPrimary)),
            const Text(' *', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Preencha ao menos uma OS. Se houver apenas uma, ela será atribuída automaticamente aos itens.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),

          // Atalhos rápidos
          Wrap(
            spacing: 8,
            children: [
              _atalho('Empresa', () {
                // Preenche o primeiro campo vazio ou adiciona
                final idx = _controllers.indexWhere((c) => c.text.trim().isEmpty);
                if (idx != -1) {
                  setState(() => _controllers[idx].text = 'EMPRESA');
                } else {
                  setState(() => _controllers.add(TextEditingController(text: 'EMPRESA')));
                }
                _sincronizar();
              }),
              _atalho('Outros', () {
                final idx = _controllers.indexWhere((c) => c.text.trim().isEmpty);
                if (idx != -1) {
                  setState(() => _controllers[idx].text = 'OUTROS');
                } else {
                  setState(() => _controllers.add(TextEditingController(text: 'OUTROS')));
                }
                _sincronizar();
              }),
            ],
          ),
          const SizedBox(height: 12),

          // Campos de OS
          ...List.generate(_controllers.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _controllers[i],
                      decoration: _deco('OS ${i + 1}'),
                      onChanged: (_) => _sincronizar(),
                    ),
                  ),
                  if (_controllers.length > 1) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => _removerCampo(i),
                      icon: const Icon(Icons.remove_circle_outline, color: AppTheme.error, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Remover campo',
                    ),
                  ],
                ],
              ),
            );
          }),

          // Botão adicionar campo
          TextButton.icon(
            onPressed: _adicionarCampo,
            icon: const Icon(Icons.add, size: 18, color: AppTheme.primary),
            label: const Text('Adicionar campo de OS', style: TextStyle(color: AppTheme.primary, fontSize: 13)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }

  Widget _atalho(String label, VoidCallback onTap) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: AppTheme.primary,
      side: const BorderSide(color: AppTheme.primary),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    child: Text(label),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RASCUNHO DE ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _ItemRascunho {
  int materialId;
  String materialNome;
  /// Indica se o material é específico (exige descrição personalizada na OC).
  bool? materialEspecifico;
  /// Descrição personalizada na OC (ex: "Tinta Branca Fosca 18L").
  String? descricaoItem;
  String numeroOS;
  double quantidade;
  double precoUnitario;
  double? precoMetroQuadrado;
  /// Se true, o total é calculado como quantidade × precoMetroQuadrado;
  /// caso contrário, quantidade × precoUnitario.
  bool usarM2;

  _ItemRascunho({
    required this.materialId,
    required this.materialNome,
    this.materialEspecifico,
    this.descricaoItem,
    required this.numeroOS,
    required this.quantidade,
    this.precoUnitario = 0,
    this.precoMetroQuadrado,
    this.usarM2 = false,
  });

  double get precoTotal {
    if (usarM2 && precoMetroQuadrado != null && precoMetroQuadrado! > 0) {
      return quantidade * precoMetroQuadrado!;
    }
    return quantidade * precoUnitario;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ITEM FORM CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ItemFormCard extends StatefulWidget {
  final _ItemRascunho item;
  final List<String> numerosOS;
  final VoidCallback onRemover;
  final VoidCallback onChanged;

  const _ItemFormCard({
    super.key,
    required this.item,
    required this.numerosOS,
    required this.onRemover,
    required this.onChanged,
  });

  @override
  State<_ItemFormCard> createState() => _ItemFormCardState();
}

class _ItemFormCardState extends State<_ItemFormCard> {
  late TextEditingController _qtdCtrl;
  late TextEditingController _precoCtrl;
  late TextEditingController _precoM2Ctrl;
  late TextEditingController _descricaoCtrl;

  @override
  void initState() {
    super.initState();
    _qtdCtrl = TextEditingController(
        text: widget.item.quantidade
            .toStringAsFixed(widget.item.quantidade % 1 == 0 ? 0 : 2));
    _precoCtrl = TextEditingController(
        text: widget.item.precoUnitario.toStringAsFixed(2));
    _precoM2Ctrl = TextEditingController(
        text: widget.item.precoMetroQuadrado?.toStringAsFixed(2) ?? '');
    _descricaoCtrl = TextEditingController(
        text: widget.item.descricaoItem ?? '');
  }

  @override
  void didUpdateWidget(covariant _ItemFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se passou a ter exatamente 1 OS, sincroniza automaticamente
    if (widget.numerosOS.length == 1 && widget.item.numeroOS != widget.numerosOS.first) {
      widget.item.numeroOS = widget.numerosOS.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged();
      });
    }
  }

  @override
  void dispose() {
    _qtdCtrl.dispose();
    _precoCtrl.dispose();
    _precoM2Ctrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppTheme.textHint, fontSize: 12),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final total = widget.item.precoTotal;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.item.materialNome,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary)),
              ),
              IconButton(
                onPressed: widget.onRemover,
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.error, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Descrição adicional (somente para materiais específicos) ──────────
          if (widget.item.materialEspecifico == true) ...[
            const Text(
              'Descrição adicional',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _descricaoCtrl,
              decoration: _deco('Descrição do material...'),
              onChanged: (v) {
                widget.item.descricaoItem = v.trim().isEmpty ? null : v.trim();
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
          ],
          if (widget.numerosOS.isNotEmpty) ...[
            const Text('OS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            if (widget.numerosOS.length == 1)
              // 1 OS: exibe como badge, sem precisar escolher
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.assignment_outlined, size: 14, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      widget.numerosOS.first,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: widget.item.numeroOS.isNotEmpty &&
                        widget.numerosOS.contains(widget.item.numeroOS)
                    ? widget.item.numeroOS
                    : null,
                decoration: _deco('Selecione a OS'),
                items: widget.numerosOS
                    .map((os) =>
                        DropdownMenuItem(value: os, child: Text(os)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => widget.item.numeroOS = v);
                    widget.onChanged();
                  }
                },
              ),
            const SizedBox(height: 8),
          ] else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Adicione números de OS acima',
                  style:
                      TextStyle(fontSize: 12, color: Color(0xFF92400E))),
            ),
          const SizedBox(height: 8),
          // ── Seletor de modo de cálculo ───────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Modo de cálculo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _ModoCalculo(
                        label: 'Qtd × Preço Unitário.',
                        ativo: !widget.item.usarM2,
                        onTap: () {
                          setState(() => widget.item.usarM2 = false);
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModoCalculo(
                        label: 'Qtd × m²',
                        ativo: widget.item.usarM2,
                        onTap: () {
                          setState(() => widget.item.usarM2 = true);
                          widget.onChanged();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        widget.item.usarM2 ? 'Quantidade (m²)' : 'Quantidade',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _qtdCtrl,
                      decoration: _deco('0'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'))
                      ],
                      onChanged: (v) {
                        widget.item.quantidade =
                            double.tryParse(v) ?? 0;
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Preço Unitário.',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary)),
                        if (!widget.item.usarM2) ...[
                          const SizedBox(width: 4),
                          const _BadgeAtivo(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _precoCtrl,
                      enabled: !widget.item.usarM2,  // ← adicionar
                      decoration: _deco('0.00').copyWith(
                        fillColor: widget.item.usarM2 ? AppTheme.divider : AppTheme.surface,  // ← adicionar
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                      ],
                      onChanged: (v) {
                        final valor = v.trim().isEmpty ? 0.0 : (double.tryParse(v) ?? 0.0);
                        widget.item.precoUnitario = valor;
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Preço m²',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary)),
                        if (widget.item.usarM2) ...[
                          const SizedBox(width: 4),
                          const _BadgeAtivo(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _precoM2Ctrl,
                      enabled: widget.item.usarM2,  // ← adicionar
                      decoration: _deco('0.00').copyWith(
                        fillColor: !widget.item.usarM2 ? AppTheme.divider : AppTheme.surface,  // ← adicionar
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                      ],
                      onChanged: (v) {
                        final valor = v.trim().isEmpty ? null : double.tryParse(v);
                        widget.item.precoMetroQuadrado = valor;
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// HELPERS DO ITEM FORM CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ModoCalculo extends StatelessWidget {
  final String label;
  final bool ativo;
  final VoidCallback onTap;

  const _ModoCalculo({required this.label, required this.ativo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: ativo ? AppTheme.primary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: ativo ? AppTheme.primary : AppTheme.divider,
            width: ativo ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Checkbox(
                value: ativo,
                onChanged: (_) => onTap(),
                activeColor: AppTheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: const CircleBorder(),
                side: BorderSide(
                  color: ativo ? AppTheme.primary : AppTheme.textHint,
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ativo ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeAtivo extends StatelessWidget {
  const _BadgeAtivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'ativo',
        style: TextStyle(
          fontSize: 9,
          color: AppTheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORNECEDOR PICKER DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _FornecedorPicker extends StatefulWidget {
  final FornecedorProvider provider;

  const _FornecedorPicker({required this.provider});

  @override
  State<_FornecedorPicker> createState() => _FornecedorPickerState();
}

class _FornecedorPickerState extends State<_FornecedorPicker> {
  final _searchCtrl = TextEditingController();
  List<FornecedorModel> _resultados = [];
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    setState(() => _buscando = true);
    final r = await widget.provider
        .buscarFornecedores(busca: q.isEmpty ? null : q);
    if (mounted) {
      setState(() {
        _resultados = r;
        _buscando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar Fornecedor',
          style: TextStyle(color: AppTheme.textPrimary)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Buscar fornecedor...',
                prefixIcon: Icon(Icons.search, color: AppTheme.textHint),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _buscar(v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buscando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : ListView.builder(
                      itemCount: _resultados.length,
                      itemBuilder: (_, i) {
                        final f = _resultados[i];
                        return ListTile(
                          title: Text(f.nomeFantasia,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary)),
                          subtitle: f.tipoFornecedor != null
                              ? Text(f.tipoFornecedor!,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary))
                              : null,
                          onTap: () => Navigator.pop(context, f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MATERIAL PICKER DIALOG (multi-select com busca)
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialPickerDialog extends StatefulWidget {
  final List<FornecedorMaterialVinculoModel> materiais;
  final void Function(List<FornecedorMaterialVinculoModel>) onConfirmar;

  const _MaterialPickerDialog({
    required this.materiais,
    required this.onConfirmar,
  });

  @override
  State<_MaterialPickerDialog> createState() => _MaterialPickerDialogState();
}

class _MaterialPickerDialogState extends State<_MaterialPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _busca = '';
  // materialId → quantidade de cópias a adicionar
  final Map<int, int> _quantidades = {};

  List<FornecedorMaterialVinculoModel> get _filtrados {
    if (_busca.isEmpty) return widget.materiais;
    final q = _busca.toLowerCase();
    return widget.materiais
        .where((m) => m.descricaoCompleta.toLowerCase().contains(q))
        .toList();
  }

  int get _totalItens => _quantidades.values.fold(0, (s, v) => s + v);

  void _confirmar() {
    final escolhidos = <FornecedorMaterialVinculoModel>[];
    for (final m in widget.materiais) {
      final qty = _quantidades[m.materialId] ?? 0;
      for (var i = 0; i < qty; i++) {
        escolhidos.add(m);
      }
    }
    widget.onConfirmar(escolhidos);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    return AlertDialog(
      title: const Text('Selecionar Materiais',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          children: [
            // Campo de busca
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar material...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textHint, size: 20),
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                isDense: true,
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: AppTheme.textHint),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _busca = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
            const SizedBox(height: 8),
            // Contador de selecionados
            if (_totalItens > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_totalItens ${_totalItens == 1 ? 'item selecionado' : 'itens selecionados'}',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            // Lista
            Expanded(
              child: filtrados.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum material encontrado.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.divider),
                      itemBuilder: (_, i) {
                        final m = filtrados[i];
                        final qty = _quantidades[m.materialId] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.descricaoCompleta,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: qty > 0
                                            ? AppTheme.primary
                                            : AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'R\$ ${m.preco.toStringAsFixed(2).replaceAll('.', ',')}${m.precoMetroQuadrado > 0 ? '  •  m²: R\$ ${m.precoMetroQuadrado.toStringAsFixed(2).replaceAll('.', ',')}' : ''}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Controle de quantidade
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: qty == 0
                                        ? null
                                        : () => setState(() {
                                              final novo = qty - 1;
                                              if (novo == 0) {
                                                _quantidades.remove(m.materialId);
                                              } else {
                                                _quantidades[m.materialId] = novo;
                                              }
                                            }),
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    color: qty == 0 ? AppTheme.textHint : AppTheme.error,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '$qty',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: qty > 0 ? AppTheme.primary : AppTheme.textHint,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      _quantidades[m.materialId] = qty + 1;
                                    }),
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    color: AppTheme.primary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        FilledButton(
          onPressed: _totalItens == 0 ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: Text(
            _totalItens == 0
                ? 'Adicionar'
                : 'Adicionar ($_totalItens)',
          ),
        ),
      ],
    );
  }
}