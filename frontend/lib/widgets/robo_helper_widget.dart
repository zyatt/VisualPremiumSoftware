import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/robo_helper_provider.dart';
import '../theme/app_theme.dart';
import '../rotas/app_router.dart';

/// Widget "de verdade" do robô — fica no Stack local do AppShell (entra
/// ANTES do ChatFloatingWidget na ordem dos children, então nunca sobrepõe
/// a janela de chat). Isso resolve dois problemas: o robô nunca aparece
/// fora do AppShell (loading, login), e nunca fica por cima do chat.
///
/// Só que isso sozinho reintroduziria o bug de dialogs (ex.: "Novo
/// Material") cobrindo o balão do tour — showDialog abre no Overlay do
/// Navigator raiz por padrão, acima de qualquer coisa no Stack local do
/// AppShell. Por isso, enquanto o tour estiver ativo, este widget se
/// "esconde" (retorna vazio aqui) e promove seu conteúdo real para um
/// OverlayEntry inserido no Overlay raiz (mesmo padrão do WelcomeBanner) —
/// aí sim o balão/overlay do tour fica acima de qualquer dialog. Quando o
/// tour termina, o OverlayEntry é removido e o robô volta a aparecer aqui,
/// na posição normal (atrás do chat).
class RoboHelperWidget extends StatefulWidget {
  const RoboHelperWidget({super.key});

  @override
  State<RoboHelperWidget> createState() => _RoboHelperWidgetState();
}

class _RoboHelperWidgetState extends State<RoboHelperWidget> {
  OverlayEntry? _overlayEntry;
  bool _promovidoParaOverlay = false;

  void _sincronizarOverlay(bool tourAtivo) {
    if (tourAtivo == _promovidoParaOverlay) return;
    _promovidoParaOverlay = tourAtivo;

    if (tourAtivo) {
      // Promove: cria o OverlayEntry no Overlay raiz, com o conteúdo real.
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      _overlayEntry = OverlayEntry(
        builder: (_) => const _RoboHelperContent(),
      );
      overlay.insert(_overlayEntry!);
      // Reconstrói este widget "vazio" pra não desenhar o robô duas vezes
      // (uma aqui, outra no Overlay) enquanto o tour estiver ativo.
      setState(() {});
    } else {
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Se o AppShell for desmontado com o tour ainda ativo (ex.: logout no
    // meio do tour), remove o entry pra não vazar — senão o balão ficaria
    // preso no Overlay raiz apontando pra uma tela que não existe mais.
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tourAtivo = context.watch<RoboHelperProvider>().tourAtivo;
    // addPostFrameCallback: evita inserir/remover o OverlayEntry no meio
    // deste build (mutar a árvore de outro Overlay durante um build em
    // andamento pode disparar asserts do framework).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sincronizarOverlay(tourAtivo);
    });

    // Enquanto promovido pro Overlay raiz, este widget fica "vazio" — quem
    // está de fato na tela é o OverlayEntry. Fora do tour, o conteúdo mora
    // aqui mesmo (posição normal, atrás do chat).
    return _promovidoParaOverlay
        ? const SizedBox.shrink()
        : const _RoboHelperContent();
  }
}

// ─── Conteúdo real do robô (ícone + balão + overlay de destaque) ──────────
class _RoboHelperContent extends StatefulWidget {
  const _RoboHelperContent();

  @override
  State<_RoboHelperContent> createState() => _RoboHelperContentState();
}

class _RoboHelperContentState extends State<_RoboHelperContent> {
  static const double _tamanho = 56;
  static const double _espacoAteChat = 12;
  static const double _larguraSeta = 28;
  static const double _larguraBalao = 240;
  static const double _alturaBalaoEstimada = 130;

  final FocusNode _focusNode = FocusNode();
  RoboTourStop? _ultimaParadaMedida;
  int _remedicoesRestantes = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.of(context).size;
    final helper = context.watch<RoboHelperProvider>();

