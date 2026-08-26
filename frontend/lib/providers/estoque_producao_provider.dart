import 'package:flutter/foundation.dart';
import '../models/estoque_producao_model.dart';
import '../repositories/estoque_producao_repository.dart';

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

class EstoqueProducaoProvider with ChangeNotifier {
  final EstoqueProducaoRepository _repo = EstoqueProducaoRepository();

  String? _producao;
  String? get producao => _producao;

  void definirProducao(String producao) {
    _producao = producao;
    notifyListeners();
  }

  final Map<String, List<MaterialEstoqueProducaoModel>> _estoquePorLinha = {
    '1': [],
    '2': [],
  };
  final Map<String, bool> _carregandoPorLinha = {'1': false, '2': false};
  final Map<String, String?> _erroPorLinha = {'1': null, '2': null};

  List<MaterialEstoqueProducaoModel> get estoque =>
      _estoquePorLinha[_producao] ?? [];
  bool get carregandoEstoque => _carregandoPorLinha[_producao] ?? false;

  List<MaterialEstoqueProducaoModel> estoqueDaLinha(String producao) =>
      _estoquePorLinha[producao] ?? [];
  bool carregandoDaLinha(String producao) =>
      _carregandoPorLinha[producao] ?? false;
  String? erroDaLinha(String producao) => _erroPorLinha[producao];

  List<MovimentacaoProducaoModel> _historico = [];
  List<MovimentacaoProducaoModel> get historico => _historico;
  bool _carregandoHistorico = false;
  bool get carregandoHistorico => _carregandoHistorico;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregarEstoque({
    String? producao,
    String? busca,
    String? categoria,
    String? identificador,
    String? medida,
    String? espessura,
    String? comprimento,
    String? largura,
  }) async {
    final linha = producao ?? _producao;
    if (linha == null) return;
    _carregandoPorLinha[linha] = true;
    _erroPorLinha[linha] = null;
    if (linha == _producao) _erro = null;
    notifyListeners();
    try {
      final lista = await _repo.listarEstoque(
        producao: linha,
        busca: busca,
        categoria: categoria,
        identificador: identificador,
        medida: medida,
        espessura: espessura,
        comprimento: comprimento,
        largura: largura,
      );
      _estoquePorLinha[linha] = lista;
    } catch (e) {
      final msg = _mensagemErro(e);
      _erroPorLinha[linha] = msg;
      if (linha == _producao) _erro = msg;
    } finally {
      _carregandoPorLinha[linha] = false;
      notifyListeners();
    }
  }

  Future<void> carregarEstoqueAmbasLinhas() async {
    await Future.wait([
      carregarEstoque(producao: '1'),
      carregarEstoque(producao: '2'),
    ]);
  }

  List<MaterialEstoqueProducaoModel> get estoqueCombinado => [
        ..._estoquePorLinha['1'] ?? [],
        ..._estoquePorLinha['2'] ?? [],
      ];

  bool get carregandoEstoqueCombinado =>
      (_carregandoPorLinha['1'] ?? false) || (_carregandoPorLinha['2'] ?? false);

  String? get erroEstoqueCombinado => _erroPorLinha['1'] ?? _erroPorLinha['2'];

  Future<void> carregarHistorico({String? busca, String? numeroOS, String? producao}) async {
    _carregandoHistorico = true;
    _erro = null;
    notifyListeners();
    try {
      _historico = await _repo.listarHistorico(busca: busca, numeroOS: numeroOS, producao: producao);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoHistorico = false;
      notifyListeners();
    }
  }

  Future<bool> transferir({
    required int materialId,
    required double quantidade,
    required String producao,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    try {
      await _repo.transferir(
        materialId: materialId,
        quantidade: quantidade,
        producao: producao,
        observacao: observacao,
        larguraUsada: larguraUsada,
        comprimentoUsado: comprimentoUsado,
      );
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> devolver({
    required int materialId,
    required double quantidade,
    required String producao,
    String? observacao,
  }) async {
    _erro = null;
    try {
      await _repo.devolver(
        materialId: materialId,
        quantidade: quantidade,
        producao: producao,
        observacao: observacao,
      );
      await carregarEstoque(producao: producao);
      await carregarHistorico();
      await carregarContadorPendentes();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> transferirEntreLinhas({
    required int materialId,
    required double quantidade,
    required String producaoOrigem,
    required String producaoDestino,
    String? observacao,
  }) async {
    _erro = null;
    try {
      await _repo.transferirEntreLinhas(
        materialId: materialId,
        quantidade: quantidade,
        producaoOrigem: producaoOrigem,
        producaoDestino: producaoDestino,
        observacao: observacao,
      );
      await Future.wait([
        carregarEstoque(producao: producaoOrigem),
        carregarEstoque(producao: producaoDestino),
      ]);
      await carregarHistorico();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> darBaixa({
    required int materialId,
    double? quantidade,
    required String numeroOS,
    String? producao,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    final linha = producao ?? _producao;
    if (linha == null) {
      _erro = 'Linha de produção não definida';
      notifyListeners();
      return false;
    }
    try {
      await _repo.darBaixa(
        materialId: materialId,
        quantidade: quantidade,
        numeroOS: numeroOS,
        producao: linha,
        observacao: observacao,
        larguraUsada: larguraUsada,
        comprimentoUsado: comprimentoUsado,
      );
      await carregarEstoque(producao: linha);
      await carregarContadorPendentes();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> excluirHistorico(int movimentacaoId) async {
    _erro = null;
    try {
      await _repo.excluirHistorico(movimentacaoId);
      await carregarHistorico();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  List<EntradaPendenteModel> _pendentes = [];
  List<EntradaPendenteModel> get pendentes => _pendentes;
  bool _carregandoPendentes = false;
  bool get carregandoPendentes => _carregandoPendentes;

  int _totalPendentes = 0;
  int get totalPendentes => _totalPendentes;

  Future<void> carregarPendentes() async {
    _carregandoPendentes = true;
    _erro = null;
    notifyListeners();
    try {
      _pendentes = await _repo.listarPendentes();
      _totalPendentes = _pendentes.length;
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoPendentes = false;
      notifyListeners();
    }
  }

  Future<void> carregarContadorPendentes() async {
    try {
      _totalPendentes = await _repo.contarPendentes();
      notifyListeners();
    } catch (_) {

    }
  }

  Future<bool> confirmarPendente(int id) async {
    _erro = null;
    try {
      await _repo.confirmarPendente(id);
      await carregarPendentes();
      await carregarEstoqueAmbasLinhas();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> recusarPendente(int id) async {
    _erro = null;
    try {
      await _repo.recusarPendente(id);
      await carregarPendentes();
      await carregarEstoqueAmbasLinhas();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}