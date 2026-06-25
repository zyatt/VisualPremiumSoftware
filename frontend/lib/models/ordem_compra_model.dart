class OrdemCompraItemModel {
  final int? id;
  final int? materialId;
  final String materialNome;
  /// Unidade de medida do material no estoque (ex: "UNIDADE", "ML", "M/L", "KG").
  final String? materialUnidade;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialIdentificador;
  final String? descricaoItem;
  final String numeroOS;
  /// Quantidade de embalagens/peças compradas (o que o usuário digita como "qtd").
  final double quantidade;
  /// Quantidade da unidade de medida por embalagem/peça
  /// (ex: 50 M/L por lona, 18000 ML por lata de thinner).
  /// Quando não nulo e > 0, o estoque recebe quantidade × qtdUnidade.
  final double? qtdUnidade;
  final double precoUnitario;
  final double? precoMetroQuadrado;
  final double precoTotal;
  final bool usarM2;

  OrdemCompraItemModel({
    this.id,
    this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.descricaoItem,
    required this.numeroOS,
    required this.quantidade,
    this.qtdUnidade,
    required this.precoUnitario,
    this.precoMetroQuadrado,
    required this.precoTotal,
    this.usarM2 = false,
  });

  /// Quantidade real que entra no estoque ao finalizar a OC.
  ///
  /// Se [qtdUnidade] foi informado na OC, usa quantidade × qtdUnidade.
  /// Exemplo: 2 lonas × 50 M/L cada → 100 M/L no estoque.
  /// Caso contrário, retorna [quantidade] diretamente.
  double get quantidadeEstoque {
    if (usarM2) return quantidade;
    if (qtdUnidade != null && qtdUnidade! > 0) return quantidade * qtdUnidade!;
    return quantidade;
  } 

  factory OrdemCompraItemModel.fromJson(Map<String, dynamic> json) => OrdemCompraItemModel(
    id:                     json['id'],
    materialId:             (json['materialId'] as num?)?.toInt(),
    materialNome:           json['material']?['nome'] ?? '',
    materialUnidade:        json['material']?['unidade'],
    materialMedida:         json['material']?['medida'],
    materialEspessura:      json['material']?['espessura'],
    materialIdentificador:  json['material']?['identificador'],
    descricaoItem:          json['descricaoItem'],
    numeroOS:               json['numeroOS'] ?? '',
    quantidade:             double.tryParse(json['quantidade']?.toString() ?? '0') ?? 0,
    qtdUnidade:             json['qtdUnidade'] != null
        ? double.tryParse(json['qtdUnidade'].toString())
        : null,
    precoUnitario:          double.tryParse(json['precoUnitario']?.toString() ?? '0') ?? 0,
    precoMetroQuadrado:     json['precoMetroQuadrado'] != null
        ? double.tryParse(json['precoMetroQuadrado'].toString())
        : null,
    precoTotal:             double.tryParse(json['precoTotal']?.toString() ?? '0') ?? 0,
    usarM2:                 json['usarM2'] == true,
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
  final String status;
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
    id:             json['id'] ?? 0,
    data:           json['data'] != null
        ? DateTime.tryParse(json['data'].toString()) ?? DateTime.now()
        : DateTime.now(),
    fornecedorId:   json['fornecedorId'] ?? 0,
    fornecedorNome: json['fornecedor']?['nomeFantasia'],
    requisitante:   json['requisitante'] ?? '',
    formaPagamento: json['formaPagamento'],
    prazoPagamento: json['prazoPagamento'],
    observacoes:    json['observacoes'],
    empresa:        json['empresa'],
    status:         json['status'] ?? 'EM_ANDAMENTO',
    valorTotal:     double.tryParse(json['valorTotal']?.toString() ?? '0') ?? 0,
    itens:          (json['itens'] as List? ?? [])
        .map((i) => OrdemCompraItemModel.fromJson(i as Map<String, dynamic>))
        .toList(),
    numerosOS: (json['numerosOS'] as List? ?? [])
        .map((o) => o['numeroOS'].toString())
        .toList(),
  );
}