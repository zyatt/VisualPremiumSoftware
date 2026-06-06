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
import 'providers/audit_log_provider.dart';

import 'widgets/update_checker_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // Cria os providers antes do runApp para poder restaurar a sessão
  final usuarioProvider   = UsuarioProvider();
  final orcamentoProvider = OrcamentoProvider();
  usuarioProvider.setOrcamentoProvider(orcamentoProvider);

  // Restaura sessão salva (token + usuário) antes de exibir qualquer tela
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
        ChangeNotifierProvider(create: (_) => EstoqueProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => OrdemCompraProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoProvider()),
        ChangeNotifierProvider(create: (_) => RelatorioOSProvider()),
        ChangeNotifierProvider(create: (_) => ProducaoProvider()),
        ChangeNotifierProvider(create: (_) => AuditLogProvider()),

      ],
      child: MaterialApp.router(
        title: 'Visual Premium',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
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
      ),
    );
  }
}