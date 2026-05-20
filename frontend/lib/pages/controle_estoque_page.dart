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

class ControleEstoquePage extends StatefulWidget {
  const ControleEstoquePage({super.key});

  @override
  State<ControleEstoquePage> createState() => _ControleEstoquePageState();
}

class _ControleEstoquePageState extends State<ControleEstoquePage> {
  final TextEditingController _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstoqueProvider>().carregarRelacoesOS();
    });
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
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
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Movimentações por Ordem de Serviço',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
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
                      : provider.relacoesOS.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhuma OS encontrada',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppTheme.textHint),
                              ),
                            )
                          : ListView.separated(
                              itemCount: provider.relacoesOS.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final rel = provider.relacoesOS[i];
                                return _RelacaoOSCard(
                                  relacao: rel,
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

  void _abrirDetalhe(RelacaoOSModel rel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RelacaoDetalhe(numeroOS: rel.numeroOS),
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
    final data = relacao.atualizadoEm ?? relacao.criadoEm;
    final dataStr = data != null
        ? '${data.day.toString().padLeft(2, '0')}/'
            '${data.month.toString().padLeft(2, '0')}/'
            '${data.year}'
        : '—';

    final materiaisUnicos =
        relacao.movimentacoes.map((m) => m.materialNome).toSet().length;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_outlined,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 14),

              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OS ${relacao.numeroOS}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$materiaisUnicos '
                      '${materiaisUnicos == 1 ? 'material' : 'materiais'} '
                      '· $dataStr',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: AppTheme.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tela de detalhe da OS ────────────────────────────────────────────────────

class _RelacaoDetalhe extends StatefulWidget {
  final String numeroOS;
  const _RelacaoDetalhe({required this.numeroOS});

  @override
  State<_RelacaoDetalhe> createState() => _RelacaoDetalheState();
}

class _RelacaoDetalheState extends State<_RelacaoDetalhe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstoqueProvider>().selecionarRelacaoOS(widget.numeroOS);
    });
  }

  Future<void> _confirmarExcluirOS(BuildContext context) async {
    // Captura dependências do context ANTES de qualquer await
    final provider   = context.read<EstoqueProvider>();
    final navigator  = Navigator.of(context);
    final messenger  = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir OS'),
        content: Text(
          'Deseja excluir a OS ${widget.numeroOS} e todas as suas '
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

    final ok = await provider.excluirRelacaoOS(widget.numeroOS);

    if (ok) {
      provider.limparSelecao();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('OS ${widget.numeroOS} excluída'),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();
    final rel = provider.relacaoSelecionada;

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
        title: Text('OS ${widget.numeroOS}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.error),
            tooltip: 'Excluir OS',
            onPressed: rel == null
                ? null
                : () => _confirmarExcluirOS(context),
          ),
        ],
      ),
      body: provider.carregandoDetalhe
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : rel == null
              ? Center(
                  child: Text(
                    'Relação não encontrada',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textHint),
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
  int? _materialExpandido; // materialId do card atualmente aberto

  @override
  Widget build(BuildContext context) {
    // Agrupa movimentações por material
    final materiaisMap = <int, List<MovimentacaoModel>>{};
    for (final mov in widget.rel.movimentacoes) {
      materiaisMap.putIfAbsent(mov.materialId, () => []).add(mov);
    }

    if (materiaisMap.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma movimentação registrada',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.textHint),
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
        final aberto = _materialExpandido == entry.key;
        return _MaterialGridCard(
          key: ValueKey(entry.key),
          movimentacoes: movs,
          numeroOS: widget.rel.numeroOS,
          aberto: aberto,
          onTap: () => setState(() =>
              _materialExpandido = aberto ? null : entry.key),
        );
      },
    );
  }
}

// ─── Card de material em grid ──────────────────────────────────────────────────

class _MaterialGridCard extends StatefulWidget {
  final List<MovimentacaoModel> movimentacoes;
  final String numeroOS;
  final bool aberto;
  final VoidCallback onTap;

  const _MaterialGridCard({
    super.key,
    required this.movimentacoes,
    required this.numeroOS,
    required this.aberto,
    required this.onTap,
  });

