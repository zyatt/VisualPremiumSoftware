import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/estoque_model.dart';
import '../providers/estoque_provider.dart';
import '../providers/relatorio_os_provider.dart';
import '../repositories/estoque_repository.dart';
import '../theme/app_theme.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Formata um valor monetário com até 6 casas decimais,
/// removendo zeros à direita desnecessários (mínimo 2 casas).
String _brl(double v) {
  if (v == 0) return '—';
  final s6 = v.toStringAsFixed(6);
  // Remove zeros à direita mas mantém ao menos 2 casas decimais
  final trimmed = s6.replaceAll(RegExp(r'0+$'), '');
  final partes = trimmed.split('.');
  final dec = partes.length > 1 ? partes[1] : '';
  final decFinal = dec.length < 2 ? dec.padRight(2, '0') : dec;
  return 'R\$ ${partes[0]},$decFinal';
}

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

/// Remove sufixos internos usados para distinguir OS textuais no banco:
/// #OC... (ordem de compra), #S... (saída global), #E... (entrada global).
String _limparNumeroOS(String numeroOS) {
  final match = RegExp(r'#(OC|S|E)\d*').firstMatch(numeroOS);
  if (match != null && match.start > 0) {
    return numeroOS.substring(0, match.start);
  }
  return numeroOS;
}

String _tituloOS(String numeroOS) {
  final n = _limparNumeroOS(numeroOS);
  return int.tryParse(n) != null ? 'OS $n' : n;
}

const _corFechada = Color(0xFF4CAF50);

