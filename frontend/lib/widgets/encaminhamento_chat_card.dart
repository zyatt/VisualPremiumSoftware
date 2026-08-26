import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/mensagem_chat_model.dart';
import '../models/material_model.dart';
import '../providers/material_provider.dart';
import '../providers/solicitacao_material_provider.dart';
import '../providers/orcamento_provider.dart';

String _formatarUnidadeExibicao(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return '';
  final u = unidade.trim().toUpperCase();
  switch (u) {
    case 'UNIDADE':
      return 'Unidade';
    case 'M/L':
      return 'm/l';
    case 'M':
      return 'm';
    case 'ML':
      return 'ml';
    case 'M²':
    case 'M2':
      return 'm²';
    case 'KG':
      return 'Kg';
    case 'G':
      return 'g';
    default:
      return unidade;
  }
}

class EncaminhamentoChatCard extends StatefulWidget {
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
  State<EncaminhamentoChatCard> createState() => _EncaminhamentoChatCardState();
}

class _EncaminhamentoChatCardState extends State<EncaminhamentoChatCard> {
  Future<MaterialModel?>? _materialAtualFuture;
  Future<Map<String, dynamic>?>? _orcamentoAtualFuture;

  @override
  void initState() {
    super.initState();
    _iniciarBuscaMaterialAtual();
    _iniciarBuscaOrcamentoAtual();
  }

