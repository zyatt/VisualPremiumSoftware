import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../pages/login_page.dart';
import '../pages/inicio_page.dart';
import '../pages/estoque_page.dart';
import '../pages/fornecedores_page.dart';
import '../pages/orcamento_page.dart';
import '../pages/ordem_compra_page.dart';
import '../pages/controle_estoque_page.dart';
import '../pages/historico_page.dart';
import '../pages/relatorio_os_page.dart';
import '../pages/producao_page.dart';
import '../widgets/app_shell.dart';
import '../providers/usuario_provider.dart';

class AppRouter {
  static final _rootNavigatorKey  = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  // Rotas acessíveis apenas por usuários gerais (não-PRODUCAO)
  static const _rotasGerais = [
    '/inicio',
    '/estoque',
    '/fornecedores',
    '/orcamento',
    '/ordem-compra',
    '/controle-estoque',
    '/historico',
    '/relatorio-os',
  ];

  static GoRouter buildRouter(UsuarioProvider usuarioProvider) {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/login',

      // Faz o router re-avaliar o redirect automaticamente sempre que
      // usuarioProvider notificar (login, logout, etc.)
      refreshListenable: usuarioProvider,

      // ── Redirect GLOBAL ────────────────────────────────────────────────────
      // Roda em TODA navegação. É o único lugar onde a lógica de role deve viver.
      redirect: (context, state) {
        final usuario = usuarioProvider.usuarioLogado;
        final path    = state.matchedLocation;
        final logado  = usuario != null;
        final naLogin = path == '/login';

        // Não logado → força login
        if (!logado) {
          return naLogin ? null : '/login';
        }

        final isProducao = AppShell.isProducaoRole(usuario.role);
        final isAdmin    = usuario.role.toUpperCase() == 'ADMIN';

        // Logado na tela de login
        if (naLogin) {
          return isProducao ? '/producao' : '/inicio';
        }

        // ADMIN acessa tudo — sem restrições de rota
        if (isAdmin) return null;

        // PRODUCAO puro tentando acessar rotas gerais
        if (isProducao && _rotasGerais.any((r) => path.startsWith(r))) {
          return '/producao';
        }

        // Usuário comum tentando acessar produção
        if (!isProducao && path.startsWith('/producao')) {
          return '/inicio';
        }

        return null;
      },

      routes: [
        // Login — fora do shell (sem menu lateral)
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginPage(),
        ),

        // Shell — todas as páginas autenticadas
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (_, __, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/inicio',           builder: (_, __) => const InicioPage()),
            GoRoute(path: '/estoque',          builder: (_, __) => const EstoquePage()),
            GoRoute(path: '/fornecedores',     builder: (_, __) => const FornecedoresPage()),
            GoRoute(path: '/orcamento',        builder: (_, __) => const OrcamentoPage()),
            GoRoute(
              path: '/ordem-compra',
              builder: (_, state) => OrdemCompraPage(ocIdParaAbrir: state.extra as int?),
            ),
            GoRoute(path: '/controle-estoque', builder: (_, __) => const ControleEstoquePage()),
            GoRoute(path: '/historico',        builder: (_, __) => const HistoricoPage()),
            GoRoute(path: '/relatorio-os',     builder: (_, __) => const RelatorioOSPage()),
            GoRoute(path: '/producao',         builder: (_, __) => const ProducaoPage()),
          ],
        ),
      ],
    );
  }
}