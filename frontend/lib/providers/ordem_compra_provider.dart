import 'package:flutter/foundation.dart';
import '../repositories/ordem_compra_repository.dart';

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
      _finalizadas = todas.where((o) => o['status'] == 'FINALIZADA').toList();
      _canceladas  = todas.where((o) => o['status'] == 'CANCELADA').toList();
    } catch (e) {
      _erro = e.toString();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> criar(Map<String, dynamic> dados) async {
    await _repo.criar(dados);
    await carregar();
  }

  Future<void> finalizar(int id) async {
    await _repo.atualizarStatus(id, 'FINALIZADA');
    await carregar();
  }

  Future<void> cancelar(int id) async {
    await _repo.atualizarStatus(id, 'CANCELADA');
    await carregar();
  }

  Future<void> atualizar(int id, Map<String, dynamic> dados) async {
    await _repo.atualizar(id, dados);
    await carregar();
  }
}