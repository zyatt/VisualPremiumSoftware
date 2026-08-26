import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../repositories/ordem_compra_repository.dart';

String mensagemErro(Object e, {required String acao}) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Erro ao $acao: Verifique a conexão com o servidor.';
  }
  final msg = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
  return 'Erro ao $acao: $msg';
}

/// Filtros de busca usados pela tela de listagem (compartilhados entre as
/// 3 abas: Em Andamento, Finalizadas, Canceladas).
class OrdemCompraFiltros {
  final String? numero;
  final String? material;
  final String? identificador;
  final String? medida;
  final String? comprimento;
  final String? largura;
  final String? espessura;

  const OrdemCompraFiltros({
    this.numero,
    this.material,
    this.identificador,
    this.medida,
    this.comprimento,
    this.largura,
    this.espessura,
  });

  bool get vazio =>
      (numero == null || numero!.isEmpty) &&
      (material == null || material!.isEmpty) &&
      (identificador == null || identificador!.isEmpty) &&
      (medida == null || medida!.isEmpty) &&
      (comprimento == null || comprimento!.isEmpty) &&
      (largura == null || largura!.isEmpty) &&
      (espessura == null || espessura!.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is OrdemCompraFiltros &&
      numero == other.numero &&
      material == other.material &&
      identificador == other.identificador &&
      medida == other.medida &&
      comprimento == other.comprimento &&
      largura == other.largura &&
      espessura == other.espessura;

  @override
  int get hashCode => Object.hash(
      numero, material, identificador, medida, comprimento, largura, espessura);
}

class OrdemCompraProvider extends ChangeNotifier {
  final OrdemCompraRepository _repo = OrdemCompraRepository();

  static const _statusPorAba = ['EM_ANDAMENTO', 'FINALIZADO', 'CANCELADO'];
  static const int porPagina = 50;

  final Map<String, List<dynamic>> _itensPorStatus = {
    'EM_ANDAMENTO': [],
    'FINALIZADO': [],
    'CANCELADO': [],
  };
  final Map<String, int> _totalPorStatus = {
    'EM_ANDAMENTO': 0,
    'FINALIZADO': 0,
    'CANCELADO': 0,
  };
  final Map<String, int> _paginaAtualPorStatus = {
    'EM_ANDAMENTO': 1,
    'FINALIZADO': 1,
    'CANCELADO': 1,
  };
  final Map<String, bool> _carregandoPaginaPorStatus = {
    'EM_ANDAMENTO': false,
    'FINALIZADO': false,
    'CANCELADO': false,
  };

  OrdemCompraFiltros _filtros = const OrdemCompraFiltros();
  OrdemCompraFiltros get filtros => _filtros;

  List<dynamic> get emAndamento => _itensPorStatus['EM_ANDAMENTO']!;
  List<dynamic> get finalizadas => _itensPorStatus['FINALIZADO']!;
  List<dynamic> get canceladas  => _itensPorStatus['CANCELADO']!;

  int get totalEmAndamento => _totalPorStatus['EM_ANDAMENTO']!;
  int get totalFinalizadas => _totalPorStatus['FINALIZADO']!;
  int get totalCanceladas  => _totalPorStatus['CANCELADO']!;

  /// Página atual (1-based) de cada aba.
  int paginaAtual(String status) => _paginaAtualPorStatus[status] ?? 1;

  /// Total de páginas de cada aba, com base no total de itens e no
  /// tamanho de página fixo [porPagina].
  int totalPaginas(String status) {
    final total = _totalPorStatus[status] ?? 0;
    return (total / porPagina).ceil().clamp(1, 999999999);
  }

  bool carregandoPagina(String status) => _carregandoPaginaPorStatus[status] ?? false;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  int? _ocPendente;
  int? get ocPendente => _ocPendente;

  void sinalizarOcParaAbrir(int id) {
    _ocPendente = id;
  }

  int? consumirOcPendente() {
    final id = _ocPendente;
    _ocPendente = null;
    return id;
  }

  /// Atualiza os filtros de busca e recarrega a primeira página de todas
  /// as abas. Não recarrega se os filtros forem idênticos aos atuais.
  Future<void> aplicarFiltros(OrdemCompraFiltros filtros) async {
    if (filtros == _filtros) return;
    _filtros = filtros;
    await carregar();
  }

  /// Carrega (ou recarrega) a primeira página das 3 abas em paralelo.
  /// Chamado ao entrar na tela e sempre que o usuário volta pra ela.
  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final resultados = await Future.wait(
        _statusPorAba.map((status) => _repo.listarPagina(
              status: status,
              numero: _filtros.numero,
              material: _filtros.material,
              identificador: _filtros.identificador,
              medida: _filtros.medida,
              comprimento: _filtros.comprimento,
              largura: _filtros.largura,
              espessura: _filtros.espessura,
              pagina: 1,
              porPagina: porPagina,
            )),
      );
      for (var i = 0; i < _statusPorAba.length; i++) {
        final status = _statusPorAba[i];
        _itensPorStatus[status]     = resultados[i].itens;
        _totalPorStatus[status]     = resultados[i].total;
        _paginaAtualPorStatus[status] = 1;
      }
    } catch (e) {
      _erro = mensagemErro(e, acao: 'carregar ordens de compra');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Vai para uma página específica (1-based) de uma aba, substituindo os
  /// itens atualmente exibidos (paginação numerada, igual à tela de
  /// Estoque). Se a página pedida ficar vazia (ex.: item da última página
  /// foi excluído), recua automaticamente para a página anterior.
  Future<void> irParaPagina(String status, int pagina) async {
    if (_carregandoPaginaPorStatus[status] == true) return;
    if (!_itensPorStatus.containsKey(status)) return;
    if (pagina < 1) pagina = 1;

    _carregandoPaginaPorStatus[status] = true;
    notifyListeners();
    try {
      final resultado = await _repo.listarPagina(
        status: status,
        numero: _filtros.numero,
        material: _filtros.material,
        identificador: _filtros.identificador,
        medida: _filtros.medida,
        comprimento: _filtros.comprimento,
        largura: _filtros.largura,
        espessura: _filtros.espessura,
        pagina: pagina,
        porPagina: porPagina,
      );

      _totalPorStatus[status] = resultado.total;

      if (resultado.itens.isEmpty && resultado.total > 0 && pagina > 1) {
        _carregandoPaginaPorStatus[status] = false;
        await irParaPagina(status, pagina - 1);
        return;
      }

      _itensPorStatus[status] = resultado.itens;
      _paginaAtualPorStatus[status] = pagina;
    } catch (e) {
      _erro = mensagemErro(e, acao: 'carregar ordens de compra');
    } finally {
      _carregandoPaginaPorStatus[status] = false;
      notifyListeners();
    }
  }

  Future<void> criar(Map<String, dynamic> dados) async {
    try {
      await _repo.criar(dados);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'criar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> finalizar(int id) async {
    try {
      await _repo.atualizarStatus(id, 'FINALIZADO');
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'finalizar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelar(int id) async {
    try {
      await _repo.atualizarStatus(id, 'CANCELADO');
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'cancelar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reverter(int id) async {
    try {
      await _repo.reverter(id);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'reverter ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizar(id, dados);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'atualizar ordem de compra');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> excluir(int id) async {
    try {
      await _repo.excluir(id);
      await carregar();
    } catch (e) {
      _erro = mensagemErro(e, acao: 'excluir ordem de compra');
      notifyListeners();
      rethrow;
    }
  }
}