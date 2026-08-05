import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/solicitacao_material_model.dart';
import '../providers/solicitacao_material_provider.dart';
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

/// Formata uma quantidade sem arredondar/cortar a precisão real do valor,
/// aplicando separador de milhar (ponto) na parte inteira e vírgula como
/// separador decimal (padrão brasileiro).
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
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

// ── Status visual de compra/estoque (mesmo padrão da tela principal) ──────

class _StatusVisual {
  final Color cor;
  final IconData icone;
  final String label;
  const _StatusVisual(this.cor, this.icone, this.label);
}

_StatusVisual _statusVisual(String status) {
  switch (status) {
    case 'COMPRADO':
      return const _StatusVisual(AppTheme.success, Icons.shopping_cart, 'COMPRADO');
    case 'ESTOQUE':
      return const _StatusVisual(Colors.blue, Icons.inventory_2, 'ESTOQUE');
    default:
      return const _StatusVisual(AppTheme.primary, Icons.schedule, 'PENDENTE');
  }
}

// ── Status visual do andamento da solicitação (mesmo padrão da tela principal) ──

({Color bg, Color fg, String label}) _andamentoEstilo(String status) {
  switch (status) {
    case 'EM_ANDAMENTO':
      return (
        bg: const Color(0xFFD97706).withValues(alpha: 0.1),
        fg: const Color(0xFFD97706),
        label: 'EM ANDAMENTO',
      );
    case 'EM_NEGOCIACAO':
      return (
        bg: const Color(0xFF2563EB).withValues(alpha: 0.1),
        fg: const Color(0xFF2563EB),
        label: 'EM NEGOCIAÇÃO',
      );
    case 'FINALIZADO':
      return (
        bg: const Color(0xFF15803D).withValues(alpha: 0.1),
        fg: const Color(0xFF15803D),
        label: 'FINALIZADO',
      );
    default:
      return (
        bg: const Color(0xFF6B7280).withValues(alpha: 0.1),
        fg: const Color(0xFF6B7280),
        label: status,
      );
  }
}

// ── Formatação de valores de log (antes/depois) ────────────────────────────

const _camposLabel = {
  'numeroOS': 'Número OS',
  'nomeCliente': 'Cliente',
  'dataNecessidade': 'Data Necessidade',
  'andamento': 'Andamento',
  'observacao': 'Observação',
  'quantidade': 'Quantidade',
};

String _fmtValorLog(dynamic v) {
  if (v == null) return '—';
  final s = v.toString();
  try {
    final d = DateTime.parse(s).toLocal();
    return '${_fmtData(d)} ${_fmtHora(d)}';
  } catch (_) {}
  return s.isEmpty ? '—' : s;
}

String? _fmtNumeroLog(dynamic v) {
  final n = v is num ? v : num.tryParse(v.toString());
  if (n == null) return null;
  return _formatarQuantidade(n.toDouble());
}

/// Quantidade + unidade a partir do snapshot de material salvo no log
/// (ex: "25 m/l", "1 Unidade").
String? _qtdComUnidadeLog(Map material) {
  final qtd = material['quantidade'];
  if (qtd == null) return null;
  final qtdFmt = _fmtNumeroLog(qtd);
  if (qtdFmt == null) return null;
  final unidade = material['materialUnidade']?.toString().trim();
  return unidade != null && unidade.isNotEmpty
      ? '$qtdFmt ${formatarUnidadeExibicao(unidade)}'
      : qtdFmt;
}

/// Nome + detalhes (medida/espessura) de um material salvo no log — ex:
/// "ACRÍLICO TESTE (2mm)".
String _nomeMaterialLog(Map material) {
  final nome = material['materialNome']?.toString().trim();
  if (nome == null || nome.isEmpty) return '';
  final detalhes = <String>[];
  final medida = material['materialMedida']?.toString().trim();
  if (medida != null && medida.isNotEmpty) detalhes.add(medida);
  final espessura = material['materialEspessura']?.toString().trim();
  if (espessura != null && espessura.isNotEmpty) detalhes.add(espessura);
  if (detalhes.isEmpty) return nome;
  return '$nome (${detalhes.join(' · ')})';
}

// ── Classificação do log de edição ─────────────────────────────────────────

enum _TipoLog { criacao, adicao, remocao, edicao }

