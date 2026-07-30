import 'package:flutter/material.dart';

class RoboTourStop {
  // Guardada como FUNÇÃO (e não como GlobalKey já resolvida) de propósito:
  // se a key fosse resolvida uma única vez aqui, no momento em que a lista
  // de paradas é montada em _registrarAjudaRobo(), qualquer key que dependa
  // de um estado que só muda DEPOIS — dentro do `aoEntrar` deste mesmo
  // passo ou de um anterior, ex.: um getter tipo
  // `_exibirFicticio ? _keyFicticio : _keyReal` — ficaria "congelada" com o
  // valor de quando o tour começou. Como `aoEntrar` roda de forma
  // assíncrona e só DEPOIS altera esse estado (ex.: setState ligando o
  // card fictício), a key certa passaria a existir na árvore só depois que
  // este RoboTourStop já tivesse sido lido pelo provider — resultando em
  // `key.currentContext == null` para sempre e o highlight/balão nunca
  // aparecendo, mesmo com o alvo certinho já montado na tela. Resolver a
  // key em `_chave()` a cada leitura (via o getter [key] abaixo) garante
  // que o widget sempre veja o valor mais atual do getter/estado no
  // momento em que efetivamente tenta localizar o alvo.
  final GlobalKey Function() _chave;
  final String texto;
  final Offset offset;

  /// Roda sempre que o tour chega (ou volta) a esta parada, antes de tentar
  /// localizar [key] na tela. Útil pra abrir/fechar um dialog/tela
  /// intermediária cujos campos só existem depois dessa ação.
  ///
  /// Pode ser assíncrono: o tour aguarda a conclusão do Future antes de
  /// notificar os listeners (evita que o highlight meça um widget que ainda
  /// não montou, ou que um dialog antigo ainda em animação de saída
  /// interfira na abertura do próximo).
  final Future<void> Function()? aoEntrar;

  /// Roda quando o usuário aperta "Anterior" e está saindo DESTA parada,
  /// antes de retroceder para a parada anterior. Útil para desfazer ações
  /// feitas por `aoEntrar` (ex.: fechar um dialog que foi aberto, remover
  /// um item fictício da lista, etc.) e garantir que a parada anterior
  /// apareça no estado correto.
  final Future<void> Function()? aoSair;

  /// Key do widget-alvo desta parada, resolvida agora — não no momento em
  /// que o RoboTourStop foi criado.
  GlobalKey get key => _chave();

  const RoboTourStop({
    required GlobalKey Function() key,
    required this.texto,
    this.offset = const Offset(0, 0),
    this.aoEntrar,
    this.aoSair,
  }) : _chave = key;
}

class RoboHelpOption {
  final String titulo;
  final List<RoboTourStop> paradas;

  /// Chamado sempre que o tour desta opção é encerrado (ESC, botão
  /// "Fechar" ou "Concluir" na última parada) — independente de qual
  /// parada estava ativa no momento. Diferente do `aoSair` de cada
  /// RoboTourStop (que só desfaz o que a própria parada abriu), este
  /// callback existe para fechar qualquer coisa "maior" que o tour tenha
  /// aberto e que sobreviva à parada em que foi criada — no caso do tour
  /// "Como criar um orçamento", a tela OrcamentoEditorPage inteira, aberta
  /// via Navigator.push na 2ª parada e ainda aberta quando o usuário
  /// encerra o tour em qualquer parada posterior (3ª a 8ª, todas "dentro"
  /// do editor). Sem isso, encerrar o tour no meio dessas paradas fechava
  /// o dialog daquela parada específica mas deixava o editor aberto,
  /// preso na tela de demonstração sem highlight nenhum.
  final Future<void> Function()? aoEncerrar;

  const RoboHelpOption({
    required this.titulo,
    required this.paradas,
    this.aoEncerrar,
  });
}

class RoboHelperProvider extends ChangeNotifier {
  bool _oculto = false;
  bool get oculto => _oculto;

  void ocultar() { _oculto = true; notifyListeners(); }
  void mostrar() { _oculto = false; notifyListeners(); }
  void alternarOculto() { _oculto = !_oculto; notifyListeners(); }

