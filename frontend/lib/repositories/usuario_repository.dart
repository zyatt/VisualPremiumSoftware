import '../models/usuario_model.dart';
import '../utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class UsuarioRepository {
  static const _keyToken        = 'session_token';
  static const _keyUsuario      = 'session_usuario';
  /// Lista de usuários que já logaram nesta máquina (sem senha).
  static const _keyUsuariosSalvos = 'usuarios_salvos';

  // ── Login remoto ──────────────────────────────────────────────────────────
  Future<({String token, UsuarioModel usuario})> login(
      String username, String senha) async {
    final data = await ApiClient.post('/auth/login', {
      'username': username,
      'senha': senha,
    });

    final token   = data['token'] as String;
    final usuario = UsuarioModel.fromJson(data['usuario'] as Map<String, dynamic>);

    await salvarSessao(token, usuario);
    return (token: token, usuario: usuario);
  }

  // ── Persistência local ────────────────────────────────────────────────────
  // Público para permitir salvar token renovado via /auth/refresh
  Future<void> salvarSessao(String token, UsuarioModel usuario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken,   token);
    await prefs.setString(_keyUsuario, jsonEncode(usuario.toJson()));
  }

  Future<({String token, UsuarioModel usuario})?> carregarSessao() async {
    final prefs   = await SharedPreferences.getInstance();
    final token   = prefs.getString(_keyToken);
    final usuJson = prefs.getString(_keyUsuario);
    if (token == null || usuJson == null) return null;

    final usuario = UsuarioModel.fromJson(
        jsonDecode(usuJson) as Map<String, dynamic>);
    return (token: token, usuario: usuario);
  }

  Future<void> limparSessao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUsuario);
  }

  // ── Usuários salvos (troca rápida) ────────────────────────────────────────
  /// Persiste o usuário na lista de "usuários salvos nesta máquina".
  /// Mantém no máximo 10 entradas e garante que não há duplicatas por id.
  Future<void> adicionarUsuarioSalvo(UsuarioModel usuario) async {
    final prefs   = await SharedPreferences.getInstance();
    final raw     = prefs.getString(_keyUsuariosSalvos);
    final lista   = raw != null
        ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    // Remove entrada antiga do mesmo id
    lista.removeWhere((e) => e['id'] == usuario.id);
    // Insere no topo
    lista.insert(0, usuario.toJson());
    if (lista.length > 10) lista.removeLast();
    await prefs.setString(_keyUsuariosSalvos, jsonEncode(lista));
  }

  /// Remove um usuário específico da lista de "usuários salvos nesta máquina".
  Future<void> removerUsuarioSalvo(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_keyUsuariosSalvos);
    if (raw == null) return;
    final lista = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    lista.removeWhere((e) => e['id'] == id);
    await prefs.setString(_keyUsuariosSalvos, jsonEncode(lista));
  }

  /// Limpa toda a lista de usuários salvos nesta máquina.
  Future<void> limparUsuariosSalvos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsuariosSalvos);
  }

  /// Retorna a lista de usuários que já logaram nesta máquina.
  Future<List<UsuarioModel>> getUsuariosSalvos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_keyUsuariosSalvos);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(UsuarioModel.fromJson)
        .toList();
  }

  // ── CRUD de usuários ──────────────────────────────────────────────────────
  Future<List<dynamic>> listar() async => ApiClient.getList('/usuarios');

  Future<Map<String, dynamic>> criar(Map<String, dynamic> dados) async =>
      ApiClient.post('/usuarios', dados);

  Future<Map<String, dynamic>> atualizar(int id, Map<String, dynamic> dados) async =>
      ApiClient.put('/usuarios/$id', dados);

  Future<void> excluir(int id) async => ApiClient.delete('/usuarios/$id');
}