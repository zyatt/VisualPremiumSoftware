import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;
import '../models/material_model.dart';
import '../repositories/material_repository.dart';
import '../utils/api_client.dart';

class FiltroMaterialChat {
  final int? materialId;
  final String? nome;
  final String? categoria;
  final String? identificador;
  final String? medida;
  final String? espessura;
  const FiltroMaterialChat({
    this.materialId,
    this.nome,
    this.categoria,
    this.identificador,
    this.medida,
    this.espessura,
  });
}

String _mensagemErro(Object e, {required String acao}) {
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

  if (raw.contains('foreign key constraint') ||
      raw.contains('violates RESTRICT') ||
      raw.contains('P2003')) {
    return 'Não é possível excluir: este item está vinculado a outros registros '
        '(movimentações, orçamentos ou ordens de compra). Desative-o em vez de excluí-lo.';
  }
  final msg = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
  return 'Erro ao $acao: $msg';
}

class MaterialProvider extends ChangeNotifier {
  final MaterialRepository _repo = MaterialRepository();

  List<MaterialModel> _materiais = [];
  List<MaterialModel> get materiais => _materiais;

  List<String> _categorias = [];
  List<String> get categorias => _categorias;

  bool _categoriasCarregadas = false;
  bool get categoriasCarregadas => _categoriasCarregadas;

  bool _carregando = false;
  bool get carregando => _carregando;

  List<MaterialModel> _materiaisPagina = [];
  List<MaterialModel> get materiaisPagina => _materiaisPagina;

  int _totalItensPagina = 0;
  int get totalItensPagina => _totalItensPagina;

  bool _carregandoPagina = false;
  bool get carregandoPagina => _carregandoPagina;

  List<MaterialModel> _materiaisRecentes = [];
  List<MaterialModel> get materiaisRecentes => _materiaisRecentes;

  bool _carregandoRecentes = false;
  bool get carregandoRecentes => _carregandoRecentes;

  String? _erro;
  String? get erro => _erro;

  String _busca = '';
  String? _categoriaFiltro;
  String _statusFiltro = '';
  String _idFiltro = '';
  String _identificadorFiltro = '';
  String _medidaFiltro = '';
  String _espessuraFiltro = '';
  String _larguraFiltro = '';
  String _comprimentoFiltro = '';

  bool _paginaAberta = false;
  bool _notificacoesConectadas = false;
  bool get notificacoesConectadas => _notificacoesConectadas;

  http.Client? _sseClient;
  HttpClient? _sseRawClient;
  StreamSubscription<String>? _sseSub;
  Timer? _reconnectTimer;
  Timer? _pollingTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  int _sseGeracao = 0;

  final _materialAtualizadoController = StreamController<void>.broadcast();
  Stream<void> get materialAtualizadoStream =>
      _materialAtualizadoController.stream;

  MaterialCriticoNotificacao? _notificacaoCriticaPendente;
  MaterialCriticoNotificacao? get notificacaoCriticaPendente =>
      _notificacaoCriticaPendente;

  void consumirNotificacaoCriticaPendente() {
    _notificacaoCriticaPendente = null;
  }

  MaterialCriticoNotificacao? _filtroNavegacaoPendente;
  MaterialCriticoNotificacao? get filtroNavegacaoPendente =>
      _filtroNavegacaoPendente;

  void solicitarNavegacaoParaMaterial(MaterialCriticoNotificacao notificacao) {
    _filtroNavegacaoPendente = notificacao;
    notifyListeners();
  }

  void consumirFiltroNavegacaoPendente() {
    _filtroNavegacaoPendente = null;
  }

  FiltroMaterialChat? _filtroChatPendente;
  FiltroMaterialChat? get filtroChatPendente => _filtroChatPendente;

  void solicitarNavegacaoParaMaterialChat(FiltroMaterialChat filtro) {
    _filtroChatPendente = filtro;
    notifyListeners();
  }

  void consumirFiltroChatPendente() {
    _filtroChatPendente = null;
  }

  String? _filtroStatusPendente;
  String? get filtroStatusPendente => _filtroStatusPendente;

  void definirFiltroStatusPendente(String status) {
    _filtroStatusPendente = status;
    notifyListeners();
  }

  void consumirFiltroStatusPendente() {
    _filtroStatusPendente = null;
  }

  Future<void> conectarNotificacoes() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _reconnectTimer?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;

    final meuId = ++_sseGeracao;
    debugPrint('[FECHAR][Materiais] ${DateTime.now().toIso8601String()} — abrindo nova conexão SSE, geração $meuId');

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/api/materiais/notificacoes');
      debugPrint('🔔 [Materiais] Conectando ao SSE: $uri');

      final token = ApiClient.token;
      if (token == null) {
        debugPrint('⚠️ [Materiais] Token não disponível para SSE');
        _scheduleReconnect(meuId);
        return;
      }

      final rawClient = HttpClient();
      _sseRawClient = rawClient;
      _sseClient = io_client.IOClient(rawClient);

      final req = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache'
        ..headers['Connection'] = 'keep-alive';

      final streamedResp = await _sseClient!.send(req);

