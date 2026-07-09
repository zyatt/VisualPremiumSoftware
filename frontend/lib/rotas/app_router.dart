import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:visual_premium/pages/gastos_categoria_page.dart';
import 'package:visual_premium/pages/solicitacoes_material_page.dart';
import 'package:visual_premium/pages/veiculo_page.dart';
import 'package:visual_premium/pages/orcamento_venda_page.dart'; // ← NOVO
import '../pages/admin_page.dart';
import '../pages/loading_page.dart';
import '../pages/login_page.dart';
import '../pages/inicio_page.dart';
import '../pages/estoque_page.dart';
import '../pages/produto_page.dart';
import '../pages/fornecedores_page.dart';
import '../pages/orcamento_page.dart';
import '../pages/ordem_compra_page.dart';
import '../pages/controle_estoque_page.dart';
import '../pages/relatorio_os_page.dart';
import '../pages/producao_page.dart';
import '../pages/chat_page.dart';
import '../widgets/app_shell.dart';
import '../providers/usuario_provider.dart';

/// Chave global que permite chamar métodos do state de OrdemCompraPage
/// mesmo quando a branch já está montada (StatefulShellRoute preserva estado).
final ordemCompraPageKey = GlobalKey<OrdemCompraPageState>();

class AppRouter {
  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  // Uma chave de Navigator por branch, para que cada seção mantenha sua
  // própria pilha de navegação (e portanto seu estado) preservada quando o
  // usuário troca de página pelo menu lateral.
  static final _inicioNavigatorKey          = GlobalKey<NavigatorState>(debugLabel: 'inicio');
  static final _estoqueNavigatorKey         = GlobalKey<NavigatorState>(debugLabel: 'estoque');
  static final _produtosNavigatorKey        = GlobalKey<NavigatorState>(debugLabel: 'produtos');
  static final _fornecedoresNavigatorKey    = GlobalKey<NavigatorState>(debugLabel: 'fornecedores');
  static final _orcamentoNavigatorKey       = GlobalKey<NavigatorState>(debugLabel: 'orcamento');
  static final _orcamentoVendaNavigatorKey  = GlobalKey<NavigatorState>(debugLabel: 'orcamento-venda');
  static final _ordemCompraNavigatorKey     = GlobalKey<NavigatorState>(debugLabel: 'ordem-compra');
  static final _controleEstoqueNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'controle-estoque');
  static final _relatorioOSNavigatorKey     = GlobalKey<NavigatorState>(debugLabel: 'relatorio-os');
  static final _producaoNavigatorKey        = GlobalKey<NavigatorState>(debugLabel: 'producao');
  static final _adminNavigatorKey           = GlobalKey<NavigatorState>(debugLabel: 'admin');
  static final _gastosCategoriaNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'gastos-categoria');
  static final _veiculosNavigatorKey        = GlobalKey<NavigatorState>(debugLabel: 'veiculos');
  static final _solicitacoesMaterialNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'solicitacoes-material');
  static final _chatNavigatorKey                  = GlobalKey<NavigatorState>(debugLabel: 'chat');

  // /inicio é intencionalmente omitido: todos os roles acessam a home.
  static const _rotasBloqueadasParaProducao = [
    '/estoque',
    '/produtos',
    '/fornecedores',
    '/orcamento',
    '/orcamento-venda',
    '/ordem-compra',
    '/controle-estoque',
    '/relatorio-os',
    '/gastos-categoria',
    '/veiculos',
    '/solicitacoes-material',
  ];

  static GoRouter buildRouter(UsuarioProvider usuarioProvider) {
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/',
      refreshListenable: usuarioProvider,

      redirect: (context, state) {
        final usuario = usuarioProvider.usuarioLogado;
        final path    = state.matchedLocation;
        final logado  = usuario != null;
        final naLogin = path == '/login';
        final naLoading = path == '/';

        if (naLoading) return null;

        if (!logado) {
          if (naLogin) return null;
          return '/login';
        }

        final roleUp     = usuario.role.trim().toUpperCase();
        final isProducao = AppShell.isProducaoRole(usuario.role);
        final isAdmin    = roleUp == 'ADMIN';
        final isGerente  = roleUp == 'GERENTE';
        final isCompras  = roleUp == 'COMPRAS';
        final isOrcamentista = roleUp == 'ORCAMENTISTA';

        if (naLogin) {
          // Todos os roles caem na home; a home exibe apenas os cards permitidos.
          return '/inicio';
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

        if (isCompras &&
            (path.startsWith('/gastos-categoria') ||
                path.startsWith('/produtos') ||
                path.startsWith('/orcamento-venda'))) {
          return '/inicio';
        }

        // ORCAMENTISTA: acesso somente a estoque, produtos e orçamento de vendas.
        // Qualquer outra rota (incluindo /inicio) cai em /orcamento-venda.
        if (isOrcamentista) {
          const rotasPermitidas = [
            '/inicio',
            '/orcamento-venda',
            '/estoque',
            '/produtos',
          ];
          if (!rotasPermitidas.any((r) => path.startsWith(r))) {
            return '/orcamento-venda';
          }
        }

        return null;
      },

      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const LoadingPage(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginPage(),
        ),

        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              navigatorKey: _inicioNavigatorKey,
              routes: [
                GoRoute(path: '/inicio', builder: (_, __) => const InicioPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _estoqueNavigatorKey,
              routes: [
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
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _produtosNavigatorKey,
              routes: [
                GoRoute(path: '/produtos', builder: (_, __) => const ProdutoPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _fornecedoresNavigatorKey,
              routes: [
                GoRoute(path: '/fornecedores', builder: (_, __) => const FornecedoresPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _orcamentoNavigatorKey,
              routes: [
                GoRoute(path: '/orcamento', builder: (_, __) => const OrcamentoPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _ordemCompraNavigatorKey,
              routes: [
                GoRoute(
                    path: '/ordem-compra',
                    builder: (_, state) => OrdemCompraPage(
                          key: ordemCompraPageKey,
                          ocIdParaAbrir: state.extra as int?,
                        )),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _controleEstoqueNavigatorKey,
              routes: [
                GoRoute(path: '/controle-estoque', builder: (_, __) => const ControleEstoquePage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _relatorioOSNavigatorKey,
              routes: [
                GoRoute(path: '/relatorio-os', builder: (_, __) => const RelatorioOSPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _producaoNavigatorKey,
              routes: [
                GoRoute(path: '/producao', builder: (_, __) => const ProducaoPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _adminNavigatorKey,
              routes: [
                GoRoute(path: '/admin', builder: (_, __) => const AdminPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _gastosCategoriaNavigatorKey,
              routes: [
                GoRoute(path: '/gastos-categoria', builder: (_, __) => const GastosCategoriaPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _veiculosNavigatorKey,
              routes: [
                GoRoute(path: '/veiculos', builder: (_, __) => const VeiculoPage()),
              ],
            ),
            StatefulShellBranch(                                   // ← NOVO
              navigatorKey: _orcamentoVendaNavigatorKey,
              routes: [
                GoRoute(path: '/orcamento-venda', builder: (_, __) => const OrcamentoVendaPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _solicitacoesMaterialNavigatorKey,
              routes: [
                GoRoute(path: '/solicitacoes-material', builder: (_, __) => const SolicitacoesMaterialPage()),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _chatNavigatorKey,
              routes: [
                GoRoute(path: '/chat', builder: (_, __) => const ChatPage()),
              ],
            ),
          ],
        ),
      ],
    );
  }
}