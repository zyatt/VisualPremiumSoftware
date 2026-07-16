import '../models/estoque_producao_model.dart';
import '../utils/api_client.dart';

class EstoqueProducaoRepository {
  /// Transfere material do estoque normal para o estoque de produção.
  /// Chamado pela página de Controle de Estoque (botão "Saída p/ Produção").
  Future<void> transferir({
    required int materialId,
    required double quantidade,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    await ApiClient.post('/estoque-producao/transferir', {
      'materialId': materialId,
      'quantidade': quantidade,
      if (observacao != null && observacao.isNotEmpty) 'observacao': observacao,
      if (larguraUsada != null)     'larguraUsada':     larguraUsada,
      if (comprimentoUsado != null) 'comprimentoUsado': comprimentoUsado,
    });
  }

  /// Lista os materiais atualmente disponíveis no estoque de produção.
  Future<List<MaterialEstoqueProducaoModel>> listarEstoque({
    String? busca,
    String? categoria,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    final params = <String, String>{};
    if (busca != null && busca.isNotEmpty)                 params['busca']         = busca;
    if (categoria != null && categoria.isNotEmpty)         params['categoria']     = categoria;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)               params['medida']        = medida;
    if (espessura != null && espessura.isNotEmpty)         params['espessura']     = espessura;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/estoque-producao' : '/estoque-producao?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MaterialEstoqueProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Dá baixa no estoque de produção, vinculando a uma OS.
  Future<void> darBaixa({
    required int materialId,
    required double quantidade,
    required String numeroOS,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    await ApiClient.post('/estoque-producao/baixas', {
      'materialId': materialId,
      'quantidade': quantidade,
      'numeroOS':   numeroOS,
      if (observacao != null && observacao.isNotEmpty) 'observacao': observacao,
      if (larguraUsada != null)     'larguraUsada':     larguraUsada,
      if (comprimentoUsado != null) 'comprimentoUsado': comprimentoUsado,
    });
  }

  /// Histórico do estoque de produção (transferências recebidas + baixas por OS).
  Future<List<MovimentacaoProducaoModel>> listarHistorico({
    String? busca,
    String? numeroOS,
  }) async {
    final params = <String, String>{};
    if (busca != null && busca.isNotEmpty)       params['busca']    = busca;
    if (numeroOS != null && numeroOS.isNotEmpty) params['numeroOS'] = numeroOS;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = query.isEmpty ? '/estoque-producao/historico' : '/estoque-producao/historico?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MovimentacaoProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}