      if (meuId != _sseGeracao) {
        return;
      }

      if (streamedResp.statusCode != 200) {
        debugPrint('❌ [Materiais] SSE falhou com status ${streamedResp.statusCode}');
        _scheduleReconnect(meuId);
        return;
      }

      debugPrint('✅ [Materiais] SSE conectado com sucesso');
      _notificacoesConectadas = true;
      _reconnectAttempts = 0;
      notifyListeners();

      final stream = streamedResp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sseSub = stream.listen(
        _processarLinhaSSE,
        onError: (error) {
          debugPrint('❌ [Materiais] Erro no SSE: $error');
          if (meuId != _sseGeracao) return;
          _notificacoesConectadas = false;
          notifyListeners();
          _scheduleReconnect(meuId);
        },
        onDone: () {
          debugPrint('⚠️ [Materiais] SSE stream encerrado');
          if (meuId != _sseGeracao) return;
          _notificacoesConectadas = false;
          notifyListeners();
          _scheduleReconnect(meuId);
        },
        cancelOnError: true,
      );

      _pollingTimer?.cancel();
      _pollingTimer = null;
    } catch (e) {
      debugPrint('❌ [Materiais] Erro ao conectar SSE: $e');
      if (meuId != _sseGeracao) return;
      _notificacoesConectadas = false;
      notifyListeners();
      _scheduleReconnect(meuId);
    }
  }

  void _processarLinhaSSE(String linha) {
    if (linha.startsWith(':')) return;
    if (linha.trim().isEmpty) return;

    if (linha.startsWith('data:')) {
      final raw = linha.substring(5).trim();
      if (raw.isEmpty) return;

      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final tipo = data['tipo'] as String?;

        if (tipo == 'conectado') {
          debugPrint('✅ [Materiais] Confirmação de conexão recebida');
          return;
        }

        if (tipo == 'material_critico') {
          debugPrint('🔴 [Materiais] Estoque crítico: ${data['nome']}');
          _notificacaoCriticaPendente =
              MaterialCriticoNotificacao.fromJson(data);
          notifyListeners();
          return;
        }

        if (tipo == 'material_atualizado') {
          debugPrint('🔔 [Materiais] Atualização recebida: motivo=${data['motivo']}');

          _materialAtualizadoController.add(null);
          if (_paginaAberta) {
            recarregar();
          }
        }
      } catch (e) {
        debugPrint('❌ [Materiais] Erro ao processar SSE: $e, linha: $linha');
      }
    }
  }

  void _scheduleReconnect(int meuId) {
    if (meuId != _sseGeracao) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('⚠️ [Materiais] Máximo de tentativas atingido. Usando polling.');
      _iniciarPolling();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    debugPrint('🔄 [Materiais] Reconectando SSE em ${delay.inSeconds}s (tentativa $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, conectarNotificacoes);
  }

  void _iniciarPolling() {
    _pollingTimer?.cancel();
    debugPrint('📊 [Materiais] Iniciando polling a cada 30s como fallback');

    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_paginaAberta) recarregar();
    });
  }

  void definirPaginaVisivel(bool visivel) {
    if (visivel == _paginaAberta) return;
    _paginaAberta = visivel;
  }

  Future<void> resetarConexao() async {
    _sseGeracao++;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await _sseSub?.cancel();
    _sseSub = null;
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;
    _notificacoesConectadas = false;
    _paginaAberta = false;
    notifyListeners();
  }

  void encerrarConexaoSSE() {
    debugPrint('[FECHAR][Materiais] ${DateTime.now().toIso8601String()} — encerrarConexaoSSE chamado, geração $_sseGeracao -> ${_sseGeracao + 1}');
    _sseGeracao++;
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _sseSub?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;
  }

  @override
  void dispose() {
    _sseGeracao++;
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _sseSub?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;
    _materialAtualizadoController.close();
    super.dispose();
  }

  Future<void> carregar({
    String busca = '',
    String? categoria,
    String status = '',
    String id = '',
    String identificador = '',
    String medida = '',
    String espessura = '',
    String largura = '',
    String comprimento = '',
    bool? ativo,
  }) async {
    _busca = busca;
    _categoriaFiltro = categoria;
    _statusFiltro = status;
    _idFiltro = id;
    _identificadorFiltro = identificador;
    _medidaFiltro = medida;
    _espessuraFiltro = espessura;
    _larguraFiltro = largura;
    _comprimentoFiltro = comprimento;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _materiais = await _repo.listar(
        busca:        busca,
        categoria:    categoria,
        status:       status,
        id:           id,
        identificador: identificador,
        medida:       medida,
        espessura:    espessura,
        largura:      largura,
        comprimento:  comprimento,
        ativo:        ativo,
      );
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar estoque');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    await carregar(
      busca:        _busca,
      categoria:    _categoriaFiltro,
      status:       _statusFiltro,
      id:           _idFiltro,
      identificador: _identificadorFiltro,
      medida:       _medidaFiltro,
      espessura:    _espessuraFiltro,
      largura:      _larguraFiltro,
      comprimento:  _comprimentoFiltro,
    );
  }

  Future<void> carregarPaginado({
    String busca = '',
    String? categoria,
    String status = '',
    String identificador = '',
    String medida = '',
    String espessura = '',
    String largura = '',
    String comprimento = '',
    bool? ativo,
    bool comFornecedor = false,
    required int pagina,
    int porPagina = 50,
    String? ordenarPor,
    String? direcao,
  }) async {
    _carregandoPagina = true;
    _erro = null;
    notifyListeners();
    try {
      final resultado = await _repo.listarPaginado(
        busca:         busca,
        categoria:     categoria,
        status:        status,
        identificador: identificador,
        medida:        medida,
        espessura:     espessura,
        largura:       largura.isEmpty ? null : largura,
        comprimento:   comprimento.isEmpty ? null : comprimento,
        ativo:         ativo,
        comFornecedor: comFornecedor,
        pagina:        pagina,
        porPagina:     porPagina,
        ordenarPor:    ordenarPor,
        direcao:       direcao,
      );
      _materiaisPagina   = resultado.itens;
      _totalItensPagina  = resultado.total;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar estoque');
    } finally {
      _carregandoPagina = false;
      notifyListeners();
    }
  }

  Future<void> carregarRecentes() async {
    _carregandoRecentes = true;
    notifyListeners();
    try {
      final resultado = await _repo.listarPaginado(
        pagina:     1,
        porPagina:  8,
        ordenarPor: 'atualizadoEm',
        direcao:    'desc',
      );
      _materiaisRecentes = resultado.itens;
    } catch (_) {

    } finally {
      _carregandoRecentes = false;
      notifyListeners();
    }
  }

  Future<void> carregarCategorias() async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _categorias = await _repo.listarCategorias();
      _categoriasCarregadas = true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar categorias');

    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<MaterialModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar material');
      notifyListeners();
      return null;
    }
  }

  List<MaterialModel> _materiaisMovimentacao = [];
  List<MaterialModel> get materiaisMovimentacao => _materiaisMovimentacao;

  int _totalItensMovimentacao = 0;
  int get totalItensMovimentacao => _totalItensMovimentacao;

  bool _carregandoMovimentacao = false;
  bool get carregandoMovimentacao => _carregandoMovimentacao;

  Future<MateriaisPaginadosModel> buscarParaMovimentacao({
    String busca = '',
    String? categoria,
    String id = '',
    String identificador = '',
    String medida = '',
    String espessura = '',
    String largura = '',
    String comprimento = '',
    required int pagina,
    int porPagina = 50,
  }) async {
    _carregandoMovimentacao = true;
    notifyListeners();
    try {
      final resultado = await _repo.listarParaMovimentacao(
        busca:         busca.isEmpty         ? null : busca,
        id:            id.isEmpty            ? null : id,
        identificador: identificador.isEmpty ? null : identificador,
        medida:        medida.isEmpty        ? null : medida,
        espessura:     espessura.isEmpty     ? null : espessura,
        largura:       largura.isEmpty       ? null : largura,
        comprimento:   comprimento.isEmpty   ? null : comprimento,
        categoria:     categoria,
        pagina:        pagina,
        porPagina:     porPagina,
      );
      _materiaisMovimentacao  = resultado.itens;
      _totalItensMovimentacao = resultado.total;
      return resultado;
    } catch (_) {
      _materiaisMovimentacao  = [];
      _totalItensMovimentacao = 0;
      return const MateriaisPaginadosModel(itens: [], total: 0);
    } finally {
      _carregandoMovimentacao = false;
      notifyListeners();
    }
  }

  bool _criando = false;

  Future<bool> criar(Map<String, dynamic> dados) async {
    if (_criando) return false;
    _criando = true;
    try {
      await _repo.criar(dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'cadastrar material');
      notifyListeners();
      return false;
    } finally {
      _criando = false;
    }
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizar(id, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> desativar(int id) async {
    try {
      await _repo.desativar(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'desativar material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmarEstoque(int id) async {
    try {
      await _repo.confirmarEstoque(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'confirmar estoque');
      notifyListeners();
      return false;
    }
  }

  Future<bool> excluir(int id) async {
    try {
      await _repo.excluir(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'excluir material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> reativar(int id) async {
    try {
      await _repo.reativar(id);
      await carregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'reativar material');
      notifyListeners();
      return false;
    }
  }

  Future<List<MaterialModel>> buscarSugestoes(String busca, {int limite = 10, bool apenasAtivos = false}) async {
    try {
      return await _repo.listar(
        busca: busca,
        ativo: apenasAtivos ? true : null,
        limite: limite,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<HistoricoPrecoModel>> listarHistoricoPrecos(int materialId) async {
    try {
      return await _repo.listarHistoricoPrecos(materialId);
    } catch (_) {
      return [];
    }
  }

  Future<bool> atualizarCustoManual(
    int id, {
    double? ultimoValorPago,
    double? ultimoValorPagoM2,
  }) async {
    try {
      await _repo.atualizarCustoManual(
        id,
        ultimoValorPago:   ultimoValorPago,
        ultimoValorPagoM2: ultimoValorPagoM2,
      );
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar custo');
      notifyListeners();
      return false;
    }
  }
}