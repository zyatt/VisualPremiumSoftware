
// ── Item de material vinculado ao produto ─────────────────────────────────────
class ProdutoMaterialModel {
  final int id;
  final int produtoId;
  final int materialId;
  final double quantidade;
  final String? observacao;
  final MaterialItemEmbutido material;

  ProdutoMaterialModel({
    required this.id,
    required this.produtoId,
    required this.materialId,
    required this.quantidade,
    this.observacao,
    required this.material,
  });

  factory ProdutoMaterialModel.fromJson(Map<String, dynamic> json) {
    return ProdutoMaterialModel(
      id:         (json['id'] as num?)?.toInt() ?? 0,
      produtoId:  (json['produtoId'] as num?)?.toInt() ?? 0,
      materialId: (json['materialId'] as num?)?.toInt() ?? 0,
      quantidade: double.tryParse(json['quantidade'].toString()) ?? 1,
      observacao: json['observacao'],
      material:   MaterialItemEmbutido.fromJson(
          json['material'] as Map<String, dynamic>? ?? {}),
    );
  }
}

// ── Material embutido (snapshot simplificado usado dentro de Produto) ─────────
class MaterialItemEmbutido {
  final int id;
  final String nome;
  final String? unidade;
  final String? categoria;
  final String? medida;
  final String? espessura;
  final String? identificador;
  final double? ultimoValorPago;
  final double? ultimoValorPagoM2;
  final double? precoMedio;
  final double? precoMedioM2;
  /// Dimensões de referência da chapa/folha (vêm do cadastro do material).
  /// Quando ambos estão preenchidos, o sistema calcula o custo por m² e
  /// aplica nas dimensões informadas pelo usuário no orçamento.
  final double? largura;
  final double? comprimento;

  MaterialItemEmbutido({
    required this.id,
    required this.nome,
    this.unidade,
    this.categoria,
    this.medida,
    this.espessura,
    this.identificador,
    this.ultimoValorPago,
    this.ultimoValorPagoM2,
    this.precoMedio,
    this.precoMedioM2,
    this.largura,
    this.comprimento,
  });

  factory MaterialItemEmbutido.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) {
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    return MaterialItemEmbutido(
      id:               (json['id'] as num?)?.toInt() ?? 0,
      nome:             json['nome'] ?? '',
      unidade:          json['unidade'],
      categoria:        json['categoria'],
      medida:           json['medida'],
      espessura:        json['espessura'],
      identificador:    json['identificador'],
      ultimoValorPago:  d(json['ultimoValorPago']),
      ultimoValorPagoM2: d(json['ultimoValorPagoM2']),
      precoMedio:       d(json['precoMedio']),
      precoMedioM2:     d(json['precoMedioM2']),
      largura:          d(json['largura']),
      comprimento:      d(json['comprimento']),
    );
  }

  /// Preço de referência: prefere último valor pago; cai pro médio; null se nenhum.
  double? get precoRef => ultimoValorPago ?? precoMedio;
  double? get precoRefM2 => ultimoValorPagoM2 ?? precoMedioM2;
}

// ── Produto ───────────────────────────────────────────────────────────────────
class ProdutoModel {
  final int id;
  final String nome;
  final String? descricao;
  final String? categoria;
  final bool ativo;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final List<ProdutoMaterialModel> materiais;

  ProdutoModel({
    required this.id,
    required this.nome,
    this.descricao,
    this.categoria,
    required this.ativo,
    this.criadoEm,
    this.atualizadoEm,
    this.materiais = const [],
  });

  /// Custo estimado total (soma de quantidade × preçoRef de cada material).
  /// Retorna null se nenhum material tem preço.
  double? get custoEstimado {
    double total = 0;
    bool temAlgum = false;
    for (final pm in materiais) {
      final ref = pm.material.precoRef;
      if (ref != null && ref > 0) {
        total += pm.quantidade * ref;
        temAlgum = true;
      }
    }
    return temAlgum ? total : null;
  }

  factory ProdutoModel.fromJson(Map<String, dynamic> json) {
    return ProdutoModel(
      id:           (json['id'] as num?)?.toInt() ?? 0,
      nome:         json['nome'] ?? '',
      descricao:    json['descricao'],
      categoria:    json['categoria'],
      ativo:        json['ativo'] ?? true,
      criadoEm:     json['criadoEm'] != null
          ? DateTime.tryParse(json['criadoEm'].toString())?.toLocal()
          : null,
      atualizadoEm: json['atualizadoEm'] != null
          ? DateTime.tryParse(json['atualizadoEm'].toString())?.toLocal()
          : null,
      materiais: (json['materiais'] as List? ?? [])
          .map((e) => ProdutoMaterialModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}