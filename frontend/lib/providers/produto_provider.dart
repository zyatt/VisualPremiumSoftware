import 'package:flutter/foundation.dart';
import '../models/produto_model.dart';
import '../repositories/produto_repository.dart';

String _mensagemErro(Object e, {required String acao}) {
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

class ProdutoProvider extends ChangeNotifier {
  final ProdutoRepository _repo = ProdutoRepository();

  List<ProdutoModel> _produtos = [];
  List<ProdutoModel> get produtos => _produtos;

  List<String> _categorias = [];
  List<String> get categorias => _categorias;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  String _busca = '';
  String? _categoriaFiltro;
  bool? _ativoFiltro;

  Future<void> carregar({
    String busca = '',
    String? categoria,
    bool? ativo,
  }) async {
    _busca = busca;
    _categoriaFiltro = categoria;
    _ativoFiltro = ativo;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _produtos = await _repo.listar(
        busca:     busca,
        categoria: categoria,
        ativo:     ativo,
      );
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar produtos');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    await carregar(
      busca:     _busca,
      categoria: _categoriaFiltro,
      ativo:     _ativoFiltro,
    );
  }

  Future<void> carregarCategorias() async {
    try {
      _categorias = await _repo.listarCategorias();
      notifyListeners();
    } catch (_) {}
  }

  Future<ProdutoModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar produto');
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
      _erro = _mensagemErro(e, acao: 'cadastrar produto');
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
      _erro = _mensagemErro(e, acao: 'atualizar produto');
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
      _erro = _mensagemErro(e, acao: 'desativar produto');
      notifyListeners();
      return false;
    }
  }

  Future<bool> reativar(int id) async {
    try {
      await _repo.reativar(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'reativar produto');
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
      _erro = _mensagemErro(e, acao: 'excluir produto');
      notifyListeners();
      return false;
    }
  }

  Future<bool> adicionarMaterial(
      int produtoId, Map<String, dynamic> dados) async {
    try {
      await _repo.adicionarMaterial(produtoId, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'adicionar material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizarMaterial(
      int produtoId, int materialItemId, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizarMaterial(produtoId, materialItemId, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> removerMaterial(int produtoId, int materialItemId) async {
    try {
      await _repo.removerMaterial(produtoId, materialItemId);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'remover material');
      notifyListeners();
      return false;
    }
  }

  void limparErro() {
    _erro = null;
    notifyListeners();
  }
}