import 'package:flutter/foundation.dart';
import '../models/gastos_categoria_model.dart';
import '../utils/api_client.dart';

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

class GastosCategoriaProvider extends ChangeNotifier {

  // ── SEÇÃO 1: Valor em estoque ─────────────────────────────────────────────

  List<EstoqueCategoriaModel> _estoque = [];
  List<EstoqueCategoriaModel> get estoque => _estoque;

  bool   _carregandoEstoque = false;
  bool   get carregandoEstoque => _carregandoEstoque;

  String? _erroEstoque;
  String? get erroEstoque => _erroEstoque;

  double get totalValorEstoque =>
      _estoque.fold(0, (s, c) => s + c.totalValor);

  Future<void> carregarEstoque() async {
    _carregandoEstoque = true;
    _erroEstoque = null;
    notifyListeners();
    try {
      final list = await ApiClient.getList('/gastos-categoria/estoque');
      _estoque = list
          .map((e) => EstoqueCategoriaModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erroEstoque = _mensagemErro(e);
    } finally {
      _carregandoEstoque = false;
      notifyListeners();
    }
  }

  // ── SEÇÃO 2: Gastos (OS fechadas, saídas com origem em OC) ───────────────

  List<GastoCategoriaModel> _gastos = [];
  List<GastoCategoriaModel> get gastos => _gastos;

  bool    _carregandoGastos = false;
  bool    get carregandoGastos => _carregandoGastos;

  String? _erroGastos;
  String? get erroGastos => _erroGastos;

  DateTime? _dataInicioAtiva;
  DateTime? _dataFimAtiva;
  DateTime? get dataInicioAtiva => _dataInicioAtiva;
  DateTime? get dataFimAtiva    => _dataFimAtiva;

  double get totalGastos =>
      _gastos.fold(0, (s, c) => s + c.totalGasto);

  Future<void> carregarGastos({DateTime? dataInicio, DateTime? dataFim}) async {
    _dataInicioAtiva = dataInicio;
    _dataFimAtiva    = dataFim;
    _carregandoGastos = true;
    _erroGastos = null;
    notifyListeners();
    try {
      final params = <String>[];
      if (dataInicio != null) {
        params.add('dataInicio=${dataInicio.year}-'
            '${dataInicio.month.toString().padLeft(2, '0')}-'
            '${dataInicio.day.toString().padLeft(2, '0')}');
      }
      if (dataFim != null) {
        params.add('dataFim=${dataFim.year}-'
            '${dataFim.month.toString().padLeft(2, '0')}-'
            '${dataFim.day.toString().padLeft(2, '0')}');
      }
      final path = params.isEmpty
          ? '/gastos-categoria'
          : '/gastos-categoria?${params.join('&')}';
      final list = await ApiClient.getList(path);
      _gastos = list
          .map((e) => GastoCategoriaModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erroGastos = _mensagemErro(e);
    } finally {
      _carregandoGastos = false;
      notifyListeners();
    }
  }

  Future<void> recarregarGastos() =>
      carregarGastos(dataInicio: _dataInicioAtiva, dataFim: _dataFimAtiva);

  // ── SEÇÃO 3: Gráfico mensal ───────────────────────────────────────────────

  List<GastoMensalModel> _mensal = [];
  List<GastoMensalModel> get mensal => _mensal;

  bool    _carregandoMensal = false;
  bool    get carregandoMensal => _carregandoMensal;

  String? _erroMensal;
  String? get erroMensal => _erroMensal;

  int _anoMensal = DateTime.now().year;
  int get anoMensal => _anoMensal;

  Future<void> carregarMensal({int? ano}) async {
    _anoMensal = ano ?? DateTime.now().year;
    _carregandoMensal = true;
    _erroMensal = null;
    notifyListeners();
    try {
      final list = await ApiClient.getList(
        '/gastos-categoria/mensal?ano=$_anoMensal',
      );
      _mensal = list
          .map((e) => GastoMensalModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erroMensal = _mensagemErro(e);
    } finally {
      _carregandoMensal = false;
      notifyListeners();
    }
  }

  // ── Ação unificada: carrega tudo ──────────────────────────────────────────

  Future<void> carregarTudo({DateTime? dataInicio, DateTime? dataFim}) async {
    await Future.wait([
      carregarEstoque(),
      carregarGastos(dataInicio: dataInicio, dataFim: dataFim),
    ]);
  }
}