import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla a exibição dos widgets flutuantes globais (bolha do chat e
/// bolha do Robô Ajudante) em toda a aplicação. Diferente do "ocultar"
/// temporário de cada widget (que apenas minimiza a bolha na tela atual),
/// esta preferência remove o widget por completo — ele deixa de ser
/// construído em [AppShell] enquanto estiver desativado. A preferência é
/// persistida localmente e vale para todas as telas até o usuário
/// reativar em Configurações.
class WidgetsFlutuantesProvider extends ChangeNotifier {
  static const _chaveChatVisivel = 'widget_chat_flutuante_visivel';
  static const _chaveRoboVisivel = 'widget_robo_helper_visivel';

  bool _chatVisivel = true;
  bool get chatVisivel => _chatVisivel;

  bool _roboVisivel = true;
  bool get roboVisivel => _roboVisivel;

  bool _carregado = false;
  bool get carregado => _carregado;

  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    _chatVisivel = prefs.getBool(_chaveChatVisivel) ?? true;
    _roboVisivel = prefs.getBool(_chaveRoboVisivel) ?? true;
    _carregado = true;
    notifyListeners();
  }

  Future<void> definirChatVisivel(bool visivel) async {
    if (_chatVisivel == visivel) return;
    _chatVisivel = visivel;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveChatVisivel, visivel);
  }

  Future<void> definirRoboVisivel(bool visivel) async {
    if (_roboVisivel == visivel) return;
    _roboVisivel = visivel;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveRoboVisivel, visivel);
  }
}