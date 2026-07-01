// lib/providers/chat_provider.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/mensagem_chat_model.dart';
import '../utils/api_client.dart';

class ChatProvider extends ChangeNotifier {
  final List<UsuarioChat> _usuarios = [];
  final Map<int, List<MensagemChat>> _conversas = {};
  int? _usuarioAtivoId;
  // Duas fontes independentes podem fazer o usuário "estar vendo o chat":
  // a página /chat inteira, ou o mini-chat do widget flutuante. Qualquer
  // uma das duas, se ativa, conta como "vendo" para fins de badge.
  bool _paginaChatVisivel       = false;
  bool _widgetFlutuanteVisivel  = false;
  bool _carregandoUsuarios = false;
  bool _carregandoMensagens = false;
  int _totalNaoLidas = 0;
  String? _erroUsuarios;
  StreamSubscription<String>? _sseSub;
  int? _meuId;

  List<UsuarioChat> get usuarios          => List.unmodifiable(_usuarios);
  int?             get usuarioAtivoId     => _usuarioAtivoId;
  bool             get paginaChatVisivel  => _paginaChatVisivel || _widgetFlutuanteVisivel;
  bool             get carregandoUsuarios => _carregandoUsuarios;
  bool             get carregandoMensagens=> _carregandoMensagens;
  int              get totalNaoLidas      => _totalNaoLidas;
  int?             get meuId              => _meuId;
  String?          get erroUsuarios       => _erroUsuarios;

  // Contador incrementado toda vez que algo externo (ex: troca de usuário
  // logado) precisa forçar o mini-chat flutuante a minimizar. O
  // ChatFloatingWidget observa esse valor e, ao perceber que mudou,
  // recolhe-se sozinho — o provider não tem referência direta ao widget.
  int _minimizarTrigger = 0;
  int              get minimizarTrigger   => _minimizarTrigger;

  /// Pede para o mini-chat flutuante (bolha) recolher, se estiver expandido.
  /// Usado, por exemplo, ao trocar de usuário logado, para não deixar a
  /// conversa de um usuário aberta na tela depois da troca.
  void minimizarWidgetFlutuante() {
    _minimizarTrigger++;
    notifyListeners();
  }

  List<MensagemChat> conversaAtual() {
    if (_usuarioAtivoId == null) return [];
    return _conversas[_usuarioAtivoId] ?? [];
  }

  // ApiClient já injeta o header Authorization a partir do token logado;
  // não precisamos mais ler o SharedPreferences aqui.

  Future<void> inicializar(int meuId, String token) async {
    _meuId = meuId;
    await carregarUsuarios();
    _conectarSSE();
  }

  Future<void> carregarUsuarios() async {
    _carregandoUsuarios = true;
    _erroUsuarios = null;
    notifyListeners();
    try {
      // ApiClient._uri já adiciona o prefixo /api, então aqui usamos só /chat/...
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

    // Zera badge local
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

  /// Chamado pelo AppShell a cada troca de rota, com base na localização atual.
  /// Não confundir com `usuarioAtivoId`: aquele indica qual conversa está
  /// selecionada e continua valendo mesmo fora da tela; este indica se a
  /// página /chat de fato está na frente do usuário agora.
  void definirPaginaVisivel(bool visivel) {
    _paginaChatVisivel = visivel;
  }

  /// Chamado pelo widget flutuante quando o mini-chat é expandido/recolhido.
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

  Future<void> enviarMensagem(String conteudo) async {
    if (_usuarioAtivoId == null || conteudo.trim().isEmpty) return;
    final destinatarioId = _usuarioAtivoId!;
    final texto = conteudo.trim();

    // Id temporário negativo (nunca colide com ids reais do banco) para
    // identificar a mensagem otimista e poder trocá-la depois pela
    // confirmada vinda do servidor.
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final otimista = MensagemChat(
      id: tempId,
      remetenteId: _meuId ?? 0,
      destinatarioId: destinatarioId,
      conteudo: texto,
      lida: false,
      criadoEm: DateTime.now(),
      pendente: true,
    );
    _adicionarMensagem(otimista);

    try {
      final data = await ApiClient.post('/chat/mensagem', {
        'destinatarioId': destinatarioId,
        'conteudo':       texto,
      });
      final msg = MensagemChat.fromJson(data);
      _removerMensagem(destinatarioId, tempId);
      _adicionarMensagem(msg);
    } catch (e) {
      debugPrint('ChatProvider.enviarMensagem erro: $e');
      // Remove a mensagem otimista que falhou para não ficar presa
      // mostrando 1 risquinho para sempre.
      _removerMensagem(destinatarioId, tempId);
    }
  }

  void _removerMensagem(int outroId, int id) {
    final lista = _conversas[outroId];
    if (lista == null) return;
    lista.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  /// Define (ou remove, passando `emoji: null`) a reação do usuário logado
  /// a uma mensagem. Atualiza o estado local otimisticamente e também
  /// recebe a confirmação via SSE (que faz a mesma atualização de forma
  /// idempotente, então não há problema em aplicar duas vezes).
  Future<void> reagirMensagem(MensagemChat mensagem, String? emoji) async {
    final outroId = mensagem.remetenteId == _meuId
        ? mensagem.destinatarioId
        : mensagem.remetenteId;

    // Atualização otimista: já reflete na tela antes da resposta do servidor.
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
      // Em caso de falha, desfaz a atualização otimista voltando ao
      // estado original da mensagem.
      _substituirMensagem(outroId, mensagem);
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

    // Evita duplicata
    if (_conversas[outroId]!.any((m) => m.id == msg.id)) return;
    _conversas[outroId]!.add(msg);
    notifyListeners();
  }

  // O SSE precisa de uma conexão de stream manual (não cabe no ApiClient,
  // que é só request/response), então montamos a URL e o token a partir
  // do próprio ApiClient para garantir que aponta para o mesmo servidor.
  void _conectarSSE() {
    _sseSub?.cancel();
    final token = ApiClient.token;
    if (token == null) return;

    final uri = Uri.parse('${ApiClient.baseUrl}/api/chat/sse');

    final client = http.Client();

    final req = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept']        = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';

    client.send(req).then((streamedResp) {
      final stream = streamedResp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sseSub = stream.listen(
        _processarLinhaSSE,
        onError: (e) {
          debugPrint('SSE erro: $e');
          Future.delayed(const Duration(seconds: 5), _conectarSSE);
        },
        onDone: () {
          Future.delayed(const Duration(seconds: 5), _conectarSSE);
        },
      );
    }).catchError((e) {
      debugPrint('SSE connect erro: $e');
      Future.delayed(const Duration(seconds: 5), _conectarSSE);
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

          // Atualiza badge se a mensagem não é da conversa que o usuário
          // está OLHANDO DE FATO agora (precisa estar com a tela de chat
          // visível E com essa conversa selecionada — não basta o id estar
          // "selecionado" no provider, pois isso persiste após navegar
          // para outra página do app).
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
        } else if (tipo == 'reacao_atualizada') {
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
    _sseSub?.cancel();
    _usuarios.clear();
    _conversas.clear();
    _usuarioAtivoId = null;
    _totalNaoLidas = 0;
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }
}