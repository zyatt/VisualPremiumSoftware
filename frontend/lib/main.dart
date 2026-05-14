import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'rotas/app_router.dart';
import 'theme/app_theme.dart';
import 'providers/usuario_provider.dart';
import 'providers/material_provider.dart';
import 'providers/estoque_provider.dart';
import 'providers/fornecedor_provider.dart';
import 'providers/orcamento_provider.dart';
import 'providers/ordem_compra_provider.dart';
import 'providers/historico_provider.dart';
import 'providers/relatorio_os_provider.dart';
import 'utils/update_checker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  runApp(const VisualPremiumApp());
}

class VisualPremiumApp extends StatefulWidget {
  const VisualPremiumApp({super.key});

  @override
  State<VisualPremiumApp> createState() => _VisualPremiumAppState();
}

class _VisualPremiumAppState extends State<VisualPremiumApp> {
  @override
  void initState() {
    super.initState();
    // Verifica updates após build inicial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.checkForUpdates(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UsuarioProvider()),
        ChangeNotifierProvider(create: (_) => MaterialProvider()),
        ChangeNotifierProvider(create: (_) => EstoqueProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => OrcamentoProvider()),
        ChangeNotifierProvider(create: (_) => OrdemCompraProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoProvider()),
        ChangeNotifierProvider(create: (_) => RelatorioOSProvider()),
      ],
      child: MaterialApp.router(
        title: 'Visual Premium',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        routerConfig: AppRouter.router,
      ),
    );
  }
}