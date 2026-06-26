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
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';
import '../utils/api_client.dart';
import '../pages/controle_estoque_page.dart' show MaterialFormDialog;
import '../pages/estoque_temporario_page.dart' show EstoqueTemporarioFormDialog;
import '../providers/estoque_temporario_provider.dart';

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
  SolicitacaoMaterialProvider? _solProvider;

  // ── Totais globais (sem filtro) ──────────────────────────────────────────
  // Capturados na primeira carga (sem busca/andamento) e atualizados sempre
  // que o usuário limpa todos os filtros.
  int _totalItensGlobal     = 0;
  int _totalCompradosGlobal = 0;
  bool _totaisGlobaisCarregados = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _solProvider = context.read<SolicitacaoMaterialProvider>();
    _solProvider?.marcarPaginaAberta();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SolicitacaoMaterialProvider>().limparNotificacoes();
      if (mounted) {
        await context.read<SolicitacaoMaterialProvider>().carregar();
        _atualizarTotaisGlobais();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    _solProvider?.sairDaPagina();
    super.dispose();
  }

  void _aplicarFiltros() {
    context.read<SolicitacaoMaterialProvider>().carregar(
          busca: _buscaCtrl.text.trim(),
          andamento: _andamentoFiltro.isEmpty ? null : _andamentoFiltro,
        );
    // Quando não há filtro ativo, a lista resultante é a global — captura os totais
    final semFiltro = _buscaCtrl.text.trim().isEmpty && _andamentoFiltro.isEmpty;
    if (semFiltro) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _atualizarTotaisGlobais());
    }
  }

  /// Captura os totais globais a partir da lista atual do provider.
  /// Deve ser chamado apenas quando não há filtros ativos.
  void _atualizarTotaisGlobais() {
    if (!mounted) return;
    final sols = context.read<SolicitacaoMaterialProvider>().solicitacoes;
    if (sols.isEmpty && _totaisGlobaisCarregados) return;
    final itens     = sols.fold<int>(0, (s, sol) => s + sol.totalMateriais);
    final comprados = sols.fold<int>(0, (s, sol) => s + sol.totalComprados);
    setState(() {
      _totalItensGlobal     = itens;
      _totalCompradosGlobal = comprados;
      _totaisGlobaisCarregados = true;
    });
  }

  Future<void> _abrirFormSolicitacao([SolicitacaoMaterialModel? solicitacao]) async {
    final Widget dialog = solicitacao == null
        ? const _CriarSolicitacaoDialog()
        : _VisualizarSolicitacaoDialog(solicitacao: solicitacao);
    
    final salvou = await showDialog<bool>(
      context: context,
      builder: (_) => dialog,
    );
    if (salvou == true && mounted) {
      await context.read<SolicitacaoMaterialProvider>().carregar();
      // Se não há filtros ativos, a lista atual é a global — atualiza os totais
      final semFiltro = _buscaCtrl.text.trim().isEmpty && _andamentoFiltro.isEmpty;
      if (semFiltro) _atualizarTotaisGlobais();
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
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gerenciar solicitações de materiais',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _aplicarFiltros,
                  icon: Icon(Icons.refresh, size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Banner de totais globais (independente de filtro) ────────────
            if (_totaisGlobaisCarregados && _totalItensGlobal > 0) ...[
              _BannerTotaisGlobais(
                totalItens:     _totalItensGlobal,
                totalComprados: _totalCompradosGlobal,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por material, OS ou cliente...',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 185,
                  child: DropdownButtonFormField<String>(
                    mouseCursor: SystemMouseCursors.click,
                    initialValue: _andamentoFiltro.isEmpty ? null : _andamentoFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Andamento',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('TODOS')),
                      DropdownMenuItem(value: 'EM_ANDAMENTO', child: Text('EM ANDAMENTO')),
                      DropdownMenuItem(value: 'FINALIZADO', child: Text('FINALIZADO')),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }
                  if (provider.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
                          const SizedBox(height: 12),
                          Text('Erro ao carregar solicitações',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(provider.erro!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center),
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
                  if (provider.solicitacoes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text('Nenhuma solicitação encontrada',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    );
                  }
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: _TabelaSolicitacoes(
                      solicitacoes: provider.solicitacoes,
                      onAbrir: _abrirFormSolicitacao,
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

String _resolverUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = ApiClient.baseUrl.replaceAll(RegExp(r'/$'), '');
  if (base.isEmpty) {
    throw StateError(
      'ApiClient.baseUrl está vazio ao montar a URL da imagem "$url". '
      'Verifique se o .env foi carregado.',
    );
  }
  return '$base$url';
}

// ═══════════════════════════════════════════════════════════════════════════
// BANNER DE TOTAIS GLOBAIS
// ═══════════════════════════════════════════════════════════════════════════

class _BannerTotaisGlobais extends StatelessWidget {
  final int totalItens;
  final int totalComprados;

  const _BannerTotaisGlobais({
    required this.totalItens,
    required this.totalComprados,
  });

  @override
  Widget build(BuildContext context) {
    final pendentes  = totalItens - totalComprados;
    final todosOk    = pendentes == 0 && totalItens > 0;
    final progresso  = totalItens == 0 ? 0.0 : totalComprados / totalItens;
    final corPrimary = todosOk ? const Color(0xFF15803D) : AppTheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: corPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: corPrimary.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            todosOk ? Icons.check_circle_outline : Icons.pending_actions_outlined,
            size: 20,
            color: corPrimary,
          ),
          const SizedBox(width: 12),
          // Texto principal
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total de materiais: $totalItens',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: corPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                todosOk
                    ? 'Todos comprados ✓'
                    : '$totalComprados/$totalItens comprados  ·  $pendentes pendente${pendentes == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Barra de progresso
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progresso,
                backgroundColor: corPrimary.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(corPrimary),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Percentual
          Text(
            '${(progresso * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: corPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TABELA DE SOLICITAÇÕES
// ═══════════════════════════════════════════════════════════════════════════

class _TabelaSolicitacoes extends StatelessWidget {
  final List<SolicitacaoMaterialModel> solicitacoes;
  final void Function(SolicitacaoMaterialModel) onAbrir;

  const _TabelaSolicitacoes({required this.solicitacoes, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: const Row(
              children: [
                Expanded(flex: 1, child: _CabecalhoColuna(label: 'OS')),
                Expanded(flex: 2, child: _CabecalhoColuna(label: 'Cliente')),
                Expanded(flex: 1, child: _CabecalhoColuna(label: 'Solicitante')),
                Expanded(flex: 2, child: _CabecalhoColuna(label: 'Materiais')),
                Expanded(flex: 1, child: _CabecalhoColuna(label: 'Solicitação')),
                Expanded(flex: 1, child: _CabecalhoColuna(label: 'Necessidade')),
                Expanded(flex: 1, child: _CabecalhoColuna(label: 'Andamento')),
              ],
            ),
          ),
          Divider(height: 0, thickness: 0.8,
              color: Theme.of(context).colorScheme.outlineVariant),
          for (int i = 0; i < solicitacoes.length; i++) ...[
            if (i > 0)
              Divider(height: 0, thickness: 0.8,
                  color: Theme.of(context).colorScheme.outlineVariant),
            _LinhaSolicitacao(solicitacao: solicitacoes[i], onAbrir: onAbrir),
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
    return Text(label, textAlign: TextAlign.center,
        style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

class _LinhaSolicitacao extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;
  final void Function(SolicitacaoMaterialModel) onAbrir;

  const _LinhaSolicitacao({required this.solicitacao, required this.onAbrir});

  @override
  State<_LinhaSolicitacao> createState() => _LinhaSolicitacaoState();
}

class _LinhaSolicitacaoState extends State<_LinhaSolicitacao> {
  bool _hovered = false;

  String _formatarData(DateTime data) => DateFormat('dd/MM/yyyy').format(data);

  @override
  Widget build(BuildContext context) {
    final sol = widget.solicitacao;
    final bgColor = _hovered
        ? const Color(0x00ff9800).withValues(alpha: 0.10)
        : Theme.of(context).colorScheme.surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onAbrir(sol),
        child: ColoredBox(
          color: bgColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 1,
                  child: Text(sol.numeroOS, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 2,
                  child: Text(sol.nomeCliente, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 1,
                  child: Text(sol.usuarioNome, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${sol.totalMateriais} ${sol.totalMateriais == 1 ? 'material' : 'materiais'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      LinearProgressIndicator(
                        value: sol.totalMateriais == 0 ? 0 : sol.totalComprados / sol.totalMateriais,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          sol.todosComprados ? AppTheme.success : AppTheme.primary,
                        ),
                        minHeight: 4,
                      ),
                      const SizedBox(height: 2),
                      Text('${sol.totalComprados}/${sol.totalMateriais} comprados',
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(_formatarData(sol.dataSolicitacao),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  flex: 1,
                  child: Text(_formatarData(sol.dataNecessidade),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  flex: 1,
                  child: Center(child: _StatusBadge(status: sol.andamento)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  ({Color bg, Color fg, String label}) _estilo(BuildContext context, String status) {
    switch (status) {
      case 'EM_ANDAMENTO':
        return (
          bg: const Color(0xFFD97706).withValues(alpha: 0.1),
          fg: const Color(0xFFD97706),
          label: 'EM ANDAMENTO',
        );
      case 'FINALIZADO':
        return (
          bg: const Color(0xFF15803D).withValues(alpha: 0.1),
          fg: const Color(0xFF15803D),
          label: 'FINALIZADO',
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: estilo.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(estilo.label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: estilo.fg)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG: CRIAR SOLICITAÇÃO (múltiplos materiais)
// ═══════════════════════════════════════════

class _ItemMaterialCriacao {
  MaterialModel? material;
  final TextEditingController quantidadeCtrl = TextEditingController();
  final TextEditingController observacaoCtrl = TextEditingController();
  File? imagem;

  void dispose() {
    quantidadeCtrl.dispose();
    observacaoCtrl.dispose();
  }
}

class _CriarSolicitacaoDialog extends StatefulWidget {
  const _CriarSolicitacaoDialog();

  @override
  State<_CriarSolicitacaoDialog> createState() => _CriarSolicitacaoDialogState();
}

class _CriarSolicitacaoDialogState extends State<_CriarSolicitacaoDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog;

  final _numeroOSCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _observacaoCtrl = TextEditingController();
  DateTime _dataNecessidade = DateTime.now().add(const Duration(days: 1));

  final List<_ItemMaterialCriacao> _itens = [];

  @override
  void dispose() {
    _numeroOSCtrl.dispose();
    _clienteCtrl.dispose();
    _observacaoCtrl.dispose();
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  void _adicionarItem() {
    setState(() => _itens.insert(0, _ItemMaterialCriacao()));
  }

  void _removerItem(int index) {
    if (_itens.length == 1) return;
    setState(() {
      _itens[index].dispose();
      _itens.removeAt(index);
    });
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    
    // Valida se todos os itens têm material e quantidade
    for (int i = 0; i < _itens.length; i++) {
      final item = _itens[i];
      if (item.material == null) {
        setState(() => _erroDialog = 'Selecione o material do item ${i + 1}');
        return;
      }
      if (item.quantidadeCtrl.text.trim().isEmpty ||
          double.tryParse(item.quantidadeCtrl.text) == null) {
        setState(() => _erroDialog = 'Informe a quantidade do item ${i + 1}');
        return;
      }
    }

    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    final dados = {
      'numeroOS': _numeroOSCtrl.text.trim(),
      'nomeCliente': _clienteCtrl.text.trim(),
      'dataNecessidade': _dataNecessidade.toIso8601String(),
      'observacao': _observacaoCtrl.text.trim().isEmpty ? null : _observacaoCtrl.text.trim(),
    };

    final itens = _itens.map((item) => {
      'materialId': item.material!.id,
      'quantidade': double.parse(item.quantidadeCtrl.text),
      'observacao': item.observacaoCtrl.text.trim().isEmpty ? null : item.observacaoCtrl.text.trim(),
    }).toList();

    final imagensPorIndice = <int, File>{};
    for (int i = 0; i < _itens.length; i++) {
      if (_itens[i].imagem != null) {
        imagensPorIndice[i] = _itens[i].imagem!;
      }
    }

    try {
      final provider = context.read<SolicitacaoMaterialProvider>();
      final ok = await provider.criarSemCarregar(dados, itens: itens, imagensPorIndice: imagensPorIndice);

      if (!mounted) return;

      if (ok) {
        // Primeiro sai do dialog, depois recarrega a lista
        Navigator.of(context, rootNavigator: true).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitação criada'),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        setState(() {
          _salvando = false;
          _erroDialog = provider.erroLocal ?? 'Erro ao criar solicitação. Verifique os dados e tente novamente.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erroDialog = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Text('Nova Solicitação', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_erroDialog != null) ...[
                        _ErroBanner(
                          mensagem: _erroDialog!,
                          onDismiss: () => setState(() => _erroDialog = null),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _numeroOSCtrl,
                              decoration: const InputDecoration(labelText: 'Número OS *'),
                              textCapitalization: TextCapitalization.characters,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Número OS é obrigatório'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _clienteCtrl,
                              decoration: const InputDecoration(labelText: 'Nome Cliente *'),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Nome do cliente é obrigatório'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _DatePickerField(
                        label: 'Data Necessidade *',
                        value: _dataNecessidade,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                        onChanged: (d) => setState(() => _dataNecessidade = d),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _observacaoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Observação',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text('Materiais',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _adicionarItem,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Adicionar Material'),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._itens.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ItemMaterialCard(
                            index: index,
                            item: item,
                            onRemover: _itens.length > 1 ? () => _removerItem(index) : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Criar'),
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

class _ItemMaterialCard extends StatelessWidget {
  final int index;
  final _ItemMaterialCriacao item;
  final VoidCallback? onRemover;

  const _ItemMaterialCard({
    required this.index,
    required this.item,
    this.onRemover,
  });

  Future<void> _selecionarMaterial(BuildContext context) async {
    final material = await showDialog<MaterialModel>(
      context: context,
      builder: (_) => const _SeletorMaterialDialog(),
    );
    if (material != null) {
      item.material = material;
      (context as Element).markNeedsBuild();
    }
  }

  Future<void> _selecionarImagem(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      if (await file.exists()) {
        item.imagem = file;
        (context as Element).markNeedsBuild();
      }
    }
  }

  Future<void> _cadastrarMaterial(BuildContext context) async {
    final criou = await showDialog<bool>(
      context: context,
      builder: (_) => const MaterialFormDialog(),
    );
    if (criou == true && context.mounted) {
      await context.read<MaterialProvider>().carregarCategorias();
    }
  }

  Future<void> _cadastrarTemporario(BuildContext context) async {
    final criou = await showDialog<bool>(
      context: context,
      builder: (_) => const EstoqueTemporarioFormDialog(),
    );
    if (criou == true && context.mounted) {
      await context.read<EstoqueTemporarioProvider>().carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Item ${index + 1}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Cadastrar material',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 14, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        const Text(
                          'Cadastrar material',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onSelected: (v) {
                    if (v == 'material') _cadastrarMaterial(context);
                    if (v == 'temporario') _cadastrarTemporario(context);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'material',
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Cadastrar Material'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'temporario',
                      child: Row(
                        children: [
                          Icon(Icons.access_time_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Material Temporário'),
                        ],
                      ),
                    ),
                  ],
                ),
                if (onRemover != null)
                  IconButton(
                    onPressed: onRemover,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remover item',
                    color: AppTheme.error,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.error.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: () => _selecionarMaterial(context),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Material *',
                        suffixIcon: item.material != null
                            ? const Icon(Icons.check_circle, color: AppTheme.success, size: 20)
                            : const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        item.material?.nome ?? 'Toque para selecionar...',
                        style: TextStyle(
                          fontSize: 14,
                          color: item.material != null
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: item.quantidadeCtrl,
                    decoration: const InputDecoration(labelText: 'Quantidade *'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: item.observacaoCtrl,
              decoration: const InputDecoration(labelText: 'Observação'),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.imagem != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(item.imagem!, width: 60, height: 60, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Imagem anexada',
                        style: TextStyle(fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      item.imagem = null;
                      (context as Element).markNeedsBuild();
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Remover'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                  ),
                ] else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selecionarImagem(context),
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                      label: const Text('Anexar imagem'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG: VISUALIZAR/EDITAR SOLICITAÇÃO
// ═══════════════════════════════════════════════════════════════════════════

class _VisualizarSolicitacaoDialog extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;

  const _VisualizarSolicitacaoDialog({required this.solicitacao});

  @override
  State<_VisualizarSolicitacaoDialog> createState() =>
      _VisualizarSolicitacaoDialogState();
}

class _VisualizarSolicitacaoDialogState extends State<_VisualizarSolicitacaoDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _salvando = false;
  bool _houveMudanca = false;
  String? _erroDialog;
  late SolicitacaoMaterialModel _solicitacaoAtual;

  // Marcações de comprado/pendente feitas na tela mas ainda não persistidas.
  // Chave: "item:<id>" ou "adicional:<id>" — Valor: novo estado desejado.
  final Map<String, bool> _comprasPendentes = {};

  bool get _temAlteracoesNaoSalvas => _comprasPendentes.isNotEmpty;

  // Edição do cabeçalho (só ADMIN)
  late final TextEditingController _numeroOSCtrl;
  late final TextEditingController _clienteCtrl;
  late final TextEditingController _observacaoCtrl;
  late DateTime _dataNecessidade;
  late String _andamento;

  @override
  void initState() {
    super.initState();
    _solicitacaoAtual = widget.solicitacao;
    _tabCtrl = TabController(length: 3, vsync: this);
    
    _numeroOSCtrl = TextEditingController(text: _solicitacaoAtual.numeroOS);
    _clienteCtrl = TextEditingController(text: _solicitacaoAtual.nomeCliente);
    _observacaoCtrl = TextEditingController(text: _solicitacaoAtual.observacao ?? '');
    _dataNecessidade = _solicitacaoAtual.dataNecessidade;
    _andamento = _solicitacaoAtual.andamento;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SolicitacaoMaterialProvider>().carregarLogs(_solicitacaoAtual.id);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _numeroOSCtrl.dispose();
    _clienteCtrl.dispose();
    _observacaoCtrl.dispose();
    super.dispose();
  }

  bool get _ehAdmin {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    return usuario?.role == 'ADMIN';
  }

  bool get _podeAdicionarMateriais {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    if (usuario == null) return false;
    final ehAdmin = usuario.role.trim().toUpperCase() == 'ADMIN';
    final ehCriador = usuario.id.toString() == _solicitacaoAtual.usuarioId.toString();
    return ehAdmin || ehCriador;
  }

  // Registra/desfaz uma alteração local de comprado (não chama a API ainda).
  void _alterarCompradoLocal(String tipo, int id, bool valorOriginal, bool novoValor) {
    final chave = '$tipo:$id';
    setState(() {
      if (novoValor == valorOriginal) {
        _comprasPendentes.remove(chave);
      } else {
        _comprasPendentes[chave] = novoValor;
      }
    });
  }

  // Persiste todas as marcações pendentes no backend. Retorna true se tudo ok.
  Future<bool> _persistirComprasPendentes() async {
    final provider = context.read<SolicitacaoMaterialProvider>();
    final pendentes = Map<String, bool>.from(_comprasPendentes);

    for (final entry in pendentes.entries) {
      final partes = entry.key.split(':');
      final tipo = partes[0];
      final id = int.parse(partes[1]);
      try {
        if (tipo == 'item') {
          await provider.marcarItemComprado(id, comprado: entry.value);
        } else {
          await provider.marcarAdicionalComprado(id, comprado: entry.value);
        }
      } catch (e) {
        if (mounted) {
          final mensagem = 'Erro ao salvar materiais: ${e.toString().replaceFirst('Exception: ', '')}';
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Erro ao salvar'),
              content: Text(mensagem),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return false;
      }
    }

    if (mounted) {
      setState(() {
        _comprasPendentes.clear();
        _houveMudanca = true;
      });
    }
    await _recarregarSolicitacao();
    // Sincroniza _andamento local com o valor retornado pelo backend
    // (pode ter sido auto-finalizado se todos os itens foram marcados como comprados)
    if (mounted) {
      setState(() => _andamento = _solicitacaoAtual.andamento);
    }
    return true;
  }

  // Ponto único de fechamento do diálogo (X, "Fechar", ESC, clique fora).
  // Se houver marcações não salvas, pede confirmação antes de fechar.
  Future<void> _tentarFechar() async {
    if (!_temAlteracoesNaoSalvas) {
      Navigator.pop(context, _houveMudanca ? true : null);
      return;
    }

    final decisao = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterações não salvas'),
        content: const Text(
          'Você marcou materiais como comprado ou pendente, mas ainda não salvou. '
          'Deseja salvar essas alterações antes de fechar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'salvar'),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (!mounted || decisao == null) return;

    if (decisao == 'salvar') {
      setState(() => _salvando = true);
      final ok = await _persistirComprasPendentes();
      if (!mounted) return;
      setState(() => _salvando = false);
      if (ok) {
        Navigator.pop(context, true);
      }
      // Se falhar, o diálogo permanece aberto com o erro exibido.
    } else if (decisao == 'cancelar') {
      setState(() => _comprasPendentes.clear());
      Navigator.pop(context, _houveMudanca ? true : null);
    }
  }

  Future<void> _recarregarSolicitacao() async {
    try {
      final provider = context.read<SolicitacaoMaterialProvider>();
      final atualizada = await provider.repository.buscarPorId(_solicitacaoAtual.id);
      if (mounted) {
        setState(() {
          _solicitacaoAtual = atualizada;
          _houveMudanca = true;
        });
      }
    } catch (e) {
      debugPrint('Erro ao recarregar solicitação: $e');
    }
  }

  Future<void> _salvarCabecalho() async {
    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    // Primeiro persiste marcações de comprado/pendente (qualquer usuário com permissão de marcar).
    if (_temAlteracoesNaoSalvas) {
      final ok = await _persistirComprasPendentes();
      if (!ok || !mounted) {
        if (mounted) setState(() => _salvando = false);
        return;
      }
    }

    // Cabeçalho (Dados) só pode ser alterado por ADMIN.
    if (!_ehAdmin) {
      if (!mounted) return;
      setState(() => _salvando = false);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Alterações salvas'), backgroundColor: AppTheme.success),
      );
      return;
    }

    // Valida se pode finalizar
    if (_andamento == 'FINALIZADO' && !_solicitacaoAtual.todosComprados) {
      setState(() => _erroDialog = 
        'Não é possível finalizar: existem materiais ainda não marcados como comprados.');
      setState(() => _salvando = false);
      return;
    }

    final dados = {
      'numeroOS': _numeroOSCtrl.text.trim(),
      'nomeCliente': _clienteCtrl.text.trim(),
      'dataNecessidade': _dataNecessidade.toIso8601String(),
      'andamento': _andamento,
      'observacao': _observacaoCtrl.text.trim().isEmpty ? null : _observacaoCtrl.text.trim(),
    };

    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.atualizar(_solicitacaoAtual.id, dados);

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitação atualizada'), backgroundColor: AppTheme.success),
      );
    } else {
      // Captura a mensagem antes de limpar o erro no provider para evitar
      // que o notifyListeners() do provider exiba o erro na página por trás
      // do dialog (Consumer na SolicitacoesMaterialPage).
      final mensagem = provider.erro ?? 'Erro ao salvar';
      provider.limparErro();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Não foi possível salvar'),
          content: Text(mensagem),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _adicionarMateriais() async {
    final salvou = await showDialog<bool>(
      context: context,
      builder: (_) => _AdicionarMateriaisDialog(solicitacao: _solicitacaoAtual),
    );
    if (salvou == true && mounted) {
      await _recarregarSolicitacao();
    }
  }

  Future<void> _excluirSolicitacao() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Solicitação'),
        content: Text(
          'Tem certeza que deseja excluir a solicitação OS ${_solicitacaoAtual.numeroOS}? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirma != true || !mounted) return;

    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.excluir(_solicitacaoAtual.id);

    if (!mounted) return;

    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitação excluída'), backgroundColor: AppTheme.success),
      );
    } else {
      final mensagemErro = provider.erro ?? 'Erro ao excluir';
      provider.limparErro();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erro ao excluir'),
          content: Text(mensagemErro),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _reabrirSolicitacao() async {
    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.atualizar(_solicitacaoAtual.id, {'andamento': 'EM_ANDAMENTO'});
    if (!mounted) return;
    if (ok) {
      await _recarregarSolicitacao();
      setState(() => _andamento = 'EM_ANDAMENTO');
    } else {
      final mensagem = provider.erro ?? 'Erro ao reabrir solicitação';
      provider.limparErro();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erro'),
          content: Text(mensagem),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_temAlteracoesNaoSalvas,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _tentarFechar();
        }
      },
      child: Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Solicitação OS ${_solicitacaoAtual.numeroOS}',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          'Cliente: ${_solicitacaoAtual.nomeCliente}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _tentarFechar,
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            // Abas
            TabBar(
              controller: _tabCtrl,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              indicatorColor: AppTheme.primary,
              tabs: const [
                Tab(text: 'Materiais'),
                Tab(text: 'Dados'),
                Tab(text: 'Histórico'),
              ],
            ),
            const Divider(height: 0),
            Flexible(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // Aba Materiais
                  _AbaMateriaisSolicitacao(
                    solicitacao: _solicitacaoAtual,
                    comprasPendentes: _comprasPendentes,
                    onToggleComprado: _alterarCompradoLocal,
                    onReabrirSolicitacao: _ehAdmin ? _reabrirSolicitacao : null,
                  ),
                  // Aba Dados
                  _AbaDadosSolicitacao(
                    solicitacao: _solicitacaoAtual,
                    numeroOSCtrl: _numeroOSCtrl,
                    clienteCtrl: _clienteCtrl,
                    observacaoCtrl: _observacaoCtrl,
                    dataNecessidade: _dataNecessidade,
                    andamento: _andamento,
                    onDataNecessidadeChanged: (d) => setState(() => _dataNecessidade = d),
                    onAndamentoChanged: (a) => setState(() => _andamento = a),
                    ehAdmin: _ehAdmin,
                    erroDialog: _erroDialog,
                    onDismissErro: () => setState(() => _erroDialog = null),
                  ),
                  // Aba Histórico
                  _AbaHistorico(solicitacaoId: _solicitacaoAtual.id),
                ],
              ),
            ),
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (_podeAdicionarMateriais)
                  FilledButton.icon(
                    onPressed: _adicionarMateriais,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Adicionar Materiais'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_ehAdmin)
                    OutlinedButton.icon(
                      onPressed: _excluirSolicitacao,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Excluir'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _tentarFechar,
                    child: const Text('Fechar'),
                  ),
                  if (_ehAdmin || _temAlteracoesNaoSalvas) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _salvando ? null : _salvarCabecalho,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                      child: _salvando
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Salvar'),
                    ),
                  ],
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

// ─── Aba Materiais ────────────────────────────────────────────────────────────

class _AbaMateriaisSolicitacao extends StatelessWidget {
  final SolicitacaoMaterialModel solicitacao;
  final Map<String, bool> comprasPendentes;
  final void Function(String tipo, int id, bool valorOriginal, bool novoValor) onToggleComprado;
  final VoidCallback? onReabrirSolicitacao;

  const _AbaMateriaisSolicitacao({
    required this.solicitacao,
    required this.comprasPendentes,
    required this.onToggleComprado,
    this.onReabrirSolicitacao,
  });

  @override
  Widget build(BuildContext context) {
    final itensOriginais = solicitacao.itens;
    final adicionais = solicitacao.adicionais;

    if (itensOriginais.isEmpty && adicionais.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('Nenhum material solicitado',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (itensOriginais.isNotEmpty) ...[
          Text('Materiais Originais',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...itensOriginais.map((item) {
            final chave = 'item:${item.id}';
            final pendente = comprasPendentes.containsKey(chave);
            final compradoEfetivo = comprasPendentes[chave] ?? item.comprado;
            return _MaterialCard(
              tipo: 'item',
              id: item.id,
              materialNome: item.materialNome,
              materialUnidade: item.materialUnidade,
              materialIdentificador: item.materialIdentificador,
              materialMedida: item.materialMedida,
              materialEspessura: item.materialEspessura,
              materialCategoria: item.materialCategoria,
              materialEstoque: item.materialQuantidadeEstoque,
              quantidade: item.quantidade,
              observacao: item.observacao,
              imagemUrl: item.imagemUrl,
              comprado: compradoEfetivo,
              pendente: pendente,
              compradoEm: item.compradoEm,
              compradoPorNome: item.compradoPorNome,
              criadoEm: item.criadoEm,
              andamento: solicitacao.andamento,
              onToggle: (novoValor) =>
                  onToggleComprado('item', item.id, item.comprado, novoValor),
              onReabrirSolicitacao: onReabrirSolicitacao,
            );
          }),
        ],
        if (adicionais.isNotEmpty) ...[
          if (itensOriginais.isNotEmpty) const SizedBox(height: 24),
          Text('Materiais Adicionais',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...adicionais.map((ad) {
            final chave = 'adicional:${ad.id}';
            final pendente = comprasPendentes.containsKey(chave);
            final compradoEfetivo = comprasPendentes[chave] ?? ad.comprado;
            return _MaterialCard(
              tipo: 'adicional',
              id: ad.id,
              materialNome: ad.materialNome,
              materialUnidade: ad.materialUnidade,
              materialIdentificador: ad.materialIdentificador,
              materialMedida: ad.materialMedida,
              materialEspessura: ad.materialEspessura,
              materialCategoria: ad.materialCategoria,
              materialEstoque: ad.materialQuantidadeEstoque,
              quantidade: ad.quantidade,
              observacao: ad.observacao,
              imagemUrl: ad.imagemUrl,
              comprado: compradoEfetivo,
              pendente: pendente,
              compradoEm: ad.compradoEm,
              compradoPorNome: ad.compradoPorNome,
              criadoEm: ad.adicionadoEm,
              adicionadoPorNome: ad.adicionadoPorNome,
              andamento: solicitacao.andamento,
              onToggle: (novoValor) =>
                  onToggleComprado('adicional', ad.id, ad.comprado, novoValor),
              onReabrirSolicitacao: onReabrirSolicitacao,
            );
          }),
        ],
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final String tipo; // 'item' ou 'adicional'
  final int id;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialCategoria;
  final double materialEstoque;
  final double quantidade;
  final String? observacao;
  final String? imagemUrl;
  final bool comprado; // valor efetivo (já considera alteração pendente não salva)
  final bool pendente; // true quando há alteração local ainda não persistida
  final DateTime? compradoEm;
  final String? compradoPorNome;
  final DateTime criadoEm;
  final String? adicionadoPorNome;
  final String andamento;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onReabrirSolicitacao;

  const _MaterialCard({
    required this.tipo,
    required this.id,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.materialCategoria,
    required this.materialEstoque,
    required this.quantidade,
    this.observacao,
    this.imagemUrl,
    required this.comprado,
    required this.pendente,
    this.compradoEm,
    this.compradoPorNome,
    required this.criadoEm,
    this.adicionadoPorNome,
    required this.andamento,
    required this.onToggle,
    this.onReabrirSolicitacao,
  });

  void _handleToggle(BuildContext context) {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    final ehAdmin = usuario?.role.trim().toUpperCase() == 'ADMIN';
    final novoValor = !comprado;

    // Bloqueia qualquer alteração se a solicitação está FINALIZADA
    if (andamento == 'FINALIZADO') {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Solicitação finalizada'),
          content: const Text(
            'Esta solicitação está finalizada. Para alterar os itens, reabra-a primeiro.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            if (ehAdmin)
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                child: const Text('Reabrir'),
              ),
          ],
        ),
      ).then((reabrir) {
        if (reabrir == true) onReabrirSolicitacao?.call();
      });
      return;
    }

    // Se está tentando desmarcar e não é admin, bloqueia
    if (!novoValor && !ehAdmin) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ação não permitida'),
          content: const Text('Apenas administradores podem desmarcar um item como comprado.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    onToggle(novoValor);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(materialNome,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (tipo == 'adicional') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_circle_outline,
                                      size: 11, color: Color(0xFF0D9488)),
                                  SizedBox(width: 3),
                                  Text('EXTRA',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0D9488),
                                        letterSpacing: 0.3,
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Quantidade: ${quantidade % 1 == 0 ? quantidade.toStringAsFixed(0) : quantidade.toStringAsFixed(2)}${materialUnidade != null ? ' $materialUnidade' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      // Atributos do material
                      Builder(builder: (context) {
                        final atributos = <String>[];
                        if (materialIdentificador != null && materialIdentificador!.isNotEmpty)
                          atributos.add(materialIdentificador!);
                        if (materialMedida != null && materialMedida!.isNotEmpty)
                          atributos.add(materialMedida!);
                        if (materialEspessura != null && materialEspessura!.isNotEmpty)
                          atributos.add(materialEspessura!);
                        if (materialCategoria != null && materialCategoria!.isNotEmpty)
                          atributos.add(materialCategoria!);
                        if (atributos.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            atributos.join(' · '),
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.outline),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                      // Estoque atual
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Estoque: ${materialEstoque % 1 == 0 ? materialEstoque.toStringAsFixed(0) : materialEstoque.toStringAsFixed(2)}${materialUnidade != null ? ' $materialUnidade' : ''}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
                _CompradoToggle(
                  comprado: comprado,
                  pendente: pendente,
                  onTap: () => _handleToggle(context),
                ),
              ],
            ),
            if (observacao != null && observacao!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Observação: $observacao',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
            ],
            if (imagemUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(_resolverUrl(imagemUrl!),
                    height: 100, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                          height: 100,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Center(child: Icon(Icons.broken_image)),
                        )),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                // Adicionais: funde data e autor em uma chip roxa
                if (tipo == 'adicional' && adicionadoPorNome != null)
                  _InfoChip(
                    icon: Icons.add_circle_outline,
                    label:
                        'Adicionado em ${DateFormat('dd/MM/yyyy HH:mm').format(criadoEm)} por $adicionadoPorNome',
                    color: const Color(0xFF0D9488),
                  )
                else ...[
                  _InfoChip(
                    icon: Icons.schedule,
                    label:
                        'Adicionado em ${DateFormat('dd/MM/yyyy HH:mm').format(criadoEm)}',
                  ),
                  if (adicionadoPorNome != null)
                    _InfoChip(
                      icon: Icons.person_outline,
                      label: 'Por $adicionadoPorNome',
                    ),
                ],
                if (comprado && compradoEm != null)
                  _InfoChip(
                    icon: Icons.shopping_cart,
                    label:
                        'Comprado em ${DateFormat('dd/MM/yyyy HH:mm').format(compradoEm!)}',
                    color: AppTheme.success,
                  ),
                if (comprado && compradoPorNome != null)
                  _InfoChip(
                    icon: Icons.person,
                    label: 'Por $compradoPorNome',
                    color: AppTheme.success,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompradoToggle extends StatelessWidget {
  final bool comprado;
  final bool pendente;
  final VoidCallback onTap;

  const _CompradoToggle({
    required this.comprado,
    required this.onTap,
    this.pendente = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: comprado
                  ? AppTheme.success.withValues(alpha: 0.15)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: pendente
                    ? AppTheme.error
                    : (comprado
                        ? AppTheme.success
                        : Theme.of(context).colorScheme.outlineVariant),
                width: pendente ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  comprado ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: comprado
                      ? AppTheme.success
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  comprado ? 'COMPRADO' : 'PENDENTE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: comprado
                        ? AppTheme.success
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (pendente) ...[
          const SizedBox(height: 4),
          Text(
            'Não salvo',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppTheme.error,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: chipColor)),
        ],
      ),
    );
  }
}

// ─── Aba Dados ────────────────────────────────

class _AbaDadosSolicitacao extends StatelessWidget {
  final SolicitacaoMaterialModel solicitacao;
  final TextEditingController numeroOSCtrl;
  final TextEditingController clienteCtrl;
  final TextEditingController observacaoCtrl;
  final DateTime dataNecessidade;
  final String andamento;
  final ValueChanged<DateTime> onDataNecessidadeChanged;
  final ValueChanged<String> onAndamentoChanged;
  final bool ehAdmin;
  final String? erroDialog;
  final VoidCallback onDismissErro;

  const _AbaDadosSolicitacao({
    required this.solicitacao,
    required this.numeroOSCtrl,
    required this.clienteCtrl,
    required this.observacaoCtrl,
    required this.dataNecessidade,
    required this.andamento,
    required this.onDataNecessidadeChanged,
    required this.onAndamentoChanged,
    required this.ehAdmin,
    this.erroDialog,
    required this.onDismissErro,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (erroDialog != null) ...[
            _ErroBanner(mensagem: erroDialog!, onDismiss: onDismissErro),
            const SizedBox(height: 16),
          ],
          if (!ehAdmin) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 16, color: Color(0xFF1E88E5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Apenas administradores podem editar os dados da solicitação.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF1E88E5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: numeroOSCtrl,
                  readOnly: !ehAdmin,
                  decoration: const InputDecoration(labelText: 'Número OS'),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: clienteCtrl,
                  readOnly: !ehAdmin,
                  decoration: const InputDecoration(labelText: 'Nome Cliente'),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: DateFormat('dd/MM/yyyy HH:mm').format(solicitacao.dataSolicitacao),
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Data Solicitação',
              suffixIcon: Icon(Icons.lock_outline, size: 16,
                  color: Theme.of(context).colorScheme.outline),
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (ehAdmin)
            _DatePickerField(
              label: 'Data Necessidade',
              value: dataNecessidade,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              onChanged: onDataNecessidadeChanged,
            )
          else
            TextFormField(
              initialValue: DateFormat('dd/MM/yyyy').format(dataNecessidade),
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Data Necessidade'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: andamento,
            decoration: const InputDecoration(labelText: 'Andamento', isDense: true),
            items: const [
              DropdownMenuItem(value: 'EM_ANDAMENTO', child: Text('EM ANDAMENTO')),
              DropdownMenuItem(value: 'FINALIZADO', child: Text('FINALIZADO')),
            ],
            onChanged: ehAdmin ? (v) => onAndamentoChanged(v!) : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: observacaoCtrl,
            readOnly: !ehAdmin,
            decoration: const InputDecoration(
              labelText: 'Observação',
              alignLabelWithHint: true,
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          Text('Solicitante: ${solicitacao.usuarioNome}',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─── Aba Histórico ────────────────────────────────────────────────────────

class _AbaHistorico extends StatelessWidget {
  final int solicitacaoId;
  const _AbaHistorico({required this.solicitacaoId});

  static const _camposLabel = {
    'numeroOS': 'Número OS',
    'nomeCliente': 'Cliente',
    'dataNecessidade': 'Data Necessidade',
    'andamento': 'Andamento',
    'observacao': 'Observação',
  };

  String _fmt(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
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
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (prov.logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                Text('Nenhuma edição registrada',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            final campos = <String>[];
            for (final key in log.depois.keys) {
              final antes = log.antes[key]?.toString();
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
                        const Icon(Icons.edit_note, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(log.editorNome,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                        Text(DateFormat('dd/MM/yyyy HH:mm').format(log.editadoEm),
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    if (campos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 0),
                      const SizedBox(height: 8),
                      ...campos.map((campo) {
                        final label = _camposLabel[campo] ?? campo;
                        final antes = _fmt(log.antes[campo]);
                        final depois = _fmt(log.depois[campo]);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(label,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.error.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('− $antes',
                                          style: const TextStyle(
                                              fontSize: 11, color: AppTheme.error),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.success.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('+ $depois',
                                          style: const TextStyle(
                                              fontSize: 11, color: AppTheme.success),
                                          overflow: TextOverflow.ellipsis),
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

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG: ADICIONAR MATERIAIS (adicional)
// ═══════════════════════════════════════════════════════════════════════════

class _AdicionarMateriaisDialog extends StatefulWidget {
  final SolicitacaoMaterialModel solicitacao;

  const _AdicionarMateriaisDialog({required this.solicitacao});

  @override
  State<_AdicionarMateriaisDialog> createState() => _AdicionarMateriaisDialogState();
}

class _AdicionarMateriaisDialogState extends State<_AdicionarMateriaisDialog> {
  bool _salvando = false;
  String? _erroDialog;

  final List<_ItemMaterialCriacao> _itens = [];

  @override
  void dispose() {
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  void _adicionarItem() {
    setState(() => _itens.insert(0, _ItemMaterialCriacao()));
  }

  void _removerItem(int index) {
    if (_itens.length == 1) return;
    setState(() {
      _itens[index].dispose();
      _itens.removeAt(index);
    });
  }

  Future<void> _salvar() async {
    for (int i = 0; i < _itens.length; i++) {
      final item = _itens[i];
      if (item.material == null) {
        setState(() => _erroDialog = 'Selecione o material do item ${i + 1}');
        return;
      }
      if (item.quantidadeCtrl.text.trim().isEmpty ||
          double.tryParse(item.quantidadeCtrl.text) == null) {
        setState(() => _erroDialog = 'Informe a quantidade do item ${i + 1}');
        return;
      }
    }

    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    final itens = _itens.map((item) => {
      'materialId': item.material!.id,
      'quantidade': double.parse(item.quantidadeCtrl.text),
      'observacao': item.observacaoCtrl.text.trim().isEmpty
          ? null
          : item.observacaoCtrl.text.trim(),
    }).toList();

    final imagensPorIndice = <int, File>{};
    for (int i = 0; i < _itens.length; i++) {
      if (_itens[i].imagem != null) {
        imagensPorIndice[i] = _itens[i].imagem!;
      }
    }

    final provider = context.read<SolicitacaoMaterialProvider>();
    final ok = await provider.adicionarMateriais(
      widget.solicitacao.id,
      itens: itens,
      imagensPorIndice: imagensPorIndice,
    );

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Materiais adicionados'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() => _erroDialog = provider.erro ?? 'Erro ao adicionar materiais');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adicionar Materiais',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text('OS ${widget.solicitacao.numeroOS}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erroDialog != null) ...[
                      _ErroBanner(
                        mensagem: _erroDialog!,
                        onDismiss: () => setState(() => _erroDialog = null),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Text('Materiais',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _adicionarItem,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Adicionar Material'),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._itens.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ItemMaterialCard(
                          index: index,
                          item: item,
                          onRemover: _itens.length > 1 ? () => _removerItem(index) : null,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Adicionar'),
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

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS AUXILIARES
// ═══════════════════════════════════════════

class _ErroBanner extends StatelessWidget {
  final String mensagem;
  final VoidCallback onDismiss;
  const _ErroBanner({required this.mensagem, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensagem,
                style: const TextStyle(color: AppTheme.error, fontSize: 13)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: AppTheme.error, size: 16),
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
            lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
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

// ═══════════════════════════════════════════════════════════════════════════
// SELETOR DE MATERIAL (reutilizado do código original)
// ═══════════════════════════════════════════

const _kSelCategoriaGeral = '__GERAL__';
const _kSelCategoriaSemCategoria = '__SEM_CATEGORIA__';

class _SeletorMaterialDialog extends StatefulWidget {
  const _SeletorMaterialDialog();

  @override
  State<_SeletorMaterialDialog> createState() => _SeletorMaterialDialogState();
}

class _SeletorMaterialDialogState extends State<_SeletorMaterialDialog> {
  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0x00ffb300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  String? _categoriaSelecionada;
  String _categoriaLabel = '';
  Color _categoriaCor = AppTheme.primary;
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria = '';
  final _buscaCtrl = TextEditingController();
  final _buscaIdCtrl = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl = TextEditingController();
  final _espessuraCtrl = TextEditingController();
  String _statusFiltro = '';
  Timer? _debounceTimer;
  bool _carregandoMateriais = false;
  List<MaterialModel> _materiais = [];
  String? _identificadorSelecionado;

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

  Future<void> _abrirCategoria(String id, String label, Color cor) async {
    setState(() {
      _categoriaSelecionada = id;
      _categoriaLabel = label;
      _categoriaCor = cor;
      _identificadorSelecionado = null;
      _filtroCategoria = '';
      _filtroCategoriaCtrl.clear();
      _buscaCtrl.clear();
      _buscaIdCtrl.clear();
      _identificadorCtrl.clear();
      _medidaCtrl.clear();
      _espessuraCtrl.clear();
      _statusFiltro = '';
      _carregandoMateriais = true;
      _materiais = [];
    });
    await _carregarMateriais();
  }

  Future<void> _carregarMateriais() async {
    final prov = context.read<MaterialProvider>();
    await prov.carregar(
      busca: _buscaCtrl.text.trim(),
      id: _buscaIdCtrl.text.trim(),
      identificador: _identificadorCtrl.text.trim(),
      medida: _medidaCtrl.text.trim(),
      espessura: _espessuraCtrl.text.trim(),
      status: _statusFiltro,
      categoria: _categoriaParaProvider(_categoriaSelecionada!),
    );
    if (mounted) {
      setState(() {
        _materiais = prov.materiais;
        _carregandoMateriais = false;
      });
    }
  }

  bool get _categoriaTemIdentificadores {
    if (_categoriaSelecionada == _kSelCategoriaGeral ||
        _categoriaSelecionada == _kSelCategoriaSemCategoria) {
      return false;
    }
    return _materiais.any(
        (m) => m.identificador != null && m.identificador!.trim().isNotEmpty);
  }

  void _aplicarFiltrosMateriais() {
    setState(() => _carregandoMateriais = true);
    _carregarMateriais();
  }

  Future<void> _cadastrarMaterial(BuildContext context) async {
    final criou = await showDialog<bool>(
      context: context,
      builder: (_) => const MaterialFormDialog(),
    );
    if (criou == true && mounted) {
      await context.read<MaterialProvider>().carregarCategorias();
      if (_categoriaSelecionada != null) {
        _aplicarFiltrosMateriais();
      }
    }
  }

  Future<void> _cadastrarTemporario(BuildContext context) async {
    final criou = await showDialog<bool>(
      context: context,
      builder: (_) => const EstoqueTemporarioFormDialog(),
    );
    if (criou == true && mounted) {
      await context.read<EstoqueTemporarioProvider>().carregar();
      if (_categoriaSelecionada != null) {
        _aplicarFiltrosMateriais();
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  if (_categoriaSelecionada != null)
                    IconButton(
                      onPressed: () {
                        if (_identificadorSelecionado != null &&
                            _categoriaTemIdentificadores) {
                          setState(() {
                            _identificadorSelecionado = null;
                            _identificadorCtrl.clear();
                            _buscaCtrl.clear();
                            _buscaIdCtrl.clear();
                            _medidaCtrl.clear();
                            _espessuraCtrl.clear();
                            _filtroCategoria = '';
                            _filtroCategoriaCtrl.clear();
                          });
                          _aplicarFiltrosMateriais();
                        } else {
                          setState(() => _categoriaSelecionada = null);
                        }
                      },
                      icon: const Icon(Icons.arrow_back, size: 20),
                      tooltip: _identificadorSelecionado != null &&
                              _categoriaTemIdentificadores
                          ? 'Voltar aos identificadores'
                          : 'Voltar às categorias',
                    ),
                  Expanded(
                    child: Text(
                      _categoriaSelecionada == null
                          ? 'Selecionar Material'
                          : _identificadorSelecionado != null
                              ? '$_categoriaLabel › ${_identificadorSelecionado == "__SEM__" ? "Sem identificador" : _identificadorSelecionado}'
                              : _categoriaLabel,
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Cadastrar material',
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onSelected: (v) {
                      if (v == 'material') _cadastrarMaterial(context);
                      if (v == 'temporario') _cadastrarTemporario(context);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'material',
                        child: Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Cadastrar Material'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'temporario',
                        child: Row(
                          children: [
                            Icon(Icons.access_time_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Material Temporário'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }

        final todasCategorias = prov.categorias;
        final categoriasVisiveis = _filtroCategoria.isEmpty
            ? todasCategorias
            : todasCategorias
                .where((c) =>
                    c.toLowerCase().contains(_filtroCategoria.toLowerCase()))
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
                  prefixIcon: Icon(Icons.search, size: 18,
                      color: Theme.of(context).colorScheme.outline),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filtroCategoria = v),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                    label: cat['label'] as String,
                    cor: cor,
                    icone: cat['icon'] as IconData,
                    onTap:() => _abrirCategoria(
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
    if (!_carregandoMateriais &&
        _materiais.isNotEmpty &&
        _categoriaTemIdentificadores &&
        _identificadorSelecionado == null) {
      return _buildGridIdentificadores(context);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _buscaIdCtrl,
                      decoration: InputDecoration(
                        hintText: 'ID',
                        prefixIcon: Icon(Icons.tag, size: 16,
                            color: Theme.of(context).colorScheme.outline),
                        isDense: true,
                        suffixIcon: _buscaIdCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _buscaIdCtrl.clear();
                                  _aplicarFiltrosMateriais();
                                })
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        _debounceTimer?.cancel();
                        _debounceTimer = Timer(
                            const Duration(milliseconds: 350),
                            _aplicarFiltrosMateriais);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _buscaCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome...',
                        prefixIcon: Icon(Icons.search, size: 18,
                            color: Theme.of(context).colorScheme.outline),
                        isDense: true,
                        suffixIcon: _buscaCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _buscaCtrl.clear();
                                  _aplicarFiltrosMateriais();
                                })
                            : null,
                      ),
                      onChanged: (_) {
                        _debounceTimer?.cancel();
                        _debounceTimer = Timer(
                            const Duration(milliseconds: 350),
                            _aplicarFiltrosMateriais);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _identificadorCtrl,
                      decoration: InputDecoration(
                        hintText: 'Identificador',
                        isDense: true,
                        suffixIcon: _identificadorCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _identificadorCtrl.clear();
                                  _aplicarFiltrosMateriais();
                                })
                            : null,
                      ),
                      onChanged: (_) {
                        _debounceTimer?.cancel();
                        _debounceTimer = Timer(
                            const Duration(milliseconds: 350),
                            _aplicarFiltrosMateriais);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _medidaCtrl,
                      decoration: InputDecoration(
                        hintText: 'Medida',
                        isDense: true,
                        suffixIcon: _medidaCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _medidaCtrl.clear();
                                  _aplicarFiltrosMateriais();
                                })
                            : null,
                      ),
                      onChanged: (_) {
                        _debounceTimer?.cancel();
                        _debounceTimer = Timer(
                            const Duration(milliseconds: 350),
                            _aplicarFiltrosMateriais);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _espessuraCtrl,
                      decoration: InputDecoration(
                        hintText: 'Espessura',
                        isDense: true,
                        suffixIcon: _espessuraCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _espessuraCtrl.clear();
                                  _aplicarFiltrosMateriais();
                                })
                            : null,
                      ),
                      onChanged: (_) {
                        _debounceTimer?.cancel();
                        _debounceTimer = Timer(
                            const Duration(milliseconds: 350),
                            _aplicarFiltrosMateriais);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Limpar filtros',
                    icon: Icon(Icons.filter_alt_off, size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: () {
                      _buscaCtrl.clear();
                      _buscaIdCtrl.clear();
                      _identificadorCtrl.clear();
                      _medidaCtrl.clear();
                      _espessuraCtrl.clear();
                      setState(() {
                        _statusFiltro = '';
                        _identificadorSelecionado = null;
                      });
                      _aplicarFiltrosMateriais();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: _carregandoMateriais
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _materiais.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text('Nenhum material encontrado',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: _materiais.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _MaterialItemSeletor(
                        material: _materiais[i],
                        cor: _categoriaCor,
                        onTap: () => Navigator.of(context, rootNavigator: true)
                            .pop(_materiais[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildGridIdentificadores(BuildContext context) {
    final Map<String, List<MaterialModel>> grupos = {};
    for (final m in _materiais) {
      final key = (m.identificador != null && m.identificador!.trim().isNotEmpty)
          ? m.identificador!.trim().toUpperCase()
          : '__SEM__';
      grupos.putIfAbsent(key, () => []).add(m);
    }

    final chaves = grupos.keys.toList()..sort();
    if (chaves.remove('__SEM__')) chaves.add('__SEM__');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _filtroCategoriaCtrl,
            decoration: InputDecoration(
              hintText: 'Filtrar identificadores...',
              prefixIcon: Icon(Icons.search, size: 18,
                  color: Theme.of(context).colorScheme.outline),
              isDense: true,
              suffixIcon: _filtroCategoria.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _filtroCategoriaCtrl.clear();
                        setState(() => _filtroCategoria = '');
                      })
                  : null,
            ),
            onChanged: (v) => setState(() => _filtroCategoria = v),
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: Builder(builder: (context) {
            final filtrados = _filtroCategoria.isEmpty
                ? chaves
                : chaves
                    .where((k) =>
                        k.toLowerCase().contains(_filtroCategoria.toLowerCase()))
                    .toList();

            if (filtrados.isEmpty) {
              return Center(
                child: Text('Nenhum identificador encontrado',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.6,
              ),
              itemCount: filtrados.length,
              itemBuilder: (_, i) {
                final key = filtrados[i];
                final label = key == '__SEM__' ? 'SEM IDENTIFICADOR' : key;
                final qtd = grupos[key]!.length;
                final cor = _cores[i % _cores.length];
                return _CategoriaCardSeletor(
                  label: '$label\n$qtd ${qtd == 1 ? 'material' : 'materiais'}',
                  cor: cor,
                  icone: Icons.label_outline,
                  onTap: () {
                    setState(() {
                      _identificadorSelecionado = key;
                      _identificadorCtrl.text = key == '__SEM__' ? '' : key;
                    });
                    _aplicarFiltrosMateriais();
                  },
                );
              },
            );
          }),
        ),
      ],
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
  State<_CategoriaCardSeletor> createState() => _CategoriaCardSeletorState();
}

class _CategoriaCardSeletorState extends State<_CategoriaCardSeletor> {
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
              color: ativo ? widget.cor : widget.cor.withValues(alpha: 0.25),
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
                child: Icon(widget.icone, color: widget.cor, size: 24),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ativo
                          ? widget.cor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
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
  State<_MaterialItemSeletor> createState() => _MaterialItemSeletorState();
}

class _MaterialItemSeletorState extends State<_MaterialItemSeletor> {
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.cor.withValues(alpha: 0.10)
                : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
                child: Icon(Icons.inventory_2, color: widget.cor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nome,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    if (detalhes.isNotEmpty)
                      Text(detalhes,
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).colorScheme.outline),
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${m.quantidade.toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2)} ${m.unidade ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18,
                  color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}