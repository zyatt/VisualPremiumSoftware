class FornecedorMaterialModel {
  final int id;
  final int fornecedorId;
  final String fornecedorNome;
  final double preco;
  final double precoMetroQuadrado;
  final bool ativo;

  FornecedorMaterialModel({
    required this.id,
    required this.fornecedorId,
    required this.fornecedorNome,
    required this.preco,
    required this.precoMetroQuadrado,
    required this.ativo,
  });

  factory FornecedorMaterialModel.fromJson(Map<String, dynamic> json) =>
      FornecedorMaterialModel(
        id:                 json['id'],
        fornecedorId:       json['fornecedorId'],
        fornecedorNome:     json['fornecedor']?['nomeFantasia'] ?? '',
        preco:              double.tryParse(json['preco'].toString()) ?? 0,
        precoMetroQuadrado: double.tryParse(json['precoMetroQuadrado'].toString()) ?? 0,
        ativo:              json['ativo'] ?? true,
      );
}

class MaterialModel {
  final int id;
  final String nome;
  final String? unidade;
  final String? categoria;
  final String? medida;
  final String? espessura;
  final double? valor;
  final double? valorMetroQuadrado;
  final double quantidade;
  final double estoqueMinimo;
  final String status; // OK | LIMITE | CRITICO | INATIVO
  final bool estoqueConfirmado;
  final bool ativo;
  final double? ultimoValorPago;

  // Calculados pelo backend (mediana entre fornecedores)
  final double? precoMediano;
  final double? precoM2Mediano;

  // Lista de fornecedores vinculados com seus preços
  final List<FornecedorMaterialModel> fornecedorMateriais;

  MaterialModel({
    required this.id,
    required this.nome,
    this.unidade,
    this.categoria,
    this.medida,
    this.espessura,
    this.valor,
    this.valorMetroQuadrado,
    required this.quantidade,
    required this.estoqueMinimo,
    required this.status,
    required this.estoqueConfirmado,
    required this.ativo,
    this.ultimoValorPago,
    this.precoMediano,
    this.precoM2Mediano,
    this.fornecedorMateriais = const [],
  });

  factory MaterialModel.fromJson(Map<String, dynamic> json) => MaterialModel(
        id:                 json['id'],
        nome:               json['nome'],
        unidade:            json['unidade'],
        categoria:          json['categoria'],
        medida:             json['medida'],
        espessura:          json['espessura'],
        valor:              json['valor'] != null
            ? double.tryParse(json['valor'].toString())
            : null,
        valorMetroQuadrado: json['valorMetroQuadrado'] != null
            ? double.tryParse(json['valorMetroQuadrado'].toString())
            : null,
        quantidade:         double.tryParse(json['quantidade'].toString()) ?? 0,
        estoqueMinimo:      double.tryParse(json['estoqueMinimo'].toString()) ?? 0,
        status:             json['status'] ?? 'OK',
        estoqueConfirmado:  json['estoqueConfirmado'] ?? false,
        ativo:              json['ativo'] ?? true,
        ultimoValorPago:    json['ultimoValorPago'] != null
            ? double.tryParse(json['ultimoValorPago'].toString())
            : null,
        precoMediano:       json['precoMediano'] != null
            ? double.tryParse(json['precoMediano'].toString())
            : null,
        precoM2Mediano:     json['precoM2Mediano'] != null
            ? double.tryParse(json['precoM2Mediano'].toString())
            : null,
        fornecedorMateriais: (json['fornecedorMateriais'] as List? ?? [])
            .map((f) => FornecedorMaterialModel.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}