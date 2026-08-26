import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerScrollEvent, PointerSignalEvent;
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/usuario_provider.dart';
import '../models/usuario_model.dart';
import '../providers/alertas_estoque_provider.dart';
import '../providers/orcamento_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/nav_layout_provider.dart';
import '../pages/orcamento_page.dart';
import '../providers/veiculo_provider.dart';
import '../providers/solicitacao_material_provider.dart';
import '../providers/material_provider.dart';
import '../providers/estoque_producao_provider.dart';
import '../providers/chat_provider.dart';
import '../rotas/app_router.dart';
import 'chat_floating_widget.dart';
import 'robo_helper_widget.dart';
import '../providers/robo_helper_provider.dart';
import '../models/veiculo_model.dart';
import '../theme/app_theme.dart';
import 'welcome_banner.dart';
import 'nova_solicitacao_banner.dart';
import 'solicitacao_alterada_banner.dart';
import 'material_critico_banner.dart';
import 'theme_transition.dart';

class SessionState {
  SessionState._();
  static bool welcomeShown = false;
}

class AppMenuItem {
  final String label;
  final String route;
  final IconData icon;
  final Color color;

  const AppMenuItem({
    required this.label,
    required this.route,
    required this.icon,
    required this.color,
  });
}

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  static bool isProducaoRole(String? role) {
    if (role == null) return false;
    final r = role.trim().toUpperCase();

    return r == 'PRODUÇÃO' ||
        r == 'PRODUCAO' ||
        r == 'PRODUCAO1' ||
        r == 'PRODUCAO2';
  }

  static bool podeReceberNotificacaoSolicitacao(String? role) {
    final r = role?.trim().toUpperCase() ?? '';
    return r == 'ADMIN' || r == 'GERENTE' || r == 'COMPRAS';
  }

  static List<AppMenuItem> getMenuForRole(String? role) {
    final r = role?.trim().toUpperCase() ?? '';

    if (isProducaoRole(role)) {
      return const [
        AppMenuItem(icon: Icons.precision_manufacturing_rounded, label: 'Produção', route: '/producao', color: Color(0xFF6C63FF)),
        AppMenuItem(icon: Icons.chat_rounded,                    label: 'Chat',     route: '/chat',     color: Color(0xFF26C6DA)),
      ];
    }

    if (r == 'ORCAMENTISTA') {
      return const [
        AppMenuItem(icon: Icons.sell_rounded,         label: 'Orç. Vendas', route: '/orcamento-venda', color: Color(0xFF22C55E)),
        AppMenuItem(icon: Icons.inventory_2_rounded,  label: 'Estoque',     route: '/estoque',         color: Color(0xFF6C63FF)),
        AppMenuItem(icon: Icons.shopping_bag_rounded, label: 'Produtos',    route: '/produtos',        color: Color(0xFF06B6D4)),
      ];
    }

    final completo = [
      const AppMenuItem(icon: Icons.inventory_2_rounded,             label: 'Estoque',            route: '/estoque',               color: Color(0xFF6C63FF)),
      const AppMenuItem(icon: Icons.shopping_bag_rounded,            label: 'Produtos',           route: '/produtos',              color: Color(0xFF06B6D4)),
      const AppMenuItem(icon: Icons.people_rounded,                  label: 'Fornecedores',       route: '/fornecedores',          color: Color(0xFF03DAC6)),
      const AppMenuItem(icon: Icons.assignment_rounded,              label: 'Solicitações',       route: '/solicitacoes-material', color: Color(0xFFF59E0B)),
      const AppMenuItem(icon: Icons.request_quote_rounded,           label: 'Orçamento Compras',       route: '/orcamento',             color: Color(0xFFFF9800)),
      const AppMenuItem(icon: Icons.sell_rounded,                    label: 'Orçamento Vendas',        route: '/orcamento-venda',       color: Color(0xFF22C55E)),
      const AppMenuItem(icon: Icons.shopping_cart_rounded,           label: 'Ordem de Compra',    route: '/ordem-compra',          color: Color(0xFF4CAF50)),
      const AppMenuItem(icon: Icons.sync_alt_rounded,                label: 'Controle de Estoque',   route: '/controle-estoque',      color: Color(0xFFE91E63)),
      const AppMenuItem(icon: Icons.description_rounded,             label: 'Relatório OS',       route: '/relatorio-os',          color: Color(0xFF2196F3)),
      const AppMenuItem(icon: Icons.precision_manufacturing_rounded, label: 'Produção',           route: '/producao',              color: Color(0xFF00BCD4)),
      const AppMenuItem(icon: Icons.pie_chart_rounded,               label: 'Gastos',             route: '/gastos-categoria',      color: Color(0xFFFF7043)),
      const AppMenuItem(icon: Icons.directions_car_rounded,          label: 'Veículos',           route: '/veiculos',              color: Color(0xFF607D8B)),
      const AppMenuItem(icon: Icons.chat_rounded,                    label: 'Chat',               route: '/chat',                  color: Color(0xFF26C6DA)),
    ];

    if (r == 'ADMIN') {
      return [
        ...completo,
        const AppMenuItem(icon: Icons.admin_panel_settings_rounded, label: 'Admin', route: '/admin', color: Color(0xFFFF5722)),
      ];
    }

    if (r == 'GERENTE') {

      return completo
          .where((e) => !['/gastos-categoria', '/orcamento-venda', '/produtos'].contains(e.route))
          .toList();
    }

    return completo
        .where((e) => !['/gastos-categoria', '/orcamento-venda', '/produtos'].contains(e.route))
        .toList();
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

BuildContext? get _contextEstavel => AppRouter.rootNavigatorKey.currentContext;

class _AppShellState extends State<AppShell> {

  int? _usuarioIdConectado;

  static const _rolesComAcessoAlertasEstoque = ['ADMIN', 'GERENTE', 'COMPRAS'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VeiculoProvider>().carregarVeiculos();
      _conectarParaUsuarioAtual();
    });
  }

  void _conectarParaUsuarioAtual() {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    final token   = context.read<UsuarioProvider>().token;

    _usuarioIdConectado = usuario?.id;

    final alertasProv = context.read<AlertasEstoqueProvider>();
    if (_rolesComAcessoAlertasEstoque.contains(usuario?.role)) {
      alertasProv.iniciarPolling();
    } else {
      alertasProv.pararPolling();
    }

    context.read<SolicitacaoMaterialProvider>().conectarNotificacoes();

    context.read<MaterialProvider>().conectarNotificacoes();

    context.read<EstoqueProducaoProvider>().carregarContadorPendentes();

    context.read<ChatProvider>().minimizarWidgetFlutuante();

    if (usuario != null && token != null) {
      context.read<ChatProvider>().inicializar(usuario.id, token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isWide   = MediaQuery.of(context).size.width >= 800;

    final usuario = context.watch<UsuarioProvider>().usuarioLogado;

    if (usuario != null && usuario.id != _usuarioIdConectado) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _conectarParaUsuarioAtual();
      });
    }

    context.read<ChatProvider>().definirPaginaVisivel(location.startsWith('/chat'));

    context
        .read<SolicitacaoMaterialProvider>()
        .definirPaginaVisivel(location.startsWith('/solicitacoes-material'));

    context
        .read<MaterialProvider>()
        .definirPaginaVisivel(location.startsWith('/estoque'));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.read<RoboHelperProvider>().notificarRota(location);
      }
    });

    final nome = usuario?.nome ?? '';
    if (!SessionState.welcomeShown && nome.isNotEmpty) {
      SessionState.welcomeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {

        final overlay = AppRouter.rootNavigatorKey.currentState?.overlay;
        if (overlay != null) WelcomeBanner.showOnOverlay(overlay, nome);
      });
    }

    final notificacaoSolicitacao =
        context.watch<SolicitacaoMaterialProvider>().notificacaoPendente;
    if (notificacaoSolicitacao != null) {
      final solProvRead = context.read<SolicitacaoMaterialProvider>();
      if (AppShell.podeReceberNotificacaoSolicitacao(usuario?.role)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {

          final overlay = AppRouter.rootNavigatorKey.currentState?.overlay;
          final ctx = _contextEstavel;
          if (overlay != null && ctx != null && ctx.mounted) {
            NovaSolicitacaoBanner.showOnOverlay(
              overlay,
              notificacaoSolicitacao,
              onTap: () => ctx.go('/solicitacoes-material'),
            );
          }
        });
      }

      solProvRead.consumirNotificacaoPendente();
    }

    final notificacaoAlterada =
        context.watch<SolicitacaoMaterialProvider>().notificacaoAlteradaPendente;
    if (notificacaoAlterada != null) {
      final solProvReadAlterada = context.read<SolicitacaoMaterialProvider>();
      if (AppShell.podeReceberNotificacaoSolicitacao(usuario?.role)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {

          final overlay = AppRouter.rootNavigatorKey.currentState?.overlay;
          final ctx = _contextEstavel;
          if (overlay != null && ctx != null && ctx.mounted) {
            SolicitacaoAlteradaBanner.showOnOverlay(
              overlay,
              notificacaoAlterada,
              onTap: () => ctx.go('/solicitacoes-material'),
            );
          }
        });
      }
      solProvReadAlterada.consumirNotificacaoAlteradaPendente();
    }

    final notificacaoCritica =
        context.watch<MaterialProvider>().notificacaoCriticaPendente;
    if (notificacaoCritica != null) {
      final matProvRead = context.read<MaterialProvider>();
      if (AppShell.podeReceberNotificacaoSolicitacao(usuario?.role)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {

          final overlay = AppRouter.rootNavigatorKey.currentState?.overlay;
          final ctx = _contextEstavel;
          if (overlay != null && ctx != null && ctx.mounted) {
            MaterialCriticoBanner.showOnOverlay(
              overlay,
              notificacaoCritica,
              onTap: () {

                matProvRead.solicitarNavegacaoParaMaterial(notificacaoCritica);
                ctx.go('/estoque');
              },
            );
          }
        });
      }
      matProvRead.consumirNotificacaoCriticaPendente();
    }

    final items = AppShell.getMenuForRole(usuario?.role)
        .map((m) => _NavItem(icon: m.icon, label: m.label, route: m.route))
        .toList();

    final sidebarItems = [
      const _NavItem(icon: Icons.home_rounded, label: 'Início', route: '/inicio'),
      ...items,
    ];

    final mostrarBolhaChat = !location.startsWith('/chat');

    final navLayout = context.watch<NavLayoutProvider>();
    final usarTopo  = isWide && navLayout.isTopo;

    return Scaffold(
      body: Stack(
        children: [
          if (usarTopo)
            Column(
              children: [
                _TopBar(currentRoute: location, items: sidebarItems),
                Expanded(child: widget.navigationShell),
              ],
            )
          else
            Row(
              children: [
                if (isWide)
                  _Sidebar(currentRoute: location, items: sidebarItems),
                Expanded(child: widget.navigationShell),
              ],
            ),

          if (mostrarBolhaChat) const RoboHelperWidget(),
          if (mostrarBolhaChat) const ChatFloatingWidget(),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              child: _SidebarContent(currentRoute: location, items: sidebarItems),
            ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  const _NavItem({required this.icon, required this.label, required this.route});
}

class _Sidebar extends StatefulWidget {
  final String currentRoute;
  final List<_NavItem> items;
  const _Sidebar({required this.currentRoute, required this.items});

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  static const double _larguraMin = 160;
  static const double _larguraMax = 340;
  static const double _larguraPadrao = 190;
  static const _chavePrefs = 'sidebar_largura';

  double _largura = _larguraPadrao;
  bool _arrastando = false;
  double _larguraAoIniciar = _larguraPadrao;

  @override
  void initState() {
    super.initState();
    _carregarLarguraSalva();
  }

  Future<void> _carregarLarguraSalva() async {
    final prefs = await SharedPreferences.getInstance();
    final salva = prefs.getDouble(_chavePrefs);
    if (salva != null && mounted) {
      setState(() {
        _largura = salva.clamp(_larguraMin, _larguraMax);
      });
    }
  }

  Future<void> _salvarLargura(double largura) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_chavePrefs, largura);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corDivisor = isDark ? Colors.white10 : Colors.black12;
    final corDivisorAtivo = AppTheme.accent.withValues(alpha: 0.6);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _largura,
          child: _SidebarContent(
              currentRoute: widget.currentRoute, items: widget.items),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              setState(() {
                _arrastando = true;
                _larguraAoIniciar = _largura;
              });
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _largura = (_larguraAoIniciar + details.localPosition.dx)
                    .clamp(_larguraMin, _larguraMax);
              });
            },
            onHorizontalDragEnd: (_) {
              setState(() => _arrastando = false);
              _salvarLargura(_largura);
            },
            child: Container(
              width: 6,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Container(
                width: _arrastando ? 2 : 1,
                color: _arrastando ? corDivisorAtivo : corDivisor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatefulWidget {
  final String currentRoute;
  final List<_NavItem> items;
  const _TopBar({required this.currentRoute, required this.items});

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  String _version = '';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()
          ? event.scrollDelta.dy
          : event.scrollDelta.dx;
      final novoOffset = (_scrollController.offset + delta).clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(novoOffset);
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  void _abrirConfiguracoes(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _ConfiguracoesDialog(),
    );
  }

  void _abrirTrocaUsuario(BuildContext context) {
    final usuarioProvider = context.read<UsuarioProvider>();
    final salvos = usuarioProvider.usuariosSalvos;
    final atual  = usuarioProvider.usuarioLogado;

    final outros = salvos.where((u) => u.id != atual?.id).toList();

    showDialog(
      context: context,
      builder: (_) => _TrocaUsuarioDialog(
        usuarioAtual: atual,
        usuariosSalvos: outros,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<UsuarioProvider>().usuarioLogado;

    final solProv       = context.watch<SolicitacaoMaterialProvider>();
    final nSolicitacoes = solProv.novasSolicitacoes;

    final chatProv = context.watch<ChatProvider>();
    final nChat    = chatProv.totalNaoLidas;

    final nPendentesProducao =
        context.watch<EstoqueProducaoProvider>().totalPendentes;

    final alertasProv = context.watch<AlertasEstoqueProvider>();
    final nAlertasCriticos = alertasProv.totalAlertas;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sidebarBg = isDark ? AppTheme.sidebar : const Color.fromARGB(255, 247, 247, 247);
    final textColor = isDark ? Colors.white : Colors.black;
    final textColorTertiary = isDark ? const Color.fromARGB(97, 240, 240, 240) : Colors.black54;
    final dividerColor = isDark ? Colors.white10 : Colors.black26;

    return Container(
      color: sidebarBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const _AnimatedLogo(),
              const SizedBox(width: 10),
              Text(
                'Visual Premium',
                style: GoogleFonts.raleway(
                  color: textColor,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 24, color: dividerColor),
              const SizedBox(width: 8),

              Expanded(
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                      children: widget.items.map((item) {
                        final isActive =
                            widget.currentRoute == item.route ||
                            (item.route != '/inicio' &&
                                widget.currentRoute
                                    .startsWith('${item.route}/'));

                        final badge = item.route == '/solicitacoes-material' && nSolicitacoes > 0
                            ? nSolicitacoes
                            : item.route == '/chat' && nChat > 0
                                ? nChat
                                : item.route == '/controle-estoque' && nPendentesProducao > 0
                                    ? nPendentesProducao
                                    : 0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _TopBarTile(
                            item: item,
                            isActive: isActive,
                            badge: badge,
                            isDark: isDark,
                          ),
                        );
                      }).toList(),
                    ),
                    ),
                  ),
                ),
              ),

              if (nAlertasCriticos > 0 && !AppShell.isProducaoRole(usuario?.role)) ...[
                const SizedBox(width: 8),
                _AlertasTopBarChip(
                  totalAlertas: nAlertasCriticos,
                  onTap: () => _mostrarPainelAlertas(context, alertasProv),
                ),
              ],

              const SizedBox(width: 8),
              Container(width: 1, height: 24, color: dividerColor),
              const SizedBox(width: 8),

              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () => _abrirTrocaUsuario(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor:
                                AppTheme.accent.withValues(alpha: 0.2),
                            child: Text(
                              (usuario?.nome ?? 'U')[0].toUpperCase(),
                              style: GoogleFonts.nunito(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                usuario?.nome ?? '',
                                maxLines: 1,
                                style: GoogleFonts.nunito(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              IconButton(
                tooltip: 'Configurações',
                icon: Icon(Icons.settings_rounded,
                    size: 18, color: textColorTertiary),
                onPressed: () => _abrirConfiguracoes(context),
                style: IconButton.styleFrom().copyWith(mouseCursor:
                    WidgetStateProperty.all(SystemMouseCursors.click)),
              ),

              if (_version.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    'v$_version',
                    style: GoogleFonts.nunito(
                        color: textColorTertiary.withValues(alpha: 0.6),
                        fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarTile extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final int badge;
  final bool isDark;

  const _TopBarTile({
    required this.item,
    required this.isActive,
    this.badge = 0,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColorSecondary = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white38 : Colors.black87;

    return Material(
      color: isActive
          ? AppTheme.accent.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        mouseCursor: SystemMouseCursors.click,
        onTap: () => context.go(item.route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? const Border(
                    bottom: BorderSide(color: AppTheme.accent, width: 2),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                color: isActive ? AppTheme.accent : iconColor,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                item.label,
                style: GoogleFonts.nunito(
                  color: isActive
                      ? (isDark ? Colors.white : Colors.black87)
                      : textColorSecondary,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: GoogleFonts.nunito(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLogo extends StatefulWidget {
  const _AnimatedLogo();

  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _float;
  late final Animation<double> _tilt;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _float = Tween<double>(begin: -3, end: 3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );

    _tilt = Tween<double>(begin: -0.045, end: 0.045).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );

    _glow = Tween<double>(begin: 0.15, end: 0.45).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _float.value),
        child: Transform.rotate(
          angle: _tilt.value,
          child: child,
        ),
      ),
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: _glow.value),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/logo.png',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

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

  void _abrirConfiguracoes(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _ConfiguracoesDialog(),
    );
  }

  void _abrirTrocaUsuario(BuildContext context) {
    final usuarioProvider = context.read<UsuarioProvider>();
    final salvos = usuarioProvider.usuariosSalvos;
    final atual  = usuarioProvider.usuarioLogado;

    final outros = salvos.where((u) => u.id != atual?.id).toList();

    showDialog(
      context: context,
      builder: (_) => _TrocaUsuarioDialog(
        usuarioAtual: atual,
        usuariosSalvos: outros,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario     = context.watch<UsuarioProvider>().usuarioLogado;
    final alertas     = context.watch<AlertasEstoqueProvider>();
    final nAlertas    = alertas.totalAlertas;
    final veiculoProv = context.watch<VeiculoProvider>();

    final nRetirada = veiculoProv.veiculos
        .cast<VeiculoModel>()
        .where((v) => v.manutencoes.any((m) => m.retiradaHoje))
        .length;

    final solProv          = context.watch<SolicitacaoMaterialProvider>();
    final nSolicitacoes    = solProv.novasSolicitacoes;

    final chatProv   = context.watch<ChatProvider>();
    final nChat      = chatProv.totalNaoLidas;

    final nPendentesProducao =
        context.watch<EstoqueProducaoProvider>().totalPendentes;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sidebarBg = isDark ? AppTheme.sidebar : const Color.fromARGB(255, 247, 247, 247);
    final textColor = isDark ? Colors.white : Colors.black;
    final textColorTertiary = isDark ? const Color.fromARGB(97, 240, 240, 240) : Colors.black54;
    final dividerColor = isDark ? Colors.white10 : Colors.black26;

    return Container(
      color: sidebarBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 20, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _AnimatedLogo(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Visual Premium',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.raleway(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(color: dividerColor, height: 1),
            const SizedBox(height: 6),

            if (!AppShell.isProducaoRole(usuario?.role))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: _StatusNotificacoesIndicador(
                  conectado: solProv.notificacoesConectadas,
                ),
              ),

            if (nAlertas > 0 && !AppShell.isProducaoRole(usuario?.role))
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: _AlertasSidebarBanner(
                  totalAlertas: nAlertas,
                  onTap: () => _mostrarPainelAlertas(context, alertas),
                ),
              ),

            if (nRetirada > 0 && !AppShell.isProducaoRole(usuario?.role))
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: _RetiradaVeiculosBanner(
                  total: nRetirada,
                  onTap: () =>
                      _mostrarPainelRetirada(context, veiculoProv),
                ),
              ),

            const SizedBox(height: 4),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: widget.items.map((item) {
                  final isActive =
                      widget.currentRoute == item.route ||
                      (item.route != '/inicio' &&
                          widget.currentRoute
                              .startsWith('${item.route}/'));

                  final badge = item.route == '/solicitacoes-material' && nSolicitacoes > 0
                      ? nSolicitacoes
                      : item.route == '/chat' && nChat > 0
                          ? nChat
                          : item.route == '/controle-estoque' && nPendentesProducao > 0
                              ? nPendentesProducao
                              : 0;

                  return _SidebarTile(
                    item: item,
                    isActive: isActive,
                    badge: badge,
                    isDark: isDark,
                  );
                }).toList(),
              ),
            ),

            Divider(color: dividerColor, height: 1),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () => _abrirTrocaUsuario(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor:
                                    AppTheme.accent.withValues(alpha: 0.2),
                                child: Text(
                                  (usuario?.nome ?? 'U')[0].toUpperCase(),
                                  style: GoogleFonts.nunito(
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      usuario?.nome ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.nunito(
                                        color: textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        height: 1.15,
                                      ),
                                    ),
                                    Text(
                                      usuario?.role ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.nunito(
                                        color: textColorTertiary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.unfold_more_rounded,
                                  size: 13, color: textColorTertiary.withValues(alpha: 0.6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Configurações',
                    icon: Icon(Icons.settings_rounded,
                        size: 17, color: textColorTertiary),
                    onPressed: () => _abrirConfiguracoes(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    style: IconButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(
                            SystemMouseCursors.click)),
                  ),
                ],
              ),
            ),

            if (_version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 12),
                child: Text(
                  'v$_version',
                  style: GoogleFonts.nunito(
                      color: textColorTertiary.withValues(alpha: 0.6), fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _mostrarPainelRetirada(
      BuildContext context, VeiculoProvider provider) {
    showDialog(
      context: context,
      builder: (_) => _PainelRetiradaDialog(provider: provider),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final int badge;
  final bool isDark;

  const _SidebarTile({
    required this.item,
    required this.isActive,
    this.badge = 0,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColorSecondary = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white38 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive
            ? AppTheme.accent.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => context.go(item.route),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
                  color: isActive ? AppTheme.accent : iconColor,
                  size: 17,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: GoogleFonts.nunito(
                        color: isActive ? (isDark ? Colors.white : Colors.black87) : textColorSecondary,
                        fontSize: 12,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                if (badge > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: GoogleFonts.nunito(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
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

class _ConfiguracoesDialog extends StatelessWidget {
  const _ConfiguracoesDialog();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark        = themeProvider.isDark;
    final colorScheme   = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: isDark ? 0.5 : 0.12),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.settings_rounded,
                          color: AppTheme.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Configurações',
                      style: GoogleFonts.raleway(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Fechar',
                      icon: Icon(Icons.close_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom().copyWith(
                          mouseCursor: WidgetStateProperty.all(
                              SystemMouseCursors.click)),
                    ),
                  ],
                ),
              ),
              Divider(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'APARÊNCIA',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Builder(
                  builder: (rowContext) {
                    Offset? tapOrigin;

                    void trocarTema() {
                      final box =
                          rowContext.findRenderObject() as RenderBox?;
                      final fallback = box != null
                          ? box.localToGlobal(
                              Offset(box.size.width - 24, box.size.height / 2))
                          : const Offset(24, 24);
                      ThemeTransitionOverlay.of(rowContext)?.switchTheme(
                            origin: tapOrigin ?? fallback,
                            onSwitch: () =>
                                rowContext.read<ThemeProvider>().toggle(),
                          ) ??
                          rowContext.read<ThemeProvider>().toggle();
                    }

                    return Listener(
                      onPointerDown: (event) => tapOrigin = event.position,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: trocarTema,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 250),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                          scale: anim, child: child),
                                  child: Icon(
                                    isDark
                                        ? Icons.dark_mode_rounded
                                        : Icons.light_mode_rounded,
                                    key: ValueKey(isDark),
                                    color: isDark
                                        ? const Color(0xFF93C5FD)
                                        : const Color(0x0fffbf24),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Modo de exibição',
                                        style: GoogleFonts.nunito(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        isDark ? 'Escuro' : 'Claro',
                                        style: GoogleFonts.nunito(
                                          fontSize: 11,
                                          color: colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: isDark,
                                  onChanged: (_) => trocarTema(),
                                  activeThumbColor: AppTheme.primary,
                                  activeTrackColor: AppTheme.primary
                                      .withValues(alpha: 0.3),
                                  inactiveThumbColor:
                                      colorScheme.onSurfaceVariant,
                                  inactiveTrackColor: colorScheme.outline
                                      .withValues(alpha: 0.3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Divider(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'LAYOUT',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Builder(
                  builder: (rowContext) {
                    final navLayout = rowContext.watch<NavLayoutProvider>();
                    final noTopo = navLayout.isTopo;

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () => rowContext.read<NavLayoutProvider>().alternar(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                noTopo
                                    ? Icons.view_agenda_rounded
                                    : Icons.view_sidebar_rounded,
                                color: colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Posição do menu',
                                      style: GoogleFonts.nunito(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      noTopo ? 'Topo' : 'Lateral',
                                      style: GoogleFonts.nunito(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: noTopo,
                                onChanged: (_) => rowContext
                                    .read<NavLayoutProvider>()
                                    .alternar(),
                                activeThumbColor: AppTheme.primary,
                                activeTrackColor:
                                    AppTheme.primary.withValues(alpha: 0.3),
                                inactiveThumbColor:
                                    colorScheme.onSurfaceVariant,
                                inactiveTrackColor: colorScheme.outline
                                    .withValues(alpha: 0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Divider(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'CONTA',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () {
                      Navigator.of(context).pop();
                      final usuarioProvider =
                          context.read<UsuarioProvider>();
                      final salvos = usuarioProvider.usuariosSalvos;
                      final atual  = usuarioProvider.usuarioLogado;
                      final outros = salvos
                          .where((u) => u.id != atual?.id)
                          .toList();
                      showDialog(
                        context: context,
                        builder: (_) => _TrocaUsuarioDialog(
                          usuarioAtual: atual,
                          usuariosSalvos: outros,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.switch_account_rounded,
                                color: AppTheme.primary, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Trocar usuário',
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.read<UsuarioProvider>().logout();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.error
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.logout_rounded,
                                color: AppTheme.error, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Sair da conta',
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.error,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppTheme.error
                                .withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrocaUsuarioDialog extends StatefulWidget {
  final UsuarioModel? usuarioAtual;
  final List<UsuarioModel> usuariosSalvos;

  const _TrocaUsuarioDialog({
    required this.usuarioAtual,
    required this.usuariosSalvos,
  });

  @override
  State<_TrocaUsuarioDialog> createState() => _TrocaUsuarioDialogState();
}

class _TrocaUsuarioDialogState extends State<_TrocaUsuarioDialog> {
  late List<UsuarioModel> _usuariosSalvos;
  UsuarioModel? get usuarioAtual => widget.usuarioAtual;

  @override
  void initState() {
    super.initState();
    _usuariosSalvos = List.of(widget.usuariosSalvos);
  }

  Future<void> _confirmarRemocao(UsuarioModel u) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text('Remover usuário salvo',
            style: GoogleFonts.raleway(fontWeight: FontWeight.w700)),
        content: Text(
          'Remover "${u.nome}" da lista de troca rápida nesta máquina? '
          'Será necessário digitar a senha novamente para entrar com esse usuário.',
          style: GoogleFonts.nunito(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: ButtonStyle(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: Text('Cancelar', style: GoogleFonts.nunito()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.all(AppTheme.error),
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: Text('Remover',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmou == true && mounted) {
      await context.read<UsuarioProvider>().removerUsuarioSalvo(u);
      setState(() {
        _usuariosSalvos.removeWhere((e) => e.id == u.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuariosSalvos = _usuariosSalvos;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark      = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.switch_account_rounded,
                          color: AppTheme.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Trocar usuário',
                      style: GoogleFonts.raleway(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Fechar',
                      icon: Icon(Icons.close_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom().copyWith(
                          mouseCursor: WidgetStateProperty.all(
                              SystemMouseCursors.click)),
                    ),
                  ],
                ),
              ),
              Divider(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  height: 1),

              if (usuarioAtual != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Text(
                    'SESSÃO ATUAL',
                    style: GoogleFonts.nunito(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          AppTheme.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            AppTheme.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              AppTheme.accent.withValues(alpha: 0.15),
                          child: Text(
                            usuarioAtual!.nome[0].toUpperCase(),
                            style: GoogleFonts.nunito(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                usuarioAtual!.nome,
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                usuarioAtual!.role,
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.success
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Ativo',
                            style: GoogleFonts.nunito(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (usuariosSalvos.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Text(
                    'TROCAR PARA',
                    style: GoogleFonts.nunito(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ...usuariosSalvos.map((u) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () async {
                            final provider = this.context.read<UsuarioProvider>();
                            final ok = await provider.loginComoUsuario(u);
                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            if (!ok) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    provider.erro ?? 'Erro ao trocar usuário',
                                    style: GoogleFonts.nunito(),
                                  ),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            } else {
                              SessionState.welcomeShown = false;
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.12),
                                  child: Text(
                                    u.nome[0].toUpperCase(),
                                    style: GoogleFonts.nunito(
                                      color:
                                          colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.nome,
                                        style: GoogleFonts.nunito(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        u.role,
                                        style: GoogleFonts.nunito(
                                          fontSize: 11,
                                          color: colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                  tooltip: 'Remover desta lista',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _confirmarRemocao(u),
                                  style: IconButton.styleFrom().copyWith(
                                      mouseCursor: WidgetStateProperty.all(
                                          SystemMouseCursors.click)),
                                ),
                                Icon(
                                  Icons.login_rounded,
                                  size: 16,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ),
                    )),
              ] else if (usuarioAtual != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Text(
                    'TROCAR PARA',
                    style: GoogleFonts.nunito(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Nenhum outro usuário logou nesta máquina ainda.',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],

              Divider(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                  height: 1),

              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.read<UsuarioProvider>().iniciarTrocaUsuario();
                  },
                  icon: const Icon(Icons.person_add_rounded, size: 16),
                  label: Text('Entrar com outra conta',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ).copyWith(
                      mouseCursor: WidgetStateProperty.all(
                          SystemMouseCursors.click)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _mostrarPainelAlertas(
    BuildContext context, AlertasEstoqueProvider alertas) {
  showDialog(
    context: context,
    builder: (_) => _PainelAlertasDialog(alertas: alertas),
  );
}

class _AlertasTopBarChip extends StatelessWidget {
  final int totalAlertas;
  final VoidCallback onTap;

  const _AlertasTopBarChip({
    required this.totalAlertas,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const cor   = Color(0xFFDC2626);
    const corBg = Color(0x1ADC2626);

    return Material(
      color: corBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 14, color: cor),
              const SizedBox(width: 6),
              Text(
                '$totalAlertas crítico${totalAlertas > 1 ? 's' : ''}',
                style: GoogleFonts.nunito(
                  color: cor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertasSidebarBanner extends StatelessWidget {
  final int totalAlertas;
  final VoidCallback onTap;

  const _AlertasSidebarBanner({
    required this.totalAlertas,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const cor   = Color(0xFFDC2626);
    const corBg = Color(0x1ADC2626);

    return Material(
      color: corBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 15, color: cor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$totalAlertas material${totalAlertas > 1 ? 'is' : ''} em crítico',
                  style: GoogleFonts.nunito(
                    color: cor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 14, color: Color(0x99DC2626)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetiradaVeiculosBanner extends StatelessWidget {
  final int total;
  final VoidCallback onTap;

  const _RetiradaVeiculosBanner(
      {required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const cor   = Color(0xFF1E88E5);
    const corBg = Color(0x1A1E88E5);

    return Material(
      color: corBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.directions_car_rounded,
                  size: 15, color: cor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$total veículo${total > 1 ? 's' : ''} p/ retirar hoje',
                  style: GoogleFonts.nunito(
                    color: cor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 14, color: Color(0x991E88E5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusNotificacoesIndicador extends StatelessWidget {
  final bool conectado;
  const _StatusNotificacoesIndicador({required this.conectado});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: (conectado ? Colors.green : Colors.orange).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (conectado ? Colors.green : Colors.orange).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: conectado ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              conectado ? 'Notificações ativas' : 'Polling ativo',
              style: GoogleFonts.nunito(
                color: conectado ? Colors.green : Colors.orange,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PainelAlertasDialog extends StatefulWidget {
  final AlertasEstoqueProvider alertas;
  const _PainelAlertasDialog({required this.alertas});

  @override
  State<_PainelAlertasDialog> createState() => _PainelAlertasDialogState();
}

class _PainelAlertasDialogState extends State<_PainelAlertasDialog> {
  final Set<int> _selecionados = {};

  void _toggleSelecao(int id) {
    setState(() {
      if (_selecionados.contains(id)) {
        _selecionados.remove(id);
      } else {
        _selecionados.add(id);
      }
    });
  }

  void _toggleTodos(List alertas) {
    setState(() {
      if (_selecionados.length == alertas.length) {
        _selecionados.clear();
      } else {
        _selecionados.addAll(alertas.map((a) => a.id as int));
      }
    });
  }

  void _orcarSelecionados() {
    final alertas = widget.alertas.alertas;
    final selecionados = alertas.where((a) => _selecionados.contains(a.id)).toList();
    if (selecionados.isEmpty) return;

    final todosMateriais = context.read<MaterialProvider>().materiais;

    final itens = selecionados.map((alerta) {
      final materialCompleto = todosMateriais.cast<dynamic>().firstWhere(
        (m) => m.id == alerta.id,
        orElse: () => null,
      );

      final precos = <int, PrecoFornecedorData>{};
      if (materialCompleto != null) {
        for (final fm in materialCompleto.fornecedorMateriais) {
          precos[fm.fornecedorId] = PrecoFornecedorData(
            fornecedorNome: fm.fornecedorNome,
            preco: fm.preco > 0 ? fm.preco : null,
          );
        }
      }

      return ItemOrcamentoData(
        materialId:            alerta.id,
        materialNome:          alerta.nome,
        materialUnidade:       alerta.unidade,
        materialCategoria:     alerta.categoria,
        materialMedida:        alerta.medida,
        materialEspessura:     alerta.espessura,
        materialIdentificador: alerta.identificador,
        materialStatus:        'CRITICO',
        materialLargura:       materialCompleto?.largura,
        materialComprimento:   materialCompleto?.comprimento,
        estoqueMinimo:         alerta.estoqueMinimo,
        precos:                precos,
      );
    }).toList();

    final titulo = selecionados.length == 1
        ? 'Orç. ${selecionados.first.nome}'
        : 'Orç. Críticos (${selecionados.length})';

    context.read<OrcamentoProvider>().adicionarItensEmLote(titulo, itens);
    OrcamentoPage.abrirEditorAoEntrar = true;

    Navigator.of(context).pop();
    context.go('/orcamento');
  }

  @override
  Widget build(BuildContext context) {
    final itens = widget.alertas.alertas;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final todosSelecionados = itens.isNotEmpty && _selecionados.length == itens.length;
    final temSelecao = _selecionados.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: isDark ? 0.5 : 0.12),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFDC2626), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Alertas de Estoque',
                      style: GoogleFonts.raleway(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.alertas.totalAlertas} itens',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Fechar',
                      icon: Icon(Icons.close_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom().copyWith(
                          mouseCursor: WidgetStateProperty.all(
                              SystemMouseCursors.click)),
                    ),
                  ],
                ),
              ),
              Divider(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  height: 1),

              if (itens.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Tooltip(
                        message: todosSelecionados ? 'Desmarcar todos' : 'Selecionar todos',
                        child: InkWell(
                          onTap: () => _toggleTodos(itens),
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: todosSelecionados,
                                tristate: true,
                                onChanged: (_) => _toggleTodos(itens),
                                activeColor: AppTheme.primary,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                todosSelecionados ? 'Desmarcar todos' : 'Selecionar todos',
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (temSelecao) ...[
                        const Spacer(),
                        Text(
                          '${_selecionados.length} selecionado${_selecionados.length > 1 ? 's' : ''}',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: SizedBox(
                  width: 400,
                  height: 320,
                  child: itens.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 48, color: colorScheme.outline),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum material em alerta',
                                style: GoogleFonts.nunito(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _AlertaSecaoHeader(
                                label: 'Críticos — abaixo do mínimo',
                                count: itens.length,
                                cor: const Color(0xFFDC2626),
                                icone: Icons.error_outline_rounded,
                              ),
                              const SizedBox(height: 6),
                              ...itens.map((a) => _AlertaItemTile(
                                alerta: a,
                                selecionado: _selecionados.contains(a.id),
                                onToggle: () => _toggleSelecao(a.id),
                              )),
                            ],
                          ),
                        ),
                ),
              ),

              Divider(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context
                            .read<MaterialProvider>()
                            .definirFiltroStatusPendente('CRITICO');
                        context.go('/estoque');
                      },
                      icon: const Icon(Icons.inventory_2_rounded, size: 15),
                      label: Text('Ver no Estoque', style: GoogleFonts.nunito()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.onSurfaceVariant,
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: temSelecao ? _orcarSelecionados : null,
                      icon: const Icon(Icons.request_quote_rounded, size: 15),
                      label: Text(
                        temSelecao
                            ? 'Orçar (${_selecionados.length})'
                            : 'Orçar selecionados',
                        style: GoogleFonts.nunito(),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
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

class _PainelRetiradaDialog extends StatelessWidget {
  final VeiculoProvider provider;
  const _PainelRetiradaDialog({required this.provider});

  @override
  Widget build(BuildContext context) {
    final veiculos = provider.veiculos
        .cast<VeiculoModel>()
        .where((v) => v.manutencoes.any((m) => m.retiradaHoje))
        .toList();
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.directions_car_rounded,
              color: Color(0xFF1E88E5), size: 20),
          const SizedBox(width: 8),
          const Text('Retirada de Veículos Hoje'),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 300,
        child: veiculos.isEmpty
            ? Center(
                child: Text('Nenhum veículo para retirar hoje.',
                    style: GoogleFonts.nunito()))
            : ListView.separated(
                itemCount: veiculos.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 8),
                itemBuilder: (_, i) {
                  final v = veiculos[i];
                  return ListTile(
                    leading: const Icon(Icons.directions_car,
                        color: Color(0xFF1E88E5)),
                    title: Text(v.nome,
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(v.placa,
                        style: GoogleFonts.nunito(fontSize: 12)),
                    dense: true,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Fechar',
              style: GoogleFonts.nunito(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant)),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            context.go('/veiculos');
          },
          icon: const Icon(Icons.directions_car_rounded, size: 15),
          label: Text('Ir para Veículos', style: GoogleFonts.nunito()),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1E88E5),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
  final dynamic alerta;
  final bool selecionado;
  final VoidCallback? onToggle;
  const _AlertaItemTile({
    required this.alerta,
    this.selecionado = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const cor = Color(0xFFDC2626);

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
    final qtd     = (alerta.quantidade as double);
    final min     = (alerta.estoqueMinimo as double);
    final qtdStr  = qtd % 1 == 0
        ? qtd.toStringAsFixed(0)
        : qtd.toStringAsFixed(2);
    final minStr  = min % 1 == 0
        ? min.toStringAsFixed(0)
        : min.toStringAsFixed(2);
    return MouseRegion(
      cursor: onToggle != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selecionado
                ? AppTheme.primary.withValues(alpha: 0.10)
                : cor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: selecionado ? AppTheme.primary : cor,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              if (onToggle != null) ...[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: selecionado,
                    onChanged: (_) => onToggle!(),
                    activeColor: AppTheme.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alerta.nome as String,
                      style: GoogleFonts.nunito(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitulo.isNotEmpty)
                      Text(
                        subtitulo,
                        style: GoogleFonts.nunito(
                          color: Theme.of(context).colorScheme.outline,
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
                      color: selecionado ? AppTheme.primary : cor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'mín $minStr',
                    style: GoogleFonts.nunito(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 10,
                    ),
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