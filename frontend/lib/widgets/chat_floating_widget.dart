// lib/widgets/chat_floating_widget.dart
//
// Bolha de chat flutuante (estilo Messenger/Intercom): fica por cima do
// conteúdo da página atual, pode ser arrastada para qualquer lugar da tela
// e, ao ser tocada (sem arrastar), expande num mini-chat com lista de
// usuários e conversa. Ela é renderizada pelo AppShell, então fica visível
// em qualquer página do app (exceto na própria página /chat, pra não
// duplicar a UI).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/chat_provider.dart';
import '../models/mensagem_chat_model.dart';
import 'reacao_mensagem_picker.dart';
import 'encaminhamento_chat_card.dart';

class ChatFloatingWidget extends StatefulWidget {
  const ChatFloatingWidget({super.key});

  @override
  State<ChatFloatingWidget> createState() => _ChatFloatingWidgetState();
}

// ─── Indicador de presença (versão compacta do widget flutuante) ──────────────
class _MiniStatusDot extends StatelessWidget {
  final bool online;
  final double size;
  const _MiniStatusDot({required this.online}) : size = 10;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
      ),
    );
  }
}

/// Mesma lógica de `_formatarStatusUsuario` em chat_page.dart, duplicada
/// aqui para manter os dois arquivos de UI de chat independentes (padrão já
/// usado no arquivo para outros widgets "Mini*").
String _formatarStatusUsuarioMini(UsuarioChat usuario) {
  if (usuario.online) return 'Online';
  final ultimo = usuario.ultimoAcesso;
  if (ultimo == null) return 'Offline';
  final agora  = DateTime.now();
  final hora   = DateFormat('HH:mm').format(ultimo);
  bool mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (mesmoDia(ultimo, agora)) return 'Visto por último às $hora';
  if (mesmoDia(ultimo, agora.subtract(const Duration(days: 1)))) {
    return 'Visto ontem às $hora';
  }
  return 'Visto em ${DateFormat('dd/MM').format(ultimo)} às $hora';
}

class _ChatFloatingWidgetState extends State<ChatFloatingWidget> {
  static const double _bolhaTamanho = 56;
  static const double _painelLargura = 320;
  static const double _painelAltura = 440;

  // Centro da bolha em coordenadas absolutas da tela.
  // Expandir/minimizar sempre parte desse centro — o widget cresce
  // circularmente a partir do ponto em que o usuário clicou.
  // Inicializado na primeira build quando o tamanho da tela é conhecido.
  double? _cx;
  double? _cy;

  // Último tamanho de tela observado. Usado para detectar mudanças (ex:
  // maximizar/restaurar a janela, entrar em fullscreen, rotacionar o
  // dispositivo) e reposicionar a bolha proporcionalmente, em vez de
  // deixá-la "presa" nas coordenadas absolutas antigas.
  Size? _telaAnterior;

  bool _expandido = false;
  bool _arrastando = false;
  Offset _inicioArrastoGlobal = Offset.zero;
  double _cxAoIniciar = 0;
  double _cyAoIniciar = 0;

  // Último valor de ChatProvider.minimizarTrigger observado. Quando o
  // provider incrementa esse contador (ex: troca de usuário logado),
  // detectamos a mudança aqui e recolhemos a bolha, se estiver expandida.
  int? _ultimoMinimizarTrigger;

