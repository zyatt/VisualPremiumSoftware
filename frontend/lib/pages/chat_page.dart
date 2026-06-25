// lib/pages/chat_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/chat_provider.dart';
import '../providers/usuario_provider.dart';
import '../models/mensagem_chat_model.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProv = context.read<ChatProvider>();
      final usuarioProv = context.read<UsuarioProvider>();
      final meuId = usuarioProv.usuarioLogado?.id;
      final token = usuarioProv.token;
      if (meuId != null && token != null) {
        chatProv.inicializar(meuId, token);
      } else {
        chatProv.carregarUsuarios();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat    = context.watch<ChatProvider>();
    final isWide  = MediaQuery.of(context).size.width >= 700;
    final cs      = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text(
          'Chat',
          style: GoogleFonts.raleway(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => chat.carregarUsuarios(),
            tooltip: 'Atualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isWide
          ? _LayoutWide(chat: chat)
          : _LayoutNarrow(chat: chat),
    );
  }
}

// ─── Layout para telas largas (split view) ────────────────────────────────────

class _LayoutWide extends StatelessWidget {
  final ChatProvider chat;
  const _LayoutWide({required this.chat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: _ListaUsuarios(chat: chat, onSelecionar: (u) => chat.abrirConversa(u.id)),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          child: chat.usuarioAtivoId == null
              ? _EmptyState()
              : _PainelConversa(chat: chat),
        ),
      ],
    );
  }
}

// ─── Layout mobile (stack view) ──────────────────────────────────────────────

class _LayoutNarrow extends StatelessWidget {
  final ChatProvider chat;
  const _LayoutNarrow({required this.chat});

  @override
  Widget build(BuildContext context) {
    if (chat.usuarioAtivoId != null) {
      return _PainelConversa(
        chat: chat,
        showBackButton: true,
      );
    }
    return _ListaUsuarios(
      chat: chat,
      onSelecionar: (u) => chat.abrirConversa(u.id),
    );
  }
}

// ─── Lista de usuários ────────────────────────────────────────────────────────

class _ListaUsuarios extends StatelessWidget {
  final ChatProvider chat;
  final void Function(UsuarioChat) onSelecionar;
  const _ListaUsuarios({required this.chat, required this.onSelecionar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final usuarios = chat.usuarios;

    if (chat.carregandoUsuarios) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chat.erroUsuarios != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 32),
              const SizedBox(height: 8),
              Text(
                chat.erroUsuarios!,
                style: GoogleFonts.nunito(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => chat.carregarUsuarios(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (usuarios.isEmpty) {
      return Center(
        child: Text(
          'Nenhum usuário disponível',
          style: GoogleFonts.nunito(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Usuários',
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: usuarios.length,
            itemBuilder: (_, i) {
              final u        = usuarios[i];
              final isAtivo  = chat.usuarioAtivoId == u.id;
              return _UsuarioTile(
                usuario:   u,
                isAtivo:   isAtivo,
                onTap:     () => onSelecionar(u),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UsuarioTile extends StatelessWidget {
  final UsuarioChat usuario;
  final bool isAtivo;
  final VoidCallback onTap;
  const _UsuarioTile({
    required this.usuario,
    required this.isAtivo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final inicial = usuario.nome.isNotEmpty ? usuario.nome[0].toUpperCase() : '?';

    return Material(
      color: isAtivo ? cs.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: cs.primary.withValues(alpha: 0.15),
                    child: Text(
                      inicial,
                      style: GoogleFonts.nunito(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (usuario.naoLidas > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          usuario.naoLidas > 99 ? '99+' : '${usuario.naoLidas}',
                          style: GoogleFonts.nunito(
                            color: cs.onError,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usuario.nome,
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      usuario.role,
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Painel de conversa ───────────────────────────────────────────────────────

class _PainelConversa extends StatefulWidget {
  final ChatProvider chat;
  final bool showBackButton;
  const _PainelConversa({required this.chat, this.showBackButton = false});

  @override
  State<_PainelConversa> createState() => _PainelConversaState();
}

class _PainelConversaState extends State<_PainelConversa> {
  final _controller    = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final _focusNode     = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _enviar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    _controller.clear();
    widget.chat.enviarMensagem(texto).then((_) => _scrollToBottom());
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
    final chat     = widget.chat;
    final cs       = Theme.of(context).colorScheme;
    final mensagens = chat.conversaAtual();
    final outroId  = chat.usuarioAtivoId;
    final outro    = chat.usuarios.firstWhere(
      (u) => u.id == outroId,
      orElse: () => UsuarioChat(id: 0, nome: '...', role: ''),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              if (widget.showBackButton)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => chat.fecharConversa(),
                ),
              CircleAvatar(
                radius: 17,
                backgroundColor: cs.primary.withValues(alpha: 0.15),
                child: Text(
                  outro.nome.isNotEmpty ? outro.nome[0].toUpperCase() : '?',
                  style: GoogleFonts.nunito(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outro.nome,
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      outro.role,
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Mensagens
        Expanded(
          child: chat.carregandoMensagens
              ? const Center(child: CircularProgressIndicator())
              : mensagens.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma mensagem ainda.\nDiga olá!',
                        style: GoogleFonts.nunito(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: mensagens.length,
                      itemBuilder: (_, i) {
                        final msg      = mensagens[i];
                        final isMinha  = msg.remetenteId == chat.meuId;
                        final anterior = i > 0 ? mensagens[i - 1] : null;
                        final showDate = anterior == null ||
                            !_mesmoDia(anterior.criadoEm, msg.criadoEm);

                        return Column(
                          children: [
                            if (showDate) _DateDivider(data: msg.criadoEm),
                            _BubbleMensagem(mensagem: msg, isMinha: isMinha),
                          ],
                        );
                      },
                    ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller:  _controller,
                  focusNode:   _focusNode,
                  maxLines:    4,
                  minLines:    1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviar(),
                  style: GoogleFonts.nunito(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Digite uma mensagem...',
                    hintStyle: GoogleFonts.nunito(color: cs.onSurfaceVariant),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                heroTag: 'chat_page_send',
                onPressed: _enviar,
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                child: const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Bubble de mensagem ───────────────────────────────────────────────────────

class _BubbleMensagem extends StatelessWidget {
  final MensagemChat mensagem;
  final bool isMinha;
  const _BubbleMensagem({required this.mensagem, required this.isMinha});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final hora = DateFormat('HH:mm').format(mensagem.criadoEm);

    return Align(
      alignment: isMinha ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: EdgeInsets.only(
          bottom: 4,
          left:  isMinha ? 60 : 0,
          right: isMinha ? 0  : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isMinha
              ? cs.primary
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(isMinha ? 16 : 4),
            bottomRight: Radius.circular(isMinha ? 4  : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMinha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              mensagem.conteudo,
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: isMinha ? cs.onPrimary : cs.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              hora,
              style: GoogleFonts.nunito(
                fontSize: 10,
                color: isMinha
                    ? cs.onPrimary.withValues(alpha: 0.7)
                    : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Divisor de data ──────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final DateTime data;
  const _DateDivider({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant)),
        ],
      ),
    );
  }

  bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 56, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            'Selecione um usuário\npara iniciar uma conversa',
            style: GoogleFonts.nunito(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}