  @override
  State<_MaterialGridCard> createState() => _MaterialGridCardState();
}

class _MaterialGridCardState extends State<_MaterialGridCard> {
  double get _totalEntradas => widget.movimentacoes
      .where((m) => m.tipo == 'ENTRADA')
      .fold(0.0, (acc, m) => acc + m.quantidade);

  double get _totalSaidas => widget.movimentacoes
      .where((m) => m.tipo == 'SAIDA')
      .fold(0.0, (acc, m) => acc + m.quantidade);

  double get _saldoLiquido => _totalEntradas - _totalSaidas;

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
    showDialog(
      context: context,
      builder: (_) => _MovimentacaoItemDialog(
        tipo: tipo,
        materialId: _primeira.materialId,
        materialNome: _primeira.materialNome,
        numeroOS: widget.numeroOS,
        precoUnitario: _primeira.precoUnitario,
        precoM2: _primeira.precoM2,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final unidade    = _primeira.materialUnidade;
    final saldoColor = _saldoLiquido > 0
        ? AppTheme.success
        : _saldoLiquido < 0
            ? AppTheme.error
            : AppTheme.textSecondary;

    // ── Card fechado (tile compacto no grid) ─────────────────────────────
    if (!widget.aberto) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome + subtítulo
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
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more,
                        size: 18, color: AppTheme.textHint),
                  ],
                ),
                const Spacer(),
                // Chips resumo
                Row(
                  children: [
                    _MiniChip(
                      icon: Icons.arrow_downward,
                      valor: _formatQtd(_totalEntradas, null),
                      cor: AppTheme.success,
                    ),
                    const SizedBox(width: 6),
                    _MiniChip(
                      icon: Icons.arrow_upward,
                      valor: _formatQtd(_totalSaidas, null),
                      cor: AppTheme.error,
                    ),
                    const SizedBox(width: 6),
                    _MiniChip(
                      icon: Icons.balance,
                      valor: _formatQtd(_saldoLiquido, null),
                      cor: saldoColor,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.movimentacoes.length} '
                  '${widget.movimentacoes.length == 1 ? 'movimentação' : 'movimentações'}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textHint),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Card aberto (painel de detalhe em overlay) ───────────────────────
    // Usa um Dialog para não quebrar o layout do grid
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.aberto && mounted) _mostrarPainel(context);
    });

    // O card no grid fica com aparência "selecionada" enquanto o painel está aberto
    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppTheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
      child: InkWell(
        onTap: widget.onTap,
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_subtitulo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _subtitulo,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_less,
                      size: 18, color: AppTheme.primary),
                ],
              ),
              if (unidade != null) ...[
                const SizedBox(height: 2),
                Text(unidade,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
              const Spacer(),
              Row(
                children: [
                  _MiniChip(
                      icon: Icons.arrow_downward,
                      valor: _formatQtd(_totalEntradas, null),
                      cor: AppTheme.success),
                  const SizedBox(width: 6),
                  _MiniChip(
                      icon: Icons.arrow_upward,
                      valor: _formatQtd(_totalSaidas, null),
                      cor: AppTheme.error),
                  const SizedBox(width: 6),
                  _MiniChip(
                      icon: Icons.balance,
                      valor: _formatQtd(_saldoLiquido, null),
                      cor: saldoColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.movimentacoes.length} '
                '${widget.movimentacoes.length == 1 ? 'movimentação' : 'movimentações'}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarPainel(BuildContext context) async {
    final unidade    = _primeira.materialUnidade;
    final saldoColor = _saldoLiquido > 0
        ? AppTheme.success
        : _saldoLiquido < 0
            ? AppTheme.error
            : AppTheme.textSecondary;

    await showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Dialog(
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
                // ── Título ────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _primeira.materialNome,
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                          if (_subtitulo.isNotEmpty)
                            Text(
                              _subtitulo,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary),
                            ),
                          if (unidade != null)
                            Text(
                              unidade,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        widget.onTap(); // fecha o card
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Resumo ────────────────────────────────────────
                Row(
                  children: [
                    _ResumoChip(
                      label: 'Entradas',
                      valor: _formatQtd(_totalEntradas, unidade),
                      cor: AppTheme.success,
                      icone: Icons.arrow_downward,
                    ),
                    const SizedBox(width: 8),
                    _ResumoChip(
                      label: 'Saídas',
                      valor: _formatQtd(_totalSaidas, unidade),
                      cor: AppTheme.error,
                      icone: Icons.arrow_upward,
                    ),
                    const SizedBox(width: 8),
                    _ResumoChip(
                      label: 'Saldo',
                      valor: _formatQtd(_saldoLiquido, unidade),
                      cor: saldoColor,
                      icone: Icons.balance,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Botões entrada / saída ─────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          widget.onTap();
                          _abrirMovimentacao(context, 'ENTRADA');
                        },
                        icon: const Icon(Icons.add,
                            size: 16, color: AppTheme.success),
                        label: const Text('Entrada',
                            style: TextStyle(color: AppTheme.success)),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: AppTheme.success),
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
                          widget.onTap();
                          _abrirMovimentacao(context, 'SAIDA');
                        },
                        icon: const Icon(Icons.remove,
                            size: 16, color: AppTheme.error),
                        label: const Text('Saída',
                            style: TextStyle(color: AppTheme.error)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.error),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── Histórico ─────────────────────────────────────
                Text(
                  'Histórico (${widget.movimentacoes.length})',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(ctx).size.height * 0.35,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.movimentacoes.length,
                    itemBuilder: (_, i) {
                      final mov = widget.movimentacoes[i];
                      return _MovimentacaoRow(
                        mov: mov,
                        unidade: unidade,
                        formatData: _formatData,
                        formatQtd: _formatQtd,
                        onRemove: () => _confirmarRemoverMovimentacao(
                            context, mov),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Ao fechar o dialog (clique fora ou botão X), deseleciona o card
    if (mounted && widget.aberto) widget.onTap();
  }
}

// ─── Mini chip para o card fechado ────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String valor;
  final Color cor;

  const _MiniChip({
    required this.icon,
    required this.valor,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cor),
          const SizedBox(width: 3),
          Text(
            valor,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: cor),
          ),
        ],
      ),
    );
  }
}


// ─── Chip de resumo (entradas / saídas / saldo) ───────────────────────────────

class _ResumoChip extends StatelessWidget {
  final String label;
  final String valor;
  final Color cor;
  final IconData icone;

  const _ResumoChip({
    required this.label,
    required this.valor,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icone, size: 14, color: cor),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    valor,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cor,
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Row de uma movimentação no histórico ─────────────────────────────────────

class _MovimentacaoRow extends StatelessWidget {
  final MovimentacaoModel mov;
  final String? unidade;
  final String Function(DateTime) formatData;
  final String Function(double, String?) formatQtd;
  final VoidCallback onRemove;

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
    final cor = isEntrada ? AppTheme.success : AppTheme.error;
    final icon =
        isEntrada ? Icons.arrow_downward : Icons.arrow_upward;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tipo
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

          // Dados
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
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  formatData(mov.criadoEm),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textHint, fontSize: 11),
                ),
                if (mov.observacao != null &&
                    mov.observacao!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notes,
                          size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          mov.observacao!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Botão remover
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
          ),
        ],
      ),
    );
  }
}

