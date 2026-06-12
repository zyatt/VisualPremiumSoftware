import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/estoque_model.dart';
import '../models/material_model.dart';
import '../providers/estoque_provider.dart';
import '../providers/material_provider.dart';
import '../theme/app_theme.dart';

// ── Formatter: maiúsculas sem acentos ─────────────────────────────────────────

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

// ── Cores do status da OS ──────────────────────────────────────────────────────

const _corEmAndamento = Color(0xFF2196F3); // azul
const _corFechada     = Color(0xFF4CAF50); // verde

Color _corStatus(String status) =>
    status == 'FECHADA' ? _corFechada : _corEmAndamento;

String _labelStatus(String status) =>
    status == 'FECHADA' ? 'Fechada' : 'Em andamento';

// ═════════════════════════════════════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class ControleEstoquePage extends StatefulWidget {
  const ControleEstoquePage({super.key});

  @override
  State<ControleEstoquePage> createState() => _ControleEstoquePageState();
}

class _ControleEstoquePageState extends State<ControleEstoquePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _buscaCtrl        = TextEditingController();
  final TextEditingController _buscaNomeCtrl    = TextEditingController();
  final TextEditingController _buscaIdCtrl      = TextEditingController();
  final TextEditingController _identificadorCtrl = TextEditingController();
  final TextEditingController _medidaCtrl        = TextEditingController();
  final TextEditingController _espessuraCtrl     = TextEditingController();
  late TabController _tabController;
  Timer? _timerFechamentoAutomatico;
  Timer? _debounceTimer;

  // ── Calcula quanto tempo falta até a meia-noite ────────────────────────────
  Duration get _duracaoAteMeiaNoite {
    final agora = DateTime.now();
    final meiaNoite = DateTime(agora.year, agora.month, agora.day + 1);
    return meiaNoite.difference(agora);
  }

  // ── Verifica se o número da OS é NÃO numérico (textual) ───────────────────
  bool _osEhTextual(String numeroOS) {
    // Remove sufixos internos (#OC, #S, #E) antes de avaliar
    final semSufixo = numeroOS.replaceAll(RegExp(r'#(OC|S|E)\d*$'), '').trim();
    return int.tryParse(semSufixo) == null;
  }

  // ── Fecha OS textuais criadas em dias anteriores ao dia atual ────────────
  /// Chamado na abertura da página para cobrir o caso em que o app ficou
  /// fechado durante a virada do dia e o timer nunca disparou.
  Future<void> _fecharOSTextuaisAtrasadas() async {
    if (!mounted) return;
    final provider = context.read<EstoqueProvider>();

    final hoje = DateTime.now();
    final inicioDoDia = DateTime(hoje.year, hoje.month, hoje.day);

    final atrasadas = provider.relacoesOS.where((r) {
      if (r.status != 'EM_ANDAMENTO') return false;
      if (!_osEhTextual(r.numeroOS)) return false;
      // criadoEm anterior ao início do dia atual = dia diferente
      final criacao = r.criadoEm;
      if (criacao == null) return false;
      return criacao.toLocal().isBefore(inicioDoDia);
    }).toList();

    for (final os in atrasadas) {
      await provider.fecharOS(os.id);
    }

    if (mounted && atrasadas.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${atrasadas.length} OS textual(is) de dia(s) anterior(es) fechada(s) automaticamente.',
          ),
          backgroundColor: _corFechada,
          duration: const Duration(seconds: 5),
        ),
      );
      await provider.carregarRelacoesOS();
    }
  }

  // ── Fecha automaticamente todas as OS textuais em andamento ───────────────
  Future<void> _fecharOSTextuaisAutomaticamente() async {
    if (!mounted) return;
    final provider = context.read<EstoqueProvider>();

    // Garante que a lista está atualizada
    await provider.carregarRelacoesOS();
    if (!mounted) return;

    final osTextuaisEmAndamento = provider.relacoesOS
        .where((r) => r.status == 'EM_ANDAMENTO' && _osEhTextual(r.numeroOS))
        .toList();

    for (final os in osTextuaisEmAndamento) {
      await provider.fecharOS(os.id);
    }

    if (mounted && osTextuaisEmAndamento.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${osTextuaisEmAndamento.length} OS textual(is) fechada(s) automaticamente.',
          ),
          backgroundColor: _corFechada,
          duration: const Duration(seconds: 5),
        ),
      );
      // Recarrega para refletir o novo estado
      await provider.carregarRelacoesOS();
    }

    // Agenda o próximo fechamento automático para a meia-noite seguinte
    if (mounted) _agendarFechamentoAutomatico();
  }

  // ── Agenda o timer para a próxima meia-noite ──────────────────────────────
  void _agendarFechamentoAutomatico() {
    _timerFechamentoAutomatico?.cancel();
    _timerFechamentoAutomatico = Timer(
      _duracaoAteMeiaNoite,
      _fecharOSTextuaisAutomaticamente,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<EstoqueProvider>().carregarRelacoesOS();
      await _fecharOSTextuaisAtrasadas();
      _agendarFechamentoAutomatico();
    });
  }

  @override
  void dispose() {
    _timerFechamentoAutomatico?.cancel();
    _debounceTimer?.cancel();
    _tabController.dispose();
    _buscaCtrl.dispose();
    _buscaNomeCtrl.dispose();
    _buscaIdCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  void _buscar(String v) {
    context
        .read<EstoqueProvider>()
        .carregarRelacoesOS(busca: v.trim().isEmpty ? null : v.trim());
  }

  void _abrirMovimentacaoGlobal(String tipo) {
    showDialog(
      context: context,
      builder: (_) => _MovimentacaoGlobalDialog(tipo: tipo),
    );
  }

  // ── Aplica filtros de material client-side ────────────────────────────────
  List<RelacaoOSModel> _filtrarPorMaterial(List<RelacaoOSModel> lista) {
    final nome          = _buscaNomeCtrl.text.trim().toLowerCase();
    final idTexto       = _buscaIdCtrl.text.trim();
    final identificador = _identificadorCtrl.text.trim().toUpperCase();
    final medida        = _medidaCtrl.text.trim().toUpperCase();
    final espessura     = _espessuraCtrl.text.trim().toUpperCase();

    final temFiltro = nome.isNotEmpty ||
        idTexto.isNotEmpty ||
        identificador.isNotEmpty ||
        medida.isNotEmpty ||
        espessura.isNotEmpty;

    if (!temFiltro) return lista;

    return lista.where((r) {
      return r.movimentacoes.any((m) {
        if (nome.isNotEmpty &&
            !m.materialNome.toLowerCase().contains(nome)) {
          return false;
        }
        if (idTexto.isNotEmpty &&
            !m.materialId.toString().contains(idTexto)) {
          return false;
        }
        if (identificador.isNotEmpty) {
          final v = (m.materialIdentificador ?? '').toUpperCase();
          if (!v.contains(identificador)) return false;
        }
        if (medida.isNotEmpty) {
          final v = (m.materialMedida ?? '').toUpperCase();
          if (!v.contains(medida)) return false;
        }
        if (espessura.isNotEmpty) {
          final v = (m.materialEspessura ?? '').toUpperCase();
          if (!v.contains(espessura)) return false;
        }
        return true;
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();

    final emAndamento = _filtrarPorMaterial(
      provider.relacoesOS.where((r) => r.status == 'EM_ANDAMENTO').toList(),
    );
    final fechadas = _filtrarPorMaterial(
      provider.relacoesOS.where((r) => r.status == 'FECHADA').toList(),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ──────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Controle de Estoque',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Movimentações por Ordem de Serviço',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _abrirMovimentacaoGlobal('ENTRADA'),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Entrada'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _abrirMovimentacaoGlobal('SAIDA'),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  label: const Text('Saída'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                SizedBox(width: 10),
                IconButton(
                  onPressed: () => context.read<EstoqueProvider>().carregarRelacoesOS(),
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
            const SizedBox(height: 20),

            // ── Barras de busca — linha 1 ──────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Busca por número da OS
                Expanded(
                  child: TextField(
                    controller: _buscaCtrl,
                    onChanged: _buscar,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Buscar por número da OS...',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Filtro por nome do material (client-side)
                Expanded(
                  child: TextField(
                    controller: _buscaNomeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Filtrar por nome do material...',
                      prefixIcon: Icon(Icons.filter_alt_outlined,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                // Limpar todos os filtros
                IconButton(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onPressed: () {
                    _buscaCtrl.clear();
                    _buscaNomeCtrl.clear();
                    _buscaIdCtrl.clear();
                    _identificadorCtrl.clear();
                    _medidaCtrl.clear();
                    _espessuraCtrl.clear();
                    setState(() {});
                    context.read<EstoqueProvider>().carregarRelacoesOS();
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),

            // ── Barras de busca — linha 2 (id, identificador, medida, espessura)
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _buscaIdCtrl,
                    decoration: InputDecoration(
                      hintText:   'ID...',
                      prefixIcon: Icon(Icons.tag,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: InputDecoration(
                      hintText:   'Identificador...',
                      prefixIcon: Icon(Icons.qr_code,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: InputDecoration(
                      hintText:   'Medida...',
                      prefixIcon: Icon(Icons.straighten,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: InputDecoration(
                      hintText:   'Espessura...',
                      prefixIcon: Icon(Icons.layers,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // ── Abas ───────────────────────────────────────────────
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
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  Tab(
                    text: provider.carregando
                        ? 'Em Andamento'
                        : 'Em Andamento (${emAndamento.length})',
                  ),
                  Tab(
                    text: provider.carregando
                        ? 'Fechadas'
                        : 'Fechadas (${fechadas.length})',
                  ),
                ],
              ),
            ),

            // ── Conteúdo ────────────────────────────────────────────
            Expanded(
              child: provider.carregando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : provider.erro != null
                      ? SizedBox(
                          height: 300,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_off_outlined,
                                    size: 48, color: AppTheme.error),
                                SizedBox(height: 12),
                                Text(
                                  'Erro ao carregar controle de estoque',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  () {
                                    final partes = provider.erro!.split(': ');
                                    return partes.length > 1
                                        ? partes.sublist(1).join(': ')
                                        : provider.erro!;
                                  }(),
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => context
                                      .read<EstoqueProvider>()
                                      .carregarRelacoesOS(),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Tentar novamente'),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.primary),
                                ),
                              ],
                            ),
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _OsGrid(
                              relacoes: emAndamento,
                              emptyMessage: 'Nenhuma OS em andamento',
                              onTap: _abrirDetalhe,
                            ),
                            _OsGrid(
                              relacoes: fechadas,
                              emptyMessage: 'Nenhuma OS fechada',
                              onTap: _abrirDetalhe,
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirDetalhe(RelacaoOSModel rel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _RelacaoDetalhe(relacaoOSId: rel.id, numeroOS: rel.numeroOS),
      ),
    );
  }
}

// ─── Grid de OS (widget auxiliar para as abas) ────────────────────────────────

bool _osEhNumerica(String numeroOS) => int.tryParse(numeroOS.trim()) != null;

class _OsGrid extends StatelessWidget {
  final List<RelacaoOSModel> relacoes;
  final String emptyMessage;
  final void Function(RelacaoOSModel) onTap;

  const _OsGrid({
    required this.relacoes,
    required this.emptyMessage,
    required this.onTap,
  });

  SliverToBoxAdapter _cabecalho(String titulo, int count, BuildContext context) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 20, bottom: 10),
          child: Row(
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (relacoes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 12),
            Text(
              emptyMessage,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final numericas = relacoes.where((r) =>  _osEhNumerica(r.numeroOS)).toList();
    final textuais  = relacoes.where((r) => !_osEhNumerica(r.numeroOS)).toList();

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1,
    );

    return CustomScrollView(
      slivers: [
        if (numericas.isNotEmpty) ...[
          _cabecalho('Ordens de Serviço', numericas.length, context),
          SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final rel = numericas[i];
                return _RelacaoOSCard(relacao: rel, onTap: () => onTap(rel));
              },
              childCount: numericas.length,
            ),
            gridDelegate: gridDelegate,
          ),
        ],
        if (textuais.isNotEmpty) ...[
          _cabecalho('Empresa', textuais.length, context),
          SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final rel = textuais[i];
                return _RelacaoOSCard(relacao: rel, onTap: () => onTap(rel));
              },
              childCount: textuais.length,
            ),
            gridDelegate: gridDelegate,
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

// ─── Card de OS ────────────────────────────────────────────────────────────────

class _RelacaoOSCard extends StatelessWidget {
  final RelacaoOSModel relacao;
  final VoidCallback onTap;

  const _RelacaoOSCard({required this.relacao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = relacao.atualizadoEm ?? relacao.criadoEm;
    final dataStr = data != null
        ? '${data.day.toString().padLeft(2, '0')}/'
            '${data.month.toString().padLeft(2, '0')}/'
            '${data.year}'
        : '—';

    // Remove sufixo interno "#OCx" / "#Sx" / "#Ex" de OS textuais antes de exibir
    final numeroOSRaw = relacao.numeroOS;
    final idxSufixo   = [
      numeroOSRaw.indexOf('#OC'),
      numeroOSRaw.indexOf('#S'),
      numeroOSRaw.indexOf('#E'),
    ].where((i) => i > 0)
     .fold<int>(-1, (best, i) => best == -1 ? i : (i < best ? i : best));
    final numeroOSDisplay = idxSufixo > 0
        ? numeroOSRaw.substring(0, idxSufixo)
        : numeroOSRaw;

    final materiaisUnicos = relacao.movimentacoes.map((m) {
      final desc = m.descricaoItem?.trim() ?? '';
      // Usa materialId (não nome) para distinguir corretamente materiais com
      // mesmo nome mas medida/espessura diferentes. Para filhos específicos,
      // adiciona a descrição do item para contar cada variação separadamente.
      return desc.isNotEmpty ? '${m.materialId}::$desc' : '${m.materialId}';
    }).toSet().length;

    final corSt = _corStatus(relacao.status);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Ícone + badge de status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_outlined,
                        color: AppTheme.primary, size: 20),
                  ),
                  const Spacer(),
                  // Badge status
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: corSt.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: corSt.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      _labelStatus(relacao.status),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: corSt,
                      ),
                    ),
                  ),
                ],
              ),
              // Título + contagem + data
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    int.tryParse(numeroOSDisplay) != null
                        ? 'OS $numeroOSDisplay'
                        : numeroOSDisplay,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    '$materiaisUnicos '
                    '${materiaisUnicos == 1 ? 'material' : 'materiais'}',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    dataStr,
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tela de detalhe da OS ────────────────────────────────────────────────────

class _RelacaoDetalhe extends StatefulWidget {
  final int relacaoOSId;
  final String numeroOS;
  const _RelacaoDetalhe({required this.relacaoOSId, required this.numeroOS});

  @override
  State<_RelacaoDetalhe> createState() => _RelacaoDetalheState();
}

class _RelacaoDetalheState extends State<_RelacaoDetalhe> {
  bool _revertendo = false;

  /// Remove sufixo interno "#OCx" / "#Sx" / "#Ex" usado para distinguir OS textuais no banco.
  String get _numeroOSDisplay {
    final n = widget.numeroOS;
    final candidates = [n.indexOf('#OC'), n.indexOf('#S'), n.indexOf('#E')]
        .where((i) => i > 0)
        .toList();
    if (candidates.isEmpty) return n;
    candidates.sort();
    return n.substring(0, candidates.first);
  }

  String get _tituloOS => int.tryParse(_numeroOSDisplay) != null
      ? 'OS $_numeroOSDisplay'
      : _numeroOSDisplay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstoqueProvider>().selecionarRelacaoOS(widget.numeroOS);
    });
  }

  // ── Abrir movimentação vinculada a esta OS ────────────────────────────────
  void _abrirMovimentacaoOS(BuildContext context, String tipo) {
    showDialog(
      context: context,
      builder: (_) => _MovimentacaoGlobalDialog(
        tipo: tipo,
        numeroOSFixo: widget.numeroOS, // passa o numeroOS real (com sufixo) para vincular
      ),
    ).then((_) {
      // Recarrega o detalhe da OS após fechar o dialog
      if (context.mounted) {
        context.read<EstoqueProvider>().selecionarRelacaoOS(widget.numeroOS);
      }
    });
  }

  // ── Reverter OS ────────────────────────────────────────────────────────────
  Future<void> _confirmarReverterOS() async {
    const corReverter = Color(0xFFED6C02);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: corReverter.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.undo_rounded, color: corReverter, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Reverter OS'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja reverter "$_tituloOS" para Em Andamento?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: const Text('Reverter OS'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!mounted) return;

    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _revertendo = true);

    final ok = await provider.reverterOS(widget.numeroOS);

    if (!mounted) return;
    setState(() => _revertendo = false);

    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$_tituloOS revertida — disponível em Em Andamento'),
          backgroundColor: corReverter,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao reverter OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Fechar OS ──────────────────────────────────────────────────────────────
  Future<void> _confirmarFecharOS(BuildContext context) async {
    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _corEmAndamento.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.lock_outline,
                  color: _corEmAndamento, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Fechar OS'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja fechar "$_tituloOS"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _corEmAndamento.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _corEmAndamento.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Após fechar:\n'
                '• A OS não aceitará novas movimentações\n'
                '• Ela será movida para a página de Relatórios\n'
                '• Um relatório PDF poderá ser gerado',
                style:
                    TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Fechar OS'),
            style: FilledButton.styleFrom(
              backgroundColor: _corEmAndamento,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await provider.fecharOS(widget.relacaoOSId);

    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$_tituloOS fechada — disponível em Relatórios'),
          backgroundColor: _corEmAndamento,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao fechar OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Excluir OS ─────────────────────────────────────────────────────────────
  Future<void> _confirmarExcluirOS(BuildContext context) async {
    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir OS'),
        content: Text(
          'Deseja excluir "$_tituloOS" e todas as suas '
          'movimentações? Esta ação não pode ser desfeita.',
        ),
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

    if (confirmar != true) return;

    final ok = await provider.excluirRelacaoOS(widget.relacaoOSId);

    if (ok) {
      provider.limparSelecao();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$_tituloOS excluída'),
          backgroundColor: AppTheme.error,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao excluir OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Renomear OS ────────────────────────────────────────────────────────────
  Future<void> _abrirRenomearOS(BuildContext context, RelacaoOSModel rel) async {
    final provider  = context.read<EstoqueProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Remove sufixo interno antes de exibir no campo
    final nomeAtual = _numeroOSDisplay;
    final ctrl = TextEditingController(text: nomeAtual);

    final novoNome = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_outlined,
                      color: AppTheme.primary, size: 20),
                ),
                SizedBox(width: 12),
                Text('Renomear OS'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Novo número / nome da OS:',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperCaseFormatter()],
                  decoration: const InputDecoration(
                    hintText: 'Ex: 1234 ou MANUTENCAO',
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    final nome = v.trim();
                    if (nome.isNotEmpty && nome != nomeAtual) {
                      Navigator.of(dialogCtx).pop(nome);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () {
                        final nome = ctrl.text.trim();
                        if (nome.isEmpty) return;
                        if (nome == nomeAtual) {
                          Navigator.of(dialogCtx).pop();
                          return;
                        }
                        Navigator.of(dialogCtx).pop(nome);
                      },
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Renomear'),
              ),
            ],
          ),
        );
      },
    );

    ctrl.dispose();
    if (novoNome == null || novoNome.isEmpty || novoNome == nomeAtual) return;
    if (!mounted) return;

    final ok = await provider.renomearOS(rel.id, novoNome);
    if (!mounted) return;

    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('OS renomeada para "$novoNome"'),
          backgroundColor: AppTheme.primary,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao renomear OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();
    final rel      = provider.relacaoSelecionada;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            provider.limparSelecao();
            Navigator.of(context).pop();
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_tituloOS),
            if (rel != null) ...[
              const SizedBox(width: 10),
              _StatusBadgeOS(status: rel.status),
            ],
          ],
        ),
        actions: [
          // Botão Reverter OS (só para OS fechadas)
          if (rel != null && rel.estaFechada)
            _revertendo
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFED6C02)),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _confirmarReverterOS,
                    icon: const Icon(Icons.undo_rounded,
                        size: 18, color: Color(0xFFED6C02)),
                    label: const Text(
                      'Reverter OS',
                      style: TextStyle(
                        color: Color(0xFFED6C02),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          // Botões Entrada / Saída (só para OS em andamento)
          if (rel != null && !rel.estaFechada) ...[
            FilledButton.icon(
              onPressed: () => _abrirMovimentacaoOS(context, 'ENTRADA'),
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('Entrada'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _abrirMovimentacaoOS(context, 'SAIDA'),
              icon: const Icon(Icons.remove_circle_outline, size: 16),
              label: const Text('Saída'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Botão Fechar OS (só exibe se EM_ANDAMENTO)
          if (rel != null && !rel.estaFechada)
            TextButton.icon(
              onPressed: provider.fechandoOS
                  ? null
                  : () => _confirmarFecharOS(context),
              icon: provider.fechandoOS
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _corEmAndamento))
                  : Icon(Icons.lock_outline,
                      size: 18, color: _corEmAndamento),
              label: Text(
                'Finalizar OS',
                style: TextStyle(
                  color: provider.fechandoOS
                      ? Theme.of(context).colorScheme.outline
                      : _corEmAndamento,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Botão excluir (só para OS em andamento)
          if (rel != null && !rel.estaFechada)
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppTheme.error),
              tooltip: 'Excluir OS',
              onPressed: () => _confirmarExcluirOS(context),
            ),
          // Botão renomear (só para OS em andamento)
          if (rel != null && !rel.estaFechada)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
              tooltip: 'Renomear OS',
              onPressed: () => _abrirRenomearOS(context, rel),
            ),
        ],
      ),
      body: provider.carregandoDetalhe
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : rel == null
              ? Center(
                  child: Text(
                    'Relação não encontrada',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : _RelacaoDetalheBody(rel: rel),
    );
  }
}

// ─── Badge de status da OS ────────────────────────────────────────────────────

class _StatusBadgeOS extends StatelessWidget {
  final String status;
  const _StatusBadgeOS({required this.status});

  @override
  Widget build(BuildContext context) {
    final cor   = _corStatus(status);
    final label = _labelStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}

// ─── Corpo do detalhe ─────────────────────────────────────────────────────────

class _RelacaoDetalheBody extends StatefulWidget {
  final RelacaoOSModel rel;
  const _RelacaoDetalheBody({required this.rel});

  @override
  State<_RelacaoDetalheBody> createState() => _RelacaoDetalheBodyState();
}

class _RelacaoDetalheBodyState extends State<_RelacaoDetalheBody> {
  // Chave composta: "materialId" para materiais normais,
  // "materialId::descricaoItem" para materiais específicos (descricaoItem != null).
  String _chaveGrupo(MovimentacaoModel mov) {
    final desc = mov.descricaoItem?.trim() ?? '';
    return desc.isNotEmpty ? '${mov.materialId}::$desc' : '${mov.materialId}';
  }

  @override
  Widget build(BuildContext context) {
    final materiaisMap = <String, List<MovimentacaoModel>>{};
    for (final mov in widget.rel.movimentacoes) {
      materiaisMap.putIfAbsent(_chaveGrupo(mov), () => []).add(mov);
    }

    if (materiaisMap.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma movimentação registrada',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    final entries = materiaisMap.entries.toList();

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final entry = entries[i];
        final movs  = List<MovimentacaoModel>.from(entry.value)
          ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
        return _MaterialGridCard(
          key: ValueKey(entry.key),
          movimentacoes: movs,
          numeroOS: widget.rel.numeroOS,
          // OS fechada: bloqueia ações de movimentação/remoção
          somenteLeitura: widget.rel.estaFechada,
        );
      },
    );
  }
}

// ─── Card de material em grid ──────────────────────────────────────────────────

class _MaterialGridCard extends StatefulWidget {
  final List<MovimentacaoModel> movimentacoes;
  final String numeroOS;
  final bool somenteLeitura;

  const _MaterialGridCard({
    super.key,
    required this.movimentacoes,
    required this.numeroOS,
    this.somenteLeitura = false,
  });

  @override
  State<_MaterialGridCard> createState() => _MaterialGridCardState();
}

class _MaterialGridCardState extends State<_MaterialGridCard> {
  MovimentacaoModel get _primeira => widget.movimentacoes.first;

  String get _subtitulo {
    final partes = <String>[
      if ((_primeira.materialIdentificador ?? '').isNotEmpty)
        _primeira.materialIdentificador!,
      if ((_primeira.materialMedida ?? '').isNotEmpty)
        _primeira.materialMedida!,
      if ((_primeira.materialEspessura ?? '').isNotEmpty)
        _primeira.materialEspessura!,
    ];
    return partes.join(' · ');
  }

  String _formatQtd(double qtd, String? unidade) {
    final qStr = qtd == qtd.truncate()
        ? qtd.toStringAsFixed(0)
        : qtd.toStringAsFixed(2);
    return unidade != null ? '$qStr $unidade' : qStr;
  }

  String _formatData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  void _abrirMovimentacao(BuildContext context, String tipo) {
    // Para materiais específicos: usa o preço da movimentação de ENTRADA mais
    // recente deste card (aquele item/descrição), que é o preço pelo qual ele
    // entrou no estoque — não o último preço global do material pai.
    // Para materiais normais: busca o último preço registrado no material.
    final descricaoItem = _primeira.descricaoItem;
    final isEspecifico  = descricaoItem != null && descricaoItem.isNotEmpty;

    if (isEspecifico) {
      // Pega o preço da entrada mais recente deste item específico
      final ultimaEntrada = widget.movimentacoes
          .where((m) => m.tipo == 'ENTRADA')
          .fold<MovimentacaoModel?>(null, (prev, m) =>
              prev == null || m.criadoEm.isAfter(prev.criadoEm) ? m : prev);

      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => _MovimentacaoItemDialog(
          tipo:                 tipo,
          materialId:           _primeira.materialId,
          materialNome:         _primeira.materialNome,
          numeroOS:             widget.numeroOS,
          descricaoItem:        descricaoItem,
          precoUnitario:        ultimaEntrada?.precoUnitario ?? _primeira.precoUnitario,
          precoM2:              ultimaEntrada?.precoM2       ?? _primeira.precoM2,
          materialQtdPadrao:    _primeira.materialQtdPadrao,
          materialUnidPadrao:   _primeira.materialUnidPadrao,
        ),
      );
    } else {
      final ultimaMovOS = widget.movimentacoes
          .where((m) =>
              m.materialId == _primeira.materialId &&
              (m.precoUnitario != null && m.precoUnitario! > 0 ||
               m.precoM2 != null && m.precoM2! > 0))
          .fold<MovimentacaoModel?>(
              null,
              (prev, m) =>
                  prev == null || m.criadoEm.isAfter(prev.criadoEm) ? m : prev);

      if (ultimaMovOS != null) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (_) => _MovimentacaoItemDialog(
            tipo:               tipo,
            materialId:         _primeira.materialId,
            materialNome:       _primeira.materialNome,
            numeroOS:           widget.numeroOS,
            descricaoItem:      null,
            precoUnitario:      ultimaMovOS.precoUnitario,
            precoM2:            ultimaMovOS.precoM2,
            materialQtdPadrao:  _primeira.materialQtdPadrao,
            materialUnidPadrao: _primeira.materialUnidPadrao,
          ),
        );
      } else {
        context.read<MaterialProvider>().buscarPorId(_primeira.materialId).then((mat) {
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (_) => _MovimentacaoItemDialog(
              tipo:               tipo,
              materialId:         _primeira.materialId,
              materialNome:       _primeira.materialNome,
              numeroOS:           widget.numeroOS,
              descricaoItem:      null,
              precoUnitario:      mat?.ultimoValorPago   ?? _primeira.precoUnitario,
              precoM2:            mat?.ultimoValorPagoM2 ?? _primeira.precoM2,
              materialQtdPadrao:  _primeira.materialQtdPadrao,
              materialUnidPadrao: _primeira.materialUnidPadrao,
            ),
          );
        });
      }
    }
  }

  Future<void> _confirmarRemoverMovimentacao(
      BuildContext context, MovimentacaoModel mov) async {
    final provider  = context.read<EstoqueProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remover movimentação'),
        content: Text(
          'Remover ${mov.tipo == 'ENTRADA' ? 'entrada' : 'saída'} de '
          '${_formatQtd(mov.quantidade, _primeira.materialUnidade)} '
          'de "${mov.materialNome}"?\n\n'
          'Atenção: o saldo de estoque do material será revertido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await provider.removerMovimentacao(
      movimentacaoId: mov.id,
      numeroOS: widget.numeroOS,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Movimentação removida' : (provider.erro ?? 'Erro')),
        backgroundColor: ok ? AppTheme.success : AppTheme.error,
      ),
    );
  }


  // ── Atualizar custo da última compra em todas as movimentações do card ──────
  Future<void> _abrirAtualizarCusto(BuildContext context) async {
    final materialProvider = context.read<MaterialProvider>();
    final estoqueProvider  = context.read<EstoqueProvider>();
    final messenger        = ScaffoldMessenger.of(context);

    // Busca o material para obter o último valor pago
    final mat = await materialProvider.buscarPorId(_primeira.materialId);
    if (!context.mounted) return;

    final temPrecoUnit = mat?.ultimoValorPago    != null && mat!.ultimoValorPago!    > 0;
    final temPrecoM2   = mat?.ultimoValorPagoM2 != null && mat!.ultimoValorPagoM2! > 0;

    if (!temPrecoUnit && !temPrecoM2) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Nenhum custo de última compra registrado para este material'),
          backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
      return;
    }

    String brl(double v) =>
        'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.price_change_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Atualizar custo'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Atualizar o custo de todas as movimentações de "${_primeira.materialNome}" nesta OS?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Novo custo (última compra):',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  if (temPrecoUnit)
                    Text(
                      'Unit.: ${brl(mat.ultimoValorPago!)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary),
                    ),
                  if (temPrecoM2)
                    Text(
                      'M²: ${brl(mat.ultimoValorPagoM2!)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary),
                    ),
                ],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Somente o custo registrado nas movimentações será alterado — '
              'as quantidades e o saldo de estoque não mudam.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Atualizar custo'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!context.mounted) return;

    // Atualiza todas as movimentações do card em sequência
    int sucessos = 0;
    int falhas   = 0;
    for (final mov in widget.movimentacoes) {
      final ok = await estoqueProvider.atualizarPrecoMovimentacao(
        mov.id,
        precoUnitario: temPrecoUnit ? mat.ultimoValorPago  : null,
        precoM2:       temPrecoM2  ? mat.ultimoValorPagoM2 : null,
      );
      if (ok) {
        sucessos++;
      } else {
        falhas++;
      }
    }

    if (!context.mounted) return;

    // Recarrega o detalhe da OS para refletir os novos preços
    await estoqueProvider.selecionarRelacaoOS(widget.numeroOS);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          falhas == 0
              ? 'Custo atualizado em $sucessos movimentação(ões)'
              : '$sucessos atualizada(s), $falhas com erro',
        ),
        backgroundColor: falhas == 0 ? AppTheme.success : AppTheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unidade = _primeira.materialUnidade;
    final totais  = _TotaisMovimentacao.calcular(widget.movimentacoes);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _mostrarPainel(context),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _primeira.materialNome,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((_primeira.descricaoItem ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _primeira.descricaoItem!,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (_subtitulo.isNotEmpty) ...[
                          SizedBox(height: 2),
                          Text(
                            _subtitulo,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.expand_more,
                      size: 18, color: Theme.of(context).colorScheme.outline),
                ],
              ),
              Spacer(),
              _UltimoPrecoRow(movimentacoes: widget.movimentacoes),
              SizedBox(height: 6),
              _TotaisResumoMini(totais: totais, unidade: unidade),
              SizedBox(height: 4),
              Text(
                '${widget.movimentacoes.length} '
                '${widget.movimentacoes.length == 1 ? 'movimentação' : 'movimentações'}',
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarPainel(BuildContext context) async {
    // Dados estáticos do card (nome, descrição, subtítulo) — não mudam
    final materialNome   = _primeira.materialNome;
    final descricaoItem  = _primeira.descricaoItem;
    final subtitulo      = _subtitulo;
    final unidade        = _primeira.materialUnidade;
    final somenteLeitura = widget.somenteLeitura;
    final chaveGrupo     = widget.movimentacoes.isNotEmpty
        ? (() {
            final desc = _primeira.descricaoItem?.trim() ?? '';
            return desc.isNotEmpty
                ? '${_primeira.materialId}::$desc'
                : '${_primeira.materialId}';
          })()
        : '';

    await showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Consumer<EstoqueProvider>(
        builder: (ctx, provider, _) {
          // Busca as movimentações atualizadas do provider
          final rel = provider.relacaoSelecionada;
          final movsAtuais = rel == null
              ? <MovimentacaoModel>[]
              : rel.movimentacoes.where((m) {
                  final desc = m.descricaoItem?.trim() ?? '';
                  final chave = desc.isNotEmpty
                      ? '${m.materialId}::$desc'
                      : '${m.materialId}';
                  return chave == chaveGrupo;
                }).toList()
            ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

          // Se todas as movimentações foram removidas, fecha o dialog
          if (movsAtuais.isEmpty && rel != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            });
          }

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: SizedBox(
              width: 560,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                materialNome,
                                style: Theme.of(ctx).textTheme.titleLarge,
                              ),
                              if ((descricaoItem ?? '').isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.label_outline,
                                        size: 13, color: AppTheme.primary),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        descricaoItem!,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (subtitulo.isNotEmpty)
                                Text(
                                  subtitulo,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              if (unidade != null)
                                Text(
                                  unidade,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _UltimoPrecoRow(
                      movimentacoes: movsAtuais,
                      expanded: true,
                    ),
                    const SizedBox(height: 10),
                    _TotaisResumoCompleto(
                      movimentacoes: movsAtuais,
                      unidade: unidade,
                    ),
                    const SizedBox(height: 16),

                    // Botões entrada / saída (ocultados se somente leitura)
                    if (!somenteLeitura) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _abrirMovimentacao(context, 'ENTRADA');
                              },
                              icon: const Icon(Icons.add,
                                  size: 16, color: AppTheme.success),
                              label: const Text('Entrada',
                                  style: TextStyle(color: AppTheme.success)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppTheme.success),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _abrirMovimentacao(context, 'SAIDA');
                              },
                              icon: const Icon(Icons.remove,
                                  size: 16, color: AppTheme.error),
                              label: const Text('Saída',
                                  style: TextStyle(color: AppTheme.error)),
                              style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: AppTheme.error),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ── Atualizar custo da última compra ─────────────────
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _abrirAtualizarCusto(context);
                          },
                          icon: Icon(Icons.price_change_outlined,
                              size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          label: Text(
                            'Atualizar custo (última compra)',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _corFechada.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _corFechada.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 14, color: _corFechada),
                            SizedBox(width: 6),
                            Text(
                              'OS fechada — somente leitura',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _corFechada,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                    ],

                    Divider(height: 1),
                    SizedBox(height: 12),

                    Text(
                      'Histórico (${movsAtuais.length})',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.35,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: movsAtuais.length,
                        itemBuilder: (_, i) {
                          final mov = movsAtuais[i];
                          return _MovimentacaoRow(
                            mov: mov,
                            unidade: unidade,
                            formatData: _formatData,
                            formatQtd: _formatQtd,
                            onRemove: somenteLeitura
                                ? null
                                : () => _confirmarRemoverMovimentacao(
                                    context, mov),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

  }
}

// ─── Último preço do material (unit. e/ou m²) ────────────────────────────────
// Lê o preço mais recente das movimentações passadas para exibir no card.

class _UltimoPrecoRow extends StatelessWidget {
  final List<MovimentacaoModel> movimentacoes;
  /// [expanded] = true no painel popup (layout horizontal mais largo).
  final bool expanded;

  const _UltimoPrecoRow({
    required this.movimentacoes,
    this.expanded = false,
  });

  static String _brl(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    // Pega a movimentação mais recente com preço (ENTRADA ou SAIDA)
    final todas = List<MovimentacaoModel>.from(movimentacoes)
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

    double? pu;
    double? pm2;
    for (final mov in todas) {
      if (pu == null && mov.precoUnitario != null && mov.precoUnitario! > 0) {
        pu = mov.precoUnitario;
      }
      if (pm2 == null && mov.precoM2 != null && mov.precoM2! > 0) {
        pm2 = mov.precoM2;
      }
      if (pu != null && pm2 != null) break;
    }

    if (pu == null && pm2 == null) return const SizedBox.shrink();

    final chips = <Widget>[];
    if (pu != null) {
      chips.add(_PrecoBadge(label: 'Unit.', valor: _brl(pu)));
    }
    if (pm2 != null) {
      if (chips.isNotEmpty) chips.add(const SizedBox(width: 4));
      chips.add(_PrecoBadge(label: 'M²', valor: _brl(pm2)));
    }

    return Row(children: chips);
  }
}

class _PrecoBadge extends StatelessWidget {
  final String label;
  final String valor;
  const _PrecoBadge({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: valor,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Totais de entrada/saída ──────────────────────────────────────────────────

class _TotaisMovimentacao {
  final double qtdEntrada;
  final double qtdSaida;
  final double valorEntrada;
  final double valorSaida;

  const _TotaisMovimentacao({
    required this.qtdEntrada,
    required this.qtdSaida,
    required this.valorEntrada,
    required this.valorSaida,
  });

  static String _brl(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String get qtdEntradaStr => qtdEntrada == qtdEntrada.truncate()
      ? qtdEntrada.toStringAsFixed(0)
      : qtdEntrada.toStringAsFixed(2);

  String get qtdSaidaStr => qtdSaida == qtdSaida.truncate()
      ? qtdSaida.toStringAsFixed(0)
      : qtdSaida.toStringAsFixed(2);

  String get valorEntradaStr => _brl(valorEntrada);
  String get valorSaidaStr   => _brl(valorSaida);

  static _TotaisMovimentacao calcular(List<MovimentacaoModel> movs) {
    double qtdE = 0, qtdS = 0, valE = 0, valS = 0;
    for (final m in movs) {
      final pm2 = m.precoM2;
      final pu  = m.precoUnitario;
      // Usa preço m² quando disponível, senão unitário
      final preco = (pm2 != null && pm2 > 0) ? pm2 : (pu ?? 0.0);
      if (m.tipo == 'ENTRADA') {
        qtdE += m.quantidade;
        valE += m.quantidade * preco;
      } else {
        qtdS += m.quantidade;
        valS += m.quantidade * preco;
      }
    }
    return _TotaisMovimentacao(
      qtdEntrada: qtdE, qtdSaida: qtdS,
      valorEntrada: valE, valorSaida: valS,
    );
  }
}

/// Chips compactos exibidos no card fechado.
class _TotaisResumoMini extends StatelessWidget {
  final _TotaisMovimentacao totais;
  final String? unidade;
  const _TotaisResumoMini({required this.totais, required this.unidade});

  @override
  Widget build(BuildContext context) {
    final unStr      = unidade ?? '';
    final temEntrada = totais.qtdEntrada > 0;
    final temSaida   = totais.qtdSaida   > 0;
    if (!temEntrada && !temSaida) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (temEntrada)
          _TotalChip(
            icon: Icons.arrow_upward,
            cor: AppTheme.success,
            qtd: '${totais.qtdEntradaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
            valor: totais.valorEntradaStr,
          ),
        if (temSaida)
          _TotalChip(
            icon: Icons.arrow_downward,
            cor: AppTheme.error,
            qtd: '${totais.qtdSaidaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
            valor: totais.valorSaidaStr,
          ),
      ],
    );
  }
}

/// Bloco expandido exibido no modal de detalhe do material.
class _TotaisResumoCompleto extends StatelessWidget {
  final List<MovimentacaoModel> movimentacoes;
  final String? unidade;
  const _TotaisResumoCompleto({required this.movimentacoes, required this.unidade});

  @override
  Widget build(BuildContext context) {
    final totais     = _TotaisMovimentacao.calcular(movimentacoes);
    final unStr      = unidade ?? '';
    final temEntrada = totais.qtdEntrada > 0;
    final temSaida   = totais.qtdSaida   > 0;
    if (!temEntrada && !temSaida) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (temEntrada)
            Expanded(
              child: _TotalLinha(
                icon: Icons.arrow_upward,
                cor: AppTheme.success,
                label: 'Entrada total',
                qtd: '${totais.qtdEntradaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
                valor: totais.valorEntradaStr,
              ),
            ),
          if (temEntrada && temSaida)
            Container(
              width: 1,
              height: 36,
              margin: EdgeInsets.symmetric(horizontal: 10),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          if (temSaida)
            Expanded(
              child: _TotalLinha(
                icon: Icons.arrow_downward,
                cor: AppTheme.error,
                label: 'Saída total',
                qtd: '${totais.qtdSaidaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
                valor: totais.valorSaidaStr,
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final IconData icon;
  final Color cor;
  final String qtd;
  final String valor;
  const _TotalChip({required this.icon, required this.cor, required this.qtd, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: cor),
          const SizedBox(width: 3),
          Text(qtd,    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cor)),
          const SizedBox(width: 3),
          Text(valor,  style: TextStyle(fontSize: 9,  fontWeight: FontWeight.w500, color: cor.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

class _TotalLinha extends StatelessWidget {
  final IconData icon;
  final Color cor;
  final String label;
  final String qtd;
  final String valor;
  const _TotalLinha({required this.icon, required this.cor, required this.label, required this.qtd, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: cor),
        ),
        SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            Text(qtd,   style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cor)),
            Text(valor, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor.withValues(alpha: 0.75))),
          ],
        ),
      ],
    );
  }
}

// ─── Row de movimentação ──────────────────────────────────────────────────────

class _MovimentacaoRow extends StatelessWidget {
  final MovimentacaoModel mov;
  final String? unidade;
  final String Function(DateTime) formatData;
  final String Function(double, String?) formatQtd;
  // null = somente leitura (OS fechada)
  final VoidCallback? onRemove;

  const _MovimentacaoRow({
    required this.mov,
    required this.unidade,
    required this.formatData,
    required this.formatQtd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isEntrada = mov.tipo == 'ENTRADA';
    final cor  = isEntrada ? AppTheme.success : AppTheme.error;
    final icon = isEntrada ? Icons.arrow_upward : Icons.arrow_downward;

    return Container(
      margin: EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: cor),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isEntrada ? 'Entrada' : 'Saída',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      formatQtd(mov.quantidade, unidade),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    // Badge de preço desta movimentação
                    Builder(builder: (_) {
                      final pu  = mov.precoUnitario;
                      final pm2 = mov.precoM2;
                      final partes = <String>[];
                      if (pu  != null && pu  > 0) partes.add('R\$ ${pu.toStringAsFixed(2).replaceAll('.', ',')}');
                      if (pm2 != null && pm2 > 0) partes.add('R\$ ${pm2.toStringAsFixed(2).replaceAll('.', ',')} /m²');
                      if (partes.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            partes.join(' · '),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  formatData(mov.criadoEm),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline, fontSize: 11),
                ),
                if (mov.observacao != null &&
                    mov.observacao!.isNotEmpty) ...[
                  SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes,
                          size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          mov.observacao!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Botão remover — oculto quando OS está fechada
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppTheme.error),
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(28, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: 'Remover movimentação',
            )
          else
            const SizedBox(width: 28),
        ],
      ),
    );
  }
}

// ─── Dialog: movimentação de item específico ──────────────────────────────────

class _MovimentacaoItemDialog extends StatefulWidget {
  final String tipo;
  final int materialId;
  final String materialNome;
  final String numeroOS;
  final String? descricaoItem;
  final double? precoUnitario;
  final double? precoM2;
  final double? materialQtdPadrao;
  final String? materialUnidPadrao;

  const _MovimentacaoItemDialog({
    required this.tipo,
    required this.materialId,
    required this.materialNome,
    required this.numeroOS,
    this.descricaoItem,
    this.precoUnitario,
    this.precoM2,
    this.materialQtdPadrao,
    this.materialUnidPadrao,
  });

  @override
  State<_MovimentacaoItemDialog> createState() =>
      _MovimentacaoItemDialogState();
}

class _MovimentacaoItemDialogState extends State<_MovimentacaoItemDialog> {
  final _formKey   = GlobalKey<FormState>();
  final _quantCtrl = TextEditingController();
  final _obsCtrl   = TextEditingController();
  bool _enviando   = false;
  String? _erroEstoque;

  @override
  void dispose() {
    _quantCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() => _erroEstoque = null);
    if (!_formKey.currentState!.validate()) return;

    final quant = double.tryParse(_quantCtrl.text.replaceAll(',', '.'));

    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _enviando = true);
    
    // ╔════════════════════════════════════════════════════════════════════╗
    // ║ Usa o numeroOS completo (com sufixo) que veio do context          ║
    // ╚════════════════════════════════════════════════════════════════════╝
    final ok = await provider.registrarMovimentacao(
      materialId:    widget.materialId,
      tipo:          widget.tipo,
      quantidade:    quant!,
      numeroOS:      widget.numeroOS,  // já vem com sufixo quando necessário
      descricaoItem: widget.descricaoItem,
      precoUnitario: widget.precoUnitario,
      precoM2:       widget.precoM2,
      observacao:    _obsCtrl.text.trim().isEmpty
          ? null
          : _obsCtrl.text.trim(),
    );
    
    if (!mounted) return;
    setState(() => _enviando = false);
    
    if (ok) {
      provider.selecionarRelacaoOS(widget.numeroOS);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${widget.tipo == 'ENTRADA' ? 'Entrada' : 'Saída'} registrada'),
        backgroundColor:
            widget.tipo == 'ENTRADA' ? AppTheme.success : AppTheme.error,
      ));
    } else {
      final erro = provider.erro ?? 'Erro desconhecido';
      if (erro.toLowerCase().contains('estoque')) {
        setState(() => _erroEstoque = erro);
        _formKey.currentState!.validate();
      } else {
        messenger.showSnackBar(
            SnackBar(content: Text(erro), backgroundColor: AppTheme.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEntrada = widget.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEntrada
                ? Icons.add_circle_outline
                : Icons.remove_circle_outline,
            color: cor,
          ),
          SizedBox(width: 8),
          Text(isEntrada ? 'Registrar Entrada' : 'Registrar Saída'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.materialNome,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 4),
            Text('OS ${widget.numeroOS}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _quantCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantidade'),
              validator: (v) {
                if (_erroEstoque != null) return _erroEstoque;
                final quant =
                    double.tryParse((v ?? '').replaceAll(',', '.'));
                if (quant == null || quant <= 0) {
                  return 'Informe uma quantidade válida';
                }
                return null;
              },
              onChanged: (_) {
                if (_erroEstoque != null) setState(() => _erroEstoque = null);
              },
            ),
            // Exibe o preço que será gravado com a movimentação
            Builder(builder: (_) {
              final pu         = widget.precoUnitario;
              final pm2        = widget.precoM2;
              final qtdPadrao  = widget.materialQtdPadrao;
              final unidPadrao = widget.materialUnidPadrao;
              final temQtdPad  = qtdPadrao != null && qtdPadrao > 0 &&
                                 unidPadrao != null && unidPadrao.isNotEmpty;

              String fmtPreco(double v) {
                if (v >= 1) return v.toStringAsFixed(2).replaceAll('.', ',');
                String s = v.toStringAsFixed(6).replaceAll('.', ',');
                while (s.endsWith('0')) {
                  s = s.substring(0, s.length - 1);
                }
                if (s.endsWith(',')) s = '${s}0';
                return s;
              }

              final partes = <String>[];
              if (pu != null && pu > 0) {
                if (temQtdPad) {
                  partes.add('Custo: R\$ ${fmtPreco(pu)}/${unidPadrao.toLowerCase()}');
                  partes.add('≈ R\$ ${fmtPreco(pu * qtdPadrao)}/embalagem');
                } else {
                  partes.add('Unit.: R\$ ${pu.toStringAsFixed(2).replaceAll('.', ',')}');
                }
              }
              if (pm2 != null && pm2 > 0) {
                partes.add('M²: R\$ ${pm2.toStringAsFixed(2).replaceAll('.', ',')}');
              }
              if (partes.isEmpty) return SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.price_check, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        partes.join('  ·  '),
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _obsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Observação (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: cor),
          child: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isEntrada ? 'Confirmar Entrada' : 'Confirmar Saída'),
        ),
      ],
    );
  }
}

