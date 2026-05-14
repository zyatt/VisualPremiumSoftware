class MovimentacaoModel {
  final int id;
  final int materialId;
  final String materialNome;
  final String tipo; // ENTRADA | SAIDA
  final double quantidade;
  final String numeroOS;
  final double? precoUnitario;
  final String? observacao;
  final DateTime criadoEm;

  MovimentacaoModel({
    required this.id,
    required this.materialId,
    required this.materialNome,
    required this.tipo,
    required this.quantidade,
    required this.numeroOS,
    this.precoUnitario,
    this.observacao,
    required this.criadoEm,
  });

  factory MovimentacaoModel.fromJson(Map<String, dynamic> json) => MovimentacaoModel(
    id:            json['id'],
    materialId:    json['materialId'],
    materialNome:  json['material']?['nome'] ?? '',
    tipo:          json['tipo'],
    quantidade:    double.tryParse(json['quantidade'].toString()) ?? 0,
    numeroOS:      json['numeroOS'],
    precoUnitario: json['precoUnitario'] != null ? double.tryParse(json['precoUnitario'].toString()) : null,
    observacao:    json['observacao'],
    criadoEm:      DateTime.parse(json['criadoEm']),
  );
}

class RelacaoOSModel {
  final int id;
  final String numeroOS;
  final String? descricao;
  final List<MovimentacaoModel> movimentacoes;

  RelacaoOSModel({
    required this.id,
    required this.numeroOS,
    this.descricao,
    required this.movimentacoes,
  });

  factory RelacaoOSModel.fromJson(Map<String, dynamic> json) => RelacaoOSModel(
    id:            json['id'],
    numeroOS:      json['numeroOS'],
    descricao:     json['descricao'],
    movimentacoes: (json['movimentacoes'] as List? ?? [])
        .map((m) => MovimentacaoModel.fromJson(m))
        .toList(),
  );
}