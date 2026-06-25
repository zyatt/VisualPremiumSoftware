// solicitacao_material_repository.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/solicitacao_material_model.dart';
import '../utils/api_client.dart';

class SolicitacaoMaterialRepository {
  Future<List<SolicitacaoMaterialModel>> listar({
    String? busca,
    String? andamento,
    int? materialId,
    String? numeroOS,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    final params = <String>[];

    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }
    if (andamento != null && andamento.isNotEmpty) {
      params.add('andamento=${Uri.encodeComponent(andamento)}');
    }
    if (materialId != null) {
      params.add('materialId=$materialId');
    }
    if (numeroOS != null && numeroOS.isNotEmpty) {
      params.add('numeroOS=${Uri.encodeComponent(numeroOS)}');
    }
    if (dataInicio != null) {
      final s =
          '${dataInicio.year}-'
          '${dataInicio.month.toString().padLeft(2, '0')}-'
          '${dataInicio.day.toString().padLeft(2, '0')}';
      params.add('dataInicio=${Uri.encodeComponent(s)}');
    }
    if (dataFim != null) {
      final s =
          '${dataFim.year}-'
          '${dataFim.month.toString().padLeft(2, '0')}-'
          '${dataFim.day.toString().padLeft(2, '0')}';
      params.add('dataFim=${Uri.encodeComponent(s)}');
    }

    final path = params.isEmpty
        ? '/solicitacoes-material'
        : '/solicitacoes-material?${params.join('&')}';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => SolicitacaoMaterialModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SolicitacaoMaterialModel> buscarPorId(int id) async {
    final data = await ApiClient.get('/solicitacoes-material/$id');
    return SolicitacaoMaterialModel.fromJson(data);
  }

  // ── Criar (com imagem opcional via multipart) ─────────────────────────────
  Future<SolicitacaoMaterialModel> criar(
    Map<String, dynamic> dados, {
    File? imagem,
  }) async {
    if (imagem != null) {
      final data = await _enviarMultipart(
        'POST',
        '/solicitacoes-material',
        dados,
        imagem,
      );
      return SolicitacaoMaterialModel.fromJson(data);
    }
    final data = await ApiClient.post('/solicitacoes-material', dados);
    return SolicitacaoMaterialModel.fromJson(data);
  }

  // ── Atualizar (com imagem opcional via multipart) ─────────────────────────
  Future<SolicitacaoMaterialModel> atualizar(
    int id,
    Map<String, dynamic> dados, {
    File? imagem,
  }) async {
    if (imagem != null) {
      final data = await _enviarMultipart(
        'PUT',
        '/solicitacoes-material/$id',
        dados,
        imagem,
      );
      return SolicitacaoMaterialModel.fromJson(data);
    }
    final data = await ApiClient.put('/solicitacoes-material/$id', dados);
    return SolicitacaoMaterialModel.fromJson(data);
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/solicitacoes-material/$id');
  }

  // ── Logs de edição ────────────────────────────────────────────────────────
  Future<List<LogEdicaoSolicitacaoModel>> listarLogs(int solicitacaoId) async {
    final list = await ApiClient.getList(
      '/solicitacoes-material/$solicitacaoId/logs',
    );
    return list
        .map((e) =>
            LogEdicaoSolicitacaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Helper multipart ──────────────────────────────────────────────────────
  /// Envia campos de texto + arquivo de imagem via multipart/form-data.
  /// NÃO usa ApiClient.authHeaders() (método inexistente).
  /// Usa ApiClient.token (getter público) e replica a lógica de prefixo
  /// /api do ApiClient._uri() interno.
  Future<Map<String, dynamic>> _enviarMultipart(
    String method,
    String path,
    Map<String, dynamic> campos,
    File arquivo,
  ) async {
    // Replica exatamente a lógica de ApiClient._uri():
    // rotas /auth ficam sem prefixo; todas as outras recebem /api.
    final prefixed = path.startsWith('/auth') ? path : '/api$path';
    final uri = Uri.parse('${ApiClient.baseUrl}$prefixed');

    final request = http.MultipartRequest(method, uri);

    // Injeta o Bearer token usando o getter público ApiClient.token
    final token = ApiClient.token;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Campos de texto — serializa valores como String
    campos.forEach((key, value) {
      if (value != null) {
        request.fields[key] = value.toString();
      }
    });

    // Arquivo de imagem (campo "imagem" esperado pelo multer no backend)
    request.files.add(
      await http.MultipartFile.fromPath('imagem', arquivo.path),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded  = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(decoded['message'] ?? 'Erro ao enviar arquivo');
    }
    return decoded;
  }
}