// ─── Dialog: movimentação de item específico ───────────────────────────────────

class _MovimentacaoItemDialog extends StatefulWidget {
  final String tipo;
  final int materialId;
  final String materialNome;
  final String numeroOS;
  final double? precoUnitario;
  final double? precoM2;

  const _MovimentacaoItemDialog({
    required this.tipo,
    required this.materialId,
    required this.materialNome,
    required this.numeroOS,
    this.precoUnitario,
    this.precoM2,
  });

  @override
  State<_MovimentacaoItemDialog> createState() =>
      _MovimentacaoItemDialogState();
}

class _MovimentacaoItemDialogState
    extends State<_MovimentacaoItemDialog> {
  final _quantCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _quantCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final quant =
        double.tryParse(_quantCtrl.text.replaceAll(',', '.'));
    if (quant == null || quant <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe uma quantidade válida')),
      );
      return;
    }

    // Captura dependências do context ANTES de qualquer await
    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _enviando = true);
    final ok = await provider.registrarMovimentacao(
      materialId:    widget.materialId,
      tipo:          widget.tipo,
      quantidade:    quant,
      numeroOS:      widget.numeroOS,
      precoUnitario: widget.precoUnitario,
      precoM2:       widget.precoM2,
      observacao:    _obsCtrl.text.trim().isEmpty
          ? null
          : _obsCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (ok) {
      // Recarrega o detalhe desta OS para refletir a nova movimentação
      provider.selecionarRelacaoOS(widget.numeroOS);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${widget.tipo == 'ENTRADA' ? 'Entrada' : 'Saída'} registrada'),
        backgroundColor: widget.tipo == 'ENTRADA'
            ? AppTheme.success
            : AppTheme.error,
      ));
    } else {
      final erro = provider.erro ?? 'Erro desconhecido';
      messenger.showSnackBar(
          SnackBar(content: Text(erro), backgroundColor: AppTheme.error));
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
          const SizedBox(width: 8),
          Text(isEntrada ? 'Registrar Entrada' : 'Registrar Saída'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.materialNome,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'OS ${widget.numeroOS}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _quantCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Quantidade'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Observação (opcional)'),
          ),
        ],
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
              : Text(isEntrada
                  ? 'Confirmar Entrada'
                  : 'Confirmar Saída'),
        ),
      ],
    );
  }
}

