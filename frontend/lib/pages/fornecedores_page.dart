import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/fornecedor_model.dart';
import '../providers/fornecedor_provider.dart';
import '../theme/app_theme.dart';
import '../utils/api_client.dart';

/// Resolve uma URL relativa (ex.: "/uploads/fornecedores/x.png") retornada
/// pelo backend para uma URL absoluta, usando o mesmo host configurado no
/// ApiClient. URLs já absolutas (http/https) são retornadas como estão.
String _resolverUrlImagem(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = ApiClient.baseUrl.replaceAll(RegExp(r'/$'), '');
  return '$base$url';
}

/// Formata a dimensão (largura x comprimento) de um material como "50x1.27m"
/// — usado como fallback quando o material não tem `medida` cadastrada.
/// Mesma convenção usada em outras telas (comprimento x largura, minúsculo).
/// Aceita `dynamic` porque esses campos podem chegar como String (ex.:
/// Decimal do Prisma serializado) ou num, dependendo do endpoint.
String? _materialDimensaoFormatada(dynamic larguraRaw, dynamic comprimentoRaw) {
  final largura = larguraRaw is num ? larguraRaw : num.tryParse(larguraRaw?.toString() ?? '');
  final comprimento = comprimentoRaw is num ? comprimentoRaw : num.tryParse(comprimentoRaw?.toString() ?? '');
  if (largura == null || comprimento == null || largura <= 0 || comprimento <= 0) return null;
  String fmt(num v) =>
      v == v.toInt() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  return '${fmt(comprimento)}x${fmt(largura)}m';
}

class _UpperCaseFormatter extends TextInputFormatter {
  static final _acentos = {
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'Ç': 'C', 'ç': 'c',
    'Ñ': 'N', 'ñ': 'n',
  };

  static String _removerAcentos(String s) =>
      s.split('').map((c) => _acentos[c] ?? c).join();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final texto = _removerAcentos(newValue.text).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _MedidaEspessuraFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(',', '.');
    texto = _UpperCaseFormatter._removerAcentos(texto).toUpperCase();
    final partes = texto.split('.');
    if (partes.length > 2) {
      texto = '${partes[0]}.${partes.sublist(1).join('')}';
    }
    final sel = newValue.selection.copyWith(
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _DecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(',', '.');
    texto = texto.replaceAll(RegExp(r'[^\d.]'), '');
    final partes = texto.split('.');
    if (partes.length > 2) {
      texto = '${partes[0]}.${partes.sublist(1).join('')}';
    }
    final sel = newValue.selection.copyWith(
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 14) {
      digits = digits.substring(0, 14);
    }

    String formatted = '';

    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) {
        formatted += '.';
      } else if (i == 8) {
        formatted += '/';
      } else if (i == 12) {
        formatted += '-';
      }

