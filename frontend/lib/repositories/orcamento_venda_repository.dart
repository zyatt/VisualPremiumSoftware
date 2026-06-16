import '../models/orcamento_venda_model.dart';
import '../utils/api_client.dart';

class OrcamentoVendaRepository {
  // ── Orçamentos ──────────────────────────────────────────────────────────────

  Future<List<OrcamentoVendaModel>> listar({
    String? status,
    String? busca,
  }) async {
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (busca != null && busca.isNotEmpty)   params['busca']  = busca;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/orcamentos-venda' : '/orcamentos-venda?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => OrcamentoVendaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<OrcamentoVendaModel> buscarPorId(int id) async {
    final data = await ApiClient.get('/orcamentos-venda/$id');
    return OrcamentoVendaModel.fromJson(data);
  }

  Future<OrcamentoVendaModel> criar(Map<String, dynamic> dados) async {
    final data = await ApiClient.post('/orcamentos-venda', dados);
    return OrcamentoVendaModel.fromJson(data);
  }

  Future<OrcamentoVendaModel> atualizar(
      int id, Map<String, dynamic> dados) async {
    final data = await ApiClient.put('/orcamentos-venda/$id', dados);
    return OrcamentoVendaModel.fromJson(data);
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/orcamentos-venda/$id');
  }

  Future<void> aprovar(int id) async {
    await ApiClient.patch('/orcamentos-venda/$id/aprovar', {});
  }

  Future<void> reprovar(int id) async {
    await ApiClient.patch('/orcamentos-venda/$id/reprovar', {});
  }

  // ── Itens ───────────────────────────────────────────────────────────────────

  Future<OrcamentoVendaItemModel> adicionarItem(
      int orcamentoId, Map<String, dynamic> dados) async {
    final data =
        await ApiClient.post('/orcamentos-venda/$orcamentoId/itens', dados);
    return OrcamentoVendaItemModel.fromJson(data);
  }

  Future<OrcamentoVendaItemModel> atualizarItem(
      int orcamentoId, int itemId, Map<String, dynamic> dados) async {
    final data = await ApiClient.put(
        '/orcamentos-venda/$orcamentoId/itens/$itemId', dados);
    return OrcamentoVendaItemModel.fromJson(data);
  }

  Future<void> removerItem(int orcamentoId, int itemId) async {
    await ApiClient.delete('/orcamentos-venda/$orcamentoId/itens/$itemId');
  }

  // ── Clientes (lookup) ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarClientes({String? busca}) async {
    final path = busca != null && busca.isNotEmpty
        ? '/orcamentos-venda/clientes?busca=${Uri.encodeComponent(busca)}'
        : '/orcamentos-venda/clientes';
    final list = await ApiClient.getList(path);
    return list.map((e) => e as Map<String, dynamic>).toList();
  }
}