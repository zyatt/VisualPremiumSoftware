class MateriaisPaginadosModel {
  final List<MaterialModel> itens;
  final int total;

  const MateriaisPaginadosModel({required this.itens, required this.total});
}

class HistoricoPrecoModel {
  final int id;
  final int materialId;
  final int? ordemCompraId;
  final int? fornecedorId;
  final String fornecedorNome;
  final double precoUnitario;
  final double? precoM2;
  final double quantidade;
  final bool usarM2;
  final DateTime criadoEm;
  final DateTime? dataOrdem;

  double get total {
    if (usarM2 && precoM2 != null && precoM2! > 0) return quantidade * precoM2!;
    return quantidade * precoUnitario;
  }

  HistoricoPrecoModel({
    required this.id,
    required this.materialId,
    this.ordemCompraId,
    this.fornecedorId,
    required this.fornecedorNome,
    required this.precoUnitario,
    this.precoM2,
    required this.quantidade,
    this.usarM2 = false,
    required this.criadoEm,
    this.dataOrdem,
  });

  factory HistoricoPrecoModel.fromJson(Map<String, dynamic> json) =>
      HistoricoPrecoModel(
        id:             (json['id'] as num?)?.toInt() ?? 0,
        materialId:     (json['materialId'] as num?)?.toInt() ?? 0,
        ordemCompraId:  (json['ordemCompraId'] as num?)?.toInt(),
        fornecedorId:   (json['fornecedorId'] as num?)?.toInt(),
        fornecedorNome: json['fornecedor']?['nomeFantasia'] ?? '—',
        precoUnitario:  double.tryParse(json['precoUnitario'].toString()) ?? 0,
        precoM2:        json['precoM2'] != null
            ? double.tryParse(json['precoM2'].toString())
            : null,
        quantidade: double.tryParse(json['quantidade'].toString()) ?? 0,
        usarM2:     json['usarM2'] ?? false,
        criadoEm:   DateTime.parse(json['criadoEm']).toLocal(),
        dataOrdem:  json['ordemCompra']?['data'] != null
            ? DateTime.tryParse(json['ordemCompra']['data'].toString())?.toLocal()
            : null,
      );
}

class FornecedorMaterialModel {
  final int id;
  final int fornecedorId;
  final String fornecedorNome;
  final double preco;
  final double precoMetroQuadrado;
  final bool ativo;
  final double? materialLargura;
  final double? materialComprimento;

  bool get usarM2 => precoMetroQuadrado > 0;

  FornecedorMaterialModel({
    required this.id,
    required this.fornecedorId,
    required this.fornecedorNome,
    required this.preco,
    required this.precoMetroQuadrado,
    required this.ativo,
    this.materialLargura,
    this.materialComprimento,
  });

  factory FornecedorMaterialModel.fromJson(Map<String, dynamic> json) =>
      FornecedorMaterialModel(
        id:                 (json['id'] as num?)?.toInt() ?? 0,
        fornecedorId:       (json['fornecedorId'] as num?)?.toInt() ?? 0,
        fornecedorNome:     json['fornecedor']?['nomeFantasia'] ?? '',
        preco:              json['preco'] != null
            ? double.tryParse(json['preco'].toString()) ?? 0
            : 0,
        precoMetroQuadrado: json['precoMetroQuadrado'] != null
            ? double.tryParse(json['precoMetroQuadrado'].toString()) ?? 0
            : 0,
        ativo:              json['ativo'] ?? true,
        materialLargura:    json['material']?['largura'] != null
            ? double.tryParse(json['material']['largura'].toString())
            : null,
        materialComprimento: json['material']?['comprimento'] != null
            ? double.tryParse(json['material']['comprimento'].toString())
            : null,
      );
}

class MaterialCriticoNotificacao {
  final int materialId;
  final String nome;
  final String? identificador;
  final String? medida;
  final String? espessura;
  final String? unidade;
  final String? categoria;
  final double quantidade;
  final double estoqueMinimo;

  MaterialCriticoNotificacao({
    required this.materialId,
    required this.nome,
    this.identificador,
    this.medida,
    this.espessura,
    this.unidade,
    this.categoria,
    required this.quantidade,
    required this.estoqueMinimo,
  });

