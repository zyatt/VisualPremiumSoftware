// lib/widgets/reacao_mensagem_picker.dart
//
// Widgets compartilhados de reação a mensagens (estilo WhatsApp/Messenger):
// - mostrarSeletorReacao: abre um menu compacto com emojis ao segurar uma
//   mensagem (long-press), na posição do toque.
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

const List<String> kEmojisReacao = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Mostra o seletor de emojis ancorado na posição [posicaoGlobal] (em geral
/// vinda de `LongPressStartDetails.globalPosition`). Retorna o emoji
/// escolhido, [removerReacaoSentinela] se o usuário quis remover a reação
/// atual, ou `null` se fechou sem escolher nada.
Future<String?> mostrarSeletorReacao(
  BuildContext context,
  Offset posicaoGlobal, {
  required bool jaReagiu,
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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    elevation: 6,
    items: [
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