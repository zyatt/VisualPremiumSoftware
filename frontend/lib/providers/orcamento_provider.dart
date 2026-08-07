import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/material_model.dart';
import '../repositories/orcamento_repository.dart';
import '../utils/api_client.dart';

// ─── Data classes ─────────────────────────────────────────────────────────────

class PrecoFornecedorData {
  double? preco;
  String fornecedorNome;
  /// Preço por m² deste material para este fornecedor. Mantido em sincronia
  /// com [preco] pela UI do editor (ver `_DialogEditarMaterial`): preencher
  /// um recalcula o outro a partir da área do material (largura x
  /// comprimento para itens em UNIDADE, ou largura x qtdUnidade para os
  /// demais). Guardado à parte para não recalcular a área toda vez que o
  /// valor precisar ser exibido.
  double? precoMetroQuadrado;
  /// Observação de disponibilidade digitada pelo usuário para este
  /// material × fornecedor (ex: "Em falta", "Prazo 5 dias").
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
  /// Largura do material (m) — usada para compor a dimensão "LxC" exibida
  /// junto às informações do item no orçamento.
  final double? materialLargura;
  /// Comprimento do material (m) — usada para compor a dimensão "LxC"
  /// exibida junto às informações do item no orçamento.
  final double? materialComprimento;
  /// Estoque mínimo do material — apenas para exibição na tabela do orçamento.
  /// Não é editável aqui; é configurado no módulo de estoque.
  final double? estoqueMinimo;
  double quantidade;
  /// Quantidade da unidade de medida por embalagem/peça (ex: 50 M/L por
  /// lona, 18000 ML por lata de thinner) — mesmo conceito de `qtdUnidade`
  /// da Ordem de Compra. Só é relevante quando [materialUnidade] não é
  /// "UNIDADE" (ver [precisaQtdUnidade]). É repassado para a OC gerada a
  /// partir deste orçamento.
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

  /// Indica se este material precisa do campo "qtd/unidade" (todo material
  /// cuja unidade não é "UNIDADE" — mesma regra usada na Ordem de Compra).
  bool get precisaQtdUnidade {
    final u = (materialUnidade ?? '').toUpperCase().trim();
    return u.isNotEmpty && u != 'UNIDADE';
  }

  /// Rótulo do campo, ex: "M/L por unidade", "M² por unidade".
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

  /// Retorna a dimensão formatada como "3X5M" (comprimento X largura) quando
  /// largura e comprimento estão cadastrados. Se o material já tiver
  /// `medida` preenchida, a medida tem prioridade e a dimensão não é usada
  /// (evita redundância na exibição).
  String? get materialDimensaoFormatada {
    if (materialMedida != null && materialMedida!.isNotEmpty) return null;
    final l = materialLargura;
    final c = materialComprimento;
    if (l == null || c == null || l <= 0 || c <= 0) return null;
    String fmt(double v) =>
        v == v.truncateToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
    return '${fmt(c)}x${fmt(l)}m';
  }

  /// Área em m² de uma unidade deste material, usada para converter entre
  /// preço unitário e preço por m² (ver `_DialogEditarMaterial`):
  /// - Para materiais em "UNIDADE" (ex.: chapas): largura x comprimento do
  ///   próprio material (ex.: uma chapa 2x1m tem 2m² por unidade).
  /// - Para os demais (M/L, M², KG etc.): esses materiais não usam
  ///   `materialComprimento` — só têm largura fixa (ex.: uma lona de 1,4m
  ///   de largura). O "comprimento" de cada unidade/rolo vendido é o que o
  ///   usuário informa no campo "Qtd por Unidade" (`qtdUnidade`, ex.: 50m
  ///   por rolo), então a área por unidade é largura x qtdUnidade.
  /// Retorna null quando não há dados suficientes para calcular (largura
  /// ausente, ou comprimento/qtdUnidade ausente conforme o caso).
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

  /// Igual a [toJson], mas sem `itemId`. Usado apenas para calcular a
  /// assinatura de "houve alteração" (ver `OrcamentoTab._calcularAssinatura`).
  /// `itemId` é um UUID gerado localmente (ver construtor) e o backend nunca
  /// o devolve — toda vez que os itens são reconstruídos a partir de uma
  /// resposta do servidor (SSE, auto-sync, reabertura), cada item ganha um
  /// UUID novo mesmo com os mesmos dados de negócio. Se `itemId` entrasse na
  /// assinatura, ela nunca mais bateria com a assinatura salva após o
  /// primeiro reload remoto, e `houveAlteracao` ficaria travado em `true`
  /// para sempre — foi exatamente isso que fez o editor achar (por engano)
  /// que havia "alterações locais não salvas" e recusar aplicar atualizações
  /// vindas de outros usuários via SSE, mesmo em uma aba que só visualiza.
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

// ─── Aba ativa (orçamento em edição) ──────────────────────────────────────────

class OrcamentoTab {
  final String id;
  String titulo;
  List<ItemOrcamentoData> itens;

  /// ID do orçamento no servidor (preenchido ao criar ou reabrir do servidor).
  /// Enquanto for null, o orçamento ainda não existe no banco.
  int? servidorId;