// ─── Dialog: movimentação global (nova OS) ────────────────────────────────────

class _MovimentacaoGlobalDialog extends StatefulWidget {
  final String tipo;
  /// Quando informado, o campo OS fica pré-preenchido e bloqueado,
  /// vinculando a movimentação a uma OS específica já aberta.
  final String? numeroOSFixo;

  const _MovimentacaoGlobalDialog({required this.tipo, this.numeroOSFixo});

  @override
  State<_MovimentacaoGlobalDialog> createState() =>
      _MovimentacaoGlobalDialogState();
}

class _MovimentacaoGlobalDialogState
    extends State<_MovimentacaoGlobalDialog> {
  final _formKey      = GlobalKey<FormState>();
  final _numeroOSCtrl = TextEditingController();
  final List<_ItemMovimentacao> _itensSelecionados = [];
  bool _enviando = false;

  final _idCtrl            = TextEditingController();
  final _nomeCtrl          = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  final _descricaoCtrl     = TextEditingController(); // filtro por descrição de filho
  String? _categoriaFiltro;
  List<String> _categorias = [];

  List<MaterialModel> _resultados = [];
  bool _buscando    = false;
  bool _buscouUmaVez = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
    // Se um numeroOS fixo foi passado, pré-preenche o campo
    if (widget.numeroOSFixo != null) {
      // Exibe sem sufixo interno (#S... ou #OC...) para o usuário
      final raw = widget.numeroOSFixo!;
      final candidates = [raw.indexOf('#OC'), raw.indexOf('#S'), raw.indexOf('#E')]
          .where((i) => i > 0)
          .toList();
      candidates.sort();
      _numeroOSCtrl.text = candidates.isEmpty
          ? raw
          : raw.substring(0, candidates.first);
    }
  }

  @override
  void dispose() {
    _numeroOSCtrl.dispose();
    _idCtrl.dispose();
    _nomeCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    _descricaoCtrl.dispose();
    _debounce?.cancel();
    for (final i in _itensSelecionados) {
      i.dispose();
    }
    super.dispose();
  }

  Set<String> get _chavesSelecionadas =>
      _itensSelecionados.map((i) => i.chaveUnica).toSet();

  Future<void> _carregarCategorias() async {
    try {
      await context.read<MaterialProvider>().carregarCategorias();
      if (mounted) {
        setState(() =>
            _categorias = context.read<MaterialProvider>().categorias);
      }
    } catch (_) {}
  }

  void _agendarBusca() {
    _debounce?.cancel();
    final temValor = _idCtrl.text.isNotEmpty ||
        _nomeCtrl.text.isNotEmpty ||
        _identificadorCtrl.text.isNotEmpty ||
        _medidaCtrl.text.isNotEmpty ||
        _espessuraCtrl.text.isNotEmpty ||
        _descricaoCtrl.text.isNotEmpty;
    if (!temValor && _categoriaFiltro == null) {
      setState(() {
        _buscouUmaVez = false;
        _resultados   = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _buscar);
  }

  Future<void> _buscar() async {
    if (!mounted) return;
    setState(() {
      _buscando     = true;
      _buscouUmaVez = true;
    });
    try {
      final provider = context.read<MaterialProvider>();
      await provider.carregar(
        busca:         _nomeCtrl.text.trim(),
        id:            _idCtrl.text.trim(),
        identificador: _identificadorCtrl.text.trim(),
        medida:        _medidaCtrl.text.trim(),
        espessura:     _espessuraCtrl.text.trim(),
        categoria:     _categoriaFiltro,
        status:        '',
      );
      if (mounted) {
        final descFiltro = _descricaoCtrl.text.trim().toLowerCase();
        setState(() {
          // Quando há filtro por descrição: mostra apenas materiais específicos
          // cujos filhos batem (ou sem filhos, para permitir nova entrada/saída).
          // Quando não há: mostra tudo normalmente.
          _resultados = provider.materiais.where((m) => m.ativo).where((m) {
            if (descFiltro.isEmpty) return true;
            // Materiais não-específicos: não aparecem quando filtrando por descrição
            if (!m.especifico) return false;
            // Materiais específicos sem filhos: aparecem sempre (nova descrição)
            if (m.filhosEspecificos.isEmpty) return true;
            // Materiais específicos com filhos: aparecem se ao menos um bate
            return m.filhosEspecificos.any(
              (f) => f.descricao.toLowerCase().contains(descFiltro),
            );
          }).toList();
          _buscando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _limparFiltros() {
    _idCtrl.clear();
    _nomeCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _espessuraCtrl.clear();
    _descricaoCtrl.clear();
    _debounce?.cancel();
    setState(() {
      _categoriaFiltro = null;
      _buscouUmaVez    = false;
      _resultados      = [];
    });
  }

  void _selecionarMaterial(MaterialModel m, {String? descricaoItem}) {
    // Para filhos específicos: chave = id__descricao; para normais: id
    final chave = descricaoItem != null ? '${m.id}__$descricaoItem' : '${m.id}';
    if (_chavesSelecionadas.contains(chave)) return;
    setState(() {
      _itensSelecionados.add(
        _ItemMovimentacao(material: m, descricaoItem: descricaoItem),
      );
    });
  }

  void _removerItem(int index) {
    setState(() {
      _itensSelecionados[index].dispose();
      _itensSelecionados.removeAt(index);
    });
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_itensSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um material')),
      );
      return;
    }

    // Se há uma OS fixada (context detalhe), usa o valor real com sufixo
    String numeroOS = widget.numeroOSFixo ?? _numeroOSCtrl.text.trim();

    // Sufixo único para OS textuais — apenas quando a OS foi digitada agora
    // (numeroOSFixo == null). OS vindas de detalhe já têm o numeroOS correto
    // do banco e não devem ser modificadas, senão cria uma RelacaoOS nova.
    if (widget.numeroOSFixo == null) {
      numeroOS = numeroOS.trim();
    }

    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _enviando = true);
    bool todosOk = true;

    // Usa registrarMovimentacaoSilencioso para não recarregar a cada iteração
    for (final item in _itensSelecionados) {
      final quant = double.parse(item.quantCtrl.text.replaceAll(',', '.'));
      final obs = item.obsCtrl.text.trim().isEmpty
          ? null
          : item.obsCtrl.text.trim();

      final ok = await provider.registrarMovimentacaoSilencioso(
        materialId:    item.material.id,
        tipo:          widget.tipo,
        quantidade:    quant,
        numeroOS:      numeroOS,  // ← Agora usa o mesmo numeroOS com sufixo
        precoUnitario: item.precoUnitarioSugerido,
        precoM2:       item.precoM2Sugerido,
        observacao:    obs,
        descricaoItem: item.descricaoItem,
      );
      
      if (!ok) {
        todosOk = false;
        final erro = provider.erro ?? 'Erro desconhecido';
        if (erro.toLowerCase().contains('estoque')) {
          setState(() => item.erroEstoque = erro);
          _formKey.currentState!.validate();
        } else {
          messenger.showSnackBar(
              SnackBar(content: Text(erro), backgroundColor: AppTheme.error));
        }
        break;
      }
    }

    // Recarrega apenas uma vez ao final
    if (todosOk) {
      await provider.carregarRelacoesOS();
    }

    if (!mounted) return;
    setState(() => _enviando = false);

    if (todosOk) {
      // Remove o sufixo para exibir ao usuário (se foi adicionado)
      final numeroOSDisplay = numeroOS;      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${widget.tipo == 'ENTRADA' ? 'Entrada' : 'Saída'} '
            'registrada para OS $numeroOSDisplay'),
        backgroundColor:
            widget.tipo == 'ENTRADA' ? AppTheme.success : AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEntrada = widget.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: 1100,
        height: MediaQuery.of(context).size.height * 0.88,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho + campo OS ──────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      isEntrada
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                      color: cor,
                    ),
                    SizedBox(width: 8),
                    Text(
                      isEntrada ? 'Nova Entrada' : 'Nova Saída',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 260,
                      child: TextFormField(
                        controller: _numeroOSCtrl,
                        // Bloqueado quando a OS já está fixada (contexto de detalhe)
                        enabled: widget.numeroOSFixo == null,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Número da OS *',
                          prefixText: 'OS ',
                          isDense: true,
                          filled: widget.numeroOSFixo != null,
                          fillColor: widget.numeroOSFixo != null
                              ? AppTheme.primary.withValues(alpha: 0.07)
                              : null,
                          suffixIcon: widget.numeroOSFixo != null
                              ? const Tooltip(
                                  message: 'OS fixada por esta janela',
                                  child: Icon(Icons.lock_outline,
                                      size: 14, color: AppTheme.primary),
                                )
                              : null,
                        ),
                        validator: (v) => (widget.numeroOSFixo == null &&
                                (v == null || v.trim().isEmpty))
                            ? 'Informe o número da OS'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Layout de duas colunas ────────────────────────────
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ══════════════ COLUNA ESQUERDA: busca + resultados ══════════════
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Filtros linha 1
                            Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: _idCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'ID...',
                                      prefixIcon: Icon(Icons.tag,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _nomeCtrl,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: 'Buscar por nome...',
                                      prefixIcon: Icon(Icons.search,
                                          color: Theme.of(context).colorScheme.outline, size: 18),
                                      isDense: true,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    inputFormatters: [_UpperCaseFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: _categoriaFiltro == null
                                        ? '__TODOS__'
                                        : _categoriaFiltro!.isEmpty
                                            ? '__SEM__'
                                            : _categoriaFiltro,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Categoria',
                                      isDense: true,
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                          value: '__TODOS__',
                                          child: Text('Todas')),
                                      const DropdownMenuItem(
                                          value: '__SEM__',
                                          child: Text('Sem categoria')),
                                      ..._categorias.map((c) =>
                                          DropdownMenuItem(
                                              value: c, child: Text(c))),
                                    ],
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == '__TODOS__') {
                                          _categoriaFiltro = null;
                                        } else if (v == '__SEM__') {
                                          _categoriaFiltro = '';
                                        } else {
                                          _categoriaFiltro = v;
                                        }
                                      });
                                      if (_buscouUmaVez) _buscar();
                                    },
                                  ),
                                ),
                                SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Limpar filtros',
                                  icon: Icon(Icons.filter_alt_off,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                                  onPressed: _limparFiltros,
                                  style: IconButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(32, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Filtros linha 2
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _identificadorCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Identificador...',
                                      prefixIcon: Icon(Icons.qr_code,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    inputFormatters: [_UpperCaseFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _medidaCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Medida...',
                                      prefixIcon: Icon(Icons.straighten,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    inputFormatters: [_UpperCaseFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _espessuraCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Espessura...',
                                      prefixIcon: Icon(Icons.layers,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    inputFormatters: [_UpperCaseFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),

                            // Filtro por descrição
                            TextField(
                              controller: _descricaoCtrl,
                              decoration: InputDecoration(
                                hintText: 'Buscar por descrição do item...',
                                prefixIcon: Icon(Icons.label_outline,
                                    color: Theme.of(context).colorScheme.outline, size: 16),
                                isDense: true,
                              ),
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [_UpperCaseFormatter()],
                              onChanged: (_) => _agendarBusca(),
                              onSubmitted: (_) => _buscar(),
                            ),
                            const SizedBox(height: 10),

                            // Resultados — ocupa o espaço restante
                            Expanded(
                              child: _buscando
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                          color: AppTheme.primary,
                                          strokeWidth: 2),
                                    )
                                  : !_buscouUmaVez
                                      ? Center(
                                          child: Text(
                                            'Digite para buscar materiais',
                                            style: TextStyle(
                                                color: Theme.of(context).colorScheme.outline,
                                                fontSize: 13),
                                          ),
                                        )
                                      : _resultados.isEmpty
                                          ? Center(
                                              child: Text(
                                                'Nenhum material encontrado',
                                                style: TextStyle(
                                                    color: Theme.of(context).colorScheme.outline,
                                                    fontSize: 13),
                                              ),
                                            )
                                          : Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Theme.of(context).colorScheme.outlineVariant),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child:
                                                    Builder(builder: (context) {
                                                  final descFiltro =
                                                      _descricaoCtrl.text
                                                          .trim()
                                                          .toLowerCase();
                                                  final itens = <Widget>[];
                                                  for (int ri = 0;
                                                      ri < _resultados.length;
                                                      ri++) {
                                                    final m = _resultados[ri];
                                                    if (ri > 0) {
                                                      itens.add(const Divider(
                                                          height: 0,
                                                          thickness: 0.5,
                                                          color: AppTheme
                                                              .divider));
                                                    }
                                                    if (m.especifico) {
                                                      itens.add(
                                                          _MaterialPaiHeader(
                                                              material: m));
                                                      final filhos = descFiltro
                                                              .isEmpty
                                                          ? m.filhosEspecificos
                                                          : m.filhosEspecificos
                                                              .where((f) => f
                                                                  .descricao
                                                                  .toLowerCase()
                                                                  .contains(
                                                                      descFiltro))
                                                              .toList();
                                                      for (final filho
                                                          in filhos) {
                                                        final chave =
                                                            '${m.id}__${filho.descricao}';
                                                        final jaSelecionado =
                                                            _chavesSelecionadas
                                                                .contains(
                                                                    chave);
                                                        itens.add(
                                                            _FilhoEspecificoTile(
                                                          filho: filho,
                                                          pai: m,
                                                          selecionado:
                                                              jaSelecionado,
                                                          onTap: jaSelecionado
                                                              ? null
                                                              : () =>
                                                                  _selecionarMaterial(
                                                                      m,
                                                                      descricaoItem:
                                                                          filho.descricao),
                                                        ));
                                                      }
                                                      // Tile para digitar nova descrição:
                                                      // ENTRADA: sempre exibido (permite nova variação)
                                                      // SAÍDA: só se não houver filhos em estoque
                                                      final isEntrada = widget.tipo == 'ENTRADA';
                                                      if (isEntrada || m.filhosEspecificos.isEmpty) {
                                                        itens.add(
                                                          _NovaDescricaoTile(
                                                            material: m,
                                                            jaSelecionada: false,
                                                            isEntrada: isEntrada,
                                                            onConfirmar: (desc) {
                                                              final chave = '${m.id}__$desc';
                                                              if (!_chavesSelecionadas.contains(chave)) {
                                                                _selecionarMaterial(m, descricaoItem: desc);
                                                              }
                                                            },
                                                          ),
                                                        );
                                                      }
                                                    } else {
                                                      final jaSelecionado =
                                                          _chavesSelecionadas
                                                              .contains(
                                                                  '${m.id}');
                                                      itens.add(
                                                          _MaterialResultadoTile(
                                                        material: m,
                                                        selecionado:
                                                            jaSelecionado,
                                                        onTap: jaSelecionado
                                                            ? () {}
                                                            : () =>
                                                                _selecionarMaterial(
                                                                    m),
                                                      ));
                                                    }
                                                  }
                                                  return ListView(
                                                    children: itens,
                                                  );
                                                }),
                                              ),
                                            ),
                                        ),
                          ],
                        ),
                      ),

                      // ── Divisor vertical ──────────────────────────────
                      const VerticalDivider(width: 24, thickness: 1),

                      // ══════════════ COLUNA DIREITA: materiais selecionados ══════════════
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Cabeçalho da coluna
                            Row(
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 16, color: AppTheme.primary),
                                SizedBox(width: 6),
                                Text(
                                  'Selecionados (${_itensSelecionados.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: AppTheme.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Lista de itens selecionados
                            Expanded(
                              child: _itensSelecionados.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.inventory_2_outlined,
                                              size: 36,
                                              color: Theme.of(context).colorScheme.outline
                                                  .withValues(alpha: 0.4)),
                                          SizedBox(height: 10),
                                          Text(
                                            'Nenhum material\nadicionado ainda',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: Theme.of(context).colorScheme.outline,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _itensSelecionados.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (_, i) {
                                        final item = _itensSelecionados[i];
                                        return _ItemSelecionadoCard(
                                          key: ValueKey(item.chaveUnica),
                                          item: item,
                                          onRemover: () => _removerItem(i),
                                        );
                                      },
                                    ),
                            ),

                            // Botões de ação
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  child: const Text('Cancelar'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _enviando ? null : _confirmar,
                                  style: FilledButton.styleFrom(
                                      backgroundColor: cor),
                                  child: _enviando
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : Text(isEntrada
                                          ? 'Confirmar Entrada'
                                          : 'Confirmar Saída'),
                                ),
                              ],
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
        ),
      ),
    );
  }
}

