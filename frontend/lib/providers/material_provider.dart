import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/material_model.dart';
import '../repositories/material_repository.dart';
import '../utils/api_client.dart';

/// Dados de um material encaminhado via chat (ver EncaminhamentoChatCard),
/// usados pela EstoquePage para abrir automaticamente a categoria certa já
/// filtrada — mesmo papel que MaterialCriticoNotificacao cumpre para o
/// MaterialCriticoBanner, mas alimentado por um encaminhamento de chat em
/// vez de um evento SSE.
class FiltroMaterialChat {
  final int? materialId;
  final String? nome;
  final String? categoria;
  final String? identificador;
  final String? medida;
  final String? espessura;
  const FiltroMaterialChat({
    this.materialId,
    this.nome,
    this.categoria,
    this.identificador,
    this.medida,
    this.espessura,
  });
}

/// Remove prefixos como "Exception:", "HttpException:" que o Dart
/// adiciona automaticamente ao fazer e.toString() em exceções.
///
/// Quando o erro é de conexão (sem internet / servidor fora do ar), retorna
/// uma mensagem amigável contextualizada com a ação que estava sendo feita
/// (ex: "Erro ao carregar materiais"). Quando é um erro específico vindo do
/// backend (ex: validação), retorna a mensagem original já tratada.
String _mensagemErro(Object e, {required String acao}) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Erro ao $acao: Verifique a conexão com o servidor.';
  }
  // Erro bruto de violação de chave estrangeira (ex.: Postgres/Prisma
  // "violates RESTRICT setting of foreign key constraint..."), caso vaze
  // do backend sem ser traduzido antes. Evita expor detalhes técnicos do
  // banco de dados ao usuário final.
  if (raw.contains('foreign key constraint') ||
      raw.contains('violates RESTRICT') ||
      raw.contains('P2003')) {
    return 'Não é possível excluir: este item está vinculado a outros registros '
        '(movimentações, orçamentos ou ordens de compra). Desative-o em vez de excluí-lo.';
  }
  final msg = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
  return 'Erro ao $acao: $msg';
}

class MaterialProvider extends ChangeNotifier {
  final MaterialRepository _repo = MaterialRepository();

  List<MaterialModel> _materiais = [];
  List<MaterialModel> get materiais => _materiais;

  List<String> _categorias = [];
  List<String> get categorias => _categorias;

  /// true somente após ao menos um carregamento bem-sucedido de categorias.
  /// Usado para evitar exibir cards hardcoded ("Geral", "Sem categoria")
  /// enquanto o servidor está offline.
  bool _categoriasCarregadas = false;
  bool get categoriasCarregadas => _categoriasCarregadas;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erro;
  String? get erro => _erro;

  // Filtros ativos
  String _busca = '';
  String? _categoriaFiltro;   // null = todos, '' = sem categoria
  String _statusFiltro = '';
  String _idFiltro = '';
  String _identificadorFiltro = '';
  String _medidaFiltro = '';
  String _espessuraFiltro = '';

  // ─── SSE ──────────────────────────────────────────────────────────────────
  bool _paginaAberta = false;
  bool _notificacoesConectadas = false;
  bool get notificacoesConectadas => _notificacoesConectadas;

  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  Timer? _reconnectTimer;
  Timer? _pollingTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // ─── Notificação para diálogos com busca local (fora do fluxo normal) ────
  /// Emite sempre que um material é criado/editado via SSE, independente de
  /// _paginaAberta. Diálogos com busca própria (ex: seleção de material em
  /// Entrada/Saída) escutam este stream pra se atualizarem enquanto estão
  /// abertos, sem precisar poluir/disparar o estado global de _materiais.
  final _materialAtualizadoController = StreamController<void>.broadcast();
  Stream<void> get materialAtualizadoStream =>
      _materialAtualizadoController.stream;

  // ─── Notificação de estoque crítico (banner flutuante) ────────────────────
  /// Preenchido quando o SSE recebe um evento 'material_critico' (disparado
  /// pelo backend apenas na transição para CRITICO). Consumido uma única vez
  /// pelo AppShell, no mesmo padrão do SolicitacaoMaterialProvider.
  MaterialCriticoNotificacao? _notificacaoCriticaPendente;
  MaterialCriticoNotificacao? get notificacaoCriticaPendente =>
      _notificacaoCriticaPendente;

  void consumirNotificacaoCriticaPendente() {
    _notificacaoCriticaPendente = null;
  }

  // ─── Navegação a partir do banner de crítico ───────────────────────────────
  /// Guardado quando o usuário toca no MaterialCriticoBanner: carrega os
  /// dados do material para que a EstoquePage, assim que ficar visível,
  /// abra automaticamente a categoria certa já com nome/identificador/
  /// medida/espessura preenchidos nos filtros.
  MaterialCriticoNotificacao? _filtroNavegacaoPendente;
  MaterialCriticoNotificacao? get filtroNavegacaoPendente =>
      _filtroNavegacaoPendente;

