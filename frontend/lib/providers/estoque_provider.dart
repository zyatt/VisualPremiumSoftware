import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/estoque_model.dart';
import '../repositories/estoque_repository.dart';

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
  if (raw.contains('foreign key constraint') ||
      raw.contains('violates RESTRICT') ||
      raw.contains('P2003')) {
    return 'Não é possível excluir: Este item está vinculado a outros registros '
        '(movimentações, orçamentos ou ordens de compra). Desative-o em vez de excluí-lo.';
  }
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class EstoqueProvider extends ChangeNotifier {
  final EstoqueRepository _repo = EstoqueRepository();

  List<RelacaoOSModel> _relacoesOS = [];
  List<RelacaoOSModel> get relacoesOS => _relacoesOS;

  Set<String> get numerosOSFechadas => _relacoesOS
      .where((r) => r.estaFechada)
      .map((r) => r.numeroOS)
      .toSet();

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
  String? _erroLista;
  String? get erroLista => _erroLista;

  Future<void> carregarRelacoesOS({String? busca}) async {
    _carregando = true;
    _erroLista = null;
    notifyListeners();
    try {
      final resultado = await _repo.listarTodasRelacoesOS(
        busca: busca,
        pagina: 1,
        porPagina: 100000,
      );
      _relacoesOS = resultado.itens;
    } catch (e) {
      _erroLista = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  final Map<String, List<RelacaoOSModel>> _relacoesOSPaginaPorStatus = {};
  List<RelacaoOSModel> relacoesOSPaginaDoStatus(String status, {bool numericas = false, bool textuais = false}) {
    final sufixo = numericas ? '#num' : (textuais ? '#txt' : '');
    return _relacoesOSPaginaPorStatus['$status$sufixo'] ?? const [];
  }

  final Map<String, int> _totalRelacoesOSPaginaPorStatus = {};
  int totalRelacoesOSPaginaDoStatus(String status, {bool numericas = false, bool textuais = false}) {
    final sufixo = numericas ? '#num' : (textuais ? '#txt' : '');
    return _totalRelacoesOSPaginaPorStatus['$status$sufixo'] ?? 0;
  }

  bool _carregandoPagina = false;
  bool get carregandoPagina => _carregandoPagina;

  Future<void> carregarRelacoesOSPagina({
    String? busca,
    String? status,
    String? cliente,
    String? material,
    String? identificador,
    String? medida,
    String? comprimento,
    String? largura,
    String? espessura,
    DateTime? dataInicio,
    DateTime? dataFim,
    String? ordenarPor,
    String? direcao,
    bool apenasNumericas = false,
    bool apenasTextuais = false,
    required int pagina,
    int porPagina = 50,
  }) async {
    _carregandoPagina = true;
    _erroLista = null;
    notifyListeners();
    try {
      final resultado = await _repo.listarTodasRelacoesOS(
        busca:            busca,
        status:           status,
        cliente:          cliente,
        material:         material,
        identificador:    identificador,
        medida:           medida,
        comprimento:      comprimento,
        largura:          largura,
        espessura:        espessura,
        dataInicio:       dataInicio,
        dataFim:          dataFim,
        ordenarPor:       ordenarPor,
        direcao:          direcao,
        apenasNumericas:  apenasNumericas,
        apenasTextuais:   apenasTextuais,
        pagina:           pagina,
        porPagina:        porPagina,
      );
      final sufixo = apenasNumericas ? '#num' : (apenasTextuais ? '#txt' : '');
      final chave = '${status ?? '_'}$sufixo';
      _relacoesOSPaginaPorStatus[chave]      = resultado.itens;
      _totalRelacoesOSPaginaPorStatus[chave] = resultado.total;
    } catch (e) {
      _erroLista = _mensagemErro(e);
    } finally {
      _carregandoPagina = false;
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
    double? larguraUsada,
    double? comprimentoUsado,
    int? materialOrigemId,
    String? cliente,
  }) async {
    try {
      await _repo.registrarMovimentacao(
        materialId:       materialId,
        tipo:             tipo,
        quantidade:       quantidade,
        numeroOS:         numeroOS,
        precoUnitario:    precoUnitario,
        precoM2:          precoM2,
        observacao:       observacao,
        ordemCompraId:    ordemCompraId,
        larguraUsada:     larguraUsada,
        comprimentoUsado: comprimentoUsado,
        materialOrigemId: materialOrigemId,
        cliente:          cliente,
      );
      await carregarRelacoesOS();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> registrarMovimentacaoSilencioso({
    required int materialId,
    required String tipo,
    required double quantidade,
    required String numeroOS,
    double? precoUnitario,
    double? precoM2,
    String? observacao,
    int? ordemCompraId,
    double? larguraUsada,
    double? comprimentoUsado,
    int? materialOrigemId,
    String? cliente,
  }) async {
    try {
      await _repo.registrarMovimentacao(
        materialId:       materialId,
        tipo:             tipo,
        quantidade:       quantidade,
        numeroOS:         numeroOS,
        precoUnitario:    precoUnitario,
        precoM2:          precoM2,
        observacao:       observacao,
        ordemCompraId:    ordemCompraId,
        larguraUsada:     larguraUsada,
        comprimentoUsado: comprimentoUsado,
        materialOrigemId: materialOrigemId,
        cliente:          cliente,
      );
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

      RelacaoOSModel? novaSelecao;
      try {
        novaSelecao = await _repo.buscarRelacaoOS(numeroOS);
      } catch (_) {
        novaSelecao = null;
      }
      final resultado = await _repo.listarTodasRelacoesOS(pagina: 1, porPagina: 100000);

      _relacaoSelecionada = novaSelecao;
      _relacoesOS = resultado.itens;
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> excluirRelacaoOS(int relacaoOSId) async {
    try {
      await _repo.excluirRelacaoOS(relacaoOSId);
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

  Future<bool> renomearOS(
    int relacaoOSId,
    String novoNumeroOS, {
    String? novoCliente,
  }) async {
    try {
      final atualizada = await _repo.renomearOS(
        relacaoOSId,
        novoNumeroOS,
        novoCliente: novoCliente,
      );
      _relacaoSelecionada = atualizada;
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<String?> buscarClientePorNumeroOS(String numeroOS) {
    return _repo.buscarClientePorNumeroOS(numeroOS);
  }

  List<MovimentacaoComOSModel> _movimentacoesPagina = [];
  List<MovimentacaoComOSModel> get movimentacoesPagina => _movimentacoesPagina;

  int _totalMovimentacoesPagina = 0;
  int get totalMovimentacoesPagina => _totalMovimentacoesPagina;

  bool _carregandoMovimentacoes = false;
  bool get carregandoMovimentacoes => _carregandoMovimentacoes;

  Future<void> carregarMovimentacoesPagina({
    String? numeroOS,
    String? material,
    String? identificador,
    String? medida,
    String? comprimento,
    String? largura,
    String? espessura,
    String? tipo,
    DateTime? dataInicio,
    DateTime? dataFim,
    required int pagina,
    int porPagina = 100,
  }) async {
    _carregandoMovimentacoes = true;
    notifyListeners();
    try {
      final resultado = await _repo.listarMovimentacoes(
        numeroOS:      numeroOS,
        material:      material,
        identificador: identificador,
        medida:        medida,
        comprimento:   comprimento,
        largura:       largura,
        espessura:     espessura,
        tipo:          tipo,
        dataInicio:    dataInicio,
        dataFim:       dataFim,
        pagina:        pagina,
        porPagina:     porPagina,
      );
      _movimentacoesPagina      = resultado.itens;
      _totalMovimentacoesPagina = resultado.total;
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoMovimentacoes = false;
      notifyListeners();
    }
  }

  Future<bool> fecharOS(int relacaoOSId) async {
    _fechandoOS = true;
    notifyListeners();
    try {
      await _repo.fecharOS(relacaoOSId);
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

  Future<bool> fecharOSSilencioso(int relacaoOSId) async {
    try {
      await _repo.fecharOS(relacaoOSId);
      if (_relacaoSelecionada?.id == relacaoOSId) {
        _relacaoSelecionada = null;
      }
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      return false;
    }
  }

  Future<void> recarregarRelacoesOSSilencioso({String? busca}) async {
    try {
      final resultado = await _repo.listarTodasRelacoesOS(
        busca: busca,
        pagina: 1,
        porPagina: 100000,
      );
      _relacoesOS = resultado.itens;
      notifyListeners();
    } catch (e) {
      _erroLista = _mensagemErro(e);
      notifyListeners();
    }
  }

  Future<bool> reverterOS(String numeroOS) async {
    try {
      await _repo.reverterOS(numeroOS);
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

  Future<bool> atualizarPrecoMovimentacao(
    int movimentacaoId, {
    double? precoUnitario,
    double? precoM2,
  }) async {
    try {
      await _repo.atualizarPrecoMovimentacao(
        movimentacaoId,
        precoUnitario: precoUnitario,
        precoM2: precoM2,
      );
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}