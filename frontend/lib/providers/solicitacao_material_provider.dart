import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/solicitacao_material_model.dart';
import '../repositories/solicitacao_material_repository.dart';
import '../utils/api_client.dart';

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
  final msg = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
  return 'Erro ao $acao: $msg';
}

class SolicitacaoMaterialProvider extends ChangeNotifier {
  final SolicitacaoMaterialRepository _repo = SolicitacaoMaterialRepository();
  SolicitacaoMaterialRepository get repository => _repo;

  List<SolicitacaoMaterialModel> _solicitacoes = [];
  List<SolicitacaoMaterialModel> get solicitacoes => _solicitacoes;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  String? _erroLocal;
  String? get erroLocal => _erroLocal;

  void limparErro() {
    if (_erro != null) {
      _erro = null;
      notifyListeners();
    }
  }

  List<LogEdicaoSolicitacaoModel> _logs = [];
  List<LogEdicaoSolicitacaoModel> get logs => _logs;
  bool _carregandoLogs = false;
  bool get carregandoLogs => _carregandoLogs;

  int _novasSolicitacoes = 0;
  int get novasSolicitacoes => _novasSolicitacoes;

  bool _paginaAberta = false;
  bool _visualizacaoPersistedaNaSessao = false;
  bool _notificacoesConectadas = false;
  bool get notificacoesConectadas => _notificacoesConectadas;

  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  Timer? _reconnectTimer;
  Timer? _pollingTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // ─── SSE ──────────────────────────────────

  Future<void> conectarNotificacoes() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _reconnectTimer?.cancel();
    _sseClient?.close();
    _sseClient = null;

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/api/solicitacoes-material/notificacoes');
      debugPrint('🔔 [Solicitações] Conectando ao SSE: $uri');

      final token = ApiClient.token;
      if (token == null) {
        debugPrint('⚠️ [Solicitações] Token não disponível para SSE');
        _scheduleReconnect();
        return;
      }

      _sseClient = http.Client();

      final req = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache'
        ..headers['Connection'] = 'keep-alive';

      final streamedResp = await _sseClient!.send(req);

      if (streamedResp.statusCode != 200) {
        debugPrint('❌ [Solicitações] SSE falhou com status ${streamedResp.statusCode}');
        _scheduleReconnect();
        return;
      }

      debugPrint('✅ [Solicitações] SSE conectado com sucesso');
      _notificacoesConectadas = true;
      _reconnectAttempts = 0;
      notifyListeners();

      if (_paginaAberta) {
        debugPrint('📖 [Solicitações] Reconexão com página aberta — re-persistindo visualizações');
        _novasSolicitacoes = 0;
        notifyListeners();
        _persistirVisualizacao();
      } else {
        await _carregarContagemInicial();
      }

      final stream = streamedResp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sseSub = stream.listen(
        _processarLinhaSSE,
        onError: (error) {
          debugPrint('❌ [Solicitações] Erro no SSE: $error');
          _notificacoesConectadas = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('⚠️ [Solicitações] SSE stream encerrado');
          _notificacoesConectadas = false;
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      _pollingTimer?.cancel();
      _pollingTimer = null;
    } catch (e) {
      debugPrint('❌ [Solicitações] Erro ao conectar SSE: $e');
      _notificacoesConectadas = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  Future<void> _carregarContagemInicial() async {
    if (_paginaAberta) {
      debugPrint('📖 [Solicitações] _carregarContagemInicial ignorado (página aberta)');
      _novasSolicitacoes = 0;
      notifyListeners();
      return;
    }

    try {
      final data = await ApiClient.get('/solicitacoes-material/novas/count');
      _novasSolicitacoes = data['count'] as int;
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar contagem inicial: $e');
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

        debugPrint('📨 [Solicitações] SSE recebido: tipo=$tipo');

        if (tipo == 'conectado') {
          debugPrint('✅ [Solicitações] Confirmação de conexão recebida');
          return;
        }

        if (tipo == 'nova_solicitacao') {
          _aoReceberNovaSolicitacao(data);
        }
      } catch (e) {
        debugPrint('❌ [Solicitações] Erro ao processar SSE: $e, linha: $linha');
      }
    }
  }

  void _aoReceberNovaSolicitacao(Map<String, dynamic> data) {
    debugPrint('🔔 [Solicitações] Nova solicitação recebida: ${data['numeroOS']}');

    if (_paginaAberta) {
      debugPrint('ℹ️ [Solicitações] Página aberta — recarregando lista');
      carregar();
      _persistirVisualizacao();
    } else {
      _novasSolicitacoes++;
      debugPrint('🔔 [Solicitações] Badge atualizado: $_novasSolicitacoes');
      notifyListeners();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('⚠️ [Solicitações] Máximo de tentativas atingido. Usando polling.');
      _iniciarPolling();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    debugPrint('🔄 [Solicitações] Reconectando SSE em ${delay.inSeconds}s (tentativa $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, conectarNotificacoes);
  }

  void _iniciarPolling() {
    _pollingTimer?.cancel();
    debugPrint('📊 [Solicitações] Iniciando polling a cada 30s como fallback');

    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_paginaAberta) return;

      try {
        final data = await ApiClient.get('/solicitacoes-material/novas/count');
        final novoCount = data['count'] as int;
        if (novoCount != _novasSolicitacoes) {
          _novasSolicitacoes = novoCount;
          debugPrint('🔔 [Solicitações] Polling: badge atualizado para $_novasSolicitacoes');
          notifyListeners();
        }
      } catch (e) {
        debugPrint('❌ [Solicitações] Erro no polling: $e');
      }
    });
  }

