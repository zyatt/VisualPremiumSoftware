class MovimentacaoModel {
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
  final String numeroOS;
  final double? precoUnitario;
  final double? precoM2;
  final String? observacao;
  final DateTime criadoEm;

  final double? larguraUsada;
  final double? comprimentoUsado;
  
  final int? materialOrigemId;
  final String? materialOrigemNome;

  final String? origemProducao;
  final String? producao;

  MovimentacaoModel({
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
    required this.numeroOS,
    this.precoUnitario,
    this.precoM2,
    this.observacao,
    required this.criadoEm,
    this.larguraUsada,
    this.comprimentoUsado,
    this.materialOrigemId,
    this.materialOrigemNome,
    this.origemProducao,
    this.producao,
  });

  bool get usouModoDimensional =>
      larguraUsada != null && larguraUsada! > 0 &&
      comprimentoUsado != null && comprimentoUsado! > 0;

  bool get ehRetalhoDeOrigem => materialOrigemId != null;
 
  String? get descricaoOrigemProducao {
    if (origemProducao == null || producao == null) return null;
    if (origemProducao == 'TRANSFERENCIA') {
      return 'Transferência do estoque padrão para produção $producao';
    }
    if (origemProducao == 'DEVOLUCAO') {
      return 'Devolução da produção $producao para o estoque padrão';
    }
    return 'Baixa da produção $producao';
  }

  factory MovimentacaoModel.fromJson(Map<String, dynamic> json) =>
      MovimentacaoModel(
        id:                    (json['id'] as num?)?.toInt() ?? 0,
        materialId:            (json['materialId'] as num?)?.toInt() ?? 0,
        materialNome:          (json['material']?['nome'] as String?)
                               ?? (json['descricaoItem']?.toString().trim().isNotEmpty == true
                                   ? json['descricaoItem'].toString().trim()
                                   : '(material excluído)'),
        materialUnidade:       json['material']?['unidade'],
        materialIdentificador: json['material']?['identificador'],
        materialMedida:        json['material']?['medida'],
        materialEspessura:     json['material']?['espessura'],
        materialLargura:       json['material']?['largura'] != null
            ? double.tryParse(json['material']['largura'].toString())
            : null,
        materialComprimento:   json['material']?['comprimento'] != null
            ? double.tryParse(json['material']['comprimento'].toString())
            : null,
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
        materialOrigemId:      (json['materialOrigemId'] as num?)?.toInt(),
        materialOrigemNome:    json['materialOrigem']?['nome'],
        origemProducao:        json['origemProducao']?.toString(),
        producao:              json['producao']?.toString(),
      );
}

class RelacoesOSPaginadasModel {
  final List<RelacaoOSModel> itens;
  final int total;
  const RelacoesOSPaginadasModel({required this.itens, required this.total});
}

class MovimentacaoComOSModel {
  final MovimentacaoModel movimentacao;
  final int relacaoOSId;
  final String numeroOS;
  final String? cliente;
  final String relacaoOSStatus;

  MovimentacaoComOSModel({
    required this.movimentacao,
    required this.relacaoOSId,
    required this.numeroOS,
    this.cliente,
    required this.relacaoOSStatus,
  });

  factory MovimentacaoComOSModel.fromJson(Map<String, dynamic> json) {
    final relacao = json['relacaoOS'] as Map<String, dynamic>? ?? const {};
    return MovimentacaoComOSModel(
      movimentacao:    MovimentacaoModel.fromJson(json),
      relacaoOSId:     (relacao['id'] as num?)?.toInt() ?? 0,
      numeroOS:        relacao['numeroOS']?.toString() ?? json['numeroOS']?.toString() ?? '',
      cliente:         relacao['cliente'],
      relacaoOSStatus: relacao['status']?.toString() ?? 'EM_ANDAMENTO',
    );
  }
}

class MovimentacoesPaginadasModel {
  final List<MovimentacaoComOSModel> itens;
  final int total;
  const MovimentacoesPaginadasModel({required this.itens, required this.total});
}

class RelacaoOSModel {
  final int id;
  final String numeroOS;
  final String? descricao;
  final String? cliente;
  final String status;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final String? fechadoPorNome;
  final List<MovimentacaoModel> movimentacoes;

  RelacaoOSModel({
    required this.id,
    required this.numeroOS,
    this.descricao,
    this.cliente,
    this.status = 'EM_ANDAMENTO',
    this.criadoEm,
    this.atualizadoEm,
    this.fechadoPorNome,
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
        cliente:      json['cliente'],
        status:       json['status'] ?? 'EM_ANDAMENTO',
        criadoEm:     json['criadoEm'] != null
            ? DateTime.tryParse(json['criadoEm'].toString())?.toLocal()
            : null,
        atualizadoEm: json['atualizadoEm'] != null
            ? DateTime.tryParse(json['atualizadoEm'].toString())?.toLocal()
            : null,
        fechadoPorNome: json['fechadoPorNome'],
        movimentacoes: (json['movimentacoes'] as List? ?? [])
            .map((m) => MovimentacaoModel.fromJson(m))
            .toList(),
      );
}