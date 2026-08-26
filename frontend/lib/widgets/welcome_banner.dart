import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WelcomeBanner extends StatelessWidget {
  final String nomeUsuario;

  const WelcomeBanner({super.key, required this.nomeUsuario});

  static void show(BuildContext context, String nomeUsuario) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    showOnOverlay(overlay, nomeUsuario);
  }

  static void showOnOverlay(OverlayState overlay, String nomeUsuario) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerOverlay(
        nomeUsuario: nomeUsuario,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => _BannerOverlay(
        nomeUsuario: nomeUsuario,
        onDone: () {},
      );
}

class _BannerOverlay extends StatefulWidget {
  final String nomeUsuario;
  final VoidCallback onDone;
  const _BannerOverlay({required this.nomeUsuario, required this.onDone});

  @override
  State<_BannerOverlay> createState() => _BannerOverlayState();
}

class _BannerOverlayState extends State<_BannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _slide = _ctrl.drive(
      _SlideTween(
        enter: const Interval(0.00, 0.25, curve: Curves.easeOutCubic),
        exit:  const Interval(0.75, 1.00, curve: Curves.easeInCubic),
      ),
    );

    _fade = _ctrl.drive(
      _FadeTween(
        fadeIn:  const Interval(0.00, 0.20, curve: Curves.easeIn),
        fadeOut: const Interval(0.80, 1.00, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hora = DateTime.now().hour;
    final saudacao = (hora >= 6 && hora < 12)
        ? 'Bom dia'
        : (hora >= 12 && hora < 18)
            ? 'Boa tarde'
            : 'Boa noite';

    return Positioned(
      top: 20,
      right: 0,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => FractionalTranslation(
          translation: _slide.value,
          child: Opacity(
            opacity: _fade.value,
            child: child,
          ),
        ),
        child: _BannerCard(
          saudacao: saudacao,
          nomeUsuario: widget.nomeUsuario,
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final String saudacao;
  final String nomeUsuario;
  const _BannerCard({required this.saudacao, required this.nomeUsuario});

  @override
  Widget build(BuildContext context) {
    final primeiroNome = nomeUsuario.split(' ').first;

    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(maxWidth: 340),
      margin: EdgeInsets.only(right: 16),
      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface,
            Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.06), scheme.surface),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.18),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.18),
                  AppTheme.primary.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SizedBox(width: 16),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  saudacao,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    decoration: TextDecoration.none,
                  ),
                ),
                SizedBox(height: 3),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.75)],
                  ).createShader(bounds),
                  child: Text(
                    primeiroNome,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withValues(alpha: 0.4),
                ],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideTween extends Animatable<Offset> {
  final Interval enter;
  final Interval exit;
  const _SlideTween({required this.enter, required this.exit});

  @override
  Offset transform(double t) {
    if (t < 0.25) {
      final p = enter.transform(t);
      return Offset(1.0 - p, 0);
    } else if (t < 0.75) {
      return Offset.zero;
    } else {
      final p = exit.transform(t);
      return Offset(p, 0);
    }
  }
}

class _FadeTween extends Animatable<double> {
  final Interval fadeIn;
  final Interval fadeOut;
  const _FadeTween({required this.fadeIn, required this.fadeOut});

  @override
  double transform(double t) {
    if (t < 0.20) return fadeIn.transform(t);
    if (t > 0.80) return 1.0 - fadeOut.transform(t);
    return 1.0;
  }
}

class WelcomeBannerInline extends StatefulWidget {
  final String nomeUsuario;
  const WelcomeBannerInline({super.key, required this.nomeUsuario});

  @override
  State<WelcomeBannerInline> createState() => _WelcomeBannerInlineState();
}

class _WelcomeBannerInlineState extends State<WelcomeBannerInline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double>  _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _slide = _ctrl.drive(_SlideTween(
      enter: const Interval(0.00, 0.25, curve: Curves.easeOutCubic),
      exit:  const Interval(0.75, 1.00, curve: Curves.easeInCubic),
    ));
    _fade = _ctrl.drive(_FadeTween(
      fadeIn:  const Interval(0.00, 0.20, curve: Curves.easeIn),
      fadeOut: const Interval(0.80, 1.00, curve: Curves.easeOut),
    ));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hora = DateTime.now().hour;
    final saudacao = (hora >= 6 && hora < 12)
        ? 'Bom dia'
        : (hora >= 12 && hora < 18)
            ? 'Boa tarde'
            : 'Boa noite';

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => FractionalTranslation(
        translation: _slide.value,
        child: Opacity(opacity: _fade.value, child: child),
      ),
      child: _BannerCard(saudacao: saudacao, nomeUsuario: widget.nomeUsuario),
    );
  }
}