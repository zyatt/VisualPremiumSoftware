import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NavPosicao { lateral, topo }

class NavLayoutProvider extends ChangeNotifier {
  static const _chave = 'nav_posicao';

  NavPosicao _posicao = NavPosicao.lateral;
  NavPosicao get posicao => _posicao;
  bool get isTopo => _posicao == NavPosicao.topo;

  NavLayoutProvider() {
    _carregar();
  }

  Future<void> _carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getString(_chave);
    if (salvo == NavPosicao.topo.name) {
      _posicao = NavPosicao.topo;
      notifyListeners();
    }
  }

  Future<void> definir(NavPosicao posicao) async {
    if (_posicao == posicao) return;
    _posicao = posicao;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, posicao.name);
  }

  Future<void> alternar() =>
      definir(_posicao == NavPosicao.lateral ? NavPosicao.topo : NavPosicao.lateral);
}