import 'dart:typed_data';
import '../utils/api_client.dart';

/// Repositório para operações de Orçamento.
class OrcamentoRepository {
  // ── Listar ────────────────────────────────────────────────────────────────────

  Future<List<dynamic>> listar() async {
    return ApiClient.getList('/orcamentos');
  }

  // ── Buscar por ID ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> buscarPorId(int id) async {
    return ApiClient.get('/orcamentos/$id');
  }

  // ── Criar ─────────────────────────────────────────────────────────────────────

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

  // ── Atualizar item ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> atualizarItem(
      int orcamentoId, int itemId, Map<String, dynamic> dados) async {
    return ApiClient.patch('/orcamentos/$orcamentoId/itens/$itemId', dados);
  }

  // ── Cancelar ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> cancelar(int id) async {
    return ApiClient.patch('/orcamentos/$id/cancelar');
  }

  // ── Gerar OC (validação server-side) ─────────────────────────────────────────

  Future<Map<String, dynamic>> gerarOrdemCompra(int id) async {
    return ApiClient.post('/orcamentos/$id/gerar-oc', {});
  }

  // ── Gerar PDF ─────────────────────────────────────────────────────────────────

  Future<Uint8List> gerarPdf(Map<String, dynamic> dadosOrcamento) async {
    return ApiClient.postBytes('/orcamentos/pdf', dadosOrcamento);
  }
}