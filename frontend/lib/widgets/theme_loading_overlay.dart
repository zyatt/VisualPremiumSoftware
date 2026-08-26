import 'package:flutter/material.dart';
import 'dart:math' as math;

class ThemeLoadingOverlay extends StatefulWidget {
  final bool isVisible;
  final Widget child;

  const ThemeLoadingOverlay({
    super.key,
    required this.isVisible,
    required this.child,
  });

  @override
  State<ThemeLoadingOverlay> createState() => _ThemeLoadingOverlayState();
}

class _ThemeLoadingOverlayState extends State<ThemeLoadingOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _iconController;
  Animation<double>? _iconRotation;

  bool _shouldBuild = false;

  @override
  void initState() {
    super.initState();
    _shouldBuild = widget.isVisible;
    _initializeController();
  }

  void _initializeController() {
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _iconRotation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _iconController!,
      curve: const Cubic(0.1, 0.0, 0.9, 1.0),
    ));

    if (widget.isVisible) {
      _iconController?.repeat();
    }
  }

  @override
  void didUpdateWidget(ThemeLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (_iconController == null) {
      return;
    }
    
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        setState(() => _shouldBuild = true);
        _iconController!.repeat();
      } else {
        _iconController!.stop();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !widget.isVisible) {
            setState(() => _shouldBuild = false);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _iconController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_iconController == null) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        if (_shouldBuild)
          AnimatedOpacity(
            opacity: widget.isVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: AnimatedBuilder(
                  animation: _iconController!,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _iconRotation!.value,
                      child: _buildThemeIcon(Theme.of(context)),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThemeIcon(ThemeData theme) {
    final circleColor = theme.brightness == Brightness.dark
        ? Colors.white
        : theme.colorScheme.onSurface;

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            circleColor,
            circleColor.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: circleColor.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}