  factory MaterialCriticoNotificacao.fromJson(Map<String, dynamic> json) =>
      MaterialCriticoNotificacao(
        materialId:    (json['materialId'] as num?)?.toInt() ?? 0,
        nome:          json['nome'] ?? '',
        identificador: json['identificador'],
        medida:        json['medida'],
        espessura:     json['espessura'],
        unidade:       json['unidade'],
        categoria:     json['categoria'],
        quantidade:    double.tryParse(json['quantidade'].toString()) ?? 0,
        estoqueMinimo: double.tryParse(json['estoqueMinimo'].toString()) ?? 0,
      );
}

class MaterialModel {
  final int id;
  final String nome;
  final String? unidade;
  final String? categoria;
  final String? medida;
  final String? espessura;
  final double? largura;
  final double? comprimento;
  final String? identificador;
  final double? valor;
  final double? valorMetroQuadrado;
  final double quantidade;
  final double estoqueMinimo;
  final String status;
  final bool estoqueConfirmado;
  final bool ativo;

  final double? ultimoValorPago;
  final double? ultimoValorPagoM2;
  final double? precoMediano;
  final double? precoM2Mediano;

  final List<FornecedorMaterialModel> fornecedorMateriais;
  final List<HistoricoPrecoModel> historicoPrecos;

  MaterialModel({
    required this.id,
    required this.nome,
    this.unidade,
    this.categoria,
    this.medida,
    this.espessura,
    this.largura,
    this.comprimento,
    this.identificador,
    this.valor,
    this.valorMetroQuadrado,
    required this.quantidade,
    required this.estoqueMinimo,
    required this.status,
    required this.estoqueConfirmado,
    required this.ativo,
    this.ultimoValorPago,
    this.ultimoValorPagoM2,
    this.precoMediano,
    this.precoM2Mediano,
    this.fornecedorMateriais = const [],
    this.historicoPrecos = const [],
  });

  double? get qtdM2 {
    if (largura == null || comprimento == null) return null;
    if (largura! <= 0 || comprimento! <= 0) return null;
    return largura! * comprimento! * quantidade;
  }

  double? get areaUnitariaM2 {
    if (largura == null || comprimento == null) return null;
    if (largura! <= 0 || comprimento! <= 0) return null;
    return largura! * comprimento!;
  }

  factory MaterialModel.fromJson(Map<String, dynamic> json) {
    double? parseDoubleOrNull(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final str = value.toString().trim();
      if (str.isEmpty) return null;
      return double.tryParse(str);
    }

    return MaterialModel(
      id:                 (json['id'] as num?)?.toInt() ?? 0,
      nome:               json['nome'] ?? '',
      unidade:            json['unidade'],
      categoria:          json['categoria'],
      medida:             json['medida'],
      espessura:          json['espessura'],
      largura:            parseDoubleOrNull(json['largura']),
      comprimento:        parseDoubleOrNull(json['comprimento']),
      identificador:      json['identificador'],
      valor:              parseDoubleOrNull(json['valor']),
      valorMetroQuadrado: parseDoubleOrNull(json['valorMetroQuadrado']),
      quantidade:         double.tryParse(json['quantidade'].toString()) ?? 0,
      estoqueMinimo:      double.tryParse(json['estoqueMinimo'].toString()) ?? 0,
      status:             json['status'] ?? 'OK',
      estoqueConfirmado:  json['estoqueConfirmado'] ?? false,
      ativo:              json['ativo'] ?? true,
      ultimoValorPago:    parseDoubleOrNull(json['custoUltimaCompra']),
      ultimoValorPagoM2:  parseDoubleOrNull(json['custoM2UltimaCompra']),
      precoMediano:       parseDoubleOrNull(json['precoMediano']),
      precoM2Mediano:     parseDoubleOrNull(json['precoM2Mediano']),
      fornecedorMateriais: (json['fornecedorMateriais'] as List? ?? [])
          .map((f) => FornecedorMaterialModel.fromJson(f as Map<String, dynamic>))
          .toList(),
      historicoPrecos: (json['historicoPrecos'] as List? ?? [])
          .map((h) => HistoricoPrecoModel.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }
}