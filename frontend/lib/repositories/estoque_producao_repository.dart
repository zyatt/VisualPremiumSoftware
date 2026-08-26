import '../models/estoque_producao_model.dart';
import '../utils/api_client.dart';

class EstoqueProducaoRepository {
  Future<void> transferir({
    required int materialId,
    required double quantidade,
    required String producao,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    await ApiClient.post('/estoque-producao/transferir', {
      'materialId': materialId,
      'quantidade': quantidade,
      'producao':   producao,
      if (observacao != null && observacao.isNotEmpty) 'observacao': observacao,
      if (larguraUsada != null)     'larguraUsada':     larguraUsada,
      if (comprimentoUsado != null) 'comprimentoUsado': comprimentoUsado,
    });
  }

  Future<void> devolver({
    required int materialId,
    required double quantidade,
    required String producao,
    String? observacao,
  }) async {
    await ApiClient.post('/estoque-producao/devolver', {
      'materialId': materialId,
      'quantidade': quantidade,
      'producao':   producao,
      if (observacao != null && observacao.isNotEmpty) 'observacao': observacao,
    });
  }

  Future<void> transferirEntreLinhas({
    required int materialId,
    required double quantidade,
    required String producaoOrigem,
    required String producaoDestino,
    String? observacao,
  }) async {
    await ApiClient.post('/estoque-producao/transferir-linha', {
      'materialId':      materialId,
      'quantidade':      quantidade,
      'producaoOrigem':  producaoOrigem,
      'producaoDestino': producaoDestino,
      if (observacao != null && observacao.isNotEmpty) 'observacao': observacao,
    });
  }

  Future<List<MaterialEstoqueProducaoModel>> listarEstoque({
    required String producao,
    String? busca,
    String? categoria,
    String? identificador,
    String? medida,
    String? espessura,
    String? comprimento,
    String? largura,
  }) async {
    final params = <String, String>{'producao': producao};
    if (busca != null && busca.isNotEmpty)                 params['busca']         = busca;
    if (categoria != null && categoria.isNotEmpty)         params['categoria']     = categoria;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)               params['medida']        = medida;
    if (espessura != null && espessura.isNotEmpty)         params['espessura']     = espessura;
    if (comprimento != null && comprimento.isNotEmpty)     params['comprimento']   = comprimento;
    if (largura != null && largura.isNotEmpty)             params['largura']       = largura;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = '/estoque-producao?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MaterialEstoqueProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> darBaixa({
    required int materialId,
    double? quantidade,
    required String numeroOS,
    required String producao,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    await ApiClient.post('/estoque-producao/baixas', {
      'materialId': materialId,
      if (quantidade != null) 'quantidade': quantidade,
      'numeroOS':   numeroOS,
      'producao':   producao,
      if (observacao != null && observacao.isNotEmpty) 'observacao': observacao,
      if (larguraUsada != null)     'larguraUsada':     larguraUsada,
      if (comprimentoUsado != null) 'comprimentoUsado': comprimentoUsado,
    });
  }

  Future<List<MovimentacaoProducaoModel>> listarHistorico({
    String? busca,
    String? numeroOS,
    String? producao,
  }) async {
    final params = <String, String>{};
    if (busca != null && busca.isNotEmpty)       params['busca']    = busca;
    if (numeroOS != null && numeroOS.isNotEmpty) params['numeroOS'] = numeroOS;
    if (producao != null && producao.isNotEmpty) params['producao'] = producao;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/estoque-producao/historico' : '/estoque-producao/historico?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MovimentacaoProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> excluirHistorico(int movimentacaoId) async {
    await ApiClient.delete('/estoque-producao/historico/$movimentacaoId');
  }

  Future<List<EntradaPendenteModel>> listarPendentes({
    String? producao,
    String? tipo,
  }) async {
    final params = <String, String>{};
    if (producao != null && producao.isNotEmpty) params['producao'] = producao;
    if (tipo != null && tipo.isNotEmpty)         params['tipo']     = tipo;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/estoque-producao/pendentes' : '/estoque-producao/pendentes?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => EntradaPendenteModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> contarPendentes() async {
    final data = await ApiClient.get('/estoque-producao/pendentes/contador');
    return (data['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> confirmarPendente(int id) async {
    await ApiClient.post('/estoque-producao/pendentes/$id/confirmar', {});
  }

  Future<void> recusarPendente(int id) async {
    await ApiClient.post('/estoque-producao/pendentes/$id/recusar', {});
  }
}