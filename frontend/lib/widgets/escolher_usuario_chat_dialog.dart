// lib/widgets/escolher_usuario_chat_dialog.dart
//
// Ponto de entrada único da feature "Enviar para chat": chame
// `encaminharParaChat(context, tipo: ..., dados: ...)` de qualquer tela.
// Ele abre o seletor de usuário e, ao escolher um, envia o encaminhamento
// via ChatProvider.enviarEncaminhamento. Retorna true se enviou com sucesso.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';

Future<bool> encaminharParaChat(
  BuildContext context, {
  required String tipo, // 'solicitacao' ou 'material'
  required Map<String, dynamic> dados,
}) async {
  final chat = context.read<ChatProvider>();
  await chat.carregarUsuarios();
  if (!context.mounted) return false;

  final destinatarioId = await showDialog<int>(
    context: context,
    builder: (_) => const _EscolherUsuarioChatDialog(),
  );
  if (destinatarioId == null) return false;

  try {
    await chat.enviarEncaminhamento(
      destinatarioId: destinatarioId,
      tipo: tipo,
      dados: dados,
    );
    await chat.solicitarAberturaConversa(destinatarioId);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao enviar para o chat'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
    return false;
  }
}

class _EscolherUsuarioChatDialog extends StatefulWidget {
  const _EscolherUsuarioChatDialog();

  @override
  State<_EscolherUsuarioChatDialog> createState() => _EscolherUsuarioChatDialogState();
}

class _EscolherUsuarioChatDialogState extends State<_EscolherUsuarioChatDialog> {
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = context.watch<ChatProvider>().usuarios
        .where((u) => u.nome.toLowerCase().contains(_busca.toLowerCase()))
        .toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Enviar para chat',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Cancelar',
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _buscaCtrl,
                decoration: const InputDecoration(
                  hintText: 'Buscar usuário...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: usuarios.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Nenhum usuário encontrado',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: usuarios.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (_, i) {
                          final u = usuarios[i];
                          return Material(
                            color: Colors.transparent,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                                  child: Text(
                                    u.nome.isNotEmpty ? u.nome[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                        color: AppTheme.primary, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                title: Text(u.nome, style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                  u.role,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                onTap: () => Navigator.pop(context, u.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}