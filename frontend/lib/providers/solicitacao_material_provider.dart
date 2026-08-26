import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;
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

  int _carregarSeq = 0;

  Timer? _sseCarregarDebounce;
  void _carregarComDebounce() {
    _sseCarregarDebounce?.cancel();
    _sseCarregarDebounce = Timer(const Duration(milliseconds: 400), () {
      carregar(emSegundoPlano: true);
    });
  }

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

  NovaSolicitacaoNotificacao? _notificacaoPendente;
  NovaSolicitacaoNotificacao? get notificacaoPendente => _notificacaoPendente;

  void consumirNotificacaoPendente() {
    if (_notificacaoPendente == null) return;
    _notificacaoPendente = null;

  }

  SolicitacaoAlteradaNotificacao? _notificacaoAlteradaPendente;
  SolicitacaoAlteradaNotificacao? get notificacaoAlteradaPendente => _notificacaoAlteradaPendente;

  void consumirNotificacaoAlteradaPendente() {
    if (_notificacaoAlteradaPendente == null) return;
    _notificacaoAlteradaPendente = null;
  }

  int? _solicitacaoParaAbrirPendente;
  int? get solicitacaoParaAbrirPendente => _solicitacaoParaAbrirPendente;

  void solicitarAberturaSolicitacao(int solicitacaoId) {
    _solicitacaoParaAbrirPendente = solicitacaoId;
    notifyListeners();
  }

  void consumirSolicitacaoParaAbrirPendente() {
    _solicitacaoParaAbrirPendente = null;
  }

  Future<SolicitacaoMaterialModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar solicitação');
      notifyListeners();
      return null;
    }
  }

  Future<List<LogEdicaoSolicitacaoModel>> buscarLogsSemAlterarEstado(int solicitacaoId) async {
    try {
      return await _repo.listarLogs(solicitacaoId);
    } catch (_) {
      return [];
    }
  }

  bool _paginaAberta = false;
  bool _visualizacaoPersistedaNaSessao = false;
  bool _persistindoVisualizacao = false;
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

  Future<void> conectarNotificacoes() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _reconnectTimer?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;

    final meuId = ++_sseGeracao;
    debugPrint('[FECHAR][Solicitações] ${DateTime.now().toIso8601String()} — abrindo nova conexão SSE, geração $meuId');

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/api/solicitacoes-material/notificacoes');
      debugPrint('🔔 [Solicitações] Conectando ao SSE: $uri');

      final token = ApiClient.token;
      if (token == null) {
        debugPrint('⚠️ [Solicitações] Token não disponível para SSE');
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
        debugPrint('❌ [Solicitações] SSE falhou com status ${streamedResp.statusCode}');
        _scheduleReconnect(meuId);
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
          if (meuId != _sseGeracao) return;
          _notificacoesConectadas = false;
          notifyListeners();
          _scheduleReconnect(meuId);
        },
        onDone: () {
          debugPrint('⚠️ [Solicitações] SSE stream encerrado');
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
      debugPrint('❌ [Solicitações] Erro ao conectar SSE: $e');
      if (meuId != _sseGeracao) return;
      _notificacoesConectadas = false;
      notifyListeners();
      _scheduleReconnect(meuId);
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

        if (tipo == 'solicitacao_atualizada') {
          _aoReceberSolicitacaoAtualizada(data);
        }
      } catch (e) {
        debugPrint('❌ [Solicitações] Erro ao processar SSE: $e, linha: $linha');
      }
    }
  }

  void _aoReceberNovaSolicitacao(Map<String, dynamic> data) {
    debugPrint('🔔 [Solicitações] Nova solicitação recebida: ${data['numeroOS']}');

    try {
      _notificacaoPendente = NovaSolicitacaoNotificacao.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ [Solicitações] Falha ao ler payload da notificação: $e');
    }

    if (_paginaAberta) {
      debugPrint('ℹ️ [Solicitações] Página aberta — recarregando lista (debounced)');
      _carregarComDebounce();
      _persistirVisualizacao();
    } else {

      _carregarContagemInicial();
      debugPrint('🔔 [Solicitações] Nova solicitação com página fechada — ressincronizando badge');
    }
    notifyListeners();
  }

  void _aoReceberSolicitacaoAtualizada(Map<String, dynamic> data) {
    debugPrint('✏️ [Solicitações] Solicitação alterada: OS=${data['numeroOS']} acao=${data['acao']}');

    try {
      _notificacaoAlteradaPendente = SolicitacaoAlteradaNotificacao.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ [Solicitações] Falha ao ler payload de alteração: $e');
    }

    if (_paginaAberta) {
      _carregarComDebounce();
    }
    notifyListeners();
  }

  void _scheduleReconnect(int meuId) {
    if (meuId != _sseGeracao) return;
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

  void definirPaginaVisivel(bool visivel) {
    if (visivel == _paginaAberta) return;
    _paginaAberta = visivel;

    if (visivel) {
      if (_novasSolicitacoes != 0) {
        _novasSolicitacoes = 0;

        WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
      }

      if (_visualizacaoPersistedaNaSessao) {
        debugPrint('✅ [Solicitações] Visualizações já persistidas nesta sessão — pulando');
      } else {
        debugPrint('🧹 [Solicitações] Persistindo visualizações no banco (primeira vez na sessão)...');
        _persistirVisualizacao();
      }
    }

  }

  Future<void> _persistirVisualizacao() async {
    if (_persistindoVisualizacao) {
      debugPrint('⏳ [Solicitações] Persistência de visualização já em andamento — pulando chamada duplicada');
      return;
    }
    _persistindoVisualizacao = true;
    try {
      await ApiClient.post('/solicitacoes-material/marcar-visualizadas', {});
      _visualizacaoPersistedaNaSessao = true;
      debugPrint('✅ [Solicitações] Visualizações persistidas no banco');
    } catch (e) {
      debugPrint('⚠️ [Solicitações] Erro ao persistir visualizações: $e');
    } finally {
      _persistindoVisualizacao = false;
    }
  }

  Future<void> resetarConexao() async {
    debugPrint('🔄 [Solicitações] Resetando conexão e estado do provider');
    _sseGeracao++;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _sseCarregarDebounce?.cancel();
    _sseCarregarDebounce = null;
    await _sseSub?.cancel();
    _sseSub = null;
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;

    _notificacoesConectadas = false;
    _paginaAberta = false;
    _visualizacaoPersistedaNaSessao = false;
    _novasSolicitacoes = 0;
    _notificacaoPendente = null;
    _notificacaoAlteradaPendente = null;
    _solicitacoes = [];
    _logs = [];
    _erro = null;
    notifyListeners();
  }

  void encerrarConexaoSSE() {
    debugPrint('[FECHAR][Solicitações] ${DateTime.now().toIso8601String()} — encerrarConexaoSSE chamado, geração $_sseGeracao -> ${_sseGeracao + 1}');
    _sseGeracao++;
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _sseCarregarDebounce?.cancel();
    _sseSub?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;
  }

  @override
  void dispose() {
    debugPrint('🗑️ [Solicitações] Dispose do provider');
    _sseGeracao++;
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _sseCarregarDebounce?.cancel();
    _sseSub?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _sseClient = null;
    super.dispose();
  }

  int _carregandoSeq = 0;

  Future<void> carregar({
    String? busca,
    String? andamento,
    int? materialId,
    String? numeroOS,
    DateTime? dataInicio,
    DateTime? dataFim,

    bool emSegundoPlano = false,
  }) async {
    final minhaSeq = ++_carregarSeq;
    int? minhaCarregandoSeq;
    if (!emSegundoPlano) {
      minhaCarregandoSeq = ++_carregandoSeq;
      _carregando = true;

      final seqDoWatchdog = minhaCarregandoSeq;
      Timer(const Duration(seconds: 20), () {
        if (seqDoWatchdog == _carregandoSeq && _carregando) {
          debugPrint('⚠️ [Solicitações] Watchdog: destravando spinner preso após 20s');
          _carregando = false;
          notifyListeners();
        }
      });
    }
    _erro = null;
    notifyListeners();
    try {
      final resultado = await _repo.listar(
        busca: busca,
        andamento: andamento,
        materialId: materialId,
        numeroOS: numeroOS,
        dataInicio: dataInicio,
        dataFim: dataFim,
      );

      if (minhaSeq != _carregarSeq) return;
      _solicitacoes = resultado;
    } catch (e) {
      if (minhaSeq != _carregarSeq) return;

      if (!emSegundoPlano) {
        _erro = _mensagemErro(e, acao: 'carregar solicitações');
      }
    } finally {
      if (minhaSeq == _carregarSeq) {
        notifyListeners();
      }

      if (minhaCarregandoSeq != null && minhaCarregandoSeq == _carregandoSeq) {
        _carregando = false;
        notifyListeners();
      }
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

  Future<void> _resincronizarSolicitacaoDoItem({int? itemId, int? adicionalId}) async {
    final idx = _solicitacoes.indexWhere((s) =>
        (itemId != null && s.itens.any((i) => i.id == itemId)) ||
        (adicionalId != null && s.adicionais.any((a) => a.id == adicionalId)));
    if (idx == -1) return;
    try {
      final atualizada = await _repo.buscarPorId(_solicitacoes[idx].id);
      _solicitacoes[idx] = atualizada;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [Solicitações] Falha ao ressincronizar solicitação: $e');
    }
  }

  Future<void> marcarItemComprado(int itemId, {required bool comprado}) async {
    try {
      await _repo.marcarItemComprado(itemId, comprado: comprado);
      await _resincronizarSolicitacaoDoItem(itemId: itemId);
      debugPrint('✅ [Solicitações] Item marcado como ${comprado ? 'comprado' : 'não comprado'}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> marcarAdicionalComprado(int adicionalId, {required bool comprado}) async {
    try {
      await _repo.marcarAdicionalComprado(adicionalId, comprado: comprado);
      await _resincronizarSolicitacaoDoItem(adicionalId: adicionalId);
      debugPrint('✅ [Solicitações] Adicional marcado como ${comprado ? 'comprado' : 'não comprado'}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> marcarItemEstoque(int itemId, {required bool estoque}) async {
    try {
      await _repo.marcarItemEstoque(itemId, estoque: estoque);
      await _resincronizarSolicitacaoDoItem(itemId: itemId);
      debugPrint('✅ [Solicitações] Item marcado como ${estoque ? 'estoque' : 'não estoque'}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> marcarAdicionalEstoque(int adicionalId, {required bool estoque}) async {
    try {
      await _repo.marcarAdicionalEstoque(adicionalId, estoque: estoque);
      await _resincronizarSolicitacaoDoItem(adicionalId: adicionalId);
      debugPrint('✅ [Solicitações] Adicional marcado como ${estoque ? 'estoque' : 'não estoque'}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> atualizarItem(int itemId, {required double quantidade, String? observacao}) async {
    try {
      await _repo.atualizarItem(itemId, quantidade: quantidade, observacao: observacao);
      await _resincronizarSolicitacaoDoItem(itemId: itemId);
      debugPrint('✅ [Solicitações] Item atualizado');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> atualizarAdicional(int adicionalId, {required double quantidade, String? observacao}) async {
    try {
      await _repo.atualizarAdicional(adicionalId, quantidade: quantidade, observacao: observacao);
      await _resincronizarSolicitacaoDoItem(adicionalId: adicionalId);
      debugPrint('✅ [Solicitações] Adicional atualizado');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> excluirItem(int itemId) async {
    try {
      final idx = _solicitacoes.indexWhere((s) => s.itens.any((i) => i.id == itemId));
      final solicitacaoId = idx != -1 ? _solicitacoes[idx].id : null;
      await _repo.excluirItem(itemId);
      if (solicitacaoId != null) {
        final atualizada = await _repo.buscarPorId(solicitacaoId);
        final i = _solicitacoes.indexWhere((s) => s.id == solicitacaoId);
        if (i != -1) {
          _solicitacoes[i] = atualizada;
          notifyListeners();
        }
      }
      debugPrint('✅ [Solicitações] Item excluído');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> excluirAdicional(int adicionalId) async {
    try {
      final idx = _solicitacoes.indexWhere((s) => s.adicionais.any((a) => a.id == adicionalId));
      final solicitacaoId = idx != -1 ? _solicitacoes[idx].id : null;
      await _repo.excluirAdicional(adicionalId);
      if (solicitacaoId != null) {
        final atualizada = await _repo.buscarPorId(solicitacaoId);
        final i = _solicitacoes.indexWhere((s) => s.id == solicitacaoId);
        if (i != -1) {
          _solicitacoes[i] = atualizada;
          notifyListeners();
        }
      }
      debugPrint('✅ [Solicitações] Adicional excluído');
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