  /// IDs de fornecedores ocultados da visualização (matriz, totais, melhor
  /// preço e PDF) deste orçamento. Persistido no servidor junto com o
  /// orçamento, então é visto por qualquer usuário que abrir o mesmo
  /// orçamento — não é uma preferência só local. Não afeta os dados em si:
  /// o fornecedor, os itens e os preços continuam intactos.
  List<int> fornecedoresOcultos;

  /// Flags de estado da aba (mantidas aqui para sobreviver a rebuilds da page).
  bool aguardandoAprovacao;
  bool jaFinalizado;
  bool modoGerarOC;
  /// true enquanto o usuário está editando (mesmo sem itens ainda).
  /// Garante que o editor fique visível logo após clicar em "Novo Orçamento".
  bool modoEdicao;

  /// true quando este orçamento pertence a outro usuário e está sendo
  /// editado por ele agora — a trava de edição (POST /travar) falhou ao
  /// abrir esta aba pela seção "Orçamentos em Aberto", então o editor deve
  /// ficar em modo somente-leitura (sem salvar/enviar itens) até a pessoa
  /// terminar. Nunca persistido: é sempre recalculado ao reabrir a aba.
  bool somenteLeitura;

  /// Modo de precificação usado no comparativo de preços e ao gerar a OC:
  /// 'UNIDADE' — o preço do fornecedor é por unidade/peça (padrão; total =
  /// preço × quantidade), ou 'METRO_LINEAR' — o preço do fornecedor já é
  /// por m/l (ou pela unidade de medida do material; total = preço ×
  /// Quantidade por Unidade × quantidade). Só afeta a visualização/
  /// conversão; os preços cadastrados não são alterados.
  String modoPrecificacao;

  /// ID do usuário que criou este orçamento no servidor. Preenchido ao
  /// carregar/reabrir do servidor (ver `setCriadorIdTab` chamado pela page
  /// em `_reabrirOrcamento`) ou, para uma aba nova, implicitamente é quem
  /// está criando agora — ver `_criarOrcamentoNoServidorImpl`. Usado para
  /// decidir se o usuário atual pode excluir o orçamento (só o criador
  /// pode): ver `OrcamentoProvider.souCriadorDaAbaAtiva`.
  int? criadorId;

  /// true quando esta aba foi criada automaticamente pelo tour do robô
  /// assistente "Como criar um orçamento" (via `adicionarAba(criadaPeloTour:
  /// true)` em `_abrirEditorTour`), e não por um clique real do usuário em
  /// "Novo Orçamento". Existe para impedir que essa aba de demonstração,
  /// com o "MATERIAL EXEMPLO" fictício, seja PERSISTIDA em SharedPreferences
  /// — sem isso, fechar o app (ou dar restart) no meio do tour, antes do
  /// `aoEncerrar`/"Concluir" ter a chance de removê-la, deixava a aba
  /// gravada em disco e ela reaparecia sozinha na próxima abertura do app,
  /// como se fosse um orçamento real esquecido. Ver `_salvarAbas` (nunca
  /// grava abas com esta flag) e `_carregar` (descarta qualquer uma que já
  /// tenha sido salva por engano antes desta correção).
  final bool criadaPeloTour;

  /// "Fotografia" (assinatura) do conteúdo da aba no momento em que ela foi
  /// carregada/sincronizada com o servidor pela última vez (ver
  /// `OrcamentoProvider.marcarComoSalvo`). Comparada com o conteúdo atual em
  /// `houveAlteracao` para saber se existem mudanças locais não persistidas.
  /// Nunca serializada: é recalculada a cada hidratação a partir do servidor.
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

  /// Registra o estado atual como "salvo" — chamado logo após a aba ser
  /// hidratada a partir do servidor (abertura/reabertura do editor) ou logo
  /// após um save bem-sucedido. A partir daqui, `houveAlteracao` volta a
  /// `false` até o usuário mexer em algo.
  void marcarComoSalvo() {
    _assinaturaSalva = _calcularAssinatura();
  }

  /// true se o conteúdo atual da aba diverge do que foi registrado em
  /// `marcarComoSalvo`. Se `marcarComoSalvo` nunca foi chamado (aba nova,
  /// nunca sincronizada), considera que não há "alteração" a perder — é só
  /// um rascunho vazio/local que ainda será criado.
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
        // 'criadaPeloTour' NÃO é serializado de propósito: uma aba do tour
        // nunca deveria chegar a ser persistida (ver _salvarAbas), então
        // este campo nem precisa sobreviver a um round-trip JSON. Se um
        // registro antigo (de antes desta correção) for lido de volta por
        // `fromJson`, ele vem com `criadaPeloTour: false` (valor padrão) —
        // o que é seguro, pois essas abas antigas já não têm mais tour
        // algum rodando que dependa da flag; elas só precisam ser abas
        // normais a partir de agora.
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

// ─── Provider ─────────────────────────────────
// NOTA: o histórico de orçamentos (salvos/cancelados) foi movido para o
// servidor. O provider agora só gerencia a aba em edição (rascunho local).

// ─── Orçamento em aberto (seção "Orçamentos em Aberto") ───────────────────
// Retrato leve de um orçamento com status ABERTO no servidor, usado para
// montar os cards agrupados por usuário criador. Não confundir com
// [OrcamentoTab], que é o estado local (rascunho) de uma aba do editor.
class OrcamentoAbertoInfo {
  final int id;
  final String titulo;
  final int? criadorId;
  final String? criadorNome;
  final int quantidadeItens;
  final DateTime atualizadoEm;
  /// Id do usuário que está com este orçamento aberto no editor agora
  /// (null = ninguém editando no momento).
  final int? travaUsuarioId;
  final String? travaUsuarioNome;

