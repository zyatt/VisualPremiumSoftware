import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
  Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
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
// Página principal — grade de veículos (cards)
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

  void _novaManutencao(int veiculoId) {
    showDialog(
      context: context,
      builder: (_) => _FormManutencaoDialog(veiculoId: veiculoId),
    );
  }

  void _confirmarDesativar(VeiculoModel veiculo) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Desativar veículo',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Deseja desativar "${veiculo.nome}"?\n'
          'O histórico de serviços será mantido.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          Tooltip(
            message: 'Fechar sem desativar o veículo',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Cancelar')),
            ),
          ),
          Tooltip(
            message: 'Confirmar desativação do veículo',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                onPressed: () async {
                  final provider = context.read<VeiculoProvider>();
                  Navigator.of(context, rootNavigator: true).pop();
                  await provider.desativarVeiculo(veiculo.id);
                },
                child:
                    const Text('Desativar', style: TextStyle(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirHistorico(VeiculoModel veiculo, Color cor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VeiculoServicosPage(veiculoId: veiculo.id, cor: cor),
      ),
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

    if (role != 'ADMIN' && role != 'GERENTE' && role != 'COMPRAS') {
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
                      'Selecione um veículo para ver o histórico de serviços',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Cadastrar um novo veículo',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FilledButton.icon(
                      onPressed: () => _abrirFormVeiculo(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Novo Veículo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    onPressed: () => provider.carregarVeiculos(),
                    icon: Icon(Icons.refresh,
                        size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    tooltip: 'Atualizar lista de veículos',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
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
                                  backgroundColor: AppTheme.primary)
                                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                              ),
                            ],
                          ),
                        )
                      : provider.veiculos.isEmpty
                          ? _EmptyState(onAdd: () => _abrirFormVeiculo())
                          : SingleChildScrollView(
                              child: GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 280,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 1.15,
                                ),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: provider.veiculos.length,
                                itemBuilder: (ctx, i) {
                                  final v = provider.veiculos[i];
                                  final cor = _corVeiculo(i);
                                  return _VeiculoCardGrid(
                                    veiculo: v,
                                    cor:     cor,
                                    onTap:          () => _abrirHistorico(v, cor),
                                    onEditar:       () => _abrirFormVeiculo(v),
                                    onNovoServico:  () => _novaManutencao(v.id),
                                    onDesativar:    () => _confirmarDesativar(v),
                                  );
                                },
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
// Card de veículo (grade, estilo dos cards de categoria do Estoque)
// ─────────────────────────────────────────────────────────────────────────────

class _VeiculoCardGrid extends StatefulWidget {
  final VeiculoModel  veiculo;
  final Color         cor;
  final VoidCallback  onTap;
  final VoidCallback  onEditar;
  final VoidCallback  onNovoServico;
  final VoidCallback  onDesativar;

  const _VeiculoCardGrid({
    required this.veiculo,
    required this.cor,
    required this.onTap,
    required this.onEditar,
    required this.onNovoServico,
    required this.onDesativar,
  });

  @override
  State<_VeiculoCardGrid> createState() => _VeiculoCardGridState();
}

class _VeiculoCardGridState extends State<_VeiculoCardGrid> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final v    = widget.veiculo;
    final cor  = widget.cor;
    final ult  = v.ultimaManutencao;

    final retiradaHoje = v.manutencoes.any((m) => m.retiradaHoje);
    final emAndamento  = ult?.emAndamento ?? false;
    final ativo        = _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo
                ? cor.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo ? cor : cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
                ? [
                    BoxShadow(
                      color: cor.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Topo: ícone + ações rápidas ──────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.directions_car_rounded, color: cor, size: 24),
                    ),
                    const Spacer(),
                    _MiniIconBtn(
                      icon:    Icons.add_circle_outline,
                      color:   AppTheme.primary,
                      tooltip: 'Novo serviço',
                      onTap:   widget.onNovoServico,
                    ),
                    _MiniIconBtn(
                      icon:    Icons.edit_outlined,
                      color:   Theme.of(context).colorScheme.onSurfaceVariant,
                      tooltip: 'Editar',
                      onTap:   widget.onEditar,
                    ),
                    _MiniIconBtn(
                      icon:    Icons.delete_outline,
                      color:   AppTheme.error,
                      tooltip: 'Desativar',
                      onTap:   widget.onDesativar,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Nome ──────────────────────────────────────────────────
                Text(
                  v.nome,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ativo ? cor : Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // ── Placa ─────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    v.placa,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cor,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                const Spacer(),

                // ── Status / último serviço ──────────────────────────────
                if (retiradaHoje)
                  _StatusTag(
                    label: 'Pronto p/ retirada',
                    color: AppTheme.success,
                    icon:  Icons.check_circle_outline,
                  )
                else if (emAndamento)
                  _StatusTag(
                    label: 'Em serviço (${labelTipo(ult!.tipo)})',
                    color: const Color(0xFFFFB300),
                    icon:  Icons.build_circle_outlined,
                  )
                else if (ult != null)
                  Text(
                    'Último: ${labelTipo(ult.tipo)} em ${_fmtData(ult.dataEnvio)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    'Nenhum serviço registrado',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pequeno botão de ícone usado nas ações rápidas do card de veículo.
class _MiniIconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       tooltip;
  final VoidCallback onTap;

  const _MiniIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// Pequena etiqueta de status exibida na base do card de veículo.
class _StatusTag extends StatelessWidget {
  final String   label;
  final Color    color;
  final IconData icon;

  const _StatusTag({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Página de histórico de serviços de um veículo
// ═════════════════════════════════════════════════════════════════════════════

class VeiculoServicosPage extends StatefulWidget {
  final int   veiculoId;
  final Color cor;

  const VeiculoServicosPage({
    super.key,
    required this.veiculoId,
    required this.cor,
  });

  @override
  State<VeiculoServicosPage> createState() => _VeiculoServicosPageState();
}

class _VeiculoServicosPageState extends State<VeiculoServicosPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VeiculoProvider>().carregarManutencoes(widget.veiculoId);
    });
  }

  void _novoServico() {
    showDialog(
      context: context,
      builder: (_) => _FormManutencaoDialog(veiculoId: widget.veiculoId),
    ).then((_) {
      if (mounted) {
        context.read<VeiculoProvider>().carregarManutencoes(widget.veiculoId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VeiculoProvider>();
    final veiculo  = provider.veiculos.firstWhere(
      (v) => v.id == widget.veiculoId,
      orElse: () => VeiculoModel(
        id: widget.veiculoId,
        nome: '',
        placa: '',
        ativo: true,
        manutencoes: const [],
      ),
    );
    final cor          = widget.cor;
    final carregando   = provider.carregandoManDoVeiculo(widget.veiculoId);
    final erro         = provider.erroManDoVeiculo(widget.veiculoId);
    final manutencoes  = provider.manutencoesDoVeiculo(widget.veiculoId);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho com botão voltar ──────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BotaoVoltar(
                  label: 'Veículos',
                  tooltip: 'Voltar para a lista de veículos',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.directions_car_rounded, color: cor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          veiculo.nome,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: cor.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            veiculo.placa,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cor,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Histórico de serviços',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Registrar um novo serviço para este veículo',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FilledButton.icon(
                      onPressed: _novoServico,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Novo Serviço'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    onPressed: () => context.read<VeiculoProvider>().carregarManutencoes(widget.veiculoId),
                    icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    tooltip: 'Atualizar histórico de serviços',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Conteúdo ──────────────────────────────────────────────────
            Expanded(
              child: carregando
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : erro != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
                              SizedBox(height: 12),
                              Text(
                                'Erro ao carregar serviços',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                erro,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => context.read<VeiculoProvider>().carregarManutencoes(widget.veiculoId),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Tentar novamente'),
                                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                              ),
                            ],
                          ),
                        )
                      : manutencoes.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.build_outlined,
                                      size: 64, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
                                  SizedBox(height: 16),
                                  Text(
                                    'Nenhum serviço registrado ainda',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: _novoServico,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Adicionar serviço'),
                                  ),
                                ],
                              ),
                            )
                          : Card(
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: manutencoes.asMap().entries.map((e) {
                                    final i = e.key;
                                    final m = e.value;
                                    return _LinhaManutencao(
                                      manutencao: m,
                                      cor:        cor,
                                      ultimo:     i == manutencoes.length - 1,
                                      veiculoId:  widget.veiculoId,
                                    );
                                  }).toList(),
                                ),
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
// Linha de uma manutenção dentro do histórico
// ─────────────────────────────────────────────────────────────────────────────

class _LinhaManutencao extends StatefulWidget {
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

  @override
  State<_LinhaManutencao> createState() => _LinhaManutencaoState();
}

class _LinhaManutencaoState extends State<_LinhaManutencao> {
  bool _hovered = false;
  bool _finalizando = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  Future<void> _finalizarServico(BuildContext context) async {
    if (_finalizando) return;
    setState(() => _finalizando = true);
    final provider = context.read<VeiculoProvider>();
    await provider.finalizarManutencao(widget.manutencao.id, widget.veiculoId);
    if (mounted) setState(() => _finalizando = false);
  }

  void _editarManutencao(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _FormManutencaoDialog(
          veiculoId: widget.veiculoId, manutencao: widget.manutencao),
    );
  }

  void _confirmarDeletar(BuildContext context) {
    final manutencao = widget.manutencao;
    final veiculoId  = widget.veiculoId;
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
          Tooltip(
            message: 'Fechar sem remover o serviço',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                  onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
                  style: TextButton.styleFrom().copyWith(
                    mouseCursor: WidgetStateProperty.all(
                        SystemMouseCursors.click),
                  ),
                  child: const Text('Cancelar')),
            ),
          ),
          Tooltip(
            message: 'Confirmar remoção do serviço',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                onPressed: () async {
                  final provider = context.read<VeiculoProvider>();
                  Navigator.of(dialogCtx, rootNavigator: true).pop();
                  await provider.deletarManutencao(manutencao.id, veiculoId);
                },
                style: TextButton.styleFrom().copyWith(
                  mouseCursor: WidgetStateProperty.all(
                      SystemMouseCursors.click),
                ),
                child: const Text('Remover',
                    style: TextStyle(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m   = widget.manutencao;
    final cor = widget.cor;

    final bgColor = _hovered ? cor.withValues(alpha: 0.08) : Colors.transparent;

    return Column(
      children: [
        MouseRegion(
          cursor:  SystemMouseCursors.click,
          onHover: _onHover,
          onExit:  _onExit,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _editarManutencao(context),
            child: ColoredBox(
              color: bgColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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
                    if (m.emAndamento)
                      _finalizando
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: Padding(
                                padding: EdgeInsets.all(6),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: IconButton(
                                onPressed: () => _finalizarServico(context),
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 18, color: Color(0xFF43A047)),
                                tooltip: 'Finalizar serviço',
                                padding: EdgeInsets.zero,
                                constraints:
                                    BoxConstraints(minWidth: 28, minHeight: 28),
                                style: IconButton.styleFrom().copyWith(
                                  mouseCursor: WidgetStateProperty.all(
                                      SystemMouseCursors.click),
                                ),
                              ),
                            ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        onPressed: () => _confirmarDeletar(context),
                        icon: Icon(Icons.delete_outline,
                            size: 16, color: AppTheme.error),
                        tooltip: 'Remover',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                        style: IconButton.styleFrom().copyWith(
                          mouseCursor: WidgetStateProperty.all(
                              SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!widget.ultimo)
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
      if (ok) Navigator.of(context, rootNavigator: true).pop();
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
                autofocus:  true,
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
        Tooltip(
          message: 'Fechar sem salvar',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: TextButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                style: TextButton.styleFrom().copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
                child: const Text('Cancelar')),
          ),
        ),
        Tooltip(
          message: widget.veiculo == null ? 'Salvar novo veículo' : 'Salvar alterações do veículo',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Salvar'),
            ),
          ),
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
      if (ok) Navigator.of(context, rootNavigator: true).pop();
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
                    return Tooltip(
                      message: 'Selecionar tipo de serviço: ${labelTipo(t)}',
                      child: ChoiceChip(
                        label: Text(labelTipo(t)),
                        selected: sel,
                        showCheckmark: false,
                        mouseCursor: SystemMouseCursors.click,
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
                      ),
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
        Tooltip(
          message: 'Fechar sem salvar',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: TextButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                style: TextButton.styleFrom().copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
                child: const Text('Cancelar')),
          ),
        ),
        Tooltip(
          message: widget.manutencao == null ? 'Salvar novo serviço' : 'Salvar alterações do serviço',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Salvar'),
            ),
          ),
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
  bool                           autofocus = false,
}) {
  return TextFormField(
    controller:  controller,
    keyboardType: inputType,
    validator:   validator,
    autofocus:   autofocus,
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
    return Tooltip(
      message: hasVal ? 'Alterar $label' : 'Selecionar $label',
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
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
                Tooltip(
                  message: 'Limpar $label',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onClear,
                      child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
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
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? _accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              border: Border.all(
                color: _hovered
                    ? _accent.withValues(alpha: 0.6)
                    : scheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: _hovered ? _accent : scheme.onSurfaceVariant,
                ),
                SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: _hovered ? _accent : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
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