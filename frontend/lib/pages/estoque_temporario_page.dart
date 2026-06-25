// estoque_temporario_page.dart
// ─────────────────────────────────────────────────────────────────────────────
// ESTOQUE TEMPORÁRIO — Layout em tabela, idêntico à EstoquePage.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/estoque_temporario_model.dart';
import '../providers/estoque_temporario_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTES
// ─────────────────────────────────────────────────────────────────────────────

const _kUnidades = [
  'UNIDADE',
];
// ─────────────────────────────────────────────────────────────────────────────
// COLUNAS DA TABELA
// ─────────────────────────────────────────────────────────────────────────────

class _ColDef {
  final String label;
  final double? fixed;
  final double? flex;
  const _ColDef({required this.label, this.fixed, this.flex});
}

const _kCols = [
  _ColDef(label: 'ID',        fixed: 56),
  _ColDef(label: 'Material',  flex: 3.0),
  _ColDef(label: 'Unidade',   flex: 1.0),
  _ColDef(label: 'Expira em', flex: 1.2),
  _ColDef(label: '',          fixed: 40),
];

Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
    ? SizedBox(width: col.fixed, child: child)
    : Expanded(flex: (col.flex! * 10).round(), child: child);

Widget _vDivider(BuildContext context) => VerticalDivider(
      width: 1, thickness: 0.5,
      color: Theme.of(context).colorScheme.outlineVariant,
    );

