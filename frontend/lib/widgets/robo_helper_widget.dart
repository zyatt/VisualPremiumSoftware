import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/robo_helper_provider.dart';
import '../theme/app_theme.dart';
import '../rotas/app_router.dart';

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

      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      // Captura o provider aqui, onde temos certeza de que o context tem
      // acesso a ele, e o repassa explicitamente para dentro do
      // OverlayEntry. O builder do OverlayEntry roda numa posição da
      // árvore (logo abaixo do root Overlay) que pode ficar acima de
      // onde o RoboHelperProvider foi originalmente provido — sem repassar
      // assim, um context.read/watch<RoboHelperProvider>() dentro do
      // conteúdo do overlay pode falhar silenciosamente ou pegar uma
      // instância diferente, quebrando o encerrarTour() disparado por ESC.
      final helperProvider = context.read<RoboHelperProvider>();
      _overlayEntry = OverlayEntry(
        builder: (_) => ChangeNotifierProvider<RoboHelperProvider>.value(
          value: helperProvider,
          child: const _RoboHelperContent(),
        ),
      );
      overlay.insert(_overlayEntry!);

      setState(() {});
    } else {
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() {});
    }
  }

  @override
  void dispose() {

    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tourAtivo = context.watch<RoboHelperProvider>().tourAtivo;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sincronizarOverlay(tourAtivo);
    });

    return _promovidoParaOverlay
        ? const SizedBox.shrink()
        : const _RoboHelperContent();
  }
}

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

  RoboTourStop? _ultimaParadaMedida;
  int _remedicoesRestantes = 0;

  // ESC precisa encerrar o tour mesmo quando um diálogo do próprio tour
  // está aberto por cima (ex.: "Adicionar Itens"). Diálogos no Flutter
  // criam seu próprio FocusScopeNode isolado por rota, então um
  // FocusNode/KeyboardListener local deste overlay nunca ganha foco
  // enquanto o diálogo estiver na tela — o ESC simplesmente não chegava
  // até aqui. Um handler no HardwareKeyboard global captura a tecla
  // independente de qual widget está com foco no momento.
  bool _onGlobalKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    late final RoboHelperProvider helper;
    try {
      helper = context.read<RoboHelperProvider>();
    } catch (_) {
      return false;
    }
    if (!helper.tourAtivo) return false;
    helper.encerrarTour();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.of(context).size;
    final helper = context.watch<RoboHelperProvider>();

    final Offset posicaoBase = Offset(
      tela.width - 16 - _tamanho / 2,
      tela.height - 16 - _tamanho - _espacoAteChat - _tamanho / 2,
    );

    Rect? highlightRect;
    bool encerrarTourPorRotaEscondida = false;

    bool aguardandoAlvo = false;

    if (helper.tourAtivo && helper.paradaAtual != null) {
      final key = helper.paradaAtual!.key;
      final ctx = key.currentContext;

      if (ctx == null || !ctx.mounted) {
        aguardandoAlvo = true;
      } else {

        ModalRoute<dynamic>? rota;
        try {
          rota = ModalRoute.of(ctx);
        } catch (_) {
          aguardandoAlvo = true;
        }
        if (aguardandoAlvo) {

        } else {

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

          aguardandoAlvo = true;
        }
        }
      }

      if (aguardandoAlvo) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else if (helper.paradaAtual != _ultimaParadaMedida) {

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

        if (mounted && !context.read<RoboHelperProvider>().navegando) {
          context.read<RoboHelperProvider>().encerrarTour();
        }
      });
    }

    double balaoLeft;
    double balaoTop;
    if (highlightRect != null) {
      balaoLeft = highlightRect.left;
      balaoTop = highlightRect.bottom + 16;
      if (balaoTop + _alturaBalaoEstimada > tela.height - 8) {

        balaoTop = highlightRect.top - _alturaBalaoEstimada - 16;
      }
    } else {
      balaoLeft = posicaoBase.dx + _tamanho / 2 + 8;
      balaoTop = posicaoBase.dy - _tamanho / 2;
    }
    balaoLeft = balaoLeft.clamp(8.0, tela.width - _larguraBalao - 8);
    balaoTop = balaoTop.clamp(8.0, tela.height - _alturaBalaoEstimada - 8);

    final Offset alvoFinal =
        helper.oculto ? Offset(tela.width - _larguraSeta / 2, posicaoBase.dy) : posicaoBase;

    return Stack(
      children: [

        if (helper.tourAtivo && !encerrarTourPorRotaEscondida)
          Positioned.fill(
            child: _HighlightOverlay(
              highlightRect: highlightRect,

              onAvancar: helper.navegando ? (() async {}) : helper.proximaParada,
            ),
          ),

        if (helper.tourAtivo && !encerrarTourPorRotaEscondida)
          const Positioned(
            left: 16,
            top: 16,
            child: _HintEsc(),
          ),

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

              desabilitado: helper.navegando,
              onAnterior: () => helper.paradaAnterior(),
              onProximo: () => helper.proximaParada(),
              onFechar: () => helper.encerrarTour(),
            ),
          ),

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
    );
  }
}

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

class _HighlightOverlay extends StatelessWidget {
  final Rect? highlightRect;
  final Future<void> Function() onAvancar;
  const _HighlightOverlay({this.highlightRect, required this.onAvancar});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(

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

      canvas.drawRect(fullRect, Paint()..color = Colors.black.withValues(alpha: 0.28));
      return;
    }

    const pad = 6.0;
    final hRect = rect!.inflate(pad);
    final rrect = RRect.fromRectAndRadius(hRect, const Radius.circular(12));

    final path = Path()
      ..addRect(fullRect)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.30));

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

    // Quando o editor está sobreposto, o menu Dúvidas deve mostrar apenas
    // as opções pertinentes ao editor (não as da listagem por baixo, ex.
    // "Como fazer uma ordem de compra"). Cada RoboHelpOption declara
    // explicitamente (visivelNoEditorSobreposto) se pertence ao editor;
    // sem isso, uma lista de títulos fixa aqui vazava entre páginas
    // diferentes (títulos de uma tela apareciam, ou faltavam, em outra).
    final opcoes = helper.telaSobrepostaAtiva
        ? helper.opcoesAtuais.where((o) => o.visivelNoEditorSobreposto).toList()
        : helper.opcoesAtuais;
    final box = context.findRenderObject() as RenderBox?;
    final posBase = box?.localToGlobal(Offset.zero) ?? Offset.zero;

    final navigatorContext = AppRouter.rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;

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

class _BalaoDica extends StatelessWidget {
  final String texto;
  final bool ehPrimeira;
  final bool ehUltima;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;
  final VoidCallback onFechar;

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