  @override
  void didUpdateWidget(covariant EncaminhamentoChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mensagem.id != widget.mensagem.id) {
      _iniciarBuscaMaterialAtual();
      _iniciarBuscaOrcamentoAtual();
    }
  }

  void _iniciarBuscaMaterialAtual() {
    final dados = widget.mensagem.dadosEncaminhados;
    final tipo  = widget.mensagem.tipoEncaminhamento;
    final materialId    = dados?['materialId'] as int?;
    final solicitacaoId = dados?['solicitacaoId'] as int?;

    if (tipo == 'material' && materialId != null && solicitacaoId == null) {
      _materialAtualFuture = context.read<MaterialProvider>().buscarPorId(materialId);
    } else {
      _materialAtualFuture = null;
    }
  }

  void _iniciarBuscaOrcamentoAtual() {
    final dados = widget.mensagem.dadosEncaminhados;
    final tipo  = widget.mensagem.tipoEncaminhamento;
    final orcamentoId = dados?['orcamentoId'] as int?;

    if (tipo == 'orcamento' && orcamentoId != null) {
      _orcamentoAtualFuture = context.read<OrcamentoProvider>().buscarPorId(orcamentoId);
    } else {
      _orcamentoAtualFuture = null;
    }
  }

  String _statusLabelDoStatus(String? status) {
    switch (status) {
      case 'ABERTO':
        return 'Aberto';
      case 'AGUARDANDO_APROVACAO':
        return 'Aguardando Aprovação';
      case 'APROVADO':
        return 'Aprovado';
      case 'NAO_APROVADO':
        return 'Não Aprovado';
      case 'CONVERTIDO':
        return 'Convertido em OC';
      case 'CANCELADO':
        return 'Cancelado';
      default:
        return 'Aberto';
    }
  }

  Map<String, dynamic> _mesclarComOrcamentoAtual(
    Map<String, dynamic> original,
    Map<String, dynamic> atual,
  ) {
    return {
      ...original,
      'titulo': atual['titulo'] ?? original['titulo'],
      'status': atual['status'],
      'statusLabel': _statusLabelDoStatus(atual['status'] as String?),
      'quantidadeMateriais': (atual['itens'] as List?)?.length ??
          original['quantidadeMateriais'],
    };
  }

  @override
  Widget build(BuildContext context) {
    final dados = widget.mensagem.dadosEncaminhados;

    if (dados == null) {
      final corTexto = widget.isMinha ? Colors.white : Theme.of(context).colorScheme.onSurface;
      return Text(
        widget.mensagem.conteudo,
        style: TextStyle(fontSize: widget.compacta ? 12.5 : 13, color: corTexto),
      );
    }

    if (_orcamentoAtualFuture != null) {
      return FutureBuilder<Map<String, dynamic>?>(
        future: _orcamentoAtualFuture,
        builder: (context, snapshot) {
          final atual = snapshot.data;
          final dadosParaExibir =
              atual != null ? _mesclarComOrcamentoAtual(dados, atual) : dados;
          return _conteudoCard(context, dadosParaExibir);
        },
      );
    }

    if (_materialAtualFuture == null) {
      return _conteudoCard(context, dados);
    }

    return FutureBuilder<MaterialModel?>(
      future: _materialAtualFuture,
      builder: (context, snapshot) {
        final atual = snapshot.data;
        final dadosParaExibir = atual != null ? _mesclarComMaterialAtual(dados, atual) : dados;
        return _conteudoCard(context, dadosParaExibir);
      },
    );
  }

  Map<String, dynamic> _mesclarComMaterialAtual(
    Map<String, dynamic> original,
    MaterialModel atual,
  ) {
    return {
      ...original,
      'materialNome':  atual.nome,
      'categoria':     atual.categoria,
      'identificador': atual.identificador,
      'medida':        atual.medida,
      'espessura':     atual.espessura,
      'largura':       atual.largura,
      'comprimento':   atual.comprimento,
      'unidade':       atual.unidade,
      'quantidade':    atual.quantidade,
    };
  }

  Widget _conteudoCard(BuildContext context, Map<String, dynamic> dados) {
    final isMinha  = widget.isMinha;
    final compacta = widget.compacta;
    final corTexto = isMinha ? Colors.white : Theme.of(context).colorScheme.onSurface;

    final tipo = widget.mensagem.tipoEncaminhamento;
    String titulo;
    final linhas = <String>[];

    if (tipo == 'material') {
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
        dimensao = '${_fmt(comprimento)}x${_fmt(largura)}m';
      }

      final quantidade = dados['quantidade'];
      final unidade = _formatarUnidadeExibicao(dados['unidade'] as String?);
      final numeroOS = dados['numeroOS'] as String?;
      if (numeroOS != null && numeroOS.isNotEmpty) linhas.add('Solicitação: $numeroOS');
      if (quantidade != null) linhas.add('Qtd: $quantidade $unidade'.trim());
      if (dimensao != null) linhas.add('Medida: $dimensao');

      final espessura = (dados['espessura'] as String?)?.trim();
      final identificador = (dados['identificador'] as String?)?.trim();
      if (identificador != null && identificador.isNotEmpty) {
        linhas.add(identificador);
      }
      if (espessura != null && espessura.isNotEmpty) {
        linhas.add('Espessura: ${espessura}mm');
      }
    } else if (tipo == 'orcamento') {
      final tituloOrc = (dados['titulo'] as String?)?.trim();
      titulo = tituloOrc != null && tituloOrc.isNotEmpty
          ? tituloOrc
          : 'Orçamento #${dados['orcamentoId'] ?? '-'}';

      final statusLabel = (dados['statusLabel'] as String?)?.trim();
      if (statusLabel != null && statusLabel.isNotEmpty) {
        linhas.add('Status: $statusLabel');
      }
      final qtdMateriais = dados['quantidadeMateriais'];
      if (qtdMateriais != null) {
        linhas.add('$qtdMateriais ${qtdMateriais == 1 ? 'material' : 'materiais'}');
      }
    } else {
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _abrirOrigem(context, tipo, dados),
        child: Container(
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
        ),
      ),
    );
  }

  void _abrirOrigem(
    BuildContext context,
    String? tipo,
    Map<String, dynamic> dados,
  ) {
    final solicitacaoId = dados['solicitacaoId'] as int?;

    if (tipo == 'orcamento') {
      final orcamentoId = dados['orcamentoId'] as int?;
      if (orcamentoId == null) return;
      context.read<OrcamentoProvider>().solicitarAberturaOrcamento(orcamentoId);
      context.go('/orcamento');
      return;
    }

    if (tipo == 'solicitacao' || solicitacaoId != null) {
      if (solicitacaoId == null) return;
      context.read<SolicitacaoMaterialProvider>().solicitarAberturaSolicitacao(solicitacaoId);
      context.go('/solicitacoes-material');
      return;
    }

    if (tipo == 'material') {
      context.read<MaterialProvider>().solicitarNavegacaoParaMaterialChat(
            FiltroMaterialChat(
              materialId: dados['materialId'] as int?,
              nome: (dados['materialNome'] as String?)?.trim(),
              categoria: (dados['categoria'] as String?)?.trim(),
              identificador: (dados['identificador'] as String?)?.trim(),
              medida: (dados['medida'] as String?)?.trim(),
              espessura: (dados['espessura'] as String?)?.trim(),
            ),
          );
      context.go('/estoque');
    }
  }

  String _fmt(num v) {
    if (v % 1 == 0) return v.toStringAsFixed(0);
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }
}