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
//       foregroundColor: const Color(0xFF7C3AED),
//       side: const BorderSide(color: Color(0xFF7C3AED)),
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
  String    _acaoFiltro = '';
  Timer?    _debounce;

  static const _acoes = [
    ('',                   'Todas as ações'),
    ('CADASTRO',           'Cadastro'),
    ('EDICAO',             'Edição'),
    ('DESATIVACAO',        'Desativação'),
    ('REATIVACAO',         'Reativação'),
    ('EXCLUSAO',           'Exclusão'),
    ('ESTOQUE_CONFIRMADO', 'Estoque confirmado'),
    ('FILHO_EDITADO',      'Variação editada'),
    ('FILHO_EXCLUIDO',     'Variação excluída'),
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
                        Text(
                          'Voltar',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.history, color: Color(0xFF7C3AED), size: 20),
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
                  ),
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
                        hintText:   'Buscar material...',
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
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    initialValue: _acaoFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Ação',
                      isDense:   true,
                    ),
                    items: _acoes
                        .map((a) => DropdownMenuItem(value: a.$1, child: Text(a.$2)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _acaoFiltro = v ?? '');
                      _carregar();
                    },
                  ),
                ),
                const SizedBox(width: 12),

                // Data início
                _BotaoData(
                  label: _dataInicio != null
                      ? 'De: ${_formatarData(_dataInicio!)}'
                      : 'Data início',
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
                      child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
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
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
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

                  return ListView.separated(
                    itemCount:  provider.logs.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    itemBuilder: (_, i) => _LinhaLog(
                      log:            provider.logs[i],
                      mostrarMaterial: widget.materialIdInicial == null,
                    ),
                  );
                },
              ),
            ),

            // ── Rodapé com contador ───────────────────────────────────────────
            Consumer<AuditLogProvider>(
              builder: (_, provider, __) {
                if (provider.carregando || provider.logs.isEmpty) {
                  return SizedBox.shrink();
                }
                return Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '${provider.logs.length} registro(s) encontrado(s)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                );
              },
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

class _BotaoData extends StatelessWidget {
  final String    label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _BotaoData({
    required this.label,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:         onTap,
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
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ],
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
            width: 170,
            child: Text('Ação',
                style: _estiloHeader(context)),
          ),
          // Material (só quando não está filtrado por material)
          if (mostrarMaterial)
            Expanded(
              flex: 3,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Badge de ação ────────────────────────────────────────────────
          SizedBox(
            width: 170,
            child: _BadgeAcao(label: log.acaoLabel, cor: cor),
          ),

          // ── Nome do material ─────────────────────────────────────────────
          if (mostrarMaterial)
            Expanded(
              flex: 3,
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
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (log.materialCategoria != null)
                    Text(
                      [
                        log.materialCategoria,
                        log.materialMedida,
                        log.materialEspessura,
                      ].whereType<String>().join(' · '),
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

          // ── Campo alterado ───────────────────────────────────────────────
          SizedBox(
            width: 140,
            child: Text(
              log.campo ?? '—',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── Valor antes ─────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: log.valorAntes != null
                ? _ValorChip(
                    valor: log.valorAntes!,
                    cor:   Color(0xFFDC2626),
                    bg:    Color(0xFFDC2626),
                  )
                : Text('—',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ),

          // ── Valor depois ─────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: log.valorDepois != null
                ? _ValorChip(
                    valor: log.valorDepois!,
                    cor:   Color(0xFF15803D),
                    bg:    Color(0xFF15803D),
                  )
                : Text('—',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ),

          // ── Usuário ──────────────────────────────────────────────────────
          SizedBox(
            width: 130,
            child: Text(
              log.usuarioNome ?? '—',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── Data ─────────────────────────────────────────────────────────
          SizedBox(
            width: 130,
            child: Text(
              dataStr,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
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
// BOTÃO PARA INSERIR NA EstoqueCategoriaPage
// ─────────────────────────────────────────────────────────────────────────────
//
// Cole este trecho NO CABEÇALHO da EstoqueCategoriaPage,
// ANTES do Consumer<MaterialProvider> que contém o botão "Orçar filtrados":
//
// OutlinedButton.icon(
//   onPressed: () => Navigator.of(context).push(
//     MaterialPageRoute(builder: (_) => const HistoricoMaterialPage()),
//   ),
//   icon: const Icon(Icons.history, size: 18),
//   label: const Text('Histórico'),
//   style: OutlinedButton.styleFrom(
//     foregroundColor: const Color(0xFF7C3AED),
//     side: const BorderSide(color: Color(0xFF7C3AED)),
//     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//   ),
// ),
// const SizedBox(width: 12),
//
// ─────────────────────────────────────────────────────────────────────────────
// ABRIR O HISTÓRICO DE UM MATERIAL ESPECÍFICO (dentro de _LinhaTabela, etc.)
// ─────────────────────────────────────────────────────────────────────────────
//
// Navigator.of(context).push(
//   MaterialPageRoute(
//     builder: (_) => HistoricoMaterialPage(
//       materialIdInicial:    material.id,
//       materialNomeInicial:  material.nome,
//     ),
//   ),
// );