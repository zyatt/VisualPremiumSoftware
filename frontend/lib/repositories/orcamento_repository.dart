import 'dart:typed_data';
import '../utils/api_client.dart';

/// Repositório para operações de Orçamento.
class OrcamentoRepository {
  // ── Listar ────────────────────────────────────

  Future<List<dynamic>> listar({String? status}) async {
    final path = status != null ? '/orcamentos?status=$status' : '/orcamentos';
    return ApiClient.getList(path);
  }

  /// Histórico do servidor: todos os status exceto CONVERTIDO.
  Future<List<dynamic>> listarHistorico() async {
    final abertos = await ApiClient.getList('/orcamentos?status=ABERTO');
    final aguardando = await ApiClient.getList('/orcamentos?status=AGUARDANDO_APROVACAO');
    final aprovados = await ApiClient.getList('/orcamentos?status=APROVADO');
    final naoAprovados = await ApiClient.getList('/orcamentos?status=NAO_APROVADO');
    final cancelados = await ApiClient.getList('/orcamentos?status=CANCELADO');
    final todos = [...abertos, ...aguardando, ...aprovados, ...naoAprovados, ...cancelados];
    todos.sort((a, b) {
      final da = DateTime.tryParse(a['criadoEm']?.toString() ?? '') ?? DateTime(0);
      final db = DateTime.tryParse(b['criadoEm']?.toString() ?? '') ?? DateTime(0);
      return db.compareTo(da);
    });
    return todos;
  }

  Future<Map<String, dynamic>> buscarPorId(int id) async {
    return ApiClient.get('/orcamentos/$id');
  }

  Future<Map<String, dynamic>> criar(String titulo) async {
    return ApiClient.post('/orcamentos', {'titulo': titulo});
  }

  // ── Adicionar item ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> adicionarItem(
      int orcamentoId, Map<String, dynamic> item) async {
    return ApiClient.post('/orcamentos/$orcamentoId/itens', item);
  }

  // ── Remover item ──────────────────────────────────────────────────────────────

  Future<void> removerItem(int orcamentoId, int itemId) async {
    await ApiClient.delete('/orcamentos/$orcamentoId/itens/$itemId');
  }

  // ── Limpar todos os itens (operação atômica) ──────────────────────────────────
  // Substitui o loop de removerItem com catch silencioso, evitando duplicatas
  // causadas por falhas parciais de remoção.

  Future<void> limparItens(int orcamentoId) async {
    await ApiClient.delete('/orcamentos/$orcamentoId/itens');
  }

  // ── Atualizar item ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> atualizarItem(
      int orcamentoId, int itemId, Map<String, dynamic> dados) async {
    return ApiClient.patch('/orcamentos/$orcamentoId/itens/$itemId', dados);
  }

  // ── Cancelar ──────────────────────────────────

  Future<Map<String, dynamic>> cancelar(int id) async {
    return ApiClient.patch('/orcamentos/$id/cancelar');
  }

  // ── Enviar para aprovação ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> enviarParaAprovacao(int id) async {
    return ApiClient.patch('/orcamentos/$id/enviar-aprovacao', {});
  }

  // ── Aprovar ───────────────────────────────────

  Future<Map<String, dynamic>> aprovar(int id) async {
    return ApiClient.patch('/orcamentos/$id/aprovar', {});
  }

  // ── Rejeitar ──────────────────────────────────

  Future<Map<String, dynamic>> rejeitar(int id, String motivo) async {
    return ApiClient.patch('/orcamentos/$id/rejeitar', {'motivo': motivo});
  }

  // ── Reabrir ───────────────────────────────────

  Future<Map<String, dynamic>> reabrir(int id) async {
    return ApiClient.patch('/orcamentos/$id/reabrir', {});
  }

  // ── Gerar OC (validação server-side) ─────────────────────────────────────────

  Future<Map<String, dynamic>> gerarOrdemCompra(int id) async {
    return ApiClient.post('/orcamentos/$id/gerar-oc', {});
  }

  // ── Gerar PDF ─────────────────────────────────

  Future<Uint8List> gerarPdf(Map<String, dynamic> dadosOrcamento) async {
    return ApiClient.postBytes('/orcamentos/pdf', dadosOrcamento);
  }

  Future<Map<String, dynamic>> atualizarOrcamento(
      int id, Map<String, dynamic> dados) async {
    return ApiClient.patch('/orcamentos/$id', dados);
  }

  // ── Salvar rascunho completo no servidor ─────────────────────────────────────
  // Cria o orçamento + todos os itens de uma só vez.
  // Retorna o ID criado no banco.

  Future<int> salvarRascunho({
    required String titulo,
    required List<Map<String, dynamic>> itens,
  }) async {
    final criado = await criar(titulo);
    final id = criado['id'] as int;
    await atualizarOrcamento(id, {'titulo': titulo});
    for (final item in itens) {
      await adicionarItem(id, item);
    }
    return id;
  }
}