  void solicitarNavegacaoParaMaterial(MaterialCriticoNotificacao notificacao) {
    _filtroNavegacaoPendente = notificacao;
    notifyListeners();
  }

  void consumirFiltroNavegacaoPendente() {
    _filtroNavegacaoPendente = null;
  }

  // ─── Navegação a partir de um encaminhamento de material no chat ──────────
  /// Guardado quando o usuário toca no card de encaminhamento de um material
  /// "solto" do estoque (ver EncaminhamentoChatCard._abrirOrigem): carrega os
  /// dados do material para que a EstoquePage, assim que ficar visível, abra
  /// automaticamente a categoria certa já com nome/identificador/medida/
  /// espessura preenchidos nos filtros. Mesmo mecanismo de
  /// `_filtroNavegacaoPendente`, mas alimentado pelo chat em vez de SSE.
  FiltroMaterialChat? _filtroChatPendente;
  FiltroMaterialChat? get filtroChatPendente => _filtroChatPendente;

  void solicitarNavegacaoParaMaterialChat(FiltroMaterialChat filtro) {
    _filtroChatPendente = filtro;
    notifyListeners();
  }

  void consumirFiltroChatPendente() {
    _filtroChatPendente = null;
  }

  // ─── Navegação a partir do diálogo "Alertas de Estoque" ────────────────────
  /// Guardado quando o usuário clica em "Ir para Estoque" no diálogo aberto
  /// pelo sino de notificações: carrega apenas o status desejado (ex.:
  /// 'CRITICO') para que a EstoquePage, assim que ficar visível, abra
  /// automaticamente a tela "Geral" já com esse status ativo no filtro.
  String? _filtroStatusPendente;
  String? get filtroStatusPendente => _filtroStatusPendente;

  void definirFiltroStatusPendente(String status) {
    _filtroStatusPendente = status;
    notifyListeners();
  }

  void consumirFiltroStatusPendente() {
    _filtroStatusPendente = null;
  }

  Future<void> conectarNotificacoes() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _reconnectTimer?.cancel();
    _sseClient?.close();
    _sseClient = null;

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/api/materiais/notificacoes');
      debugPrint('🔔 [Materiais] Conectando ao SSE: $uri');

      final token = ApiClient.token;
      if (token == null) {
        debugPrint('⚠️ [Materiais] Token não disponível para SSE');
        _scheduleReconnect();
        return;
      }

      _sseClient = http.Client();

      final req = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache'
        ..headers['Connection'] = 'keep-alive';

      final streamedResp = await _sseClient!.send(req);

      if (streamedResp.statusCode != 200) {
        debugPrint('❌ [Materiais] SSE falhou com status ${streamedResp.statusCode}');
        _scheduleReconnect();
        return;
      }

      debugPrint('✅ [Materiais] SSE conectado com sucesso');
      _notificacoesConectadas = true;
      _reconnectAttempts = 0;
      notifyListeners();

      final stream = streamedResp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sseSub = stream.listen(
        _processarLinhaSSE,
        onError: (error) {
          debugPrint('❌ [Materiais] Erro no SSE: $error');
          _notificacoesConectadas = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('⚠️ [Materiais] SSE stream encerrado');
          _notificacoesConectadas = false;
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      _pollingTimer?.cancel();
      _pollingTimer = null;
    } catch (e) {
      debugPrint('❌ [Materiais] Erro ao conectar SSE: $e');
      _notificacoesConectadas = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _processarLinhaSSE(String linha) {
    if (linha.startsWith(':')) return;
    if (linha.trim().isEmpty) return;

    if (linha.startsWith('data:')) {
      final raw = linha.substring(5).trim();
      if (raw.isEmpty) return;

      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final tipo = data['tipo'] as String?;

        if (tipo == 'conectado') {
          debugPrint('✅ [Materiais] Confirmação de conexão recebida');
          return;
        }

        if (tipo == 'material_critico') {
          debugPrint('🔴 [Materiais] Estoque crítico: ${data['nome']}');
          _notificacaoCriticaPendente =
              MaterialCriticoNotificacao.fromJson(data);
          notifyListeners();
          return;
        }

        if (tipo == 'material_atualizado') {
          debugPrint('🔔 [Materiais] Atualização recebida: motivo=${data['motivo']}');
          // Notifica quem estiver escutando (ex: diálogo de Entrada/Saída
          // com busca própria), independente da página de catálogo estar
          // visível ou não.
          _materialAtualizadoController.add(null);
          if (_paginaAberta) {
            recarregar();
          }
        }
      } catch (e) {
        debugPrint('❌ [Materiais] Erro ao processar SSE: $e, linha: $linha');
      }
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('⚠️ [Materiais] Máximo de tentativas atingido. Usando polling.');
      _iniciarPolling();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    debugPrint('🔄 [Materiais] Reconectando SSE em ${delay.inSeconds}s (tentativa $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, conectarNotificacoes);
  }

  void _iniciarPolling() {
    _pollingTimer?.cancel();
    debugPrint('📊 [Materiais] Iniciando polling a cada 30s como fallback');

    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_paginaAberta) recarregar();
    });
  }

