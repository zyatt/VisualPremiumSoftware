import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/estoque_model.dart';
import '../models/material_model.dart';
import '../providers/estoque_provider.dart';
import '../providers/material_provider.dart';
import '../theme/app_theme.dart';

// ── Formatação ────────────────────────────────

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

String _brl6(double v) {
  final s6 = v.toStringAsFixed(6);
  final trimmed = s6.replaceAll(RegExp(r'0+$'), '');
  final partes = trimmed.split('.');
  final dec = partes.length > 1 ? partes[1] : '';
  final decFinal = dec.length < 2 ? dec.padRight(2, '0') : dec;
  return 'R\$ ${partes[0].replaceAll('.', ',')},$decFinal';
}

// ── Formatter ─────────────────────────────────

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
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _DecimalInputFormatter extends TextInputFormatter {
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

// ── Ordenação ─────────────────────────────────

enum _OrdenacaoOS { recente, criacao, numero }

extension on _OrdenacaoOS {
  String get label => switch (this) {
        _OrdenacaoOS.recente => 'Última alteração',
        _OrdenacaoOS.criacao => 'Data de criação',
        _OrdenacaoOS.numero => 'Número da OS',
      };

  IconData get icon => switch (this) {
        _OrdenacaoOS.recente => Icons.update,
        _OrdenacaoOS.criacao => Icons.event,
        _OrdenacaoOS.numero => Icons.tag,
      };
}

// ── Cores do status ───────────────────────────────────────────────────────────

const _corEmAndamento = Color(0xFF2196F3);
const _corFechada = Color(0xFF4CAF50);

Color _corStatus(String status) =>
    status == 'FECHADA' ? _corFechada : _corEmAndamento;

String _labelStatus(String status) =>
    status == 'FECHADA' ? 'Fechada' : 'Em andamento';

String _normalizarTextoComparacao(String? v) {
  if (v == null) return '';
  final upper = _UpperCaseFormatter._removerAcentos(v.trim().toUpperCase());
  return upper.replaceAll(RegExp(r'\s+'), ' ');
}

// ═════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class ProducaoRetalhoPage extends StatefulWidget {
  const ProducaoRetalhoPage({super.key});

  @override
  State<ProducaoRetalhoPage> createState() => _ProducaoRetalhoPageState();
}