  OrcamentoAbertoInfo({
    required this.id,
    required this.titulo,
    this.criadorId,
    this.criadorNome,
    required this.quantidadeItens,
    required this.atualizadoEm,
    this.travaUsuarioId,
    this.travaUsuarioNome,
  });

  bool get emEdicaoPorAlguem => travaUsuarioId != null;

  factory OrcamentoAbertoInfo.fromJson(Map<String, dynamic> j) => OrcamentoAbertoInfo(
        id: j['id'] as int,
        titulo: j['titulo'] as String? ?? 'Orçamento',
        criadorId: j['criadorId'] as int? ?? (j['criador'] as Map?)?['id'] as int?,
        criadorNome: (j['criador'] as Map?)?['nome'] as String?,
        quantidadeItens: (j['itens'] as List? ?? []).length,
        atualizadoEm: DateTime.tryParse(j['atualizadoEm']?.toString() ?? '') ?? DateTime.now(),
        travaUsuarioId: j['travaUsuarioId'] as int? ?? (j['travaUsuario'] as Map?)?['id'] as int?,
        travaUsuarioNome: (j['travaUsuario'] as Map?)?['nome'] as String?,
      );
}

class OrcamentoProvider extends ChangeNotifier {
  // Chaves agora dependem do usuário — sem prefixo, sem dados de outro usuário
  static String _kAbas(int userId)     => 'orcamento_abas_$userId';
  static String _kAbaAtiva(int userId) => 'orcamento_aba_ativa_$userId';

  final _uuid = const Uuid();
  final _repo = OrcamentoRepository();
  int? _userId; // usuário atual
  String? _userNome; // nome do usuário atual (ver trocarUsuario)

  /// Nome de exibição do usuário logado, se conhecido. Usado como fallback
  /// nos cards de "Orçamentos em Aberto" quando o card é do PRÓPRIO usuário
  /// e o campo `criadorNome` vindo do servidor ainda não chegou (ex: logo
  /// após criar o orçamento, antes do primeiro refresh completo) — em vez
  /// de mostrar "Usuário #<id>" para si mesmo.
  String? get usuarioAtualNome => _userNome;
  /// Getter público do id do usuário logado, usado pelo editor para setar
  /// `criadorId` ao persistir um orçamento recém-criado fora do fluxo normal
  /// de `_criarOrcamentoNoServidorImpl` (ex.: auto-save silencioso ao sair).
  int? get usuarioAtualId => _userId;

  // ─── Sinalização de edição local para auto-save em tempo real ────────────
  // Incrementado sempre que o usuário faz uma edição local nos itens da aba
  // ativa (quantidade, preço, fornecedor, adicionar/remover material) que
  // ainda não foi persistida no servidor. O editor (orcamento_editor_page)
  // observa este contador para agendar um auto-save debounced — sem isso,
  // outras pessoas vendo o mesmo orçamento só recebiam as mudanças quando
  // quem editava saía da tela. NÃO é incrementado por `substituirItensTab`
  // (usado para aplicar mudanças que VIERAM de outro usuário via SSE) nem
  // por `adicionarItensEmLote` (carregamento inicial ao reabrir uma aba) —
  // só edições que o próprio usuário fez agora, que precisam subir.
  int _edicaoLocalTrigger = 0;
  int get edicaoLocalTrigger => _edicaoLocalTrigger;
  void _sinalizarEdicaoLocal() => _edicaoLocalTrigger++;

  /// Busca os dados ATUAIS de um orçamento no servidor (status, título,
  /// quantidade de itens etc.). Usado pelo EncaminhamentoChatCard para
  /// exibir o status em tempo real em vez do retrato congelado no momento
  /// do encaminhamento — ver `_mesclarComOrcamentoAtual` naquele arquivo.
  Future<Map<String, dynamic>?> buscarPorId(int id) async {
    try {
      return await _repo.buscarPorId(id);
    } catch (_) {
      return null;
    }
  }

  final List<OrcamentoTab> _abas = [];
  List<OrcamentoTab> get abas => List.unmodifiable(_abas);

  // ─── Seção "Orçamentos em Aberto" (compartilhados entre usuários) ─────────
  // Lista bruta vinda do servidor (todos com status ABERTO, de qualquer
  // usuário). Atualizada via GET inicial + eventos SSE em tempo real.
  List<OrcamentoAbertoInfo> _orcamentosAbertos = [];
  bool _carregandoOrcamentosAbertos = false;
  String? _erroOrcamentosAbertos;

