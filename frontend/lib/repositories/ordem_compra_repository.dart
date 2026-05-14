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

  Future<Map<String, dynamic>> atualizar(int id, Map<String, dynamic> dados) async {
    return await ApiClient.put('/ordens-compra/$id', dados);
  }

  Future<void> atualizarStatus(int id, String status) async {
    await ApiClient.put('/ordens-compra/$id/status', {'status': status});
  }
}