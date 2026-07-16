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

/// Gerencia o estoque de produção: saldo disponível (alimentado por
/// transferências vindas do Controle de Estoque) e histórico de
/// movimentações (transferências recebidas + baixas por OS).
class EstoqueProducaoProvider with ChangeNotifier {
  final EstoqueProducaoRepository _repo = EstoqueProducaoRepository();

  List<MaterialEstoqueProducaoModel> _estoque = [];
  List<MaterialEstoqueProducaoModel> get estoque => _estoque;
  bool _carregandoEstoque = false;
  bool get carregandoEstoque => _carregandoEstoque;

  List<MovimentacaoProducaoModel> _historico = [];
  List<MovimentacaoProducaoModel> get historico => _historico;
  bool _carregandoHistorico = false;
  bool get carregandoHistorico => _carregandoHistorico;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregarEstoque({
    String? busca,
    String? categoria,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    _carregandoEstoque = true;
    _erro = null;
    notifyListeners();
    try {
      _estoque = await _repo.listarEstoque(
        busca: busca,
        categoria: categoria,
        identificador: identificador,
        medida: medida,
        espessura: espessura,
      );
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoEstoque = false;
      notifyListeners();
    }
  }

  Future<void> carregarHistorico({String? busca, String? numeroOS}) async {
    _carregandoHistorico = true;
    _erro = null;
    notifyListeners();
    try {
      _historico = await _repo.listarHistorico(busca: busca, numeroOS: numeroOS);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoHistorico = false;
      notifyListeners();
    }
  }

  /// Transfere material do estoque normal para o estoque de produção.
  /// Usado pelo diálogo "Saída p/ Produção" na página de Controle de Estoque.
  Future<bool> transferir({
    required int materialId,
    required double quantidade,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    try {
      await _repo.transferir(
        materialId: materialId,
        quantidade: quantidade,
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

  /// Dá baixa no estoque de produção para uma OS. Usado na página de Produção.
  Future<bool> darBaixa({
    required int materialId,
    required double quantidade,
    required String numeroOS,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    try {
      await _repo.darBaixa(
        materialId: materialId,
        quantidade: quantidade,
        numeroOS: numeroOS,
        observacao: observacao,
        larguraUsada: larguraUsada,
        comprimentoUsado: comprimentoUsado,
      );
      await carregarEstoque();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}