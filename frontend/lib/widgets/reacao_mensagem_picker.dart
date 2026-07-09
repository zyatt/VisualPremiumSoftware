// lib/widgets/reacao_mensagem_picker.dart
//
// Widgets compartilhados de reação/resposta a mensagens (estilo
// WhatsApp/Messenger):
// - mostrarSeletorReacao: abre, ao segurar uma mensagem (long-press), um
//   menu compacto na posição do toque com a opção "Responder" no topo e os
//   emojis de reação logo abaixo.
// - ReacoesBadge: pequeno "chip" com os emojis já usados na mensagem,
//   agrupados com contagem, sobreposto ao canto inferior da bolha.
//
// Usado tanto pela página /chat (chat_page.dart) quanto pelo mini-chat do
// widget flutuante (chat_floating_widget.dart) para manter o mesmo
// comportamento e visual em ambos os lugares.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sentinela retornada por [mostrarSeletorReacao] quando o usuário toca no
/// botão de remover a própria reação (ao invés de escolher um emoji novo).
const String removerReacaoSentinela = '__remover__';

/// Sentinela retornada por [mostrarSeletorReacao] quando o usuário toca na
/// opção "Responder", exibida no topo do menu (acima dos emojis).
const String responderSentinela = '__responder__';

/// Sentinela retornada por [mostrarSeletorReacao] quando o usuário toca na
/// opção "Editar". Só aparece para mensagens próprias (ver `souAutor`).
const String editarSentinela = '__editar__';

/// Sentinela retornada por [mostrarSeletorReacao] quando o usuário toca na
/// opção "Excluir". Só aparece para mensagens próprias (ver `souAutor`).
const String excluirSentinela = '__excluir__';

