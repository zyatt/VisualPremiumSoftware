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

  /// Inicia o polling automático a cada [intervalo].
  /// Chame em initState da AppShell ou no login do usuário.
  void iniciarPolling({Duration intervalo = const Duration(minutes: 5)}) {
    _pollingTimer?.cancel();
    carregar(); // carrega imediatamente
    _pollingTimer = Timer.periodic(intervalo, (_) => carregar());
  }

  void pararPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> carregar() async {
    // Não mostra loading no polling silencioso (só na primeira vez)
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