// solicitacao_material_model.dart

// ─── Notificação em tempo real (payload do SSE 'nova_solicitacao') ───────────
// Não é o mesmo que SolicitacaoMaterialModel: é só o resumo enviado no evento,
// usado para exibir o banner flutuante assim que a solicitação é criada.
class NovaSolicitacaoNotificacao {
  final int id;
  final String numeroOS;
  final String nomeCliente;
  final String usuarioNome;
  final String? observacao;
  final int qtdMateriais;
  final DateTime criadoEm;

  const NovaSolicitacaoNotificacao({
    required this.id,
    required this.numeroOS,
    required this.nomeCliente,
    required this.usuarioNome,
    this.observacao,
    required this.qtdMateriais,
    required this.criadoEm,
  });

  factory NovaSolicitacaoNotificacao.fromJson(Map<String, dynamic> json) {
    return NovaSolicitacaoNotificacao(
      id:           (json['id'] as num).toInt(),
      numeroOS:     json['numeroOS'] ?? '',
      nomeCliente:  json['nomeCliente'] ?? '',
      usuarioNome:  json['usuarioNome'] ?? '',
      observacao:   json['observacao'],
      qtdMateriais: (json['qtdMateriais'] as num?)?.toInt() ?? 0,
      criadoEm:     json['criadoEm'] != null
          ? DateTime.parse(json['criadoEm']).toLocal()
          : DateTime.now(),
    );
  }
}

class SolicitacaoAlteradaNotificacao {
  final int id;
  final String numeroOS;
  final String nomeCliente;
  final String editorNome;
  final String acao;
  final String? materialNome;
  final String? item;
  final Map<String, dynamic>? antes;
  final Map<String, dynamic>? depois;

  const SolicitacaoAlteradaNotificacao({
    required this.id,
    required this.numeroOS,
    required this.nomeCliente,
    required this.editorNome,
    required this.acao,
    this.materialNome,
    this.item,
    this.antes,
    this.depois,
  });

  factory SolicitacaoAlteradaNotificacao.fromJson(Map<String, dynamic> json) {
    return SolicitacaoAlteradaNotificacao(
      id:           (json['id'] as num).toInt(),
      numeroOS:     json['numeroOS'] ?? '',
      nomeCliente:  json['nomeCliente'] ?? '',
      editorNome:   json['editorNome'] ?? 'Desconhecido',
      acao:         json['acao'] ?? '',
      materialNome: json['materialNome'],
      item:         json['item'],
      antes:        json['antes'] != null ? Map<String, dynamic>.from(json['antes']) : null,
      depois:       json['depois'] != null ? Map<String, dynamic>.from(json['depois']) : null,
    );
  }

  String get descricao {
    switch (acao) {
      case 'edicao_dados':
        return 'Dados da solicitação foram alterados';
      case 'edicao_material':
        return 'Um material foi editado';
      case 'adicao_material':
        return 'Novo material adicionado';
      case 'exclusao_material':
        return materialNome != null
            ? '"$materialNome" foi removido'
            : 'Um material foi removido';
      default:
        return 'Solicitação alterada';
    }
  }
}

// ─── Item original da solicitação ────────────────────────────────────────────
class ItemSolicitacaoModel {
  final int id;
  final int solicitacaoId;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final double? materialLargura;
  final double? materialComprimento;
  final String? materialCategoria;
  final double materialQuantidadeEstoque;
  final double quantidade;
  final String? observacao;
  final String? imagemUrl;

  final bool comprado;
  final DateTime? compradoEm;
  final int? compradoPorId;
  final String? compradoPorNome;

  final DateTime criadoEm;

  final DateTime? editadoEm;
  final String? editadoPorNome;

  /// Rótulo de dimensões do material a ser exibido ao lado do nome.
  /// Regra: se houver [materialMedida] preenchida, mostra apenas a medida
  /// (mesmo quando também há largura/comprimento, para evitar repetição).
  /// Caso contrário, se houver largura e comprimento, mostra "LxCM".
  String? get medidaOuDimensao {
    final temMedida = materialMedida != null && materialMedida!.trim().isNotEmpty;
    if (temMedida) return materialMedida!.trim();

    final temDimensoes = materialLargura != null &&
        materialComprimento != null &&
        materialLargura! > 0 &&
        materialComprimento! > 0;
    if (temDimensoes) {
      final l = _formatarNumero(materialComprimento!);
      final c = _formatarNumero(materialLargura!);
      return '${l}X${c}M';
    }
    return null;
  }

