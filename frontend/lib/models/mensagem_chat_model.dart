// lib/models/mensagem_chat_model.dart

class MensagemChat {
  final int id;
  final int remetenteId;
  final int destinatarioId;
  final String conteudo;
  final bool lida;
  final DateTime criadoEm;
  final String? remetenteNome;
  final String? destinatarioNome;

  const MensagemChat({
    required this.id,
    required this.remetenteId,
    required this.destinatarioId,
    required this.conteudo,
    required this.lida,
    required this.criadoEm,
    this.remetenteNome,
    this.destinatarioNome,
  });

  factory MensagemChat.fromJson(Map<String, dynamic> json) {
    return MensagemChat(
      id:              json['id'] as int,
      remetenteId:     json['remetenteId'] as int,
      destinatarioId:  json['destinatarioId'] as int,
      conteudo:        json['conteudo'] as String,
      lida:            json['lida'] as bool? ?? false,
      criadoEm:        DateTime.parse(json['criadoEm'] as String).toLocal(),
      remetenteNome:   (json['remetente'] as Map<String, dynamic>?)?['nome'] as String?,
      destinatarioNome:(json['destinatario'] as Map<String, dynamic>?)?['nome'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':             id,
    'remetenteId':    remetenteId,
    'destinatarioId': destinatarioId,
    'conteudo':       conteudo,
    'lida':           lida,
    'criadoEm':       criadoEm.toIso8601String(),
  };
}

class UsuarioChat {
  final int id;
  final String nome;
  final String role;
  int naoLidas;

  UsuarioChat({
    required this.id,
    required this.nome,
    required this.role,
    this.naoLidas = 0,
  });

  factory UsuarioChat.fromJson(Map<String, dynamic> json) {
    return UsuarioChat(
      id:       json['id'] as int,
      nome:     json['nome'] as String,
      role:     json['role'] as String,
      naoLidas: json['naoLidas'] as int? ?? 0,
    );
  }
}