import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/usuario_provider.dart';
import '../providers/alertas_estoque_provider.dart';
import '../theme/app_theme.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  // Itens visíveis para ADMIN e GERENTE (acesso total)
  static const _navItemsCompleto = [
    _NavItem(icon: Icons.home_rounded,                    label: 'Início',           route: '/inicio'),
    _NavItem(icon: Icons.inventory_2_rounded,             label: 'Estoque',          route: '/estoque'),
    _NavItem(icon: Icons.people_rounded,                  label: 'Fornecedores',     route: '/fornecedores'),
    _NavItem(icon: Icons.request_quote_rounded,           label: 'Orçamento',        route: '/orcamento'),
    _NavItem(icon: Icons.shopping_cart_rounded,           label: 'Ordem de Compra',  route: '/ordem-compra'),
    _NavItem(icon: Icons.sync_alt_rounded,                label: 'Controle Estoque', route: '/controle-estoque'),
    _NavItem(icon: Icons.history_rounded,                 label: 'Histórico',        route: '/historico'),
    _NavItem(icon: Icons.description_rounded,             label: 'Relatório OS',     route: '/relatorio-os'),
    _NavItem(icon: Icons.precision_manufacturing_rounded, label: 'Produção',         route: '/producao'),
    _NavItem(icon: Icons.admin_panel_settings_rounded,    label: 'Admin',            route: '/admin'),
    _NavItem(icon: Icons.pie_chart_rounded,               label: 'Gastos',           route: '/gastos-categoria'),
    _NavItem(icon: Icons.directions_car_rounded,          label: 'Veículos',         route: '/veiculos'), // ← adicionar
  ];

  // Itens para COMPRAS (sem Admin; pode ver Produção como somente leitura)
  static const _navItemsCompras = [
    _NavItem(icon: Icons.home_rounded,                    label: 'Início',           route: '/inicio'),
    _NavItem(icon: Icons.inventory_2_rounded,             label: 'Estoque',          route: '/estoque'),
    _NavItem(icon: Icons.people_rounded,                  label: 'Fornecedores',     route: '/fornecedores'),
    _NavItem(icon: Icons.request_quote_rounded,           label: 'Orçamento',        route: '/orcamento'),
    _NavItem(icon: Icons.shopping_cart_rounded,           label: 'Ordem de Compra',  route: '/ordem-compra'),
    _NavItem(icon: Icons.sync_alt_rounded,                label: 'Controle Estoque por OS', route: '/controle-estoque'),
    _NavItem(icon: Icons.history_rounded,                 label: 'Histórico',        route: '/historico'),
    _NavItem(icon: Icons.description_rounded,             label: 'Relatório OS',     route: '/relatorio-os'),
    _NavItem(icon: Icons.precision_manufacturing_rounded, label: 'Produção',         route: '/producao'),
    _NavItem(icon: Icons.directions_car_rounded,          label: 'Veículos',         route: '/veiculos'),
  ];

  // Único item visível para o cargo PRODUCAO
  static const _navItemsProducao = [
    _NavItem(icon: Icons.precision_manufacturing_rounded, label: 'Produção', route: '/producao'),
  ];

  static bool isProducaoRole(String? role) {
    if (role == null) return false;
    final r = role.trim().toUpperCase();
    return r == 'PRODUÇÃO' || r == 'PRODUCAO';
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertasEstoqueProvider>().iniciarPolling();
    });
  }

  @override
  void dispose() {
    // O provider é global (MultiProvider no main), não fazemos pararPolling aqui
    // para que o polling continue mesmo ao navegar entre páginas.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isWide   = MediaQuery.of(context).size.width >= 800;

    final usuario    = context.watch<UsuarioProvider>().usuarioLogado;
    final isProducao = AppShell.isProducaoRole(usuario?.role);
    final roleUp     = usuario?.role.trim().toUpperCase() ?? '';
    final isAdmin    = roleUp == 'ADMIN';
    final isGerente  = roleUp == 'GERENTE';

    final List<_NavItem> items;
    if (isProducao) {
      items = AppShell._navItemsProducao;
    } else if (isAdmin || isGerente) {
      items = AppShell._navItemsCompleto;
    } else {
      // COMPRAS e qualquer outro role não-produção
      items = AppShell._navItemsCompras;
    }

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            _Sidebar(currentRoute: location, items: items),
          Expanded(child: widget.child),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              child: _SidebarContent(currentRoute: location, items: items),
            ),
    );
  }
}