  List<OrcamentoAbertoInfo> get orcamentosAbertos => List.unmodifiable(_orcamentosAbertos);
  bool get carregandoOrcamentosAbertos => _carregandoOrcamentosAbertos;
  String? get erroOrcamentosAbertos => _erroOrcamentosAbertos;

  /// Agrupa [orcamentosAbertos] por criador, na ordem de última atualização
  /// (usuário com o orçamento mais recentemente alterado aparece primeiro).
  /// Usuários sem nenhum orçamento em aberto simplesmente não aparecem —
  /// não é uma lista de todos os usuários do sistema.
  List<MapEntry<int, List<OrcamentoAbertoInfo>>> get orcamentosAbertosPorUsuario {
    final Map<int, List<OrcamentoAbertoInfo>> agrupado = {};
    for (final o in _orcamentosAbertos) {
      if (o.criadorId == null) continue; // sem criador identificável, não mostra card
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

  // ─── SSE: mantém a lista de orçamentos em aberto sincronizada em tempo
  // real entre todos os usuários conectados. Mesmo padrão de conexão do
  // ChatProvider (ver chat_provider.dart), com reconexão automática.
  StreamSubscription<String>? _sseSub;
  String _sseBuffer = '';

  void _conectarSSE() {
    _sseSub?.cancel();
    final token = ApiClient.token;
    if (token == null) return;

    final uri = Uri.parse('${ApiClient.baseUrl}/api/orcamentos/stream');
    final client = http.Client();

    final req = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';

    client.send(req).then((streamedResp) {
      final stream = streamedResp.stream.transform(utf8.decoder).transform(const LineSplitter());
      _sseSub = stream.listen(
        _processarLinhaSSE,
        onError: (e) {
          debugPrint('OrcamentoProvider SSE erro: $e');
          Future.delayed(const Duration(seconds: 5), _conectarSSE);
        },
        onDone: () {
          Future.delayed(const Duration(seconds: 5), _conectarSSE);
        },
      );
    }).catchError((e) {
      debugPrint('OrcamentoProvider SSE connect erro: $e');
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
          // Item mudou (qtd/preço/fornecedor/título etc): a contagem de
          // itens e o "atualizado em" exibidos no card podem ter mudado —
          // refaz o GET leve para esse único orçamento ficar consistente
          // sem precisar recarregar a lista inteira.
          final id = evento['orcamentoId'] as int?;
          if (id != null) _atualizarUmOrcamentoAberto(id);
          // Também notifica quem está no editor deste orçamento agora, para
          // puxar as mudanças do outro usuário em tempo real — EXCETO
          // quando o próprio evento foi gerado por este usuário (eco do
          // seu próprio auto-save debounced, ver
          // OrcamentoEditorPage._onProviderTempoRealChanged). Sem esse
          // filtro, o autor recebia de volta o próprio salvamento como se
          // fosse "mudança externa" e recarregava a aba a partir do
          // servidor, podendo sobrescrever uma edição local seguinte feita
          // enquanto o auto-save anterior ainda estava em voo.
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
      // Linha malformada/incompleta — ignora, o próximo "data:" corrige.
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
        travaUsuarioId: travaUsuarioId,
        travaUsuarioNome: travaUsuarioNome,
      );
      notifyListeners();
    }
    // Se o orçamento travado/destravado for o que está aberto no editor
    // agora, avisa quem está editando (ver getter/listener em
    // OrcamentoEditorPage para reagir a isso, ex: mostrar aviso ou travar UI).
    //
    // IMPORTANTE: quando `travaUsuarioId == _userId`, a trava é do PRÓPRIO
    // usuário (ex: acabou de criar o orçamento e travou para si mesmo em
    // _criarOrcamentoNoServidorImpl, ou o heartbeat renovou). Esse caso não
    // deve disparar o aviso de "trava externa" — mesmo com o fix em
    // OrcamentoEditorPage._onProviderTempoRealChanged (que já ignora esse
    // cenário via _idsComTravaMinha), filtrar aqui na origem evita qualquer
    // corrida residual e deixa a intenção explícita: só é "trava externa"
    // se pertencer de fato a outra pessoa.
    final travaEhDeOutroUsuario = travaUsuarioId != null && travaUsuarioId != _userId;
    final destravouEAntesEraDeOutro = travaUsuarioId == null; // destravamento sempre é relevante notificar
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
      if (data['status'] != 'ABERTO') return; // já saiu do pool, outro evento cuida disso
      final info = OrcamentoAbertoInfo.fromJson(data);
      final idx = _orcamentosAbertos.indexWhere((o) => o.id == orcamentoId);
      if (idx != -1) {
        _orcamentosAbertos[idx] = info;
      } else {
        _orcamentosAbertos.insert(0, info);
      }
      notifyListeners();
    } catch (_) {}
  }

  // ─── Notificação ao editor aberto de que o orçamento mudou por fora ───────
  // O OrcamentoEditorPage escuta este provider e, ao ver o contador mudar
  // para um servidorId igual ao da aba que está mostrando na tela, recarrega
  // os dados do servidor (mesmo fluxo já usado pelo botão "Atualizar"/
  // auto-sync de 30s, só que disparado na hora em vez de esperar o timer).
  int _mudancaExternaTrigger = 0;
  int? _mudancaExternaOrcamentoId;
  int get mudancaExternaTrigger => _mudancaExternaTrigger;
  int? get mudancaExternaOrcamentoId => _mudancaExternaOrcamentoId;

  void _emitirMudancaExterna(int orcamentoId) {
    _mudancaExternaOrcamentoId = orcamentoId;
    _mudancaExternaTrigger++;
    notifyListeners();
  }

  // Mesmo mecanismo para avisos de trava (outro usuário assumiu ou liberou
  // a edição de um orçamento que está aberto localmente).
  int _travaExternaTrigger = 0;
  int? _travaExternaOrcamentoId;
  String? _travaExternaUsuarioNome;
  int get travaExternaTrigger => _travaExternaTrigger;
  int? get travaExternaOrcamentoId => _travaExternaOrcamentoId;
  String? get travaExternaUsuarioNome => _travaExternaUsuarioNome;

  /// Chamado no login/restauração de sessão (mesmo ponto onde o ChatProvider
  /// é inicializado — ver usuario_provider.dart) para abrir a conexão SSE e
  /// carregar a lista inicial de orçamentos em aberto.
  Future<void> inicializarTempoReal() async {
    await carregarOrcamentosAbertos();
    _conectarSSE();
  }

  void _pararTempoReal() {
    _sseSub?.cancel();
    _sseSub = null;
    _orcamentosAbertos = [];
  }

  int _abaAtiva = 0;
  int get abaAtiva => _abaAtiva;

  OrcamentoTab? get tabAtual => _abas.isEmpty ? null : _abas[_abaAtiva];

  bool _carregado = false;
  bool get carregado => _carregado;

  // ─── Abertura pendente vinda de um encaminhamento no chat ─────────────────
  /// Guardado quando o usuário toca no card de um orçamento encaminhado no
  /// chat — ver EncaminhamentoChatCard._abrirOrigem. A OrcamentoPage, assim
  /// que ficar visível, consome este id e abre o orçamento no editor
  /// automaticamente (mesmo fluxo de _reabrirOrcamento).
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

  // ── Chamado pelo main.dart ao logar/deslogar ──────────────────────────────
  // [userNome] é opcional para não quebrar chamadas existentes de
  // trocarUsuario(userId) já espalhadas pelo app; quando informado, permite
  // que a UI mostre o próprio nome do usuário logado em vez de um fallback
  // genérico como "Usuário #<id>" nos cards de "Orçamentos em Aberto" (ver
  // usuarioAtualNome / orcamento_page.dart).
  Future<void> trocarUsuario(int? userId, [String? userNome]) async {
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

    if (userId != null) {
      await _carregar();
      await inicializarTempoReal();
    } else {
      // Deslogou: sem abas, painel de aprovação é a tela base
      _carregado = true;
      notifyListeners();
    }
  }

  // ── Persistência ─────────────────────────────────────────────────────────
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
      // Filtro defensivo: remove qualquer aba fictícia do tour do robô
      // assistente que já tenha sido salva em disco ANTES desta correção
      // (quando `_salvarAbas` ainda não excluía abas com `criadaPeloTour`).
      // Como o campo `criadaPeloTour` nunca é serializado (ver toJson), não
      // dá pra identificar essas abas antigas por ele — em vez disso,
      // reconhecemos o padrão único da aba de demonstração do tour: sem
      // servidorId (nunca foi salva de verdade de fato) e cujos itens são
      // exatamente os nomes fixos usados só pelo tour — "MATERIAL EXEMPLO"
      // (1º item) e, desde que o tour passou a mostrar dois materiais,
      // opcionalmente "ADESIVO" (2º item, usado só para ilustrar o campo
      // "Quantidade por Unidade") — ver orcamento_editor_page.dart. Um
      // orçamento real do usuário nunca cai nesse padrão exato.
      const nomesFicticiosDoTour = {'MATERIAL EXEMPLO', 'ADESIVO'};
      _abas.removeWhere((a) =>
          a.servidorId == null &&
          a.itens.isNotEmpty &&
          a.itens.length <= 2 &&
          a.itens.every((i) => nomesFicticiosDoTour.contains(i.materialNome)));
      _abaAtiva = prefs.getInt(_kAbaAtiva(_userId!)) ?? 0;
      if (_abaAtiva >= _abas.length) _abaAtiva = 0;
    } catch (_) {}

