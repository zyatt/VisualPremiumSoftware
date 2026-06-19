class OrdemCompraItemModel {
  final int? id;
  final int materialId;
  final String materialNome;
  /// Unidade de medida do material no estoque (ex: "UNIDADE", "ML", "M/L", "KG").
  final String? materialUnidade;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialIdentificador;
  final double? materialQtdPadrao;
  final String? materialUnidPadrao;
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
  final bool materialEspecifico;

  OrdemCompraItemModel({
    this.id,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.materialQtdPadrao,
    this.materialUnidPadrao,
    this.descricaoItem,
    required this.numeroOS,
    required this.quantidade,
    this.qtdUnidade,
    required this.precoUnitario,
    this.precoMetroQuadrado,
    required this.precoTotal,
    this.usarM2 = false,
    this.materialEspecifico = false,
  });

  /// Quantidade real que entra no estoque ao finalizar a OC.
  ///
  /// Prioridade:
  /// 1. Se [qtdUnidade] foi informado na OC (novo fluxo), usa quantidade × qtdUnidade.
  ///    Exemplo: 2 lonas × 50 M/L cada → 100 M/L no estoque.
  /// 2. Se o material tem [materialQtdPadrao] (fluxo legado), usa quantidade × qtdPadrao.
  ///    Exemplo: 2 latas de thinner 18000 ml → 36000 ml no estoque.
  /// 3. Caso contrário, retorna [quantidade] diretamente.
  double get quantidadeEstoque {
    if (usarM2) return quantidade;
    // Novo fluxo: qtdUnidade informada explicitamente na OC
    if (qtdUnidade != null && qtdUnidade! > 0) return quantidade * qtdUnidade!;
    // Fluxo legado: qtdPadrao do cadastro do material
    final qtd = materialQtdPadrao;
    if (qtd == null || qtd <= 0) return quantidade;
    return quantidade * qtd;
  }

  /// Custo calculado por unidade de medida (M/L, ML, KG etc.).
  ///
  /// Usa [qtdUnidade] quando disponível (novo fluxo), senão [materialQtdPadrao].
  /// Retorna null quando nenhum dos dois está definido ou usarM2 está ativo.
  double? get custoPorUnidPadrao {
    if (usarM2) return null;
    final qtd = qtdUnidade ?? materialQtdPadrao;
    if (qtd == null || qtd <= 0) return null;
    if (precoUnitario <= 0) return null;
    return precoUnitario / qtd;
  }

  factory OrdemCompraItemModel.fromJson(Map<String, dynamic> json) => OrdemCompraItemModel(
    id:                     json['id'],
    materialId:             json['materialId'] ?? 0,
    materialNome:           json['material']?['nome'] ?? '',
    materialUnidade:        json['material']?['unidade'],
    materialMedida:         json['material']?['medida'],
    materialEspessura:      json['material']?['espessura'],
    materialIdentificador:  json['material']?['identificador'],
    materialQtdPadrao:      json['material']?['qtdPadrao'] != null
        ? double.tryParse(json['material']['qtdPadrao'].toString())
        : null,
    materialUnidPadrao:     json['material']?['unidPadrao'],
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
    materialEspecifico:     json['material']?['especifico'] == true,
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