class _ProducaoRetalhoPageState extends State<ProducaoRetalhoPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _buscaCtrl = TextEditingController();
  final TextEditingController _buscaNomeCtrl = TextEditingController();
  final TextEditingController _identificadorCtrl = TextEditingController();
  final TextEditingController _medidaCtrl = TextEditingController();
  final TextEditingController _espessuraCtrl = TextEditingController();
  late TabController _tabController;
  Timer? _debounceTimer;

  _OrdenacaoOS _ordenacao = _OrdenacaoOS.recente;
  bool _decrescente = true;
  DateTime? _dataInicio;
  DateTime? _dataFim;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<EstoqueProvider>().carregarRelacoesOS();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    _buscaCtrl.dispose();
    _buscaNomeCtrl.dispose();
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

  bool get _temFiltroData => _dataInicio != null || _dataFim != null;

  List<RelacaoOSModel> _filtrarPorData(List<RelacaoOSModel> lista) {
    if (!_temFiltroData) return lista;
    return lista.where((r) {
      final criacao = r.criadoEm;
      if (criacao == null) return false;
      final dia = DateTime(criacao.year, criacao.month, criacao.day);
      if (_dataInicio != null) {
        final ini = DateTime(
            _dataInicio!.year, _dataInicio!.month, _dataInicio!.day);
        if (dia.isBefore(ini)) return false;
      }
      if (_dataFim != null) {
        final fim = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day);
        if (dia.isAfter(fim)) return false;
      }
      return true;
    }).toList();
  }

  List<RelacaoOSModel> _ordenarRelacoes(List<RelacaoOSModel> lista) {
    final ordenada = [...lista];
    int cmp(RelacaoOSModel a, RelacaoOSModel b) {
      switch (_ordenacao) {
        case _OrdenacaoOS.recente:
          final da = a.atualizadoEm ?? a.criadoEm ?? DateTime(1970);
          final db = b.atualizadoEm ?? b.criadoEm ?? DateTime(1970);
          return da.compareTo(db);
        case _OrdenacaoOS.criacao:
          final da = a.criadoEm ?? DateTime(1970);
          final db = b.criadoEm ?? DateTime(1970);
          return da.compareTo(db);
        case _OrdenacaoOS.numero:
          final na = int.tryParse(a.numeroOS.trim());
          final nb = int.tryParse(b.numeroOS.trim());
          if (na != null && nb != null) return na.compareTo(nb);
          if (na != null) return -1;
          if (nb != null) return 1;
          return a.numeroOS.toLowerCase().compareTo(b.numeroOS.toLowerCase());
      }
    }

    ordenada.sort(_decrescente ? (a, b) => cmp(b, a) : cmp);
    return ordenada;
  }

  List<RelacaoOSModel> _filtrarPorMaterial(List<RelacaoOSModel> lista) {
    final nome = _buscaNomeCtrl.text.trim().toLowerCase();
    final identificador = _identificadorCtrl.text.trim().toUpperCase();
    final medida = _medidaCtrl.text.trim().toUpperCase();
    final espessura = _espessuraCtrl.text.trim().toUpperCase();

    final temFiltro = nome.isNotEmpty ||
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

    final emAndamento = _ordenarRelacoes(_filtrarPorData(_filtrarPorMaterial(
      provider.relacoesOS
          .where((r) => r.status == 'EM_ANDAMENTO')
          .toList(),
    )));
    final fechadas = _ordenarRelacoes(_filtrarPorData(_filtrarPorMaterial(
      provider.relacoesOS.where((r) => r.status == 'FECHADA').toList(),
    )));

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
                      'Reentrada de Retalhos',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Visualização de OS e Materiais',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Atualizar lista de ordens de serviço',
                  child: IconButton(
                    onPressed: () =>
                        context.read<EstoqueProvider>().carregarRelacoesOS(),
                    icon: Icon(Icons.refresh,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(
                          color:
                              Theme.of(context).colorScheme.outlineVariant),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.all(
                          SystemMouseCursors.click),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscaCtrl,
                    onChanged: _buscar,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Buscar por número da OS...',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline,
                          size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _buscaNomeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Filtrar por nome do material...',
                      prefixIcon: Icon(Icons.filter_alt_outlined,
                          color: Theme.of(context).colorScheme.outline,
                          size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onPressed: () {
                    _buscaCtrl.clear();
                    _buscaNomeCtrl.clear();
                    _identificadorCtrl.clear();
                    _medidaCtrl.clear();
                    _espessuraCtrl.clear();
                    setState(() {
                      _dataInicio = null;
                      _dataFim = null;
                      _ordenacao = _OrdenacaoOS.recente;
                      _decrescente = true;
                    });
                    context.read<EstoqueProvider>().carregarRelacoesOS();
                  },
                  style: IconButton.styleFrom(
                    side: BorderSide(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: InputDecoration(
                      hintText: 'Identificador...',
                      prefixIcon: Icon(Icons.qr_code,
                          color: Theme.of(context).colorScheme.outline,
                          size: 18),
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
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Medida...',
                      prefixIcon: Icon(Icons.straighten,
                          color: Theme.of(context).colorScheme.outline,
                          size: 18),
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
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: InputDecoration(
                      hintText: 'Espessura...',
                      prefixIcon: Icon(Icons.layers,
                          color: Theme.of(context).colorScheme.outline,
                          size: 18),
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
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _DatePickerField(
                  label: 'Criado de',
                  value: _dataInicio,
                  firstDate: DateTime(2020),
                  lastDate: _dataFim ?? DateTime.now(),
                  onPicked: (d) => setState(() => _dataInicio = d),
                  onCleared: () => setState(() => _dataInicio = null),
                ),
                const SizedBox(width: 12),
                _DatePickerField(
                  label: 'até',
                  value: _dataFim,
                  firstDate: _dataInicio ?? DateTime(2020),
                  lastDate: DateTime.now(),
                  onPicked: (d) => setState(() => _dataFim = d),
                  onCleared: () => setState(() => _dataFim = null),
                ),
                const Spacer(),
                _OrdenacaoControl(
                  ordenacao: _ordenacao,
                  decrescente: _decrescente,
                  onOrdenacaoChanged: (o) => setState(() => _ordenacao = o),
                  onDirecaoToggled: () =>
                      setState(() => _decrescente = !_decrescente),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                    bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
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
                                const Icon(Icons.cloud_off_outlined,
                                    size: 48, color: AppTheme.error),
                                const SizedBox(height: 12),
                                Text(
                                  'Erro ao carregar',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  () {
                                    final partes =
                                        provider.erro!.split(': ');
                                    return partes.length > 1
                                        ? partes.sublist(1).join(': ')
                                        : provider.erro!;
                                  }(),
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
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

// ─── Seletor de período ───────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback onCleared;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onPicked,
    required this.onCleared,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value != null
        ? (value!.isAfter(lastDate) ? lastDate : value!)
        : (now.isBefore(lastDate) ? now : lastDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        final base = Theme.of(context);
        final clickCursor = WidgetStateProperty.resolveWith<MouseCursor>(
          (states) => states.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
        );
        return Theme(
          data: base.copyWith(
            textButtonTheme: TextButtonThemeData(
              style: (base.textButtonTheme.style ?? const ButtonStyle())
                  .copyWith(mouseCursor: clickCursor),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: (base.iconButtonTheme.style ?? const ButtonStyle())
                  .copyWith(mouseCursor: clickCursor),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
                  .copyWith(mouseCursor: clickCursor),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Tooltip(
      message:
          hasValue ? 'Alterar data ($label)' : 'Selecionar data ($label)',
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(8),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: hasValue
                  ? AppTheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: hasValue
                    ? AppTheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Text(
                hasValue ? '$label: ${_fmtData(value)}' : label,
                style: TextStyle(
                  fontSize: 13,
                  color: hasValue
                      ? AppTheme.primary
                      : Theme.of(context).colorScheme.outline,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (hasValue) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Limpar data',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onCleared,
                      child: Icon(Icons.close,
                          size: 14,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Controle de ordenação ────────────────────────────────────────────────────

class _OrdenacaoControl extends StatelessWidget {
  final _OrdenacaoOS ordenacao;
  final bool decrescente;
  final ValueChanged<_OrdenacaoOS> onOrdenacaoChanged;
  final VoidCallback onDirecaoToggled;

  const _OrdenacaoControl({
    required this.ordenacao,
    required this.decrescente,
    required this.onOrdenacaoChanged,
    required this.onDirecaoToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Ordenar lista de ordens de serviço',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_OrdenacaoOS>(
                  value: ordenacao,
                  isDense: true,
                  mouseCursor: SystemMouseCursors.click,
                  icon: Icon(Icons.arrow_drop_down,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  items: _OrdenacaoOS.values
                      .map((o) => DropdownMenuItem(
                            value: o,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(o.icon, size: 15, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Text('Ordenar: ${o.label}'),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (o) {
                    if (o != null) onOrdenacaoChanged(o);
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: decrescente
              ? 'Ordem decrescente (clique para inverter)'
              : 'Ordem crescente (clique para inverter)',
          onPressed: onDirecaoToggled,
          icon: Icon(
            decrescente ? Icons.arrow_downward : Icons.arrow_upward,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
        ),
      ],
    );
  }
}

// ─── Grid de OS ────────────────────────────────────────────────────────────────

bool _osEhNumerica(String numeroOS) => int.tryParse(numeroOS.trim()) != null;

String _categoriaEmpresa(String numeroOS) {
  final upper = numeroOS.trim().toUpperCase();
  if (upper.startsWith('EMPRESA-') || upper == 'EMPRESA') return 'EMPRESA';
  if (upper.startsWith('INVESTIMENTO-') || upper == 'INVESTIMENTO') {
    return 'INVESTIMENTO';
  }
  return 'OUTROS';
}

class _CategoriaEmpresaInfo {
  final String chave;
  final String label;
  final IconData icone;
  final Color cor;
  const _CategoriaEmpresaInfo(this.chave, this.label, this.icone, this.cor);
}

final _categoriasEmpresa = <_CategoriaEmpresaInfo>[
  _CategoriaEmpresaInfo(
      'EMPRESA', 'Empresa', Icons.business_outlined, AppTheme.primary),
  _CategoriaEmpresaInfo('INVESTIMENTO', 'Investimento', Icons.trending_up,
      const Color(0xFF2E7D32)),
  _CategoriaEmpresaInfo(
      'OUTROS', 'Outros', Icons.category_outlined, const Color(0xFF6D4C41)),
];

class _OsGrid extends StatefulWidget {
  final List<RelacaoOSModel> relacoes;
  final String emptyMessage;
  final void Function(RelacaoOSModel) onTap;

  const _OsGrid({
    required this.relacoes,
    required this.emptyMessage,
    required this.onTap,
  });

  @override
  State<_OsGrid> createState() => _OsGridState();
}

class _OsGridState extends State<_OsGrid> {
  String? _categoriaAberta;
  final GlobalKey _cardsCategoriaKey = GlobalKey();
  final GlobalKey _conteudoExpandidoKey = GlobalKey();

  void _alternarCategoria(String chave, bool estaSelecionada) {
    final abrindo = !estaSelecionada;
    setState(() => _categoriaAberta = abrindo ? chave : null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = abrindo ? _conteudoExpandidoKey : _cardsCategoriaKey;
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: abrindo ? 1.0 : 0.0,
        );
      }
    });
  }

  SliverToBoxAdapter _cabecalho(
          String titulo, int count, BuildContext context) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Divider(
                      color: Theme.of(context).colorScheme.outlineVariant)),
            ],
          ),
        ),
      );

  @override
  void didUpdateWidget(covariant _OsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_categoriaAberta != null) {
      final aindaExiste = widget.relacoes.any((r) =>
          !_osEhNumerica(r.numeroOS) &&
          _categoriaEmpresa(r.numeroOS) == _categoriaAberta);
      if (!aindaExiste) {
        _categoriaAberta = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.relacoes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              widget.emptyMessage,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 15),
            ),
          ],
        ),
      );
    }

    final numericas =
        widget.relacoes.where((r) => _osEhNumerica(r.numeroOS)).toList();
    final textuais =
        widget.relacoes.where((r) => !_osEhNumerica(r.numeroOS)).toList();

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1,
    );

    final porCategoria = <String, List<RelacaoOSModel>>{
      for (final c in _categoriasEmpresa) c.chave: <RelacaoOSModel>[],
    };
    for (final r in textuais) {
      porCategoria[_categoriaEmpresa(r.numeroOS)]!.add(r);
    }

    final categoriaInfo = _categoriaAberta == null
        ? null
        : _categoriasEmpresa.firstWhere((c) => c.chave == _categoriaAberta);
    final itensCategoria = _categoriaAberta == null
        ? const <RelacaoOSModel>[]
        : porCategoria[_categoriaAberta]!;

    return CustomScrollView(
      slivers: [
        if (numericas.isNotEmpty) ...[
          _cabecalho('Ordens de Serviço', numericas.length, context),
          SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final rel = numericas[i];
                return _RelacaoOSCard(
                    relacao: rel, onTap: () => widget.onTap(rel));
              },
              childCount: numericas.length,
            ),
            gridDelegate: gridDelegate,
          ),
        ],
        if (textuais.isNotEmpty) ...[
          _cabecalho('Outros', textuais.length, context),
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final largura = constraints.maxWidth;
                final colunas =
                    largura >= 640 ? 3 : (largura >= 420 ? 2 : 1);
                return Container(
                  key: _cardsCategoriaKey,
                  child: GridView.count(
                    crossAxisCount: colunas,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.9,
                    children: _categoriasEmpresa.map((cat) {
                      final itens = porCategoria[cat.chave]!;
                      final selecionado = _categoriaAberta == cat.chave;
                      return _CategoriaEmpresaCard(
                        info: cat,
                        count: itens.length,
                        selecionado: selecionado,
                        onTap: itens.isEmpty
                            ? null
                            : () => _alternarCategoria(cat.chave, selecionado),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
          if (_categoriaAberta != null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: categoriaInfo!.cor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OS em ${categoriaInfo.label}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final rel = itensCategoria[i];
                  final card = _RelacaoOSCard(
                      relacao: rel, onTap: () => widget.onTap(rel));
                  return i == 0
                      ? KeyedSubtree(key: _conteudoExpandidoKey, child: card)
                      : card;
                },
                childCount: itensCategoria.length,
              ),
              gridDelegate: gridDelegate,
            ),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

// ─── Card grande de categoria ──────────────────────────────────────────────────

class _CategoriaEmpresaCard extends StatelessWidget {
  final _CategoriaEmpresaInfo info;
  final int count;
  final bool selecionado;
  final VoidCallback? onTap;

  const _CategoriaEmpresaCard({
    required this.info,
    required this.count,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return Tooltip(
      message: habilitado
          ? (selecionado
              ? 'Recolher ${info.label}'
              : 'Ver ordens de ${info.label}')
          : 'Nenhuma ordem em ${info.label}',
      child: Card(
        elevation: selecionado ? 2 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: selecionado
              ? BorderSide(color: info.cor, width: 1.6)
              : BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1),
        ),
        color: selecionado ? info.cor.withValues(alpha: 0.06) : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          mouseCursor: habilitado
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Opacity(
            opacity: habilitado ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: info.cor
                          .withValues(alpha: selecionado ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(info.icone, color: info.cor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          info.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: selecionado
                                ? info.cor
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count ${count == 1 ? 'ordem' : 'ordens'}',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (habilitado)
                    Icon(
                      selecionado ? Icons.expand_less : Icons.expand_more,
                      color: selecionado
                          ? info.cor
                          : Theme.of(context).colorScheme.outline,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    final foiAlterada = relacao.atualizadoEm != null &&
        relacao.criadoEm != null &&
        relacao.atualizadoEm!.difference(relacao.criadoEm!).inMinutes.abs() >
            1;
    final dataStr = _fmtData(relacao.atualizadoEm ?? relacao.criadoEm);
    final criadoEmStr = _fmtData(relacao.criadoEm);

    final numeroOSRaw = relacao.numeroOS;
    final idxSufixo = [
      numeroOSRaw.indexOf('#OC'),
      numeroOSRaw.indexOf('#S'),
      numeroOSRaw.indexOf('#E'),
    ].where((i) => i > 0).fold<int>(
        -1, (best, i) => best == -1 ? i : (i < best ? i : best));
    final numeroOSDisplay =
        idxSufixo > 0 ? numeroOSRaw.substring(0, idxSufixo) : numeroOSRaw;

    final materiaisUnicos =
        relacao.movimentacoes.map((m) => m.materialId).toSet().length;

    final corSt = _corStatus(relacao.status);

    final tituloCard = int.tryParse(numeroOSDisplay) != null
        ? 'OS $numeroOSDisplay'
        : numeroOSDisplay;

    return Tooltip(
      message: 'Abrir $tituloCard',
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: corSt.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: corSt.withValues(alpha: 0.35)),
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
                    const SizedBox(height: 2),
                    Text(
                      '$materiaisUnicos '
                      '${materiaisUnicos == 1 ? 'material' : 'materiais'}',
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 11,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 3),
                        Text(
                          'Criado em $criadoEmStr',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    if (foiAlterada) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(right: 3),
                            child: Icon(Icons.update,
                                size: 11, color: AppTheme.primary),
                          ),
                          Text(
                            'Alterada em $dataStr',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();
    final rel = provider.relacaoSelecionada;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Tooltip(
          message: 'Voltar para a lista de ordens de serviço',
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              provider.limparSelecao();
              Navigator.of(context).pop();
            },
            style: IconButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_tituloOS),
            if (rel != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _corStatus(rel.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _corStatus(rel.status).withValues(alpha: 0.35)),
                ),
                child: Text(
                  _labelStatus(rel.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _corStatus(rel.status),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: provider.carregandoDetalhe
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : rel == null
              ? Center(
                  child: Text(
                    'Relação não encontrada',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : _RelacaoDetalheBody(rel: rel),
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
  String _chaveGrupo(MovimentacaoModel mov) => '${mov.materialId}';

  final TextEditingController _filtroCtrl = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  bool _entradaCorresponde(MapEntry<String, List<MovimentacaoModel>> entry) {
    if (_filtro.isEmpty) return true;
    final mov = entry.value.first;
    final campos = [
      mov.materialNome,
      mov.materialIdentificador ?? '',
      mov.materialMedida ?? '',
      mov.materialEspessura ?? '',
    ].join(' ').toLowerCase();
    return campos.contains(_filtro);
  }

  @override
  Widget build(BuildContext context) {
    final materiaisMap = <String, List<MovimentacaoModel>>{};
    for (final mov in widget.rel.movimentacoes) {
      materiaisMap.putIfAbsent(_chaveGrupo(mov), () => []).add(mov);
    }

    if (materiaisMap.isEmpty) {
      return const Center(
        child: Text('Nenhuma movimentação registrada'),
      );
    }

    final entries = materiaisMap.entries.where(_entradaCorresponde).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: TextField(
            controller: _filtroCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_UpperCaseFormatter()],
            decoration: InputDecoration(
              hintText:
                  'Filtrar materiais por nome, identificador, medida ou espessura...',
              prefixIcon: Icon(Icons.filter_alt_outlined,
                  color: Theme.of(context).colorScheme.outline, size: 20),
              isDense: true,
              suffixIcon: _filtro.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar filtro',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _filtroCtrl.clear();
                        setState(() => _filtro = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum material encontrado para o filtro.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    final movs = List<MovimentacaoModel>.from(entry.value)
                      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
                    return _MaterialGridCard(
                      key: ValueKey(entry.key),
                      movimentacoes: movs,
                      numeroOS: widget.rel.numeroOS,
                      somenteLeitura: widget.rel.estaFechada,
                    );
                  },
                ),
        ),],
    );
  }
}

// ─── Card de material em grid (somente leitura + reentrada de retalho) ─────────

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

  bool get _materialFoiExcluido =>
      _primeira.materialNome == '(material excluído)' ||
      _primeira.materialNome.isEmpty;

  String get _subtitulo {
    final partes = <String>[
      if ((_primeira.materialIdentificador ?? '').isNotEmpty)
        _primeira.materialIdentificador!,
      if ((_primeira.materialMedida ?? '').isNotEmpty) _primeira.materialMedida!,
      if ((_primeira.materialEspessura ?? '').isNotEmpty)
        _primeira.materialEspessura!,
    ];
    return partes.join(' · ');
  }

  String _formatQtd(double qtd, String? unidade) {
    final qStr =
        qtd == qtd.truncate() ? qtd.toStringAsFixed(0) : qtd.toStringAsFixed(2);
    return unidade != null ? '$qStr $unidade' : qStr;
  }

  String _formatData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _abrirReentradaRetalho(BuildContext context) async {
    if (_materialFoiExcluido) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Material excluído — não é possível criar reentrada de retalho.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    final material = _primeira;

    final messenger = ScaffoldMessenger.of(context);
    final estoqueProvider = context.read<EstoqueProvider>();
    final materialProvider = context.read<MaterialProvider>();

    final mat = await materialProvider.buscarPorId(material.materialId);
    if (!context.mounted) return;

    final largura = mat?.largura;
    final comprimento = mat?.comprimento;

    if (largura == null ||
        comprimento == null ||
        largura <= 0 ||
        comprimento <= 0) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Este material não tem largura/comprimento cadastrados. '
          'Cadastre as dimensões para usar a reentrada de retalho.',
        ),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }

    final custoM2 = () {
      final ultimaSaidaComPreco = widget.movimentacoes
          .where((m) =>
              m.tipo == 'SAIDA' && m.precoM2 != null && m.precoM2! > 0)
          .fold<MovimentacaoModel?>(
              null,
              (prev, m) => prev == null || m.criadoEm.isAfter(prev.criadoEm)
                  ? m
                  : prev);
      if (ultimaSaidaComPreco != null) {
        if (ultimaSaidaComPreco.usouModoDimensional) {
          final lu = ultimaSaidaComPreco.larguraUsada!;
          final cu = ultimaSaidaComPreco.comprimentoUsado!;
          final area = lu * cu;
          return area > 0
              ? ultimaSaidaComPreco.precoM2! / area
              : mat?.ultimoValorPagoM2;
        }
        return ultimaSaidaComPreco.precoM2;
      }
      if (mat?.ultimoValorPago != null && mat!.ultimoValorPago! > 0) {
        final areaChapa = largura * comprimento;
        return areaChapa > 0 ? mat.ultimoValorPago! / areaChapa : null;
      }
      return mat?.ultimoValorPagoM2;
    }();

    final areaUnitaria = largura * comprimento;

    final totalSaidasUnid = widget.movimentacoes
        .where((m) => m.tipo == 'SAIDA')
        .fold<double>(0, (s, m) => s + m.quantidade);

    final areaTotalSaida = totalSaidasUnid * areaUnitaria;

    final custoTotalSaidas =
        widget.movimentacoes.where((m) => m.tipo == 'SAIDA').fold<double>(0,
            (s, m) {
      if (m.usouModoDimensional && m.precoM2 != null) {
        return s + m.precoM2!;
      }
      if (m.precoUnitario != null && m.precoUnitario! > 0) {
        return s + m.precoUnitario! * m.quantidade;
      }
      if (m.precoM2 != null && m.precoM2! > 0) {
        return s + m.precoM2! * m.quantidade;
      }
      return s;
    });

    final m2Ctrl = TextEditingController();

    String fmt6(double v) => _brl6(v);
    String fmtQtd(double v) => v == v.truncateToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(4);

    final resultado = await showDialog<double>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) {
          final m2TextoRaw = m2Ctrl.text.replaceAll(',', '.');
          final m2Retalho = double.tryParse(m2TextoRaw);

          final liquidoM2 = (m2Retalho != null && m2Retalho > 0)
              ? (areaTotalSaida - m2Retalho)
                  .clamp(0.0, double.infinity)
                  .toDouble()
              : null;

          final custoLiquido = (liquidoM2 != null &&
                  areaTotalSaida > 0 &&
                  custoTotalSaidas > 0)
              ? custoTotalSaidas * (liquidoM2 / areaTotalSaida)
              : (liquidoM2 != null && custoM2 != null && custoM2 > 0)
                  ? liquidoM2 * custoM2
                  : null;

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.content_cut,
                      color: AppTheme.success, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Reentrada de Retalho'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    material.materialNome,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  if ((material.materialEspessura ?? '').isNotEmpty)
                    Text(
                      material.materialEspessura!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total saído nesta OS',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${fmtQtd(totalSaidasUnid)} unid. '
                          '× ${fmtQtd(areaUnitaria)} m²/unid. '
                          '= ${fmtQtd(areaTotalSaida)} m²',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.error,
                          ),
                        ),
                        if (custoTotalSaidas > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Custo total registrado: ${fmt6(custoTotalSaidas)}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ] else if (custoM2 != null && custoM2 > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Custo m²: ${fmt6(custoM2)}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: m2Ctrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'M² de retalho que sobrou *',
                      suffixText: 'm²',
                      isDense: true,
                    ),
                    onChanged: (_) => setDlg(() {}),
                  ),
                  if (liquidoM2 != null) ...[
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
                            'M² realmente utilizado nesta OS',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${fmtQtd(areaTotalSaida)} m² − ${fmtQtd(m2Retalho!)} m² '
                            '= ${fmtQtd(liquidoM2)} m²',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          if (custoLiquido != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Custo líquido no relatório: ${fmt6(custoLiquido)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.success.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      'Será criado (ou somado ao existente) um material '
                      '"${material.materialNome}" com identificador RETALHO, unidade M² '
                      'e a quantidade informada será adicionada ao estoque.',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: m2Retalho == null || m2Retalho <= 0
                    ? null
                    : () => Navigator.of(dlgCtx).pop(m2Retalho),
                icon: const Icon(Icons.content_cut, size: 16),
                label: const Text('Confirmar Reentrada'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
              ),
            ],
          );
        },
      ),
    );

    if (resultado == null || resultado <= 0) return;
    if (!context.mounted) return;

    final m2Retalho = resultado;

    final nomeRetalho = material.materialNome;
    final espessura = material.materialEspessura;
    final categoria = mat?.categoria;

    final sugestoes = await materialProvider.buscarSugestoes(
      nomeRetalho,
      limite: 20,
      apenasAtivos: true,
    );
    if (!context.mounted) return;

    MaterialModel? retalhoExistente;
    for (final s in sugestoes) {
      final nomeNorm = _normalizarTextoComparacao(s.nome);
      final nomeAlvo = _normalizarTextoComparacao(nomeRetalho);
      final mesmoIdent = (s.identificador?.toUpperCase() ?? '') == 'RETALHO';
      final mesmaEsp = espessura == null ||
          espessura.isEmpty ||
          _normalizarTextoComparacao(s.espessura) ==
              _normalizarTextoComparacao(espessura);
      if (nomeNorm == nomeAlvo && mesmoIdent && mesmaEsp) {
        retalhoExistente = s;
        break;
      }
    }

    int retalhoMaterialId;

    if (retalhoExistente != null) {
      retalhoMaterialId = retalhoExistente.id;
    } else {
      final ok = await materialProvider.criar({
        'nome': nomeRetalho,
        'identificador': 'RETALHO',
        'unidade': 'M²',
        'categoria': categoria,
        'espessura': espessura,
        'quantidade': 0.0,
        'estoqueMinimo': 0.0,
        'estoqueConfirmado': false,
        if (custoM2 != null && custoM2 > 0) 'ultimoValorPagoM2': custoM2,
      });
      if (!context.mounted) return;
      if (!ok) {
        messenger.showSnackBar(SnackBar(
          content: Text(materialProvider.erro ??
              'Erro ao criar material "$nomeRetalho"'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
      final lista =
          await materialProvider.buscarSugestoes(nomeRetalho, limite: 5);
      if (!context.mounted) return;
      final criado = lista.firstWhere(
        (s) =>
            _normalizarTextoComparacao(s.nome) ==
                _normalizarTextoComparacao(nomeRetalho) &&
            (s.identificador?.toUpperCase() ?? '') == 'RETALHO',
        orElse: () => lista.first,
      );
      retalhoMaterialId = criado.id;
    }

    final custoM2Retalho = custoM2;

    final entradaOk = await estoqueProvider.registrarMovimentacaoSilencioso(
      materialId: retalhoMaterialId,
      tipo: 'ENTRADA',
      quantidade: m2Retalho,
      numeroOS: widget.numeroOS,
      precoUnitario: null,
      precoM2: custoM2Retalho,
      observacao: 'Retalho de ${material.materialNome}',
      materialOrigemId: material.materialId,
    );
    if (!context.mounted) return;

    if (!entradaOk) {
      messenger.showSnackBar(SnackBar(
        content:
            Text(estoqueProvider.erro ?? 'Erro ao registrar reentrada'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }

    await estoqueProvider.carregarRelacoesOS();
    if (!context.mounted) return;
    await estoqueProvider.selecionarRelacaoOS(widget.numeroOS);
    if (!context.mounted) return;

    final liquidoM2Final =
        (areaTotalSaida - m2Retalho).clamp(0.0, double.infinity).toDouble();
    final custoLiquidoFinal = custoTotalSaidas > 0 && areaTotalSaida > 0
        ? custoTotalSaidas * (liquidoM2Final / areaTotalSaida)
        : (custoM2 != null && custoM2 > 0 ? liquidoM2Final * custoM2 : null);

    messenger.showSnackBar(SnackBar(
      content: Text(
        custoLiquidoFinal != null
            ? 'Retalho registrado. Líquido utilizado: ${liquidoM2Final.toStringAsFixed(4)} m²'
                ' — Custo: ${_brl6(custoLiquidoFinal)}'
            : 'Retalho registrado. M² líquido utilizado: ${liquidoM2Final.toStringAsFixed(4)} m²',
      ),
      backgroundColor: AppTheme.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _mostrarPainel(context),
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
                        Text(
                          _primeira.materialNome,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_subtitulo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _subtitulo,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.expand_more,
                      size: 18, color: Theme.of(context).colorScheme.outline),
                ],
              ),
              const Spacer(),
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
    final materialNome = _primeira.materialNome;
    final subtitulo = _subtitulo;
    final unidade = _primeira.materialUnidade;
    final somenteLeitura = widget.somenteLeitura;
    final chaveGrupo =
        widget.movimentacoes.isNotEmpty ? '${_primeira.materialId}' : '';

    await showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Consumer<EstoqueProvider>(
        builder: (ctx, provider, _) {
          final rel = provider.relacaoSelecionada;
          final movsAtuais = rel == null
              ? <MovimentacaoModel>[]
              : rel.movimentacoes
                  .where((m) => '${m.materialId}' == chaveGrupo)
                  .toList()
            ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

          if (movsAtuais.isEmpty && rel != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              final navigator = Navigator.of(ctx);
              if (navigator.canPop()) navigator.pop();
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
                              if (subtitulo.isNotEmpty)
                                Text(
                                  subtitulo,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              if (unidade != null)
                                Text(
                                  unidade,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Fechar',
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                            },
                            style: IconButton.styleFrom().copyWith(
                              mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (!somenteLeitura &&
                        _primeira.materialUnidade?.toUpperCase() ==
                            'UNIDADE') ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _abrirReentradaRetalho(context);
                          },
                          icon: const Icon(Icons.content_cut,
                              size: 16, color: AppTheme.success),
                          label: const Text(
                            'Reentrada de Retalho',
                            style: TextStyle(color: AppTheme.success),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.success),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (somenteLeitura) ...[
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
                      const SizedBox(height: 16),
                    ],
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text(
                      'Histórico (${movsAtuais.length})',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
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

// ─── Row de movimentação (somente leitura) ────────────────────────────────────

class _MovimentacaoRow extends StatelessWidget {
  final MovimentacaoModel mov;
  final String? unidade;
  final String Function(DateTime) formatData;
  final String Function(double, String?) formatQtd;

  const _MovimentacaoRow({
    required this.mov,
    required this.unidade,
    required this.formatData,
    required this.formatQtd,
  });

  @override
  Widget build(BuildContext context) {
    final isEntrada = mov.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;
    final icon = isEntrada ? Icons.arrow_upward : Icons.arrow_downward;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          const SizedBox(width: 10),
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
                    const SizedBox(width: 6),
                    Text(
                      formatQtd(mov.quantidade, unidade),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  formatData(mov.criadoEm),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 11),
                ),
                if (mov.observacao != null && mov.observacao!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes,
                          size: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          mov.observacao!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontStyle: FontStyle.italic),
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
    );
  }
}