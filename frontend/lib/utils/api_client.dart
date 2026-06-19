import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  /// Timeout aplicado a toda requisição. Sem isso, uma chamada que nunca
  /// recebe resposta (ex: túnel reconectando, backend reiniciando no meio
  /// da requisição) deixa o `await` pendurado para sempre — e como nenhum
  /// catch/finally roda, o `carregando` do provider nunca volta a `false`,
  /// travando a tela no loading indefinidamente.
  static const _timeout = Duration(seconds: 15);

  static String get _base {
    final tunnel = dotenv.env['API_TUNNEL_URL'] ?? '';
    if (tunnel.isNotEmpty) return tunnel;

    final host = dotenv.env['API_HOST'] ?? 'localhost';
    final port = dotenv.env['API_PORT'] ?? '3000';
    return 'http://$host:$port'; // caso padrão, nada muda
  }

  /// URL base pública (ex: para montar links de PDF via url_launcher).
  static String get baseUrl => _base;

  // Token injetado pelo UsuarioProvider após login
  static String? _token;
  static void setToken(String? token) => _token = token;
  static String? get token => _token;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Monta a URL completa.
  /// Rotas /auth ficam sem prefixo; todas as outras recebem /api.
  static Uri _uri(String path) {
    final prefixed = path.startsWith('/auth') ? path : '/api$path';
    return Uri.parse('$_base$prefixed');
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final res = await http.get(_uri(path), headers: _headers).timeout(_timeout);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getList(String path) async {
    final res = await http.get(_uri(path), headers: _headers).timeout(_timeout);
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final res = await http.put(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// PATCH para endpoints como /materiais/:id/confirmar e /materiais/:id/desativar
  static Future<Map<String, dynamic>> patch(String path,
      [Map<String, dynamic>? body]) async {
    final res = await http.patch(
      _uri(path),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(_timeout);
    _check(res);
    if (res.body.isEmpty) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> delete(String path) async {
    final res = await http.delete(_uri(path), headers: _headers).timeout(_timeout);
    _check(res);
  }

  /// Baixa uma resposta binária (ex: PDF) e retorna os bytes brutos.
  static Future<List<int>> getBytes(String path) async {
    final res = await http.get(_uri(path), headers: _headers).timeout(_timeout);
    _check(res);
    return res.bodyBytes;
  }

  /// Envia um POST com body JSON e retorna a resposta como bytes brutos (ex: PDF).
  static Future<Uint8List> postBytes(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    _check(res);
    return res.bodyBytes;
  }

  static void _check(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Erro ${res.statusCode}';
      try {
        final body = jsonDecode(res.body);
        msg = body['message'] ?? body['error'] ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  static Future<List<dynamic>> putList(String path, Map<String, dynamic> body) async {
  final res = await http.put(
    _uri(path),
    headers: _headers,
    body: jsonEncode(body),
  ).timeout(_timeout);
  _check(res);
  return jsonDecode(res.body) as List<dynamic>;
}
}