_TipoLog _tipoDoLog(LogEdicaoSolicitacaoModel log) {
  if (log.depois['excluido'] == true) return _TipoLog.remocao;
  if (log.depois['criada'] == true) return _TipoLog.criacao;
  if (log.depois['adicionado'] == true) return _TipoLog.adicao;
  return _TipoLog.edicao;
}

/// Campos que mudaram entre `antes` e `depois` — vazio para eventos
/// especiais (criação/adição/remoção), que têm exibição própria.
List<String> _camposAlterados(LogEdicaoSolicitacaoModel log) {
  if (_tipoDoLog(log) != _TipoLog.edicao) return const [];
  final campos = <String>[];
  for (final key in log.depois.keys) {
    final antes = log.antes[key]?.toString();
    final depois = log.depois[key]?.toString();
    if (antes != depois) campos.add(key);
  }
  return campos;
}

// ── Filtro por status do material ──────────────────────────────────────────

enum _FiltroStatus { todos, pendente, comprado, estoque }

// ── Evento genérico da timeline: pode ser um material (item/adicional) ou
// um evento de edição (log). Unifica os dois para que possam ser ordenados,
// agrupados por dia e renderizados juntos numa única lista.

abstract class _Evento {
  DateTime get data;
  SolicitacaoMaterialModel get solicitacao;
}

class _EventoMaterial extends _Evento {
  final _ItemHistorico item;
  _EventoMaterial(this.item);
  @override
  DateTime get data => item.dataReferencia;
  @override
  SolicitacaoMaterialModel get solicitacao => item.solicitacao;
}

class _EventoEdicao extends _Evento {
  final LogEdicaoSolicitacaoModel log;
  @override
  final SolicitacaoMaterialModel solicitacao;
  _EventoEdicao(this.log, this.solicitacao);
  @override
  DateTime get data => log.editadoEm;
}

// ── Item flatten: um material (original ou adicional) + a solicitação a
// que ele pertence. Normaliza os dois modelos (ItemSolicitacaoModel e
// AdicionalSolicitacaoModel) em um único formato, já que eles compartilham
// praticamente todos os campos relevantes para exibição.

class _ItemHistorico {
  final SolicitacaoMaterialModel solicitacao;
  final bool isAdicional;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final double quantidade;
  final String? observacao;
  final String statusCompra;
  final DateTime? compradoEm;
  final String? compradoPorNome;
  final DateTime? estoqueEm;
  final String? estoquePorNome;
  final DateTime dataReferencia; // data usada para ordenar/agrupar

  _ItemHistorico({
    required this.solicitacao,
    required this.isAdicional,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    required this.quantidade,
    this.observacao,
    required this.statusCompra,
    this.compradoEm,
    this.compradoPorNome,
    this.estoqueEm,
    this.estoquePorNome,
    required this.dataReferencia,
  });

  factory _ItemHistorico.deItem(SolicitacaoMaterialModel sol, ItemSolicitacaoModel i) {
    return _ItemHistorico(
      solicitacao: sol,
      isAdicional: false,
      materialNome: i.materialNome,
      materialUnidade: i.materialUnidade,
      materialIdentificador: i.materialIdentificador,
      quantidade: i.quantidade,
      observacao: i.observacao,
      statusCompra: i.statusCompra,
      compradoEm: i.compradoEm,
      compradoPorNome: i.compradoPorNome,
      estoqueEm: i.estoqueEm,
      estoquePorNome: i.estoquePorNome,
      dataReferencia: i.estoqueEm ?? i.compradoEm ?? i.criadoEm,
    );
  }

