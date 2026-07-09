// lib/models/mensagem_chat_model.dart

import 'dart:convert';

class MensagemChat {
  final int id;
  final int remetenteId;
  final int destinatarioId;
  final String conteudo;
  final bool lida;
  final DateTime criadoEm;
  final String? remetenteNome;
  final String? destinatarioNome;
  // Mapa "idDoUsuario" (como String, porque chaves de JSON são sempre
  // string) -> emoji escolhido por aquele usuário. Permite múltiplas
  // pessoas reagindo à mesma mensagem, cada uma com no máximo uma reação
  // (reagir de novo com outro emoji substitui a anterior).
  final Map<String, String> reacoes;
  // Campo puramente local/transiente (nunca vem do JSON do servidor nem é
  // enviado): true enquanto a mensagem foi adicionada otimisticamente na UI
  // e ainda aguarda confirmação do POST /chat/mensagem. Usado só para
  // decidir entre 1 risquinho (enviando) e 2 risquinhos (confirmada).
  final bool pendente;

  // Dados (achatados/denormalizados) da mensagem citada, quando esta é uma
  // resposta a outra mensagem da conversa. Vêm prontos do backend dentro de
  // `respondendoA` (ver include no chat.routes.js) — guardamos só o
  // necessário pra exibir a citação na bolha, sem montar um MensagemChat
  // aninhado completo.
  final int? respondendoAId;
  final String? respondendoAConteudo;
  final String? respondendoARemetenteNome;

  bool get ehResposta => respondendoAId != null;

  // ── Encaminhamento de solicitação/material (ver feature "enviar para chat") ─
  // Aproveita o campo `conteudo` (String livre) para carregar um payload JSON
  // prefixado, evitando qualquer alteração de schema no backend. Se o parse
  // falhar por algum motivo, `ehEncaminhamento` continua true mas os getters
  // de dados retornam null — a UI cai de volta pro texto cru.
  static const _prefixoEncaminhamento = '§FWD§';

  bool get ehEncaminhamento => conteudo.startsWith(_prefixoEncaminhamento);

  Map<String, dynamic>? get _payloadEncaminhamento {
    if (!ehEncaminhamento) return null;
    try {
      return jsonDecode(conteudo.substring(_prefixoEncaminhamento.length))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 'solicitacao' ou 'material'.
  String? get tipoEncaminhamento => _payloadEncaminhamento?['tipo'] as String?;

  Map<String, dynamic>? get dadosEncaminhados =>
      _payloadEncaminhamento?['dados'] as Map<String, dynamic>?;

  static String codificarEncaminhamento({
    required String tipo,
    required Map<String, dynamic> dados,
  }) {
    return '$_prefixoEncaminhamento${jsonEncode({'tipo': tipo, 'dados': dados})}';
  }

  const MensagemChat({
    required this.id,
    required this.remetenteId,
    required this.destinatarioId,
    required this.conteudo,
    required this.lida,
    required this.criadoEm,
    this.remetenteNome,
    this.destinatarioNome,
    this.reacoes = const {},
    this.pendente = false,
    this.respondendoAId,
    this.respondendoAConteudo,
    this.respondendoARemetenteNome,
  });

  factory MensagemChat.fromJson(Map<String, dynamic> json) {
    final respondendoA = json['respondendoA'] as Map<String, dynamic>?;
    return MensagemChat(
      id:              json['id'] as int,
      remetenteId:     json['remetenteId'] as int,
      destinatarioId:  json['destinatarioId'] as int,
      conteudo:        json['conteudo'] as String,
      lida:            json['lida'] as bool? ?? false,
      criadoEm:        DateTime.parse(json['criadoEm'] as String).toLocal(),
      remetenteNome:   (json['remetente'] as Map<String, dynamic>?)?['nome'] as String?,
      destinatarioNome:(json['destinatario'] as Map<String, dynamic>?)?['nome'] as String?,
      reacoes: (json['reacoes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
      respondendoAId:            respondendoA?['id'] as int?,
      respondendoAConteudo:      respondendoA?['conteudo'] as String?,
      respondendoARemetenteNome:
          (respondendoA?['remetente'] as Map<String, dynamic>?)?['nome'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':             id,
    'remetenteId':    remetenteId,
    'destinatarioId': destinatarioId,
    'conteudo':       conteudo,
    'lida':           lida,
    'criadoEm':       criadoEm.toIso8601String(),
    'reacoes':        reacoes,
    if (respondendoAId != null) 'respondendoAId': respondendoAId,
  };

  /// Retorna uma cópia da mensagem com o mapa de reações substituído.
  /// Usado pelo provider para atualizar o estado local sem precisar
  /// recarregar a conversa inteira do servidor.
  MensagemChat copyComReacoes(Map<String, String> novasReacoes) {
    return MensagemChat(
      id: id,
      remetenteId: remetenteId,
      destinatarioId: destinatarioId,
      conteudo: conteudo,
      lida: lida,
      criadoEm: criadoEm,
      remetenteNome: remetenteNome,
      destinatarioNome: destinatarioNome,
      reacoes: novasReacoes,
      pendente: pendente,
      respondendoAId: respondendoAId,
      respondendoAConteudo: respondendoAConteudo,
      respondendoARemetenteNome: respondendoARemetenteNome,
    );
  }
}

class UsuarioChat {
  final int id;
  final String nome;
  final String role;
  int naoLidas;
  // Presença: `online` reflete se o usuário tem uma conexão SSE ativa
  // agora (app aberto em primeiro plano); `ultimoAcesso` é o momento em
  // que a conexão anterior caiu (app fechado/minimizado/perda de rede) —
  // só faz sentido mostrar quando `online` é false. Ambos chegam prontos
  // do backend em /chat/usuarios e são atualizados em tempo real pelos
  // eventos SSE 'usuario_online'/'usuario_offline' (ver ChatProvider).
  bool online;
  DateTime? ultimoAcesso;

  UsuarioChat({
    required this.id,
    required this.nome,
    required this.role,
    this.naoLidas = 0,
    this.online = false,
    this.ultimoAcesso,
  });

  factory UsuarioChat.fromJson(Map<String, dynamic> json) {
    return UsuarioChat(
      id:           json['id'] as int,
      nome:         json['nome'] as String,
      role:         json['role'] as String,
      naoLidas:     json['naoLidas'] as int? ?? 0,
      online:       json['online'] as bool? ?? false,
      ultimoAcesso: json['ultimoAcesso'] != null
          ? DateTime.parse(json['ultimoAcesso'] as String).toLocal()
          : null,
    );
  }
}