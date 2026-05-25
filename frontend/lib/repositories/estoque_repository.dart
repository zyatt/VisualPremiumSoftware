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
  }) async {
    final data = await ApiClient.post('/estoque/movimentacoes', {
      'materialId': materialId,
      'tipo':       tipo,
      'quantidade': quantidade,
      'numeroOS':   numeroOS,
      if (precoUnitario != null) 'precoUnitario': precoUnitario,
      if (precoM2 != null)       'precoM2':       precoM2,
      if (observacao != null)    'observacao':    observacao,
      if (ordemCompraId != null) 'ordemCompraId': ordemCompraId,
    });
    return MovimentacaoModel.fromJson(data);
  }

  Future<void> removerMovimentacao(int movimentacaoId) async {
    await ApiClient.delete('/estoque/movimentacoes/$movimentacaoId');
  }

  // ── RelacaoOS ─────────────────────────────────────────────────────────────

  Future<void> excluirRelacaoOS(String numeroOS) async {
    await ApiClient.delete('/estoque/${Uri.encodeComponent(numeroOS)}');
  }

  /// Fecha a OS: muda status para FECHADA no backend.
  /// A OS deixa de aparecer no controle de estoque e passa para relatórios.
  Future<RelacaoOSModel> fecharOS(String numeroOS) async {
    final data = await ApiClient.patch('/estoque/${Uri.encodeComponent(numeroOS)}/fechar');
    return RelacaoOSModel.fromJson(data);
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  Future<List<int>> baixarPdf({String? categoria}) async {
    final cat = (categoria == null || categoria.isEmpty) ? 'TODAS' : categoria;
    return ApiClient.getBytes('/estoque/pdf?categoria=${Uri.encodeComponent(cat)}');
  }
}