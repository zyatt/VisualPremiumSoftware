import 'package:flutter/foundation.dart';
import '../models/estoque_model.dart';
import '../repositories/estoque_repository.dart';

String _mensagemErro(Object e) {
  final raw = e.toString();
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class RelatorioOSProvider extends ChangeNotifier {
  final EstoqueRepository _repo = EstoqueRepository();

  List<RelacaoOSModel> _relatorios = [];
  List<RelacaoOSModel> get relatorios => _relatorios;

  RelacaoOSModel? _selecionado;
  RelacaoOSModel? get selecionado => _selecionado;

  bool _carregando = false;
  bool get carregando => _carregando;

  bool _carregandoDetalhe = false;
  bool get carregandoDetalhe => _carregandoDetalhe;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregar({String? busca}) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _relatorios = await _repo.listarRelatoriosOS(busca: busca);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> selecionar(String numeroOS) async {
    _carregandoDetalhe = true;
    notifyListeners();
    try {
      _selecionado = await _repo.buscarRelacaoOS(numeroOS);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoDetalhe = false;
      notifyListeners();
    }
  }

  void limparSelecao() {
    _selecionado = null;
    notifyListeners();
  }

  Future<bool> reverterOS(String numeroOS) async {
    try {
      await _repo.reverterOS(numeroOS);
      _selecionado = null;
      await carregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}