  // ── Tela sobreposta (Navigator.push por cima, sem trocar de rota) ────────
  // Algumas telas (ex.: OrcamentoEditorPage) são abertas via Navigator.push
  // por CIMA de uma página que já registrou opções de ajuda, mas de
  // propósito NÃO chamam notificarRota — isso permite que um tour iniciado
  // na página de baixo continue funcionando enquanto o usuário navega para
  // a tela de cima (ver comentário em _registrarAjudaRobo/
  // _anexarParadasDoEditorAoTour nas duas páginas de orçamento).
  //
  // O efeito colateral disso é que o menu "Dúvidas" do robô, que lê
  // `opcoesAtuais` (atrelado à ROTA, não à tela realmente visível), continua
  // oferecendo a dica da página de baixo mesmo com a tela de cima aberta —
  // o que não faz sentido quando o tour não está em andamento (o usuário
  // não pode iniciar ali um tour cuja 1ª parada é um botão que não existe
  // nesta tela). Esta flag permite que a tela de cima avise "estou por
  // cima, esconda as opções de baixo enquanto isso" sem precisar mexer no
  // mecanismo de rota/tour em si.
  bool _telaSobrepostaAtiva = false;
  bool get telaSobrepostaAtiva => _telaSobrepostaAtiva;

  void definirTelaSobreposta(bool ativa) {
    if (_telaSobrepostaAtiva == ativa) return;
    _telaSobrepostaAtiva = ativa;
    notifyListeners();
  }

  // ── Rota atual ──────────────────────────────────────────────────────────────
  // Cada página notifica sua rota ao montar. O widget usa isso para saber
  // se deve mostrar opções ou limpar o tour ao trocar de página.
  String _rotaAtual = '';

  String get rotaAtual => _rotaAtual;

  void notificarRota(String rota) {
    if (_rotaAtual == rota) return;
    _rotaAtual = rota;
    // Troca de página encerra o tour, mas NÃO apaga as opções já
    // registradas por outras rotas — elas ficam guardadas em
    // _opcoesPorRota e voltam a aparecer sozinhas quando o usuário
    // retornar à página (útil quando a página vive dentro de um
    // StatefulShellRoute/IndexedStack e seu initState não roda de novo).
    _encerrarTourInterno();
    notifyListeners();
  }

  // ── Opções contextuais ──────────────────────────────────────────────────────
  // Guardadas por rota para sobreviver a idas-e-vindas entre páginas que
  // ficam vivas num IndexedStack (onde initState só roda uma vez).
  final Map<String, List<RoboHelpOption>> _opcoesPorRota = {};

  List<RoboHelpOption> get opcoesAtuais =>
      _opcoesPorRota[_rotaAtual] ?? const [];

  /// Lê as opções registradas para uma rota específica, independente de
  /// qual seja a rota atualmente ativa (_rotaAtual). Diferente de
  /// [opcoesAtuais] (que só enxerga a rota corrente), este getter permite
  /// que uma tela consulte/atualize as próprias opções registradas em sua
  /// rota "dona" mesmo que o usuário já tenha navegado para outro lugar —
  /// útil no dispose() de telas empurradas por Navigator.push (que não
  /// trocam _rotaAtual) para truncar paradas de tour que elas mesmas
  /// anexaram, sem apagar a opção inteira nem depender de coincidência
  /// com a rota atual.
  List<RoboHelpOption> opcoesDaRota(String rota) =>
      _opcoesPorRota[rota] ?? const [];

  void registrarOpcoes(String rota, List<RoboHelpOption> opcoes) {
    // Recebe a rota explicitamente (em vez de usar _rotaAtual) porque
    // páginas dentro de um IndexedStack continuam rebuildando em segundo
    // plano mesmo depois que o usuário navegou pra outra tela (ex.: por
    // causa de polling/streams). Se a escrita dependesse de _rotaAtual,
    // uma dessas rebuilds tardias acabaria registrando as opções da
    // página antiga na rota ATUAL (a que o usuário está vendo agora),
    // fazendo a dica errada aparecer em outra página.
    _opcoesPorRota[rota] = opcoes;
    if (rota == _rotaAtual) notifyListeners();
  }

  void limparOpcoes(String rota) {
    _opcoesPorRota.remove(rota);
    if (rota == _rotaAtual) notifyListeners();
  }

