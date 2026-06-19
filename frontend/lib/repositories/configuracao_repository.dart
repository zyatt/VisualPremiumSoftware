import '../utils/api_client.dart';

// ─── Modelos ──────────────────────────────────────────────────────────────────

class MarkupFaixa {
  final int?    id;
  final double  valorMin;
  final double? valorMax;   // null = aberto
  final double  percentual;

  MarkupFaixa({
    this.id,
    required this.valorMin,
    this.valorMax,
    required this.percentual,
  });

  factory MarkupFaixa.fromJson(Map<String, dynamic> j) => MarkupFaixa(
        id:         (j['id'] as num?)?.toInt(),
        valorMin:   double.tryParse(j['valorMin'].toString()) ?? 0,
        valorMax:   j['valorMax'] != null
            ? double.tryParse(j['valorMax'].toString())
            : null,
        percentual: double.tryParse(j['percentual'].toString()) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'valorMin':   valorMin,
        'valorMax':   valorMax,
        'percentual': percentual,
      };

  MarkupFaixa copyWith({
    double? valorMin,
    double? valorMax,
    bool    clearValorMax = false,
    double? percentual,
  }) =>
      MarkupFaixa(
        id:         id,
        valorMin:   valorMin   ?? this.valorMin,
        valorMax:   clearValorMax ? null : (valorMax ?? this.valorMax),
        percentual: percentual ?? this.percentual,
      );
}

// ─── Repositório ──────────────────────────────────────────────────────────────

class ConfiguracaoRepository {
  // ── Markup ──────────────────────────────────────────────────────────────────

  Future<List<MarkupFaixa>> listarFaixas() async {
    final list = await ApiClient.getList('/configuracoes/markup');
    return list
        .map((e) => MarkupFaixa.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MarkupFaixa>> salvarFaixas(List<MarkupFaixa> faixas) async {
    final list = await ApiClient.putList('/configuracoes/markup', {
      'faixas': faixas.map((f) => f.toJson()).toList(),
    });
    return list
        .map((e) => MarkupFaixa.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  // ── Configurações ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> listarConfiguracoes() async {
    final data = await ApiClient.get('/configuracoes/config');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> salvarConfiguracoes(Map<String, dynamic> dados) async {
    await ApiClient.put('/configuracoes/config', dados);
  }
}