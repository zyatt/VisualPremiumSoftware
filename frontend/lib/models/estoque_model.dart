class MovimentacaoModel {
  final int id;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final String tipo;
  final double quantidade;
  final String numeroOS;
  final double? precoUnitario;
  final double? precoM2;
  final String? observacao;
  final DateTime criadoEm;
  // Presentes apenas em saídas de material UNIDADE com modo dimensional ativo.
  // Quando não nulos, indicam que precoM2 é o custo proporcional da área usada
  // (não o custo/m² do material), e o valor correto da saída é precoM2 × 1.
  final double? larguraUsada;
  final double? comprimentoUsado;

  MovimentacaoModel({
    required this.id,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    required this.tipo,
    required this.quantidade,
    required this.numeroOS,
    this.precoUnitario,
    this.precoM2,
    this.observacao,
    required this.criadoEm,
    this.larguraUsada,
    this.comprimentoUsado,
  });

  /// Nesse caso, [precoM2] é o custo proporcional total da área consumida, não o custo/m².
  bool get usouModoDimensional =>
      larguraUsada != null && larguraUsada! > 0 &&
      comprimentoUsado != null && comprimentoUsado! > 0;

  factory MovimentacaoModel.fromJson(Map<String, dynamic> json) =>
      MovimentacaoModel(
        id:                    (json['id'] as num?)?.toInt() ?? 0,
        materialId:            (json['materialId'] as num?)?.toInt() ?? 0,
        materialNome:          json['material']?['nome'] ?? '',
        materialUnidade:       json['material']?['unidade'],
        materialIdentificador: json['material']?['identificador'],
        materialMedida:        json['material']?['medida'],
        materialEspessura:     json['material']?['espessura'],
        tipo:                  json['tipo'],
        quantidade:            double.tryParse(json['quantidade'].toString()) ?? 0,
        numeroOS:              json['numeroOS']?.toString() ?? '',
        precoUnitario:         json['precoUnitario'] != null
            ? double.tryParse(json['precoUnitario'].toString())
            : null,
        precoM2:               json['precoM2'] != null
            ? double.tryParse(json['precoM2'].toString())
            : null,
        observacao:            json['observacao'],
        criadoEm:              DateTime.parse(json['criadoEm']).toLocal(),
        larguraUsada:          json['larguraUsada'] != null
            ? double.tryParse(json['larguraUsada'].toString())
            : null,
        comprimentoUsado:      json['comprimentoUsado'] != null
            ? double.tryParse(json['comprimentoUsado'].toString())
            : null,
      );
}

class RelacaoOSModel {
  final int id;
  final String numeroOS;
  final String? descricao;
  // 'EM_ANDAMENTO' | 'FECHADA'
  final String status;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final List<MovimentacaoModel> movimentacoes;

  RelacaoOSModel({
    required this.id,
    required this.numeroOS,
    this.descricao,
    this.status = 'EM_ANDAMENTO',
    this.criadoEm,
    this.atualizadoEm,
    required this.movimentacoes,
  });

  bool get estaFechada => status == 'FECHADA';

  int get totalItens => movimentacoes.length;

  List<String> get materiaisNomes {
    final nomes = movimentacoes.map((m) => m.materialNome).toSet().toList();
    nomes.sort();
    return nomes;
  }

  factory RelacaoOSModel.fromJson(Map<String, dynamic> json) => RelacaoOSModel(
        id:           (json['id'] as num?)?.toInt() ?? 0,
        numeroOS:     json['numeroOS'],
        descricao:    json['descricao'],
        status:       json['status'] ?? 'EM_ANDAMENTO',
        criadoEm:     json['criadoEm'] != null
            ? DateTime.tryParse(json['criadoEm'].toString())?.toLocal()
            : null,
        atualizadoEm: json['atualizadoEm'] != null
            ? DateTime.tryParse(json['atualizadoEm'].toString())?.toLocal()
            : null,
        movimentacoes: (json['movimentacoes'] as List? ?? [])
            .map((m) => MovimentacaoModel.fromJson(m))
            .toList(),
      );
}