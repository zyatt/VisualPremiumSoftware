import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
  final bool materialEspecifico;
  String? descricao;
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
    this.materialEspecifico = false,
    this.descricao,
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
        'materialEspecifico': materialEspecifico,
        'descricao': descricao,
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
        materialEspecifico: j['materialEspecifico'] as bool? ?? false,
        descricao: j['descricao'] as String?,
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

  OrcamentoTab({
    required this.id,
    required this.titulo,
    List<ItemOrcamentoData>? itens,
    this.servidorId,
  }) : itens = itens ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'itens': itens.map((i) => i.toJson()).toList(),
        'servidorId': servidorId,
      };

  factory OrcamentoTab.fromJson(Map<String, dynamic> j) => OrcamentoTab(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        servidorId: j['servidorId'] as int?,
        itens: (j['itens'] as List)
            .map((i) => ItemOrcamentoData.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

// ─── Provider ─────────────────────────────────
// NOTA: o histórico de orçamentos (salvos/cancelados) foi movido para o
// servidor. O provider agora só gerencia a aba em edição (rascunho local).

class OrcamentoProvider extends ChangeNotifier {
  static const _kAbas = 'orcamento_abas';
  static const _kAbaAtiva = 'orcamento_aba_ativa';

  final _uuid = const Uuid();

  final List<OrcamentoTab> _abas = [];
  List<OrcamentoTab> get abas => List.unmodifiable(_abas);

  int _abaAtiva = 0;
  int get abaAtiva => _abaAtiva;

  OrcamentoTab? get tabAtual =>
      _abas.isEmpty ? null : _abas[_abaAtiva];

  bool _carregado = false;
  bool get carregado => _carregado;

  OrcamentoProvider() {
    _carregar();
  }

  // ── Persistência ─────────────────────────────────────────────────────────────

  Future<void> _carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final abasJson = prefs.getString(_kAbas);
      if (abasJson != null) {
        final lista = jsonDecode(abasJson) as List;
        _abas.addAll(lista.map(
          (j) => OrcamentoTab.fromJson(j as Map<String, dynamic>),
        ));
      }
      _abaAtiva = prefs.getInt(_kAbaAtiva) ?? 0;
      if (_abaAtiva >= _abas.length) _abaAtiva = 0;
    } catch (_) {}

    if (_abas.isEmpty) _novaAba(notificar: false);
    _carregado = true;
    notifyListeners();
  }

  Future<void> _salvarAbas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kAbas, jsonEncode(_abas.map((a) => a.toJson()).toList()));
      await prefs.setInt(_kAbaAtiva, _abaAtiva);
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

  // ── Itens da aba ativa ────────────────────────────────────────────────────────

  void adicionarItem(ItemOrcamentoData item) {
    if (tabAtual == null) return;

    // Deduplica apenas para materiais não-específicos adicionados manualmente
    // (sem itemId pré-existente), usando materialId como chave.
    // Itens restaurados do servidor já chegam com itemId próprio e NÃO devem
    // ser colapsados — cada combinação (material + fornecedor) é uma linha distinta.
    if (!item.materialEspecifico) {
      final idx = tabAtual!.itens.indexWhere(
        (i) => i.itemId == item.itemId ||
               (i.materialId == item.materialId && !i.materialEspecifico),
      );
      if (idx >= 0) {
        tabAtual!.itens[idx] = item;
        _salvarAbas();
        notifyListeners();
        return;
      }
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
    String? descricao,
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
      materialEspecifico: old.materialEspecifico,
      descricao: descricao ?? old.descricao,
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
    tabAtual?.itens.clear();
    if (tabAtual != null) tabAtual!.servidorId = null;
    _salvarAbas();
    notifyListeners();
  }

  // ── Fechar aba após salvar/cancelar ───────────────────────────────────────────
  // Chamado pela page após confirmar a operação no servidor.

  void fecharAbaAposOperacao() {
    _fecharAbaAtual();
    notifyListeners();
  }

  void _fecharAbaAtual() {
    if (_abas.length == 1) {
      // Mantém sempre ao menos uma aba vazia (sem servidorId)
      _abas[0] = OrcamentoTab(id: _uuid.v4(), titulo: 'Orçamento 1');
    } else {
      _abas.removeAt(_abaAtiva);
      if (_abaAtiva >= _abas.length) _abaAtiva = _abas.length - 1;
    }
    _salvarAbas();
  }

  void fecharAba(int index) {
    if (index < 0 || index >= _abas.length) return;
    if (_abas.length == 1) {
      _abas[0] = OrcamentoTab(id: _uuid.v4(), titulo: 'Orçamento 1');
    } else {
      _abas.removeAt(index);
      if (_abaAtiva >= _abas.length) _abaAtiva = _abas.length - 1;
    }
    _salvarAbas();
    notifyListeners();
  }

  /// Inicia uma nova aba de edição SEM criar nada no servidor ainda.
  /// O servidorId será preenchido apenas ao salvar ou enviar para aprovação.
  void novoOrcamento(String titulo) {
    if (_abas.isEmpty) {
      _abas.add(OrcamentoTab(id: _uuid.v4(), titulo: titulo));
      _abaAtiva = 0;
    } else {
      // Substitui a aba atual (que deve estar vazia)
      _abas[_abaAtiva] = OrcamentoTab(id: _uuid.v4(), titulo: titulo);
    }
    _salvarAbas();
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────

  bool get podeGerarOrdem {
    if (tabAtual == null || tabAtual!.itens.isEmpty) return false;
    final fornecedores = tabAtual!.itens
        .where((i) => i.fornecedorSelecionado != null)
        .map((i) => i.fornecedorSelecionado!)
        .toSet();
    return fornecedores.isNotEmpty &&
        tabAtual!.itens.every((i) => i.fornecedorSelecionado != null);
  }
}