    // Dá foco ao helper sempre que o tour estiver ativo, pra que o ESC
    // funcione sem precisar que o usuário clique em algo antes.
    if (helper.tourAtivo && !_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }

    // Posição fixa do robô fora do tour: canto inferior direito, sempre
    // acima da bolha de chat.
    final Offset posicaoBase = Offset(
      tela.width - 16 - _tamanho / 2,
      tela.height - 16 - _tamanho - _espacoAteChat - _tamanho / 2,
    );

    // Calcula rect do elemento em destaque (usado só pelo balão e pelo
    // recorte do overlay — o robô permanece parado no canto).
    Rect? highlightRect;
    bool encerrarTourPorRotaEscondida = false;
    // true quando a parada atual aponta pra uma key que ainda não existe
    // neste frame (ex.: aoEntrar acabou de abrir um dialog que só termina
    // de montar no próximo frame). Nesse intervalo o balão fica invisível
    // em vez de "teleportar" pro canto (posição de fallback) e depois pro
    // alvo real — evita o salto visual perto do robô/interrogação.
    bool aguardandoAlvo = false;

    if (helper.tourAtivo && helper.paradaAtual != null) {
      final key = helper.paradaAtual!.key;
      final ctx = key.currentContext;
      // ctx.mounted é essencial aqui: durante uma transição de
      // paradaAnterior()/proximaParada() (helper.navegando == true), a
      // key.currentContext pode continuar apontando, POR UM FRAME, para o
      // Element do dialog ANTIGO, que já está desativado (saindo da árvore
      // via animação de pop) mas ainda não foi coletado. Chamar
      // ModalRoute.of(ctx) ou ctx.findRenderObject() sobre um Element
      // desativado é exatamente o que dispara "Looking up a deactivated
      // widget's ancestor is unsafe" — então tratamos esse caso igual a
      // "alvo ainda não existe" em vez de tentar ler ancestrais dele.
      if (ctx == null || !ctx.mounted) {
        aguardandoAlvo = true;
      } else {
        // A página com essa chave pode continuar "montada" mesmo depois
        // que o usuário navegou pra outro lugar (ex.: Navigator.push
        // interno mantém a tela anterior viva, só escondida por baixo).
        // Se a rota dessa chave não for mais a rota do topo, o alvo do
        // tour não está realmente visível — encerra o tour em vez de
        // continuar apontando pra ele "através" da tela nova.
        //
        // IMPORTANTE: `ctx.mounted` sozinho NÃO garante que dar
        // dependOnInheritedWidgetOfExactType (usado por ModalRoute.of)
        // seja seguro aqui. `Element.mounted` é `true` em QUALQUER estado
        // exceto "defunct" — isso inclui o estado "inactive", que é
        // exatamente o estado do dialog antigo enquanto ele está sendo
        // desmontado (entre deactivate() e unmount(), durante a animação
        // de pop). Só o estado "active" permite lookup de ancestral, e
        // esse estado não é exposto publicamente pelo Element — por isso
        // a única forma robusta de lidar com essa janela é tentar o
        // lookup e capturar o erro, tratando como "alvo indisponível
        // neste frame" em vez de deixar a exceção subir e derrubar o
        // build inteiro do robô.
        ModalRoute<dynamic>? rota;
        try {
          rota = ModalRoute.of(ctx);
        } catch (_) {
          aguardandoAlvo = true;
        }
        if (aguardandoAlvo) {
          // não faz nada — cai direto pro bloco de aguardandoAlvo abaixo
        } else {
        // Usamos isActive (ainda existe na pilha) em vez de isCurrent (é o
        // topo da pilha) porque o tour abre um dialog por cima do outro de
        // propósito (ex.: "Selecionar Material" sobre "Nova Solicitação").
        // Nesses casos a rota de baixo deixa de ser isCurrent mas continua
        // isActive — encerrar o tour aqui seria o bug de "a dica para".
        // Só encerramos quando a rota realmente saiu da pilha (isActive
        // == false), ou seja, quando o usuário de fato navegou pra outro
        // lugar e a tela/dialog original não existe mais de verdade.
        //
        // EXCEÇÃO CRÍTICA: enquanto `helper.navegando` for true, o
        // provider está no meio de um `aoSair`/`aoEntrar` (ex.:
        // `paradaAnterior()` fechando o dialog de fornecedores para
        // reabri-lo na parada anterior). Durante essa transição, a
        // `key.currentContext` ainda aponta pro dialog ANTIGO, que está
        // literalmente saindo da árvore (animação de pop) — nesse instante
        // sua rota passa por `isActive == false` de forma passageira e
        // ESPERADA, não porque o usuário "navegou pra outro lugar" de
        // verdade. Antes desta checagem, esse instante disparava
        // `encerrarTour()` diretamente daqui (postFrameCallback abaixo),
        // concorrendo com o `paradaAnterior()` que ainda estava em
        // andamento — o resultado observado era clicar "Anterior" no
        // dialog "Adicionar Fornecedores" e o tour inteiro morrer (editor
        // e aba fechados) em vez de voltar para a parada "Buscar
        // fornecedor". Ignorar essa checagem enquanto `navegando` é true
        // deixa o próprio `paradaAnterior()` terminar sua transição em paz;
        // se o alvo realmente não existir mais depois disso, o próximo
        // build (já com `navegando == false`) volta a aplicar a checagem
        // normalmente.
        if (rota != null && !rota.isActive && !helper.navegando) {
          encerrarTourPorRotaEscondida = true;
        } else if (rota == null || rota.isActive) {
          RenderBox? box;
          try {
            box = ctx.findRenderObject() as RenderBox?;
          } catch (_) {
            box = null;
          }
          if (box != null && box.hasSize) {
            final posGlobal = box.localToGlobal(Offset.zero);
            highlightRect = posGlobal & box.size;
          } else {
            aguardandoAlvo = true;
          }
        } else {
          // rota inativa mas helper.navegando é true: trata como "aguardando
          // alvo" (sem highlight neste frame) em vez de medir/encerrar —
          // o próximo frame, já com a navegação concluída, vai reavaliar
          // com a key nova (key é resolvida a cada leitura, ver
          // RoboTourStop._chave).
          aguardandoAlvo = true;
        }
        }
      }
      // Se o alvo ainda não existe neste frame — normalmente porque a
      // parada acabou de abrir um dialog (via aoEntrar) que só termina de
      // montar no próximo frame — agendamos um postFrameCallback que
      // refaz o build assim que o frame seguinte terminar. Repete sozinho
      // (um setState local, sem tocar no provider) até o RenderBox da key
      // finalmente existir. Enquanto isso, aguardandoAlvo mantém o balão
      // oculto (ver mais abaixo) em vez de desenhá-lo na posição de
      // fallback do canto, evitando o salto visual perto do robô.
      if (aguardandoAlvo) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else if (helper.paradaAtual != _ultimaParadaMedida) {
        // Primeiro frame em que o alvo foi encontrado nesta parada: agenda
        // mais algumas remedições (a posição pode mudar por animação do
        // teclado, do dialog, etc. mesmo depois do RenderBox já existir).
        _ultimaParadaMedida = helper.paradaAtual;
        _remedicoesRestantes = 6;
      }
      if (_remedicoesRestantes > 0) {
        _remedicoesRestantes--;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _ultimaParadaMedida = null;
      _remedicoesRestantes = 0;
    }

    if (encerrarTourPorRotaEscondida) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Reconfirma `navegando` aqui também (e não só na checagem acima):
        // entre o build que setou essa flag e este callback rodar, uma
        // transição de paradaAnterior()/proximaParada() pode ter começado.
        if (mounted && !context.read<RoboHelperProvider>().navegando) {
          context.read<RoboHelperProvider>().encerrarTour();
        }
      });
    }

    // Posição do balão: logo ABAIXO do item em destaque (evita cortar na
    // borda direita da tela quando o botão está perto dela, e não fica
    // sobrepondo o próprio botão). Se não couber embaixo, sobe pra cima.
    double balaoLeft;
    double balaoTop;
    if (highlightRect != null) {
      balaoLeft = highlightRect.left;
      balaoTop = highlightRect.bottom + 16;
      if (balaoTop + _alturaBalaoEstimada > tela.height - 8) {
        // Não cabe embaixo — mostra acima do item.
        balaoTop = highlightRect.top - _alturaBalaoEstimada - 16;
      }
    } else {
      balaoLeft = posicaoBase.dx + _tamanho / 2 + 8;
      balaoTop = posicaoBase.dy - _tamanho / 2;
    }
    balaoLeft = balaoLeft.clamp(8.0, tela.width - _larguraBalao - 8);
    balaoTop = balaoTop.clamp(8.0, tela.height - _alturaBalaoEstimada - 8);

    // O ícone fica sempre parado no canto inferior direito, acima da
    // bolha de chat — não acompanha o tour nem o balão de dica.
    final Offset alvoFinal =
        helper.oculto ? Offset(tela.width - _larguraSeta / 2, posicaoBase.dy) : posicaoBase;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: helper.tourAtivo,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (helper.tourAtivo) helper.encerrarTour();
        }
      },
      child: Stack(
      children: [
        // ── 1. Overlay escurecido COM highlight recortado ──────────────────
        if (helper.tourAtivo && !encerrarTourPorRotaEscondida)
          Positioned.fill(
            child: _HighlightOverlay(
              highlightRect: highlightRect,
              // Enquanto uma navegação (Anterior/Próximo) assíncrona está em
              // andamento, ignora toques no overlay/highlight também — sem
              // isso, tocar no alvo destacado durante a transição disparava
              // um proximaParada() concorrente com o clique nos botões do
              // balão, mesma causa da corrida com paradaAnterior() descrita
              // em robo_helper_provider.dart (get navegando).
              onAvancar: helper.navegando ? (() async {}) : helper.proximaParada,
            ),
          ),

        // ── 2. Hint ESC no topo esquerdo ───────────────────────────────────
        if (helper.tourAtivo && !encerrarTourPorRotaEscondida)
          const Positioned(
            left: 16,
            top: 16,
            child: _HintEsc(),
          ),

        // ── 3. Balão de dica ───────────────────────────────────────────────
        if (helper.tourAtivo &&
            helper.paradaAtual != null &&
            !encerrarTourPorRotaEscondida &&
            !aguardandoAlvo)
          Positioned(
            left: balaoLeft,
            top: balaoTop,
            width: _larguraBalao,
            child: _BalaoDica(
              texto: helper.paradaAtual!.texto,
              ehPrimeira: helper.ehPrimeiraParada,
              ehUltima: helper.ehUltimaParada,
              // Desabilita os 3 botões enquanto helper.navegando é true —
              // ver comentário em RoboHelperProvider.navegando. Isso é o
              // "limitador" pedido: evita que o usuário spamme cliques em
              // Anterior/Próximo/Fechar e dispare chamadas concorrentes que
              // corrompem o estado dos dialogs simulados pelo tour.
              desabilitado: helper.navegando,
              onAnterior: () => helper.paradaAnterior(),
              onProximo: () => helper.proximaParada(),
              onFechar: () => helper.encerrarTour(),
            ),
          ),

        // ── 4. Robô (sempre no topo do stack) ─────────────────────────────
        Positioned(
          left: helper.oculto
              ? tela.width - _larguraSeta
              : alvoFinal.dx - _tamanho / 2,
          top: alvoFinal.dy - _tamanho / 2,
          width: helper.oculto ? _larguraSeta : _tamanho,
          height: _tamanho,
          child: helper.oculto
              ? _SetaOculta(onTap: helper.mostrar)
              : _RoboBubble(tamanho: _tamanho),
        ),
      ],
      ),
    );
  }
}

