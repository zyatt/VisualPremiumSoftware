import 'package:flutter/foundation.dart';
import 'package:visual_premium/providers/orcamento_provider.dart';
import '../models/usuario_model.dart';
import '../repositories/usuario_repository.dart';
import '../utils/api_client.dart';

/// Converte exceções técnicas (SocketException, ClientException, TimeoutException
/// etc.) em uma mensagem amigável para o usuário. Mensagens de erro vindas do
/// próprio servidor (ex: "Credenciais inválidas") são mantidas como estão.
String _mensagemErro(Object e) {
  final texto = e.toString();
  if (texto.contains('SocketException') ||
      texto.contains('ClientException') ||
      texto.contains('Connection refused') ||
      texto.contains('Connection reset') ||
      texto.contains('Failed host lookup') ||
      texto.contains('HandshakeException') ||
      texto.contains('TimeoutException') ||
      texto.contains('Network is unreachable')) {
    return 'Não foi possível acessar. Verifique sua conexão com o servidor';
  }
  return texto.replaceFirst('Exception: ', '');
}

class UsuarioProvider extends ChangeNotifier {
  final UsuarioRepository _repo = UsuarioRepository();
  OrcamentoProvider? _orcamentoProvider;

  void setOrcamentoProvider(OrcamentoProvider p) => _orcamentoProvider = p;

  UsuarioModel? _usuarioLogado;
  UsuarioModel? get usuarioLogado => _usuarioLogado;

  String? _token;
  String? get token => _token;

  bool _carregando = false;
  bool get carregando => _carregando;

  bool _restaurando = true;
  bool get restaurando => _restaurando;

  String? _erro;
  String? get erro => _erro;

  // Chamado em main() antes de runApp — tenta restaurar sessão salva
  Future<void> restaurarSessao() async {
    try {
      final sessao = await _repo.carregarSessao();
      if (sessao != null) {
        // Seta o token salvo para poder chamar /auth/refresh
        ApiClient.setToken(sessao.token);
        try {
          // Renova o token (útil para usuários que tinham token com expiresIn antigo)
          final data = await ApiClient.post('/auth/refresh', {});
          final novoToken = data['token'] as String;
          _token         = novoToken;
          _usuarioLogado = sessao.usuario;
          ApiClient.setToken(novoToken);
          await _repo.salvarSessao(novoToken, sessao.usuario);
          await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id);
        } catch (_) {
          // Token rejeitado pelo servidor — limpa e vai para login
          _token         = null;
          _usuarioLogado = null;
          ApiClient.setToken(null);
          await _repo.limparSessao();
        }
      }
    } catch (_) {
      // Sessão corrompida — ignora e segue para login
      await _repo.limparSessao();
    } finally {
      _restaurando = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String senha) async {
    _carregando = true;
    _erro       = null;
    notifyListeners();
    try {
      final result   = await _repo.login(username, senha);
      _token         = result.token;
      _usuarioLogado = result.usuario;
      ApiClient.setToken(_token);
      await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id);
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      return false;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _usuarioLogado = null;
    _token         = null;
    ApiClient.setToken(null);
    await _repo.limparSessao();
    _orcamentoProvider?.trocarUsuario(null);
    notifyListeners();
  }
}