      formatted += digits[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class FornecedoresPage extends StatefulWidget {
  const FornecedoresPage({super.key});

  @override
  State<FornecedoresPage> createState() => _FornecedoresPageState();
}

class _FornecedoresPageState extends State<FornecedoresPage> {
  final _buscaCtrl   = TextEditingController();
  String _tipoFiltro  = '';
  bool   _tipoHovered = false;
  Timer? _debounceTimer;

  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FornecedorProvider>().carregar();
    });
  }

  void _onBuscaChanged(String _) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), _aplicarFiltros);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _abrirFormulario({FornecedorModel? fornecedor}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _FornecedorDialog(
        fornecedor: fornecedor,
        onRemover:  fornecedor != null ? _confirmarRemover : null,
      ),
    ).then((salvou) {
      if (salvou == true) _aplicarFiltros();
    });
  }

  void _aplicarFiltros() {
    context.read<FornecedorProvider>().carregar(
          busca: _buscaCtrl.text,
          tipo: _tipoFiltro,
        );
  }

  void _abrirVincularPorMaterial() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _VincularPorMaterialDialog(
        onSalvo: () => context.read<FornecedorProvider>().recarregar(),
      ),
    );
  }

  void _abrirMateriais(FornecedorModel fornecedor) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MateriaisDialog(fornecedor: fornecedor),
    );
  }

  Future<void> _confirmarRemover(FornecedorModel f) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remover fornecedor'),
        content: Text(
          'Deseja remover "${f.nomeFantasia}"? Esta ação desativará o registro.',
        ),
        actions: [
          Tooltip(
            message: 'Cancelar e fechar sem remover',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                style: TextButton.styleFrom()
                    .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                child: const Text('Cancelar'),
              ),
            ),
          ),
          Tooltip(
            message: 'Confirmar remoção do fornecedor',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                    .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                child: const Text('Remover'),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final prov = context.read<FornecedorProvider>();
    final sucesso = await prov.remover(f.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          sucesso ? 'Fornecedor removido.' : prov.erro ?? 'Erro ao remover.'),
      backgroundColor: sucesso ? AppTheme.success : AppTheme.error,
    ));
    if (sucesso) _aplicarFiltros();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fornecedores',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Gerencie fornecedores e seus materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Vincular vários fornecedores a um material de uma vez',
                  child: OutlinedButton.icon(
                    onPressed: _abrirVincularPorMaterial,
                    icon: const Icon(Icons.category_outlined, size: 18),
                    label: const Text('Vincular por Material'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Cadastrar um novo fornecedor',
                  child: FilledButton.icon(
                    onPressed: () => _abrirFormulario(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Novo Fornecedor'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
                SizedBox(width: 10),
                IconButton(
                  onPressed: () => context.read<FornecedorProvider>().carregar(),
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaCtrl,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome, vendedor ou CNPJ…',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                    onChanged: _onBuscaChanged,
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                Consumer<FornecedorProvider>(
                  builder: (_, p, __) {
                    final tipos = p.tipos;
                    final valorAtual = _tipoFiltro.isEmpty ? null : _tipoFiltro;
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _tipoHovered = true),
                      onExit:  (_) => setState(() => _tipoHovered = false),
                      child: SizedBox(
                        width: 180,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            isDense: true,
                          ),
                          isEmpty: valorAtual == null,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: ValueKey('tipo_${tipos.join('|')}'),
                              value: valorAtual,
                              isDense: true,
                              isExpanded: true,
                              mouseCursor: SystemMouseCursors.click,
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: _tipoHovered
                                    ? AppTheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              items: [
                                const DropdownMenuItem(value: '', child: Text('TODOS', overflow: TextOverflow.ellipsis)),
                                for (final t in tipos)
                                  DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (v) {
                                setState(() => _tipoFiltro = v ?? '');
                                _aplicarFiltros();
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder(
                  valueListenable: _buscaCtrl,
                  builder: (context, v, __) {
                    final temFiltro = v.text.isNotEmpty || _tipoFiltro.isNotEmpty;
                    return IconButton.outlined(
                      tooltip: 'Limpar filtros',
                      icon: Icon(Icons.filter_alt_off,
                          color: scheme.onSurfaceVariant),
                      onPressed: () {
                        if (!temFiltro) return;
                        _buscaCtrl.clear();
                        setState(() => _tipoFiltro = '');
                        context.read<FornecedorProvider>().carregar();
                      },
                      style: IconButton.styleFrom(
                        side: BorderSide(color: Theme.of(context).colorScheme.outline),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.resolveWith((states) {
                          if (!temFiltro) {
                            return SystemMouseCursors.basic;
                          }
                          return SystemMouseCursors.click;
                        }),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

          Expanded(
            child: Consumer<FornecedorProvider>(
              builder: (_, prov, __) {
                if (prov.carregando) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  );
                }
                if (prov.erro != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 48, color: AppTheme.error),
                        SizedBox(height: 12),
                        Text(
                          prov.erro!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: prov.recarregar,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Tentar novamente'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary)
                            .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        ),
                      ],
                    ),
                  );
                }
                if (prov.fornecedores.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _buscaCtrl.text.isNotEmpty || _tipoFiltro.isNotEmpty
                              ? Icons.search_off_outlined
                              : Icons.storefront_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        SizedBox(height: 16),
                        Text(
                          _buscaCtrl.text.isNotEmpty || _tipoFiltro.isNotEmpty
                              ? 'Nenhum fornecedor encontrado'
                              : 'Nenhum fornecedor cadastrado',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _buscaCtrl.text.isNotEmpty || _tipoFiltro.isNotEmpty
                              ? 'Tente um termo diferente.'
                              : 'Clique em "Novo Fornecedor" para começar.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: List.generate(prov.fornecedores.length, (i) {
                      final f = prov.fornecedores[i];
                      final cor = _cores[i % _cores.length];
                      return _FornecedorCard(
                        fornecedor: f,
                        cor: cor,
                        onTap: () => _abrirFormulario(fornecedor: f),
                        onVerMateriais: () => _abrirMateriais(f),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  }
}

class _FornecedorCard extends StatefulWidget {
  final FornecedorModel fornecedor;
  final Color cor;
  final VoidCallback onTap;
  final VoidCallback onVerMateriais;

  const _FornecedorCard({
    required this.fornecedor,
    required this.cor,
    required this.onTap,
    required this.onVerMateriais,
  });

  @override
  State<_FornecedorCard> createState() => _FornecedorCardState();
}

class _FornecedorCardState extends State<_FornecedorCard> {
  bool _hovered = false;
  final _cardKey = GlobalKey();

  void _abrirMenu(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final cardBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;

    // Centraliza o menu dentro do próprio card, em vez de na posição do clique.
    final Rect areaAncora;
    if (cardBox != null) {
      final topLeft = cardBox.localToGlobal(Offset.zero, ancestor: overlay);
      areaAncora = topLeft & cardBox.size;
    } else {
      areaAncora = Offset.zero & overlay.size;
    }

    final opcao = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        areaAncora,
        Offset.zero & overlay.size,
      ),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      items: [
        PopupMenuItem(
          value: 1,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: widget.cor),
                const SizedBox(width: 10),
                const Text('Editar fornecedor'),
              ],
            ),
          ),
        ),
        PopupMenuItem(
          value: 2,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 18, color: widget.cor),
                const SizedBox(width: 10),
                const Text('Materiais vinculados'),
              ],
            ),
          ),
        ),
      ],
    );

    if (opcao == 1) {
      widget.onTap();
    } else if (opcao == 2) {
      widget.onVerMateriais();
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fornecedor;
    final temImagem = f.imagemUrl != null && f.imagemUrl!.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      opaque: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _abrirMenu(context),
        child: AnimatedContainer(
          key: _cardKey,
          duration: const Duration(milliseconds: 150),
          width: 280,
          height: 240,
          decoration: BoxDecoration(
            color: _hovered
                ? widget.cor.withValues(alpha: 0.08)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? widget.cor
                  : widget.cor.withValues(alpha: 0.25),
              width: _hovered ? 2 : 1.5,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.cor.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: Column(
            children: [
              // Imagem ou ícone
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  // Fundo sempre branco por trás da logo, independente do
                  // tema claro/escuro: a maioria dos logos de fornecedores
                  // já vem com fundo branco/opaco próprio, então tingir esse
                  // container com widget.cor (que varia por fornecedor)
                  // deixava algumas logos ilegíveis no escuro e brigando
                  // com a cor do card no claro. Quando não há imagem, o
                  // ícone genérico continua usando a cor do card por cima
                  // de um fundo neutro levemente tingido.
                  color: temImagem
                      ? Colors.white
                      : widget.cor.withValues(alpha: 0.10),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                ),
                child: temImagem
                    ? ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          topRight: Radius.circular(14),
                        ),
                        child: Padding(
                          // Padding evita que a logo encoste nas bordas do
                          // card e garante área de respiro consistente,
                          // já que fit: contain por si só não garante isso
                          // quando a imagem já vem "colada" nas bordas.
                          padding: const EdgeInsets.all(12),
                          child: Image.network(
                            _resolverUrlImagem(f.imagemUrl!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.store,
                              size: 48,
                              color: widget.cor,
                            ),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.store,
                        size: 48,
                        color: widget.cor,
                      ),
              ),
              // Informações
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.nomeFantasia,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _hovered
                              ? widget.cor
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (f.tipoFornecedor != null)
                        Text(
                          f.tipoFornecedor!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 14,
                            color: widget.cor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${f.materiais.length} material${f.materiais.length != 1 ? 'is' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: widget.cor,
                            ),
                          ),
                          const Spacer(),
                          Tooltip(
                            message: 'Editar fornecedor',
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: widget.onTap,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: widget.cor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 14,
                                    color: widget.cor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Ver materiais vinculados',
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: widget.onVerMateriais,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: widget.cor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2_outlined,
                                    size: 14,
                                    color: widget.cor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FornecedorDialog extends StatefulWidget {
  final FornecedorModel? fornecedor;
  final void Function(FornecedorModel)? onRemover;
  const _FornecedorDialog({this.fornecedor, this.onRemover});

  @override
  State<_FornecedorDialog> createState() => _FornecedorDialogState();
}

class _FornecedorDialogState extends State<_FornecedorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeFantasiaCtrl;
  late final TextEditingController _razaoSocialCtrl;
  late final TextEditingController _cnpjCtrl;
  late final TextEditingController _telefoneCtrl;
  late final TextEditingController _nomeVendedorCtrl;
  late final TextEditingController _tipoCtrl;

  File? _imagemSelecionada;
  String? _imagemUrlAtual;

  bool _salvando = false;
  String? _erroDialog;

  Future<void> _selecionarImagem() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      if (await file.exists()) {
        setState(() {
          _imagemSelecionada = file;
          _imagemUrlAtual = null;
        });
      }
    }
  }

  void _removerImagem() {
    setState(() {
      _imagemSelecionada = null;
      _imagemUrlAtual = null;
    });
  }

  bool get _editando => widget.fornecedor != null;

  static String _formatarTelefone(String digits) {
    if (digits.length <= 2) return digits;
    if (digits.length <= 6) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    }
    if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return digits;
  }

  @override
  void initState() {
    super.initState();
    final f = widget.fornecedor;
    _nomeFantasiaCtrl = TextEditingController(text: f?.nomeFantasia ?? '');
    _razaoSocialCtrl = TextEditingController(text: f?.razaoSocial ?? '');
    _cnpjCtrl = TextEditingController(text: f?.cnpj ?? '');
    _telefoneCtrl = TextEditingController(
      text: f?.telefone != null ? _formatarTelefone(f!.telefone!) : '',
    );
    _nomeVendedorCtrl = TextEditingController(text: f?.nomeVendedor ?? '');
    _tipoCtrl = TextEditingController(text: f?.tipoFornecedor ?? '');
    _imagemUrlAtual = f?.imagemUrl;
  }

  @override
  void dispose() {
    _nomeFantasiaCtrl.dispose();
    _razaoSocialCtrl.dispose();
    _cnpjCtrl.dispose();
    _telefoneCtrl.dispose();
    _nomeVendedorCtrl.dispose();
    _tipoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    final telefoneSomenteDigitos =
        _telefoneCtrl.text.replaceAll(RegExp(r'\D'), '');

    final dados = {
      'nomeFantasia': _nomeFantasiaCtrl.text.trim(),
      'razaoSocial': _razaoSocialCtrl.text.trim().isEmpty
          ? null
          : _razaoSocialCtrl.text.trim(),
      'cnpj': _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '').isEmpty
          ? null
          : _cnpjCtrl.text.replaceAll(RegExp(r'\D'), ''),
      'telefone': telefoneSomenteDigitos.isEmpty ? null : telefoneSomenteDigitos,
      'nomeVendedor': _nomeVendedorCtrl.text.trim().isEmpty
          ? null
          : _nomeVendedorCtrl.text.trim(),
      'tipoFornecedor': _tipoCtrl.text.trim().isEmpty
          ? null
          : _tipoCtrl.text.trim(),
    };

    final prov = context.read<FornecedorProvider>();
    final bool sucesso = _editando
        ? await prov.atualizar(widget.fornecedor!.id, dados,
            imagem: _imagemSelecionada)
        : await prov.criar(dados, imagem: _imagemSelecionada);

    if (!mounted) return;
    setState(() => _salvando = false);

    if (sucesso) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            _editando ? 'Fornecedor atualizado.' : 'Fornecedor criado.'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      setState(() => _erroDialog = prov.erro ?? 'Erro ao salvar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _editando ? 'Editar fornecedor' : 'Novo fornecedor',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (_editando && widget.onRemover != null)
                    Tooltip(
                      message: 'Remover este fornecedor',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: TextButton.icon(
                          onPressed: _salvando
                              ? null
                              : () {
                                  Navigator.of(context, rootNavigator: true).pop(false);
                                  widget.onRemover!(widget.fornecedor!);
                                },
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Remover'),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.error)
                              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_erroDialog != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppTheme.error, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _erroDialog!,
                                  style: const TextStyle(
                                      color: AppTheme.error, fontSize: 13),
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _erroDialog = null),
                                child: const Icon(Icons.close,
                                    color: AppTheme.error, size: 16),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextFormField(
                        controller: _nomeFantasiaCtrl,
                        autofocus: !_editando,
                        decoration:
                            const InputDecoration(labelText: 'Nome fantasia *'),
                        inputFormatters: [_UpperCaseFormatter()],
                        onChanged: (_) {
                          if (_erroDialog != null) {
                            setState(() => _erroDialog = null);
                          }
                        },
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Nome Fantasia é obrigatório'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _razaoSocialCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Razão social'),
                        inputFormatters: [_UpperCaseFormatter()],
                      ),
                      const SizedBox(height: 12),

                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cnpjCtrl,
                            decoration: const InputDecoration(labelText: 'CNPJ'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [_CnpjInputFormatter()],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _telefoneCtrl,
                            decoration:
                                const InputDecoration(labelText: 'WhatsAPP'),
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d() \-]')),
                              LengthLimitingTextInputFormatter(14),
                              _TelefoneFormatter(),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final digits = v.replaceAll(RegExp(r'\D'), '');
                              if (digits.length != 10) {
                                return 'Use DDD (2) + 8 dígitos: (42) 9999-9999';
                              }
                              return null;
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nomeVendedorCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Nome do vendedor'),
                            inputFormatters: [_UpperCaseFormatter()],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _tipoCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Tipo de fornecedor'),
                            inputFormatters: [_UpperCaseFormatter()],
                          ),
                        ),
                      ]),

                      const SizedBox(height: 12),

                      if (_imagemSelecionada != null ||
                          (_imagemUrlAtual != null &&
                              _imagemUrlAtual!.isNotEmpty))
                        Container(
                          width: double.infinity,
                          height: 140,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            // Fundo branco fixo, independente do tema: a
                            // maioria das logos enviadas já tem fundo
                            // branco/opaco próprio, então usar a cor de
                            // superfície do tema (escura no dark mode)
                            // deixava o preview com contraste ruim, igual
                            // acontecia no card da listagem.
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _imagemSelecionada != null
                                  ? Image.file(
                                      _imagemSelecionada!,
                                      fit: BoxFit.contain,
                                    )
                                  : Image.network(
                                      _resolverUrlImagem(_imagemUrlAtual!),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selecionarImagem,
                              icon: const Icon(Icons.add_photo_alternate_outlined,
                                  size: 16),
                              label: Text(
                                _imagemSelecionada != null ||
                                        (_imagemUrlAtual != null &&
                                            _imagemUrlAtual!.isNotEmpty)
                                    ? 'Trocar imagem'
                                    : 'Anexar imagem',
                              ),
                              style: OutlinedButton.styleFrom().copyWith(
                                mouseCursor: WidgetStateProperty.all(
                                    SystemMouseCursors.click),
                              ),
                            ),
                          ),
                          if (_imagemSelecionada != null ||
                              (_imagemUrlAtual != null &&
                                  _imagemUrlAtual!.isNotEmpty)) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: _removerImagem,
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Remover'),
                              style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.error)
                                  .copyWith(
                                mouseCursor: WidgetStateProperty.all(
                                    SystemMouseCursors.click),
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),

            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Cancelar e fechar sem salvar',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: TextButton(
                        onPressed: _salvando ? null : () => Navigator.pop(context),
                        style: TextButton.styleFrom().copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _editando
                        ? 'Salvar alterações do fornecedor'
                        : 'Criar novo fornecedor',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: FilledButton(
                        onPressed: _salvando ? null : _salvar,
                        style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary)
                            .copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                        child: _salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_editando ? 'Salvar' : 'Criar'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelefoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 10 ? digits.substring(0, 10) : digits;

    String formatted;
    if (d.isEmpty) {
      formatted = '';
    } else if (d.length <= 2) {
      formatted = '($d';
    } else if (d.length <= 6) {
      formatted = '(${d.substring(0, 2)}) ${d.substring(2)}';
    } else {
      formatted =
          '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _MateriaisDialog extends StatefulWidget {
  final FornecedorModel fornecedor;
  const _MateriaisDialog({required this.fornecedor});

  @override
  State<_MateriaisDialog> createState() => _MateriaisDialogState();
}

