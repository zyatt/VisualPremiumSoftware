class HistoricoPrecoModel {
  final int id;
  final int materialId;
  final int? ordemCompraId;
  final int? fornecedorId;
  final String fornecedorNome;
  final double precoUnitario;
  final double? precoM2;
  final double quantidade;
  final DateTime criadoEm;

  final DateTime? dataOrdem;

  HistoricoPrecoModel({
    required this.id,
    required this.materialId,
    this.ordemCompraId,
    this.fornecedorId,
    required this.fornecedorNome,
    required this.precoUnitario,
    this.precoM2,
    required this.quantidade,
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
        criadoEm:   DateTime.parse(json['criadoEm']),
        dataOrdem:  json['ordemCompra']?['data'] != null
            ? DateTime.tryParse(json['ordemCompra']['data'].toString())
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
        id:                 (json['id'] as num?)?.toInt() ?? 0,
        fornecedorId:       (json['fornecedorId'] as num?)?.toInt() ?? 0,
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

  factory MaterialModel.fromJson(Map<String, dynamic> json) => MaterialModel(
        id:                 (json['id'] as num?)?.toInt() ?? 0,
        nome:               json['nome'] ?? '',
        unidade:            json['unidade'],
        categoria:          json['categoria'],
        medida:             json['medida'],
        espessura:          json['espessura'],
        identificador:      json['identificador'],
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
        ultimoValorPago:    json['custoUltimaCompra'] != null
            ? double.tryParse(json['custoUltimaCompra'].toString())
            : null,
        ultimoValorPagoM2:  json['custoM2UltimaCompra'] != null
            ? double.tryParse(json['custoM2UltimaCompra'].toString())
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
        historicoPrecos: (json['historicoPrecos'] as List? ?? [])
            .map((h) => HistoricoPrecoModel.fromJson(h as Map<String, dynamic>))
            .toList(),
      );
}