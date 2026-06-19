import 'produto_model.dart';

// ── Material dentro de um item do orçamento de venda ─────────────────────────

class OrcamentoVendaItemMaterialModel {
  final int id;
  final int materialId;
  double quantidade; // mutável — editado pelo usuário
  final double? precoMedio;
  final double? precoMedioM2;
  double? precoUnitario; // mutável — pode ser editado
  final bool usarM2;
  /// Dimensões da peça informadas pelo usuário no orçamento.
  final double? largura;
  final double? comprimento;
  final MaterialItemEmbutido material;

  OrcamentoVendaItemMaterialModel({
    required this.id,
    required this.materialId,
    required this.quantidade,
    this.precoMedio,
    this.precoMedioM2,
    this.precoUnitario,
    required this.usarM2,
    this.largura,
    this.comprimento,
    required this.material,
  });

  /// Preço de referência: prefere precoUnitario, depois último valor pago, depois médio.
  double? get precoRef {
    if (precoUnitario != null && precoUnitario! > 0) return precoUnitario;
    if (usarM2) return precoMedioM2 ?? material.precoRefM2;
    return precoMedio ?? material.precoRef;
  }

  double get subtotal => quantidade * (precoRef ?? 0);

  factory OrcamentoVendaItemMaterialModel.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) => v == null ? null : double.tryParse(v.toString());
    return OrcamentoVendaItemMaterialModel(
      id:            (json['id'] as num?)?.toInt() ?? 0,
      materialId:    (json['materialId'] as num?)?.toInt() ?? 0,
      quantidade:    double.tryParse(json['quantidade'].toString()) ?? 0,
      precoMedio:    d(json['precoMedio']),
      precoMedioM2:  d(json['precoMedioM2']),
      precoUnitario: d(json['precoUnitario']),
      usarM2:        json['usarM2'] ?? false,
      largura:       d(json['largura']),
      comprimento:   d(json['comprimento']),
      material:      MaterialItemEmbutido.fromJson(
          json['material'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'materialId':    materialId,
    'quantidade':    quantidade,
    'precoUnitario': precoUnitario,
    'precoMedio':    precoMedio,
    'precoMedioM2':  precoMedioM2,
    'usarM2':        usarM2,
    'largura':       largura,
    'comprimento':   comprimento,
  };
}

// ── Item (produto) do orçamento de venda ─────────────────────────────────────

class OrcamentoVendaItemModel {
  final int id;
  final int produtoId;
  final double quantidade;
  final String? observacao;
  final String produtoNome;
  final String? produtoCategoria;
  final List<OrcamentoVendaItemMaterialModel> materiais;

  OrcamentoVendaItemModel({
    required this.id,
    required this.produtoId,
    required this.quantidade,
    this.observacao,
    required this.produtoNome,
    this.produtoCategoria,
    required this.materiais,
  });

  double get subtotal => materiais.fold(0, (s, m) => s + m.subtotal);

  factory OrcamentoVendaItemModel.fromJson(Map<String, dynamic> json) {
    final prod = json['produto'] as Map<String, dynamic>? ?? {};
    return OrcamentoVendaItemModel(
      id:               (json['id'] as num?)?.toInt() ?? 0,
      produtoId:        (json['produtoId'] as num?)?.toInt() ?? 0,
      quantidade:       double.tryParse(json['quantidade'].toString()) ?? 1,
      observacao:       json['observacao'],
      produtoNome:      prod['nome'] ?? '',
      produtoCategoria: prod['categoria'],
      materiais: (json['materiais'] as List? ?? [])
          .map((e) => OrcamentoVendaItemMaterialModel.fromJson(
              e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Orçamento de Venda ────────────────────────────────────────────────────────

class OrcamentoVendaModel {
  final int id;
  final String numero;
  final String status;
  final String? observacao;
  final double valorTotal;
  final double? margemLucro;
  final DateTime? criadoEm;
  final String? clienteNome;
  final String? criadorNome;
  final List<OrcamentoVendaItemModel> itens;

  /// Percentual de markup aplicado ao calcular o valorTotal (ex: 400 = 400%).
  /// Null quando o orçamento ainda não foi salvo ou não há faixas configuradas.
  final double? percentualMarkup;

  OrcamentoVendaModel({
    required this.id,
    required this.numero,
    required this.status,
    this.observacao,
    required this.valorTotal,
    this.margemLucro,
    this.criadoEm,
    this.clienteNome,
    this.criadorNome,
    required this.itens,
    this.percentualMarkup,
  });

  factory OrcamentoVendaModel.fromJson(Map<String, dynamic> json) {
    final cliente = json['cliente'] as Map<String, dynamic>?;
    final criador = json['criador'] as Map<String, dynamic>?;

    // Prioriza o campo direto clienteNome, depois o nome do relacionamento cliente
    final nomeCliente = json['clienteNome'] as String? ?? cliente?['nome'] as String?;

    return OrcamentoVendaModel(
      id:               (json['id'] as num?)?.toInt() ?? 0,
      numero:           json['numero'] ?? '',
      status:           json['status'] ?? 'EM_ANDAMENTO',
      observacao:       json['observacao'],
      valorTotal:       double.tryParse(json['valorTotal'].toString()) ?? 0,
      margemLucro:      json['margemLucro'] != null
          ? double.tryParse(json['margemLucro'].toString())
          : null,
      criadoEm:         json['criadoEm'] != null
          ? DateTime.tryParse(json['criadoEm'].toString())?.toLocal()
          : null,
      clienteNome:      nomeCliente,
      criadorNome:      criador?['nome'],
      percentualMarkup: json['percentualMarkup'] != null
          ? double.tryParse(json['percentualMarkup'].toString())
          : null,
      itens: (json['itens'] as List? ?? [])
          .map((e) => OrcamentoVendaItemModel.fromJson(
              e as Map<String, dynamic>))
          .toList(),
    );
  }
}