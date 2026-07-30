class AlertaEstoqueModel {
  final int id;
  final String nome;
  final String? categoria;
  final String? unidade;
  final String? identificador;
  final String? medida;
  final String? espessura;
  final double quantidade;
  final double estoqueMinimo;

  const AlertaEstoqueModel({
    required this.id,
    required this.nome,
    this.categoria,
    this.unidade,
    this.identificador,
    this.medida,
    this.espessura,
    required this.quantidade,
    required this.estoqueMinimo,
  });

  factory AlertaEstoqueModel.fromJson(Map<String, dynamic> json) =>
      AlertaEstoqueModel(
        id:            (json['id'] as num?)?.toInt() ?? 0,
        nome:          json['nome'] ?? '',
        categoria:     json['categoria'],
        unidade:       json['unidade'],
        identificador: json['identificador'],
        medida:        json['medida'],
        espessura:     json['espessura'],
        quantidade:    (json['quantidade'] as num?)?.toDouble() ?? 0,
        estoqueMinimo: (json['estoqueMinimo'] as num?)?.toDouble() ?? 0,
      );
}