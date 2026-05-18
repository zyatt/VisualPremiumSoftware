// ─────────────────────────────────────────────────────────────────────────────
// Histórico de preço de custo pago por OC finalizada
// ─────────────────────────────────────────────────────────────────────────────
class HistoricoPrecoModel {
  final int id;
  final int materialId;
  final int ordemCompraId;
  final int fornecedorId;
  final String fornecedorNome;
  final double precoUnitario;
  final double? precoM2;
  final double quantidade;
  final DateTime criadoEm;

  // Data da ordem de compra (pode diferir da data de criação do registro)
  final DateTime? dataOrdem;

  HistoricoPrecoModel({
    required this.id,
    required this.materialId,
    required this.ordemCompraId,
    required this.fornecedorId,
    required this.fornecedorNome,
    required this.precoUnitario,
    this.precoM2,
    required this.quantidade,
    required this.criadoEm,
    this.dataOrdem,
  });

  factory HistoricoPrecoModel.fromJson(Map<String, dynamic> json) =>
      HistoricoPrecoModel(
        id:             json['id'],
        materialId:     json['materialId'],
        ordemCompraId:  json['ordemCompraId'],
        fornecedorId:   json['fornecedorId'],
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

// ─────────────────────────────────────────────────────────────────────────────
// Fornecedor vinculado ao material com preços de tabela
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Material
// ─────────────────────────────────────────────────────────────────────────────
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

  /// Último custo pago (preço unitário da última OC finalizada com este material)
  final double? ultimoValorPago;

  /// Último custo por m² pago (da última OC finalizada com este material)
  final double? ultimoValorPagoM2;

  // Calculados pelo backend (mediana entre fornecedores de tabela)
  final double? precoMediano;
  final double? precoM2Mediano;

  // Fornecedores vinculados com preços de tabela
  final List<FornecedorMaterialModel> fornecedorMateriais;

  // Histórico de custos pagos via OC (opcional — só vem no buscarPorId)
  final List<HistoricoPrecoModel> historicoPrecos;

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
    this.ultimoValorPagoM2,
    this.precoMediano,
    this.precoM2Mediano,
    this.fornecedorMateriais = const [],
    this.historicoPrecos = const [],
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
        ultimoValorPagoM2:  json['ultimoValorPagoM2'] != null
            ? double.tryParse(json['ultimoValorPagoM2'].toString())
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