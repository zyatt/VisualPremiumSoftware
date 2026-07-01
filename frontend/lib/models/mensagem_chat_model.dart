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
      reacoes: (json['reacoes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
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
    );
  }
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