import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum ModoOrcamento { unitario, metroQuadrado }

enum StatusOrcamentoHistorico { salvo, descartado }

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
  }) : precos = precos ?? {};

  Map<String, dynamic> toJson() => {
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

  OrcamentoTab({
    required this.id,
    required this.titulo,
    List<ItemOrcamentoData>? itens,
  }) : itens = itens ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'itens': itens.map((i) => i.toJson()).toList(),
      };

  factory OrcamentoTab.fromJson(Map<String, dynamic> j) => OrcamentoTab(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        itens: (j['itens'] as List)
            .map((i) => ItemOrcamentoData.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

// ─── Histórico ────────────────────────────────────────────────────────────────

class OrcamentoHistoricoEntry {
  final String id;
  final String titulo;
  final List<ItemOrcamentoData> itens;
  final StatusOrcamentoHistorico status;
  final String? motivoDescarte;
  final DateTime criadoEm;

  OrcamentoHistoricoEntry({
    required this.id,
    required this.titulo,
    required this.itens,
    required this.status,
    this.motivoDescarte,
    required this.criadoEm,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'itens': itens.map((i) => i.toJson()).toList(),
        'status': status.name,
        'motivoDescarte': motivoDescarte,
        'criadoEm': criadoEm.toIso8601String(),
      };

  factory OrcamentoHistoricoEntry.fromJson(Map<String, dynamic> j) =>
      OrcamentoHistoricoEntry(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        itens: (j['itens'] as List)
            .map((i) => ItemOrcamentoData.fromJson(i as Map<String, dynamic>))
            .toList(),
        status: StatusOrcamentoHistorico.values.byName(j['status'] as String),
        motivoDescarte: j['motivoDescarte'] as String?,
        criadoEm: DateTime.parse(j['criadoEm'] as String),
      );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

class OrcamentoProvider extends ChangeNotifier {
  static const _kAbas = 'orcamento_abas';
  static const _kAbaAtiva = 'orcamento_aba_ativa';
  static const _kHistorico = 'orcamento_historico';

  final _uuid = const Uuid();

  final List<OrcamentoTab> _abas = [];
  List<OrcamentoTab> get abas => List.unmodifiable(_abas);

  int _abaAtiva = 0;
  int get abaAtiva => _abaAtiva;

  OrcamentoTab? get tabAtual =>
      _abas.isEmpty ? null : _abas[_abaAtiva];

  final List<OrcamentoHistoricoEntry> _historico = [];
  List<OrcamentoHistoricoEntry> get historico => List.unmodifiable(_historico);

  List<OrcamentoHistoricoEntry> get historicoSalvos =>
      _historico.where((e) => e.status == StatusOrcamentoHistorico.salvo).toList();

  List<OrcamentoHistoricoEntry> get historicoDescartados =>
      _historico.where((e) => e.status == StatusOrcamentoHistorico.descartado).toList();

  bool _carregado = false;
  bool get carregado => _carregado;

  OrcamentoProvider() {
    _carregar();
  }

  // ── Persistência ─────────────────────────────────────────────────────────────

  Future<void> _carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Abas
      final abasJson = prefs.getString(_kAbas);
      if (abasJson != null) {
        final lista = jsonDecode(abasJson) as List;
        _abas.addAll(lista.map(
          (j) => OrcamentoTab.fromJson(j as Map<String, dynamic>),
        ));
        _abaAtiva = prefs.getInt(_kAbaAtiva) ?? 0;
        if (_abaAtiva >= _abas.length) _abaAtiva = 0;
      }

      // Histórico
      final histJson = prefs.getString(_kHistorico);
      if (histJson != null) {
        final lista = jsonDecode(histJson) as List;
        _historico.addAll(lista.map(
          (j) => OrcamentoHistoricoEntry.fromJson(j as Map<String, dynamic>),
        ));
      }
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

  Future<void> _salvarHistorico() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kHistorico,
          jsonEncode(_historico.map((h) => h.toJson()).toList()));
    } catch (_) {}
  }

  // ── Abas ──────────────────────────────────────────────────────────────────────

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

  // ── Itens da aba ativa ────────────────────────────────────────────────────────

  void adicionarItem(ItemOrcamentoData item) {
    if (tabAtual == null) return;
    final idx = tabAtual!.itens
        .indexWhere((i) => i.materialId == item.materialId);
    if (idx >= 0) {
      tabAtual!.itens[idx] = item;
    } else {
      tabAtual!.itens.add(item);
    }
    _salvarAbas();
    notifyListeners();
  }

  void removerItem(int materialId) {
    tabAtual?.itens.removeWhere((i) => i.materialId == materialId);
    _salvarAbas();
    notifyListeners();
  }

  void atualizarItem(int materialId, ItemOrcamentoData dados) {
    if (tabAtual == null) return;
    final idx = tabAtual!.itens.indexWhere((i) => i.materialId == materialId);
    if (idx >= 0) {
      tabAtual!.itens[idx] = dados;
      _salvarAbas();
      notifyListeners();
    }
  }

  void atualizarItemParcial(int materialId, {
    double? quantidade,
    int? fornecedorSelecionado,
    bool clearFornecedor = false,
    ModoOrcamento? modoOrcamento,
    Map<int, PrecoFornecedorData>? precos,
  }) {
    if (tabAtual == null) return;
    final idx = tabAtual!.itens.indexWhere((i) => i.materialId == materialId);
    if (idx < 0) return;
    final old = tabAtual!.itens[idx];
    tabAtual!.itens[idx] = ItemOrcamentoData(
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
    tabAtual?.itens.clear();
    _salvarAbas();
    notifyListeners();
  }

  // ── Salvar orçamento no histórico ─────────────────────────────────────────────

  void salvarOrcamento() {
    if (tabAtual == null || tabAtual!.itens.isEmpty) return;
    _historico.insert(
      0,
      OrcamentoHistoricoEntry(
        id: _uuid.v4(),
        titulo: tabAtual!.titulo,
        itens: List<ItemOrcamentoData>.from(tabAtual!.itens),
        status: StatusOrcamentoHistorico.salvo,
        criadoEm: DateTime.now(),
      ),
    );
    _fecharAbaAtual();
    _salvarHistorico();
    notifyListeners();
  }

  // ── Descartar orçamento ───────────────────────────────────────────────────────

  void descartarOrcamento(String motivo) {
    if (tabAtual == null) return;
    _historico.insert(
      0,
      OrcamentoHistoricoEntry(
        id: _uuid.v4(),
        titulo: tabAtual!.titulo,
        itens: List<ItemOrcamentoData>.from(tabAtual!.itens),
        status: StatusOrcamentoHistorico.descartado,
        motivoDescarte: motivo.trim().isEmpty ? 'Não informado' : motivo.trim(),
        criadoEm: DateTime.now(),
      ),
    );
    _fecharAbaAtual();
    _salvarHistorico();
    notifyListeners();
  }

  // ── Reabrir orçamento salvo ───────────────────────────────────────────────────

  void reabrirOrcamento(OrcamentoHistoricoEntry entry) {
    // Cria nova aba com o conteúdo do histórico
    _abas.add(OrcamentoTab(
      id: _uuid.v4(),
      titulo: entry.titulo,
      itens: List<ItemOrcamentoData>.from(entry.itens),
    ));
    _abaAtiva = _abas.length - 1;
    _salvarAbas();
    notifyListeners();
  }

  // ── Excluir do histórico ──────────────────────────────────────────────────────

  void excluirDoHistorico(String id) {
    _historico.removeWhere((e) => e.id == id);
    _salvarHistorico();
    notifyListeners();
  }

  // ── Fechar aba ────────────────────────────────────────────────────────────────

  void _fecharAbaAtual() {
    if (_abas.length == 1) {
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

  // ── Helpers ───────────────────────────────────────────────────────────────────

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