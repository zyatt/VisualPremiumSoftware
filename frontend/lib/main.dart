import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'dart:io' show Platform, exit;
import 'package:window_manager/window_manager.dart';

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
import 'providers/estoque_producao_provider.dart';
import 'providers/audit_log_provider.dart';
import 'providers/gastos_categoria_provider.dart';
import 'providers/alertas_estoque_provider.dart';
import 'providers/veiculo_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/nav_layout_provider.dart';
import 'providers/orcamento_venda_provider.dart';
import 'providers/solicitacao_material_provider.dart';
import 'providers/chat_provider.dart';

import 'widgets/update_checker_widget.dart';
import 'widgets/theme_transition.dart';
import 'providers/robo_helper_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();

    final jaVisivel = await windowManager.isVisible();

    if (!jaVisivel) {
      const windowOptions = WindowOptions(
        title: 'Visual Premium',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setPreventClose(true);
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setMinimumSize(const Size(1024, 700));
      });
    } else {
      await windowManager.setPreventClose(true);
    }
  }

  final usuarioProvider             = UsuarioProvider();
  final orcamentoProvider           = OrcamentoProvider();
  final solicitacaoMaterialProvider = SolicitacaoMaterialProvider();
  final materialProvider            = MaterialProvider();

  final chatProvider                = ChatProvider();

  usuarioProvider.setOrcamentoProvider(orcamentoProvider);
  usuarioProvider.setSolicitacaoMaterialProvider(solicitacaoMaterialProvider);
  usuarioProvider.setChatProvider(chatProvider);

  await usuarioProvider.restaurarSessao();

  runApp(VisualPremiumApp(
    usuarioProvider:             usuarioProvider,
    orcamentoProvider:           orcamentoProvider,
    solicitacaoMaterialProvider: solicitacaoMaterialProvider,
    materialProvider:            materialProvider,
    chatProvider:                chatProvider,
  ));
}

class VisualPremiumApp extends StatefulWidget {
  final UsuarioProvider             usuarioProvider;
  final OrcamentoProvider           orcamentoProvider;
  final SolicitacaoMaterialProvider solicitacaoMaterialProvider;
  final MaterialProvider            materialProvider;
  final ChatProvider                chatProvider;

  const VisualPremiumApp({
    super.key,
    required this.usuarioProvider,
    required this.orcamentoProvider,
    required this.solicitacaoMaterialProvider,
    required this.materialProvider,
    required this.chatProvider,
  });

  @override
  State<VisualPremiumApp> createState() => _VisualPremiumAppState();
}

class _VisualPremiumAppState extends State<VisualPremiumApp> with WindowListener {
  late final GoRouter _router = AppRouter.buildRouter(widget.usuarioProvider);

  bool get _suportaJanelaDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (_suportaJanelaDesktop) {
      windowManager.addListener(this);
    }
  }

  @override
  void onWindowClose() async {
    final sw = Stopwatch()..start();
    void log(String etapa) =>
        debugPrint('[FECHAR] ${sw.elapsedMilliseconds}ms — $etapa');

    log('onWindowClose chamado, iniciando encerramento das conexões SSE');

    try {
      widget.orcamentoProvider.encerrarConexoesTempoReal();
      log('orcamentoProvider.encerrarConexoesTempoReal() concluído');
    } catch (e, st) {
      log('ERRO em orcamentoProvider.encerrarConexoesTempoReal(): $e\n$st');
    }

    try {
      widget.chatProvider.encerrarConexaoSSE();
      log('chatProvider.encerrarConexaoSSE() concluído');
    } catch (e, st) {
      log('ERRO em chatProvider.encerrarConexaoSSE(): $e\n$st');
    }

    try {
      widget.materialProvider.encerrarConexaoSSE();
      log('materialProvider.encerrarConexaoSSE() concluído');
    } catch (e, st) {
      log('ERRO em materialProvider.encerrarConexaoSSE(): $e\n$st');
    }

    try {
      widget.solicitacaoMaterialProvider.encerrarConexaoSSE();
      log('solicitacaoMaterialProvider.encerrarConexaoSSE() concluído');
    } catch (e, st) {
      log('ERRO em solicitacaoMaterialProvider.encerrarConexaoSSE(): $e\n$st');
    }

    log('todos os encerramentos de SSE concluídos, chamando windowManager.destroy()');

    try {
      await windowManager.destroy().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          log('TIMEOUT: windowManager.destroy() não retornou em 10s');
        },
      );
      log('windowManager.destroy() retornou');
    } catch (e, st) {
      log('ERRO em windowManager.destroy(): $e\n$st');
    }

    log('forçando encerramento do processo com exit(0)');
    exit(0);
  }

  @override
  void dispose() {
    if (_suportaJanelaDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.usuarioProvider),
        ChangeNotifierProvider.value(value: widget.orcamentoProvider),
        ChangeNotifierProvider.value(value: widget.materialProvider),
        ChangeNotifierProvider(create: (_) => ProdutoProvider()),
        ChangeNotifierProvider(create: (_) => EstoqueProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => OrdemCompraProvider()),
        ChangeNotifierProvider(create: (_) => RelatorioOSProvider()),
        ChangeNotifierProvider(create: (_) => EstoqueProducaoProvider()),
        ChangeNotifierProvider(create: (_) => AuditLogProvider()),
        ChangeNotifierProvider(create: (_) => GastosCategoriaProvider()),
        ChangeNotifierProvider(create: (_) => AlertasEstoqueProvider()),
        ChangeNotifierProvider(create: (_) => VeiculoProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NavLayoutProvider()),
        ChangeNotifierProvider(create: (_) => OrcamentoVendaProvider()),
        ChangeNotifierProvider(create: (_) => RoboHelperProvider()),
        ChangeNotifierProvider.value(value: widget.solicitacaoMaterialProvider),
        ChangeNotifierProvider.value(value: widget.chatProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp.router(
            title: 'Visual Premium',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeProvider.themeMode,
           
            builder: (context, child) => ThemeTransitionOverlay(
              child: AnimatedTheme(
                data: themeProvider.isDark ? AppTheme.dark : AppTheme.light,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: UpdateChecker(child: child!),
              ),
            ),
            routerConfig: _router,
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