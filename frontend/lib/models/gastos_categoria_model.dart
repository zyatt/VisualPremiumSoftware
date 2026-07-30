class EstoqueMaterialModel {
  final int     id;
  final String  nome;
  final String? unidade;
  final String? identificador;
  final String? medida;
  final String? espessura;
  final double  quantidade;
  final double  estoqueMinimo;
  final String  status;
  final double? ultimoValorPago;
  final double? ultimoValorPagoM2;
  final double? largura;
  final double? comprimento;
  final double  valorTotal;

  const EstoqueMaterialModel({
    required this.id,
    required this.nome,
    this.unidade,
    this.identificador,
    this.medida,
    this.espessura,
    required this.quantidade,
    required this.estoqueMinimo,
    required this.status,
    this.ultimoValorPago,
    this.ultimoValorPagoM2,
    this.largura,
    this.comprimento,
    required this.valorTotal,
  });

  bool get semCusto =>
      (ultimoValorPago == null || ultimoValorPago! <= 0) &&
      (ultimoValorPagoM2 == null || ultimoValorPagoM2! <= 0);

  factory EstoqueMaterialModel.fromJson(Map<String, dynamic> json) =>
      EstoqueMaterialModel(
        id:                (json['id'] as num?)?.toInt() ?? 0,
        nome:              json['nome'] ?? '',
        unidade:           json['unidade'],
        identificador:     json['identificador'],
        medida:            json['medida'],
        espessura:         json['espessura'],
        quantidade:        (json['quantidade'] as num?)?.toDouble() ?? 0,
        estoqueMinimo:     (json['estoqueMinimo'] as num?)?.toDouble() ?? 0,
        status:            json['status'] ?? 'OK',
        ultimoValorPago:   (json['ultimoValorPago']   as num?)?.toDouble(),
        ultimoValorPagoM2: (json['ultimoValorPagoM2'] as num?)?.toDouble(),
        largura:           (json['largura']    as num?)?.toDouble(),
        comprimento:       (json['comprimento'] as num?)?.toDouble(),
        valorTotal:        (json['valorTotal']  as num?)?.toDouble() ?? 0,
      );
}

class EstoqueCategoriaModel {
  final String?                   categoria;
  final double                    totalValor;
  final int                       qtdMateriais;
  final List<EstoqueMaterialModel> materiais;

  const EstoqueCategoriaModel({
    this.categoria,
    required this.totalValor,
    required this.qtdMateriais,
    required this.materiais,
  });

  String get categoriaLabel => categoria ?? 'Sem categoria';

  factory EstoqueCategoriaModel.fromJson(Map<String, dynamic> json) =>
      EstoqueCategoriaModel(
        categoria:    json['categoria'],
        totalValor:   (json['totalValor']   as num?)?.toDouble() ?? 0,
        qtdMateriais: (json['qtdMateriais'] as num?)?.toInt()    ?? 0,
        materiais: (json['materiais'] as List? ?? [])
            .map((m) => EstoqueMaterialModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class GastoMaterialModel {
  final int     id;
  final String  nome;
  final String? unidade;
  final String? identificador;
  final String? medida;
  final String? espessura;
  final double? largura;
  final double? comprimento;
  final double  totalGasto;
  final double  qtdGasta;

  const GastoMaterialModel({
    required this.id,
    required this.nome,
    this.unidade,
    this.identificador,
    this.medida,
    this.espessura,
    this.largura,
    this.comprimento,
    required this.totalGasto,
    required this.qtdGasta,
  });

  factory GastoMaterialModel.fromJson(Map<String, dynamic> json) =>
      GastoMaterialModel(
        id:            (json['id'] as num?)?.toInt() ?? 0,
        nome:          json['nome'] ?? '',
        unidade:       json['unidade'],
        identificador: json['identificador'],
        medida:        json['medida'],
        espessura:     json['espessura'],
        largura:       (json['largura']     as num?)?.toDouble(),
        comprimento:   (json['comprimento'] as num?)?.toDouble(),
        totalGasto:    (json['totalGasto'] as num?)?.toDouble() ?? 0,
        qtdGasta:      (json['qtdGasta']   as num?)?.toDouble() ?? 0,
      );
}

class GastoCategoriaModel {
  final String?                 categoria;
  final double                  totalGasto;
  final List<GastoMaterialModel> materiais;

  const GastoCategoriaModel({
    this.categoria,
    required this.totalGasto,
    required this.materiais,
  });

  String get categoriaLabel => categoria ?? 'Sem categoria';

  factory GastoCategoriaModel.fromJson(Map<String, dynamic> json) =>
      GastoCategoriaModel(
        categoria:  json['categoria'],
        totalGasto: (json['totalGasto'] as num?)?.toDouble() ?? 0,
        materiais: (json['materiais'] as List? ?? [])
            .map((m) => GastoMaterialModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class GastoMensalModel {
  final String mesAno;
  final int    ano;
  final int    mes;
  final double totalGasto;

  const GastoMensalModel({
    required this.mesAno,
    required this.ano,
    required this.mes,
    required this.totalGasto,
  });

  static const _meses = [
    '', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];
  String get label => _meses[mes];

  factory GastoMensalModel.fromJson(Map<String, dynamic> json) {
    final parts = (json['mesAno'] as String).split('-');
    return GastoMensalModel(
      mesAno:     json['mesAno'] as String,
      ano:        int.parse(parts[0]),
      mes:        int.parse(parts[1]),
      totalGasto: (json['totalGasto'] as num?)?.toDouble() ?? 0,
    );
  }
}