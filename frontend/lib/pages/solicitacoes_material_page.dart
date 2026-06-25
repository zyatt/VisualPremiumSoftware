// solicitacoes_material_page.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/material_model.dart';
import '../models/solicitacao_material_model.dart';
import '../providers/solicitacao_material_provider.dart';
import '../providers/material_provider.dart';
import '../theme/app_theme.dart';
import '../pages/controle_estoque_page.dart' show MaterialFormDialog;
import '../utils/api_client.dart';

class SolicitacoesMaterialPage extends StatefulWidget {
  const SolicitacoesMaterialPage({super.key});

  @override
  State<SolicitacoesMaterialPage> createState() =>
      _SolicitacoesMaterialPageState();
}

class _SolicitacoesMaterialPageState extends State<SolicitacoesMaterialPage> {
  final _buscaCtrl = TextEditingController();
  String _andamentoFiltro = '';
  Timer? _debounceTimer;

  // Guardamos a referência do provider aqui (e não em dispose) porque em
  // dispose() o BuildContext pode já estar inativo (ex.: durante logout, com
  // a árvore de rotas sendo desmontada), o que causa o erro:
  // "element._lifecycleState == _ElementLifecycle.inactive: is not true".
  SolicitacaoMaterialProvider? _solProvider;

   @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Captura a referência antes de qualquer frame (evita erro de context em dispose)
    _solProvider = context.read<SolicitacaoMaterialProvider>();
 
    // ★ CRÍTICO: seta _paginaAberta = true de forma SÍNCRONA aqui,
    // antes de qualquer postFrameCallback. Isso garante que, se um evento
    // SSE chegar enquanto a página está carregando, ele cai no branch
    // "recarregar lista" e não incrementa o badge.
    _solProvider?.marcarPaginaAberta();
  }
 
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SolicitacaoMaterialProvider>().limparNotificacoes();
      if (mounted) {
        context.read<SolicitacaoMaterialProvider>().carregar();
      }
    });
  }
 
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    // Usa a referência capturada em didChangeDependencies (nunca context aqui)
    _solProvider?.sairDaPagina();
    super.dispose();
  }

  void _aplicarFiltros() {
    context.read<SolicitacaoMaterialProvider>().carregar(
          busca: _buscaCtrl.text.trim(),
          andamento: _andamentoFiltro.isEmpty ? null : _andamentoFiltro,
        );
  }

  Future<void> _abrirFormSolicitacao(
      [SolicitacaoMaterialModel? solicitacao]) async {
    final salvou = await showDialog<bool>(
      context: context,
      builder: (_) => _SolicitacaoFormDialog(solicitacao: solicitacao),
    );
    if (salvou == true && mounted) {
      context.read<SolicitacaoMaterialProvider>().carregar();
    }
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
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitações de Material',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gerenciar solicitações de materiais',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _abrirFormSolicitacao(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nova Solicitação'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _aplicarFiltros,
                  icon: Icon(Icons.refresh,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(
                        color:
                            Theme.of(context).colorScheme.outlineVariant),
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
                      hintText:
                          'Buscar por material, OS ou cliente...',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline,
                          size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400),
                          _aplicarFiltros);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 185,
                  child: DropdownButtonFormField<String>(
                    initialValue: _andamentoFiltro.isEmpty
                        ? null
                        : _andamentoFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Andamento',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('TODOS')),
                      DropdownMenuItem(
                          value: 'EM_ANDAMENTO',
                          child: Text('EM ANDAMENTO')),
                      DropdownMenuItem(
                          value: 'NEGOCIANDO', child: Text('NEGOCIANDO')),
                      DropdownMenuItem(
                          value: 'COMPRADO', child: Text('COMPRADO')),
                      DropdownMenuItem(
                          value: 'ENTREGUE', child: Text('ENTREGUE')),
                      DropdownMenuItem(
                          value: 'FINALIZADA', child: Text('FINALIZADA')),
                    ],
                    onChanged: (v) {
                      setState(() => _andamentoFiltro = v ?? '');
                      _aplicarFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                  onPressed: () {
                    _buscaCtrl.clear();
                    setState(() => _andamentoFiltro = '');
                    _aplicarFiltros();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Consumer<SolicitacaoMaterialProvider>(
                builder: (_, provider, __) {
                  if (provider.carregando) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary));
                  }
                  if (provider.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          const SizedBox(height: 12),
                          Text(
                            'Erro ao carregar solicitações',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            provider.erro!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _aplicarFiltros,
                            icon:
                                const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    );
                  }
                  if (provider.solicitacoes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma solicitação encontrada',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: _TabelaSolicitacoes(
                      solicitacoes: provider.solicitacoes,
                      onEditar: _abrirFormSolicitacao,
                      onAlterarAndamento: (sol, novoStatus) async {
                        final prov =
                            context.read<SolicitacaoMaterialProvider>();
                        final messenger =
                            ScaffoldMessenger.of(context);
                        final ok = await prov.atualizar(
                            sol.id, {'andamento': novoStatus});
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Andamento atualizado'
                                : prov.erro ??
                                    'Erro ao atualizar andamento'),
                            backgroundColor:
                                ok ? AppTheme.success : AppTheme.error,
                          ),
                        );
                      },
                      onExcluir: (sol) async {
                        // Captura referências ao context ANTES de qualquer await
                        final prov =
                            context.read<SolicitacaoMaterialProvider>();
                        final messenger =
                            ScaffoldMessenger.of(context);
                        final confirmar = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title:
                                const Text('Excluir solicitação'),
                            content: const Text(
                                'Deseja excluir esta solicitação?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(true),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.error),
                                child: const Text('Excluir'),
                              ),
                            ],
                          ),
                        );
                        if (confirmar == true && mounted) {
                          final ok = await prov.excluir(sol.id);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? 'Solicitação excluída'
                                  : prov.erro ?? 'Erro'),
                              backgroundColor: ok
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          );
                        }
                      },
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


