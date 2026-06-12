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

  // ── Filtros ativos ────────────────────────────────────────────────────────
  String? _buscaAtiva;
  String? _materialIdAtivo;
  String? _materialNomeAtivo;
  String? _materialIdentificadorAtivo;
  String? _materialMedidaAtiva;
  String? _materialEspessuraAtiva;
  DateTime? _dataInicioAtiva;
  DateTime? _dataFimAtiva;

  bool get temFiltroMaterial =>
      (_materialIdAtivo?.isNotEmpty ?? false) ||
      (_materialNomeAtivo?.isNotEmpty ?? false) ||
      (_materialIdentificadorAtivo?.isNotEmpty ?? false) ||
      (_materialMedidaAtiva?.isNotEmpty ?? false) ||
      (_materialEspessuraAtiva?.isNotEmpty ?? false);

  Future<void> carregar({
    String? busca,
    String? materialId,
    String? materialNome,
    String? materialIdentificador,
    String? materialMedida,
    String? materialEspessura,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    _buscaAtiva                  = busca;
    _materialIdAtivo             = materialId;
    _materialNomeAtivo           = materialNome;
    _materialIdentificadorAtivo  = materialIdentificador;
    _materialMedidaAtiva         = materialMedida;
    _materialEspessuraAtiva      = materialEspessura;
    _dataInicioAtiva             = dataInicio;
    _dataFimAtiva                = dataFim;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _relatorios = await _repo.listarRelatoriosOS(
        busca:                 busca,
        materialId:            materialId,
        materialNome:          materialNome,
        materialIdentificador: materialIdentificador,
        materialMedida:        materialMedida,
        materialEspessura:     materialEspessura,
        dataInicio:            dataInicio,
        dataFim:               dataFim,
      );
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Recarrega preservando todos os filtros ativos.
  Future<void> recarregar() => carregar(
        busca:                 _buscaAtiva,
        materialId:            _materialIdAtivo,
        materialNome:          _materialNomeAtivo,
        materialIdentificador: _materialIdentificadorAtivo,
        materialMedida:        _materialMedidaAtiva,
        materialEspessura:     _materialEspessuraAtiva,
        dataInicio:            _dataInicioAtiva,
        dataFim:               _dataFimAtiva,
      );

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
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}