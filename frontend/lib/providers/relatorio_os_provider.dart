import 'package:flutter/foundation.dart';
import '../repositories/estoque_repository.dart';

class RelatorioOSProvider extends ChangeNotifier {
  final EstoqueRepository _repo = EstoqueRepository();

  List<dynamic> _relatorios = [];
  List<dynamic> get relatorios => _relatorios;

  dynamic _selecionado;
  dynamic get selecionado => _selecionado;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    
  }

  void selecionar(dynamic relatorio) {
    _selecionado = relatorio;
    notifyListeners();
  }

  void limparSelecao() {
    _selecionado = null;
    notifyListeners();
  }
}