// ─── Modelos ────────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  const _NavItem({required this.icon, required this.label, required this.route});
}

// ─── Sidebar wrapper (largura fixa) ─────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final String currentRoute;
  final List<_NavItem> items;
  const _Sidebar({required this.currentRoute, required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: _SidebarContent(currentRoute: currentRoute, items: items),
    );
  }
}

// ─── Conteúdo da sidebar ────────────────────────────────────────────────────

class _SidebarContent extends StatefulWidget {
  final String currentRoute;
  final List<_NavItem> items;
  const _SidebarContent({required this.currentRoute, required this.items});

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final usuario  = context.watch<UsuarioProvider>().usuarioLogado;
    final alertas  = context.watch<AlertasEstoqueProvider>();
    final nAlertas = alertas.totalAlertas;
    final nCriticos = alertas.totalCriticos;

    return Container(
      color: AppTheme.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho / logo ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Visual Premium',
                    style: GoogleFonts.raleway(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Gestão de Estoque e Compras',
                    style: GoogleFonts.nunito(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 6),

            // ── Banner de alertas de estoque ──────────────────────────────
            if (nAlertas > 0 && !AppShell.isProducaoRole(usuario?.role))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: _AlertasSidebarBanner(
                  totalAlertas: nAlertas,
                  totalCriticos: nCriticos,
                  onTap: () => _mostrarPainelAlertas(context, alertas),
                ),
              ),

            const SizedBox(height: 4),

            // ── Itens de navegação ────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: widget.items
                    .map((item) => _SidebarTile(
                          item: item,
                          isActive: widget.currentRoute == item.route ||
                              (item.route != '/inicio' &&
                                  widget.currentRoute.startsWith(item.route)),
                        ))
                    .toList(),
              ),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── Usuário + logout ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
                    child: Text(
                      (usuario?.nome ?? 'U')[0].toUpperCase(),
                      style: GoogleFonts.nunito(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          usuario?.nome ?? '',
                          style: GoogleFonts.nunito(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          usuario?.role ?? '',
                          style: GoogleFonts.nunito(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sair',
                    icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.white38),
                    onPressed: () {
                      context.read<UsuarioProvider>().logout();
                      context.go('/login');
                    },
                  ),
                ],
              ),
            ),

            // ── Versão ────────────────────────────────────────────────────
            if (_version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 12),
                child: Text(
                  'v$_version',
                  style: GoogleFonts.nunito(color: Colors.white24, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _mostrarPainelAlertas(BuildContext context, AlertasEstoqueProvider alertas) {
    showDialog(
      context: context,
      builder: (_) => _PainelAlertasDialog(alertas: alertas),
    );
  }
}

// ─── Tile individual ────────────────────────────────────────────────────────

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  const _SidebarTile({required this.item, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive
            ? AppTheme.accent.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(item.route),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isActive
                  ? const Border(
                      left: BorderSide(color: AppTheme.accent, width: 3),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: isActive ? AppTheme.accent : Colors.white38,
                  size: 17,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.label,
                    style: GoogleFonts.nunito(
                      color: isActive ? Colors.white : Colors.white54,
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
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

// ─── Banner compacto de alertas na sidebar ───────────────────────────────────

class _AlertasSidebarBanner extends StatelessWidget {
  final int totalAlertas;
  final int totalCriticos;
  final VoidCallback onTap;

  const _AlertasSidebarBanner({
    required this.totalAlertas,
    required this.totalCriticos,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCritico = totalCriticos > 0;
    final cor = isCritico ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final corBg = isCritico
        ? const Color(0xFFDC2626).withValues(alpha: 0.12)
        : const Color(0xFFD97706).withValues(alpha: 0.10);
    final icone = isCritico ? Icons.error_outline_rounded : Icons.warning_amber_rounded;
    final label = isCritico
        ? '$totalCriticos crítico${totalCriticos > 1 ? 's' : ''}'
        : '$totalAlertas no limite';

    return Material(
      color: corBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icone, size: 15, color: cor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.nunito(
                    color: cor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 14, color: cor.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dialog / painel completo de alertas ─────────────────────────────────────

class _PainelAlertasDialog extends StatelessWidget {
  final AlertasEstoqueProvider alertas;
  const _PainelAlertasDialog({required this.alertas});

  @override
  Widget build(BuildContext context) {
    final criticos = alertas.criticos;
    final limites  = alertas.limites;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 8),
          Text(
            'Alertas de Estoque',
            style: GoogleFonts.nunito(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          // Botão de atualizar
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: AppTheme.textSecondary,
            onPressed: () => alertas.carregar(),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: alertas.carregando
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: Color(0xFFDC2626)),
                  ),
                )
              : alertas.totalAlertas == 0
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 48, color: Color(0xFF15803D)),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhum material em alerta',
                              style: GoogleFonts.nunito(
                                  color: AppTheme.textSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (criticos.isNotEmpty) ...[
                            _AlertaSecaoHeader(
                              label: 'Críticos — abaixo do mínimo',
                              count: criticos.length,
                              cor: const Color(0xFFDC2626),
                              icone: Icons.error_outline_rounded,
                            ),
                            const SizedBox(height: 6),
                            ...criticos.map((a) => _AlertaItemTile(alerta: a)),
                            if (limites.isNotEmpty) const SizedBox(height: 16),
                          ],
                          if (limites.isNotEmpty) ...[
                            _AlertaSecaoHeader(
                              label: 'No limite — igual ao mínimo',
                              count: limites.length,
                              cor: const Color(0xFFD97706),
                              icone: Icons.warning_amber_rounded,
                            ),
                            const SizedBox(height: 6),
                            ...limites.map((a) => _AlertaItemTile(alerta: a)),
                          ],
                        ],
                      ),
                    ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Fechar',
            style: GoogleFonts.nunito(color: AppTheme.textSecondary),
          ),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            context.go('/estoque');
          },
          icon: const Icon(Icons.inventory_2_rounded, size: 15),
          label: Text('Ir para Estoque', style: GoogleFonts.nunito()),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _AlertaSecaoHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color cor;
  final IconData icone;
  const _AlertaSecaoHeader({
    required this.label,
    required this.count,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 14, color: cor),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.nunito(
            color: cor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.nunito(
              color: cor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertaItemTile extends StatelessWidget {
  final dynamic alerta; // AlertaEstoqueModel
  const _AlertaItemTile({required this.alerta});

  @override
  Widget build(BuildContext context) {
    final isCritico = alerta.isCritico as bool;
    final cor = isCritico ? const Color(0xFFDC2626) : const Color(0xFFD97706);

    // Monta subtítulo com unidade, identificador, medida, espessura
    final partes = <String>[];
    if ((alerta.categoria as String?) != null &&
        (alerta.categoria as String).isNotEmpty) {
      partes.add(alerta.categoria as String);
    }
    if ((alerta.identificador as String?) != null &&
        (alerta.identificador as String).isNotEmpty) {
      partes.add(alerta.identificador as String);
    }
    if ((alerta.medida as String?) != null &&
        (alerta.medida as String).isNotEmpty) {
      partes.add(alerta.medida as String);
    }
    if ((alerta.espessura as String?) != null &&
        (alerta.espessura as String).isNotEmpty) {
      partes.add(alerta.espessura as String);
    }
    final subtitulo = partes.join(' · ');

    final unidade = (alerta.unidade as String?) ?? '';
    final qtd = (alerta.quantidade as double);
    final min = (alerta.estoqueMinimo as double);
    final qtdStr = qtd % 1 == 0 ? qtd.toStringAsFixed(0) : qtd.toStringAsFixed(2);
    final minStr = min % 1 == 0 ? min.toStringAsFixed(0) : min.toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: cor, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alerta.nome as String,
                  style: GoogleFonts.nunito(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitulo.isNotEmpty)
                  Text(
                    subtitulo,
                    style: GoogleFonts.nunito(
                      color: AppTheme.textHint,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$qtdStr${unidade.isNotEmpty ? ' $unidade' : ''}',
                style: GoogleFonts.nunito(
                  color: cor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                'mín $minStr',
                style: GoogleFonts.nunito(
                  color: AppTheme.textHint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}