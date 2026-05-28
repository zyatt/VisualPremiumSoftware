import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
import 'providers/producao_provider.dart';
//import 'utils/update_checker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  runApp(const VisualPremiumApp());
}

class VisualPremiumApp extends StatelessWidget {
  const VisualPremiumApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Criamos o UsuarioProvider aqui fora para passá-lo tanto ao
    // MultiProvider quanto ao AppRouter (que precisa de refreshListenable).
    final usuarioProvider = UsuarioProvider();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: usuarioProvider),
        ChangeNotifierProvider(create: (_) => MaterialProvider()),
        ChangeNotifierProvider(create: (_) => EstoqueProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => OrcamentoProvider()),
        ChangeNotifierProvider(create: (_) => OrdemCompraProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoProvider()),
        ChangeNotifierProvider(create: (_) => RelatorioOSProvider()),
        ChangeNotifierProvider(create: (_) => ProducaoProvider()),
      ],
      child: MaterialApp.router(
        title: 'Visual Premium',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        // Passa a mesma instância do provider para que o router possa
        // usar refreshListenable e o redirect global funcione corretamente.
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
      ),
    );
  }
}