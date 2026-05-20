import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/usuario_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey   = GlobalKey<FormState>();
  final _userCtrl  = TextEditingController();
  final _senhaCtrl = TextEditingController();
  bool _obscure = true;
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
    if (ok) {
      context.go('/inicio');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<UsuarioProvider>().carregando;
    final erro = context.watch<UsuarioProvider>().erro;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Visual Premium',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 32),
                    if (erro != null) ...[
                      Text(
                        erro,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(labelText: 'Usuário'),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_senhaFocus),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Informe o usuário' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _senhaCtrl,
                      focusNode: _senhaFocus,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => loading ? null : _login(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Informe a senha' : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : _login,
                        child: loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Text('Entrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}