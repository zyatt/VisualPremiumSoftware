import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'rotas/app_router.dart';
import 'theme/app_theme.dart';

import 'providers/usuario_provider.dart';
import 'providers/material_provider.dart';
import 'providers/produto_provider.dart';
import 'providers/estoque_provider.dart';
import 'providers/fornecedor_provider.dart';
import 'providers/orcamento_provider.dart';
import 'providers/ordem_compra_provider.dart';
import 'providers/relatorio_os_provider.dart';
import 'providers/producao_provider.dart';
import 'providers/audit_log_provider.dart';
import 'providers/gastos_categoria_provider.dart';
import 'providers/alertas_estoque_provider.dart';
import 'providers/veiculo_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/orcamento_venda_provider.dart';
import 'providers/solicitacao_material_provider.dart';
import 'providers/chat_provider.dart';

import 'widgets/update_checker_widget.dart';
import 'widgets/theme_transition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final usuarioProvider             = UsuarioProvider();
  final orcamentoProvider           = OrcamentoProvider();
  final solicitacaoMaterialProvider = SolicitacaoMaterialProvider();
  usuarioProvider.setOrcamentoProvider(orcamentoProvider);
  usuarioProvider.setSolicitacaoMaterialProvider(solicitacaoMaterialProvider);

  await usuarioProvider.restaurarSessao();

  runApp(VisualPremiumApp(
    usuarioProvider:             usuarioProvider,
    orcamentoProvider:           orcamentoProvider,
    solicitacaoMaterialProvider: solicitacaoMaterialProvider,
  ));
}

class VisualPremiumApp extends StatefulWidget {
  final UsuarioProvider             usuarioProvider;
  final OrcamentoProvider           orcamentoProvider;
  final SolicitacaoMaterialProvider solicitacaoMaterialProvider;

  const VisualPremiumApp({
    super.key,
    required this.usuarioProvider,
    required this.orcamentoProvider,
    required this.solicitacaoMaterialProvider,
  });

  @override
  State<VisualPremiumApp> createState() => _VisualPremiumAppState();
}

class _VisualPremiumAppState extends State<VisualPremiumApp> {
  // Criado uma única vez. Se isso for reconstruído a cada troca de tema
  // (ex: dentro de um Consumer<ThemeProvider>), o GoRouter reinicia do zero
  // em initialLocation: '/' — ou seja, a LoadingPage reaparece a cada toggle.
  late final GoRouter _router = AppRouter.buildRouter(widget.usuarioProvider);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.usuarioProvider),
        ChangeNotifierProvider.value(value: widget.orcamentoProvider),
        ChangeNotifierProvider(create: (_) => MaterialProvider()),
        ChangeNotifierProvider(create: (_) => ProdutoProvider()),
        ChangeNotifierProvider(create: (_) => EstoqueProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => OrdemCompraProvider()),
        ChangeNotifierProvider(create: (_) => RelatorioOSProvider()),
        ChangeNotifierProvider(create: (_) => ProducaoProvider()),
        ChangeNotifierProvider(create: (_) => AuditLogProvider()),
        ChangeNotifierProvider(create: (_) => GastosCategoriaProvider()),
        ChangeNotifierProvider(create: (_) => AlertasEstoqueProvider()),
        ChangeNotifierProvider(create: (_) => VeiculoProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => OrcamentoVendaProvider()),
        ChangeNotifierProvider.value(value: widget.solicitacaoMaterialProvider),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp.router(
            title: 'Visual Premium',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeProvider.themeMode,   // ← controlado pelo provider
            // AnimatedTheme faz a transição de cores (fundo, texto, bordas
            // etc.) suavemente em vez do corte seco que MaterialApp aplica
            // por padrão ao trocar theme/darkTheme. O ThemeTransitionOverlay
            // adiciona por cima um efeito de revelação circular a partir do
            // ponto tocado (ver widgets/theme_transition.dart), que é quem
            // dispara o toggle propriamente dito.
            builder: (context, child) => ThemeTransitionOverlay(
              child: AnimatedTheme(
                data: themeProvider.isDark ? AppTheme.dark : AppTheme.light,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: UpdateChecker(child: child!),
              ),
            ),
            routerConfig: _router, // ← reaproveitado, nunca recriado
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('pt', 'BR'),
              Locale('en', 'US'),
            ],
            locale: const Locale('pt', 'BR'),
          );
        },
      ),
    );
  }
}