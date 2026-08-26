import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;

import '../models/mensagem_chat_model.dart';
import '../utils/api_client.dart';

class ChatProvider extends ChangeNotifier {
  final List<UsuarioChat> _usuarios = [];
  final Map<int, List<MensagemChat>> _conversas = {};
  int? _usuarioAtivoId;

  bool _paginaChatVisivel       = false;
  bool _widgetFlutuanteVisivel  = false;
  bool _carregandoUsuarios = false;
  bool _carregandoMensagens = false;
  int _totalNaoLidas = 0;
  String? _erroUsuarios;
  StreamSubscription<String>? _sseSub;
  HttpClient? _sseRawClient;
  bool _disposed = false;
  int _sseConexaoId = 0;
  int? _meuId;

  Timer? _heartbeatTimer;
  static const _heartbeatIntervalo = Duration(seconds: 20);

  List<UsuarioChat> get usuarios          => List.unmodifiable(_usuarios);
  int?             get usuarioAtivoId     => _usuarioAtivoId;
  bool             get paginaChatVisivel  => _paginaChatVisivel || _widgetFlutuanteVisivel;
  bool             get carregandoUsuarios => _carregandoUsuarios;
  bool             get carregandoMensagens=> _carregandoMensagens;
  int              get totalNaoLidas      => _totalNaoLidas;
  int?             get meuId              => _meuId;
  String?          get erroUsuarios       => _erroUsuarios;

  int _minimizarTrigger = 0;
  int              get minimizarTrigger   => _minimizarTrigger;

  int _abrirConversaTrigger = 0;
  int              get abrirConversaTrigger => _abrirConversaTrigger;

  static const _digitandoExpira = Duration(seconds: 3);
  final Map<int, Timer> _digitandoTimers = {};
  final Set<int> _usuariosDigitando = {};

  bool estaDigitando(int usuarioId) => _usuariosDigitando.contains(usuarioId);

  void _marcarDigitando(int usuarioId) {
    _usuariosDigitando.add(usuarioId);
    _digitandoTimers[usuarioId]?.cancel();
    _digitandoTimers[usuarioId] = Timer(_digitandoExpira, () {
      _usuariosDigitando.remove(usuarioId);
      notifyListeners();
    });
    notifyListeners();
  }

  DateTime? _ultimoPingDigitando;
  Future<void> notificarDigitando() async {
    if (_usuarioAtivoId == null) return;
    final agora = DateTime.now();
    if (_ultimoPingDigitando != null &&
        agora.difference(_ultimoPingDigitando!) < const Duration(seconds: 2)) {
      return;
    }
    _ultimoPingDigitando = agora;
    try {
      await ApiClient.post('/chat/typing', {
        'destinatarioId': _usuarioAtivoId,
      });
    } catch (e) {

      debugPrint('ChatProvider.notificarDigitando erro: $e');
    }
  }

  void minimizarWidgetFlutuante() {
    _minimizarTrigger++;
    notifyListeners();
  }

  Future<void> solicitarAberturaConversa(int usuarioId) async {
    await abrirConversa(usuarioId);
    _abrirConversaTrigger++;
    notifyListeners();
  }

  List<MensagemChat> conversaAtual() {
    if (_usuarioAtivoId == null) return [];
    return _conversas[_usuarioAtivoId] ?? [];
  }

