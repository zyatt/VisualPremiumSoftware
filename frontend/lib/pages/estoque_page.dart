import 'dart:async';
import 'dart:io';
import 'historico_material_page.dart';
import 'orcamento_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/material_model.dart';
import '../providers/material_provider.dart';
import '../providers/orcamento_provider.dart';
import '../providers/produto_provider.dart';
import '../providers/orcamento_venda_provider.dart';
import '../providers/usuario_provider.dart';
import '../repositories/estoque_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/escolher_usuario_chat_dialog.dart';
import '../providers/robo_helper_provider.dart';

String formatarUnidadeExibicao(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return '—';
  final u = unidade.trim().toUpperCase();
  switch (u) {
    case 'M':
      return 'm';
    case 'M/L':
      return 'm/l';
    case 'ML':
      return 'ml';
    case 'M²':
    case 'M2':
      return 'm²';
    case 'KG':
      return 'Kg';
    case 'G':
      return 'g';
    case 'UNIDADE':
      return 'Unidade';
    default:
      return unidade;
  }
}

String labelPrecoUnidade(String? unidade) {
  final u = formatarUnidadeExibicao(unidade);
  if (u == '—' || u.isEmpty) return 'Preço unidade';
  return 'Preço $u';
}

bool deveExibirPrecoUnidade(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return false;
  return unidade.trim().toUpperCase() != 'UNIDADE';
}

class _NotifiableTextEditingController extends TextEditingController {
  _NotifiableTextEditingController({super.text});
  void notify() => notifyListeners();
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

    final semVirgula = newValue.text.replaceAll(',', '');
    final texto = _removerAcentos(semVirgula).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
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

    texto = _UpperCaseFormatter._removerAcentos(texto).toLowerCase();

