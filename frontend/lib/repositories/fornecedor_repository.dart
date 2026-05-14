import '../utils/api_client.dart';

class FornecedorRepository {
  Future<List<dynamic>> listar() async {
    return await ApiClient.getList('/fornecedores');
  }

  Future<Map<String, dynamic>> buscarPorId(int id) async {
    return await ApiClient.get('/fornecedores/$id');
  }

  Future<Map<String, dynamic>> criar(Map<String, dynamic> dados) async {
    return await ApiClient.post('/fornecedores', dados);
  }

  Future<Map<String, dynamic>> atualizar(int id, Map<String, dynamic> dados) async {
    return await ApiClient.put('/fornecedores/$id', dados);
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/fornecedores/$id');
  }

  Future<void> vincularMaterial(int fornecedorId, Map<String, dynamic> dados) async {
    await ApiClient.post('/fornecedores/$fornecedorId/materiais', dados);
  }

  Future<void> desvincularMaterial(int fornecedorId, int materialId) async {
    await ApiClient.delete('/fornecedores/$fornecedorId/materiais/$materialId');
  }

  /// Busca fornecedores que possuem um determinado material vinculado
  Future<List<dynamic>> listarPorMaterial(int materialId) async {
    return await ApiClient.getList('/fornecedores/material/$materialId');
  }
}