  // ── Tour guiado ─────────────────────────────────────────────────────────────
  // Guardamos apenas ROTA + TÍTULO da opção em andamento — NÃO a lista de
  // RoboTourStop em si. Isso é de propósito: telas como
  // OrcamentoEditorPage anexam novas paradas à mesma opção DEPOIS que o
  // tour já começou (ver _anexarParadasDoEditorAoTour), substituindo a
  // lista guardada em _opcoesPorRota por uma mais longa. Se
  // _tourAtivo fosse a própria List<RoboTourStop> (uma cópia da
  // referência que existia no momento do clique em "Iniciar tour"), ele
  // ficaria "congelado" com o tamanho de então — no caso do orçamento,
  // só as 2 paradas que já existiam antes do editor ser aberto e anexar
  // o resto. O resultado era o tour ficar preso na 2ª parada (campo
  // Nome) pra sempre, sempre mostrando "Concluir" ali, porque _tourAtivo
  // nunca era resincronizado com as paradas novas registradas em
  // _opcoesPorRota. Resolver [_paradasAtivas] a cada leitura (getter
  // abaixo) garante que o tour sempre enxergue a lista mais atual.
  String? _tourRota;
  String? _tourTitulo;
  int _passoAtual = 0;

  List<RoboTourStop> get _paradasAtivas {
    if (_tourRota == null || _tourTitulo == null) return const [];
    final opcoes = _opcoesPorRota[_tourRota] ?? const [];
    final opcao = opcoes.where((o) => o.titulo == _tourTitulo).firstOrNull;
    return opcao?.paradas ?? const [];
  }

  bool get tourAtivo => _tourRota != null;
  int get passoAtual => _passoAtual;

  RoboTourStop? get paradaAtual {
    final paradas = _paradasAtivas;
    return (_tourRota != null && _passoAtual < paradas.length)
        ? paradas[_passoAtual]
        : null;
  }

  bool get ehUltimaParada {
    final paradas = _paradasAtivas;
    return _tourRota != null &&
        paradas.isNotEmpty &&
        _passoAtual == paradas.length - 1;
  }

  bool get ehPrimeiraParada => _passoAtual == 0;

  // Impede que cliques rápidos em "Próximo"/"Anterior" disparem aoEntrar
  // concorrentes enquanto o anterior ainda está em progresso.
  bool _navegando = false;

  /// Exposto para a UI (robo_helper_widget.dart) desabilitar os botões
  /// "Anterior"/"Próximo"/"Fechar" enquanto uma navegação assíncrona está
  /// em andamento. Antes desta flag ser pública, nada impedia o usuário de
  /// clicar de novo em "Anterior" enquanto o `aoSair`/`aoEntrar` do clique
  /// anterior ainda estava fechando/reabrindo um dialog (ex.: o dialog de
  /// fornecedores) — o segundo clique era silenciosamente ignorado aqui
  /// dentro (`if (_navegando) return`), mas a UI não dava nenhum feedback
  /// disso, então o usuário continuava clicando. Pior: como
  /// `_fecharDialogFornecedorSemVincular`/`_abrirDialogFornecedorTour`
  /// mexem nas mesmas flags (`_dialogFornecedorTourAberto`) e dependem de
  /// callbacks assíncronos do próprio Navigator (`showDialog(...).then(...)`
  /// disparando bem depois do `maybePop`), cliques extras durante essa
  /// janela conseguiam fazer o `.then()` de uma chamada antiga sobrescrever
  /// o estado que a chamada nova acabou de montar — resultando em
  /// `_paradaEm()` não encontrar mais a parada esperada e o tour se
  /// encerrar sozinho (voltando para a OrcamentoPage) em vez de retroceder
  /// para o campo "Buscar fornecedor". Com os botões desabilitados durante
  /// `_navegando`, essa sobreposição de cliques deixa de ser possível.
  bool get navegando => _navegando;

  /// Inicia o tour da opção [titulo] registrada na rota [rota]. A partir
  /// daqui as paradas são sempre lidas ao vivo de _opcoesPorRota (ver
  /// [_paradasAtivas]) — se alguma tela anexar mais paradas à mesma opção
  /// enquanto o tour está em andamento, elas passam a valer no próximo
  /// avanço, sem precisar reiniciar o tour.
  Future<void> iniciarTour(String rota, String titulo) async {
    final opcoes = _opcoesPorRota[rota] ?? const [];
    final opcao = opcoes.where((o) => o.titulo == titulo).firstOrNull;
    if (opcao == null || opcao.paradas.isEmpty) return;
    _tourRota = rota;
    _tourTitulo = titulo;
    _passoAtual = 0;
    notifyListeners();
    await _chamarAoEntrarComTimeout(opcao.paradas[0].aoEntrar);
  }

