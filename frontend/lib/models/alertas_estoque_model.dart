/// Representa um material com estoque crítico ou no limite.
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
  /// 'CRITICO' | 'LIMITE'
  final String status;
  final bool especifico;

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
    required this.status,
    required this.especifico,
  });

  bool get isCritico => status == 'CRITICO';

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
        status:        json['status'] ?? 'CRITICO',
        especifico:    json['especifico'] ?? false,
      );
}