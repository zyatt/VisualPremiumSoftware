import 'package:flutter/foundation.dart';
import '../models/estoque_producao_model.dart';
import '../repositories/estoque_producao_repository.dart';

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
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

/// Gerencia o estoque de produção: saldo disponível (alimentado por
/// transferências vindas do Controle de Estoque) e histórico de
/// movimentações (transferências recebidas + baixas por OS).
///
/// Desde que ADMIN/GERENTE/COMPRAS passaram a visualizar as duas linhas
/// SIMULTANEAMENTE (uma aba para cada), o provider guarda o estoque de
/// cada linha ('1' e '2') separadamente em [_estoquePorLinha], em vez de
/// manter apenas uma "linha ativa" por vez. Isso evita que abrir a aba da
/// produção 2 sobrescreva o que está sendo mostrado na aba da produção 1.
///
/// [_producao] continua existindo como a linha "padrão/ativa" — usada por
/// usuários PRODUCAO1/PRODUCAO2 (que só têm uma linha) e por operações que
/// não recebem a linha explicitamente (ex.: dar baixa a partir da tela de
/// detalhe, que hoje sempre baixa da linha ativa do usuário logado).
class EstoqueProducaoProvider with ChangeNotifier {
  final EstoqueProducaoRepository _repo = EstoqueProducaoRepository();

  String? _producao;
  String? get producao => _producao;

  /// Define a linha de produção ativa ('1' ou '2'). Chamada logo após o
  /// login (a partir do cargo do usuário: PRODUCAO1 → '1', PRODUCAO2 → '2')
  /// e também sempre que o usuário logado mudar, para evitar que a página
  /// de Produção — ao não ser remontada entre logins, já que
  /// StatefulShellRoute preserva o estado dos branches — continue usando a
  /// linha do usuário anterior. ADMIN/GERENTE/COMPRAS podem trocar de linha
  /// manualmente (seletor na tela) chamando de novo com outro valor.
  ///
  /// IMPORTANTE: este método NÃO ignora mais chamadas repetidas com o mesmo
  /// valor. O guard antigo (`if (_producao == producao) return;`),
  /// combinado com o provider não sendo recriado entre logins, fazia a
  /// linha do usuário anterior "grudar" — foi essa a causa do PRODUCAO2
  /// enxergar o estoque da produção 1. Quem chama este método deve, em
  /// seguida, recarregar estoque/histórico para refletir a troca (a página
  /// de Produção já faz isso em `_definirProducaoDoUsuario`).
  void definirProducao(String producao) {
    _producao = producao;
    notifyListeners();
  }

  // Estoque guardado por linha ('1' / '2'), permitindo exibir as duas
  // simultaneamente (uma aba para cada) sem que uma sobrescreva a outra.
  final Map<String, List<MaterialEstoqueProducaoModel>> _estoquePorLinha = {
    '1': [],
    '2': [],
  };
  final Map<String, bool> _carregandoPorLinha = {'1': false, '2': false};
  final Map<String, String?> _erroPorLinha = {'1': null, '2': null};

  /// Estoque da linha ativa ([_producao]) — mantido por compatibilidade com
  /// código que ainda não foi adaptado para múltiplas linhas simultâneas
  /// (ex.: telas de detalhe/baixa, que sempre operam a linha do usuário
  /// logado).
  List<MaterialEstoqueProducaoModel> get estoque =>
      _estoquePorLinha[_producao] ?? [];
  bool get carregandoEstoque => _carregandoPorLinha[_producao] ?? false;

  /// Estoque de uma linha específica ('1' ou '2'), independente de qual é a
  /// linha ativa. Usado pelas abas "Estoque Produção 1" / "Estoque Produção
  /// 2" quando exibidas lado a lado para ADMIN/GERENTE/COMPRAS.
  List<MaterialEstoqueProducaoModel> estoqueDaLinha(String producao) =>
      _estoquePorLinha[producao] ?? [];
  bool carregandoDaLinha(String producao) =>
      _carregandoPorLinha[producao] ?? false;
  String? erroDaLinha(String producao) => _erroPorLinha[producao];

  List<MovimentacaoProducaoModel> _historico = [];
  List<MovimentacaoProducaoModel> get historico => _historico;
  bool _carregandoHistorico = false;
  bool get carregandoHistorico => _carregandoHistorico;

  String? _erro;
  String? get erro => _erro;