  // Teto de segurança para qualquer `aoEntrar` ou `aoSair`: nenhuma parada
  // deveria legitimamente demorar mais que isso para preparar seu alvo
  // (abrir um dialog, aguardar um frame, etc.). Existe para o caso de algum
  // callback futuro voltar a esperar por algo de vida longa (ex.: um
  // Navigator.push aguardando o usuário fechar a tela) — sem este teto,
  // isso prende `_navegando = true` para sempre e, como o provider é
  // global, passa a bloquear Próximo/Anterior em QUALQUER outra página
  // que use o tour, mesmo depois de trocar de rota.
  static const _timeoutAoEntrar = Duration(seconds: 5);

  Future<void> _chamarAoEntrarComTimeout(Future<void> Function()? aoEntrar) async {
    if (aoEntrar == null) return;
    try {
      await aoEntrar().timeout(_timeoutAoEntrar);
    } catch (_) {
      // Ignora timeout/erro do aoEntrar: melhor deixar o tour seguir
      // (mesmo que o highlight desta parada específica fique impreciso)
      // do que travar o robô inteiro para o resto da sessão.
    }
  }

  Future<void> _chamarAoSairComTimeout(Future<void> Function()? aoSair) async {
    if (aoSair == null) return;
    try {
      await aoSair().timeout(_timeoutAoEntrar);
    } catch (_) {
      // Mesma lógica do aoEntrar: ignora erros/timeout para não travar
      // a navegação do tour.
    }
  }

  Future<void> proximaParada() async {
    if (_tourRota == null || _navegando) return;
    final paradas = _paradasAtivas;
    if (paradas.isEmpty) return;
    if (_passoAtual < paradas.length - 1) {
      _navegando = true;
      try {
        _passoAtual++;
        notifyListeners();
        // Relê as paradas depois do notifyListeners acima: um `aoEntrar`
        // (ainda não chamado aqui, mas o de um passo anterior recente pode
        // ter concluído de forma assíncrona só agora) pode ter disparado um
        // registrarOpcoes que troca/encolhe a lista — nunca confiamos no
        // tamanho lido antes do notifyListeners. _paradaEm() valida os
        // limites e devolve null se o índice não existir mais.
        final parada = _paradaEm(_passoAtual);
        if (parada != null) {
          await _chamarAoEntrarComTimeout(parada.aoEntrar);
        } else {
          // A parada para a qual avançamos deixou de existir (lista foi
          // truncada/substituída por outra tela enquanto navegávamos) —
          // encerra o tour de forma segura em vez de deixar o índice
          // apontando para "lugar nenhum".
          _encerrarTourInterno();
        }
      } finally {
        _navegando = false;
        // Notifica de novo para o highlight medir a key após o aoEntrar
        // terminar (ex.: dialog já aberto e montado, ou novas paradas
        // recém-anexadas por uma tela que acabou de ser aberta).
        notifyListeners();
      }
    } else {
      // "Concluir": passa pelo mesmo encerrarTour() que ESC/"Fechar" usam,
      // para que o aoSair da última parada também rode aqui e feche
      // qualquer dialog que ainda esteja aberto (ex.: dialog de preço).
      await encerrarTour();
    }
  }

  /// Lê a parada no índice [i] da lista ATUAL de `_paradasAtivas`,
  /// devolvendo null se o índice não existir (lista vazia, encolhida, ou
  /// substituída por outra rota/tela enquanto um `aoEntrar`/`aoSair`
  /// assíncrono estava em andamento). Usado no lugar da indexação direta
  /// (`_paradasAtivas[i]`) sempre que o índice for lido DEPOIS de um
  /// `await`, para nunca lançar RangeError.
  RoboTourStop? _paradaEm(int i) {
    final paradas = _paradasAtivas;
    if (i < 0 || i >= paradas.length) return null;
    return paradas[i];
  }