// ─── Modelo de item de movimentação ──────────────────────────────────────────

class _ItemMovimentacao {
  final MaterialModel material;
  /// Para materiais específicos: a descrição do filho selecionado (ex: "Tinta Branca 18L").
  /// Para materiais normais: null.
  final String? descricaoItem;
  final TextEditingController quantCtrl        = TextEditingController();
  final TextEditingController obsCtrl          = TextEditingController();
  final TextEditingController larguraUsadaCtrl = TextEditingController();
  final TextEditingController alturaUsadaCtrl  = TextEditingController();
  bool usarModoDimensional = false;
  String? erroEstoque;

  /// Preço unitário sugerido: vem do filho específico selecionado (ultimoValorPago)
  /// ou, para materiais normais, do ultimoValorPago do material pai.
  double? get precoUnitarioSugerido {
    if (descricaoItem != null) {
      final filho = material.filhosEspecificos
          .where((f) => f.descricao == descricaoItem)
          .firstOrNull;
      return filho?.ultimoValorPago ?? material.ultimoValorPago;
    }
    return material.ultimoValorPago;
  }

  /// Preço m² sugerido: mesma lógica acima mas para m².
  double? get precoM2Sugerido {
    if (descricaoItem != null) {
      final filho = material.filhosEspecificos
          .where((f) => f.descricao == descricaoItem)
          .firstOrNull;
      return filho?.ultimoValorPagoM2 ?? material.ultimoValorPagoM2;
    }
    return material.ultimoValorPagoM2;
  }

