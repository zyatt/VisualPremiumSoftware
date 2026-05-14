class UsuarioModel {
  final int id;
  final String nome;
  final String username;
  final String role;
  final bool ativo;

  UsuarioModel({
    required this.id,
    required this.nome,
    required this.username,
    required this.role,
    required this.ativo,
  });

  factory UsuarioModel.fromJson(Map<String, dynamic> json) => UsuarioModel(
    id:       json['id'],
    nome:     json['nome'],
    username: json['username'],
    role:     json['role'],
    ativo:    json['ativo'] ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id':       id,
    'nome':     nome,
    'username': username,
    'role':     role,
    'ativo':    ativo,
  };
}