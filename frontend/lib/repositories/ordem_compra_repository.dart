import '../utils/api_client.dart';

class OrdensCompraPaginadasResult {
  final List<dynamic> itens;
  final int total;
  const OrdensCompraPaginadasResult({required this.itens, required this.total});
}

class OrdemCompraRepository {
  Future<List<dynamic>> listar() async {
    return await ApiClient.getList('/ordens-compra');
  }

  Future<OrdensCompraPaginadasResult> listarPagina({
    String? status,
    String? numero,
    String? material,
    String? identificador,
    String? medida,
    String? comprimento,
    String? largura,
    String? espessura,
    required int pagina,
    int porPagina = 50,
  }) async {
    final params = <String, String>{
      'pagina':    pagina.toString(),
      'porPagina': porPagina.toString(),
    };
    if (status != null && status.isNotEmpty)               params['status']        = status;
    if (numero != null && numero.isNotEmpty)                params['numero']        = numero;
    if (material != null && material.isNotEmpty)           params['material']      = material;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)               params['medida']        = medida;
    if (comprimento != null && comprimento.isNotEmpty)     params['comprimento']   = comprimento;
    if (largura != null && largura.isNotEmpty)             params['largura']       = largura;
    if (espessura != null && espessura.isNotEmpty)         params['espessura']     = espessura;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final data = await ApiClient.get('/ordens-compra/pagina?$query');

    final itens = (data['data'] as List? ?? []);
    final total = (data['total'] as num?)?.toInt() ?? itens.length;
    return OrdensCompraPaginadasResult(itens: itens, total: total);
  }

  Future<Map<String, int>> contarPorStatus() async {
    final data = await ApiClient.get('/ordens-compra/contagem-status');
    return {
      'EM_ANDAMENTO': (data['EM_ANDAMENTO'] as num?)?.toInt() ?? 0,
      'FINALIZADO':   (data['FINALIZADO']   as num?)?.toInt() ?? 0,
      'CANCELADO':    (data['CANCELADO']    as num?)?.toInt() ?? 0,
    };
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

  Future<List<int>> baixarPdf(int id) async {
    return ApiClient.getBytes('/ordens-compra/$id/pdf');
  }

  Future<Map<String, dynamic>> adicionarItem(
    int ordemCompraId,
    Map<String, dynamic> item,
  ) async {
    return ApiClient.post(
      '/ordens-compra/$ordemCompraId/itens',
      item,
    );
  }
}