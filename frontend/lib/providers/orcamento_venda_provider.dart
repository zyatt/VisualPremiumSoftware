import 'package:flutter/foundation.dart';
import '../models/orcamento_venda_model.dart';
import '../repositories/orcamento_venda_repository.dart';

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

class OrcamentoVendaProvider extends ChangeNotifier {
  final OrcamentoVendaRepository _repo = OrcamentoVendaRepository();

  List<OrcamentoVendaModel> _orcamentos = [];
  List<OrcamentoVendaModel> get orcamentos => _orcamentos;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  String _busca = '';
  String? _statusFiltro;

  Future<void> carregar({String busca = '', String? status}) async {
    _busca        = busca;
    _statusFiltro = status;
    _carregando   = true;
    _erro         = null;
    notifyListeners();
    try {
      _orcamentos = await _repo.listar(status: status, busca: busca);
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar orçamentos');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() =>
      carregar(busca: _busca, status: _statusFiltro);

  Future<OrcamentoVendaModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar orçamento');
      notifyListeners();
      return null;
    }
  }

  Future<OrcamentoVendaModel?> criar(Map<String, dynamic> dados) async {
    try {
      final ov = await _repo.criar(dados);
      await recarregar();
      return ov;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'criar orçamento');
      notifyListeners();
      return null;
    }
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizar(id, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar orçamento');
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
      _erro = _mensagemErro(e, acao: 'excluir orçamento');
      notifyListeners();
      return false;
    }
  }

  Future<bool> aprovar(int id) async {
    try {
      await _repo.aprovar(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'aprovar orçamento');
      notifyListeners();
      return false;
    }
  }

  Future<bool> reprovar(int id) async {
    try {
      await _repo.reprovar(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'reprovar orçamento');
      notifyListeners();
      return false;
    }
  }

  Future<bool> adicionarItem(
      int orcamentoId, Map<String, dynamic> dados) async {
    try {
      await _repo.adicionarItem(orcamentoId, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'adicionar item');
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizarItem(
      int orcamentoId, int itemId, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizarItem(orcamentoId, itemId, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar item');
      notifyListeners();
      return false;
    }
  }

  Future<bool> removerItem(int orcamentoId, int itemId) async {
    try {
      await _repo.removerItem(orcamentoId, itemId);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'remover item');
      notifyListeners();
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listarClientes({String? busca}) async {
    try {
      return await _repo.listarClientes(busca: busca);
    } catch (_) {
      return [];
    }
  }

  void limparErro() {
    _erro = null;
    notifyListeners();
  }
}