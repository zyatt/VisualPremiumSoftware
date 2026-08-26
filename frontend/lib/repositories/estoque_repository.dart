import '../models/estoque_model.dart';
import '../utils/api_client.dart';

class EstoqueRepository {

  Future<List<RelacaoOSModel>> listarRelacoesOS({String? busca}) async {
    final path = busca != null && busca.isNotEmpty
        ? '/estoque?busca=${Uri.encodeComponent(busca)}'
        : '/estoque';
    final list = await ApiClient.getList(path);
    return list.map((e) => RelacaoOSModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RelacaoOSModel> buscarRelacaoOS(String numeroOS) async {
    final data = await ApiClient.get('/estoque/${Uri.encodeComponent(numeroOS)}');
    return RelacaoOSModel.fromJson(data);
  }

  Future<List<RelacaoOSModel>> listarRelatoriosOS({
    String? busca,
    String? cliente,
    String? materialId,
    String? materialNome,
    String? materialIdentificador,
    String? materialMedida,
    String? materialComprimento,
    String? materialLargura,
    String? materialEspessura,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    final params = <String>[];
    if (busca != null && busca.isNotEmpty) {
      params.add('busca=${Uri.encodeComponent(busca)}');
    }
    if (cliente != null && cliente.isNotEmpty) {
      params.add('cliente=${Uri.encodeComponent(cliente)}');
    }
    if (materialId != null && materialId.isNotEmpty) {
      params.add('materialId=${Uri.encodeComponent(materialId)}');
    }
    if (materialNome != null && materialNome.isNotEmpty) {
      params.add('materialNome=${Uri.encodeComponent(materialNome)}');
    }
    if (materialIdentificador != null && materialIdentificador.isNotEmpty) {
      params.add('materialIdentificador=${Uri.encodeComponent(materialIdentificador)}');
    }
    if (materialComprimento != null &&
      materialComprimento.isNotEmpty) {
      params.add(
        'materialComprimento=${Uri.encodeComponent(materialComprimento)}',
      );
    }

    if (materialLargura != null &&
        materialLargura.isNotEmpty) {
      params.add(
        'materialLargura=${Uri.encodeComponent(materialLargura)}',
      );
    }
    if (materialEspessura != null && materialEspessura.isNotEmpty) {
      params.add('materialEspessura=${Uri.encodeComponent(materialEspessura)}');
    }
    if (dataInicio != null) {
      final s = '${dataInicio.year}-'
          '${dataInicio.month.toString().padLeft(2, '0')}-'
          '${dataInicio.day.toString().padLeft(2, '0')}';
      params.add('dataInicio=${Uri.encodeComponent(s)}');
    }
    if (dataFim != null) {
      final s = '${dataFim.year}-'
          '${dataFim.month.toString().padLeft(2, '0')}-'
          '${dataFim.day.toString().padLeft(2, '0')}';
      params.add('dataFim=${Uri.encodeComponent(s)}');
    }
    final path = params.isEmpty
        ? '/relatorios-os'
        : '/relatorios-os?${params.join('&')}';
    final list = await ApiClient.getList(path);
    return list.map((e) => RelacaoOSModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MovimentacaoModel> registrarMovimentacao({
    required int materialId,
    required String tipo,
    required double quantidade,
    required String numeroOS,
    double? precoUnitario,
    double? precoM2,
    String? observacao,
    int? ordemCompraId,
    double? larguraUsada,
    double? comprimentoUsado,
    int? materialOrigemId,
    String? cliente,
  }) async {
    final data = await ApiClient.post('/estoque/movimentacoes', {
      'materialId': materialId,
      'tipo':       tipo,
      'quantidade': quantidade,
      'numeroOS':   numeroOS,
      if (precoUnitario != null)    'precoUnitario':    precoUnitario,
      if (precoM2 != null)          'precoM2':          precoM2,
      if (observacao != null)       'observacao':       observacao,
      if (ordemCompraId != null)    'ordemCompraId':    ordemCompraId,
      if (larguraUsada != null)     'larguraUsada':     larguraUsada,
      if (comprimentoUsado != null) 'comprimentoUsado': comprimentoUsado,
      if (materialOrigemId != null) 'materialOrigemId': materialOrigemId,
      if (cliente != null && cliente.trim().isNotEmpty) 'cliente': cliente.trim(),
    });
    return MovimentacaoModel.fromJson(data);
  }

  Future<void> removerMovimentacao(int movimentacaoId) async {
    await ApiClient.delete('/estoque/movimentacoes/$movimentacaoId');
  }

  Future<void> excluirRelacaoOS(int relacaoOSId) async {
    await ApiClient.delete('/estoque/$relacaoOSId');
  }

  Future<RelacaoOSModel> renomearOS(
    int relacaoOSId,
    String novoNumeroOS, {
    String? novoCliente,
  }) async {
    final data = await ApiClient.patch(
      '/estoque/$relacaoOSId/renomear',
      {
        'novoNumeroOS': novoNumeroOS,
        if (novoCliente != null) 'novoCliente': novoCliente,
      },
    );
    return RelacaoOSModel.fromJson(data);
  }

  Future<String?> buscarClientePorNumeroOS(String numeroOS) async {
    try {
      final data = await ApiClient.get('/estoque/${Uri.encodeComponent(numeroOS)}/cliente');
      return data['cliente'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<RelacaoOSModel> fecharOS(int relacaoOSId) async {
    final data = await ApiClient.patch('/estoque/$relacaoOSId/fechar');
    return RelacaoOSModel.fromJson(data);
  }

  Future<List<int>> baixarPdf({
    String? categoria,
    String? status,
    String? busca,
    String? id,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    final cat = (categoria == null || categoria.isEmpty) ? 'TODAS' : categoria;
    final st  = (status == null || status.isEmpty) ? 'TODOS' : status;
    final params = StringBuffer(
      '/estoque/pdf?categoria=${Uri.encodeComponent(cat)}&status=${Uri.encodeComponent(st)}',
    );
    if (busca != null && busca.isNotEmpty) {
      params.write('&busca=${Uri.encodeComponent(busca)}');
    }
    if (id != null && id.isNotEmpty) {
      params.write('&id=${Uri.encodeComponent(id)}');
    }
    if (identificador != null && identificador.isNotEmpty) {
      params.write('&identificador=${Uri.encodeComponent(identificador)}');
    }
    if (medida != null && medida.isNotEmpty) {
      params.write('&medida=${Uri.encodeComponent(medida)}');
    }
    if (espessura != null && espessura.isNotEmpty) {
      params.write('&espessura=${Uri.encodeComponent(espessura)}');
    }
    return ApiClient.getBytes(params.toString());
  }

  Future<RelacaoOSModel> reverterOS(String numeroOS) async {
    final data = await ApiClient.patch(
      '/relatorios-os/${Uri.encodeComponent(numeroOS)}/reverter',
    );
    return RelacaoOSModel.fromJson(data);
  }

  Future<List<int>> baixarRelatorioOSPdf(String numeroOS) async {
    return ApiClient.getBytes(
      '/relatorios-os/${Uri.encodeComponent(numeroOS)}/pdf',
    );
  }

  Future<RelacoesOSPaginadasModel> listarTodasRelacoesOS({
    String? busca,
    String? status,
    String? cliente,
    String? material,
    String? identificador,
    String? medida,
    String? comprimento,
    String? largura,
    String? espessura,
    DateTime? dataInicio,
    DateTime? dataFim,
    String? ordenarPor,
    String? direcao,
    bool? apenasNumericas,
    bool? apenasTextuais,
    required int pagina,
    int porPagina = 50,
  }) async {
    final params = <String, String>{
      'pagina':    pagina.toString(),
      'porPagina': porPagina.toString(),
    };
    if (busca != null && busca.isNotEmpty)                 params['busca']         = busca;
    if (status != null && status.isNotEmpty)               params['status']        = status;
    if (cliente != null && cliente.isNotEmpty)             params['cliente']       = cliente;
    if (material != null && material.isNotEmpty)           params['material']      = material;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)               params['medida']        = medida;
    if (comprimento != null && comprimento.isNotEmpty)     params['comprimento']   = comprimento;
    if (largura != null && largura.isNotEmpty)             params['largura']       = largura;
    if (espessura != null && espessura.isNotEmpty)         params['espessura']     = espessura;
    if (ordenarPor != null && ordenarPor.isNotEmpty)       params['ordenarPor']    = ordenarPor;
    if (direcao != null && direcao.isNotEmpty)             params['direcao']       = direcao;
    if (apenasNumericas == true)                           params['apenasNumericas'] = 'true';
    if (apenasTextuais == true)                            params['apenasTextuais']  = 'true';
    if (dataInicio != null) {
      params['dataInicio'] = '${dataInicio.year}-'
          '${dataInicio.month.toString().padLeft(2, '0')}-'
          '${dataInicio.day.toString().padLeft(2, '0')}';
    }
    if (dataFim != null) {
      params['dataFim'] = '${dataFim.year}-'
          '${dataFim.month.toString().padLeft(2, '0')}-'
          '${dataFim.day.toString().padLeft(2, '0')}';
    }
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final data = await ApiClient.get('/estoque/todas?$query');

    final itens = (data['data'] as List? ?? [])
        .map((e) => RelacaoOSModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? itens.length;
    return RelacoesOSPaginadasModel(itens: itens, total: total);
  }

  Future<MovimentacoesPaginadasModel> listarMovimentacoes({
    String? numeroOS,
    String? material,
    String? identificador,
    String? medida,
    String? comprimento,
    String? largura,
    String? espessura,
    String? tipo,
    DateTime? dataInicio,
    DateTime? dataFim,
    required int pagina,
    int porPagina = 100,
  }) async {
    final params = <String, String>{
      'pagina':    pagina.toString(),
      'porPagina': porPagina.toString(),
    };
    if (numeroOS != null && numeroOS.isNotEmpty)           params['numeroOS']      = numeroOS;
    if (material != null && material.isNotEmpty)           params['material']      = material;
    if (identificador != null && identificador.isNotEmpty) params['identificador'] = identificador;
    if (medida != null && medida.isNotEmpty)               params['medida']        = medida;
    if (comprimento != null && comprimento.isNotEmpty)     params['comprimento']   = comprimento;
    if (largura != null && largura.isNotEmpty)             params['largura']       = largura;
    if (espessura != null && espessura.isNotEmpty)         params['espessura']     = espessura;
    if (tipo != null && tipo.isNotEmpty)                   params['tipo']          = tipo;
    if (dataInicio != null) {
      params['dataInicio'] = '${dataInicio.year}-'
          '${dataInicio.month.toString().padLeft(2, '0')}-'
          '${dataInicio.day.toString().padLeft(2, '0')}';
    }
    if (dataFim != null) {
      params['dataFim'] = '${dataFim.year}-'
          '${dataFim.month.toString().padLeft(2, '0')}-'
          '${dataFim.day.toString().padLeft(2, '0')}';
    }

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final data = await ApiClient.get('/estoque/movimentacoes?$query');

    final itens = (data['data'] as List? ?? [])
        .map((e) => MovimentacaoComOSModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? itens.length;
    return MovimentacoesPaginadasModel(itens: itens, total: total);
  }

  Future<void> atualizarPrecoMovimentacao(
    int movimentacaoId, {
    double? precoUnitario,
    double? precoM2,
  }) async {
    final body = <String, dynamic>{};
    if (precoUnitario != null) body['precoUnitario'] = precoUnitario;
    if (precoM2       != null) body['precoM2']       = precoM2;
    await ApiClient.patch(
      '/estoque/movimentacoes/$movimentacaoId/preco',
      body,
    );
  }
}