  /// Carrega o estoque de uma linha específica. Se [producao] não for
  /// informado, usa a linha ativa ([_producao]) — comportamento antigo,
  /// mantido para não quebrar quem já chama sem esse parâmetro.
  Future<void> carregarEstoque({
    String? producao,
    String? busca,
    String? categoria,
    String? identificador,
    String? medida,
    String? espessura,
  }) async {
    final linha = producao ?? _producao;
    if (linha == null) return;
    _carregandoPorLinha[linha] = true;
    _erroPorLinha[linha] = null;
    if (linha == _producao) _erro = null;
    notifyListeners();
    try {
      final lista = await _repo.listarEstoque(
        producao: linha,
        busca: busca,
        categoria: categoria,
        identificador: identificador,
        medida: medida,
        espessura: espessura,
      );
      _estoquePorLinha[linha] = lista;
    } catch (e) {
      final msg = _mensagemErro(e);
      _erroPorLinha[linha] = msg;
      if (linha == _producao) _erro = msg;
    } finally {
      _carregandoPorLinha[linha] = false;
      notifyListeners();
    }
  }

  /// Carrega o estoque das duas linhas de uma vez (usado para exibir as
  /// duas juntas, em uma única lista combinada, para ADMIN/GERENTE/COMPRAS).
  Future<void> carregarEstoqueAmbasLinhas() async {
    await Future.wait([
      carregarEstoque(producao: '1'),
      carregarEstoque(producao: '2'),
    ]);
  }

  /// Estoque das DUAS linhas juntas, em uma única lista (produção 1 e
  /// produção 2 combinadas) — usado por ADMIN/GERENTE/COMPRAS, que devem
  /// enxergar tudo de uma vez, com a coluna `producao` de cada item
  /// indicando a que linha ele pertence. Materiais da linha '1' vêm
  /// primeiro, seguidos pelos da linha '2'.
  List<MaterialEstoqueProducaoModel> get estoqueCombinado => [
        ..._estoquePorLinha['1'] ?? [],
        ..._estoquePorLinha['2'] ?? [],
      ];

  /// True se qualquer uma das duas linhas ainda está carregando (usado pela
  /// visão combinada).
  bool get carregandoEstoqueCombinado =>
      (_carregandoPorLinha['1'] ?? false) || (_carregandoPorLinha['2'] ?? false);

  /// Erro da visão combinada: retorna o primeiro erro encontrado entre as
  /// duas linhas, se a lista combinada estiver vazia.
  String? get erroEstoqueCombinado => _erroPorLinha['1'] ?? _erroPorLinha['2'];


  /// Histórico compartilhado entre as duas linhas. Passe [producao] para
  /// filtrar por apenas uma delas; por padrão traz as duas.
  Future<void> carregarHistorico({String? busca, String? numeroOS, String? producao}) async {
    _carregandoHistorico = true;
    _erro = null;
    notifyListeners();
    try {
      _historico = await _repo.listarHistorico(busca: busca, numeroOS: numeroOS, producao: producao);
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoHistorico = false;
      notifyListeners();
    }
  }

