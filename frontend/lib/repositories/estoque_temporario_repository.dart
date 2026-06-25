// estoque_temporario_repository.dart
import '../models/estoque_temporario_model.dart';
import '../utils/api_client.dart';

class EstoqueTemporarioRepository {
  Future<List<EstoqueTemporarioModel>> listar({String? busca}) async {
    final path = (busca != null && busca.isNotEmpty)
        ? '/estoque-temporario?busca=${Uri.encodeComponent(busca)}'
        : '/estoque-temporario';
    final list = await ApiClient.getList(path);
    return list
        .map((e) => EstoqueTemporarioModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EstoqueTemporarioModel> criar(Map<String, dynamic> dados) async {
    final data = await ApiClient.post('/estoque-temporario', dados);
    return EstoqueTemporarioModel.fromJson(data);
  }

  Future<EstoqueTemporarioModel> atualizar(
      int id, Map<String, dynamic> dados) async {
    final data = await ApiClient.put('/estoque-temporario/$id', dados);
    return EstoqueTemporarioModel.fromJson(data);
  }

  /// Desativa o material temporário no backend (ativo = false).
  Future<void> remover(int id) async {
    await ApiClient.delete('/estoque-temporario/$id');
  }

  /// Reativa um material temporário desativado (ativo = true) e
  /// renova o prazo de desativação por mais 3 meses.
  Future<EstoqueTemporarioModel> reativar(int id) async {
    final data = await ApiClient.post('/estoque-temporario/$id/reativar', {});
    return EstoqueTemporarioModel.fromJson(data);
  }
}