class _MateriaisDialogState extends State<_MateriaisDialog> {
  late FornecedorModel _fornecedor;

  final _filtroNomeCtrl         = TextEditingController();
  final _filtroIdentificadorCtrl = TextEditingController();
  final _filtroMedidaCtrl       = TextEditingController();
  final _filtroEspessuraCtrl    = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fornecedor = widget.fornecedor;
    _filtroNomeCtrl.addListener(_atualizar);
    _filtroIdentificadorCtrl.addListener(_atualizar);
    _filtroMedidaCtrl.addListener(_atualizar);
    _filtroEspessuraCtrl.addListener(_atualizar);
  }

  void _atualizar() => setState(() {});

  @override
  void dispose() {
    _filtroNomeCtrl.dispose();
    _filtroIdentificadorCtrl.dispose();
    _filtroMedidaCtrl.dispose();
    _filtroEspessuraCtrl.dispose();
    super.dispose();
  }

  List<FornecedorMaterialVinculoModel> get _materiaisFiltrados {
    final nome         = _filtroNomeCtrl.text.trim().toLowerCase();
    final identificador = _filtroIdentificadorCtrl.text.trim().toLowerCase();
    final medida       = _filtroMedidaCtrl.text.trim().toLowerCase();
    final espessura    = _filtroEspessuraCtrl.text.trim().toLowerCase();

    return _fornecedor.materiais.where((m) {
      if (nome.isNotEmpty &&
          !(m.materialNome ?? '').toLowerCase().contains(nome)) {
        return false;
      }
      if (identificador.isNotEmpty &&
          !(m.materialIdentificador ?? '').toLowerCase().contains(identificador)) {
        return false;
      }
      if (medida.isNotEmpty &&
          !(m.materialMedida ?? '').toLowerCase().contains(medida)) {
        return false;
      }
      if (espessura.isNotEmpty &&
          !(m.materialEspessura ?? '').toLowerCase().contains(espessura)) {
        return false;
      }
      return true;
    }).toList();
  }

  bool get _temFiltro =>
      _filtroNomeCtrl.text.isNotEmpty ||
      _filtroIdentificadorCtrl.text.isNotEmpty ||
      _filtroMedidaCtrl.text.isNotEmpty ||
      _filtroEspessuraCtrl.text.isNotEmpty;

  void _limparFiltros() {
    _filtroNomeCtrl.clear();
    _filtroIdentificadorCtrl.clear();
    _filtroMedidaCtrl.clear();
    _filtroEspessuraCtrl.clear();
  }

  Future<void> _recarregar() async {
    final prov = context.read<FornecedorProvider>();
    final atualizado = await prov.buscarPorId(_fornecedor.id);
    if (atualizado != null && mounted) {
      setState(() => _fornecedor = atualizado);
    }
  }

  Future<void> _desvincular(FornecedorMaterialVinculoModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Desvincular material'),
        content: Text(
            'Remover "${m.materialNome ?? 'material'}" deste fornecedor?'),
        actions: [
          Tooltip(
            message: 'Cancelar e fechar sem desvincular',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                style: TextButton.styleFrom().copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                child: const Text('Cancelar'),
              ),
            ),
          ),
          Tooltip(
            message: 'Confirmar desvínculo do material',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                    .copyWith(
                        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                child: const Text('Desvincular'),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final prov = context.read<FornecedorProvider>();
      final sucesso = await prov.desvincularMaterial(_fornecedor.id, m.materialId);
      if (sucesso) await _recarregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              sucesso ? 'Material desvinculado.' : prov.erro ?? 'Erro'),
          backgroundColor: sucesso ? AppTheme.success : AppTheme.error,
        ));
      }
    }
  }

  void _abrirVincularOuEditar({FornecedorMaterialVinculoModel? vinculo}) {
    showDialog(
      context: context,
      builder: (_) => _VinculoMaterialDialog(
        fornecedorId: _fornecedor.id,
        vinculo: vinculo,
        materiaisVinculados: _fornecedor.materiais
            .where((m) => m.ativo)
            .map((m) => m.materialId)
            .toSet(),
        onSalvo: _recarregar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final materiais = _materiaisFiltrados;
    final total     = _fornecedor.materiais.length;

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: SizedBox(
        width: 660,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Materiais vinculados',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                        ),
                        SizedBox(height: 2),
                        Text(
                          _fornecedor.nomeFantasia,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Vincular novo material a este fornecedor',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: FilledButton.icon(
                        onPressed: () => _abrirVincularOuEditar(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Vincular'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ).copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Tooltip(
                    message: 'Fechar',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        style: IconButton.styleFrom().copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _filtroNomeCtrl,
                          autofocus: true,
                          inputFormatters: [_UpperCaseFormatter()],
                          decoration: InputDecoration(
                            hintText: 'Buscar por nome…',
                            prefixIcon: Icon(Icons.search,
                                color: Theme.of(context).colorScheme.outline, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            suffixIcon: ValueListenableBuilder(
                              valueListenable: _filtroNomeCtrl,
                              builder: (_, v, __) => v.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, size: 16),
                                      onPressed: _filtroNomeCtrl.clear,
                                      color: Theme.of(context).colorScheme.outline,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Limpar filtros',
                        child: IconButton.outlined(
                          icon: Icon(Icons.filter_alt_off, size: 18),
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            if (!_temFiltro) return;
                            _limparFiltros();
                          },
                          style: IconButton.styleFrom().copyWith(
                            mouseCursor: WidgetStateProperty.resolveWith((states) {
                              if (!_temFiltro) {
                                return SystemMouseCursors.basic;
                              }
                              return SystemMouseCursors.click;
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _filtroIdentificadorCtrl,
                          inputFormatters: [_UpperCaseFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'Identificador',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _filtroMedidaCtrl,
                          inputFormatters: [_MedidaEspessuraFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'Medida',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _filtroEspessuraCtrl,
                          inputFormatters: [_MedidaEspessuraFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'Espessura',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _temFiltro
                              ? '${materiais.length} de $total material${total != 1 ? 'is' : ''}'
                              : '$total material${total != 1 ? 'is' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

            Expanded(
              child: total == 0
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 48, color: Theme.of(context).colorScheme.outline),
                          SizedBox(height: 12),
                          Text(
                            'Nenhum material vinculado',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : materiais.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_outlined,
                                  size: 48, color: Theme.of(context).colorScheme.outline),
                              SizedBox(height: 12),
                              Text(
                                'Nenhum material encontrado',
                                style:
                                    TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: _limparFiltros,
                                child: const Text('Limpar filtros'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: materiais.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _VinculoCard(
                            vinculo: materiais[i],
                            onEditar: () =>
                                _abrirVincularOuEditar(vinculo: materiais[i]),
                            onDesvincular: () => _desvincular(materiais[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VinculoCard extends StatefulWidget {
  final FornecedorMaterialVinculoModel vinculo;
  final VoidCallback onEditar;
  final VoidCallback onDesvincular;

  const _VinculoCard({
    required this.vinculo,
    required this.onEditar,
    required this.onDesvincular,
  });

  @override
  State<_VinculoCard> createState() => _VinculoCardState();
}

class _VinculoCardState extends State<_VinculoCard> {
  bool _hovered = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vinculo;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit: _onExit,
      child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFFFF9800).withValues(alpha: 0.08)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onEditar,
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.category_outlined,
                              color: AppTheme.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.descricaoCompleta,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurface),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _PriceTag(label: 'Valor:', valor: v.preco),
                                  const SizedBox(width: 10),
                                  _PriceTag(label: 'Valor m²:', valor: v.precoMetroQuadrado),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDesvincular,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.link_off, size: 18, color: AppTheme.error),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final String label;
  final double valor;
  const _PriceTag({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: 'R\$ ${FornecedorMaterialVinculoModel.formatarPreco(valor)}',
            style: const TextStyle(
                color: AppTheme.success, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VinculoMaterialDialog extends StatefulWidget {
  final int fornecedorId;
  final FornecedorMaterialVinculoModel? vinculo;
  final Set<int> materiaisVinculados;
  final Future<void> Function() onSalvo;

  const _VinculoMaterialDialog({
    required this.fornecedorId,
    this.vinculo,
    this.materiaisVinculados = const {},
    required this.onSalvo,
  });

  @override
  State<_VinculoMaterialDialog> createState() => _VinculoMaterialDialogState();
}

class _VinculoMaterialDialogState extends State<_VinculoMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _materialIdCtrl = TextEditingController();
  final _materialNomeCtrl = TextEditingController();
  final _materialIdentificadorCtrl = TextEditingController();
  final _materialMedidaCtrl = TextEditingController();
  final _materialEspessuraCtrl = TextEditingController();
  final _precoCtrl = TextEditingController();
  final _precoM2Ctrl = TextEditingController();
  bool _salvando = false;

  List<Map<String, dynamic>> _sugestoes = [];
  bool _buscandoMateriais = false;
  int? _materialIdSelecionado;
  bool _idNaoEncontrado = false;
  Timer? _debounceId;
  bool _ignorarListeners = false;

  bool get _editando => widget.vinculo != null;

  @override
  void initState() {
    super.initState();
    if (_editando) {
      final v = widget.vinculo!;
      _materialIdCtrl.text = v.materialId.toString();
      _materialNomeCtrl.text = v.materialNome ?? v.descricaoCompleta;
      _materialIdentificadorCtrl.text = v.materialIdentificador ?? '';
      _materialMedidaCtrl.text = v.materialMedida ?? '';
      _materialEspessuraCtrl.text = v.materialEspessura ?? '';
      _materialIdSelecionado = v.materialId;
      _precoCtrl.text = v.preco == 0 ? '' : FornecedorMaterialVinculoModel.formatarPreco(v.preco).replaceAll(',', '.');
      _precoM2Ctrl.text = v.precoMetroQuadrado == 0 ? '' : FornecedorMaterialVinculoModel.formatarPreco(v.precoMetroQuadrado).replaceAll(',', '.');
    }

    _materialIdCtrl.addListener(_onIdChanged);
    _materialNomeCtrl.addListener(_onNomeChanged);
    _materialIdentificadorCtrl.addListener(_onFiltroAdicionalChanged);
    _materialMedidaCtrl.addListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.addListener(_onFiltroAdicionalChanged);
  }

  @override
  void dispose() {
    _debounceId?.cancel();
    _materialIdCtrl.removeListener(_onIdChanged);
    _materialNomeCtrl.removeListener(_onNomeChanged);
    _materialIdentificadorCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialMedidaCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialIdCtrl.dispose();
    _materialNomeCtrl.dispose();
    _materialIdentificadorCtrl.dispose();
    _materialMedidaCtrl.dispose();
    _materialEspessuraCtrl.dispose();
    _precoCtrl.dispose();
    _precoM2Ctrl.dispose();
    super.dispose();
  }

  void _limparSelecaoMaterial() {
    _debounceId?.cancel();
    _ignorarListeners = true;
    _materialIdCtrl.text        = '';
    _materialNomeCtrl.text      = '';
    _materialIdentificadorCtrl.text = '';
    _materialMedidaCtrl.text    = '';
    _materialEspessuraCtrl.text = '';
    _ignorarListeners = false;
    setState(() {
      _sugestoes             = [];
      _materialIdSelecionado = null;
      _idNaoEncontrado       = false;
    });
  }

  void _onIdChanged() {
    if (_ignorarListeners) return;
    final texto = _materialIdCtrl.text.trim();

    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialNomeCtrl.text          = '';
      _materialIdentificadorCtrl.text = '';
      _materialMedidaCtrl.text        = '';
      _materialEspessuraCtrl.text     = '';
      _ignorarListeners = false;
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
      return;
    }

    final idDigitadoAgora = int.tryParse(texto);
    if (idDigitadoAgora != null && idDigitadoAgora == _materialIdSelecionado) return;

    if (_materialIdSelecionado != null || _idNaoEncontrado) {
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
    }

    _debounceId?.cancel();
    _debounceId = Timer(const Duration(milliseconds: 500), () async {
      final idDigitado = int.tryParse(texto);
      if (idDigitado == null || !mounted) return;

      setState(() {
        _buscandoMateriais = true;
        _sugestoes         = [];
      });

      try {
        final prov  = context.read<FornecedorProvider>();
        final lista = await prov.buscarMateriais(idPrefix: texto);

        if (!mounted) return;

        final match = lista
            .where((m) => int.tryParse(m['id'].toString()) == idDigitado)
            .toList();

        if (match.isNotEmpty) {
          _selecionarMaterial(match.first);
        } else {
          _ignorarListeners = true;
          _materialNomeCtrl.text          = '';
          _materialIdentificadorCtrl.text = '';
          _ignorarListeners = false;
          setState(() {
            _sugestoes       = [];
            _idNaoEncontrado = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _idNaoEncontrado = false);
      } finally {
        if (mounted) setState(() => _buscandoMateriais = false);
      }
    });
  }

  void _onNomeChanged() {
    if (_ignorarListeners) return;
    final texto = _materialNomeCtrl.text.trim();

    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialIdCtrl.text            = '';
      _materialIdentificadorCtrl.text = '';
      _materialMedidaCtrl.text        = '';
      _materialEspessuraCtrl.text     = '';
      _ignorarListeners = false;
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
      return;
    }

    if (_materialIdSelecionado != null) return;
    _buscarMateriais(nomePrefix: texto);
  }

  void _onFiltroAdicionalChanged() {
    if (_ignorarListeners) return;
    if (_materialIdSelecionado != null) {
      _ignorarListeners = true;
      _materialIdCtrl.text = '';
      _ignorarListeners = false;
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
    }
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialIdentificadorCtrl.text.trim().isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    } else {
      setState(() => _sugestoes = []);
    }
  }

  void _onFiltroAdicionalFocus() {
    if (_materialIdSelecionado != null) return;
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialIdentificadorCtrl.text.trim().isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    }
  }

  Future<void> _buscarMateriais({String? idPrefix, String? nomePrefix}) async {
    setState(() => _buscandoMateriais = true);
    try {
      final prov  = context.read<FornecedorProvider>();
      final lista = await prov.buscarMateriais(
        idPrefix:   idPrefix,
        nomePrefix: nomePrefix,
        identificador: _materialIdentificadorCtrl.text.trim().isEmpty ? null : _materialIdentificadorCtrl.text.trim(),
        medida:    _materialMedidaCtrl.text.trim().isEmpty ? null : _materialMedidaCtrl.text.trim(),
        espessura: _materialEspessuraCtrl.text.trim().isEmpty ? null : _materialEspessuraCtrl.text.trim(),
      );
      if (mounted) setState(() => _sugestoes = lista);
    } catch (_) {
      if (mounted) setState(() => _sugestoes = []);
    } finally {
      if (mounted) setState(() => _buscandoMateriais = false);
    }
  }

  void _selecionarMaterial(Map<String, dynamic> material) {
    final id           = material['id']           as int;
    final nome         = material['nome']         as String? ?? '';
    final identificador = material['identificador'] as String?;
    final medida       = material['medida']       as String?;
    final espessura    = material['espessura']    as String?;

    _ignorarListeners = true;
    _materialIdCtrl.text            = id.toString();
    _materialNomeCtrl.text          = nome;
    _materialIdentificadorCtrl.text = identificador ?? '';
    _materialMedidaCtrl.text        = medida    ?? '';
    _materialEspessuraCtrl.text     = espessura ?? '';
    _ignorarListeners = false;

    setState(() {
      _materialIdSelecionado = id;
      _idNaoEncontrado       = false;
      _sugestoes             = [];
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);

    final prov = context.read<FornecedorProvider>();

    double? parsePreco(String text) {
      final v = text.trim().replaceAll(',', '.');
      return v.isEmpty ? null : double.tryParse(v);
    }

    final dados = {
      'preco': parsePreco(_precoCtrl.text),
      'precoMetroQuadrado': parsePreco(_precoM2Ctrl.text),
    };

    bool sucesso;
    if (_editando) {
      sucesso = await prov.atualizarPreco(
          widget.fornecedorId, widget.vinculo!.materialId, dados);
    } else {
      sucesso = await prov.vincularMaterial(widget.fornecedorId, {
        'materialId': _materialIdSelecionado ?? int.parse(_materialIdCtrl.text),
        ...dados,
      });
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    if (sucesso) {
      await widget.onSalvo();
      if (mounted) Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(prov.erro ?? 'Erro ao salvar'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(_editando ? 'Editar valor' : 'Vincular material'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_editando) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _materialNomeCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Nome do material *',
                          isDense: true,
                          suffixIcon: _buscandoMateriais
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primary),
                                  ),
                                )
                              : _materialIdSelecionado != null
                                  ? const Icon(Icons.check_circle,
                                      color: AppTheme.success, size: 18)
                                  : null,
                        ),
                        inputFormatters: [_UpperCaseFormatter()],
                        validator: (v) {
                          if (_materialIdSelecionado == null &&
                              (v == null || v.trim().isEmpty)) {
                            return 'Selecione um material pelo nome ou ID';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _materialIdentificadorCtrl,
                        decoration: InputDecoration(
                          labelText: 'Identificador',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.qr_code_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          suffixIcon: _materialIdSelecionado != null &&
                                  _materialIdentificadorCtrl.text.isNotEmpty
                              ? const Icon(Icons.check_circle,
                                  color: AppTheme.success, size: 16)
                              : null,
                        ),
                        inputFormatters: [_UpperCaseFormatter()],
                        readOnly: _materialIdSelecionado != null,
                        onTap: _onFiltroAdicionalFocus,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _materialMedidaCtrl,
                        decoration: InputDecoration(
                          labelText: 'Medida',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.straighten_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        inputFormatters: [_MedidaEspessuraFormatter()],
                        onTap: _onFiltroAdicionalFocus,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: TextFormField(
                        controller: _materialEspessuraCtrl,
                        decoration: InputDecoration(
                          labelText: 'Espessura',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.layers_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        inputFormatters: [_MedidaEspessuraFormatter()],
                        onTap: _onFiltroAdicionalFocus,
                      ),
                    ),

                    const SizedBox(width: 8),

                    TextButton.icon(
                      onPressed: _limparSelecaoMaterial,
                      icon: Icon(Icons.clear_all, size: 16),
                      label: Text('Limpar'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),

                if (_sugestoes.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _sugestoes.length,
                      itemBuilder: (_, i) {
                        final m = _sugestoes[i];
                        final identificador = m['identificador'] as String?;
                        final medidaOuDimensao = (m['medida'] as String?)?.isNotEmpty == true
                            ? m['medida'] as String?
                            : _materialDimensaoFormatada(m['largura'], m['comprimento']);
                        final espessura = m['espessura'] as String?;
                        final detalhe = [
                          if (identificador != null && identificador.isNotEmpty) identificador,
                          if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
                          if (espessura != null && espessura.isNotEmpty) espessura,
                        ].join(' · ');

                        final jaVinculado = widget.materiaisVinculados
                            .contains(m['id'] as int);

                        return InkWell(
                          onTap: jaVinculado ? null : () => _selecionarMaterial(m),
                          child: Opacity(
                            opacity: jaVinculado ? 0.45 : 1.0,
                            child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${m['id']}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m['nome'] ?? '',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (detalhe.isNotEmpty)
                                        Text(
                                          detalhe,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (jaVinculado)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.outline
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Já vinculado',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],

              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _precoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Valor (R\$)',
                      prefixText: 'R\$ ',
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalInputFormatter()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _precoM2Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Valor m² (R\$)',
                      prefixText: 'R\$ ',
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalInputFormatter()],
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        Tooltip(
          message: 'Cancelar e fechar sem salvar',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: const Text('Cancelar'),
            ),
          ),
        ),
        Tooltip(
          message: 'Salvar vínculo do material',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                  .copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Salvar'),
            ),
          ),
        ),
      ],
    );
  }
}

class _FornecedorVinculoEntry {
  final FornecedorModel fornecedor;
  bool selecionado;
  final TextEditingController precoCtrl;
  final TextEditingController precoM2Ctrl;
  final bool jaVinculado;

  _FornecedorVinculoEntry({
    required this.fornecedor,
    required this.selecionado,
    required this.precoCtrl,
    required this.precoM2Ctrl,
    this.jaVinculado = false,
  });

  void dispose() {
    precoCtrl.dispose();
    precoM2Ctrl.dispose();
  }
}

class _VincularPorMaterialDialog extends StatefulWidget {
  final Future<void> Function() onSalvo;
  const _VincularPorMaterialDialog({required this.onSalvo});

  @override
  State<_VincularPorMaterialDialog> createState() =>
      _VincularPorMaterialDialogState();
}

class _VincularPorMaterialDialogState
    extends State<_VincularPorMaterialDialog> {
  final _materialIdCtrl       = TextEditingController();
  final _materialNomeCtrl     = TextEditingController();
  final _materialIdentificadorCtrl = TextEditingController();
  final _materialMedidaCtrl   = TextEditingController();
  final _materialEspessuraCtrl = TextEditingController();

  int?   _materialIdSelecionado;
  bool   _buscandoMaterial  = false;
  bool   _idNaoEncontrado   = false;
  bool   _ignorarListeners  = false;
  List<Map<String, dynamic>> _sugestoes = [];
  Timer? _debounceId;

  List<_FornecedorVinculoEntry> _entradas = [];
  bool _carregandoFornecedores = false;

  bool _salvando = false;

  final _buscaFornecedorCtrl  = TextEditingController();
  final _buscaFornecedorFocus = FocusNode();
  final _buscaLayerLink       = LayerLink();
  OverlayEntry? _overlayEntry;
  List<FornecedorModel> _sugestoesFornecedor = [];
  bool _buscandoFornecedor = false;
  Timer? _debounceFornecedor;

  @override
  void initState() {
    super.initState();
    _materialIdCtrl.addListener(_onIdChanged);
    _materialNomeCtrl.addListener(_onNomeChanged);
    _materialIdentificadorCtrl.addListener(_onFiltroAdicionalChanged);
    _materialMedidaCtrl.addListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.addListener(_onFiltroAdicionalChanged);
    _buscaFornecedorCtrl.addListener(_onBuscaFornecedorChanged);
    _buscaFornecedorFocus.addListener(_onBuscaFornecedorFocusChanged);
    _carregarFornecedores();
  }

  @override
  void dispose() {
    _debounceId?.cancel();
    _debounceFornecedor?.cancel();
    _materialIdCtrl.removeListener(_onIdChanged);
    _materialNomeCtrl.removeListener(_onNomeChanged);
    _materialIdentificadorCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialMedidaCtrl.removeListener(_onFiltroAdicionalChanged);
    _materialEspessuraCtrl.removeListener(_onFiltroAdicionalChanged);
    _buscaFornecedorCtrl.removeListener(_onBuscaFornecedorChanged);
    _buscaFornecedorFocus.removeListener(_onBuscaFornecedorFocusChanged);
    _overlayEntry?.remove();
    _overlayEntry = null;
    _materialIdCtrl.dispose();
    _materialNomeCtrl.dispose();
    _materialIdentificadorCtrl.dispose();
    _materialMedidaCtrl.dispose();
    _materialEspessuraCtrl.dispose();
    _buscaFornecedorCtrl.dispose();
    _buscaFornecedorFocus.dispose();
    for (final e in _entradas) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarFornecedores() async {
  }

  void _mostrarOverlay() {
    _fecharOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (_) => _BuscaFornecedorOverlay(
        layerLink:  _buscaLayerLink,
        sugestoes:  _sugestoesFornecedor,
        carregando: _buscandoFornecedor,
        onSelecionar: _adicionarFornecedorDoOverlay,
        onFechar:   _fecharOverlay,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _fecharOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _atualizarOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _onBuscaFornecedorFocusChanged() {
    if (_buscaFornecedorFocus.hasFocus) {
      _dispararBuscaFornecedor(_buscaFornecedorCtrl.text.trim());
    } else {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_buscaFornecedorFocus.hasFocus) {
          _fecharOverlay();
        }
      });
    }
  }

  void _onBuscaFornecedorChanged() {
    if (_materialIdSelecionado == null) return;
    _dispararBuscaFornecedor(_buscaFornecedorCtrl.text.trim());
  }

  void _dispararBuscaFornecedor(String texto) {
    if (_materialIdSelecionado == null) return;

    _debounceFornecedor?.cancel();

    if (_overlayEntry == null) _mostrarOverlay();

    _debounceFornecedor = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _buscandoFornecedor = true);
      _atualizarOverlay();
      try {
        final prov = context.read<FornecedorProvider>();
        final lista = await prov.buscarFornecedores(
            busca: texto.isEmpty ? null : texto);
        if (!mounted) return;
        final idsExistentes = _entradas.map((e) => e.fornecedor.id).toSet();
        setState(() {
          _sugestoesFornecedor =
              lista.where((f) => !idsExistentes.contains(f.id)).toList();
          _buscandoFornecedor = false;
        });
        if (_overlayEntry == null) {
          _mostrarOverlay();
        } else {
          _atualizarOverlay();
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _sugestoesFornecedor = [];
            _buscandoFornecedor  = false;
          });
          _atualizarOverlay();
        }
      }
    });
  }

  void _adicionarFornecedorDoOverlay(FornecedorModel f) {
    setState(() {
      _entradas.add(_FornecedorVinculoEntry(
        fornecedor:  f,
        selecionado: true,
        precoCtrl:   TextEditingController(),
        precoM2Ctrl: TextEditingController(),
        jaVinculado: false,
      ));
      _sugestoesFornecedor.removeWhere((s) => s.id == f.id);
    });
    _atualizarOverlay();
  }

  Future<void> _carregarFornecedoresDoMaterial(int materialId) async {
    setState(() => _carregandoFornecedores = true);
    try {
      final prov = context.read<FornecedorProvider>();
      final lista = await prov.listarPorMaterial(materialId);
      if (!mounted) return;
      _reconstruirEntradas(lista, materialTrocou: true);
    } finally {
      if (mounted) setState(() => _carregandoFornecedores = false);
    }
  }

  void _reconstruirEntradas(
    List<FornecedorModel> fornecedores, {
    bool materialTrocou = false,
  }) {
    if (materialTrocou) {
      for (final e in _entradas) {
        e.dispose();
      }
      _entradas = [];
    }

    final antigos = {for (final e in _entradas) e.fornecedor.id: e};

    final novas = <_FornecedorVinculoEntry>[];
    for (final f in fornecedores) {
      FornecedorMaterialVinculoModel? vinculo;
      if (_materialIdSelecionado != null) {
        try {
          vinculo = f.materiais.firstWhere(
            (m) => m.materialId == _materialIdSelecionado && m.ativo,
          );
        } catch (_) {
          vinculo = null;
        }
      }

      final antigo = antigos[f.id];
      final jaVinculado = vinculo != null;

      String precoInicial   = '';
      String precoM2Inicial = '';
      if (!materialTrocou && antigo != null && antigo.precoCtrl.text.isNotEmpty) {
        precoInicial   = antigo.precoCtrl.text;
        precoM2Inicial = antigo.precoM2Ctrl.text;
      } else if (jaVinculado) {
        precoInicial   = vinculo.preco.toStringAsFixed(2);
        precoM2Inicial = vinculo.precoMetroQuadrado.toStringAsFixed(2);
      }

      novas.add(_FornecedorVinculoEntry(
        fornecedor: f,
        selecionado: materialTrocou ? jaVinculado : (antigo?.selecionado ?? jaVinculado),
        precoCtrl:   TextEditingController(text: precoInicial),
        precoM2Ctrl: TextEditingController(text: precoM2Inicial),
        jaVinculado: jaVinculado,
      ));

      if (!materialTrocou) antigo?.dispose();
    }

    _entradas = novas;
  }

  void _limparSelecaoMaterial() {
    _debounceId?.cancel();
    _ignorarListeners = true;
    _materialIdCtrl.text            = '';
    _materialNomeCtrl.text          = '';
    _materialIdentificadorCtrl.text = '';
    _materialMedidaCtrl.text        = '';
    _materialEspessuraCtrl.text     = '';
    _ignorarListeners = false;
    for (final e in _entradas) { e.dispose(); }
    setState(() {
      _sugestoes             = [];
      _materialIdSelecionado = null;
      _idNaoEncontrado       = false;
      _entradas              = [];
    });
  }

  void _onIdChanged() {
    if (_ignorarListeners) return;
    final texto = _materialIdCtrl.text.trim();

    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialNomeCtrl.text          = '';
      _materialIdentificadorCtrl.text = '';
      _materialMedidaCtrl.text        = '';
      _materialEspessuraCtrl.text     = '';
      _ignorarListeners = false;
      for (final e in _entradas) { e.dispose(); }
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
        _entradas              = [];
      });
      return;
    }

    final idDigitadoAgora = int.tryParse(texto);
    if (idDigitadoAgora != null && idDigitadoAgora == _materialIdSelecionado) return;

    if (_materialIdSelecionado != null || _idNaoEncontrado) {
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
      });
    }

    _debounceId?.cancel();
    _debounceId = Timer(const Duration(milliseconds: 500), () async {
      final idDigitado = int.tryParse(texto);
      if (idDigitado == null || !mounted) return;
      setState(() {
        _buscandoMaterial = true;
        _sugestoes        = [];
      });
      try {
        final prov  = context.read<FornecedorProvider>();
        final lista = await prov.buscarMateriais(idPrefix: texto);
        if (!mounted) return;
        final match =
            lista.where((m) => int.tryParse(m['id'].toString()) == idDigitado).toList();
        if (match.isNotEmpty) {
          _selecionarMaterial(match.first);
        } else {
          _ignorarListeners = true;
          _materialNomeCtrl.text          = '';
          _materialIdentificadorCtrl.text = '';
          _ignorarListeners = false;
          setState(() {
            _sugestoes       = [];
            _idNaoEncontrado = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _idNaoEncontrado = false);
      } finally {
        if (mounted) setState(() => _buscandoMaterial = false);
      }
    });
  }

  void _onNomeChanged() {
    if (_ignorarListeners) return;
    final texto = _materialNomeCtrl.text.trim();

    if (texto.isEmpty) {
      _debounceId?.cancel();
      _ignorarListeners = true;
      _materialIdCtrl.text            = '';
      _materialIdentificadorCtrl.text = '';
      _materialMedidaCtrl.text        = '';
      _materialEspessuraCtrl.text     = '';
      _ignorarListeners = false;
      for (final e in _entradas) { e.dispose(); }
      setState(() {
        _sugestoes             = [];
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
        _entradas              = [];
      });
      return;
    }
    if (_materialIdSelecionado != null) return;
    _buscarMateriais(nomePrefix: texto);
  }

  void _onFiltroAdicionalChanged() {
    if (_ignorarListeners) return;
    if (_materialIdSelecionado != null) {
      _ignorarListeners = true;
      _materialIdCtrl.text = '';
      _ignorarListeners = false;
      for (final e in _entradas) { e.dispose(); }
      setState(() {
        _materialIdSelecionado = null;
        _idNaoEncontrado       = false;
        _entradas              = [];
      });
    }
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialIdentificadorCtrl.text.trim().isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    } else {
      setState(() => _sugestoes = []);
    }
  }

  void _onFiltroAdicionalFocus() {
    if (_materialIdSelecionado != null) return;
    final nome = _materialNomeCtrl.text.trim();
    if (nome.isNotEmpty ||
        _materialIdentificadorCtrl.text.trim().isNotEmpty ||
        _materialMedidaCtrl.text.trim().isNotEmpty ||
        _materialEspessuraCtrl.text.trim().isNotEmpty) {
      _buscarMateriais(nomePrefix: nome.isEmpty ? null : nome);
    }
  }

  Future<void> _buscarMateriais({String? idPrefix, String? nomePrefix}) async {
    setState(() => _buscandoMaterial = true);
    try {
      final prov  = context.read<FornecedorProvider>();
      final lista = await prov.buscarMateriais(
        idPrefix:      idPrefix,
        nomePrefix:    nomePrefix,
        identificador: _materialIdentificadorCtrl.text.trim().isEmpty ? null : _materialIdentificadorCtrl.text.trim(),
        medida:        _materialMedidaCtrl.text.trim().isEmpty ? null : _materialMedidaCtrl.text.trim(),
        espessura:     _materialEspessuraCtrl.text.trim().isEmpty ? null : _materialEspessuraCtrl.text.trim(),
      );
      if (mounted) setState(() => _sugestoes = lista);
    } catch (_) {
      if (mounted) setState(() => _sugestoes = []);
    } finally {
      if (mounted) setState(() => _buscandoMaterial = false);
    }
  }

  void _selecionarMaterial(Map<String, dynamic> material) {
    final id            = material['id']            as int;
    final nome          = material['nome']          as String? ?? '';
    final identificador = material['identificador'] as String?;
    final medida        = material['medida']        as String?;
    final espessura     = material['espessura']     as String?;

    _ignorarListeners = true;
    _materialIdCtrl.text            = id.toString();
    _materialNomeCtrl.text          = nome;
    _materialIdentificadorCtrl.text = identificador ?? '';
    _materialMedidaCtrl.text        = medida    ?? '';
    _materialEspessuraCtrl.text     = espessura ?? '';
    _ignorarListeners = false;

    _materialIdSelecionado = id;

    setState(() {
      _idNaoEncontrado = false;
      _sugestoes       = [];
    });

    _carregarFornecedoresDoMaterial(id);
  }

  Future<void> _salvar() async {
    if (_materialIdSelecionado == null) return;

    if (_entradas.isEmpty) return;

    setState(() => _salvando = true);

    double? parsePreco(String text) {
      final v = text.trim().replaceAll(',', '.');
      return v.isEmpty ? null : double.tryParse(v);
    }

    final prov   = context.read<FornecedorProvider>();
    int sucessos = 0;
    int falhas   = 0;

    for (final entrada in _entradas) {
      final dados = {
        'materialId': _materialIdSelecionado,
        'preco':               parsePreco(entrada.precoCtrl.text),
        'precoMetroQuadrado':  parsePreco(entrada.precoM2Ctrl.text),
      };
      final ok = await prov.vincularMaterial(entrada.fornecedor.id, dados);
      if (ok) {
        sucessos++;
      } else {
        falhas++;
      }
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    await widget.onSalvo();

    if (mounted) {
      final msg = falhas == 0
          ? '$sucessos fornecedor(es) vinculado(s) com sucesso.'
          : '$sucessos vinculado(s), $falhas com erro.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: falhas == 0 ? AppTheme.success : AppTheme.error,
      ));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: SizedBox(
        width: 720,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vincular por Material',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Selecione um material e vincule a vários fornecedores',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Fechar',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        style: IconButton.styleFrom().copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height:1, color: Theme.of(context).colorScheme.outlineVariant),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Material',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _materialNomeCtrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'Nome do material',
                            isDense: true,
                            suffixIcon: _buscandoMaterial
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primary),
                                    ),
                                  )
                                : _materialIdSelecionado != null
                                    ? const Icon(Icons.check_circle,
                                        color: AppTheme.success, size: 18)
                                    : null,
                          ),
                          inputFormatters: [_UpperCaseFormatter()],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _materialIdentificadorCtrl,
                          decoration: InputDecoration(
                            labelText: 'Identificador',
                            isDense: true,
                            prefixIcon: Icon(Icons.qr_code_outlined,
                                size: 16, color: Theme.of(context).colorScheme.outline),
                            suffixIcon: _materialIdSelecionado != null &&
                                    _materialIdentificadorCtrl.text.isNotEmpty
                                ? const Icon(Icons.check_circle,
                                    color: AppTheme.success, size: 16)
                                : null,
                          ),
                          inputFormatters: [_UpperCaseFormatter()],
                          readOnly: _materialIdSelecionado != null,
                          onTap: _onFiltroAdicionalFocus,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _materialMedidaCtrl,
                          decoration: InputDecoration(
                            labelText: 'Medida',
                            isDense: true,
                            prefixIcon: Icon(Icons.straighten_outlined,
                                size: 16, color: Theme.of(context).colorScheme.outline),
                          ),
                          inputFormatters: [_MedidaEspessuraFormatter()],
                          onTap: _onFiltroAdicionalFocus,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _materialEspessuraCtrl,
                          decoration: InputDecoration(
                            labelText: 'Espessura',
                            isDense: true,
                            prefixIcon: Icon(Icons.layers_outlined,
                                size: 16, color: Theme.of(context).colorScheme.outline),
                          ),
                          inputFormatters: [_MedidaEspessuraFormatter()],
                          onTap: _onFiltroAdicionalFocus,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _limparSelecaoMaterial,
                        icon: Icon(Icons.clear_all, size: 16),
                        label: Text('Limpar'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  if (_sugestoes.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _sugestoes.length,
                        itemBuilder: (_, i) {
                          final m         = _sugestoes[i];
                          final identificador = m['identificador'] as String?;
                          final medidaOuDimensao = (m['medida'] as String?)?.isNotEmpty == true
                              ? m['medida'] as String?
                              : _materialDimensaoFormatada(m['largura'], m['comprimento']);
                          final espessura = m['espessura'] as String?;
                          final detalhe   = [
                            if (identificador != null && identificador.isNotEmpty) identificador,
                            if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
                            if (espessura != null && espessura.isNotEmpty) espessura,
                          ].join(' · ');
                          return InkWell(
                            onTap: () => _selecionarMaterial(m),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '#${m['id']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: m['nome'] ?? '',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: Theme.of(context).colorScheme.onSurface),
                                          ),
                                          if (detalhe.isNotEmpty)
                                            TextSpan(
                                              text: '  ·  $detalhe',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Theme.of(context).colorScheme.onSurface),
                                            ),
                                        ],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  SizedBox(height: 12),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Fornecedores',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  if (_materialIdSelecionado != null) ...[
                    const SizedBox(height: 8),
                    CompositedTransformTarget(
                      link: _buscaLayerLink,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _buscaFornecedorCtrl,
                        builder: (_, val, __) => TextField(
                          controller:  _buscaFornecedorCtrl,
                          focusNode:   _buscaFornecedorFocus,
                          onTap:       () {
                            _dispararBuscaFornecedor(_buscaFornecedorCtrl.text.trim());
                          },
                          decoration: InputDecoration(
                            hintText: 'Buscar fornecedor para adicionar…',
                            isDense: true,
                            prefixIcon: Icon(Icons.person_search_outlined,
                                size: 16, color: Theme.of(context).colorScheme.outline),
                            suffixIcon: _buscandoFornecedor
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primary),
                                    ),
                                  )
                                : val.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear, size: 16),
                                        color: Theme.of(context).colorScheme.outline,
                                        onPressed: () {
                                          _buscaFornecedorCtrl.clear();
                                          setState(() => _sugestoesFornecedor = []);
                                          _fecharOverlay();
                                        },
                                      )
                                    : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Expanded(
              child: _carregandoFornecedores
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    )
                  : _entradas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _materialIdSelecionado == null
                                    ? Icons.category_outlined
                                    : Icons.storefront_outlined,
                                size: 40,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              SizedBox(height: 10),
                              Text(
                                _materialIdSelecionado == null
                                    ? 'Selecione um material para ver os fornecedores vinculados.'
                                    : 'Nenhum fornecedor vinculado ainda.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                              if (_materialIdSelecionado != null) ...[
                                SizedBox(height: 6),
                                Text(
                                  'Use o campo acima para buscar e adicionar fornecedores.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.outline,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _entradas.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final entrada = _entradas[i];
                            return _FornecedorVinculoTile(
                              entrada:   entrada,
                              onRemover: () {
                                final f = entrada.fornecedor;
                                setState(() {
                                  _entradas.removeAt(i);
                                  if (_overlayEntry != null) {
                                    _sugestoesFornecedor.insert(0, f);
                                  }
                                });
                                entrada.dispose();
                                _atualizarOverlay();
                              },
                            );
                          },
                        ),
            ),

            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              child: Row(
                children: [
                  if (_materialIdSelecionado != null && _entradas.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '${_entradas.length} fornecedor(es)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Tooltip(
                    message: 'Cancelar e fechar sem salvar',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom().copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Salvar vínculos deste material com os fornecedores selecionados',
                    child: MouseRegion(
                      cursor: (_salvando ||
                              _materialIdSelecionado == null ||
                              _entradas.isEmpty)
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: FilledButton(
                        onPressed: (_salvando ||
                                _materialIdSelecionado == null ||
                                _entradas.isEmpty)
                            ? null
                            : _salvar,
                        style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary)
                            .copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                        child: _salvando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Salvar vínculos'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuscaFornecedorOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final List<FornecedorModel> sugestoes;
  final bool carregando;
  final void Function(FornecedorModel) onSelecionar;
  final VoidCallback onFechar;

  const _BuscaFornecedorOverlay({
    required this.layerLink,
    required this.sugestoes,
    required this.carregando,
    required this.onSelecionar,
    required this.onFechar,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onFechar,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link:             layerLink,
          showWhenUnlinked: false,
          offset:           const Offset(0, 40),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation:    8,
              borderRadius: BorderRadius.circular(10),
              color:        Theme.of(context).colorScheme.surface,
              child: Container(
                width:       500,
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: carregando && sugestoes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                      )
                    : sugestoes.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Nenhum fornecedor encontrado.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding:    EdgeInsets.zero,
                            itemCount:  sugestoes.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                            itemBuilder: (_, i) {
                              final f = sugestoes[i];
                              return InkWell(
                                onTap: () => onSelecionar(f),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 11),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.add_circle_outline,
                                        size: 18,
                                        color: AppTheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              f.nomeFantasia,
                                              style: TextStyle(
                                                fontSize:   13,
                                                fontWeight: FontWeight.w600,
                                                color:      Theme.of(context).colorScheme.onSurface,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (f.tipoFornecedor != null ||
                                                f.nomeVendedor   != null)
                                              Text(
                                                [
                                                  if (f.tipoFornecedor != null)
                                                    f.tipoFornecedor!,
                                                  if (f.nomeVendedor != null)
                                                    f.nomeVendedor!,
                                                ].join(' · '),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:    Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FornecedorVinculoTile extends StatefulWidget {
  final _FornecedorVinculoEntry entrada;
  final VoidCallback? onRemover;

  const _FornecedorVinculoTile({
    required this.entrada,
    this.onRemover,
  });

  @override
  State<_FornecedorVinculoTile> createState() => _FornecedorVinculoTileState();
}

class _FornecedorVinculoTileState extends State<_FornecedorVinculoTile> {
  @override
  Widget build(BuildContext context) {
    final e = widget.entrada;
    final f = e.fornecedor;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          f.nomeFantasia,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (e.jaVinculado) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'já vinculado',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (f.tipoFornecedor != null || f.nomeVendedor != null)
                    Text(
                      [
                        if (f.tipoFornecedor != null) f.tipoFornecedor!,
                        if (f.nomeVendedor   != null) f.nomeVendedor!,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: e.precoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor (R\$)',
                  prefixText: 'R\$ ',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_DecimalInputFormatter()],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: e.precoM2Ctrl,
                decoration: const InputDecoration(
                  labelText: 'Valor m²',
                  prefixText: 'R\$ ',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_DecimalInputFormatter()],
              ),
            ),

            if (widget.onRemover != null) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Remover',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onRemover,
                    child: const Icon(
                      Icons.remove_circle_outline,
                      size: 18,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              )
            ],
          ],
        ),
      ),
    );
  }
}