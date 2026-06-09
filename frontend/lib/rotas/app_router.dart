import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:visual_premium/pages/gastos_categoria_page.dart';
import 'package:visual_premium/pages/veiculo_page.dart';         // ← NOVO
import '../pages/admin_page.dart';
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
  static final rootNavigatorKey   = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static const _rotasBloqueadasParaProducao = [
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
      navigatorKey: rootNavigatorKey,
      initialLocation: '/login',
      refreshListenable: usuarioProvider,

      redirect: (context, state) {
        final usuario = usuarioProvider.usuarioLogado;
        final path    = state.matchedLocation;
        final logado  = usuario != null;
        final naLogin = path == '/login';

        if (!logado) {
          return naLogin ? null : '/login';
        }

        final roleUp     = usuario.role.trim().toUpperCase();
        final isProducao = AppShell.isProducaoRole(usuario.role);
        final isAdmin    = roleUp == 'ADMIN';
        final isGerente  = roleUp == 'GERENTE';
        final isCompras  = roleUp == 'COMPRAS';

        if (naLogin) {
          return isProducao ? '/producao' : '/inicio';
        }

        if (isAdmin || isGerente) return null;

        if (isProducao &&
            _rotasBloqueadasParaProducao.any((r) => path.startsWith(r))) {
          return '/producao';
        }
        if (isProducao && path.startsWith('/admin')) {
          return '/producao';
        }

        if (isCompras && path.startsWith('/admin')) return '/inicio';

        return null;
      },

      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginPage(),
        ),

        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (_, __, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/inicio', builder: (_, __) => const InicioPage()),

            GoRoute(
              path: '/estoque',
              builder: (context, __) => EstoquePage(
                roleUsuario:
                    Provider.of<UsuarioProvider>(context, listen: false)
                            .usuarioLogado
                            ?.role ??
                        '',
              ),
            ),

            GoRoute(
                path: '/fornecedores',
                builder: (_, __) => const FornecedoresPage()),
            GoRoute(
                path: '/orcamento',
                builder: (_, __) => const OrcamentoPage()),
            GoRoute(
                path: '/ordem-compra',
                builder: (_, state) =>
                    OrdemCompraPage(ocIdParaAbrir: state.extra as int?)),
            GoRoute(
                path: '/controle-estoque',
                builder: (_, __) => const ControleEstoquePage()),
            GoRoute(
                path: '/historico',
                builder: (_, __) => const HistoricoPage()),
            GoRoute(
                path: '/relatorio-os',
                builder: (_, __) => const RelatorioOSPage()),
            GoRoute(
                path: '/producao',
                builder: (_, __) => const ProducaoPage()),
            GoRoute(path: '/admin', builder: (_, __) => const AdminPage()),
            GoRoute(
                path: '/gastos-categoria',
                builder: (_, __) => const GastosCategoriaPage()),
            GoRoute(
                path: '/veiculos',                              // ← NOVO
                builder: (_, __) => const VeiculoPage()),
          ],
        ),
      ],
    );
  }
}