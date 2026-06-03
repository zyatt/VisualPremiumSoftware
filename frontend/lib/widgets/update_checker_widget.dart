import 'package:flutter/material.dart';
import '../utils/update_service.dart';
import '../rotas/app_router.dart';
import 'auto_update_dialog.dart';

class UpdateChecker extends StatefulWidget {
  final Widget child;

  const UpdateChecker({
    super.key,
    required this.child,
  });

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _checkForUpdates();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkForUpdates();
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      debugPrint('[UpdateChecker] Iniciando verificação...');

      final updateInfo = await UpdateService.checkForUpdates();

      if (updateInfo == null) {
        debugPrint('[UpdateChecker] Nenhuma atualização disponível');
        return;
      }

      debugPrint('[UpdateChecker] Atualização encontrada: ${updateInfo.latestVersion}');

      // Usa a GlobalKey do Navigator raiz — independente de contexto
      final navigatorState = AppRouter.rootNavigatorKey.currentState;
      if (navigatorState == null) {
        debugPrint('[UpdateChecker] Navigator ainda não está pronto');
        return;
      }

      // ignore: use_build_context_synchronously
      await AutoUpdateDialog.show(navigatorState.context, updateInfo);
    } catch (e, stack) {
      debugPrint('[UpdateChecker] ERRO ao verificar updates: $e');
      debugPrint('[UpdateChecker] Stack: $stack');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}