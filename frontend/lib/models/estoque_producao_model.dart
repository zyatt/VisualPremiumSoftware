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
  final double quantidadePendente;
  final String producao;

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
    this.quantidadePendente = 0,
    required this.producao,
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
      quantidadePendente: double.tryParse(json['quantidadePendente']?.toString() ?? '0') ?? 0,
      producao:   json['producao']?.toString() ?? '',
    );
  }
}

class EntradaPendenteModel {
  final int id;
  final String tipo;
  final String status;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final double? materialLargura;
  final double? materialComprimento;
  final double quantidade;
  final String producao;
  final String? numeroOS;
  final String? observacao;
  final String? usuarioNome;
  final DateTime criadoEm;

  EntradaPendenteModel({
    required this.id,
    required this.tipo,
    required this.status,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.materialLargura,
    this.materialComprimento,
    required this.quantidade,
    required this.producao,
    this.numeroOS,
    this.observacao,
    this.usuarioNome,
    required this.criadoEm,
  });

  bool get ehRetalho => tipo == 'RETALHO';
  bool get ehDevolucao => tipo == 'DEVOLUCAO';

  String get descricaoTipo => ehRetalho
      ? 'Retalho gerado na produção $producao'
      : 'Devolução da produção $producao';

  factory EntradaPendenteModel.fromJson(Map<String, dynamic> json) {
    double? parseDoubleOrNull(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final str = value.toString().trim();
      if (str.isEmpty) return null;
      return double.tryParse(str);
    }

    return EntradaPendenteModel(
      id:                    (json['id'] as num?)?.toInt() ?? 0,
      tipo:                  json['tipo']?.toString() ?? '',
      status:                json['status']?.toString() ?? 'PENDENTE',
      materialId:            (json['materialId'] as num?)?.toInt() ?? 0,
      materialNome:          json['material']?['nome']?.toString() ?? '(material excluído)',
      materialUnidade:       json['material']?['unidade']?.toString(),
      materialIdentificador: json['material']?['identificador']?.toString(),
      materialMedida:        json['material']?['medida']?.toString(),
      materialEspessura:     json['material']?['espessura']?.toString(),
      materialLargura:       parseDoubleOrNull(json['material']?['largura']),
      materialComprimento:   parseDoubleOrNull(json['material']?['comprimento']),
      quantidade:            double.tryParse(json['quantidade']?.toString() ?? '0') ?? 0,
      producao:              json['producao']?.toString() ?? '',
      numeroOS:              json['numeroOS']?.toString(),
      observacao:            json['observacao']?.toString(),
      usuarioNome:           json['usuarioNome']?.toString(),
      criadoEm:              DateTime.parse(json['criadoEm']).toLocal(),
    );
  }
}

class MovimentacaoProducaoModel {
  final int id;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final double? materialLargura;
  final double? materialComprimento;
  final String tipo;
  final double quantidade;
  final String? numeroOS;
  final String? observacao;
  final String? usuarioNome;
  final DateTime criadoEm;
  final String producao;

  MovimentacaoProducaoModel({
    required this.id,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.materialLargura,
    this.materialComprimento,
    required this.tipo,
    required this.quantidade,
    this.numeroOS,
    this.observacao,
    this.usuarioNome,
    required this.criadoEm,
    required this.producao,
  });

  bool get ehTransferencia => tipo == 'TRANSFERENCIA';
  bool get ehBaixa => tipo == 'BAIXA';
  bool get ehTransferenciaLinha => tipo == 'TRANSFERENCIA_LINHA';
  bool get ehDevolucao => tipo == 'DEVOLUCAO';

  String get producaoOrigemDerivada => producao == '1' ? '2' : '1';

  String get descricaoOrigem {
    if (ehTransferenciaLinha) {
      return 'Transferência da produção $producaoOrigemDerivada para produção $producao';
    }
    if (ehTransferencia) {
      return 'Transferência do estoque padrão para produção $producao';
    }
    if (ehDevolucao) {
      return 'Devolução da produção $producao para o estoque padrão';
    }
    return 'Baixa da produção $producao';
  }

  bool get ehEstorno =>
      (observacao ?? '').toLowerCase().startsWith('estorno');

  factory MovimentacaoProducaoModel.fromJson(Map<String, dynamic> json) {
    return MovimentacaoProducaoModel(
      id:                    (json['id'] as num?)?.toInt() ?? 0,
      materialId:            (json['materialId'] as num?)?.toInt() ?? 0,
      materialNome:          json['material']?['nome']?.toString() ?? '(material excluído)',
      materialUnidade:       json['material']?['unidade']?.toString(),
      materialIdentificador: json['material']?['identificador']?.toString(),
      materialMedida:        json['material']?['medida']?.toString(),
      materialEspessura:     json['material']?['espessura']?.toString(),
      materialLargura:       json['material']?['largura'] != null
          ? double.tryParse(json['material']['largura'].toString())
          : null,
      materialComprimento:   json['material']?['comprimento'] != null
          ? double.tryParse(json['material']['comprimento'].toString())
          : null,
      tipo:                  json['tipo']?.toString() ?? '',
      quantidade:            double.tryParse(json['quantidade'].toString()) ?? 0,
      numeroOS:              json['numeroOS']?.toString(),
      observacao:            json['observacao']?.toString(),
      usuarioNome:           json['usuarioNome']?.toString(),
      criadoEm:              DateTime.parse(json['criadoEm']).toLocal(),
      producao:              json['producao']?.toString() ?? '',
    );
  }
}