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

  Future<List<RelacaoOSModel>> listarRelatoriosOS({String? busca}) async {
    final path = busca != null && busca.isNotEmpty
        ? '/relatorios-os?busca=${Uri.encodeComponent(busca)}'
        : '/relatorios-os';
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

  /// Fecha a OS: muda status para FECHADA no backend.
  /// A OS deixa de aparecer no controle de estoque e passa para relatórios.
  Future<RelacaoOSModel> fecharOS(int relacaoOSId) async {
    final data = await ApiClient.patch('/estoque/$relacaoOSId/fechar');
    return RelacaoOSModel.fromJson(data);
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  Future<List<int>> baixarPdf({String? categoria, String? status}) async {
    final cat = (categoria == null || categoria.isEmpty) ? 'TODAS' : categoria;
    final st  = (status == null || status.isEmpty) ? 'TODOS' : status;
    return ApiClient.getBytes(
      '/estoque/pdf?categoria=${Uri.encodeComponent(cat)}&status=${Uri.encodeComponent(st)}',
    );
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