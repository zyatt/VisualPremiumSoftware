import 'package:flutter/material.dart';
import '../models/solicitacao_material_model.dart';

/// Banner flutuante que desliza da direita para dentro da tela avisando
/// que uma solicitação já existente foi alterada — mesmo padrão
/// visual/animação do [NovaSolicitacaoBanner], mas com os dados da
/// alteração ([SolicitacaoAlteradaNotificacao]).
///
/// Permanece fixo na tela até o usuário fechá-lo manualmente (botão de
/// fechar no card ou toque no card, que também dispara [onTap]).
///
/// Exibido apenas uma vez por evento (quem chama controla isso consumindo
/// a notificação no provider assim que mostra o banner).
class SolicitacaoAlteradaBanner extends StatelessWidget {
  final SolicitacaoAlteradaNotificacao notificacao;
  final VoidCallback? onTap;

  const SolicitacaoAlteradaBanner({
    super.key,
    required this.notificacao,
    this.onTap,
  });

  static void show(
    BuildContext context,
    SolicitacaoAlteradaNotificacao notificacao, {
    VoidCallback? onTap,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerOverlay(
        notificacao: notificacao,
        onDone: () => entry.remove(),
        onTap: onTap,
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => _BannerOverlay(
        notificacao: notificacao,
        onDone: () {},
        onTap: onTap,
      );
}

// ── Versão overlay ────────────────────────────────────────────────────────────

class _BannerOverlay extends StatefulWidget {
  final SolicitacaoAlteradaNotificacao notificacao;
  final VoidCallback onDone;
  final VoidCallback? onTap;
  const _BannerOverlay({
    required this.notificacao,
    required this.onDone,
    this.onTap,
  });

  @override
  State<_BannerOverlay> createState() => _BannerOverlayState();
}

class _BannerOverlayState extends State<_BannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _fechando = false;

  // Posição atual do banner na tela (atualizada ao arrastar).
  double? _top;
  double? _left;

  static const double _cardWidth = 320;
  static const double _margemDireita = 16;

  @override
  void initState() {
    super.initState();

    // Sem timeline fixa: o controller representa apenas o quanto o banner
    // está "aberto" (0 = fora da tela, 1 = totalmente visível). Ele entra
    // uma vez e permanece em 1 até o usuário fechar manualmente.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320), // entrada
      reverseDuration: const Duration(milliseconds: 220), // saída
    );

    _slide = _ctrl.drive(
      Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    );

    _fade = _ctrl.drive(
      Tween<double>(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _garantirPosicaoInicial(Size tela) {
    _top ??= 100;
    _left ??= (tela.width - _cardWidth - _margemDireita).clamp(0.0, tela.width);
  }

  void _arrastar(DragUpdateDetails details, Size tela) {
    setState(() {
      _left = (_left! + details.delta.dx).clamp(0.0, tela.width - 60);
      _top = (_top! + details.delta.dy).clamp(0.0, tela.height - 60);
    });
  }

  /// Toque no corpo do card: dispara a ação (se houver) e fecha o banner.
  void _tocarCard() {
    widget.onTap?.call();
    _fechar();
  }

  /// Botão de fechar: apenas dispensa o banner, sem disparar [onTap].
  void _fechar() {
    if (_fechando) return;
    _fechando = true;
    _ctrl.reverse().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.of(context).size;
    _garantirPosicaoInicial(tela);

    return Positioned(
      top: _top,
      left: _left,
      child: GestureDetector(
        onPanUpdate: (details) => _arrastar(details, tela),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => FractionalTranslation(
              translation: _slide.value,
              child: Opacity(
                opacity: _fade.value,
                child: child,
              ),
            ),
            child: _BannerCard(
              notificacao: widget.notificacao,
              onTap: _tocarCard,
              onClose: _fechar,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card visual ───────────────────────────────────────────────────────────────

class _BannerCard extends StatefulWidget {
  final SolicitacaoAlteradaNotificacao notificacao;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _BannerCard({
    required this.notificacao,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.notificacao;
    final excluido = n.depois?['excluido'] == true;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(maxWidth: 340),
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: _hover ? 1 : 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB45309).withValues(alpha: _hover ? 0.16 : 0.12),
                  blurRadius: _hover ? 24 : 20,
                  offset: Offset(0, _hover ? 8 : 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB45309).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    excluido ? Icons.delete_outline : Icons.edit_note_rounded,
                    color: const Color(0xFFB45309),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Solicitação alterada',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB45309).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                n.numeroOS,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB45309),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        n.nomeCliente,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.editorNome,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (n.item != null && n.item!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          n.item!,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (excluido) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Material removido',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                      if (!excluido && n.antes != null && n.depois != null) ...[
                        const SizedBox(height: 6),
                        ..._buildCamposAlterados(context),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _CloseButton(onTap: widget.onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  List<Widget> _buildCamposAlterados(BuildContext context) {
    final n = widget.notificacao;
    final campos = <String>[];
    
    for (final key in n.depois!.keys) {
      if (key == 'excluido') continue;
      final antes = n.antes![key]?.toString();
      final depois = n.depois![key]?.toString();
      if (antes != depois) campos.add(key);
    }

    if (campos.isEmpty) return [];

    return campos.take(2).map((campo) {
      final label = _camposLabel[campo] ?? campo;
      final antes = _fmt(n.antes![campo]);
      final depois = _fmt(n.depois![campo]);
      
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      const TextSpan(
                        text: 'antes: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      TextSpan(text: antes),
                    ],
                  ),
                ),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      const TextSpan(
                        text: 'depois: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF15803D),
                        ),
                      ),
                      TextSpan(text: depois),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  static const _camposLabel = {
    'numeroOS': 'OS',
    'nomeCliente': 'Cliente',
    'dataNecessidade': 'Necessidade',
    'andamento': 'Andamento',
    'observacao': 'Observação',
    'quantidade': 'Quantidade',
  };

  String _fmt(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    try {
      final d = DateTime.parse(s).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {}
    return s.isEmpty ? '—' : s;
  }
}

// ── Botão de fechar ───────────────────────────────────────────────────────────

class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? onSurfaceVariant.withValues(alpha: 0.12) : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: _hover ? onSurfaceVariant : onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}