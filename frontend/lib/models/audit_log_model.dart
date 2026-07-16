// audit_log_model.dart

class AuditLogModel {
  final int id;
  final int materialId;
  final String? materialNome;
  final String? materialCategoria;
  final String? materialUnidade;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialIdentificador;
  final double? materialLargura;
  final double? materialComprimento;

  /// true quando o material referenciado por este log já foi excluído do
  /// banco. Os dados acima, nesse caso, vêm do snapshot gravado no momento
  /// da ação (ver backend), não do material em si (que não existe mais).
  final bool materialExcluido;

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
    this.materialUnidade,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.materialLargura,
    this.materialComprimento,
    this.materialExcluido = false,
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
        materialNome:          json['material']?['nome'],
        materialCategoria:     json['material']?['categoria'],
        materialUnidade:       json['material']?['unidade'],
        materialMedida:        json['material']?['medida'],
        materialEspessura:     json['material']?['espessura'],
        materialIdentificador: json['material']?['identificador'],
        materialLargura:       json['material']?['largura'] != null
            ? double.tryParse(json['material']['largura'].toString())
            : null,
        materialComprimento:   json['material']?['comprimento'] != null
            ? double.tryParse(json['material']['comprimento'].toString())
            : null,
        materialExcluido:      json['materialExcluido'] == true,
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

  /// Formata um número sem casas decimais desnecessárias (2.0 -> '2', 2.5 -> '2.5').
  static String _numFmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  /// Linha secundária exibida ao lado do nome do material no histórico:
  /// identificador, unidade (minúscula), medida OU comprimento×largura
  /// (quando não há medida cadastrada), e espessura — separados por " · ".
  ///
  /// Regra de comprimento/largura: só é exibido quando NÃO há [materialMedida]
  /// preenchida (medida e dimensões são formas alternativas de descrever o
  /// tamanho do material; não faz sentido mostrar as duas). Formato: "2x1m".
  String get materialInfoLine {
    final partes = <String>[];

    if (materialIdentificador != null && materialIdentificador!.trim().isNotEmpty) {
      partes.add(materialIdentificador!.trim());
    }

    if (materialUnidade != null && materialUnidade!.trim().isNotEmpty) {
      partes.add(materialUnidade!.trim().toLowerCase());
    }

    if (materialMedida != null && materialMedida!.trim().isNotEmpty) {
      partes.add(materialMedida!.trim().toLowerCase());
    } else if (materialComprimento != null &&
        materialComprimento! > 0 &&
        materialLargura != null &&
        materialLargura! > 0) {
      partes.add(
        '${_numFmt(materialComprimento!)}x${_numFmt(materialLargura!)}m',
      );
    }

    if (materialEspessura != null && materialEspessura!.trim().isNotEmpty) {
      partes.add(materialEspessura!.trim().toLowerCase());
    }

    return partes.join(' · ');
  }
}