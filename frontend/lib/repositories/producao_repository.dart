import '../models/producao_model.dart';
import '../utils/api_client.dart';

class ProducaoRepository {

  // ── Materiais ─────────────────────────────────────────────────────────────

  Future<List<MaterialProducaoModel>> listarMateriais({
    String? busca,
    String? categoria,
    String? status,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    final params = <String>[];
    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }
    if (categoria != null && categoria.isNotEmpty) {
      params.add('categoria=${Uri.encodeComponent(categoria)}');
    }
    if (status != null && status.isNotEmpty) {
      params.add('status=${Uri.encodeComponent(status)}');
    }
    if (id != null && id.isNotEmpty) {
      params.add('id=${Uri.encodeComponent(id)}');
    }
    if (identificador != null && identificador.isNotEmpty) {
      params.add('identificador=${Uri.encodeComponent(identificador)}');
    }
    if (medida != null && medida.isNotEmpty) {
      params.add('medida=${Uri.encodeComponent(medida)}');
    }
    if (espessura != null && espessura.isNotEmpty) {
      params.add('espessura=${Uri.encodeComponent(espessura)}');
    }

    final path = params.isEmpty
        ? '/producao/materiais'
        : '/producao/materiais?${params.join('&')}';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => MaterialProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> listarCategorias() async {
    final list = await ApiClient.getList('/producao/categorias');
    return list.cast<String>();
  }

  // ── Solicitações ──────────────────────────────────────────────────────────

  Future<List<SolicitacaoProducaoModel>> listarSolicitacoes({
    List<String>? status,
    String? busca,
  }) async {
    final params = <String>[];
    if (status != null && status.isNotEmpty) {
      params.add('status=${status.join(',')}');
    }
    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }

    final path = params.isEmpty
        ? '/producao/solicitacoes'
        : '/producao/solicitacoes?${params.join('&')}';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => SolicitacaoProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SolicitacaoProducaoModel>> listarHistorico({String? busca}) async {
    final params = <String>[];
    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }

    final path = params.isEmpty
        ? '/producao/historico'
        : '/producao/historico?${params.join('&')}';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => SolicitacaoProducaoModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SolicitacaoProducaoModel> buscarSolicitacao(int id) async {
    final data = await ApiClient.get('/producao/solicitacoes/$id');
    return SolicitacaoProducaoModel.fromJson(data);
  }

  Future<SolicitacaoProducaoModel> criarSolicitacao({
    required int materialId,
    String? descricaoItem,
    required double quantidadeReservada,
    required String numeroOS,
  }) async {
    final data = await ApiClient.post('/producao/solicitacoes', {
      'materialId':          materialId,
      if (descricaoItem != null) 'descricaoItem': descricaoItem,
      'quantidadeReservada': quantidadeReservada,
      'numeroOS':            numeroOS,
    });
    return SolicitacaoProducaoModel.fromJson(data);
  }

  Future<SolicitacaoProducaoModel> registrarBaixa({
    required int solicitacaoId,
    required double quantidade,
    String? observacao,
  }) async {
    final data = await ApiClient.post(
      '/producao/solicitacoes/$solicitacaoId/baixa',
      {
        'quantidade': quantidade,
        if (observacao != null) 'observacao': observacao,
      },
    );
    return SolicitacaoProducaoModel.fromJson(data);
  }

  Future<SolicitacaoProducaoModel> finalizarSolicitacao(int solicitacaoId) async {
    final data = await ApiClient.post(
      '/producao/solicitacoes/$solicitacaoId/finalizar',
      {},
    );
    return SolicitacaoProducaoModel.fromJson(data);
  }

  Future<void> excluirHistorico(int solicitacaoId) async {
    await ApiClient.delete('/producao/historico/$solicitacaoId');
  }
}