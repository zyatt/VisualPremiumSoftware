import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/fornecedor_model.dart';
import '../repositories/fornecedor_repository.dart';

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

class FornecedorProvider extends ChangeNotifier {
  final FornecedorRepository _repo = FornecedorRepository();

  List<FornecedorModel> _fornecedores = [];
  List<FornecedorModel> get fornecedores => _fornecedores;

  bool _carregando = false;
  bool get carregando => _carregando;

  List<FornecedorModel> _fornecedoresPagina = [];
  List<FornecedorModel> get fornecedoresPagina => _fornecedoresPagina;

  int _totalItensPagina = 0;
  int get totalItensPagina => _totalItensPagina;

  bool _carregandoPagina = false;
  bool get carregandoPagina => _carregandoPagina;

  String? _erro;
  String? get erro => _erro;

  // Erro específico de ações (criar/atualizar/remover/vincular etc).
  // Separado de `_erro` para não derrubar a listagem da página quando
  // uma ação feita dentro de um diálogo falha — nesse caso o erro deve
  // aparecer só no diálogo, não substituir a tela de fornecedores.
  String? _erroAcao;
  String? get erroAcao => _erroAcao;

  String _busca = '';
  String _tipo = '';
  String _id = '';

  List<String> _tipos = [];
  List<String> get tipos => _tipos;

  Future<void> carregarTipos() async {
    try {
      _tipos = await _repo.listarTipos();
      notifyListeners();
    } catch (_) {
    }
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

  Future<void> carregarPaginado({
    String busca = '',
    String tipo = '',
    String id = '',
    required int pagina,
    int porPagina = 40,
  }) async {
    _busca = busca;
    _tipo = tipo;
    _id = id;

    _carregandoPagina = true;
    _erro = null;
    notifyListeners();

    try {
      final resultado = await _repo.listarPaginado(
        busca: busca,
        tipo: tipo,
        id: id,
        pagina: pagina,
        porPagina: porPagina,
      );
      _fornecedoresPagina = resultado.itens;
      _totalItensPagina    = resultado.total;
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoPagina = false;
      notifyListeners();
    }
  }

  Future<FornecedorModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> criar(Map<String, dynamic> dados, {File? imagem}) async {
    _erroAcao = null;
    try {
      await _repo.criar(dados, imagem: imagem);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return false;
    }
    await recarregar();
    return true;
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados, {File? imagem}) async {
    _erroAcao = null;
    try {
      await _repo.atualizar(id, dados, imagem: imagem);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return false;
    }
    await recarregar();
    return true;
  }

  Future<bool> remover(int id) async {
    _erroAcao = null;
    try {
      await _repo.remover(id);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return false;
    }
    await recarregar();
    return true;
  }

  Future<bool> vincularMaterial(int fornecedorId, Map<String, dynamic> dados) async {
    _erroAcao = null;
    try {
      await _repo.vincularMaterial(fornecedorId, dados);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return false;
    }
    await recarregar();
    return true;
  }

  Future<bool> desvincularMaterial(int fornecedorId, int materialId) async {
    _erroAcao = null;
    try {
      await _repo.desvincularMaterial(fornecedorId, materialId);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return false;
    }
    await recarregar();
    return true;
  }

  Future<bool> atualizarPreco(int fornecedorId, int materialId, Map<String, dynamic> dados) async {
    _erroAcao = null;
    try {
      await _repo.atualizarPreco(fornecedorId, materialId, dados);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return false;
    }
    await recarregar();
    return true;
  }

  Future<List<FornecedorSemelhanteModel>> verificarSemelhantes({
    required String nomeFantasia,
    int? ignorarId,
  }) async {
    try {
      return await _repo.verificarSemelhantes(
        nomeFantasia: nomeFantasia,
        ignorarId: ignorarId,
      );
    } catch (_) {
      // Falha nessa checagem é apenas um aviso auxiliar — não deve
      // atrapalhar o preenchimento do formulário.
      return [];
    }
  }

  Future<List<FornecedorModel>> buscarFornecedores({String? busca}) async {
    try {
      return await _repo.buscarParaVinculo(busca: busca);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return [];
    }
  }

  Future<List<FornecedorModel>> listarPorMaterial(int materialId) async {
    try {
      return await _repo.listarPorMaterial(materialId);
    } catch (e) {
      _erroAcao = _mensagemErro(e);
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
      _erroAcao = _mensagemErro(e);
      notifyListeners();
      return [];
    }
  }
}