/// Converte uma URL relativa do backend (ex: /uploads/solicitacoes/x.png)
/// em URL absoluta usando o baseUrl do ApiClient.
String _resolverUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = ApiClient.baseUrl.replaceAll(RegExp(r'/$'), '');

  // DEBUG temporário — confirma o valor real de baseUrl em tempo de execução.
  // Remover após identificar a causa.
  // ignore: avoid_print
  print('[_resolverUrl] ApiClient.baseUrl="$base" url="$url"');

  if (base.isEmpty) {
    // Guarda defensiva: nunca deixa Image.network receber uma URL
    // apenas com path (ex: "/uploads/..."), pois no desktop o Flutter
    // resolve isso contra Uri.base (file://), causando
    // "No host specified in URI file:///...".
    throw StateError(
      'ApiClient.baseUrl está vazio ao montar a URL da imagem "$url". '
      'Verifique se o .env foi carregado (dotenv.load) antes do uso do ApiClient, '
      'e se API_HOST/API_PORT ou API_TUNNEL_URL estão definidos no .env '
      'incluído no build (assets).',
    );
  }

  return '$base$url';
}

// ─────────────────────────────────────────────────────────────────────────────
// TABELA
// ─────────────────────────────────────────────────────────────────────────────

class _TabelaSolicitacoes extends StatelessWidget {
  final List<SolicitacaoMaterialModel> solicitacoes;
  final void Function(SolicitacaoMaterialModel) onEditar;
  final void Function(SolicitacaoMaterialModel) onExcluir;
  final Future<void> Function(SolicitacaoMaterialModel, String)
      onAlterarAndamento;

  const _TabelaSolicitacoes({
    required this.solicitacoes,
    required this.onEditar,
    required this.onExcluir,
    required this.onAlterarAndamento,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(
                vertical: 12, horizontal: 16),
            child: const Row(
              children: [
                Expanded(
                    flex: 1,
                    child: _CabecalhoColuna(label: 'Solicitante')),
                Expanded(
                    flex: 2,
                    child: _CabecalhoColuna(label: 'Material')),
                Expanded(
                    flex: 1,
                    child: _CabecalhoColuna(label: 'Quantidade')),
                Expanded(
                    flex: 1, child: _CabecalhoColuna(label: 'OS')),
                Expanded(
                    flex: 1,
                    child: _CabecalhoColuna(label: 'Cliente')),
                Expanded(
                    flex: 1,
                    child: _CabecalhoColuna(label: 'Solicitação')),
                Expanded(
                    flex: 1,
                    child: _CabecalhoColuna(label: 'Necessidade')),
                Expanded(
                    flex: 2,
                    child: _CabecalhoColuna(label: 'Andamento')),
                SizedBox(
                    width: 96,
                    child: _CabecalhoColuna(label: 'Ações')),
              ],
            ),
          ),
          Divider(
              height: 0,
              thickness: 0.8,
              color: Theme.of(context).colorScheme.outlineVariant),
          for (int i = 0; i < solicitacoes.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 0,
                  thickness: 0.8,
                  color:
                      Theme.of(context).colorScheme.outlineVariant),
            _LinhaSolicitacao(
              solicitacao: solicitacoes[i],
              onEditar: onEditar,
              onExcluir: onExcluir,
              onAlterarAndamento: onAlterarAndamento,
            ),
          ],
        ],
      ),
    );
  }
}

