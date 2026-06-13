// ─────────────────────────────────────────────────────────────────────────────
// Modelos de Veículo e Manutenção
// ─────────────────────────────────────────────────────────────────────────────

const tiposManutencao = ['MANUTENCAO', 'LIMPEZA', 'REVISAO', 'PNEU', 'OUTRO'];

String labelTipo(String tipo) {
  switch (tipo) {
    case 'MANUTENCAO': return 'Manutenção';
    case 'LIMPEZA':    return 'Limpeza';
    case 'REVISAO':    return 'Revisão';
    case 'PNEU':       return 'Pneu';
    case 'OUTRO':      return 'Outro';
    default:           return tipo;
  }
}

class ManutencaoModel {
  final int       id;
  final int       veiculoId;
  final String    tipo;
  final String?   descricao;
  final double    valor;
  final DateTime  dataEnvio;
  final DateTime? dataRetirada;
  final DateTime  criadoEm;

  const ManutencaoModel({
    required this.id,
    required this.veiculoId,
    required this.tipo,
    this.descricao,
    required this.valor,
    required this.dataEnvio,
    this.dataRetirada,
    required this.criadoEm,
  });

  factory ManutencaoModel.fromJson(Map<String, dynamic> json) =>
      ManutencaoModel(
        id:           (json['id'] as num).toInt(),
        veiculoId:    (json['veiculoId'] as num).toInt(),
        tipo:         json['tipo'] ?? 'OUTRO',
        descricao:    json['descricao'],
        valor:        double.tryParse(json['valor']?.toString() ?? '0') ?? 0,
        dataEnvio:    DateTime.parse(json['dataEnvio']),
        dataRetirada: json['dataRetirada'] != null
            ? DateTime.parse(json['dataRetirada'])
            : null,
        criadoEm:     DateTime.parse(json['criadoEm']),
      );

  /// Em andamento enquanto não houver data de retirada OU enquanto a retirada
  /// ainda não tiver chegado (retirada >= início do dia de hoje).
  bool get emAndamento {
    if (dataRetirada == null) return true;
    final hoje = DateTime.now();
    final inicioDiaHoje = DateTime(hoje.year, hoje.month, hoje.day);
    return !dataRetirada!.isBefore(inicioDiaHoje);
  }

  /// Verdadeiro apenas quando a data de retirada é exatamente hoje
  /// (usado para mostrar a notificação de "pronto para retirar").
  bool get retiradaHoje {
    if (dataRetirada == null) return false;
    final hoje = DateTime.now();
    return dataRetirada!.year  == hoje.year  &&
           dataRetirada!.month == hoje.month &&
           dataRetirada!.day   == hoje.day;
  }
}

class VeiculoModel {
  final int                  id;
  final String               nome;
  final String               placa;
  final bool                 ativo;
  final List<ManutencaoModel> manutencoes; // última manutenção (do endpoint de lista)

  const VeiculoModel({
    required this.id,
    required this.nome,
    required this.placa,
    required this.ativo,
    required this.manutencoes,
  });

  factory VeiculoModel.fromJson(Map<String, dynamic> json) => VeiculoModel(
        id:         (json['id'] as num).toInt(),
        nome:       json['nome'] ?? '',
        placa:      json['placa'] ?? '',
        ativo:      json['ativo'] ?? true,
        manutencoes: (json['manutencoes'] as List? ?? [])
            .map((m) => ManutencaoModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  ManutencaoModel? get ultimaManutencao =>
      manutencoes.isEmpty ? null : manutencoes.first;
}

// ── Gasto por veículo (para a página de gastos) ──────────────────────────────

class GastoServicoModel {
  final int       id;
  final String    tipo;
  final String?   descricao;
  final double    valor;
  final DateTime  dataEnvio;
  final DateTime? dataRetirada;

  const GastoServicoModel({
    required this.id,
    required this.tipo,
    this.descricao,
    required this.valor,
    required this.dataEnvio,
    this.dataRetirada,
  });

  factory GastoServicoModel.fromJson(Map<String, dynamic> json) =>
      GastoServicoModel(
        id:           (json['id'] as num).toInt(),
        tipo:         json['tipo'] ?? 'OUTRO',
        descricao:    json['descricao'],
        valor:        double.tryParse(json['valor']?.toString() ?? '0') ?? 0,
        dataEnvio:    DateTime.parse(json['dataEnvio']),
        dataRetirada: json['dataRetirada'] != null
            ? DateTime.parse(json['dataRetirada'])
            : null,
      );
}

class GastoVeiculoModel {
  final int                    veiculoId;
  final String                 nome;
  final String                 placa;
  final double                 totalGasto;
  final int                    qtdServicos;
  final List<GastoServicoModel> servicos;

  const GastoVeiculoModel({
    required this.veiculoId,
    required this.nome,
    required this.placa,
    required this.totalGasto,
    required this.qtdServicos,
    required this.servicos,
  });

  factory GastoVeiculoModel.fromJson(Map<String, dynamic> json) =>
      GastoVeiculoModel(
        veiculoId:   (json['veiculoId'] as num).toInt(),
        nome:        json['nome'] ?? '',
        placa:       json['placa'] ?? '',
        totalGasto:  double.tryParse(json['totalGasto']?.toString() ?? '0') ?? 0,
        qtdServicos: (json['qtdServicos'] as num?)?.toInt() ?? 0,
        servicos:    (json['servicos'] as List? ?? [])
            .map((s) => GastoServicoModel.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class ResumoMensalVeiculoModel {
  final int    mes;
  final double totalGasto;

  const ResumoMensalVeiculoModel({required this.mes, required this.totalGasto});

  factory ResumoMensalVeiculoModel.fromJson(Map<String, dynamic> json) =>
      ResumoMensalVeiculoModel(
        mes:        (json['mes'] as num).toInt(),
        totalGasto: (json['totalGasto'] as num?)?.toDouble() ?? 0,
      );

  static const _meses = [
    '', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];

  String get label => _meses[mes];
}

class ResumoAnualVeiculoModel {
  final int                         ano;
  final double                      totalAnual;
  final List<ResumoMensalVeiculoModel> porMes;

  const ResumoAnualVeiculoModel({
    required this.ano,
    required this.totalAnual,
    required this.porMes,
  });

  factory ResumoAnualVeiculoModel.fromJson(Map<String, dynamic> json) =>
      ResumoAnualVeiculoModel(
        ano:        (json['ano'] as num).toInt(),
        totalAnual: (json['totalAnual'] as num?)?.toDouble() ?? 0,
        porMes:     (json['porMes'] as List? ?? [])
            .map((m) =>
                ResumoMensalVeiculoModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}