import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/estoque_model.dart';
import '../providers/estoque_provider.dart';
import '../theme/app_theme.dart';

// ── Formatação de data/hora ────────────────────────────────────────────────

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

String _fmtHora(DateTime? dt) {
  if (dt == null) return '';
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

String _fmtDataCompleta(DateTime dt) {
  final hoje = DateTime.now();
  final hojeData = DateTime(hoje.year, hoje.month, hoje.day);
  final dtData = DateTime(dt.year, dt.month, dt.day);
  if (dtData == hojeData) return 'Hoje';
  if (dtData == hojeData.subtract(const Duration(days: 1))) return 'Ontem';
  const dias = ['', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
  return '${_fmtData(dt)} • ${dias[dt.weekday]}';
}

// ── Extrai "quem fez" e observação extra do campo observacao ──────────────
// O backend grava automaticamente: "Entrada/Saída via controle de estoque – {nome}"
// seguido opcionalmente de uma quebra de linha com a observação digitada pelo usuário.

String? _extrairUsuario(String? obs) {
  if (obs == null || obs.isEmpty) return null;
  final primeiraLinha = obs.split('\n').first;
  final idx = primeiraLinha.indexOf('–');
  if (idx == -1) return null;
  final nome = primeiraLinha.substring(idx + 1).trim();
  return nome.isEmpty ? null : nome;
}

String? _extrairObsExtra(String? obs) {
  if (obs == null || obs.isEmpty) return null;
  final linhas = obs.split('\n');
  if (linhas.length <= 1) return null;
  final extra = linhas.sublist(1).join('\n').trim();
  return extra.isEmpty ? null : extra;
}

// ── Formatter: maiúsculas sem acentos (mesmo padrão das outras telas) ─────

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

// ── Origem da movimentação ─────────────────────────────────────────────────
// Detectada pelo prefixo gravado automaticamente no campo observacao:
//   "Entrada/Saída via controle de estoque – {nome}"  → estoque
//   "Saída via produção – {nome}"                     → producao
//   "Entrada via OC #{id} – {nome}"                   → ordemCompra

enum _OrigemMov { estoque, producao, ordemCompra, desconhecida }

_OrigemMov _detectarOrigem(String? obs) {
  if (obs == null || obs.isEmpty) return _OrigemMov.desconhecida;
  final linha = obs.split('\n').first.toLowerCase();
  if (linha.contains('via controle de estoque')) return _OrigemMov.estoque;
  if (linha.contains('via producao') || linha.contains('via produção')) return _OrigemMov.producao;
  if (linha.contains('via oc')) return _OrigemMov.ordemCompra;
  return _OrigemMov.desconhecida;
}

({String label, IconData icon, Color cor}) _origemInfo(
    _OrigemMov origem, BuildContext context) {
  switch (origem) {
    case _OrigemMov.estoque:
      return (label: 'Estoque', icon: Icons.inventory_2_outlined, cor: const Color(0xFF2196F3));
    case _OrigemMov.producao:
      return (label: 'Produção', icon: Icons.precision_manufacturing_outlined, cor: const Color(0xFFFF9800));
    case _OrigemMov.ordemCompra:
      return (label: 'Ordem de Compra', icon: Icons.receipt_long_outlined, cor: const Color(0xFF4CAF50));
    case _OrigemMov.desconhecida:
      return (label: '—', icon: Icons.help_outline, cor: Theme.of(context).colorScheme.outline);
  }
}

// ── Filtro por tipo de movimentação ────────────────────────────────────────

enum _FiltroTipo { todos, entrada, saida }

// ── Item flatten: uma movimentação + a OS a que ela pertence ──────────────

class _ItemHistorico {
  final RelacaoOSModel relacao;
  final MovimentacaoModel mov;
  _ItemHistorico(this.relacao, this.mov);
}

const _corEmAndamento = Color(0xFF2196F3); // ignore: unused_element
const _corFechada     = Color(0xFF4CAF50); // ignore: unused_element

// ═════════════════════════════════════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class HistoricoMovimentacoesPage extends StatefulWidget {
  const HistoricoMovimentacoesPage({super.key});

  @override
  State<HistoricoMovimentacoesPage> createState() =>
      _HistoricoMovimentacoesPageState();
}

class _HistoricoMovimentacoesPageState
    extends State<HistoricoMovimentacoesPage> {
  final TextEditingController _buscaOSCtrl       = TextEditingController();
  final TextEditingController _buscaMaterialCtrl  = TextEditingController();
  final TextEditingController _buscaUsuarioCtrl   = TextEditingController();
  Timer? _debounceTimer;

  _FiltroTipo _filtroTipo   = _FiltroTipo.todos;
  _OrigemMov? _filtroOrigem; // null = todas as origens
  DateTime? _dataInicio;
  DateTime? _dataFim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstoqueProvider>().carregarRelacoesOS();
    });
  }

  @override
  void dispose() {
    _buscaOSCtrl.dispose();
    _buscaMaterialCtrl.dispose();
    _buscaUsuarioCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onFiltroDigitado(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  void _limparFiltros() {
    _buscaOSCtrl.clear();
    _buscaMaterialCtrl.clear();
    _buscaUsuarioCtrl.clear();
    setState(() {
      _filtroTipo   = _FiltroTipo.todos;
      _filtroOrigem = null;
      _dataInicio   = null;
      _dataFim      = null;
    });
  }

  List<_ItemHistorico> _itensFiltrados(List<RelacaoOSModel> relacoes) {
    final os       = _buscaOSCtrl.text.trim().toUpperCase();
    final material = _buscaMaterialCtrl.text.trim().toLowerCase();
    final usuario  = _buscaUsuarioCtrl.text.trim().toLowerCase();

    final itens = <_ItemHistorico>[];
    for (final r in relacoes) {
      for (final m in r.movimentacoes) {
        if (_filtroTipo == _FiltroTipo.entrada && m.tipo != 'ENTRADA') continue;
        if (_filtroTipo == _FiltroTipo.saida && m.tipo != 'SAIDA') continue;
        if (_filtroOrigem != null && _detectarOrigem(m.observacao) != _filtroOrigem) continue;
        if (os.isNotEmpty && !r.numeroOS.toUpperCase().contains(os)) continue;
        if (material.isNotEmpty &&
            !m.materialNome.toLowerCase().contains(material)) {
          continue;
        }
        if (usuario.isNotEmpty) {
          final nomeUsuario = (_extrairUsuario(m.observacao) ?? '').toLowerCase();
          if (!nomeUsuario.contains(usuario)) continue;
        }
        if (_dataInicio != null && m.criadoEm.isBefore(_dataInicio!)) continue;
        if (_dataFim != null) {
          final fimDoDia = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day, 23, 59, 59);
          if (m.criadoEm.isAfter(fimDoDia)) continue;
        }
        itens.add(_ItemHistorico(r, m));
      }
    }
    itens.sort((a, b) => b.mov.criadoEm.compareTo(a.mov.criadoEm));
    return itens;
  }

  Map<String, List<_ItemHistorico>> _agruparPorDia(List<_ItemHistorico> itens) {
    final grupos = <String, List<_ItemHistorico>>{};
    for (final item in itens) {
      final chave = _fmtData(item.mov.criadoEm);
      grupos.putIfAbsent(chave, () => []).add(item);
    }
    return grupos;
  }

  Future<void> _selecionarData({required bool inicio}) async {
    final agora = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (inicio ? _dataInicio : _dataFim) ?? agora,
      firstDate: DateTime(2020),
      lastDate: agora,
    );
    if (picked != null) {
      setState(() {
        if (inicio) {
          _dataInicio = picked;
        } else {
          _dataFim = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();
    final itens = _itensFiltrados(provider.relacoesOS);
    final grupos = _agruparPorDia(itens);
    final chavesOrdenadas = grupos.keys.toList(); // já vem em ordem desc pois itens estão ordenados

    final totalEntradas = itens.where((i) => i.mov.tipo == 'ENTRADA').length;
    final totalSaidas    = itens.where((i) => i.mov.tipo == 'SAIDA').length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ──────────────────────────────────────────────────
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Voltar',
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Histórico de Movimentações',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Todas as entradas e saídas do estoque, em ordem cronológica',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () =>
                      context.read<EstoqueProvider>().carregarRelacoesOS(),
                  icon: Icon(Icons.refresh,
                      size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

            // ── Filtros de texto ──────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscaOSCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Buscar por número da OS...',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _buscaMaterialCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Filtrar por material...',
                      prefixIcon: Icon(Icons.inventory_2_outlined,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _buscaUsuarioCtrl,
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Filtrar por quem fez...',
                      prefixIcon: Icon(Icons.person_outline,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onPressed: _limparFiltros,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Tipo + período + contadores ───────────────────────────────
            Row(
              children: [
                SegmentedButton<_FiltroTipo>(
                  segments: const [
                    ButtonSegment(value: _FiltroTipo.todos, label: Text('Todos')),
                    ButtonSegment(value: _FiltroTipo.entrada, label: Text('Entradas')),
                    ButtonSegment(value: _FiltroTipo.saida, label: Text('Saídas')),
                  ],
                  selected: {_filtroTipo},
                  onSelectionChanged: (s) => setState(() => _filtroTipo = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _selecionarData(inicio: true),
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(_dataInicio == null ? 'De' : _fmtData(_dataInicio)),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () => _selecionarData(inicio: false),
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(_dataFim == null ? 'Até' : _fmtData(_dataFim)),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                if (_dataInicio != null || _dataFim != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Limpar período',
                    onPressed: () => setState(() {
                      _dataInicio = null;
                      _dataFim = null;
                    }),
                  ),
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.arrow_upward, size: 14, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text('$totalEntradas entradas',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 14),
                    Icon(Icons.arrow_downward, size: 14, color: AppTheme.error),
                    const SizedBox(width: 4),
                    Text('$totalSaidas saídas',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Filtro de origem ──────────────────────────────────────────
            Row(
              children: [
                Text('Origem:',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                ...(<(_OrigemMov?, String, IconData)>[
                  (null,                   'Todas',           Icons.all_inclusive_outlined),
                  (_OrigemMov.estoque,      'Estoque',         Icons.inventory_2_outlined),
                  (_OrigemMov.producao,     'Produção',        Icons.precision_manufacturing_outlined),
                  (_OrigemMov.ordemCompra,  'Ordem de Compra', Icons.receipt_long_outlined),
                ].map((entry) {
                  final _OrigemMov? origem = entry.$1;
                  final String label       = entry.$2;
                  final IconData icon      = entry.$3;
                  final selecionado = _filtroOrigem == origem;
                  final cor = origem == null
                      ? Theme.of(context).colorScheme.primary
                      : _origemInfo(origem, context).cor;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 13,
                              color: selecionado
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: selecionado
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface)),
                        ],
                      ),
                      selected: selecionado,
                      onSelected: (_) => setState(() => _filtroOrigem = origem),
                      selectedColor: cor,
                      checkmarkColor: Colors.white,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    ),
                  );
                })),
              ],
            ),
            const SizedBox(height: 16),

            // ── Lista ──────────────────────────────────────────────────────
            Expanded(
              child: provider.carregando
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : provider.erro != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
                              const SizedBox(height: 12),
                              Text(provider.erro!,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => context.read<EstoqueProvider>().carregarRelacoesOS(),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Tentar novamente'),
                                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                              ),
                            ],
                          ),
                        )
                      : itens.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history,
                                      size: 48, color: Theme.of(context).colorScheme.outline),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nenhuma movimentação encontrada',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: chavesOrdenadas.length,
                              itemBuilder: (context, i) {
                                final chave = chavesOrdenadas[i];
                                final itensDoDia = grupos[chave]!;
                                final dataRef = itensDoDia.first.mov.criadoEm;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.only(top: i == 0 ? 0 : 18, bottom: 8),
                                      child: Text(
                                        _fmtDataCompleta(dataRef),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(context).colorScheme.outline,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                    ...itensDoDia.map((item) => _LinhaHistorico(
                                          item: item,
                                          onTapOS: () => _abrirOS(item.relacao),
                                        )),
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

  void _abrirOS(RelacaoOSModel relacao) {
    Navigator.of(context).pop(relacao.numeroOS);
  }
}

// ── Linha de movimentação ───────────────────────────────────────────────────

class _LinhaHistorico extends StatelessWidget {
  final _ItemHistorico item;
  final VoidCallback onTapOS;
  const _LinhaHistorico({required this.item, required this.onTapOS});

  @override
  Widget build(BuildContext context) {
    final mov = item.mov;
    final relacao = item.relacao;
    final isEntrada = mov.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;
    final icon = isEntrada ? Icons.arrow_upward : Icons.arrow_downward;
    final usuario = _extrairUsuario(mov.observacao);
    final obsExtra = _extrairObsExtra(mov.observacao);
    final origem = _detectarOrigem(mov.observacao);
    final origemInfo = _origemInfo(origem, context);

    final qtdStr = mov.quantidade == mov.quantidade.truncate()
        ? mov.quantidade.toStringAsFixed(0)
        : mov.quantidade.toStringAsFixed(2);
    final detalhesMaterial = [
      if (mov.materialIdentificador != null && mov.materialIdentificador!.isNotEmpty) mov.materialIdentificador!,
      if (mov.materialMedida != null && mov.materialMedida!.isNotEmpty) mov.materialMedida!,
      if (mov.materialEspessura != null && mov.materialEspessura!.isNotEmpty) mov.materialEspessura!,
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Ícone entrada/saída (32px fixo) ─────────────────────────────
          SizedBox(
            width: 32,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: cor),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // ── Material (máx 160px) ─────────────────────────────────────────
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mov.materialNome,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                if (detalhesMaterial.isNotEmpty)
                  Text(
                    detalhesMaterial,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (obsExtra != null)
                  Text(
                    obsExtra,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const Spacer(),

          // ── Quantidade (100px fixo) ──────────────────────────────────────
          SizedBox(
            width: 100,
            child: Text(
              '${isEntrada ? '+' : '-'}$qtdStr${mov.materialUnidade != null ? ' ${mov.materialUnidade}' : ''}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cor),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── OS (160px fixo) ──────────────────────────────────────────────
          SizedBox(
            width: 160,
            child: GestureDetector(
              onTap: onTapOS,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 13,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      relacao.numeroOS,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.primary.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Usuário (130px fixo) ─────────────────────────────────────────
          SizedBox(
            width: 130,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, size: 13,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    usuario ?? '—',
                    style: TextStyle(fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Badge de origem (140px fixo) ─────────────────────────────────
          SizedBox(
            width: 140,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: origemInfo.cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: origemInfo.cor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(origemInfo.icon, size: 11, color: origemInfo.cor),
                    const SizedBox(width: 4),
                    Text(
                      origemInfo.label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: origemInfo.cor),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Hora (50px fixo) ─────────────────────────────────────────────
          SizedBox(
            width: 50,
            child: Text(
              _fmtHora(mov.criadoEm),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12,
                  color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}