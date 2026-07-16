/// Representa o saldo de um material dentro do estoque de produção
/// (separado do estoque normal). Alimentado por transferências feitas na
/// página de Controle de Estoque.
class MaterialEstoqueProducaoModel {
  final int id;
  final String nome;
  final String? unidade;
  final String? categoria;
  final String? identificador;
  final String? medida;
  final String? espessura;
  final double? largura;
  final double? comprimento;
  final double? ultimoValorPago;
  final double? ultimoValorPagoM2;
  final double quantidade;

  MaterialEstoqueProducaoModel({
    required this.id,
    required this.nome,
    this.unidade,
    this.categoria,
    this.identificador,
    this.medida,
    this.espessura,
    this.largura,
    this.comprimento,
    this.ultimoValorPago,
    this.ultimoValorPagoM2,
    required this.quantidade,
  });

  factory MaterialEstoqueProducaoModel.fromJson(Map<String, dynamic> json) {
    double? parseDoubleOrNull(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final str = value.toString().trim();
      if (str.isEmpty) return null;
      return double.tryParse(str);
    }

    return MaterialEstoqueProducaoModel(
      id:            (json['id'] as num?)?.toInt() ?? 0,
      nome:          json['nome']?.toString() ?? '',
      unidade:       json['unidade']?.toString(),
      categoria:     json['categoria']?.toString(),
      identificador: json['identificador']?.toString(),
      medida:        json['medida']?.toString(),
      espessura:     json['espessura']?.toString(),
      largura:       parseDoubleOrNull(json['largura']),
      comprimento:   parseDoubleOrNull(json['comprimento']),
      ultimoValorPago:   parseDoubleOrNull(json['ultimoValorPago']),
      ultimoValorPagoM2: parseDoubleOrNull(json['ultimoValorPagoM2']),
      quantidade: double.tryParse(json['quantidade'].toString()) ?? 0,
    );
  }
}

/// Uma linha do histórico do estoque de produção: TRANSFERENCIA (entrada
/// vinda do estoque normal) ou BAIXA (saída para uma OS).
class MovimentacaoProducaoModel {
  final int id;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final String tipo; // 'TRANSFERENCIA' | 'BAIXA'
  final double quantidade;
  final String? numeroOS;
  final String? observacao;
  final String? usuarioNome;
  final DateTime criadoEm;

  MovimentacaoProducaoModel({
    required this.id,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    required this.tipo,
    required this.quantidade,
    this.numeroOS,
    this.observacao,
    this.usuarioNome,
    required this.criadoEm,
  });

  bool get ehTransferencia => tipo == 'TRANSFERENCIA';
  bool get ehBaixa => tipo == 'BAIXA';

  factory MovimentacaoProducaoModel.fromJson(Map<String, dynamic> json) {
    return MovimentacaoProducaoModel(
      id:                    (json['id'] as num?)?.toInt() ?? 0,
      materialId:            (json['materialId'] as num?)?.toInt() ?? 0,
      materialNome:          json['material']?['nome']?.toString() ?? '(material excluído)',
      materialUnidade:       json['material']?['unidade']?.toString(),
      materialIdentificador: json['material']?['identificador']?.toString(),
      materialMedida:        json['material']?['medida']?.toString(),
      materialEspessura:     json['material']?['espessura']?.toString(),
      tipo:                  json['tipo']?.toString() ?? '',
      quantidade:            double.tryParse(json['quantidade'].toString()) ?? 0,
      numeroOS:              json['numeroOS']?.toString(),
      observacao:            json['observacao']?.toString(),
      usuarioNome:           json['usuarioNome']?.toString(),
      criadoEm:              DateTime.parse(json['criadoEm']).toLocal(),
    );
  }
}
