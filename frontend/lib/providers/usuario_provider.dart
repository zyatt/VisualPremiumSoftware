import 'package:flutter/foundation.dart';
import '../models/usuario_model.dart';
import '../repositories/usuario_repository.dart';
import '../utils/api_client.dart';

class UsuarioProvider extends ChangeNotifier {
  final UsuarioRepository _repo = UsuarioRepository();

  UsuarioModel? _usuarioLogado;
  UsuarioModel? get usuarioLogado => _usuarioLogado;

  String? _token;
  String? get token => _token;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  Future<bool> login(String username, String senha) async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      final result = await _repo.login(username, senha);

      _token = result.token;
      _usuarioLogado = result.usuario;

      ApiClient.setToken(_token);

      return true;
    } catch (e) {
      _erro = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  void logout() {
    _usuarioLogado = null;
    _token = null;

    ApiClient.setToken(null);

    notifyListeners();
  }
}