    // Não força aba inicial — o painel de aprovação é a tela base quando não há abas.
    _carregado = true;
    notifyListeners();
  }

  /// Wrapper público de `_salvarAbas`, usado pelo editor após o auto-save
  /// silencioso (ver `_salvarSilenciosamenteAoSair`) para persistir no
  /// SharedPreferences o `servidorId`/`criadorId` recém-atribuídos à aba,
  /// além de disparar `notifyListeners()` para refletir o estado em telas
  /// que observam o provider (ex.: seção "Orçamentos em Aberto").
  Future<void> salvarAbasAgora() async {
    await _salvarAbas();
    notifyListeners();
  }

  Future<void> _salvarAbas() async {
    if (_userId == null) return; // sem usuário, não persiste
    try {
      final prefs = await SharedPreferences.getInstance();
      // Filtra abas criadas pelo tour do robô assistente ANTES de
      // persistir — essa aba de demonstração ("MATERIAL EXEMPLO") nunca
      // deve ir para o disco. Sem este filtro, fechar o app (ou dar
      // restart) no meio do tour salvava a aba fictícia junto com as
      // reais, e ela reaparecia sozinha na próxima abertura do app,
      // mesmo o tour nunca tendo sido concluído.
      final abasPersistiveis = _abas.where((a) => !a.criadaPeloTour).toList();
      await prefs.setString(
        _kAbas(_userId!),
        jsonEncode(abasPersistiveis.map((a) => a.toJson()).toList()),
      );
      // O índice salvo precisa se referir à lista JÁ FILTRADA (sem abas do
      // tour), não à lista completa em memória — senão, se houver uma aba
      // do tour antes da aba ativa real, o índice salvo ficaria deslocado
      // e, ao restaurar, abriria a aba errada (ou nenhuma, se ficasse fora
      // dos limites).
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
  // ── Abas ──────────────────────────────────────

  /// Cria a aba local E, em paralelo, já cria o orçamento no servidor (POST
  /// /orcamentos) — exceto para a aba fictícia do tour do robô assistente,
  /// que nunca deve tocar o backend. Isso é o que faz o orçamento aparecer
  /// na seção "Orçamentos em Aberto" (e para outros usuários, em tempo
  /// real via SSE) desde o momento em que a guia é aberta, e não só quando
  /// o usuário clica em "Salvar" — antes disso ele existia só localmente
  /// (SharedPreferences), invisível para o backend e para outros usuários.
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

  /// Futures de criação em andamento no servidor, uma por aba (chave =
  /// OrcamentoTab.id local). Permite que quem for salvar/enviar manualmente
  /// espere o POST inicial (disparado por _novaAba) terminar antes de
  /// decidir se deve criar ou atualizar — sem isso, um clique muito rápido
  /// em "Salvar" logo após abrir a aba poderia disparar um SEGUNDO POST
  /// /orcamentos (servidorId ainda nulo nesse instante) e duplicar o
  /// orçamento no servidor.
  final Map<String, Future<void>> _criacoesEmAndamento = {};

  /// Espera a criação inicial no servidor terminar, se houver uma em
  /// andamento para a aba ativa. Chamado pelo editor antes de salvar/
  /// enviar para aprovação/gerar OC, para nunca correr com _novaAba.
  Future<void> aguardarCriacaoInicial() async {
    if (tabAtual == null) return;
    final future = _criacoesEmAndamento[tabAtual!.id];
    if (future != null) await future;
  }

  /// Notificado após o orçamento ser criado no servidor E travado com
  /// sucesso para o próprio criador (ver _criarOrcamentoNoServidorImpl).
  /// O OrcamentoEditorPage escuta isso para registrar o id em
  /// `_idsComTravaMinha` mesmo quando a criação aconteceu DEPOIS que o
  /// editor já estava montado (aba criada pelo botão "Nova guia" dentro do
  /// próprio editor, por exemplo) — sem isso, o heartbeat/dispose não
  /// saberiam que devem renovar/liberar essa trava específica.
  int _servidorIdTravadoTrigger = 0;
  int? _servidorIdTravadoRecente;
  int get servidorIdTravadoTrigger => _servidorIdTravadoTrigger;
  int? get servidorIdTravadoRecente => _servidorIdTravadoRecente;

  /// Cria o orçamento vazio no servidor para uma aba recém-aberta, preenche
  /// `servidorId` assim que a resposta chega e já trava a edição para o
  /// próprio criador (afinal, é ele quem está com a aba aberta agora).
  /// Falha aqui não bloqueia o usuário — ele continua podendo editar
  /// localmente e o orçamento é criado de verdade no primeiro "Salvar"/
  /// "Enviar para aprovação" manual, como já acontecia antes desta mudança
  /// (fallback via `aguardarCriacaoInicial` + branch `servidorId == null`
  /// no editor).
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
      // A aba pode ter sido fechada/renomeada/removida enquanto o POST
      // estava em andamento — só aplica o servidorId se ela ainda existir.
      final aindaExiste = _abas.any((a) => a.id == tab.id);
      if (!aindaExiste) {
        // Aba fechada antes do POST retornar: cancela o orçamento recém
        // criado no servidor para não deixar um "Em Aberto" fantasma sem
        // dono visível na UI.
        try {
          await _repo.cancelar(id);
        } catch (_) {}
        return;
      }
      tab.servidorId = id;
      tab.criadorId = _userId; // quem cria é sempre o dono
      _salvarAbas();
      notifyListeners();

      // Trava a edição para o próprio criador. Normalmente não deveria
      // falhar (o orçamento acabou de ser criado, ninguém mais pode ter a
      // trava ainda), mas se falhar por qualquer motivo o usuário
      // simplesmente segue editando localmente sem trava — o heartbeat do
      // editor tentará de novo no próximo ciclo de 30s.
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

  /// [criadaPeloTour] deve ser `true` apenas quando chamado pelo tour do
  /// robô assistente (`_abrirEditorTour` em orcamento_page.dart), para que
  /// a aba de demonstração criada não seja persistida — ver `_salvarAbas`.
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

  /// Define a lista completa de fornecedores ocultos da aba ativa (usado ao
  /// carregar/recarregar um orçamento do servidor, que é a fonte da verdade).
  void setFornecedoresOcultosTab(List<int> ids) {
    if (tabAtual == null) return;
    tabAtual!.fornecedoresOcultos = List.of(ids);
    _salvarAbas();
    notifyListeners();
  }

  /// Oculta ou reexibe um fornecedor na aba ativa (apenas o estado local —
  /// a chamada ao servidor para persistir é feita pela page/editor, que então
  /// deve atualizar o provider com o resultado confirmado).
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

  /// Atualiza as flags de estado da aba ativa.
  /// Chamado pela page após operações no servidor (salvar, aprovar, reabrir…).
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

  // ── Itens da aba ativa ────────────────────────────────────────────────────────

  void adicionarItem(ItemOrcamentoData item) {
    if (tabAtual == null) return;

    // Deduplica itens adicionados manualmente (sem itemId pré-existente),
    // usando materialId como chave.
    // Itens restaurados do servidor já chegam com itemId próprio e NÃO devem
    // ser colapsados — cada combinação (material + fornecedor) é uma linha distinta.
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

  /// Substitui TODOS os itens da aba ativa pelos [itens] informados,
  /// preservando o restante do estado da aba (servidorId, título, flags).
  /// Usado quando outro usuário altera o mesmo orçamento em tempo real
  /// (ver OrcamentoEditorPage._recarregarItensDoServidor via evento SSE) —
  /// diferente de [adicionarItensEmLote], que cria uma aba nova.
  void substituirItensTab(List<ItemOrcamentoData> itens) {
    if (tabAtual == null) return;
    tabAtual!.itens
      ..clear()
      ..addAll(itens);
    _salvarAbas();
    notifyListeners();
  }

  /// Cria uma nova aba e adiciona todos os [itens] de uma vez.
  /// Os itens já chegam agrupados por material (cada ItemOrcamentoData contém
  /// o mapa de precos por fornecedor), portanto NÃO há deduplicação por
  /// materialId aqui — cada item da lista é distinto por itemId.
  int adicionarItensEmLote(String tituloAba, List<ItemOrcamentoData> itens) {
    _abas.add(OrcamentoTab(
      id: _uuid.v4(),
      titulo: tituloAba,
      itens: List.of(itens), // cópia direta, sem deduplicação
    ));
    _abaAtiva = _abas.length - 1;
    _salvarAbas();
    notifyListeners();
    return _abaAtiva;
  }

  /// Atualiza campos "somente leitura" vindos do material (estoque mínimo,
  /// dimensões, medida/espessura/identificador/status) nos itens da aba
  /// ativa, usando a lista atual de materiais fornecida (ex: do
  /// MaterialProvider). Não altera quantidade, preços ou fornecedor
  /// selecionado. Usado ao sincronizar/atualizar um orçamento já existente,
  /// já que esses dados podem ter mudado no módulo de estoque desde que o
  /// item foi adicionado ao orçamento.
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

  /// Define o modo de precificação da aba atual ('UNIDADE' ou
  /// 'METRO_LINEAR'). Usado pelo botão "Orçar por" no comparativo de preços.
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

    // Quando qtdUnidade muda (ex.: usuário editou "Quantidade por Unidade"
    // na tabela) e o item ainda não recebeu um novo mapa de `precos`
    // explícito, a área m² por unidade muda junto — e qualquer preço
    // unitário que havia sido calculado a partir de um preço m² salvo fica
    // desatualizado em relação à nova área. Recalculamos aqui o `preco` de
    // cada fornecedor a partir do `precoMetroQuadrado` já salvo (que
    // continua sendo o valor "fonte da verdade" nesse fluxo) x a nova
    // área, para que preço e preço/m² nunca fiquem inconsistentes entre si
    // mesmo quando a mudança não veio do diálogo "Editar Material".
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

  // ── Fechar aba após salvar/cancelar ───────────────────────────────────────────
  // Chamado pela page após confirmar a operação no servidor.

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

  /// Define o id do usuário que criou a aba ativa (vindo do servidor ao
  /// carregar/reabrir um orçamento existente). Usado para decidir se o
  /// usuário logado pode excluir o orçamento — ver `souCriadorDaAbaAtiva`.
  void setCriadorIdTab(int? criadorId) {
    if (tabAtual == null) return;
    tabAtual!.criadorId = criadorId;
    _salvarAbas();
    notifyListeners();
  }

  /// true se o usuário logado é o criador do orçamento na aba ativa —
  /// controla se a opção de excluir aparece ao fechar a guia ou pela
  /// seção "Orçamentos em Aberto". Antes do servidor confirmar quem é o
  /// criador (`criadorId` ainda null, ex: rascunho local nunca salvo),
  /// consideramos que é o próprio usuário — afinal, só ele pode estar
  /// vendo/editando um rascunho que não existe no backend ainda.
  bool get souCriadorDaAbaAtiva {
    if (tabAtual == null) return false;
    if (tabAtual!.criadorId == null) return true;
    return tabAtual!.criadorId == _userId;
  }

  /// Registra o conteúdo atual da aba ativa como "salvo" — chamar logo após
  /// hidratar a aba a partir do servidor (abertura/reabertura do editor) ou
  /// logo após uma persistência bem-sucedida (salvar/auto-save). A partir
  /// daqui, `houveAlteracaoNaAbaAtiva` volta a `false` até o usuário mexer em
  /// algo. Ver `OrcamentoTab.marcarComoSalvo`.
  void marcarAbaAtivaComoSalva() {
    tabAtual?.marcarComoSalvo();
  }

  /// true se a aba ativa tem alterações locais ainda não persistidas desde
  /// a última chamada a [marcarAbaAtivaComoSalva]. Usado para decidir se o
  /// editor deve perguntar "salvar alterações?" ao fechar — em especial
  /// quando quem está editando não é o criador do orçamento (ver
  /// `OrcamentoEditorPage`, botão "Voltar").
  bool get houveAlteracaoNaAbaAtiva => tabAtual?.houveAlteracao ?? false;

  /// Mesma lógica de [souCriadorDaAbaAtiva], mas para qualquer [criadorId]
  /// informado diretamente (ex: um item de [OrcamentoAbertoInfo] da lista
  /// "Em Aberto", sem precisar ter uma aba local aberta para ele).
  bool souCriadorDe(int? criadorId) {
    if (criadorId == null) return false; // sem dono identificável, não arrisca
    return criadorId == _userId;
  }

  /// Verifica se já existe uma aba aberta com o [servidorId] informado.
  /// Se sim, ativa essa aba e retorna seu índice.
  /// Se não, retorna -1 (chamador deve criar a aba normalmente).
  int ativarAbaExistente(int servidorId) {
    final idx = _abas.indexWhere((a) => a.servidorId == servidorId);
    if (idx >= 0) {
      _abaAtiva = idx;
      _salvarAbas();
      notifyListeners();
    }
    return idx;
  }

  /// Mesmo comportamento de [ativarAbaExistente], mas espera primeiro
  /// qualquer criação de orçamento em andamento (`_criacoesEmAndamento`)
  /// terminar. Existe para fechar uma corrida: ao clicar em "Novo
  /// Orçamento", a aba local é criada na hora mas o `servidorId` só chega
  /// de forma assíncrona (POST /orcamentos). Se, nesse intervalo, o mesmo
  /// orçamento já aparecer na seção "Orçamentos em Aberto" (via SSE
  /// 'orcamento_criado', que é emitido pelo backend antes da resposta do
  /// POST retornar ao próprio criador) e o usuário clicar nele, uma
  /// checagem síncrona não encontraria a aba ainda sem servidorId e abriria
  /// uma SEGUNDA guia para o mesmo orçamento. Aguardando as criações
  /// pendentes antes de checar, garantimos que `servidorId` já esteja
  /// preenchido quando a comparação acontece.
  Future<int> ativarAbaExistenteAsync(int servidorId) async {
    if (_criacoesEmAndamento.isNotEmpty) {
      await Future.wait(_criacoesEmAndamento.values.toList());
    }
    return ativarAbaExistente(servidorId);
  }

  /// Inicia uma nova aba de edição SEM criar nada no servidor ainda.
  /// O servidorId será preenchido apenas ao salvar ou enviar para aprovação.
  void novoOrcamento(String titulo) {
    if (_abas.isEmpty) {
      _abas.add(OrcamentoTab(id: _uuid.v4(), titulo: titulo, modoEdicao: true));
      _abaAtiva = 0;
    } else {
      // Substitui a aba atual (que deve estar vazia)
      _abas[_abaAtiva] = OrcamentoTab(id: _uuid.v4(), titulo: titulo, modoEdicao: true);
    }
    _salvarAbas();
    notifyListeners();
  }

  // ── Adicionar material direto do estoque (com fornecedor pré-selecionado) ──
  //
  // Chamado quando o usuário clica em um fornecedor no painel lateral do
  // _MaterialFormDialog. Monta o ItemOrcamentoData com TODOS os fornecedores
  // do material, mas com o fornecedor clicado já pré-selecionado.
  void adicionarMaterialDireto({
    required MaterialModel material,
    required FornecedorMaterialModel fornecedor,
  }) {
    // Monta o mapa de preços com TODOS os fornecedores do material
    final precos = <int, PrecoFornecedorData>{};
    for (final fm in material.fornecedorMateriais) {
      precos[fm.fornecedorId] = PrecoFornecedorData(
        fornecedorNome: fm.fornecedorNome,
        preco:   fm.preco > 0 ? fm.preco : null,
      );
    }

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

  // ── Helpers ───────────────────────────────────

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
    _sseSub?.cancel();
    super.dispose();
  }
}