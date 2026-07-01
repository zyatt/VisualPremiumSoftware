class MaterialProducaoModel {
  final int id;
  final String nome;
  final String? identificador;
  final String? categoria;
  final String? medida;
  final String? espessura;
  final String? unidade;
  final double? largura;
  final double? comprimento;
  final double quantidade;
  final double emUso;
  final double estoqueMinimo;
  final String statusReal;
  final double? ultimoValorPago;
  final double? ultimoValorPagoM2;

  MaterialProducaoModel({
    required this.id,
    required this.nome,
    this.identificador,
    this.categoria,
    this.medida,
    this.espessura,
    this.unidade,
    this.largura,
    this.comprimento,
    required this.quantidade,
    required this.emUso,
    required this.estoqueMinimo,
    required this.statusReal,
    this.ultimoValorPago,
    this.ultimoValorPagoM2,
  });

  factory MaterialProducaoModel.fromJson(Map<String, dynamic> json) {
    // Helper para converter valores que podem vir como string ou number
    double parseDouble(dynamic value, double defaultValue) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? defaultValue;
    }

    double? parseDoubleOrNull(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final str = value.toString().trim();
      if (str.isEmpty) return null;
      return double.tryParse(str);
    }

    return MaterialProducaoModel(
      id:             (json['id'] as num?)?.toInt() ?? 0,
      nome:           json['nome']?.toString() ?? '',
      identificador:  json['identificador']?.toString(),
      categoria:      json['categoria']?.toString(),
      medida:         json['medida']?.toString(),
      espessura:      json['espessura']?.toString(),
      unidade:        json['unidade']?.toString(),
      largura:        parseDoubleOrNull(json['largura']),
      comprimento:    parseDoubleOrNull(json['comprimento']),
      quantidade:     parseDouble(json['quantidade'], 0.0),
      emUso:          parseDouble(json['emUso'], 0.0),
      estoqueMinimo:  parseDouble(json['estoqueMinimo'], 0.0),
      statusReal:     json['statusReal']?.toString() ?? 'OK',
      ultimoValorPago:   parseDoubleOrNull(json['custoUltimaCompra'] ?? json['ultimoValorPago']),
      ultimoValorPagoM2: parseDoubleOrNull(json['custoM2UltimaCompra'] ?? json['ultimoValorPagoM2']),
    );
  }
}

class SolicitacaoProducaoModel {
  final int id;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final String? descricaoItem;
  final double quantidadeReservada;
  final double quantidadeUsada;
  final String numeroOS;
  final String usuarioNome;
  final DateTime criadoEm;
  final DateTime atualizadoEm;
  final DateTime? finalizadoEm;
  final List<BaixaProducaoModel> baixas;

  SolicitacaoProducaoModel({
    required this.id,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.descricaoItem,
    required this.quantidadeReservada,
    required this.quantidadeUsada,
    required this.numeroOS,
    required this.usuarioNome,
    required this.criadoEm,
    required this.atualizadoEm,
    this.finalizadoEm,
    required this.baixas,
  });

  double get saldoEmUso => quantidadeReservada - quantidadeUsada;
  bool get estaFinalizada => saldoEmUso <= 0;

  factory SolicitacaoProducaoModel.fromJson(Map<String, dynamic> json) {
    return SolicitacaoProducaoModel(
      id:                  (json['id'] as num?)?.toInt() ?? 0,
      materialId:          (json['materialId'] as num?)?.toInt() ?? 0,
      materialNome:        json['material']?['nome']?.toString() ?? '',
      materialUnidade:     json['material']?['unidade']?.toString(),
      materialIdentificador: json['material']?['identificador']?.toString(),
      materialMedida:      json['material']?['medida']?.toString(),
      materialEspessura:   json['material']?['espessura']?.toString(),
      descricaoItem:       json['descricaoItem']?.toString(),
      quantidadeReservada: double.tryParse(json['quantidadeReservada']?.toString() ?? '0') ?? 0.0,
      quantidadeUsada:     double.tryParse(json['quantidadeUsada']?.toString() ?? '0') ?? 0.0,
      numeroOS:            json['numeroOS']?.toString() ?? '',
      usuarioNome:         json['usuarioNome']?.toString() ?? '',
      criadoEm:            (DateTime.tryParse(json['criadoEm']?.toString() ?? '') ?? DateTime.now()).toLocal(),
      atualizadoEm:        (DateTime.tryParse(json['atualizadoEm']?.toString() ?? '') ?? DateTime.now()).toLocal(),
      finalizadoEm:        json['finalizadoEm'] != null
          ? DateTime.tryParse(json['finalizadoEm'].toString())?.toLocal()
          : null,
      baixas: (json['baixas'] as List?)
              ?.map((e) => BaixaProducaoModel.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class BaixaProducaoModel {
  final int id;
  final double quantidade;
  final String? observacao;
  final DateTime criadoEm;

  BaixaProducaoModel({
    required this.id,
    required this.quantidade,
    this.observacao,
    required this.criadoEm,
  });

  factory BaixaProducaoModel.fromJson(Map<String, dynamic> json) {
    return BaixaProducaoModel(
      id:         (json['id'] as num?)?.toInt() ?? 0,
      quantidade: double.tryParse(json['quantidade']?.toString() ?? '0') ?? 0.0,
      observacao: json['observacao']?.toString(),
      criadoEm:   (DateTime.tryParse(json['criadoEm']?.toString() ?? '') ?? DateTime.now()).toLocal(),
    );
  }
}