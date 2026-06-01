import 'package:flutter/material.dart';
import '../utils/update_service.dart';
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

class _UpdateCheckerState extends State<UpdateChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final updateInfo = await UpdateService.checkForUpdates();

    if (updateInfo != null && mounted) {
      await AutoUpdateDialog.show(context, updateInfo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}