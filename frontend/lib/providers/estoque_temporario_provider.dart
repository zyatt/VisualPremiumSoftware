// estoque_temporario_provider.dart
import 'package:flutter/foundation.dart';
import '../models/estoque_temporario_model.dart';
import '../repositories/estoque_temporario_repository.dart';

String _msgErro(Object e) {
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

class EstoqueTemporarioProvider extends ChangeNotifier {
  final _repo = EstoqueTemporarioRepository();

  List<EstoqueTemporarioModel> _itens = [];
  List<EstoqueTemporarioModel> get itens => _itens;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregar({String? busca}) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _itens = await _repo.listar(busca: busca);
    } catch (e) {
      _erro = _msgErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<bool> criar(Map<String, dynamic> dados) async {
    try {
      final novo = await _repo.criar(dados);
      _itens.insert(0, novo);
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _msgErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      final atualizado = await _repo.atualizar(id, dados);
      final idx = _itens.indexWhere((i) => i.id == id);
      if (idx != -1) _itens[idx] = atualizado;
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _msgErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Desativa o item (soft-delete) mas mantém na lista local, marcado
  /// como inativo, para permitir reativação posterior.
  Future<bool> remover(int id) async {
    try {
      await _repo.remover(id);
      final idx = _itens.indexWhere((i) => i.id == id);
      if (idx != -1) _itens[idx] = _itens[idx].copyWith(ativo: false);
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _msgErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Reativa um item previamente desativado, renovando seu prazo.
  Future<bool> reativar(int id) async {
    try {
      final atualizado = await _repo.reativar(id);
      final idx = _itens.indexWhere((i) => i.id == id);
      if (idx != -1) _itens[idx] = atualizado;
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _msgErro(e);
      notifyListeners();
      return false;
    }
  }

  void limparErro() {
    _erro = null;
    notifyListeners();
  }
}