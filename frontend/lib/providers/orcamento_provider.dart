import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/material_model.dart';

// ─── Enums ────────────────────────────────────

enum ModoOrcamento { unitario, metroQuadrado }

// ─── Data classes ─────────────────────────────────────────────────────────────

class PrecoFornecedorData {
  double? preco;
  double? precoM2;
  String fornecedorNome;

  PrecoFornecedorData({
    required this.fornecedorNome,
    this.preco,
    this.precoM2,
  });

  Map<String, dynamic> toJson() => {
        'fornecedorNome': fornecedorNome,
        'preco': preco,
        'precoM2': precoM2,
      };

  factory PrecoFornecedorData.fromJson(Map<String, dynamic> j) =>
      PrecoFornecedorData(
        fornecedorNome: j['fornecedorNome'] as String,
        preco: (j['preco'] as num?)?.toDouble(),
        precoM2: (j['precoM2'] as num?)?.toDouble(),
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
  double quantidade;
  Map<int, PrecoFornecedorData> precos;
  int? fornecedorSelecionado;
  ModoOrcamento? modoOrcamento;

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
    this.quantidade = 1,
    Map<int, PrecoFornecedorData>? precos,
    this.fornecedorSelecionado,
    this.modoOrcamento,
  }) : itemId = itemId ?? const Uuid().v4(),
       precos = precos ?? {};

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
        'quantidade': quantidade,
        'precos': precos.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'fornecedorSelecionado': fornecedorSelecionado,
        'modoOrcamento': modoOrcamento?.name,
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
        quantidade: (j['quantidade'] as num).toDouble(),
        precos: (j['precos'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(
            int.parse(k),
            PrecoFornecedorData.fromJson(v as Map<String, dynamic>),
          ),
        ),
        fornecedorSelecionado: j['fornecedorSelecionado'] as int?,
        modoOrcamento: j['modoOrcamento'] != null
            ? ModoOrcamento.values.byName(j['modoOrcamento'] as String)
            : null,
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
  }) : itens = itens ?? [],
       fornecedoresOcultos = fornecedoresOcultos ?? [];

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
      await prefs.setString(
        _kAbas(_userId!),
        jsonEncode(_abas.map((a) => a.toJson()).toList()),
      );
      await prefs.setInt(_kAbaAtiva(_userId!), _abaAtiva);
    } catch (_) {}
  }
  // ── Abas ──────────────────────────────────────

  void _novaAba({bool notificar = true}) {
    final idx = _abas.length + 1;
    _abas.add(OrcamentoTab(
      id: _uuid.v4(),
      titulo: 'Orçamento $idx',
    ));
    _abaAtiva = _abas.length - 1;
    if (notificar) {
      _salvarAbas();
      notifyListeners();
    }
  }

  void adicionarAba() => _novaAba();

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

  void removerItem(String itemId) {
    tabAtual?.itens.removeWhere((i) => i.itemId == itemId);
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
    int? fornecedorSelecionado,
    bool clearFornecedor = false,
    ModoOrcamento? modoOrcamento,
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
      quantidade: quantidade ?? old.quantidade,
      precos: precos ?? old.precos,
      fornecedorSelecionado: clearFornecedor
          ? null
          : (fornecedorSelecionado ?? old.fornecedorSelecionado),
      modoOrcamento: modoOrcamento ?? old.modoOrcamento,
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
        precoM2: fm.precoMetroQuadrado > 0 ? fm.precoMetroQuadrado : null,
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