// ─── Hint ESC no topo esquerdo ────────────────────────────────────────────
class _HintEsc extends StatelessWidget {
  const _HintEsc();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Text(
              'ESC',
              style: GoogleFonts.nunito(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'para sair',
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Overlay com buraco recortado no elemento em destaque ─────────────────
class _HighlightOverlay extends StatelessWidget {
  final Rect? highlightRect;
  final Future<void> Function() onAvancar;
  const _HighlightOverlay({this.highlightRect, required this.onAvancar});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // Clicar em qualquer lugar da tela avança o tour.
        onTap: onAvancar,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _HighlightPainter(rect: highlightRect),
        ),
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  final Rect? rect;
  const _HighlightPainter({this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;

    if (rect == null) {
      // Sem elemento alvo: só escurece tudo
      canvas.drawRect(fullRect, Paint()..color = Colors.black.withValues(alpha: 0.28));
      return;
    }

    // Padding ao redor do elemento destacado
    const pad = 6.0;
    final hRect = rect!.inflate(pad);
    final rrect = RRect.fromRectAndRadius(hRect, const Radius.circular(12));

    // Escurece toda a tela exceto o elemento
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.30));

    // Borda laranja brilhante ao redor do elemento destacado
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppTheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => old.rect != rect;
}

// ─── Seta de "robô oculto" ────────────────────────────────────────────────
class _SetaOculta extends StatelessWidget {
  final VoidCallback onTap;
  const _SetaOculta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(14)),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(14)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(-1, 2),
                ),
              ],
            ),
            child: const Icon(Icons.chevron_left_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─── Bolha do robô ────────────────────────────────────────────────────────
class _RoboBubble extends StatelessWidget {
  final double tamanho;
  const _RoboBubble({required this.tamanho});

  void _aoTocar(BuildContext context) {
    final helper = context.read<RoboHelperProvider>();
    if (helper.tourAtivo) {
      helper.proximaParada();
      return;
    }
    _abrirMenu(context);
  }

  void _abrirMenu(BuildContext context) {
    final helper = context.read<RoboHelperProvider>();
    // Com uma tela sobreposta ativa (ex.: OrcamentoEditorPage aberta por
    // Navigator.push por cima de OrcamentoPage), as opções registradas na
    // rota de baixo continuam em opcoesAtuais de propósito (ver
    // RoboHelperProvider.telaSobrepostaAtiva) — mas não fazem sentido no
    // menu "Dúvidas" enquanto essa tela de cima estiver visível, já que a
    // 1ª parada de cada tour aponta pra um elemento da tela de baixo. Some
    // com as opções aqui; o tour em si (se já estiver em andamento) não é
    // afetado, pois usa _paradasAtivas diretamente, não este menu.
    final opcoes = helper.telaSobrepostaAtiva
        ? const <RoboHelpOption>[]
        : helper.opcoesAtuais;
    final box = context.findRenderObject() as RenderBox?;
    final posBase = box?.localToGlobal(Offset.zero) ?? Offset.zero;

    // O RoboHelperWidget vive ACIMA do Navigator raiz (ver main.dart) —
    // fora dali para não ficar coberto por dialogs. Isso significa que o
    // `context` deste widget não tem nenhum Navigator ancestral, e
    // showMenu() precisa de um (ele empurra a rota do menu através de um
    // Navigator, mesmo com useRootNavigator: true por padrão). Por isso
    // usamos o context estável do Navigator raiz do próprio GoRouter em
    // vez do context local — mantendo a posição calculada a partir do
    // RenderBox do robô (que continua sendo o correto pra POSICIONAR o
    // menu na tela).
    final navigatorContext = AppRouter.rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;

    // RelativeRect.fromLTRB(left, top, right, bottom) informa ao Flutter a
    // distância de cada lado do RETÂNGULO ÂNCORA (não do menu) até os 4
    // lados do Overlay. O PopupMenuRoute usa esse retângulo-âncora (aqui,
    // de tamanho zero, pois top==bottom e left==right originalmente) como
    // ponto de referência e cresce o menu a partir dele, tentando não
    // estourar a tela.
    //
    // O bug original não era o `top == bottom` (isso é correto — o robô é
    // um ponto, não uma área) e sim o `right`, que estava fixo em
    // `posBase.dx` em vez de ser a distância real até a borda direita da
    // tela — isso fazia o menu, ao tentar caber no espaço "sobrando"
    // (largura da tela − right), calcular uma largura inconsistente
    // dependendo do conteúdo, e ancorar de forma imprevisível. Corrigido
    // abaixo: `right` agora é `larguraTela - posBase.dx`, a distância real
    // do robô até a borda direita — igual ao padrão usado em estoque_page.
    final larguraTela = MediaQuery.of(navigatorContext).size.width;

    showMenu<void>(
      context: navigatorContext,
      position: RelativeRect.fromLTRB(
        posBase.dx - 260,
        posBase.dy,
        larguraTela - posBase.dx,
        posBase.dy,
      ),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          height: 36,
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.question_mark_rounded,
                  size: 14,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Dúvidas',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
        if (opcoes.isEmpty)
          PopupMenuItem<void>(
            enabled: false,
            child: Text(
              'Nenhuma dica disponível para esta tela.',
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final opcao in opcoes)
            PopupMenuItem<void>(
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                Future.delayed(const Duration(milliseconds: 80), () {
                  helper.iniciarTour(helper.rotaAtual, opcao.titulo);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Icon(Icons.help_outline_rounded,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        opcao.titulo,
                        style: GoogleFonts.nunito(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<void>(
          mouseCursor: SystemMouseCursors.click,
          onTap: helper.ocultar,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Icon(Icons.visibility_off_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Ocultar assistente',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _aoTocar(context),
        child: Container(
          width: tamanho,
          height: tamanho,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            Icons.question_mark_rounded,
            size: tamanho * 0.5,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }
}

// ─── Balão de dica ────────────────────────────────────────────────────────
class _BalaoDica extends StatelessWidget {
  final String texto;
  final bool ehPrimeira;
  final bool ehUltima;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;
  final VoidCallback onFechar;

  /// Quando true (RoboHelperProvider.navegando), os 3 botões abaixo ficam
  /// visualmente esmaecidos e seus `onTap` viram no-op — é o limitador
  /// contra spam de cliques em Anterior/Próximo/Fechar enquanto uma
  /// navegação assíncrona anterior (que pode estar fechando/reabrindo um
  /// dialog do tour) ainda está em andamento. Ver comentário completo em
  /// RoboHelperProvider.navegando (robo_helper_provider.dart).
  final bool desabilitado;

  const _BalaoDica({
    required this.texto,
    required this.ehPrimeira,
    required this.ehUltima,
    required this.onAnterior,
    required this.onProximo,
    required this.onFechar,
    this.desabilitado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              texto,
              style: GoogleFonts.nunito(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Fechar
                MouseRegion(
                  cursor: desabilitado
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: InkWell(
                    onTap: desabilitado ? null : onFechar,
                    mouseCursor: desabilitado
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(6),
                    child: Opacity(
                      opacity: desabilitado ? 0.4 : 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Text(
                          'Fechar',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Anterior
                if (!ehPrimeira) ...[
                  MouseRegion(
                    cursor: desabilitado
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: InkWell(
                      onTap: desabilitado ? null : onAnterior,
                      mouseCursor: desabilitado
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(6),
                      child: Opacity(
                        opacity: desabilitado ? 0.4 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.5),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Anterior',
                            style: GoogleFonts.nunito(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                MouseRegion(
                  cursor: desabilitado
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: InkWell(
                    onTap: desabilitado ? null : onProximo,
                    mouseCursor: desabilitado
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(6),
                    child: Opacity(
                      opacity: desabilitado ? 0.4 : 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ehUltima ? 'Concluir' : 'Próximo',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}