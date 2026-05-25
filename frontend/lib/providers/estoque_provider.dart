import 'package:flutter/foundation.dart';
import '../models/estoque_model.dart';
import '../repositories/estoque_repository.dart';

String _mensagemErro(Object e) {
  final raw = e.toString();
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class EstoqueProvider extends ChangeNotifier {
  final EstoqueRepository _repo = EstoqueRepository();

  List<RelacaoOSModel> _relacoesOS = [];
  List<RelacaoOSModel> get relacoesOS => _relacoesOS;

  RelacaoOSModel? _relacaoSelecionada;
  RelacaoOSModel? get relacaoSelecionada => _relacaoSelecionada;

  bool _carregando = false;
  bool get carregando => _carregando;

  bool _carregandoDetalhe = false;
  bool get carregandoDetalhe => _carregandoDetalhe;

  bool _fechandoOS = false;
  bool get fechandoOS => _fechandoOS;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregarRelacoesOS({String? busca}) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _relacoesOS = await _repo.listarRelacoesOS(busca: busca);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> selecionarRelacaoOS(String numeroOS) async {
    _carregandoDetalhe = true;
    notifyListeners();
    try {
      _relacaoSelecionada = await _repo.buscarRelacaoOS(numeroOS);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoDetalhe = false;
      notifyListeners();
    }
  }

  void limparSelecao() {
    _relacaoSelecionada = null;
    notifyListeners();
  }

  Future<bool> registrarMovimentacao({
    required int materialId,
    required String tipo,
    required double quantidade,
    required String numeroOS,
    double? precoUnitario,
    double? precoM2,
    String? observacao,
    int? ordemCompraId,
  }) async {
    try {
      await _repo.registrarMovimentacao(
        materialId:    materialId,
        tipo:          tipo,
        quantidade:    quantidade,
        numeroOS:      numeroOS,
        precoUnitario: precoUnitario,
        precoM2:       precoM2,
        observacao:    observacao,
        ordemCompraId: ordemCompraId,
      );
      await carregarRelacoesOS();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> removerMovimentacao({
    required int movimentacaoId,
    required String numeroOS,
  }) async {
    try {
      await _repo.removerMovimentacao(movimentacaoId);
      try {
        _relacaoSelecionada = await _repo.buscarRelacaoOS(numeroOS);
      } catch (_) {
        _relacaoSelecionada = null;
      }
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> excluirRelacaoOS(String numeroOS) async {
    try {
      await _repo.excluirRelacaoOS(numeroOS);
      _relacaoSelecionada = null;
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Fecha a OS: muda status para FECHADA no backend e remove da lista
  /// de controle de estoque. A OS passa a aparecer só na página de relatórios.
  Future<bool> fecharOS(String numeroOS) async {
    _fechandoOS = true;
    notifyListeners();
    try {
      await _repo.fecharOS(numeroOS);
      _relacaoSelecionada = null;
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    } finally {
      _fechandoOS = false;
      notifyListeners();
    }
  }
}