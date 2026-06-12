import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/veiculo_model.dart';
import '../providers/veiculo_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _brl(double v) =>
    'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

const _coresVeiculo = [
  Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
  Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
];

Color _corVeiculo(int i) => _coresVeiculo[i % _coresVeiculo.length];

IconData _iconeTipo(String tipo) {
  switch (tipo) {
    case 'MANUTENCAO': return Icons.build_rounded;
    case 'LIMPEZA':    return Icons.cleaning_services_rounded;
    case 'REVISAO':    return Icons.fact_check_rounded;
    case 'PNEU':       return Icons.tire_repair_rounded;
    default:           return Icons.miscellaneous_services_rounded;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class VeiculoPage extends StatefulWidget {
  const VeiculoPage({super.key});

  @override
  State<VeiculoPage> createState() => _VeiculoPageState();
}

class _VeiculoPageState extends State<VeiculoPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VeiculoProvider>().carregarVeiculos();
    });
  }

  void _abrirFormVeiculo([VeiculoModel? veiculo]) {
    showDialog(
      context: context,
      builder: (_) => _FormVeiculoDialog(veiculo: veiculo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context
            .watch<UsuarioProvider>()
            .usuarioLogado
            ?.role
            .trim()
            .toUpperCase() ??
        '';

    if (role != 'ADMIN' && role != 'GERENTE') {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.outline),
              SizedBox(height: 16),
              Text('Acesso restrito',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      );
    }

    final provider = context.watch<VeiculoProvider>();

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Veículos',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Gerencie veículos e seus serviços',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _abrirFormVeiculo(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo Veículo'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                SizedBox(width: 12),
                IconButton(
                  onPressed: () => provider.carregarVeiculos(),
                  icon: Icon(Icons.refresh,
                      size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Conteúdo ───────────────────────────────────────────────────
            Expanded(
              child: provider.carregando
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : provider.erro != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_outlined,
                                  size: 48, color: AppTheme.error),
                              SizedBox(height: 12),
                              Text(
                                'Erro ao carregar veículos',
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
                                onPressed: () =>
                                    provider.carregarVeiculos(),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Tentar novamente'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primary),
                              ),
                            ],
                          ),
                        )
                      : provider.veiculos.isEmpty
                          ? _EmptyState(onAdd: () => _abrirFormVeiculo())
                          : ListView.separated(
                              itemCount: provider.veiculos.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (ctx, i) => _VeiculoCard(
                                veiculo: provider.veiculos[i],
                                cor:     _corVeiculo(i),
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
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
          SizedBox(height: 16),
          Text('Nenhum veículo cadastrado',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar veículo'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card do veículo (expansível)
// ─────────────────────────────────────────────────────────────────────────────

class _VeiculoCard extends StatefulWidget {
  final VeiculoModel veiculo;
  final Color        cor;

  const _VeiculoCard({required this.veiculo, required this.cor});

  @override
  State<_VeiculoCard> createState() => _VeiculoCardState();
}

class _VeiculoCardState extends State<_VeiculoCard> {
  bool _expandido = false;

  void _expandirECarregar() {
    setState(() => _expandido = !_expandido);
    if (_expandido) {
      context
          .read<VeiculoProvider>()
          .carregarManutencoes(widget.veiculo.id);
    }
  }

  void _editarVeiculo() {
    showDialog(
      context: context,
      builder: (_) => _FormVeiculoDialog(veiculo: widget.veiculo),
    );
  }

  void _novaManutencao() {
    showDialog(
      context: context,
      builder: (_) => _FormManutencaoDialog(veiculoId: widget.veiculo.id),
    ).then((_) {
      if (_expandido && mounted) {
        context
            .read<VeiculoProvider>()
            .carregarManutencoes(widget.veiculo.id);
      }
    });
  }

  void _confirmarDesativar() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Desativar veículo',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Deseja desativar "${widget.veiculo.nome}"?\n'
          'O histórico de serviços será mantido.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context
                  .read<VeiculoProvider>()
                  .desativarVeiculo(widget.veiculo.id);
            },
            child:
                const Text('Desativar', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v   = widget.veiculo;
    final cor = widget.cor;
    final ult = v.ultimaManutencao;

    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color:        Theme.of(context).colorScheme.surface,
        border:       Border.all(
          color: _expandido ? cor.withValues(alpha: 0.4) : Theme.of(context).colorScheme.outlineVariant,
          width: _expandido ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          // ── Cabeçalho ───────────────────────────────────────────────────
          InkWell(
            onTap: _expandirECarregar,
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
                  // Ícone
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color:        cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.directions_car_rounded,
                        color: cor, size: 24),
                  ),
                  const SizedBox(width: 14),

                  // Nome + placa
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.nome,
                            style: TextStyle(
                              fontSize:   15,
                              fontWeight: FontWeight.w700,
                              color:      Theme.of(context).colorScheme.onSurface,
                            )),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:        cor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border:       Border.all(
                                    color: cor.withValues(alpha: 0.25)),
                              ),
                              child: Text(v.placa,
                                  style: TextStyle(
                                    fontSize:   12,
                                    fontWeight: FontWeight.w700,
                                    color:      cor,
                                    letterSpacing: 1.2,
                                  )),
                            ),
                            if (ult != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                ult.emAndamento
                                    ? '• Em serviço (${labelTipo(ult.tipo)})'
                                    : '• Último: ${labelTipo(ult.tipo)} em ${_fmtData(ult.dataEnvio)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ult.emAndamento
                                      ? Color(0xFFFFB300)
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Ações
                  IconButton(
                    onPressed: _novaManutencao,
                    icon: Icon(Icons.add_circle_outline,
                        size: 20, color: AppTheme.primary),
                    tooltip: 'Novo serviço',
                  ),
                  IconButton(
                    onPressed: _editarVeiculo,
                    icon: Icon(Icons.edit_outlined,
                        size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    onPressed: _confirmarDesativar,
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppTheme.error),
                    tooltip: 'Desativar',
                  ),

                  SizedBox(width: 4),
                  AnimatedRotation(
                    turns:    _expandido ? 0.5 : 0,
                    duration: Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          // ── Histórico de serviços ────────────────────────────────────────
          if (_expandido) ...[
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            _HistoricoManutencoes(
              veiculoId: v.id,
              cor:       cor,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Histórico de manutenções dentro do card
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricoManutencoes extends StatelessWidget {
  final int   veiculoId;
  final Color cor;

  const _HistoricoManutencoes({
    required this.veiculoId,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VeiculoProvider>();

    if (provider.carregandoMan) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (provider.manutencoes.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nenhum serviço registrado ainda.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline, fontSize: 13),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Histórico de serviços',
            style: TextStyle(
              fontSize:   13,
              fontWeight: FontWeight.w600,
              color:      Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...provider.manutencoes.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            return _LinhaManutencao(
              manutencao: m,
              cor:        cor,
              ultimo:     i == provider.manutencoes.length - 1,
              veiculoId:  veiculoId,
            );
          }),
        ],
      ),
    );
  }
}

class _LinhaManutencao extends StatelessWidget {
  final ManutencaoModel manutencao;
  final Color           cor;
  final bool            ultimo;
  final int             veiculoId;

  const _LinhaManutencao({
    required this.manutencao,
    required this.cor,
    required this.ultimo,
    required this.veiculoId,
  });

  void _editarManutencao(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _FormManutencaoDialog(
          veiculoId: veiculoId, manutencao: manutencao),
    );
  }

  void _confirmarDeletar(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Remover serviço',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Remover "${labelTipo(manutencao.tipo)}" de ${_fmtData(manutencao.dataEnvio)}?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await context
                  .read<VeiculoProvider>()
                  .deletarManutencao(manutencao.id, veiculoId);
            },
            child: const Text('Remover',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = manutencao;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // Ícone do tipo
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color:        cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_iconeTipo(m.tipo), color: cor, size: 18),
              ),
              const SizedBox(width: 12),

              // Tipo + descrição + datas
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(labelTipo(m.tipo),
                            style: TextStyle(
                              fontSize:   13,
                              fontWeight: FontWeight.w600,
                              color:      Theme.of(context).colorScheme.onSurface,
                            )),
                        if (m.emAndamento) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB300)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Em andamento',
                                style: TextStyle(
                                    fontSize: 10,
                                    color:    Color(0xFFFFB300),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    if (m.descricao != null && m.descricao!.isNotEmpty)
                      Text(m.descricao!,
                          style: TextStyle(
                              fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    SizedBox(height: 2),
                    Text(
                      m.dataRetirada != null
                          ? 'Envio: ${_fmtData(m.dataEnvio)}  ·  Retirada: ${_fmtData(m.dataRetirada)}'
                          : 'Envio: ${_fmtData(m.dataEnvio)}',
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              // Valor
              Text(
                _brl(m.valor),
                style: TextStyle(
                  fontSize:   14,
                  fontWeight: FontWeight.w700,
                  color:      Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(width: 8),

              // Ações
              IconButton(
                onPressed: () => _editarManutencao(context),
                icon: Icon(Icons.edit_outlined,
                    size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                tooltip: 'Editar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                onPressed: () => _confirmarDeletar(context),
                icon: Icon(Icons.delete_outline,
                    size: 16, color: AppTheme.error),
                tooltip: 'Remover',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        if (!ultimo)
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog: criar / editar veículo
// ─────────────────────────────────────────────────────────────────────────────

class _FormVeiculoDialog extends StatefulWidget {
  final VeiculoModel? veiculo;
  const _FormVeiculoDialog({this.veiculo});

  @override
  State<_FormVeiculoDialog> createState() => _FormVeiculoDialogState();
}

class _FormVeiculoDialogState extends State<_FormVeiculoDialog> {
  final _formKey  = GlobalKey<FormState>();
  late final _nomeCtrl  = TextEditingController(text: widget.veiculo?.nome);
  late final _placaCtrl = TextEditingController(text: widget.veiculo?.placa);
  bool _salvando = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _placaCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    final provider = context.read<VeiculoProvider>();
    bool ok;
    if (widget.veiculo == null) {
      ok = await provider.criarVeiculo(
          nome: _nomeCtrl.text.trim(), placa: _placaCtrl.text.trim());
    } else {
      ok = await provider.atualizarVeiculo(
        widget.veiculo!.id,
        nome:  _nomeCtrl.text.trim(),
        placa: _placaCtrl.text.trim(),
      );
    }
    if (mounted) {
      setState(() => _salvando = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo =
        widget.veiculo == null ? 'Novo Veículo' : 'Editar Veículo';
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(titulo,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _campo(
                context: context,
                controller: _nomeCtrl,
                label:      'Nome do veículo',
                validator:  (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
              ),
              const SizedBox(height: 12),
              _campo(
                context: context,
                controller: _placaCtrl,
                label:      'Placa',
                validator:  (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a placa' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog: criar / editar manutenção
// ─────────────────────────────────────────────────────────────────────────────

class _FormManutencaoDialog extends StatefulWidget {
  final int              veiculoId;
  final ManutencaoModel? manutencao;

  const _FormManutencaoDialog({required this.veiculoId, this.manutencao});

  @override
  State<_FormManutencaoDialog> createState() => _FormManutencaoDialogState();
}

class _FormManutencaoDialogState extends State<_FormManutencaoDialog> {
  final _formKey     = GlobalKey<FormState>();
  late String   _tipo;
  late final _descCtrl  = TextEditingController(
      text: widget.manutencao?.descricao);
  late final _valorCtrl = TextEditingController(
      text: widget.manutencao != null
          ? widget.manutencao!.valor.toStringAsFixed(2)
          : '');
  late DateTime  _dataEnvio;
  DateTime?      _dataRetirada;
  bool           _salvando = false;

  @override
  void initState() {
    super.initState();
    _tipo         = widget.manutencao?.tipo ?? 'MANUTENCAO';
    _dataEnvio    = widget.manutencao?.dataEnvio    ?? DateTime.now();
    _dataRetirada = widget.manutencao?.dataRetirada;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickData(BuildContext context, bool isEnvio) async {
    final initial = isEnvio ? _dataEnvio : (_dataRetirada ?? DateTime.now());
    final picked  = await showDatePicker(
      context:     context,
      initialDate: initial,
      firstDate:   DateTime(2020),
      lastDate:    DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isEnvio) {
          _dataEnvio = picked;
        } else {
          _dataRetirada = picked;
        }
      });
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final valor = double.tryParse(
        _valorCtrl.text.trim().replaceAll(',', '.'));
    if (valor == null || valor <= 0) return;

    setState(() => _salvando = true);
    final provider = context.read<VeiculoProvider>();
    bool ok;

    if (widget.manutencao == null) {
      ok = await provider.criarManutencao(
        veiculoId:    widget.veiculoId,
        tipo:         _tipo,
        descricao:    _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        valor:        valor,
        dataEnvio:    _dataEnvio,
        dataRetirada: _dataRetirada,
      );
    } else {
      ok = await provider.atualizarManutencao(
        widget.manutencao!.id,
        widget.veiculoId,
        tipo:           _tipo,
        descricao:      _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        valor:          valor,
        dataEnvio:      _dataEnvio,
        dataRetirada:   _dataRetirada,
        limparRetirada: _dataRetirada == null,
      );
    }

    if (mounted) {
      setState(() => _salvando = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(
        widget.manutencao == null ? 'Novo Serviço' : 'Editar Serviço',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tipo
                Text('Tipo de serviço',
                    style: TextStyle(
                        fontSize: 12,
                        color:    Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tiposManutencao.map((t) {
                    final sel = _tipo == t;
                    return ChoiceChip(
                      label: Text(labelTipo(t)),
                      selected: sel,
                      onSelected: (_) => setState(() => _tipo = t),
                      selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: sel ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight:
                            sel ? FontWeight.w700 : FontWeight.normal,
                      ),
                      side: BorderSide(
                          color: sel ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Descrição
                _campo(
                  context: context,
                  controller: _descCtrl,
                  label:      'Descrição (opcional)',
                ),
                const SizedBox(height: 12),

                // Valor
                _campo(
                  context: context,
                  controller: _valorCtrl,
                  label:      'Valor (R\$)',
                  hint:       '0,00',
                  inputType:  TextInputType.numberWithOptions(decimal: true),
                  validator:  (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe o valor';
                    final d = double.tryParse(v.replaceAll(',', '.'));
                    if (d == null || d <= 0) return 'Valor inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Datas
                Row(
                  children: [
                    Expanded(
                      child: _DataBtn(
                        label: 'Data de envio',
                        valor: _dataEnvio,
                        onTap: () => _pickData(context, true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DataBtn(
                        label:    'Data de retirada',
                        valor:    _dataRetirada,
                        opcional: true,
                        onTap:    () => _pickData(context, false),
                        onClear:  _dataRetirada != null
                            ? () => setState(() => _dataRetirada = null)
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

// ── Widgets auxiliares dos dialogs ────────────────────────────────────────────

Widget _campo({
  required BuildContext context,
  required TextEditingController controller,
  required String                label,
  String?                        hint,
  String? Function(String?)?     validator,
  TextInputType?                 inputType,
}) {
  return TextFormField(
    controller:  controller,
    keyboardType: inputType,
    validator:   validator,
    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
    decoration: InputDecoration(
      labelText:     label,
      hintText:      hint,
      labelStyle:    TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
      hintStyle:     TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
      filled:        true,
      fillColor:     Theme.of(context).scaffoldBackgroundColor,
      border:        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(color: AppTheme.primary)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

class _DataBtn extends StatelessWidget {
  final String     label;
  final DateTime?  valor;
  final bool       opcional;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DataBtn({
    required this.label,
    required this.valor,
    required this.onTap,
    this.opcional = false,
    this.onClear,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasVal = valor != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color:        Theme.of(context).scaffoldBackgroundColor,
          border:       Border.all(
              color: hasVal ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size:  15,
                color: hasVal ? AppTheme.primary : Theme.of(context).colorScheme.outline),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                hasVal ? _fmt(valor!) : label,
                style: TextStyle(
                  fontSize:   13,
                  color:      hasVal ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                  fontWeight: hasVal ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasVal && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}