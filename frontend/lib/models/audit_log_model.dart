// audit_log_model.dart

class AuditLogModel {
  final int id;
  final int materialId;
  final String? materialNome;
  final String? materialCategoria;
  final String? materialMedida;
  final String? materialEspessura;

  /// 'CADASTRO' | 'EDICAO' | 'DESATIVACAO' | 'REATIVACAO' | 'EXCLUSAO'
  /// | 'ESTOQUE_CONFIRMADO' | 'FILHO_EDITADO' | 'FILHO_EXCLUIDO'
  final String acao;

  /// Campo alterado — presente em EDICAO e FILHO_*
  final String? campo;

  /// Valor antes da alteração (string serializada)
  final String? valorAntes;

  /// Novo valor após a alteração
  final String? valorDepois;

  final int? usuarioId;
  final String? usuarioNome;
  final DateTime criadoEm;

  AuditLogModel({
    required this.id,
    required this.materialId,
    this.materialNome,
    this.materialCategoria,
    this.materialMedida,
    this.materialEspessura,
    required this.acao,
    this.campo,
    this.valorAntes,
    this.valorDepois,
    this.usuarioId,
    this.usuarioNome,
    required this.criadoEm,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) => AuditLogModel(
        id:                (json['id'] as num?)?.toInt() ?? 0,
        materialId:        (json['materialId'] as num?)?.toInt() ?? 0,
        materialNome:      json['material']?['nome'],
        materialCategoria: json['material']?['categoria'],
        materialMedida:    json['material']?['medida'],
        materialEspessura: json['material']?['espessura'],
        acao:              json['acao'] ?? '',
        campo:             json['campo'],
        valorAntes:        json['valorAntes'],
        valorDepois:       json['valorDepois'],
        usuarioId:         (json['usuarioId'] as num?)?.toInt(),
        usuarioNome:       json['usuarioNome'],
        criadoEm:          DateTime.parse(json['criadoEm']),
      );

  // ── Helpers de exibição ────────────────────────────────────────────────────

  String get acaoLabel {
    switch (acao) {
      case 'CADASTRO':           return 'Cadastro';
      case 'EDICAO':             return 'Edição';
      case 'DESATIVACAO':        return 'Desativação';
      case 'REATIVACAO':         return 'Reativação';
      case 'EXCLUSAO':           return 'Exclusão';
      case 'ESTOQUE_CONFIRMADO': return 'Estoque confirmado';
      case 'CUSTO_MANUAL':       return 'Custo manual';
      case 'FILHO_EDITADO':      return 'Variação editada';
      case 'FILHO_EXCLUIDO':     return 'Variação excluída';
      default:                   return acao;
    }
  }

  // Cor associada à ação para badge visual
  // Retorna um código de cor hex que o widget irá parsear
  String get acaoCor {
    switch (acao) {
      case 'CADASTRO':           return '#15803D'; // verde
      case 'EDICAO':             return '#1E88E5'; // azul
      case 'DESATIVACAO':        return '#D97706'; // amarelo
      case 'REATIVACAO':         return '#7C3AED'; // roxo
      case 'EXCLUSAO':           return '#DC2626'; // vermelho
      case 'ESTOQUE_CONFIRMADO': return '#0891B2'; // ciano
      case 'CUSTO_MANUAL':       return '#7C3AED'; // roxo
      case 'FILHO_EDITADO':      return '#1E88E5'; // azul
      case 'FILHO_EXCLUIDO':     return '#E85D04'; // laranja
      default:                   return '#6B7280'; // cinza
    }
  }

  bool get temDiff => valorAntes != null || valorDepois != null;
}