import 'package:flutter/foundation.dart';
import '../repositories/ordem_compra_repository.dart';

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
      _historico = todas.where((o) => o['status'] == 'FINALIZADA').toList();
    } catch (e) {
      _erro = e.toString();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }
}