/// Calcula o custo líquido de uma OS: saídas - devoluções, agrupado por material.
/// Usa o preço da saída como referência. Entradas de materiais sem saída são ignoradas.
/// Processa em ordem cronológica: apenas entradas POSTERIORES à primeira saída
/// do material são contadas como devolução (evita somar entradas anteriores à saída).
///
/// Entradas geradas por Ordem de Compra (observacao ou descricaoItem contendo
/// "via OC") são reposição de estoque — NÃO são devoluções — e por isso são
/// ignoradas no cálculo do custo líquido.
double _totalLiquido(List<MovimentacaoModel> movimentacoes) {
  // materialId → { preco, qtdSaida, qtdEntrada }
  final porMaterial = <int, Map<String, double>>{};

  // Ordena por criadoEm ascendente (mais antiga primeiro)
  final ordenadas = [...movimentacoes]
    ..sort((a, b) {
      return a.criadoEm.compareTo(b.criadoEm);
    });

  for (final m in ordenadas) {
    final pu = m.precoUnitario ?? 0.0;
    final pm = m.precoM2 ?? 0.0;
    final p  = pu > 0 ? pu : (pm > 0 ? pm : 0.0);

    if (m.tipo == 'SAIDA') {
      porMaterial.putIfAbsent(
        m.materialId,
        () => {'preco': p, 'qtdSaida': 0.0, 'qtdEntrada': 0.0},
      );
      final entry = porMaterial[m.materialId]!;
      if (p > entry['preco']!) entry['preco'] = p;
      entry['qtdSaida'] = entry['qtdSaida']! + m.quantidade;
    } else if (m.tipo == 'ENTRADA') {
      // Entradas via OC são reposição de estoque, não devoluções — ignorar.
      final isEntradaOC =
          (m.observacao?.contains('via OC') ?? false);
      if (isEntradaOC) continue;

      // Só conta como devolução se já houve ao menos uma saída deste material
      if (porMaterial.containsKey(m.materialId)) {
        porMaterial[m.materialId]!['qtdEntrada'] =
            porMaterial[m.materialId]!['qtdEntrada']! + m.quantidade;
      }
    }
  }

  return porMaterial.values.fold(0.0, (acc, e) {
    final qtdLiquida = (e['qtdSaida']! - e['qtdEntrada']!).clamp(0.0, double.infinity);
    return acc + e['preco']! * qtdLiquida;
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// Página principal — lista de OS fechadas
// ═════════════════════════════════════════════════════════════════════════════

class RelatorioOSPage extends StatefulWidget {
  const RelatorioOSPage({super.key});

  @override
  State<RelatorioOSPage> createState() => _RelatorioOSPageState();
}

// Formatter reutilizado do estoque: maiúsculas sem acentos
class _UpperCaseFormatter extends TextInputFormatter {
  static final _acentos = {
    'À':'A','Á':'A','Â':'A','Ã':'A','à':'a','á':'a','â':'a','ã':'a',
    'È':'E','É':'E','Ê':'E','è':'e','é':'e','ê':'e',
    'Ì':'I','Í':'I','ì':'i','í':'i',
    'Ò':'O','Ó':'O','Ô':'O','Õ':'O','ò':'o','ó':'o','ô':'o','õ':'o',
    'Ù':'U','Ú':'U','Û':'U','ù':'u','ú':'u','û':'u',
    'Ç':'C','ç':'c','Ñ':'N','ñ':'n',
  };
  static String _rem(String s) =>
      s.split('').map((c) => _acentos[c] ?? c).join();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue o, TextEditingValue n) {
    final t = _rem(n.text).toUpperCase();
    final sel = n.selection.copyWith(
      baseOffset:   n.selection.baseOffset.clamp(0, t.length),
      extentOffset: n.selection.extentOffset.clamp(0, t.length),
    );
    return n.copyWith(text: t, selection: sel);
  }
}

class _RelatorioOSPageState extends State<RelatorioOSPage> {
  // ── Controllers ───────────────────────────────────────────────────────────
  final _buscaOSCtrl       = TextEditingController(); // busca por nº OS
  final _materialIdCtrl    = TextEditingController();
  final _materialNomeCtrl  = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  Timer? _debounce;

  // ── Filtro de período ─────────────────────────────────────────────────────
  DateTime? _dataInicio;
  DateTime? _dataFim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RelatorioOSProvider>().carregar();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaOSCtrl.dispose();
    _materialIdCtrl.dispose();
    _materialNomeCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  void _aplicarFiltros() {
    context.read<RelatorioOSProvider>().carregar(
          busca:                 _buscaOSCtrl.text.trim().isEmpty
              ? null
              : _buscaOSCtrl.text.trim(),
          materialId:            _materialIdCtrl.text.trim().isEmpty
              ? null
              : _materialIdCtrl.text.trim(),
          materialNome:          _materialNomeCtrl.text.trim().isEmpty
              ? null
              : _materialNomeCtrl.text.trim(),
          materialIdentificador: _identificadorCtrl.text.trim().isEmpty
              ? null
              : _identificadorCtrl.text.trim(),
          materialMedida:        _medidaCtrl.text.trim().isEmpty
              ? null
              : _medidaCtrl.text.trim(),
          materialEspessura:     _espessuraCtrl.text.trim().isEmpty
              ? null
              : _espessuraCtrl.text.trim(),
          dataInicio:            _dataInicio,
          dataFim:               _dataFim,
        );
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      _aplicarFiltros,
    );
  }

  void _limparFiltrosMaterial() {
    _materialIdCtrl.clear();
    _materialNomeCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _espessuraCtrl.clear();
    setState(() {
      _dataInicio = null;
      _dataFim    = null;
    });
    _aplicarFiltros();
  }

  bool get _temFiltroData => _dataInicio != null || _dataFim != null;

  bool get _temFiltroMaterial =>
      _materialIdCtrl.text.isNotEmpty ||
      _materialNomeCtrl.text.isNotEmpty ||
      _identificadorCtrl.text.isNotEmpty ||
      _medidaCtrl.text.isNotEmpty ||
      _espessuraCtrl.text.isNotEmpty ||
      _temFiltroData;

  void _abrirDetalhe(RelacaoOSModel rel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RelatorioDetalhe(numeroOS: rel.numeroOS),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RelatorioOSProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ───────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relatórios de OS',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ordens de Serviço encerradas',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  onPressed: () => context.read<RelatorioOSProvider>().carregar(),
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
            // ── Filtro linha 1: busca OS + nome material + botão limpar
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscaOSCtrl,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
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
                    controller: _materialNomeCtrl,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                    decoration: InputDecoration(
                      hintText: 'Nome do material...',
                      prefixIcon: Icon(Icons.filter_alt_outlined,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(
                    Icons.filter_alt_off,
                    color: _temFiltroMaterial
                        ? AppTheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: _temFiltroMaterial ? _limparFiltrosMaterial : null,
                  style: IconButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Filtro linha 2: ID + identificador + medida + espessura
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _materialIdCtrl,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: 'ID mat...',
                      prefixIcon: Icon(Icons.tag,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Identificador...',
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
                    onChanged: _onChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Medida...',
                      prefixIcon: Icon(Icons.straighten,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Espessura...',
                      prefixIcon: Icon(Icons.layers,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Filtro linha 3: período de fechamento ────────────────────────
            Row(
              children: [
                _DatePickerField(
                  label: 'Criado de',
                  value: _dataInicio,
                  firstDate: DateTime(2020),
                  lastDate: _dataFim ?? DateTime.now(),
                  onPicked: (d) {
                    setState(() => _dataInicio = d);
                    _aplicarFiltros();
                  },
                  onCleared: () {
                    setState(() => _dataInicio = null);
                    _aplicarFiltros();
                  },
                ),
                const SizedBox(width: 12),
                _DatePickerField(
                  label: 'até',
                  value: _dataFim,
                  firstDate: _dataInicio ?? DateTime(2020),
                  lastDate: DateTime.now(),
                  onPicked: (d) {
                    setState(() => _dataFim = d);
                    _aplicarFiltros();
                  },
                  onCleared: () {
                    setState(() => _dataFim = null);
                    _aplicarFiltros();
                  },
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),

            // ── Barra de resumo: contagem + total geral filtrado ─────────────
            if (!provider.carregando && provider.erro == null && provider.relatorios.isNotEmpty)
              Builder(
                builder: (_) {
                  final total = provider.relatorios.fold<double>(
                    0,
                    (acc, rel) => acc + _totalLiquido(rel.movimentacoes),
                  );
                  final qtd = provider.relatorios.length;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color:        _corFechada.withValues(alpha: 0.07),
                      border:       Border.all(color: _corFechada.withValues(alpha: 0.25)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.summarize_outlined, size: 16, color: _corFechada.withValues(alpha: 0.8)),
                        SizedBox(width: 8),
                        Text(
                          '$qtd ${qtd == 1 ? 'OS' : 'OS'} encontrada${qtd == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Spacer(),
                        if (total > 0) ...[
                          Text(
                            'Total filtrado:',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _brl(total),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _corFechada,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

            // ── Conteúdo ────────────────────────────────────────────
            Expanded(
              child: provider.carregando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : provider.erro != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_outlined,
                                  size: 48, color: AppTheme.error),
                              SizedBox(height: 12),
                              Text(
                                'Erro ao carregar relatórios',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                provider.erro!.contains(': ')
                                    ? provider.erro!.substring(
                                        provider.erro!.indexOf(': ') + 2)
                                    : provider.erro!,
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
                        )
                      : provider.relatorios.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.description_outlined,
                                    size: 48,
                                    color: Theme.of(context).colorScheme.outline
                                        .withValues(alpha: 0.4),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    provider.temFiltroMaterial
                                        ? 'Nenhuma OS com este material'
                                        : 'Nenhuma OS fechada',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color: Theme.of(context).colorScheme.outline),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    provider.temFiltroMaterial
                                        ? 'Tente ajustar os filtros de material'
                                        : 'As OS fechadas aparecerão aqui',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Theme.of(context).colorScheme.outline
                                                .withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            )
                          : _RelatorioOSGrid(
                              relatorios: provider.relatorios,
                              onTap: _abrirDetalhe,
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper: verifica se a OS é numérica (mesmo critério do controle) ─────────

bool _osEhNumerica(String numeroOS) => int.tryParse(numeroOS.trim()) != null;

// ─── Grid de OS (separado em numéricas × descritivas) ────────────────────────

class _RelatorioOSGrid extends StatelessWidget {
  final List<RelacaoOSModel> relatorios;
  final void Function(RelacaoOSModel) onTap;

  const _RelatorioOSGrid({
    required this.relatorios,
    required this.onTap,
  });

  SliverToBoxAdapter _cabecalho(BuildContext context, String titulo, int count) =>
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
    final numericas = relatorios
        .where((r) => _osEhNumerica(_limparNumeroOS(r.numeroOS)))
        .toList();
    final textuais = relatorios
        .where((r) => !_osEhNumerica(_limparNumeroOS(r.numeroOS)))
        .toList();

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 220,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1,
    );

    return CustomScrollView(
      slivers: [
        if (numericas.isNotEmpty) ...[
          _cabecalho(context, 'Ordens de Serviço', numericas.length),
          SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final rel = numericas[i];
                return _RelatorioOSCard(
                  relatorio: rel,
                  onTap: () => onTap(rel),
                );
              },
              childCount: numericas.length,
            ),
            gridDelegate: gridDelegate,
          ),
        ],
        if (textuais.isNotEmpty) ...[
          _cabecalho(context, 'Empresa', textuais.length),
          SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final rel = textuais[i];
                return _RelatorioOSCard(
                  relatorio: rel,
                  onTap: () => onTap(rel),
                );
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

// ─── Card de OS fechada ────────────────────────────────────────────────────────

class _RelatorioOSCard extends StatelessWidget {
  final RelacaoOSModel relatorio;
  final VoidCallback onTap;

  const _RelatorioOSCard({required this.relatorio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Data representativa = primeira movimentação (criação real da OS)
    final todasMovs = relatorio.movimentacoes;
    DateTime? dataRepresentativa;
    if (todasMovs.isNotEmpty) {
      dataRepresentativa = todasMovs
          .map((m) => m.criadoEm)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (min, d) => min == null || d.isBefore(min) ? d : min);
    }
    dataRepresentativa ??= relatorio.criadoEm;
    final dataStr = _fmtData(dataRepresentativa);

    final saidas = relatorio.movimentacoes
        .where((m) => m.tipo == 'SAIDA')
        .toList();
    final entradas = relatorio.movimentacoes
        .where((m) => m.tipo == 'ENTRADA')
        .toList();

    final totalGeral = _totalLiquido(relatorio.movimentacoes);
    final materiaisUnicos =
        relatorio.movimentacoes.map((m) => m.materialNome).toSet().length;

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
              // Ícone + badge FECHADA
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _corFechada.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.task_alt,
                        color: _corFechada, size: 20),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _corFechada.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _corFechada.withValues(alpha: 0.35)),
                    ),
                    child: const Text(
                      'Fechada',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _corFechada,
                      ),
                    ),
                  ),
                ],
              ),
              // Info
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tituloOS(relatorio.numeroOS),
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
                  if (entradas.isNotEmpty)
                    Text(
                      '${entradas.length} entrada(s). · ${saidas.length} saída(s).',
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  if (totalGeral > 0)
                    Text(
                      _brl(totalGeral),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _corFechada,
                      ),
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

// ═════════════════════════════════════════════════════════════════════════════
// Tela de detalhe da OS fechada
// ═════════════════════════════════════════════════════════════════════════════

class _RelatorioDetalhe extends StatefulWidget {
  final String numeroOS;
  const _RelatorioDetalhe({required this.numeroOS});

  @override
  State<_RelatorioDetalhe> createState() => _RelatorioDetalheState();
}

class _RelatorioDetalheState extends State<_RelatorioDetalhe> {
  bool _gerandoPdf = false;
  bool _revertendo = false;

  String get _titulo => _tituloOS(widget.numeroOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RelatorioOSProvider>().selecionar(widget.numeroOS);
    });
  }

  // ── Reverter OS ──────────────────────────────────────────────────────────
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
            child: const Icon(
              Icons.undo_rounded,
              color: corReverter,
              size: 20,
            ),
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
            'Deseja reverter "$_titulo" para Em Andamento?',
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

  final relProvider = context.read<RelatorioOSProvider>();
  final estoqueProvider = context.read<EstoqueProvider>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  setState(() => _revertendo = true);

  final ok = await relProvider.reverterOS(widget.numeroOS);

  if (!mounted) return;

  setState(() => _revertendo = false);

  if (ok) {
    estoqueProvider.carregarRelacoesOS();

    navigator.pop();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$_titulo revertida — disponível em Controle de Estoque',
        ),
        backgroundColor: corReverter,
      ),
    );
  } else {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          relProvider.erro ?? 'Erro ao reverter OS',
        ),
        backgroundColor: AppTheme.error,
      ),
    );
  }
}

  // ── Gera PDF via backend (mesmo esquema do Estoque) ──────────────────────

  Future<void> _gerarPDF() async {
    setState(() => _gerandoPdf = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 3),
        backgroundColor: AppTheme.primary,
      ),
    );

    try {
      // Chama o endpoint /:numeroOS/pdf — retorna os bytes do PDF
      final bytes = await EstoqueRepository()
          .baixarRelatorioOSPdf(widget.numeroOS);

      // Valida magic bytes PDF (%PDF)
      if (bytes.length < 4 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46) {
        throw Exception(
            'O servidor não retornou um PDF válido. Verifique o console do backend.');
      }

      // Salva em arquivo temporário
      final numeroLimpo =
          _limparNumeroOS(widget.numeroOS).replaceAll(RegExp(r'\W'), '_');
      final fileName = 'relatorio_os_$numeroLimpo.pdf';
      final dir      = await getTemporaryDirectory();
      final file     = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      // Abre com o programa padrão do SO
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _gerandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RelatorioOSProvider>();
    final rel = provider.selecionado;

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
            Text(_titulo),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _corFechada.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _corFechada.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'Fechada',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _corFechada,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (rel != null) ...[
            // Botão Reverter OS
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
            const SizedBox(width: 4),
            // Botão Gerar PDF
            _gerandoPdf
                ? const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _corFechada),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _gerarPDF,
                    icon: const Icon(Icons.picture_as_pdf_outlined,
                        size: 18, color: _corFechada),
                    label: const Text(
                      'Gerar PDF',
                      style: TextStyle(
                        color: _corFechada,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ],  // fecha if (rel != null)
        ],
      ),
      body: provider.carregandoDetalhe
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : rel == null
              ? Center(
                  child: Text(
                    'Relatório não encontrado',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : _RelatorioDetalheBody(rel: rel),
    );
  }
}

// ─── Body do detalhe ──────────────────────────────────────────────────────────

class _RelatorioDetalheBody extends StatelessWidget {
  final RelacaoOSModel rel;
  const _RelatorioDetalheBody({required this.rel});

  @override
  Widget build(BuildContext context) {
    final saidas =
        rel.movimentacoes.where((m) => m.tipo == 'SAIDA').toList();
    final entradas =
        rel.movimentacoes.where((m) => m.tipo == 'ENTRADA').toList();

    final totalGeral = _totalLiquido(rel.movimentacoes);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cards de resumo ──────────────────────────────────────
          Row(
            children: [
              _SummaryCard(
                icon: Icons.output_rounded,
                label: 'Saídas',
                valor: '${saidas.length}',
                cor: AppTheme.error,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                icon: Icons.input_rounded,
                label: 'Entradas',
                valor: '${entradas.length}',
                cor: AppTheme.primary,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                icon: Icons.attach_money_rounded,
                label: 'Total em saídas',
                valor: _brl(totalGeral),
                cor: _corFechada,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                icon: Icons.calendar_today_outlined,
                label: 'Criada em',
                valor: () {
                  final movs = rel.movimentacoes;
                  if (movs.isEmpty) return _fmtData(rel.criadoEm);
                  final primeira = movs
                      .map((m) => m.criadoEm)
                      .whereType<DateTime>()
                      .fold<DateTime?>(null, (min, d) => min == null || d.isBefore(min) ? d : min);
                  return _fmtData(primeira ?? rel.criadoEm);
                }(),
                cor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              _SummaryCard(
                icon: Icons.lock_outline_rounded,
                label: 'Fechada em',
                valor: _fmtData(rel.atualizadoEm ?? rel.criadoEm),
                cor: AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Saídas ───────────────────────────────────────────────
          _MovimentacaoSection(
            titulo: 'Saídas de material',
            icone: Icons.output_rounded,
            cor: AppTheme.error,
            movimentacoes: saidas,
            mostrarPreco: true,
          ),

          // ── Entradas ─────────────────────────────────────────────
          if (entradas.isNotEmpty) ...[
            const SizedBox(height: 16),
            _MovimentacaoSection(
              titulo: 'Entradas de material',
              icone: Icons.input_rounded,
              cor: AppTheme.primary,
              movimentacoes: entradas,
              mostrarPreco: true,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Card de resumo ────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valor;
  final Color cor;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.valor,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: cor, size: 18),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valor,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cor,
                      ),
                      overflow: TextOverflow.ellipsis,
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

// ─── Seção de movimentações ───────────────────────────────────────────────────

class _MovimentacaoSection extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final List<MovimentacaoModel> movimentacoes;
  final bool mostrarPreco;

  const _MovimentacaoSection({
    required this.titulo,
    required this.icone,
    required this.cor,
    required this.movimentacoes,
    required this.mostrarPreco,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho da seção
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icone, color: cor, size: 16),
                ),
                SizedBox(width: 10),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Spacer(),
                Text(
                  '${movimentacoes.length} '
                  '${movimentacoes.length == 1 ? 'item' : 'itens'}',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cabeçalho da tabela
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Material',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'Qtd.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (mostrarPreco) ...[
                    SizedBox(
                      width: 90,
                      child: Text(
                        'Unit.',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        'M²',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text(
                        'Total',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Data',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 12, color: Theme.of(context).colorScheme.outlineVariant),

            // Linhas
            ...List.generate(movimentacoes.length, (i) {
              final m   = movimentacoes[i];
              final pu  = (m.precoUnitario != null && m.precoUnitario! > 0) ? m.precoUnitario! : null;
              final pm2 = (m.precoM2       != null && m.precoM2!       > 0) ? m.precoM2!       : null;
              // Total usa o preço efetivo (pu tem prioridade; fallback pm2)
              final precoEfetivo = pu ?? pm2 ?? 0.0;
              final total = precoEfetivo * m.quantidade;
              final qtdStr = m.quantidade % 1 == 0
                  ? m.quantidade.toStringAsFixed(0)
                  : m.quantidade.toStringAsFixed(2);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 9),
                    child: Row(
                      children: [
                        // Material
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.materialNome,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if ((m.materialUnidade ?? '').isNotEmpty)
                                Text(
                                  m.materialUnidade!,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              // Identificador / medida / espessura
                              if ([
                                    m.materialIdentificador,
                                    m.materialMedida,
                                    m.materialEspessura,
                                  ].any((v) => v != null && v.isNotEmpty))
                                Text(
                                  [
                                    if ((m.materialIdentificador ?? '').isNotEmpty)
                                      m.materialIdentificador!,
                                    if ((m.materialMedida ?? '').isNotEmpty)
                                      m.materialMedida!,
                                    if ((m.materialEspessura ?? '').isNotEmpty)
                                      m.materialEspessura!,
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (m.observacao != null &&
                                  m.observacao!.isNotEmpty)
                                Text(
                                  m.observacao!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.outline,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        // Quantidade
                        SizedBox(
                          width: 80,
                          child: Text(
                            '$qtdStr ${m.materialUnidade ?? ''}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                        // Preço — colunas separadas Unit. | M² | Total
                        if (mostrarPreco) ...[
                          SizedBox(
                            width: 90,
                            child: Text(
                              pu != null ? _brl(pu) : '—',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text(
                              pm2 != null ? _brl(pm2) : '—',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              total > 0 ? _brl(total) : '—',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                        // Data
                        SizedBox(
                          width: 90,
                          child: Text(
                            _fmtData(m.criadoEm),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < movimentacoes.length - 1)
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                ],
              );
            }),

            // Rodapé com total
            if (mostrarPreco) ...[
              Divider(height: 16, color: Theme.of(context).colorScheme.outlineVariant),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Spacer(),
                    Text(
                      'Total geral',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _brl(movimentacoes.fold(0.0, (acc, m) {
                        // rodapé da tabela: soma bruta das linhas exibidas
                        // (já filtradas por tipo pela chamada — só saídas chegam aqui)
                        final pu = m.precoUnitario ?? 0.0;
                        final pm = m.precoM2 ?? 0.0;
                        final p  = pu > 0 ? pu : (pm > 0 ? pm : 0.0);
                        return acc + p * m.quantidade;
                      })),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _corFechada,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Widget auxiliar — seletor de data com chip clicável
// ═════════════════════════════════════════════════════════════════════════════

class _DatePickerField extends StatelessWidget {
  final String    label;
  final DateTime? value;
  final DateTime  firstDate;
  final DateTime  lastDate;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback           onCleared;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onPicked,
    required this.onCleared,
  });

  Future<void> _pick(BuildContext context) async {
    final now     = DateTime.now();
    final initial = value != null
        ? (value!.isAfter(lastDate) ? lastDate : value!)
        : (now.isBefore(lastDate) ? now : lastDate);
    final picked = await showDatePicker(
      context:     context,
      initialDate: initial,
      firstDate:   firstDate,
      lastDate:    lastDate,
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:  Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: hasValue ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size:  16,
              color: hasValue ? AppTheme.primary : Theme.of(context).colorScheme.outline,
            ),
            SizedBox(width: 6),
            Text(
              hasValue ? '$label: ${_fmtData(value)}' : label,
              style: TextStyle(
                fontSize:   13,
                color:      hasValue ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (hasValue) ...[
              SizedBox(width: 6),
              GestureDetector(
                onTap: onCleared,
                child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}