  Future<void> paradaAnterior() async {
    if (_tourRota == null || _passoAtual == 0 || _navegando) return;
    _navegando = true;
    try {
      // PRIMEIRO chama aoSair da parada ATUAL (antes de decrementar
      // _passoAtual) para desfazer o que aoEntrar dela fez (ex.: fechar
      // dialog aberto, remover item fictício, etc.).
      final paradaAtualAntesDeMudar = _paradaEm(_passoAtual);
      await _chamarAoSairComTimeout(paradaAtualAntesDeMudar?.aoSair);

      // O aoSair acima pode ter fechado uma tela inteira (ex.: o editor de
      // orçamento) cujo dispose() registra de volta uma lista de paradas
      // mais curta (ou até vazia) para a mesma rota — então NUNCA
      // confiamos que o índice antigo ainda é válido depois do await.
      final novoIndice = _passoAtual - 1;
      final paradaAnterior = _paradaEm(novoIndice);
      if (paradaAnterior == null) {
        // A lista mudou de baixo do tour (ficou menor que o esperado) —
        // encerra com segurança em vez de indexar fora dos limites.
        _encerrarTourInterno();
        return;
      }
      // SÓ DEPOIS retrocede o índice e chama aoEntrar da parada anterior.
      _passoAtual = novoIndice;
      notifyListeners();
      await _chamarAoEntrarComTimeout(paradaAnterior.aoEntrar);
    } finally {
      _navegando = false;
      notifyListeners();
    }
  }

  void _encerrarTourInterno() {
    _tourRota = null;
    _tourTitulo = null;
    _passoAtual = 0;
  }

  /// Encerra o tour a partir de qualquer ponto: ESC, botão "Fechar" e
  /// "Concluir" (proximaParada() na última parada) chamam este método.
  ///
  /// ANTES desta correção, encerrarTour() só zerava o estado do tour sem
  /// rodar o `aoSair` da parada em que o usuário estava — então, se o
  /// usuário fechasse o tour bem no meio de uma parada que tinha aberto um
  /// dialog (ex.: "Editar Material") ou até uma tela inteira via
  /// Navigator.push (ex.: OrcamentoEditorPage, aberta por
  /// _abrirEditorTour), esse dialog/tela ficava aberto na tela, por cima de
  /// tudo, mesmo com o tour "encerrado" — o usuário se via preso numa tela
  /// de demonstração sem highlight nenhum indicando o que fazer.
  ///
  /// Agora, antes de zerar o estado, chamamos o `aoSair` da parada atual
  /// (com o mesmo timeout de segurança usado em proximaParada/
  /// paradaAnterior) — cada `aoSair` já sabe fechar o que a respectiva
  /// `aoEntrar` abriu (dialog de fornecedor, dialog de preço, ou a própria
  /// tela do editor, no caso da 2ª parada). Isso garante que encerrar o
  /// tour a qualquer momento sempre devolve o usuário para o estado normal
  /// da página, com qualquer dialog fechado.
  Future<void> encerrarTour() async {
    if (_tourRota == null) return;
    if (_navegando) {
      // Uma navegação (Próximo/Anterior) já está em andamento — apenas
      // marca para encerrar assim que ela terminar, em vez de tentar rodar
      // dois aoSair concorrentes.
      _encerrarTourInterno();
      notifyListeners();
      return;
    }
    _navegando = true;
    try {
      final rota = _tourRota;
      final titulo = _tourTitulo;
      final parada = paradaAtual;
      // Primeiro desfaz o que a parada atual abriu (ex.: dialog de
      // preço/fornecedor), depois fecha qualquer coisa "maior" que a
      // opção como um todo tenha aberto (ex.: a tela do editor).
      await _chamarAoSairComTimeout(parada?.aoSair);
      // Relê rota/título/opção pelo NOME (nunca por índice) depois do
      // await acima — o aoSair pode ter trocado a lista registrada para
      // esta rota, mas a opção continua localizável pelo `titulo`.
      if (rota != null && titulo != null) {
        final opcoes = _opcoesPorRota[rota] ?? const [];
        final opcao = opcoes.where((o) => o.titulo == titulo).firstOrNull;
        await _chamarAoSairComTimeout(opcao?.aoEncerrar);
      }
    } finally {
      _navegando = false;
      _encerrarTourInterno();
      notifyListeners();
    }
  }
}