  // Contrapartida: último valor de ChatProvider.abrirConversaTrigger
  // observado. Ao mudar, expandimos a bolha (a conversa em si já foi
  // selecionada pelo provider antes de incrementar o trigger).
  int? _ultimoAbrirConversaTrigger;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ultimoMinimizarTrigger = context.read<ChatProvider>().minimizarTrigger;
        _ultimoAbrirConversaTrigger = context.read<ChatProvider>().abrirConversaTrigger;
      }
    });
  }

  @override
  void dispose() {
    try {
      context.read<ChatProvider>().definirWidgetFlutuanteVisivel(false);
    } catch (_) {}
    super.dispose();
  }

  void _alternarExpandido(BuildContext context) {
    setState(() => _expandido = !_expandido);
    context.read<ChatProvider>().definirWidgetFlutuanteVisivel(_expandido);
  }

  void _fechar(BuildContext context) {
    setState(() => _expandido = false);
    context.read<ChatProvider>().definirWidgetFlutuanteVisivel(false);
  }

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.of(context).size;

    // Observa o gatilho de minimizar (ex: troca de usuário logado) e
    // recolhe a bolha se estiver expandida no momento em que ele mudar.
    final minimizarTrigger = context.watch<ChatProvider>().minimizarTrigger;
    if (_ultimoMinimizarTrigger != null &&
        minimizarTrigger != _ultimoMinimizarTrigger &&
        _expandido) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fechar(context);
      });
    }
    _ultimoMinimizarTrigger = minimizarTrigger;

    // Idem, mas para o gatilho de ABRIR (expandir com uma conversa
    // específica) — disparado após encaminhar solicitação/material.
    final abrirConversaTrigger = context.watch<ChatProvider>().abrirConversaTrigger;
    if (_ultimoAbrirConversaTrigger != null &&
        abrirConversaTrigger != _ultimoAbrirConversaTrigger &&
        !_expandido) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _expandido = true);
          context.read<ChatProvider>().definirWidgetFlutuanteVisivel(true);
        }
      });
    }
    _ultimoAbrirConversaTrigger = abrirConversaTrigger;

    if (_cx == null || _cy == null) {
      // Primeira build: ancora no canto inferior direito.
      _cx = tela.width  - 16 - _bolhaTamanho / 2;
      _cy = tela.height - 16 - _bolhaTamanho / 2;
    } else if (_telaAnterior != null &&
        (_telaAnterior!.width != tela.width ||
         _telaAnterior!.height != tela.height)) {
      // A tela mudou de tamanho (ex: maximizar/restaurar a janela, entrar
      // em fullscreen). Reescala a posição da bolha proporcionalmente para
      // que ela mantenha a mesma posição RELATIVA na tela — se estava perto
      // do canto inferior direito, continua perto do canto inferior
      // direito na nova resolução, em vez de ficar "presa" no pixel
      // absoluto antigo.
      _cx = _cx! * (tela.width  / _telaAnterior!.width);
      _cy = _cy! * (tela.height / _telaAnterior!.height);
      _cx = _cx!.clamp(_bolhaTamanho / 2, tela.width  - _bolhaTamanho / 2);
      _cy = _cy!.clamp(_bolhaTamanho / 2, tela.height - _bolhaTamanho / 2);
    }
    _telaAnterior = tela;

    final largura = _expandido ? _painelLargura : _bolhaTamanho;
    final altura  = _expandido ? _painelAltura  : _bolhaTamanho;

    final left = (_cx! - largura / 2).clamp(0.0, tela.width  - largura);
    final top  = (_cy! - altura  / 2).clamp(0.0, tela.height - altura);

    // AnimatedPositioned anima left/top junto com largura/altura,
    // garantindo que o painel expanda/minimize a partir do centro
    // da bolha sem nenhum salto de posição.
    // O GestureDetector fica DENTRO para capturar arrasto normalmente;
    // durante o arrasto _arrastando=true e não há mudança de _expandido,
    // então a animação não dispara enquanto o usuário arrasta.
    return AnimatedPositioned(
      duration: _arrastando
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: left,
      top:  top,
      width:  largura,
      height: altura,
      child: GestureDetector(
        onPanStart: (details) {
          _arrastando = false;
          _inicioArrastoGlobal = details.globalPosition;
          _cxAoIniciar = _cx!;
          _cyAoIniciar = _cy!;
        },
        onPanUpdate: (details) {
          final delta = details.globalPosition - _inicioArrastoGlobal;
          if (delta.distance > 4) _arrastando = true;
          // setState direto no callback de gesto: nada de
          // addPostFrameCallback aqui. Adiar a atualização para o frame
          // seguinte fazia o widget "perseguir" o dedo com 1 frame de
          // atraso, o que dava a sensação de arrasto travado/pouco fluido.
          // onPanUpdate já roda fora da fase de build, então setState
          // direto é seguro e responde no mesmo frame do gesto.
          setState(() {
            // O clamp do centro precisa refletir a metade da largura/altura
            // REAIS do que está sendo arrastado (bolha OU painel expandido).
            // Usar sempre _bolhaTamanho/2 aqui — mesmo com o painel expandido
            // (320x440) — fazia _cx/_cy se moverem livremente numa faixa
            // maior do que aquela em que `left`/`top` (que usam `largura`/
            // `altura` reais) já estavam saturados. Resultado: o painel
            // ficava "preso" visualmente por um trecho do arrasto até o
            // centro finalmente sair da zona clampada — exatamente o
            // travamento reportado ao arrastar o chat expandido perto da
            // borda inferior da tela.
            final larguraAtual = _expandido ? _painelLargura : _bolhaTamanho;
            final alturaAtual  = _expandido ? _painelAltura  : _bolhaTamanho;
            _cx = (_cxAoIniciar + delta.dx)
                .clamp(larguraAtual / 2, tela.width  - larguraAtual / 2);
            _cy = (_cyAoIniciar + delta.dy)
                .clamp(alturaAtual  / 2, tela.height - alturaAtual  / 2);
          });
        },
        onPanEnd: (_) {
          final foiClique = !_arrastando;
          setState(() => _arrastando = false);
          if (foiClique) _alternarExpandido(context);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(
                  _expandido ? 16 : _bolhaTamanho / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            // Só recorta (clip) quando o painel está expandido — é nele que
            // a lista de conversa/scroll precisa ficar contida nos cantos
            // arredondados. Em modo bolha, Clip.none evita que o badge de
            // não-lidas (que fica posicionado levemente para fora do
            // círculo) seja cortado pelo próprio container.
            clipBehavior: _expandido ? Clip.antiAlias : Clip.none,
            // IMPORTANTE: o tamanho deste AnimatedContainer acompanha o
            // AnimatedPositioned pai, ou seja, a CADA FRAME da animação de
            // abrir/fechar ele tem uma largura/altura intermediária
            // diferente (ex.: 56 -> 130 -> 220 -> 320). Se o conteúdo
            // (ListView/ListTile da lista de usuários e da conversa) fosse
            // filho direto daqui, ele seria relayoutado nessas larguras
            // intermediárias a cada frame — é exatamente isso que causava
            // os erros "RenderBox was not laid out", "child.hasSize is not
            // true" (sliver) e "RenderFlex overflowed", além do piscar de
            // tela ao expandir.
            //
            // A correção: o conteúdo é sempre desenhado no seu tamanho
            // FINAL e FIXO (painel completo ou bolha completa) dentro de
            // um SizedBox; o AnimatedContainer ao redor só recorta
            // (Clip.antiAlias) a parte visível conforme cresce/encolhe.
            // Assim o ListView nunca é relayoutado com larguras
            // intermediárias — ele já nasce no tamanho certo.
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: _expandido ? _painelLargura : _bolhaTamanho,
              maxHeight: _expandido ? _painelAltura  : _bolhaTamanho,
              child: SizedBox(
                width:  _expandido ? _painelLargura : _bolhaTamanho,
                height: _expandido ? _painelAltura  : _bolhaTamanho,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _expandido
                      ? _MiniChatPainel(
                          key: const ValueKey('painel'),
                          onFechar: () => _fechar(context),
                          onMinimizar: () => _alternarExpandido(context),
                        )
                      : const _BolhaIcone(key: ValueKey('bolha')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _BolhaIcone extends StatelessWidget {
  const _BolhaIcone({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final naoLidas = chat.totalNaoLidas;
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary,
                  Color.lerp(cs.primary, Colors.deepOrange, 0.35)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.50),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          if (naoLidas > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.surface, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  naoLidas > 99 ? '99+' : '$naoLidas',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Painel expandido (mini-chat) ─────────────────────────────────────────────

class _MiniChatPainel extends StatefulWidget {
  final VoidCallback onFechar;
  final VoidCallback onMinimizar;
  const _MiniChatPainel({super.key, required this.onFechar, required this.onMinimizar});

  @override
  State<_MiniChatPainel> createState() => _MiniChatPainelState();
}

class _MiniChatPainelState extends State<_MiniChatPainel> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _msgFocus = FocusNode();
  int? _usuarioAtivoAnterior;
  MensagemChat? _respondendoA;

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _msgFocus.dispose();
    super.dispose();
  }

  void _focarCampoMensagem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _msgFocus.requestFocus();
    });
  }

  void _enviar(ChatProvider chat) {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    _controller.clear();
    final respondendoA = _respondendoA;
    setState(() => _respondendoA = null);
    chat
        .enviarMensagem(texto, respondendoA: respondendoA)
        .then((_) => _scrollToBottom());
  }

  void _responderA(MensagemChat msg) {
    setState(() => _respondendoA = msg);
    _msgFocus.requestFocus();
  }

  Future<void> _editarMensagem(ChatProvider chat, MensagemChat msg) async {
    final novoTexto = await mostrarDialogoEditarMensagem(
      context,
      textoAtual: msg.conteudo,
    );
    if (novoTexto == null) return;
    final texto = novoTexto.trim();
    if (texto.isEmpty || texto == msg.conteudo) return;
    try {
      await chat.editarMensagem(msg, texto);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível editar: $e')),
        );
      }
    }
  }

  Future<void> _excluirMensagem(ChatProvider chat, MensagemChat msg) async {
    final confirmado = await confirmarExclusaoMensagem(context);
    if (!confirmado) return;
    try {
      await chat.excluirMensagem(msg);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível excluir: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final cs   = Theme.of(context).colorScheme;

    // Sempre que a conversa ativa muda (inclusive na primeira vez que uma
    // conversa é aberta), pede foco pro campo de mensagem explicitamente.
    // Não dá pra confiar só em `autofocus: true` no TextField porque, se o
    // provider já estava com usuarioAtivoId setado quando este painel
    // montou (ex.: reaberto durante a mesma sessão), o Element do TextField
    // pode ser reaproveitado entre rebuilds do Column — nesse caso
    // `autofocus` não dispara de novo, já que ele só age na montagem
    // inicial do Element, e não a cada troca de conversa.
    if (chat.usuarioAtivoId != _usuarioAtivoAnterior) {
      _usuarioAtivoAnterior = chat.usuarioAtivoId;
      if (chat.usuarioAtivoId != null) _focarCampoMensagem();
    }

    // Material local e transparente: o ListTile/InkWell (lista de usuários)
    // e os InkWell dos botões pintam o splash de toque no Material
    // ANCESTRAL mais próximo. Sem um Material aqui perto, esse splash é
    // pintado num Material distante (lá em cima, no Scaffold do app) e
    // acaba ficando visualmente "embaixo" do nosso próprio
    // AnimatedContainer/OverflowBox com fundo opaco — daí o aviso
    // "ListTile background color or ink splashes may be invisible" e o
    // toque sem feedback visual. Com este Material local o splash passa a
    // ser pintado na camada certa, por cima do fundo.
    return Material(
      type: MaterialType.transparency,
      child: Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(color: cs.primary),
          child: Row(
            children: [
              if (chat.usuarioAtivoId != null)
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: cs.onPrimary, size: 18),
                  onPressed: () => chat.fecharConversa(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(
                          SystemMouseCursors.click)),
                ),
              Builder(builder: (context) {
                final ativo = chat.usuarioAtivoId != null
                    ? chat.usuarioPorId(chat.usuarioAtivoId!)
                    : null;
                if (ativo == null) {
                  return Icon(Icons.chat_bubble_rounded, color: cs.onPrimary, size: 16);
                }
                final inicial = ativo.nome.isNotEmpty ? ativo.nome[0].toUpperCase() : '?';
                return Stack(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: cs.onPrimary.withValues(alpha: 0.20),
                      child: Text(
                        inicial,
                        style: GoogleFonts.nunito(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: _MiniStatusDot(online: ativo.online),
                    ),
                  ],
                );
              }),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chat.usuarioAtivoId == null
                          ? 'Chat'
                          : chat.usuarios
                              .firstWhere(
                                (u) => u.id == chat.usuarioAtivoId,
                                orElse: () => UsuarioChat(id: 0, nome: '...', role: ''),
                              )
                              .nome,
                      style: GoogleFonts.nunito(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (chat.usuarioAtivoId != null)
                      Text(
                        chat.estaDigitando(chat.usuarioAtivoId!)
                            ? 'digitando...'
                            : _formatarStatusUsuarioMini(
                                chat.usuarioPorId(chat.usuarioAtivoId!) ??
                                    UsuarioChat(id: 0, nome: '', role: ''),
                              ),
                        style: GoogleFonts.nunito(
                          color: cs.onPrimary.withValues(alpha: 0.85),
                          fontSize: 10,
                          fontStyle: chat.estaDigitando(chat.usuarioAtivoId!)
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.remove_rounded, color: cs.onPrimary, size: 18),
                onPressed: widget.onMinimizar,
                tooltip: 'Minimizar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                style: IconButton.styleFrom().copyWith(
                    mouseCursor: WidgetStateProperty.all(
                        SystemMouseCursors.click)),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: cs.onPrimary, size: 18),
                onPressed: widget.onFechar,
                tooltip: 'Fechar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                style: IconButton.styleFrom().copyWith(
                    mouseCursor: WidgetStateProperty.all(
                        SystemMouseCursors.click)),
              ),
            ],
          ),
        ),

        Expanded(
          child: chat.usuarioAtivoId == null
              ? _MiniListaUsuarios(chat: chat)
              : _MiniConversa(
                  chat: chat,
                  scrollCtrl: _scrollCtrl,
                  onResponder: _responderA,
                  onEditar: (msg) => _editarMensagem(chat, msg),
                  onExcluir: (msg) => _excluirMensagem(chat, msg),
                ),
        ),

        if (chat.usuarioAtivoId != null)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_respondendoA != null)
                  _MiniPreviewResposta(
                    mensagem: _respondendoA!,
                    meuId: chat.meuId,
                    onCancelar: () => setState(() => _respondendoA = null),
                  ),
                Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _msgFocus,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviar(chat),
                    onChanged: (_) => chat.notificarDigitando(),
                    style: GoogleFonts.nunito(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Mensagem...',
                      hintStyle: GoogleFonts.nunito(fontSize: 13, color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => _enviar(chat),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    child: Icon(Icons.send_rounded, color: cs.onPrimary, size: 16),
                  ),
                ),
              ],
                ),
              ],
            ),
          ),
      ],
      ),
    );
  }
}

