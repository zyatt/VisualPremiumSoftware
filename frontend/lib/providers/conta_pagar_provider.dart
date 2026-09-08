import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/api_client.dart'; // ajuste o caminho se api_client.dart estiver em outra pasta no seu projeto

String _mensagemErro(Object e) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Verifique a conexão com o servidor';
  }
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

/// Modelo simples de Conta a Pagar (mesmo estilo direto usado nos demais
/// providers do projeto, sem freezed/json_serializable).
class ContaPagarModel {
  final int id;
  final String descricao;
  final String? numeroDocumento;
  final double valor;
  final DateTime? dataEmissao;
  final DateTime dataVencimento;
  final DateTime? dataPagamento;
  final String status; // PENDENTE | PAGO | VENCIDO | CANCELADO
  final String? statusExibicao;
  final String? formaPagamento;
  final String? categoria;
  final String? observacao;
  final int? empresaId;
  final String? empresaNome;
  final String? emitenteNome;
  final String? emitenteCnpj;
  final int? notaFiscalId;
  final String? notaFiscalNumero;

  ContaPagarModel({
    required this.id,
    required this.descricao,
    this.numeroDocumento,
    required this.valor,
    this.dataEmissao,
    required this.dataVencimento,
    this.dataPagamento,
    required this.status,
    this.statusExibicao,
    this.formaPagamento,
    this.categoria,
    this.observacao,
    this.empresaId,
    this.empresaNome,
    this.emitenteNome,
    this.emitenteCnpj,
    this.notaFiscalId,
    this.notaFiscalNumero,
  });

  String get statusEfetivo => statusExibicao ?? status;

  factory ContaPagarModel.fromJson(Map<String, dynamic> j) {
    return ContaPagarModel(
      id: j['id'] as int,
      descricao: j['descricao'] as String? ?? '',
      numeroDocumento: j['numeroDocumento'] as String?,
      valor: double.tryParse('${j['valor']}') ?? 0,
      dataEmissao: j['dataEmissao'] != null ? DateTime.tryParse(j['dataEmissao']) : null,
      dataVencimento: DateTime.parse(j['dataVencimento']),
      dataPagamento: j['dataPagamento'] != null ? DateTime.tryParse(j['dataPagamento']) : null,
      status: j['status'] as String? ?? 'PENDENTE',
      statusExibicao: j['statusExibicao'] as String?,
      formaPagamento: j['formaPagamento'] as String?,
      categoria: j['categoria'] as String?,
      observacao: j['observacao'] as String?,
      empresaId: j['empresaId'] as int?,
      empresaNome: j['empresa']?['nome'] as String?,
      emitenteNome: j['emitenteNome'] as String?,
      emitenteCnpj: j['emitenteCnpj'] as String?,
      notaFiscalId: j['notaFiscalId'] as int?,
      notaFiscalNumero: j['notaFiscal']?['numero'] as String?,
    );
  }
}

class NotaFiscalImportada {
  final int id;
  final String chaveAcesso;
  final String? numero;
  final String? serie;
  final DateTime? dataEmissao;
  final double? valorTotal;
  final String? emitenteCnpj;
  final String? emitenteNome;
  final DateTime? vencimentoSugerido;

  NotaFiscalImportada({
    required this.id,
    required this.chaveAcesso,
    this.numero,
    this.serie,
    this.dataEmissao,
    this.valorTotal,
    this.emitenteCnpj,
    this.emitenteNome,
    this.vencimentoSugerido,
  });

  factory NotaFiscalImportada.fromJson(Map<String, dynamic> j) {
    final nf = j['notaFiscal'] as Map<String, dynamic>;
    return NotaFiscalImportada(
      id: nf['id'] as int,
      chaveAcesso: nf['chaveAcesso'] as String,
      numero: nf['numero'] as String?,
      serie: nf['serie'] as String?,
      dataEmissao: nf['dataEmissao'] != null ? DateTime.tryParse(nf['dataEmissao']) : null,
      valorTotal: nf['valorTotal'] != null ? double.tryParse('${nf['valorTotal']}') : null,
      emitenteCnpj: nf['emitenteCnpj'] as String?,
      emitenteNome: nf['emitenteNome'] as String?,
      vencimentoSugerido: j['vencimentoSugerido'] != null
          ? DateTime.tryParse(j['vencimentoSugerido'])
          : null,
    );
  }
}

