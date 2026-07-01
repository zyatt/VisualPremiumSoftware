import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/solicitacao_material_model.dart';
import '../utils/api_client.dart';

class SolicitacaoMaterialRepository {
  // ── Listar ────────────────────────────────────────────────────────────────
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
    if (materialId != null) params.add('materialId=$materialId');
    if (numeroOS != null && numeroOS.isNotEmpty) {
      params.add('numeroOS=${Uri.encodeComponent(numeroOS)}');
    }
    if (dataInicio != null) {
      final s =
          '${dataInicio.year}-${dataInicio.month.toString().padLeft(2, '0')}-${dataInicio.day.toString().padLeft(2, '0')}';
      params.add('dataInicio=${Uri.encodeComponent(s)}');
    }
    if (dataFim != null) {
      final s =
          '${dataFim.year}-${dataFim.month.toString().padLeft(2, '0')}-${dataFim.day.toString().padLeft(2, '0')}';
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

  // ── Buscar por ID ─────────────────────────────────────────────────────────
  Future<SolicitacaoMaterialModel> buscarPorId(int id) async {
    final data = await ApiClient.get('/solicitacoes-material/$id');
    return SolicitacaoMaterialModel.fromJson(data);
  }

  // ── Criar (multipart — múltiplos itens com imagens opcionais) ─────────────
  Future<SolicitacaoMaterialModel> criar(
    Map<String, dynamic> dados, {
    List<Map<String, dynamic>> itens = const [],
    Map<int, File> imagensPorIndice = const {},
  }) async {
    final data = await _enviarMultipartComItens(
      'POST',
      '/solicitacoes-material',
      dados,
      itens,
      imagensPorIndice,
    );
    return SolicitacaoMaterialModel.fromJson(data);
  }

  // ── Atualizar cabeçalho (somente ADMIN) ───────────────────────────────────
  Future<SolicitacaoMaterialModel> atualizar(
    int id,
    Map<String, dynamic> dados,
  ) async {
    final data = await ApiClient.put('/solicitacoes-material/$id', dados);
    return SolicitacaoMaterialModel.fromJson(data);
  }

  // ── Adicionar materiais extras ─────────────────────────────────────────────
  Future<SolicitacaoMaterialModel> adicionarMateriais(
    int solicitacaoId, {
    required List<Map<String, dynamic>> itens,
    Map<int, File> imagensPorIndice = const {},
  }) async {
    final data = await _enviarMultipartComItens(
      'POST',
      '/solicitacoes-material/$solicitacaoId/adicionais',
      {},
      itens,
      imagensPorIndice,
    );
    return SolicitacaoMaterialModel.fromJson(data);
  }

  // ── Marcar item original como comprado ────────────────────────────────────
  Future<ItemSolicitacaoModel> marcarItemComprado(
    int itemId, {
    required bool comprado,
  }) async {
    final data = await ApiClient.patch(
      '/solicitacoes-material/itens/$itemId/comprado',
      {'comprado': comprado},
    );
    return ItemSolicitacaoModel.fromJson(data);
  }

  // ── Marcar adicional como comprado ────────────────────────────────────────
  Future<AdicionalSolicitacaoModel> marcarAdicionalComprado(
    int adicionalId, {
    required bool comprado,
  }) async {
    final data = await ApiClient.patch(
      '/solicitacoes-material/adicionais/$adicionalId/comprado',
      {'comprado': comprado},
    );
    return AdicionalSolicitacaoModel.fromJson(data);
  }

  // ── Excluir ───────────────────────────────────────────────────────────────
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

  // ── Helper: multipart com lista de itens e imagens por índice ─────────────
  Future<Map<String, dynamic>> _enviarMultipartComItens(
    String method,
    String path,
    Map<String, dynamic> campos,
    List<Map<String, dynamic>> itens,
    Map<int, File> imagensPorIndice,
  ) async {
    final prefixed = path.startsWith('/auth') ? path : '/api$path';
    final uri = Uri.parse('${ApiClient.baseUrl}$prefixed');

    final request = http.MultipartRequest(method, uri);

    final token = ApiClient.token;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Campos escalares
    campos.forEach((key, value) {
      if (value != null) request.fields[key] = value.toString();
    });

    // Itens como JSON string
    request.fields['itens'] = jsonEncode(itens);

    // Imagens por índice: campo "imagens[N]"
    for (final entry in imagensPorIndice.entries) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'imagens[${entry.key}]',
          entry.value.path,
        ),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    Map<String, dynamic> decoded;
    try {
      decoded = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = <String, dynamic>{};
    }

    if (response.statusCode >= 400) {
      final mensagem = decoded['message'] as String? ??
          'Erro ao enviar dados (HTTP ${response.statusCode}).';
      throw Exception(mensagem);
    }
    return decoded;
  }
}