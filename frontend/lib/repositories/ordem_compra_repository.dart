import '../utils/api_client.dart';

class OrdemCompraRepository {
  Future<List<dynamic>> listar() async {
    return await ApiClient.getList('/ordens-compra');
  }

  Future<Map<String, dynamic>> buscarPorId(int id) async {
    return await ApiClient.get('/ordens-compra/$id');
  }

  Future<Map<String, dynamic>> criar(Map<String, dynamic> dados) async {
    return await ApiClient.post('/ordens-compra', dados);
  }

  Future<int?> proximoId() async {
    try {
      final result = await ApiClient.get('/ordens-compra/proximo-id');
      return result['proximoId'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> atualizar(int id, Map<String, dynamic> dados) async {
    return await ApiClient.put('/ordens-compra/$id', dados);
  }

  Future<void> atualizarStatus(int id, String status) async {
    final rota = status == 'FINALIZADO' ? 'finalizar' : 'cancelar';
    await ApiClient.patch('/ordens-compra/$id/$rota');
  }

  Future<void> reverter(int id) async {
    await ApiClient.patch('/ordens-compra/$id/reverter');
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/ordens-compra/$id');
  }

  /// Baixa o PDF da OC e retorna os bytes prontos para exibição.
  Future<List<int>> baixarPdf(int id) async {
    return ApiClient.getBytes('/ordens-compra/$id/pdf');
  }
}