import '../models/estoque_model.dart';
import '../utils/api_client.dart';

class EstoqueRepository {
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
    required String tipo,
    required double quantidade,
    required String numeroOS,
    double? precoUnitario,
    double? precoM2,
    String? observacao,
    int? ordemCompraId,
  }) async {
    final data = await ApiClient.post('/estoque/movimentacao', {
      'materialId':    materialId,
      'tipo':          tipo,
      'quantidade':    quantidade,
      'numeroOS':      numeroOS,
      if (precoUnitario != null) 'precoUnitario': precoUnitario,
      if (precoM2 != null)       'precoM2':       precoM2,
      if (observacao != null)    'observacao':    observacao,
      if (ordemCompraId != null) 'ordemCompraId': ordemCompraId,
    });
    return MovimentacaoModel.fromJson(data);
  }

  Future<List<MovimentacaoModel>> listarMovimentacoesPorMaterial(int materialId) async {
    final list = await ApiClient.getList('/estoque/material/$materialId/movimentacoes');
    return list.map((e) => MovimentacaoModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Remove uma movimentação pelo seu [id].
  Future<void> removerMovimentacao(int movimentacaoId) async {
    await ApiClient.delete('/estoque/movimentacao/$movimentacaoId');
  }

  /// Exclui a RelacaoOS inteira (e suas movimentações) pelo [numeroOS].
  Future<void> excluirRelacaoOS(String numeroOS) async {
    await ApiClient.delete('/estoque/relacoes/${Uri.encodeComponent(numeroOS)}');
  }

  Future<List<int>> baixarPdf({String? categoria}) async {
    final cat = (categoria == null || categoria.isEmpty) ? 'TODAS' : categoria;
    return ApiClient.getBytes('/estoque/pdf?categoria=${Uri.encodeComponent(cat)}');
  }
}