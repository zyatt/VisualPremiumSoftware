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

  factory OrcamentoItemModel.fromJson(Map<String, dynamic> json) => OrcamentoItemModel(
    id:            json['id'],
    materialId:    json['materialId'],
    materialNome:  json['material']?['nome'] ?? '',
    fornecedorId:  json['fornecedorId'],
    fornecedorNome: json['fornecedor']?['nomeFantasia'],
    quantidade:    double.tryParse(json['quantidade'].toString()) ?? 1,
    precoUnitario: json['precoUnitario'] != null ? double.tryParse(json['precoUnitario'].toString()) : null,
  );
}

class OrcamentoModel {
  final int id;
  final String titulo;
  final String status;
  final List<OrcamentoItemModel> itens;

  OrcamentoModel({
    required this.id,
    required this.titulo,
    required this.status,
    required this.itens,
  });

  factory OrcamentoModel.fromJson(Map<String, dynamic> json) => OrcamentoModel(
    id:     json['id'],
    titulo: json['titulo'] ?? 'Orçamento',
    status: json['status'] ?? 'ABERTO',
    itens:  (json['itens'] as List? ?? [])
        .map((i) => OrcamentoItemModel.fromJson(i))
        .toList(),
  );
}