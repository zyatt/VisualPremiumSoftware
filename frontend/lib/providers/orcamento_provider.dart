import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/material_model.dart';
import '../repositories/orcamento_repository.dart';
import '../utils/api_client.dart';

class PrecoFornecedorData {
  double? preco;
  String fornecedorNome;

  double? precoMetroQuadrado;

  String? observacao;

  PrecoFornecedorData({
    required this.fornecedorNome,
    this.preco,
    this.precoMetroQuadrado,
    this.observacao,
  });

  Map<String, dynamic> toJson() => {
        'fornecedorNome': fornecedorNome,
        'preco': preco,
        'precoMetroQuadrado': precoMetroQuadrado,
        'observacao': observacao,
      };

  factory PrecoFornecedorData.fromJson(Map<String, dynamic> j) =>
      PrecoFornecedorData(
        fornecedorNome: j['fornecedorNome'] as String,
        preco: (j['preco'] as num?)?.toDouble(),
        precoMetroQuadrado: (j['precoMetroQuadrado'] as num?)?.toDouble(),
        observacao: j['observacao'] as String?,
      );
}

class ItemOrcamentoData {
  final String itemId;
  final int materialId;
  final String materialNome;
  final String? materialUnidade;
  final String? materialCategoria;
  final String? materialMedida;
  final String? materialEspessura;
  final String? materialIdentificador;
  final String? materialStatus;

  final double? materialLargura;

  final double? materialComprimento;

  final double? estoqueMinimo;
  double quantidade;

  double? qtdUnidade;
  Map<int, PrecoFornecedorData> precos;
  int? fornecedorSelecionado;

  ItemOrcamentoData({
    String? itemId,
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialCategoria,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.materialStatus,
    this.materialLargura,
    this.materialComprimento,
    this.estoqueMinimo,
    this.quantidade = 1,
    this.qtdUnidade,
    Map<int, PrecoFornecedorData>? precos,
    this.fornecedorSelecionado,
  }) : itemId = itemId ?? const Uuid().v4(),
       precos = precos ?? {};

  bool get precisaQtdUnidade {
    final u = (materialUnidade ?? '').toUpperCase().trim();
    return u.isNotEmpty && u != 'UNIDADE';
  }

  String get labelQtdUnidade {
    final u = (materialUnidade ?? '').toUpperCase().trim();
    switch (u) {
      case 'M/L':    return 'M/L por unidade';
      case 'ML':     return 'ML por unidade';
      case 'KG':     return 'KG por unidade';
      case 'G':      return 'g por unidade';
      case 'L':      return 'L por unidade';
      case 'M':      return 'M por unidade';
      case 'M2':
      case 'M²':     return 'M² por unidade';
      default:       return '$u por unidade';
    }
  }

  String? get materialDimensaoFormatada {
    if (materialMedida != null && materialMedida!.isNotEmpty) return null;
    final l = materialLargura;
    final c = materialComprimento;
    if (l == null || c == null || l <= 0 || c <= 0) return null;
    String fmt(double v) =>
        v == v.truncateToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
    return '${fmt(c)}x${fmt(l)}m';
  }

  double? get areaM2PorUnidade {
    final l = materialLargura;
    if (l == null || l <= 0) return null;
    if (!precisaQtdUnidade) {
      final c = materialComprimento;
      if (c == null || c <= 0) return null;
      return l * c;
    }
    final q = qtdUnidade;
    if (q == null || q <= 0) return null;
    return l * q;
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'materialId': materialId,
        'materialNome': materialNome,
        'materialUnidade': materialUnidade,
        'materialCategoria': materialCategoria,
        'materialMedida': materialMedida,
        'materialEspessura': materialEspessura,
        'materialIdentificador': materialIdentificador,
        'materialStatus': materialStatus,
        'materialLargura': materialLargura,
        'materialComprimento': materialComprimento,
        'estoqueMinimo': estoqueMinimo,
        'quantidade': quantidade,
        'qtdUnidade': qtdUnidade,
        'precos': precos.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'fornecedorSelecionado': fornecedorSelecionado,
      };

  Map<String, dynamic> toJsonComparavel() {
    final m = toJson();
    m.remove('itemId');
    return m;
  }

  factory ItemOrcamentoData.fromJson(Map<String, dynamic> j) =>
      ItemOrcamentoData(
        itemId: j['itemId'] as String?,
        materialId: j['materialId'] as int,
        materialNome: j['materialNome'] as String,
        materialUnidade: j['materialUnidade'] as String?,
        materialCategoria: j['materialCategoria'] as String?,
        materialMedida: j['materialMedida'] as String?,
        materialEspessura: j['materialEspessura'] as String?,
        materialIdentificador: j['materialIdentificador'] as String?,
        materialStatus: j['materialStatus'] as String?,
        materialLargura: (j['materialLargura'] as num?)?.toDouble(),
        materialComprimento: (j['materialComprimento'] as num?)?.toDouble(),
        estoqueMinimo: (j['estoqueMinimo'] as num?)?.toDouble(),
        quantidade: (j['quantidade'] as num).toDouble(),
        qtdUnidade: (j['qtdUnidade'] as num?)?.toDouble(),
        precos: (j['precos'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(
            int.parse(k),
            PrecoFornecedorData.fromJson(v as Map<String, dynamic>),
          ),
        ),
        fornecedorSelecionado: j['fornecedorSelecionado'] as int?,
      );
}

class OrcamentoTab {
  final String id;
  String titulo;
  List<ItemOrcamentoData> itens;

