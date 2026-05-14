class OrdemCompraItemModel {
  final int? id;
  final int materialId;
  final String materialNome;
  final String numeroOS;
  final double quantidade;
  final double precoUnitario;
  final double? precoMetroQuadrado;
  final double precoTotal;

  OrdemCompraItemModel({
    this.id,
    required this.materialId,
    required this.materialNome,
    required this.numeroOS,
    required this.quantidade,
    required this.precoUnitario,
    this.precoMetroQuadrado,
    required this.precoTotal,
  });

  factory OrdemCompraItemModel.fromJson(Map<String, dynamic> json) => OrdemCompraItemModel(
    id:                 json['id'],
    materialId:         json['materialId'],
    materialNome:       json['material']?['nome'] ?? '',
    numeroOS:           json['numeroOS'],
    quantidade:         double.tryParse(json['quantidade'].toString()) ?? 0,
    precoUnitario:      double.tryParse(json['precoUnitario'].toString()) ?? 0,
    precoMetroQuadrado: json['precoMetroQuadrado'] != null ? double.tryParse(json['precoMetroQuadrado'].toString()) : null,
    precoTotal:         double.tryParse(json['precoTotal'].toString()) ?? 0,
  );
}

class OrdemCompraModel {
  final int id;
  final DateTime data;
  final int fornecedorId;
  final String? fornecedorNome;
  final String requisitante;
  final String? formaPagamento;
  final String? prazoPagamento;
  final String? observacoes;
  final String? empresa;
  final String status; // EM_ANDAMENTO | FINALIZADO | CANCELADO
  final double valorTotal;
  final List<OrdemCompraItemModel> itens;
  final List<String> numerosOS;

  OrdemCompraModel({
    required this.id,
    required this.data,
    required this.fornecedorId,
    this.fornecedorNome,
    required this.requisitante,
    this.formaPagamento,
    this.prazoPagamento,
    this.observacoes,
    this.empresa,
    required this.status,
    required this.valorTotal,
    required this.itens,
    required this.numerosOS,
  });

  factory OrdemCompraModel.fromJson(Map<String, dynamic> json) => OrdemCompraModel(
    id:             json['id'],
    data:           DateTime.parse(json['data']),
    fornecedorId:   json['fornecedorId'],
    fornecedorNome: json['fornecedor']?['nomeFantasia'],
    requisitante:   json['requisitante'],
    formaPagamento: json['formaPagamento'],
    prazoPagamento: json['prazoPagamento'],
    observacoes:    json['observacoes'],
    empresa:        json['empresa'],
    status:         json['status'],
    valorTotal:     double.tryParse(json['valorTotal'].toString()) ?? 0,
    itens:          (json['itens'] as List? ?? [])
        .map((i) => OrdemCompraItemModel.fromJson(i))
        .toList(),
    numerosOS:      (json['numerosOS'] as List? ?? [])
        .map((o) => o['numeroOS'].toString())
        .toList(),
  );
}