  const ItemSolicitacaoModel({
    required this.id,
    required this.solicitacaoId,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.materialLargura,
    this.materialComprimento,
    this.materialCategoria,
    required this.materialQuantidadeEstoque,
    required this.quantidade,
    this.observacao,
    this.imagemUrl,
    required this.comprado,
    this.compradoEm,
    this.compradoPorId,
    this.compradoPorNome,
    required this.criadoEm,
    this.editadoEm,
    this.editadoPorNome,
  });

  factory ItemSolicitacaoModel.fromJson(Map<String, dynamic> json) {
    return ItemSolicitacaoModel(
      id:            (json['id'] as num).toInt(),
      solicitacaoId: (json['solicitacaoId'] as num).toInt(),
      materialId:    (json['materialId'] as num).toInt(),
      materialNome:  json['material']?['nome'] ?? '',
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
      materialCategoria:     json['material']?['categoria'],
      materialQuantidadeEstoque:
          double.tryParse(json['material']?['quantidade']?.toString() ?? '0') ?? 0,
      quantidade: double.tryParse(json['quantidade'].toString()) ?? 0,
      observacao: json['observacao'],
      imagemUrl:  json['imagemUrl'],
      comprado:       json['comprado'] as bool? ?? false,
      compradoEm:     json['compradoEm'] != null
          ? DateTime.parse(json['compradoEm']).toLocal()
          : null,
      compradoPorId:   (json['compradoPorId'] as num?)?.toInt(),
      compradoPorNome: json['compradoPorNome'],
      criadoEm: DateTime.parse(json['criadoEm']).toLocal(),
      editadoEm: json['editadoEm'] != null
          ? DateTime.parse(json['editadoEm']).toLocal()
          : null,
      editadoPorNome: json['editadoPorNome'],
    );
  }

  ItemSolicitacaoModel copyWith({
    bool? comprado,
    DateTime? compradoEm,
    int? compradoPorId,
    String? compradoPorNome,
    DateTime? editadoEm,
    String? editadoPorNome,
  }) {
    return ItemSolicitacaoModel(
      id: id,
      solicitacaoId: solicitacaoId,
      materialId: materialId,
      materialNome: materialNome,
      materialUnidade: materialUnidade,
      materialIdentificador: materialIdentificador,
      materialMedida: materialMedida,
      materialEspessura: materialEspessura,
      materialLargura: materialLargura,
      materialComprimento: materialComprimento,
      materialCategoria: materialCategoria,
      materialQuantidadeEstoque: materialQuantidadeEstoque,
      quantidade: quantidade,
      observacao: observacao,
      imagemUrl: imagemUrl,
      comprado: comprado ?? this.comprado,
      compradoEm: compradoEm ?? this.compradoEm,
      compradoPorId: compradoPorId ?? this.compradoPorId,
      compradoPorNome: compradoPorNome ?? this.compradoPorNome,
      criadoEm: criadoEm,
      editadoEm: editadoEm ?? this.editadoEm,
      editadoPorNome: editadoPorNome ?? this.editadoPorNome,
    );
  }
}

