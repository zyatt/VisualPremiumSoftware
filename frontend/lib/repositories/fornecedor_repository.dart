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

  Future<FornecedorModel> criar(Map<String, dynamic> dados) async {
    final data = await ApiClient.post('/fornecedores', dados);
    return FornecedorModel.fromJson(data);
  }

  Future<FornecedorModel> atualizar(int id, Map<String, dynamic> dados) async {
    final data = await ApiClient.put('/fornecedores/$id', dados);
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
        'id':        item['id'],
        'nome':      item['nome'],
        'medida':    item['medida'],
        'espessura': item['espessura'],
      };
    }).toList();
  }
}