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
import '../widgets/app_shell.dart';

class AppRouter {
  static final _rootNavigatorKey  = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
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
          GoRoute(path: '/ordem-compra',     builder: (_, state) => OrdemCompraPage(ocIdParaAbrir: state.extra as int?)),
          GoRoute(path: '/controle-estoque', builder: (_, __) => const ControleEstoquePage()),
          GoRoute(path: '/historico',        builder: (_, __) => const HistoricoPage()),
          GoRoute(path: '/relatorio-os',     builder: (_, __) => const RelatorioOSPage()),
        ],
      ),
    ],
  );
}