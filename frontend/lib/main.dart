import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'rotas/app_router.dart';
import 'theme/app_theme.dart';

import 'providers/usuario_provider.dart';
import 'providers/material_provider.dart';
import 'providers/produto_provider.dart';
import 'providers/estoque_provider.dart';
import 'providers/fornecedor_provider.dart';
import 'providers/orcamento_provider.dart';
import 'providers/ordem_compra_provider.dart';
import 'providers/historico_provider.dart';
import 'providers/relatorio_os_provider.dart';
import 'providers/producao_provider.dart';
import 'providers/audit_log_provider.dart';
import 'providers/gastos_categoria_provider.dart';
import 'providers/alertas_estoque_provider.dart';
import 'providers/veiculo_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/orcamento_venda_provider.dart';

import 'widgets/update_checker_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final usuarioProvider   = UsuarioProvider();
  final orcamentoProvider = OrcamentoProvider();
  usuarioProvider.setOrcamentoProvider(orcamentoProvider);

  await usuarioProvider.restaurarSessao();

  runApp(VisualPremiumApp(
    usuarioProvider:   usuarioProvider,
    orcamentoProvider: orcamentoProvider,
  ));
}

class VisualPremiumApp extends StatelessWidget {
  final UsuarioProvider   usuarioProvider;
  final OrcamentoProvider orcamentoProvider;

  const VisualPremiumApp({
    super.key,
    required this.usuarioProvider,
    required this.orcamentoProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: usuarioProvider),
        ChangeNotifierProvider.value(value: orcamentoProvider),
        ChangeNotifierProvider(create: (_) => MaterialProvider()),
        ChangeNotifierProvider(create: (_) => ProdutoProvider()),
        ChangeNotifierProvider(create: (_) => EstoqueProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => OrdemCompraProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoProvider()),
        ChangeNotifierProvider(create: (_) => RelatorioOSProvider()),
        ChangeNotifierProvider(create: (_) => ProducaoProvider()),
        ChangeNotifierProvider(create: (_) => AuditLogProvider()),
        ChangeNotifierProvider(create: (_) => GastosCategoriaProvider()),
        ChangeNotifierProvider(create: (_) => AlertasEstoqueProvider()),
        ChangeNotifierProvider(create: (_) => VeiculoProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => OrcamentoVendaProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp.router(
            title: 'Visual Premium',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeProvider.themeMode,   // ← controlado pelo provider
            builder: (context, child) => UpdateChecker(child: child!),
            routerConfig: AppRouter.buildRouter(usuarioProvider),
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