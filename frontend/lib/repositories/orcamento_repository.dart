import 'dart:typed_data';
import '../utils/api_client.dart';

class OrcamentoRepository {
  Future<List<dynamic>> listar({String? status}) async {
    final path = status != null ? '/orcamentos?status=$status' : '/orcamentos';
    return ApiClient.getList(path);
  }

  Future<List<dynamic>> listarHistorico() async {
    final abertos = await ApiClient.getList('/orcamentos?status=ABERTO');
    final aguardando = await ApiClient.getList('/orcamentos?status=AGUARDANDO_APROVACAO');
    final aprovados = await ApiClient.getList('/orcamentos?status=APROVADO');
    final naoAprovados = await ApiClient.getList('/orcamentos?status=NAO_APROVADO');
    final cancelados = await ApiClient.getList('/orcamentos?status=CANCELADO');
    final convertidos = await ApiClient.getList('/orcamentos?status=CONVERTIDO');
    final todos = [...abertos, ...aguardando, ...aprovados, ...naoAprovados, ...cancelados, ...convertidos];
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

  Future<List<dynamic>> listarAbertos() async {
    return ApiClient.getList('/orcamentos/abertos');
  }

  Future<Map<String, dynamic>> travar(int id) async {
    return ApiClient.post('/orcamentos/$id/travar', {});
  }

  Future<void> heartbeatTrava(int id) async {
    await ApiClient.post('/orcamentos/$id/travar/heartbeat', {});
  }

  Future<void> destravar(int id) async {
    await ApiClient.post('/orcamentos/$id/destravar', {});
  }

  Future<Map<String, dynamic>> criar(String titulo) async {
    return ApiClient.post('/orcamentos', {'titulo': titulo});
  }

  Future<Map<String, dynamic>> adicionarItem(
      int orcamentoId, Map<String, dynamic> item) async {
    return ApiClient.post('/orcamentos/$orcamentoId/itens', item);
  }

  Future<void> removerItem(int orcamentoId, int itemId) async {
    await ApiClient.delete('/orcamentos/$orcamentoId/itens/$itemId');
  }

  Future<void> limparItens(int orcamentoId) async {
    await ApiClient.delete('/orcamentos/$orcamentoId/itens');
  }

  Future<List<dynamic>> substituirItens(
      int orcamentoId, List<Map<String, dynamic>> itens) async {
    return ApiClient.putList('/orcamentos/$orcamentoId/itens', {'itens': itens});
  }

  Future<Map<String, dynamic>> atualizarItem(
      int orcamentoId, int itemId, Map<String, dynamic> dados) async {
    return ApiClient.patch('/orcamentos/$orcamentoId/itens/$itemId', dados);
  }

  Future<Map<String, dynamic>> cancelar(int id) async {
    return ApiClient.patch('/orcamentos/$id/cancelar');
  }

  Future<void> excluir(int id) async {
    await ApiClient.delete('/orcamentos/$id');
  }

  Future<Map<String, dynamic>> enviarParaAprovacao(int id) async {
    return ApiClient.patch('/orcamentos/$id/enviar-aprovacao', {});
  }

  Future<Map<String, dynamic>> aprovar(int id) async {
    return ApiClient.patch('/orcamentos/$id/aprovar', {});
  }

  Future<Map<String, dynamic>> rejeitar(int id, String motivo) async {
    return ApiClient.patch('/orcamentos/$id/rejeitar', {'motivo': motivo});
  }

  Future<Map<String, dynamic>> reabrir(int id) async {
    return ApiClient.patch('/orcamentos/$id/reabrir', {});
  }

  Future<Map<String, dynamic>> gerarOrdemCompra(int id, {String modoPreco = 'UNIDADE'}) async {
    return ApiClient.post('/orcamentos/$id/gerar-oc', {'modoPreco': modoPreco});
  }

  Future<Uint8List> gerarPdf(Map<String, dynamic> dadosOrcamento) async {
    return ApiClient.postBytes('/orcamentos/pdf', dadosOrcamento);
  }

  Future<Map<String, dynamic>> definirFornecedorOculto(
      int orcamentoId, int fornecedorId, bool oculto) async {
    return ApiClient.patch('/orcamentos/$orcamentoId/fornecedores-ocultos', {
      'fornecedorId': fornecedorId,
      'oculto': oculto,
    });
  }

  Future<Map<String, dynamic>> atualizarOrcamento(
      int id, Map<String, dynamic> dados) async {
    return ApiClient.patch('/orcamentos/$id', dados);
  }

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