    texto = texto.replaceAllMapped(RegExp(r'[\d.]+'), (m) {
      final partes = m.group(0)!.split('.');
      if (partes.length > 2) {
        return '${partes[0]}.${partes.sublist(1).join('')}';
      }
      return m.group(0)!;
    });

    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _MedidaRetalhoFormatter extends TextInputFormatter {
  static const String sufixo = 'm²';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text;

    texto = texto.replaceAll(sufixo, '');

    texto = texto.replaceAll(',', '.');

    texto = texto.replaceAll(RegExp(r'[^\d.]'), '');

    final partes = texto.split('.');
    if (partes.length > 2) {
      texto = '${partes[0]}.${partes.sublist(1).join('')}';
    }

    final novoTexto = '$texto$sufixo';

    int cursor = newValue.selection.baseOffset;
    if (cursor < 0 || cursor > texto.length) {
      cursor = texto.length;
    }

    return TextEditingValue(
      text: novoTexto,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

class _EspessuraFormatter extends TextInputFormatter {
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
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
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
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

class _PrecoInputFormatter extends TextInputFormatter {
  static String _aplicarMilhar(String digitosInteiros) {
    final buffer = StringBuffer();
    for (int i = 0; i < digitosInteiros.length; i++) {
      if (i > 0 && (digitosInteiros.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digitosInteiros[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text;

    final cursorPos = newValue.selection.end.clamp(0, texto.length);
    final antesDoCursor = texto.substring(0, cursorPos);
    final digitosAntesCursor =
        antesDoCursor.replaceAll(RegExp(r'[^\d,]'), '').length;

    texto = texto.replaceAll(RegExp(r'[^\d,]'), '');

    final partes = texto.split(',');
    String inteiro = partes[0];
    String? decimais = partes.length > 1 ? partes.sublist(1).join('') : null;
    if (decimais != null && decimais.length > 2) {
      decimais = decimais.substring(0, 2);
    }

    inteiro = inteiro.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    final inteiroFormatado = _aplicarMilhar(inteiro);
    final textoFormatado = decimais != null
        ? '$inteiroFormatado,$decimais'
        : (texto.contains(',') ? '$inteiroFormatado,' : inteiroFormatado);

    int novoOffset = 0;
    int contador = 0;
    for (int i = 0; i < textoFormatado.length; i++) {
      if (contador >= digitosAntesCursor) break;
      if (textoFormatado[i] != '.') contador++;
      novoOffset = i + 1;
    }
    novoOffset = novoOffset.clamp(0, textoFormatado.length);

    return TextEditingValue(
      text: textoFormatado,
      selection: TextSelection.collapsed(offset: novoOffset),
    );
  }
}

double? _parsePreco(String texto) {
  final v = texto.trim();
  if (v.isEmpty) return null;
  final semMilhar = v.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(semMilhar);
}

String _mensagemErroAmigavelPdf(Object e) {
  final raw   = e.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('connection refused') ||
      lower.contains('recusou a conexão') ||
      lower.contains('errno')) {
    return 'Verifique a conexão com o servidor.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'Conexão com o servidor expirou. Verifique a rede e tente novamente.';
  }

  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

const _kCategoriaGeral       = '__GERAL__';
const _kCategoriaSemCategoria = '__SEM_CATEGORIA__';

class EstoquePage extends StatefulWidget {
  final String roleUsuario;
  const EstoquePage({super.key, required this.roleUsuario});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {

  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria    = '';

  final _tourKeyCardGeral       = GlobalKey();
  final _tourKeyCardEspecifica  = GlobalKey();
  final _tourKeyCampoBusca      = GlobalKey();
  final _scrollCtrlCategorias   = ScrollController();

  void _registrarAjudaRobo() {

    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isCurrent) return;

    final helper = context.read<RoboHelperProvider>();
    helper.registrarOpcoes('/estoque', [
      RoboHelpOption(
        titulo: 'Como selecionar uma categoria',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyCardGeral,
            texto: 'Este é o card "Geral" — toque nele para ver materiais '
                'de todas as categorias misturados.',
            aoEntrar: () async {

              if (_scrollCtrlCategorias.hasClients &&
                  _scrollCtrlCategorias.offset > 0) {
                _scrollCtrlCategorias.jumpTo(0);
                await Future<void>.delayed(const Duration(milliseconds: 16));
              }

              if (_filtroCategoriaCtrl.text.isNotEmpty) {
                _filtroCategoriaCtrl.clear();
                setState(() => _filtroCategoria = '');
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
            },
          ),
          RoboTourStop(
            key: () => _tourKeyCardEspecifica,
            texto: 'Ou escolha um card de categoria específica para ver '
                'somente os materiais daquele tipo.',
          ),
          RoboTourStop(
            key: () => _tourKeyCampoBusca,
            texto: 'Use este campo para filtrar as '
                'categorias pelo nome enquanto digita.',
          ),
        ],
      ),
    ]);
  }

  static IconData _iconePara(String categoria) {
    return Icons.inventory_2;
  }

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
      context.read<MaterialProvider>().carregarCategorias();
      context.read<RoboHelperProvider>().notificarRota('/estoque');
    });
  }

  @override
  void dispose() {
    _filtroCategoriaCtrl.dispose();
    _scrollCtrlCategorias.dispose();

    try {
      context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');
    } catch (_) {}
    super.dispose();
  }

  void _navegarParaCategoria({
    required String categoriaId,
    required String categoriaLabel,
    required Color cor,
    required IconData icone,
  }) {

    final pularIdentificadores =
        categoriaId == _kCategoriaGeral ||
        categoriaId == _kCategoriaSemCategoria;

    context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => pularIdentificadores
            ? EstoqueCategoriaPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
                roleUsuario:    widget.roleUsuario,
              )
            : EstoqueIdentificadorPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
                roleUsuario:    widget.roleUsuario,
              ),
      ),
    ).then((_) {

      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  void _abrirParaNotificacaoCritica(MaterialCriticoNotificacao n) {
    final temCategoria = n.categoria != null && n.categoria!.trim().isNotEmpty;
    final categoriaId    = temCategoria ? n.categoria! : _kCategoriaSemCategoria;
    final categoriaLabel = temCategoria ? n.categoria! : 'Sem categoria';
    final temIdentificador =
        n.identificador != null && n.identificador!.trim().isNotEmpty;

    context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => EstoqueCategoriaPage(
          categoriaId:         categoriaId,
          categoriaLabel:      categoriaLabel,
          cor:                 _cores.first,
          icone:               Icons.warning_amber_rounded,
          buscaInicial:        n.nome,
          identificadorFiltro: temIdentificador ? n.identificador!.trim() : null,
          medidaInicial:       n.medida,
          espessuraInicial:    n.espessura,
          roleUsuario:         widget.roleUsuario,
        ),
      ),
      (route) => route.isFirst,
    ).then((_) {
      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  Future<void> _abrirParaFiltroChat(FiltroMaterialChat f) async {

    var nome         = f.nome;
    var identificador = f.identificador;
    var medida        = f.medida;
    var espessura      = f.espessura;

    if (f.materialId != null) {
      final atual = await context.read<MaterialProvider>().buscarPorId(f.materialId!);
      if (atual != null) {
        nome          = atual.nome;
        identificador = atual.identificador;
        medida        = atual.medida;
        espessura     = atual.espessura;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Material não encontrado (pode ter sido excluído). Mostrando com os dados de quando foi encaminhado.'),
          ),
        );
      }
    }

    if (!mounted) return;

    context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');

    final identificadorTrim = identificador?.trim();
    final temIdentificador = identificadorTrim != null && identificadorTrim.isNotEmpty;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => EstoqueCategoriaPage(
          categoriaId:         _kCategoriaGeral,
          categoriaLabel:      'Geral',
          cor:                 _cores.first,
          icone:               Icons.grid_view_rounded,
          buscaInicial:        nome,
          identificadorFiltro: temIdentificador ? identificadorTrim : null,
          medidaInicial:       medida,
          espessuraInicial:    espessura,
          roleUsuario:         widget.roleUsuario,
        ),
      ),
      (route) => route.isFirst,
    ).then((_) {
      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  void _abrirGeralComStatus(String status) {
    context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => EstoqueCategoriaPage(
          categoriaId:    _kCategoriaGeral,
          categoriaLabel: 'Geral',
          cor:            const Color(0xFF5E35B1),
          icone:          Icons.grid_view_rounded,
          statusInicial:  status,
          roleUsuario:    widget.roleUsuario,
        ),
      ),
      (route) => route.isFirst,
    ).then((_) {
      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  @override
  Widget build(BuildContext context) {

    final filtroPendente =
        context.watch<MaterialProvider>().filtroNavegacaoPendente;
    if (filtroPendente != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MaterialProvider>().consumirFiltroNavegacaoPendente();
        _abrirParaNotificacaoCritica(filtroPendente);
      });
    }

    final statusPendente =
        context.watch<MaterialProvider>().filtroStatusPendente;
    if (statusPendente != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MaterialProvider>().consumirFiltroStatusPendente();
        _abrirGeralComStatus(statusPendente);
      });
    }

    final filtroChatPendente =
        context.watch<MaterialProvider>().filtroChatPendente;
    if (filtroChatPendente != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MaterialProvider>().consumirFiltroChatPendente();
        _abrirParaFiltroChat(filtroChatPendente);
      });
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estoque',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Selecione uma categoria para ver os materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => context.read<MaterialProvider>().carregarCategorias(),
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
              ],
            ),
            const SizedBox(height: 20),

            SizedBox(
              key: _tourKeyCampoBusca,
              width: 360,
              child: TextField(
                controller: _filtroCategoriaCtrl,
                inputFormatters: [_UpperCaseFormatter()],
                decoration: InputDecoration(
                  hintText:   'Buscar categoria',
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
                  isDense:    true,
                  suffixIcon: _filtroCategoria.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _filtroCategoriaCtrl.clear();
                            setState(() => _filtroCategoria = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _filtroCategoria = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrlCategorias,
                child: Consumer<MaterialProvider>(
                  builder: (_, provider, __) {
                    if (provider.carregando) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                      );
                    }

                    if (provider.erro != null) {

                      final partes = provider.erro!.split(': ');
                      final subtitulo = partes.length > 1
                          ? partes.sublist(1).join(': ')
                          : provider.erro!;
                      return SizedBox(
                        height: 300,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_outlined,
                                  size: 48, color: AppTheme.error),
                              SizedBox(height: 12),
                              Text(
                                'Erro ao carregar categorias',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 4),
                              Text(
                                subtitulo,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => context
                                    .read<MaterialProvider>()
                                    .carregarCategorias(),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Tentar novamente'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary)
                                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (!provider.categoriasCarregadas) {
                      return const SizedBox(
                        height: 200,
                        child: Center(
                          child: CircularProgressIndicator(color: AppTheme.primary),
                        ),
                      );
                    }

                    final especiais = <_CardEspecialData>[
                      const _CardEspecialData(
                        id:    _kCategoriaGeral,
                        label: 'Geral',
                        icone: Icons.grid_view_rounded,
                        cor:   Color(0xFF5E35B1),
                      ),
                      const _CardEspecialData(
                        id:    _kCategoriaSemCategoria,
                        label: 'Sem categoria',
                        icone: Icons.help_outline,
                        cor:   Color(0xFF546E7A),
                      ),
                    ];

                    bool corresponde(String label) =>
                        _filtroCategoria.isEmpty ||
                        label.toLowerCase().contains(_filtroCategoria);

                    int indiceCardMontado = 0;

                    Widget cardComTourKey(Widget card) {
                      final indice = indiceCardMontado;
                      indiceCardMontado++;
                      if (indice == 0) {
                        return KeyedSubtree(key: _tourKeyCardGeral, child: card);
                      }
                      if (indice == 2) {
                        return KeyedSubtree(key: _tourKeyCardEspecifica, child: card);
                      }
                      return card;
                    }

                    final todosCards = <Widget>[
                      for (final esp in especiais)
                        if (corresponde(esp.label))
                          cardComTourKey(
                            _CategoriaCardCompact(
                              categoria: esp.label,
                              cor:       esp.cor,
                              icone:     esp.icone,
                              onTap: () => _navegarParaCategoria(
                                categoriaId:    esp.id,
                                categoriaLabel: esp.label,
                                cor:            esp.cor,
                                icone:          esp.icone,
                              ),
                            ),
                          ),
                      for (int i = 0; i < provider.categorias.length; i++)
                        if (corresponde(provider.categorias[i]))
                          cardComTourKey(
                            _CategoriaCardCompact(
                              categoria: provider.categorias[i],
                              cor:       _cores[i % _cores.length],
                              icone:     _iconePara(provider.categorias[i]),
                              onTap: () => _navegarParaCategoria(
                                categoriaId:    provider.categorias[i],
                                categoriaLabel: provider.categorias[i],
                                cor:            _cores[i % _cores.length],
                                icone:          _iconePara(provider.categorias[i]),
                              ),
                            ),
                          ),
                    ];

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _registrarAjudaRobo();
                    });

                    if (todosCards.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 64, color: Theme.of(context).colorScheme.outline),
                              SizedBox(height: 16),
                              Text(
                                _filtroCategoria.isNotEmpty
                                    ? 'Nenhuma categoria encontrada'
                                    : 'Nenhuma categoria cadastrada',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return GridView.count(
                      crossAxisCount:   6,
                      crossAxisSpacing: 12,
                      mainAxisSpacing:  12,
                      childAspectRatio: 1.0,
                      shrinkWrap:       true,
                      physics:          const NeverScrollableScrollPhysics(),
                      children:         todosCards,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportarPdfDialog extends StatefulWidget {
  final bool         mostrarSeletorCategoria;
  final List<String> categorias;
  final String       categoriaInicial;
  final GlobalKey?   tourKeyCategoria;
  final GlobalKey?   tourKeyStatus;
  final GlobalKey?   tourKeyBotaoExportar;

  const _ExportarPdfDialog({
    this.mostrarSeletorCategoria = false,
    this.categorias = const [],
    this.categoriaInicial = '',
    this.tourKeyCategoria,
    this.tourKeyStatus,
    this.tourKeyBotaoExportar,
  });

  @override
  State<_ExportarPdfDialog> createState() => _ExportarPdfDialogState();
}

class _ExportarPdfDialogState extends State<_ExportarPdfDialog> {
  String _statusSelecionado = 'TODOS';
  late String _categoriaSelecionada = widget.categoriaInicial;

  static const _opcoes = [
    ('TODOS',   'Todos os status',   Icons.list_alt,          AppTheme.primary),
    ('OK',      'OK',                Icons.check_circle,       Color(0xFF15803D)),
    ('LIMITE',  'Limite',            Icons.warning_amber,      Color(0xFFD97706)),
    ('CRITICO', 'Crítico',           Icons.error_outline,      Color(0xFFDC2626)),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          const Expanded(child: Text('Exportar PDF de Estoque')),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Fechar',
            style: IconButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.mostrarSeletorCategoria) ...[
              KeyedSubtree(
                key: widget.tourKeyCategoria,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categoria a exportar:',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _CategoriaFiltroDropdown(
                      categorias: widget.categorias,
                      valorSelecionado: _categoriaSelecionada.isEmpty ||
                              widget.categorias.contains(_categoriaSelecionada)
                          ? _categoriaSelecionada
                          : '',
                      onSelecionar: (v) => setState(() => _categoriaSelecionada = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'Selecione quais materiais deseja incluir no relatório:',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: widget.tourKeyStatus,
              child: Column(
                children: _opcoes.map((opcao) {
                  final (valor, label, icone, cor) = opcao;
                  final selecionado = _statusSelecionado == valor;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _statusSelecionado = valor),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: selecionado
                              ? cor.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selecionado
                                ? cor
                                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                            width: selecionado ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(icone, size: 18, color: selecionado ? cor : Theme.of(context).colorScheme.onSurfaceVariant),
                            SizedBox(width: 10),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selecionado ? FontWeight.w700 : FontWeight.w400,
                                color: selecionado ? cor : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            if (selecionado)
                              Icon(Icons.check, size: 16, color: cor),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        Tooltip(
          message: 'Fechar sem exportar',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
        ),
        Tooltip(
          message: 'Gerar o PDF com os filtros selecionados',
          child: FilledButton.icon(
            key: widget.tourKeyBotaoExportar,
            onPressed: () => Navigator.of(context).pop(
              (status: _statusSelecionado, categoria: _categoriaSelecionada),
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Exportar'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ),
      ],
    );
  }
}

const _kIdentificadorTodos       = '__TODOS__';
const _kIdentificadorSemIdentificador = '__SEM_IDENTIFICADOR__';

class EstoqueIdentificadorPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String   roleUsuario;

  const EstoqueIdentificadorPage({
    super.key,
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    required this.roleUsuario,
  });

  @override
  State<EstoqueIdentificadorPage> createState() => _EstoqueIdentificadorPageState();
}

class _EstoqueIdentificadorPageState extends State<EstoqueIdentificadorPage> {
  final _filtroCtrl = TextEditingController();
  String _filtro = '';
  bool _carregando = true;
  List<MaterialModel> _materiais = [];

  final _tourKeyCardTodos      = GlobalKey();
  final _tourKeyCardEspecifico = GlobalKey();
  final _scrollCtrlIdentificadores = ScrollController();

  void _registrarAjudaRobo() {
    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isCurrent) return;

    final helper = context.read<RoboHelperProvider>();
    helper.registrarOpcoes('/estoque', [
      RoboHelpOption(
        titulo: 'Como selecionar um identificador',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyCardTodos,
            texto: 'Este é o card "Todos" — toque nele para ver os '
                'materiais desta categoria, independente do identificador.',
            aoEntrar: () async {
              if (_scrollCtrlIdentificadores.hasClients &&
                  _scrollCtrlIdentificadores.offset > 0) {
                _scrollCtrlIdentificadores.jumpTo(0);
                await Future<void>.delayed(const Duration(milliseconds: 16));
              }

              if (_filtroCtrl.text.isNotEmpty) {
                _filtroCtrl.clear();
                setState(() => _filtro = '');
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
            },
          ),
          RoboTourStop(
            key: () => _tourKeyCardEspecifico,
            texto: 'Ou escolha um card de identificador específico para ver '
                'somente os materiais daquele identificador.',
          ),
        ],
      ),
    ]);
  }

  static const _cores = [
    Color(0xFF1E88E5), Color(0xFF00897B), Color(0xFFE53935),
    Color(0xFFF4511E), Color(0xFF8E24AA), Color(0xFF039BE5),
    Color(0xFF43A047), Color(0xFFFFB300), Color(0xFF6D4C41),
    Color(0xFF546E7A), Color(0xFFD81B60), Color(0xFF5E35B1),
  ];

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral)        return null;
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregar();
      context.read<RoboHelperProvider>().notificarRota('/estoque');
    });
  }

  @override
  void dispose() {
    _filtroCtrl.dispose();
    _scrollCtrlIdentificadores.dispose();

    try {
      context.read<RoboHelperProvider>().encerrarTour();
      context.read<RoboHelperProvider>().limparOpcoes('/estoque');
    } catch (_) {}
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      await context.read<MaterialProvider>().buscarSugestoes(
        '',
        limite: 9999,
      );

      if (!mounted) return;

      await context.read<MaterialProvider>().carregar(
        categoria: _categoriaParaProvider(),
      );
      if (!mounted) return;
      setState(() {
        _materiais = context.read<MaterialProvider>().materiais;
        _carregando = false;
      });

      if (mounted) _registrarAjudaRobo();
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<String?> _identificadoresUnicos() {
    final set = <String?>{};
    for (final m in _materiais) {
      set.add(m.identificador?.trim().isNotEmpty == true ? m.identificador!.trim() : null);
    }
    final lista = set.toList();
    lista.sort((a, b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    });
    return lista;
  }

  int _contarMateriais(String? identificador) {
    if (identificador == null) {
      return _materiais.where((m) =>
        m.identificador == null || m.identificador!.trim().isEmpty).length;
    }
    return _materiais.where((m) =>
      m.identificador?.trim() == identificador).length;
  }

  void _navegarParaIdentificador({
    required String identificadorId,
    required String? identificadorReal,
  }) {

    context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EstoqueCategoriaPage(
          categoriaId:          widget.categoriaId,
          categoriaLabel:       widget.categoriaLabel,
          cor:                  widget.cor,
          icone:                widget.icone,
          identificadorFiltro:  identificadorReal,
          identificadorLabel:   identificadorId == _kIdentificadorTodos
              ? null
              : identificadorId == _kIdentificadorSemIdentificador
                  ? 'Sem identificador'
                  : identificadorId,
          mostrarBotaoIdentificadores: true,
          roleUsuario: widget.roleUsuario,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              children: [
                _BotaoVoltar(
                  label: 'Categorias',
                  tooltip: 'Voltar para categorias',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.cor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icone, color: widget.cor, size: 20),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.categoriaLabel,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Selecione um identificador para ver os materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  onPressed: _carregar,
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
            SizedBox(height: 20),

            SizedBox(
              width: 360,
              child: TextField(
                controller: _filtroCtrl,
                inputFormatters: [_UpperCaseFormatter()],
                decoration: InputDecoration(
                  hintText:   'Buscar identificador',
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
                  isDense:    true,
                  suffixIcon: _filtro.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _filtroCtrl.clear();
                            setState(() => _filtro = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _buildGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final identificadores = _identificadoresUnicos();

    bool corresponde(String label) =>
        _filtro.isEmpty || label.toLowerCase().contains(_filtro);

    final cards = <Widget>[];

    if (corresponde('todos')) {
      cards.add(_IdentificadorCard(
        key:         _tourKeyCardTodos,
        label:       'Todos',
        quantidade:  _materiais.length,
        cor:         widget.cor,
        icone:       Icons.grid_view_rounded,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   _kIdentificadorTodos,
          identificadorReal: null,
        ),
      ));
    }

    for (int i = 0; i < identificadores.length; i++) {
      final ident = identificadores[i];
      final label = ident ?? 'Sem identificador';
      if (!corresponde(label)) continue;
      final cor = ident == null
          ? const Color(0xFF546E7A)
          : _cores[i % _cores.length];

      final ehPrimeiro = cards.length == (corresponde('todos') ? 1 : 0);
      cards.add(_IdentificadorCard(
        key:         ehPrimeiro ? _tourKeyCardEspecifico : null,
        label:       label,
        quantidade:  _contarMateriais(ident),
        cor:         cor,
        icone:       ident == null ? Icons.help_outline : Icons.qr_code,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   ident ?? _kIdentificadorSemIdentificador,
          identificadorReal: ident,
        ),
      ));
    }

    if (cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 16),
            Text(
              'Nenhum identificador encontrado',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollCtrlIdentificadores,
      child: GridView.count(
        crossAxisCount:   6,
        crossAxisSpacing: 12,
        mainAxisSpacing:  12,
        childAspectRatio: 1.0,
        shrinkWrap:       true,
        physics:          const NeverScrollableScrollPhysics(),
        children:         cards,
      ),
    );
  }
}

/// Botão de ação do cabeçalho ("Ver mais", "Histórico", "Aguardando
/// aprovação", "Novo Material") — mesmo comportamento de hover do
/// [_BotaoVoltar] (escurece levemente a cor de fundo ao passar o mouse),
/// garantindo feedback visual consistente entre todos os botões da barra.
class _BotaoCabecalhoWidget extends StatefulWidget {
  final Key? tourKey;
  final IconData icone;
  final String texto;
  final VoidCallback onPressed;
  final Color corFundo;
  final Color corTexto;
  final double iconSize;
  final double fontSize;
  final double padH;
  final double padV;
  final String? tooltip;
  final Color? corBorda;
  final Widget? badge;

  const _BotaoCabecalhoWidget({
    this.tourKey,
    required this.icone,
    required this.texto,
    required this.onPressed,
    required this.corFundo,
    required this.corTexto,
    required this.iconSize,
    required this.fontSize,
    required this.padH,
    required this.padV,
    this.tooltip,
    this.corBorda,
    this.badge,
  });

  @override
  State<_BotaoCabecalhoWidget> createState() => _BotaoCabecalhoWidgetState();
}

class _BotaoCabecalhoWidgetState extends State<_BotaoCabecalhoWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final botao = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered
            ? widget.corFundo.withValues(alpha: 0.85)
            : widget.corFundo,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: widget.onPressed,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: widget.padH, vertical: widget.padV),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: widget.corBorda != null ? Border.all(color: widget.corBorda!) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icone, size: widget.iconSize, color: widget.corTexto),
                const SizedBox(width: 6),
                Text(
                  widget.texto,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    color: widget.corTexto,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final comChave = widget.tourKey != null ? Container(key: widget.tourKey, child: botao) : botao;
    final comTooltip =
        widget.tooltip != null ? Tooltip(message: widget.tooltip, child: comChave) : comChave;

    if (widget.badge == null) return comTooltip;
    return Stack(clipBehavior: Clip.none, children: [comTooltip, widget.badge!]);
  }
}

class _BotaoVoltar extends StatefulWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;
  final double fontSize;
  final double padH;
  final double padV;

  const _BotaoVoltar({
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 18,
    this.fontSize = 13,
    this.padH = 16,
    this.padV = 12,
  });

  @override
  State<_BotaoVoltar> createState() => _BotaoVoltarState();
}

class _BotaoVoltarState extends State<_BotaoVoltar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: _hovered
              ? AppTheme.primary.withValues(alpha: 0.85)
              : AppTheme.primary,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: widget.onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.padH, vertical: widget.padV),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: widget.iconSize,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentificadorCard extends StatefulWidget {
  final String   label;
  final int      quantidade;
  final Color    cor;
  final IconData icone;
  final VoidCallback onTap;

  const _IdentificadorCard({
    super.key,
    required this.label,
    required this.quantidade,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_IdentificadorCard> createState() => _IdentificadorCardState();
}

class _IdentificadorCardState extends State<_IdentificadorCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ativo = _hovered;
    return MouseRegion(
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo
                ? widget.cor.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo
                  ? widget.cor
                  : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icone, color: widget.cor, size: 20),
              ),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ativo ? widget.cor : Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '${widget.quantidade} ${widget.quantidade == 1 ? "material" : "materiais"}',
                style: TextStyle(
                  fontSize: 9,
                  color: ativo
                      ? widget.cor.withValues(alpha: 0.8)
                      : Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialFormTourKeys {
  final nome           = GlobalKey();
  final identificador  = GlobalKey();
  final categoria      = GlobalKey();
  final unidade        = GlobalKey();
  final medida         = GlobalKey();
  final comprimento    = GlobalKey();
  final largura        = GlobalKey();
  final espessura      = GlobalKey();
  final quantidade     = GlobalKey();
  final estoqueMinimo  = GlobalKey();
  final estoqueConfirmado = GlobalKey();
  final cadastrar      = GlobalKey();

  bool contemParada(GlobalKey key) => [
        nome, identificador, categoria, unidade, medida, comprimento, largura,
        espessura, quantidade, estoqueMinimo, estoqueConfirmado, cadastrar,
      ].contains(key);
}

class EstoqueCategoriaPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String?  buscaInicial;

  final String?  medidaInicial;
  final String?  espessuraInicial;

  final String?  statusInicial;

  final String?  identificadorFiltro;

  final String?  identificadorLabel;

  final bool     mostrarBotaoIdentificadores;
  final String   roleUsuario;

  const EstoqueCategoriaPage({
    super.key,
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    this.buscaInicial,
    this.medidaInicial,
    this.espessuraInicial,
    this.statusInicial,
    this.identificadorFiltro,
    this.identificadorLabel,
    this.mostrarBotaoIdentificadores = false,
    required this.roleUsuario,
  });

  @override
  State<EstoqueCategoriaPage> createState() => _EstoqueCategoriaPageState();
}

class _CategoriaFiltroDropdown extends StatefulWidget {
  final List<String> categorias;
  final String valorSelecionado;
  final ValueChanged<String> onSelecionar;
  const _CategoriaFiltroDropdown({
    required this.categorias,
    required this.valorSelecionado,
    required this.onSelecionar,
  });

  @override
  State<_CategoriaFiltroDropdown> createState() => _CategoriaFiltroDropdownState();
}

class _CategoriaFiltroDropdownState extends State<_CategoriaFiltroDropdown> {
  final MenuController _menuController = MenuController();
  final TextEditingController _buscaCtrl = TextEditingController();
  String _busca = '';
  bool _hovered = false;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _abrirMenu() {
    _buscaCtrl.clear();
    setState(() => _busca = '');
    _menuController.open();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      controller: _menuController,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        StatefulBuilder(
          builder: (context, setMenuState) {

            final filtradas = _busca.trim().isEmpty
                ? widget.categorias
                : widget.categorias
                    .where((c) => c.toLowerCase().contains(_busca.trim().toLowerCase()))
                    .toList();
            return SizedBox(
              width: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: TextField(
                      controller: _buscaCtrl,
                      autofocus: true,
                      inputFormatters: [_UpperCaseFormatter()],
                      decoration: InputDecoration(
                        hintText:   'Buscar categoria',
                        isDense:    true,
                        prefixIcon: Icon(Icons.search, size: 18, color: scheme.outline),
                      ),
                      onChanged: (v) {
                        _busca = v;
                        setMenuState(() {});
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MenuItemButton(
                            style: ButtonStyle(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                            onPressed: () {
                              widget.onSelecionar('');
                              _menuController.close();
                            },
                            trailingIcon: widget.valorSelecionado.isEmpty
                                ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                                : null,
                            child: const SizedBox(
                              width: 208,
                              child: Text('TODAS'),
                            ),
                          ),
                          for (final c in filtradas)
                            MenuItemButton(
                              style: ButtonStyle(
                                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                              ),
                              onPressed: () {
                                widget.onSelecionar(c);
                                _menuController.close();
                              },
                              trailingIcon: widget.valorSelecionado == c
                                  ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                                  : null,
                              child: SizedBox(
                                width: 208,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          if (filtradas.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Nenhuma categoria encontrada',
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
      builder: (context, controller, child) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit:  (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () => controller.isOpen ? controller.close() : _abrirMenu(),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Categoria',
                isDense:   true,
                suffixIcon: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: _hovered ? AppTheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              child: Text(
                widget.valorSelecionado.isEmpty ? 'TODAS' : widget.valorSelecionado,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: scheme.onSurface),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusFiltroDropdown extends StatefulWidget {
  final MenuController menuController;
  final String valorSelecionado;
  final ValueChanged<String> onSelecionar;
  const _StatusFiltroDropdown({
    required this.menuController,
    required this.valorSelecionado,
    required this.onSelecionar,
  });

  @override
  State<_StatusFiltroDropdown> createState() => _StatusFiltroDropdownState();
}

class _StatusFiltroDropdownState extends State<_StatusFiltroDropdown> {
  bool _hovered = false;

  static const _opcoes = ['OK', 'LIMITE', 'CRITICO', 'INATIVO'];

  Color _corStatus(String status, ColorScheme scheme) {
    switch (status) {
      case 'OK':
        return AppTheme.statusOk;
      case 'LIMITE':
        return AppTheme.statusBaixo;
      case 'CRITICO':
        return AppTheme.statusCritico;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 160,
      child: MenuAnchor(
        controller: widget.menuController,
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
        menuChildren: [
          SizedBox(
            width: 160,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MenuItemButton(
                  style: ButtonStyle(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                  onPressed: () {
                    widget.onSelecionar('');
                    widget.menuController.close();
                  },
                  trailingIcon: widget.valorSelecionado.isEmpty
                      ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                      : null,
                  child: const SizedBox(
                    width: 128,
                    child: Text('TODOS'),
                  ),
                ),
                for (final s in _opcoes)
                  MenuItemButton(
                    style: ButtonStyle(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                    onPressed: () {
                      widget.onSelecionar(s);
                      widget.menuController.close();
                    },
                    leadingIcon: Icon(Icons.circle, size: 8, color: _corStatus(s, scheme)),
                    trailingIcon: widget.valorSelecionado == s
                        ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                        : null,
                    child: SizedBox(
                      width: 108,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
            ),
          ),
        ],
        builder: (context, controller, child) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit:  (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () => controller.isOpen ? controller.close() : controller.open(),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Status',
                  isDense:   true,
                  suffixIcon: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: _hovered ? AppTheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                child: Text(
                  widget.valorSelecionado.isEmpty ? 'TODOS' : widget.valorSelecionado,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: scheme.onSurface),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FornecedorFiltroDropdown extends StatefulWidget {
  final bool? valorSelecionado;
  final ValueChanged<bool?> onSelecionar;
  const _FornecedorFiltroDropdown({
    required this.valorSelecionado,
    required this.onSelecionar,
  });

  @override
  State<_FornecedorFiltroDropdown> createState() => _FornecedorFiltroDropdownState();
}

class _FornecedorFiltroDropdownState extends State<_FornecedorFiltroDropdown> {
  bool _hovered = false;
  final MenuController _menuController = MenuController();

  String _rotulo(bool? v) {
    if (v == null) return 'TODOS';
    return v ? 'COM FORNECEDOR' : 'SEM FORNECEDOR';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 190,
      child: MenuAnchor(
        controller: _menuController,
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
        menuChildren: [
          SizedBox(
            width: 190,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MenuItemButton(
                  style: ButtonStyle(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                  onPressed: () {
                    widget.onSelecionar(null);
                    _menuController.close();
                  },
                  trailingIcon: widget.valorSelecionado == null
                      ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                      : null,
                  child: const SizedBox(
                    width: 158,
                    child: Text('TODOS'),
                  ),
                ),
                MenuItemButton(
                  style: ButtonStyle(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                  onPressed: () {
                    widget.onSelecionar(true);
                    _menuController.close();
                  },
                  leadingIcon: Icon(Icons.store_outlined, size: 16, color: scheme.onSurfaceVariant),
                  trailingIcon: widget.valorSelecionado == true
                      ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                      : null,
                  child: const SizedBox(
                    width: 138,
                    child: Text('COM FORNECEDOR'),
                  ),
                ),
                MenuItemButton(
                  style: ButtonStyle(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                  onPressed: () {
                    widget.onSelecionar(false);
                    _menuController.close();
                  },
                  leadingIcon: Icon(Icons.store_mall_directory_outlined, size: 16, color: scheme.onSurfaceVariant),
                  trailingIcon: widget.valorSelecionado == false
                      ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                      : null,
                  child: const SizedBox(
                    width: 138,
                    child: Text('SEM FORNECEDOR'),
                  ),
                ),
              ],
            ),
          ),
        ],
        builder: (context, controller, child) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit:  (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () => controller.isOpen ? controller.close() : controller.open(),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Fornecedor',
                  isDense:   true,
                  suffixIcon: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: _hovered ? AppTheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                child: Text(
                  _rotulo(widget.valorSelecionado),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: scheme.onSurface),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EstoqueCategoriaPageState extends State<EstoqueCategoriaPage> {
  late final TextEditingController _buscaCtrl;
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  final _larguraCtrl       = TextEditingController();
  final _comprimentoCtrl   = TextEditingController();
  String _statusFiltro         = '';
  String _categoriaFiltro      = '';
  bool?  _comFornecedor;
  Timer? _debounceTimer;
  final MenuController _statusMenuController = MenuController();

  final _tourKeyHistorico     = GlobalKey();
  final _tourKeyVerMais       = GlobalKey();
  final _verMaisLink          = LayerLink();
  final _tourKeyOrcar         = GlobalKey();
  final _tourKeyExportar      = GlobalKey();
  OverlayEntry? _verMaisOverlay;
  bool _verMaisAberto = false;
  final _tourKeyExportarCategoria = GlobalKey();
  final _tourKeyExportarStatus    = GlobalKey();
  final _tourKeyExportarBotao     = GlobalKey();
  final _tourKeyNovoMaterial  = GlobalKey();

  final _tourKeyBusca            = GlobalKey();
  final _tourKeyFiltroIdent      = GlobalKey();
  final _tourKeyFiltroMedida     = GlobalKey();
  final _tourKeyFiltroComp       = GlobalKey();
  final _tourKeyFiltroLargura    = GlobalKey();
  final _tourKeyFiltroEspessura  = GlobalKey();
  final _tourKeyFiltroCategoria  = GlobalKey();
  final _tourKeyFiltroStatus     = GlobalKey();
  final _tourKeyFiltroFornecedor = GlobalKey();
  final _materialTourKeys     = _MaterialFormTourKeys();

  bool _dialogTourAberto = false;

  static const int _itensPorPagina = 50;
  int     _paginaAtual  = 0;
  String? _colunaOrdem;
  bool    _crescente    = true;

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral) {

      return _categoriaFiltro.isEmpty ? null : _categoriaFiltro;
    }
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  @override
  void initState() {
    super.initState();
    _buscaCtrl = TextEditingController(text: widget.buscaInicial ?? '');

    if (widget.identificadorFiltro != null) {
      _identificadorCtrl.text = widget.identificadorFiltro!;
    }
    if (widget.medidaInicial != null && widget.medidaInicial!.trim().isNotEmpty) {
      _medidaCtrl.text = widget.medidaInicial!.trim();
    }
    if (widget.espessuraInicial != null && widget.espessuraInicial!.trim().isNotEmpty) {
      _espessuraCtrl.text = widget.espessuraInicial!.trim();
    }
    if (widget.statusInicial != null && widget.statusInicial!.trim().isNotEmpty) {
      _statusFiltro = widget.statusInicial!.trim();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aplicarFiltros();
      if (widget.categoriaId == _kCategoriaGeral &&
          context.read<MaterialProvider>().categorias.isEmpty) {
        context.read<MaterialProvider>().carregarCategorias();
      }
      final roleInicial = context.read<UsuarioProvider>().usuarioLogado?.role;
      if (roleInicial == 'ADMIN' || roleInicial == 'GERENTE') {
        context.read<MaterialProvider>().atualizarContadorPendentes();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _buscaCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    _larguraCtrl.dispose();
    _comprimentoCtrl.dispose();
    _verMaisOverlay?.remove();
    super.dispose();
  }

  void _aplicarFiltros() {
    _carregarPaginaAtual(irParaPagina: 0);
  }

  void _recarregarSemResetarPagina() {
    _carregarPaginaAtual(irParaPagina: _paginaAtual);
  }

  Future<void> _carregarPaginaAtual({required int irParaPagina}) async {
    final provider = context.read<MaterialProvider>();
    await provider.carregarPaginado(
      busca:         _buscaCtrl.text,
      categoria:     _categoriaParaProvider(),
      status:        _statusFiltro,
      identificador: _identificadorCtrl.text.trim(),
      medida:        _medidaCtrl.text.trim(),
      espessura:     _espessuraCtrl.text.trim(),
      largura:       _larguraCtrl.text.trim(),
      comprimento:   _comprimentoCtrl.text.trim(),
      comFornecedor: _comFornecedor,
      pagina:        irParaPagina + 1,
      porPagina:     _itensPorPagina,
      ordenarPor:    _colunaOrdem,
      direcao:       _crescente ? 'asc' : 'desc',
    );
    if (!mounted) return;
    if (provider.materiaisPagina.isEmpty &&
        provider.totalItensPagina > 0 &&
        irParaPagina > 0) {
      setState(() => _paginaAtual = irParaPagina - 1);
      await _carregarPaginaAtual(irParaPagina: irParaPagina - 1);
    } else {
      setState(() => _paginaAtual = irParaPagina);
    }
  }

  void _toggleOrdem(String sortKey) {
    setState(() {
      if (_colunaOrdem == sortKey) {
        _crescente = !_crescente;
      } else {
        _colunaOrdem = sortKey;
        _crescente   = true;
      }
    });

    _carregarPaginaAtual(irParaPagina: 0);
  }

  void _abrirHistoricoPrecos(MaterialModel material) {
    final materialProvider = context.read<MaterialProvider>();
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider<MaterialProvider>.value(
        value: materialProvider,
        child: _HistoricoPrecoDialog(material: material),
      ),
    );
  }

  void _registrarAjudaRoboCategoria() {
    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isCurrent) return;

    final bloqueiaQuantidade =
        context.read<UsuarioProvider>().usuarioLogado?.role == 'COMPRAS';

    final helper = context.read<RoboHelperProvider>();
    helper.registrarOpcoes('/estoque', [
      RoboHelpOption(
        titulo: 'Como cadastrar um material',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyNovoMaterial,
            texto: 'Toque aqui para abrir o formulário de cadastro de um '
                'novo material.',
            aoEntrar: () async {

              if (_dialogTourAberto) {
                _dialogTourAberto = false;
                await Navigator.of(context, rootNavigator: true).maybePop();
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
            },
          ),
          RoboTourStop(
            key: () => _materialTourKeys.nome,
            texto: 'Nome do material — obrigatório.',
            aoEntrar: () async {
              if (!_dialogTourAberto) {
                _dialogTourAberto = true;
                _abrirFormMaterial().then((_) {
                  if (mounted) _dialogTourAberto = false;
                });

                await Future<void>.delayed(const Duration(milliseconds: 80));
              }
            },
          ),
          RoboTourStop(
            key: () =>_materialTourKeys.identificador,
            texto: 'Identificador — Adicione um código, marca ou especificação.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.categoria,
            texto: 'Categoria do material — Digite uma categoria ou escolha '
                'uma das categorias já existentes.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.unidade,
            texto: 'Unidade de medida do material (Unidade, m, m², m/l ou g).',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.medida,
            texto: 'Medida do material — descrição livre (ex.: dimensões, '
                'bitola, polegada).',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.comprimento,
            texto: 'Comprimento da peça, em metros.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.largura,
            texto: 'Largura da peça, em metros.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.espessura,
            texto: 'Espessura da peça, em milímetros.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.quantidade,
            texto: bloqueiaQuantidade
                ? 'A quantidade em estoque não é definida aqui — ela deve '
                    'ser dada de entrada pela página de Controle de '
                    'Estoque, vinculada a uma Ordem de Serviço.'
                : 'Quantidade atual em estoque desse material.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.estoqueMinimo,
            texto: bloqueiaQuantidade
                ? 'O estoque mínimo também é bloqueado aqui pelo mesmo '
                    'motivo — é definido em Controle de Estoque.'
                : 'Estoque mínimo — abaixo desse valor o material aparece '
                    'como crítico/em limite.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.estoqueConfirmado,
            texto: 'Marque aqui quando a quantidade cadastrada já foi '
                'conferida fisicamente no estoque.',
          ),
          RoboTourStop(
            key: () => _materialTourKeys.cadastrar,
            texto: 'Por fim, toque em "Cadastrar" para salvar o novo '
                'material.',
          ),
        ],
      ),
      RoboHelpOption(
        titulo: 'Como buscar um material',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyBusca,
            texto: 'Digite aqui o nome do material que você procura.',
          ),
          RoboTourStop(
            key: () => _tourKeyFiltroIdent,
            texto: 'Filtre pelo identificador — código, marca ou '
                'especificação cadastrada no material.',
          ),
          RoboTourStop(
            key: () =>_tourKeyFiltroMedida,
            texto: 'Filtre pela medida do material.',
          ),
          RoboTourStop(
            key: () => _tourKeyFiltroComp,
            texto: 'Filtre pelo comprimento da peça, em metros.',
          ),
          RoboTourStop(
            key: () => _tourKeyFiltroLargura,
            texto: 'Filtre pela largura da peça, em metros.',
          ),
          RoboTourStop(
            key: () => _tourKeyFiltroEspessura,
            texto: 'Filtre pela espessura da peça, em milímetros.',
          ),
          if (widget.categoriaId == _kCategoriaGeral)
            RoboTourStop(
              key: () => _tourKeyFiltroCategoria,
              texto: 'Filtre por uma categoria específica.',
            ),
          RoboTourStop(
            key: () => _tourKeyFiltroStatus,
            texto: 'Filtre pelo status do estoque: OK, Limite, Crítico '
                'ou Inativo.',
          ),
          RoboTourStop(
            key: () => _tourKeyFiltroFornecedor,
            texto: 'Marque aqui pra mostrar somente materiais que têm '
                'um fornecedor vinculado.',
          ),
        ],
      ),
      RoboHelpOption(
        titulo: 'Como ver o histórico de alterações',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyHistorico,
            texto: 'Toque aqui para ver o histórico de cadastros, edições, '
                'desativações e exclusões de materiais.',
          ),
        ],
      ),
      RoboHelpOption(
        titulo: 'Como orçar os materiais filtrados na página',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyVerMais,
            texto: 'Toque aqui em "Ver mais" para abrir mais opções.',
            aoEntrar: () async {
              if (!_verMaisAberto) _abrirVerMais();
              await Future<void>.delayed(const Duration(milliseconds: 120));
            },
          ),
          RoboTourStop(
            key: () => _tourKeyOrcar,
            texto: 'Toque aqui em "Orçar filtrados" para criar um orçamento '
                'com todos os materiais que estão filtrados nesta página '
                'agora.',
            aoSair: () async {
              _fecharVerMais();
            },
          ),
        ],
        aoEncerrar: () async {
          _fecharVerMais();
        },
      ),
      RoboHelpOption(
        titulo: 'Como exportar o estoque para um PDF',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyVerMais,
            texto: 'Toque aqui em "Ver mais" para abrir mais opções.',
            aoEntrar: () async {
              if (_dialogTourAberto) {
                _dialogTourAberto = false;
                await Navigator.of(context, rootNavigator: true).maybePop();
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
              if (!_verMaisAberto) _abrirVerMais();
              await Future<void>.delayed(const Duration(milliseconds: 120));
            },
          ),
          RoboTourStop(
            key: () => _tourKeyExportar,
            texto: 'Toque aqui em "Exportar Estoque (PDF)" para abrir a '
                'exportação do estoque em PDF.',
            aoEntrar: () async {
              if (_dialogTourAberto) {
                _dialogTourAberto = false;
                await Navigator.of(context, rootNavigator: true).maybePop();
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
              if (!_verMaisAberto) {
                _abrirVerMais();
                await Future<void>.delayed(const Duration(milliseconds: 120));
              }
            },
            aoSair: () async {
              _fecharVerMais();
            },
          ),
          if (widget.categoriaId == _kCategoriaGeral)
            RoboTourStop(
              key: () => _tourKeyExportarCategoria,
              texto: 'Escolha a categoria que deseja exportar, ou deixe '
                  'em "Todas" para exportar de todas as categorias.',
              aoEntrar: () async {
                if (!_dialogTourAberto) {
                  _dialogTourAberto = true;
                  _exportarPdf().then((_) {
                    if (mounted) _dialogTourAberto = false;
                  });

                  await Future<void>.delayed(const Duration(milliseconds: 80));
                }
              },
            ),
          RoboTourStop(
            key: () => _tourKeyExportarStatus,
            texto: 'Selecione quais materiais deseja incluir no relatório: '
                'todos os status, ou apenas OK, Limite ou Crítico.',
            aoEntrar: widget.categoriaId == _kCategoriaGeral
                ? null
                : () async {
                    if (!_dialogTourAberto) {
                      _dialogTourAberto = true;
                      _exportarPdf().then((_) {
                        if (mounted) _dialogTourAberto = false;
                      });

                      await Future<void>.delayed(const Duration(milliseconds: 80));
                    }
                  },
          ),
          RoboTourStop(
            key: () => _tourKeyExportarBotao,
            texto: 'Por fim, toque em "Exportar" para gerar o PDF.',
          ),
        ],
        aoEncerrar: () async {
          _fecharVerMais();
          if (_dialogTourAberto) {
            _dialogTourAberto = false;
            await Navigator.of(context, rootNavigator: true).maybePop();
          }
        },
      ),
    ]);
  }

  Future<void> _abrirFormMaterial(
    [MaterialModel? material, bool abrirComoGenerico = false]
  ) async {
    // Material genérico: em vez de abrir o form de edição direto, mostra
    // primeiro o dialog com as variantes vinculadas a ele. Escolher uma
    // variante abre o form de edição dela normalmente; "Novo material
    // vinculado" (dentro do dialog) abre o form já pré-preenchido com o
    // vínculo ao genérico. `abrirComoGenerico: true` pula essa etapa e
    // abre direto o form de edição do próprio genérico (botão "Editar"
    // dentro do dialog de variantes).
    if (material != null && material.ehGenerico && !abrirComoGenerico) {
      final escolhido = await showMaterialVinculadosDialog(
        context,
        materialGenerico: material,
        apenasAtivos: false,
      );
      if (!mounted) return;
      if (escolhido != null) {
        // Se o próprio material genérico foi retornado (botão "Editar" do
        // dialog de variantes), abre o form de edição dele diretamente,
        // em vez de reabrir o dialog de variantes de novo.
        // Se o próprio material genérico foi retornado (botão "Editar" do
        // dialog de variantes), abre o form de edição dele diretamente,
        // passando `abrirComoGenerico: true` para não cair de novo no
        // ramo acima (que reabriria o dialog de variantes).
        if (escolhido.id == material.id) {
          await _abrirFormMaterial(escolhido, true);
        } else {
          await _abrirFormMaterial(escolhido);
        }
      }
      return;
    }

    final roleAtual = context.read<UsuarioProvider>().usuarioLogado?.role;
    final isCompras = roleAtual == 'COMPRAS';
    debugPrint('[Page] _abrirFormMaterial() ABRINDO showDialog(_MaterialFormDialog) editando=${material != null}');
    final salvou = await showDialog(
      context: context,

      barrierDismissible: !_dialogTourAberto,
      builder: (_) => _MaterialFormDialog(
        material:    material,
        onDesativar: (!isCompras && material != null) ? _desativar : null,
        onReativar:  (!isCompras && material != null) ? _reativar  : null,
        onExcluir:   (!isCompras && material != null) ? _excluir   : null,
        roleUsuario: roleAtual,
        somenteLeitura: false,
        tourKeys: _materialTourKeys,
      ),
    );
    debugPrint('[Page] _abrirFormMaterial() showDialog RETORNOU salvou=$salvou mounted=$mounted');
    if (!mounted) return;
    if (salvou == true) {
      context.read<MaterialProvider>().carregarCategorias();
      _recarregarSemResetarPagina();
      if (context.mounted) {
        context.read<ProdutoProvider>().recarregar();
        context.read<OrcamentoVendaProvider>().recarregar();
      }
    }
  }

  Future<bool> _recusarPendente(MaterialModel material) async {
    final provider = context.read<MaterialProvider>();
    final ok = await provider.recusarPendente(material.id);
    if (!mounted) return ok;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '"${material.nome}" recusado e excluído.'
          : provider.erro ?? 'Erro ao recusar material.'),
      backgroundColor: ok ? AppTheme.success : AppTheme.error,
    ));
    return ok;
  }

  /// Abre o mesmo _MaterialFormDialog usado para cadastro/edição, mas em
  /// modo `aprovando: true` — o ADMIN pode alterar qualquer campo livremente
  /// e o botão principal vira "Aprovar" em vez de "Cadastrar"/"Salvar".
  Future<void> _abrirFormAprovacao(MaterialModel material) async {
    debugPrint('[Page] _abrirFormAprovacao() ABRINDO showDialog(_MaterialFormDialog, aprovando=true) '
        'material=${material.id}');
    final resultado = await showDialog(
      context: context,
      builder: (_) => _MaterialFormDialog(
        material: material,
        aprovando: true,
        onRecusar: (m) async {
          final ok = await _recusarPendente(m);
          if (!mounted) return;
          if (ok) {
            context.read<MaterialProvider>().carregarPendentes();
          }
        },
      ),
    );
    debugPrint('[Page] _abrirFormAprovacao() showDialog RETORNOU resultado=$resultado mounted=$mounted');
    if (!mounted) return;
    if (resultado == true) {
      _recarregarSemResetarPagina();
      context.read<MaterialProvider>().carregarPendentes();
    }
  }

  /// Abre o dialog com a lista de materiais aguardando aprovação. Ao tocar
  /// em um item, abre o form de aprovação (_abrirFormAprovacao). Fecha e
  /// reabre automaticamente enquanto a lista muda (aprovar/recusar
  /// atualizam a lista em tempo real via provider).
  Future<void> _abrirListaAguardandoAprovacao() async {
    final provider = context.read<MaterialProvider>();
    await provider.carregarPendentes();
    if (!mounted) return;
    debugPrint('[Page] _abrirListaAguardandoAprovacao() ABRINDO showDialog(_AguardandoAprovacaoDialog)');
    await showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider<MaterialProvider>.value(
        value: provider,
        child: _AguardandoAprovacaoDialog(
          onAbrirMaterial: _abrirFormAprovacao,
        ),
      ),
    );
    debugPrint('[Page] _abrirListaAguardandoAprovacao() showDialog(_AguardandoAprovacaoDialog) RETORNOU mounted=$mounted');
    if (!mounted) return;
    _recarregarSemResetarPagina();
  }

  void _abrirPrecosFornecedores(MaterialModel material) {
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider<MaterialProvider>.value(
        value: context.read<MaterialProvider>(),
        child: _HistoricoPrecoDialog(material: material),
      ),
    );
  }

  Future<void> _desativar(MaterialModel m) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Desativar material'),
        content: Text(
          'Deseja desativar "${m.nome}"?\n\nSe ele estiver vinculado a ordens em andamento, a operação será bloqueada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final ok = await context.read<MaterialProvider>().desativar(m.id);
    if (!mounted) return;
    if (ok) _recarregarSemResetarPagina();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '"${m.nome}" desativado.' : context.read<MaterialProvider>().erro ?? 'Erro'),
      backgroundColor: ok ? AppTheme.warning : AppTheme.error,
    ));
  }

  Future<void> _reativar(MaterialModel m) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reativar material'),
        content: Text('Deseja reativar "${m.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Reativar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final ok = await context.read<MaterialProvider>().reativar(m.id);
    if (!mounted) return;
    if (ok) _recarregarSemResetarPagina();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '"${m.nome}" reativado.' : context.read<MaterialProvider>().erro ?? 'Erro'),
      backgroundColor: ok ? AppTheme.success : AppTheme.error,
    ));
  }

  Future<void> _excluir(MaterialModel m) async {
    if (m.ativo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Desative o material antes de excluí-lo.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir material'),
        content: Text('Tem certeza que deseja excluir "${m.nome}" permanentemente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final ok = await context.read<MaterialProvider>().excluir(m.id);
    if (!mounted) return;
    if (ok) _recarregarSemResetarPagina();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '"${m.nome}" excluído.' : context.read<MaterialProvider>().erro ?? 'Erro'),
      backgroundColor: AppTheme.error,
    ));
  }

  Future<void> _exportarPdf() async {
    final mostrarSeletorCategoria = widget.categoriaId == _kCategoriaGeral;

    final escolha = await showDialog<({String status, String categoria})>(
      context: context,
      builder: (ctx) {
        return _ExportarPdfDialog(
          mostrarSeletorCategoria: mostrarSeletorCategoria,
          categorias:              context.read<MaterialProvider>().categorias,
          categoriaInicial:        _categoriaFiltro,
          tourKeyCategoria:        _tourKeyExportarCategoria,
          tourKeyStatus:           _tourKeyExportarStatus,
          tourKeyBotaoExportar:    _tourKeyExportarBotao,
        );
      },
    );
    if (escolha == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 3),
        backgroundColor: AppTheme.primary,
      ),
    );

    final String? catParam = mostrarSeletorCategoria
        ? (escolha.categoria.isEmpty ? null : escolha.categoria)
        : widget.categoriaId == _kCategoriaSemCategoria
            ? ''
            : widget.categoriaId;

    final String? statusParam =
        escolha.status == 'TODOS' ? null : escolha.status;

    try {
      final bytes = await EstoqueRepository().baixarPdf(
        categoria: catParam,
        status:    statusParam,
      );

      if (bytes.length < 4 ||
          bytes[0] != 0x25 || bytes[1] != 0x50 ||
          bytes[2] != 0x44 || bytes[3] != 0x46) {
        throw Exception('O servidor não retornou um PDF válido. Verifique o console do backend.');
      }

      final catLabel = catParam == null
          ? 'GERAL'
          : catParam.isEmpty
              ? 'SEM_CATEGORIA'
              : catParam.toUpperCase().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final stLabel  = statusParam ?? 'TODOS';
      final fileName = 'estoque_${catLabel}_$stLabel.pdf';

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (Platform.isWindows) {

        await Process.run('cmd', ['/c', 'start', '', file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: ${_mensagemErroAmigavelPdf(e)}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _orcarFiltrados() async {
    final provider = context.read<MaterialProvider>();

    final totalFiltrado = provider.totalItensPagina;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Orçar materiais filtrados'),
        content: Text(
          'Deseja orçar os $totalFiltrado material${totalFiltrado == 1 ? '' : 'is'} filtrado${totalFiltrado == 1 ? '' : 's'}?',
        ),
        actions: [
          Tooltip(
            message: 'Fechar sem orçar',
            child: TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              style: TextButton.styleFrom()
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              child: const Text('Cancelar'),
            ),
          ),
          Tooltip(
            message: 'Criar orçamento com os materiais filtrados',
            child: FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              child: const Text('Orçar'),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Carregando materiais...'),
      duration: Duration(seconds: 2),
    ));
    await provider.carregar(
      busca:         _buscaCtrl.text,
      categoria:     _categoriaParaProvider(),
      status:        _statusFiltro,
      identificador: _identificadorCtrl.text.trim(),
      medida:        _medidaCtrl.text.trim(),
      espessura:     _espessuraCtrl.text.trim(),
      largura:       _larguraCtrl.text.trim(),
      comprimento:   _comprimentoCtrl.text.trim(),
      ativo:         null,
    );
    if (!mounted) return;
    final todos = provider.materiais;
    final materiais = _comFornecedor == null
        ? todos
        : _comFornecedor == true
            ? todos.where((m) => m.fornecedorMateriais.isNotEmpty).toList()
            : todos.where((m) => m.fornecedorMateriais.isEmpty).toList();
    if (materiais.isEmpty) return;

    final itens = materiais.map((m) {
      final precos = <int, PrecoFornecedorData>{};
      for (final fm in m.fornecedorMateriais) {
        precos[fm.fornecedorId] = PrecoFornecedorData(
          fornecedorNome: fm.fornecedorNome,
          preco:   fm.preco > 0 ? fm.preco : null,
        );
      }
      return ItemOrcamentoData(
        materialId:            m.id,
        materialNome:          m.nome,
        materialUnidade:       m.unidade,
        materialCategoria:     m.categoria,
        materialMedida:        m.medida,
        materialEspessura:     m.espessura,
        materialIdentificador: m.identificador,
        materialStatus:        m.status,
        materialLargura:       m.largura,
        materialComprimento:   m.comprimento,
        estoqueMinimo:         m.estoqueMinimo,
        precos:                precos,
      );
    }).toList();

    final partes = <String>[];
    if (widget.categoriaId != _kCategoriaGeral &&
        widget.categoriaId != _kCategoriaSemCategoria) {
      partes.add(widget.categoriaLabel);
    } else if (_categoriaFiltro.isNotEmpty) {
      partes.add(_categoriaFiltro);
    }
    if (_medidaCtrl.text.trim().isNotEmpty) {
      partes.add(_medidaCtrl.text.trim());
    }
    if (_espessuraCtrl.text.trim().isNotEmpty) {
      partes.add(_espessuraCtrl.text.trim());
    }
    if (_buscaCtrl.text.trim().isNotEmpty) {
      partes.add(_buscaCtrl.text.trim());
    }
    final titulo = partes.isNotEmpty
        ? 'Orç. ${partes.join(' · ')}'
        : 'Orç. ${widget.categoriaLabel}';

    if (!mounted) return;
    context.read<OrcamentoProvider>().adicionarItensEmLote(titulo, itens);

    OrcamentoPage.abrirEditorAoEntrar = true;
    context.go('/orcamento');
  }

  void _fecharVerMais() {
    _verMaisOverlay?.remove();
    _verMaisOverlay = null;
    if (_verMaisAberto && mounted) {
      setState(() => _verMaisAberto = false);
    } else {
      _verMaisAberto = false;
    }
  }

  void _abrirVerMais() {
    if (_verMaisAberto) return;
    final overlay = Overlay.of(context, rootOverlay: true);

    _verMaisOverlay = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            // Área transparente que fecha o dropdown ao clicar fora dele.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _fecharVerMais,
              ),
            ),
            CompositedTransformFollower(
              link: _verMaisLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 8),
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              child: _VerMaisDropdown(
                tourKeyOrcar: _tourKeyOrcar,
                tourKeyExportar: _tourKeyExportar,
                onOrcar: () {
                  _fecharVerMais();
                  _orcarFiltrados();
                },
                onExportar: () {
                  _fecharVerMais();
                  _exportarPdf();
                },
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_verMaisOverlay!);
    setState(() => _verMaisAberto = true);
  }

  void _alternarVerMais() {
    if (_verMaisAberto) {
      _fecharVerMais();
    } else {
      _abrirVerMais();
    }
  }

  /// Botão de ação do cabeçalho — base única e compartilhada por "Ver mais",
  /// "Histórico", "Aguardando aprovação" e "Novo Material", garantindo que
  /// todos tenham exatamente a mesma altura, raio e comportamento de toque,
  /// variando apenas a cor (que carrega a hierarquia/semântica de cada um).
  Widget _botaoCabecalho({
    Key? key,
    required IconData icone,
    required String texto,
    required VoidCallback onPressed,
    required Color corFundo,
    required Color corTexto,
    required double iconSize,
    required double fontSize,
    required double padH,
    required double padV,
    String? tooltip,
    Color? corBorda,
    Widget? badge,
  }) {
    return _BotaoCabecalhoWidget(
      tourKey: key,
      icone: icone,
      texto: texto,
      onPressed: onPressed,
      corFundo: corFundo,
      corTexto: corTexto,
      iconSize: iconSize,
      fontSize: fontSize,
      padH: padH,
      padV: padV,
      tooltip: tooltip,
      corBorda: corBorda,
      badge: badge,
    );
  }

  /// Botão "Ver mais" — agrupa "Orçar filtrados" e "Exportar Estoque (PDF)"
  /// num dropdown customizado, para evitar overflow horizontal na barra
  /// de ações. Usa um OverlayEntry próprio (em vez de PopupMenuButton) para
  /// que os itens do dropdown tenham GlobalKeys estáveis, permitindo que o
  /// tour do robô os destaque normalmente.
  Widget _botaoVerMais({
    required double iconSize,
    required double fontSize,
    required double padH,
    required double padV,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CompositedTransformTarget(
      link: _verMaisLink,
      child: _botaoCabecalho(
        key: _tourKeyVerMais,
        icone: Icons.more_horiz,
        texto: 'Ver mais',
        onPressed: _alternarVerMais,
        corFundo: scheme.surfaceContainerHighest,
        corTexto: scheme.onSurface,
        corBorda: isDark ? scheme.outlineVariant : null,
        iconSize: iconSize,
        fontSize: fontSize,
        padH: padH,
        padV: padV,
        tooltip: 'Mais opções',
      ),
    );
  }

  Widget _botaoHistorico({
    required bool compacto,
    required double iconSize,
    required double fontSize,
    required double padH,
    required double padV,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _botaoCabecalho(
      key: _tourKeyHistorico,
      icone: Icons.history,
      texto: 'Histórico',
      onPressed: () {
        context.read<RoboHelperProvider>().encerrarTour();
        context.read<RoboHelperProvider>().limparOpcoes('/estoque');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const HistoricoMaterialPage(),
          ),
        ).then((_) {
          if (mounted) _registrarAjudaRoboCategoria();
        });
      },
      corFundo: scheme.surfaceContainerHighest,
      corTexto: scheme.onSurface,
      corBorda: isDark ? scheme.outlineVariant : null,
      iconSize: iconSize,
      fontSize: fontSize,
      padH: padH,
      padV: padV,
      tooltip: 'Ver histórico de movimentações do estoque',
    );
  }

  Widget _botaoNovoMaterial({
    required bool compacto,
    required bool muitoCompacto,
    required double iconSize,
    required double fontSize,
    required double padHPrimario,
    required double padV,
  }) {
    return _botaoCabecalho(
      key: _tourKeyNovoMaterial,
      icone: Icons.add,
      texto: muitoCompacto ? 'Novo' : 'Novo Material',
      onPressed: () => _abrirFormMaterial(),
      corFundo: AppTheme.primary,
      corTexto: Colors.white,
      iconSize: iconSize,
      fontSize: fontSize,
      padH: padHPrimario,
      padV: padV,
      tooltip: 'Cadastrar novo material no estoque',
    );
  }

  /// Botão "Aguardando aprovação" — aparece para ADMIN e GERENTE, mostra um
  /// badge com a quantidade de materiais pendentes e abre a lista ao clicar.
  Widget _botaoAguardandoAprovacao({
    required bool compacto,
    required bool muitoCompacto,
    required double iconSize,
    required double fontSize,
    required double padH,
    required double padV,
  }) {
    final roleAtual = context.watch<UsuarioProvider>().usuarioLogado?.role;
    if (roleAtual != 'ADMIN' && roleAtual != 'GERENTE') {
      return const SizedBox.shrink();
    }

    final total = context.watch<MaterialProvider>().totalPendentes;
    final scheme = Theme.of(context).colorScheme;

    Widget? badge;
    if (total > 0) {
      badge = Positioned(
        right: -6,
        top: -6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppTheme.error,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.surface, width: 1.5),
          ),
          constraints: const BoxConstraints(minWidth: 18),
          child: Text(
            total > 99 ? '99+' : '$total',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return _botaoCabecalho(
      icone: Icons.hourglass_top,
      texto: muitoCompacto ? 'Aprovação' : 'Aguardando aprovação',
      onPressed: _abrirListaAguardandoAprovacao,
      corFundo: AppTheme.warning,
      corTexto: Colors.white,
      iconSize: iconSize,
      fontSize: fontSize,
      padH: padH,
      padV: padV,
      tooltip: total > 0
          ? '$total material(is) aguardando aprovação de cadastro'
          : 'Nenhum material aguardando aprovação',
      badge: badge,
    );
  }

  Widget _botaoRefresh({required double iconSize}) {
    return IconButton(
      onPressed: _aplicarFiltros,
      icon: Icon(Icons.refresh, size: iconSize, color: Theme.of(context).colorScheme.onSurfaceVariant),
      tooltip: 'Atualizar',
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cor    = widget.cor;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _registrarAjudaRoboCategoria();
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 1150;
                final muitoCompacto = constraints.maxWidth < 750;

                final iconSize = muitoCompacto ? 13.0 : (compacto ? 15.0 : 18.0);
                final fontSize = muitoCompacto ? 11.0 : (compacto ? 12.0 : 14.0);
                final padH = muitoCompacto ? 8.0 : (compacto ? 12.0 : 16.0);
                final padHPrimario = muitoCompacto ? 8.0 : (compacto ? 12.0 : 20.0);
                final padV = muitoCompacto ? 6.0 : (compacto ? 8.0 : 12.0);
                final espacamento = muitoCompacto ? 4.0 : (compacto ? 6.0 : 12.0);

                return Row(
                  children: [
                    _BotaoVoltar(
                      label: widget.mostrarBotaoIdentificadores
                          ? widget.categoriaLabel
                          : 'Categorias',
                      tooltip: widget.mostrarBotaoIdentificadores
                          ? 'Voltar para ${widget.categoriaLabel}'
                          : 'Voltar para categorias',
                      onTap: () => Navigator.of(context).pop(),
                      iconSize: iconSize,
                      fontSize: fontSize,
                      padH: padH,
                      padV: padV,
                    ),
                    const SizedBox(width: 16),

                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icone, color: cor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        if (widget.mostrarBotaoIdentificadores && widget.identificadorLabel != null)
                          Row(
                            children: [
                              Text(
                                widget.categoriaLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.chevron_right, size: 14, color: Theme.of(context).colorScheme.outline),
                              ),
                              Text(
                                widget.identificadorLabel!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: cor,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        Text(
                          widget.mostrarBotaoIdentificadores && widget.identificadorLabel != null
                              ? widget.identificadorLabel!
                              : widget.categoriaLabel,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Materiais desta categoria',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    ),
                    SizedBox(width: espacamento),
                    _botaoVerMais(iconSize: iconSize, fontSize: fontSize, padH: padH, padV: padV),
                    SizedBox(width: espacamento),
                    _botaoHistorico(compacto: compacto, iconSize: iconSize, fontSize: fontSize, padH: padH, padV: padV),
                    SizedBox(width: espacamento),
                    _botaoAguardandoAprovacao(compacto: compacto, muitoCompacto: muitoCompacto, iconSize: iconSize, fontSize: fontSize, padH: padH, padV: padV),
                    SizedBox(width: espacamento),
                    _botaoNovoMaterial(compacto: compacto, muitoCompacto: muitoCompacto, iconSize: iconSize, fontSize: fontSize, padHPrimario: padHPrimario, padV: padV),
                    SizedBox(width: espacamento),
                    _botaoRefresh(iconSize: iconSize),
                  ],
                );
              },
            ),
            SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: KeyedSubtree(
                  key: _tourKeyBusca,
                  child: TextField(
                    controller: _buscaCtrl,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText:   'Nome do material',
                      prefixIcon: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense:    true,
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.categoriaId == _kCategoriaGeral) ...[
                  SizedBox(
                    width: 160,
                    child: KeyedSubtree(
                    key: _tourKeyFiltroCategoria,
                    child: Consumer<MaterialProvider>(
                      builder: (_, provider, __) {
                        final categorias = provider.categorias;

                        final valorValido = _categoriaFiltro.isEmpty ||
                            categorias.contains(_categoriaFiltro);
                        return _CategoriaFiltroDropdown(
                          categorias: categorias,
                          valorSelecionado: valorValido ? _categoriaFiltro : '',
                          onSelecionar: (v) {
                            setState(() => _categoriaFiltro = v);
                            _aplicarFiltros();
                          },
                        );
                      },
                    ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                KeyedSubtree(
                  key: _tourKeyFiltroStatus,
                  child: _StatusFiltroDropdown(
                  menuController: _statusMenuController,
                  valorSelecionado: _statusFiltro,
                  onSelecionar: (v) {
                    setState(() => _statusFiltro = v);
                    _aplicarFiltros();
                  },
                  ),
                ),
                SizedBox(width: 8),
                KeyedSubtree(
                key: _tourKeyFiltroFornecedor,
                child: _FornecedorFiltroDropdown(
                  valorSelecionado: _comFornecedor,
                  onSelecionar: (v) {
                    setState(() => _comFornecedor = v);
                    _aplicarFiltros();
                  },
                ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final temFiltro = _buscaCtrl.text.isNotEmpty ||
                        _identificadorCtrl.text.isNotEmpty ||
                        _medidaCtrl.text.isNotEmpty ||
                        _espessuraCtrl.text.isNotEmpty ||
                        _larguraCtrl.text.isNotEmpty ||
                        _comprimentoCtrl.text.isNotEmpty ||
                        _statusFiltro.isNotEmpty ||
                        _categoriaFiltro.isNotEmpty ||
                        _comFornecedor != null;
                    return IconButton.outlined(
                      tooltip: 'Limpar filtros',
                      icon: Icon(
                        Icons.filter_alt_off,
                        color: temFiltro
                            ? scheme.onSurfaceVariant
                            : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                      onPressed: temFiltro
                          ? () {
                              _buscaCtrl.clear();
                              _identificadorCtrl.clear();
                              _medidaCtrl.clear();
                              _espessuraCtrl.clear();
                              _larguraCtrl.clear();
                              _comprimentoCtrl.clear();
                              setState(() {
                                _statusFiltro    = '';
                                _categoriaFiltro = '';
                                _comFornecedor   = null;
                              });
                              _aplicarFiltros();
                            }
                          : null,
                      style: IconButton.styleFrom(
                        side: BorderSide(
                          color: temFiltro
                              ? Theme.of(context).colorScheme.outline
                              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
                        ),
                      ).copyWith(
                        mouseCursor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.disabled)) {
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
            SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                  key: _tourKeyFiltroIdent,
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: InputDecoration(
                      hintText:   'Identificador',
                      prefixIcon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      setState(() {});
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                  key: _tourKeyFiltroMedida,
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: InputDecoration(
                      hintText:   'Medida',
                      prefixIcon: Icon(Icons.straighten, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    inputFormatters: [_MedidaEspessuraFormatter()],
                    onChanged: (_) {
                      setState(() {});
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                  key: _tourKeyFiltroComp,
                  child: TextField(
                    controller: _comprimentoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText:   'Comprimento',
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: 1,
                          child: Text(
                            'm',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      prefixIcon: Icon(Icons.height, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) {
                      setState(() {});
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                  key: _tourKeyFiltroLargura,
                  child: TextField(
                    controller: _larguraCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText:   'Largura',
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: 1,
                          child: Text(
                            'm',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      prefixIcon: Icon(Icons.width_normal, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) {
                      setState(() {});
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                  key: _tourKeyFiltroEspessura,
                  child: TextField(
                    controller: _espessuraCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText:   'Espessura',
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: 1,
                          child: Text(
                            'mm',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      prefixIcon: Icon(Icons.layers, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) {
                      setState(() {});
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                          const Duration(milliseconds: 400), _aplicarFiltros);
                    },
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: Consumer<MaterialProvider>(
                builder: (_, provider, __) {
                  if (provider.carregandoPagina) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    );
                  }
                  if (provider.erro != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          SizedBox(height: 12),
                          Text(
                            'Erro ao carregar materiais',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            provider.erro!.contains(': ')
                                ? provider.erro!.substring(provider.erro!.indexOf(': ') + 2)
                                : provider.erro!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _aplicarFiltros,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ],
                      ),
                    );
                  }
                  final paginados = provider.materiaisPagina;

                  if (paginados.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64, color: Theme.of(context).colorScheme.outline),
                          SizedBox(height: 16),
                          Text(
                            _comFornecedor == true
                                ? 'Nenhum material com fornecedor vinculado'
                                : _comFornecedor == false
                                    ? 'Nenhum material sem fornecedor vinculado'
                                    : 'Nenhum material encontrado',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _comFornecedor != null
                                ? 'Altere o filtro "Fornecedor" para ver todos.'
                                : 'Clique em "Novo Material" para adicionar.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Theme.of(context).colorScheme.outline),
                          ),
                        ],
                      ),
                    );
                  }
                  final totalItens  = provider.totalItensPagina;
                  final totalPaginas = (totalItens / _itensPorPagina).ceil().clamp(1, 999999999);

                  final mostrarCat = widget.categoriaId == _kCategoriaGeral;
                  return Column(
                    children: [
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: _TabelaMateriais(
                            materiais:            paginados,
                            onEditar:             _abrirFormMaterial,
                            onVerFornecedores:    _abrirPrecosFornecedores,
                            onVerHistoricoPrecos: _abrirHistoricoPrecos,
                            mostrarCategoria:     mostrarCat,
                            colunaOrdem:          _colunaOrdem,
                            crescente:            _crescente,
                            onToggleOrdem:        _toggleOrdem,
                          ),
                        ),
                      ),
                      if (totalPaginas > 1) ...[
                        const SizedBox(height: 12),
                        _BarraPaginacao(
                          paginaAtual:     _paginaAtual,
                          totalPaginas:    totalPaginas,
                          totalItens:      totalItens,
                          itensPorPagina:  _itensPorPagina,
                          onPaginaChanged: (p) => _carregarPaginaAtual(irParaPagina: p),
                        ),
                      ],
                    ],
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

/// Conteúdo do dropdown do botão "Ver mais": agrupa "Orçar filtrados" e
/// "Exportar Estoque (PDF)". Cada item usa uma GlobalKey estável (recebida
/// de fora) para que o tour do robô consiga medir e destacar o item mesmo
/// dentro deste overlay.
class _VerMaisDropdown extends StatelessWidget {
  final GlobalKey tourKeyOrcar;
  final GlobalKey tourKeyExportar;
  final VoidCallback onOrcar;
  final VoidCallback onExportar;

  const _VerMaisDropdown({
    required this.tourKeyOrcar,
    required this.tourKeyExportar,
    required this.onOrcar,
    required this.onExportar,
  });

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MaterialProvider>();
    final total = mp.totalItensPagina;
    final temMateriais = !mp.carregandoPagina && total > 0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).colorScheme.surfaceContainerHigh;
    final dividerColor = Theme.of(context).colorScheme.outlineVariant;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VerMaisItem(
              key: tourKeyOrcar,
              icon: Icons.request_quote,
              iconColor: const Color(0xFF1E88E5),
              label: temMateriais ? 'Orçar filtrados ($total)' : 'Orçar filtrados',
              enabled: temMateriais,
              isDark: isDark,
              onTap: onOrcar,
            ),
            Divider(height: 1, color: dividerColor, indent: 14, endIndent: 14),
            _VerMaisItem(
              key: tourKeyExportar,
              icon: Icons.picture_as_pdf,
              iconColor: const Color(0xFFE85D04),
              label: 'Exportar Estoque (PDF)',
              enabled: true,
              isDark: isDark,
              onTap: onExportar,
            ),
          ],
        ),
      ),
    );
  }
}

class _VerMaisItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool enabled;
  final bool isDark;
  final VoidCallback onTap;

  const _VerMaisItem({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.enabled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: iconColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardEspecialData {
  final String id;
  final String label;
  final IconData icone;
  final Color cor;
  const _CardEspecialData({
    required this.id,
    required this.label,
    required this.icone,
    required this.cor,
  });
}

class _CategoriaCardCompact extends StatefulWidget {
  final String categoria;
  final Color cor;
  final IconData icone;
  final VoidCallback onTap;

  const _CategoriaCardCompact({
    required this.categoria,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_CategoriaCardCompact> createState() => _CategoriaCardCompactState();
}

class _CategoriaCardCompactState extends State<_CategoriaCardCompact> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ativo = _hovered;
    return MouseRegion(
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: ativo
                ? widget.cor.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo
                  ? widget.cor
                  : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icone, color: widget.cor, size: 24),
              ),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.categoria,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ativo ? widget.cor : Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarraPaginacao extends StatelessWidget {
  final int paginaAtual;
  final int totalPaginas;
  final int totalItens;
  final int itensPorPagina;
  final void Function(int) onPaginaChanged;

  const _BarraPaginacao({
    required this.paginaAtual,
    required this.totalPaginas,
    required this.totalItens,
    required this.itensPorPagina,
    required this.onPaginaChanged,
  });

  List<int> _paginas() {
    if (totalPaginas <= 7) return List.generate(totalPaginas, (i) => i);
    final Set<int> vis = {0, totalPaginas - 1, paginaAtual};
    if (paginaAtual > 0) vis.add(paginaAtual - 1);
    if (paginaAtual < totalPaginas - 1) vis.add(paginaAtual + 1);
    final sorted = vis.toList()..sort();
    final List<int> result = [];
    for (int i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) result.add(-1);
      result.add(sorted[i]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final inicio  = paginaAtual * itensPorPagina + 1;
    final fim     = ((paginaAtual + 1) * itensPorPagina).clamp(0, totalItens);
    final paginas = _paginas();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Exibindo $inicio–$fim de $totalItens materiais',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BotaoPagina(
                icon: Icons.chevron_left,
                tooltip: 'Página anterior',
                enabled: paginaAtual > 0,
                onTap: () => onPaginaChanged(paginaAtual - 1),
              ),
              SizedBox(width: 4),
              for (final p in paginas) ...[
                if (p == -1)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  )
                else
                  _BotaoNumeroPagina(
                    numero: p,
                    ativa: p == paginaAtual,
                    onTap: () => onPaginaChanged(p),
                  ),
                const SizedBox(width: 4),
              ],
              _BotaoPagina(
                icon: Icons.chevron_right,
                tooltip: 'Próxima página',
                enabled: paginaAtual < totalPaginas - 1,
                onTap: () => onPaginaChanged(paginaAtual + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotaoPagina extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _BotaoPagina({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? Theme.of(context).colorScheme.outlineVariant : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _BotaoNumeroPagina extends StatelessWidget {
  final int numero;
  final bool ativa;
  final VoidCallback onTap;

  const _BotaoNumeroPagina({
    required this.numero,
    required this.ativa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: ativa ? null : onTap,
      mouseCursor: ativa ? SystemMouseCursors.basic : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: ativa ? AppTheme.primary : Colors.transparent,
          border: Border.all(
            color: ativa ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '${numero + 1}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: ativa ? FontWeight.w700 : FontWeight.w400,
            color: ativa ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String message;
  const _EmptySection({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.8),
        ),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

class _TabelaMateriais extends StatefulWidget {
  final List<MaterialModel> materiais;
  final void Function(MaterialModel) onEditar;
  final void Function(MaterialModel) onVerFornecedores;
  final void Function(MaterialModel) onVerHistoricoPrecos;
  final bool mostrarCategoria;
  final String? colunaOrdem;
  final bool crescente;
  final void Function(String sortKey) onToggleOrdem;

  const _TabelaMateriais({
    required this.materiais,
    required this.onEditar,
    required this.onVerFornecedores,
    required this.onVerHistoricoPrecos,
    this.mostrarCategoria = true,
    required this.colunaOrdem,
    required this.crescente,
    required this.onToggleOrdem,
  });

  static const List<_ColDef> _colsBase = [
    _ColDef(label: 'ID',                          fixed: 56,  sortKey: 'id'),
    _ColDef(label: 'Identificador',               flex: 1.0,  minWidth: 160, sortKey: 'identificador'),
    _ColDef(label: 'Material',                    flex: 2.0,  minWidth: 200, sortKey: 'nome'),
    _ColDef(label: 'Categoria',                   flex: 1.0,  minWidth: 110, sortKey: 'categoria'),
    _ColDef(label: 'Medida',                      flex: 0.8,  minWidth: 100, sortKey: 'medida'),
    _ColDef(label: 'Espessura',                   flex: 0.7,  minWidth: 100, sortKey: 'espessura'),
    _ColDef(label: 'Comprimento',                 flex: 0.8,  minWidth: 120, sortKey: 'comprimento'),
    _ColDef(label: 'Largura',                     flex: 0.7,  minWidth: 100, sortKey: 'largura'),
    _ColDef(label: 'Estoque atual',               flex: 0.6,  minWidth: 120, sortKey: 'quantidade'),
    _ColDef(label: 'Estoque mínimo',              flex: 0.6,  minWidth: 130, sortKey: 'estoqueMinimo'),
    _ColDef(label: 'Unidade',                     flex: 0.9,  minWidth: 100, sortKey: 'unidade'),
    _ColDef(label: 'Preço',                       flex: 0.9,  minWidth: 140, sortKey: 'ultimoValorPago'),
    _ColDef(label: 'Status',                      flex: 0.6,  minWidth: 120, sortKey: 'status'),
    _ColDef(label: '',                             fixed: 40),
  ];

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(
          flex: (col.flex! * 10).round(),
          child: child,
        );

  @override
  State<_TabelaMateriais> createState() => _TabelaMateriaisState();
}

class _TabelaMateriaisState extends State<_TabelaMateriais> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<_ColDef> get _cols => widget.mostrarCategoria
      ? _TabelaMateriais._colsBase
      : _TabelaMateriais._colsBase.where((c) => c.label != 'Categoria').toList();

  Widget _cabecalho() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            for (final col in _cols)
              _TabelaMateriais._colWrap(
                col,
                col.sortKey != null
                    ? _CabecalhoOrdenavel(
                        label:    col.label,
                        ativo:    widget.colunaOrdem == col.sortKey,
                        crescente: widget.crescente,
                        onTap:    () => widget.onToggleOrdem(col.sortKey!),
                      )
                    : Padding(
                        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        child: Text(
                          col.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final materiais = widget.materiais;

    Widget corpoRolavel = SingleChildScrollView(
      controller: _scrollCtrl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (materiais.isEmpty)
            _EmptySection(message: 'Nenhum material encontrado.')
          else ...[
            for (int i = 0; i < materiais.length; i++) ...[
              if (i > 0)
                Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
              _LinhaMateria(
                material:             materiais[i],
                cols:                 _cols,
                onEditar:             widget.onEditar,
                onVerFornecedores:    widget.onVerFornecedores,
                onVerHistoricoPrecos: widget.onVerHistoricoPrecos,
                mostrarCategoria:     widget.mostrarCategoria,
              ),
            ],
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        _cabecalho(),
        Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),

        Expanded(child: corpoRolavel),
      ],
    );
  }
}

class _ColDef {
  final String  label;
  final double? fixed;
  final double? flex;

  final double  minWidth;

  final String? sortKey;
  const _ColDef({
    required this.label,
    this.fixed,
    this.flex,
    this.minWidth = 90,
    this.sortKey,
  });
}

class _CabecalhoOrdenavel extends StatelessWidget {
  final String label;
  final bool   ativo;
  final bool   crescente;
  final VoidCallback onTap;

  const _CabecalhoOrdenavel({
    required this.label,
    required this.ativo,
    required this.crescente,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: ativo ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  ativo
                      ? (crescente
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded)
                      : Icons.unfold_more_rounded,
                  size: 12,
                  color: ativo ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaMateria extends StatefulWidget {
  final MaterialModel material;
  final List<_ColDef> cols;
  final void Function(MaterialModel) onEditar;
  final void Function(MaterialModel) onVerFornecedores;
  final void Function(MaterialModel) onVerHistoricoPrecos;
  final bool mostrarCategoria;

  const _LinhaMateria({
    required this.material,
    required this.cols,
    required this.onEditar,
    required this.onVerFornecedores,
    required this.onVerHistoricoPrecos,
    this.mostrarCategoria = true,
  });

  @override
  State<_LinhaMateria> createState() => _LinhaMateriaState();
}

class _LinhaMateriaState extends State<_LinhaMateria> {
  bool _hovered  = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(
          flex: (col.flex! * 10).round(),
          child: child,
        );

  static Widget _cell(String text, BuildContext context, {bool inativo = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: inativo ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );

  Widget _buildLinhaRaiz(BuildContext context) {
    final m       = widget.material;
    final inativo = !m.ativo;
    final cols    = widget.cols;

    final bgColor = _hovered
        ? Color(0xFFFF9800).withValues(alpha: 0.10)
        : inativo
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.surface;

    Widget maybeOpacity(Widget child) =>
        inativo ? Opacity(opacity: 0.45, child: child) : child;

    Widget estoqueAtualCell() {
      return maybeOpacity(_cell(
        formatarQuantidadeExibicao(m.quantidade),
        context,
        inativo: inativo,
      ));
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit:  _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEditar(m),
        child: ColoredBox(
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                _colWrap(cols[0], maybeOpacity(Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    '${m.id}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: inativo ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ))),
                _vDivider(context),

                _colWrap(cols[1], maybeOpacity(_cell(m.identificador ?? '—', context, inativo: inativo))),
                _vDivider(context),

                _colWrap(cols[2], maybeOpacity(Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          m.nome,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: inativo ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurface,
                            decoration: inativo ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))),
                _vDivider(context),

                if (widget.mostrarCategoria) ...[
                  _colWrap(cols[3], maybeOpacity(_cell(m.categoria ?? '—', context, inativo: inativo))),
                  _vDivider(context),
                ],

                _colWrap(cols[widget.mostrarCategoria ? 4 : 3], maybeOpacity(_cell(m.medida ?? '—', context, inativo: inativo))),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 5 : 4], maybeOpacity(_cell(m.espessura != null && m.espessura!.trim().isNotEmpty ? '${m.espessura!.trim().replaceAll(RegExp("mm\\s*\$", caseSensitive: false), '').trim()}mm' : '—', context, inativo: inativo))),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 6 : 5], maybeOpacity(_cell(m.comprimento != null ? formatarQuantidade(m.comprimento!) : '—', context, inativo: inativo))),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 7 : 6], maybeOpacity(_cell(m.largura != null ? formatarQuantidade(m.largura!) : '—', context, inativo: inativo))),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 8 : 7], estoqueAtualCell()),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 9 : 8], maybeOpacity(_cell(
                  formatarQuantidadeExibicao(m.estoqueMinimo),
                  context,
                  inativo: inativo,
                ))),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 10 : 9], maybeOpacity(_cell(formatarUnidadeExibicao(m.unidade), context, inativo: inativo))),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 11 : 10], maybeOpacity(_VerPrecoCell(
                  onTap: () => widget.onVerHistoricoPrecos(m),
                ))),
                _vDivider(context),

                _colWrap(cols[widget.mostrarCategoria ? 12 : 11], maybeOpacity(Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: _StatusBadgeEstoque(status: m.status),
                  ),
                ))),

                _colWrap(
                  cols[widget.mostrarCategoria ? 13 : 12],
                  Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkResponse(
                        mouseCursor: SystemMouseCursors.click,
                        radius: 18,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HistoricoMaterialPage(
                              materialIdInicial: m.id,
                              materialNomeInicial: m.nome,
                            ),
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.history,
                            size: 18,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildLinhaRaiz(context);
  }

  static Widget _vDivider(BuildContext context) => VerticalDivider(
    width: 1, thickness: 0.5, color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// Dialog que lista materiais cadastrados por usuários não-ADMIN aguardando
/// aprovação. Ao tocar em um item, chama [onAbrirMaterial] (que abre o
/// _MaterialFormDialog em modo aprovação). A lista é reativa: recusar ou
/// aprovar um item na tela de aprovação atualiza esta lista via
/// MaterialProvider (o mesmo provider é compartilhado com este dialog).
class _AguardandoAprovacaoDialog extends StatelessWidget {
  final Future<void> Function(MaterialModel) onAbrirMaterial;
  const _AguardandoAprovacaoDialog({required this.onAbrirMaterial});

  String _formatarData(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} às $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: SizedBox(
        width: 620,
        height: 640,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top, color: AppTheme.warning, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Aguardando Aprovação',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Materiais cadastrados por usuários que não são ADMIN. Revise, edite se '
                  'necessário e aprove para que entrem no estoque.',
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 0),
            Expanded(
              child: Consumer<MaterialProvider>(
                builder: (_, provider, __) {
                  if (provider.carregandoPendentes && provider.pendentes.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final pendentes = provider.pendentes;
                  if (pendentes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 40, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum material aguardando aprovação.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: pendentes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = pendentes[i];
                      final subtitulo = [
                        if (m.identificador != null && m.identificador!.trim().isNotEmpty)
                          m.identificador,
                        if (m.medida != null && m.medida!.trim().isNotEmpty) m.medida,
                        if (m.espessura != null && m.espessura!.trim().isNotEmpty) m.espessura,
                      ].whereType<String>().join(' • ');

                      return ListTile(
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () => onAbrirMaterial(m),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.warning.withValues(alpha: 0.15),
                          child: Icon(Icons.inventory_2_outlined, color: AppTheme.warning, size: 18),
                        ),
                        title: Text(m.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (subtitulo.isNotEmpty) subtitulo,
                            if (m.criadoPorNome != null) 'Por ${m.criadoPorNome}',
                            'Cadastrado em ${_formatarData(m.criadoEm)}',
                          ].join(' — '),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        trailing: Icon(Icons.chevron_right,
                            color: Theme.of(context).colorScheme.outline),
                      );
                    },
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

class _MaterialFormDialog extends StatefulWidget {
  final MaterialModel? material;
  final void Function(MaterialModel)? onDesativar;
  final void Function(MaterialModel)? onReativar;
  final void Function(MaterialModel)? onExcluir;
  final String? roleUsuario;

  final bool somenteLeitura;

  /// Quando true, o dialog abre em modo "aprovação de cadastro pendente":
  /// mesmo layout de edição, mas o ADMIN pode alterar qualquer campo (sem
  /// os bloqueios normais de COMPRAS) e o botão principal vira "Aprovar",
  /// chamando MaterialProvider.aprovarPendente em vez de criar/atualizar.
  /// Também expõe um botão "Recusar" para descartar o cadastro pendente.
  final bool aprovando;
  final void Function(MaterialModel)? onRecusar;

  final _MaterialFormTourKeys? tourKeys;
  const _MaterialFormDialog({this.material, this.onDesativar, this.onReativar, this.onExcluir, this.roleUsuario, this.somenteLeitura = false, this.aprovando = false, this.onRecusar, this.tourKeys});

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog;
  final ScrollController _formScrollController = ScrollController();

  RoboHelperProvider? _roboHelper;

  void _aoMudarRoboHelper() {

    if (widget.tourKeys != null &&
        !(_roboHelper?.tourAtivo ?? false) &&
        mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Timer? _debounceDuplicata;
  bool _verificandoDuplicata = false;
  List<_PossivelDuplicata> _possiveisDuplicatas = [];

  bool _modoRetalho = false;
  bool _hoverRetalho = false;

  late final TextEditingController _nome;
  late final TextEditingController _descricao;
  late final TextEditingController _identificador;
  String? _unidade;
  late final _NotifiableTextEditingController _categoria;
  final FocusNode _categoriaFocusNode = FocusNode();
  late final TextEditingController _medida;
  late final TextEditingController _espessura;
  late final TextEditingController _largura;
  late final TextEditingController _comprimento;
  late final TextEditingController _quantidade;
  late final TextEditingController _estoqueMinimo;

  bool get _editando => widget.material != null;

  /// Material genérico escolhido no cadastro (via botão "GENÉRICO"), quando
  /// o material ainda não existe e o usuário optou por cadastrá-lo como
  /// variante de um genérico já existente (ex.: TINTA). Nome e unidade
  /// desta variante herdam os do genérico; só a Descrição é editável.
  MaterialModel? _materialGenericoEscolhido;
  bool _hoverGenerico = false;

  bool get _ehVinculado =>
      widget.material?.materialGenericoId != null || _materialGenericoEscolhido != null;
  late bool _estoqueConfirmado;
  late bool _ehGenerico;
  bool _fornecedoresExpandido = false;

  bool get _bloquearQuantidade =>
      !widget.aprovando &&
      (context.watch<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      !_editando;

  bool get _bloquearQuantidadeAtual =>
      !widget.aprovando &&
      (context.read<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      !_editando;

  bool get _bloquearEstoqueMinimo => _bloquearQuantidade;

  bool get _bloquearEstoqueMinimoAtual => _bloquearQuantidadeAtual;

  bool get _bloqueadoParaCompras =>
      !widget.aprovando &&
      (context.watch<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      _editando;

  bool get _bloqueadoParaComprasAtual =>
      !widget.aprovando &&
      (context.read<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      _editando;

  static const _unidadesValidas = {
    'UNIDADE', 'M/L', 'M', 'ML', 'M²', 'G',
  };
  static const _aliasUnidade = {
    'M2': 'M²',
    'M 2': 'M²',
    'M2 ': 'M²',
  };
  static String? _normalizarUnidade(String? v) {
    if (v == null || v.isEmpty) return null;
    final norm = v.trim().toUpperCase();
    if (_unidadesValidas.contains(norm)) return norm;
    return _aliasUnidade[norm] ?? norm;
  }

  static const _palavraRetalho = 'RETALHO';

  static int _distanciaEdicao(String a, String b) {
    final la = a.length, lb = b.length;
    final d = List.generate(la + 1, (_) => List<int>.filled(lb + 1, 0));
    for (var i = 0; i <= la; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= lb; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= la; i++) {
      for (var j = 1; j <= lb; j++) {
        final custo = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + custo,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return d[la][lb];
  }

  static bool _pareceRetalho(String palavra) {
    final p = palavra.toUpperCase();
    if (p.length < 5) return false;

    final distBase   = _distanciaEdicao(p, _palavraRetalho);
    final distPlural = _distanciaEdicao(p, '${_palavraRetalho}S');
    final tolerancia = p.length <= 7 ? 2 : 3;
    return distBase <= tolerancia || distPlural <= tolerancia;
  }

  static bool _contemRetalho(String texto) {
    final palavras = texto.split(RegExp(r'[^A-Za-zÀ-ÿ]+'));
    return palavras.any((p) => p.isNotEmpty && _pareceRetalho(p));
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[MFD ${identityHashCode(this)}] initState() aprovando=${widget.aprovando} editando=${widget.material != null}');
    if (widget.tourKeys != null) {

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _roboHelper = context.read<RoboHelperProvider>();
        _roboHelper!.addListener(_aoMudarRoboHelper);
      });
    }
    final m        = widget.material;
    _estoqueConfirmado = m?.estoqueConfirmado ?? false;
    _ehGenerico    = m?.ehGenerico ?? false;
    _nome          = TextEditingController(text: m?.nome ?? '');
    _descricao     = TextEditingController(text: m?.descricao ?? '');
    _identificador = TextEditingController(text: m?.identificador ?? '');
    _unidade       = _normalizarUnidade(m?.unidade);

    _modoRetalho   = (m?.identificador?.trim().toUpperCase() == _palavraRetalho);
    _categoria     = _NotifiableTextEditingController(text: m?.categoria ?? '');

    _categoriaFocusNode.addListener(() {
      if (_categoriaFocusNode.hasFocus) {

        _categoria.notify();
      }
    });

    final medidaInicialTexto = m?.medida ?? '';
    _medida        = TextEditingController(
      text: _modoRetalho
          ? (medidaInicialTexto.trim().isEmpty
              ? _MedidaRetalhoFormatter.sufixo
              : medidaInicialTexto)
          : medidaInicialTexto,
    );
    _espessura     = TextEditingController(text: m?.espessura ?? '');
    _largura       = TextEditingController(text: m?.largura != null ? formatarQuantidade(m!.largura!) : '');
    _comprimento   = TextEditingController(text: m?.comprimento != null ? formatarQuantidade(m!.comprimento!) : '');
    _quantidade    = TextEditingController(
        text: m != null ? m.quantidade.toString() : '0');
    _estoqueMinimo = TextEditingController(
        text: m != null ? m.estoqueMinimo.toString() : '0');

    for (final c in [_nome, _identificador, _medida, _espessura, _largura, _comprimento, _descricao]) {
      c.addListener(_agendarVerificacaoDuplicata);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _agendarVerificacaoDuplicata());

    _snapshotInicial = _capturarEstadoAtual();
  }

  late String _snapshotInicial;

  String _capturarEstadoAtual() => [
        _nome.text,
        _identificador.text,
        _unidade ?? '',
        _categoria.text,
        _medida.text,
        _espessura.text,
        _largura.text,
        _comprimento.text,
        _quantidade.text,
        _estoqueMinimo.text,
        _estoqueConfirmado.toString(),
        _ehGenerico.toString(),
        _modoRetalho.toString(),
        _materialGenericoEscolhido?.id.toString() ?? '',
      ].join('␟');

  bool get _temAlteracoesNaoSalvas => _capturarEstadoAtual() != _snapshotInicial;

  /// Resultado da caixa de diálogo "Descartar alterações?": o usuário optou
  /// por descartar e fechar, salvar e então fechar, ou continuar editando
  /// (dialog permanece aberto).
  Future<String?> _confirmarFechamento() async {
    debugPrint('[MFD ${identityHashCode(this)}] _confirmarFechamento() chamado, temAlteracoes=$_temAlteracoesNaoSalvas somenteLeitura=${widget.somenteLeitura}');
    if (widget.somenteLeitura || !_temAlteracoesNaoSalvas) {
      debugPrint('[MFD ${identityHashCode(this)}] _confirmarFechamento() retorna "descartar" direto, sem abrir dialog <String>');
      return 'descartar';
    }

    // Dialog aninhado próprio (DialogRoute<String>), empilhado por cima do
    // dialog do formulário. Aqui só perguntamos a intenção do usuário e
    // retornamos essa intenção — NÃO chamamos _salvar() aqui dentro, pois
    // isso faria um Navigator.pop(context, bool) ser disparado enquanto essa
    // rota <String> ainda está sendo desempilhada, causando o erro de tipo
    // "expected String, got bool". Quem decide o que fazer com o resultado
    // é _tentarFechar, já fora do ciclo de vida deste dialog aninhado.
    debugPrint('[MFD ${identityHashCode(this)}] ABRINDO showDialog<String> ("Descartar alterações?")');
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Você fez alterações neste material que ainda não foram salvas. '
          'O que deseja fazer?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('[MFD ${identityHashCode(this)}] botão "continuar" clicado');
              Navigator.pop(context, 'continuar');
            },
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: Text(widget.aprovando
                ? 'Continuar revisando'
                : (_editando ? 'Continuar editando' : 'Continuar cadastrando')),
          ),
          TextButton(
            onPressed: () {
              debugPrint('[MFD ${identityHashCode(this)}] botão "descartar" clicado');
              Navigator.pop(context, 'descartar');
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () {
              debugPrint('[MFD ${identityHashCode(this)}] botão "salvar" clicado');
              Navigator.pop(context, 'salvar');
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: Text(widget.aprovando ? 'Aprovar' : (_editando ? 'Salvar alterações' : 'Cadastrar')),
          ),
        ],
      ),
    );
    debugPrint('[MFD ${identityHashCode(this)}] showDialog<String> RETORNOU resultado=$resultado mounted=$mounted');

    if (!mounted) return null;
    return resultado;
  }

  Future<void> _tentarFechar() async {
    debugPrint('[MFD ${identityHashCode(this)}] _tentarFechar() chamado salvando=$_salvando');
    if (_salvando) return;
    final resultado = await _confirmarFechamento();
    debugPrint('[MFD ${identityHashCode(this)}] _tentarFechar() apos _confirmarFechamento resultado=$resultado mounted=$mounted');
    if (!mounted || resultado == null) return;

    // IMPORTANTE: o `await showDialog<String>` dentro de _confirmarFechamento
    // resolve a Future assim que o Navigator.pop() da rota <String> é
    // CHAMADO — mas a remoção efetiva dessa rota da pilha (e o unlock do
    // Navigator) só termina no fim do frame de build seguinte. Se
    // continuarmos síncronamente e chamarmos outro Navigator.pop/push aqui
    // (por ex. _salvar() fechando o dialog do formulário), esse segundo pop
    // pode ser processado enquanto o Navigator ainda está com
    // `_debugLocked` = true ou enquanto a rota <String> ainda não foi
    // totalmente destruída, causando os erros:
    //   - "expected String, got bool"
    //   - "You have popped the last page off of the stack"
    //   - "!_debugLocked is not true"
    // Esperar um frame completo garante que o Navigator já processou e
    // finalizou a remoção da rota anterior antes de prosseguirmos.
    await SchedulerBinding.instance.endOfFrame;
    debugPrint('[MFD ${identityHashCode(this)}] _tentarFechar() apos endOfFrame mounted=$mounted, vai executar case=$resultado');
    if (!mounted) return;

    switch (resultado) {
      case 'descartar':
        debugPrint('[MFD ${identityHashCode(this)}] _tentarFechar() -> Navigator.of(context).pop() (descartar)');
        Navigator.of(context).pop();
        break;
      case 'salvar':
        debugPrint('[MFD ${identityHashCode(this)}] _tentarFechar() -> chamando _salvar()');
        await _salvar();
        break;
      case 'continuar':
      default:
        break;
    }
  }

  @override
  void dispose() {
    debugPrint('[MFD ${identityHashCode(this)}] dispose() salvando=$_salvando');
    _roboHelper?.removeListener(_aoMudarRoboHelper);
    _debounceDuplicata?.cancel();
    for (final c in [
      _nome, _descricao, _identificador, _categoria, _medida, _espessura,
      _largura, _comprimento, _quantidade, _estoqueMinimo,
    ]) {
      c.dispose();
    }
    _categoriaFocusNode.dispose();
    _formScrollController.dispose();
    super.dispose();
  }

  void _agendarVerificacaoDuplicata() {
    _debounceDuplicata?.cancel();
    _debounceDuplicata = Timer(const Duration(milliseconds: 450), _verificarDuplicatas);
  }

  Future<void> _verificarDuplicatas() async {
    if (!mounted) return;
    final nomeNorm = _normalizarTextoComparacao(_nome.text);

    if (nomeNorm.length < 3) {
      if (_possiveisDuplicatas.isNotEmpty || _verificandoDuplicata) {
        setState(() {
          _possiveisDuplicatas = [];
          _verificandoDuplicata = false;
        });
      }
      return;
    }

    setState(() => _verificandoDuplicata = true);

    final provider = context.read<MaterialProvider>();

    final tokensUnicos = _nome.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final termosBusca = tokensUnicos.where((t) => t.length >= 2).take(5).toList();
    if (termosBusca.isEmpty && _nome.text.trim().isNotEmpty) {
      termosBusca.add(_nome.text.trim());
    }

    final resultadosPorToken = await Future.wait(
      termosBusca.map((t) => provider.buscarSugestoes(t, limite: 30, incluirVinculados: _ehVinculado)),
    );
    if (!mounted) return;

    final candidatosMap = <int, MaterialModel>{};
    for (final lista in resultadosPorToken) {
      for (final m in lista) {
        candidatosMap[m.id] = m;
      }
    }
    final candidatos = candidatosMap.values.toList();

    final identificadorNorm = _normalizarTextoComparacao(_identificador.text);
    final medidaNorm        = _normalizarTextoComparacao(_medida.text);
    final espessuraNorm     = _normalizarTextoComparacao(_espessura.text);

    final medidaDigitadaExtraida = _extrairDimensoesMedida(_medida.text);
    final comprimentoDigitado = double.tryParse(_comprimento.text.trim().replaceAll(',', '.'))
        ?? medidaDigitadaExtraida.comprimento;
    final larguraDigitada = double.tryParse(_largura.text.trim().replaceAll(',', '.'))
        ?? medidaDigitadaExtraida.largura;
    final espessuraDigitadaNum = _extrairNumeroDeTexto(_espessura.text)
        ?? medidaDigitadaExtraida.espessura;

    bool dimensaoBate(double? a, double? b) {
      if (a == null || b == null) return false;
      return (a - b).abs() < 0.001;
    }

    final encontrados = <_PossivelDuplicata>[];
    for (final m in candidatos) {

      if (_editando && m.id == widget.material!.id) continue;

      // Materiais vinculados a um genérico (ex.: "TINTA" + descrição
      // "AZUL CLARO") se diferenciam pela descrição, não pelo nome —
      // que é sempre igual ao do pai. Comparar por nome aqui faria o
      // próprio material genérico (ou qualquer outra variante) aparecer
      // como "idêntico" só por compartilhar o nome. Nesse modo a
      // checagem de duplicidade é: mesma descrição, dentro do mesmo
      // genérico.
      if (_ehVinculado) {
        final genericoId = _materialGenericoEscolhido?.id ?? widget.material?.materialGenericoId;
        if (m.materialGenericoId == null || m.materialGenericoId != genericoId) continue;

        final mDescricaoNorm = _normalizarTextoComparacao(m.descricao);
        final descricaoNorm  = _normalizarTextoComparacao(_descricao.text);
        if (descricaoNorm.isEmpty) continue;

        final exataDesc = mDescricaoNorm == descricaoNorm;
        final similarDesc = !exataDesc &&
            _similaridadeTexto(descricaoNorm, mDescricaoNorm) >= 0.72;

        if (exataDesc || similarDesc) {
          encontrados.add(_PossivelDuplicata(
            material: m,
            exata: exataDesc,
            similaridade: _similaridadeTexto(descricaoNorm, mDescricaoNorm),
            contido: false,
          ));
        }
        continue;
      }

      final mNomeNorm          = _normalizarTextoComparacao(m.nome);
      final mIdentificadorNorm = _normalizarTextoComparacao(m.identificador);
      final mMedidaNorm        = _normalizarTextoComparacao(m.medida);
      final mEspessuraNorm     = _normalizarTextoComparacao(m.espessura);

      final mMedidaExtraida = _extrairDimensoesMedida(m.medida);
      final mComprimentoFinal = m.comprimento ?? mMedidaExtraida.comprimento;
      final mLarguraFinal     = m.largura ?? mMedidaExtraida.largura;
      final mEspessuraFinal   = _extrairNumeroDeTexto(m.espessura) ?? mMedidaExtraida.espessura;

      final dimensoesBatem = dimensaoBate(comprimentoDigitado, mComprimentoFinal) &&
          dimensaoBate(larguraDigitada, mLarguraFinal);
      final medidaOuDimensaoBate = mMedidaNorm == medidaNorm || dimensoesBatem;

      final espessuraBate = (espessuraNorm.isEmpty && mEspessuraNorm.isEmpty)
          ? true
          : (espessuraDigitadaNum != null && mEspessuraFinal != null)
              ? dimensaoBate(espessuraDigitadaNum, mEspessuraFinal)
              : mEspessuraNorm == espessuraNorm;

      final exata = mNomeNorm == nomeNorm &&
          mIdentificadorNorm == identificadorNorm &&
          medidaOuDimensaoBate &&
          espessuraBate;

      final similaridadeNome = _similaridadeTexto(nomeNorm, mNomeNorm);

      final similaridadePalavras = _similaridadePalavras(nomeNorm, mNomeNorm);
      final similaridadeEfetiva =
          similaridadeNome > similaridadePalavras ? similaridadeNome : similaridadePalavras;
      final mesmoIdentificador =
          identificadorNorm.isNotEmpty && identificadorNorm == mIdentificadorNorm;

      final curto = nomeNorm.length <= mNomeNorm.length ? nomeNorm : mNomeNorm;
      final longo = nomeNorm.length <= mNomeNorm.length ? mNomeNorm : nomeNorm;
      final contido = curto.length >= 4 && curto.isNotEmpty && longo.contains(curto);

      final palavrasDigitadas = nomeNorm.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
      final palavrasCadastro  = mNomeNorm.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
      final palavrasComuns = palavrasDigitadas.intersection(palavrasCadastro).length;

      final menorQtdPalavras =
          palavrasDigitadas.length < palavrasCadastro.length ? palavrasDigitadas.length : palavrasCadastro.length;
      final cobreParcialPalavras = palavrasComuns >= 2 &&
          menorQtdPalavras > 0 &&
          (palavrasComuns / menorQtdPalavras) >= 0.6;

      final similar = !exata &&
          (similaridadeNome >= 0.72 ||
              similaridadePalavras >= 0.72 ||
              (mesmoIdentificador && similaridadeNome >= 0.4) ||
              contido ||
              cobreParcialPalavras);

      if (exata || similar) {
        encontrados.add(_PossivelDuplicata(
          material: m,
          exata: exata,
          similaridade: similaridadeEfetiva,
          contido: contido,
        ));
      }
    }

    encontrados.sort((a, b) {
      if (a.exata != b.exata) return a.exata ? -1 : 1;
      if (a.contido != b.contido) return a.contido ? -1 : 1;
      return b.similaridade.compareTo(a.similaridade);
    });

    if (!mounted) return;
    setState(() {
      _possiveisDuplicatas = encontrados.take(5).toList();
      _verificandoDuplicata = false;
    });
  }

  bool _medidaRetalhoEstaVazia() {
    final texto = _medida.text.trim();
    if (!_modoRetalho) return texto.isEmpty;
    return texto == _MedidaRetalhoFormatter.sufixo || texto.isEmpty;
  }

  void _ativarModoRetalho() {
    setState(() {
      _modoRetalho = true;
      _identificador.text = 'RETALHO';
      _unidade = 'M²';
      _medida.text = _MedidaRetalhoFormatter.sufixo;
      _medida.selection = const TextSelection.collapsed(offset: 0);
      _largura.clear();
      _comprimento.clear();
      _estoqueMinimo.text = '0';
      // Genérico e retalho são conceitos mutuamente exclusivos.
      if (_materialGenericoEscolhido != null) {
        _materialGenericoEscolhido = null;
        _nome.clear();
        _descricao.clear();
      }
    });
  }

  void _desativarModoRetalho() {
    setState(() {
      _modoRetalho = false;
      _identificador.clear();
      _unidade = null;
      _medida.clear();
    });
  }

  /// Abre o dialog de seleção de material genérico (ex.: TINTA) e, se o
  /// usuário escolher um, prepara o formulário para cadastrar uma nova
  /// variante vinculada a ele: nome e unidade passam a ser herdados do
  /// genérico (bloqueados), restando ao usuário preencher a Descrição.
  Future<void> _abrirSeletorGenerico() async {
    final escolhido = await showSelecionarMaterialGenericoDialog(context);
    if (!mounted || escolhido == null) return;
    setState(() {
      _materialGenericoEscolhido = escolhido;
      _nome.text = escolhido.nome;
      _unidade   = _normalizarUnidade(escolhido.unidade);
      _descricao.clear();
      // Genérico e retalho são conceitos mutuamente exclusivos.
      if (_modoRetalho) {
        _modoRetalho = false;
        _identificador.clear();
        _medida.clear();
      }
    });
  }

  void _desvincularGenerico() {
    setState(() {
      _materialGenericoEscolhido = null;
      _nome.clear();
      _descricao.clear();
      _unidade = null;
    });
  }

  Future<void> _salvar() async {
    debugPrint('[MFD ${identityHashCode(this)}] _salvar() INICIO mounted=$mounted');
    if (widget.somenteLeitura) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_modoRetalho && (_unidade == null || _unidade!.isEmpty)) {
      setState(() => _erroDialog = 'Selecione uma unidade antes de salvar.');
      _rolarParaTopoDoFormulario();
      return;
    }

    _debounceDuplicata?.cancel();
    await _verificarDuplicatas();
    if (!mounted) return;
    if (_possiveisDuplicatas.any((d) => d.exata)) {
      setState(() {
        _erroDialog = 'Já existe um material idêntico cadastrado. '
            'Ajuste a medida/espessura ou edite o material existente.';
      });
      _rolarParaTopoDoFormulario();
      return;
    }
    setState(() { _salvando = true; _erroDialog = null; });

    final material = widget.material;
    final bloqueado = _bloqueadoParaComprasAtual && material != null;

    final dados = {
      'nome':          bloqueado ? material.nome : _nome.text.trim(),
      'descricao':     !_ehVinculado
          ? material?.descricao
          : (bloqueado ? material.descricao : (_descricao.text.trim().isEmpty ? null : _descricao.text.trim())),
      'identificador': bloqueado ? material.identificador  : (_identificador.text.trim().isEmpty ? null : _identificador.text.trim()),
      'unidade':       bloqueado ? material.unidade         : ((_unidade == null || _unidade!.isEmpty) ? null : _unidade),
      'categoria':     _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
      'medida':        bloqueado ? material.medida          : (_medidaRetalhoEstaVazia() ? null : _medida.text.trim()),
      'espessura':     bloqueado ? material.espessura       : (_espessura.text.trim().isEmpty ? null : _espessura.text.trim()),
      'largura':       bloqueado ? material.largura         : (_modoRetalho ? null : (_largura.text.trim().isEmpty ? null : double.tryParse(_largura.text.trim()))),
      'comprimento':   bloqueado ? material.comprimento     : (_modoRetalho ? null : (_comprimento.text.trim().isEmpty ? null : double.tryParse(_comprimento.text.trim()))),
      'quantidade':    bloqueado ? material.quantidade      : (_bloquearQuantidadeAtual ? 0 : (double.tryParse(_quantidade.text) ?? 0)),
      'estoqueMinimo': bloqueado ? material.estoqueMinimo   : ((_modoRetalho || _bloquearEstoqueMinimoAtual) ? 0.0 : (double.tryParse(_estoqueMinimo.text) ?? 0)),
      'estoqueConfirmado': _estoqueConfirmado,
      'ehGenerico':        _ehGenerico,
      if (!_editando && _materialGenericoEscolhido != null)
        'materialGenericoId': _materialGenericoEscolhido!.id,
    };

    debugPrint('[MFD ${identityHashCode(this)}] _salvar() antes de chamar provider (aprovando=${widget.aprovando} editando=$_editando)');
    final provider = context.read<MaterialProvider>();
    final bool ok;
    if (widget.aprovando) {
      ok = await provider.aprovarPendente(widget.material!.id, dados);
    } else if (_editando) {
      ok = await provider.atualizar(widget.material!.id, dados);
    } else {
      ok = await provider.criar(dados);
    }
    debugPrint('[MFD ${identityHashCode(this)}] _salvar() provider retornou ok=$ok mounted=$mounted');

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      final aguardaAprovacao = !_editando &&
          !widget.aprovando &&
          provider.ultimoMaterialCriadoAguardaAprovacao;

      final mensagem = widget.aprovando
          ? 'Material aprovado e adicionado ao estoque.'
          : (_editando
              ? 'Material atualizado.'
              : (aguardaAprovacao
                  ? 'Material enviado para aprovação.'
                  : 'Material cadastrado.'));

      // Captura o ScaffoldMessenger da tela por trás do dialog ANTES de
      // fechar. Usar `context` do dialog depois do pop aponta para uma
      // rota já removida da pilha, o que faz o GoRouter (delegate) tentar
      // resolver uma pop page inexistente e derrubar o app com
      // "currentConfiguration.isNotEmpty" / "_debugLocked".
      final messenger = ScaffoldMessenger.of(context);

      debugPrint('[MFD ${identityHashCode(this)}] _salvar() -> ANTES Navigator.of(context).pop(true). '
          'context.mounted=${context.mounted} '
          'ModalRoute.of(context)=${ModalRoute.of(context)?.settings} '
          'canPop=${Navigator.of(context).canPop()}');

      Navigator.of(context).pop(true);

      debugPrint('[MFD ${identityHashCode(this)}] _salvar() -> DEPOIS Navigator.of(context).pop(true) (sem exception ate aqui)');

      messenger.showSnackBar(SnackBar(
        content: Text(mensagem),
        backgroundColor: AppTheme.success,
      ));
      debugPrint('[MFD ${identityHashCode(this)}] _salvar() -> snackbar enfileirado, FIM');
    } else {
      setState(() => _erroDialog = provider.erro ?? 'Erro ao salvar.');
      _rolarParaTopoDoFormulario();
    }
  }

  void _rolarParaTopoDoFormulario() {
    if (!_formScrollController.hasClients) return;
    _formScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _recusar() async {
    if (widget.material == null || widget.onRecusar == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recusar cadastro?'),
        content: Text(
          'O material "${widget.material!.nome}" será excluído e não entrará no estoque. '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    Navigator.of(context).pop(false);
    widget.onRecusar!(widget.material!);
  }

  @override
  Widget build(BuildContext context) {
    final material      = widget.material;
    final fornecedores  = material?.fornecedorMateriais ?? <FornecedorMaterialModel>[];
    final temFornecedor = _editando && fornecedores.isNotEmpty;

    Widget formPanel = Form(
      key: _formKey,
      child: SingleChildScrollView(
        controller: _formScrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_erroDialog != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _erroDialog!,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _erroDialog = null),
                      child: const Icon(Icons.close, color: AppTheme.error, size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            KeyedSubtree(
              key: widget.tourKeys?.nome,
              child: TextFormField(
              controller: _nome,
              autofocus: !_editando && widget.tourKeys == null,
              readOnly: _bloqueadoParaCompras || _ehVinculado,
              decoration: InputDecoration(
                labelText: 'Nome',
                suffixIcon: _ehVinculado
                    ? Tooltip(
                        message: 'Nome herdado do material genérico — edite a Descrição para diferenciar esta variante',
                        child: _materialGenericoEscolhido != null
                            ? MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: _desvincularGenerico,
                                  child: const Icon(Icons.close, size: 16),
                                ),
                              )
                            : const Icon(Icons.lock_outline, size: 16),
                      )
                    : null,
              ),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseFormatter()],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Nome é obrigatório';
                if (_contemRetalho(v)) {
                  return 'Não digite "RETALHO" no nome — digite no campo Identificador';
                }
                return null;
              },
              ),
            ),
            if (_ehVinculado) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _descricao,
                autofocus: _materialGenericoEscolhido != null,
                readOnly: _bloqueadoParaCompras,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  helperText: _materialGenericoEscolhido != null
                      ? 'Ex.: "AZUL CLARO" — vai compor o nome junto com "${_materialGenericoEscolhido!.nome}"'
                      : null,
                ),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseFormatter()],
                minLines: 1,
                maxLines: 3,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) {
                  if (_materialGenericoEscolhido != null && (v == null || v.trim().isEmpty)) {
                    return 'Informe uma descrição para diferenciar esta variante';
                  }
                  return null;
                },
              ),
            ],
            if (!_ehVinculado) ...[
            const SizedBox(height: 10),
            KeyedSubtree(
              key: widget.tourKeys?.identificador,
              child: TextFormField(
              controller: _identificador,
              readOnly: _modoRetalho || _bloqueadoParaCompras,
              onChanged: (v) {

                if (!_modoRetalho && _contemRetalho(v)) {
                  _ativarModoRetalho();
                }
              },
              decoration: InputDecoration(
                labelText: 'Identificador',
                suffixIcon: _modoRetalho
                    ? const Tooltip(
                        message: 'Bloqueado no modo Retalho',
                        child: Icon(Icons.lock_outline, size: 16),
                      )
                    : null,
              ),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseFormatter()],
              ),
            ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              if (!_ehVinculado) ...[
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeys?.categoria,
                  child: widget.somenteLeitura
                    ? TextFormField(
                        controller: _categoria,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'Categoria'),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return RawAutocomplete<String>(
                            textEditingController: _categoria,
                            focusNode: _categoriaFocusNode,
                            optionsBuilder: (TextEditingValue value) {
                              final query = value.text.trim().toUpperCase();
                              final categorias =
                                  context.read<MaterialProvider>().categorias;
                              if (query.isEmpty) return categorias;
                              return categorias.where((c) {
                                final upper = c.toUpperCase();
                                return upper.contains(query) && upper != query;
                              });
                            },
                            onSelected: (String selection) {
                              _categoria.text = selection;
                              _categoria.selection =
                                  TextSelection.collapsed(offset: selection.length);
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              return TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(labelText: 'Categoria'),
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [_UpperCaseFormatter()],
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: constraints.maxWidth,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxHeight: 200),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (context, index) {
                                          final opcao = options.elementAt(index);
                                          return MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: InkWell(
                                              onTap: () => onSelected(opcao),
                                              hoverColor: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.08),
                                              child: Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                color: Colors.transparent,
                                                child: Text(opcao),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              ),
              const SizedBox(width: 12),
              ],
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeys?.unidade,
                  child: _modoRetalho
                    ? InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Unidade',
                          suffixIcon: const Tooltip(
                            message: 'Bloqueado no modo Retalho',
                            child: Icon(Icons.lock_outline, size: 16),
                          ),
                        ),
                        child: const Text('m²', style: TextStyle(fontSize: 14)),
                      )
                    : _ehVinculado
                    ? InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Unidade',
                          suffixIcon: Tooltip(
                            message: 'Unidade herdada do material genérico',
                            child: Icon(Icons.lock_outline, size: 16),
                          ),
                        ),
                        child: Text(
                          formatarUnidadeExibicao(_unidade),
                          style: const TextStyle(fontSize: 14),
                        ),
                      )
                    : MouseRegion(
                        cursor: _bloqueadoParaCompras ? SystemMouseCursors.basic : SystemMouseCursors.click,
                        child: DropdownButtonFormField<String>(
                          initialValue: _unidade,
                          decoration: const InputDecoration(labelText: 'Unidade'),
                          hint: const Text('Selecione'),
                          icon: const Icon(Icons.arrow_drop_down),
                          mouseCursor: _bloqueadoParaCompras ? SystemMouseCursors.basic : SystemMouseCursors.click,
                          items: const [
                            DropdownMenuItem(
                              value: 'UNIDADE',
                              child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('Unidade')),
                            ),
                            DropdownMenuItem(
                              value: 'M/L',
                              child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('m/l — (metro linear)')),
                            ),
                            DropdownMenuItem(
                              value: 'M',
                              child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('m — (metro)')),
                            ),
                            DropdownMenuItem(
                              value: 'ML',
                              child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('ml — (mililitro)')),
                            ),
                            DropdownMenuItem(
                              value: 'M²',
                              child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('m² — (metro quadrado)')),
                            ),
                            DropdownMenuItem(
                              value: 'G',
                              child: MouseRegion(cursor: SystemMouseCursors.click, child: Text('g — (grama)')),
                            ),
                          ],
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Selecione uma unidade' : null,
                          onChanged: _bloqueadoParaCompras ? null : (v) => setState(() => _unidade = v),
                        ),
                      ),
              ),
              ),
            ]),
            const SizedBox(height: 10),
            if (_unidade != 'ML' && _unidade != 'G') ...[
            KeyedSubtree(
              key: widget.tourKeys?.medida,
              child: TextFormField(
                controller: _medida,
                readOnly: _bloqueadoParaCompras,
                decoration: InputDecoration(
                  labelText: 'Medida',
                  hintText: _modoRetalho ? 'Ex.: 1.63' : null,
                  suffixIcon: _modoRetalho
                      ? const Tooltip(
                          message: 'No modo Retalho, informe apenas o valor em m²',
                          child: Icon(Icons.straighten, size: 16),
                        )
                      : null,
                ),
                textCapitalization: TextCapitalization.none,
                keyboardType: _modoRetalho
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                inputFormatters: [
                  _modoRetalho ? _MedidaRetalhoFormatter() : _MedidaEspessuraFormatter(),
                ],
                onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
              ),
            ),
            ],
            if (_unidade != 'ML' && _unidade != 'G') ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeys?.comprimento,
                  child: TextFormField(
                  controller: _comprimento,
                  readOnly: _modoRetalho || _bloqueadoParaCompras,
                  decoration: InputDecoration(
                    labelText: 'Comprimento',
                    suffixText: 'm',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    suffixIcon: _modoRetalho
                        ? const Tooltip(
                            message: 'Bloqueado no modo Retalho',
                            child: Icon(Icons.lock_outline, size: 16),
                          )
                        : null,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeys?.largura,
                  child: TextFormField(
                  controller: _largura,
                  readOnly: _modoRetalho || _bloqueadoParaCompras,
                  decoration: InputDecoration(
                    labelText: 'Largura',
                    suffixText: 'm',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    suffixIcon: _modoRetalho
                        ? const Tooltip(
                            message: 'Bloqueado no modo Retalho',
                            child: Icon(Icons.lock_outline, size: 16),
                          )
                        : null,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeys?.espessura,
                  child: TextFormField(
                  controller: _espessura,
                  readOnly: _bloqueadoParaCompras,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Espessura',
                    suffixText: 'mm',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [_EspessuraFormatter()],
                  onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                  ),
                ),
              ),
            ]),
            ],
            const SizedBox(height: 10),
            if (!_ehVinculado) ...[
            Row(children: [
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeys?.quantidade,
                  child: _bloquearQuantidade
                    ? _QuantidadeBloqueadaInfo()
                    : TextFormField(
                  controller: _quantidade,
                  readOnly: _bloqueadoParaCompras,
                  decoration: const InputDecoration(labelText: 'Quantidade'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty || double.tryParse(v) == null)
                          ? 'Número inválido'
                          : null,
                ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KeyedSubtree(
                  key: widget.tourKeys?.estoqueMinimo,
                  child: _bloquearEstoqueMinimo
                    ? _EstoqueMinimoBloqueadoInfo()
                    : TextFormField(
                  controller: _estoqueMinimo,
                  readOnly: _modoRetalho || _bloqueadoParaCompras,
                  decoration: InputDecoration(
                    labelText: 'Estoque mínimo',
                    suffixIcon: _modoRetalho
                        ? const Tooltip(
                            message: 'Bloqueado no modo Retalho',
                            child: Icon(Icons.lock_outline, size: 16),
                          )
                        : null,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty || double.tryParse(v) == null)
                          ? 'Número inválido'
                          : null,
                ),
                ),
              ),
            ]),
            SizedBox(height: 10),
            const SizedBox(height: 10),
            KeyedSubtree(
              key: widget.tourKeys?.estoqueConfirmado,
              child: InkWell(
              borderRadius: BorderRadius.circular(8),
              mouseCursor: widget.somenteLeitura ? SystemMouseCursors.basic : SystemMouseCursors.click,
              onTap: widget.somenteLeitura ? null : () => setState(() => _estoqueConfirmado = !_estoqueConfirmado),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      _estoqueConfirmado
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _estoqueConfirmado ? AppTheme.success : Theme.of(context).colorScheme.outline,
                    ),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estoque confirmado',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _estoqueConfirmado
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _estoqueConfirmado
                              ? 'A quantidade atual foi verificada fisicamente'
                              : 'Quantidade ainda não verificada fisicamente',
                          style: TextStyle(
                              fontSize: 11, color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ),
            ],
            if (widget.material?.materialGenericoId == null && _materialGenericoEscolhido == null) ...[
              const SizedBox(height: 4),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                mouseCursor: widget.somenteLeitura ? SystemMouseCursors.basic : SystemMouseCursors.click,
                onTap: widget.somenteLeitura ? null : () => setState(() => _ehGenerico = !_ehGenerico),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        _ehGenerico
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: _ehGenerico ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                      ),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Material genérico',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _ehGenerico
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            _ehGenerico
                                ? 'Este material servirá como genérico para outros materiais (ex.: TINTA + descrição)'
                                : 'Marque para usar como agrupador(ex.: TINTAS)',
                            style: TextStyle(
                                fontSize: 11, color: Theme.of(context).colorScheme.outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

          ],
        ),
      ),
    );

    String formatarMoeda(double valor) {
      final partes = valor.toStringAsFixed(2).split('.');
      final inteiro = partes[0];
      final decimal = partes[1];
      final buffer = StringBuffer();
      for (int i = 0; i < inteiro.length; i++) {
        final posicaoDaDireita = inteiro.length - i;
        buffer.write(inteiro[i]);
        if (posicaoDaDireita > 1 && posicaoDaDireita % 3 == 1) {
          buffer.write('.');
        }
      }
      return 'R\$ ${buffer.toString()},$decimal';
    }

    final Widget avisoPanel = Container(
      width: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft:    Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(
              children: [
                Icon(Icons.search_outlined, size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Materiais semelhantes',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: _AvisoPossivelDuplicata(
                carregando: _verificandoDuplicata,
                duplicatas: _possiveisDuplicatas,
              ),
            ),
          ),
        ],
      ),
    );

    Widget? fornecedorPanel;
    if (temFornecedor) {
      final ordenados = [...fornecedores]
        ..sort((a, b) => a.preco.compareTo(b.preco));

      double media(Iterable<double> valores) {
        final validos = valores.where((v) => v > 0).toList();
        if (validos.isEmpty) return 0;
        return validos.reduce((a, b) => a + b) / validos.length;
      }

      final mediaPreco        = media(fornecedores.map((fm) => fm.preco));
      final mediaPrecoM2      = media(fornecedores.map((fm) => fm.precoMetroQuadrado));
      final mediaPrecoUnidade = media(fornecedores.map((fm) => fm.precoUnidadeMedida));

      final fmMediaPreco        = mediaPreco > 0 ? formatarMoeda(mediaPreco) : '—';
      final fmMediaPrecoM2      = mediaPrecoM2 > 0 ? formatarMoeda(mediaPrecoM2) : '—';
      final fmMediaPrecoUnidade = mediaPrecoUnidade > 0 ? formatarMoeda(mediaPrecoUnidade) : '—';

      fornecedorPanel = Container(
        width: _fornecedoresExpandido ? 380 : 220,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.only(
            topRight:    Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border(
            left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
              onTap: () => setState(() => _fornecedoresExpandido = !_fornecedoresExpandido),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: _fornecedoresExpandido ? Radius.zero : Radius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 12, 16),
                child: Row(
                  children: [
                    Icon(Icons.store_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Fornecedores (${fornecedores.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _fornecedoresExpandido ? Icons.chevron_left : Icons.chevron_right,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              ),
            ),
            if (_fornecedoresExpandido) ...[
            Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fornecedor',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      'Preço Unidade',
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      'Preço m²',
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  if (deveExibirPrecoUnidade(material?.unidade))
                    SizedBox(
                      width: 84,
                      child: Text('Preço ${formatarUnidadeExibicao(material!.unidade)}',
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: Theme.of(context).colorScheme.outlineVariant),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(ordenados.length, (i) {
                    final fm = ordenados[i];
                    final isMediano = material!.precoMediano != null &&
                        fm.preco == material.precoMediano;

                    final fmPreco   = fm.preco > 0 ? formatarMoeda(fm.preco) : '—';
                    final fmPrecoM2 = fm.precoMetroQuadrado > 0 ? formatarMoeda(fm.precoMetroQuadrado) : '—';
                    final fmPrecoUnidade = fm.precoUnidadeMedida > 0 ? formatarMoeda(fm.precoUnidadeMedida) : '—';
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fm.fornecedorNome,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isMediano ? FontWeight.w700 : FontWeight.w400,
                                    color: isMediano
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 84,
                                child: Text(fmPreco, textAlign: TextAlign.right,
                                    maxLines: 1, softWrap: false, overflow: TextOverflow.visible,
                                    style: const TextStyle(fontSize: 11)),
                              ),
                              SizedBox(
                                width: 84,
                                child: Text(fmPrecoM2, textAlign: TextAlign.right,
                                    maxLines: 1, softWrap: false, overflow: TextOverflow.visible,
                                    style: const TextStyle(fontSize: 11)),
                              ),
                              if (deveExibirPrecoUnidade(material.unidade))
                                SizedBox(
                                  width: 84,
                                  child: Text(fmPrecoUnidade, textAlign: TextAlign.right,
                                      maxLines: 1, softWrap: false, overflow: TextOverflow.visible,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                            ],
                          ),
                        ),
                        if (i < ordenados.length - 1)
                          Divider(height: 0, thickness: 0.5,
                              color: Theme.of(context).colorScheme.outlineVariant),
                      ],
                    );
                  }),
                ),
              ),
            ),

            Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Preço médio',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(fmMediaPreco, textAlign: TextAlign.right,
                        maxLines: 1, softWrap: false, overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(fmMediaPrecoM2, textAlign: TextAlign.right,
                        maxLines: 1, softWrap: false, overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                  ),
                  if (deveExibirPrecoUnidade(material!.unidade))
                    SizedBox(
                      width: 84,
                      child: Text(fmMediaPrecoUnidade, textAlign: TextAlign.right,
                          maxLines: 1, softWrap: false, overflow: TextOverflow.visible,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                    ),
                ],
              ),
            ),

            SizedBox(height: 8),
            ],
          ],
        ),
      );
    }

    return PopScope(

      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        debugPrint('[MFD ${identityHashCode(this)}] PopScope.onPopInvokedWithResult didPop=$didPop result=$result salvando=$_salvando');
        if (didPop) return;

        // CRÍTICO: se _salvar() já está em andamento (usuário clicou em
        // Cadastrar/Salvar alterações), NÃO abrir o dialog de confirmação
        // de descarte aqui. Sem essa guarda, o PopScope roda em paralelo
        // com _salvar() (o próprio clique no botão de salvar aciona esse
        // callback de pop), abre o showDialog<String> ("Descartar
        // alterações?") por cima, e quando _salvar() tenta fechar o dialog
        // do formulário momentos depois, a rota no topo da pilha já é a
        // <String> — causando "expected String, got bool" e o dialog
        // nunca fechar de fato.
        if (_salvando) {
          debugPrint('[MFD ${identityHashCode(this)}] PopScope -> ignorado, _salvando=true');
          return;
        }

        final roboHelper =
            context.mounted ? context.read<RoboHelperProvider>() : null;
        final tourNavegandoParaFora = widget.tourKeys != null &&
            roboHelper != null &&
            roboHelper.tourAtivo &&
            roboHelper.paradaAtual != null &&
            !widget.tourKeys!.contemParada(roboHelper.paradaAtual!.key);
        if (tourNavegandoParaFora) {
          debugPrint('[MFD ${identityHashCode(this)}] PopScope -> tourNavegandoParaFora, pop()');
          Navigator.of(context).pop();
          return;
        }
        if (widget.tourKeys != null &&
            context.mounted &&
            roboHelper != null &&
            roboHelper.tourAtivo) {
          roboHelper.encerrarTour();
          debugPrint('[MFD ${identityHashCode(this)}] PopScope -> tourAtivo encerrado, pop()');
          Navigator.of(context).pop();
          return;
        }
        debugPrint('[MFD ${identityHashCode(this)}] PopScope -> chamando _confirmarFechamento()');
        final resultado = await _confirmarFechamento();
        debugPrint('[MFD ${identityHashCode(this)}] PopScope -> _confirmarFechamento retornou $resultado context.mounted=${context.mounted}');
        if (!context.mounted || resultado == null) return;

        // Ver comentário em _tentarFechar: espera o Navigator terminar de
        // processar a remoção da rota <String> do dialog de confirmação
        // antes de disparar outro pop/ação neste mesmo Navigator.
        await SchedulerBinding.instance.endOfFrame;
        debugPrint('[MFD ${identityHashCode(this)}] PopScope -> apos endOfFrame context.mounted=${context.mounted}, executando case=$resultado');
        if (!context.mounted) return;

        switch (resultado) {
          case 'descartar':
            debugPrint('[MFD ${identityHashCode(this)}] PopScope -> case descartar, pop()');
            Navigator.of(context).pop();
            break;
          case 'salvar':
            debugPrint('[MFD ${identityHashCode(this)}] PopScope -> case salvar, chamando _salvar()');
            await _salvar();
            break;
          case 'continuar':
          default:
            break;
        }
      },
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: SizedBox(
        width: 560 + (temFornecedor ? 400 : 0) + 260,
        height: 680,
        child: Column(
          children: [

            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    widget.aprovando
                        ? 'Aprovar Cadastro'
                        : (widget.somenteLeitura
                            ? 'Visualizar Material'
                            : (_editando ? 'Editar Material' : 'Novo Material')),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (widget.aprovando) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.warning, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top, size: 13, color: AppTheme.warning),
                          const SizedBox(width: 5),
                          Text(
                            'AGUARDANDO APROVAÇÃO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppTheme.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!_editando) ...[
                    const SizedBox(width: 12),

                    Tooltip(
                      message: _modoRetalho
                          ? 'Desmarcar como retalho'
                          : 'Marcar como retalho (sobra de material)',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _hoverRetalho = true),
                        onExit:  (_) => setState(() => _hoverRetalho = false),
                        child: GestureDetector(
                          onTap: _modoRetalho ? _desativarModoRetalho : _ativarModoRetalho,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _modoRetalho
                                  ? AppTheme.primary.withValues(alpha: 0.15)
                                  : _hoverRetalho
                                      ? AppTheme.primary.withValues(alpha: 0.08)
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _modoRetalho
                                    ? AppTheme.primary
                                    : _hoverRetalho
                                        ? AppTheme.primary.withValues(alpha: 0.6)
                                        : Theme.of(context).colorScheme.outlineVariant,
                                width: _modoRetalho ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.content_cut,
                                  size: 13,
                                  color: _modoRetalho || _hoverRetalho
                                      ? AppTheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'RETALHO',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: _modoRetalho || _hoverRetalho
                                        ? AppTheme.primary
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (_modoRetalho) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.check_circle, size: 13, color: AppTheme.primary),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _materialGenericoEscolhido != null
                          ? 'Trocar material genérico'
                          : 'Cadastrar como variante de um material genérico (ex.: TINTA)',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _hoverGenerico = true),
                        onExit:  (_) => setState(() => _hoverGenerico = false),
                        child: GestureDetector(
                          onTap: _abrirSeletorGenerico,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _materialGenericoEscolhido != null
                                  ? AppTheme.primary.withValues(alpha: 0.15)
                                  : _hoverGenerico
                                      ? AppTheme.primary.withValues(alpha: 0.08)
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _materialGenericoEscolhido != null
                                    ? AppTheme.primary
                                    : _hoverGenerico
                                        ? AppTheme.primary.withValues(alpha: 0.6)
                                        : Theme.of(context).colorScheme.outlineVariant,
                                width: _materialGenericoEscolhido != null ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.category_outlined,
                                  size: 13,
                                  color: _materialGenericoEscolhido != null || _hoverGenerico
                                      ? AppTheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _materialGenericoEscolhido != null
                                      ? _materialGenericoEscolhido!.nome
                                      : 'GENÉRICO',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: _materialGenericoEscolhido != null || _hoverGenerico
                                        ? AppTheme.primary
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (_materialGenericoEscolhido != null) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.check_circle, size: 13, color: AppTheme.primary),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_editando)
                    Tooltip(
                      message: 'Encaminhar este material no chat',
                      child: IconButton(
                        onPressed: () async {
                          final m = widget.material!;
                          final enviado = await encaminharParaChat(
                            context,
                            tipo: 'material',
                            dados: {
                              'materialId':     m.id,
                              'materialNome':   m.nome,
                              'unidade':        m.unidade,
                              'categoria':      m.categoria,
                              'identificador':  m.identificador,
                              'medida':         m.medida,
                              'espessura':      m.espessura,
                              'largura':        m.largura,
                              'comprimento':    m.comprimento,
                              'quantidade':     m.quantidade,
                            },
                          );
                          if (enviado && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.ios_share_outlined, size: 20),
                        style: IconButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                        ).copyWith(
                          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: _salvando ? null : _tentarFechar,
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 0),

            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  avisoPanel,

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                      child: formPanel,
                    ),
                  ),

                  if (fornecedorPanel != null) fornecedorPanel,
                ],
              ),
            ),

            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (_editando) ...[
                    if (widget.material!.ativo && widget.onDesativar != null)
                      Tooltip(
                        message: 'Desativar este material (ele deixa de aparecer nas listagens ativas)',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: TextButton.icon(
                            onPressed: _salvando
                                ? null
                                : () {
                                    Navigator.of(context).pop(false);
                                    widget.onDesativar!(widget.material!);
                                  },
                            icon: const Icon(Icons.block, size: 16),
                            label: const Text('Desativar'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.warning,
                            ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ),
                      ),
                    if (!widget.material!.ativo && widget.onReativar != null)
                      TextButton.icon(
                        onPressed: _salvando
                            ? null
                            : () {
                                Navigator.of(context).pop(false);
                                widget.onReativar!(widget.material!);
                              },
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Reativar'),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.success)
                            .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                    if (!widget.material!.ativo && widget.onExcluir != null)
                      Tooltip(
                        message: 'Excluir permanentemente este material',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: TextButton.icon(
                            onPressed: _salvando
                                ? null
                                : () {
                                    Navigator.of(context).pop(false);
                                    widget.onExcluir!(widget.material!);
                                  },
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Excluir'),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.error)
                                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ),
                      ),
                    if (widget.aprovando && widget.onRecusar != null)
                      Tooltip(
                        message: 'Recusar e excluir este cadastro pendente',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: TextButton.icon(
                            onPressed: _salvando ? null : _recusar,
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Recusar'),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.error)
                                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ),
                      ),
                  ],
                  if (widget.aprovando && widget.material?.criadoPorNome != null) ...[
                    Icon(Icons.person_outline, size: 14, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      'Cadastrado por ${widget.material!.criadoPorNome}',
                      style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline),
                    ),
                  ] else if (_bloqueadoParaCompras) ...[
                    Icon(Icons.lock_outline, size: 14, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      'Você pode alterar apenas a Categoria e confirmar o Estoque.',
                      style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                  const Spacer(),
                  Tooltip(
                    message: widget.somenteLeitura ? 'Fechar' : 'Cancelar e fechar sem salvar',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: TextButton(
                        onPressed: _salvando ? null : _tentarFechar,
                        style: TextButton.styleFrom()
                            .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        child: Text(widget.somenteLeitura ? 'Fechar' : 'Cancelar'),
                      ),
                    ),
                  ),
                  if (!widget.somenteLeitura) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    key: widget.tourKeys?.cadastrar,
                    message: widget.aprovando
                        ? 'Aprovar este material e adicioná-lo ao estoque'
                        : (_editando ? 'Salvar alterações' : 'Cadastrar este material'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: FilledButton(
                        onPressed: _salvando ? null : _salvar,
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.aprovando ? AppTheme.success : AppTheme.primary,
                        ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        child: _salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(widget.aprovando ? 'Aprovar' : (_editando ? 'Salvar' : 'Cadastrar')),
                      ),
                    ),
                  ),
                  ],
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

double? _extrairNumeroDeTexto(String? s) {
  if (s == null) return null;
  final match = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(s.trim());
  if (match == null) return null;
  return double.tryParse(match.group(0)!.replaceAll(',', '.'));
}

/// Dialog para escolher um material genérico (ex.: TINTA) ao qual a nova
/// variante em cadastro será vinculada. Usado pelo botão "GENÉRICO" no
/// formulário de cadastro de material (Estoque e Controle de Estoque).
///
/// Uso:
/// ```dart
/// final generico = await showSelecionarMaterialGenericoDialog(context);
/// if (generico != null) {
///   // generico.ehGenerico == true — usar generico.nome/unidade para
///   // pré-preencher a nova variante.
/// }
/// ```
Future<MaterialModel?> showSelecionarMaterialGenericoDialog(BuildContext context) {
  return showDialog<MaterialModel>(
    context: context,
    builder: (_) => const _SelecionarMaterialGenericoDialog(),
  );
}

class _SelecionarMaterialGenericoDialog extends StatefulWidget {
  const _SelecionarMaterialGenericoDialog();

  @override
  State<_SelecionarMaterialGenericoDialog> createState() =>
      _SelecionarMaterialGenericoDialogState();
}

class _SelecionarMaterialGenericoDialogState
    extends State<_SelecionarMaterialGenericoDialog> {
  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  bool _carregando = true;
  String? _erro;
  List<MaterialModel> _genericos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar([String? busca]) async {
    setState(() { _carregando = true; _erro = null; });
    try {
      final lista = await context.read<MaterialProvider>().listarGenericos(busca: busca);
      if (!mounted) return;
      setState(() { _genericos = lista; _carregando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os materiais genéricos.';
        _carregando = false;
      });
    }
  }

  void _aoBuscar(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _carregar(v.trim().isEmpty ? null : v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Material genérico',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Escolha o material genérico desta variante',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Fechar',
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom()
                          .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _buscaCtrl,
                autofocus: true,
                onChanged: _aoBuscar,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Buscar',
                  hintText: 'Ex.: TINTA',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _erro != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_erro!, textAlign: TextAlign.center),
                          ),
                        )
                      : _genericos.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.category_outlined, size: 40, color: Theme.of(context).hintColor),
                                    const SizedBox(height: 12),
                                    Text(
                                      _buscaCtrl.text.trim().isEmpty
                                          ? 'Nenhum material genérico cadastrado ainda.\n'
                                              'Marque um material como "Material genérico"\n'
                                              'no cadastro para poder usá-lo aqui.'
                                          : 'Nenhum material genérico encontrado para "${_buscaCtrl.text.trim()}".',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Theme.of(context).hintColor),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _genericos.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final m = _genericos[i];
                                return InkWell(
                                  mouseCursor: SystemMouseCursors.click,
                                  onTap: () => Navigator.of(context).pop(m),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    child: Row(
                                      children: [
                                        Icon(Icons.category_outlined, size: 18, color: AppTheme.primary),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                m.nome,
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                              if (m.categoria != null && m.categoria!.trim().isNotEmpty)
                                                Text(
                                                  m.categoria!,
                                                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          formatarUnidadeExibicao(m.unidade),
                                          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right, size: 18),
                                      ],
                                    ),
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

class _DimensoesMedida {
  final double? comprimento;
  final double? largura;
  final double? espessura;
  const _DimensoesMedida({this.comprimento, this.largura, this.espessura});
}

_DimensoesMedida _extrairDimensoesMedida(String? medida) {
  if (medida == null || medida.trim().isEmpty) return const _DimensoesMedida();
  final partes = medida.trim().split(RegExp(r'[xX×]'));
  final numeros = partes.map(_extrairNumeroDeTexto).toList();
  return _DimensoesMedida(
    comprimento: numeros.isNotEmpty ? numeros[0] : null,
    largura:     numeros.length > 1 ? numeros[1] : null,
    espessura:   numeros.length > 2 ? numeros[2] : null,
  );
}

String _normalizarTextoComparacao(String? v) {
  if (v == null) return '';
  final upper = _UpperCaseFormatter._removerAcentos(v.trim().toUpperCase());
  return upper.replaceAll(RegExp(r'\s+'), ' ');
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> anterior = List<int>.generate(b.length + 1, (j) => j);
  List<int> atual = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    atual[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final custoSubstituicao = a[i - 1] == b[j - 1] ? 0 : 1;
      final remocao = anterior[j] + 1;
      final insercao = atual[j - 1] + 1;
      final substituicao = anterior[j - 1] + custoSubstituicao;
      atual[j] = [remocao, insercao, substituicao].reduce((x, y) => x < y ? x : y);
    }
    final troca = anterior;
    anterior = atual;
    atual = troca;
  }
  return anterior[b.length];
}

double _similaridadeTexto(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final distancia = _levenshteinDistance(a, b);
  final maiorTamanho = a.length > b.length ? a.length : b.length;
  return 1 - (distancia / maiorTamanho);
}

double _similaridadePalavras(String a, String b) {
  final palavrasA = a.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final palavrasB = b.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (palavrasA.isEmpty && palavrasB.isEmpty) return 1;
  if (palavrasA.isEmpty || palavrasB.isEmpty) return 0;

  final menor = palavrasA.length <= palavrasB.length ? palavrasA : palavrasB;
  final maior = palavrasA.length <= palavrasB.length ? palavrasB : palavrasA;
  final usados = List<bool>.filled(maior.length, false);

  var pesoCasado = 0.0;
  for (final palavra in menor) {
    var melhorIdx = -1;
    var melhorScore = 0.0;
    for (var i = 0; i < maior.length; i++) {
      if (usados[i]) continue;
      if (palavra == maior[i]) {

        melhorIdx = i;
        melhorScore = 1.0;
        break;
      }

      final tamMin = palavra.length < maior[i].length ? palavra.length : maior[i].length;
      if (tamMin <= 2 && palavra != maior[i]) continue;
      final score = _similaridadeTexto(palavra, maior[i]);

      if (score >= 0.75 && score > melhorScore) {
        melhorScore = score;
        melhorIdx = i;
      }
    }
    if (melhorIdx != -1) {
      usados[melhorIdx] = true;
      pesoCasado += melhorScore * palavra.length;
    }
  }

  final pesoTotal = (palavrasA + palavrasB).fold<int>(0, (soma, p) => soma + p.length);
  if (pesoTotal == 0) return 0;

  return (pesoCasado * 2) / pesoTotal;
}

class _PossivelDuplicata {
  final MaterialModel material;

  final bool exata;
  final double similaridade;

  final bool contido;

  _PossivelDuplicata({
    required this.material,
    required this.exata,
    required this.similaridade,
    this.contido = false,
  });
}

class _AvisoPossivelDuplicata extends StatelessWidget {
  final bool carregando;
  final List<_PossivelDuplicata> duplicatas;
  const _AvisoPossivelDuplicata({required this.carregando, required this.duplicatas});

  @override
  Widget build(BuildContext context) {
    if (carregando && duplicatas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 8),
            Text(
              'Verificando materiais semelhantes...',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    if (duplicatas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline, size: 14,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nenhum material parecido encontrado até agora',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ],
        ),
      );
    }

    final temExata = duplicatas.any((d) => d.exata);
    final cor = temExata ? AppTheme.error : AppTheme.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: cor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  temExata
                      ? 'Já existe um material idêntico cadastrado'
                      : 'Pode já existir um material parecido cadastrado',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...duplicatas.map((d) {
            final m = d.material;

            String? dimensaoFormatada;
            if (m.comprimento != null && m.largura != null &&
                m.comprimento! > 0 && m.largura! > 0) {
              String fmt(double v) =>
                  v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
              dimensaoFormatada = '${fmt(m.comprimento!)}x${fmt(m.largura!)}m';
            }

            final detalhes = [
              if (m.identificador != null && m.identificador!.trim().isNotEmpty) m.identificador!.trim(),
              if (dimensaoFormatada != null)
                dimensaoFormatada
              else if (m.medida != null && m.medida!.trim().isNotEmpty)
                m.medida!.trim(),
              if (m.espessura != null && m.espessura!.trim().isNotEmpty)
                '${m.espessura!.trim().replaceAll(RegExp(r"mm\s*$", caseSensitive: false), '').trim()}mm',
            ].join(' • ');

            final qtdTxt = formatarQuantidadeExibicao(m.quantidade);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: d.exata ? AppTheme.error : AppTheme.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                        children: [
                          TextSpan(text: m.nomeExibicao, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (detalhes.isNotEmpty)
                            TextSpan(
                              text: '  ($detalhes)',
                              style: TextStyle(color: Theme.of(context).colorScheme.outline),
                            ),
                          TextSpan(
                            text: !m.ativo ? '  • inativo' : '  • estoque: $qtdTxt',
                            style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            temExata
                ? 'Esse cadastro será bloqueado pelo sistema. Ajuste a medida/espessura ou edite o material existente.'
                : 'Confira se não é o mesmo material antes de continuar, para evitar estoques duplicados.',
            style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _QuantidadeBloqueadaInfo extends StatelessWidget {
  const _QuantidadeBloqueadaInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A entrada de quantidade deve ser feita na página de '
              'Controle de Estoque, vinculada a uma OS.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstoqueMinimoBloqueadoInfo extends StatelessWidget {
  const _EstoqueMinimoBloqueadoInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estoque mínimo bloqueado.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatarCustoVisual(double valor) {
  final fixo = valor.toStringAsFixed(2);
  final partes = fixo.split('.');
  final inteiro = partes[0];
  final decimal = partes.length > 1 ? partes[1] : '00';

  final buffer = StringBuffer();
  final len = inteiro.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buffer.write('.');
    buffer.write(inteiro[i]);
  }

  return '${buffer.toString()},$decimal';
}

String formatarQuantidade(double valor) {
  if (valor == valor.truncateToDouble()) return valor.toStringAsFixed(0);

  return valor.toString();
}

String formatarQuantidadeExibicao(double v) {
  final bool isInteiro = v == v.truncateToDouble();
  final String bruto = isInteiro ? v.toStringAsFixed(0) : v.toString();

  final bool negativo = bruto.startsWith('-');
  final String semSinal = negativo ? bruto.substring(1) : bruto;

  final partes = semSinal.split('.');
  final parteInteira = partes[0];
  final parteDecimal = partes.length > 1 ? partes[1] : null;

  final buffer = StringBuffer();
  final len = parteInteira.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buffer.write('.');
    buffer.write(parteInteira[i]);
  }

  final resultado = parteDecimal != null
      ? '${buffer.toString()},$parteDecimal'
      : buffer.toString();

  return negativo ? '-$resultado' : resultado;
}

/// Célula de "Preço" da tabela de materiais. Em vez de mostrar o valor
/// numérico (que pode ser unitário, m² ou por unidade de medida — ver
/// [_HistoricoPrecoDialog]), mostra sempre um texto-botão "Ver preço"
/// que abre o histórico de compras com o detalhamento completo.
class _VerPrecoCell extends StatefulWidget {
  final VoidCallback onTap;

  const _VerPrecoCell({required this.onTap});

  @override
  State<_VerPrecoCell> createState() => _VerPrecoCellState();
}

class _VerPrecoCellState extends State<_VerPrecoCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (_) { if (!_hovered) setState(() => _hovered = true); },
      onExit:  (_) { if (_hovered)  setState(() => _hovered = false); },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              decoration: BoxDecoration(
                color: _hovered
                    ? AppTheme.primary.withValues(alpha: 0.85)
                    : AppTheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sell_outlined, size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Ver preço',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustoCell extends StatefulWidget {
  final double? valor;
  final bool temHistorico;
  final VoidCallback onTap;

  const _CustoCell({
    required this.valor,
    required this.temHistorico,
    required this.onTap,
  });

  @override
  State<_CustoCell> createState() => _CustoCellState();
}

class _CustoCellState extends State<_CustoCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hasValue  = widget.valor != null && widget.valor! > 0;
    final label     = hasValue ? 'R\$ ${_formatarCustoVisual(widget.valor!)}' : '—';
    final showHover = widget.temHistorico && _hovered;

    return MouseRegion(
      cursor: widget.temHistorico ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: (_) { if (!_hovered) setState(() => _hovered = true); },
      onExit:  (_) { if (_hovered)  setState(() => _hovered = false); },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.temHistorico ? widget.onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: showHover
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasValue && showHover)
                  const Padding(
                    padding: EdgeInsets.only(right: 0),
                  ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: showHover
                        ? AppTheme.primary
                        : hasValue
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outline,
                        fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog exibido ao selecionar um material "genérico" (ex.: "TINTA").
/// Lista todos os materiais vinculados a ele — cada um com sua própria
/// descrição, fornecedores, preços e estoque próprios — permitindo
/// escolher qual variante usar no fluxo atual (Estoque, Orçamento, Ordem
/// de Compra, Solicitações, etc).
///
/// Uso:
/// ```dart
/// final selecionado = await showMaterialVinculadosDialog(
///   context,
///   materialGenerico: material, // material.ehGenerico == true
/// );
/// if (selecionado != null) {
///   // usar `selecionado` (um MaterialModel filho) normalmente
/// }
/// ```
Future<MaterialModel?> showMaterialVinculadosDialog(
  BuildContext context, {
  required MaterialModel materialGenerico,
  bool apenasAtivos = true,
}) {
  return showDialog<MaterialModel>(
    context: context,
    builder: (_) => _MaterialVinculadosDialog(
      materialGenerico: materialGenerico,
      apenasAtivos: apenasAtivos,
    ),
  );
}

/// Badge de contagem usado nas abas "Com estoque" / "Sem estoque" do
/// [_MaterialVinculadosDialog], no mesmo estilo do usado em Controle de
/// Estoque para "Em Andamento" / "Fechadas".
Widget _badgeContagemVinculados(int contagem) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$contagem',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.primary,
      ),
    ),
  );
}

class _MaterialVinculadosDialog extends StatefulWidget {
  final MaterialModel materialGenerico;
  final bool apenasAtivos;

  const _MaterialVinculadosDialog({
    required this.materialGenerico,
    this.apenasAtivos = true,
  });

  @override
  State<_MaterialVinculadosDialog> createState() => _MaterialVinculadosDialogState();
}

class _MaterialVinculadosDialogState extends State<_MaterialVinculadosDialog>
    with SingleTickerProviderStateMixin {
  final Set<int> _selecionados = {};
  final TextEditingController _buscaCtrl = TextEditingController();
  late final TabController _tabController;
  bool _processando = false;
  bool _modoSelecao = false;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MaterialProvider>().carregarVinculados(
            widget.materialGenerico.id,
            apenasAtivos: widget.apenasAtivos,
          );
    });
  }

  @override
  void dispose() {
    context.read<MaterialProvider>().limparVinculados();
    _buscaCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _aoBuscar(String v) => setState(() => _busca = v);

  /// Filtra os itens vinculados pela descrição, ignorando maiúsculas/
  /// minúsculas e espaços nas pontas. Se a busca estiver vazia, retorna a
  /// lista completa sem alterações.
  List<MaterialModel> _filtrarPorDescricao(List<MaterialModel> itens) {
    final termo = _busca.trim().toLowerCase();
    if (termo.isEmpty) return itens;
    return itens.where((i) {
      final descricao = (i.descricao ?? '').toLowerCase();
      return descricao.contains(termo);
    }).toList();
  }

  /// Variantes com estoque atual maior que zero.
  List<MaterialModel> _comEstoque(List<MaterialModel> itens) =>
      itens.where((i) => i.quantidade > 0).toList();

  /// Variantes sem estoque (zeradas ou negativas).
  List<MaterialModel> _semEstoque(List<MaterialModel> itens) =>
      itens.where((i) => i.quantidade <= 0).toList();

  Color _corStatus(String status) {
    switch (status) {
      case 'CRITICO':
        return Colors.red;
      case 'LIMITE':
        return Colors.orange;
      case 'INATIVO':
        return Colors.grey;
      default:
        return Colors.green;
    }
  }

  List<MaterialModel> get _itens => context.read<MaterialProvider>().vinculados?.itens ?? const [];

  List<MaterialModel> get _itensSelecionados =>
      _itens.where((i) => _selecionados.contains(i.id)).toList();

  /// true se a seleção atual é só de ativos, false se é só de inativos,
  /// null se estiver vazia ou misturada (não deve acontecer, pois
  /// impedimos toggle misto em [_alternarSelecao]).
  bool? get _selecaoEhAtiva {
    if (_selecionados.isEmpty) return null;
    final selecionados = _itensSelecionados;
    final todosAtivos = selecionados.every((i) => i.ativo);
    final todosInativos = selecionados.every((i) => !i.ativo);
    if (todosAtivos) return true;
    if (todosInativos) return false;
    return null;
  }

  void _alternarSelecao(MaterialModel item) {
    setState(() {
      _modoSelecao = true;
      if (_selecionados.contains(item.id)) {
        _selecionados.remove(item.id);
        return;
      }
      // Impede misturar ativos e inativos na mesma seleção: ao selecionar
      // um item de status diferente do que já está selecionado, troca a
      // seleção para conter apenas o novo item.
      final jaSelecionados = _itensSelecionados;
      if (jaSelecionados.isNotEmpty && jaSelecionados.first.ativo != item.ativo) {
        _selecionados
          ..clear()
          ..add(item.id);
      } else {
        _selecionados.add(item.id);
      }
    });
  }

  void _alternarModoSelecao() {
    setState(() {
      _modoSelecao = !_modoSelecao;
      if (!_modoSelecao) _selecionados.clear();
    });
  }

  Future<void> _desativarSelecionados() async {
    final itens = _itensSelecionados;
    if (itens.isEmpty) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Desativar materiais'),
        content: Text(
          itens.length == 1
              ? 'Deseja desativar "${itens.first.nomeExibicao}"?\n\nSe ele estiver vinculado a ordens em andamento, a operação será bloqueada.'
              : 'Deseja desativar ${itens.length} materiais selecionados?\n\nSe algum estiver vinculado a ordens em andamento, a operação será bloqueada para esse item.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await _executarEmLote(itens, (provider, id) => provider.desativar(id));
  }

  Future<void> _reativarSelecionados() async {
    final itens = _itensSelecionados;
    if (itens.isEmpty) return;
    await _executarEmLote(itens, (provider, id) => provider.reativar(id));
  }

  Future<void> _excluirSelecionados() async {
    final itens = _itensSelecionados;
    if (itens.isEmpty) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir materiais'),
        content: Text(
          itens.length == 1
              ? 'Deseja excluir "${itens.first.nomeExibicao}"? Esta ação não pode ser desfeita.'
              : 'Deseja excluir ${itens.length} materiais selecionados? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await _executarEmLote(itens, (provider, id) => provider.excluir(id));
  }

  Future<void> _executarEmLote(
    List<MaterialModel> itens,
    Future<bool> Function(MaterialProvider provider, int id) acao,
  ) async {
    setState(() => _processando = true);
    final provider = context.read<MaterialProvider>();
    var sucesso = 0;
    var falha = 0;
    for (final item in itens) {
      final ok = await acao(provider, item.id);
      if (ok) {
        sucesso++;
      } else {
        falha++;
      }
    }
    if (!mounted) return;
    setState(() {
      _selecionados.clear();
      _modoSelecao = false;
      _processando = false;
    });
    await provider.carregarVinculados(widget.materialGenerico.id, apenasAtivos: widget.apenasAtivos);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        falha == 0
            ? '$sucesso material(is) atualizado(s) com sucesso.'
            : '$sucesso atualizado(s), $falha falhou(aram). ${provider.erro ?? ''}'.trim(),
      ),
      backgroundColor: falha == 0 ? AppTheme.success : AppTheme.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialProvider>();
    final carregando = provider.carregandoVinculados;
    final resultado = provider.vinculados;
    final erro = provider.erro;
    final modoSelecao = _modoSelecao;
    final temSelecao = _selecionados.isNotEmpty;
    final selecaoEhAtiva = _selecaoEhAtiva;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.materialGenerico.nome,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          modoSelecao
                              ? (temSelecao
                                  ? '${_selecionados.length} selecionado(s)'
                                  : 'Toque nos materiais para selecionar')
                              : 'Selecione a variante do material',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (!modoSelecao)
                    Tooltip(
                      message: 'Editar material genérico',
                      child: TextButton.icon(
                        onPressed: _processando
                            ? null
                            : () => Navigator.of(context).pop(widget.materialGenerico),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar'),
                        style: TextButton.styleFrom()
                            .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                    ),
                  if (resultado != null && resultado.itens.isNotEmpty)
                    Tooltip(
                      message: modoSelecao ? 'Cancelar seleção' : 'Selecionar materiais',
                      child: TextButton.icon(
                        onPressed: _processando ? null : _alternarModoSelecao,
                        icon: Icon(modoSelecao ? Icons.close : Icons.checklist, size: 18),
                        label: Text(modoSelecao ? 'Cancelar seleção' : 'Selecionar'),
                        style: TextButton.styleFrom()
                            .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                    ),
                  Tooltip(
                    message: 'Fechar',
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom()
                          .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                ],
              ),
            ),
            if (!carregando && erro == null && resultado != null && resultado.itens.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _buscaCtrl,
                  onChanged: _aoBuscar,
                  decoration: InputDecoration(
                    hintText: 'Buscar por descrição',
                    prefixIcon: Icon(Icons.search, size: 20, color: Theme.of(context).colorScheme.outline),
                    isDense: true,
                    suffixIcon: _busca.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _buscaCtrl.clear();
                              _aoBuscar('');
                            },
                            style: IconButton.styleFrom()
                                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                  ),
                ),
              ),
            if (temSelecao) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_processando)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    if (selecaoEhAtiva == true)
                      Tooltip(
                        message: 'Desativar os materiais selecionados',
                        child: OutlinedButton.icon(
                          onPressed: _processando ? null : _desativarSelecionados,
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('Desativar'),
                          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.warning)
                              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        ),
                      )
                    else if (selecaoEhAtiva == false) ...[
                      Tooltip(
                        message: 'Reativar os materiais selecionados',
                        child: OutlinedButton.icon(
                          onPressed: _processando ? null : _reativarSelecionados,
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('Reativar'),
                          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success)
                              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Excluir os materiais selecionados',
                        child: OutlinedButton.icon(
                          onPressed: _processando ? null : _excluirSelecionados,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Excluir'),
                          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error)
                              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const Divider(height: 1),
            Expanded(
              child: carregando
                  ? const Center(child: CircularProgressIndicator())
                  : erro != null
                      ? _MaterialVinculadosEstadoVazio(
                          icone: Icons.error_outline,
                          mensagem: erro,
                        )
                      : (resultado == null || resultado.itens.isEmpty)
                          ? const _MaterialVinculadosEstadoVazio(
                              icone: Icons.inventory_2_outlined,
                              mensagem: 'Nenhum material vinculado ainda.\n'
                                  'Vincule variantes deste material genérico em\n'
                                  'Orçamento, Ordem de Compra\n'
                                  'ou Solicitações.',
                            )
                          : Builder(builder: (context) {
                              final itensFiltrados = _filtrarPorDescricao(resultado.itens);
                              final comEstoque = _comEstoque(itensFiltrados);
                              final semEstoque = _semEstoque(itensFiltrados);

                              Widget listaOuVazio(List<MaterialModel> itens, String mensagemVazia) {
                                if (itens.isEmpty) {
                                  return _MaterialVinculadosEstadoVazio(
                                    icone: _busca.trim().isEmpty
                                        ? Icons.inventory_2_outlined
                                        : Icons.search_off,
                                    mensagem: _busca.trim().isEmpty
                                        ? mensagemVazia
                                        : 'Nenhuma variante encontrada para\n'
                                            '"${_busca.trim()}".',
                                  );
                                }
                                return _MaterialVinculadosTabela(
                                  itens: itens,
                                  modoSelecao: modoSelecao,
                                  processando: _processando,
                                  selecionados: _selecionados,
                                  selecaoEhAtiva: selecaoEhAtiva,
                                  corStatus: _corStatus,
                                  onAlternarSelecao: _alternarSelecao,
                                  onSelecionar: (item) => Navigator.of(context).pop(item),
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surface,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Theme.of(context).colorScheme.outlineVariant,
                                        ),
                                      ),
                                    ),
                                    child: TabBar(
                                      controller: _tabController,
                                      labelColor: AppTheme.primary,
                                      unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                      indicatorColor: AppTheme.primary,
                                      indicatorWeight: 2,
                                      labelStyle: const TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 13),
                                      tabs: [
                                        Tab(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text('Com estoque'),
                                              const SizedBox(width: 6),
                                              _badgeContagemVinculados(comEstoque.length),
                                            ],
                                          ),
                                        ),
                                        Tab(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text('Sem estoque'),
                                              const SizedBox(width: 6),
                                              _badgeContagemVinculados(semEstoque.length),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: [
                                        listaOuVazio(
                                          comEstoque,
                                          'Nenhuma variante com estoque no momento.',
                                        ),
                                        listaOuVazio(
                                          semEstoque,
                                          'Nenhuma variante sem estoque no momento.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialVinculadosEstadoVazio extends StatelessWidget {
  final IconData icone;
  final String mensagem;
  const _MaterialVinculadosEstadoVazio({required this.icone, required this.mensagem});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tabela de materiais variantes exibida no [_MaterialVinculadosDialog].
/// Colunas: nome (com descrição abaixo, antes do identificador),
/// identificador, medida/qtd e um preço clicável que abre o histórico
/// de compras daquela variante (mesmo padrão de [_CustoCell] usado na
/// tela de Estoque).
class _MaterialVinculadosTabela extends StatelessWidget {
  final List<MaterialModel> itens;
  final bool modoSelecao;
  final bool processando;
  final Set<int> selecionados;
  final bool? selecaoEhAtiva;
  final Color Function(String status) corStatus;
  final void Function(MaterialModel item) onAlternarSelecao;
  final void Function(MaterialModel item) onSelecionar;

  const _MaterialVinculadosTabela({
    required this.itens,
    required this.modoSelecao,
    required this.processando,
    required this.selecionados,
    required this.selecaoEhAtiva,
    required this.corStatus,
    required this.onAlternarSelecao,
    required this.onSelecionar,
  });

  void _abrirHistorico(BuildContext context, MaterialModel item) {
    showDialog(
      context: context,
      builder: (_) => _HistoricoPrecoDialog(material: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    const colNome   = 4;
    const colQtd    = 2;
    const colPreco  = 2;
    const colStatus = 2;

    Widget headerCell(String texto, int flex, {TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              texto,
              textAlign: align,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              if (modoSelecao) const SizedBox(width: 44),
              headerCell('Material', colNome),
              headerCell('Estoque atual', colQtd, align: TextAlign.right),
              headerCell('Preço', colPreco, align: TextAlign.center),
              headerCell('Status', colStatus, align: TextAlign.center),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: itens.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = itens[index];
              final selecionado = selecionados.contains(item.id);
              // Durante uma seleção ativa, itens de status oposto ao
              // selecionado ficam desabilitados (não podem entrar na
              // seleção mista).
              final bloqueadoPelaSelecao = modoSelecao &&
                  selecaoEhAtiva != null &&
                  item.ativo != selecaoEhAtiva &&
                  !selecionado;
              final desabilitado = processando || bloqueadoPelaSelecao;
              final corTexto = item.ativo ? null : Theme.of(context).hintColor;
              final temDescricao = item.descricao != null && item.descricao!.trim().isNotEmpty;

              return Tooltip(
                message: desabilitado
                    ? ''
                    : (modoSelecao
                        ? (selecionado ? 'Remover da seleção' : 'Selecionar')
                        : ''),
                child: MouseRegion(
                  cursor: desabilitado
                      ? MouseCursor.defer
                      : SystemMouseCursors.click,
                  child: InkWell(
                    mouseCursor: desabilitado
                        ? MouseCursor.defer
                        : SystemMouseCursors.click,
                    onTap: desabilitado
                        ? null
                        : (modoSelecao
                            ? () => onAlternarSelecao(item)
                            : () => onSelecionar(item)),
                    onLongPress:
                        desabilitado ? null : () => onAlternarSelecao(item),
                    child: Opacity(
                      opacity: desabilitado && !selecionado ? 0.45 : 1,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (modoSelecao)
                            SizedBox(
                              width: 44,
                              child: Checkbox(
                                value: selecionado,
                                onChanged: bloqueadoPelaSelecao
                                    ? null
                                    : (_) => onAlternarSelecao(item),
                              ),
                            ),

                          Expanded(
                            flex: colNome,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.nome,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: corTexto,
                                    ),
                                  ),
                                  if (temDescricao) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.descricao!.trim(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).hintColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          Expanded(
                            flex: colQtd,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '${formatarQuantidadeExibicao(item.quantidade)} ${(item.unidade ?? '').toLowerCase()}'
                                    .trim(),
                                textAlign: TextAlign.right,
                                style: TextStyle(color: corTexto),
                              ),
                            ),
                          ),

                          Expanded(
                            flex: colPreco,
                            child: _CustoCell(
                              valor: item.precoRef,
                              temHistorico: true,
                              onTap: () => _abrirHistorico(context, item),
                            ),
                          ),

                          Expanded(
                            flex: colStatus,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (item.ativo
                                            ? corStatus(item.status)
                                            : Theme.of(context).hintColor)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.ativo ? item.status : 'INATIVO',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: item.ativo
                                          ? corStatus(item.status)
                                          : Theme.of(context).hintColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Os 3 tipos de preço que um material pode ter registrado no histórico
/// de compras, conforme como cada Ordem de Compra foi lançada.
enum _TipoPreco { unitario, m2, unidadeMedida }

/// Uma coluna do resumo de preços no topo do [_HistoricoPrecoDialog]:
/// rótulo do tipo de preço em cima, valor (ou "—" se esse material nunca
/// foi comprado nesse formato) embaixo.
class _PrecoResumoColuna extends StatelessWidget {
  final String label;
  final double? valor;

  const _PrecoResumoColuna({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    final temValor = valor != null && valor! > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          temValor ? 'R\$ ${_formatarCustoVisual(valor!)}' : '—',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: temValor ? const Color(0xFFE85D04) : Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _HistoricoPrecoDialog extends StatefulWidget {
  final MaterialModel material;
  const _HistoricoPrecoDialog({required this.material});

  @override
  State<_HistoricoPrecoDialog> createState() => _HistoricoPrecoDialogState();
}

class _HistoricoPrecoDialogState extends State<_HistoricoPrecoDialog> {
  List<HistoricoPrecoModel> _historico = [];
  bool _carregando = true;
  String? _erro;

  bool _mostrarFormCusto = false;
  bool _salvandoCusto    = false;
  final _ctrlUnit = TextEditingController();
  final _ctrlM2   = TextEditingController();

  @override
  void dispose() {
    _ctrlUnit.dispose();
    _ctrlM2.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _carregar();
    });
  }

  Future<void> _salvarCustoManual() async {
    final unitStr = _ctrlUnit.text.trim();
    final m2Str   = _ctrlM2.text.trim();
    final unit = _parsePreco(unitStr);
    final m2   = _parsePreco(m2Str);

    if ((unitStr.isEmpty || unit == null) && (m2Str.isEmpty || m2 == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ao menos um valor (unitário ou m²).'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    setState(() => _salvandoCusto = true);
    final ok = await context.read<MaterialProvider>().atualizarCustoManual(
      widget.material.id,
      ultimoValorPago:   (unitStr.isNotEmpty && unit != null) ? unit : null,
      ultimoValorPagoM2: (m2Str.isNotEmpty   && m2   != null) ? m2   : null,
    );
    if (!mounted) return;
    setState(() { _salvandoCusto = false; _mostrarFormCusto = false; });
    if (ok) {
      _ctrlUnit.clear();
      _ctrlM2.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custo atualizado com sucesso.'),
          backgroundColor: AppTheme.success,
        ),
      );
      if (context.mounted) {
        context.read<ProdutoProvider>().recarregar();
        context.read<OrcamentoVendaProvider>().recarregar();
      }
    }
  }

  Widget _buildFormCusto() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Inserir custo manualmente',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 4),
          Text(
            'Preencha apenas os campos que deseja atualizar. Deixe em branco para não alterar.',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrlUnit,
                  decoration: const InputDecoration(
                    labelText: 'Preço',
                    prefixText: 'R\$ ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_PrecoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ctrlM2,
                  decoration: const InputDecoration(
                    labelText: 'Preço m²',
                    prefixText: 'R\$ ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_PrecoInputFormatter()],
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _salvandoCusto ? null : () => setState(() {
                  _mostrarFormCusto = false;
                  _ctrlUnit.clear();
                  _ctrlM2.clear();
                }),
                style: TextButton.styleFrom()
                    .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _salvandoCusto ? null : _salvarCustoManual,
                icon: _salvandoCusto
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 16),
                label: const Text('Salvar'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                    .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _carregar() async {
    try {
      final lista = await context
          .read<MaterialProvider>()
          .listarHistoricoPrecos(widget.material.id);
      if (mounted) setState(() { _historico = lista; _carregando = false; });
    } catch (e) {
      if (mounted) setState(() { _erro = e.toString(); _carregando = false; });
    }
  }

  /// Preço unitário "real" de uma compra: valor total dividido pela
  /// quantidade comprada. Para itens comprados por unidade simples isso
  /// coincide com `h.precoUnitario`, mas para itens m/l (onde
  /// `precoUnitario` guarda o preço por metro linear, não o preço da
  /// compra) é a única forma correta de saber quanto custou cada unidade
  /// — ex.: 2 unidades por R$ 1.000,00 no total = R$ 500,00/unidade,
  /// mesmo que o preço por m/l seja R$ 10,00. Sem isso, o card "Preço
  /// unitário" ficava vazio para qualquer item comprado com qtdUnidade
  /// preenchido (m/l, ml, g...).
  double? _precoUnitarioReal(HistoricoPrecoModel h) {
    if (h.usarM2) return null;
    if (h.quantidade > 0 && h.total > 0) return h.total / h.quantidade;
    if (h.precoUnitario > 0) return h.precoUnitario;
    return null;
  }

  /// Custo m² de um registro do histórico. Quando a compra já veio com
  /// preço por m² (usarM2), usa o valor direto. Caso contrário, para
  /// materiais vendidos por unidade de medida linear (m/l) com largura
  /// cadastrada, deriva o preço por m² a partir do preço por metro linear
  /// — mesma conta que o backend já faz para preencher
  /// `ultimoValorPagoM2` do material (preço/l / largura). Sem isso, a
  /// coluna "Custo m²" ficava sempre vazia para materiais m/l, mesmo
  /// quando dá pra calcular.
  double? _custoM2(HistoricoPrecoModel h) {
    if (h.usarM2 && h.precoM2 != null && h.precoM2! > 0) return h.precoM2;
    if (!h.usarM2 && h.precoUnitario > 0) {
      final m = widget.material;
      final unidade = (m.unidade ?? '').trim().toUpperCase();
      const unidadesMetroLinear = ['M', 'ML', 'M/L', 'METRO', 'METROS', 'METRO LINEAR', 'METROS LINEARES'];
      if (unidadesMetroLinear.contains(unidade) && m.largura != null && m.largura! > 0) {
        return h.precoUnitario / m.largura!;
      }
      final area = m.areaUnitariaM2;
      if (area != null && area > 0) {
        return h.precoUnitario / area;
      }
    }
    return null;
  }

  /// Busca, na lista de histórico (já ordenada da compra mais recente
  /// para a mais antiga), o primeiro registro que corresponda ao tipo de
  /// preço pedido — o material pode ter sido comprado ora por m², ora por
  /// unidade, ora por unidade de medida (m/l, ml, g...), então cada tipo
  /// precisa do seu próprio "último preço" em vez de olhar só a compra
  /// mais recente (que só reflete um dos três tipos por vez).
  HistoricoPrecoModel? _ultimoDoTipo(_TipoPreco tipo) {
    for (final h in _historico) {
      switch (tipo) {
        case _TipoPreco.m2:
          final custoM2 = _custoM2(h);
          if (custoM2 != null && custoM2 > 0) return h;
          break;
        case _TipoPreco.unidadeMedida:
          if (!h.usarM2 && h.qtdUnidade != null && h.qtdUnidade! > 0 && h.precoUnitario > 0) return h;
          break;
        case _TipoPreco.unitario:
          final real = _precoUnitarioReal(h);
          if (real != null && real > 0) return h;
          break;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;

    final ultimoUnitario      = _ultimoDoTipo(_TipoPreco.unitario);
    final ultimoM2            = _ultimoDoTipo(_TipoPreco.m2);
    final ultimoUnidadeMedida = _ultimoDoTipo(_TipoPreco.unidadeMedida);

    final ultimoCusto        = ultimoUnitario != null ? _precoUnitarioReal(ultimoUnitario) : null;
    final ultimoCustoM2      = ultimoM2 != null ? _custoM2(ultimoM2) : null;
    final ultimoCustoUnidade = ultimoUnidadeMedida?.precoUnitario;

    final temCusto        = ultimoCusto        != null && ultimoCusto        > 0;
    final temCustoM2      = ultimoCustoM2      != null && ultimoCustoM2      > 0;
    final temCustoUnidade = ultimoCustoUnidade != null && ultimoCustoUnidade > 0 &&
        deveExibirPrecoUnidade(m.unidade);
    final labelUnidade = labelPrecoUnidade(m.unidade);

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 740,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20, color: Color(0xFFE85D04)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Histórico de Compras — ${m.nome}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            if (_historico.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE85D04).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE85D04).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _PrecoResumoColuna(
                        label: 'Preço',
                        valor: temCusto ? ultimoCusto : null,
                      ),
                    ),
                    SizedBox(
                      height: 30,
                      child: VerticalDivider(
                        width: 24,
                        thickness: 0.8,
                        color: const Color(0xFFE85D04).withValues(alpha: 0.2),
                      ),
                    ),
                    Expanded(
                      child: _PrecoResumoColuna(
                        label: 'Preço m²',
                        valor: temCustoM2 ? ultimoCustoM2 : null,
                      ),
                    ),
                    SizedBox(
                      height: 30,
                      child: VerticalDivider(
                        width: 24,
                        thickness: 0.8,
                        color: const Color(0xFFE85D04).withValues(alpha: 0.2),
                      ),
                    ),
                    Expanded(
                      child: _PrecoResumoColuna(
                        label: labelUnidade,
                        valor: temCustoUnidade ? ultimoCustoUnidade : null,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Fornecedor',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      'OC #',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'Quantidade',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'm/l por unidade',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Valor/m/l',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Preço m²',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Total',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      'Data',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFE85D04))),
              )
            else if (_erro != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                      SizedBox(height: 12),
                      Text(
                        _erro!,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _carregar,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Tentar novamente'),
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                          .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                    ],
                  ),
                ),
              )
            else if (_historico.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Nenhum preço registrado.\nO histórico é criado automaticamente ao finalizar uma Ordem de Compra.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_historico.length, (i) {
                      final h = _historico[i];
                      final isUltimo = i == 0;
                      final data = h.dataOrdem ?? h.criadoEm;
                      final dataStr =
                          '${data.day.toString().padLeft(2, '0')}/'
                          '${data.month.toString().padLeft(2, '0')}/'
                          '${data.year}';

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                            decoration: isUltimo
                                ? BoxDecoration(
                                    color: const Color(0xFFE85D04).withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(6),
                                  )
                                : null,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      if (isUltimo) ...[
                                        const Tooltip(
                                          message: 'Custo atual (mais recente)',
                                          child: Icon(Icons.radio_button_checked,
                                              size: 13, color: Color(0xFFE85D04)),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: Text(
                                          h.fornecedorNome,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isUltimo
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                            color: isUltimo
                                                ? Theme.of(context).colorScheme.onSurface
                                                : Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    h.ordemCompraId != null ? '#${h.ordemCompraId}' : '—',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ),
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    formatarQuantidadeExibicao(h.quantidade),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUltimo ? FontWeight.w700 : FontWeight.normal,
                                      color: isUltimo
                                          ? Theme.of(context).colorScheme.onSurface
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    !h.usarM2 && h.qtdUnidade != null && h.qtdUnidade! > 0
                                        ? '${formatarQuantidadeExibicao(h.qtdUnidade!)} m/l'
                                        : '—',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUltimo ? FontWeight.w700 : FontWeight.normal,
                                      color: isUltimo
                                          ? Theme.of(context).colorScheme.onSurface
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    !h.usarM2 && h.precoUnitario > 0
                                        ? 'R\$ ${_formatarCustoVisual(h.precoUnitario)}'
                                        : '—',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUltimo
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      color: isUltimo
                                          ? Color(0xFFE85D04)
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Builder(builder: (_) {
                                    final custoM2 = _custoM2(h);
                                    return Text(
                                      custoM2 != null && custoM2 > 0
                                          ? 'R\$ ${_formatarCustoVisual(custoM2)}'
                                          : '—',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isUltimo
                                            ? Color(0xFFE85D04)
                                            : Theme.of(context).colorScheme.onSurface,
                                        fontWeight: isUltimo
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                      ),
                                    );
                                  }),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    'R\$ ${_formatarCustoVisual(h.total)}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUltimo ? FontWeight.w700 : FontWeight.normal,
                                      color: isUltimo
                                          ? Color(0xFFE85D04)
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    dataStr,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < _historico.length - 1)
                            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                        ],
                      );
                    }),
                  ),
            if (_mostrarFormCusto) _buildFormCusto(),
                ],
              ),
            ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _mostrarFormCusto = !_mostrarFormCusto),
                    icon: Icon(
                      _mostrarFormCusto ? Icons.close : Icons.edit_outlined,
                      size: 16,
                    ),
                    label: Text(_mostrarFormCusto ? 'Cancelar inserção' : 'Inserir preço manualmente'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primary)
                        .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom()
                        .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    child: const Text('Fechar'),
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

class _StatusBadgeEstoque extends StatelessWidget {
  final String status;
  const _StatusBadgeEstoque({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status) {
      case 'OK':
        bg = AppTheme.statusOk.withValues(alpha: 0.1);
        fg = AppTheme.statusOk;
      case 'LIMITE':
        bg = AppTheme.statusBaixo.withValues(alpha: 0.1);
        fg = AppTheme.statusBaixo;
      case 'CRITICO':
        bg = AppTheme.statusCritico.withValues(alpha: 0.1);
        fg = AppTheme.statusCritico;
      default:
        bg = Theme.of(context).colorScheme.surfaceContainerHighest;
        fg = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status,
        softWrap: false,
        overflow: TextOverflow.visible,
        maxLines: 1,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}