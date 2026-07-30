import '../models/estoque_producao_model.dart';
import '../utils/api_client.dart';

class EstoqueProducaoRepository {
  /// Transfere material do estoque normal para o estoque de produção.
  /// Chamado pela página de Controle de Estoque (botão "Saída p/ Produção").
  /// [producao] indica para qual linha ('1' ou '2') a transferência vai.
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

  /// Devolve material do estoque de produção de volta para o estoque normal
  /// (operação inversa de [transferir]). [producao] indica de qual linha
  /// ('1' ou '2') o material está sendo devolvido.
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

  /// Transfere material de uma linha de produção para a outra ('1' <-> '2').
  /// Restrito a ADMIN/GERENTE no backend (roleMiddleware da rota).
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

  /// Lista os materiais atualmente disponíveis no estoque de produção.
  /// [producao] indica de qual linha ('1' ou '2') consultar o saldo.
  Future<List<MaterialEstoqueProducaoModel>> listarEstoque({
    required String producao,
    String? busca,
    String? categoria,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    final params = <String, String>{'producao': producao};
    if (busca != null && busca.isNotEmpty)                 params['busca']         = busca;
    if (categoria != null && categoria.isNotEmpty)         params['categoria']     = categoria;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)               params['medida']        = medida;
    if (espessura != null && espessura.isNotEmpty)         params['espessura']     = espessura;

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = '/estoque-producao?$query';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MaterialEstoqueProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Dá baixa no estoque de produção, vinculando a uma OS.
  /// [producao] indica de qual linha ('1' ou '2') a baixa é feita.
  ///
  /// BAIXA COMBINADA: [quantidade] (unidades inteiras) e
  /// [larguraUsada]/[comprimentoUsado] (dimensão usada de uma unidade
  /// adicional parcial) são ambos OPCIONAIS — o backend exige que pelo
  /// menos um dos dois seja informado. Preencher os dois soma-se numa
  /// única baixa (ver estoqueProducao.service.js#darBaixa).
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

  /// Histórico do estoque de produção (transferências recebidas + baixas
  /// por OS). Compartilhado entre as duas linhas — [producao] é um filtro
  /// OPCIONAL para restringir a apenas uma delas.
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

  /// Exclui um registro do histórico do estoque de produção (transferência
  /// ou baixa). Apenas remove o registro — não altera o saldo do estoque.
  Future<void> excluirHistorico(int movimentacaoId) async {
    await ApiClient.delete('/estoque-producao/historico/$movimentacaoId');
  }

  /// Lista as entradas pendentes de confirmação (retalho + devolução).
  /// Sem filtro de linha por padrão — traz todas.
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

  /// Total de pendências (para o badge do botão "Saída p/ Produção").
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