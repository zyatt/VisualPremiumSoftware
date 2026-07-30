import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/material_model.dart';

// ─── Data classes ─────────────────────────────────────────────────────────────

class PrecoFornecedorData {
  double? preco;
  String fornecedorNome;
  /// Observação de disponibilidade digitada pelo usuário para este
  /// material × fornecedor (ex: "Em falta", "Prazo 5 dias").
  String? observacao;

  PrecoFornecedorData({
    required this.fornecedorNome,
    this.preco,
    this.observacao,
  });

  Map<String, dynamic> toJson() => {
        'fornecedorNome': fornecedorNome,
        'preco': preco,
        'observacao': observacao,
      };

  factory PrecoFornecedorData.fromJson(Map<String, dynamic> j) =>
      PrecoFornecedorData(
        fornecedorNome: j['fornecedorNome'] as String,
        preco: (j['preco'] as num?)?.toDouble(),
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

  /// Modo de precificação usado no comparativo de preços e ao gerar a OC:
  /// 'UNIDADE' — o preço do fornecedor é por unidade/peça (padrão; total =
  /// preço × quantidade), ou 'METRO_LINEAR' — o preço do fornecedor já é
  /// por m/l (ou pela unidade de medida do material; total = preço ×
  /// Quantidade por Unidade × quantidade). Só afeta a visualização/
  /// conversão; os preços cadastrados não são alterados.
  String modoPrecificacao;

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
    this.modoPrecificacao = 'UNIDADE',
    this.criadaPeloTour = false,
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
        itens: (j['itens'] as List)
            .map((i) => ItemOrcamentoData.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

// ─── Provider ─────────────────────────────────
// NOTA: o histórico de orçamentos (salvos/cancelados) foi movido para o
// servidor. O provider agora só gerencia a aba em edição (rascunho local).

class OrcamentoProvider extends ChangeNotifier {
  // Chaves agora dependem do usuário — sem prefixo, sem dados de outro usuário
  static String _kAbas(int userId)     => 'orcamento_abas_$userId';
  static String _kAbaAtiva(int userId) => 'orcamento_aba_ativa_$userId';

  final _uuid = const Uuid();
  int? _userId; // usuário atual

  final List<OrcamentoTab> _abas = [];
  List<OrcamentoTab> get abas => List.unmodifiable(_abas);

  int _abaAtiva = 0;
  int get abaAtiva => _abaAtiva;

  OrcamentoTab? get tabAtual => _abas.isEmpty ? null : _abas[_abaAtiva];

  bool _carregado = false;
  bool get carregado => _carregado;

  OrcamentoProvider();

  // ── Chamado pelo main.dart ao logar/deslogar ──────────────────────────────
  Future<void> trocarUsuario(int? userId) async {
    if (_userId == userId) return; // mesmo usuário, não recarrega
    _userId = userId;
    _abas.clear();
    _abaAtiva = 0;
    _carregado = false;
    notifyListeners();

    if (userId != null) {
      await _carregar();
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

  void _novaAba({bool notificar = true, bool criadaPeloTour = false}) {
    final idx = _abas.length + 1;
    _abas.add(OrcamentoTab(
      id: _uuid.v4(),
      titulo: 'Orçamento $idx',
      criadaPeloTour: criadaPeloTour,
    ));
    _abaAtiva = _abas.length - 1;
    if (notificar) {
      _salvarAbas();
      notifyListeners();
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
  }) {
    if (tabAtual == null) return;
    if (aguardandoAprovacao != null) tabAtual!.aguardandoAprovacao = aguardandoAprovacao;
    if (jaFinalizado != null) tabAtual!.jaFinalizado = jaFinalizado;
    if (modoGerarOC != null) tabAtual!.modoGerarOC = modoGerarOC;
    if (modoEdicao != null) tabAtual!.modoEdicao = modoEdicao;
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
      notifyListeners();
      return;
    }

    tabAtual!.itens.add(item);
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
      precos: precos ?? old.precos,
      fornecedorSelecionado: clearFornecedor
          ? null
          : (fornecedorSelecionado ?? old.fornecedorSelecionado),
    );
    _salvarAbas();
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
}