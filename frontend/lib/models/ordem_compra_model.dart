/// Nome de exibição do material: "NOME DESCRICAO" quando o material é uma
/// variante vinculada a um genérico (ex.: "TINTA" + descricao "teste123"),
/// ou apenas o nome quando não há descrição. Mesma lógica usada em
/// orcamento_model.dart — sem isso, itens cujo material genérico foi
/// resolvido para um filho concreto no backend voltam a aparecer com o
/// nome "pelado" do pai (ex.: só "TINTA"), escondendo a descrição que
/// migrou para o próprio Material.
String _nomeExibicaoMaterial(dynamic material) {
  if (material == null) return '';
  final nome = material['nome'] ?? '';
  final descricao = material['descricao'];
  if (descricao != null && descricao.toString().trim().isNotEmpty) {
    return '$nome · ${descricao.toString().trim()}';
  }
  return nome;
}

class OrdemCompraItemModel {
  final int? id;
  final int? materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialIdentificador;
  final double? materialLargura;
  final double? materialComprimento;
  final String? descricaoItem;
  final String numeroOS;
  final double quantidade;
  final double? qtdUnidade;
  final double precoUnitario;
  final double? precoMetroQuadrado;
  final double precoTotal;
  final bool usarM2;
  // Só true se o material retornado pelo backend ainda for o genérico
  // "pai" (ex.: item legado ou algum fluxo que não resolveu a variante).
  // Itens normais, já resolvidos, apontam pro Material filho concreto e
  // vêm com isso false — a descrição nesse caso já faz parte do nome.
  final bool ehGenerico;

  OrdemCompraItemModel({
    this.id,
    this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.materialLargura,
    this.materialComprimento,
    this.descricaoItem,
    this.ehGenerico = false,
    required this.numeroOS,
    required this.quantidade,
    this.qtdUnidade,
    required this.precoUnitario,
    this.precoMetroQuadrado,
    required this.precoTotal,
    this.usarM2 = false,
  });

  double get quantidadeEstoque {
    if (usarM2) return quantidade;
    if (qtdUnidade != null && qtdUnidade! > 0) return quantidade * qtdUnidade!;
    return quantidade;
  } 

  factory OrdemCompraItemModel.fromJson(Map<String, dynamic> json) => OrdemCompraItemModel(
    id:                     json['id'],
    materialId:             (json['materialId'] as num?)?.toInt(),
    materialNome:           _nomeExibicaoMaterial(json['material']),
    materialUnidade:        json['material']?['unidade'],
    materialMedida:         json['material']?['medida'],
    materialEspessura:      json['material']?['espessura'],
    materialIdentificador:  json['material']?['identificador'],
    materialLargura:        json['material']?['largura'] != null
        ? double.tryParse(json['material']['largura'].toString())
        : null,
    materialComprimento:    json['material']?['comprimento'] != null
        ? double.tryParse(json['material']['comprimento'].toString())
        : null,
    descricaoItem:          json['descricaoItem'],
    ehGenerico:             json['material']?['ehGenerico'] ?? false,
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