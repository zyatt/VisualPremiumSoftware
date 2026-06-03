import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/material_model.dart';
import '../repositories/material_repository.dart';

/// Remove prefixos como "Exception:", "HttpException:" que o Dart
/// adiciona automaticamente ao fazer e.toString() em exceções.
String _mensagemErro(Object e) {
  final raw = e.toString();
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

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
  String? _categoriaFiltro;   // null = todos, '' = sem categoria
  String _statusFiltro = '';
  String _idFiltro = '';
  String _identificadorFiltro = '';
  String _medidaFiltro = '';
  String _espessuraFiltro = '';

  Future<void> carregar({
    String busca = '',
    String? categoria,         // null = todos, '' = sem categoria
    String status = '',
    String id = '',
    String identificador = '',
    String medida = '',
    String espessura = '',
    bool? ativo,
  }) async {
    _busca = busca;
    _categoriaFiltro = categoria;
    _statusFiltro = status;
    _idFiltro = id;
    _identificadorFiltro = identificador;
    _medidaFiltro = medida;
    _espessuraFiltro = espessura;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _materiais = await _repo.listar(
        busca:        busca,
        categoria:    categoria,
        status:       status,
        id:           id,
        identificador: identificador,
        medida:       medida,
        espessura:    espessura,
        ativo:        ativo,
      );
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    await carregar(
      busca:        _busca,
      categoria:    _categoriaFiltro,
      status:       _statusFiltro,
      id:           _idFiltro,
      identificador: _identificadorFiltro,
      medida:       _medidaFiltro,
      espessura:    _espessuraFiltro,
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

  Future<bool> desativar(int id) async {
    try {
      await _repo.desativar(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
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
      _erro = _mensagemErro(e);
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
      _erro = _mensagemErro(e);
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
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Busca rápida para autocomplete — retorna até [limite] materiais sem
  /// alterar o estado da lista principal nem disparar notifyListeners.
  Future<List<MaterialModel>> buscarSugestoes(String busca, {int limite = 10, bool apenasAtivos = false}) async {
    try {
      final lista = await _repo.listar(busca: busca, ativo: apenasAtivos ? true : null);
      return lista.take(limite).toList();
    } catch (_) {
      return [];
    }
  }

  /// Busca histórico de custos pagos via OC para o material informado.
  /// Retorna lista vazia em caso de erro (não expõe _erro para não interferir
  /// com o estado geral da página de estoque).
  Future<List<HistoricoPrecoModel>> listarHistoricoPrecos(int materialId) async {
    try {
      return await _repo.listarHistoricoPrecos(materialId);
    } catch (_) {
      return [];
    }
  }

  Future<bool> excluirFilhoEspecifico(int materialId, int filhoId) async {
    try {
      await _repo.excluirFilhoEspecifico(materialId, filhoId);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizarFilhoEspecifico(
    int materialId,
    int filhoId, {
    String? descricao,
    double? quantidade,
  }) async {
    try {
      await _repo.atualizarFilhoEspecifico(
        materialId, filhoId,
        descricao:  descricao,
        quantidade: quantidade,
      );
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}