import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/estoque_model.dart';
import '../repositories/estoque_repository.dart';

String _mensagemErro(Object e) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Verifique a conexão com o servidor';
      }
  if (raw.contains('foreign key constraint') ||
      raw.contains('violates RESTRICT') ||
      raw.contains('P2003')) {
    return 'Não é possível excluir: Este item está vinculado a outros registros '
        '(movimentações, orçamentos ou ordens de compra). Desative-o em vez de excluí-lo.';
  }
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class EstoqueProvider extends ChangeNotifier {
  final EstoqueRepository _repo = EstoqueRepository();

  List<RelacaoOSModel> _relacoesOS = [];
  List<RelacaoOSModel> get relacoesOS => _relacoesOS;

  /// Retorna o conjunto de números de OS que já foram fechadas no controle
  /// de estoque. Usado para bloquear a finalização de OCs que referenciam
  /// essas OS.
  Set<String> get numerosOSFechadas => _relacoesOS
      .where((r) => r.estaFechada)
      .map((r) => r.numeroOS)
      .toSet();

  RelacaoOSModel? _relacaoSelecionada;
  RelacaoOSModel? get relacaoSelecionada => _relacaoSelecionada;

  bool _carregando = false;
  bool get carregando => _carregando;

  bool _carregandoDetalhe = false;
  bool get carregandoDetalhe => _carregandoDetalhe;

  bool _fechandoOS = false;
  bool get fechandoOS => _fechandoOS;

  String? _erro;
  String? get erro => _erro;

  Future<void> carregarRelacoesOS({String? busca}) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _relacoesOS = await _repo.listarTodasRelacoesOS(busca: busca);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> selecionarRelacaoOS(String numeroOS) async {
    _carregandoDetalhe = true;
    notifyListeners();
    try {
      _relacaoSelecionada = await _repo.buscarRelacaoOS(numeroOS);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoDetalhe = false;
      notifyListeners();
    }
  }

  void limparSelecao() {
    _relacaoSelecionada = null;
    notifyListeners();
  }

  Future<bool> registrarMovimentacao({
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
  }) async {
    try {
      await _repo.registrarMovimentacao(
        materialId:       materialId,
        tipo:             tipo,
        quantidade:       quantidade,
        numeroOS:         numeroOS,
        precoUnitario:    precoUnitario,
        precoM2:          precoM2,
        observacao:       observacao,
        ordemCompraId:    ordemCompraId,
        larguraUsada:     larguraUsada,
        comprimentoUsado: comprimentoUsado,
        materialOrigemId: materialOrigemId,
      );
      await carregarRelacoesOS();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Igual a [registrarMovimentacao] mas NÃO chama [carregarRelacoesOS] ao
  /// final. Use quando for registrar múltiplas movimentações em sequência e
  /// quiser recarregar apenas uma vez ao final (evita criar RelacaoOS
  /// duplicadas por race condition entre chamadas consecutivas).
  Future<bool> registrarMovimentacaoSilencioso({
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
  }) async {
    try {
      await _repo.registrarMovimentacao(
        materialId:       materialId,
        tipo:             tipo,
        quantidade:       quantidade,
        numeroOS:         numeroOS,
        precoUnitario:    precoUnitario,
        precoM2:          precoM2,
        observacao:       observacao,
        ordemCompraId:    ordemCompraId,
        larguraUsada:     larguraUsada,
        comprimentoUsado: comprimentoUsado,
        materialOrigemId: materialOrigemId,
      );
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> removerMovimentacao({
    required int movimentacaoId,
    required String numeroOS,
  }) async {
    try {
      await _repo.removerMovimentacao(movimentacaoId);

      // Busca os dados atualizados ANTES de tocar no estado/notificar,
      // para que a troca de _relacaoSelecionada e _relacoesOS aconteça
      // em um único ponto, com uma única notifyListeners() ao final.
      // Encadear vários notifyListeners() em sequência (como fazia antes,
      // via carregarRelacoesOS() + notify explícito) pode disparar um
      // rebuild enquanto o Flutter ainda está processando o rebuild
      // anterior — e se esse rebuild remover da árvore o card cuja
      // última movimentação acabou de ser excluída (ex.: ao remover a
      // saída restante de um material), o widget é desativado nesse
      // meio-tempo, causando "setState()/markNeedsBuild() called during
      // build" e "Looking up a deactivated widget's ancestor is unsafe".
      RelacaoOSModel? novaSelecao;
      try {
        novaSelecao = await _repo.buscarRelacaoOS(numeroOS);
      } catch (_) {
        novaSelecao = null;
      }
      final novasRelacoes = await _repo.listarTodasRelacoesOS();

      _relacaoSelecionada = novaSelecao;
      _relacoesOS = novasRelacoes;
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Usa o [relacaoOSId] numérico — OS textuais podem ter múltiplas relações
  /// com o mesmo numeroOS, então o id garante a relação correta.
  Future<bool> excluirRelacaoOS(int relacaoOSId) async {
    try {
      await _repo.excluirRelacaoOS(relacaoOSId);
      _relacaoSelecionada = null;
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Renomeia a OS: altera o numeroOS no backend e recarrega a lista.
  Future<bool> renomearOS(int relacaoOSId, String novoNumeroOS) async {
    try {
      final atualizada = await _repo.renomearOS(relacaoOSId, novoNumeroOS);
      // Atualiza a seleção com os dados atualizados (numeroOS novo)
      _relacaoSelecionada = atualizada;
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Fecha a OS: muda status para FECHADA no backend e remove da lista
  /// de controle de estoque. A OS passa a aparecer só na página de relatórios.
  Future<bool> fecharOS(int relacaoOSId) async {
    _fechandoOS = true;
    notifyListeners();
    try {
      await _repo.fecharOS(relacaoOSId);
      _relacaoSelecionada = null;
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    } finally {
      _fechandoOS = false;
      notifyListeners();
    }
  }

  /// Igual a [fecharOS], mas não altera [_carregando]/[_fechandoOS] nem
  /// recarrega a lista internamente — não dispara o spinner de tela cheia.
  /// Usado no fechamento automático em segundo plano (ex.: ao virar o dia),
  /// onde a lista deve ser atualizada sem "piscar" a UI. Chame
  /// [recarregarRelacoesOSSilencioso] uma única vez ao final do lote.
  Future<bool> fecharOSSilencioso(int relacaoOSId) async {
    try {
      await _repo.fecharOS(relacaoOSId);
      if (_relacaoSelecionada?.id == relacaoOSId) {
        _relacaoSelecionada = null;
      }
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      return false;
    }
  }

  /// Recarrega [_relacoesOS] do servidor e notifica os listeners sem passar
  /// por [_carregando] — evita o spinner de tela cheia. Usado após um lote
  /// de fechamentos automáticos silenciosos, para refletir o resultado na
  /// UI com uma única atualização "suave".
  Future<void> recarregarRelacoesOSSilencioso({String? busca}) async {
    try {
      final novasRelacoes = await _repo.listarTodasRelacoesOS(busca: busca);
      _relacoesOS = novasRelacoes;
      notifyListeners();
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
    }
  }

  /// Reverte a OS fechada: muda status para EM_ANDAMENTO no backend.
  /// A OS volta ao controle de estoque e some da página de relatórios.
  Future<bool> reverterOS(String numeroOS) async {
    try {
      await _repo.reverterOS(numeroOS);
      _relacaoSelecionada = null;
      await carregarRelacoesOS();
      notifyListeners();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Atualiza o preço (precoUnitario e/ou precoM2) de uma movimentação existente.
  /// Não altera quantidade nem saldo de estoque — apenas corrige o custo registrado.
  Future<bool> atualizarPrecoMovimentacao(
    int movimentacaoId, {
    double? precoUnitario,
    double? precoM2,
  }) async {
    try {
      await _repo.atualizarPrecoMovimentacao(
        movimentacaoId,
        precoUnitario: precoUnitario,
        precoM2: precoM2,
      );
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}