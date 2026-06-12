import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/usuario_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/welcome_banner.dart';

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  static bool _bannerExibidoNaSessao = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_bannerExibidoNaSessao && mounted) {
        _bannerExibidoNaSessao = true;
        final nome = context.read<UsuarioProvider>().usuarioLogado?.nome ?? '';
        if (nome.isNotEmpty) WelcomeBanner.show(context, nome);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final usuario    = context.watch<UsuarioProvider>().usuarioLogado;
    final scheme     = Theme.of(context).colorScheme;
    final textTheme  = Theme.of(context).textTheme;
    final isProducao = AppShell.isProducaoRole(usuario?.role);
    final roleUp     = usuario?.role.trim().toUpperCase() ?? '';
    final isAdmin    = roleUp == 'ADMIN';
    final isGerente  = roleUp == 'GERENTE';

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Saudação ─────────────────────────────────────────────────
            Text(
              'Olá, ${usuario?.nome ?? ''}',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Bem-vindo à Visual Premium',
              style: GoogleFonts.nunito(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),

            // ── Grid de cards ─────────────────────────────────────────────
            Expanded(
              child: isProducao
                  ? _buildProducaoCards(scheme)
                  : _buildGeralCards(
                      scheme: scheme,
                      isAdmin: isAdmin,
                      isGerente: isGerente,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProducaoCards(ColorScheme scheme) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.8,
      children: [
        _DashCard(
          icon: Icons.precision_manufacturing_rounded,
          label: 'Produção',
          route: '/producao',
          color: const Color(0xFF6C63FF),
          scheme: scheme,
        ),
      ],
    );
  }

  Widget _buildGeralCards({
    required ColorScheme scheme,
    required bool isAdmin,
    required bool isGerente,
  }) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.8,
      children: [
        _DashCard(icon: Icons.inventory_2,                     label: 'Estoque',          route: '/estoque',          color: const Color(0xFF6C63FF), scheme: scheme),
        _DashCard(icon: Icons.people,                          label: 'Fornecedores',      route: '/fornecedores',     color: const Color(0xFF03DAC6), scheme: scheme),
        _DashCard(icon: Icons.request_quote,                   label: 'Orçamento',         route: '/orcamento',        color: const Color(0xFFFF9800), scheme: scheme),
        _DashCard(icon: Icons.shopping_cart,                   label: 'Ordem de Compra',   route: '/ordem-compra',     color: const Color(0xFF4CAF50), scheme: scheme),
        _DashCard(icon: Icons.sync_alt,                        label: 'Controle Estoque',  route: '/controle-estoque', color: const Color(0xFFE91E63), scheme: scheme),
        _DashCard(icon: Icons.history,                         label: 'Histórico',         route: '/historico',        color: const Color(0xFF9C27B0), scheme: scheme),
        _DashCard(icon: Icons.description,                     label: 'Relatório OS',      route: '/relatorio-os',     color: const Color(0xFF2196F3), scheme: scheme),
        _DashCard(icon: Icons.precision_manufacturing_rounded, label: 'Produção',          route: '/producao',         color: const Color(0xFF00BCD4), scheme: scheme),
        _DashCard(icon: Icons.pie_chart_rounded,               label: 'Gastos',            route: '/gastos-categoria', color: const Color(0xFFFF7043), scheme: scheme),
        _DashCard(icon: Icons.directions_car_rounded,          label: 'Veículos',          route: '/veiculos',         color: const Color(0xFF607D8B), scheme: scheme),
        if (isAdmin || isGerente)
          _DashCard(icon: Icons.admin_panel_settings_rounded,  label: 'Admin',             route: '/admin',            color: const Color(0xFFFF5722), scheme: scheme),
      ],
    );
  }
}

// ── Card individual ───────────────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  final IconData    icon;
  final String      label;
  final String      route;
  final Color       color;
  final ColorScheme scheme;

  const _DashCard({
    required this.icon,
    required this.label,
    required this.route,
    required this.color,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: scheme.onSurface,
                    ),
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