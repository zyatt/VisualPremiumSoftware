import 'package:flutter/material.dart';

import 'theme_loading_overlay.dart';

class ThemeTransitionOverlay extends StatefulWidget {
  final Widget child;
  const ThemeTransitionOverlay({super.key, required this.child});

  static ThemeTransitionOverlayState? of(BuildContext context) {
    return context.findAncestorStateOfType<ThemeTransitionOverlayState>();
  }

  @override
  State<ThemeTransitionOverlay> createState() =>
      ThemeTransitionOverlayState();
}

class ThemeTransitionOverlayState extends State<ThemeTransitionOverlay> {
  bool _loading = false;
  bool _busy = false;

  Future<void> switchTheme({
    Offset? origin,
    required VoidCallback onSwitch,
  }) async {
    if (_busy) return;
    _busy = true;

    setState(() => _loading = true);

    await Future.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      _busy = false;
      return;
    }

    onSwitch();

    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) {
      _busy = false;
      return;
    }

    setState(() => _loading = false);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return ThemeLoadingOverlay(
      isVisible: _loading,
      child: widget.child,
    );
  }
}