/// Formata um número: sem casas decimais se for inteiro, senão até 2 casas
/// (removendo zeros à direita desnecessários). Ex: 5 -> "5", 1.20 -> "1.2".
String _formatarNumero(double valor) {
  if (valor % 1 == 0) return valor.toStringAsFixed(0);
  var s = valor.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

// ─── Adicional ────────────────────────────────────────────────────────────────
class AdicionalSolicitacaoModel {
  final int id;
  final int solicitacaoId;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final double? materialLargura;
  final double? materialComprimento;
  final String? materialCategoria;
  final double materialQuantidadeEstoque;
  final double quantidade;
  final String? observacao;
  final String? imagemUrl;

  final int adicionadoPorId;
  final String adicionadoPorNome;
  final DateTime adicionadoEm;

  final bool comprado;
  final DateTime? compradoEm;
  final int? compradoPorId;
  final String? compradoPorNome;

  final DateTime? editadoEm;
  final String? editadoPorNome;

  /// Rótulo de dimensões do material a ser exibido ao lado do nome.
  /// Regra: se houver [materialMedida] preenchida, mostra apenas a medida
  /// (mesmo quando também há largura/comprimento, para evitar repetição).
  /// Caso contrário, se houver largura e comprimento, mostra "LxCM".
  String? get medidaOuDimensao {
    final temMedida = materialMedida != null && materialMedida!.trim().isNotEmpty;
    if (temMedida) return materialMedida!.trim();

    final temDimensoes = materialLargura != null &&
        materialComprimento != null &&
        materialLargura! > 0 &&
        materialComprimento! > 0;
    if (temDimensoes) {
      final l = _formatarNumero(materialComprimento!);
      final c = _formatarNumero(materialLargura!);
      return '${l}X${c}M';
    }
    return null;
  }

  const AdicionalSolicitacaoModel({
    required this.id,
    required this.solicitacaoId,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    this.materialLargura,
    this.materialComprimento,
    this.materialCategoria,
    required this.materialQuantidadeEstoque,
    required this.quantidade,
    this.observacao,
    this.imagemUrl,
    required this.adicionadoPorId,
    required this.adicionadoPorNome,
    required this.adicionadoEm,
    required this.comprado,
    this.compradoEm,
    this.compradoPorId,
    this.compradoPorNome,
    this.editadoEm,
    this.editadoPorNome,
  });

  factory AdicionalSolicitacaoModel.fromJson(Map<String, dynamic> json) {
    return AdicionalSolicitacaoModel(
      id:            (json['id'] as num).toInt(),
      solicitacaoId: (json['solicitacaoId'] as num).toInt(),
      materialId:    (json['materialId'] as num).toInt(),
      materialNome:  json['material']?['nome'] ?? '',
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
      materialCategoria:     json['material']?['categoria'],
      materialQuantidadeEstoque:
          double.tryParse(json['material']?['quantidade']?.toString() ?? '0') ?? 0,
      quantidade: double.tryParse(json['quantidade'].toString()) ?? 0,
      observacao: json['observacao'],
      imagemUrl:  json['imagemUrl'],
      adicionadoPorId:   (json['adicionadoPorId'] as num).toInt(),
      adicionadoPorNome: json['adicionadoPorNome'] ?? '',
      adicionadoEm: DateTime.parse(json['adicionadoEm']).toLocal(),
      comprado:       json['comprado'] as bool? ?? false,
      compradoEm:     json['compradoEm'] != null
          ? DateTime.parse(json['compradoEm']).toLocal()
          : null,
      compradoPorId:   (json['compradoPorId'] as num?)?.toInt(),
      compradoPorNome: json['compradoPorNome'],
      editadoEm: json['editadoEm'] != null
          ? DateTime.parse(json['editadoEm']).toLocal()
          : null,
      editadoPorNome: json['editadoPorNome'],
    );
  }

  AdicionalSolicitacaoModel copyWith({
    bool? comprado,
    DateTime? compradoEm,
    int? compradoPorId,
    String? compradoPorNome,
    DateTime? editadoEm,
    String? editadoPorNome,
  }) {
    return AdicionalSolicitacaoModel(
      id: id,
      solicitacaoId: solicitacaoId,
      materialId: materialId,
      materialNome: materialNome,
      materialUnidade: materialUnidade,
      materialIdentificador: materialIdentificador,
      materialMedida: materialMedida,
      materialEspessura: materialEspessura,
      materialLargura: materialLargura,
      materialComprimento: materialComprimento,
      materialCategoria: materialCategoria,
      materialQuantidadeEstoque: materialQuantidadeEstoque,
      quantidade: quantidade,
      observacao: observacao,
      imagemUrl: imagemUrl,
      adicionadoPorId: adicionadoPorId,
      adicionadoPorNome: adicionadoPorNome,
      adicionadoEm: adicionadoEm,
      comprado: comprado ?? this.comprado,
      compradoEm: compradoEm ?? this.compradoEm,
      compradoPorId: compradoPorId ?? this.compradoPorId,
      compradoPorNome: compradoPorNome ?? this.compradoPorNome,
      editadoEm: editadoEm ?? this.editadoEm,
      editadoPorNome: editadoPorNome ?? this.editadoPorNome,
    );
  }
}

// ─── Solicitação principal ────────────────────────────────────────────────────
class SolicitacaoMaterialModel {
  final int id;
  final String numeroOS;
  final String nomeCliente;
  final DateTime dataNecessidade;
  final String andamento;
  final String? observacao;
  final int usuarioId;
  final String usuarioNome;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  final List<ItemSolicitacaoModel> itens;
  final List<AdicionalSolicitacaoModel> adicionais;

  const SolicitacaoMaterialModel({
    required this.id,
    required this.numeroOS,
    required this.nomeCliente,
    required this.dataNecessidade,
    required this.andamento,
    this.observacao,
    required this.usuarioId,
    required this.usuarioNome,
    required this.criadoEm,
    required this.atualizadoEm,
    required this.itens,
    required this.adicionais,
  });

  /// Alias para criadoEm — data em que a solicitação foi aberta.
  DateTime get dataSolicitacao => criadoEm;

  /// Retorna true se todos os materiais (itens + adicionais) estão marcados como comprado.
  bool get todosComprados {
    final todos = [...itens, ...adicionais];
    if (todos.isEmpty) return false;
    return itens.every((e) => e.comprado) &&
        adicionais.every((e) => e.comprado);
  }

  /// Quantidade total de materiais (itens + adicionais).
  int get totalMateriais => itens.length + adicionais.length;

  /// Quantidade de materiais já comprados.
  int get totalComprados {
    int c = 0;
    for (final i in itens)      { if (i.comprado) c++; }
    for (final a in adicionais) { if (a.comprado) c++; }
    return c;
  }

  factory SolicitacaoMaterialModel.fromJson(Map<String, dynamic> json) {
    return SolicitacaoMaterialModel(
      id:              (json['id'] as num).toInt(),
      numeroOS:        json['numeroOS'] ?? '',
      nomeCliente:     json['nomeCliente'] ?? '',
      dataNecessidade: DateTime.parse(json['dataNecessidade']).toLocal(),
      andamento:       json['andamento'] ?? 'EM_ANDAMENTO',
      observacao:      json['observacao'],
      usuarioId:       (json['usuarioId'] as num).toInt(),
      usuarioNome:     json['usuarioNome'] ?? '',
      criadoEm:        DateTime.parse(json['criadoEm']).toLocal(),
      atualizadoEm:    DateTime.parse(json['atualizadoEm']).toLocal(),
      itens: (json['itens'] as List<dynamic>? ?? [])
          .map((e) => ItemSolicitacaoModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      adicionais: (json['adicionais'] as List<dynamic>? ?? [])
          .map((e) => AdicionalSolicitacaoModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  SolicitacaoMaterialModel copyWith({
    List<ItemSolicitacaoModel>? itens,
    List<AdicionalSolicitacaoModel>? adicionais,
    String? andamento,
  }) {
    return SolicitacaoMaterialModel(
      id: id,
      numeroOS: numeroOS,
      nomeCliente: nomeCliente,
      dataNecessidade: dataNecessidade,
      andamento: andamento ?? this.andamento,
      observacao: observacao,
      usuarioId: usuarioId,
      usuarioNome: usuarioNome,
      criadoEm: criadoEm,
      atualizadoEm: atualizadoEm,
      itens: itens ?? this.itens,
      adicionais: adicionais ?? this.adicionais,
    );
  }
}

// ─── Log de edição ────────────────────────────────────────────────────────────
class LogEdicaoSolicitacaoModel {
  final int id;
  final int solicitacaoId;
  final int editorId;
  final String editorNome;
  final Map<String, dynamic> antes;
  final Map<String, dynamic> depois;
  final DateTime editadoEm;
  /// Contexto opcional: nome do material editado, quando o log se refere a
  /// um item/adicional em vez dos dados do cabeçalho da solicitação.
  final String? item;

  const LogEdicaoSolicitacaoModel({
    required this.id,
    required this.solicitacaoId,
    required this.editorId,
    required this.editorNome,
    required this.antes,
    required this.depois,
    required this.editadoEm,
    this.item,
  });

  factory LogEdicaoSolicitacaoModel.fromJson(Map<String, dynamic> json) {
    return LogEdicaoSolicitacaoModel(
      id:            (json['id'] as num).toInt(),
      solicitacaoId: (json['solicitacaoId'] as num).toInt(),
      editorId:      (json['editorId'] as num).toInt(),
      editorNome:    json['editorNome'] ?? '',
      antes:         Map<String, dynamic>.from(json['antes'] ?? {}),
      depois:        Map<String, dynamic>.from(json['depois'] ?? {}),
      editadoEm:     DateTime.parse(json['editadoEm']).toLocal(),
      item:          json['item'],
    );
  }
}