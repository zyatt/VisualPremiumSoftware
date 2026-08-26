import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/solicitacao_material_model.dart';
import '../utils/api_client.dart';

class VerificacaoOSResult {
  final bool existe;
  final int? id;
  final String? numeroOS;
  final String? nomeCliente;
  final String? andamento;

  const VerificacaoOSResult({
    required this.existe,
    this.id,
    this.numeroOS,
    this.nomeCliente,
    this.andamento,
  });

  factory VerificacaoOSResult.fromJson(Map<String, dynamic> json) {
    return VerificacaoOSResult(
      existe: json['existe'] as bool? ?? false,
      id: json['id'] as int?,
      numeroOS: json['numeroOS'] as String?,
      nomeCliente: json['nomeCliente'] as String?,
      andamento: json['andamento'] as String?,
    );
  }
}

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

  Future<SolicitacaoMaterialModel> buscarPorId(int id) async {
    final data = await ApiClient.get('/solicitacoes-material/$id');
    return SolicitacaoMaterialModel.fromJson(data);
  }

  Future<VerificacaoOSResult> verificarOSExiste(
    String numeroOS, {
    int? ignorarId,
  }) async {
    final os = numeroOS.trim();
    if (os.isEmpty) return const VerificacaoOSResult(existe: false);

    final path = ignorarId != null
        ? '/solicitacoes-material/verificar-os/${Uri.encodeComponent(os)}?ignorarId=$ignorarId'
        : '/solicitacoes-material/verificar-os/${Uri.encodeComponent(os)}';

    final data = await ApiClient.get(path);
    return VerificacaoOSResult.fromJson(data);
  }

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

  Future<SolicitacaoMaterialModel> atualizar(
    int id,
    Map<String, dynamic> dados,
  ) async {
    final data = await ApiClient.put('/solicitacoes-material/$id', dados);
    return SolicitacaoMaterialModel.fromJson(data);
  }

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

  Future<ItemSolicitacaoModel> marcarItemEstoque(
    int itemId, {
    required bool estoque,
  }) async {
    final data = await ApiClient.patch(
      '/solicitacoes-material/itens/$itemId/estoque',
      {'estoque': estoque},
    );
    return ItemSolicitacaoModel.fromJson(data);
  }

  Future<AdicionalSolicitacaoModel> marcarAdicionalEstoque(
    int adicionalId, {
    required bool estoque,
  }) async {
    final data = await ApiClient.patch(
      '/solicitacoes-material/adicionais/$adicionalId/estoque',
      {'estoque': estoque},
    );
    return AdicionalSolicitacaoModel.fromJson(data);
  }

  Future<ItemSolicitacaoModel> atualizarItem(
    int itemId, {
    required double quantidade,
    String? observacao,
  }) async {
    final data = await ApiClient.patch(
      '/solicitacoes-material/itens/$itemId',
      {'quantidade': quantidade, 'observacao': observacao},
    );
    return ItemSolicitacaoModel.fromJson(data);
  }

  Future<AdicionalSolicitacaoModel> atualizarAdicional(
    int adicionalId, {
    required double quantidade,
    String? observacao,
  }) async {
    final data = await ApiClient.patch(
      '/solicitacoes-material/adicionais/$adicionalId',
      {'quantidade': quantidade, 'observacao': observacao},
    );
    return AdicionalSolicitacaoModel.fromJson(data);
  }

  Future<void> excluirItem(int itemId) async {
    await ApiClient.delete('/solicitacoes-material/itens/$itemId');
  }

  Future<void> excluirAdicional(int adicionalId) async {
    await ApiClient.delete('/solicitacoes-material/adicionais/$adicionalId');
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/solicitacoes-material/$id');
  }

  Future<List<LogEdicaoSolicitacaoModel>> listarLogs(int solicitacaoId) async {
    final list = await ApiClient.getList(
      '/solicitacoes-material/$solicitacaoId/logs',
    );
    return list
        .map((e) =>
            LogEdicaoSolicitacaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

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

    campos.forEach((key, value) {
      if (value != null) request.fields[key] = value.toString();
    });

    request.fields['itens'] = jsonEncode(itens);

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