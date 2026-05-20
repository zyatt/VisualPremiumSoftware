import '../models/material_model.dart';
import '../utils/api_client.dart';

class MaterialRepository {
  Future<List<MaterialModel>> listar({
    String? busca,
    String? categoria,
    String? status,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    final params = <String, String>{};
    if (busca != null && busca.isNotEmpty)               params['busca']        = busca;
    if (categoria != null && categoria.isEmpty) {
      params['semCategoria'] = 'true';
    } else if (categoria != null && categoria.isNotEmpty)  {
      params['categoria']    = categoria;
    }
    if (status != null && status.isNotEmpty)             params['status']       = status;
    if (id != null && id.isNotEmpty)                     params['id']           = id;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)             params['medida']       = medida;
    if (espessura != null && espessura.isNotEmpty)       params['espessura']    = espessura;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/materiais' : '/materiais?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MaterialModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MaterialModel> buscarPorId(int id) async {
    final data = await ApiClient.get('/materiais/$id');
    return MaterialModel.fromJson(data);
  }

  Future<MaterialModel> criar(Map<String, dynamic> dados) async {
    final data = await ApiClient.post('/materiais', dados);
    return MaterialModel.fromJson(data);
  }

  Future<MaterialModel> atualizar(int id, Map<String, dynamic> dados) async {
    final data = await ApiClient.put('/materiais/$id', dados);
    return MaterialModel.fromJson(data);
  }

  /// PATCH /api/materiais/:id/desativar
  Future<void> desativar(int id) async {
    await ApiClient.patch('/materiais/$id/desativar');
  }

  /// PATCH /api/materiais/:id/confirmar
  Future<void> confirmarEstoque(int id) async {
    await ApiClient.patch('/materiais/$id/confirmar');
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/materiais/$id');
  }

  Future<List<String>> listarCategorias() async {
    final list = await ApiClient.getList('/materiais/categorias');
    return list.map((e) => e.toString()).toList();
  }

  Future<MaterialModel> reativar(int id) async {
    final data = await ApiClient.patch('/materiais/$id/reativar', {});
    return MaterialModel.fromJson(data);
  }

  /// GET /api/materiais/:id/historico-precos
  /// Retorna o histórico de custos pagos via OC finalizada para o material.
  Future<List<HistoricoPrecoModel>> listarHistoricoPrecos(int materialId) async {
    final list = await ApiClient.getList('/materiais/$materialId/historico-precos');
    return list
        .map((e) => HistoricoPrecoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}