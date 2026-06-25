// estoque_temporario_model.dart
// Representa um Material com temporario = true vindo do backend.
// Os campos batem com o _select do service.
class EstoqueTemporarioModel {
  final int id;
  final String nome;
  final String unidade;
  final String? categoria;
  final bool ativo;
  final String? observacao;
  final String? criadoPorNome;
  final DateTime criadoEm;
  final DateTime desativaEm;

  EstoqueTemporarioModel({
    required this.id,
    required this.nome,
    required this.unidade,
    this.categoria,
    required this.ativo,
    this.observacao,
    this.criadoPorNome,
    required this.criadoEm,
    required this.desativaEm,
  });

  /// Dias restantes até desativação automática.
  int get diasRestantes => desativaEm.difference(DateTime.now()).inDays;

  /// Percentual de vida restante (0.0 a 1.0), baseado em 90 dias (~3 meses).
  double get percentualRestante {
    const totalDias = 90.0;
    return (diasRestantes / totalDias).clamp(0.0, 1.0);
  }

  EstoqueTemporarioModel copyWith({bool? ativo, DateTime? desativaEm}) =>
      EstoqueTemporarioModel(
        id:            id,
        nome:          nome,
        unidade:       unidade,
        categoria:     categoria,
        ativo:         ativo ?? this.ativo,
        observacao:    observacao,
        criadoPorNome: criadoPorNome,
        criadoEm:      criadoEm,
        desativaEm:    desativaEm ?? this.desativaEm,
      );

  factory EstoqueTemporarioModel.fromJson(Map<String, dynamic> json) =>
      EstoqueTemporarioModel(
        id:            (json['id'] as num?)?.toInt() ?? 0,
        nome:          json['nome'] ?? '',
        unidade:       json['unidade'] ?? 'UNIDADE',
        categoria:     json['categoria'],
        ativo:         json['ativo'] as bool? ?? true,
        observacao:    json['observacaoTemporario'],
        criadoPorNome: json['criadoPorNome'],
        criadoEm:      DateTime.parse(json['criadoEm']).toLocal(),
        desativaEm:    DateTime.parse(json['desativaEm']).toLocal(),
      );
}