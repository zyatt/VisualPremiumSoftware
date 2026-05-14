class FornecedorModel {
  final int id;
  final String nomeFantasia;
  final String? tipoFornecedor;
  final String? telefone;
  final String? cnpj;
  final String? razaoSocial;
  final String? nomeVendedor;
  final bool ativo;

  FornecedorModel({
    required this.id,
    required this.nomeFantasia,
    this.tipoFornecedor,
    this.telefone,
    this.cnpj,
    this.razaoSocial,
    this.nomeVendedor,
    required this.ativo,
  });

  factory FornecedorModel.fromJson(Map<String, dynamic> json) => FornecedorModel(
    id:             json['id'],
    nomeFantasia:   json['nomeFantasia'],
    tipoFornecedor: json['tipoFornecedor'],
    telefone:       json['telefone'],
    cnpj:           json['cnpj'],
    razaoSocial:    json['razaoSocial'],
    nomeVendedor:   json['nomeVendedor'],
    ativo:          json['ativo'] ?? true,
  );
}