import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../repositories/ordem_compra_repository.dart';

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

class HistoricoProvider extends ChangeNotifier {
  final OrdemCompraRepository _repo = OrdemCompraRepository();

  List<dynamic> _historico = [];
  List<dynamic> get historico => _historico;

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
      // Histórico = apenas ordens finalizadas
      _historico = todas.where((o) => o['status'] == 'FINALIZADO').toList();
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }
}