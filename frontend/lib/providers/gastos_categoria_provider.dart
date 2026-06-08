import 'package:flutter/foundation.dart';
import '../models/gastos_categoria_model.dart';
import '../utils/api_client.dart';

String _mensagemErro(Object e) {
  final raw = e.toString();
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class GastosCategoriaProvider extends ChangeNotifier {
  List<GastoCategoriaModel> _categorias = [];
  List<GastoCategoriaModel> get categorias => _categorias;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  DateTime? _dataInicioAtiva;
  DateTime? _dataFimAtiva;

  DateTime? get dataInicioAtiva => _dataInicioAtiva;
  DateTime? get dataFimAtiva    => _dataFimAtiva;

  double get totalEntradaGeral =>
      _categorias.fold(0, (s, c) => s + c.totalEntrada);

  double get totalSaidaGeral =>
      _categorias.fold(0, (s, c) => s + c.totalSaida);

  Future<void> carregar({DateTime? dataInicio, DateTime? dataFim}) async {
    _dataInicioAtiva = dataInicio;
    _dataFimAtiva    = dataFim;
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      final params = <String>[];
      if (dataInicio != null) {
        params.add(
          'dataInicio=${dataInicio.year}-'
          '${dataInicio.month.toString().padLeft(2, '0')}-'
          '${dataInicio.day.toString().padLeft(2, '0')}',
        );
      }
      if (dataFim != null) {
        params.add(
          'dataFim=${dataFim.year}-'
          '${dataFim.month.toString().padLeft(2, '0')}-'
          '${dataFim.day.toString().padLeft(2, '0')}',
        );
      }
      final path = params.isEmpty
          ? '/gastos-categoria'
          : '/gastos-categoria?${params.join('&')}';

      final list = await ApiClient.getList(path);
      _categorias = list
          .map((e) => GastoCategoriaModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() =>
      carregar(dataInicio: _dataInicioAtiva, dataFim: _dataFimAtiva);
}