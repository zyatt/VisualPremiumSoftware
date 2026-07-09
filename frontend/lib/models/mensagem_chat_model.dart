// lib/models/mensagem_chat_model.dart

import 'dart:convert';

/// Prefixo usado para identificar conteúdo de mensagem que na verdade é um
/// payload de encaminhamento (solicitação/material) — ver
/// `MensagemChat.codificarEncaminhamento`. Exposto separadamente (e não só
/// como constante privada da classe) porque `resumoConteudoParaPreview`
/// também precisa dele para decodificar textos crus de mensagens citadas
/// (`respondendoAConteudo`), que chegam do backend já achatados em uma
/// String solta — sem o wrapper `MensagemChat` e seus getters.
const _prefixoEncaminhamentoGlobal = '§FWD§';

/// Decodifica um `conteudo` cru de mensagem (seja da própria mensagem, seja
/// de uma mensagem citada, ex.: `respondendoAConteudo`) para um texto curto
/// e legível: mensagens normais retornam o próprio texto; encaminhamentos
/// (payload JSON prefixado) mostram o nome do material ou o número da OS
/// em vez do JSON cru — mesmas chaves que `EncaminhamentoChatCard` usa para
/// montar o título do card (`materialNome` / `numeroOS`), para o preview
/// bater com o que a bolha efetivamente mostra.
/// Usado tanto pela citação "respondendo a" dentro da bolha quanto pelo
/// preview acima do campo de digitação.
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
  // Mapa "idDoUsuario" (como String, porque chaves de JSON são sempre
  // string) -> emoji escolhido por aquele usuário. Permite múltiplas
  // pessoas reagindo à mesma mensagem, cada uma com no máximo uma reação
  // (reagir de novo com outro emoji substitui a anterior).
  final Map<String, String> reacoes;
  // Presente quando a mensagem foi editada após o envio original — usado
  // pela UI para mostrar o marcador "(editada)" ao lado do horário.
  final DateTime? editadaEm;
  // true quando o remetente excluiu a mensagem (exclusão lógica: o
  // conteúdo original é descartado no backend e a UI mostra um texto
  // "Mensagem apagada" no lugar).
  final bool apagada;
  bool get ehEditada => editadaEm != null;
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

  /// Texto curto e legível para exibir em contextos de "preview" do
  /// conteúdo desta mensagem — citação na bolha de quem respondeu, e o
  /// preview acima do campo de digitação enquanto se está respondendo.
  /// Mensagens normais retornam o próprio `conteudo`; encaminhamentos
  /// (que guardam um payload JSON bruto em `conteudo`, ver acima) viram um
  /// resumo amigável em vez do JSON cru.
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