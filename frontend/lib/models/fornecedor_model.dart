/// Nome de exibição do material: "NOME DESCRICAO" quando o material é uma
/// variante vinculada a um genérico (ex.: "TINTA" + descricao "AZUL 400ML"),
/// ou apenas o nome quando não há descrição. Sem isso, o vínculo do
/// fornecedor com uma variante aparece só com o nome do genérico pai.
String? _nomeExibicaoMaterial(dynamic material) {
  if (material == null) return null;
  final nome = material['nome'];
  final descricao = material['descricao'];
  if (nome == null) return null;
  if (descricao != null && descricao.toString().trim().isNotEmpty) {
    return '$nome · ${descricao.toString().trim()}';
  }
  return nome;
}

class FornecedorSemelhanteModel {
  final int id;
  final String nomeFantasia;
  final String? tipoFornecedor;
  final String? nomeVendedor;
  final String? cnpj;
  final bool exata;
  final double similaridade;
  final bool contido;

  FornecedorSemelhanteModel({
    required this.id,
    required this.nomeFantasia,
    this.tipoFornecedor,
    this.nomeVendedor,
    this.cnpj,
    required this.exata,
    required this.similaridade,
    this.contido = false,
  });

  factory FornecedorSemelhanteModel.fromJson(Map<String, dynamic> json) =>
      FornecedorSemelhanteModel(
        id:             json['id'],
        nomeFantasia:   json['nomeFantasia'],
        tipoFornecedor: json['tipoFornecedor'],
        nomeVendedor:   json['nomeVendedor'],
        cnpj:           json['cnpj'],
        exata:          json['exata'] ?? false,
        similaridade:   (json['similaridade'] as num?)?.toDouble() ?? 0,
        contido:        json['contido'] ?? false,
      );
}

class FornecedoresPaginadosModel {
  final List<FornecedorModel> itens;
  final int total;

  const FornecedoresPaginadosModel({required this.itens, required this.total});
}

class FornecedorMaterialVinculoModel {
  final int id;
  final int fornecedorId;
  final int materialId;
  final String? materialNome;
  // Descrição "crua" da variante (ex.: "ABC" de "TINTA · ABC"), separada
  // do nome de exibição já formatado em `materialNome`. Necessária em
  // telas que precisam mostrar a descrição isoladamente (ex.: junto ao
  // nome do fornecedor, com o mesmo separador " · " usado no resto do
  // app), sem depender de parsear `materialNome`.
  final String? materialDescricao;
  final String? materialIdentificador;
  final String? materialMedida;
  final String? materialEspessura;
  final double preco;
  final double precoMetroQuadrado;
  final double precoUnidadeMedida;
  final bool ativo;
  final String? materialUnidade;
  final double? materialLargura;
  final double? materialComprimento;
  // Ativo do Material em si (não do vínculo fornecedor-material). Um
  // vínculo pode estar `ativo == true` mesmo com o material desativado no
  // Estoque — a tela de Fornecedores não deve listar esses materiais.
  final bool materialAtivo;
  // Indica se o Material vinculado é genérico (ex.: "TINTA"), caso em que
  // a tela de Ordem de Compra / Orçamento deve pedir uma descrição pra
  // criar/reaproveitar a variante concreta. Vínculos de material comum
  // (não genérico) nunca devem exibir esse campo.
  final bool ehGenerico;

  FornecedorMaterialVinculoModel({
    required this.id,
    required this.fornecedorId,
    required this.materialId,
    this.materialNome,
    this.materialDescricao,
    this.materialIdentificador,
    this.materialMedida,
    this.materialEspessura,
    required this.preco,
    required this.precoMetroQuadrado,
    this.precoUnidadeMedida = 0,
    required this.ativo,
    this.materialUnidade,
    this.materialLargura,
    this.materialComprimento,
    this.materialAtivo = true,
    this.ehGenerico = false,
  });

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
      final numero = materialEspessura!
          .replaceAll(RegExp('mm\\s*\$', caseSensitive: false), '')
          .trim();
      partes.add('${numero}mm');
    }

    final nomeBase = materialNome ?? 'Material #$materialId';
    final nomeComIdentificador = (materialIdentificador != null && materialIdentificador!.isNotEmpty)
        ? '$materialIdentificador · $nomeBase'
        : nomeBase;

    if (partes.isEmpty) {
      return nomeComIdentificador;
    }

    return '$nomeComIdentificador · ${partes.join(' · ')}';
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
        materialNome:         _nomeExibicaoMaterial(json['material']),
        materialDescricao:    json['material']?['descricao'],
        materialIdentificador: json['material']?['identificador'],
        materialMedida:       json['material']?['medida'],
        materialEspessura:    json['material']?['espessura'],
        preco:                double.tryParse(json['preco'].toString()) ?? 0,
        precoMetroQuadrado:   double.tryParse(json['precoMetroQuadrado'].toString()) ?? 0,
        precoUnidadeMedida:   json['precoUnidadeMedida'] != null
            ? double.tryParse(json['precoUnidadeMedida'].toString()) ?? 0
            : 0,
        ativo:                json['ativo'] ?? true,
        materialUnidade:      json['material']?['unidade'],
        materialLargura:      json['material']?['largura'] != null
            ? double.tryParse(json['material']['largura'].toString())
            : null,
        materialComprimento:  json['material']?['comprimento'] != null
            ? double.tryParse(json['material']['comprimento'].toString())
            : null,
        materialAtivo:        json['material']?['ativo'] ?? true,
        ehGenerico:           json['material']?['ehGenerico'] ?? false,
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