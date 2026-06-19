import 'package:flutter/foundation.dart';
import '../models/producao_model.dart';
import '../repositories/producao_repository.dart';

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

class ProducaoProvider with ChangeNotifier {
  final ProducaoRepository _repo = ProducaoRepository();

  List<String> _categorias = [];
  List<String> get categorias => _categorias;
  bool _carregandoCategorias = false;
  bool get carregandoCategorias => _carregandoCategorias;
  /// true somente após ao menos um carregamento bem-sucedido
  bool _categoriasCarregadas = false;
  bool get categoriasCarregadas => _categoriasCarregadas;
  String? _erroCategorias;
  String? get erroCategorias => _erroCategorias;

  List<MaterialProducaoModel> _materiais = [];
  List<MaterialProducaoModel> get materiais => _materiais;
  bool _carregandoMateriais = false;
  bool get carregandoMateriais => _carregandoMateriais;

  List<SolicitacaoProducaoModel> _historico = [];
  List<SolicitacaoProducaoModel> get historico => _historico;
  bool _carregandoHistorico = false;
  bool get carregandoHistorico => _carregandoHistorico;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregarCategorias() async {
    _carregandoCategorias = true;
    _erroCategorias = null;
    notifyListeners();
    try {
      _categorias = await _repo.listarCategorias();
      _categoriasCarregadas = true;
    } catch (e) {
      _erroCategorias = _mensagemErro(e);
      debugPrint('Erro ao carregar categorias: $e');
    } finally {
      _carregandoCategorias = false;
      notifyListeners();
    }
  }

  Future<void> carregarMateriais({
    String? busca,
    String? categoria,
    String? status,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    _carregandoMateriais = true;
    _erro = null;
    notifyListeners();

    try {
      _materiais = await _repo.listarMateriais(
        busca:         busca,
        categoria:     categoria,
        status:        status,
        id:            id,
        identificador: identificador,
        medida:        medida,
        espessura:     espessura,
      );
    } catch (e) {
      _erro = _mensagemErro(e);

    } finally {
      _carregandoMateriais = false;
      notifyListeners();
    }
  }

  Future<void> carregarHistorico({String? busca}) async {
    _carregandoHistorico = true;
    _erro = null;
    notifyListeners();

    try {
      _historico = await _repo.listarHistorico(busca: busca);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoHistorico = false;
      notifyListeners();
    }
  }

  Future<bool> criarSolicitacao({
    required int materialId,
    String? descricaoItem,
    required double quantidadeReservada,
    required String numeroOS,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    _erro = null;
    try {
      await _repo.criarSolicitacao(
        materialId: materialId,
        descricaoItem: descricaoItem,
        quantidadeReservada: quantidadeReservada,
        numeroOS: numeroOS,
        larguraUsada: larguraUsada,
        comprimentoUsado: comprimentoUsado,
      );
      await carregarMateriais();
      await carregarHistorico();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> registrarBaixa({
    required int solicitacaoId,
    required double quantidade,
    String? observacao,
  }) async {
    _erro = null;
    try {
      await _repo.registrarBaixa(
        solicitacaoId: solicitacaoId,
        quantidade: quantidade,
        observacao: observacao,
      );
      await carregarMateriais();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> finalizarSolicitacao(int solicitacaoId) async {
    _erro = null;
    try {
      await _repo.finalizarSolicitacao(solicitacaoId);
      await carregarMateriais();
      await carregarHistorico();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> excluirHistorico(int solicitacaoId) async {
    _erro = null;
    try {
      await _repo.excluirHistorico(solicitacaoId);
      await carregarHistorico();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}