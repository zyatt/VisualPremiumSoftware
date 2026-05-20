import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _navItems = [
    _NavItem(icon: Icons.home_rounded,             label: 'Início',             route: '/inicio'),
    _NavItem(icon: Icons.inventory_2_rounded,      label: 'Estoque',            route: '/estoque'),
    _NavItem(icon: Icons.people_rounded,           label: 'Fornecedores',       route: '/fornecedores'),
    _NavItem(icon: Icons.request_quote_rounded,    label: 'Orçamento',          route: '/orcamento'),
    _NavItem(icon: Icons.shopping_cart_rounded,    label: 'Ordem de Compra',    route: '/ordem-compra'),
    _NavItem(icon: Icons.sync_alt_rounded,         label: 'Controle Estoque',   route: '/controle-estoque'),
    _NavItem(icon: Icons.history_rounded,          label: 'Histórico',          route: '/historico'),
    _NavItem(icon: Icons.description_rounded,      label: 'Relatório OS',       route: '/relatorio-os'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            _Sidebar(currentRoute: location, items: _navItems),
          Expanded(child: child),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              child: _SidebarContent(currentRoute: location, items: _navItems),
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
      width: 190, // ← menor que o padrão de 220
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
    final usuario = context.watch<UsuarioProvider>().usuarioLogado;

    return Container(
      color: AppTheme.sidebar, // defina AppTheme.sidebar na sua AppTheme
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
            const SizedBox(height: 10),

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