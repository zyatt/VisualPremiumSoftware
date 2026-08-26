import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:visual_premium/widgets/theme_transition.dart';
import '../providers/usuario_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey   = GlobalKey<FormState>();
  final _userCtrl  = TextEditingController();
  final _senhaCtrl = TextEditingController();
  bool _obscure    = true;
  final _senhaFocus = FocusNode();

  @override
  void dispose() {
    _userCtrl.dispose();
    _senhaCtrl.dispose();
    _senhaFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<UsuarioProvider>();
    final ok = await provider.login(_userCtrl.text.trim(), _senhaCtrl.text);
    if (!mounted) return;
    if (ok) context.go('/inicio');
  }

  @override
  Widget build(BuildContext context) {
    final loading      = context.watch<UsuarioProvider>().carregando;
    final erro         = context.watch<UsuarioProvider>().erro;
    final themeProvider = context.watch<ThemeProvider>();
    final isDark       = themeProvider.isDark;
    final scheme       = Theme.of(context).colorScheme;

    final logoAsset = isDark
        ? 'assets/images/logo.png'
        : 'assets/images/logo.png';

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 16,
            right: 16,
            child: _ThemeToggleButton(isDark: isDark, themeProvider: themeProvider),
          ),

          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.4 : 0.08),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(36),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          logoAsset,
                          height: 52,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Visual Premium',
                          style: GoogleFonts.raleway(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 32),

                        if (erro != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppTheme.error, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    erro,
                                    style: GoogleFonts.nunito(
                                      color: AppTheme.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextFormField(
                          controller: _userCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Usuário',
                            prefixIcon: Icon(Icons.person_outline_rounded,
                                size: 18),
                          ),
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_senhaFocus),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Informe o usuário'
                              : null,
                        ),
                        const SizedBox(height: 14),

                        TextFormField(
                          controller: _senhaCtrl,
                          focusNode: _senhaFocus,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => loading ? null : _login(),
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 18),
                            suffixIcon: IconButton(
                              mouseCursor: SystemMouseCursors.click,
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Informe a senha'
                              : null,
                        ),

                        const SizedBox(height: 28),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: loading ? null : _login,
                            style: ButtonStyle(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                            child: loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : Text(
                                    'Entrar',
                                    style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  final bool isDark;
  final ThemeProvider themeProvider;
  const _ThemeToggleButton({required this.isDark, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: isDark ? 'Modo claro' : 'Modo escuro',
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(50),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(50),
          mouseCursor: SystemMouseCursors.click,
          onTap: () {
            ThemeTransitionOverlay.of(context)?.switchTheme(
              onSwitch: () => themeProvider.toggle(),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.5),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                key: ValueKey(isDark),
                size: 18,
                color: isDark
                    ? const Color(0xFFFBBF24)
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}