const List<String> kEmojisReacao = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Mostra o seletor de emojis ancorado na posição [posicaoGlobal] (em geral
/// vinda de `LongPressStartDetails.globalPosition`). Retorna o emoji
/// escolhido, [removerReacaoSentinela] se o usuário quis remover a reação
/// atual, ou `null` se fechou sem escolher nada.
Future<String?> mostrarSeletorReacao(
  BuildContext context,
  Offset posicaoGlobal, {
  required bool jaReagiu,
  // Quando true (mensagem enviada pelo próprio usuário logado), o menu
  // ganha também as opções "Editar" e "Excluir" logo abaixo de
  // "Responder" — reações e resposta continuam disponíveis para
  // mensagens de qualquer autor, mas editar/excluir é restrito ao dono
  // da mensagem (o backend também valida isso, então esta é só a
  // camada de UI).
  bool souAutor = false,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final cs = Theme.of(context).colorScheme;

  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      posicaoGlobal & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    color: cs.surfaceContainerHigh,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 6,
    items: [
      // ── Opção "Responder", em destaque no topo do menu ───────────────────
      PopupMenuItem<String>(
        value: responderSentinela,
        height: 40,
        mouseCursor: SystemMouseCursors.click,
        child: Row(
          children: [
            Icon(Icons.reply_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Text(
              'Responder',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
      if (souAutor) ...[
        PopupMenuItem<String>(
          value: editarSentinela,
          height: 40,
          mouseCursor: SystemMouseCursors.click,
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                'Editar',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: excluirSentinela,
          height: 40,
          mouseCursor: SystemMouseCursors.click,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: cs.error),
              const SizedBox(width: 10),
              Text(
                'Excluir',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: cs.error,
                ),
              ),
            ],
          ),
        ),
      ],
      const PopupMenuDivider(height: 8),
      PopupMenuItem<String>(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        // Item único contendo todos os emojis numa linha — assim o menu
        // inteiro vira uma "barrinha" horizontal de reações, igual ao
        // padrão visual de apps de mensagem.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in kEmojisReacao)
              InkResponse(
                radius: 22,
                mouseCursor: SystemMouseCursors.click,
                onTap: () => Navigator.pop(context, emoji),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
            if (jaReagiu) ...[
              const SizedBox(width: 4),
              Container(width: 1, height: 22, color: cs.outlineVariant),
              const SizedBox(width: 4),
              InkResponse(
                radius: 18,
                mouseCursor: SystemMouseCursors.click,
                onTap: () => Navigator.pop(context, removerReacaoSentinela),
                child: Icon(Icons.close_rounded, size: 18, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// Mostra um diálogo de confirmação antes de excluir uma mensagem.
/// Retorna `true` se o usuário confirmou.
Future<bool> confirmarExclusaoMensagem(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final resultado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir mensagem?'),
      content: const Text(
        'Esta ação não pode ser desfeita. A mensagem será substituída por "Mensagem apagada" para ambos os participantes da conversa.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom().copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: cs.error).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  return resultado ?? false;
}

/// Diálogo de edição de mensagem, com [TextEditingController] próprio e
/// ciclo de vida corretamente gerenciado pelo próprio State — evita o bug
/// de "TextEditingController usado após dispose" que ocorre quando o
/// controller é criado no widget PAI (que sobrevive à navegação) e apenas
/// emprestado ao TextField do diálogo: ao fechar o diálogo via Esc, botão,
/// ou toque fora, a transição de saída da rota pode reconstruir a árvore
/// numa ordem em que o controller "emprestado" já foi descartado por outro
/// caminho, ou nunca é descartado corretamente e fica pendurado após o
/// diálogo sumir. Aqui o controller nasce e morre junto com o diálogo.
///
/// Retorna o novo texto se o usuário confirmou com "Salvar" (e o texto
/// mudou), ou `null` se cancelou/fechou sem alterar nada (Esc, tocar fora,
/// ou "Cancelar").
Future<String?> mostrarDialogoEditarMensagem(
  BuildContext context, {
  required String textoAtual,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _EditarMensagemDialog(textoAtual: textoAtual),
  );
}

class _EditarMensagemDialog extends StatefulWidget {
  final String textoAtual;
  const _EditarMensagemDialog({required this.textoAtual});

  @override
  State<_EditarMensagemDialog> createState() => _EditarMensagemDialogState();
}

class _EditarMensagemDialogState extends State<_EditarMensagemDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.textoAtual);

  @override
  void dispose() {
    // Dono do controller é este State, então é aqui — e só aqui — que ele
    // deve ser descartado, garantindo que isso só acontece quando o
    // próprio diálogo está sendo definitivamente removido da árvore.
    _controller.dispose();
    super.dispose();
  }

  void _salvar() => Navigator.pop(context, _controller.text);
  void _cancelar() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar mensagem'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        minLines: 1,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        // Enter confirma, igual ao campo de envio normal.
        onSubmitted: (_) => _salvar(),
      ),
      actions: [
        TextButton(
          onPressed: _cancelar,
          style: TextButton.styleFrom().copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvar,
          style: FilledButton.styleFrom().copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Chip com os emojis já usados na mensagem, agrupados por emoji com
/// contagem (ex.: "👍2"). Pensado para ficar posicionado sobre o canto
/// inferior da bolha, levemente sobreposto — por isso o fundo opaco e a
/// borda, para se destacar bem por cima da bolha por baixo.
class ReacoesBadge extends StatelessWidget {
  final Map<String, String> reacoes; // idUsuario -> emoji
  final bool isMinha;
  const ReacoesBadge({super.key, required this.reacoes, required this.isMinha});

  @override
  Widget build(BuildContext context) {
    if (reacoes.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final contagem = <String, int>{};
    for (final emoji in reacoes.values) {
      contagem[emoji] = (contagem[emoji] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in contagem.entries) ...[
            Text(entry.key, style: const TextStyle(fontSize: 12)),
            if (entry.value > 1) ...[
              const SizedBox(width: 1),
              Text(
                '${entry.value}',
                style: GoogleFonts.nunito(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (entry.key != contagem.keys.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}