Widget _cell(String text, BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// BOTÃO — inserido no cabeçalho da EstoquePage
// ─────────────────────────────────────────────────────────────────────────────

class BotaoEstoqueTemporario extends StatelessWidget {
  final String roleUsuario;
  const BotaoEstoqueTemporario({super.key, required this.roleUsuario});

  bool get _podeEditar {
    final r = roleUsuario.trim().toUpperCase();
    return r == 'ADMIN' || r == 'GERENTE' || r == 'COMPRAS';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EstoqueTemporarioProvider>(
      builder: (_, prov, __) {
        final total = prov.itens.length;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                prov.carregar();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: prov,
                      child: EstoqueTemporarioPage(podeEditar: _podeEditar),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.access_time_rounded, size: 16),
              label: const Text('Estoque Temporário'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (total > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class EstoqueTemporarioPage extends StatefulWidget {
  final bool podeEditar;
  const EstoqueTemporarioPage({super.key, required this.podeEditar});

  @override
  State<EstoqueTemporarioPage> createState() => _EstoqueTemporarioPageState();
}

class _EstoqueTemporarioPageState extends State<EstoqueTemporarioPage> {
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstoqueTemporarioProvider>().carregar();
    });
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _abrirFormCadastro() {
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<EstoqueTemporarioProvider>(),
        child: const _DialogMaterial(),
      ),
    );
  }

  void _abrirFormEdicao(EstoqueTemporarioModel item) {
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<EstoqueTemporarioProvider>(),
        child: _DialogMaterial(itemExistente: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ─────────────────────────────────────────────────────
            Row(
              children: [
                // Botão voltar
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          'Estoque',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
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
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estoque Temporário',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Materiais pontuais desativados automaticamente após 3 meses',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                // Botões de ação
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.podeEditar)
                      FilledButton.icon(
                        onPressed: _abrirFormCadastro,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Novo material'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    // Botão atualizar — mesmo estilo da EstoquePage
                    IconButton(
                      onPressed: () => context
                          .read<EstoqueTemporarioProvider>()
                          .carregar(busca: _busca.isEmpty ? null : _busca),
                      icon: Icon(Icons.refresh, size: 18, color: scheme.onSurfaceVariant),
                      tooltip: 'Atualizar',
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Aviso informativo ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Materiais cadastrados aqui são desativados automaticamente '
                      'após 3 meses — não excluídos. O histórico permanece íntegro. '
                      'Use para materiais pontuais que não fazem parte do catálogo permanente.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Busca ─────────────────────────────────────────────────────────
            SizedBox(
              width: 360,
              child: TextField(
                controller: _buscaCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar material...',
                  prefixIcon: Icon(Icons.search, color: scheme.outline, size: 20),
                  isDense: true,
                  suffixIcon: _busca.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _buscaCtrl.clear();
                            setState(() => _busca = '');
                            context.read<EstoqueTemporarioProvider>().carregar();
                          },
                        )
                      : null,
                ),
                onChanged: (v) {
                  setState(() => _busca = v.trim());
                  context
                      .read<EstoqueTemporarioProvider>()
                      .carregar(busca: v.trim());
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Tabela ────────────────────────────────────────────────────────
            Expanded(
              child: Consumer<EstoqueTemporarioProvider>(
                builder: (_, prov, __) {
                  if (prov.carregando) {
                    return const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary));
                  }

                  if (prov.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
                          const SizedBox(height: 12),
                          Text(
                            prov.erro!,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => prov.carregar(),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    );
                  }

                  if (prov.itens.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 56,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _busca.isEmpty
                                ? 'Nenhum material temporário cadastrado'
                                : 'Nenhum material encontrado para "$_busca"',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                          ),
                          if (_busca.isEmpty && widget.podeEditar) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _abrirFormCadastro,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Cadastrar primeiro material'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return _TabelaTemporario(
                    itens: prov.itens,
                    podeEditar: widget.podeEditar,
                    onEditar: _abrirFormEdicao,
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
// TABELA
// ─────────────────────────────────────────────────────────────────────────────

class _TabelaTemporario extends StatefulWidget {
  final List<EstoqueTemporarioModel> itens;
  final bool podeEditar;
  final void Function(EstoqueTemporarioModel) onEditar;

  const _TabelaTemporario({
    required this.itens,
    required this.podeEditar,
    required this.onEditar,
  });

  @override
  State<_TabelaTemporario> createState() => _TabelaTemporarioState();
}

class _TabelaTemporarioState extends State<_TabelaTemporario> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Widget _cabecalho(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          for (final col in _kCols)
            _colWrap(
              col,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Text(
                  col.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalho(context),
        Divider(
          height: 0, thickness: 0.8,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < widget.itens.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 0, thickness: 0.8,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  _LinhaTemporario(
                    item: widget.itens[i],
                    podeEditar: widget.podeEditar,
                    onEditar: widget.onEditar,
                  ),
                ],
                Divider(
                  height: 0, thickness: 0.8,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LINHA DA TABELA
// ─────────────────────────────────────────────────────────────────────────────

class _LinhaTemporario extends StatefulWidget {
  final EstoqueTemporarioModel item;
  final bool podeEditar;
  final void Function(EstoqueTemporarioModel) onEditar;

  const _LinhaTemporario({
    required this.item,
    required this.podeEditar,
    required this.onEditar,
  });

  @override
  State<_LinhaTemporario> createState() => _LinhaTemporarioState();
}

class _LinhaTemporarioState extends State<_LinhaTemporario> {
  bool _hovered = false;

  Color _corExpiracao() {
    final d = widget.item.diasRestantes;
    if (d <= 7)  return const Color(0xFFDC2626);
    if (d <= 30) return const Color(0xFFD97706);
    return AppTheme.primary;
  }

  String _textoExpiracao() {
    final d = widget.item.diasRestantes;
    if (d <= 0)  return 'Expirado';
    if (d == 1)  return 'Amanhã';
    if (d < 30)  return '$d dias';
    final meses = (d / 30).floor();
    return '~$meses ${meses == 1 ? 'mês' : 'meses'}';
  }

  Future<void> _confirmarDesativacao(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar material'),
        content: Text(
          'O material "${widget.item.nome}" será desativado e não aparecerá mais '
          'no catálogo. O histórico de compras e orçamentos permanece intacto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );

    if (confirmar == true && context.mounted) {
      final prov = context.read<EstoqueTemporarioProvider>();
      final ok = await prov.remover(widget.item.id);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(prov.erro ?? 'Erro ao desativar material'),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }

  Future<void> _confirmarReativacao(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reativar material'),
        content: Text(
          'O material "${widget.item.nome}" voltará a aparecer no catálogo '
          'e o prazo de desativação será renovado por mais 3 meses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Reativar'),
          ),
        ],
      ),
    );

    if (confirmar == true && context.mounted) {
      final prov = context.read<EstoqueTemporarioProvider>();
      final ok = await prov.reativar(widget.item.id);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(prov.erro ?? 'Erro ao reativar material'),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final corExp = _corExpiracao();
    final ativo = item.ativo;

    final bgColor = !ativo
        ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
        : (_hovered
            ? const Color(0xFFFF9800).withValues(alpha: 0.10)
            : Theme.of(context).colorScheme.surface);

    return MouseRegion(
      cursor: ativo ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Item desativado não pode ser editado por clique — precisa reativar primeiro.
        onTap: (widget.podeEditar && ativo) ? () => widget.onEditar(item) : null,
        child: ColoredBox(
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ID
                _colWrap(_kCols[0], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    '${item.id}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )),
                _vDivider(context),

                // Nome/Material
                _colWrap(_kCols[1], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    item.nome,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: ativo
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      decoration: ativo ? null : TextDecoration.lineThrough,
                    ),
                  ),
                )),
                _vDivider(context),

                // Unidade
                _colWrap(_kCols[2], _cell(item.unidade, context)),
                _vDivider(context),

                // Expira em / Desativado
                _colWrap(_kCols[3], Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (ativo ? corExp : Theme.of(context).colorScheme.outline)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (ativo ? corExp : Theme.of(context).colorScheme.outline)
                              .withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ativo ? Icons.schedule : Icons.block_outlined,
                            size: 11,
                            color: ativo ? corExp : Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            ativo ? _textoExpiracao() : 'Desativado',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ativo ? corExp : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
                _vDivider(context),

                // Ações
                _colWrap(_kCols[4], Center(
                  child: widget.podeEditar
                      ? (ativo
                          ? IconButton(
                              onPressed: () => _confirmarDesativacao(context),
                              icon: const Icon(Icons.block_outlined, size: 16),
                              tooltip: 'Desativar',
                              color: AppTheme.error,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : IconButton(
                              onPressed: () => _confirmarReativacao(context),
                              icon: const Icon(Icons.restart_alt_rounded, size: 16),
                              tooltip: 'Reativar',
                              color: AppTheme.primary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ))
                      : const SizedBox.shrink(),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG DE CADASTRO / EDIÇÃO
// ─────────────────────────────────────────────────────────────────────────────

class _DialogMaterial extends StatefulWidget {
  final EstoqueTemporarioModel? itemExistente;
  const _DialogMaterial({this.itemExistente});

  @override
  State<_DialogMaterial> createState() => _DialogMaterialState();
}

class _DialogMaterialState extends State<_DialogMaterial> {
  final _formKey  = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();

  String  _unidade   = 'UNIDADE';
  bool    _salvando  = false;

  bool get _editando => widget.itemExistente != null;

  @override
  void initState() {
    super.initState();
    final item = widget.itemExistente;
    if (item != null) {
      _nomeCtrl.text = item.nome;
      _unidade       = _kUnidades.contains(item.unidade) ? item.unidade : 'UNIDADE';
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);

    final prov = context.read<EstoqueTemporarioProvider>();
    final dados = {
      'nome':       _nomeCtrl.text.trim(),
      'unidade':    _unidade,
    };

    final bool ok;
    if (_editando) {
      ok = await prov.atualizar(widget.itemExistente!.id, dados);
    } else {
      ok = await prov.criar(dados);
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_editando
            ? 'Material atualizado'
            : 'Material cadastrado no estoque temporário'),
        backgroundColor: const Color(0xFF16A34A),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(prov.erro ?? 'Erro ao salvar'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory_2_outlined,
                          color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _editando
                              ? 'Editar material temporário'
                              : 'Novo material temporário',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          _editando
                              ? 'O prazo de desativação é renovado ao salvar'
                              : 'Desativado automaticamente após 3 meses',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),

                // Nome
                TextFormField(
                  controller: _nomeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Nome do material *',
                    hintText: 'Ex: CHAPA DE TESTE, PARAFUSO ESPECIAL...',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                ),
                const SizedBox(height: 14),

                // Unidade
                DropdownButtonFormField<String>(
                  initialValue: _unidade,
                  decoration: const InputDecoration(
                    labelText: 'Unidade *',
                    isDense: true,
                  ),
                  items: _kUnidades
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => _unidade = v ?? 'UNIDADE'),
                ),
                const SizedBox(height: 24),

                // Aviso
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Campos avançados (dimensões, estoque mínimo, '
                          'identificador) podem ser preenchidos depois '
                          'na tela de Materiais.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Botões
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _salvando ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: Text(_salvando
                          ? 'Salvando...'
                          : (_editando ? 'Salvar' : 'Cadastrar')),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
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