  /// Transfere material do estoque normal para o estoque de produção.
  /// Usado pelo diálogo "Saída p/ Produção" na página de Controle de
  /// Estoque — quem transfere escolhe explicitamente para qual linha
  /// ('1' ou '2') o material vai, por isso [producao] é obrigatório aqui
  /// (não usa o [_producao] do provider, que é o da linha do usuário
  /// logado — o Controle de Estoque normalmente é operado por
  /// ADMIN/GERENTE/COMPRAS, sem uma linha própria).
  Future<bool> transferir({
    required int materialId,
    required double quantidade,
    required String producao,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    try {
      await _repo.transferir(
        materialId: materialId,
        quantidade: quantidade,
        producao: producao,
        observacao: observacao,
        larguraUsada: larguraUsada,
        comprimentoUsado: comprimentoUsado,
      );
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Devolve material do estoque de produção de volta para o estoque normal
  /// (operação inversa de [transferir]). Ao concluir, recarrega o estoque
  /// da linha afetada e o histórico compartilhado (a devolução gera um
  /// novo registro nele). Não recarrega o estoque normal (Controle de
  /// Estoque) — quem chama este método a partir daquela tela deve
  /// recarregar o `EstoqueProvider` separadamente, assim como já é feito
  /// hoje para a transferência na direção contrária.
  Future<bool> devolver({
    required int materialId,
    required double quantidade,
    required String producao,
    String? observacao,
  }) async {
    _erro = null;
    try {
      await _repo.devolver(
        materialId: materialId,
        quantidade: quantidade,
        producao: producao,
        observacao: observacao,
      );
      await carregarEstoque(producao: producao);
      await carregarHistorico();
      await carregarContadorPendentes();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Transfere material de uma linha de produção para a outra. Restrito a
  /// ADMIN/GERENTE (a UI só mostra a opção para esses cargos, e o backend
  /// reforça a mesma regra). Ao concluir, recarrega as DUAS linhas — a de
  /// origem (que perdeu saldo) e a de destino (que ganhou) — e o histórico,
  /// já que a transferência gera um novo registro nele.
  Future<bool> transferirEntreLinhas({
    required int materialId,
    required double quantidade,
    required String producaoOrigem,
    required String producaoDestino,
    String? observacao,
  }) async {
    _erro = null;
    try {
      await _repo.transferirEntreLinhas(
        materialId: materialId,
        quantidade: quantidade,
        producaoOrigem: producaoOrigem,
        producaoDestino: producaoDestino,
        observacao: observacao,
      );
      await Future.wait([
        carregarEstoque(producao: producaoOrigem),
        carregarEstoque(producao: producaoDestino),
      ]);
      await carregarHistorico();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Dá baixa no estoque de produção para uma OS. Se [producao] não for
  /// informado, baixa da linha ativa ([_producao]) — comportamento antigo.
  /// Ao dar baixa, recarrega o estoque só da linha afetada.
  /// BAIXA COMBINADA: [quantidade] (unidades inteiras) e
  /// [larguraUsada]/[comprimentoUsado] (dimensão usada) são ambos
  /// OPCIONAIS — pelo menos um deve ser informado por quem chama (a tela
  /// já valida isso antes de chegar aqui; ver estoqueProducao.service.js
  /// #darBaixa para a validação espelhada no backend).
  Future<bool> darBaixa({
    required int materialId,
    double? quantidade,
    required String numeroOS,
    String? producao,
    String? observacao,
    double? larguraUsada,
    double? comprimentoUsado,
  }) async {
    final linha = producao ?? _producao;
    if (linha == null) {
      _erro = 'Linha de produção não definida';
      notifyListeners();
      return false;
    }
    try {
      await _repo.darBaixa(
        materialId: materialId,
        quantidade: quantidade,
        numeroOS: numeroOS,
        producao: linha,
        observacao: observacao,
        larguraUsada: larguraUsada,
        comprimentoUsado: comprimentoUsado,
      );
      await carregarEstoque(producao: linha);
      await carregarContadorPendentes();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Exclui um registro do histórico do estoque de produção (transferência
  /// ou baixa). Não altera o saldo do estoque — apenas remove o registro.
  Future<bool> excluirHistorico(int movimentacaoId) async {
    _erro = null;
    try {
      await _repo.excluirHistorico(movimentacaoId);
      await carregarHistorico();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  // ── Entradas pendentes (retalho + devolução aguardando confirmação) ────

  List<EntradaPendenteModel> _pendentes = [];
  List<EntradaPendenteModel> get pendentes => _pendentes;
  bool _carregandoPendentes = false;
  bool get carregandoPendentes => _carregandoPendentes;

  int _totalPendentes = 0;
  int get totalPendentes => _totalPendentes;

  /// Carrega todas as pendências (sem filtro de linha — o card mostra todas).
  Future<void> carregarPendentes() async {
    _carregandoPendentes = true;
    _erro = null;
    notifyListeners();
    try {
      _pendentes = await _repo.listarPendentes();
      _totalPendentes = _pendentes.length;
    } catch (e) {
      _erro = _mensagemErro(e);
    } finally {
      _carregandoPendentes = false;
      notifyListeners();
    }
  }

  /// Atualiza só o contador (usado pelo badge do botão, sem precisar
  /// carregar a lista inteira).
  Future<void> carregarContadorPendentes() async {
    try {
      _totalPendentes = await _repo.contarPendentes();
      notifyListeners();
    } catch (_) {
      // Falha silenciosa: o badge simplesmente não atualiza.
    }
  }

  /// Confirma uma pendência (efetiva o impacto no estoque padrão). Ao
  /// concluir, recarrega a lista de pendentes e, se a linha afetada for
  /// conhecida, o estoque de produção correspondente.
  Future<bool> confirmarPendente(int id) async {
    _erro = null;
    try {
      await _repo.confirmarPendente(id);
      await carregarPendentes();
      await carregarEstoqueAmbasLinhas();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }

  /// Recusa uma pendência, estornando o que for necessário (devolução
  /// volta pra produção de origem). Recarrega pendentes e estoque.
  Future<bool> recusarPendente(int id) async {
    _erro = null;
    try {
      await _repo.recusarPendente(id);
      await carregarPendentes();
      await carregarEstoqueAmbasLinhas();
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      notifyListeners();
      return false;
    }
  }
}