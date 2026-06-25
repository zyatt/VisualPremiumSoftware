// solicitacao_material_model.dart

class SolicitacaoMaterialModel {
  final int id;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialCategoria;
  final double materialQuantidadeEstoque;
  final double quantidade;
  final String numeroOS;
  final String nomeCliente;
  final DateTime dataSolicitacao;
  final DateTime dataNecessidade;
  final String andamento;
  final String? observacao;
  /// URL relativa ou absoluta da imagem anexada (ex.: /uploads/solicitacoes/sol_xxx.jpg)
  final String? imagemUrl;
  final int usuarioId;
  final String usuarioNome;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  SolicitacaoMaterialModel({
    required this.id,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.materialCategoria,
    required this.materialQuantidadeEstoque,
    required this.quantidade,
    required this.numeroOS,
    required this.nomeCliente,
    required this.dataSolicitacao,
    required this.dataNecessidade,
    required this.andamento,
    this.observacao,
    this.imagemUrl,
    required this.usuarioId,
    required this.usuarioNome,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  factory SolicitacaoMaterialModel.fromJson(Map<String, dynamic> json) {
    return SolicitacaoMaterialModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      materialId: (json['materialId'] as num?)?.toInt() ?? 0,
      materialNome: json['material']?['nome'] ?? '',
      materialUnidade: json['material']?['unidade'],
      materialIdentificador: json['material']?['identificador'],
      materialMedida: json['material']?['medida'],
      materialEspessura: json['material']?['espessura'],
      materialCategoria: json['material']?['categoria'],
      materialQuantidadeEstoque:
          double.tryParse(json['material']?['quantidade']?.toString() ?? '0') ?? 0,
      quantidade: double.tryParse(json['quantidade'].toString()) ?? 0,
      numeroOS: json['numeroOS'] ?? '',
      nomeCliente: json['nomeCliente'] ?? '',
      dataSolicitacao: DateTime.parse(json['dataSolicitacao']).toLocal(),
      dataNecessidade: DateTime.parse(json['dataNecessidade']).toLocal(),
      andamento: json['andamento'] ?? 'EM_ANDAMENTO',
      observacao: json['observacao'],
      imagemUrl: json['imagemUrl'],
      usuarioId: (json['usuarioId'] as num?)?.toInt() ?? 0,
      usuarioNome: json['usuarioNome'] ?? '',
      criadoEm: DateTime.parse(json['criadoEm']).toLocal(),
      atualizadoEm: DateTime.parse(json['atualizadoEm']).toLocal(),
    );
  }
}

// ─── Log de edição ────────────────────────────────────────────────────────────

class LogEdicaoSolicitacaoModel {
  final int id;
  final int solicitacaoId;
  final int editorId;
  final String editorNome;
  final Map<String, dynamic> antes;
  final Map<String, dynamic> depois;
  final DateTime editadoEm;

  LogEdicaoSolicitacaoModel({
    required this.id,
    required this.solicitacaoId,
    required this.editorId,
    required this.editorNome,
    required this.antes,
    required this.depois,
    required this.editadoEm,
  });

  factory LogEdicaoSolicitacaoModel.fromJson(Map<String, dynamic> json) {
    return LogEdicaoSolicitacaoModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      solicitacaoId: (json['solicitacaoId'] as num?)?.toInt() ?? 0,
      editorId: (json['editorId'] as num?)?.toInt() ?? 0,
      editorNome: json['editorNome'] ?? '',
      antes: Map<String, dynamic>.from(json['antes'] ?? {}),
      depois: Map<String, dynamic>.from(json['depois'] ?? {}),
      editadoEm: DateTime.parse(json['editadoEm']).toLocal(),
    );
  }
}