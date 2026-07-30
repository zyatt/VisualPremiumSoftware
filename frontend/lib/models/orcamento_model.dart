class OrcamentoItemModel {
  final int? id;
  final int materialId;
  final String materialNome;
  final int? fornecedorId;
  final String? fornecedorNome;
  double quantidade;
  double? precoUnitario;
  final double? qtdUnidade;
  final double? materialLargura;
  final double? materialComprimento;

  OrcamentoItemModel({
    this.id,
    required this.materialId,
    required this.materialNome,
    this.fornecedorId,
    this.fornecedorNome,
    required this.quantidade,
    this.precoUnitario,
    this.qtdUnidade,
    this.materialLargura,
    this.materialComprimento,
  });

  String? get materialDimensaoFormatada {
    final l = materialLargura;
    final c = materialComprimento;
    if (l == null || c == null || l <= 0 || c <= 0) return null;
    String fmt(double v) =>
        v == v.truncateToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
    return '${fmt(c)}x${fmt(l)}m';
  }

  factory OrcamentoItemModel.fromJson(Map<String, dynamic> json) =>
      OrcamentoItemModel(
        id: json['id'],
        materialId: json['materialId'],
        materialNome: json['material']?['nome'] ?? '',
        fornecedorId: json['fornecedorId'],
        fornecedorNome: json['fornecedor']?['nomeFantasia'],
        quantidade:
            double.tryParse(json['quantidade'].toString()) ?? 1,
        precoUnitario: json['precoUnitario'] != null
            ? double.tryParse(json['precoUnitario'].toString())
            : null,
        qtdUnidade: json['qtdUnidade'] != null
            ? double.tryParse(json['qtdUnidade'].toString())
            : null,
        materialLargura: json['material']?['largura'] != null
            ? double.tryParse(json['material']['largura'].toString())
            : null,
        materialComprimento: json['material']?['comprimento'] != null
            ? double.tryParse(json['material']['comprimento'].toString())
            : null,
      );
}

class OrcamentoModel {
  final int id;
  final String titulo;
  final String status;
  final List<OrcamentoItemModel> itens;
  final String? criadorNome;
  final String? aprovadorNome;
  final DateTime? aprovadoEm;
  final String? motivoRejeicao;
  final DateTime criadoEm;

  final List<int> fornecedoresOcultos;

  OrcamentoModel({
    required this.id,
    required this.titulo,
    required this.status,
    required this.itens,
    this.criadorNome,
    this.aprovadorNome,
    this.aprovadoEm,
    this.motivoRejeicao,
    required this.criadoEm,
    this.fornecedoresOcultos = const [],
  });

  factory OrcamentoModel.fromJson(Map<String, dynamic> json) =>
      OrcamentoModel(
        id: json['id'],
        titulo: json['titulo'] ?? 'Orçamento',
        status: json['status'] ?? 'ABERTO',
        itens: (json['itens'] as List? ?? [])
            .map((i) => OrcamentoItemModel.fromJson(i))
            .toList(),
        criadorNome: json['criador']?['nome'],
        aprovadorNome: json['aprovador']?['nome'],
        aprovadoEm: json['aprovadoEm'] != null
            ? DateTime.tryParse(json['aprovadoEm'])
            : null,
        motivoRejeicao: json['motivoRejeicao'],
        criadoEm: json['criadoEm'] != null
            ? DateTime.tryParse(json['criadoEm']) ?? DateTime.now()
            : DateTime.now(),
        fornecedoresOcultos: (json['fornecedoresOcultos'] as List? ?? [])
            .map((e) => e as int)
            .toList(),
      );

  String get statusLabel {
    switch (status) {
      case 'ABERTO':
        return 'Aberto';
      case 'AGUARDANDO_APROVACAO':
        return 'Aguardando Aprovação';
      case 'APROVADO':
        return 'Aprovado';
      case 'NAO_APROVADO':
        return 'Não Aprovado';
      case 'CONVERTIDO':
        return 'Convertido em OC';
      case 'CANCELADO':
        return 'Cancelado';
      default:
        return status;
    }
  }

  bool get podeEnviarAprovacao => status == 'ABERTO';
  bool get podeGerarOC => status == 'APROVADO';
  bool get aguardandoAprovacao => status == 'AGUARDANDO_APROVACAO';
  bool get aprovado => status == 'APROVADO';
  bool get naoAprovado => status == 'NAO_APROVADO';
}