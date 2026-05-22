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
  /// Quando true, o material exige descrição personalizada na OC.
  final bool materialEspecifico;

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
    this.materialEspecifico = false,
  });

  String get descricaoCompleta {
    final partes = <String>[];

    if (materialMedida != null && materialMedida!.isNotEmpty) {
      partes.add(materialMedida!);
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

  String get especifico => descricaoCompleta;

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
        materialEspecifico:   json['material']?['especifico'] ?? false,
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
        ativo:          json['ativo'] ?? true,
        materiais:      (json['materiais'] as List? ?? [])
            .map((m) => FornecedorMaterialVinculoModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}