  _ItemMovimentacao({required this.material, this.descricaoItem});

  /// Chave única que distingue o mesmo material pai com descrições diferentes.
  String get chaveUnica =>
      descricaoItem != null ? '${material.id}__$descricaoItem' : '${material.id}';

  void dispose() {
    quantCtrl.dispose();
    obsCtrl.dispose();
    larguraUsadaCtrl.dispose();
    alturaUsadaCtrl.dispose();
  }
}

// ─── Card de item selecionado ─────────────────────────────────────────────────

class _ItemSelecionadoCard extends StatefulWidget {
  final _ItemMovimentacao item;
  final VoidCallback onRemover;

  const _ItemSelecionadoCard({
    super.key,
    required this.item,
    required this.onRemover,
  });

  @override
  State<_ItemSelecionadoCard> createState() => _ItemSelecionadoCardState();
}

class _ItemSelecionadoCardState extends State<_ItemSelecionadoCard> {
  _ItemMovimentacao get item => widget.item;

  // ── Detecta medida no formato "LxA" ou "LxAM" (ex: "2X1", "1.20X0.80M") ──
  bool get _temMedidaDimensional {
    final medida = item.material.medida;
    if (medida == null || medida.isEmpty) return false;
    // Aceita sufixo opcional "M" no final (ex: 1.20X0.80M, 2X1M)
    return RegExp(r'^\d+([.,]\d+)?\s*[xX]\s*\d+([.,]\d+)?\s*M?$', caseSensitive: false)
        .hasMatch(medida.trim());
  }

