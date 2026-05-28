class OrcamentoItemModel {
  final int? id;
  final int materialId;
  final String materialNome;
  final int? fornecedorId;
  final String? fornecedorNome;
  double quantidade;
  double? precoUnitario;

  OrcamentoItemModel({
    this.id,
    required this.materialId,
    required this.materialNome,
    this.fornecedorId,
    this.fornecedorNome,
    required this.quantidade,
    this.precoUnitario,
  });

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
      );

  /// Label legível para o status
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