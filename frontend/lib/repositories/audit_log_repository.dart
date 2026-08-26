import '../models/audit_log_model.dart';
import '../utils/api_client.dart';

class AuditLogRepository {
  Future<List<AuditLogModel>> listar({
    int? materialId,
    String? acao,
    String? busca,
    DateTime? dataInicio,
    DateTime? dataFim,
    int limite = 500,
  }) async {
    final params = <String>[];

    if (materialId != null) params.add('materialId=$materialId');
    if (acao != null && acao.isNotEmpty) params.add('acao=${Uri.encodeComponent(acao)}');
    if (busca != null && busca.isNotEmpty) params.add('busca=${Uri.encodeComponent(busca)}');
    if (dataInicio != null) {
      final s =
          '${dataInicio.year}-${dataInicio.month.toString().padLeft(2, '0')}-${dataInicio.day.toString().padLeft(2, '0')}';
      params.add('dataInicio=${Uri.encodeComponent(s)}');
    }
    if (dataFim != null) {
      final s =
          '${dataFim.year}-${dataFim.month.toString().padLeft(2, '0')}-${dataFim.day.toString().padLeft(2, '0')}';
      params.add('dataFim=${Uri.encodeComponent(s)}');
    }
    params.add('limite=$limite');

    final path = params.isEmpty
        ? '/audit-log'
        : '/audit-log?${params.join('&')}';

    final list = await ApiClient.getList(path);
    return list
        .map((e) => AuditLogModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AuditLogModel>> listarPorMaterial(int materialId,
      {int limite = 200}) async {
    final list =
        await ApiClient.getList('/audit-log/material/$materialId?limite=$limite');
    return list
        .map((e) => AuditLogModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}