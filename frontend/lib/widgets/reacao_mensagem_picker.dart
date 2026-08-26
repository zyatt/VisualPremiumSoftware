import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const String removerReacaoSentinela = '__remover__';
const String responderSentinela = '__responder__';
const String editarSentinela = '__editar__';
const String excluirSentinela = '__excluir__';
const List<String> kEmojisReacao = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

Future<String?> mostrarSeletorReacao(
  BuildContext context,
  Offset posicaoGlobal, {
  required bool jaReagiu,
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

class ReacoesBadge extends StatelessWidget {
  final Map<String, String> reacoes;
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