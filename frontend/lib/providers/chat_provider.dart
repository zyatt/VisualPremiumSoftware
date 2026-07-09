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

  // Contrapartida do trigger acima: pede para o mini-chat flutuante
  // EXPANDIR (em vez de recolher) já com uma conversa específica aberta.
  // Usado após encaminhar uma solicitação/material — a UI
  // (ChatFloatingWidget) observa `abrirConversaTrigger` e, ao mudar, se
  // expande e confia em `usuarioAtivoId` (já setado por `abrirConversa`
  // abaixo) para saber qual conversa mostrar.
  int _abrirConversaTrigger = 0;
  int              get abrirConversaTrigger => _abrirConversaTrigger;

  // ── Indicador de "digitando..." ──────────────────────────────────────
  // Guarda, por id de usuário, um Timer que expira o indicador se nenhum
  // novo ping SSE chegar em _digitandoExpira. O evento é só um "ping"
  // repassado pelo servidor (não fica persistido), então quem decide
  // quando o indicador some é sempre o lado que recebe.
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

  // Throttle do lado de quem digita: evita disparar um POST a cada tecla.
  // Reenvia o ping no máximo 1x a cada 2s enquanto o campo continua sendo
  // editado, o que é suficiente pro timer de 3s do lado receptor nunca
  // expirar entre uma tecla e outra.
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
      // Falha aqui é inofensiva (o indicador só deixa de aparecer), então
      // não vale a pena mostrar erro pro usuário nem tentar de novo.
      debugPrint('ChatProvider.notificarDigitando erro: $e');
    }
  }

  /// Pede para o mini-chat flutuante (bolha) recolher, se estiver expandido.
  /// Usado, por exemplo, ao trocar de usuário logado, para não deixar a
  /// conversa de um usuário aberta na tela depois da troca.
  void minimizarWidgetFlutuante() {
    _minimizarTrigger++;
    notifyListeners();
  }

  /// Pede para o mini-chat flutuante expandir já com a conversa de
  /// `usuarioId` aberta (carregando as mensagens, se necessário). Usado após
  /// encaminhar uma solicitação/material para alguém no chat.
  Future<void> solicitarAberturaConversa(int usuarioId) async {
    await abrirConversa(usuarioId);
    _abrirConversaTrigger++;
    notifyListeners();
  }

  List<MensagemChat> conversaAtual() {
    if (_usuarioAtivoId == null) return [];
    return _conversas[_usuarioAtivoId] ?? [];
  }

  /// Busca um usuário da lista pelo id — usado pela UI para exibir o
  /// indicador de presença (online/offline) do usuário da conversa aberta.
  UsuarioChat? usuarioPorId(int id) {
    for (final u in _usuarios) {
      if (u.id == id) return u;
    }
    return null;
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

  /// Se `respondendoA` for informada, a mensagem é enviada como resposta
  /// (citação) àquela mensagem — ver feature "responder mensagem".
  Future<void> enviarMensagem(String conteudo, {MensagemChat? respondendoA}) async {
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
      // Remove a mensagem otimista que falhou para não ficar presa
      // mostrando 1 risquinho para sempre.
      _removerMensagem(destinatarioId, tempId);
    }
  }

  /// Envia uma solicitação ou material "encaminhado" para `destinatarioId`,
  /// que não precisa ser a conversa atualmente aberta (diferente de
  /// `enviarMensagem`, que sempre manda para `_usuarioAtivoId`).
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
    for (final t in _digitandoTimers.values) {
      t.cancel();
    }
    _digitandoTimers.clear();
    _usuariosDigitando.clear();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    for (final t in _digitandoTimers.values) {
      t.cancel();
    }
    super.dispose();
  }
}