class ContaPagarProvider extends ChangeNotifier {
  List<ContaPagarModel> _contas = [];
  bool _carregando = false;
  String? _erro;

  List<ContaPagarModel> get contas => _contas;
  bool get carregando => _carregando;
  String? get erro => _erro;

  Future<void> carregar({String? status}) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final path = status != null
          ? '/contas-pagar?status=${Uri.encodeQueryComponent(status)}'
          : '/contas-pagar';
      final lista = await ApiClient.getList(path);
      _contas = lista
          .map((e) => ContaPagarModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Sobe o XML e retorna os dados extraídos para revisão do usuário
  /// (ainda NÃO cria a conta — isso é feito em [confirmarContaDeNota]).
  /// Usa multipart manualmente pois ApiClient não tem um método de upload
  /// de arquivo pronto (mesmo padrão de headers/baseUrl/token do ApiClient).
  Future<NotaFiscalImportada> importarXml(List<int> bytes, String nomeArquivo) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/api/contas-pagar/importar-xml');
    final request = http.MultipartRequest('POST', uri);
    if (ApiClient.token != null) {
      request.headers['Authorization'] = 'Bearer ${ApiClient.token}';
    }
    request.files.add(http.MultipartFile.fromBytes('arquivo', bytes, filename: nomeArquivo));

    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'Falha ao importar o XML da nota fiscal.';
      try {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        msg = body['error'] as String? ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }

    return NotaFiscalImportada.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> confirmarContaDeNota({
    required int notaFiscalId,
    required DateTime dataVencimento,
    double? valor,
    int? empresaId,
    String? formaPagamento,
    String? categoria,
    String? observacao,
    String? descricao,
  }) async {
    try {
      await ApiClient.post('/contas-pagar/confirmar-nota/$notaFiscalId', {
        'dataVencimento': dataVencimento.toIso8601String(),
        if (valor != null) 'valor': valor,
        if (empresaId != null) 'empresaId': empresaId,
        if (formaPagamento != null) 'formaPagamento': formaPagamento,
        if (categoria != null) 'categoria': categoria,
        if (observacao != null) 'observacao': observacao,
        if (descricao != null) 'descricao': descricao,
      });
      await carregar();
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> criarManual({
    required String descricao,
    required double valor,
    required DateTime dataVencimento,
    String? numeroDocumento,
    DateTime? dataEmissao,
    int? empresaId,
    String? formaPagamento,
    String? categoria,
    String? observacao,
  }) async {
    try {
      await ApiClient.post('/contas-pagar', {
        'descricao': descricao,
        'valor': valor,
        'dataVencimento': dataVencimento.toIso8601String(),
        if (numeroDocumento != null) 'numeroDocumento': numeroDocumento,
        if (dataEmissao != null) 'dataEmissao': dataEmissao.toIso8601String(),
        if (empresaId != null) 'empresaId': empresaId,
        if (formaPagamento != null) 'formaPagamento': formaPagamento,
        if (categoria != null) 'categoria': categoria,
        if (observacao != null) 'observacao': observacao,
      });
      await carregar();
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> marcarComoPaga(int id, {DateTime? dataPagamento, String? formaPagamento}) async {
    try {
      await ApiClient.post('/contas-pagar/$id/pagar', {
        if (dataPagamento != null) 'dataPagamento': dataPagamento.toIso8601String(),
        if (formaPagamento != null) 'formaPagamento': formaPagamento,
      });
      await carregar();
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      rethrow;
    }
  }

  /// Altera o status para qualquer valor: PENDENTE, VENCIDO, PAGO ou CANCELADO.
  Future<void> alterarStatus(int id, String status) async {
    try {
      await ApiClient.post('/contas-pagar/$id/status', {'status': status});
      await carregar();
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelar(int id) async {
    try {
      await ApiClient.post('/contas-pagar/$id/cancelar', const {});
      await carregar();
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> excluir(int id) async {
    try {
      await ApiClient.delete('/contas-pagar/$id');
      await carregar();
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      rethrow;
    }
  }
}