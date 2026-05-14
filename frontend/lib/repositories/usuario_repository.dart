import '../models/usuario_model.dart';
import '../utils/api_client.dart';

class UsuarioRepository {
  Future<({String token, UsuarioModel usuario})> login(
      String username, String senha) async {
    final data = await ApiClient.post('/auth/login', {
      'username': username,
      'senha': senha,
    });

    final token = data['token'] as String;
    final usuario =
        UsuarioModel.fromJson(data['usuario'] as Map<String, dynamic>);

    return (token: token, usuario: usuario);
  }

  Future<List<dynamic>> listar() async {
    return await ApiClient.getList('/usuarios');
  }

  Future<Map<String, dynamic>> criar(Map<String, dynamic> dados) async {
    return await ApiClient.post('/usuarios', dados);
  }

  Future<Map<String, dynamic>> atualizar(
      int id, Map<String, dynamic> dados) async {
    return await ApiClient.put('/usuarios/$id', dados);
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/usuarios/$id');
  }
}