  /// Parseia "2X1" ou "1.20X0.80M" → (largura: 2.0, comprimento: 1.0).
  /// Retorna null se inválido.
  (double l, double a)? get _medidaChapa {
    final medida = item.material.medida;
    if (medida == null) return null;
    // Remove sufixo "M" antes de parsear
    final semSufixo = medida.trim().replaceFirst(RegExp(r'M\s*$', caseSensitive: false), '').trim();
    final partes = semSufixo.split(RegExp(r'\s*[xX]\s*'));
    if (partes.length < 2) return null;
    final l = double.tryParse(partes[0].replaceAll(',', '.'));
    final a = double.tryParse(partes[1].replaceAll(',', '.'));
    if (l == null || l <= 0 || a == null || a <= 0) return null;
    return (l, a);
  }

  void _recalcularQtd() {
    final chapa = _medidaChapa;
    if (chapa == null) return;
    final largStr = item.larguraUsadaCtrl.text.replaceAll(',', '.');
    final altStr  = item.alturaUsadaCtrl.text.replaceAll(',', '.');
    final larg = double.tryParse(largStr);
    final alt  = double.tryParse(altStr);
    if (larg == null || alt == null || larg <= 0 || alt <= 0) {
      setState(() {}); // ainda atualiza o preview
      return;
    }
    // Arredonda para 4 casas antes de formatar para evitar ruído de ponto flutuante
    // (ex: 0.6 * 0.4 pode virar 0.23999... ou 0.24000...2 em double)
    final fracaoBruta = (larg * alt) / (chapa.$1 * chapa.$2);
    final fracao = double.parse(fracaoBruta.toStringAsFixed(4));
    final qtdStr = fracao.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '');
    item.quantCtrl.text =
        qtdStr.endsWith('.') ? '${qtdStr}0' : qtdStr;
    setState(() {});
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final m = item.material;
    final partes = <String>[
      if (m.medida    != null && m.medida!.isNotEmpty)    m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
      if (m.categoria != null && m.categoria!.isNotEmpty) m.categoria!,
    ].join(' · ');