  UsuarioChat? usuarioPorId(int id) {
    for (final u in _usuarios) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<void> inicializar(int meuId, String token) async {
    _meuId = meuId;
    await carregarUsuarios();
    _conectarSSE();
    _iniciarHeartbeat();
  }

  void _iniciarHeartbeat() {
    _heartbeatTimer?.cancel();
    _enviarHeartbeat();
    _heartbeatTimer = Timer.periodic(
      _heartbeatIntervalo,
      (_) => _enviarHeartbeat(),
    );
  }

  Future<void> _enviarHeartbeat() async {
    if (_meuId == null) return;
    try {
      await ApiClient.post('/chat/heartbeat', {});
    } catch (e) {

      debugPrint('ChatProvider._enviarHeartbeat erro: $e');
    }
  }

  Future<void> carregarUsuarios() async {
    _carregandoUsuarios = true;
    _erroUsuarios = null;
    notifyListeners();
    try {

      final data = await ApiClient.getList('/chat/usuarios');
      _usuarios
        ..clear()
        ..addAll(data.map((e) => UsuarioChat.fromJson(e as Map<String, dynamic>)));
      _atualizarTotalNaoLidas();
    } catch (e) {
      _erroUsuarios = e.toString().replaceFirst('Exception: ', '');
      debugPrint('ChatProvider.carregarUsuarios erro: $e');
    } finally {
      _carregandoUsuarios = false;
      notifyListeners();
    }
  }

  Future<void> abrirConversa(int outroId) async {
    _usuarioAtivoId = outroId;
    notifyListeners();
    await _carregarConversa(outroId);

    final idx = _usuarios.indexWhere((u) => u.id == outroId);
    if (idx != -1) {
      _usuarios[idx].naoLidas = 0;
      _atualizarTotalNaoLidas();
      notifyListeners();
    }
  }

  void fecharConversa() {
    _usuarioAtivoId = null;
    notifyListeners();
  }

  void definirPaginaVisivel(bool visivel) {
    _paginaChatVisivel = visivel;
  }

  void definirWidgetFlutuanteVisivel(bool visivel) {
    _widgetFlutuanteVisivel = visivel;
  }

  Future<void> _carregarConversa(int outroId) async {
    _carregandoMensagens = true;
    notifyListeners();
    try {
      final data = await ApiClient.getList('/chat/conversa/$outroId');
      _conversas[outroId] = data
          .map((e) => MensagemChat.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('ChatProvider._carregarConversa erro: $e');
    } finally {
      _carregandoMensagens = false;
      notifyListeners();
    }
  }

  Future<void> enviarMensagem(String conteudo, {MensagemChat? respondendoA}) async {
    if (_usuarioAtivoId == null || conteudo.trim().isEmpty) return;
    final destinatarioId = _usuarioAtivoId!;
    final texto = conteudo.trim();

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final otimista = MensagemChat(
      id: tempId,
      remetenteId: _meuId ?? 0,
      destinatarioId: destinatarioId,
      conteudo: texto,
      lida: false,
      criadoEm: DateTime.now(),
      pendente: true,
      respondendoAId: respondendoA?.id,
      respondendoAConteudo: respondendoA?.conteudo,
      respondendoARemetenteNome: respondendoA?.remetenteId == _meuId
          ? 'Você'
          : respondendoA?.remetenteNome,
    );
    _adicionarMensagem(otimista);

    try {
      final data = await ApiClient.post('/chat/mensagem', {
        'destinatarioId': destinatarioId,
        'conteudo':       texto,
        if (respondendoA != null) 'respondendoAId': respondendoA.id,
      });
      final msg = MensagemChat.fromJson(data);
      _removerMensagem(destinatarioId, tempId);
      _adicionarMensagem(msg);
    } catch (e) {
      debugPrint('ChatProvider.enviarMensagem erro: $e');

      _removerMensagem(destinatarioId, tempId);
    }
  }

  Future<void> enviarEncaminhamento({
    required int destinatarioId,
    required String tipo,
    required Map<String, dynamic> dados,
  }) async {
    final conteudo = MensagemChat.codificarEncaminhamento(tipo: tipo, dados: dados);

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final otimista = MensagemChat(
      id: tempId,
      remetenteId: _meuId ?? 0,
      destinatarioId: destinatarioId,
      conteudo: conteudo,
      lida: false,
      criadoEm: DateTime.now(),
      pendente: true,
    );
    _adicionarMensagem(otimista);

    try {
      final data = await ApiClient.post('/chat/mensagem', {
        'destinatarioId': destinatarioId,
        'conteudo':       conteudo,
      });
      final msg = MensagemChat.fromJson(data);
      _removerMensagem(destinatarioId, tempId);
      _adicionarMensagem(msg);
    } catch (e) {
      debugPrint('ChatProvider.enviarEncaminhamento erro: $e');
      _removerMensagem(destinatarioId, tempId);
      rethrow;
    }
  }

  void _removerMensagem(int outroId, int id) {
    final lista = _conversas[outroId];
    if (lista == null) return;
    lista.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  Future<void> reagirMensagem(MensagemChat mensagem, String? emoji) async {
    final outroId = mensagem.remetenteId == _meuId
        ? mensagem.destinatarioId
        : mensagem.remetenteId;

    final reacoesOtimistas = Map<String, String>.from(mensagem.reacoes);
    if (_meuId != null) {
      if (emoji != null) {
        reacoesOtimistas[_meuId.toString()] = emoji;
      } else {
        reacoesOtimistas.remove(_meuId.toString());
      }
    }
    _substituirMensagem(
      outroId,
      mensagem.copyComReacoes(reacoesOtimistas),
    );

    try {
      final data = await ApiClient.patch(
        '/chat/mensagem/${mensagem.id}/reacao',
        {'emoji': emoji},
      );
      _substituirMensagem(outroId, MensagemChat.fromJson(data));
    } catch (e) {
      debugPrint('ChatProvider.reagirMensagem erro: $e');

      _substituirMensagem(outroId, mensagem);
    }
  }

  Future<void> editarMensagem(MensagemChat mensagem, String novoConteudo) async {
    final texto = novoConteudo.trim();
    if (texto.isEmpty || texto == mensagem.conteudo) return;

    final outroId = mensagem.remetenteId == _meuId
        ? mensagem.destinatarioId
        : mensagem.remetenteId;

    final otimista = MensagemChat(
      id: mensagem.id,
      remetenteId: mensagem.remetenteId,
      destinatarioId: mensagem.destinatarioId,
      conteudo: texto,
      lida: mensagem.lida,
      criadoEm: mensagem.criadoEm,
      remetenteNome: mensagem.remetenteNome,
      destinatarioNome: mensagem.destinatarioNome,
      reacoes: mensagem.reacoes,
      editadaEm: DateTime.now(),
      apagada: mensagem.apagada,
      pendente: mensagem.pendente,
      respondendoAId: mensagem.respondendoAId,
      respondendoAConteudo: mensagem.respondendoAConteudo,
      respondendoARemetenteNome: mensagem.respondendoARemetenteNome,
    );
    _substituirMensagem(outroId, otimista);

    try {
      final data = await ApiClient.patch(
        '/chat/mensagem/${mensagem.id}',
        {'conteudo': texto},
      );
      _substituirMensagem(outroId, MensagemChat.fromJson(data));
    } catch (e) {
      debugPrint('ChatProvider.editarMensagem erro: $e');

      _substituirMensagem(outroId, mensagem);
      rethrow;
    }
  }

  Future<void> excluirMensagem(MensagemChat mensagem) async {
    final outroId = mensagem.remetenteId == _meuId
        ? mensagem.destinatarioId
        : mensagem.remetenteId;

    final otimista = MensagemChat(
      id: mensagem.id,
      remetenteId: mensagem.remetenteId,
      destinatarioId: mensagem.destinatarioId,
      conteudo: '',
      lida: mensagem.lida,
      criadoEm: mensagem.criadoEm,
      remetenteNome: mensagem.remetenteNome,
      destinatarioNome: mensagem.destinatarioNome,
      reacoes: const {},
      editadaEm: mensagem.editadaEm,
      apagada: true,
      pendente: mensagem.pendente,
      respondendoAId: mensagem.respondendoAId,
      respondendoAConteudo: mensagem.respondendoAConteudo,
      respondendoARemetenteNome: mensagem.respondendoARemetenteNome,
    );
    _substituirMensagem(outroId, otimista);

    try {

      await ApiClient.delete('/chat/mensagem/${mensagem.id}');
    } catch (e) {
      debugPrint('ChatProvider.excluirMensagem erro: $e');
      _substituirMensagem(outroId, mensagem);
      rethrow;
    }
  }

  void _substituirMensagem(int outroId, MensagemChat atualizada) {
    final lista = _conversas[outroId];
    if (lista == null) return;
    final idx = lista.indexWhere((m) => m.id == atualizada.id);
    if (idx == -1) return;
    lista[idx] = atualizada;
    notifyListeners();
  }

  void _adicionarMensagem(MensagemChat msg) {
    final outroId = msg.remetenteId == _meuId
        ? msg.destinatarioId
        : msg.remetenteId;

    _conversas.putIfAbsent(outroId, () => []);

    if (_conversas[outroId]!.any((m) => m.id == msg.id)) return;
    _conversas[outroId]!.add(msg);
    notifyListeners();
  }

  void _conectarSSE() {
    if (_disposed) return;
    _sseSub?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    final token = ApiClient.token;
    if (token == null) return;

    final meuId = ++_sseConexaoId;
    debugPrint('[FECHAR][Chat] ${DateTime.now().toIso8601String()} — abrindo nova conexão SSE, geração $meuId');

    final uri = Uri.parse('${ApiClient.baseUrl}/api/chat/sse');

    final rawClient = HttpClient();
    _sseRawClient = rawClient;
    final client = io_client.IOClient(rawClient);

    final req = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept']        = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';

    client.send(req).then((streamedResp) {
      if (_disposed || meuId != _sseConexaoId) {
        rawClient.close(force: true);
        return;
      }
      final stream = streamedResp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sseSub = stream.listen(
        _processarLinhaSSE,
        onError: (e) {
          debugPrint('SSE erro: $e');
          if (!_disposed && meuId == _sseConexaoId) {
            Future.delayed(const Duration(seconds: 5), _conectarSSE);
          }
        },
        onDone: () {
          if (!_disposed && meuId == _sseConexaoId) {
            Future.delayed(const Duration(seconds: 5), _conectarSSE);
          }
        },
      );
    }).catchError((e) {
      debugPrint('SSE connect erro: $e');
      if (!_disposed && meuId == _sseConexaoId) {
        Future.delayed(const Duration(seconds: 5), _conectarSSE);
      }
    });
  }

  String _sseBuffer = '';

  void _processarLinhaSSE(String linha) {
    if (linha.startsWith('data: ')) {
      _sseBuffer = linha.substring(6);
      try {
        final data = jsonDecode(_sseBuffer) as Map<String, dynamic>;
        final tipo = data['tipo'] as String?;

        if (tipo == 'nova_mensagem' || tipo == 'mensagem_enviada') {
          final msg = MensagemChat.fromJson(
              data['mensagem'] as Map<String, dynamic>);
          _adicionarMensagem(msg);

          final estaVendoEssaConversa =
              paginaChatVisivel && msg.remetenteId == _usuarioAtivoId;
          if (tipo == 'nova_mensagem' && !estaVendoEssaConversa) {
            final idx = _usuarios.indexWhere((u) => u.id == msg.remetenteId);
            if (idx != -1) {
              _usuarios[idx].naoLidas++;
              _atualizarTotalNaoLidas();
              notifyListeners();
            }
          }
        } else if (tipo == 'digitando') {
          final remetenteId = data['remetenteId'] as int?;
          if (remetenteId != null) _marcarDigitando(remetenteId);
        } else if (tipo == 'usuario_online') {
          final uid = data['usuarioId'] as int?;
          if (uid != null) {
            final idx = _usuarios.indexWhere((u) => u.id == uid);
            if (idx != -1) {
              _usuarios[idx].online = true;
              notifyListeners();
            }
          }
        } else if (tipo == 'usuario_offline') {
          final uid = data['usuarioId'] as int?;
          if (uid != null) {
            final idx = _usuarios.indexWhere((u) => u.id == uid);
            if (idx != -1) {
              _usuarios[idx].online = false;
              final ultimo = data['ultimoAcesso'] as String?;
              if (ultimo != null) {
                _usuarios[idx].ultimoAcesso = DateTime.parse(ultimo).toLocal();
              }
              notifyListeners();
            }
          }
        } else if (tipo == 'reacao_atualizada' ||
            tipo == 'mensagem_editada' ||
            tipo == 'mensagem_apagada') {
          final msg = MensagemChat.fromJson(
              data['mensagem'] as Map<String, dynamic>);
          final outroId = msg.remetenteId == _meuId
              ? msg.destinatarioId
              : msg.remetenteId;
          _substituirMensagem(outroId, msg);
        }
        _sseBuffer = '';
      } catch (_) {}
    }
  }

  void _atualizarTotalNaoLidas() {
    _totalNaoLidas = _usuarios.fold(0, (sum, u) => sum + u.naoLidas);
  }

  void limparToken() {
    _meuId = null;
    _sseConexaoId++;
    _sseSub?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _heartbeatTimer?.cancel();
    _usuarios.clear();
    _conversas.clear();
    _usuarioAtivoId = null;
    _totalNaoLidas = 0;
    for (final t in _digitandoTimers.values) {
      t.cancel();
    }
    _digitandoTimers.clear();
    _usuariosDigitando.clear();

    notifyListeners();
  }

  void encerrarConexaoSSE() {
    debugPrint('[FECHAR][Chat] ${DateTime.now().toIso8601String()} — encerrarConexaoSSE chamado, geração $_sseConexaoId -> ${_sseConexaoId + 1}');
    _sseConexaoId++;
    _sseSub?.cancel();
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
  }

  @override
  void dispose() {
    _disposed = true;
    encerrarConexaoSSE();
    _heartbeatTimer?.cancel();
    for (final t in _digitandoTimers.values) {
      t.cancel();
    }
    super.dispose();
  }
}