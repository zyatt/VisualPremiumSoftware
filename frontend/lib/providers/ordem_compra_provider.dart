import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../repositories/ordem_compra_repository.dart';

/// Remove prefixos como "Exception:", "HttpException:" que o Dart adiciona
/// automaticamente ao fazer e.toString() em exceções. Quando o erro é de
/// conexão (sem internet / servidor fora do ar), retorna uma mensagem
/// amigável contextualizada com a ação que estava sendo feita.
String mensagemErro(Object e, {required String acao}) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Erro ao $acao: Verifique a conexão com o servidor.';
  }
  final msg = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
  return 'Erro ao $acao: $msg';
}

class OrdemCompraProvider extends ChangeNotifier {
  final OrdemCompraRepository _repo = OrdemCompraRepository();

  List<dynamic> _emAndamento = [];
  List<dynamic> _finalizadas = [];
  List<dynamic> _canceladas  = [];

  List<dynamic> get emAndamento => _emAndamento;
  List<dynamic> get finalizadas => _finalizadas;
  List<dynamic> get canceladas  => _canceladas;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final todas = await _repo.listar();
      _emAndamento = todas.where((o) => o['status'] == 'EM_ANDAMENTO').toList();
      _finalizadas = todas.where((o) => o['status'] == 'FINALIZADO').toList();
      _canceladas  = todas.where((o) => o['status'] == 'CANCELADO').toList();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'carregar ordens de compra');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> criar(Map<String, dynamic> dados) async {
    try {
      await _repo.criar(dados);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'criar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> finalizar(int id) async {
    try {
      await _repo.atualizarStatus(id, 'FINALIZADO');
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'finalizar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelar(int id) async {
    try {
      await _repo.atualizarStatus(id, 'CANCELADO');
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'cancelar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reverter(int id) async {
    try {
      await _repo.reverter(id);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'reverter ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizar(id, dados);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'atualizar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> excluir(int id) async {
    try {
      await _repo.excluir(id);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'excluir ordem de compra');
      notifyListeners();
      rethrow;
    }
  }
}