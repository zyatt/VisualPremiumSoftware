// historico_material_page.dart
//
// Contém:
//   1. HistoricoMaterialPage  — página completa com filtros, lista e diff
//   2. Botão "Histórico" para inserir na EstoqueCategoriaPage
//
// ─── Como integrar o botão na EstoqueCategoriaPage ───────────────────────────
// No cabeçalho da EstoqueCategoriaPage, ANTES do Consumer<MaterialProvider>
// (o botão "Orçar filtrados"), adicione:
//
//   OutlinedButton.icon(
//     onPressed: () => Navigator.of(context).push(
//       MaterialPageRoute(builder: (_) => const HistoricoMaterialPage()),
//     ),
//     icon: const Icon(Icons.history, size: 18),
//     label: const Text('Histórico'),
//     style: OutlinedButton.styleFrom(
//       foregroundColor: const Color(0xFFF59E0B),
//       side: const BorderSide(color: Color(0xFFF59E0B)),
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//     ),
//   ),
//   const SizedBox(width: 12),
//
// ─── Como registrar o provider ───────────────────────────────────────────────
// No main.dart, dentro do MultiProvider, adicione:
//   ChangeNotifierProvider(create: (_) => AuditLogProvider()),
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audit_log_model.dart';
import '../providers/audit_log_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// A partir de materialInfoLine, mantém apenas os segmentos que representam
/// dimensões (medida, espessura, comprimento, largura — sempre contêm algum
/// número), descartando categoria e unidade (que são apenas texto, ex.:
/// "unidade", "m²", "RETALHO").
String _dimensoesDoMaterial(String infoLine) {
  final s = infoLine.trim();
  if (s.isEmpty) return '';
  final soNumero = RegExp(r'^\d+([.,]\d+)?$');
  final partes = s
      .split(RegExp(r'[·•∙⋅]|(?<=\s)-(?=\s)'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty && RegExp(r'\d').hasMatch(p))
      // Segmento composto só por um número (ex.: "14") representa a
      // espessura em milímetros — acrescenta o sufixo "mm".
      .map((p) => soNumero.hasMatch(p) ? '${p}mm' : p)
      .toList();
  return partes.join(' · ');
}

/// Nome do campo exibido na coluna "Campo" do histórico. Quando o campo
/// alterado for "Espessura", acrescenta "(mm)" ao lado do texto.
String _nomeCampoExibicao(String? campo) {
  if (campo == null || campo.isEmpty) return '—';
  if (campo.trim().toLowerCase() == 'espessura') return '$campo (mm)';
  return campo;
}

/// Converte mensagens de erro técnicas em textos legíveis pelo usuário.
/// Trata especialmente erros de rede (SocketException / ClientException).
String _mensagemErroAmigavel(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('connection refused') ||
      lower.contains('recusou a conexão') ||
      lower.contains('errno')) {
    return 'Erro ao carregar o histórico.\nVerifique a conexão com o servidor.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'A conexão com o servidor expirou.\nVerifique a rede e tente novamente.';
  }
  // Remove prefixos técnicos como "Exception:", "HttpException:" etc.
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class HistoricoMaterialPage extends StatefulWidget {
  /// Se não-nulo, filtra automaticamente pelo material informado
  /// e exibe o nome no cabeçalho.
  final int?    materialIdInicial;
  final String? materialNomeInicial;

  const HistoricoMaterialPage({
    super.key,
    this.materialIdInicial,
    this.materialNomeInicial,
  });

  @override
  State<HistoricoMaterialPage> createState() => _HistoricoMaterialPageState();
}

class _HistoricoMaterialPageState extends State<HistoricoMaterialPage> {
  final _buscaCtrl      = TextEditingController();
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String    _acaoFiltro  = '';
  bool      _acaoHovered = false;
  Timer?    _debounce;

  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  static const _acoes = [
    ('',                   'Todas as ações'),
    ('CADASTRO',           'Cadastro'),
    ('EDICAO',             'Edição'),
    ('DESATIVACAO',        'Desativação'),
    ('REATIVACAO',         'Reativação'),
    ('EXCLUSAO',           'Exclusão'),
    ('ESTOQUE_CONFIRMADO', 'Estoque confirmado'),
    ('CUSTO_MANUAL',       'Custo manual'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _carregar() {
    setState(() => _paginaAtual = 0);
    context.read<AuditLogProvider>().carregar(
      materialId: widget.materialIdInicial,
      acao:       _acaoFiltro.isEmpty ? null : _acaoFiltro,
      busca:      widget.materialIdInicial != null
          ? null
          : (_buscaCtrl.text.trim().isEmpty ? null : _buscaCtrl.text.trim()),
      dataInicio: _dataInicio,
      dataFim:    _dataFim,
    );
  }

  Future<void> _selecionarData(bool isInicio) async {
    final picked = await showDatePicker(
      context:      context,
      initialDate:  isInicio
          ? (_dataInicio ?? DateTime.now())
          : (_dataFim    ?? DateTime.now()),
      firstDate:    DateTime(2020),
      lastDate:     DateTime.now().add(const Duration(days: 1)),
      locale:       const Locale('pt', 'BR'),
      builder: (context, child) {
        // Garante cursor de mão nos botões do diálogo — OK/Cancelar,
        // alternar modo de entrada (lápis/calendário) e navegação de
        // mês anterior/próximo — sem alterar cores/estilo já definidos
        // pelo tema do app.
        final baseTextStyle = Theme.of(context).textButtonTheme.style ?? const ButtonStyle();
        final baseIconStyle = Theme.of(context).iconButtonTheme.style ?? const ButtonStyle();
        return Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: baseTextStyle.copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: baseIconStyle.copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isInicio) {
        _dataInicio = picked;
      } else {
        _dataFim    = picked;
      }
    });
    _carregar();
  }

  String _formatarData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ────────────────────────────────────────────────────
            Row(
              children: [
                _BotaoVoltar(
                  label: 'Voltar',
                  tooltip: 'Voltar',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.history, color: Color(0xFFF59E0B), size: 20),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.materialNomeInicial != null
                          ? 'Histórico — ${widget.materialNomeInicial}'
                          : 'Histórico de Alterações',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cadastros, edições, desativações e exclusões de materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  onPressed: _carregar,
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Filtros ───────────────────────────────────────────────────────
            Row(
              children: [
                // Busca por nome de material (oculta quando filtra por material fixo)
                if (widget.materialIdInicial == null) ...[
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _buscaCtrl,
                      decoration: InputDecoration(
                        hintText:   'Buscar material',
                        prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
                        isDense:    true,
                        suffixIcon: _buscaCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _buscaCtrl.clear();
                                  _carregar();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 400), () {
                          _carregar();
                          setState(() {});
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Filtro de ação
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _acaoHovered = true),
                  onExit:  (_) => setState(() => _acaoHovered = false),
                  child: SizedBox(
                    width: 200,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                          hoverColor: Colors.transparent,
                          focusColor: Colors.transparent,
                        ),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _acaoFiltro,
                        decoration: InputDecoration(
                          labelText: 'Ação',
                          isDense:   true,
                          suffixIcon: Icon(
                            Icons.arrow_drop_down,
                            color: _acaoHovered
                                ? AppTheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          focusedBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
                        ),
                        mouseCursor: SystemMouseCursors.click,
                        icon: const SizedBox.shrink(),
                        items: _acoes
                            .map((a) => DropdownMenuItem(value: a.$1, child: Text(a.$2)))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _acaoFiltro = v ?? '');
                          _carregar();
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Data início
                _BotaoData(
                  label: _dataInicio != null
                      ? 'De: ${_formatarData(_dataInicio!)}'
                      : 'Data início',
                  tooltip: 'Selecionar data de início',
                  onTap: () => _selecionarData(true),
                  onClear: _dataInicio != null
                      ? () {
                          setState(() => _dataInicio = null);
                          _carregar();
                        }
                      : null,
                ),
                const SizedBox(width: 8),

                // Data fim
                _BotaoData(
                  label: _dataFim != null
                      ? 'Até: ${_formatarData(_dataFim!)}'
                      : 'Data fim',
                  tooltip: 'Selecionar data de fim',
                  onTap: () => _selecionarData(false),
                  onClear: _dataFim != null
                      ? () {
                          setState(() => _dataFim = null);
                          _carregar();
                        }
                      : null,
                ),
              ],
            ),
            SizedBox(height: 16),

            // ── Tabela ────────────────────────────────────────────────────────
            _CabecalhoTabela(mostrarMaterial: widget.materialIdInicial == null),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

            Expanded(
              child: Consumer<AuditLogProvider>(
                builder: (_, provider, __) {
                  if (provider.carregando) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
                    );
                  }
                  if (provider.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                          SizedBox(height: 12),
                          Text(
                            _mensagemErroAmigavel(provider.erro!),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _carregar,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ],
                      ),
                    );
                  }
                  if (provider.logs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off,
                              size: 56, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
                          SizedBox(height: 12),
                          Text(
                            'Nenhum registro encontrado',
                            style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  final todos        = provider.logs;
                  final totalPaginas = (todos.length / _itensPorPagina).ceil();
                  final paginaSegura = _paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
                  final inicio       = paginaSegura * _itensPorPagina;
                  final fim          = (inicio + _itensPorPagina).clamp(0, todos.length);
                  final paginados    = todos.sublist(inicio, fim);

                  return Column(
                    children: [
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (int i = 0; i < paginados.length; i++) ...[
                                  _LinhaLog(
                                    log:             paginados[i],
                                    mostrarMaterial: widget.materialIdInicial == null,
                                  ),
                                  if (i < paginados.length - 1)
                                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _BarraPaginacao(
                        paginaAtual:     paginaSegura,
                        totalPaginas:    totalPaginas,
                        totalItens:      todos.length,
                        itensPorPagina:  _itensPorPagina,
                        onPaginaChanged: (p) => setState(() => _paginaAtual = p),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

// ── Botão "voltar" com hover, cursor de mão e tooltip ───────────────────────
// Mesmo padrão usado no cabeçalho das páginas de estoque (_BotaoVoltar).
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

class _BotaoData extends StatelessWidget {
  final String    label;
  final String    tooltip;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _BotaoData({
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap:         onTap,
        mouseCursor:   SystemMouseCursors.click,
        borderRadius:  BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border:       Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
            color:        Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 14, color: Theme.of(context).colorScheme.outline),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              if (onClear != null) ...[
                SizedBox(width: 6),
                Tooltip(
                  message: 'Limpar filtro',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onClear,
                      child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.outline),
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

// ─────────────────────────────────────────────────────────────────────────────

class _CabecalhoTabela extends StatelessWidget {
  final bool mostrarMaterial;

  const _CabecalhoTabela({required this.mostrarMaterial});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          // Ação
          SizedBox(
            width: 96,
            child: Text('Ação',
                style: _estiloHeader(context)),
          ),
          // Material (só quando não está filtrado por material)
          if (mostrarMaterial)
            Expanded(
              flex: 4,
              child: Text('Material', style: _estiloHeader(context)),
            ),
          // Campo alterado
          SizedBox(
            width: 140,
            child: Text('Campo', style: _estiloHeader(context)),
          ),
          // Antes
          Expanded(
            flex: 2,
            child: Text('Antes', style: _estiloHeader(context)),
          ),
          // Depois
          Expanded(
            flex: 2,
            child: Text('Depois', style: _estiloHeader(context)),
          ),
          // Usuário
          SizedBox(
            width: 130,
            child: Text('Usuário', style: _estiloHeader(context)),
          ),
          // Data
          SizedBox(
            width: 130,
            child: Text('Data/Hora', style: _estiloHeader(context), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  static TextStyle _estiloHeader(BuildContext context) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Theme.of(context).colorScheme.outline,
    letterSpacing: 0.5,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _LinhaLog extends StatelessWidget {
  final AuditLogModel log;
  final bool          mostrarMaterial;

  const _LinhaLog({required this.log, required this.mostrarMaterial});

  @override
  Widget build(BuildContext context) {
    final dt = log.criadoEm.toLocal();
    final dataStr =
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    // Converte a string hex da cor em Color
    final corHex = log.acaoCor.replaceFirst('#', '');
    final cor = Color(int.parse('FF$corHex', radix: 16));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Badge de ação ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SizedBox(
              width: 96,
              child: _BadgeAcao(label: log.acaoLabel, cor: cor),
            ),
          ),

          // ── Nome do material ─────────────────────────────────────────────
          if (mostrarMaterial)
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    log.materialNome ?? '—',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_dimensoesDoMaterial(log.materialInfoLine).isNotEmpty ||
                      log.materialExcluido) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_dimensoesDoMaterial(log.materialInfoLine).isNotEmpty)
                          Flexible(
                            child: Text(
                              _dimensoesDoMaterial(log.materialInfoLine),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (log.materialExcluido) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'excluído',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // ── Campo alterado ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 140,
              child: Text(
                _nomeCampoExibicao(log.campo),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // ── Valor antes ─────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: log.valorAntes != null
                  ? _ValorChip(
                      valor: log.valorAntes!,
                      cor:   Color(0xFFDC2626),
                      bg:    Color(0xFFDC2626),
                    )
                  : Text('—',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
            ),
          ),

          // ── Valor depois ─────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: log.valorDepois != null
                  ? _ValorChip(
                      valor: log.valorDepois!,
                      cor:   Color(0xFF15803D),
                      bg:    Color(0xFF15803D),
                    )
                  : Text('—',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
            ),
          ),

          // ── Usuário ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 130,
              child: Text(
                log.usuarioNome ?? '—',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // ── Data ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 130,
              child: Text(
                dataStr,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BadgeAcao extends StatelessWidget {
  final String label;
  final Color  cor;

  const _BadgeAcao({required this.label, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: cor.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w600,
                color:      cor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ValorChip extends StatelessWidget {
  final String valor;
  final Color  cor;
  final Color  bg;

  const _ValorChip({
    required this.valor,
    required this.cor,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        bg.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: bg.withValues(alpha: 0.20)),
      ),
      child: Text(
        valor,
        style: TextStyle(
          fontSize:   12,
          color:      cor,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// PAGINAÇÃO
// ─────────────────────────────────────────────────────────────────────────────

class _BarraPaginacao extends StatelessWidget {
  final int paginaAtual;
  final int totalPaginas;
  final int totalItens;
  final int itensPorPagina;
  final void Function(int) onPaginaChanged;

  const _BarraPaginacao({
    required this.paginaAtual,
    required this.totalPaginas,
    required this.totalItens,
    required this.itensPorPagina,
    required this.onPaginaChanged,
  });

  List<int> _paginas() {
    if (totalPaginas <= 7) return List.generate(totalPaginas, (i) => i);
    final Set<int> vis = {0, totalPaginas - 1, paginaAtual};
    if (paginaAtual > 0) vis.add(paginaAtual - 1);
    if (paginaAtual < totalPaginas - 1) vis.add(paginaAtual + 1);
    final sorted = vis.toList()..sort();
    final List<int> result = [];
    for (int i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) result.add(-1);
      result.add(sorted[i]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final inicio  = paginaAtual * itensPorPagina + 1;
    final fim     = ((paginaAtual + 1) * itensPorPagina).clamp(0, totalItens);
    final paginas = _paginas();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Exibindo $inicio–$fim de $totalItens',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BotaoPagina(
                icon: Icons.chevron_left,
                tooltip: 'Página anterior',
                enabled: paginaAtual > 0,
                onTap: () => onPaginaChanged(paginaAtual - 1),
              ),
              const SizedBox(width: 4),
              for (final p in paginas) ...[
                if (p == -1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  )
                else
                  _BotaoNumeroPagina(
                    numero: p,
                    ativa: p == paginaAtual,
                    onTap: () => onPaginaChanged(p),
                  ),
                const SizedBox(width: 4),
              ],
              _BotaoPagina(
                icon: Icons.chevron_right,
                tooltip: 'Próxima página',
                enabled: paginaAtual < totalPaginas - 1,
                onTap: () => onPaginaChanged(paginaAtual + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotaoPagina extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _BotaoPagina({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? Theme.of(context).colorScheme.outlineVariant
                  : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _BotaoNumeroPagina extends StatelessWidget {
  final int numero;
  final bool ativa;
  final VoidCallback onTap;

  const _BotaoNumeroPagina({
    required this.numero,
    required this.ativa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: ativa ? null : onTap,
      mouseCursor: ativa ? SystemMouseCursors.basic : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: ativa ? const Color(0xFFF59E0B) : Colors.transparent,
          border: Border.all(
            color: ativa ? const Color(0xFFF59E0B) : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '${numero + 1}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: ativa ? FontWeight.w700 : FontWeight.w400,
            color: ativa ? Colors.black87 : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}