  int? servidorId;

  List<int> fornecedoresOcultos;

  bool aguardandoAprovacao;
  bool jaFinalizado;
  bool modoGerarOC;

  bool modoEdicao;

  bool somenteLeitura;

  String modoPrecificacao;

  int? criadorId;

  final bool criadaPeloTour;

  String? _assinaturaSalva;

  String _calcularAssinatura() {
    final itensOrdenados = itens.map((i) => i.toJsonComparavel()).toList()
      ..sort((a, b) => (a['materialId'] as int? ?? 0)
          .compareTo(b['materialId'] as int? ?? 0));
    return jsonEncode({
      'titulo': titulo,
      'modoPrecificacao': modoPrecificacao,
      'fornecedoresOcultos': List<int>.of(fornecedoresOcultos)..sort(),
      'itens': itensOrdenados,
    });
  }

  void marcarComoSalvo() {
    _assinaturaSalva = _calcularAssinatura();
  }

  bool get houveAlteracao {
    if (_assinaturaSalva == null) return false;
    return _assinaturaSalva != _calcularAssinatura();
  }

  OrcamentoTab({
    required this.id,
    required this.titulo,
    List<ItemOrcamentoData>? itens,
    this.servidorId,
    List<int>? fornecedoresOcultos,
    this.aguardandoAprovacao = false,
    this.jaFinalizado = false,
    this.modoGerarOC = false,
    this.modoEdicao = false,
    this.somenteLeitura = false,
    this.modoPrecificacao = 'UNIDADE',
    this.criadaPeloTour = false,
    this.criadorId,
  }) : itens = itens ?? [],
       fornecedoresOcultos = fornecedoresOcultos ?? [];

  bool get orcarPorMetroLinear => modoPrecificacao == 'METRO_LINEAR';

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'itens': itens.map((i) => i.toJson()).toList(),
        'servidorId': servidorId,
        'fornecedoresOcultos': fornecedoresOcultos,
        'aguardandoAprovacao': aguardandoAprovacao,
        'jaFinalizado': jaFinalizado,
        'modoGerarOC': modoGerarOC,
        'modoEdicao': modoEdicao,
        'modoPrecificacao': modoPrecificacao,
        'criadorId': criadorId,

      };

