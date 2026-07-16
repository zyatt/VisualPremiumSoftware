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

  /// Evita iniciar múltiplos pollings em paralelo caso este método
  /// seja chamado mais de uma vez (ex.: rebuilds da AppShell).
  bool _pollingAtivo = false;

  /// Inicia o polling automático a cada [intervalo].
  /// Chame em initState da AppShell ou no login do usuário.
  void iniciarPolling({Duration intervalo = const Duration(minutes: 5)}) {
    // Já está rodando: não recria o timer nem duplica as chamadas.
    if (_pollingAtivo) return;
    _pollingAtivo = true;

    _pollingTimer?.cancel();
    carregar(); // carrega imediatamente
    _pollingTimer = Timer.periodic(intervalo, (_) => carregar());
  }

  void pararPolling() {
    _pollingAtivo = false;
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

      // Sessão expirada/sem permissão: não adianta continuar batendo
      // na API em loop, então paramos o polling automático.
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