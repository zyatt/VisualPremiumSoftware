// lib/widgets/encaminhamento_chat_card.dart
//
// Card compacto exibido dentro da bolha de chat quando a mensagem é um
// encaminhamento de solicitação de material ou de um material específico
// (ver MensagemChat.ehEncaminhamento). Usado tanto pelo chat_page.dart
// (versão normal) quanto pelo chat_floating_widget.dart (versão compacta,
// via o parâmetro `compacta`).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/mensagem_chat_model.dart';

class EncaminhamentoChatCard extends StatelessWidget {
  final MensagemChat mensagem;
  final bool isMinha;
  final bool compacta;

  const EncaminhamentoChatCard({
    super.key,
    required this.mensagem,
    required this.isMinha,
    this.compacta = false,
  });

  @override
  Widget build(BuildContext context) {
    final dados = mensagem.dadosEncaminhados;
    final corTexto = isMinha ? Colors.white : Theme.of(context).colorScheme.onSurface;

    if (dados == null) {
      // Payload corrompido/ilegível: mostra o texto cru como fallback.
      return Text(
        mensagem.conteudo,
        style: TextStyle(fontSize: compacta ? 12.5 : 13, color: corTexto),
      );
    }

    final tipo = mensagem.tipoEncaminhamento;
    IconData icone;
    String titulo;
    final linhas = <String>[];

    if (tipo == 'material') {
      icone = Icons.inventory_2_outlined;
      titulo = (dados['materialNome'] as String?)?.trim().isNotEmpty == true
          ? dados['materialNome'] as String
          : 'Material';

      final medida = (dados['medida'] as String?)?.trim();
      final largura = (dados['largura'] as num?);
      final comprimento = (dados['comprimento'] as num?);
      String? dimensao;
      if (medida != null && medida.isNotEmpty) {
        dimensao = medida;
      } else if (largura != null && comprimento != null && largura > 0 && comprimento > 0) {
        dimensao = '${_fmt(comprimento)}X${_fmt(largura)}M';
      }

      final quantidade = dados['quantidade'];
      final unidade = (dados['unidade'] as String?) ?? '';
      linhas.add('OS: ${dados['numeroOS'] ?? '-'}');
      if (quantidade != null) linhas.add('Qtd: $quantidade $unidade'.trim());
      if (dimensao != null) linhas.add('Medida: $dimensao');

      final espessura = (dados['espessura'] as String?)?.trim();
      final identificador = (dados['identificador'] as String?)?.trim();
      final extras = [identificador, espessura]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' · ');
      if (extras.isNotEmpty) linhas.add(extras);
    } else {
      // tipo == 'solicitacao'
      icone = Icons.assignment_outlined;
      titulo = 'OS ${dados['numeroOS'] ?? '-'}';
      linhas.add('Cliente: ${dados['nomeCliente'] ?? '-'}');
      final dataStr = dados['dataNecessidade'] as String?;
      final data = dataStr != null ? DateTime.tryParse(dataStr) : null;
      if (data != null) {
        linhas.add('Necessidade: ${DateFormat('dd/MM/yyyy').format(data.toLocal())}');
      }
    }

    final corFundo = (isMinha ? Colors.white : Theme.of(context).colorScheme.primary)
        .withValues(alpha: isMinha ? 0.14 : 0.08);
    final corBorda = (isMinha ? Colors.white : Theme.of(context).colorScheme.primary)
        .withValues(alpha: 0.3);

    return Container(
      constraints: BoxConstraints(maxWidth: compacta ? 200 : 260),
      padding: EdgeInsets.symmetric(horizontal: compacta ? 8 : 10, vertical: compacta ? 6 : 8),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: corBorda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icone, size: compacta ? 14 : 16, color: corTexto),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: compacta ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    color: corTexto,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          for (final linha in linhas)
            Text(
              linha,
              style: TextStyle(
                fontSize: compacta ? 10.5 : 11.5,
                color: corTexto.withValues(alpha: 0.85),
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  String _fmt(num v) {
    if (v % 1 == 0) return v.toStringAsFixed(0);
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }
}