// ─── Dialog: movimentação global (nova OS) ─────────────────────────────────────

class _MovimentacaoGlobalDialog extends StatefulWidget {
  final String tipo;
  const _MovimentacaoGlobalDialog({required this.tipo});

  @override
  State<_MovimentacaoGlobalDialog> createState() =>
      _MovimentacaoGlobalDialogState();
}

class _MovimentacaoGlobalDialogState
    extends State<_MovimentacaoGlobalDialog> {
  final _numeroOSCtrl = TextEditingController();
  // Lista de itens selecionados (material + qtd + obs)
  final List<_ItemMovimentacao> _itensSelecionados = [];
  bool _enviando = false;

  // ── Filtros de busca ─────────────────────────────────────────────────────
  final _idCtrl            = TextEditingController();
  final _nomeCtrl          = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  String? _categoriaFiltro;
  List<String> _categorias = [];

  List<MaterialModel> _resultados = [];
  bool _buscando = false;
  bool _buscouUmaVez = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
  }

  @override
  void dispose() {
    _numeroOSCtrl.dispose();
    _idCtrl.dispose();
    _nomeCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    _debounce?.cancel();
    for (final i in _itensSelecionados) {
      i.dispose();
    }
    super.dispose();
  }

  Set<int> get _idsSelecionados =>
      _itensSelecionados.map((i) => i.material.id).toSet();

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
        _espessuraCtrl.text.isNotEmpty;
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
        setState(() {
          _resultados = provider.materiais
              .where((m) => m.ativo && !_idsSelecionados.contains(m.id))
              .toList();
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
    _debounce?.cancel();
    setState(() {
      _categoriaFiltro = null;
      _buscouUmaVez    = false;
      _resultados      = [];
    });
  }

  void _selecionarMaterial(MaterialModel m) {
    if (_idsSelecionados.contains(m.id)) return;
    setState(() {
      _itensSelecionados.add(_ItemMovimentacao(material: m));
      _resultados = _resultados.where((r) => r.id != m.id).toList();
    });
  }

  void _removerItem(int index) {
    setState(() {
      _itensSelecionados[index].dispose();
      _itensSelecionados.removeAt(index);
      if (_buscouUmaVez) _buscar();
    });
  }

  Future<void> _confirmar() async {
    final numeroOS = _numeroOSCtrl.text.trim();
    if (numeroOS.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o número da OS')),
      );
      return;
    }
    if (_itensSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um material')),
      );
      return;
    }
    for (int i = 0; i < _itensSelecionados.length; i++) {
      final item = _itensSelecionados[i];
      final quant = double.tryParse(item.quantCtrl.text.replaceAll(',', '.'));
      if (quant == null || quant <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Informe a quantidade válida para "${item.material.nome}"'),
          ),
        );
        return;
      }
    }

    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _enviando = true);
    bool todosOk = true;

    for (final item in _itensSelecionados) {
      final quant = double.parse(item.quantCtrl.text.replaceAll(',', '.'));
      final obs = item.obsCtrl.text.trim().isEmpty
          ? null
          : item.obsCtrl.text.trim();

      final ok = await provider.registrarMovimentacao(
        materialId: item.material.id,
        tipo:       widget.tipo,
        quantidade: quant,
        numeroOS:   numeroOS,
        observacao: obs,
      );
      if (!ok) {
        todosOk = false;
        break;
      }
    }

    if (!mounted) return;
    setState(() => _enviando = false);

    if (todosOk) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${widget.tipo == 'ENTRADA' ? 'Entrada' : 'Saída'} '
            'registrada para OS $numeroOS'),
        backgroundColor:
            widget.tipo == 'ENTRADA' ? AppTheme.success : AppTheme.error,
      ));
    } else {
      final erro = provider.erro ?? 'Erro desconhecido';
      messenger.showSnackBar(
          SnackBar(content: Text(erro), backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEntrada = widget.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: SizedBox(
        width: 720,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Título ──────────────────────────────────────────────
              Row(
                children: [
                  Icon(
                    isEntrada
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: cor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEntrada ? 'Nova Entrada' : 'Nova Saída',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Número da OS ─────────────────────────────────────────
              TextField(
                controller: _numeroOSCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número da OS *',
                  prefixText: 'OS ',
                ),
              ),
              const SizedBox(height: 20),

              // ── Filtros — linha 1: ID · Nome · Categoria ─────────────
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _idCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ID...',
                        prefixIcon: Icon(Icons.tag,
                            color: AppTheme.textHint, size: 16),
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
                      decoration: const InputDecoration(
                        hintText: 'Buscar por nome...',
                        prefixIcon: Icon(Icons.search,
                            color: AppTheme.textHint, size: 18),
                        isDense: true,
                      ),
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
                            value: '__TODOS__', child: Text('Todas')),
                        const DropdownMenuItem(
                            value: '__SEM__',
                            child: Text('Sem categoria')),
                        ..._categorias.map((c) =>
                            DropdownMenuItem(value: c, child: Text(c))),
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
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Limpar filtros',
                    icon: const Icon(Icons.filter_alt_off,
                        color: AppTheme.textSecondary, size: 18),
                    onPressed: _limparFiltros,
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Filtros — linha 2: Identificador · Medida · Espessura ─
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _identificadorCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Identificador...',
                        prefixIcon: Icon(Icons.qr_code,
                            color: AppTheme.textHint, size: 16),
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [_UpperCaseFormatter()],
                      onChanged: (_) => _agendarBusca(),
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _medidaCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Medida...',
                        prefixIcon: Icon(Icons.straighten,
                            color: AppTheme.textHint, size: 16),
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [_UpperCaseFormatter()],
                      onChanged: (_) => _agendarBusca(),
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _espessuraCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Espessura...',
                        prefixIcon: Icon(Icons.layers,
                            color: AppTheme.textHint, size: 16),
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [_UpperCaseFormatter()],
                      onChanged: (_) => _agendarBusca(),
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Resultados da busca ──────────────────────────────────
              if (_buscando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 2),
                  ),
                )
              else if (!_buscouUmaVez)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Digite para buscar materiais',
                    style: TextStyle(
                        color: AppTheme.textHint, fontSize: 13),
                  ),
                )
              else if (_resultados.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Nenhum material encontrado',
                    style: TextStyle(
                        color: AppTheme.textHint, fontSize: 13),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _resultados.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 0,
                          thickness: 0.5,
                          color: AppTheme.divider),
                      itemBuilder: (_, i) {
                        final m = _resultados[i];
                        return _MaterialResultadoTile(
                          material: m,
                          selecionado: false,
                          onTap: () => _selecionarMaterial(m),
                        );
                      },
                    ),
                  ),
                ),

              const SizedBox(height: 14),

              // ── Materiais selecionados ───────────────────────────────
              if (_itensSelecionados.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Materiais selecionados (${_itensSelecionados.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              Expanded(
                child: _itensSelecionados.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 36,
                                color: AppTheme.textHint
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 10),
                            const Text(
                              'Nenhum material adicionado ainda',
                              style: TextStyle(
                                  color: AppTheme.textHint, fontSize: 13),
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
                            key: ValueKey(item.material.id),
                            item: item,
                            onRemover: () => _removerItem(i),
                          );
                        },
                      ),
              ),

              // ── Ações ────────────────────────────────────────────────
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _enviando ? null : _confirmar,
                    style: FilledButton.styleFrom(backgroundColor: cor),
                    child: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(isEntrada
                            ? 'Confirmar Entrada'
                            : 'Confirmar Saída'),
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