    final chapa        = _medidaChapa;
    final podeDimensao = _temMedidaDimensional && chapa != null;

    // ── Preview do cálculo dimensional ───────────────────────────────────────
    Widget? previewDimensional;
    if (item.usarModoDimensional && podeDimensao) {
      final largStr = item.larguraUsadaCtrl.text.replaceAll(',', '.');
      final altStr  = item.alturaUsadaCtrl.text.replaceAll(',', '.');
      final larg    = double.tryParse(largStr);
      final alt     = double.tryParse(altStr);

      if (larg != null && larg > 0 && alt != null && alt > 0) {
        final areaUsada = larg * alt;
        final areaTotal = chapa.$1 * chapa.$2;
        final fracao    = areaUsada / areaTotal;
        final pct       = (fracao * 100).toStringAsFixed(1);

        previewDimensional = Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Icon(Icons.calculate_outlined,
                  size: 14, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    children: [
                      TextSpan(
                          text: '${_fmt(larg)} × ${_fmt(alt)} m  =  '),
                      TextSpan(
                        text: '${_fmt(areaUsada)} m²',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const TextSpan(text: '  →  '),
                      TextSpan(
                        text: item.quantCtrl.text,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary),
                      ),
                      TextSpan(
                        text: ' ${m.unidade ?? 'UN'}  ($pct% da chapa)',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho: nome + botão remover ──────────────────────────────
          Row(
            children: [
              const Icon(Icons.check_circle,
                  size: 15, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.nome,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.descricaoItem != null)
                      Text(
                        item.descricaoItem!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (partes.isNotEmpty)
                      Text(
                        partes,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onRemover,
                icon: Icon(Icons.close,
                    size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(28, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                tooltip: 'Remover',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Toggle modo dimensional (só chapas com medida LxA) ───────────
          if (podeDimensao) ...[
            InkWell(
              onTap: () => setState(
                  () => item.usarModoDimensional = !item.usarModoDimensional),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.usarModoDimensional
                          ? Icons.toggle_on
                          : Icons.toggle_off_outlined,
                      size: 20,
                      color: item.usarModoDimensional
                          ? AppTheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Informar por dimensão usada',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: item.usarModoDimensional
                            ? AppTheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Chapa ${_fmt(chapa.$1)}×${_fmt(chapa.$2)} m',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Campos de dimensão (quando modo ativo) ────────────────────────
          if (item.usarModoDimensional && podeDimensao) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item.larguraUsadaCtrl,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Largura usada (m)',
                      isDense: true,
                      suffixText: '/ ${_fmt(chapa.$1)} m',
                      suffixStyle: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.outline),
                    ),
                    onChanged: (_) => _recalcularQtd(),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×',
                      style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: TextField(
                    controller: item.alturaUsadaCtrl,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Comprimento usado (m)',
                      isDense: true,
                      suffixText: '/ ${_fmt(chapa.$2)} m',
                      suffixStyle: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.outline),
                    ),
                    onChanged: (_) => _recalcularQtd(),
                  ),
                ),
              ],
            ),
            if (previewDimensional != null) previewDimensional,
            const SizedBox(height: 10),
          ],

          // ── Campos de quantidade e observação ─────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextFormField(
                  controller: item.quantCtrl,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Quantidade *',
                    isDense: true,
                    suffixText: m.unidade,
                    helperText: item.usarModoDimensional
                        ? 'Calculado automaticamente'
                        : null,
                    helperStyle: TextStyle(
                        fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  readOnly: item.usarModoDimensional,
                  validator: (v) {
                    if (item.erroEstoque != null) return item.erroEstoque;
                    final quant =
                        double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (quant == null || quant <= 0) return 'Qtd. inválida';
                    return null;
                  },
                  onChanged: (_) {
                    if (item.erroEstoque != null) item.erroEstoque = null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: item.obsCtrl,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                    isDense: true,
                    prefixIcon: Icon(Icons.notes, size: 16),
                  ),
                ),
              ),
            ],
          ),

          // ── Preço sugerido ────────────────────────────────────────────────
          Builder(builder: (_) {
            final pu  = item.precoUnitarioSugerido;
            final pm2 = item.precoM2Sugerido;
            if (pu == null && pm2 == null) return const SizedBox.shrink();

            final qtdPadrao  = m.qtdPadrao;
            final unidPadrao = m.unidPadrao;
            final temQtdPad  = qtdPadrao != null && qtdPadrao > 0 && unidPadrao != null && unidPadrao.isNotEmpty;

            // Formata número: sem zeros à direita desnecessários até 6 casas
            String fmtPreco(double v) {
              if (v >= 1) return v.toStringAsFixed(2).replaceAll('.', ',');
              // Custo por unidade menor: pode ter muitas casas (ex: 0.014722...)
              // Mostra até 6 casas significativas sem zeros no final
              String s = v.toStringAsFixed(6).replaceAll('.', ',');
              while (s.endsWith('0')) {
                s = s.substring(0, s.length - 1);
              }
              if (s.endsWith(',')) s = '${s}0';
              return s;
            }

            final partesBrl = <String>[];

            if (pu != null && pu > 0) {
              if (temQtdPad) {
                // Custo por unidade menor (ex: R$ 0,0147/ml)
                partesBrl.add('Custo: R\$ ${fmtPreco(pu)}/${unidPadrao.toLowerCase()}');
                // Custo reconstituído por embalagem (informativo)
                final porEmbalagem = pu * qtdPadrao;
                partesBrl.add('≈ R\$ ${fmtPreco(porEmbalagem)}/embalagem');
              } else {
                partesBrl.add('Unit.: R\$ ${pu.toStringAsFixed(2).replaceAll('.', ',')}');
              }
            }
            if (pm2 != null && pm2 > 0) {
              partesBrl.add('M²: R\$ ${pm2.toStringAsFixed(2).replaceAll('.', ',')}');
            }
            if (partesBrl.isEmpty) return SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.price_check,
                      size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      partesBrl.join('  ·  '),
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Cabeçalho de material pai específico (não selecionável) ─────────────────

class _MaterialPaiHeader extends StatelessWidget {
  final MaterialModel material;
  const _MaterialPaiHeader({required this.material});

  @override
  Widget build(BuildContext context) {
    final partes = <String>[
      if (material.identificador != null && material.identificador!.isNotEmpty)
        '${material.identificador}',
      if (material.medida != null && material.medida!.isNotEmpty)
        material.medida!,
      if (material.espessura != null && material.espessura!.isNotEmpty)
        material.espessura!,
      if (material.categoria != null && material.categoria!.isNotEmpty)
        material.categoria!,
    ].join(' · ');

    return Container(
      color: AppTheme.primary.withValues(alpha: 0.05),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.folder_special_outlined,
              size: 14, color: AppTheme.primary),
          SizedBox(width: 6),
          SizedBox(
            width: 36,
            child: Text(
              '#${material.id}',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.nome,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (partes.isNotEmpty)
                  Text(
                    partes,
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const Text(
            'específico',
            style: TextStyle(
                fontSize: 10,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

// ─── Tile "informar nova descrição" para material específico ──────────────────
// Exibido abaixo do _MaterialPaiHeader para permitir registrar entrada/saída
// de uma descrição que ainda não existe no estoque (ou para adicionar nova).

class _NovaDescricaoTile extends StatefulWidget {
  final MaterialModel material;
  final bool jaSelecionada;
  final void Function(String descricao) onConfirmar;
  /// Se true, o tile mostra texto de "Nova descrição" (ENTRADA).
  /// Se false, mostra "Descrição não listada" (SAIDA manual).
  final bool isEntrada;

  const _NovaDescricaoTile({
    required this.material,
    required this.jaSelecionada,
    required this.onConfirmar,
    required this.isEntrada,
  });

  @override
  State<_NovaDescricaoTile> createState() => _NovaDescricaoTileState();
}

class _NovaDescricaoTileState extends State<_NovaDescricaoTile> {
  bool _expandido = false;
  final _ctrl = TextEditingController();
  bool _hovered = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final desc = _ctrl.text.trim();
    if (desc.isEmpty) return;
    widget.onConfirmar(desc);
    setState(() {
      _expandido = false;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jaSelecionada && !_expandido) {
      return const SizedBox.shrink();
    }

    if (!_expandido) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => setState(() => _expandido = true),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _hovered
                ? AppTheme.primary.withValues(alpha: 0.05)
                : Colors.transparent,
            padding: const EdgeInsets.only(left: 32, right: 10, top: 7, bottom: 7),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.add_circle_outline, size: 14, color: AppTheme.primary),
                ),
                Expanded(
                  child: Text(
                    widget.isEntrada
                        ? 'Informar nova descrição...'
                        : 'Informar descrição manualmente...',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Expandido: campo de texto inline
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.04),
      padding: const EdgeInsets.only(left: 32, right: 10, top: 8, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ex.: Tinta Branca Fosca 18L',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onSubmitted: (_) => _confirmar(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _confirmar,
            icon: const Icon(Icons.check, size: 16, color: AppTheme.success),
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: 'Confirmar descrição',
          ),
          IconButton(
            onPressed: () => setState(() {
              _expandido = false;
              _ctrl.clear();
            }),
            icon: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: 'Cancelar',
          ),
        ],
      ),
    );
  }
}

// ─── Tile de filho específico (selecionável) ──────────────────────────────────

class _FilhoEspecificoTile extends StatefulWidget {
  final EstoqueEspecificoModel filho;
  final MaterialModel pai;
  final bool selecionado;
  final VoidCallback? onTap;

  const _FilhoEspecificoTile({
    required this.filho,
    required this.pai,
    required this.selecionado,
    required this.onTap,
  });

  @override
  State<_FilhoEspecificoTile> createState() => _FilhoEspecificoTileState();
}

class _FilhoEspecificoTileState extends State<_FilhoEspecificoTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selecionado;
    final desativado = widget.onTap == null;
    final bg = sel
        ? AppTheme.primary.withValues(alpha: 0.10)
        : _hovered && !desativado
            ? AppTheme.primary.withValues(alpha: 0.05)
            : Colors.transparent;

    final qtd = widget.filho.quantidade;
    final qtdStr = qtd == qtd.truncate()
        ? qtd.toStringAsFixed(0)
        : qtd.toStringAsFixed(2);

    return MouseRegion(
      cursor:
          desativado ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: bg,
          padding: const EdgeInsets.only(
              left: 32, right: 10, top: 7, bottom: 7),
          child: Row(
            children: [
              if (sel)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_circle,
                      size: 15, color: AppTheme.primary),
                )
              else
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.subdirectory_arrow_right,
                      size: 14, color: Theme.of(context).colorScheme.outline),
                ),
              Expanded(
                child: Text(
                  widget.filho.descricao,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? AppTheme.primary : Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    qtdStr,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                  if (widget.pai.unidade != null)
                    Text(
                      widget.pai.unidade!,
                      style: TextStyle(
                          fontSize: 10, color: Theme.of(context).colorScheme.outline),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              _StatusBadgeMini(
                status: qtd > (widget.pai.estoqueMinimo)
                    ? 'OK'
                    : qtd == widget.pai.estoqueMinimo
                        ? 'LIMITE'
                        : 'CRITICO',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tile de resultado de busca ───────────────────────────────────────────────

class _MaterialResultadoTile extends StatefulWidget {
  final MaterialModel material;
  final bool selecionado;
  final VoidCallback onTap;

  const _MaterialResultadoTile({
    required this.material,
    required this.selecionado,
    required this.onTap,
  });

  @override
  State<_MaterialResultadoTile> createState() =>
      _MaterialResultadoTileState();
}

class _MaterialResultadoTileState extends State<_MaterialResultadoTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m   = widget.material;
    final sel = widget.selecionado;
    final bg  = sel
        ? AppTheme.primary.withValues(alpha: 0.10)
        : _hovered
            ? AppTheme.primary.withValues(alpha: 0.05)
            : Colors.transparent;

    final partes = <String>[
      if (m.identificador != null && m.identificador!.isNotEmpty)
        '${m.identificador}',
      if (m.medida != null && m.medida!.isNotEmpty) m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
      if (m.categoria != null && m.categoria!.isNotEmpty) m.categoria!,
    ].join(' · ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: bg,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (sel)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_circle,
                      size: 15, color: AppTheme.primary),
                )
              else
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle_outlined,
                      size: 15, color: Theme.of(context).colorScheme.outline),
                ),
              SizedBox(
                width: 36,
                child: Text(
                  '#${m.id}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.nome,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            sel ? FontWeight.w700 : FontWeight.w500,
                        color:
                            sel ? AppTheme.primary : Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (partes.isNotEmpty)
                      Text(
                        partes,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    m.quantidade.toStringAsFixed(
                        m.quantidade % 1 == 0 ? 0 : 2),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                  if (m.unidade != null)
                    Text(
                      m.unidade!,
                      style: TextStyle(
                          fontSize: 10, color: Theme.of(context).colorScheme.outline),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              _StatusBadgeMini(status: m.status),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Badge de status mini (material) ─────────────────────────────────────────

class _StatusBadgeMini extends StatelessWidget {
  final String status;
  _StatusBadgeMini({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'OK'      => ('OK',      AppTheme.statusOk),
      'LIMITE'  => ('LIMITE',  AppTheme.statusBaixo),
      'CRITICO' => ('CRITICO', AppTheme.statusCritico),
      'INATIVO' => ('INATIVO', Theme.of(context).colorScheme.outline),
      _         => ('—',       Theme.of(context).colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}