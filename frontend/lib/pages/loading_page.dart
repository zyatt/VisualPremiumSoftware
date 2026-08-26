import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/usuario_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final Animation<double>   _logoScale;
  late final Animation<double>   _logoOpacity;

  late final AnimationController _barCtrl;
  late final Animation<double>   _barProgress;

  late final AnimationController _tagCtrl;
  late final Animation<double>   _tagOpacity;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _logoScale = CurvedAnimation(
      parent: _logoCtrl,
      curve: Curves.easeOutBack,
    ).drive(Tween(begin: 0.6, end: 1.0));
    _logoOpacity = CurvedAnimation(
      parent: _logoCtrl,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));

    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _barProgress = CurvedAnimation(
      parent: _barCtrl,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.0, end: 1.0));

    _tagCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _tagOpacity = CurvedAnimation(
      parent: _tagCtrl,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([
        precacheImage(const AssetImage('assets/images/logoPreta.png'), context),
        precacheImage(const AssetImage('assets/images/logoBranca.png'), context),
      ]);

      if (mounted) {
        final prov = context.read<UsuarioProvider>();
        while (prov.restaurando) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      if (mounted) _runSequence();
    });
  }

  Future<void> _runSequence() async {
    await _logoCtrl.forward();
    _barCtrl.forward();
    _tagCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 1400));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final prov = context.read<UsuarioProvider>();
    if (prov.usuarioLogado != null) {
      final isProducao = prov.usuarioLogado!.role.trim().toUpperCase() == 'PRODUCAO';
      context.go(isProducao ? '/producao' : '/inicio');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _barCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final bg     = isDark ? AppTheme.darkBackground : AppTheme.background;
    final hint   = isDark ? AppTheme.darkTextHint   : AppTheme.textHint;
    final track  = isDark ? AppTheme.darkDivider     : AppTheme.divider;

    final logoAsset = isDark
        ? 'assets/images/logoBranca.png'
        : 'assets/images/logoPreta.png';

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, child) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: child,
                  ),
                ),
                child: Image.asset(
                  logoAsset,
                  height: 72,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 40),

              AnimatedBuilder(
                animation: Listenable.merge([_barProgress, _logoOpacity]),
                builder: (_, __) => Opacity(
                  opacity: _logoOpacity.value,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        children: [
                          Container(width: double.infinity, color: track),
                          FractionallySizedBox(
                            widthFactor: _barProgress.value,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.primaryLight,
                                    AppTheme.primary,
                                    AppTheme.primaryDark,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              AnimatedBuilder(
                animation: _tagOpacity,
                builder: (_, child) => Opacity(
                  opacity: _tagOpacity.value,
                  child: child,
                ),
                child: Text(
                  'Carregando…',
                  style: TextStyle(
                    fontSize: 12,
                    color: hint,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}