// ─── Modelo de item de movimentação ───────────────────────────────────────────

class _ItemMovimentacao {
  final MaterialModel material;
  final TextEditingController quantCtrl = TextEditingController();
  final TextEditingController obsCtrl   = TextEditingController();

  _ItemMovimentacao({required this.material});

  void dispose() {
    quantCtrl.dispose();
    obsCtrl.dispose();
  }
}

// ─── Card de item já selecionado (quantidade + observação) ────────────────────

class _ItemSelecionadoCard extends StatelessWidget {
  final _ItemMovimentacao item;
  final VoidCallback onRemover;

  const _ItemSelecionadoCard({
    super.key,
    required this.item,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    final m = item.material;
    final partes = <String>[
      if (m.medida != null && m.medida!.isNotEmpty) m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
      if (m.categoria != null && m.categoria!.isNotEmpty) m.categoria!,
    ].join(' · ');

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
          // ── Nome do material + botão remover ───────────────────────
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
                    if (partes.isNotEmpty)
                      Text(
                        partes,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemover,
                icon: const Icon(Icons.close,
                    size: 16, color: AppTheme.textSecondary),
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

          // ── Quantidade + Observação ────────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: item.quantCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Quantidade *',
                    isDense: true,
                  ),
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
        ],
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
  State<_MaterialResultadoTile> createState() => _MaterialResultadoTileState();
}

class _MaterialResultadoTileState extends State<_MaterialResultadoTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m    = widget.material;
    final sel  = widget.selecionado;
    final bg   = sel
        ? AppTheme.primary.withValues(alpha: 0.10)
        : _hovered
            ? AppTheme.primary.withValues(alpha: 0.05)
            : Colors.transparent;

