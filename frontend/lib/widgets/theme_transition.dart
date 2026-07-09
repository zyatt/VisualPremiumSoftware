import 'package:flutter/material.dart';

import 'theme_loading_overlay.dart';

/// Envolve a árvore do app e permite disparar a troca de tema mostrando um
/// [ThemeLoadingOverlay] (ícone girando) durante a transição.
///
/// Uso:
/// ```dart
/// ThemeTransitionOverlay(child: MaterialApp(...))
/// ```
///
/// No ponto de troca:
/// ```dart
/// ThemeTransitionOverlay.of(context)?.switchTheme(
///   origin: globalTapPosition,
///   onSwitch: () => context.read<ThemeProvider>().toggle(),
/// );
/// ```
///
/// O parâmetro `origin` é mantido só por compatibilidade com quem já chama
/// `switchTheme` (ex.: `app_shell.dart`) — não é mais usado aqui, já que não
/// há mais revelação circular a partir de um ponto de toque.
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

  /// Mostra o [ThemeLoadingOverlay], executa [onSwitch] (que deve alterar o
  /// ThemeMode) e esconde o overlay depois de um tempo mínimo — só pra dar
  /// feedback visual da troca, sem nenhum efeito de revelação.
  Future<void> switchTheme({
    Offset? origin,
    required VoidCallback onSwitch,
  }) async {
    // Evita reentrância se o usuário tocar rápido demais.
    if (_busy) return;
    _busy = true;

    setState(() => _loading = true);

    // Um frame de folga pra garantir que o ícone realmente chegue a
    // aparecer antes do rebuild causado por onSwitch().
    await Future.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      _busy = false;
      return;
    }

    onSwitch();

    // Tempo mínimo visível do loading — dá pra ver o ícone completar quase
    // uma volta inteira (a rotação dele dura 1200ms) antes de sumir.
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