  factory _ItemHistorico.deAdicional(SolicitacaoMaterialModel sol, AdicionalSolicitacaoModel a) {
    return _ItemHistorico(
      solicitacao: sol,
      isAdicional: true,
      materialNome: a.materialNome,
      materialUnidade: a.materialUnidade,
      materialIdentificador: a.materialIdentificador,
      quantidade: a.quantidade,
      observacao: a.observacao,
      statusCompra: a.statusCompra,
      compradoEm: a.compradoEm,
      compradoPorNome: a.compradoPorNome,
      estoqueEm: a.estoqueEm,
      estoquePorNome: a.estoquePorNome,
      dataReferencia: a.estoqueEm ?? a.compradoEm ?? a.adicionadoEm,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class HistoricoSolicitacoesPage extends StatefulWidget {
  const HistoricoSolicitacoesPage({super.key});

  @override
  State<HistoricoSolicitacoesPage> createState() => _HistoricoSolicitacoesPageState();
}

class _HistoricoSolicitacoesPageState extends State<HistoricoSolicitacoesPage> {
  final TextEditingController _buscaOSCtrl = TextEditingController();
  final TextEditingController _buscaClienteCtrl = TextEditingController();
  final TextEditingController _buscaMaterialCtrl = TextEditingController();
  Timer? _debounceTimer;

  _FiltroStatus _filtroStatus = _FiltroStatus.todos;
  String? _filtroAndamento; // null = todos
  DateTime? _dataInicio;
  DateTime? _dataFim;

  // Logs de edição de cada solicitação, buscados à parte (o endpoint de
  // listagem não os inclui) e mesclados na timeline junto com os materiais.
  final Map<int, List<LogEdicaoSolicitacaoModel>> _logsPorSolicitacao = {};
  bool _carregandoLogs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregarTudo());
  }

  @override
  void dispose() {
    _buscaOSCtrl.dispose();
    _buscaClienteCtrl.dispose();
    _buscaMaterialCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Recarrega a lista de solicitações e, em seguida, busca os logs de
  /// edição de cada uma (em paralelo) para montar a timeline completa.
  Future<void> _carregarTudo() async {
    final provider = context.read<SolicitacaoMaterialProvider>();
    await provider.carregar();
    if (!mounted) return;

    setState(() => _carregandoLogs = true);
    final solicitacoes = provider.solicitacoes;
    final resultados = await Future.wait(
      solicitacoes.map((s) => provider.buscarLogsSemAlterarEstado(s.id)),
    );
    if (!mounted) return;
    setState(() {
      _logsPorSolicitacao
        ..clear()
        ..addEntries(
          List.generate(solicitacoes.length, (i) => MapEntry(solicitacoes[i].id, resultados[i])),
        );
      _carregandoLogs = false;
    });
  }

  void _onFiltroDigitado(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  void _limparFiltros() {
    _buscaOSCtrl.clear();
    _buscaClienteCtrl.clear();
    _buscaMaterialCtrl.clear();
    setState(() {
      _filtroStatus = _FiltroStatus.todos;
      _filtroAndamento = null;
      _dataInicio = null;
      _dataFim = null;
    });
  }

  /// true se um evento com o nome de material [nomeMaterial] (pode ser
  /// vazio/nulo) deve passar pelo filtro de texto de material.
  bool _passaFiltroMaterial(String filtro, String? nomeMaterial) {
    if (filtro.isEmpty) return true;
    if (nomeMaterial == null) return false;
    return nomeMaterial.toLowerCase().contains(filtro);
  }

  List<_Evento> _itensFiltrados(List<SolicitacaoMaterialModel> solicitacoes) {
    final os = _buscaOSCtrl.text.trim().toUpperCase();
    final cliente = _buscaClienteCtrl.text.trim().toLowerCase();
    final material = _buscaMaterialCtrl.text.trim().toLowerCase();
    final statusAtivo = _filtroStatus != _FiltroStatus.todos;

    final eventos = <_Evento>[];
    for (final sol in solicitacoes) {
      if (_filtroAndamento != null && sol.andamento != _filtroAndamento) continue;
      if (os.isNotEmpty && !sol.numeroOS.toUpperCase().contains(os)) continue;
      if (cliente.isNotEmpty && !sol.nomeCliente.toLowerCase().contains(cliente)) continue;

      // ── Materiais (itens originais + adicionais) ──────────────────────
      final materiais = <_ItemHistorico>[
        ...sol.itens.map((i) => _ItemHistorico.deItem(sol, i)),
        ...sol.adicionais.map((a) => _ItemHistorico.deAdicional(sol, a)),
      ];
      for (final item in materiais) {
        if (_filtroStatus == _FiltroStatus.pendente && item.statusCompra != 'PENDENTE') continue;
        if (_filtroStatus == _FiltroStatus.comprado && item.statusCompra != 'COMPRADO') continue;
        if (_filtroStatus == _FiltroStatus.estoque && item.statusCompra != 'ESTOQUE') continue;
        if (!_passaFiltroMaterial(material, item.materialNome)) continue;
        if (_dataInicio != null && item.dataReferencia.isBefore(_dataInicio!)) continue;
        if (_dataFim != null) {
          final fimDoDia = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day, 23, 59, 59);
          if (item.dataReferencia.isAfter(fimDoDia)) continue;
        }
        eventos.add(_EventoMaterial(item));
      }

      // ── Edições (logs) ──────────────────────────────────────────────────
      // Eventos de edição não têm um "status de compra" próprio, então só
      // entram na timeline quando nenhum filtro de status está ativo.
      if (statusAtivo) continue;
      final logs = _logsPorSolicitacao[sol.id] ?? const [];
      for (final log in logs) {
        if (_dataInicio != null && log.editadoEm.isBefore(_dataInicio!)) continue;
        if (_dataFim != null) {
          final fimDoDia = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day, 23, 59, 59);
          if (log.editadoEm.isAfter(fimDoDia)) continue;
        }
        if (material.isNotEmpty) {
          final tipo = _tipoDoLog(log);
          final nomeDoItem = log.item;
          final nomesCriacao = tipo == _TipoLog.criacao && log.depois['materiais'] is List
              ? (log.depois['materiais'] as List)
                  .whereType<Map>()
                  .map((m) => m['materialNome']?.toString() ?? '')
                  .join(' ')
              : null;
          final nomeAdicionado = tipo == _TipoLog.adicao
              ? log.depois['materialNome']?.toString()
              : null;
          final candidato = [nomeDoItem, nomesCriacao, nomeAdicionado]
              .whereType<String>()
              .join(' ')
              .toLowerCase();
          if (!candidato.contains(material)) continue;
        }
        eventos.add(_EventoEdicao(log, sol));
      }
    }
    eventos.sort((a, b) => b.data.compareTo(a.data));
    return eventos;
  }

  Map<String, List<_Evento>> _agruparPorDia(List<_Evento> eventos) {
    final grupos = <String, List<_Evento>>{};
    for (final evento in eventos) {
      final chave = _fmtData(evento.data);
      grupos.putIfAbsent(chave, () => []).add(evento);
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

  void _abrirSolicitacao(SolicitacaoMaterialModel sol) {
    context.read<SolicitacaoMaterialProvider>().solicitarAberturaSolicitacao(sol.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SolicitacaoMaterialProvider>();
    final eventos = _itensFiltrados(provider.solicitacoes);
    final grupos = _agruparPorDia(eventos);
    final chavesOrdenadas = grupos.keys.toList(); // já em ordem desc pois eventos estão ordenados

    final materiaisEventos = eventos.whereType<_EventoMaterial>().map((e) => e.item);
    final totalPendentes = materiaisEventos.where((i) => i.statusCompra == 'PENDENTE').length;
    final totalComprados = materiaisEventos.where((i) => i.statusCompra == 'COMPRADO').length;
    final totalEstoque = materiaisEventos.where((i) => i.statusCompra == 'ESTOQUE').length;
    final totalEdicoes = eventos.whereType<_EventoEdicao>().length;
    final carregandoTudo = provider.carregando || _carregandoLogs;

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
                      'Histórico de Solicitações',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Todos os materiais de todas as solicitações, em ordem cronológica',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: carregandoTudo ? null : _carregarTudo,
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
                      prefixIcon: Icon(Icons.description_outlined,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _buscaClienteCtrl,
                    onChanged: _onFiltroDigitado,
                    decoration: InputDecoration(
                      hintText: 'Filtrar por cliente',
                      prefixIcon: Icon(Icons.person_outline,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _buscaMaterialCtrl,
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
                Builder(
                  builder: (context) {
                    final temFiltro = _buscaOSCtrl.text.isNotEmpty ||
                        _buscaClienteCtrl.text.isNotEmpty ||
                        _buscaMaterialCtrl.text.isNotEmpty ||
                        _filtroStatus != _FiltroStatus.todos ||
                        _filtroAndamento != null ||
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

            // ── Status do material + período + contadores ────────────────
            Row(
              children: [
                SegmentedButton<_FiltroStatus>(
                  segments: const [
                    ButtonSegment(
                      value: _FiltroStatus.todos,
                      label: Text('Todos'),
                      tooltip: 'Mostrar todos os status',
                    ),
                    ButtonSegment(
                      value: _FiltroStatus.pendente,
                      label: Text('Pendentes'),
                      tooltip: 'Mostrar apenas pendentes',
                    ),
                    ButtonSegment(
                      value: _FiltroStatus.comprado,
                      label: Text('Comprados'),
                      tooltip: 'Mostrar apenas comprados',
                    ),
                    ButtonSegment(
                      value: _FiltroStatus.estoque,
                      label: Text('Estoque'),
                      tooltip: 'Mostrar apenas retirados do estoque',
                    ),
                  ],
                  selected: {_filtroStatus},
                  onSelectionChanged: (s) => setState(() => _filtroStatus = s.first),
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
                    Icon(Icons.schedule, size: 14, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text('$totalPendentes pendentes',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 14),
                    const Icon(Icons.shopping_cart, size: 14, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text('$totalComprados comprados',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 14),
                    const Icon(Icons.inventory_2, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text('$totalEstoque no estoque',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 14),
                    Icon(Icons.edit_note, size: 14, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 4),
                    Text('$totalEdicoes edições',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Filtro por andamento da solicitação ────────────────────────
            Row(
              children: [
                Text('Andamento:',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                ...(<String?>[null, 'EM_ANDAMENTO', 'EM_NEGOCIACAO', 'FINALIZADO'].map((andamento) {
                  final selecionado = _filtroAndamento == andamento;
                  final label = andamento == null ? 'Todos' : _andamentoEstilo(andamento).label;
                  final cor = andamento == null
                      ? Theme.of(context).colorScheme.primary
                      : _andamentoEstilo(andamento).fg;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: andamento == null
                          ? 'Mostrar solicitações de todos os andamentos'
                          : 'Filtrar por andamento: $label',
                      child: FilterChip(
                        label: Text(label,
                            style: TextStyle(
                                fontSize: 12,
                                color: selecionado
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface)),
                        selected: selecionado,
                        onSelected: (_) => setState(() => _filtroAndamento = andamento),
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
              child: carregandoTudo && eventos.isEmpty
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
                                onPressed: _carregarTudo,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Tentar novamente'),
                                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                              ),
                            ],
                          ),
                        )
                      : eventos.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history,
                                      size: 48, color: Theme.of(context).colorScheme.outline),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nenhum evento encontrado',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: chavesOrdenadas.length,
                              itemBuilder: (context, i) {
                                final chave = chavesOrdenadas[i];
                                final eventosDoDia = grupos[chave]!;
                                final dataRef = eventosDoDia.first.data;
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
                                    ...eventosDoDia.map((evento) {
                                      if (evento is _EventoMaterial) {
                                        return _LinhaHistorico(
                                          item: evento.item,
                                          onTapOS: () => _abrirSolicitacao(evento.solicitacao),
                                        );
                                      }
                                      final edicao = evento as _EventoEdicao;
                                      return _LinhaEdicao(
                                        log: edicao.log,
                                        solicitacao: edicao.solicitacao,
                                        onTapOS: () => _abrirSolicitacao(edicao.solicitacao),
                                      );
                                    }),
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

// ── Linha de histórico ──────────────────────────────────────────────────────
// O card inteiro é clicável (abre a solicitação), com hover e cursor de mão,
// seguindo o mesmo padrão visual do histórico de movimentações de estoque.

// ── Larguras de coluna compartilhadas pela tabela (linhas de material e de
// edição usam exatamente as mesmas, para o cabeçalho alinhar com o corpo).

const double _colSolicitacaoW = 170;
const double _colAcaoW = 118;
const double _colUsuarioW = 130;
const double _colHoraW = 50;

/// Badge de ação (usado tanto para o status do material quanto para o tipo
/// de edição) — mesmo visual do badge de andamento, só que reutilizável.
Widget _badgeTabela(String label, Color cor, {double width = _colAcaoW}) {
  return SizedBox(
    width: width,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: cor.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
        ),
      ),
    ),
  );
}

/// Coluna "Solicitação": número da OS (clicável) + nome do cliente.
Widget _celulaSolicitacao(
  SolicitacaoMaterialModel sol,
  ColorScheme scheme, {
  required bool hovered,
}) {
  return SizedBox(
    width: _colSolicitacaoW,
    child: Tooltip(
      message: 'Abrir solicitação OS ${sol.numeroOS}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 13,
              color: hovered ? AppTheme.primary : scheme.outline),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sol.numeroOS,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0x66FF9800),
                  ),
                ),
                if (sol.nomeCliente.isNotEmpty)
                  Text(
                    sol.nomeCliente,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Coluna "Usuário": ícone de pessoa + nome de quem realizou a ação.
Widget _celulaUsuario(String? nome, ColorScheme scheme) {
  return SizedBox(
    width: _colUsuarioW,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_outline, size: 13, color: scheme.outline),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            nome ?? '—',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// Coluna "Hora".
Widget _celulaHora(DateTime dt, ColorScheme scheme) {
  return SizedBox(
    width: _colHoraW,
    child: Text(
      _fmtHora(dt),
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 12, color: scheme.outline),
    ),
  );
}

/// Cabeçalho fixo da tabela, alinhado com as mesmas larguras de coluna
/// usadas nas linhas de material e de edição.
class _CabecalhoTabela extends StatelessWidget {
  const _CabecalhoTabela();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estilo = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: scheme.outline,
      letterSpacing: 0.3,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: _colSolicitacaoW, child: Text('SOLICITAÇÃO', style: estilo)),
          SizedBox(width: _colAcaoW, child: Text('AÇÃO', style: estilo)),
          Expanded(flex: 3, child: Text('MATERIAL', style: estilo)),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: Text('ANTES / DEPOIS', style: estilo)),
          SizedBox(width: _colUsuarioW, child: Text('USUÁRIO', style: estilo)),
          SizedBox(width: _colHoraW, child: Text('', style: estilo)),
        ],
      ),
    );
  }
}

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
    final item = widget.item;
    final sol = item.solicitacao;
    final statusInfo = _statusVisual(item.statusCompra);
    final scheme = Theme.of(context).colorScheme;

    final qtdStr = _formatarQuantidade(item.quantidade);
    final temIdentificador =
        item.materialIdentificador != null && item.materialIdentificador!.isNotEmpty;

    // Quem realizou a última ação e quando, dependendo do status atual.
    String? responsavel;
    if (item.statusCompra == 'ESTOQUE') {
      responsavel = item.estoquePorNome;
    } else if (item.statusCompra == 'COMPRADO') {
      responsavel = item.compradoPorNome;
    } else {
      responsavel = sol.usuarioNome;
    }

    final bgColor = _hovered
        ? const Color(0xFFFF9800).withValues(alpha: 0.10)
        : scheme.surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
                    // ── 1. Solicitação ───────────────────────────────────
                    _celulaSolicitacao(sol, scheme, hovered: _hovered),
                    const SizedBox(width: 10),

                    // ── 2. Ação (status do material) ─────────────────────
                    _badgeTabela(statusInfo.label, statusInfo.cor),
                    const SizedBox(width: 10),

                    // ── 3. Material + quantidade ─────────────────────────
                    Expanded(
                      flex: 3,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (temIdentificador)
                              TextSpan(text: '${item.materialIdentificador!} · '),
                            TextSpan(text: item.materialNome),
                            if (item.isAdicional)
                              const TextSpan(
                                text: '  (adicional)',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            TextSpan(
                              text:
                                  '  ·  $qtdStr${item.materialUnidade != null ? ' ${formatarUnidadeExibicao(item.materialUnidade)}' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w400, color: Colors.grey),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // ── 4. Antes/depois (observação, quando houver) ──────
                    Expanded(
                      flex: 3,
                      child: item.observacao != null && item.observacao!.trim().isNotEmpty
                          ? Text(
                              item.observacao!,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 10),

                    // ── 5. Usuário ────────────────────────────────────────
                    _celulaUsuario(responsavel, scheme),

                    // ── 6. Hora ───────────────────────────────────────────
                    _celulaHora(item.dataReferencia, scheme),
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

// ── Linha de edição (log) ────────────────────────────────────────────────
// Mostra criação/adição/remoção de material ou alteração de campos (com
// diff antes/depois), no mesmo padrão visual usado na aba "Histórico" do
// diálogo de cada solicitação.

class _LinhaEdicao extends StatefulWidget {
  final LogEdicaoSolicitacaoModel log;
  final SolicitacaoMaterialModel solicitacao;
  final VoidCallback onTapOS;
  const _LinhaEdicao({required this.log, required this.solicitacao, required this.onTapOS});

  @override
  State<_LinhaEdicao> createState() => _LinhaEdicaoState();
}

class _LinhaEdicaoState extends State<_LinhaEdicao> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final sol = widget.solicitacao;
    final scheme = Theme.of(context).colorScheme;
    final tipo = _tipoDoLog(log);
    final campos = _camposAlterados(log);

    final Color cor;
    final String acaoLabel;
    switch (tipo) {
      case _TipoLog.criacao:
        cor = AppTheme.success;
        acaoLabel = 'CRIAR';
        break;
      case _TipoLog.adicao:
        cor = AppTheme.success;
        acaoLabel = 'ADICIONAR';
        break;
      case _TipoLog.remocao:
        cor = AppTheme.error;
        acaoLabel = 'REMOVER';
        break;
      case _TipoLog.edicao:
        cor = AppTheme.primary;
        acaoLabel = 'EDITAR';
        break;
    }

    // Materiais envolvidos no evento (criação pode ter vários; adição, um só).
    final materiaisCriacao = tipo == _TipoLog.criacao && log.depois['materiais'] is List
        ? (log.depois['materiais'] as List)
            .whereType<Map>()
            .where((m) => _nomeMaterialLog(m).isNotEmpty)
            .toList()
        : const <Map>[];
    final materialAdicionado = tipo == _TipoLog.adicao ? log.depois : null;

    final bgColor = _hovered
        ? const Color(0xFFFF9800).withValues(alpha: 0.10)
        : scheme.surface;

    // ── Conteúdo da coluna "Material" ─────────────────────────────────────
    Widget colunaMaterial;
    if (materiaisCriacao.isNotEmpty) {
      colunaMaterial = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in materiaisCriacao)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _linhaMaterialLogCompacta(m),
            ),
        ],
      );
    } else if (materialAdicionado != null) {
      colunaMaterial = _linhaMaterialLogCompacta(materialAdicionado);
    } else if (log.item != null && log.item!.isNotEmpty) {
      colunaMaterial = Text(
        log.item!,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      );
    } else {
      colunaMaterial = Text(
        '—',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      );
    }

    // ── Conteúdo da coluna "Antes / Depois" ───────────────────────────────
    Widget colunaAntesDepois;
    if (campos.isNotEmpty) {
      colunaAntesDepois = Wrap(
        spacing: 12,
        runSpacing: 4,
        children: campos.map((campo) {
          final label = _camposLabel[campo] ?? campo;
          final antes = _fmtValorLog(log.antes[campo]);
          final depois = _fmtValorLog(log.depois[campo]);
          return RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                    text: 'antes ',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.error)),
                TextSpan(text: '$antes  '),
                const TextSpan(
                    text: 'depois ',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.success)),
                TextSpan(text: depois),
              ],
            ),
          );
        }).toList(),
      );
    } else {
      colunaAntesDepois = const SizedBox.shrink();
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
                    // ── 1. Solicitação ───────────────────────────────────
                    _celulaSolicitacao(sol, scheme, hovered: _hovered),
                    const SizedBox(width: 10),

                    // ── 2. Ação ───────────────────────────────────────────
                    _badgeTabela(acaoLabel, cor),
                    const SizedBox(width: 10),

                    // ── 3. Material + quantidade ─────────────────────────
                    Expanded(flex: 3, child: colunaMaterial),
                    const SizedBox(width: 10),

                    // ── 4. Antes / depois ─────────────────────────────────
                    Expanded(flex: 3, child: colunaAntesDepois),
                    const SizedBox(width: 10),

                    // ── 5. Usuário ────────────────────────────────────────
                    _celulaUsuario(log.editorNome, scheme),

                    // ── 6. Hora ───────────────────────────────────────────
                    _celulaHora(log.editadoEm, scheme),
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

/// Linha compacta de material (nome+detalhes em destaque, quantidade em
/// cinza) usada nos eventos de criação/adição de material.
Widget _linhaMaterialLogCompacta(Map material) {
  final nome = _nomeMaterialLog(material);
  final qtd = _qtdComUnidadeLog(material);
  return RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: nome,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.success),
        ),
        if (qtd != null && qtd.isNotEmpty)
          TextSpan(
            text: '  $qtd',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.grey),
          ),
      ],
    ),
  );
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
      onExit: (_) => setState(() => _hovered = false),
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