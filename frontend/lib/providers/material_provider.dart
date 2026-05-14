import 'package:flutter/foundation.dart';
import '../models/material_model.dart';
import '../repositories/material_repository.dart';

class MaterialProvider extends ChangeNotifier {
  final MaterialRepository _repo = MaterialRepository();

  List<MaterialModel> _materiais = [];
  List<MaterialModel> get materiais => _materiais;

  List<String> _categorias = [];
  List<String> get categorias => _categorias;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  // Filtros ativos
  String _busca = '';
  String _categoriaFiltro = '';
  String _statusFiltro = '';

  Future<void> carregar({
    String busca = '',
    String categoria = '',
    String status = '',
  }) async {
    _busca = busca;
    _categoriaFiltro = categoria;
    _statusFiltro = status;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _materiais = await _repo.listar(
        busca: busca,
        categoria: categoria,
        status: status,
      );
    } catch (e) {
      _erro = e.toString();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    await carregar(
      busca: _busca,
      categoria: _categoriaFiltro,
      status: _statusFiltro,
    );
  }

  Future<void> carregarCategorias() async {
    try {
      _categorias = await _repo.listarCategorias();
      notifyListeners();
    } catch (_) {}
  }

  Future<MaterialModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erro = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> criar(Map<String, dynamic> dados) async {
    try {
      await _repo.criar(dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizar(id, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> desativar(int id) async {
    try {
      await _repo.desativar(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmarEstoque(int id) async {
    try {
      await _repo.confirmarEstoque(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> excluir(int id) async {
    try {
      await _repo.excluir(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> reativar(int id) async {
    try {
      await _repo.reativar(id);
      await carregar();
      return true;
    } catch (e) {
      _erro = e.toString();
      notifyListeners();
      return false;
    }
  }
}