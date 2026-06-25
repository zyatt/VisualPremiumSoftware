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

  List<SolicitacaoMaterialModel> _solicitacoes = [];
  List<SolicitacaoMaterialModel> get solicitacoes => _solicitacoes;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  List<LogEdicaoSolicitacaoModel> _logs = [];
  List<LogEdicaoSolicitacaoModel> get logs => _logs;
  bool _carregandoLogs = false;
  bool get carregandoLogs => _carregandoLogs;

  int _novasSolicitacoes = 0;
  int get novasSolicitacoes => _novasSolicitacoes;

  // true enquanto o usuário está vendo a página de solicitações
  bool _paginaAberta = false;

  // true após limparNotificacoes() ter persistido com sucesso no banco
  // (evita que _carregarContagemInicial restaure o badge enquanto a
  // persistência ainda está em andamento ou já foi feita nesta sessão)
  bool _visualizacaoPersistedaNaSessao = false;

  bool _notificacoesConectadas = false;
  bool get notificacoesConectadas => _notificacoesConectadas;

  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  Timer? _reconnectTimer;
  Timer? _pollingTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // ─── SSE ──────────────────────────────────────────────────────────────────

  Future<void> conectarNotificacoes() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _reconnectTimer?.cancel();
    _sseClient?.close();
    _sseClient = null;

    try {
      final uri = Uri.parse(
          '${ApiClient.baseUrl}/api/solicitacoes-material/notificacoes');
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
        debugPrint(
            '❌ [Solicitações] SSE falhou com status ${streamedResp.statusCode}');
        _scheduleReconnect();
        return;
      }

      debugPrint('✅ [Solicitações] SSE conectado com sucesso');
      _notificacoesConectadas = true;
      _reconnectAttempts = 0;
      notifyListeners();

      // FIX: Se a página está aberta no momento da reconexão (ex.: API reiniciou),
      // re-persiste as visualizações no banco e mantém badge em 0.
      // Caso contrário, carrega a contagem real do banco.
      if (_paginaAberta) {
        debugPrint(
            '📖 [Solicitações] Reconexão com página aberta — re-persistindo visualizações');
        _novasSolicitacoes = 0;
        notifyListeners();
        // Re-persiste de forma assíncrona para garantir que o banco fique
        // sincronizado mesmo após um restart da API.
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
    // FIX: Se a página está aberta, não restaura o badge do banco.
    // O usuário já está vendo as solicitações — o badge deve ser 0.
    if (_paginaAberta) {
      debugPrint(
          '📖 [Solicitações] _carregarContagemInicial ignorado (página aberta)');
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
    debugPrint(
        '🔔 [Solicitações] Nova solicitação recebida: ${data['numeroOS']}');

    if (_paginaAberta) {
      // Usuário está na página — recarrega a lista e mantém badge em 0
      debugPrint('ℹ️ [Solicitações] Página aberta — recarregando lista');
      carregar();
      // Marca a nova solicitação como visualizada imediatamente
      _persistirVisualizacao();
    } else {
      // Usuário fora da página — incrementa badge
      _novasSolicitacoes++;
      debugPrint('🔔 [Solicitações] Badge atualizado: $_novasSolicitacoes');
      notifyListeners();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint(
          '⚠️ [Solicitações] Máximo de tentativas atingido. Usando polling.');
      _iniciarPolling();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    debugPrint(
        '🔄 [Solicitações] Reconectando SSE em ${delay.inSeconds}s (tentativa $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, conectarNotificacoes);
  }

  void _iniciarPolling() {
    _pollingTimer?.cancel();
    debugPrint('📊 [Solicitações] Iniciando polling a cada 30s como fallback');

    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      // FIX: polling também deve respeitar _paginaAberta
      if (_paginaAberta) return;

      try {
        final data = await ApiClient.get('/solicitacoes-material/novas/count');
        final novoCount = data['count'] as int;
        if (novoCount != _novasSolicitacoes) {
          _novasSolicitacoes = novoCount;
          debugPrint(
              '🔔 [Solicitações] Polling: badge atualizado para $_novasSolicitacoes');
          notifyListeners();
        }
      } catch (e) {
        debugPrint('❌ [Solicitações] Erro no polling: $e');
      }
    });
  }

  // ─── Controle de página ────────────────────────────────────────────────────

  /// Chamado assim que o widget é inserido na árvore (didChangeDependencies),
  /// ANTES do postFrameCallback. Isso garante que _paginaAberta = true antes
  /// de qualquer evento SSE ser processado enquanto a página está visível.
  void marcarPaginaAberta() {
    if (_paginaAberta) return;
    debugPrint('📖 [Solicitações] Página marcada como aberta');
    _paginaAberta = true;

    // FIX: ao marcar a página como aberta, zera o badge imediatamente
    // (sem esperar o postFrameCallback de limparNotificacoes), evitando
    // que um evento SSE que chegue nesse intervalo incremente o badge.
    if (_novasSolicitacoes != 0) {
      _novasSolicitacoes = 0;
      notifyListeners();
    }
  }

  /// Chamado no initState (postFrameCallback) para zerar badge e persistir.
  /// Separado de marcarPaginaAberta() para que a flag de página seja setada
  /// imediatamente, mas a limpeza do badge (que envolve I/O) venha depois.
  Future<void> limparNotificacoes() async {
    _paginaAberta = true; // redundante mas garante

    // FIX: zera localmente antes de aguardar a persistência para que a UI
    // atualize imediatamente, e só persiste se ainda não foi feito nesta sessão.
    if (_novasSolicitacoes != 0) {
      _novasSolicitacoes = 0;
      notifyListeners();
    }

    if (_visualizacaoPersistedaNaSessao) {
      debugPrint(
          '✅ [Solicitações] Visualizações já persistidas nesta sessão — pulando');
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
      // FIX: não marca como persistido em caso de erro — será tentado novamente
      // na próxima reconexão SSE ou quando o usuário voltar à página.
    }
  }

  /// Chamado quando o usuário sai da página (dispose do widget).
  void sairDaPagina() {
    debugPrint('👋 [Solicitações] Usuário saiu da página');
    _paginaAberta = false;
    // FIX: reseta o flag de persistência ao sair da página, para que ao
    // retornar (com possíveis novas solicitações no intervalo) a persistência
    // seja feita novamente.
    _visualizacaoPersistedaNaSessao = false;
  }

  /// Chamado no logout para encerrar SSE e zerar estado.
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

  // ─── CRUD ──────────────────────────────────────────────────────────────────

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

  Future<bool> criar(Map<String, dynamic> dados, {File? imagem}) async {
    try {
      await _repo.criar(dados, imagem: imagem);
      await carregar();
      debugPrint('✅ [Solicitações] Solicitação criada com sucesso');
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'criar solicitação');
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados,
      {File? imagem}) async {
    try {
      await _repo.atualizar(id, dados, imagem: imagem);
      await carregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar solicitação');
      notifyListeners();
      return false;
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