import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/estoque_model.dart';
import '../providers/relatorio_os_provider.dart';
import '../theme/app_theme.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

String _brl(double v) =>
    v == 0 ? '—' : 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

String _tituloOS(String numeroOS) =>
    int.tryParse(numeroOS) != null ? 'OS $numeroOS' : numeroOS;

const _corFechada = Color(0xFF4CAF50);

// ═════════════════════════════════════════════════════════════════════════════
// Página principal — lista de OS fechadas
// ═════════════════════════════════════════════════════════════════════════════

class RelatorioOSPage extends StatefulWidget {
  const RelatorioOSPage({super.key});

  @override
  State<RelatorioOSPage> createState() => _RelatorioOSPageState();
}

class _RelatorioOSPageState extends State<RelatorioOSPage> {
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RelatorioOSProvider>().carregar();
    });
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _buscar(String v) {
    context
        .read<RelatorioOSProvider>()
        .carregar(busca: v.trim().isEmpty ? null : v.trim());
  }

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
      backgroundColor: AppTheme.background,
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
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ordens de Serviço encerradas',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 20),

            // ── Barra de busca ──────────────────────────────────────
            TextField(
              controller: _buscaCtrl,
              onChanged: _buscar,
              decoration: const InputDecoration(
                hintText: 'Buscar por número da OS...',
                prefixIcon:
                    Icon(Icons.search, color: AppTheme.textHint, size: 20),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            // ── Conteúdo ────────────────────────────────────────────
            Expanded(
              child: provider.carregando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : provider.erro != null
                      ? Center(
                          child: Text(
                            'Erro: ${provider.erro}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppTheme.error),
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
                                    color: AppTheme.textHint
                                        .withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nenhuma OS fechada',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color: AppTheme.textHint),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'As OS fechadas aparecerão aqui',
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
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1,
                              ),
                              itemCount: provider.relatorios.length,
                              itemBuilder: (ctx, i) {
                                final rel = provider.relatorios[i];
                                return _RelatorioOSCard(
                                  relatorio: rel,
                                  onTap: () => _abrirDetalhe(rel),
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

// ─── Card de OS fechada ────────────────────────────────────────────────────────

class _RelatorioOSCard extends StatelessWidget {
  final RelacaoOSModel relatorio;
  final VoidCallback onTap;

  const _RelatorioOSCard({required this.relatorio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = relatorio.atualizadoEm ?? relatorio.criadoEm;
    final dataStr = _fmtData(data);

    final saidas = relatorio.movimentacoes
        .where((m) => m.tipo == 'SAIDA')
        .toList();

    final totalGeral = saidas.fold<double>(
      0,
      (acc, m) => acc + (m.precoUnitario ?? 0) * m.quantidade,
    );

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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$materiaisUnicos '
                    '${materiaisUnicos == 1 ? 'material' : 'materiais'}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  if (totalGeral > 0)
                    Text(
                      _brl(totalGeral),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _corFechada,
                      ),
                    ),
                  Text(
                    dataStr,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textHint),
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

  String get _titulo => _tituloOS(widget.numeroOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RelatorioOSProvider>().selecionar(widget.numeroOS);
    });
  }

  Future<void> _gerarPDF() async {
    final rel = context.read<RelatorioOSProvider>().selecionado;
    if (rel == null) return;

    setState(() => _gerandoPdf = true);
    try {
      final saidas =
          rel.movimentacoes.where((m) => m.tipo == 'SAIDA').toList();
      final totalGeral = saidas.fold<double>(
        0,
        (acc, m) => acc + (m.precoUnitario ?? 0) * m.quantidade,
      );

      final buffer = StringBuffer();
      buffer.writeln('RELATÓRIO DE OS — ${_tituloOS(rel.numeroOS)}');
      buffer.writeln('=' * 50);
      buffer.writeln(
          'Fechada em: ${_fmtData(rel.atualizadoEm ?? rel.criadoEm)}');
      buffer.writeln('Gerado em : ${_fmtData(DateTime.now())}');
      buffer.writeln('');
      buffer.writeln('ITENS (saídas):');
      buffer.writeln('-' * 50);

      for (final m in saidas) {
        final preco = m.precoUnitario ?? 0;
        final total = preco * m.quantidade;
        final qtdStr = m.quantidade % 1 == 0
            ? m.quantidade.toStringAsFixed(0)
            : m.quantidade.toStringAsFixed(2);
        buffer.writeln(
            '• ${m.materialNome} (${m.materialUnidade ?? ""}) — '
            'Qtd: $qtdStr  '
            'Unit: ${_brl(preco)}  '
            'Total: ${_brl(total)}');
        if (m.observacao != null && m.observacao!.isNotEmpty) {
          buffer.writeln('  Obs: ${m.observacao}');
        }
      }

      buffer.writeln('-' * 50);
      buffer.writeln('TOTAL GERAL: ${_brl(totalGeral)}');

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/relatorio_os_${rel.numeroOS.replaceAll(RegExp(r"\W"), "_")}.txt');
      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Relatório salvo em: ${file.path}'),
          backgroundColor: _corFechada,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar relatório: $e'),
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
      backgroundColor: AppTheme.background,
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
          if (rel != null)
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
        ],
      ),
      body: provider.carregandoDetalhe
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : rel == null
              ? Center(
                  child: Text(
                    'Relatório não encontrado',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textHint),
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

    final totalGeral = saidas.fold<double>(
      0,
      (acc, m) => acc + (m.precoUnitario ?? 0) * m.quantidade,
    );

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
                cor: AppTheme.success,
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
          if (entradas.isNotEmpty) ...[
            const SizedBox(height: 24),
            _MovimentacaoSection(
              titulo: 'Entradas de material',
              icone: Icons.input_rounded,
              cor: AppTheme.success,
              movimentacoes: entradas,
              mostrarPreco: false,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
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
                const SizedBox(width: 10),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${movimentacoes.length} '
                  '${movimentacoes.length == 1 ? 'item' : 'itens'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cabeçalho da tabela
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'Material',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'Qtd.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  if (mostrarPreco) ...[
                    const SizedBox(
                      width: 100,
                      child: Text(
                        'Unit.',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 100,
                      child: Text(
                        'Total',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(
                    width: 90,
                    child: Text(
                      'Data',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 12, color: AppTheme.divider),

            // Linhas
            ...List.generate(movimentacoes.length, (i) {
              final m = movimentacoes[i];
              final preco = m.precoUnitario ?? 0;
              final total = preco * m.quantidade;
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
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if ((m.materialUnidade ?? '').isNotEmpty)
                                Text(
                                  m.materialUnidade!,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (m.observacao != null &&
                                  m.observacao!.isNotEmpty)
                                Text(
                                  m.observacao!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textHint,
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
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary),
                          ),
                        ),
                        // Preço (só em saídas)
                        if (mostrarPreco) ...[
                          SizedBox(
                            width: 100,
                            child: Text(
                              _brl(preco),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              total > 0 ? _brl(total) : '—',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
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
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < movimentacoes.length - 1)
                    const Divider(height: 1, color: AppTheme.divider),
                ],
              );
            }),

            // Rodapé com total
            if (mostrarPreco) ...[
              const Divider(height: 16, color: AppTheme.divider),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Spacer(),
                    const Text(
                      'Total geral',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _brl(movimentacoes.fold(
                        0,
                        (acc, m) =>
                            acc + (m.precoUnitario ?? 0) * m.quantidade,
                      )),
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