    final partes = <String>[
      if (m.identificador != null && m.identificador!.isNotEmpty)
        'ID: ${m.identificador}',
      if (m.medida != null && m.medida!.isNotEmpty) m.medida!,
      if (m.espessura != null && m.espessura!.isNotEmpty) m.espessura!,
      if (m.categoria != null && m.categoria!.isNotEmpty) m.categoria!,
    ].join(' · ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (sel)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_circle,
                      size: 15, color: AppTheme.primary),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle_outlined,
                      size: 15, color: AppTheme.textHint),
                ),
              // ID
              SizedBox(
                width: 36,
                child: Text(
                  '#${m.id}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textHint,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 4),
              // Nome + sub-info
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
                        color: sel
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (partes.isNotEmpty)
                      Text(
                        partes,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Estoque atual
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    m.quantidade.toStringAsFixed(
                        m.quantidade % 1 == 0 ? 0 : 2),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                  if (m.unidade != null)
                    Text(
                      m.unidade!,
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textHint),
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

// ─── Badge de status mini ─────────────────────────────────────────────────────

class _StatusBadgeMini extends StatelessWidget {
  final String status;
  const _StatusBadgeMini({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'OK'      => ('OK',      AppTheme.statusOk),
      'LIMITE'  => ('LIMITE',  AppTheme.statusBaixo),
      'CRITICO' => ('CRITICO', AppTheme.statusCritico),
      'INATIVO' => ('INATIVO', AppTheme.textHint),
      _         => ('—',       AppTheme.textHint),
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