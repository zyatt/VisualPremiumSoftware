import 'dart:convert';

const _prefixoEncaminhamentoGlobal = '§FWD§';

String resumoConteudoParaPreview(String conteudo) {
  if (!conteudo.startsWith(_prefixoEncaminhamentoGlobal)) return conteudo;
  try {
    final payload = jsonDecode(
      conteudo.substring(_prefixoEncaminhamentoGlobal.length),
    ) as Map<String, dynamic>;
    final dados = payload['dados'] as Map<String, dynamic>?;
    switch (payload['tipo'] as String?) {
      case 'solicitacao':
        final numeroOS = dados?['numeroOS'];
        return numeroOS != null ? 'OS $numeroOS' : 'Solicitação encaminhada';
      case 'material':
        final nome = (dados?['materialNome'] as String?)?.trim();
        return nome != null && nome.isNotEmpty ? nome : 'Material encaminhado';
      default:
        return 'Encaminhamento';
    }
  } catch (_) {
    return 'Encaminhamento';
  }
}

class MensagemChat {
  final int id;
  final int remetenteId;
  final int destinatarioId;
  final String conteudo;
  final bool lida;
  final DateTime criadoEm;
  final String? remetenteNome;
  final String? destinatarioNome;
  final Map<String, String> reacoes;
  final DateTime? editadaEm;
  final bool apagada;
  bool get ehEditada => editadaEm != null;
  
  final bool pendente;

  final int? respondendoAId;
  final String? respondendoAConteudo;
  final String? respondendoARemetenteNome;

  bool get ehResposta => respondendoAId != null;

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

  String? get tipoEncaminhamento => _payloadEncaminhamento?['tipo'] as String?;

  Map<String, dynamic>? get dadosEncaminhados =>
      _payloadEncaminhamento?['dados'] as Map<String, dynamic>?;

  static String codificarEncaminhamento({
    required String tipo,
    required Map<String, dynamic> dados,
  }) {
    return '$_prefixoEncaminhamento${jsonEncode({'tipo': tipo, 'dados': dados})}';
  }

  String get resumoParaPreview => resumoConteudoParaPreview(conteudo);

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
    this.editadaEm,
    this.apagada = false,
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
      editadaEm: json['editadaEm'] != null
          ? DateTime.parse(json['editadaEm'] as String).toLocal()
          : null,
      apagada: json['apagada'] as bool? ?? false,
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
    if (editadaEm != null) 'editadaEm': editadaEm!.toIso8601String(),
    'apagada':        apagada,
    if (respondendoAId != null) 'respondendoAId': respondendoAId,
  };

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
      editadaEm: editadaEm,
      apagada: apagada,
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