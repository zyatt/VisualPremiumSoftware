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

/// Formata um valor de dimensão (metros) sem casas decimais desnecessárias.
/// Ex.: 1.0 → "1"; 0.5 → "0.5".
String _fmtDim(double v) =>
    v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

/// Formata uma quantidade sem arredondar/cortar a precisão real do valor,
/// aplicando separador de milhar (ponto) na parte inteira e vírgula como
/// separador decimal (padrão brasileiro).
/// Diferente de `toStringAsFixed(2)`, que exibia apenas 2 casas mesmo quando
/// o valor real tinha mais precisão (ex.: 3.696 aparecia como "3.70").
/// Ex.: 3.696 → "3,696"; 4.0 → "4"; 1000 → "1.000"; 1000.5 → "1.000,5".
String _formatarQuantidade(double v) {
  final bool isInteiro = v == v.truncateToDouble();
  final String bruto = isInteiro ? v.toStringAsFixed(0) : v.toString();

  final bool negativo = bruto.startsWith('-');
  final String semSinal = negativo ? bruto.substring(1) : bruto;

  final partes = semSinal.split('.');
  final parteInteira = partes[0];
  final parteDecimal = partes.length > 1 ? partes[1] : null;

  final buffer = StringBuffer();
  final len = parteInteira.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buffer.write('.');
    buffer.write(parteInteira[i]);
  }

  final resultado = parteDecimal != null
      ? '${buffer.toString()},$parteDecimal'
      : buffer.toString();

  return negativo ? '-$resultado' : resultado;
}

/// Retorna a exibição de medida de um material: usa o campo [medida] quando
/// preenchido; caso contrário, monta a partir de [largura]/[comprimento]
/// cadastrados diretamente no material.
/// Exemplos: comprimento=50 e largura=1.22 → "50x1.22m"; só comprimento=50 → "50m";
/// só largura=1.22 → "1.22m". Retorna null se nada estiver disponível.
String? _formatarMedidaOuDimensoes({
  required String? medida,
  required double? largura,
  required double? comprimento,
}) {
  if (medida != null && medida.trim().isNotEmpty) return medida.trim();

  final temLargura     = largura != null && largura > 0;
  final temComprimento = comprimento != null && comprimento > 0;

  if (temComprimento && temLargura) {
    return '${_fmtDim(comprimento)}x${_fmtDim(largura)}m';
  }
  if (temComprimento) return '${_fmtDim(comprimento)}m';
  if (temLargura)     return '${_fmtDim(largura)}m';
  return null;
}

