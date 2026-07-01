// lib/pages/chat_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/chat_provider.dart';
import '../providers/usuario_provider.dart';
import '../models/mensagem_chat_model.dart';
import '../widgets/reacao_mensagem_picker.dart';

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
                // Se o usuário clicado já é a conversa ativa, não faz nada.
                // Evita reabrir/recarregar a mesma conversa (o que fazia o
                // chat rolar de volta pro topo).
                onTap:     isAtivo ? () {} : () => onSelecionar(u),
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

  int? _conversaAnterior;
  int  _qtdMensagensAnterior = 0;

  // true enquanto esperamos as mensagens de uma conversa recém-aberta (ou
  // recém-trocada) chegarem, para então dar o salto inicial pro fim. Evita
  // o bug em que a troca de conversa é "detectada" (e consumida) já no
  // build de loading — antes das mensagens chegarem — fazendo o salto
  // instantâneo nunca ser de fato aplicado quando os dados terminam de
  // carregar (o build seguinte via chegouMensagem então usava animateTo,
  // que pode não alcançar o fim exato).
  bool _aguardandoSaltoInicial = false;

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

  // instantaneo=true força um "salto" direto pro fim (jumpTo), garantindo
  // que sempre chega exatamente no maxScrollExtent mais atual — usado ao
  // abrir/trocar de conversa. animateTo pode ser interrompido por um novo
  // build/callback antes de terminar (ex.: mensagens chegando em sequência
  // via socket), fazendo o scroll parar "quase" no fim, que era a causa da
  // última mensagem ficar cortada/incompleta na tela.
  void _scrollToBottom({bool instantaneo = false}) {
    void aplicar() {
      if (!_scrollCtrl.hasClients) return;
      final destino = _scrollCtrl.position.maxScrollExtent;
      if (instantaneo) {
        _scrollCtrl.jumpTo(destino);
      } else {
        _scrollCtrl.animateTo(
          destino,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      aplicar();
      // Segundo salto no frame seguinte: quando a lista acabou de trocar
      // de conteúdo (nova conversa carregada), o maxScrollExtent do
      // primeiro frame pode ainda não refletir o layout final de todos os
      // itens (alturas variáveis, reações, etc). Um jumpTo extra no
      // próximo frame corrige qualquer resíduo e garante que realmente
      // pousa no fim.
      if (instantaneo) {
        WidgetsBinding.instance.addPostFrameCallback((_) => aplicar());
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

    final chatKeyChanged = outroId != _conversaAnterior;
    if (chatKeyChanged) {
      // Conversa trocou (ou é a primeira aberta). Registramos a troca já
      // aqui, mas só marcamos o salto como "resolvido" quando as mensagens
      // realmente chegarem — se ainda estiver carregando (mensagens vazia
      // por estar buscando os dados), fica pendente em
      // _aguardandoSaltoInicial até o próximo build que já tiver os dados.
      _conversaAnterior     = outroId;
      _qtdMensagensAnterior = mensagens.length;
      _aguardandoSaltoInicial = true;
      if (!chat.carregandoMensagens) {
        _aguardandoSaltoInicial = false;
        _scrollToBottom(instantaneo: true);
      }
      // Ao trocar de conversa, leva o foco pro campo de digitação
      // automaticamente, pra já poder digitar sem precisar clicar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else if (_aguardandoSaltoInicial) {
      // As mensagens da conversa que acabamos de abrir/trocar terminaram
      // de carregar agora — dá o salto instantâneo pro fim.
      if (!chat.carregandoMensagens) {
        _qtdMensagensAnterior   = mensagens.length;
        _aguardandoSaltoInicial = false;
        _scrollToBottom(instantaneo: true);
      }
    } else {
      final chegouMensagem = mensagens.length != _qtdMensagensAnterior;
      if (chegouMensagem) {
        _qtdMensagensAnterior = mensagens.length;
        // Mensagem nova chegando numa conversa já aberta: animação suave.
        _scrollToBottom();
      }
    }

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
                            _BubbleMensagem(
                              mensagem: msg,
                              isMinha: isMinha,
                              meuId: chat.meuId,
                              onReagir: (emoji) => chat.reagirMensagem(msg, emoji),
                            ),
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
                  autofocus:   true,
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

class _BubbleMensagem extends StatefulWidget {
  final MensagemChat mensagem;
  final bool isMinha;
  final int? meuId;
  final ValueChanged<String?> onReagir;
  const _BubbleMensagem({
    required this.mensagem,
    required this.isMinha,
    required this.meuId,
    required this.onReagir,
  });

  @override
  State<_BubbleMensagem> createState() => _BubbleMensagemState();
}

class _BubbleMensagemState extends State<_BubbleMensagem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mensagem = widget.mensagem;
    final isMinha  = widget.isMinha;
    final meuId    = widget.meuId;
    final onReagir = widget.onReagir;

    final cs   = Theme.of(context).colorScheme;
    final hora = DateFormat('HH:mm').format(mensagem.criadoEm);
    final minhaReacaoAtual =
        meuId != null ? mensagem.reacoes[meuId.toString()] : null;

    Future<void> abrirSeletor(Offset posicaoGlobal) async {
      final escolha = await mostrarSeletorReacao(
        context,
        posicaoGlobal,
        jaReagiu: minhaReacaoAtual != null,
      );
      if (escolha == null) return;
      onReagir(escolha == removerReacaoSentinela ? null : escolha);
    }

    final corBase = isMinha ? cs.primary : cs.surfaceContainerHighest;
    // Leve realce no hover: clareia (msg própria) ou escurece de leve
    // (msg do outro) o suficiente pra sinalizar interatividade sem
    // chamar atenção demais.
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
          onTapDown: (details) => abrirSeletor(details.globalPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                margin: EdgeInsets.only(
                  bottom: mensagem.reacoes.isEmpty ? 4 : 16,
                  left:  isMinha ? 60 : 0,
                  right: isMinha ? 0  : 60,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: _hover ? corHover : corBase,
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(16),
                    topRight:    const Radius.circular(16),
                    bottomLeft:  Radius.circular(isMinha ? 16 : 4),
                    bottomRight: Radius.circular(isMinha ? 4  : 16),
                  ),
                  boxShadow: _hover
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hora,
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            color: isMinha
                                ? cs.onPrimary.withValues(alpha: 0.7)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        if (isMinha) ...[
                          const SizedBox(width: 4),
                          _TicksMensagem(
                            pendente: mensagem.pendente,
                            lida: mensagem.lida,
                            corBase: cs.onPrimary.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (mensagem.reacoes.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left:  isMinha ? null : 66,
                  right: isMinha ? 6    : null,
                  child: ReacoesBadge(reacoes: mensagem.reacoes, isMinha: isMinha),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Divisor de data ──────────────────────────────────────────────────────────

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
      return Icon(Icons.done, size: 14, color: corBase);
    }
    final corLida = const Color(0xFF4FC3F7); // azul estilo WhatsApp
    return Icon(
      Icons.done_all,
      size: 14,
      color: lida ? corLida : corBase,
    );
  }
}

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