import 'package:flutter/foundation.dart';
import '../models/veiculo_model.dart';
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

class VeiculoProvider extends ChangeNotifier {
  // ── Lista de veículos ──────────────────────────────────────────────────────
  List<VeiculoModel> _veiculos = [];
  List<VeiculoModel> get veiculos => _veiculos;

  bool   _carregando = false;
  bool   get carregando => _carregando;
  String? _erro;
  String? get erro => _erro;

  // ── Manutenções do veículo selecionado ─────────────────────────────────────
  List<ManutencaoModel> _manutencoes = [];
  List<ManutencaoModel> get manutencoes => _manutencoes;

  bool   _carregandoMan = false;
  bool   get carregandoMan => _carregandoMan;
  String? _erroMan;
  String? get erroMan => _erroMan;

  // ── Gastos por veículo ─────────────────────────────────────────────────────
  List<GastoVeiculoModel> _gastos = [];
  List<GastoVeiculoModel> get gastos => _gastos;

  bool   _carregandoGastos = false;
  bool   get carregandoGastos => _carregandoGastos;

  double get totalGastosGeral =>
      _gastos.fold(0, (s, g) => s + g.totalGasto);

  // ── Resumo anual ───────────────────────────────────────────────────────────
  ResumoAnualVeiculoModel? _resumoAnual;
  ResumoAnualVeiculoModel? get resumoAnual => _resumoAnual;

  bool _carregandoResumo = false;
  bool get carregandoResumo => _carregandoResumo;

  // ─────────────────────────────────────────────────────────────────────────
  // Veículos
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> carregarVeiculos() async {
    _carregando = true;
    _erro       = null;
    notifyListeners();
    try {
      final list  = await ApiClient.getList('/veiculos');
      _veiculos   = list
          .map((e) => VeiculoModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<bool> criarVeiculo({required String nome, required String placa}) async {
    try {
      await ApiClient.post('/veiculos', {'nome': nome, 'placa': placa});
      await carregarVeiculos();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizarVeiculo(int id, {String? nome, String? placa}) async {
    try {
      final body = <String, dynamic>{};
      if (nome  != null) body['nome']  = nome;
      if (placa != null) body['placa'] = placa;
      await ApiClient.put('/veiculos/$id', body);
      await carregarVeiculos();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> desativarVeiculo(int id) async {
    try {
      await ApiClient.delete('/veiculos/$id');
      await carregarVeiculos();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Manutenções
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> carregarManutencoes(int veiculoId) async {
    _carregandoMan = true;
    _erroMan       = null;
    notifyListeners();
    try {
      final list  = await ApiClient.getList('/veiculos/$veiculoId/manutencoes');
      _manutencoes = list
          .map((e) => ManutencaoModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erroMan = _mensagemErro(e);
    } finally {
      _carregandoMan = false;
      notifyListeners();
    }
  }

  Future<bool> criarManutencao({
    required int     veiculoId,
    required String  tipo,
    String?          descricao,
    required double  valor,
    required DateTime dataEnvio,
    DateTime?        dataRetirada,
  }) async {
    try {
      final body = {
        'tipo':         tipo,
        'descricao':    descricao,
        'valor':        valor,
        'dataEnvio':    dataEnvio.toIso8601String(),
        'dataRetirada': dataRetirada?.toIso8601String(),
      };
      await ApiClient.post('/veiculos/$veiculoId/manutencoes', body);
      await carregarManutencoes(veiculoId);
      await carregarVeiculos(); // atualiza última manutenção no card
      return true;
    } catch (e) {
      _erroMan = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizarManutencao(
    int manutencaoId,
    int veiculoId, {
    String?   tipo,
    String?   descricao,
    double?   valor,
    DateTime? dataEnvio,
    DateTime? dataRetirada,
    bool      limparRetirada = false,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (tipo         != null) body['tipo']      = tipo;
      if (descricao    != null) body['descricao'] = descricao;
      if (valor        != null) body['valor']     = valor;
      if (dataEnvio    != null) body['dataEnvio'] = dataEnvio.toIso8601String();
      if (limparRetirada) {
        body['dataRetirada'] = null;
      } else if (dataRetirada != null) {
        body['dataRetirada'] = dataRetirada.toIso8601String();
      }
      await ApiClient.put('/veiculos/manutencoes/$manutencaoId', body);
      await carregarManutencoes(veiculoId);
      return true;
    } catch (e) {
      _erroMan = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deletarManutencao(int manutencaoId, int veiculoId) async {
    try {
      await ApiClient.delete('/veiculos/manutencoes/$manutencaoId');
      await carregarManutencoes(veiculoId);
      return true;
    } catch (e) {
      _erroMan = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gastos
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> carregarGastos({DateTime? dataInicio, DateTime? dataFim}) async {
    _carregandoGastos = true;
    notifyListeners();
    try {
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final params = <String>[];
      if (dataInicio != null) params.add('dataInicio=${fmt(dataInicio)}');
      if (dataFim    != null) params.add('dataFim=${fmt(dataFim)}');
      final path = params.isEmpty
          ? '/veiculos/gastos'
          : '/veiculos/gastos?${params.join('&')}';

      final list = await ApiClient.getList(path);
      _gastos    = list
          .map((e) => GastoVeiculoModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _gastos = [];
    } finally {
      _carregandoGastos = false;
      notifyListeners();
    }
  }

  Future<void> carregarResumoAnual({int? ano}) async {
    _carregandoResumo = true;
    notifyListeners();
    try {
      final path  = ano != null ? '/veiculos/gastos/resumo?ano=$ano' : '/veiculos/gastos/resumo';
      final json  = await ApiClient.get(path);
      _resumoAnual = ResumoAnualVeiculoModel.fromJson(json);
    } catch (_) {
      _resumoAnual = null;
    } finally {
      _carregandoResumo = false;
      notifyListeners();
    }
  }
}