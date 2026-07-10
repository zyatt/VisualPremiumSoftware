import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/usuario_provider.dart';
import '../models/usuario_model.dart';
import '../providers/alertas_estoque_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/veiculo_provider.dart';
import '../providers/solicitacao_material_provider.dart';
import '../providers/material_provider.dart';
import '../providers/chat_provider.dart';
import 'chat_floating_widget.dart';
import '../models/veiculo_model.dart';
import '../theme/app_theme.dart';
import 'welcome_banner.dart';
import 'nova_solicitacao_banner.dart';
import 'solicitacao_alterada_banner.dart';
import 'material_critico_banner.dart';
import 'theme_transition.dart';

/// Controle de estado de sessão para evitar exibir o banner mais de uma vez.
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
    return r == 'PRODUÇÃO' || r == 'PRODUCAO';
  }

  /// Somente estes cargos devem ver o banner flutuante de nova solicitação
  /// de material — o autor da solicitação nunca recebe o evento (o backend
  /// já o exclui do broadcast), então não é preciso filtrar isso aqui.
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
      const AppMenuItem(icon: Icons.request_quote_rounded,           label: 'Orç. Compras',       route: '/orcamento',             color: Color(0xFFFF9800)),
      const AppMenuItem(icon: Icons.sell_rounded,                    label: 'Orç. Vendas',        route: '/orcamento-venda',       color: Color(0xFF22C55E)),
      const AppMenuItem(icon: Icons.shopping_cart_rounded,           label: 'Ordem de Compra',    route: '/ordem-compra',          color: Color(0xFF4CAF50)),
      const AppMenuItem(icon: Icons.sync_alt_rounded,                label: 'Controle Estoque',   route: '/controle-estoque',      color: Color(0xFFE91E63)),
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
      // Gerente não vê: Admin, Gastos e Orç. Vendas
      return completo
          .where((e) => !['/gastos-categoria', '/orcamento-venda'].contains(e.route))
          .toList();
    }

    // COMPRAS e demais roles
    return completo
        .where((e) => !['/gastos-categoria', '/orcamento-venda'].contains(e.route))
        .toList();
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Id do usuário para o qual já conectamos SSE/chat. Usado para detectar
  /// troca de usuário (via "Trocar para") e reconectar tudo, já que o
  /// AppShell NUNCA é recriado nesse fluxo — initState() só roda uma vez.
  int? _usuarioIdConectado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertasEstoqueProvider>().iniciarPolling();
      context.read<VeiculoProvider>().carregarVeiculos();
      _conectarParaUsuarioAtual();
    });
  }

  /// (Re)conecta o SSE de notificações e inicializa o chat para o usuário
  /// logado no momento. Chamado tanto no initState quanto sempre que
  /// detectamos, no build(), que o usuário ativo mudou (troca de usuário
  /// sem reiniciar o app).
  void _conectarParaUsuarioAtual() {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    final token   = context.read<UsuarioProvider>().token;

    _usuarioIdConectado = usuario?.id;

    // Conecta (ou reconecta) ao stream SSE de novas solicitações
    context.read<SolicitacaoMaterialProvider>().conectarNotificacoes();

    // Conecta (ou reconecta) ao stream SSE de atualizações de materiais
    context.read<MaterialProvider>().conectarNotificacoes();

    // Trocar de usuário não deve deixar a conversa do usuário anterior
    // aberta na tela: recolhe o mini-chat flutuante (se estiver expandido)
    // antes de inicializar o chat do novo usuário.
    context.read<ChatProvider>().minimizarWidgetFlutuante();

    // Inicializa chat com id e token do usuário logado
    if (usuario != null && token != null) {
      context.read<ChatProvider>().inicializar(usuario.id, token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isWide   = MediaQuery.of(context).size.width >= 800;

    final usuario = context.watch<UsuarioProvider>().usuarioLogado;

    // ── Detecta troca de usuário (via "Trocar para") e reconecta SSE/chat ──
    // O AppShell não é recriado nesse fluxo, então é aqui que percebemos
    // que o usuário ativo mudou e disparamos a reconexão.
    if (usuario != null && usuario.id != _usuarioIdConectado) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _conectarParaUsuarioAtual();
      });
    }

    // ── Visibilidade real da tela de Chat ──────────────────────────────────
    // O ChatPage vive dentro de um StatefulShellRoute.indexedStack, então ela
    // NUNCA é destruída ao trocar de aba pela sidebar (fica só escondida no
    // IndexedStack). Por isso o dispose() da própria página não é confiável
    // pra saber se o usuário está "olhando" o chat agora — quem sabe disso
    // de verdade é o AppShell, que reconstrói a cada troca de rota.
    context.read<ChatProvider>().definirPaginaVisivel(location.startsWith('/chat'));

    // ── Visibilidade real da tela de Solicitações de Material ─────────────
    // Mesmo motivo do Chat: a página vive dentro de um StatefulShellBranch
    // (IndexedStack) e seu dispose() não é chamado ao trocar de aba, então
    // quem sabe se ela está realmente visível é o AppShell, não a própria
    // página.
    context
        .read<SolicitacaoMaterialProvider>()
        .definirPaginaVisivel(location.startsWith('/solicitacoes-material'));

    // ── Visibilidade real da tela de Estoque (Materiais) ───────────────────
    // Mesmo motivo do Chat e Solicitações: a página vive dentro de um
    // StatefulShellBranch (IndexedStack) e seu dispose() não é chamado ao
    // trocar de aba, então quem sabe se ela está realmente visível é o
    // AppShell, não a própria página.
    context
        .read<MaterialProvider>()
        .definirPaginaVisivel(location.startsWith('/estoque'));

    // ── Banner de boas-vindas (global — funciona para qualquer role) ──────────
    // Roda uma única vez por sessão, independente da rota inicial do usuário.
    final nome = usuario?.nome ?? '';
    if (!SessionState.welcomeShown && nome.isNotEmpty) {
      SessionState.welcomeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) WelcomeBanner.show(context, nome);
      });
    }

    // ── Banner flutuante de nova solicitação de material ──────────────────
    // Aparece uma única vez por evento SSE recebido, e somente para quem
    // pode agir sobre solicitações (ADMIN, GERENTE, COMPRAS). O autor da
    // solicitação nunca chega a receber o evento (o backend já o exclui do
    // broadcast), então não precisamos checar "é o autor?" aqui.
    final notificacaoSolicitacao =
        context.watch<SolicitacaoMaterialProvider>().notificacaoPendente;
    if (notificacaoSolicitacao != null) {
      final solProvRead = context.read<SolicitacaoMaterialProvider>();
      if (AppShell.podeReceberNotificacaoSolicitacao(usuario?.role)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            NovaSolicitacaoBanner.show(
              context,
              notificacaoSolicitacao,
              onTap: () => context.go('/solicitacoes-material'),
            );
          }
        });
      }
      // Consome de qualquer forma (mostrando ou não), garantindo exibição
      // única e evitando reprocessar o mesmo evento em rebuilds futuros.
      solProvRead.consumirNotificacaoPendente();
    }

    // ── Banner flutuante de solicitação alterada ───────────────────────────
    // Mesmo padrão do banner de nova solicitação, mas para edição/adição/
    // exclusão de materiais ou dados de uma solicitação já existente. O
    // autor da alteração nunca recebe este evento via SSE (o backend o
    // exclui do broadcast), então este banner só aparece para outros
    // usuários com permissão sobre solicitações.
    final notificacaoAlterada =
        context.watch<SolicitacaoMaterialProvider>().notificacaoAlteradaPendente;
    if (notificacaoAlterada != null) {
      final solProvReadAlterada = context.read<SolicitacaoMaterialProvider>();
      if (AppShell.podeReceberNotificacaoSolicitacao(usuario?.role)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            SolicitacaoAlteradaBanner.show(
              context,
              notificacaoAlterada,
              onTap: () => context.go('/solicitacoes-material'),
            );
          }
        });
      }
      solProvReadAlterada.consumirNotificacaoAlteradaPendente();
    }

    // ── Banner flutuante de material em estoque crítico ────────────────────
    // Aparece uma única vez por evento SSE 'material_critico', disparado pelo
    // backend somente na transição para CRITICO (não repete enquanto o
    // material permanece crítico). Mesmo público-alvo do banner de
    // solicitações: quem pode agir sobre compras/estoque.
    final notificacaoCritica =
        context.watch<MaterialProvider>().notificacaoCriticaPendente;
    if (notificacaoCritica != null) {
      final matProvRead = context.read<MaterialProvider>();
      if (AppShell.podeReceberNotificacaoSolicitacao(usuario?.role)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            MaterialCriticoBanner.show(
              context,
              notificacaoCritica,
              onTap: () {
                // Guarda os dados do material para a EstoquePage abrir
                // automaticamente a categoria certa já filtrada (nome,
                // identificador, medida, espessura).
                matProvRead.solicitarNavegacaoParaMaterial(notificacaoCritica);
                context.go('/estoque');
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

    // Adiciona o item Início no topo da sidebar (não aparece nos cards da Home)
    final sidebarItems = [
      const _NavItem(icon: Icons.home_rounded, label: 'Início', route: '/inicio'),
      ...items,
    ];

    final mostrarBolhaChat = !location.startsWith('/chat');

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              if (isWide)
                _Sidebar(currentRoute: location, items: sidebarItems),
              Expanded(child: widget.navigationShell),
            ],
          ),
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

// ─── Modelos ─────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  const _NavItem({required this.icon, required this.label, required this.route});
}

// ─── Sidebar wrapper (largura fixa) ──────────────────────────────────────────

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

// ─── Conteúdo da sidebar ─────────────────────────────────────────────────────

/// Logo animada da sidebar: flutua suavemente para cima e para baixo,
/// com uma leve rotação e um brilho pulsante ao redor — um toque vivo
/// sem ser exagerado.
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

    // Filtra o usuário atual da lista
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
    // Conta veículos que têm alguma manutenção com retiradaHoje == true
    final nRetirada = veiculoProv.veiculos
        .cast<VeiculoModel>()
        .where((v) => v.manutencoes.any((m) => m.retiradaHoje))
        .length;
    
    // Badge de novas solicitações
    final solProv          = context.watch<SolicitacaoMaterialProvider>();
    final nSolicitacoes    = solProv.novasSolicitacoes;

    // Badge de mensagens não lidas no chat
    final chatProv   = context.watch<ChatProvider>();
    final nChat      = chatProv.totalNaoLidas;

    const sidebarBg = AppTheme.sidebar;

    return Container(
      color: sidebarBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho / logo ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _AnimatedLogo(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Visual Premium',
                      style: GoogleFonts.raleway(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 6),

            // ── Status de notificações SSE ────────────────────────────────
            if (!AppShell.isProducaoRole(usuario?.role))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: _StatusNotificacoesIndicador(
                  conectado: solProv.notificacoesConectadas,
                ),
              ),

            // ── Banner de alertas de estoque ─────────────────────────────
            if (nAlertas > 0 && !AppShell.isProducaoRole(usuario?.role))
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: _AlertasSidebarBanner(
                  totalAlertas: nAlertas,
                  onTap: () => _mostrarPainelAlertas(context, alertas),
                ),
              ),

            // ── Banner de retirada de veículos hoje ──────────────────────
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

            // ── Itens de navegação ────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: widget.items.map((item) {
                  final isActive =
                      widget.currentRoute == item.route ||
                      (item.route != '/inicio' &&
                          widget.currentRoute
                              .startsWith('${item.route}/'));

                  // Badge de notificação: solicitações ou chat
                  final badge = item.route == '/solicitacoes-material' && nSolicitacoes > 0
                      ? nSolicitacoes
                      : item.route == '/chat' && nChat > 0
                          ? nChat
                          : 0;

                  return _SidebarTile(
                    item: item,
                    isActive: isActive,
                    badge: badge,
                  );
                }).toList(),
              ),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── Usuário + botão de configurações ─────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                radius: 14,
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
                              const Icon(Icons.unfold_more_rounded,
                                  size: 15, color: Colors.white24),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Configurações',
                    icon: const Icon(Icons.settings_rounded,
                        size: 18, color: Colors.white38),
                    onPressed: () => _abrirConfiguracoes(context),
                    style: IconButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(
                            SystemMouseCursors.click)),
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
                  style: GoogleFonts.nunito(
                      color: Colors.white24, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _mostrarPainelAlertas(
      BuildContext context, AlertasEstoqueProvider alertas) {
    showDialog(
      context: context,
      builder: (_) => _PainelAlertasDialog(alertas: alertas),
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

// ─── Tile individual ─────────────────────────────────────────────────────────

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  /// Número a mostrar no badge (0 = sem badge).
  final int badge;

  const _SidebarTile({
    required this.item,
    required this.isActive,
    this.badge = 0,
  });

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
                  color: isActive ? AppTheme.accent : Colors.white38,
                  size: 17,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.label,
                    style: GoogleFonts.nunito(
                      color:
                          isActive ? Colors.white : Colors.white54,
                      fontSize: 12,
                      fontWeight: isActive
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // ── Badge de notificação ──────────────────────────────
                if (badge > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444), // vermelho vivo
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

// ─── Dialog de Configurações ─────────────────────────────────────────────────

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
                    // Guarda o ponto onde o dedo/mouse tocou para usar como
                    // origem do efeito de revelação circular. É atualizado
                    // no pointer-down, que dispara antes do onTap/onChanged.
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
                  'CONTA',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // ── Trocar usuário ──────────────────────────────────────────
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

// ─── Dialog de troca de usuário ──────────────────────────────────────────────

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
            child: Text('Cancelar', style: GoogleFonts.nunito()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
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
              // ── Cabeçalho ────────────────────────────────────────────────
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

              // ── Usuário atual ─────────────────────────────────────────────
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

              // ── Outros usuários salvos ────────────────────────────────────
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
                            Navigator.of(context).pop();
                            final provider = context.read<UsuarioProvider>();
                            final ok = await provider.loginComoUsuario(u);
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
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

              // ── Entrar com outra conta ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.read<UsuarioProvider>().iniciarTrocaUsuario();
                    context.go('/login');
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

// ─── Banner compacto de alertas de estoque ───────────────────────────────────

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

// ─── Banner compacto de retirada de veículos ─────────────────────────────────

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

// ─── Indicador de status de notificações SSE ─────────────────────────────────

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

// ─── Painel de alertas ───────────────────────────────────────────────────────

class _PainelAlertasDialog extends StatelessWidget {
  final AlertasEstoqueProvider alertas;
  const _PainelAlertasDialog({required this.alertas});

  @override
  Widget build(BuildContext context) {
    final itens = alertas.alertas;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                      '${alertas.totalAlertas} itens',
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: SizedBox(
                  width: 400,
                  height: 360,
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
                              ...itens.map((a) => _AlertaItemTile(alerta: a)),
                            ],
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context
                            .read<MaterialProvider>()
                            .definirFiltroStatusPendente('CRITICO');
                        context.go('/estoque');
                      },
                      icon: const Icon(Icons.inventory_2_rounded, size: 15),
                      label:
                          Text('Ir para Estoque', style: GoogleFonts.nunito()),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ).copyWith(
                          mouseCursor: WidgetStateProperty.all(
                              SystemMouseCursors.click)),
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

// ─── Painel de retirada de veículos ──────────────────────────────────────────

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

// ─── Seção header de alertas ─────────────────────────────────────────────────

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

// ─── Item de alerta ──────────────────────────────────────────────────────────

class _AlertaItemTile extends StatelessWidget {
  final dynamic alerta;
  const _AlertaItemTile({required this.alerta});

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

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    color:
                        Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitulo.isNotEmpty)
                  Text(
                    subtitulo,
                    style: GoogleFonts.nunito(
                      color:
                          Theme.of(context).colorScheme.outline,
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
                  color: Theme.of(context).colorScheme.outline,
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