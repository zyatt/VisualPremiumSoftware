import 'package:flutter/foundation.dart';
import '../repositories/fornecedor_repository.dart';

class FornecedorProvider extends ChangeNotifier {
  final FornecedorRepository _repo = FornecedorRepository();

  List<dynamic> _fornecedores = [];
  List<dynamic> get fornecedores => _fornecedores;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _fornecedores = await _repo.listar();
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

  Future<void> atualizar(int id, Map<String, dynamic> dados) async {
    await _repo.atualizar(id, dados);
    await carregar();
  }

  Future<void> excluir(int id) async {
    await _repo.excluir(id);
    await carregar();
  }

  Future<void> vincularMaterial(int fornecedorId, Map<String, dynamic> dados) async {
    await _repo.vincularMaterial(fornecedorId, dados);
    await carregar();
  }

  Future<void> desvincularMaterial(int fornecedorId, int materialId) async {
    await _repo.desvincularMaterial(fornecedorId, materialId);
    await carregar();
  }
}