  /// Chamado pelo AppShell (mesmo esquema usado por Solicitações e Chat) —
  /// a página vive num StatefulShellBranch, então dispose() não é confiável
  /// pra saber se a tela realmente está visível.
  void definirPaginaVisivel(bool visivel) {
    if (visivel == _paginaAberta) return;
    _paginaAberta = visivel;
  }

  Future<void> resetarConexao() async {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;
    _notificacoesConectadas = false;
    _paginaAberta = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    _materialAtualizadoController.close();
    super.dispose();
  }

  Future<void> carregar({
    String busca = '',
    String? categoria,         // null = todos, '' = sem categoria
    String status = '',
    String id = '',
    String identificador = '',
    String medida = '',
    String espessura = '',
    bool? ativo,
  }) async {
    _busca = busca;
    _categoriaFiltro = categoria;
    _statusFiltro = status;
    _idFiltro = id;
    _identificadorFiltro = identificador;
    _medidaFiltro = medida;
    _espessuraFiltro = espessura;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _materiais = await _repo.listar(
        busca:        busca,
        categoria:    categoria,
        status:       status,
        id:           id,
        identificador: identificador,
        medida:       medida,
        espessura:    espessura,
        ativo:        ativo,
      );
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar estoque');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    await carregar(
      busca:        _busca,
      categoria:    _categoriaFiltro,
      status:       _statusFiltro,
      id:           _idFiltro,
      identificador: _identificadorFiltro,
      medida:       _medidaFiltro,
      espessura:    _espessuraFiltro,
    );
  }

  Future<void> carregarCategorias() async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _categorias = await _repo.listarCategorias();
      _categoriasCarregadas = true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar categorias');
      // _categoriasCarregadas permanece false enquanto nunca houver sucesso
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<MaterialModel?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'carregar material');
      notifyListeners();
      return null;
    }
  }

  Future<List<MaterialModel>> buscarParaMovimentacao({
    String busca = '',
    String? categoria,
    String id = '',
    String identificador = '',
    String medida = '',
    String espessura = '',
  }) async {
    try {
      return await _repo.listarParaMovimentacao(
        busca:         busca.isEmpty         ? null : busca,
        id:            id.isEmpty            ? null : id,
        identificador: identificador.isEmpty ? null : identificador,
        medida:        medida.isEmpty        ? null : medida,
        espessura:     espessura.isEmpty     ? null : espessura,
        categoria:     categoria,
      );
    } catch (_) {
      return [];
    }
  }

  Future<bool> criar(Map<String, dynamic> dados) async {
    try {
      await _repo.criar(dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'cadastrar material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> atualizar(int id, Map<String, dynamic> dados) async {
    try {
      await _repo.atualizar(id, dados);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> desativar(int id) async {
    try {
      await _repo.desativar(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'desativar material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmarEstoque(int id) async {
    try {
      await _repo.confirmarEstoque(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'confirmar estoque');
      notifyListeners();
      return false;
    }
  }

  Future<bool> excluir(int id) async {
    try {
      await _repo.excluir(id);
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'excluir material');
      notifyListeners();
      return false;
    }
  }

  Future<bool> reativar(int id) async {
    try {
      await _repo.reativar(id);
      await carregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'reativar material');
      notifyListeners();
      return false;
    }
  }

  /// Busca rápida para autocomplete — retorna até [limite] materiais sem
  /// alterar o estado da lista principal nem disparar notifyListeners.
  Future<List<MaterialModel>> buscarSugestoes(String busca, {int limite = 10, bool apenasAtivos = false}) async {
    try {
      final lista = await _repo.listar(busca: busca, ativo: apenasAtivos ? true : null);
      return lista.take(limite).toList();
    } catch (_) {
      return [];
    }
  }

  /// Busca histórico de custos pagos via OC para o material informado.
  /// Retorna lista vazia em caso de erro (não expõe _erro para não interferir
  /// com o estado geral da página de estoque).
  Future<List<HistoricoPrecoModel>> listarHistoricoPrecos(int materialId) async {
    try {
      return await _repo.listarHistoricoPrecos(materialId);
    } catch (_) {
      return [];
    }
  }

  /// Atualiza diretamente o custo de última compra do material sem OC.
  Future<bool> atualizarCustoManual(
    int id, {
    double? ultimoValorPago,
    double? ultimoValorPagoM2,
  }) async {
    try {
      await _repo.atualizarCustoManual(
        id,
        ultimoValorPago:   ultimoValorPago,
        ultimoValorPagoM2: ultimoValorPagoM2,
      );
      await recarregar();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e, acao: 'atualizar custo');
      notifyListeners();
      return false;
    }
  }
}