/// Formata a unidade para exibição (o valor interno permanece em maiúsculo,
/// usado para comparações/enum). Ex.: 'UNIDADE' → 'Unidade'; 'M' → 'm';
/// 'M/L' → 'm/l'; 'ML' → 'ml'; 'M²' → 'm²'; 'KG' → 'Kg'; 'G' → 'g'.
String formatarUnidadeExibicao(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return '';
  final u = unidade.trim().toUpperCase();
  switch (u) {
    case 'M':
      return 'm';
    case 'M/L':
      return 'm/l';
    case 'ML':
      return 'ml';
    case 'M²':
    case 'M2':
      return 'm²';
    case 'KG':
      return 'Kg';
    case 'G':
      return 'g';
    case 'UNIDADE':
      return 'Unidade';
    default:
      return unidade;
  }
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

// ── Formatter: medida (vírgula -> ponto, minúsculas, 1 ponto por número) ──

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

/// Formata um valor de espessura garantindo o sufixo "mm" sem duplicar.
String? formatarEspessuraComSufixo(String? valor) {
  final v = valor?.trim();
  if (v == null || v.isEmpty) return null;
  final numero = v.replaceAll(RegExp(r'\s*mm\s*$', caseSensitive: false), '').trim();
  if (numero.isEmpty) return null;
  return '${numero}mm';
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

// ── Origem da movimentação ─────────────────────────────────────────────────
// Fonte primária: o campo estruturado mov.origemProducao ('TRANSFERENCIA' /
// 'BAIXA'), preenchido pelo backend sempre que a movimentação faz parte do
// fluxo de produção — mais confiável que ler texto livre.
// Fallback (movimentações antigas sem esse campo): prefixo gravado
// automaticamente no campo observacao:
//   "Entrada/Saída via controle de estoque – {nome}"  → estoque
//   "Saída via produção – {nome}"                     → producao
//   "Entrada via OC #{id} – {nome}"                   → ordemCompra

enum _OrigemMov { estoque, producao, ordemCompra, desconhecida }

_OrigemMov _detectarOrigemMov(MovimentacaoModel mov) {
  if (mov.origemProducao != null && mov.origemProducao!.isNotEmpty) {
    return _OrigemMov.producao;
  }
  return _detectarOrigem(mov.observacao);
}

_OrigemMov _detectarOrigem(String? obs) {
  if (obs == null || obs.isEmpty) return _OrigemMov.desconhecida;
  final linha = obs.split('\n').first.toLowerCase();
  if (linha.contains('via controle de estoque')) return _OrigemMov.estoque;
  if (linha.contains('via producao') || linha.contains('via produção')) return _OrigemMov.producao;
  if (linha.contains('via oc')) return _OrigemMov.ordemCompra;
  return _OrigemMov.desconhecida;
}

({String label, IconData icon, Color cor}) _origemInfo(
    _OrigemMov origem, BuildContext context, {String? producao}) {
  switch (origem) {
    case _OrigemMov.estoque:
      return (label: 'Estoque', icon: Icons.inventory_2_outlined, cor: const Color(0xFF2196F3));
    case _OrigemMov.producao:
      final label = (producao != null && producao.isNotEmpty)
          ? 'Produção $producao'
          : 'Produção';
      return (label: label, icon: Icons.precision_manufacturing_outlined, cor: const Color(0xFFFF9800));
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
  final TextEditingController _identificadorCtrl  = TextEditingController();
  final TextEditingController _medidaCtrl         = TextEditingController();
  final TextEditingController _comprimentoCtrl    = TextEditingController();
  final TextEditingController _larguraCtrl        = TextEditingController();
  final TextEditingController _espessuraCtrl      = TextEditingController();
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
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _comprimentoCtrl.dispose();
    _larguraCtrl.dispose();
    _espessuraCtrl.dispose();
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
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _comprimentoCtrl.clear();
    _larguraCtrl.clear();
    _espessuraCtrl.clear();
    setState(() {
      _filtroTipo   = _FiltroTipo.todos;
      _filtroOrigem = null;
      _dataInicio   = null;
      _dataFim      = null;
    });
  }

  List<_ItemHistorico> _itensFiltrados(List<RelacaoOSModel> relacoes) {
    final os             = _buscaOSCtrl.text.trim().toUpperCase();
    final material       = _buscaMaterialCtrl.text.trim().toLowerCase();
    final usuario        = _buscaUsuarioCtrl.text.trim().toLowerCase();
    final identificador  = _identificadorCtrl.text.trim().toLowerCase();
    final medida         = _medidaCtrl.text.trim().toLowerCase();
    final comprimento    = _comprimentoCtrl.text.trim().toUpperCase();
    final largura        = _larguraCtrl.text.trim().toUpperCase();
    final espessura      = _espessuraCtrl.text.trim().toLowerCase();

    final itens = <_ItemHistorico>[];
    for (final r in relacoes) {
      for (final m in r.movimentacoes) {
        if (_filtroTipo == _FiltroTipo.entrada && m.tipo != 'ENTRADA') continue;
        if (_filtroTipo == _FiltroTipo.saida && m.tipo != 'SAIDA') continue;
        if (_filtroOrigem != null && _detectarOrigemMov(m) != _filtroOrigem) continue;
        if (os.isNotEmpty && !r.numeroOS.toUpperCase().contains(os)) continue;
        if (material.isNotEmpty &&
            !m.materialNome.toLowerCase().contains(material)) {
          continue;
        }
        if (identificador.isNotEmpty) {
          final v = (m.materialIdentificador ?? '').toLowerCase();
          if (!v.contains(identificador)) continue;
        }
        if (medida.isNotEmpty) {
          final medidaFmt = _formatarMedidaOuDimensoes(
                medida:      m.materialMedida,
                largura:     m.materialLargura,
                comprimento: m.materialComprimento,
              ) ??
              '';
          if (!medidaFmt.toLowerCase().contains(medida)) continue;
        }
        if (comprimento.isNotEmpty) {
          final v = (m.materialComprimento?.toString() ?? '').toUpperCase();
          if (!v.contains(comprimento)) continue;
        }
        if (largura.isNotEmpty) {
          final v = (m.materialLargura?.toString() ?? '').toUpperCase();
          if (!v.contains(largura)) continue;
        }
        if (espessura.isNotEmpty) {
          final v = (m.materialEspessura ?? '').toLowerCase();
          if (!v.contains(espessura)) continue;
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
                _BotaoVoltar(
                  label: 'Voltar',
                  tooltip: 'Voltar',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
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
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
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
                      hintText: 'Buscar por número da OS',
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
                      hintText: 'Filtrar por material',
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
                      hintText: 'Filtrar por usuário',
                      prefixIcon: Icon(Icons.person_outline,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Builder(
                  builder: (context) {
                    final temFiltro = _buscaOSCtrl.text.isNotEmpty ||
                        _buscaMaterialCtrl.text.isNotEmpty ||
                        _buscaUsuarioCtrl.text.isNotEmpty ||
                        _identificadorCtrl.text.isNotEmpty ||
                        _medidaCtrl.text.isNotEmpty ||
                        _comprimentoCtrl.text.isNotEmpty ||
                        _larguraCtrl.text.isNotEmpty ||
                        _espessuraCtrl.text.isNotEmpty ||
                        _filtroTipo != _FiltroTipo.todos ||
                        _filtroOrigem != null ||
                        _dataInicio != null ||
                        _dataFim != null;
                    return IconButton.outlined(
                      tooltip: 'Limpar filtros',
                      icon: Icon(Icons.filter_alt_off,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: temFiltro ? _limparFiltros : null,
                      style: IconButton.styleFrom(
                        side: BorderSide(color: Theme.of(context).colorScheme.outline),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.disabled)) {
                            return SystemMouseCursors.basic;
                          }
                          return SystemMouseCursors.click;
                        }),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Filtros de material: identificador, medida, espessura ────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Identificador',
                      prefixIcon: Icon(Icons.qr_code,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    inputFormatters: [_MedidaEspessuraFormatter()],
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Medida',
                      prefixIcon: Icon(Icons.straighten,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _comprimentoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Comprimento',
                      suffixText: 'm',
                      prefixIcon: Icon(Icons.height,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _larguraCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Largura',
                      suffixText: 'm',
                      prefixIcon: Icon(Icons.width_normal,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Espessura...',
                      suffixText: 'mm',
                      prefixIcon: Icon(Icons.layers,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
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
                    ButtonSegment(
                      value: _FiltroTipo.todos,
                      label: Text('Todos'),
                      tooltip: 'Mostrar entradas e saídas',
                    ),
                    ButtonSegment(
                      value: _FiltroTipo.entrada,
                      label: Text('Entradas'),
                      tooltip: 'Mostrar apenas entradas',
                    ),
                    ButtonSegment(
                      value: _FiltroTipo.saida,
                      label: Text('Saídas'),
                      tooltip: 'Mostrar apenas saídas',
                    ),
                  ],
                  selected: {_filtroTipo},
                  onSelectionChanged: (s) => setState(() => _filtroTipo = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Filtrar a partir de uma data',
                  child: OutlinedButton.icon(
                    onPressed: () => _selecionarData(inicio: true),
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(_dataInicio == null ? 'De' : _fmtData(_dataInicio)),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact)
                        .copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Filtrar até uma data',
                  child: OutlinedButton.icon(
                    onPressed: () => _selecionarData(inicio: false),
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(_dataFim == null ? 'Até' : _fmtData(_dataFim)),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact)
                        .copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
                if (_dataInicio != null || _dataFim != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Limpar período',
                    onPressed: () => setState(() {
                      _dataInicio = null;
                      _dataFim = null;
                    }),
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
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
                    child: Tooltip(
                      message: origem == null
                          ? 'Mostrar movimentações de todas as origens'
                          : 'Filtrar por origem: $label',
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
                        mouseCursor: SystemMouseCursors.click,
                      ),
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
// O card inteiro é clicável (abre a OS), com hover e cursor de mão,
// seguindo o mesmo padrão visual do botão "Voltar" no cabeçalho.

class _LinhaHistorico extends StatefulWidget {
  final _ItemHistorico item;
  final VoidCallback onTapOS;
  const _LinhaHistorico({required this.item, required this.onTapOS});

  @override
  State<_LinhaHistorico> createState() => _LinhaHistoricoState();
}

class _LinhaHistoricoState extends State<_LinhaHistorico> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mov = widget.item.mov;
    final relacao = widget.item.relacao;
    final isEntrada = mov.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;
    final icon = isEntrada ? Icons.arrow_upward : Icons.arrow_downward;
    final usuario = _extrairUsuario(mov.observacao);
    final obsExtra = _extrairObsExtra(mov.observacao);
    final origem = _detectarOrigemMov(mov);
    final origemInfo = _origemInfo(origem, context, producao: mov.producao);
    final scheme = Theme.of(context).colorScheme;

    final qtdStr = _formatarQuantidade(mov.quantidade);
    final temDimensaoUsada = mov.usouModoDimensional == true &&
        mov.comprimentoUsado != null &&
        mov.larguraUsada != null;
    final dimensaoUsadaStr = temDimensaoUsada
        ? ' (${_fmtDim(mov.comprimentoUsado!)}x${_fmtDim(mov.larguraUsada!)}m)'
        : '';
    final medidaFmt = _formatarMedidaOuDimensoes(
      medida:      mov.materialMedida,
      largura:     mov.materialLargura,
      comprimento: mov.materialComprimento,
    );
    final espessuraFmt = formatarEspessuraComSufixo(mov.materialEspessura);
    final temIdentificador = mov.materialIdentificador != null && mov.materialIdentificador!.isNotEmpty;
    final detalhesMaterial = [
      if (medidaFmt != null) medidaFmt,
      if (espessuraFmt != null) espessuraFmt,
    ].join(' · ');

    final bgColor = _hovered
        ? const Color(0xFFFF9800).withValues(alpha: 0.10)
        : scheme.surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTapOS,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: bgColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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

          // ── Material (flexível, com bastante espaço para o nome) ─────────
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (temIdentificador)
                        TextSpan(text: '${mov.materialIdentificador!} · '),
                      TextSpan(text: mov.materialNome),
                      if (detalhesMaterial.isNotEmpty)
                        TextSpan(text: ' · $detalhesMaterial'),
                    ],
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  softWrap: true,
                ),
                if (obsExtra != null)
                  Text(
                    obsExtra,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ── Quantidade (150px fixo) ──────────────────────────────────────
          SizedBox(
            width: 150,
            child: Text(
              '${isEntrada ? '+' : '-'}$qtdStr${mov.materialUnidade != null ? ' ${formatarUnidadeExibicao(mov.materialUnidade)}' : ''}$dimensaoUsadaStr',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cor),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── OS (160px fixo) ──────────────────────────────────────────────
          SizedBox(
            width: 160,
            child: Tooltip(
              message: 'Abrir OS ${relacao.numeroOS}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 13,
                      color: _hovered ? AppTheme.primary : Theme.of(context).colorScheme.outline),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ── Botão "voltar" com hover, cursor de mão e tooltip ───────────────────────
// Mesmo padrão usado no cabeçalho das outras páginas do sistema.
class _BotaoVoltar extends StatefulWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _BotaoVoltar({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_BotaoVoltar> createState() => _BotaoVoltarState();
}

class _BotaoVoltarState extends State<_BotaoVoltar> {
  bool _hovered = false;
  static const _accent = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? _accent.withValues(alpha: 0.15)
                  : _accent.withValues(alpha: 0.08),
              border: Border.all(
                color: _accent.withValues(alpha: _hovered ? 0.9 : 0.5),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: _accent,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _accent,
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