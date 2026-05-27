import '../models/estoque_model.dart';
import '../utils/api_client.dart';

class EstoqueRepository {

  // ── Controle de Estoque (EM_ANDAMENTO) ────────────────────────────────────

  Future<List<RelacaoOSModel>> listarRelacoesOS({String? busca}) async {
    final path = busca != null && busca.isNotEmpty
        ? '/estoque?busca=${Uri.encodeComponent(busca)}'
        : '/estoque';
    final list = await ApiClient.getList(path);
    return list.map((e) => RelacaoOSModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RelacaoOSModel> buscarRelacaoOS(String numeroOS) async {
    final data = await ApiClient.get('/estoque/${Uri.encodeComponent(numeroOS)}');
    return RelacaoOSModel.fromJson(data);
  }

  // ── Relatórios (FECHADA) ──────────────────────────────────────────────────

  Future<List<RelacaoOSModel>> listarRelatoriosOS({
    String? busca,
    String? materialId,
    String? materialNome,
    String? materialIdentificador,
    String? materialMedida,
    String? materialEspessura,
  }) async {
    final params = <String>[];
    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }
    if (materialId != null && materialId.isNotEmpty) {
      params.add('materialId=${Uri.encodeComponent(materialId)}');
    }
    if (materialNome != null && materialNome.isNotEmpty) {
      params.add('materialNome=${Uri.encodeComponent(materialNome)}');
    }
    if (materialIdentificador != null && materialIdentificador.isNotEmpty) {
      params.add('materialIdentificador=${Uri.encodeComponent(materialIdentificador)}');
    }
    if (materialMedida != null && materialMedida.isNotEmpty) {
      params.add('materialMedida=${Uri.encodeComponent(materialMedida)}');
    }
    if (materialEspessura != null && materialEspessura.isNotEmpty) {
      params.add('materialEspessura=${Uri.encodeComponent(materialEspessura)}');
    }
    final path = params.isEmpty
        ? '/relatorios-os'
        : '/relatorios-os?${params.join('&')}';
    final list = await ApiClient.getList(path);
    return list.map((e) => RelacaoOSModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── Movimentações ─────────────────────────────────────────────────────────

  Future<MovimentacaoModel> registrarMovimentacao({
    required int materialId,
    required String tipo,
    required double quantidade,
    required String numeroOS,
    double? precoUnitario,
    double? precoM2,
    String? observacao,
    int? ordemCompraId,
    String? descricaoItem,
  }) async {
    final data = await ApiClient.post('/estoque/movimentacoes', {
      'materialId': materialId,
      'tipo':       tipo,
      'quantidade': quantidade,
      'numeroOS':   numeroOS,
      if (precoUnitario != null)  'precoUnitario': precoUnitario,
      if (precoM2 != null)        'precoM2':       precoM2,
      if (observacao != null)     'observacao':    observacao,
      if (ordemCompraId != null)  'ordemCompraId': ordemCompraId,
      if (descricaoItem != null)  'descricaoItem': descricaoItem,
    });
    return MovimentacaoModel.fromJson(data);
  }

  Future<void> removerMovimentacao(int movimentacaoId) async {
    await ApiClient.delete('/estoque/movimentacoes/$movimentacaoId');
  }

  // ── RelacaoOS ─────────────────────────────────────────────────────────────

  /// Usa o [id] numérico da RelacaoOS — OS textuais podem ter múltiplas
  /// relações com o mesmo numeroOS, então o id garante a relação correta.
  Future<void> excluirRelacaoOS(int relacaoOSId) async {
    await ApiClient.delete('/estoque/$relacaoOSId');
  }

  /// Renomeia a OS: altera o numeroOS da RelacaoOS e de todas as suas movimentações.
  /// Só permitido para OS em andamento.
  Future<RelacaoOSModel> renomearOS(int relacaoOSId, String novoNumeroOS) async {
    final data = await ApiClient.patch(
      '/estoque/$relacaoOSId/renomear',
      {'novoNumeroOS': novoNumeroOS},
    );
    return RelacaoOSModel.fromJson(data);
  }

  /// Fecha a OS: muda status para FECHADA no backend.
  /// A OS deixa de aparecer no controle de estoque e passa para relatórios.
  Future<RelacaoOSModel> fecharOS(int relacaoOSId) async {
    final data = await ApiClient.patch('/estoque/$relacaoOSId/fechar');
    return RelacaoOSModel.fromJson(data);
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  Future<List<int>> baixarPdf({
    String? categoria,
    String? status,
    String? busca,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    final cat = (categoria == null || categoria.isEmpty) ? 'TODAS' : categoria;
    final st  = (status == null || status.isEmpty) ? 'TODOS' : status;
    final params = StringBuffer(
      '/estoque/pdf?categoria=${Uri.encodeComponent(cat)}&status=${Uri.encodeComponent(st)}',
    );
    if (busca != null && busca.isNotEmpty) {
      params.write('&busca=${Uri.encodeComponent(busca)}');
    }
    if (id != null && id.isNotEmpty) {
      params.write('&id=${Uri.encodeComponent(id)}');
    }
    if (identificador != null && identificador.isNotEmpty) {
      params.write('&identificador=${Uri.encodeComponent(identificador)}');
    }
    if (medida != null && medida.isNotEmpty) {
      params.write('&medida=${Uri.encodeComponent(medida)}');
    }
    if (espessura != null && espessura.isNotEmpty) {
      params.write('&espessura=${Uri.encodeComponent(espessura)}');
    }
    return ApiClient.getBytes(params.toString());
  }

  /// Reverte a OS: muda status de FECHADA para EM_ANDAMENTO.
  /// A OS volta a aparecer no controle de estoque e some dos relatórios.
  Future<RelacaoOSModel> reverterOS(String numeroOS) async {
    final data = await ApiClient.patch(
      '/relatorios-os/${Uri.encodeComponent(numeroOS)}/reverter',
    );
    return RelacaoOSModel.fromJson(data);
  }

  /// Baixa o PDF de relatório de uma OS fechada gerado pelo backend.
  /// Retorna os bytes brutos do PDF para salvar em arquivo temporário e abrir no SO.
  Future<List<int>> baixarRelatorioOSPdf(String numeroOS) async {
    return ApiClient.getBytes(
      '/relatorios-os/${Uri.encodeComponent(numeroOS)}/pdf',
    );
  }

  Future<List<RelacaoOSModel>> listarTodasRelacoesOS({String? busca}) async {
    final path = busca != null && busca.isNotEmpty
        ? '/estoque/todas?busca=${Uri.encodeComponent(busca)}'
        : '/estoque/todas';
    final list = await ApiClient.getList(path);
    return list.map((e) => RelacaoOSModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}