class _CabecalhoColuna extends StatelessWidget {
  final String label;
  const _CabecalhoColuna({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _LinhaSolicitacao extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;
  final void Function(SolicitacaoMaterialModel) onEditar;
  final void Function(SolicitacaoMaterialModel) onExcluir;
  final Future<void> Function(SolicitacaoMaterialModel, String)
      onAlterarAndamento;

  const _LinhaSolicitacao({
    required this.solicitacao,
    required this.onEditar,
    required this.onExcluir,
    required this.onAlterarAndamento,
  });

  @override
  State<_LinhaSolicitacao> createState() => _LinhaSolicitacaoState();
}

class _LinhaSolicitacaoState extends State<_LinhaSolicitacao> {
  bool _hovered = false;

  String _formatarData(DateTime data) =>
      DateFormat('dd/MM/yyyy').format(data);

  @override
  Widget build(BuildContext context) {
    final sol = widget.solicitacao;
    final bgColor = _hovered
        ? const Color(0xFFFF9800).withValues(alpha: 0.10)
        : Theme.of(context).colorScheme.surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEditar(sol),
        child: ColoredBox(
          color: bgColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 12, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    sol.usuarioNome,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sol.materialNome,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sol.materialIdentificador != null ||
                          sol.materialMedida != null ||
                          sol.materialEspessura != null)
                        Text(
                          [
                            sol.materialIdentificador,
                            sol.materialMedida,
                            sol.materialEspessura
                          ]
                              .whereType<String>()
                              .where((s) => s.trim().isNotEmpty)
                              .join(' · '),
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    sol.quantidade % 1 == 0
                        ? sol.quantidade.toStringAsFixed(0)
                        : sol.quantidade.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    sol.numeroOS,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    sol.nomeCliente,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    _formatarData(sol.dataSolicitacao),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    _formatarData(sol.dataNecessidade),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 130),
                      child: _StatusBadge(
                        status: sol.andamento,
                        onAlterar: (novoStatus) =>
                            widget.onAlterarAndamento(
                                sol, novoStatus),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Botão de imagem (visualizar se houver, ou é indicador)
                      if (sol.imagemUrl != null)
                        Tooltip(
                          message: 'Ver imagem anexada',
                          child: IconButton(
                            onPressed: () =>
                                _verImagem(context, sol.imagemUrl!),
                            icon: const Icon(Icons.image_outlined,
                                size: 18),
                            color: AppTheme.primary
                                .withValues(alpha: 0.7),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      IconButton(
                        onPressed: () => widget.onEditar(sol),
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Editar',
                        color: AppTheme.primary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () => widget.onExcluir(sol),
                        icon: const Icon(Icons.delete, size: 18),
                        tooltip: 'Excluir',
                        color: AppTheme.error,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
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

  void _verImagem(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(_resolverUrl(url), fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                radius: 16,
                child: IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white, size: 16),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
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
// STATUS BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final void Function(String novoStatus)? onAlterar;
  const _StatusBadge({required this.status, this.onAlterar});

  static const _opcoes = ['EM_ANDAMENTO', 'NEGOCIANDO', 'COMPRADO', 'ENTREGUE', 'FINALIZADA'];

  ({Color bg, Color fg, String label}) _estilo(
      BuildContext context, String status) {
    switch (status) {
      case 'EM_ANDAMENTO':
        return (
          bg: const Color(0xFFD97706).withValues(alpha: 0.1),
          fg: const Color(0xFFD97706),
          label: 'EM ANDAMENTO',
        );
      case 'NEGOCIANDO':
        return (
          bg: const Color(0xFF8E24AA).withValues(alpha: 0.1),
          fg: const Color(0xFF8E24AA),
          label: 'NEGOCIANDO',
        );
      case 'COMPRADO':
        return (
          bg: const Color(0xFF1E88E5).withValues(alpha: 0.1),
          fg: const Color(0xFF1E88E5),
          label: 'COMPRADO',
        );
      case 'ENTREGUE':
        return (
          bg: const Color(0xFF15803D).withValues(alpha: 0.1),
          fg: const Color(0xFF15803D),
          label: 'ENTREGUE',
        );
      case 'FINALIZADA':
        return (
          bg: const Color(0xFF546E7A).withValues(alpha: 0.1),
          fg: const Color(0xFF546E7A),
          label: 'FINALIZADA',
        );
      default:
        return (
          bg: Theme.of(context).colorScheme.surfaceContainerHighest,
          fg: Theme.of(context).colorScheme.onSurfaceVariant,
          label: status,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final estilo = _estilo(context, status);
    final badge = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: estilo.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              estilo.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: estilo.fg,
              ),
            ),
          ),
          if (onAlterar != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 14, color: estilo.fg),
          ],
        ],
      ),
    );

    if (onAlterar == null) return badge;

    return PopupMenuButton<String>(
      tooltip: 'Alterar andamento',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 28),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (ctx) => _opcoes.map((op) {
        final e = _estilo(ctx, op);
        final selecionado = op == status;
        return PopupMenuItem<String>(
          value: op,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: e.fg, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                e.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      selecionado ? FontWeight.w700 : FontWeight.w400,
                  color: selecionado ? e.fg : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onSelected: (novoStatus) {
        if (novoStatus != status) onAlterar!(novoStatus);
      },
      child: badge,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG FORMULÁRIO (criar / editar) — com abas: Dados | Imagem | Histórico
// ─────────────────────────────────────────────────────────────────────────────

class _SolicitacaoFormDialog extends StatefulWidget {
  final SolicitacaoMaterialModel? solicitacao;
  const _SolicitacaoFormDialog({this.solicitacao});

  @override
  State<_SolicitacaoFormDialog> createState() =>
      _SolicitacaoFormDialogState();
}

class _SolicitacaoFormDialogState extends State<_SolicitacaoFormDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog;

  MaterialModel? _materialSelecionado;
  final _quantidadeCtrl   = TextEditingController();
  final _numeroOSCtrl     = TextEditingController();
  final _clienteCtrl      = TextEditingController();
  final _observacaoCtrl   = TextEditingController();
  final _buscaMaterialCtrl = TextEditingController();
  DateTime _dataSolicitacao = DateTime.now();

  DateTime _dataNecessidade =
      DateTime.now().add(const Duration(days: 1));
  String _andamento = 'EM_ANDAMENTO';

  // Imagem
  File? _imagemLocal;         // arquivo selecionado ainda não enviado
  String? _imagemUrlExistente; // URL já salva no servidor

  bool get _editando => widget.solicitacao != null;

  @override
  void initState() {
    super.initState();
    final abas = _editando ? 3 : 2; // sem aba de histórico em criação
    _tabCtrl = TabController(length: abas, vsync: this);

    if (_editando) {
      final sol = widget.solicitacao!;
      _quantidadeCtrl.text    = sol.quantidade.toString();
      _numeroOSCtrl.text      = sol.numeroOS;
      _clienteCtrl.text       = sol.nomeCliente;
      _dataSolicitacao        = sol.dataSolicitacao;
      _dataNecessidade        = sol.dataNecessidade;
      _andamento              = sol.andamento;
      _observacaoCtrl.text    = sol.observacao ?? '';
      _imagemUrlExistente     = sol.imagemUrl;
      _materialSelecionado    = MaterialModel(
        id: sol.materialId,
        nome: sol.materialNome,
        unidade: sol.materialUnidade,
        categoria: sol.materialCategoria,
        medida: sol.materialMedida,
        espessura: sol.materialEspessura,
        identificador: sol.materialIdentificador,
        quantidade: sol.materialQuantidadeEstoque,
        estoqueMinimo: 0,
        status: 'OK',
        estoqueConfirmado: false,
        ativo: true,
      );
      _buscaMaterialCtrl.text = sol.materialNome;

      // Carrega logs ao abrir edição
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context
            .read<SolicitacaoMaterialProvider>()
            .carregarLogs(sol.id);
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _quantidadeCtrl.dispose();
    _numeroOSCtrl.dispose();
    _clienteCtrl.dispose();
    _observacaoCtrl.dispose();
    _buscaMaterialCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirSeletorMaterial() async {
    final material = await showDialog<MaterialModel>(
      context: context,
      builder: (_) => const _SeletorMaterialDialog(),
    );
    if (!mounted) return;
    if (material != null) {
      setState(() {
        _materialSelecionado    = material;
        _buscaMaterialCtrl.text = material.nome;
        _erroDialog             = null;
      });
    } else {
      _buscaMaterialCtrl.text = _materialSelecionado?.nome ?? '';
    }
  }

  Future<void> _selecionarImagem() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      if (await file.exists()) {
        setState(() => _imagemLocal = file);
      }
    }
  }

  void _removerImagem() {
    setState(() {
      _imagemLocal        = null;
      _imagemUrlExistente = null;
    });
  }

  Future<void> _salvar() async {
    // currentState pode ser null se a aba Dados nao foi renderizada ainda
    final formValido = _formKey.currentState?.validate() ?? true;
    if (!formValido) { _tabCtrl.animateTo(0); return; }
    if (_materialSelecionado == null) {
      _tabCtrl.animateTo(0);
      setState(() => _erroDialog = 'Selecione um material');
      return;
    }

    setState(() {
      _salvando   = true;
      _erroDialog = null;
    });

    final dados = {
      'materialId':      _materialSelecionado!.id,
      'quantidade':      double.parse(_quantidadeCtrl.text),
      'numeroOS':        _numeroOSCtrl.text.trim(),
      'nomeCliente':     _clienteCtrl.text.trim(),
      'dataSolicitacao': DateTime.now().toIso8601String(),
      'dataNecessidade': _dataNecessidade.toIso8601String(),
      'andamento':       _andamento,
      'observacao':      _observacaoCtrl.text.trim().isEmpty
          ? null
          : _observacaoCtrl.text.trim(),
      // Se o usuário removeu a imagem existente sem selecionar outra,
      // envia null para o backend limpar o campo
      if (_imagemLocal == null && _imagemUrlExistente == null)
        'imagemUrl': null,
    };

    final provider = context.read<SolicitacaoMaterialProvider>();
    final bool ok;
    if (_editando) {
      ok = await provider.atualizar(
        widget.solicitacao!.id,
        dados,
        imagem: _imagemLocal,
      );
    } else {
      ok = await provider.criar(dados, imagem: _imagemLocal);
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      final messenger = ScaffoldMessenger.of(context); // captura ANTES do pop
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              _editando ? 'Solicitação atualizada' : 'Solicitação criada'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() => _erroDialog = provider.erro ?? 'Erro ao salvar');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    _editando
                        ? 'Editar Solicitação'
                        : 'Nova Solicitação',
                    style:
                        Theme.of(context).textTheme.titleLarge,
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
            // ── Abas ───────────────────────────────────────────────────────
            TabBar(
              controller: _tabCtrl,
              labelColor: AppTheme.primary,
              unselectedLabelColor:
                  Theme.of(context).colorScheme.onSurfaceVariant,
              indicatorColor: AppTheme.primary,
              tabs: [
                const Tab(text: 'Dados'),
                const Tab(text: 'Imagem'),
                if (_editando) const Tab(text: 'Histórico'),
              ],
            ),
            const Divider(height: 0),
            Flexible(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // ── ABA 1: Dados ──────────────────────────────────────
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          if (_erroDialog != null) ...[
                            _ErroBanner(
                              mensagem: _erroDialog!,
                              onDismiss: () => setState(
                                  () => _erroDialog = null),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _buscaMaterialCtrl,
                                  readOnly: true,
                                  onTap: _abrirSeletorMaterial,
                                  decoration: InputDecoration(
                                    labelText: 'Material *',
                                    hintText:
                                        'Toque para selecionar...',
                                    suffixIcon: _materialSelecionado !=
                                            null
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: AppTheme.success,
                                            size: 20)
                                        : const Icon(
                                            Icons.arrow_drop_down),
                                  ),
                                  validator: (v) =>
                                      _materialSelecionado == null
                                          ? 'Selecione um material'
                                          : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: 'Cadastrar novo material',
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    final criou =
                                        await showDialog<bool>(
                                      context: context,
                                      builder: (_) =>
                                          const MaterialFormDialog(),
                                    );
                                    if (criou == true && mounted) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('Material cadastrado'),
                                          backgroundColor:
                                              AppTheme.success,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.add,
                                      size: 16),
                                  label: const Text('Novo'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primary,
                                    side: const BorderSide(
                                        color: AppTheme.primary),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _quantidadeCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Quantidade *'),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d+\.?\d{0,3}')),
                            ],
                            validator: (v) => v == null ||
                                    v.isEmpty ||
                                    double.tryParse(v) == null
                                ? 'Quantidade inválida'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _numeroOSCtrl,
                                  decoration:
                                      const InputDecoration(
                                          labelText: 'Número OS *'),
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                          ? 'Número OS é obrigatório'
                                          : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _clienteCtrl,
                                  decoration:
                                      const InputDecoration(
                                          labelText: 'Nome Cliente *'),
                                  textCapitalization:
                                      TextCapitalization.words,
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                          ? 'Nome do cliente é obrigatório'
                                          : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: DateFormat('dd/MM/yyyy HH:mm').format(_dataSolicitacao),
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: 'Data Solicitação',
                                    suffixIcon: Icon(
                                      Icons.lock_outline,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _DatePickerField(
                                  label: 'Data Necessidade *',
                                  value: _dataNecessidade,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                      const Duration(days: 365 * 2)),
                                  onChanged: (d) =>
                                      setState(() => _dataNecessidade = d),
                                ),
                              ),
                            ],
                           ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _andamento,
                            decoration: const InputDecoration(
                              labelText: 'Andamento *',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'EM_ANDAMENTO',
                                  child: Text('EM ANDAMENTO')),
                              DropdownMenuItem(
                                  value: 'NEGOCIANDO',
                                  child: Text('NEGOCIANDO')),
                              DropdownMenuItem(
                                  value: 'COMPRADO',
                                  child: Text('COMPRADO')),
                              DropdownMenuItem(
                                  value: 'ENTREGUE',
                                  child: Text('ENTREGUE')),
                              DropdownMenuItem(
                                  value: 'FINALIZADA',
                                  child: Text('FINALIZADA')),
                            ],
                            onChanged: (v) =>
                                setState(() => _andamento = v!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _observacaoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Observação',
                              alignLabelWithHint: true,
                            ),
                            maxLines: 3,
                            textCapitalization:
                                TextCapitalization.sentences,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── ABA 2: Imagem ─────────────────────────────────────
                  _AbaImagem(
                    imagemLocal: _imagemLocal,
                    imagemUrl: _imagemUrlExistente,
                    onSelecionar: _selecionarImagem,
                    onRemover: _removerImagem,
                  ),

                  // ── ABA 3: Histórico (somente edição) ─────────────────
                  if (_editando)
                    _AbaHistorico(
                        solicitacaoId: widget.solicitacao!.id),
                ],
              ),
            ),
            const Divider(height: 0),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _salvando ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _salvando ? null : _salvar,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                    child: _salvando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
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

// ─────────────────────────────────────────────────────────────────────────────
// ABA IMAGEM
// ─────────────────────────────────────────────────────────────────────────────

class _AbaImagem extends StatelessWidget {
  final File? imagemLocal;
  final String? imagemUrl;
  final VoidCallback onSelecionar;
  final VoidCallback onRemover;

  const _AbaImagem({
    required this.imagemLocal,
    required this.imagemUrl,
    required this.onSelecionar,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    final temImagem = imagemLocal != null || imagemUrl != null;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Imagem de referência',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Anexe uma foto ou imagem relacionada à solicitação (JPG, PNG, WEBP — máx. 10 MB).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),

         if (temImagem) ...[
            // Preview
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imagemLocal != null
                      ? Image.file(imagemLocal!,
                          fit: BoxFit.contain)
                      : Image.network(
                          _resolverUrl(imagemUrl!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, __) => Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              error.toString(),
                              style: TextStyle(color: AppTheme.error, fontSize: 12),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSelecionar,
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Trocar imagem'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onRemover,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remover'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                        color: AppTheme.error.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Drop zone / botão de seleção
            GestureDetector(
              onTap: onSelecionar,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant,
                    style: BorderStyle.solid,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 48,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Clique para selecionar uma imagem',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'JPG, PNG, WEBP — até 10 MB',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline,
                              ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSelecionar,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Buscar do dispositivo'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABA HISTÓRICO DE EDIÇÕES
// ─────────────────────────────────────────────────────────────────────────────

class _AbaHistorico extends StatelessWidget {
  final int solicitacaoId;
  const _AbaHistorico({required this.solicitacaoId});

  static const _camposLabel = {
    'materialId':      'Material (ID)',
    'quantidade':      'Quantidade',
    'numeroOS':        'Número OS',
    'nomeCliente':     'Cliente',
    'dataSolicitacao': 'Data Solicitação',
    'dataNecessidade': 'Data Necessidade',
    'andamento':       'Andamento',
    'observacao':      'Observação',
    'imagemUrl':       'Imagem',
  };

  String _fmt(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    // Tenta formatar datas ISO
    try {
      final d = DateTime.parse(s).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(d);
    } catch (_) {}
    return s.isEmpty ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SolicitacaoMaterialProvider>(
      builder: (_, prov, __) {
        if (prov.carregandoLogs) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary));
        }
        if (prov.logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  'Nenhuma edição registrada',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: prov.logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final log = prov.logs[i];
            // Detecta quais campos mudaram
            final campos = <String>[];
            for (final key in log.depois.keys) {
              final antes  = log.antes[key]?.toString();
              final depois = log.depois[key]?.toString();
              if (antes != depois) campos.add(key);
            }

            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.edit_note,
                            size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            log.editorNome,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                        ),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(log.editadoEm),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (campos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 0),
                      const SizedBox(height: 8),
                      ...campos.map((campo) {
                        final label = _camposLabel[campo] ?? campo;
                        final antes =
                            _fmt(log.antes[campo]);
                        final depois =
                            _fmt(log.depois[campo]);
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Antes
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.error
                                            .withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '− $antes',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.error),
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    // Depois
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.success
                                            .withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '+ $depois',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.success),
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

class _ErroBanner extends StatelessWidget {
  final String mensagem;
  final VoidCallback onDismiss;
  const _ErroBanner({required this.mensagem, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppTheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensagem,
                style: const TextStyle(
                    color: AppTheme.error, fontSize: 13)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close,
                color: AppTheme.error, size: 16),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime value;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onChanged;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: firstDate ?? DateTime(2020),
            lastDate: lastDate ??
                DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) onChanged(picked);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat('dd/MM/yyyy').format(value),
                style: const TextStyle(fontSize: 14)),
            const Icon(Icons.calendar_today, size: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELETOR DE MATERIAL (igual ao original — mantido integralmente)
// ─────────────────────────────────────────────────────────────────────────────

const _kSelCategoriaGeral = '__GERAL__';
const _kSelCategoriaSemCategoria = '__SEM_CATEGORIA__';

class _SeletorMaterialDialog extends StatefulWidget {
  const _SeletorMaterialDialog();

  @override
  State<_SeletorMaterialDialog> createState() =>
      _SeletorMaterialDialogState();
}

class _SeletorMaterialDialogState
    extends State<_SeletorMaterialDialog> {
  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  String? _categoriaSelecionada;
  String _categoriaLabel = '';
  Color _categoriaCor = AppTheme.primary;

  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria = '';

  final _buscaCtrl        = TextEditingController();
  final _buscaIdCtrl      = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl       = TextEditingController();
  final _espessuraCtrl    = TextEditingController();
  String _statusFiltro = '';
  Timer? _debounceTimer;

  bool _carregandoMateriais = false;
  List<MaterialModel> _materiais = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MaterialProvider>().carregarCategorias();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filtroCategoriaCtrl.dispose();
    _buscaCtrl.dispose();
    _buscaIdCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  String? _categoriaParaProvider(String categoriaId) {
    if (categoriaId == _kSelCategoriaGeral) return null;
    if (categoriaId == _kSelCategoriaSemCategoria) return '';
    return categoriaId;
  }

  Future<void> _abrirCategoria(
      String id, String label, Color cor) async {
    setState(() {
      _categoriaSelecionada = id;
      _categoriaLabel       = label;
      _categoriaCor         = cor;
      _buscaCtrl.clear();
      _buscaIdCtrl.clear();
      _identificadorCtrl.clear();
      _medidaCtrl.clear();
      _espessuraCtrl.clear();
      _statusFiltro         = '';
      _carregandoMateriais  = true;
      _materiais            = [];
    });
    await _carregarMateriais();
  }

  Future<void> _carregarMateriais() async {
    final prov = context.read<MaterialProvider>();
    await prov.carregar(
      busca:         _buscaCtrl.text.trim(),
      id:            _buscaIdCtrl.text.trim(),
      identificador: _identificadorCtrl.text.trim(),
      medida:        _medidaCtrl.text.trim(),
      espessura:     _espessuraCtrl.text.trim(),
      status:        _statusFiltro,
      categoria:     _categoriaParaProvider(_categoriaSelecionada!),
    );
    if (mounted) {
      setState(() {
        _materiais           = prov.materiais;
        _carregandoMateriais = false;
      });
    }
  }

  // ignore: unused_element
  void _aplicarFiltrosMateriais() {
    setState(() => _carregandoMateriais = true);
    _carregarMateriais();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  if (_categoriaSelecionada != null)
                    IconButton(
                      onPressed: () => setState(
                          () => _categoriaSelecionada = null),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      tooltip: 'Voltar às categorias',
                    ),
                  Expanded(
                    child: Text(
                      _categoriaSelecionada == null
                          ? 'Selecionar Material'
                          : _categoriaLabel,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 0),
            Expanded(
              child: _categoriaSelecionada == null
                  ? _buildGridCategorias(context)
                  : _buildListaMateriais(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCategorias(BuildContext context) {
    return Consumer<MaterialProvider>(
      builder: (_, prov, __) {
        if (prov.carregando) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary));
        }

        final todasCategorias = prov.categorias;
        final categoriasVisiveis = _filtroCategoria.isEmpty
            ? todasCategorias
            : todasCategorias
                .where((c) => c
                    .toLowerCase()
                    .contains(_filtroCategoria.toLowerCase()))
                .toList();

        final categorias = <Map<String, dynamic>>[
          {'id': _kSelCategoriaGeral, 'label': 'TODOS', 'icon': Icons.grid_view_rounded},
          ...categoriasVisiveis.map((c) => {
                'id': c,
                'label': c.toUpperCase(),
                'icon': Icons.category_rounded,
              }),
          if (_filtroCategoria.isEmpty)
            {'id': _kSelCategoriaSemCategoria, 'label': 'SEM CATEGORIA', 'icon': Icons.label_off_rounded},
        ];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _filtroCategoriaCtrl,
                decoration: InputDecoration(
                  hintText: 'Filtrar categorias...',
                  prefixIcon: Icon(Icons.search,
                      size: 18,
                      color: Theme.of(context).colorScheme.outline),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _filtroCategoria = v),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.6,
                ),
                itemCount: categorias.length,
                itemBuilder: (_, i) {
                  final cat = categorias[i];
                  final cor = _cores[i % _cores.length];
                  return _CategoriaCardSeletor(
                    label:  cat['label'] as String,
                    cor:    cor,
                    icone:  cat['icon'] as IconData,
                    onTap:  () => _abrirCategoria(
                        cat['id'] as String,
                        cat['label'] as String,
                        cor),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListaMateriais(BuildContext context) {
    if (_carregandoMateriais) {
      return const Center(
          child:
              CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_materiais.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'Nenhum material encontrado',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: _materiais.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _MaterialItemSeletor(
        material: _materiais[i],
        cor: _categoriaCor,
        onTap: () => Navigator.of(context).pop(_materiais[i]),
      ),
    );
  }
}

class _CategoriaCardSeletor extends StatefulWidget {
  final String label;
  final Color cor;
  final IconData icone;
  final VoidCallback onTap;

  const _CategoriaCardSeletor({
    required this.label,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_CategoriaCardSeletor> createState() =>
      _CategoriaCardSeletorState();
}

class _CategoriaCardSeletorState
    extends State<_CategoriaCardSeletor> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ativo = _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo
                ? widget.cor.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ativo
                  ? widget.cor
                  : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icone,
                    color: widget.cor, size: 24),
              ),
              const SizedBox(height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ativo
                        ? widget.cor
                        : Theme.of(context)
                            .colorScheme
                            .onSurface,
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

class _MaterialItemSeletor extends StatefulWidget {
  final MaterialModel material;
  final Color cor;
  final VoidCallback onTap;

  const _MaterialItemSeletor({
    required this.material,
    required this.cor,
    required this.onTap,
  });

  @override
  State<_MaterialItemSeletor> createState() =>
      _MaterialItemSeletorState();
}

class _MaterialItemSeletorState
    extends State<_MaterialItemSeletor> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final detalhes = [m.identificador, m.medida, m.espessura]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.cor.withValues(alpha: 0.10)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? widget.cor.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.inventory_2,
                    color: widget.cor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.nome,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detalhes.isNotEmpty)
                      Text(
                        detalhes,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${m.quantidade.toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2)} ${m.unidade ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}