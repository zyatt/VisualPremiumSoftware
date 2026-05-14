import '../models/estoque_model.dart';
import '../utils/api_client.dart';

class EstoqueRepository {
  // Relações OS (grid de cards do controle de estoque)
  Future<List<RelacaoOSModel>> listarRelacoesOS({String? busca}) async {
    final path = busca != null && busca.isNotEmpty
        ? '/estoque/relacoes?busca=${Uri.encodeComponent(busca)}'
        : '/estoque/relacoes';
    final list = await ApiClient.getList(path);
    return list.map((e) => RelacaoOSModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RelacaoOSModel> buscarRelacaoOS(String numeroOS) async {
    final data = await ApiClient.get('/estoque/relacoes/$numeroOS');
    return RelacaoOSModel.fromJson(data);
  }

  Future<MovimentacaoModel> registrarMovimentacao({
    required int materialId,
    required String tipo, // ENTRADA | SAIDA
    required double quantidade,
    required String numeroOS,
    double? precoUnitario,
    String? observacao,
    int? ordemCompraId,
  }) async {
    final data = await ApiClient.post('/estoque/movimentacao', {
      'materialId':    materialId,
      'tipo':          tipo,
      'quantidade':    quantidade,
      'numeroOS':      numeroOS,
      if (precoUnitario != null) 'precoUnitario': precoUnitario,
      if (observacao != null)    'observacao':    observacao,
      if (ordemCompraId != null) 'ordemCompraId': ordemCompraId,
    });
    return MovimentacaoModel.fromJson(data);
  }

  Future<List<MovimentacaoModel>> listarMovimentacoesPorMaterial(int materialId) async {
    final list = await ApiClient.getList('/estoque/material/$materialId/movimentacoes');
    return list.map((e) => MovimentacaoModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}