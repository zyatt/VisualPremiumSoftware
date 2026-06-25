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

class ChatFloatingWidget extends StatefulWidget {
  const ChatFloatingWidget({super.key});

  @override
  State<ChatFloatingWidget> createState() => _ChatFloatingWidgetState();
}

class _ChatFloatingWidgetState extends State<ChatFloatingWidget> {
  static const double _bolhaTamanho = 56;
  static const double _painelLargura = 320;
  static const double _painelAltura = 440;

  Offset? _posicao; // canto superior-esquerdo da bolha/painel
  bool _expandido = false;
  bool _arrastando = false;
  Offset _inicioArrastoLocal = Offset.zero;

  @override
  void dispose() {
    // Garante que, se o widget for removido da árvore com o mini-chat
    // aberto, a flag de visibilidade não fique "travada" em true.
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

  Offset _clampPosicao(Offset pos, Size tela, double largura, double altura) {
    final maxX = tela.width - largura;
    final maxY = tela.height - altura;
    return Offset(
      pos.dx.clamp(0, maxX < 0 ? 0 : maxX),
      pos.dy.clamp(0, maxY < 0 ? 0 : maxY),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.of(context).size;

    // Posição inicial: canto inferior direito, com uma margem.
    _posicao ??= Offset(
      tela.width - _bolhaTamanho - 24,
      tela.height - _bolhaTamanho - 24,
    );

    final largura = _expandido ? _painelLargura : _bolhaTamanho;
    final altura  = _expandido ? _painelAltura  : _bolhaTamanho;

    // Ao expandir, ajusta a posição pra o painel não vazar da tela.
    final posicaoAtual = _clampPosicao(_posicao!, tela, largura, altura);

    return Positioned(
      left: posicaoAtual.dx,
      top: posicaoAtual.dy,
      child: GestureDetector(
        onPanStart: (details) {
          _arrastando = false;
          _inicioArrastoLocal = details.globalPosition;
        },
        onPanUpdate: (details) {
          final delta = details.globalPosition - _inicioArrastoLocal;
          if (delta.distance > 4) _arrastando = true;
          setState(() {
            _posicao = _clampPosicao(
              _posicao! + details.delta,
              tela,
              largura,
              altura,
            );
          });
        },
        onPanEnd: (_) {
          if (!_arrastando) _alternarExpandido(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: largura,
          height: altura,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(_expandido ? 16 : _bolhaTamanho / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _expandido
              ? _MiniChatPainel(onFechar: () => _fechar(context))
              : const _BolhaIcone(),
        ),
      ),
    );
  }
}

// ─── Bolha (estado recolhido) ─────────────────────────────────────────────────

class _BolhaIcone extends StatelessWidget {
  const _BolhaIcone();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final naoLidas = chat.totalNaoLidas;
    final cs = Theme.of(context).colorScheme;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          child: Icon(Icons.chat_bubble_rounded, color: cs.onPrimary, size: 26),
        ),
        if (naoLidas > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: cs.error,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.surface, width: 1.5),
              ),
              child: Text(
                naoLidas > 99 ? '99+' : '$naoLidas',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  color: cs.onError,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Painel expandido (mini-chat) ─────────────────────────────────────────────

class _MiniChatPainel extends StatefulWidget {
  final VoidCallback onFechar;
  const _MiniChatPainel({required this.onFechar});

  @override
  State<_MiniChatPainel> createState() => _MiniChatPainelState();
}

class _MiniChatPainelState extends State<_MiniChatPainel> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _enviar(ChatProvider chat) {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    _controller.clear();
    chat.enviarMensagem(texto).then((_) => _scrollToBottom());
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

    return Column(
      children: [
        // Header
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
                ),
              Icon(Icons.chat_bubble_rounded, color: cs.onPrimary, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
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
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: cs.onPrimary, size: 18),
                onPressed: widget.onFechar,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),

        // Corpo: lista de usuários OU conversa
        Expanded(
          child: chat.usuarioAtivoId == null
              ? _MiniListaUsuarios(chat: chat)
              : _MiniConversa(chat: chat, scrollCtrl: _scrollCtrl),
        ),

        // Input (só quando há conversa aberta)
        if (chat.usuarioAtivoId != null)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviar(chat),
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
                  onTap: () => _enviar(chat),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    child: Icon(Icons.send_rounded, color: cs.onPrimary, size: 16),
                  ),
                ),
              ],
            ),
          ),
      ],
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
          leading: CircleAvatar(
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
          title: Text(
            u.nome,
            style: GoogleFonts.nunito(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Text(
            u.role,
            style: GoogleFonts.nunito(fontSize: 10, color: cs.onSurfaceVariant),
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

class _MiniConversa extends StatelessWidget {
  final ChatProvider chat;
  final ScrollController scrollCtrl;
  const _MiniConversa({required this.chat, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mensagens = chat.conversaAtual();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollCtrl.hasClients) {
        scrollCtrl.jumpTo(scrollCtrl.position.maxScrollExtent);
      }
    });

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
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: mensagens.length,
      itemBuilder: (_, i) {
        final msg = mensagens[i];
        final isMinha = msg.remetenteId == chat.meuId;
        final hora = DateFormat('HH:mm').format(msg.criadoEm);

        return Align(
          alignment: isMinha ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isMinha ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMinha ? 12 : 3),
                bottomRight: Radius.circular(isMinha ? 3 : 12),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isMinha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  msg.conteudo,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: isMinha ? cs.onPrimary : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hora,
                  style: GoogleFonts.nunito(
                    fontSize: 9,
                    color: isMinha
                        ? cs.onPrimary.withValues(alpha: 0.7)
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}