  // ─── Controle de página ────────────────────────────────────────────────────

  void marcarPaginaAberta() {
    if (_paginaAberta) return;
    debugPrint('📖 [Solicitações] Página marcada como aberta');
    _paginaAberta = true;

    if (_novasSolicitacoes != 0) {
      _novasSolicitacoes = 0;
      notifyListeners();
    }
  }

  Future<void> limparNotificacoes() async {
    _paginaAberta = true;

    if (_novasSolicitacoes != 0) {
      _novasSolicitacoes = 0;
      notifyListeners();
    }

    if (_visualizacaoPersistedaNaSessao) {
      debugPrint('✅ [Solicitações] Visualizações já persistidas nesta sessão — pulando');
      return;
    }

    debugPrint('🧹 [Solicitações] Persistindo visualizações no banco...');
    await _persistirVisualizacao();
  }

  Future<void> _persistirVisualizacao() async {
    try {
      await ApiClient.post('/solicitacoes-material/marcar-visualizadas', {});
      _visualizacaoPersistedaNaSessao = true;
      debugPrint('✅ [Solicitações] Visualizações persistidas no banco');
    } catch (e) {
      debugPrint('⚠️ [Solicitações] Erro ao persistir visualizações: $e');
    }
  }

  void sairDaPagina() {
    debugPrint('👋 [Solicitações] Usuário saiu da página');
    _paginaAberta = false;
    _visualizacaoPersistedaNaSessao = false;
  }

  Future<void> resetarConexao() async {
    debugPrint('🔄 [Solicitações] Resetando conexão e estado do provider');
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;

    _notificacoesConectadas = false;
    _paginaAberta = false;
    _visualizacaoPersistedaNaSessao = false;
    _novasSolicitacoes = 0;
    _solicitacoes = [];
    _logs = [];
    _erro = null;
    notifyListeners();
  }

  @override
  void dispose() {
    debugPrint('🗑️ [Solicitações] Dispose do provider');
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    super.dispose();
  }

  // ─── CRUD ──────────────────────────────────

  Future<void> carregar({
    String? busca,
    String? andamento,
    int? materialId,
    String? numeroOS,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _solicitacoes = await _repo.listar(
        busca: busca,
        andamento: andamento,
        materialId: materialId,
        numeroOS: numeroOS,
        dataInicio: dataInicio,
        dataFim: dataFim,
      );
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar solicitações');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<bool> criar(
    Map<String, dynamic> dados, {
    List<Map<String, dynamic>> itens = const [],
    Map<int, File> imagensPorIndice = const {},
  }) async {
    try {
      await _repo.criar(dados, itens: itens, imagensPorIndice: imagensPorIndice);
      await carregar();
      debugPrint('✅ [Solicitações] Solicitação criada com sucesso');
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'criar solicitação');
      notifyListeners();
      return false;
    }
  }

  Future<bool> criarSemCarregar(
    Map<String, dynamic> dados, {
    List<Map<String, dynamic>> itens = const [],
    Map<int, File> imagensPorIndice = const {},
  }) async {
    try {
      await _repo.criar(dados, itens: itens, imagensPorIndice: imagensPorIndice);
      debugPrint('✅ [Solicitações] Solicitação criada com sucesso');
      _erroLocal = null;
      return true;
    } catch (e) {
      _erroLocal = _mensagemErro(e, acao: 'criar solicitação');
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizar(id, dados);
      await carregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar solicitação');
      notifyListeners();
      return false;
    }
  }

  Future<bool> adicionarMateriais(
    int solicitacaoId, {
    required List<Map<String, dynamic>> itens,
    Map<int, File> imagensPorIndice = const {},
  }) async {
    try {
      await _repo.adicionarMateriais(
        solicitacaoId,
        itens: itens,
        imagensPorIndice: imagensPorIndice,
      );
      await carregar();
      debugPrint('✅ [Solicitações] Materiais adicionados com sucesso');
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'adicionar materiais');
      notifyListeners();
      return false;
    }
  }

  Future<void> marcarItemComprado(int itemId, {required bool comprado}) async {
    try {
      await _repo.marcarItemComprado(itemId, comprado: comprado);
      debugPrint('✅ [Solicitações] Item marcado como ${comprado ? 'comprado' : 'não comprado'}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> marcarAdicionalComprado(int adicionalId, {required bool comprado}) async {
    try {
      await _repo.marcarAdicionalComprado(adicionalId, comprado: comprado);
      debugPrint('✅ [Solicitações] Adicional marcado como ${comprado ? 'comprado' : 'não comprado'}');
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> excluir(int id) async {
    try {
      await _repo.excluir(id);
      await carregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'excluir solicitação');
      notifyListeners();
      return false;
    }
  }

  Future<void> carregarLogs(int solicitacaoId) async {
    _carregandoLogs = true;
    notifyListeners();
    try {
      _logs = await _repo.listarLogs(solicitacaoId);
    } catch (_) {
      _logs = [];
    } finally {
      _carregandoLogs = false;
      notifyListeners();
    }
  }
}