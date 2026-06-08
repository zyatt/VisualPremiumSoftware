import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/gastos_categoria_model.dart';
import '../providers/gastos_categoria_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _brl(double v) =>
    v == 0 ? '—' : 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

String _fmtQtd(double q) =>
    q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

const _corEntrada = Color(0xFF1E88E5); // azul
const _corSaida   = Color(0xFFE53935); // vermelho

// Paleta de cores para os cards de categoria (igual à ProducaoPage)
const _coresCat = [
  Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
  Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
  Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
  Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
];

Color _corCategoria(int index) => _coresCat[index % _coresCat.length];

// ═════════════════════════════════════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class GastosCategoriaPage extends StatefulWidget {
  const GastosCategoriaPage({super.key});

  @override
  State<GastosCategoriaPage> createState() => _GastosCategoriaPageState();
}

class _GastosCategoriaPageState extends State<GastosCategoriaPage> {
  DateTime? _dataInicio;
  DateTime? _dataFim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarAcessoECarregar();
    });
  }

  void _verificarAcessoECarregar() {
    final role = context
            .read<UsuarioProvider>()
            .usuarioLogado
            ?.role
            .trim()
            .toUpperCase() ??
        '';
    if (role != 'ADMIN') return; // guard extra — rota já bloqueia
    context.read<GastosCategoriaProvider>().carregar();
  }

  void _aplicarFiltros() {
    context.read<GastosCategoriaProvider>().carregar(
          dataInicio: _dataInicio,
          dataFim: _dataFim,
        );
  }

  bool get _temFiltro => _dataInicio != null || _dataFim != null;

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim    = null;
    });
    _aplicarFiltros();
  }

  @override
  Widget build(BuildContext context) {
    // Verificação de acesso no próprio build
    final role = context
            .watch<UsuarioProvider>()
            .usuarioLogado
            ?.role
            .trim()
            .toUpperCase() ??
        '';

    if (role != 'ADMIN') {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppTheme.textHint),
              const SizedBox(height: 16),
              Text(
                'Acesso restrito',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Apenas administradores podem visualizar esta página.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final provider = context.watch<GastosCategoriaProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ─────────────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gastos por Categoria',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Entradas e saídas agrupadas por categoria — OS fechadas',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () =>
                      context.read<GastosCategoriaProvider>().recarregar(),
                  icon: const Icon(Icons.refresh,
                      size: 18, color: AppTheme.textSecondary),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: const BorderSide(color: AppTheme.divider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Filtro de período ──────────────────────────────────────────
            Row(
              children: [
                _DatePickerField(
                  label: 'De',
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
                if (_temFiltro) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _limparFiltros,
                    icon: const Icon(Icons.filter_alt_off, size: 16),
                    label: const Text('Limpar filtro'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary),
                  ),
                ],
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),

            // ── Totalizadores gerais ───────────────────────────────────────
            if (!provider.carregando && provider.erro == null && provider.categorias.isNotEmpty)
              _ResumoGeral(
                totalEntrada: provider.totalEntradaGeral,
                totalSaida:   provider.totalSaidaGeral,
              ),

            const SizedBox(height: 16),

            // ── Conteúdo ──────────────────────────────────────────────────
            Expanded(
              child: provider.carregando
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : provider.erro != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 48, color: AppTheme.error),
                              const SizedBox(height: 12),
                              Text(
                                'Erro: ${provider.erro}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppTheme.error),
                              ),
                            ],
                          ),
                        )
                      : provider.categorias.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.category_outlined,
                                    size: 56,
                                    color: AppTheme.textHint
                                        .withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nenhum dado encontrado',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(color: AppTheme.textHint),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _temFiltro
                                        ? 'Tente ajustar o período selecionado'
                                        : 'Ainda não há OS fechadas com movimentações',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: AppTheme.textHint
                                                .withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: provider.categorias.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (ctx, i) => _CategoriaCard(
                                gasto: provider.categorias[i],
                                cor:   _corCategoria(i),
                                index: i,
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resumo geral (totalizadores de todas as categorias)
// ─────────────────────────────────────────────────────────────────────────────

class _ResumoGeral extends StatelessWidget {
  final double totalEntrada;
  final double totalSaida;

  const _ResumoGeral({
    required this.totalEntrada,
    required this.totalSaida,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        border:       Border.all(color: AppTheme.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.bar_chart_rounded,
              size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(
            'Totais gerais',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const Spacer(),
          _TotalBadge(
            label: 'Total entradas',
            valor: totalEntrada,
            cor:   _corEntrada,
            icone: Icons.arrow_downward_rounded,
          ),
          const SizedBox(width: 24),
          _TotalBadge(
            label: 'Total saídas',
            valor: totalSaida,
            cor:   _corSaida,
            icone: Icons.arrow_upward_rounded,
          ),
        ],
      ),
    );
  }
}

class _TotalBadge extends StatelessWidget {
  final String   label;
  final double   valor;
  final Color    cor;
  final IconData icone;

  const _TotalBadge({
    required this.label,
    required this.valor,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 14, color: cor),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary),
            ),
            Text(
              _brl(valor),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de categoria (expansível)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoriaCard extends StatefulWidget {
  final GastoCategoriaModel gasto;
  final Color               cor;
  final int                 index;

  const _CategoriaCard({
    required this.gasto,
    required this.cor,
    required this.index,
  });

  @override
  State<_CategoriaCard> createState() => _CategoriaCardState();
}

class _CategoriaCardState extends State<_CategoriaCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final g   = widget.gasto;
    final cor = widget.cor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        border:       Border.all(
          color: _expandido ? cor.withValues(alpha: 0.4) : AppTheme.divider,
          width: _expandido ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: _expandido
            ? [
                BoxShadow(
                  color:      cor.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset:     const Offset(0, 4),
                )
              ]
            : [],
      ),
      child: Column(
        children: [
          // ── Cabeçalho clicável ─────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(14),
              topRight:    const Radius.circular(14),
              bottomLeft:  Radius.circular(_expandido ? 0 : 14),
              bottomRight: Radius.circular(_expandido ? 0 : 14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Ícone da categoria
                  Container(
                    width:  44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:        cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.category_rounded, color: cor, size: 22),
                  ),
                  const SizedBox(width: 14),

                  // Nome + contagem de materiais
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.categoriaLabel,
                          style: TextStyle(
                            fontSize:   15,
                            fontWeight: FontWeight.w700,
                            color:      AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${g.materiais.length} '
                          '${g.materiais.length == 1 ? 'material' : 'materiais'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color:    AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Totais de entrada e saída
                  _PillValor(
                    label: 'Entrada',
                    valor: g.totalEntrada,
                    cor:   _corEntrada,
                    icone: Icons.arrow_downward_rounded,
                  ),
                  const SizedBox(width: 12),
                  _PillValor(
                    label: 'Saída',
                    valor: g.totalSaida,
                    cor:   _corSaida,
                    icone: Icons.arrow_upward_rounded,
                  ),
                  const SizedBox(width: 12),

                  // Chevron
                  AnimatedRotation(
                    turns:    _expandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),

          // ── Tabela de materiais (expandível) ──────────────────────────
          if (_expandido) ...[
            const Divider(height: 1, color: AppTheme.divider),
            _TabelaMateriais(materiais: g.materiais, cor: cor),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pílula de valor (entrada / saída) no cabeçalho do card
// ─────────────────────────────────────────────────────────────────────────────

class _PillValor extends StatelessWidget {
  final String   label;
  final double   valor;
  final Color    cor;
  final IconData icone;

  const _PillValor({
    required this.label,
    required this.valor,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:        cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 12, color: cor),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: cor.withValues(alpha: 0.8)),
              ),
              Text(
                _brl(valor),
                style: TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w700,
                  color:      cor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabela de materiais dentro de uma categoria
// ─────────────────────────────────────────────────────────────────────────────

class _TabelaMateriais extends StatelessWidget {
  final List<GastoMaterialModel> materiais;
  final Color                    cor;

  const _TabelaMateriais({required this.materiais, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho da tabela
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Material',
                    style: TextStyle(
                      fontSize:   11,
                      fontWeight: FontWeight.w600,
                      color:      AppTheme.textSecondary,
                    ),
                  ),
                ),
                _HeaderCol('Qtd. Entrada', align: TextAlign.right),
                const SizedBox(width: 8),
                _HeaderCol('Valor Entrada',
                    cor: _corEntrada, align: TextAlign.right),
                const SizedBox(width: 16),
                _HeaderCol('Qtd. Saída', align: TextAlign.right),
                const SizedBox(width: 8),
                _HeaderCol('Valor Saído',
                    cor: _corSaida, align: TextAlign.right),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 4),

          // Linhas
          ...materiais.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            return _LinhaMateria(
              material:  m,
              cor:       cor,
              ultimo:    i == materiais.length - 1,
            );
          }),

          // Rodapé com subtotais da categoria
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text(
                  'Subtotal da categoria',
                  style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.w600,
                    color:      AppTheme.textSecondary,
                  ),
                ),
              ),
              // qtd entrada (vazio no rodapé)
              const SizedBox(width: 70),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(
                  _brl(materiais.fold(0.0, (s, m) => s + m.totalEntrada)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      _corEntrada,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // qtd saída (vazio no rodapé)
              const SizedBox(width: 70),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(
                  _brl(materiais.fold(0.0, (s, m) => s + m.totalSaida)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      _corSaida,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCol extends StatelessWidget {
  final String    text;
  final Color?    cor;
  final TextAlign align;

  const _HeaderCol(this.text, {this.cor, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cor != null ? 100 : 70,
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize:   11,
          fontWeight: FontWeight.w600,
          color:      cor ?? AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Linha de um material dentro da tabela
// ─────────────────────────────────────────────────────────────────────────────

class _LinhaMateria extends StatelessWidget {
  final GastoMaterialModel material;
  final Color              cor;
  final bool               ultimo;

  const _LinhaMateria({
    required this.material,
    required this.cor,
    required this.ultimo,
  });

  @override
  Widget build(BuildContext context) {
    final m       = material;
    final detalhes = [
      if (m.identificador != null && m.identificador!.isNotEmpty)
        m.identificador!,
      if (m.medida != null && m.medida!.isNotEmpty) m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
    ].join(' · ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Nome do material
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.nome,
                      style: const TextStyle(
                        fontSize:   13,
                        fontWeight: FontWeight.w500,
                        color:      AppTheme.textPrimary,
                      ),
                    ),
                    if (detalhes.isNotEmpty)
                      Text(
                        detalhes,
                        style: const TextStyle(
                          fontSize: 11,
                          color:    AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),

              // Qtd Entrada
              SizedBox(
                width: 70,
                child: Text(
                  m.qtdEntrada > 0
                      ? '${_fmtQtd(m.qtdEntrada)} ${m.unidade ?? ''}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: m.qtdEntrada > 0
                        ? AppTheme.textPrimary
                        : AppTheme.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Valor Entrada
              SizedBox(
                width: 100,
                child: Text(
                  _brl(m.totalEntrada),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: m.totalEntrada > 0
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: m.totalEntrada > 0
                        ? _corEntrada
                        : AppTheme.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Qtd Saída
              SizedBox(
                width: 70,
                child: Text(
                  m.qtdSaida > 0
                      ? '${_fmtQtd(m.qtdSaida)} ${m.unidade ?? ''}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: m.qtdSaida > 0
                        ? AppTheme.textPrimary
                        : AppTheme.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Valor Saída
              SizedBox(
                width: 100,
                child: Text(
                  _brl(m.totalSaida),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: m.totalSaida > 0
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: m.totalSaida > 0
                        ? _corSaida
                        : AppTheme.textHint,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!ultimo)
          const Divider(height: 1, color: AppTheme.divider),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seletor de data reutilizável (igual ao relatorio_os_page.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String       label;
  final DateTime?    value;
  final DateTime     firstDate;
  final DateTime     lastDate;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:        AppTheme.surface,
          border:       Border.all(
            color: hasValue ? AppTheme.primary : AppTheme.divider,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size:  16,
              color: hasValue ? AppTheme.primary : AppTheme.textHint,
            ),
            const SizedBox(width: 6),
            Text(
              hasValue ? '$label: ${_fmtData(value)}' : label,
              style: TextStyle(
                fontSize:   13,
                color:      hasValue ? AppTheme.primary : AppTheme.textHint,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (hasValue) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onCleared,
                child: const Icon(Icons.close,
                    size: 14, color: AppTheme.textHint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}