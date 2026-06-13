// ─────────────────────────────────────────────────────────────────────────────
// Modelo de gasto por categoria (OS fechadas)
// ─────────────────────────────────────────────────────────────────────────────

class GastoMaterialModel {
  final int id;
  final String nome;
  final String? unidade;
  final String? identificador;
  final String? medida;
  final String? espessura;
  final double totalEntrada;
  final double totalSaida;
  final double qtdEntrada;
  final double qtdSaida;

  const GastoMaterialModel({
    required this.id,
    required this.nome,
    this.unidade,
    this.identificador,
    this.medida,
    this.espessura,
    required this.totalEntrada,
    required this.totalSaida,
    required this.qtdEntrada,
    required this.qtdSaida,
  });

  factory GastoMaterialModel.fromJson(Map<String, dynamic> json) =>
      GastoMaterialModel(
        id:           (json['id'] as num?)?.toInt() ?? 0,
        nome:         json['nome'] ?? '',
        unidade:      json['unidade'],
        identificador: json['identificador'],
        medida:       json['medida'],
        espessura:    json['espessura'],
        totalEntrada: (json['totalEntrada'] as num?)?.toDouble() ?? 0,
        totalSaida:   (json['totalSaida']   as num?)?.toDouble() ?? 0,
        qtdEntrada:   (json['qtdEntrada']   as num?)?.toDouble() ?? 0,
        qtdSaida:     (json['qtdSaida']     as num?)?.toDouble() ?? 0,
      );
}

class GastoCategoriaModel {
  /// null = materiais sem categoria
  final String? categoria;
  final double totalEntrada;
  final double totalSaida;
  final double qtdEntrada;
  final double qtdSaida;
  final List<GastoMaterialModel> materiais;

  const GastoCategoriaModel({
    this.categoria,
    required this.totalEntrada,
    required this.totalSaida,
    required this.qtdEntrada,
    required this.qtdSaida,
    required this.materiais,
  });

  String get categoriaLabel => categoria ?? 'Sem categoria';

  double get totalGeral => totalEntrada;

  factory GastoCategoriaModel.fromJson(Map<String, dynamic> json) =>
      GastoCategoriaModel(
        categoria:    json['categoria'],
        totalEntrada: (json['totalEntrada'] as num?)?.toDouble() ?? 0,
        totalSaida:   (json['totalSaida']   as num?)?.toDouble() ?? 0,
        qtdEntrada:   (json['qtdEntrada']   as num?)?.toDouble() ?? 0,
        qtdSaida:     (json['qtdSaida']     as num?)?.toDouble() ?? 0,
        materiais: (json['materiais'] as List? ?? [])
            .map((m) => GastoMaterialModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de gasto mensal (para o gráfico)
// ─────────────────────────────────────────────────────────────────────────────

class GastoMensalModel {
  /// Ex: "2024-03"
  final String mesAno;
  final int    ano;
  final int    mes;
  final double totalEntrada;
  final double totalSaida;

  const GastoMensalModel({
    required this.mesAno,
    required this.ano,
    required this.mes,
    required this.totalEntrada,
    required this.totalSaida,
  });

  double get total => totalEntrada;

  /// Rótulo curto: "Jan", "Fev", …
  static const _meses = [
    '', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];
  String get label => _meses[mes];

  factory GastoMensalModel.fromJson(Map<String, dynamic> json) {
    final parts = (json['mesAno'] as String).split('-');
    return GastoMensalModel(
      mesAno:       json['mesAno'] as String,
      ano:          int.parse(parts[0]),
      mes:          int.parse(parts[1]),
      totalEntrada: (json['totalEntrada'] as num?)?.toDouble() ?? 0,
      totalSaida:   (json['totalSaida']   as num?)?.toDouble() ?? 0,
    );
  }
}