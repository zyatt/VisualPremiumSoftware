import 'package:flutter/foundation.dart';
import '../models/fornecedor_model.dart';
import '../repositories/fornecedor_repository.dart';

String _mensagemErro(Object e) {
  final raw = e.toString();
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class FornecedorProvider extends ChangeNotifier {
  final FornecedorRepository _repo = FornecedorRepository();

  List<FornecedorModel> _fornecedores = [];
  List<FornecedorModel> get fornecedores => _fornecedores;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  String _busca = '';
  String _tipo = '';
  String _id = '';

  /// Retorna os tipoFornecedor distintos (não nulos/vazios) dos fornecedores carregados.
  List<String> get tipos {
    final set = <String>{};
    for (final f in _fornecedores) {
      if (f.tipoFornecedor != null && f.tipoFornecedor!.isNotEmpty) set.add(f.tipoFornecedor!);
    }
    return set.toList()..sort();
  }

  Future<void> carregar({
    String busca = '',
    String tipo = '',
    String id = '',
  }) async {
    _busca = busca;
    _tipo = tipo;
    _id = id;

    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _fornecedores = await _repo.listar(
        busca: busca,
        tipo: tipo,
        id: id,
      );
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async => carregar(
        busca: _busca,
        tipo: _tipo,
        id: _id,
      );
  Future<FornecedorModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erro = _mensagemErro(e);
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
      _erro = _mensagemErro(e);
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
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> remover(int id) async {
    try {
      await _repo.remover(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> vincularMaterial(int fornecedorId, Map<String, dynamic> dados) async {
    try {
      await _repo.vincularMaterial(fornecedorId, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> desvincularMaterial(int fornecedorId, int materialId) async {
    try {
      await _repo.desvincularMaterial(fornecedorId, materialId);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizarPreco(int fornecedorId, int materialId, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizarPreco(fornecedorId, materialId, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Busca rápida para o overlay de vínculo — usa endpoint dedicado (/fornecedores/buscar)
  /// que não carrega materiais e limita a 50 resultados, evitando payload pesado.
  Future<List<FornecedorModel>> buscarFornecedores({String? busca}) async {
    try {
      return await _repo.buscarParaVinculo(busca: busca);
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return [];
    }
  }

  Future<List<FornecedorModel>> listarPorMaterial(int materialId) async {
    try {
      return await _repo.listarPorMaterial(materialId);
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> buscarMateriais({
    String? idPrefix,
    String? nomePrefix,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    try {
      return await _repo.buscarMateriais(
        idPrefix:      idPrefix,
        nomePrefix:    nomePrefix,
        identificador: identificador,
        medida:        medida,
        espessura:     espessura,
      );
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return [];
    }
  }
}