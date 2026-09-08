import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/conta_pagar_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _formatoData = DateFormat('dd/MM/yyyy');

class ContasPagarPage extends StatefulWidget {
  const ContasPagarPage({super.key});

  @override
  State<ContasPagarPage> createState() => _ContasPagarPageState();
}

const _statusAbas = ['TODAS', 'PENDENTE', 'VENCIDO', 'PAGO', 'CANCELADO'];

class _ContasPagarPageState extends State<ContasPagarPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _importando = false;

  String? get _filtroStatus =>
      _statusAbas[_tabController.index] == 'TODAS' ? null : _statusAbas[_tabController.index];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusAbas.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final role = context.read<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase();
      if (role == 'ADMIN') {
        context.read<ContaPagarProvider>().carregar();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _importarXml() async {
    final provider = context.read<ContaPagarProvider>();
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      withData: true,
    );
    if (resultado == null || resultado.files.isEmpty) return;

    final arquivo = resultado.files.first;
    if (arquivo.bytes == null) return;

    setState(() => _importando = true);
    try {
      final nota = await provider.importarXml(arquivo.bytes!, arquivo.name);
      if (!mounted) return;
      await _abrirDialogRevisaoNota(nota);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  Future<void> _abrirDialogRevisaoNota(NotaFiscalImportada nota) async {
    final vencimentoCtrl = TextEditingController(
      text: _formatoData.format(nota.vencimentoSugerido ?? DateTime.now().add(const Duration(days: 30))),
    );
    final valorCtrl = TextEditingController(text: nota.valorTotal?.toStringAsFixed(2) ?? '');
    final categoriaCtrl = TextEditingController();
    final observacaoCtrl = TextEditingController();
    DateTime dataVencimento = nota.vencimentoSugerido ?? DateTime.now().add(const Duration(days: 30));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Confirmar Conta a Pagar', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _linhaInfo('Fornecedor', nota.emitenteNome ?? '-'),
                  _linhaInfo('CNPJ', nota.emitenteCnpj ?? '-'),
                  _linhaInfo('NF-e', '${nota.numero ?? '-'}  série ${nota.serie ?? '-'}'),
                  _linhaInfo('Chave de acesso', nota.chaveAcesso),
                  if (nota.dataEmissao != null)
                    _linhaInfo('Emissão', _formatoData.format(nota.dataEmissao!)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: valorCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Valor (R\$)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: vencimentoCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Data de vencimento',
                      suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                    ),
                    onTap: () async {
                      final escolhida = await showDatePicker(
                        context: ctx,
                        initialDate: dataVencimento,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                      );
                      if (escolhida != null) {
                        setStateDialog(() {
                          dataVencimento = escolhida;
                          vencimentoCtrl.text = _formatoData.format(escolhida);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: categoriaCtrl,
                    decoration: const InputDecoration(labelText: 'Categoria (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: observacaoCtrl,
                    decoration: const InputDecoration(labelText: 'Observação (opcional)'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final provider = context.read<ContaPagarProvider>();
                try {
                  await provider.confirmarContaDeNota(
                        notaFiscalId: nota.id,
                        dataVencimento: dataVencimento,
                        valor: double.tryParse(valorCtrl.text.replaceAll(',', '.')),
                        categoria: categoriaCtrl.text.isEmpty ? null : categoriaCtrl.text,
                        observacao: observacaoCtrl.text.isEmpty ? null : observacaoCtrl.text,
                      );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Conta a pagar criada a partir da NF-e.')),
                    );
                  }
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                  );
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaInfo(String label, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
            children: [
              TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: valor),
            ],
          ),
        ),
      );

  Future<void> _confirmarExclusao(int id, String descricao) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir conta a pagar', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Tem certeza que deseja excluir "$descricao"? Essa ação não pode ser desfeita.'),
        actions: [
          Tooltip(
            message: 'Fechar sem excluir',
            child: TextButton(
              style: ButtonStyle(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
          ),
          Tooltip(
            message: 'Excluir permanentemente esta conta',
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir'),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    try {
      await context.read<ContaPagarProvider>().excluir(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta a pagar excluída.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'PAGO':
        return const Color(0xFF4CAF50);
      case 'VENCIDO':
        return AppTheme.error;
      case 'CANCELADO':
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _labelStatus(String status) {
    switch (status) {
      case 'PENDENTE':
        return 'Pendente';
      case 'VENCIDO':
        return 'Vencido';
      case 'PAGO':
        return 'Pago';
      case 'CANCELADO':
        return 'Cancelado';
      default:
        return status;
    }
  }

  int _contagemPara(List<dynamic> contas, String status) {
    if (status == 'TODAS') return contas.length;
    return contas.where((c) => c.statusEfetivo == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final role = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase();
    if (role != 'ADMIN') {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Acesso restrito',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Por enquanto, apenas usuários administradores podem acessar Contas a Pagar.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final provider = context.watch<ContaPagarProvider>();

    final contasFiltradas = _filtroStatus == null
        ? provider.contas
        : provider.contas.where((c) => c.statusEfetivo == _filtroStatus).toList();

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
                      'Contas a Pagar',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${provider.contas.length} ${provider.contas.length == 1 ? 'conta' : 'contas'} no total',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                _BotaoCabecalhoWidget(
                  leading: _importando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file_rounded, size: 18, color: Colors.white),
                  texto: 'Importar XML da NF-e',
                  onPressed: _importando ? null : _importarXml,
                  corFundo: AppTheme.primary,
                  corTexto: Colors.white,
                  tooltip: 'Importar uma NF-e em XML para gerar uma conta a pagar',
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () => context.read<ContaPagarProvider>().carregar(),
                  icon: Icon(Icons.refresh, size: 18, color: scheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: scheme.outlineVariant),
                  ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: AppTheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 2,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  for (final s in _statusAbas)
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s == 'TODAS' ? 'Todas' : _labelStatus(s)),
                          const SizedBox(width: 6),
                          _badgeContagem(
                              provider.carregando ? 0 : _contagemPara(provider.contas, s)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: provider.carregando
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : contasFiltradas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 64,
                                color: scheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _filtroStatus == null
                                    ? 'Nenhuma conta cadastrada'
                                    : 'Nenhuma conta ${_labelStatus(_filtroStatus!).toLowerCase()}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _filtroStatus == null
                                    ? 'Importe uma NF-e em XML para começar.'
                                    : 'Tente outro filtro de status.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: scheme.outline),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: contasFiltradas.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final c = contasFiltradas[i];
                            final cor = _corStatus(c.statusEfetivo);
                            return Container(
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: cor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.descricao,
                                            style: const TextStyle(fontWeight: FontWeight.w700)),
                                        if (c.emitenteNome != null || c.notaFiscalNumero != null)
                                          Text(
                                            [
                                              if (c.emitenteNome != null) c.emitenteNome,
                                              if (c.notaFiscalNumero != null)
                                                'NF-e ${c.notaFiscalNumero}',
                                            ].join(' · '),
                                            style: TextStyle(
                                                fontSize: 12, color: scheme.onSurfaceVariant),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Text('Venc.: ${_formatoData.format(c.dataVencimento)}',
                                        style: const TextStyle(fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: Text(_formatoMoeda.format(c.valor),
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(_labelStatus(c.statusEfetivo),
                                        style: TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Alterar status',
                                    child: PopupMenuButton<String>(
                                      tooltip: '',
                                      icon: const Icon(Icons.sync_alt_rounded, size: 20),
                                      color: scheme.surface,
                                      style: ButtonStyle(
                                        foregroundColor:
                                            WidgetStateProperty.all(AppTheme.primary),
                                        mouseCursor:
                                            WidgetStateProperty.all(SystemMouseCursors.click),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(color: scheme.outlineVariant),
                                      ),
                                      onSelected: (novoStatus) {
                                        if (novoStatus == c.statusEfetivo) return;
                                        context
                                            .read<ContaPagarProvider>()
                                            .alterarStatus(c.id, novoStatus);
                                      },
                                      itemBuilder: (context) => const [
                                        'PENDENTE',
                                        'VENCIDO',
                                        'PAGO',
                                        'CANCELADO',
                                      ]
                                          .map(
                                            (status) => PopupMenuItem<String>(
                                              value: status,
                                              mouseCursor: SystemMouseCursors.click,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: _corStatus(status),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(_labelStatus(status)),
                                                  if (status == c.statusEfetivo) ...[
                                                    const Spacer(),
                                                    const Icon(Icons.check_rounded, size: 16),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Excluir conta',
                                    child: IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                      style: IconButton.styleFrom(
                                        foregroundColor: AppTheme.error,
                                      ).copyWith(
                                          mouseCursor:
                                              WidgetStateProperty.all(SystemMouseCursors.click)),
                                      onPressed: () => _confirmarExclusao(c.id, c.descricao),
                                    ),
                                  ),
                                ],
                              ),
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

/// Botão de ação do cabeçalho ("Importar XML da NF-e") — mesma base visual
/// (Material + InkWell + padding manual) usada em estoque/veículos, para que
/// a altura do botão seja idêntica em todas as telas, sem os mínimos de
/// altura/target do FilledButton do Material Design.
class _BotaoCabecalhoWidget extends StatefulWidget {
  final Widget leading;
  final String texto;
  final VoidCallback? onPressed;
  final Color corFundo;
  final Color corTexto;
  final String? tooltip;

  const _BotaoCabecalhoWidget({
    required this.leading,
    required this.texto,
    required this.onPressed,
    required this.corFundo,
    required this.corTexto,
    this.tooltip,
  });

  @override
  State<_BotaoCabecalhoWidget> createState() => _BotaoCabecalhoWidgetState();
}

class _BotaoCabecalhoWidgetState extends State<_BotaoCabecalhoWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final desabilitado = widget.onPressed == null;
    final corFundo = desabilitado ? widget.corFundo.withValues(alpha: 0.6) : widget.corFundo;

    final botao = MouseRegion(
      cursor: desabilitado ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered && !desabilitado ? corFundo.withValues(alpha: 0.85) : corFundo,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: widget.onPressed,
          mouseCursor: desabilitado ? SystemMouseCursors.basic : SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.leading,
                const SizedBox(width: 6),
                Text(
                  widget.texto,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.corTexto,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return widget.tooltip != null ? Tooltip(message: widget.tooltip, child: botao) : botao;
  }
}

Widget _badgeContagem(int contagem) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$contagem',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.primary,
      ),
    ),
  );
}