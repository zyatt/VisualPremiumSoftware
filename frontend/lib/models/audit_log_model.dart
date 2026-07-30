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

  final bool materialExcluido;

  final String acao;

  final String? campo;

  final String? valorAntes;

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

  String get acaoCor {
    switch (acao) {
      case 'CADASTRO':           return '#15803D';
      case 'EDICAO':             return '#1E88E5';
      case 'DESATIVACAO':        return '#D97706';
      case 'REATIVACAO':         return '#7C3AED';
      case 'EXCLUSAO':           return '#DC2626';
      case 'ESTOQUE_CONFIRMADO': return '#0891B2';
      case 'CUSTO_MANUAL':       return '#7C3AED';
      case 'FILHO_EDITADO':      return '#1E88E5';
      case 'FILHO_EXCLUIDO':     return '#E85D04';
      default:                   return '#6B7280';
    }
  }

  bool get temDiff => valorAntes != null || valorDepois != null;

  static String _numFmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

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