class _MiniListaUsuarios extends StatelessWidget {
  final ChatProvider chat;
  const _MiniListaUsuarios({required this.chat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (chat.carregandoUsuarios) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (chat.usuarios.isEmpty) {
      return Center(
        child: Text(
          'Nenhum usuário disponível',
          style: GoogleFonts.nunito(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: chat.usuarios.length,
      itemBuilder: (_, i) {
        final u = chat.usuarios[i];
        final inicial = u.nome.isNotEmpty ? u.nome[0].toUpperCase() : '?';
        return ListTile(
          dense: true,
          onTap: () => chat.abrirConversa(u.id),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: cs.primary.withValues(alpha: 0.15),
                child: Text(
                  inicial,
                  style: GoogleFonts.nunito(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: _MiniStatusDot(online: u.online),
              ),
            ],
          ),
          title: Text(
            u.nome,
            style: GoogleFonts.nunito(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Text(
            u.online ? u.role : _formatarStatusUsuarioMini(u),
            style: GoogleFonts.nunito(fontSize: 10, color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: u.naoLidas > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    u.naoLidas > 99 ? '99+' : '${u.naoLidas}',
                    style: GoogleFonts.nunito(
                      color: cs.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _MiniConversa extends StatefulWidget {
  final ChatProvider chat;
  final ScrollController scrollCtrl;
  final ValueChanged<MensagemChat> onResponder;
  final ValueChanged<MensagemChat> onEditar;
  final ValueChanged<MensagemChat> onExcluir;
  const _MiniConversa({
    required this.chat,
    required this.scrollCtrl,
    required this.onResponder,
    required this.onEditar,
    required this.onExcluir,
  });

  @override
  State<_MiniConversa> createState() => _MiniConversaState();
}

class _MiniConversaState extends State<_MiniConversa> {
  int? _conversaAnterior;
  int  _qtdMensagensAnterior = 0;

  // true enquanto esperamos as mensagens de uma conversa recém-aberta (ou
  // recém-trocada) chegarem, para então dar o salto pro fim. Sem isso, um
  // jumpTo disparado a cada build (mesmo durante o carregamento, antes das
  // mensagens existirem) pode "gastar" o salto num frame em que a lista
  // ainda não tem o conteúdo final, deixando a conversa parada no topo.
  bool _aguardandoSaltoInicial = false;

  void _scrollToBottom({bool instantaneo = true}) {
    final scrollCtrl = widget.scrollCtrl;
    void aplicar() {
      if (!scrollCtrl.hasClients) return;
      final destino = scrollCtrl.position.maxScrollExtent;
      if (instantaneo) {
        scrollCtrl.jumpTo(destino);
      } else {
        scrollCtrl.animateTo(
          destino,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      aplicar();
      // Segundo salto no frame seguinte: garante que o layout final da
      // lista (alturas variáveis, reações, etc.) já foi considerado —
      // corrige o caso em que o primeiro jumpTo acontece antes da lista
      // terminar de se estabilizar.
      if (instantaneo) {
        WidgetsBinding.instance.addPostFrameCallback((_) => aplicar());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final cs = Theme.of(context).colorScheme;
    final mensagens = chat.conversaAtual();
    final outroId = chat.usuarioAtivoId;

    final chatKeyChanged = outroId != _conversaAnterior;
    if (chatKeyChanged) {
      _conversaAnterior       = outroId;
      _qtdMensagensAnterior   = mensagens.length;
      _aguardandoSaltoInicial = true;
      if (!chat.carregandoMensagens) {
        _aguardandoSaltoInicial = false;
        _scrollToBottom(instantaneo: true);
      }
    } else if (_aguardandoSaltoInicial) {
      if (!chat.carregandoMensagens) {
        _qtdMensagensAnterior   = mensagens.length;
        _aguardandoSaltoInicial = false;
        _scrollToBottom(instantaneo: true);
      }
    } else {
      final chegouMensagem = mensagens.length != _qtdMensagensAnterior;
      if (chegouMensagem) {
        _qtdMensagensAnterior = mensagens.length;
        _scrollToBottom(instantaneo: false);
      }
    }

    if (chat.carregandoMensagens) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (mensagens.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma mensagem ainda.\nDiga olá!',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: mensagens.length,
      itemBuilder: (ctx, i) {
        final msg = mensagens[i];
        final isMinha = msg.remetenteId == chat.meuId;
        final hora = DateFormat('HH:mm').format(msg.criadoEm);
        final anterior = i > 0 ? mensagens[i - 1] : null;
        final mostrarData = anterior == null ||
            !_mesmoDia(anterior.criadoEm, msg.criadoEm);
        final minhaReacaoAtual = chat.meuId != null
            ? msg.reacoes[chat.meuId.toString()]
            : null;

        Future<void> abrirSeletor(Offset posicaoGlobal) async {
          if (msg.apagada) return;
          final escolha = await mostrarSeletorReacao(
            ctx,
            posicaoGlobal,
            jaReagiu: minhaReacaoAtual != null,
            souAutor: isMinha,
          );
          if (escolha == null) return;
          if (escolha == responderSentinela) {
            widget.onResponder(msg);
            return;
          }
          if (escolha == editarSentinela) {
            widget.onEditar(msg);
            return;
          }
          if (escolha == excluirSentinela) {
            widget.onExcluir(msg);
            return;
          }
          chat.reagirMensagem(
            msg,
            escolha == removerReacaoSentinela ? null : escolha,
          );
        }

        final bolha = _MiniBolhaMensagem(
          isMinha: isMinha,
          mensagem: msg,
          conteudo: msg.conteudo,
          hora: hora,
          temReacoes: msg.reacoes.isNotEmpty,
          pendente: msg.pendente,
          lida: msg.lida,
          onLongPressStart: (details) => abrirSeletor(details.globalPosition),
          respondendoAConteudo: msg.respondendoAConteudo,
          respondendoARemetenteNome: msg.respondendoARemetenteNome,
          reacoesBadge: msg.reacoes.isNotEmpty
              ? ReacoesBadge(reacoes: msg.reacoes, isMinha: isMinha)
              : null,
        );

        final bolhaAnimada = _MiniEntradaAnimada(
          animar: i == mensagens.length - 1,
          child: bolha,
        );

        if (!mostrarData) return bolhaAnimada;

        return Column(
          children: [
            _MiniDateDivider(data: msg.criadoEm),
            bolhaAnimada,
          ],
        );
      },
    );
  }

  bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Bolha de mensagem com hover (versão compacta do widget flutuante) ───────

class _MiniBolhaMensagem extends StatefulWidget {
  final bool isMinha;
  final MensagemChat mensagem;
  final String conteudo;
  final String hora;
  final bool temReacoes;
  final bool pendente;
  final bool lida;
  final GestureLongPressStartCallback onLongPressStart;
  final String? respondendoAConteudo;
  final String? respondendoARemetenteNome;
  final Widget? reacoesBadge;
  const _MiniBolhaMensagem({
    required this.isMinha,
    required this.mensagem,
    required this.conteudo,
    required this.hora,
    required this.temReacoes,
    required this.pendente,
    required this.lida,
    required this.onLongPressStart,
    this.respondendoAConteudo,
    this.respondendoARemetenteNome,
    this.reacoesBadge,
  });

  @override
  State<_MiniBolhaMensagem> createState() => _MiniBolhaMensagemState();
}

class _MiniBolhaMensagemState extends State<_MiniBolhaMensagem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMinha = widget.isMinha;

    final corBase = isMinha ? cs.primary : cs.surfaceContainerHighest;
    final corHover = isMinha
        ? Color.lerp(corBase, Colors.white, 0.08)!
        : Color.lerp(corBase, Colors.black, 0.05)!;

    return Align(
      alignment: isMinha ? Alignment.centerRight : Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit:  (_) => setState(() => _hover = false),
        child: GestureDetector(
          onLongPressStart: widget.onLongPressStart,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                constraints: const BoxConstraints(maxWidth: 220),
                margin: EdgeInsets.only(
                  bottom: widget.temReacoes ? 14 : 6,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _hover ? corHover : corBase,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isMinha ? 12 : 3),
                    bottomRight: Radius.circular(isMinha ? 3 : 12),
                  ),
                  boxShadow: _hover
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment:
                      isMinha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (widget.respondendoAConteudo != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isMinha ? cs.onPrimary : cs.primary)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border(
                            left: BorderSide(
                              color: isMinha ? cs.onPrimary : cs.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.respondendoARemetenteNome ?? '...',
                              style: GoogleFonts.nunito(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isMinha ? cs.onPrimary : cs.primary,
                              ),
                            ),
                            Text(
                              resumoConteudoParaPreview(
                                widget.respondendoAConteudo!,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(
                                fontSize: 10.5,
                                color: (isMinha ? cs.onPrimary : cs.onSurface)
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.mensagem.apagada)
                      Text(
                        'Mensagem apagada',
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: (isMinha ? cs.onPrimary : cs.onSurface)
                              .withValues(alpha: 0.6),
                        ),
                      )
                    else if (widget.mensagem.ehEncaminhamento)
                      EncaminhamentoChatCard(
                        mensagem: widget.mensagem,
                        isMinha: isMinha,
                        compacta: true,
                      )
                    else
                      Text(
                        widget.conteudo,
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: isMinha ? cs.onPrimary : cs.onSurface,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.mensagem.ehEditada && !widget.mensagem.apagada)
                          Text(
                            'editada · ',
                            style: GoogleFonts.nunito(
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                              color: isMinha
                                  ? cs.onPrimary.withValues(alpha: 0.7)
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          widget.hora,
                          style: GoogleFonts.nunito(
                            fontSize: 9,
                            color: isMinha
                                ? cs.onPrimary.withValues(alpha: 0.7)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        if (isMinha) ...[
                          const SizedBox(width: 3),
                          _TicksMensagem(
                            pendente: widget.pendente,
                            lida: widget.lida,
                            corBase: cs.onPrimary.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.reacoesBadge != null)
                Positioned(
                  bottom: 0,
                  left: isMinha ? null : 6,
                  right: isMinha ? 6 : null,
                  child: widget.reacoesBadge!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Divisor de data (versão compacta do widget flutuante) ───────────────────

// ─── Risquinhos de status (estilo WhatsApp) ────────────────────────────────
// 1 risquinho cinza  -> mensagem enviada, aguardando confirmação do servidor
// 2 risquinhos cinza -> confirmada pelo servidor, ainda não visualizada
// 2 risquinhos azuis -> visualizada (lida) pelo destinatário
class _TicksMensagem extends StatelessWidget {
  final bool pendente;
  final bool lida;
  final Color corBase;
  const _TicksMensagem({
    required this.pendente,
    required this.lida,
    required this.corBase,
  });

  @override
  Widget build(BuildContext context) {
    if (pendente) {
      return Icon(Icons.done, size: 12, color: corBase);
    }
    final corLida = const Color(0xFF4FC3F7); // azul estilo WhatsApp
    return Icon(
      Icons.done_all,
      size: 12,
      color: lida ? corLida : corBase,
    );
  }
}

// ─── Preview compacto da mensagem sendo respondida (mini-chat) ────────────────

class _MiniPreviewResposta extends StatelessWidget {
  final MensagemChat mensagem;
  final int? meuId;
  final VoidCallback onCancelar;
  const _MiniPreviewResposta({
    required this.mensagem,
    required this.meuId,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final autor = mensagem.remetenteId == meuId
        ? 'Você'
        : (mensagem.remetenteNome ?? '...');

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: cs.primary, width: 2.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respondendo a $autor',
                  style: GoogleFonts.nunito(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                Text(
                  mensagem.resumoParaPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(fontSize: 10.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 13),
            onPressed: onCancelar,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ─── Entrada animada (versão compacta, ver explicação em chat_page.dart) ──────

class _MiniEntradaAnimada extends StatefulWidget {
  final Widget child;
  final bool animar;
  const _MiniEntradaAnimada({required this.child, required this.animar});

  @override
  State<_MiniEntradaAnimada> createState() => _MiniEntradaAnimadaState();
}

class _MiniEntradaAnimadaState extends State<_MiniEntradaAnimada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _opacidade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _posicao = Tween<Offset>(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    if (widget.animar) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacidade,
      child: SlideTransition(position: _posicao, child: widget.child),
    );
  }
}

class _MiniDateDivider extends StatelessWidget {
  final DateTime data;
  const _MiniDateDivider({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));
    String label;
    if (_mesmoDia(data, hoje)) {
      label = 'Hoje';
    } else if (_mesmoDia(data, ontem)) {
      label = 'Ontem';
    } else {
      label = DateFormat('dd/MM/yyyy').format(data);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 9.5,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
        ],
      ),
    );
  }

  bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}