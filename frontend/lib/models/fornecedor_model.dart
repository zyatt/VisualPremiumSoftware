class FornecedorMaterialVinculoModel {
  final int id;
  final int fornecedorId;
  final int materialId;
  final String? materialNome;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final double preco;
  final double precoMetroQuadrado;
  final bool ativo;
  final String? materialUnidade;
  final double? materialLargura;
  final double? materialComprimento;

  FornecedorMaterialVinculoModel({
    required this.id,
    required this.fornecedorId,
    required this.materialId,
    this.materialNome,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    required this.preco,
    required this.precoMetroQuadrado,
    required this.ativo,
    this.materialUnidade,
    this.materialLargura,
    this.materialComprimento,
  });

  /// Formata a dimensão (largura x comprimento) como "50x1.27m" — mesma
  /// convenção usada nas demais telas (comprimento x largura, minúsculo).
  String? get _dimensaoFormatada {
    final l = materialLargura;
    final c = materialComprimento;
    if (l == null || c == null || l <= 0 || c <= 0) return null;
    String fmt(double v) =>
        v == v.truncateToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
    return '${fmt(c)}x${fmt(l)}m';
  }

  String get descricaoCompleta {
    final partes = <String>[];

    if (materialMedida != null && materialMedida!.isNotEmpty) {
      partes.add(materialMedida!);
    } else if (_dimensaoFormatada != null) {
      partes.add(_dimensaoFormatada!);
    }

    if (materialEspessura != null &&
        materialEspessura!.isNotEmpty) {
      partes.add(materialEspessura!);
    }

    if (materialIdentificador != null &&
        materialIdentificador!.isNotEmpty) {
      partes.add(materialIdentificador!);
    }

    if (partes.isEmpty) {
      return materialNome ?? 'Material #$materialId';
    }

    return '${materialNome ?? 'Material #$materialId'} · ${partes.join(' · ')}';
  }

  static String formatarPreco(double valor) {
    if (valor == 0) return '0,00';
    
    String s = valor.toStringAsFixed(6);
    
    s = s.replaceAll(RegExp(r'\.?0*$'), '');
    
    if (!s.contains('.')) {
      return '$s,00';
    }
    
    final partes = s.split('.');
    final decimais = partes[1];
    
    if (decimais.length < 2) {
      s = '${partes[0]}.${decimais.padRight(2, '0')}';
    }
    
    return s.replaceAll('.', ',');
  }

  factory FornecedorMaterialVinculoModel.fromJson(Map<String, dynamic> json) =>
      FornecedorMaterialVinculoModel(
        id:                   json['id'],
        fornecedorId:         json['fornecedorId'],
        materialId:           json['materialId'],
        materialNome:         json['material']?['nome'],
        materialIdentificador: json['material']?['identificador'],
        materialMedida:       json['material']?['medida'],
        materialEspessura:    json['material']?['espessura'],
        preco:                double.tryParse(json['preco'].toString()) ?? 0,
        precoMetroQuadrado:   double.tryParse(json['precoMetroQuadrado'].toString()) ?? 0,
        ativo:                json['ativo'] ?? true,
        materialUnidade:      json['material']?['unidade'],
        materialLargura:      json['material']?['largura'] != null
            ? double.tryParse(json['material']['largura'].toString())
            : null,
        materialComprimento:  json['material']?['comprimento'] != null
            ? double.tryParse(json['material']['comprimento'].toString())
            : null,
      );
}

class FornecedorModel {
  final int id;
  final String nomeFantasia;
  final String? tipoFornecedor;
  final String? telefone;
  final String? cnpj;
  final String? razaoSocial;
  final String? nomeVendedor;
  final String? imagemUrl;
  final bool ativo;
  final List<FornecedorMaterialVinculoModel> materiais;

  FornecedorModel({
    required this.id,
    required this.nomeFantasia,
    this.tipoFornecedor,
    this.telefone,
    this.cnpj,
    this.razaoSocial,
    this.nomeVendedor,
    this.imagemUrl,
    required this.ativo,
    this.materiais = const [],
  });

  String get telefoneFormatado {
    if (telefone == null || telefone!.length != 10) return telefone ?? '—';
    final t = telefone!;
    return '(${t.substring(0, 2)}) ${t.substring(2, 6)}-${t.substring(6)}';
  }

  String get cnpjFormatado {
    if (cnpj == null || cnpj!.length != 14) return cnpj ?? '—';
    final c = cnpj!;
    return '${c.substring(0, 2)}.${c.substring(2, 5)}.${c.substring(5, 8)}/${c.substring(8, 12)}-${c.substring(12)}';
  }

  factory FornecedorModel.fromJson(Map<String, dynamic> json) => FornecedorModel(
        id:             json['id'],
        nomeFantasia:   json['nomeFantasia'],
        tipoFornecedor: json['tipoFornecedor'],
        telefone:       json['telefone'],
        cnpj:           json['cnpj'],
        razaoSocial:    json['razaoSocial'],
        nomeVendedor:   json['nomeVendedor'],
        imagemUrl:      json['imagemUrl'],
        ativo:          json['ativo'] ?? true,
        materiais:      (json['materiais'] as List? ?? [])
            .map((m) => FornecedorMaterialVinculoModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}