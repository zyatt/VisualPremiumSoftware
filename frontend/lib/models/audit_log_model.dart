class AuditLogModel {
  final int id;
  final int materialId;
  final String? materialNome;
  final String? materialCategoria;
  final String? materialUnidade;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialIdentificador;
  final double? materialLargura;
  final double? materialComprimento;
  final String? materialDescricao;

  final bool materialExcluido;

  final String acao;

  final String? campo;

  final String? valorAntes;

  final String? valorDepois;

  final int? usuarioId;
  final String? usuarioNome;
  final DateTime criadoEm;

  AuditLogModel({
    required this.id,
    required this.materialId,
    this.materialNome,
    this.materialCategoria,
    this.materialUnidade,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.materialLargura,
    this.materialComprimento,
    this.materialDescricao,
    this.materialExcluido = false,
    required this.acao,
    this.campo,
    this.valorAntes,
    this.valorDepois,
    this.usuarioId,
    this.usuarioNome,
    required this.criadoEm,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) => AuditLogModel(
        id:                (json['id'] as num?)?.toInt() ?? 0,
        materialId:        (json['materialId'] as num?)?.toInt() ?? 0,
        materialNome:          json['material']?['nome'],
        materialCategoria:     json['material']?['categoria'],
        materialUnidade:       json['material']?['unidade'],
        materialMedida:        json['material']?['medida'],
        materialEspessura:     json['material']?['espessura'],
        materialIdentificador: json['material']?['identificador'],
        materialLargura:       json['material']?['largura'] != null
            ? double.tryParse(json['material']['largura'].toString())
            : null,
        materialComprimento:   json['material']?['comprimento'] != null
            ? double.tryParse(json['material']['comprimento'].toString())
            : null,
        materialDescricao:     json['material']?['descricao'],
        materialExcluido:      json['materialExcluido'] == true,
        acao:              json['acao'] ?? '',
        campo:             json['campo'],
        valorAntes:        json['valorAntes'],
        valorDepois:       json['valorDepois'],
        usuarioId:         (json['usuarioId'] as num?)?.toInt(),
        usuarioNome:       json['usuarioNome'],
        criadoEm:          DateTime.parse(json['criadoEm']),
      );

  String get acaoLabel {
    switch (acao) {
      case 'CADASTRO':             return 'Cadastro';
      case 'EDICAO':               return 'Edição';
      case 'DESATIVACAO':          return 'Desativação';
      case 'REATIVACAO':           return 'Reativação';
      case 'EXCLUSAO':             return 'Exclusão';
      case 'ESTOQUE_CONFIRMADO':   return 'Estoque confirmado';
      case 'CUSTO_MANUAL':         return 'Custo manual';
      case 'FILHO_EDITADO':        return 'Variação editada';
      case 'FILHO_EXCLUIDO':       return 'Variação excluída';
      // Fluxo de aprovação de cadastro (usuários não-ADMIN)
      case 'ENVIO_APROVACAO':      return 'Enviado para aprovação';
      case 'CADASTRO_PENDENTE':    return 'Enviado para aprovação';
      case 'APROVACAO':            return 'Cadastro aprovado';
      case 'CADASTRO_APROVADO':    return 'Cadastro aprovado';
      case 'RECUSA':               return 'Cadastro recusado';
      case 'CADASTRO_RECUSADO':    return 'Cadastro recusado';
      default:
        // Fallback amigável: transforma "ALGO_ASSIM" em "Algo assim" em vez
        // de mostrar a constante crua para o usuário.
        if (acao.isEmpty) return '—';
        final texto = acao.replaceAll('_', ' ').toLowerCase();
        return texto[0].toUpperCase() + texto.substring(1);
    }
  }

  String get acaoCor {
    switch (acao) {
      case 'CADASTRO':             return '#15803D';
      case 'EDICAO':               return '#1E88E5';
      case 'DESATIVACAO':          return '#D97706';
      case 'REATIVACAO':           return '#7C3AED';
      case 'EXCLUSAO':             return '#DC2626';
      case 'ESTOQUE_CONFIRMADO':   return '#0891B2';
      case 'CUSTO_MANUAL':         return '#7C3AED';
      case 'FILHO_EDITADO':        return '#1E88E5';
      case 'FILHO_EXCLUIDO':       return '#E85D04';
      // Fluxo de aprovação de cadastro (usuários não-ADMIN)
      case 'ENVIO_APROVACAO':
      case 'CADASTRO_PENDENTE':    return '#D97706';
      case 'APROVACAO':
      case 'CADASTRO_APROVADO':    return '#15803D';
      case 'RECUSA':
      case 'CADASTRO_RECUSADO':    return '#DC2626';
      default:                     return '#6B7280';
    }
  }

  bool get temDiff => valorAntes != null || valorDepois != null;

  /// Nome de exibição: "NOME DESCRICAO" quando o material é uma variante
  /// vinculada a um genérico (ex.: "TINTA" + "ABC"), ou o próprio nome
  /// caso contrário.
  String get materialNomeExibicao {
    final nome = materialNome ?? '';
    final desc = materialDescricao?.trim();
    if (desc != null && desc.isNotEmpty) return '$nome $desc';
    return nome;
  }

  /// Nome do campo pronto para exibição ao usuário. O backend já envia a
  /// maioria dos campos com label amigável (ex: "Nome", "Estoque Mínimo"),
  /// mas caso algum campo escape sem tradução (ex: vindo de uma versão mais
  /// antiga do backend, ou um campo novo ainda não mapeado), este getter
  /// evita mostrar a variável crua em camelCase/SNAKE_CASE truncada — ele
  /// insere espaços antes de letras maiúsculas e capitaliza a primeira letra.
  String get campoExibicao {
    final c = campo?.trim();
    if (c == null || c.isEmpty) return '—';

    // Já parece um label amigável (contém espaço ou é só uma palavra comum
    // com inicial maiúscula) — devolve como veio.
    final jaFormatado = RegExp(r'^[A-ZÀ-Ý][a-zà-ÿ0-9²]*(\s[A-ZÀ-Ýa-zà-ÿ0-9²()%.]*)*$');
    if (jaFormatado.hasMatch(c) && !c.contains('_') && c == c.trim()) {
      // Ainda assim, se vier em camelCase disfarçado de uma palavra só
      // (ex: "EstoqueMinimo"), quebra em palavras.
      if (!RegExp(r'[a-z][A-Z]').hasMatch(c)) return c;
    }

    final comEspacos = c
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .trim();
    if (comEspacos.isEmpty) return '—';
    return comEspacos[0].toUpperCase() + comEspacos.substring(1);
  }

  static String _numFmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  String get materialInfoLine {
    final partes = <String>[];

    if (materialIdentificador != null && materialIdentificador!.trim().isNotEmpty) {
      partes.add(materialIdentificador!.trim());
    }

    if (materialUnidade != null && materialUnidade!.trim().isNotEmpty) {
      partes.add(materialUnidade!.trim().toLowerCase());
    }

    if (materialMedida != null && materialMedida!.trim().isNotEmpty) {
      partes.add(materialMedida!.trim().toLowerCase());
    } else if (materialComprimento != null &&
        materialComprimento! > 0 &&
        materialLargura != null &&
        materialLargura! > 0) {
      partes.add(
        '${_numFmt(materialComprimento!)}x${_numFmt(materialLargura!)}m',
      );
    }

    if (materialEspessura != null && materialEspessura!.trim().isNotEmpty) {
      partes.add(materialEspessura!.trim().toLowerCase());
    }

    return partes.join(' · ');
  }
}