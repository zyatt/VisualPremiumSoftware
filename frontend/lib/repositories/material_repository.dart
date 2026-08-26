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
    String? largura,
    String? comprimento,
    bool? ativo,
    int? limite,
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
    if (largura != null && largura.isNotEmpty)           params['largura']      = largura;
    if (comprimento != null && comprimento.isNotEmpty)   params['comprimento']  = comprimento;
    if (ativo != null)                                   params['ativo']        = ativo.toString();
    if (limite != null)                                  params['limite']       = limite.toString();

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/materiais' : '/materiais?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MaterialModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, String> _paramsComuns({
    String? busca,
    String? categoria,
    String? status,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
    bool? ativo,
    bool? comFornecedor,
  }) {
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
    if (ativo != null)                                   params['ativo']        = ativo.toString();
    if (comFornecedor == true)                           params['comFornecedor'] = 'true';
    return params;
  }

  Future<MateriaisPaginadosModel> listarPaginado({
    String? busca,
    String? categoria,
    String? status,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
    String? largura,
    String? comprimento,
    bool? ativo,
    bool? comFornecedor,
    required int pagina,
    int porPagina = 50,
    String? ordenarPor,
    String? direcao,
  }) async {
    final params = _paramsComuns(
      busca: busca,
      categoria: categoria,
      status: status,
      id: id,
      identificador: identificador,
      medida: medida,
      espessura: espessura,
      ativo: ativo,
      comFornecedor: comFornecedor,
    );
    if (largura != null && largura.isNotEmpty)       params['largura']      = largura;
    if (comprimento != null && comprimento.isNotEmpty) params['comprimento'] = comprimento;
    params['pagina']    = pagina.toString();
    params['porPagina'] = porPagina.toString();
    if (ordenarPor != null && ordenarPor.isNotEmpty) params['ordenarPor'] = ordenarPor;
    if (direcao != null && direcao.isNotEmpty)       params['direcao']    = direcao;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final data = await ApiClient.get('/materiais/paginado?$query');

    final itens = (data['data'] as List? ?? [])
        .map((e) => MaterialModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? itens.length;
    return MateriaisPaginadosModel(itens: itens, total: total);
  }

  Future<MateriaisPaginadosModel> listarParaMovimentacao({
    String? busca,
    String? categoria,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
    String? largura,
    String? comprimento,
    required int pagina,
    int porPagina = 50,
  }) async {
    final params = <String, String>{};
    if (busca != null && busca.isNotEmpty)                 params['busca']         = busca;
    if (id != null && id.isNotEmpty)                       params['id']            = id;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)               params['medida']        = medida;
    if (espessura != null && espessura.isNotEmpty)         params['espessura']     = espessura;
    if (largura != null && largura.isNotEmpty)             params['largura']       = largura;
    if (comprimento != null && comprimento.isNotEmpty)     params['comprimento']   = comprimento;
    if (categoria != null && categoria.isEmpty) {
      params['semCategoria'] = 'true';
    } else if (categoria != null && categoria.isNotEmpty) {
      params['categoria'] = categoria;
    }
    params['pagina']    = pagina.toString();
    params['porPagina'] = porPagina.toString();

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final data = await ApiClient.get('/materiais/para-movimentacao?$query');

    final itens = (data['data'] as List? ?? [])
        .map((e) => MaterialModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? itens.length;
    return MateriaisPaginadosModel(itens: itens, total: total);
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

  Future<void> desativar(int id) async {
    await ApiClient.patch('/materiais/$id/desativar');
  }

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

  Future<List<HistoricoPrecoModel>> listarHistoricoPrecos(int materialId) async {
    final list = await ApiClient.getList('/materiais/$materialId/historico-precos');
    return list
        .map((e) => HistoricoPrecoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MaterialModel> atualizarCustoManual(
    int id, {
    double? ultimoValorPago,
    double? ultimoValorPagoM2,
  }) async {
    final body = <String, dynamic>{};
    if (ultimoValorPago   != null) body['ultimoValorPago']   = ultimoValorPago;
    if (ultimoValorPagoM2 != null) body['ultimoValorPagoM2'] = ultimoValorPagoM2;
    final data = await ApiClient.patch('/materiais/$id/custo', body);
    return MaterialModel.fromJson(data);
  }
}