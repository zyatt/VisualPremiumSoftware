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
import '../repositories/fornecedor_repository.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FORMATTER: MAIÚSCULAS SEM ACENTOS
// ─────────────────────────────────────────────────────────────────────────────

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
      baseOffset:   newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────

class OrdemCompraPage extends StatefulWidget {
  /// Quando informado, abre automaticamente os detalhes desta OC ao entrar na página.
  final int? ocIdParaAbrir;

  const OrdemCompraPage({super.key, this.ocIdParaAbrir});

  @override
  State<OrdemCompraPage> createState() => OrdemCompraPageState();
}

class OrdemCompraPageState extends State<OrdemCompraPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _buscaNumeroCtrl      = TextEditingController();
  final _buscaNomeCtrl        = TextEditingController();
  final _buscaMedidaCtrl      = TextEditingController();
  final _buscaEspessuraCtrl   = TextEditingController();
  final _buscaIdentificadorCtrl = TextEditingController();
  final _buscaIdCtrl          = TextEditingController();
  String _filtroBuscaNumero      = '';
  String _filtroBuscaNome        = '';
  String _filtroBuscaMedida      = '';
  String _filtroBuscaEspessura   = '';
  String _filtroBuscaIdentificador = '';
  String _filtroBuscaId          = '';

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

      // Prioridade 1: OC pendente setada pelo orçamento antes de navegar
      // (funciona mesmo em StatefulShellRoute, onde initState pode não re-executar).
      final ocPendente = provider.consumirOcPendente();
      final idAlvo = ocPendente ?? widget.ocIdParaAbrir;

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

  /// Chamado externamente (via GlobalKey) quando a branch já está montada
  /// e o initState não será re-executado (StatefulShellRoute preserva estado).
  /// Recarrega as OCs e abre os detalhes da OC com o [id] informado.
  Future<void> abrirOcPorId(int id) async {
    if (!mounted) return;
    final provider = context.read<OrdemCompraProvider>();
    await provider.carregar();
    if (!mounted) return;
    final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
    final raw = todas.cast<dynamic>().firstWhere(
      (o) {
        final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
        return m.id == id;
      },
      orElse: () => null,
    );
    if (raw != null && mounted) {
      _verDetalhes(context, raw);
    }
  }

  /// Verifica se há uma OC pendente no provider (setada pelo orçamento após
  /// gerar OC) e, em caso positivo, recarrega a lista e abre os detalhes.
  /// Chamado em [didChangeDependencies] para capturar o caso onde a página de
  /// OC já estava montada no StatefulShellRoute quando o usuário navegou até ela.
  Future<void> _verificarOcPendente() async {
    if (!mounted) return;
    final provider = context.read<OrdemCompraProvider>();
    // Verifica sem consumir ainda — o consumo acontece dentro de abrirOcPorId,
    // após o carregar() trazer a OC recém-criada da API.
    if (provider.ocPendente == null) return;
    final id = provider.consumirOcPendente()!;
    await abrirOcPorId(id);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaNumeroCtrl.dispose();
    _buscaNomeCtrl.dispose();
    _buscaMedidaCtrl.dispose();
    _buscaEspessuraCtrl.dispose();
    _buscaIdentificadorCtrl.dispose();
    _buscaIdCtrl.dispose();
    super.dispose();
  }

  bool _dependenciasInicializadas = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Na primeira chamada, o initState cuida da abertura via postFrameCallback.
    // Nas chamadas subsequentes (ex: usuário navega de volta para esta rota no
    // StatefulShellRoute), verifica se há uma OC pendente para abrir.
    if (_dependenciasInicializadas) {
      _verificarOcPendente();
    }
    _dependenciasInicializadas = true;
  }

  List<dynamic> _filtrar(List<dynamic> lista) {
    final qNum  = _filtroBuscaNumero.trim();
    final qNome = _filtroBuscaNome.trim().toLowerCase();
    final qMed  = _filtroBuscaMedida.trim().toLowerCase();
    final qEsp  = _filtroBuscaEspessura.trim().toLowerCase();
    final qId   = _filtroBuscaIdentificador.trim().toUpperCase();
    final qMid  = _filtroBuscaId.trim();
    if (qNum.isEmpty && qNome.isEmpty && qMed.isEmpty && qEsp.isEmpty && qId.isEmpty && qMid.isEmpty) return lista;
    return lista.where((o) {
      final raw = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
      if (qNum.isNotEmpty && !raw.id.toString().contains(qNum)) return false;
      if (qNome.isNotEmpty) {
        final tem = raw.itens.any((item) => item.materialNome.toLowerCase().contains(qNome));
        if (!tem) return false;
      }
      if (qMed.isNotEmpty) {
        final tem = raw.itens.any((item) => item.materialMedida?.toLowerCase().contains(qMed) ?? false);
        if (!tem) return false;
      }
      if (qEsp.isNotEmpty) {
        final tem = raw.itens.any((item) => item.materialEspessura?.toLowerCase().contains(qEsp) ?? false);
        if (!tem) return false;
      }
      if (qId.isNotEmpty) {
        final tem = raw.itens.any((item) => (item.materialIdentificador ?? '').toUpperCase().contains(qId));
        if (!tem) return false;
      }
      if (qMid.isNotEmpty) {
        final tem = raw.itens.any((item) => item.materialId.toString().contains(qMid));
        if (!tem) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _abrirCriacaoOC() async {
    final resultado = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => NovaOrdemCompraPage()),
    );
    // resultado pode ser OrdemCompraModel (novo fluxo) ou bool true (fallback)
    if (resultado != null && mounted) {
      context.read<OrdemCompraProvider>().carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: EdgeInsets.all(24),
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
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Consumer<OrdemCompraProvider>(
                      builder: (_, p, __) {
                        final total = p.emAndamento.length + p.finalizadas.length + p.canceladas.length;
                        return Text(
                          '$total ${total == 1 ? 'ordem' : 'ordens'} no total',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                SizedBox(width: 12),
                IconButton(
                  onPressed: () => context.read<OrdemCompraProvider>().carregar(),
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            // ── Filtros ────────────────────────────────────────────────────
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _buscaNumeroCtrl,
                    decoration: InputDecoration(
                      hintText: 'Nº da OC...',
                      prefixIcon: Icon(Icons.tag, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                      suffixIcon: _filtroBuscaNumero.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18, color: Theme.of(context).colorScheme.outline),
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
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaNomeCtrl,
                    decoration: InputDecoration(
                      hintText: 'Nome do material...',
                      prefixIcon: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                      suffixIcon: _filtroBuscaNome.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18, color: Theme.of(context).colorScheme.outline),
                              onPressed: () {
                                _buscaNomeCtrl.clear();
                                setState(() => _filtroBuscaNome = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _filtroBuscaNome = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaIdentificadorCtrl,
                    decoration: InputDecoration(
                      hintText: 'Identificador...',
                      prefixIcon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                      suffixIcon: _filtroBuscaIdentificador.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18, color: Theme.of(context).colorScheme.outline),
                              onPressed: () {
                                _buscaIdentificadorCtrl.clear();
                                setState(() => _filtroBuscaIdentificador = '');
                              },
                            )
                          : null,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (v) => setState(() => _filtroBuscaIdentificador = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaMedidaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Medida...',
                      prefixIcon: Icon(Icons.straighten_outlined, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                      suffixIcon: _filtroBuscaMedida.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18, color: Theme.of(context).colorScheme.outline),
                              onPressed: () {
                                _buscaMedidaCtrl.clear();
                                setState(() => _filtroBuscaMedida = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _filtroBuscaMedida = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaEspessuraCtrl,
                    decoration: InputDecoration(
                      hintText: 'Espessura...',
                      prefixIcon: Icon(Icons.layers_outlined, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                      suffixIcon: _filtroBuscaEspessura.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18, color: Theme.of(context).colorScheme.outline),
                              onPressed: () {
                                _buscaEspessuraCtrl.clear();
                                setState(() => _filtroBuscaEspessura = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _filtroBuscaEspessura = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _buscaIdCtrl,
                    decoration: InputDecoration(
                      hintText: 'ID...',
                      prefixIcon: Icon(Icons.numbers, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                      suffixIcon: _filtroBuscaId.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18, color: Theme.of(context).colorScheme.outline),
                              onPressed: () {
                                _buscaIdCtrl.clear();
                                setState(() => _filtroBuscaId = '');
                              },
                            )
                          : null,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => setState(() => _filtroBuscaId = v),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(
                    Icons.filter_alt_off,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: (_filtroBuscaNumero.isNotEmpty || _filtroBuscaNome.isNotEmpty || _filtroBuscaMedida.isNotEmpty || _filtroBuscaEspessura.isNotEmpty || _filtroBuscaIdentificador.isNotEmpty || _filtroBuscaId.isNotEmpty)
                      ? () {
                          _buscaNumeroCtrl.clear();
                          _buscaNomeCtrl.clear();
                          _buscaMedidaCtrl.clear();
                          _buscaEspessuraCtrl.clear();
                          _buscaIdentificadorCtrl.clear();
                          _buscaIdCtrl.clear();
                          setState(() {
                            _filtroBuscaNumero = '';
                            _filtroBuscaNome = '';
                            _filtroBuscaMedida = '';
                            _filtroBuscaEspessura = '';
                            _filtroBuscaIdentificador = '';
                            _filtroBuscaId = '';
                          });
                        }
                      : null,
                  style: IconButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // ── Abas ───────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    final partes = provider.erro!.split(': ');
                    final subtitulo = partes.length > 1
                        ? partes.sublist(1).join(': ')
                        : provider.erro!;
                    return SizedBox(
                      height: 300,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_outlined,
                                size: 48, color: AppTheme.error),
                            SizedBox(height: 12),
                            Text(
                              'Erro ao carregar ordens de compra',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 4),
                            Text(
                              subtitulo,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => provider.carregar(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Tentar novamente'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primary),
                            ),
                          ],
                        ),
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
        title: Row(children: [
          Icon(Icons.lock_outline, color: AppTheme.error, size: 22),
          SizedBox(width: 8),
          Text('OS Fechada', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não é possível finalizar esta OC porque ${osBloqueadas.length == 1 ? 'a seguinte OS já foi fechada' : 'as seguintes OS já foram fechadas'} no controle de estoque:',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
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
                child: Text(os, style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13)),
              )).toList(),
            ),
            SizedBox(height: 12),
            Text(
              'Para prosseguir, reabra essa OS no controle de estoque antes de finalizar a OC.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
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

      // ── Verifica OS fechadas (apenas OS numéricas) ────────────────────────
      final osFechadas = context.read<EstoqueProvider>().numerosOSFechadas;
      final osBloqueadas = model.numerosOS
          .where((os) => RegExp(r'^\d+$').hasMatch(os) && osFechadas.contains(os))
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
        title: Text('Finalizar Ordem'),
        content: Text(
            'Ao finalizar, os itens serão adicionados ao estoque. Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
        title: Text('Cancelar Ordem'),
        content: Text(
            'Tem certeza que deseja cancelar esta ordem de compra?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Voltar',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
        title: Text('Reverter Ordem Finalizada'),
        content: Text(
            'Esta ação irá desfazer a finalização: os itens serão removidos do estoque e a ordem voltará para "Em Andamento". Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Voltar',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
            Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 12),
            Text(emptyMessage,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
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
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.error)),
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
                ? Color(0xFFFF9800).withValues(alpha: 0.06)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface,
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
            SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(Icons.person_outline, ordem.requisitante,
                    Theme.of(context).colorScheme.onSurfaceVariant),
                _chip(Icons.calendar_today_outlined, _formatData(ordem.data),
                    Theme.of(context).colorScheme.onSurfaceVariant),
                if (ordem.empresa != null)
                  _chip(Icons.business_outlined, ordem.empresa!,
                      Theme.of(context).colorScheme.onSurfaceVariant),
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
            if (ordem.itens.isNotEmpty) ...[
              const SizedBox(height: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ordem.itens.map((item) {
                  final partes = <String>[
                    if ((item.materialMedida ?? '').isNotEmpty) item.materialMedida!,
                    if ((item.materialEspessura ?? '').isNotEmpty) item.materialEspessura!,
                    if ((item.materialIdentificador ?? '').isNotEmpty) item.materialIdentificador!,
                  ];
                  final desc = partes.isEmpty
                      ? item.materialNome
                      : '${item.materialNome} · ${partes.join(' · ')}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (widget.mostrarAcoes) ...[
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onAbrirPdf,
                    icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onAbrirPdf,
                    icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
    // ── Verifica OS fechadas antes de abrir o diálogo de confirmação (apenas OS numéricas) ──
    final osFechadas = context.read<EstoqueProvider>().numerosOSFechadas;
    final osBloqueadas = _ordem.numerosOS
        .where((os) => RegExp(r'^\d+$').hasMatch(os) && osFechadas.contains(os))
        .toList();
    if (osBloqueadas.isNotEmpty) {
      if (!mounted) return;
      showDialog(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(Icons.lock_outline, color: AppTheme.error, size: 22),
            SizedBox(width: 8),
            Text('OS Fechada', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Não é possível finalizar esta OC porque ${osBloqueadas.length == 1 ? 'a seguinte OS já foi fechada' : 'as seguintes OS já foram fechadas'} no controle de estoque:',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
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
                  child: Text(os, style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13)),
                )).toList(),
              ),
              SizedBox(height: 12),
              Text(
                'Para prosseguir, reabra essa OS no controle de estoque antes de finalizar a OC.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
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
        title: Text('Finalizar Ordem'),
        content: Text('Ao finalizar, os itens serão adicionados ao estoque. Confirmar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
        title: Text('Cancelar Ordem'),
        content: Text('Tem certeza que deseja cancelar esta ordem de compra?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Voltar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
        title: Text('Reverter Ordem Finalizada'),
        content: Text('Esta ação irá desfazer a finalização: os itens serão removidos do estoque e a ordem voltará para "Em Andamento". Confirmar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Voltar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
      final atualizado = raw is OrdemCompraModel
          ? raw
          : OrdemCompraModel.fromJson(raw as Map<String, dynamic>);
      if (mounted) setState(() { _ordem = atualizado; });
    }
  }

  Future<void> _abrirPdf() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );
    try {
      final bytes = await OrdemCompraRepository().baixarPdf(_ordem.id);

      // Monta nome: "OC_42_FORNECEDOR NOME.pdf" → sanitiza caracteres inválidos
      final fornecedor = (_ordem.fornecedorNome ?? 'FORNECEDOR')
          .toUpperCase()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = 'OC_${_ordem.id}_$fornecedor.pdf';

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

  @override
  Widget build(BuildContext context) {
    final emAndamento = _ordem.status == 'EM_ANDAMENTO';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        SizedBox(width: 6),
                        Text('Ordens de Compra', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Text('OC #${_ordem.id}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
                SizedBox(width: 10),
                _statusBadge(_ordem.status),
                Spacer(),
                _headerActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: _abrirPdf,
                ),
                if (emAndamento) ...[
                  const SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.cancel_outlined,
                    label: 'Cancelar',
                    color: AppTheme.error,
                    onPressed: _processando ? null : _confirmarCancelar,
                  ),
                  const SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Editar',
                    color: AppTheme.primary,
                    onPressed: _processando ? null : _abrirEdicao,
                  ),
                  const SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.check_circle_outline,
                    label: 'Finalizar',
                    color: AppTheme.success,
                    filled: true,
                    onPressed: _processando ? null : _confirmarFinalizar,
                  ),
                ],
                if (_ordem.status == 'FINALIZADO') ...[
                  SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.undo,
                    label: 'Reverter',
                    color: Color(0xFFB45309),
                    onPressed: _processando ? null : _confirmarReverter,
                  ),
                ],
                SizedBox(width: 8),
                IconButton(
                  onPressed: _recarregar,
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                child: Text(os, style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
              )).toList()),
            ]),
            SizedBox(height: 16),
          ],
          _secaoCard('Itens (${_ordem.itens.length})', Icons.inventory_2_outlined, [
            ..._ordem.itens.map((item) => Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.materialNome, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                        Builder(builder: (_) {
                          final sub = [
                            if (item.materialMedida != null && item.materialMedida!.isNotEmpty) item.materialMedida!,
                            if (item.materialEspessura != null && item.materialEspessura!.isNotEmpty) item.materialEspessura!,
                            if (item.materialIdentificador != null && item.materialIdentificador!.isNotEmpty) item.materialIdentificador!,
                          ].join(' · ');
                          if (sub.isEmpty) return SizedBox.shrink();
                          return Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(sub, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          );
                        }),
                        if (item.descricaoItem != null && item.descricaoItem!.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              item.descricaoItem!,
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
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
                      'Qtd: ${item.quantidade}',
                    ),
                    // Exibe a quantidade por unidade logo após a quantidade principal
                    if (item.qtdUnidade != null && item.qtdUnidade! > 0)
                      _itemChipDestaque(
                        Icons.inventory_2_outlined,
                        '${item.qtdUnidade! % 1 == 0 ? item.qtdUnidade!.toInt() : item.qtdUnidade} ${item.materialUnidade ?? 'unid.'}/unidade',
                        ativo: true,
                      ),
                    _itemChipDestaque(
                      Icons.attach_money,
                      () {
                        if (item.qtdUnidade != null && item.qtdUnidade! > 0) {
                          return 'R\$ ${item.precoUnitario.toStringAsFixed(6).replaceAll('.', ',')}/${item.materialUnidade ?? 'unid.'}';
                        }
                        return item.precoUnitario > 0
                            ? 'Unitário: R\$ ${item.precoUnitario.toStringAsFixed(6).replaceAll('.', ',')}'
                            : 'Unitário: —';
                      }(),
                      ativo: true,
                    ),
                  ],
                ),
              ]),
            )),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
                Text('R\$ ${_ordem.valorTotal.toStringAsFixed(2).replaceAll('.', ',')}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.primary)),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
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
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
    padding: EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 16, color: AppTheme.primary), SizedBox(width: 6), Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface))]),
      SizedBox(height: 12),
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
      SizedBox(height: 12),
      ...children,
    ]),
  );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: Theme.of(context).colorScheme.outline),
      SizedBox(width: 8),
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface))),
    ]),
  );

  Widget _itemChip(IconData icon, String label) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
          SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
            SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _headerActionButton({
    required IconData icon,
    required String label,
    required Color color,
    bool filled = false,
    VoidCallback? onPressed,
  }) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    _itens = _agruparItensEmRascunhos(widget.ordem.itens);
    _requisitanteCtrl = TextEditingController(text: widget.ordem.requisitante);
    _formaPagamentoCtrl = TextEditingController(text: widget.ordem.formaPagamento ?? '');
    _prazoPagamentoCtrl = TextEditingController(text: widget.ordem.prazoPagamento ?? '');
    _observacoesCtrl = TextEditingController(text: widget.ordem.observacoes ?? '');
    _carregarFornecedor();
  }

  /// Agrupa itens do banco (um por linha OS) de volta em _ItemRascunho com
  /// múltiplas linhas de distribuição. Itens do mesmo material com o mesmo
  /// preço e descrição são consolidados.
  List<_ItemRascunho> _agruparItensEmRascunhos(List<OrdemCompraItemModel> itens) {
    final grupos = <String, _ItemRascunho>{};
    for (final i in itens) {
      // Chave: material + preço + modo + descrição
      final chave = '${i.materialId}|${i.precoUnitario}|${i.descricaoItem ?? ''}';
      if (grupos.containsKey(chave)) {
        // Adiciona linha de distribuição ao rascunho existente
        final r = grupos[chave]!;
        r.distribuicao.add(_DistribuicaoLinha(os: i.numeroOS, quantidade: i.quantidade));
        r.quantidade += i.quantidade;
        r.numeroOS = r.distribuicao.first.os;
      } else {
        grupos[chave] = _ItemRascunho(
          materialId:            i.materialId,
          materialNome:          i.materialNome,
          materialUnidade:       i.materialUnidade,
          materialMedida:        i.materialMedida,
          materialEspessura:     i.materialEspessura,
          materialIdentificador: i.materialIdentificador,
          descricaoItem:         i.descricaoItem,
          numeroOS:              i.numeroOS,
          quantidade:            i.quantidade,
          qtdUnidade:            i.qtdUnidade,
          precoUnitario:         i.precoUnitario,
          precoMetroQuadrado:    i.precoMetroQuadrado,
          distribuicao: [_DistribuicaoLinha(os: i.numeroOS, quantidade: i.quantidade)],
        );
      }
    }
    return grupos.values.toList();
  }

  Future<void> _carregarFornecedor() async {
    final f = await context.read<FornecedorProvider>().buscarPorId(widget.ordem.fornecedorId);
    if (mounted) {
      setState(() {
        _fornecedor = f;
        if (f != null) {
          for (final item in _itens) {
            final vinculo = f.materiais.cast<FornecedorMaterialVinculoModel?>().firstWhere(
              (m) => m?.materialId == item.materialId,
              orElse: () => null,
            );
            if (vinculo != null) {
              item.materialLargura     = vinculo.materialLargura;
              item.materialComprimento = vinculo.materialComprimento;
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
          final novosFornecedorMateriais = _fornecedor?.materiais ?? [];
          for (final item in _itens) {
            final vinculo = novosFornecedorMateriais
                .cast<FornecedorMaterialVinculoModel?>()
                .firstWhere(
                  (m) => m?.materialId == item.materialId,
                  orElse: () => null,
                );
            if (vinculo != null) {
              // Atualiza preço com o do novo fornecedor se disponível
              if (vinculo.preco > 0) {
                item.precoUnitario = vinculo.preco;
              }
            }
          }
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
        materialId:             vinculo.materialId,
        materialNome:           vinculo.descricaoCompleta,
        materialUnidade:        vinculo.materialUnidade,
        materialMedida:         vinculo.materialMedida,
        materialEspessura:      vinculo.materialEspessura,
        materialIdentificador:  vinculo.materialIdentificador,
        materialLargura:        vinculo.materialLargura,
        materialComprimento:    vinculo.materialComprimento,
        numeroOS:               osAuto,
        quantidade:             1,
        precoUnitario:          vinculo.preco,
        precoMetroQuadrado:
            vinculo.precoMetroQuadrado > 0 ? vinculo.precoMetroQuadrado : null,
      ));
    });
  }

  void _removerItem(int idx) => setState(() => _itens.removeAt(idx));

  Future<void> _salvar() async {
    if (_fornecedor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um fornecedor.'), backgroundColor: AppTheme.error));
      return;
    }
    if (_itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adicione pelo menos um item à ordem de compra.'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }
    for (final item in _itens) {
      // Pelo menos uma linha deve ter OS selecionada E que ainda conste na lista atual
      final temOSSelecionada = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os),
      );
      if (!temOSSelecionada) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Selecione a OS para o item "${item.materialNome}".'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
      // Nenhuma linha com OS válida pode ter qtd = 0
      final linhaComZero = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os) && l.quantidade <= 0,
      );
      if (linhaComZero) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('A quantidade deve ser maior que 0 para todos os itens da distribuição em "${item.materialNome}".'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
      // Total distribuído deve ser exatamente igual à quantidade do item
      final totalDistribuido = item.distribuicao.fold(0.0, (s, l) => s + l.quantidade);
      final diff = totalDistribuido - item.quantidade;
      if (diff > 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('A quantidade distribuída (${totalDistribuido % 1 == 0 ? totalDistribuido.toInt() : totalDistribuido.toStringAsFixed(2)}) excede a quantidade do item "${item.materialNome}" (${item.quantidade % 1 == 0 ? item.quantidade.toInt() : item.quantidade}).'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
      if (diff < -0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'A soma das quantidades distribuídas (${totalDistribuido % 1 == 0 ? totalDistribuido.toInt() : totalDistribuido.toStringAsFixed(2)}) '
            'está abaixo da quantidade do item "${item.materialNome}" '
            '(${item.quantidade % 1 == 0 ? item.quantidade.toInt() : item.quantidade}). '
            'O total distribuído deve ser igual à quantidade.',
          ),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
    }
    for (final item in _itens) {
      {
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
          'numeroOS': i.distribuicao.firstWhere((l) => l.os.isNotEmpty, orElse: () => _DistribuicaoLinha()).os,
          'quantidade': i.quantidade,
          'qtdUnidade': i.qtdUnidade,           // ← LINHA ADICIONADA
          'precoUnitario': i.precoUnitario,
          'precoMetroQuadrado': i.precoM2Calculado,
          'usarM2': false,
          'distribuicao': i.distribuicao.where((l) => l.os.isNotEmpty && l.quantidade > 0).map((l) => {'os': l.os, 'quantidade': l.quantidade}).toList(),
        }).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ordem atualizada com sucesso!'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14),
    filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
  );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _aviso(String msg) => Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
  );

  Widget _card({ required String titulo, String? subtitulo, required List<Widget> children, Widget? trailing }) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      padding: EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            if (subtitulo != null) ...[
              SizedBox(height: 2),
              Text(subtitulo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.06) : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant, width: selected ? 1.5 : 1),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: 6),
            Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outline, size: 20),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: () => Navigator.of(context).pop()),
        title: Text('Editar OC #${widget.ordem.id}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
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
                  prefixIcon: Icon(Icons.tag, size: 18, color: Theme.of(context).colorScheme.outline),
                  suffixText: 'Fixo',
                  suffixStyle: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                child: Text('#${widget.ordem.id}', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
              ),
            ])),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Data'),
              InkWell(
                onTap: _selecionarData,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: _deco('').copyWith(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18, color: Theme.of(context).colorScheme.outline)),
                  child: Text(
                    '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            ])),
          ]),
          SizedBox(height: 14),

          _label('Fornecedor'),
          InkWell(
            onTap: _selecionarFornecedor,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _deco('Buscar fornecedor...').copyWith(prefixIcon: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.outline)),
              child: Text(
                _fornecedor?.nomeFantasia ?? widget.ordem.fornecedorNome ?? '',
                style: TextStyle(fontSize: 14, color: _fornecedor == null ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurface),
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
              // Se agora não há exatamente 1 OS (0 ou 2+),
              // limpa a OS atribuída aos itens para forçar
              // o usuário a selecionar novamente
              if (_numerosOS.length != 1) {
                for (final item in _itens) {
                  item.numeroOS = '';
                  for (final linha in item.distribuicao) {
                    linha.os = '';
                  }
                }
              }
            });
          },    
        ),
        const SizedBox(height: 16),

        // ── Itens ─────────────────────────────────────────────────────────────
        _card(
          titulo: 'Itens (${_itens.length})',
          children: [
            if (_fornecedor == null)
              _aviso('Selecione um fornecedor para ver os materiais disponíveis.')
            else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => _AdicionarItemDialog(
                        materiais: _materiaisDoFornecedor,
                        fornecedorId: _fornecedor!.id,
                        onConfirmar: (lista) {
                          for (final v in lista) {
                            _adicionarItem(v);
                          }
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar Item'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    textStyle: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (_itens.isNotEmpty) ...[
                SizedBox(height: 16),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 8),
              ],
            ],
            ..._itens.asMap().entries.map((e) => _ItemFormCard(
              key: ValueKey(e.key),
              item: e.value,
              numerosOS: _numerosOS,
              onRemover: () => _removerItem(e.key),
              onChanged: () => setState(() {}),
            )),
            if (_itens.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
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
  final double? precoMetroQuadrado;
  final String? descricao;

  ItemPreCarregadoOC({
    required this.materialId,
    required this.materialNome,
    required this.quantidade,
    required this.precoUnitario,
    this.precoMetroQuadrado,
    this.descricao,
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
          numeroOS:           '',
          quantidade:         item.quantidade,
          precoUnitario:      item.precoUnitario,
          precoMetroQuadrado: item.precoMetroQuadrado,
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

    if (_itens.isEmpty) {
      _showErro('Adicione pelo menos um item à ordem de compra.');
      return;
    }

    for (final item in _itens) {
      // Pelo menos uma linha deve ter OS selecionada E que ainda conste na lista atual
      final temOSSelecionada = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os),
      );
      if (!temOSSelecionada) {
        _showErro('Selecione a OS para o item "${item.materialNome}".');
        return;
      }
      // Nenhuma linha com OS válida pode ter qtd = 0
      final linhaComZero = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os) && l.quantidade <= 0,
      );
      if (linhaComZero) {
        _showErro('A quantidade deve ser maior que 0 para todos os itens da distribuição em "${item.materialNome}".');
        return;
      }
      // Total distribuído deve ser exatamente igual à quantidade do item
      final totalDistribuido = item.distribuicao.fold(0.0, (s, l) => s + l.quantidade);
      final diff = totalDistribuido - item.quantidade;
      if (diff > 0.0001) {
        _showErro('A quantidade distribuída (${totalDistribuido % 1 == 0 ? totalDistribuido.toInt() : totalDistribuido.toStringAsFixed(2)}) excede a quantidade do item "${item.materialNome}" (${item.quantidade % 1 == 0 ? item.quantidade.toInt() : item.quantidade}).');
        return;
      }
      if (diff < -0.0001) {
        _showErro(
          'A soma das quantidades distribuídas (${totalDistribuido % 1 == 0 ? totalDistribuido.toInt() : totalDistribuido.toStringAsFixed(2)}) '
          'está abaixo da quantidade do item "${item.materialNome}" '
          '(${item.quantidade % 1 == 0 ? item.quantidade.toInt() : item.quantidade}). '
          'O total distribuído deve ser igual à quantidade.',
        );
        return;
      }
    }
    for (final item in _itens) {
      {
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
                  'numeroOS': i.distribuicao.firstWhere((l) => l.os.isNotEmpty, orElse: () => _DistribuicaoLinha()).os,
                  'quantidade': i.quantidade,
                  'qtdUnidade': i.qtdUnidade,
                  'precoUnitario': i.precoUnitario,
                  'precoMetroQuadrado': i.precoM2Calculado,
                  'usarM2': false,
                  'distribuicao': i.distribuicao.where((l) => l.os.isNotEmpty && l.quantidade > 0).map((l) => {'os': l.os, 'quantidade': l.quantidade}).toList(),
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
        materialId:             vinculo.materialId,
        materialNome:           vinculo.descricaoCompleta,
        materialUnidade:        vinculo.materialUnidade,
        materialMedida:         vinculo.materialMedida,
        materialEspessura:      vinculo.materialEspessura,
        materialIdentificador:  vinculo.materialIdentificador,
        materialLargura:        vinculo.materialLargura,
        materialComprimento:    vinculo.materialComprimento,
        numeroOS:               osAuto,
        quantidade:             1,
        precoUnitario:          vinculo.preco,
        precoMetroQuadrado:
            vinculo.precoMetroQuadrado > 0 ? vinculo.precoMetroQuadrado : null,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.itensPreCarregados.isNotEmpty
              ? 'Nova OC — do Orçamento'
              : 'Nova Ordem de Compra',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface),
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
                              prefixIcon: Icon(Icons.tag,
                                  size: 18, color: Theme.of(context).colorScheme.outline),
                              suffixText: 'Automático',
                              suffixStyle: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                            child: Text(
                              _proximoId != null ? '$_proximoId' : '—',
                              style: TextStyle(
                                color: _proximoId != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.outline,
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
                                suffixIcon: Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.outline),
                              ),
                              child: Text(
                                '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),

                // Fornecedor
                _label('Fornecedor principal'),
                InkWell(
                  onTap: _selecionarFornecedor,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: _deco('Buscar fornecedor...').copyWith(
                      prefixIcon: Icon(Icons.search,
                          size: 18, color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Text(
                      _fornecedor?.nomeFantasia ?? '',
                      style: TextStyle(
                          fontSize: 14,
                          color: _fornecedor == null
                              ? Theme.of(context).colorScheme.outline
                              : Theme.of(context).colorScheme.onSurface),
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
                  // Se agora não há exatamente 1 OS (0 ou 2+),
                  // limpa a OS atribuída aos itens para forçar
                  // o usuário a selecionar novamente
                  if (_numerosOS.length != 1) {
                    for (final item in _itens) {
                      item.numeroOS = '';
                      for (final linha in item.distribuicao) {
                        linha.os = '';
                      }
                    }
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // ── Itens ──────────────────────────────────────────────────────
            _card(
              titulo: 'Itens (${_itens.length})',
              children: [
                if (_fornecedor == null)
                  _aviso(
                      'Selecione um fornecedor para ver os materiais disponíveis.')
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => _AdicionarItemDialog(
                            materiais: _materiaisDoFornecedor,
                            fornecedorId: _fornecedor!.id,
                            onConfirmar: (lista) {
                              for (final v in lista) {
                                _adicionarItem(v);
                              }
                            },
                          ),
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Adicionar Item'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (_itens.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Divider(color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                  ],
                ],
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
                        Text('Total',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface)),
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
            SizedBox(height: 16),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      padding: EdgeInsets.all(16),
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
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                    if (subtitulo != null) ...[
                      SizedBox(height: 2),
                      Text(subtitulo,
                          style: TextStyle(
                              fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.06)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
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
                  color: selected ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 6),
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outline,
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(msg,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
      );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        prefixIcon: Icon(Icons.assignment_outlined, size: 18, color: Theme.of(context).colorScheme.outline),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final hasValue = _controllers.any((c) => c.text.trim().isNotEmpty);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: !hasValue ? AppTheme.primary.withValues(alpha: 0.5) : Theme.of(context).colorScheme.outlineVariant,
          width: !hasValue ? 1.5 : 1,
        ),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Números de OS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            Text(' *', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ]),
          SizedBox(height: 4),
          Text(
            'Preencha ao menos uma OS. Se houver apenas uma, ela será atribuída automaticamente aos itens.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
// LINHA DE DISTRIBUIÇÃO POR OS
// ─────────────────────────────────────────────────────────────────────────────

class _DistribuicaoLinha {
  String os;
  double quantidade;
  _DistribuicaoLinha({this.os = '', this.quantidade = 0});
}

// ─────────────────────────────────────────────────────────────────────────────
// RASCUNHO DE ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _ItemRascunho {
  int materialId;
  String materialNome;
  /// Unidade de medida do material no estoque (ex: "UNIDADE", "ML", "M/L", "KG").
  String? materialUnidade;
  String? materialMedida;
  String? materialEspessura;
  String? materialIdentificador;
  double? materialLargura;
  double? materialComprimento;
  String? descricaoItem;
  String numeroOS;
  double quantidade;
  double? qtdUnidade;
  double precoUnitario;
  double? precoMetroQuadrado;
  List<_DistribuicaoLinha> distribuicao;

  _ItemRascunho({
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.materialLargura,
    this.materialComprimento,
    this.descricaoItem,
    required this.numeroOS,
    required this.quantidade,
    this.qtdUnidade,
    this.precoUnitario = 0,
    this.precoMetroQuadrado,
    List<_DistribuicaoLinha>? distribuicao,
  }) : distribuicao = distribuicao ?? [_DistribuicaoLinha(os: numeroOS, quantidade: quantidade)];

  /// True quando o material tem dimensões cadastradas e o modo não é m².
  /// Nesses casos o preço m² é calculado automaticamente — não editável.
  bool get temDimensoes =>
      materialLargura != null && materialLargura! > 0 &&
      materialComprimento != null && materialComprimento! > 0;

  /// Custo/m² automático: precoUnitario / (largura × comprimento).
  double? get precoM2Calculado {
    if (!temDimensoes || precoUnitario <= 0) return null;
    return precoUnitario / (materialLargura! * materialComprimento!);
  }

  bool get precisaQtdUnidade {
    final u = (materialUnidade ?? '').toUpperCase().trim();
    return u.isNotEmpty && u != 'UNIDADE';
  }

  String get labelQtdUnidade {
    final u = (materialUnidade ?? '').toUpperCase().trim();
    switch (u) {
      case 'M/L':    return 'M/L por unidade';
      case 'ML':     return 'ML por unidade';
      case 'KG':     return 'KG por unidade';
      case 'G':      return 'g por unidade';
      case 'L':      return 'L por unidade';
      case 'M':      return 'M por unidade';
      case 'M2':
      case 'M²':     return 'M² por unidade';
      default:       return '$u por unidade';
    }
  }

  /// Quantidade real que irá para o estoque: quantidade × qtdUnidade (quando aplicável).
  double get quantidadeEstoque {
    if (qtdUnidade != null && qtdUnidade! > 0) return quantidade * qtdUnidade!;
    return quantidade;
  }

  /// Preço total: quantidade × qtdUnidade × precoUnitario quando qtdUnidade está preenchido.
  /// Sem qtdUnidade: quantidade × precoUnitario (comportamento legado).
  double get precoTotal {
    if (precisaQtdUnidade && qtdUnidade != null && qtdUnidade! > 0) {
      return quantidade * qtdUnidade! * precoUnitario;
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
  late TextEditingController _qtdUnidadeCtrl;
  late TextEditingController _precoCtrl;
  late TextEditingController _precoTotalCtrl;
  late TextEditingController _descricaoCtrl;
  
  bool _ignorarCalculo = false;
  // ← NOVO: rastreia qual campo tem prioridade
  // 'unitario' = mantém o preço unitário fixo e recalcula o total
  // 'total' = mantém o total fixo e recalcula o preço unitário
  String _campoEditado = 'unitario';

  @override
  void initState() {
    super.initState();
    _qtdCtrl = TextEditingController(
        text: widget.item.quantidade == 0
            ? ''
            : widget.item.quantidade % 1 == 0
                ? widget.item.quantidade.toInt().toString()
                : widget.item.quantidade.toString());
    _qtdUnidadeCtrl = TextEditingController(
        text: widget.item.qtdUnidade == null || widget.item.qtdUnidade == 0
            ? ''
            : widget.item.qtdUnidade! % 1 == 0
                ? widget.item.qtdUnidade!.toInt().toString()
                : widget.item.qtdUnidade.toString());
    _precoCtrl = TextEditingController(
        text: widget.item.precoUnitario == 0 ? '' : widget.item.precoUnitario.toString());
    
    _precoTotalCtrl = TextEditingController(
        text: _calcularPrecoTotal() == 0 ? '' : _calcularPrecoTotal().toStringAsFixed(2));
    
    _descricaoCtrl = TextEditingController(
        text: widget.item.descricaoItem ?? '');
    
    _precoCtrl.addListener(_onPrecoUnitarioChanged);
    _precoTotalCtrl.addListener(_onPrecoTotalChanged);
  }

  @override
  void dispose() {
    _precoCtrl.removeListener(_onPrecoUnitarioChanged);
    _precoTotalCtrl.removeListener(_onPrecoTotalChanged);
    _qtdCtrl.dispose();
    _qtdUnidadeCtrl.dispose();
    _precoCtrl.dispose();
    _precoTotalCtrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  double _calcularPrecoTotal() {
    final qtd = double.tryParse(_qtdCtrl.text) ?? 0;
    final qtdUnit = double.tryParse(_qtdUnidadeCtrl.text);
    final preco = double.tryParse(_precoCtrl.text) ?? 0;
    
    if (qtd <= 0 || preco <= 0) return 0;
    
    if (qtdUnit != null && qtdUnit > 0) {
      return qtd * qtdUnit * preco;
    }
    return qtd * preco;
  }
  
  // ← MODIFICADO: marca que o usuário editou o preço unitário
  void _onPrecoUnitarioChanged() {
    if (_ignorarCalculo) return;
    
    final preco = double.tryParse(_precoCtrl.text);
    if (preco == null || preco <= 0) {
      if (_precoTotalCtrl.text.isNotEmpty) {
        _ignorarCalculo = true;
        _precoTotalCtrl.clear();
        _ignorarCalculo = false;
      }
      return;
    }
    
    // ← NOVO: marca que o unitário foi editado
    _campoEditado = 'unitario';
    
    final total = _calcularPrecoTotal();
    if (total > 0) {
      final novoTexto = total.toStringAsFixed(2);
      if (_precoTotalCtrl.text != novoTexto) {
        _ignorarCalculo = true;
        _precoTotalCtrl.text = novoTexto;
        _ignorarCalculo = false;
      }
    }
  }

  // ← MODIFICADO: marca que o usuário editou o total
  void _onPrecoTotalChanged() {
    if (_ignorarCalculo) return;
    
    final total = double.tryParse(_precoTotalCtrl.text);
    if (total == null || total <= 0) {
      return;
    }
    
    // ← NOVO: marca que o total foi editado
    _campoEditado = 'total';
    
    final qtd = double.tryParse(_qtdCtrl.text) ?? 0;
    final qtdUnit = double.tryParse(_qtdUnidadeCtrl.text);
    
    if (qtd <= 0) return;
    
    double precoUnitario;
    if (qtdUnit != null && qtdUnit > 0) {
      precoUnitario = total / (qtd * qtdUnit);
    } else {
      precoUnitario = total / qtd;
    }
    
    final novoTexto = precoUnitario.toStringAsFixed(6);
    if (_precoCtrl.text != novoTexto) {
      _ignorarCalculo = true;
      _precoCtrl.text = novoTexto;
      widget.item.precoUnitario = precoUnitario;
      _ignorarCalculo = false;
      widget.onChanged();
      setState(() {});
    }
  }
  
  // ← NOVO: método chamado quando quantidade ou qtdUnidade muda
  void _recalcularComBaseNaPrioridade() {
    if (_campoEditado == 'total') {
      // Total tem prioridade: recalcula o unitário mantendo o total fixo
      final total = double.tryParse(_precoTotalCtrl.text);
      if (total != null && total > 0) {
        final qtd = double.tryParse(_qtdCtrl.text) ?? 0;
        final qtdUnit = double.tryParse(_qtdUnidadeCtrl.text);
        
        if (qtd > 0) {
          double precoUnitario;
          if (qtdUnit != null && qtdUnit > 0) {
            precoUnitario = total / (qtd * qtdUnit);
          } else {
            precoUnitario = total / qtd;
          }
          
          _ignorarCalculo = true;
          _precoCtrl.text = precoUnitario.toStringAsFixed(6);
          widget.item.precoUnitario = precoUnitario;
          _ignorarCalculo = false;
        }
      }
    } else {
      // Unitário tem prioridade: recalcula o total mantendo o unitário fixo
      final preco = double.tryParse(_precoCtrl.text);
      if (preco != null && preco > 0) {
        final total = _calcularPrecoTotal();
        if (total > 0) {
          _ignorarCalculo = true;
          _precoTotalCtrl.text = total.toStringAsFixed(2);
          _ignorarCalculo = false;
        }
      }
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppTheme.primary),
        ),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final total = item.precoTotal;
    final unidade = (item.materialUnidade ?? '').toUpperCase().trim();
    final labelQtd = 'Quantidade';

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.materialNome,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface)),
                    Builder(builder: (_) {
                      final sub = [
                        if (item.materialMedida != null && item.materialMedida!.isNotEmpty) item.materialMedida!,
                        if (item.materialEspessura != null && item.materialEspessura!.isNotEmpty) item.materialEspessura!,
                        if (item.materialIdentificador != null && item.materialIdentificador!.isNotEmpty) item.materialIdentificador!,
                        if (unidade.isNotEmpty) unidade,
                      ].join(' · ');
                      if (sub.isEmpty) return SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(sub, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      );
                    }),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onRemover,
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.error, size: 20),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DistribuicaoSection(
            item: item,
            numerosOS: widget.numerosOS,
            onChanged: () {
              final primeira = item.distribuicao
                  .firstWhere((l) => l.os.isNotEmpty, orElse: () => _DistribuicaoLinha());
              item.numeroOS = primeira.os;
              widget.onChanged();
              setState(() {});
            },
          ),
          SizedBox(height: 8),
          if (item.precisaQtdUnidade) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(labelQtd,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _qtdCtrl,
                        decoration: _deco('0'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d*'))],
                        onChanged: (v) {
                          item.quantidade = double.tryParse(v) ?? 0;
                          if (widget.numerosOS.length == 1 && item.distribuicao.length == 1) {
                            item.distribuicao[0].os = widget.numerosOS.first;
                            item.distribuicao[0].quantidade = item.quantidade;
                          }
                          // ← MODIFICADO: usa o novo método de recálculo baseado em prioridade
                          _recalcularComBaseNaPrioridade();
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.labelQtdUnidade,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _qtdUnidadeCtrl,
                        decoration: _deco('0.000'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))
                        ],
                        onChanged: (v) {
                          item.qtdUnidade = double.tryParse(v);
                          // ← MODIFICADO: usa o novo método de recálculo baseado em prioridade
                          _recalcularComBaseNaPrioridade();
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor/${unidade.isNotEmpty ? unidade : 'unid.'}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _precoCtrl,
                        decoration: _deco('0.000000'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))
                        ],
                        onChanged: (v) {
                          item.precoUnitario = double.tryParse(v.trim().isEmpty ? '0' : v) ?? 0;
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor total (R\$)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _precoTotalCtrl,
                        decoration: _deco('0.00').copyWith(
                          prefixText: 'R\$ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                        ],
                        onChanged: (_) {
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item.qtdUnidade != null && item.qtdUnidade! > 0 && item.quantidade > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 13, color: AppTheme.primary),
                      SizedBox(width: 5),
                      Text(
                        'Entrará no estoque: ${item.quantidadeEstoque % 1 == 0 ? item.quantidadeEstoque.toInt() : item.quantidadeEstoque.toStringAsFixed(2)} $unidade',
                        style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quantidade',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _qtdCtrl,
                        decoration: _deco('0'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d*'))],
                        onChanged: (v) {
                          item.quantidade = double.tryParse(v) ?? 0;
                          if (widget.numerosOS.length == 1 && item.distribuicao.length == 1) {
                            item.distribuicao[0].os = widget.numerosOS.first;
                            item.distribuicao[0].quantidade = item.quantidade;
                          }
                          // ← MODIFICADO: usa o novo método
                          _recalcularComBaseNaPrioridade();
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Preço Unitário',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      SizedBox(height: 4),
                      TextFormField(
                        controller: _precoCtrl,
                        decoration: _deco('0.00'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d*'))],
                        onChanged: (v) {
                          item.precoUnitario = double.tryParse(v.trim().isEmpty ? '0' : v) ?? 0;
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor total (R\$)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      SizedBox(height: 4),
                      TextFormField(
                        controller: _precoTotalCtrl,
                        decoration: _deco('0.00').copyWith(
                          prefixText: 'R\$ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                        ],
                        onChanged: (_) {
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
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

// ─────────────────────────────────────────────────────────────────────────────
// DISTRIBUIÇÃO POR OS (sempre expandida)
// ─────────────────────────────────────────────────────────────────────────────

class _DistribuicaoSection extends StatefulWidget {
  final _ItemRascunho item;
  final List<String> numerosOS;
  final VoidCallback onChanged;

  const _DistribuicaoSection({
    required this.item,
    required this.numerosOS,
    required this.onChanged,
  });

  @override
  State<_DistribuicaoSection> createState() => _DistribuicaoSectionState();
}

class _DistribuicaoSectionState extends State<_DistribuicaoSection> {
  late List<TextEditingController> _qtdCtrls;

  @override
  void initState() {
    super.initState();
    _autoFillSeUmaOS();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _DistribuicaoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Quando muda de múltiplas OS para uma só (ou já é uma só),
    // preenche automaticamente OS e quantidade na linha 0.
    final preencheuAuto = _autoFillSeUmaOS();
    if (preencheuAuto) {
      // Atualiza o controller da linha 0 para refletir a nova quantidade
      if (_qtdCtrls.isNotEmpty) {
        final qtd = widget.item.distribuicao[0].quantidade;
        final novoTexto = qtd == 0
            ? ''
            : qtd % 1 == 0
                ? qtd.toInt().toString()
                : qtd.toString();
        if (_qtdCtrls[0].text != novoTexto) {
          _qtdCtrls[0].text = novoTexto;
        }
      }
    }
    // Quando a quantidade total do item muda e há exatamente 1 OS,
    // mantém o controller sincronizado com a quantidade atualizada.
    if (widget.numerosOS.length == 1 &&
        widget.item.distribuicao.length == 1 &&
        _qtdCtrls.isNotEmpty) {
      final qtd = widget.item.distribuicao[0].quantidade;
      final novoTexto = qtd == 0
          ? ''
          : qtd % 1 == 0
              ? qtd.toInt().toString()
              : qtd.toString();
      if (_qtdCtrls[0].text != novoTexto) {
        _qtdCtrls[0].text = novoTexto;
      }
    }
  }

  /// Quando há exatamente 1 OS cadastrada, preenche automaticamente a
  /// linha 0 da distribuição com essa OS e a quantidade total do item.
  /// Retorna true se fez alguma alteração.
  bool _autoFillSeUmaOS() {
    if (widget.numerosOS.length != 1) return false;
    final umaOS = widget.numerosOS.first;
    final dist = widget.item.distribuicao;
    // Garante que existe pelo menos 1 linha
    if (dist.isEmpty) {
      dist.add(_DistribuicaoLinha(os: umaOS, quantidade: widget.item.quantidade));
      return true;
    }
    bool changed = false;
    // Remove linhas extras (caso tenha sobrado de quando havia 2 OS)
    while (dist.length > 1) {
      dist.removeLast();
      changed = true;
    }
    // Preenche a linha 0
    if (dist[0].os != umaOS) {
      dist[0].os = umaOS;
      changed = true;
    }
    if ((dist[0].quantidade - widget.item.quantidade).abs() > 0.0001) {
      dist[0].quantidade = widget.item.quantidade;
      changed = true;
    }
    return changed;
  }

  void _syncControllers() {
    _qtdCtrls = widget.item.distribuicao.map((l) {
      final v = l.quantidade == 0 ? '' : (l.quantidade % 1 == 0 ? l.quantidade.toInt().toString() : l.quantidade.toString());
      return TextEditingController(text: v);
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _qtdCtrls) { c.dispose(); }
    super.dispose();
  }

  void _adicionarLinha() {
    final ctrl = TextEditingController();
    setState(() {
      widget.item.distribuicao.add(_DistribuicaoLinha());
      _qtdCtrls.add(ctrl);
    });
    widget.onChanged();
  }

  void _removerLinha(int idx) {
    _qtdCtrls[idx].dispose();
    setState(() {
      widget.item.distribuicao.removeAt(idx);
      _qtdCtrls.removeAt(idx);
    });
    widget.onChanged();
  }

  void _limpar() {
    for (final c in _qtdCtrls) { c.dispose(); }
    setState(() {
      widget.item.distribuicao
        ..clear()
        ..add(_DistribuicaoLinha());
      _qtdCtrls = [TextEditingController()];
    });
    widget.onChanged();
  }

  double get _totalDistribuido =>
      widget.item.distribuicao.fold(0.0, (s, l) => s + l.quantidade);

  @override
  Widget build(BuildContext context) {
    final total = widget.item.quantidade;
    final distribuido = _totalDistribuido;
    final excesso = distribuido - total;
    final ok = (distribuido - total).abs() < 0.0001;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Distribuição por OS',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: ok
                        ? AppTheme.success.withValues(alpha: 0.12)
                        : AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${distribuido % 1 == 0 ? distribuido.toInt() : distribuido}/${total % 1 == 0 ? total.toInt() : total} distribuído',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ok ? AppTheme.success : AppTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Barra de excesso ─────────────────────────────────────────────
          if (excesso > 0.0001)
            Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Excede em ${excesso % 1 == 0 ? excesso.toInt() : excesso.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (excesso > 0.0001) SizedBox(height: 6),

          // ── Cabeçalho da tabela ──────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(child: Text('OS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                SizedBox(width: 8),
                SizedBox(width: 80, child: Text('Quantidade', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center)),
                SizedBox(width: 28),
              ],
            ),
          ),
          SizedBox(height: 4),

          // ── Linhas ────────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: widget.item.distribuicao.asMap().entries.map((e) {
                final idx = e.key;
                final linha = e.value;
                final InputDecoration decoSmall = InputDecoration(
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppTheme.primary)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: widget.numerosOS.isEmpty
                            // Sem OS cadastradas: campo bloqueado
                            ? Container(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                ),
                                child: Text(
                                  'Preencha os números de OS acima',
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic),
                                ),
                              )
                            // Com OS cadastradas: dropdown
                            : DropdownButtonFormField<String>(
                                key: ValueKey('os_dd_${idx}_${widget.numerosOS.join(",")}_${widget.item.distribuicao.length}_${linha.os}'),
                                initialValue: linha.os.isNotEmpty && widget.numerosOS.contains(linha.os) ? linha.os : null,
                                decoration: InputDecoration(
                                  hintText: 'Selecione a OS',
                                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.primary)),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  isDense: true,
                                ),
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                items: widget.numerosOS
                                    .map((os) => DropdownMenuItem(value: os, child: Text(os)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => linha.os = v);
                                    widget.onChanged();
                                  }
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _qtdCtrls[idx],
                          decoration: decoSmall.copyWith(hintText: '0'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d*'))],
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            linha.quantidade = double.tryParse(v) ?? 0;
                            setState(() {});
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 24,
                        child: widget.item.distribuicao.length > 1
                            ? GestureDetector(
                                onTap: () => _removerLinha(idx),
                                child: const Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.error),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Ações ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _adicionarLinha,
                  icon: const Icon(Icons.add, size: 14, color: AppTheme.primary),
                  label: Text('Adicionar OS', style: TextStyle(fontSize: 12, color: AppTheme.primary)),
                  style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
                SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _limpar,
                  icon: Icon(Icons.close, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  label: Text('Limpar distribuição', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ],
            ),
          ),
        ],
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
      title: Text('Selecionar Fornecedor',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar fornecedor...',
                prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline),
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
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface)),
                          subtitle: f.tipoFornecedor != null
                              ? Text(f.tipoFornecedor!,
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant))
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
            child: Text('Cancelar',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG UNIFICADO: FILTRO + SELEÇÃO DE MATERIAIS
// ─────────────────────────────────────────────────────────────────────────────

class _AdicionarItemDialog extends StatefulWidget {
  final List<FornecedorMaterialVinculoModel> materiais;
  final int fornecedorId;
  final void Function(List<FornecedorMaterialVinculoModel>) onConfirmar;

  const _AdicionarItemDialog({
    required this.materiais,
    required this.fornecedorId,
    required this.onConfirmar,
  });

  @override
  State<_AdicionarItemDialog> createState() => _AdicionarItemDialogState();
}

class _AdicionarItemDialogState extends State<_AdicionarItemDialog> {
  final _idCtrl            = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _nomeCtrl          = TextEditingController();
  final _categoriaCtrl     = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();

  // materialId → quantidade de cópias a adicionar
  final Map<int, int> _quantidades = {};

  // ── modo "todo o estoque" ──────────────────────────────────────────────────
  late bool _verTodoEstoque;
  bool _buscando = false;
  List<Map<String, dynamic>> _todosOsMateriais = [];

  /// IDs já vinculados ao fornecedor
  Set<int> get _idsVinculados =>
      widget.materiais.map((m) => m.materialId).toSet();

  @override
  void initState() {
    super.initState();
    // Abre já no modo "todo o estoque" se o fornecedor não tiver vinculados
    _verTodoEstoque = widget.materiais.isEmpty;
    if (_verTodoEstoque) _carregarTodoEstoque();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _identificadorCtrl.dispose();
    _nomeCtrl.dispose();
    _categoriaCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  // ── lista filtrada para o modo "só vinculados" ─────────────────────────────
  List<FornecedorMaterialVinculoModel> get _filtradosVinculados {
    var lista = widget.materiais;
    final id        = _idCtrl.text.trim();
    final ident     = _identificadorCtrl.text.trim().toLowerCase();
    final nome      = _nomeCtrl.text.trim().toLowerCase();
    final categoria = _categoriaCtrl.text.trim().toLowerCase();
    final medida    = _medidaCtrl.text.trim().toLowerCase();
    final espessura = _espessuraCtrl.text.trim().toLowerCase();

    if (id.isNotEmpty)        lista = lista.where((m) => m.materialId.toString() == id).toList();
    if (ident.isNotEmpty)     lista = lista.where((m) => (m.materialIdentificador ?? '').toLowerCase().contains(ident)).toList();
    if (nome.isNotEmpty) {
      final tokens = nome.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      lista = lista.where((m) {
        final desc = m.descricaoCompleta.toLowerCase();
        return tokens.every((t) => desc.contains(t));
      }).toList();
    }
    if (categoria.isNotEmpty) lista = lista.where((m) => m.descricaoCompleta.toLowerCase().contains(categoria)).toList();
    if (medida.isNotEmpty)    lista = lista.where((m) => m.descricaoCompleta.toLowerCase().contains(medida)).toList();
    if (espessura.isNotEmpty) lista = lista.where((m) => m.descricaoCompleta.toLowerCase().contains(espessura)).toList();
    return lista;
  }

  // ── lista filtrada para o modo "todo o estoque" (client-side após fetch) ──
  List<Map<String, dynamic>> get _filtradosTodos {
    var lista = _todosOsMateriais;
    final id        = _idCtrl.text.trim();
    final ident     = _identificadorCtrl.text.trim().toLowerCase();
    final nome      = _nomeCtrl.text.trim().toLowerCase();
    final medida    = _medidaCtrl.text.trim().toLowerCase();
    final espessura = _espessuraCtrl.text.trim().toLowerCase();

    if (id.isNotEmpty)        lista = lista.where((m) => m['id'].toString() == id).toList();
    if (ident.isNotEmpty)     lista = lista.where((m) => (m['identificador'] ?? '').toString().toLowerCase().contains(ident)).toList();
    if (espessura.isNotEmpty) lista = lista.where((m) => (m['espessura'] ?? '').toString().toLowerCase().contains(espessura)).toList();
    if (medida.isNotEmpty)    lista = lista.where((m) => (m['medida'] ?? '').toString().toLowerCase().contains(medida)).toList();
    if (nome.isNotEmpty) {
      final tokens = nome.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      lista = lista.where((m) {
        final n = (m['nome'] ?? '').toString().toLowerCase();
        return tokens.every((t) => n.contains(t));
      }).toList();
    }
    return lista;
  }

  Future<void> _carregarTodoEstoque() async {
    setState(() { _buscando = true; });
    try {
      final repo = FornecedorRepository();
      final todos = await repo.buscarMateriais();
      if (mounted) setState(() { _todosOsMateriais = todos; });
    } catch (_) {
      // silencia — a lista fica vazia e o usuário vê o aviso
    } finally {
      if (mounted) setState(() { _buscando = false; });
    }
  }

  int get _totalItens => _quantidades.values.fold(0, (s, v) => s + v);

  bool get _temFiltro =>
      _idCtrl.text.isNotEmpty ||
      _identificadorCtrl.text.isNotEmpty ||
      _nomeCtrl.text.isNotEmpty ||
      _categoriaCtrl.text.isNotEmpty ||
      _medidaCtrl.text.isNotEmpty ||
      _espessuraCtrl.text.isNotEmpty;

  void _limparFiltros() => setState(() {
        _idCtrl.clear();
        _identificadorCtrl.clear();
        _nomeCtrl.clear();
        _categoriaCtrl.clear();
        _medidaCtrl.clear();
        _espessuraCtrl.clear();
      });

  void _confirmar() {
    final escolhidos = <FornecedorMaterialVinculoModel>[];

    if (!_verTodoEstoque) {
      // modo vinculados — igual ao original
      for (final m in widget.materiais) {
        final qty = _quantidades[m.materialId] ?? 0;
        for (var i = 0; i < qty; i++) {
          escolhidos.add(m);
        }
      }
    } else {
      // modo todo o estoque
      // Itens já vinculados: usa o FornecedorMaterialVinculoModel existente
      // Itens não vinculados: cria um sintético com preço 0 (o usuário preenche no card)
      final vinculadosPorId = { for (final m in widget.materiais) m.materialId: m };
      for (final m in _todosOsMateriais) {
        final mid = m['id'] as int;
        final qty = _quantidades[mid] ?? 0;
        if (qty == 0) continue;
        final vinculo = vinculadosPorId[mid] ?? FornecedorMaterialVinculoModel(
          id:                   0,
          fornecedorId:         widget.fornecedorId,
          materialId:           mid,
          materialNome:         m['nome'] as String?,
          materialIdentificador: m['identificador'] as String?,
          materialMedida:       m['medida'] as String?,
          materialEspessura:    m['espessura'] as String?,
          preco:                0,
          precoMetroQuadrado:   0,
          ativo:                true,
          materialUnidade:      m['unidade'] as String?,
          // Dimensões para cálculo automático de preço/m²
          materialLargura:      m['largura'] != null
              ? double.tryParse(m['largura'].toString())
              : null,
          materialComprimento:  m['comprimento'] != null
              ? double.tryParse(m['comprimento'].toString())
              : null,
        );
        for (var i = 0; i < qty; i++) {
          escolhidos.add(vinculo);
        }
      }
    }

    widget.onConfirmar(escolhidos);
    Navigator.pop(context);
  }

  InputDecoration _deco(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
        prefixIcon: icon != null ? Icon(icon, size: 15, color: Theme.of(context).colorScheme.outline) : null,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
      );

  Widget _buildItem({
    required int materialId,
    required String descricao,
    required String preco,
    required bool eNovo,
  }) {
    final qty = _quantidades[materialId] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        descricao,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: qty > 0
                              ? AppTheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (eNovo) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Novo vínculo',
                          style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  preco,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: qty == 0
                    ? null
                    : () => setState(() {
                          final novo = qty - 1;
                          if (novo == 0) { _quantidades.remove(materialId); }
                          else { _quantidades[materialId] = novo; }
                        }),
                icon: const Icon(Icons.remove_circle_outline, size: 22),
                color: qty == 0 ? Theme.of(context).colorScheme.outline : AppTheme.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              SizedBox(
                width: 30,
                child: Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: qty > 0 ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() { _quantidades[materialId] = qty + 1; }),
                icon: const Icon(Icons.add_circle_outline, size: 22),
                color: AppTheme.primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtradosVinc = _filtradosVinculados;
    final filtradosTodos = _verTodoEstoque ? _filtradosTodos : <Map<String, dynamic>>[];
    final vinculadosIds = _idsVinculados;

    return AlertDialog(
      title: Row(
        children: [
          Text('Adicionar Itens',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_totalItens > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_totalItens ${_totalItens == 1 ? 'selecionado' : 'selecionados'}',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12),
              ),
            ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 580,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Toggle ver todo estoque ────────────────────────────────────
            Row(
              children: [
                Switch(
                  value: _verTodoEstoque,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (v) {
                    setState(() { _verTodoEstoque = v; });
                    if (v && _todosOsMateriais.isEmpty) _carregarTodoEstoque();
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  'Ver todo o estoque',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                ),
                if (_verTodoEstoque && widget.materiais.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${widget.materiais.length} já vinculados)',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // ── Filtros ────────────────────────────────────────────────────
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _idCtrl,
                    decoration: _deco('ID...', icon: Icons.tag),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _nomeCtrl,
                    autofocus: true,
                    decoration: _deco('Buscar por nome...', icon: Icons.search),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: _deco('Identificador...', icon: Icons.qr_code),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 6),
                if (!_verTodoEstoque)
                  Expanded(
                    child: TextField(
                      controller: _categoriaCtrl,
                      decoration: _deco('Categoria', icon: Icons.category_outlined),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                if (!_verTodoEstoque) const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: _deco('Medida', icon: Icons.straighten_outlined),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: _deco('Espessura', icon: Icons.layers_outlined),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(width: 4),
                IconButton(
                  onPressed: _temFiltro ? _limparFiltros : null,
                  icon: Icon(
                    Icons.filter_alt_off,
                    size: 18,
                    color: _temFiltro ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.outline,
                  ),
                  tooltip: 'Limpar filtros',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Contador ───────────────────────────────────────────────────
            Text(
              _verTodoEstoque
                  ? '${filtradosTodos.length} ${filtradosTodos.length == 1 ? 'material encontrado' : 'materiais encontrados'}'
                  : '${filtradosVinc.length} ${filtradosVinc.length == 1 ? 'material encontrado' : 'materiais encontrados'}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

            // ── Lista ──────────────────────────────────────────────────────
            Expanded(
              child: _verTodoEstoque
                  ? _buscando
                      ? const Center(child: CircularProgressIndicator())
                      : filtradosTodos.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum material encontrado.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtradosTodos.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                              itemBuilder: (_, i) {
                                final m = filtradosTodos[i];
                                final mid = m['id'] as int;
                                final eNovo = !vinculadosIds.contains(mid);
                                final partes = <String>[
                                  if ((m['medida'] ?? '').toString().isNotEmpty) m['medida'].toString(),
                                  if ((m['espessura'] ?? '').toString().isNotEmpty) m['espessura'].toString(),
                                  if ((m['identificador'] ?? '').toString().isNotEmpty) m['identificador'].toString(),
                                ];
                                final desc = partes.isEmpty
                                    ? (m['nome'] ?? '').toString()
                                    : '${m['nome']} · ${partes.join(' · ')}';

                                // Preço do vínculo existente, se houver
                                final vinculo = widget.materiais.cast<FornecedorMaterialVinculoModel?>()
                                    .firstWhere((v) => v?.materialId == mid, orElse: () => null);
                                final precoStr = vinculo != null
                                    ? (vinculo.preco > 0
                                        ? 'R\$ ${vinculo.preco.toStringAsFixed(2).replaceAll('.', ',')}${vinculo.precoMetroQuadrado > 0 ? '  •  m²: R\$ ${vinculo.precoMetroQuadrado.toStringAsFixed(2).replaceAll('.', ',')}' : ''}'
                                        : vinculo.precoMetroQuadrado > 0
                                            ? 'm²: R\$ ${vinculo.precoMetroQuadrado.toStringAsFixed(2).replaceAll('.', ',')}'
                                            : 'Sem preço cadastrado')
                                    : 'Sem preço — será vinculado ao salvar';

                                return _buildItem(
                                  materialId: mid,
                                  descricao: desc,
                                  preco: precoStr,
                                  eNovo: eNovo,
                                );
                              },
                            )
                  // ── modo vinculados (comportamento original) ─────────────
                  : filtradosVinc.isEmpty
                      ? Center(
                          child: Text(
                            widget.materiais.isEmpty
                                ? 'Este fornecedor não possui materiais vinculados.\nUse "Ver todo o estoque" para adicionar.'
                                : 'Nenhum material encontrado com esses filtros.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtradosVinc.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                          itemBuilder: (_, i) {
                            final m = filtradosVinc[i];
                            final precoStr = m.preco > 0
                                ? 'R\$ ${m.preco.toStringAsFixed(2).replaceAll('.', ',')}${m.precoMetroQuadrado > 0 ? '  •  m²: R\$ ${m.precoMetroQuadrado.toStringAsFixed(2).replaceAll('.', ',')}' : ''}'
                                : m.precoMetroQuadrado > 0
                                    ? 'm²: R\$ ${m.precoMetroQuadrado.toStringAsFixed(2).replaceAll('.', ',')}'
                                    : 'Sem preço cadastrado';
                            return _buildItem(
                              materialId: m.materialId,
                              descricao: m.descricaoCompleta,
                              preco: precoStr,
                              eNovo: false,
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
          child: Text('Cancelar',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: _totalItens == 0 ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: Text(
            _totalItens == 0 ? 'Adicionar' : 'Adicionar ($_totalItens)',
          ),
        ),
      ],
    );
  }
}