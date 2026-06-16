import '../models/produto_model.dart';
import '../utils/api_client.dart';

class ProdutoRepository {
  Future<List<ProdutoModel>> listar({
    String? busca,
    String? categoria,
    bool? ativo,
  }) async {
    final params = <String, String>{};
    if (busca != null && busca.isNotEmpty)         params['busca']     = busca;
    if (categoria != null && categoria.isNotEmpty) params['categoria'] = categoria;
    if (ativo != null)                             params['ativo']     = ativo.toString();

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/produtos' : '/produtos?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => ProdutoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ProdutoModel> buscarPorId(int id) async {
    final data = await ApiClient.get('/produtos/$id');
    return ProdutoModel.fromJson(data);
  }

  Future<ProdutoModel> criar(Map<String, dynamic> dados) async {
    final data = await ApiClient.post('/produtos', dados);
    return ProdutoModel.fromJson(data);
  }

  Future<ProdutoModel> atualizar(int id, Map<String, dynamic> dados) async {
    final data = await ApiClient.put('/produtos/$id', dados);
    return ProdutoModel.fromJson(data);
  }

  Future<void> desativar(int id) async {
    await ApiClient.patch('/produtos/$id/desativar', {});
  }

  Future<void> reativar(int id) async {
    await ApiClient.patch('/produtos/$id/reativar', {});
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/produtos/$id');
  }

  Future<List<String>> listarCategorias() async {
    final list = await ApiClient.getList('/produtos/categorias');
    return list.map((e) => e.toString()).toList();
  }

  Future<ProdutoModel> adicionarMaterial(
      int produtoId, Map<String, dynamic> dados) async {
    final data =
        await ApiClient.post('/produtos/$produtoId/materiais', dados);
    return ProdutoModel.fromJson(data);
  }

  Future<void> atualizarMaterial(
      int produtoId, int materialItemId, Map<String, dynamic> dados) async {
    await ApiClient.patch(
        '/produtos/$produtoId/materiais/$materialItemId', dados);
  }

  Future<void> removerMaterial(int produtoId, int materialItemId) async {
    await ApiClient.delete('/produtos/$produtoId/materiais/$materialItemId');
  }
}