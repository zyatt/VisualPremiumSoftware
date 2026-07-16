import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/fornecedor_model.dart';
import '../utils/api_client.dart';

class FornecedorRepository {
  Future<List<FornecedorModel>> listar({
    String? busca,
    String? tipo,
    String? id,
  }) async {
    final params = <String>[];

    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }

    if (tipo != null && tipo.isNotEmpty) {
      params.add('tipo=${Uri.encodeComponent(tipo)}');
    }

    if (id != null && id.isNotEmpty) {
      params.add('id=${Uri.encodeComponent(id)}');
    }

    final path = params.isEmpty
        ? '/fornecedores'
        : '/fornecedores?${params.join('&')}';

    final list = await ApiClient.getList(path);

    return list
        .map((e) => FornecedorModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FornecedorModel> buscarPorId(int id) async {
    final data = await ApiClient.get('/fornecedores/$id');
    return FornecedorModel.fromJson(data);
  }

  /// Busca rápida para o overlay de vínculo — retorna apenas campos essenciais,
  /// sem include pesado de materiais. [busca] nulo lista os primeiros 50.
  Future<List<FornecedorModel>> buscarParaVinculo({String? busca}) async {
    final params = <String>[];
    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }
    final path = params.isEmpty
        ? '/fornecedores/buscar'
        : '/fornecedores/buscar?${params.join('&')}';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => FornecedorModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FornecedorModel>> listarPorMaterial(int materialId) async {
    final list = await ApiClient.getList('/fornecedores/material/$materialId');
    return list
        .map((e) => FornecedorModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cria um fornecedor. Se [imagem] for informada, envia como multipart
  /// (campo "imagem"); caso contrário, envia JSON comum.
  Future<FornecedorModel> criar(
    Map<String, dynamic> dados, {
    File? imagem,
  }) async {
    final data = imagem != null
        ? await _enviarMultipart('POST', '/fornecedores', dados, imagem)
        : await ApiClient.post('/fornecedores', dados);
    return FornecedorModel.fromJson(data);
  }

  /// Atualiza um fornecedor. Se [imagem] for informada, envia como multipart
  /// (campo "imagem"), substituindo a imagem atual; caso contrário, envia JSON.
  Future<FornecedorModel> atualizar(
    int id,
    Map<String, dynamic> dados, {
    File? imagem,
  }) async {
    final data = imagem != null
        ? await _enviarMultipart('PUT', '/fornecedores/$id', dados, imagem)
        : await ApiClient.put('/fornecedores/$id', dados);
    return FornecedorModel.fromJson(data);
  }

  Future<void> remover(int id) async {
    await ApiClient.delete('/fornecedores/$id');
  }

  Future<void> vincularMaterial(int fornecedorId, Map<String, dynamic> dados) async {
    await ApiClient.post('/fornecedores/$fornecedorId/materiais', dados);
  }

  Future<void> desvincularMaterial(int fornecedorId, int materialId) async {
    await ApiClient.delete('/fornecedores/$fornecedorId/materiais/$materialId');
  }

  Future<void> atualizarPreco(int fornecedorId, int materialId, Map<String, dynamic> dados) async {
    await ApiClient.patch('/fornecedores/$fornecedorId/materiais/$materialId/preco', dados);
  }

  Future<List<Map<String, dynamic>>> buscarMateriais({
    String? idPrefix,
    String? nomePrefix,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    String path;

    if (idPrefix != null && idPrefix.isNotEmpty) {
      path = '/materiais?ativo=true&id=${Uri.encodeComponent(idPrefix)}';
    } else {
      final params = <String>['ativo=true'];
      if (nomePrefix != null && nomePrefix.isNotEmpty) {
        params.add('busca=${Uri.encodeComponent(nomePrefix)}');
      }
      if (identificador != null && identificador.isNotEmpty) {
        params.add('identificador=${Uri.encodeComponent(identificador)}');
      }
      if (medida != null && medida.isNotEmpty) {
        params.add('medida=${Uri.encodeComponent(medida)}');
      }
      if (espessura != null && espessura.isNotEmpty) {
        params.add('espessura=${Uri.encodeComponent(espessura)}');
      }
      path = '/materiais?${params.join('&')}';
    }

    final list = await ApiClient.getList(path);

    return list.map<Map<String, dynamic>>((e) {
      final item = e as Map<String, dynamic>;

      return {
        'id':           item['id'],
        'nome':         item['nome'],
        'identificador': item['identificador'],
        'medida':       item['medida'],
        'espessura':    item['espessura'],
        'unidade':      item['unidade'],
        'largura':      item['largura'],
        'comprimento':  item['comprimento'],
      };
    }).toList();
  }

  // ── Helper: multipart com campos escalares + 1 arquivo de imagem ──────────
  Future<Map<String, dynamic>> _enviarMultipart(
    String method,
    String path,
    Map<String, dynamic> campos,
    File imagem,
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

    request.files.add(
      await http.MultipartFile.fromPath('imagem', imagem.path),
    );

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