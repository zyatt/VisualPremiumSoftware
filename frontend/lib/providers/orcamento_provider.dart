import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class OrcamentoTab {
  final String id;
  String titulo;
  List<Map<String, dynamic>> itens;

  OrcamentoTab({
    required this.id,
    required this.titulo,
    List<Map<String, dynamic>>? itens,
  }) : itens = itens ?? [];
}

class OrcamentoProvider extends ChangeNotifier {
  final _uuid = const Uuid();

  final List<OrcamentoTab> _abas = [];
  List<OrcamentoTab> get abas => _abas;

  int _abaAtiva = 0;
  int get abaAtiva => _abaAtiva;

  OrcamentoTab? get tabAtual =>
      _abas.isEmpty ? null : _abas[_abaAtiva];

  OrcamentoProvider() {
    _novaAba(); // começa com uma aba vazia
  }

  void _novaAba() {
    final idx = _abas.length + 1;
    _abas.add(OrcamentoTab(
      id: _uuid.v4(),
      titulo: 'Orçamento $idx',
    ));
    _abaAtiva = _abas.length - 1;
    notifyListeners();
  }

  void adicionarAba() => _novaAba();

  void selecionarAba(int index) {
    _abaAtiva = index;
    notifyListeners();
  }

  void renomearAba(int index, String titulo) {
    _abas[index].titulo = titulo;
    notifyListeners();
  }

  /// Adiciona ou atualiza item na aba ativa
  void adicionarItem(Map<String, dynamic> item) {
    if (tabAtual == null) return;
    final idx = tabAtual!.itens
        .indexWhere((i) => i['materialId'] == item['materialId']);
    if (idx >= 0) {
      tabAtual!.itens[idx] = item;
    } else {
      tabAtual!.itens.add(item);
    }
    notifyListeners();
  }

  void removerItem(int materialId) {
    tabAtual?.itens.removeWhere((i) => i['materialId'] == materialId);
    notifyListeners();
  }

  void atualizarItem(int materialId, Map<String, dynamic> dados) {
    if (tabAtual == null) return;
    final idx = tabAtual!.itens
        .indexWhere((i) => i['materialId'] == materialId);
    if (idx >= 0) {
      tabAtual!.itens[idx] = {...tabAtual!.itens[idx], ...dados};
      notifyListeners();
    }
  }

  /// Remove a aba após gerar a ordem de compra
  void fecharAba(int index) {
    if (_abas.length == 1) {
      _abas[0] = OrcamentoTab(id: _uuid.v4(), titulo: 'Orçamento 1');
    } else {
      _abas.removeAt(index);
      if (_abaAtiva >= _abas.length) _abaAtiva = _abas.length - 1;
    }
    notifyListeners();
  }

  bool get podeGerarOrdem {
    if (tabAtual == null) return false;
    final fornecedores = tabAtual!.itens
        .where((i) => i['fornecedorId'] != null)
        .map((i) => i['fornecedorId'])
        .toSet();
    return fornecedores.length >= 3 && tabAtual!.itens.isNotEmpty;
  }
}