  factory OrcamentoTab.fromJson(Map<String, dynamic> j) => OrcamentoTab(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        servidorId: j['servidorId'] as int?,
        fornecedoresOcultos: (j['fornecedoresOcultos'] as List? ?? [])
            .map((e) => e as int)
            .toList(),
        aguardandoAprovacao: j['aguardandoAprovacao'] as bool? ?? false,
        jaFinalizado: j['jaFinalizado'] as bool? ?? false,
        modoGerarOC: j['modoGerarOC'] as bool? ?? false,
        modoEdicao: j['modoEdicao'] as bool? ?? false,
        modoPrecificacao: j['modoPrecificacao'] as String? ?? 'UNIDADE',
        criadorId: j['criadorId'] as int?,
        itens: (j['itens'] as List)
            .map((i) => ItemOrcamentoData.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

class OrcamentoAbertoMaterialInfo {
  final int materialId;
  final String nome;
  final String? medida;
  final String? espessura;
  final String? identificador;
  final double? largura;
  final double? comprimento;

  OrcamentoAbertoMaterialInfo({
    required this.materialId,
    required this.nome,
    this.medida,
    this.espessura,
    this.identificador,
    this.largura,
    this.comprimento,
  });

  factory OrcamentoAbertoMaterialInfo.fromJson(Map<String, dynamic> j) =>
      OrcamentoAbertoMaterialInfo(
        materialId: j['id'] as int,
        nome: j['nome'] as String? ?? '',
        medida: j['medida'] as String?,
        espessura: j['espessura'] as String?,
        identificador: j['identificador'] as String?,
        largura: j['largura'] != null ? double.tryParse(j['largura'].toString()) : null,
        comprimento: j['comprimento'] != null ? double.tryParse(j['comprimento'].toString()) : null,
      );
}

class OrcamentoAbertoInfo {
  final int id;
  final String titulo;
  final int? criadorId;
  final String? criadorNome;
  final int quantidadeItens;
  final DateTime atualizadoEm;
  final DateTime? criadoEm;

  final int? travaUsuarioId;
  final String? travaUsuarioNome;

  final List<OrcamentoAbertoMaterialInfo> materiais;

  OrcamentoAbertoInfo({
    required this.id,
    required this.titulo,
    this.criadorId,
    this.criadorNome,
    required this.quantidadeItens,
    required this.atualizadoEm,
    this.criadoEm,
    this.travaUsuarioId,
    this.travaUsuarioNome,
    this.materiais = const [],
  });

  bool emEdicaoPorOutro(int? meuUsuarioId) =>
      travaUsuarioId != null && travaUsuarioId != meuUsuarioId;

  @Deprecated('Use emEdicaoPorOutro(meuUsuarioId) — este getter não distingue a própria trava de uma alheia.')
  bool get emEdicaoPorAlguem => travaUsuarioId != null;

  static List<OrcamentoAbertoMaterialInfo> _materiaisUnicosFromJson(List itens) {
    final Map<int, OrcamentoAbertoMaterialInfo> unicos = {};
    for (final item in itens) {
      final materialId = item['materialId'] as int?;
      if (materialId == null || unicos.containsKey(materialId)) continue;
      final materialData = item['material'] as Map<String, dynamic>?;
      if (materialData == null) continue;
      unicos[materialId] = OrcamentoAbertoMaterialInfo.fromJson(materialData);
    }
    return unicos.values.toList();
  }

  factory OrcamentoAbertoInfo.fromJson(Map<String, dynamic> j) {
    final itens = (j['itens'] as List? ?? []);
    return OrcamentoAbertoInfo(
      id: j['id'] as int,
      titulo: j['titulo'] as String? ?? 'Orçamento',
      criadorId: j['criadorId'] as int? ?? (j['criador'] as Map?)?['id'] as int?,
      criadorNome: (j['criador'] as Map?)?['nome'] as String?,
      quantidadeItens: itens.length,
      atualizadoEm: DateTime.tryParse(j['atualizadoEm']?.toString() ?? '') ?? DateTime.now(),
      criadoEm: j['criadoEm'] != null ? DateTime.tryParse(j['criadoEm'].toString()) : null,
      travaUsuarioId: j['travaUsuarioId'] as int? ?? (j['travaUsuario'] as Map?)?['id'] as int?,
      travaUsuarioNome: (j['travaUsuario'] as Map?)?['nome'] as String?,
      materiais: _materiaisUnicosFromJson(itens),
    );
  }
}

class OrcamentoProvider extends ChangeNotifier {

  static String _kAbas(int userId)     => 'orcamento_abas_$userId';
  static String _kAbaAtiva(int userId) => 'orcamento_aba_ativa_$userId';

  final _uuid = const Uuid();
  final _repo = OrcamentoRepository();
  int? _userId;
  String? _userNome;

  String? get usuarioAtualNome => _userNome;

  int? get usuarioAtualId => _userId;

  int _edicaoLocalTrigger = 0;
  int get edicaoLocalTrigger => _edicaoLocalTrigger;
  void _sinalizarEdicaoLocal() => _edicaoLocalTrigger++;

  Future<Map<String, dynamic>?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (_) {
      return null;
    }
  }

  final List<OrcamentoTab> _abas = [];
  List<OrcamentoTab> get abas => List.unmodifiable(_abas);

  List<OrcamentoAbertoInfo> _orcamentosAbertos = [];
  bool _carregandoOrcamentosAbertos = false;
  String? _erroOrcamentosAbertos;

  List<OrcamentoAbertoInfo> get orcamentosAbertos => List.unmodifiable(_orcamentosAbertos);
  bool get carregandoOrcamentosAbertos => _carregandoOrcamentosAbertos;
  String? get erroOrcamentosAbertos => _erroOrcamentosAbertos;

  List<MapEntry<int, List<OrcamentoAbertoInfo>>> get orcamentosAbertosPorUsuario {
    final Map<int, List<OrcamentoAbertoInfo>> agrupado = {};
    for (final o in _orcamentosAbertos) {
      if (o.criadorId == null) continue;
      agrupado.putIfAbsent(o.criadorId!, () => []).add(o);
    }
    final entradas = agrupado.entries.toList()
      ..sort((a, b) {
        final maisRecenteA = a.value.map((o) => o.atualizadoEm).reduce((x, y) => x.isAfter(y) ? x : y);
        final maisRecenteB = b.value.map((o) => o.atualizadoEm).reduce((x, y) => x.isAfter(y) ? x : y);
        return maisRecenteB.compareTo(maisRecenteA);
      });
    return entradas;
  }

  Future<void> carregarOrcamentosAbertos() async {
    _carregandoOrcamentosAbertos = true;
    _erroOrcamentosAbertos = null;
    notifyListeners();
    try {
      final data = await _repo.listarAbertos();
      _orcamentosAbertos = data
          .map((j) => OrcamentoAbertoInfo.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _erroOrcamentosAbertos = e.toString().replaceFirst('Exception: ', '');
      debugPrint('OrcamentoProvider.carregarOrcamentosAbertos erro: $e');
    } finally {
      _carregandoOrcamentosAbertos = false;
      notifyListeners();
    }
  }

  StreamSubscription<String>? _sseSub;
  HttpClient? _sseRawClient;
  String _sseBuffer = '';

  int _sseConexaoId = 0;

  void _conectarSSE() {

    _sseSub?.cancel();
    _sseSub = null;
    _sseRawClient?.close(force: true);
    _sseRawClient = null;

    final token = ApiClient.token;
    if (token == null) return;

    final meuId = ++_sseConexaoId;
    debugPrint('[FECHAR][Orçamentos] ${DateTime.now().toIso8601String()} — abrindo nova conexão SSE, geração $meuId');

    final uri = Uri.parse('${ApiClient.baseUrl}/api/orcamentos/stream');
    final rawClient = HttpClient();
    _sseRawClient = rawClient;
    final client = io_client.IOClient(rawClient);

    final req = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';

    client.send(req).then((streamedResp) {
      if (meuId != _sseConexaoId) {

        rawClient.close(force: true);
        return;
      }

      if (streamedResp.statusCode == 401 || streamedResp.statusCode == 403) {
        debugPrint(
          'OrcamentoProvider SSE: sem permissão para o stream '
          '(${streamedResp.statusCode}). Não haverá nova tentativa automática.',
        );
        rawClient.close(force: true);
        return;
      }

      if (streamedResp.statusCode < 200 || streamedResp.statusCode >= 300) {
        debugPrint('OrcamentoProvider SSE status inesperado: ${streamedResp.statusCode}');
        rawClient.close(force: true);
        Future.delayed(const Duration(seconds: 5), _conectarSSE);
        return;
      }

      final stream = streamedResp.stream.transform(utf8.decoder).transform(const LineSplitter());
      _sseSub = stream.listen(
        _processarLinhaSSE,
        onError: (e) {
          if (meuId != _sseConexaoId) return;
          debugPrint('OrcamentoProvider SSE erro: $e');
          Future.delayed(const Duration(seconds: 5), _conectarSSE);
        },
        onDone: () {
          if (meuId != _sseConexaoId) return;
          Future.delayed(const Duration(seconds: 5), _conectarSSE);
        },
        cancelOnError: true,
      );
    }).catchError((e) {
      if (meuId != _sseConexaoId) return;
      debugPrint('OrcamentoProvider SSE connect erro: $e');
      rawClient.close(force: true);
      Future.delayed(const Duration(seconds: 5), _conectarSSE);
    });
  }

  void _processarLinhaSSE(String linha) {
    if (!linha.startsWith('data: ')) return;
    _sseBuffer = linha.substring(6);
    try {
      final evento = jsonDecode(_sseBuffer) as Map<String, dynamic>;
      final tipo = evento['tipo'] as String?;

      switch (tipo) {
        case 'orcamento_criado':
          final info = OrcamentoAbertoInfo.fromJson(evento['orcamento'] as Map<String, dynamic>);
          _orcamentosAbertos.removeWhere((o) => o.id == info.id);
          _orcamentosAbertos.insert(0, info);
          notifyListeners();
          break;

        case 'orcamento_voltou_a_aberto':
          final info = OrcamentoAbertoInfo.fromJson(evento['orcamento'] as Map<String, dynamic>);
          _orcamentosAbertos.removeWhere((o) => o.id == info.id);
          _orcamentosAbertos.insert(0, info);
          notifyListeners();
          break;

        case 'orcamento_saiu_de_aberto':
          final id = evento['orcamentoId'] as int?;
          if (id != null) {
            _orcamentosAbertos.removeWhere((o) => o.id == id);
            notifyListeners();
          }
          break;

        case 'orcamento_item_alterado':

          final id = evento['orcamentoId'] as int?;
          if (id != null) _atualizarUmOrcamentoAberto(id);

          final origemUsuarioId = evento['origemUsuarioId'] as int?;
          final ecoDoProprioUsuario = origemUsuarioId != null && origemUsuarioId == _userId;
          if (id != null && !ecoDoProprioUsuario) _emitirMudancaExterna(id);
          break;

        case 'orcamento_travado':
          final id = evento['orcamentoId'] as int?;
          final uid = evento['travaUsuarioId'] as int?;
          final nome = evento['travaUsuarioNome'] as String?;
          if (id != null) _atualizarTravaLocal(id, uid, nome);
          break;

        case 'orcamento_destravado':
          final id = evento['orcamentoId'] as int?;
          if (id != null) _atualizarTravaLocal(id, null, null);
          break;
      }
    } catch (_) {

    }
    _sseBuffer = '';
  }

  void _atualizarTravaLocal(int orcamentoId, int? travaUsuarioId, String? travaUsuarioNome) {
    final idx = _orcamentosAbertos.indexWhere((o) => o.id == orcamentoId);
    if (idx != -1) {
      final atual = _orcamentosAbertos[idx];
      _orcamentosAbertos[idx] = OrcamentoAbertoInfo(
        id: atual.id,
        titulo: atual.titulo,
        criadorId: atual.criadorId,
        criadorNome: atual.criadorNome,
        quantidadeItens: atual.quantidadeItens,
        atualizadoEm: atual.atualizadoEm,
        criadoEm: atual.criadoEm,
        travaUsuarioId: travaUsuarioId,
        travaUsuarioNome: travaUsuarioNome,
        materiais: atual.materiais,
      );
      notifyListeners();
    }

    final travaEhDeOutroUsuario = travaUsuarioId != null && travaUsuarioId != _userId;
    final destravouEAntesEraDeOutro = travaUsuarioId == null;
    if (_abas.any((a) => a.servidorId == orcamentoId) &&
        (travaEhDeOutroUsuario || destravouEAntesEraDeOutro)) {
      _travaExternaTrigger++;
      _travaExternaOrcamentoId = orcamentoId;
      _travaExternaUsuarioNome = travaUsuarioNome;
      notifyListeners();
    }
  }

  Future<void> _atualizarUmOrcamentoAberto(int orcamentoId) async {
    try {
      final data = await _repo.buscarPorId(orcamentoId);
      if (data['status'] != 'ABERTO') return;
      final info = OrcamentoAbertoInfo.fromJson(data);
      final idx = _orcamentosAbertos.indexWhere((o) => o.id == orcamentoId);
      if (idx != -1) {

        final atual = _orcamentosAbertos[idx];
        _orcamentosAbertos[idx] = OrcamentoAbertoInfo(
          id: info.id,
          titulo: info.titulo,
          criadorId: info.criadorId,
          criadorNome: info.criadorNome,
          quantidadeItens: info.quantidadeItens,
          atualizadoEm: info.atualizadoEm,
          travaUsuarioId: atual.travaUsuarioId,
          travaUsuarioNome: atual.travaUsuarioNome,
        );
      } else {
        _orcamentosAbertos.insert(0, info);
      }
      notifyListeners();
    } catch (_) {}
  }

  int _mudancaExternaTrigger = 0;
  int? _mudancaExternaOrcamentoId;
  int get mudancaExternaTrigger => _mudancaExternaTrigger;
  int? get mudancaExternaOrcamentoId => _mudancaExternaOrcamentoId;

  void _emitirMudancaExterna(int orcamentoId) {
    _mudancaExternaOrcamentoId = orcamentoId;
    _mudancaExternaTrigger++;
    notifyListeners();
  }

  int _travaExternaTrigger = 0;
  int? _travaExternaOrcamentoId;
  String? _travaExternaUsuarioNome;
  int get travaExternaTrigger => _travaExternaTrigger;
  int? get travaExternaOrcamentoId => _travaExternaOrcamentoId;
  String? get travaExternaUsuarioNome => _travaExternaUsuarioNome;

  Future<void> inicializarTempoReal() async {
    await carregarOrcamentosAbertos();
    _conectarSSE();
  }

  void _pararTempoReal() {
    _sseConexaoId++;
    _sseSub?.cancel();
    _sseSub = null;
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
    _orcamentosAbertos = [];
  }

  void encerrarConexoesTempoReal() {
    debugPrint('[FECHAR][Orçamentos] ${DateTime.now().toIso8601String()} — encerrarConexoesTempoReal chamado, geração $_sseConexaoId -> ${_sseConexaoId + 1}');
    _sseConexaoId++;
    _sseSub?.cancel();
    _sseSub = null;
    _sseRawClient?.close(force: true);
    _sseRawClient = null;
  }

  int _abaAtiva = 0;
  int get abaAtiva => _abaAtiva;

  OrcamentoTab? get tabAtual => _abas.isEmpty ? null : _abas[_abaAtiva];

  bool _carregado = false;
  bool get carregado => _carregado;

  int? _orcamentoParaAbrirPendente;
  int? get orcamentoParaAbrirPendente => _orcamentoParaAbrirPendente;

  void solicitarAberturaOrcamento(int orcamentoId) {
    _orcamentoParaAbrirPendente = orcamentoId;
    notifyListeners();
  }

  void consumirOrcamentoParaAbrirPendente() {
    _orcamentoParaAbrirPendente = null;
  }

  OrcamentoProvider();

  static const _rolesComAcessoOrcamentos = ['ADMIN', 'GERENTE', 'COMPRAS'];

  Future<void> trocarUsuario(int? userId, [String? userNome, String? userRole]) async {
    if (_userId == userId) {
      if (userNome != null && userNome.trim().isNotEmpty) _userNome = userNome.trim();
      return;
    }
    _userId = userId;
    _userNome = (userNome != null && userNome.trim().isNotEmpty) ? userNome.trim() : null;
    _abas.clear();
    _abaAtiva = 0;
    _carregado = false;
    _pararTempoReal();
    notifyListeners();

    if (userId == null) {
      _carregado = true;
      notifyListeners();
      return;
    }

    final temAcesso = userRole == null ||
        _rolesComAcessoOrcamentos.contains(userRole.trim().toUpperCase());

    await _carregar();

    if (temAcesso) {
      await inicializarTempoReal();
    } else {
      debugPrint(
        'OrcamentoProvider: usuário sem role de acesso a Orçamentos '
        '(role="$userRole"). Tempo real não será iniciado.',
      );
      _carregado = true;
      notifyListeners();
    }
  }

  Future<void> _carregar() async {
    if (_userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final abasJson = prefs.getString(_kAbas(_userId!));
      if (abasJson != null) {
        final lista = jsonDecode(abasJson) as List;
        _abas.addAll(
          lista.map((j) => OrcamentoTab.fromJson(j as Map<String, dynamic>)),
        );
      }

      const nomesFicticiosDoTour = {'MATERIAL EXEMPLO', 'ADESIVO'};
      _abas.removeWhere((a) =>
          a.servidorId == null &&
          a.itens.isNotEmpty &&
          a.itens.length <= 2 &&
          a.itens.every((i) => nomesFicticiosDoTour.contains(i.materialNome)));
      _abaAtiva = prefs.getInt(_kAbaAtiva(_userId!)) ?? 0;
      if (_abaAtiva >= _abas.length) _abaAtiva = 0;
    } catch (_) {}

    _carregado = true;
    notifyListeners();
  }

  Future<void> salvarAbasAgora() async {
    await _salvarAbas();
    notifyListeners();
  }

  Future<void> _salvarAbas() async {
    if (_userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final abasPersistiveis = _abas.where((a) => !a.criadaPeloTour).toList();
      await prefs.setString(
        _kAbas(_userId!),
        jsonEncode(abasPersistiveis.map((a) => a.toJson()).toList()),
      );

      final abaAtivaObj = _abas.isNotEmpty && _abaAtiva < _abas.length
          ? _abas[_abaAtiva]
          : null;
      final indicePersistivel = abaAtivaObj == null
          ? 0
          : abasPersistiveis.indexOf(abaAtivaObj);
      await prefs.setInt(
        _kAbaAtiva(_userId!),
        indicePersistivel < 0 ? 0 : indicePersistivel,
      );
    } catch (_) {}
  }

  void _novaAba({bool notificar = true, bool criadaPeloTour = false}) {
    final idx = _abas.length + 1;
    final tab = OrcamentoTab(
      id: _uuid.v4(),
      titulo: 'Orçamento $idx',
      criadaPeloTour: criadaPeloTour,
    );
    _abas.add(tab);
    _abaAtiva = _abas.length - 1;
    if (notificar) {
      _salvarAbas();
      notifyListeners();
    }

    if (!criadaPeloTour) {
      _criarOrcamentoNoServidor(tab);
    }
  }

  final Map<String, Future<void>> _criacoesEmAndamento = {};

  Future<void> aguardarCriacaoInicial() async {
    if (tabAtual == null) return;
    final future = _criacoesEmAndamento[tabAtual!.id];
    if (future != null) await future;
  }

  int _servidorIdTravadoTrigger = 0;
  int? _servidorIdTravadoRecente;
  int get servidorIdTravadoTrigger => _servidorIdTravadoTrigger;
  int? get servidorIdTravadoRecente => _servidorIdTravadoRecente;

  Future<void> _criarOrcamentoNoServidor(OrcamentoTab tab) async {
    final future = _criarOrcamentoNoServidorImpl(tab);
    _criacoesEmAndamento[tab.id] = future;
    await future;
    _criacoesEmAndamento.remove(tab.id);
  }

  Future<void> _criarOrcamentoNoServidorImpl(OrcamentoTab tab) async {
    try {
      final criado = await _repo.criar(tab.titulo);
      final id = criado['id'] as int;

      final aindaExiste = _abas.any((a) => a.id == tab.id);
      if (!aindaExiste) {

        try {
          await _repo.cancelar(id);
        } catch (_) {}
        return;
      }
      tab.servidorId = id;
      tab.criadorId = _userId;
      _salvarAbas();
      notifyListeners();

      try {
        await _repo.travar(id);
        _servidorIdTravadoRecente = id;
        _servidorIdTravadoTrigger++;
        notifyListeners();
      } catch (e) {
        debugPrint('OrcamentoProvider._criarOrcamentoNoServidor: falha ao travar orcamentoId=$id: $e');
      }
    } catch (e) {
      debugPrint('OrcamentoProvider._criarOrcamentoNoServidor erro: $e');
    }
  }

  void adicionarAba({bool criadaPeloTour = false}) =>
      _novaAba(criadaPeloTour: criadaPeloTour);

  void selecionarAba(int index) {
    if (index < 0 || index >= _abas.length) return;
    _abaAtiva = index;
    _salvarAbas();
    notifyListeners();
  }

  void renomearAba(int index, String titulo) {
    if (index < 0 || index >= _abas.length) return;
    _abas[index].titulo = titulo;
    _salvarAbas();
    notifyListeners();
  }

  void setServidorIdTab(int? id) {
    if (tabAtual == null) return;
    tabAtual!.servidorId = id;
    _salvarAbas();
    notifyListeners();
  }

  void setFornecedoresOcultosTab(List<int> ids) {
    if (tabAtual == null) return;
    tabAtual!.fornecedoresOcultos = List.of(ids);
    _salvarAbas();
    notifyListeners();
  }

  void definirFornecedorOcultoLocal(int fornecedorId, bool oculto) {
    if (tabAtual == null) return;
    final lista = tabAtual!.fornecedoresOcultos;
    if (oculto) {
      if (!lista.contains(fornecedorId)) lista.add(fornecedorId);
    } else {
      lista.remove(fornecedorId);
    }
    _salvarAbas();
    notifyListeners();
  }

  void atualizarFlagsTab({
    bool? aguardandoAprovacao,
    bool? jaFinalizado,
    bool? modoGerarOC,
    bool? modoEdicao,
    bool? somenteLeitura,
  }) {
    if (tabAtual == null) return;
    if (aguardandoAprovacao != null) tabAtual!.aguardandoAprovacao = aguardandoAprovacao;
    if (jaFinalizado != null) tabAtual!.jaFinalizado = jaFinalizado;
    if (modoGerarOC != null) tabAtual!.modoGerarOC = modoGerarOC;
    if (modoEdicao != null) tabAtual!.modoEdicao = modoEdicao;
    if (somenteLeitura != null) tabAtual!.somenteLeitura = somenteLeitura;
    _salvarAbas();
    notifyListeners();
  }

  void adicionarItem(ItemOrcamentoData item) {
    if (tabAtual == null) return;

    final idx = tabAtual!.itens.indexWhere(
      (i) => i.itemId == item.itemId ||
             i.materialId == item.materialId,
    );
    if (idx >= 0) {
      tabAtual!.itens[idx] = item;
      _salvarAbas();
      _sinalizarEdicaoLocal();
      notifyListeners();
      return;
    }

    tabAtual!.itens.add(item);
    _salvarAbas();
    _sinalizarEdicaoLocal();
    notifyListeners();
  }

  void substituirItensTab(List<ItemOrcamentoData> itens) {
    if (tabAtual == null) return;
    tabAtual!.itens
      ..clear()
      ..addAll(itens);
    _salvarAbas();
    notifyListeners();
  }

  int adicionarItensEmLote(String tituloAba, List<ItemOrcamentoData> itens) {
    _abas.add(OrcamentoTab(
      id: _uuid.v4(),
      titulo: tituloAba,
      itens: List.of(itens),
    ));
    _abaAtiva = _abas.length - 1;
    _salvarAbas();
    notifyListeners();
    return _abaAtiva;
  }

  bool atualizarDadosMateriaisDosItens(List<MaterialModel> materiaisAtuais) {
    if (tabAtual == null || tabAtual!.itens.isEmpty) return false;
    final porId = {for (final m in materiaisAtuais) m.id: m};
    var mudou = false;
    for (var i = 0; i < tabAtual!.itens.length; i++) {
      final old = tabAtual!.itens[i];
      final m = porId[old.materialId];
      if (m == null) continue;
      if (old.materialNome == m.nome &&
          old.materialUnidade == m.unidade &&
          old.materialCategoria == m.categoria &&
          old.estoqueMinimo == m.estoqueMinimo &&
          old.materialLargura == m.largura &&
          old.materialComprimento == m.comprimento &&
          old.materialMedida == m.medida &&
          old.materialEspessura == m.espessura &&
          old.materialIdentificador == m.identificador &&
          old.materialStatus == m.status) {
        continue;
      }
      tabAtual!.itens[i] = ItemOrcamentoData(
        itemId: old.itemId,
        materialId: old.materialId,
        materialNome: m.nome,
        materialUnidade: m.unidade,
        materialCategoria: m.categoria,
        materialMedida: m.medida,
        materialEspessura: m.espessura,
        materialIdentificador: m.identificador,
        materialStatus: m.status,
        materialLargura: m.largura,
        materialComprimento: m.comprimento,
        estoqueMinimo: m.estoqueMinimo,
        quantidade: old.quantidade,
        qtdUnidade: old.qtdUnidade,
        precos: old.precos,
        fornecedorSelecionado: old.fornecedorSelecionado,
      );
      mudou = true;
    }
    if (mudou) {
      _salvarAbas();
      notifyListeners();
    }
    return mudou;
  }

  void removerItem(String itemId) {
    tabAtual?.itens.removeWhere((i) => i.itemId == itemId);
    _salvarAbas();
    _sinalizarEdicaoLocal();
    notifyListeners();
  }

  void definirModoPrecificacao(String modo) {
    if (tabAtual == null) return;
    tabAtual!.modoPrecificacao = modo;
    _salvarAbas();
    notifyListeners();
  }

  void atualizarItem(String itemId, ItemOrcamentoData dados) {
    if (tabAtual == null) return;
    final idx = tabAtual!.itens.indexWhere((i) => i.itemId == itemId);
    if (idx >= 0) {
      tabAtual!.itens[idx] = dados;
      _salvarAbas();
      _sinalizarEdicaoLocal();
      notifyListeners();
    }
  }

  void atualizarItemParcial(String itemId, {
    double? quantidade,
    double? qtdUnidade,
    int? fornecedorSelecionado,
    bool clearFornecedor = false,
    Map<int, PrecoFornecedorData>? precos,
  }) {
    if (tabAtual == null) return;
    final idx = tabAtual!.itens.indexWhere((i) => i.itemId == itemId);
    if (idx < 0) return;
    final old = tabAtual!.itens[idx];

    var precosFinal = precos ?? old.precos;
    if (precos == null && qtdUnidade != null && old.precisaQtdUnidade) {
      final novaArea = (old.materialLargura != null && old.materialLargura! > 0 && qtdUnidade > 0)
          ? old.materialLargura! * qtdUnidade
          : null;
      if (novaArea != null) {
        precosFinal = old.precos.map((fId, pf) {
          if (pf.precoMetroQuadrado == null) return MapEntry(fId, pf);
          return MapEntry(
            fId,
            PrecoFornecedorData(
              fornecedorNome: pf.fornecedorNome,
              preco: pf.precoMetroQuadrado! * novaArea,
              precoMetroQuadrado: pf.precoMetroQuadrado,
              observacao: pf.observacao,
            ),
          );
        });
      }
    }

    tabAtual!.itens[idx] = ItemOrcamentoData(
      itemId: old.itemId,
      materialId: old.materialId,
      materialNome: old.materialNome,
      materialUnidade: old.materialUnidade,
      materialCategoria: old.materialCategoria,
      materialMedida: old.materialMedida,
      materialEspessura: old.materialEspessura,
      materialIdentificador: old.materialIdentificador,
      materialStatus: old.materialStatus,
      materialLargura: old.materialLargura,
      materialComprimento: old.materialComprimento,
      estoqueMinimo: old.estoqueMinimo,
      quantidade: quantidade ?? old.quantidade,
      qtdUnidade: qtdUnidade ?? old.qtdUnidade,
      precos: precosFinal,
      fornecedorSelecionado: clearFornecedor
          ? null
          : (fornecedorSelecionado ?? old.fornecedorSelecionado),
    );
    _salvarAbas();
    _sinalizarEdicaoLocal();
    notifyListeners();
  }

  void limparAba() {
    _fecharAbaAtual();
    notifyListeners();
  }

  void fecharAbaAposOperacao() {
    _fecharAbaAtual();
    notifyListeners();
  }

  void _fecharAbaAtual() {
    _abas.removeAt(_abaAtiva);
    if (_abaAtiva >= _abas.length) _abaAtiva = _abas.isEmpty ? 0 : _abas.length - 1;
    _salvarAbas();
  }

  void fecharAba(int index) {
    if (index < 0 || index >= _abas.length) return;
    _abas.removeAt(index);
    if (_abaAtiva >= _abas.length) _abaAtiva = _abas.isEmpty ? 0 : _abas.length - 1;
    _salvarAbas();
    notifyListeners();
  }

  void setCriadorIdTab(int? criadorId) {
    if (tabAtual == null) return;
    tabAtual!.criadorId = criadorId;
    _salvarAbas();
    notifyListeners();
  }

  bool get souCriadorDaAbaAtiva {
    if (tabAtual == null) return false;
    if (tabAtual!.criadorId == null) return true;
    return tabAtual!.criadorId == _userId;
  }

  void marcarAbaAtivaComoSalva() {
    tabAtual?.marcarComoSalvo();
  }

  bool get houveAlteracaoNaAbaAtiva => tabAtual?.houveAlteracao ?? false;

  bool souCriadorDe(int? criadorId) {
    if (criadorId == null) return false;
    return criadorId == _userId;
  }

  int ativarAbaExistente(int servidorId) {
    final idx = _abas.indexWhere((a) => a.servidorId == servidorId);
    if (idx >= 0) {
      _abaAtiva = idx;
      _salvarAbas();
      notifyListeners();
    }
    return idx;
  }

  Future<int> ativarAbaExistenteAsync(int servidorId) async {
    if (_criacoesEmAndamento.isNotEmpty) {
      await Future.wait(_criacoesEmAndamento.values.toList());
    }
    return ativarAbaExistente(servidorId);
  }

  void novoOrcamento(String titulo) {
    if (_abas.isEmpty) {
      _abas.add(OrcamentoTab(id: _uuid.v4(), titulo: titulo, modoEdicao: true));
      _abaAtiva = 0;
    } else {

      _abas[_abaAtiva] = OrcamentoTab(id: _uuid.v4(), titulo: titulo, modoEdicao: true);
    }
    _salvarAbas();
    notifyListeners();
  }

  void adicionarMaterialDireto({
    required MaterialModel material,
    required FornecedorMaterialModel fornecedor,
  }) {

    final precos = <int, PrecoFornecedorData>{};
    for (final fm in material.fornecedorMateriais) {
      precos[fm.fornecedorId] = PrecoFornecedorData(
        fornecedorNome: fm.fornecedorNome,
        preco:   fm.preco > 0 ? fm.preco : null,
      );
    }

    // Defensivo: o objeto `material` pode ter vindo de um endpoint de
    // busca/listagem que não trouxe o vínculo completo em
    // fornecedorMateriais (versão "leve"). Sem isto, o fornecedor que o
    // usuário está de fato selecionando agora poderia nunca virar coluna
    // na tabela comparativa.
    precos.putIfAbsent(
      fornecedor.fornecedorId,
      () => PrecoFornecedorData(
        fornecedorNome: fornecedor.fornecedorNome,
        preco: fornecedor.preco > 0 ? fornecedor.preco : null,
      ),
    );

    final item = ItemOrcamentoData(
      materialId:            material.id,
      materialNome:          material.nome,
      materialUnidade:       material.unidade,
      materialCategoria:     material.categoria,
      materialMedida:        material.medida,
      materialEspessura:     material.espessura,
      materialIdentificador: material.identificador,
      materialStatus:        material.status,
      materialLargura:       material.largura,
      materialComprimento:   material.comprimento,
      estoqueMinimo:         material.estoqueMinimo,
      precos:                precos,
      fornecedorSelecionado: fornecedor.fornecedorId,
    );
    adicionarItem(item);
  }

  bool get podeGerarOrdem {
    if (tabAtual == null || tabAtual!.itens.isEmpty) return false;
    final ocultos = tabAtual!.fornecedoresOcultos.toSet();
    final fornecedores = tabAtual!.itens
        .where((i) => i.fornecedorSelecionado != null && !ocultos.contains(i.fornecedorSelecionado))
        .map((i) => i.fornecedorSelecionado!)
        .toSet();
    return fornecedores.isNotEmpty &&
        tabAtual!.itens.every((i) =>
            i.fornecedorSelecionado != null && !ocultos.contains(i.fornecedorSelecionado));
  }

  @override
  void dispose() {
    encerrarConexoesTempoReal();
    super.dispose();
  }
}