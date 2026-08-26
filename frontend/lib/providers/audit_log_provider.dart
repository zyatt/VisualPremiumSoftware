import 'package:flutter/foundation.dart';
import '../models/audit_log_model.dart';
import '../repositories/audit_log_repository.dart';

String _mensagemErro(Object e) {
  final raw = e.toString();
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class AuditLogProvider extends ChangeNotifier {
  final AuditLogRepository _repo = AuditLogRepository();

  List<AuditLogModel> _logs = [];
  List<AuditLogModel> get logs => _logs;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  int?      _materialId;
  String?   _acao;
  String?   _busca;
  DateTime? _dataInicio;
  DateTime? _dataFim;

  Future<void> carregar({
    int? materialId,
    String? acao,
    String? busca,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    _materialId  = materialId;
    _acao        = acao;
    _busca       = busca;
    _dataInicio  = dataInicio;
    _dataFim     = dataFim;

    _carregando = true;
    _erro       = null;
    notifyListeners();

    try {
      _logs = await _repo.listar(
        materialId: materialId,
        acao:       acao,
        busca:      busca,
        dataInicio: dataInicio,
        dataFim:    dataFim,
      );
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> carregarPorMaterial(int materialId) async {
    _carregando = true;
    _erro       = null;
    notifyListeners();

    try {
      _logs = await _repo.listarPorMaterial(materialId);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    await carregar(
      materialId: _materialId,
      acao:       _acao,
      busca:      _busca,
      dataInicio: _dataInicio,
      dataFim:    _dataFim,
    );
  }

  void limpar() {
    _logs        = [];
    _materialId  = null;
    _acao        = null;
    _busca       = null;
    _dataInicio  = null;
    _dataFim     = null;
    _erro        = null;
    notifyListeners();
  }
}