import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/alertas_estoque_model.dart';
import '../utils/api_client.dart';

class AlertasEstoqueProvider extends ChangeNotifier {
  List<AlertaEstoqueModel> _alertas = [];
  List<AlertaEstoqueModel> get alertas => _alertas;

  int get totalAlertas => _alertas.length;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  Timer? _pollingTimer;

  bool _pollingAtivo = false;

  void iniciarPolling({Duration intervalo = const Duration(minutes: 5)}) {
    if (_pollingAtivo) return;
    _pollingAtivo = true;

    _pollingTimer?.cancel();
    carregar();
    _pollingTimer = Timer.periodic(intervalo, (_) => carregar());
  }

  void pararPolling() {
    _pollingAtivo = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> carregar() async {
    if (_alertas.isEmpty) {
      _carregando = true;
      notifyListeners();
    }
    try {
      final list = await ApiClient.getList('/alertas-estoque');
      _alertas = list
          .map((e) => AlertaEstoqueModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _erro = null;
    } catch (e) {
      final raw = e.toString();
      _erro = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();

      final erroLower = raw.toLowerCase();
      if (erroLower.contains('401') || erroLower.contains('403')) {
        pararPolling();
      }
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    pararPolling();
    super.dispose();
  }
}