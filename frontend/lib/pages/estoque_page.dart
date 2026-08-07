import 'dart:async';
import 'dart:io';
import 'historico_material_page.dart';
import 'orcamento_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/material_model.dart';
import '../providers/material_provider.dart';
import '../providers/orcamento_provider.dart';
import '../providers/produto_provider.dart';
import '../providers/orcamento_venda_provider.dart';
import '../providers/alertas_estoque_provider.dart';
import '../providers/usuario_provider.dart';
import '../repositories/estoque_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/escolher_usuario_chat_dialog.dart';
import '../providers/robo_helper_provider.dart';

// ── Formatação de preço: até 6 casas decimais, sem zeros à direita ────────────

/// Formata a unidade para exibição (o valor interno permanece em maiúsculo,
/// usado para comparações/enum). Ex.: 'UNIDADE' → 'Unidade'; 'M' → 'm';
/// 'M/L' → 'm/l'; 'ML' → 'ml'; 'M²' → 'm²'; 'KG' → 'Kg'; 'G' → 'g'.
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

/// Monta o label dinâmico do campo/coluna de preço por unidade de medida,
/// ex.: 'Preço m/l', 'Preço g', 'Preço ml'. Quando a unidade não é
/// conhecida, cai de volta em 'Preço unidade'.
String labelPrecoUnidade(String? unidade) {
  final u = formatarUnidadeExibicao(unidade);
  if (u == '—' || u.isEmpty) return 'Preço unidade';
  return 'Preço $u';
}

/// Indica se o campo/coluna de preço por unidade de medida faz sentido para
/// este material. Quando a unidade já é "Unidade", o campo seria redundante
/// com o "Valor"/"Unit." comum, então não deve aparecer.
bool deveExibirPrecoUnidade(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return false;
  return unidade.trim().toUpperCase() != 'UNIDADE';
}

/// TextEditingController que expõe [notify] publicamente. `notifyListeners()`
/// é `@protected` em `ChangeNotifier`, então não pode ser chamado de fora da
/// própria classe/subclasse — usamos essa subclasse só para forçar o
/// RawAutocomplete a reavaliar as opções ao focar o campo vazio.
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
    // Remove vírgulas antes de qualquer outra transformação
    final semVirgula = newValue.text.replaceAll(',', '');
    final texto = _removerAcentos(semVirgula).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset:  newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

/// Formatter para os campos Medida e Espessura (cadastro e filtro/busca):
/// - remove acentuação e força minúsculas
/// - converte vírgula em ponto
/// - permite apenas 1 ponto POR NÚMERO (bloqueia pontos repetidos/seguidos
///   dentro do mesmo número, ex.: "1..5" ou "1.2.3"), mas preserva múltiplos
///   números na mesma medida, ex.: "2.44x1.22m" (dois números, um ponto cada)
class _MedidaEspessuraFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1) Vírgula -> ponto
    var texto = newValue.text.replaceAll(',', '.');

    // 2) Remove acentos e força minúsculas
    texto = _UpperCaseFormatter._removerAcentos(texto).toLowerCase();

    // 3) Para cada bloco de dígitos+pontos (um "número"), permite apenas o
    //    primeiro ponto e remove os demais. Não mexe no que não é dígito/ponto
    //    (letras, "x", espaços, etc.), preservando a separação entre números.
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

/// Formatter para o campo Medida no modo Retalho: só permite dígitos e um
/// único ponto decimal (vírgula é convertida em ponto) antes do sufixo fixo
/// "m²", que é sempre mantido ao final e não pode ser apagado nem editado
/// pelo usuário — o texto digitado sempre entra à esquerda do "m²".
class _MedidaRetalhoFormatter extends TextInputFormatter {
  static const String sufixo = 'm²';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text;

    // Remove o sufixo (onde quer que esteja) para trabalhar só com a parte
    // numérica digitada pelo usuário.
    texto = texto.replaceAll(sufixo, '');

    // Vírgula -> ponto
    texto = texto.replaceAll(',', '.');

    // Mantém apenas dígitos e ponto
    texto = texto.replaceAll(RegExp(r'[^\d.]'), '');

    // Permite apenas 1 ponto decimal
    final partes = texto.split('.');
    if (partes.length > 2) {
      texto = '${partes[0]}.${partes.sublist(1).join('')}';
    }

    final novoTexto = '$texto$sufixo';

    // Cursor sempre logo após a parte numérica digitada (nunca dentro ou
    // depois do sufixo).
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

/// Formatter para o campo Espessura: aceita apenas dígitos, ponto e vírgula
/// (vírgula é convertida em ponto), bloqueando letras e qualquer outro
/// caractere. Também permite apenas 1 ponto no total (evita "2..5"/"2.5.5").
class _EspessuraFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1) Vírgula -> ponto
    var texto = newValue.text.replaceAll(',', '.');

    // 2) Remove tudo que não for dígito ou ponto (bloqueia letras, "mm", etc.)
    texto = texto.replaceAll(RegExp(r'[^\d.]'), '');

    // 3) Permite apenas o primeiro ponto
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

/// Formatter para campos de preço em BRL: aplica separador de milhar (ponto)
/// na parte inteira em tempo real enquanto o usuário digita, usando vírgula
/// como separador decimal (padrão brasileiro). Ex.: digitar "1000" exibe
/// "1.000"; digitar "1000,5" exibe "1.000,5".
///
/// O texto exposto ao controller já vem SEM separador de milhar (apenas
/// dígitos + ponto decimal, ex.: "1000.5") para não quebrar `double.parse`
/// no restante do código — a exibição com milhar é feita só visualmente
/// através do `TextEditingValue` retornado aqui.
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

    // Conta quantos caracteres "digitados" (dígitos/vírgula) existiam antes
    // do cursor no valor novo, para poder recolocar o cursor no lugar certo
    // depois de re-formatar.
    final cursorPos = newValue.selection.end.clamp(0, texto.length);
    final antesDoCursor = texto.substring(0, cursorPos);
    final digitosAntesCursor =
        antesDoCursor.replaceAll(RegExp(r'[^\d,]'), '').length;

    // Aceita apenas dígitos e vírgula (o ponto de milhar é recalculado, não
    // digitado pelo usuário).
    texto = texto.replaceAll(RegExp(r'[^\d,]'), '');

    final partes = texto.split(',');
    String inteiro = partes[0];
    String? decimais = partes.length > 1 ? partes.sublist(1).join('') : null;
    if (decimais != null && decimais.length > 2) {
      decimais = decimais.substring(0, 2);
    }

    // Remove zeros à esquerda supérfluos, mantendo pelo menos um dígito.
    inteiro = inteiro.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    final inteiroFormatado = _aplicarMilhar(inteiro);
    final textoFormatado = decimais != null
        ? '$inteiroFormatado,$decimais'
        : (texto.contains(',') ? '$inteiroFormatado,' : inteiroFormatado);

    // Reposiciona o cursor: conta dígitos+vírgula até atingir a mesma
    // quantidade que havia antes do cursor original, pulando os pontos de
    // milhar (que não contam como "digitados" pelo usuário).
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

/// Converte o texto de um campo formatado com [_PrecoInputFormatter]
/// (ex.: "1.000,50") para um double (1000.5), para uso em cálculos/envio
/// ao backend.
double? _parsePreco(String texto) {
  final v = texto.trim();
  if (v.isEmpty) return null;
  final semMilhar = v.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(semMilhar);
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Converte exceções técnicas de rede em mensagens legíveis pelo usuário.
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
  // Remove prefixos técnicos
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

// ─────────────────────────────────────────────────────────────────────────────
// TELA PRINCIPAL: busca + grade de categorias + tabela inline
// ─────────────────────────────────────────────────────────────────────────────

// Sentinel para cards especiais
const _kCategoriaGeral       = '__GERAL__';
const _kCategoriaSemCategoria = '__SEM_CATEGORIA__';

class EstoquePage extends StatefulWidget {
  final String roleUsuario;
  const EstoquePage({super.key, required this.roleUsuario});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  // ── Filtro de categorias ───────────────────────────────────────────────────
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria    = '';

  // ── Pontos de interesse para o tour guiado do robô assistente ───────────
  // ("Como selecionar uma categoria"): card "Geral" → card de categoria
  // específica → campo de busca.
  final _tourKeyCardGeral       = GlobalKey();
  final _tourKeyCardEspecifica  = GlobalKey();
  final _tourKeyCampoBusca      = GlobalKey();

  /// Registra no RoboHelperProvider a(s) opção(ões) de ajuda contextual
  /// desta página. Chamado sempre que o build ocorre com as categorias já
  /// carregadas (as keys do tour só existem depois que os cards estão na
  /// árvore). Repetir o registro em cada build é barato (é só uma
  /// atribuição de lista) e garante que a opção sempre aponte para as
  /// keys corretas mesmo se a página for reconstruída.
  void _registrarAjudaRobo() {
    // A página de categorias continua "montada" (só escondida) quando o
    // usuário navega pra dentro de uma categoria, histórico, etc. (o
    // Navigator.push é interno, não muda a rota do GoRouter). Se ela
    // rebuildar em segundo plano nesse estado (por causa de outro
    // provider notificando, por exemplo), NÃO deve re-registrar a dica —
    // senão ela reaparece por cima da tela que empurramos, mesmo depois
    // de já termos limpado antes do push.
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
              // Limpa o campo de busca de categorias antes do tour: se
              // houver um filtro digitado (ex.: "AA"), os cards podem
              // estar todos escondidos ("Nenhuma categoria encontrada"),
              // e o robô não teria nada para destacar.
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

  // ── Ícones e cores ─────────────────────────────────────────────────────────
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
    // Evita que o robô continue oferecendo "Como selecionar uma
    // categoria?" em outra página depois que o usuário sai do Estoque.
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
    // Geral e Sem categoria não possuem tela de identificadores —
    // navegam diretamente para a listagem de materiais.
    final pularIdentificadores =
        categoriaId == _kCategoriaGeral ||
        categoriaId == _kCategoriaSemCategoria;

    // A dica de "como selecionar uma categoria" só faz sentido na própria
    // lista de categorias. Como esta navegação é um Navigator.push interno
    // (a rota do GoRouter continua sendo '/estoque' o tempo todo), o
    // provider nunca é avisado de que "saímos" da lista — por isso
    // limpamos aqui manualmente. Ao voltar, carregarCategorias() (chamado
    // no .then abaixo) reconstrói a lista e re-registra a dica sozinho.
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
      // Recarrega categorias ao voltar (pode ter sido criada/removida alguma)
      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  /// Abre a listagem de materiais direto na categoria do material informado,
  /// já com nome/identificador/medida/espessura preenchidos — usado quando a
  /// página é aberta a partir do MaterialCriticoBanner (SSE 'material_critico').
  /// Pula a tela de identificadores porque já sabemos exatamente qual é.
  void _abrirParaNotificacaoCritica(MaterialCriticoNotificacao n) {
    final temCategoria = n.categoria != null && n.categoria!.trim().isNotEmpty;
    final categoriaId    = temCategoria ? n.categoria! : _kCategoriaSemCategoria;
    final categoriaLabel = temCategoria ? n.categoria! : 'Sem categoria';
    final temIdentificador =
        n.identificador != null && n.identificador!.trim().isNotEmpty;

    context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');

    Navigator.of(context).push(
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
    ).then((_) {
      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  /// Abre a listagem de materiais direto na categoria do material informado,
  /// já com nome/identificador/medida/espessura preenchidos — usado quando o
  /// usuário toca no card de um material "solto" encaminhado no chat (ver
  /// EncaminhamentoChatCard). Mesmo comportamento de
  /// `_abrirParaNotificacaoCritica`, mas a partir de um FiltroMaterialChat.
  Future<void> _abrirParaFiltroChat(FiltroMaterialChat f) async {
    // O card de encaminhamento guarda um "retrato" dos dados do material no
    // momento do envio (nome/identificador/medida/espessura/categoria). Se o
    // material for editado depois, esse retrato fica desatualizado e filtrar
    // por ele pode não encontrar mais o material (ou encontrar o errado).
    // Por isso, quando temos o materialId (mensagens encaminhadas após essa
    // correção), buscamos os dados atuais do material antes de montar os
    // filtros — só caindo para o retrato antigo se a busca falhar (ex.:
    // material excluído, ou mensagem antiga sem materialId).
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

    // Sempre abre na aba "Geral" (todas as categorias misturadas) em vez de
    // tentar acertar a categoria específica do material: nem sempre bate
    // exatamente com o categoriaId esperado, e como os demais filtros
    // (busca/identificador/medida/espessura) já são suficientes para achar
    // o material certo, não há necessidade de acertar a categoria de
    // antemão.
    final identificadorTrim = identificador?.trim();
    final temIdentificador = identificadorTrim != null && identificadorTrim.isNotEmpty;

    // Remove todas as rotas empilhadas acima da EstoquePage raiz antes de
    // empilhar a nova página filtrada. Sem isso, cada clique num material
    // encaminhado no chat empilhava mais uma EstoqueCategoriaPage por cima
    // da anterior — o botão "Categorias" só desempilhava um nível por vez,
    // então voltava para o material clicado antes, e não para a lista de
    // categorias, até desempilhar todas de uma por uma.
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

  /// Abre a listagem "Geral" (todas as categorias) já filtrada por status —
  /// usado quando a página é aberta a partir do diálogo de Alertas de
  /// Estoque, clicando em "Ir para Estoque".
  void _abrirGeralComStatus(String status) {
    context.read<RoboHelperProvider>().encerrarTour();
    context.read<RoboHelperProvider>().limparOpcoes('/estoque');
    Navigator.of(context).push(
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
    ).then((_) {
      if (mounted) context.read<MaterialProvider>().carregarCategorias();
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── Navegação pendente vinda do MaterialCriticoBanner ────────────────────
    // Ao tocar no banner, o AppShell guarda os dados do material no
    // MaterialProvider e navega para /estoque. Aqui detectamos isso e abrimos
    // automaticamente a categoria certa já filtrada.
    final filtroPendente =
        context.watch<MaterialProvider>().filtroNavegacaoPendente;
    if (filtroPendente != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MaterialProvider>().consumirFiltroNavegacaoPendente();
        _abrirParaNotificacaoCritica(filtroPendente);
      });
    }

    // ── Navegação pendente vinda do diálogo "Alertas de Estoque" ─────────────
    // Ao clicar em "Ir para Estoque" no diálogo aberto pelo sino de
    // notificações, o AppShell guarda o status desejado (ex.: 'CRITICO') no
    // MaterialProvider e navega para /estoque. Aqui abrimos a tela "Geral"
    // já com esse status ativo no filtro.
    final statusPendente =
        context.watch<MaterialProvider>().filtroStatusPendente;
    if (statusPendente != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MaterialProvider>().consumirFiltroStatusPendente();
        _abrirGeralComStatus(statusPendente);
      });
    }

    // ── Navegação pendente vinda de um encaminhamento de material no chat ───
    // Ao tocar no card de um material "solto" encaminhado no chat, o
    // MaterialProvider guarda os dados do material para abrirmos a
    // categoria certa já filtrada, assim que esta página ficar visível.
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
            // ── Cabeçalho ──────────────────────────────────────────────────
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

            // ── Banner de alertas de estoque ───────────────────────────────
            Consumer<AlertasEstoqueProvider>(
              builder: (_, alertasProv, __) {
                if (alertasProv.totalAlertas == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _AlertasBannerEstoque(provider: alertasProv),
                );
              },
            ),

            // ── Campo de busca de categorias ───────────────────────────────
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

            // ── Grid de categorias ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Consumer<MaterialProvider>(
                  builder: (_, provider, __) {
                    if (provider.carregando) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                      );
                    }

                    if (provider.erro != null) {
                      // A mensagem vem como "Erro ao carregar categorias: Verifique..."
                      // Extrai só a parte após o primeiro ": " para evitar duplicação.
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

                    // Só exibe os cards se o servidor respondeu com sucesso
                    // pelo menos uma vez. Evita mostrar "Geral" e "Sem categoria"
                    // com o servidor offline (quando categorias ainda não foram carregadas).
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

                    // Índice do primeiro card a ser exibido (após filtro),
                    // usado para saber qual é o "primeiro" (card Geral, se
                    // visível) e o "segundo" (a próxima opção logo depois),
                    // que são os dois pontos do tour de ajuda do robô.
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

                    // Só depois que os cards e o campo de busca já foram
                    // descritos é que registramos a opção de ajuda do robô
                    // (as GlobalKeys precisam estar associadas a widgets
                    // que serão de fato montados neste frame).
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
                      crossAxisCount:   4,
                      crossAxisSpacing: 16,
                      mainAxisSpacing:  16,
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

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG DE SELEÇÃO DE STATUS PARA EXPORTAR PDF
// ─────────────────────────────────────────────────────────────────────────────

class _ExportarPdfDialog extends StatefulWidget {
  final bool         mostrarSeletorCategoria;
  final List<String> categorias;
  final String       categoriaInicial;

  const _ExportarPdfDialog({
    this.mostrarSeletorCategoria = false,
    this.categorias = const [],
    this.categoriaInicial = '',
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
      title: const Row(
        children: [
          Icon(Icons.picture_as_pdf, color: AppTheme.primary, size: 22),
          SizedBox(width: 10),
          Text('Exportar PDF de Estoque'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.mostrarSeletorCategoria) ...[
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
              const SizedBox(height: 18),
            ],
            Text(
              'Selecione quais materiais deseja incluir no relatório:',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ..._opcoes.map((opcao) {
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
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: TextButton.styleFrom()
              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
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
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE IDENTIFICADORES (nível 2 da hierarquia: categoria → identificador)
// ─────────────────────────────────────────────────────────────────────────────

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

  // ── Pontos de interesse para o tour guiado do robô assistente ───────────
  // ("Como selecionar um identificador"): card "Todos" → card de
  // identificador específico.
  final _tourKeyCardTodos      = GlobalKey();
  final _tourKeyCardEspecifico = GlobalKey();

  /// Registra no RoboHelperProvider a dica desta página. Chamado a cada
  /// build (é barato) para garantir que aponte para as keys corretas mesmo
  /// após reconstruções — seguindo o mesmo padrão de EstoquePage.
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

  // ── Helpers de ícone / cor para identificadores ──────────────────────────
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
    // Evita que o robô continue oferecendo "Como selecionar um
    // identificador?" em outra página depois que o usuário sai daqui.
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
      // buscarSugestoes não filtra por categoria; fazemos aqui no client:
      // Melhor usar o repo diretamente via provider.carregar e capturar o resultado.
      // Mas como não temos acesso direto, usamos o provider normalmente.
      if (!mounted) return;
      // Carrega tudo da categoria no provider para extrair identificadores
      await context.read<MaterialProvider>().carregar(
        categoria: _categoriaParaProvider(),
      );
      if (!mounted) return;
      setState(() {
        _materiais = context.read<MaterialProvider>().materiais;
        _carregando = false;
      });
      // Registra a dica só depois que os identificadores foram carregados —
      // é quando os cards (e suas GlobalKeys) já existem na árvore.
      if (mounted) _registrarAjudaRobo();
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Extrai identificadores únicos dos materiais (null → sem identificador).
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
    // A dica "Como selecionar um identificador" só faz sentido nesta
    // própria página — limpamos antes de navegar para dentro dela.
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
            // ── Cabeçalho ────────────────────────────────────────────────────
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

            // ── Campo de busca ────────────────────────────────────────────────
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

            // ── Grid de identificadores ───────────────────────────────────────
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

    // Card "Todos"
    if (corresponde('todos')) {
      cards.add(_IdentificadorCard(
        key:         _tourKeyCardTodos,
        label:       'Todos',
        quantidade:  _materiais.length,
        cor:         widget.cor,
        icone:       Icons.grid_view_rounded,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   _kIdentificadorTodos,
          identificadorReal: null, // sem filtro de identificador
        ),
      ));
    }

    // Identificadores reais
    for (int i = 0; i < identificadores.length; i++) {
      final ident = identificadores[i];
      final label = ident ?? 'Sem identificador';
      if (!corresponde(label)) continue;
      final cor = ident == null
          ? const Color(0xFF546E7A)
          : _cores[i % _cores.length];
      // Só o primeiro card de identificador específico ganha a tour key
      // (é o único destacado nesta parada da dica).
      final ehPrimeiro = cards.length == (corresponde('todos') ? 1 : 0);
      cards.add(_IdentificadorCard(
        key:         ehPrimeiro ? _tourKeyCardEspecifico : null,
        label:       label,
        quantidade:  _contarMateriais(ident),
        cor:         cor,
        icone:       ident == null ? Icons.help_outline : Icons.qr_code,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   ident ?? _kIdentificadorSemIdentificador,
          identificadorReal: ident, // null = sem identificador
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
      child: GridView.count(
        crossAxisCount:   4,
        crossAxisSpacing: 16,
        mainAxisSpacing:  16,
        childAspectRatio: 1.0,
        shrinkWrap:       true,
        physics:          const NeverScrollableScrollPhysics(),
        children:         cards,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD DE IDENTIFICADOR
// ─────────────────────────────────────────────────────────────────────────────

// ── Botão "voltar" com hover, cursor de mão e tooltip ───────────────────────
// Usado no cabeçalho das páginas de identificadores/materiais para voltar
// à tela anterior (categorias ou identificadores).
class _BotaoVoltar extends StatefulWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _BotaoVoltar({
    required this.label,
    required this.tooltip,
    required this.onTap,
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
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.primary.withValues(alpha: 0.08),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: _hovered ? 0.9 : 0.5),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
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
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icone, color: widget.cor, size: 28),
              ),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ativo ? widget.cor : Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${widget.quantidade} ${widget.quantidade == 1 ? "material" : "materiais"}',
                style: TextStyle(
                  fontSize: 11,
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

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE MATERIAIS POR CATEGORIA
// ─────────────────────────────────────────────────────────────────────────────

/// Chaves usadas pelo tour "Como cadastrar um material?" pra destacar cada
/// campo do dialog de cadastro. Ficam guardadas na página (não no dialog em
/// si), porque o dialog é recriado do zero toda vez que é aberto, mas o tour
/// referencia essas chaves antes mesmo do dialog existir.
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

  /// True quando [key] é uma das keys deste formulário — usado pelo
  /// PopScope do dialog para distinguir um Esc/fechamento manual real (a
  /// parada do tour ainda está dentro deste formulário) de um pop
  /// disparado pelo próprio tour navegando "Anterior" para um passo fora
  /// dele (ex.: o botão "Novo Material" na página).
  bool contemParada(GlobalKey key) => [
        nome, identificador, categoria, unidade, medida, comprimento, largura,
        espessura, quantidade, estoqueMinimo, estoqueConfirmado,
      ].contains(key);
}

class EstoqueCategoriaPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String?  buscaInicial;
  /// Pré-preenchem os filtros de medida/espessura — usados quando a página é
  /// aberta a partir do MaterialCriticoBanner, que já sabe exatamente qual
  /// medida/espessura do material crítico.
  final String?  medidaInicial;
  final String?  espessuraInicial;
  /// Pré-preenche o filtro de status (ex.: 'CRITICO') — usado quando a
  /// página é aberta a partir do diálogo de Alertas de Estoque, clicando em
  /// "Ir para Estoque".
  final String?  statusInicial;
  /// Quando não-null, filtra automaticamente pelo identificador escolhido na
  /// página anterior (EstoqueIdentificadorPage). String vazia = sem identificador.
  /// null especial vindo de _kIdentificadorTodos = sem filtro de identificador.
  final String?  identificadorFiltro;
  /// Rótulo do identificador para exibir no breadcrumb (null = sem filtro).
  final String?  identificadorLabel;
  /// Se true, exibe breadcrumb de volta à tela de identificadores.
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

// ── Dropdown de categoria com busca embutida no próprio menu ────────────────
// Diferente de um DropdownButtonFormField comum: ao abrir, mostra um campo de
// texto no topo do próprio dropdown para filtrar a lista em tempo real. O
// controle fechado se parece com os demais filtros (label "Categoria" +
// valor selecionado).
class _CategoriaFiltroDropdown extends StatefulWidget {
  final List<String> categorias;
  final String valorSelecionado; // '' = TODAS
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
            // Recalculado a cada setMenuState (ex.: ao digitar na busca),
            // já que _busca pode ter mudado desde o último build externo.
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

// ── Dropdown de status (OK / LIMITE / CRITICO / INATIVO) ────────────────────
// Lista curta e fixa, então sem campo de busca — apenas um MenuAnchor simples
// com um indicador de cor por status, no mesmo padrão visual do
// _CategoriaFiltroDropdown.
class _StatusFiltroDropdown extends StatefulWidget {
  final MenuController menuController;
  final String valorSelecionado; // '' = TODOS
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

class _EstoqueCategoriaPageState extends State<EstoqueCategoriaPage> {
  late final TextEditingController _buscaCtrl;
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  final _larguraCtrl       = TextEditingController();
  final _comprimentoCtrl   = TextEditingController();
  String _statusFiltro         = '';
  String _categoriaFiltro      = ''; // só usado quando widget.categoriaId == _kCategoriaGeral
  bool   _somenteFornecedor    = false;
  Timer? _debounceTimer;
  final MenuController _statusMenuController = MenuController();

  // ── Ajuda do robô ────────────────────────────────────────────────────────
  final _tourKeyHistorico     = GlobalKey();
  final _tourKeyOrcar         = GlobalKey();
  final _tourKeyExportar      = GlobalKey();
  final _tourKeyNovoMaterial  = GlobalKey();
  // ── Ajuda do robô: busca/filtro de materiais ─────────────────────────────
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
  // true enquanto o dialog de "Novo Material" estiver aberto POR CAUSA do
  // tour — usado pra fechá-lo de novo se o usuário clicar "Anterior" e
  // voltar pro passo do botão (que fica escondido atrás do dialog).
  bool _dialogTourAberto = false;

  static const int _itensPorPagina = 50;
  int     _paginaAtual  = 0;
  String? _colunaOrdem;
  bool    _crescente    = true;

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral) {
      // Na página "Geral" (todas as categorias misturadas), o dropdown
      // de Categoria permite restringir a uma categoria específica sem
      // sair da tela; vazio = todas.
      return _categoriaFiltro.isEmpty ? null : _categoriaFiltro;
    }
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  @override
  void initState() {
    super.initState();
    _buscaCtrl = TextEditingController(text: widget.buscaInicial ?? '');
    // Pré-preenche o filtro de identificador vindo da página anterior
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
    super.dispose();
  }

  void _aplicarFiltros() {
    _carregarPaginaAtual(irParaPagina: 0);
  }

  /// Recarrega a página atual do servidor (mantém _paginaAtual, ordenação
  /// e filtros). Usar após editar/desativar/reativar/excluir um material.
  void _recarregarSemResetarPagina() {
    _carregarPaginaAtual(irParaPagina: _paginaAtual);
  }

  /// Busca a página [irParaPagina] do servidor já ordenada/filtrada.
  /// Se a página vier vazia mas ainda existirem itens (ex.: acabou de
  /// excluir o último item da última página), volta uma página.
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
      comFornecedor: _somenteFornecedor,
      pagina:        irParaPagina + 1, // backend é 1-indexado
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
    // A ordenação agora acontece no servidor — volta pra primeira página.
    _carregarPaginaAtual(irParaPagina: 0);
  }

  // ── Ações de material ──────────────────────────────────────────────────────

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

  /// Registra as dicas desta página (materiais de uma categoria) sob a
  /// mesma rota '/estoque'. Só escreve de fato se esta página for a rota
  /// visível no topo — evita que uma rebuild em segundo plano (ex.: esta
  /// tela escondida atrás do dialog "Novo Material" ou de "Histórico")
  /// sobrescreva as opções enquanto não é ela que está sendo mostrada.
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
              // Se estivermos voltando pra este passo (botão "Anterior"
              // vindo de dentro do dialog), fecha o dialog que o tour
              // tinha aberto — senão o botão fica escondido atrás dele.
              // IMPORTANTE: usa rootNavigator:true porque showDialog abre
              // no Navigator raiz; sem isso maybePop() poppa a rota da
              // página de estoque em vez do dialog.
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
                // Aguarda um frame para que o dialog comece a montar antes
                // de o provider tentar medir a key em destaque.
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
            key: () => _tourKeyOrcar,
            texto: 'Toque aqui para criar um orçamento com todos os '
                'materiais que estão filtrados nesta página agora.',
          ),
        ],
      ),
      RoboHelpOption(
        titulo: 'Como exportar o estoque para um PDF',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyExportar,
            texto: 'Toque aqui para exportar a lista de materiais '
                'filtrada em um arquivo PDF.',
          ),
        ],
      ),
    ]);
  }

  Future<void> _abrirFormMaterial([MaterialModel? material]) async {
    // Lê o role sempre do UsuarioProvider (fonte da verdade), e não de
    // widget.roleUsuario: esta página pode ter sido aberta via
    // Navigator.push antes de uma troca de usuário ("Trocar para"), e nesse
    // caso o valor recebido no construtor fica desatualizado — o
    // Navigator.push não reconstrói a página quando o usuário muda.
    final roleAtual = context.read<UsuarioProvider>().usuarioLogado?.role;
    final isCompras = roleAtual == 'COMPRAS';
    final salvou = await showDialog(
      context: context,
      // true: precisa estar habilitado para que o Esc e o clique fora do
      // barrier disparem uma tentativa de fechamento — é essa tentativa que
      // o PopScope dentro de _MaterialFormDialog intercepta (canPop: false)
      // para decidir se confirma alterações não salvas antes de fechar.
      // Se ficasse false, o Flutter nem chegaria a acionar o PopScope.
      //
      // Exceção: enquanto o tour do robô estiver guiando este formulário,
      // o balão de dica fica fora do dialog (numa camada abaixo dele), e
      // qualquer clique do usuário tentando interagir com a dica cairia
      // no barrier e fecharia o formulário sem querer. Por isso, nesse
      // caso o barrier fica não-dismissible — só X/Cancelar/Esc fecham.
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

    // ── 1. Pedir ao usuário qual status (e, na tela Geral, qual categoria) ──
    final escolha = await showDialog<({String status, String categoria})>(
      context: context,
      builder: (ctx) {
        return _ExportarPdfDialog(
          mostrarSeletorCategoria: mostrarSeletorCategoria,
          categorias:              context.read<MaterialProvider>().categorias,
          categoriaInicial:        _categoriaFiltro,
        );
      },
    );
    if (escolha == null) return; // cancelou

    // ── 2. Mostrar progresso ────────────────────────────────────────────────
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 3),
        backgroundColor: AppTheme.primary,
      ),
    );

    // Na tela "Geral", a categoria vem da escolha feita no diálogo
    // (pré-preenchida com o filtro já aplicado na tela, mas o usuário
    // pode trocar sem precisar sair do diálogo). Nas demais telas, a
    // categoria já é fixa (a da própria página).
    final String? catParam = mostrarSeletorCategoria
        ? (escolha.categoria.isEmpty ? null : escolha.categoria)
        : widget.categoriaId == _kCategoriaSemCategoria
            ? ''
            : widget.categoriaId;

    // 'TODOS' → não passa status (backend interpreta como sem filtro)
    final String? statusParam =
        escolha.status == 'TODOS' ? null : escolha.status;

    try {
      final bytes = await EstoqueRepository().baixarPdf(
        categoria: catParam,
        status:    statusParam,
      );

      // Valida que a resposta é realmente um PDF
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
        // 'start' abre com o programa padrão associado ao .pdf no Windows
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

  // ── Orçar materiais filtrados ──────────────────────────────────────────────
  Future<void> _orcarFiltrados() async {
    final provider = context.read<MaterialProvider>();

    // Confirmação antes de disparar a busca completa + navegação: usa a
    // contagem já calculada pelo servidor para a página atual (mesma exibida
    // no botão "Orçar filtrados (X)"), sem precisar buscar a lista inteira
    // só pra mostrar o número no dialog.
    final totalFiltrado = provider.totalItensPagina;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Orçar materiais filtrados'),
        content: Text(
          'Deseja orçar os $totalFiltrado material${totalFiltrado == 1 ? '' : 'is'} filtrado${totalFiltrado == 1 ? '' : 's'}?',
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
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Orçar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    // Esta função só roda sob demanda (clique em "Orçar filtrados"), então
    // busca a lista completa que bate no filtro atual aqui — a tela em si
    // usa carregarPaginado() e não mantém mais a tabela inteira em memória.
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
    final materiais = _somenteFornecedor
        ? todos.where((m) => m.fornecedorMateriais.isNotEmpty).toList()
        : todos;
    if (materiais.isEmpty) return;

    // Monta os itens para o orçamento com os dados de preço de cada material
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

    // Monta um título descritivo baseado nos filtros ativos
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

    // Ao entrar em /orcamento, abre direto no editor (aba "abertos") com
    // este orçamento recém-criado, em vez da lista de aprovação.
    OrcamentoPage.abrirEditorAoEntrar = true;
    context.go('/orcamento');
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
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
            // ── Cabeçalho com botão voltar ──────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Botão voltar
                _BotaoVoltar(
                  label: widget.mostrarBotaoIdentificadores
                      ? widget.categoriaLabel
                      : 'Categorias',
                  tooltip: widget.mostrarBotaoIdentificadores
                      ? 'Voltar para ${widget.categoriaLabel}'
                      : 'Voltar para categorias',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 16),
                // Ícone da categoria
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Breadcrumb: Categoria › Identificador (se veio da tela de identificadores)
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
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Materiais desta categoria',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                // Botões de ação — Wrap evita overflow quando a janela estreita
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      key: _tourKeyHistorico,
                      child: Tooltip(
                      message: 'Ver histórico de movimentações do estoque',
                      child: OutlinedButton.icon(
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
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('Histórico'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                      ),
                    ),
                    Container(
                      key: _tourKeyOrcar,
                      child: Consumer<MaterialProvider>(
                      builder: (_, mp, __) {
                        // O contador usa o total já calculado no servidor pela
                        // página atual (respeita busca/status/comFornecedor).
                        // A lista completa só é buscada de fato ao clicar,
                        // dentro de _orcarFiltrados — não fica pré-carregada.
                        final total = mp.totalItensPagina;
                        final temMateriais = !mp.carregandoPagina && total > 0;
                        return Tooltip(
                          message: temMateriais
                              ? 'Criar orçamento com os $total material(is) filtrado(s)'
                              : 'Nenhum material filtrado',
                          child: OutlinedButton.icon(
                            onPressed: temMateriais ? _orcarFiltrados : null,
                            icon: const Icon(Icons.request_quote, size: 18),
                            label: Text(
                              temMateriais
                                  ? 'Orçar filtrados ($total)'
                                  : 'Orçar filtrados',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Color(0xFF1E88E5),
                              side: BorderSide(
                                color: temMateriais
                                    ? Color(0xFF1E88E5)
                                    : Theme.of(context).colorScheme.outline,
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ).copyWith(
                              mouseCursor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.disabled)
                                    ? SystemMouseCursors.forbidden
                                    : SystemMouseCursors.click,
                              ),
                            ),
                          ),
                        );
                      },
                      ),
                    ),
                    Container(
                      key: _tourKeyExportar,
                      child: Tooltip(
                      message: 'Exportar lista de materiais em PDF',
                      child: OutlinedButton.icon(
                        onPressed: _exportarPdf,
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        label: const Text('Exportar Estoque (PDF)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE85D04),
                          side: const BorderSide(color: Color(0xFFE85D04)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                      ),
                    ),
                    Container(
                      key: _tourKeyNovoMaterial,
                      child: Tooltip(
                      message: 'Cadastrar novo material no estoque',
                      child: FilledButton.icon(
                        onPressed: () => _abrirFormMaterial(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Novo Material'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                      ),
                    ),
                    IconButton(
                      onPressed: _aplicarFiltros,
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
            SizedBox(height: 20),

            // ── Filtros linha 1 ────────────────────────────────────────────
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
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
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
                        // Garante que o valor selecionado ainda exista na lista
                        // (ex.: categoria removida enquanto o filtro estava ativo).
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
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Tooltip(
                    message: 'Mostrar somente materiais com fornecedor vinculado',
                    child: FilterChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  label: Text('Com fornecedor'),
                  avatar: Icon(
                    Icons.store_outlined,
                    size: 16,
                    color: _somenteFornecedor ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                  ),
                  selected: _somenteFornecedor,
                  onSelected: (v) {
                    setState(() => _somenteFornecedor = v);
                    _aplicarFiltros();
                  },
                  selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                  checkmarkColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: _somenteFornecedor ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: _somenteFornecedor ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: _somenteFornecedor
                        ? AppTheme.primary
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                  ),
                  ),
                  ),
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
                        _somenteFornecedor;
                    return IconButton.outlined(
                      tooltip: 'Limpar filtros',
                      icon: Icon(Icons.filter_alt_off, color: scheme.onSurfaceVariant),
                      onPressed: temFiltro
                          ? () {
                              _buscaCtrl.clear();
                              _identificadorCtrl.clear();
                              _medidaCtrl.clear();
                              _espessuraCtrl.clear();
                              _larguraCtrl.clear();
                              _comprimentoCtrl.clear();
                              setState(() {
                                _statusFiltro      = '';
                                _categoriaFiltro   = '';
                                _somenteFornecedor = false;
                              });
                              _aplicarFiltros();
                            }
                          : null,
                      style: IconButton.styleFrom(
                        side: BorderSide(color: Theme.of(context).colorScheme.outline),
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

            // ── Filtros linha 2 ────────────────────────────────────────────
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
                      suffixText: 'm',
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
                      suffixText: 'm',
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
                      suffixText: 'mm',
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

            // ── Tabela ─────────────────────────────────────────────────────
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
                            _somenteFornecedor
                                ? 'Nenhum material com fornecedor vinculado'
                                : 'Nenhum material encontrado',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _somenteFornecedor
                                ? 'Desative o filtro "Com fornecedor" para ver todos.'
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

                  final mostrarCat = widget.categoriaId != _kCategoriaGeral;
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

// Dados de um card especial (Geral / Sem categoria)
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

// ─────────────────────────────────────────────────────────────────────────────
// CARD COMPACTO DE CATEGORIA (horizontal scroll)
// ─────────────────────────────────────────────────────────────────────────────

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
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: widget.cor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icone, color: widget.cor, size: 28),
              ),
              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  widget.categoria,
                  style: TextStyle(
                    fontSize: 13,
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border(
          left: BorderSide(color: color, width: 3),
          bottom: BorderSide(color: color.withValues(alpha: 0.2), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
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
    _ColDef(label: 'Preço',                       flex: 0.9,  minWidth: 170, sortKey: 'ultimoValorPago'),
    _ColDef(label: 'Preço m²',                    flex: 0.9,  minWidth: 180, sortKey: 'ultimoValorPagoM2'),
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
    final confirmados = widget.materiais.where((m) =>  m.estoqueConfirmado).toList();
    final naoConfirm  = widget.materiais.where((m) => !m.estoqueConfirmado).toList();

    // Corpo rolável (sem o cabeçalho — ele fica fixo acima)
    Widget corpoRolavel = SingleChildScrollView(
      controller: _scrollCtrl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SectionHeader(
            icon:  Icons.pending_outlined,
            label: 'Aguardando confirmação de estoque',
            count: naoConfirm.length,
            color: AppTheme.warning,
          ),
          if (naoConfirm.isEmpty)
            _EmptySection(message: 'Nenhum material pendente de confirmação.')
          else ...[
            for (int i = 0; i < naoConfirm.length; i++) ...[
              if (i > 0)
                Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
              _LinhaMateria(
                material:             naoConfirm[i],
                cols:                 _cols,
                onEditar:             widget.onEditar,
                onVerFornecedores:    widget.onVerFornecedores,
                onVerHistoricoPrecos: widget.onVerHistoricoPrecos,
                mostrarCategoria:     widget.mostrarCategoria,
              ),
            ],
            Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
          ],

          const SizedBox(height: 24),

          _SectionHeader(
            icon:  Icons.verified_outlined,
            label: 'Estoque confirmado',
            count: confirmados.length,
            color: AppTheme.success,
          ),
          if (confirmados.isEmpty)
            _EmptySection(message: 'Nenhum material com estoque confirmado.')
          else ...[
            for (int i = 0; i < confirmados.length; i++) ...[
              if (i > 0)
                Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
              _LinhaMateria(
                material:             confirmados[i],
                cols:                 _cols,
                onEditar:             widget.onEditar,
                onVerFornecedores:    widget.onVerFornecedores,
                onVerHistoricoPrecos: widget.onVerHistoricoPrecos,
                mostrarCategoria:     widget.mostrarCategoria,
              ),
            ],
            Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
          ],
        ],
      ),
    );

    // A tabela sempre ocupa exatamente a largura disponível — as colunas
    // encolhem proporcionalmente (via Expanded/flex) e o texto que não
    // couber é cortado com reticências, em vez de forçar scroll horizontal.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho fixo — não entra no scroll vertical
        _cabecalho(),
        Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
        // Corpo rolável (verticalmente) ocupa o espaço restante
        Expanded(child: corpoRolavel),
      ],
    );
  }
}

class _ColDef {
  final String  label;
  final double? fixed;
  final double? flex;
  /// Largura mínima em pixels — garante que o texto da coluna (cabeçalho e
  /// células) nunca quebre em mais de uma linha nem seja cortado, mesmo em
  /// telas estreitas. Quando a soma das larguras mínimas ultrapassa a largura
  /// disponível, a tabela passa a rolar horizontalmente em vez de espremer
  /// as colunas.
  final double  minWidth;
  /// Identificador de ordenação; null = coluna não ordenável
  final String? sortKey;
  const _ColDef({
    required this.label,
    this.fixed,
    this.flex,
    this.minWidth = 90,
    this.sortKey,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CABEÇALHO ORDENÁVEL
// ─────────────────────────────────────────────────────────────────────────────

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
    // Layout idêntico ao cabeçalho original — só adiciona clique e ícone de seta
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
              // Ícone pequeno no canto superior direito, sem afetar o layout do texto
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
 
  // ── Linha principal (pai) ──────────────────────────────────────────────────
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
                // ID
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
 
                // Identificador
                _colWrap(cols[1], maybeOpacity(_cell(m.identificador ?? '—', context, inativo: inativo))),
                _vDivider(context),
 
                // Nome
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
 
                // Categoria (apenas em Geral / Sem categoria)
                if (widget.mostrarCategoria) ...[
                  _colWrap(cols[3], maybeOpacity(_cell(m.categoria ?? '—', context, inativo: inativo))),
                  _vDivider(context),
                ],
 
                // Medida
                _colWrap(cols[widget.mostrarCategoria ? 4 : 3], maybeOpacity(_cell(m.medida ?? '—', context, inativo: inativo))),
                _vDivider(context),
 
                // Espessura
                _colWrap(cols[widget.mostrarCategoria ? 5 : 4], maybeOpacity(_cell(m.espessura != null && m.espessura!.trim().isNotEmpty ? '${m.espessura!.trim().replaceAll(RegExp("mm\\s*\$", caseSensitive: false), '').trim()}mm' : '—', context, inativo: inativo))),
                _vDivider(context),
 
                // Comprimento
                _colWrap(cols[widget.mostrarCategoria ? 6 : 5], maybeOpacity(_cell(m.comprimento != null ? formatarQuantidade(m.comprimento!) : '—', context, inativo: inativo))),
                _vDivider(context),
 
                // Largura
                _colWrap(cols[widget.mostrarCategoria ? 7 : 6], maybeOpacity(_cell(m.largura != null ? formatarQuantidade(m.largura!) : '—', context, inativo: inativo))),
                _vDivider(context),
 
                // Estoque atual (com lógica especial para específico)
                _colWrap(cols[widget.mostrarCategoria ? 8 : 7], estoqueAtualCell()),
                _vDivider(context),
 
                // Estoque mínimo
                _colWrap(cols[widget.mostrarCategoria ? 9 : 8], maybeOpacity(_cell(
                  formatarQuantidadeExibicao(m.estoqueMinimo),
                  context,
                  inativo: inativo,
                ))),
                _vDivider(context),
 
                // Unidade
                _colWrap(cols[widget.mostrarCategoria ? 10 : 9], maybeOpacity(_cell(formatarUnidadeExibicao(m.unidade), context, inativo: inativo))),
                _vDivider(context),
 
                // Custo última compra
                _colWrap(cols[widget.mostrarCategoria ? 11 : 10], maybeOpacity(_CustoCell(
                  valor:       m.ultimoValorPago,
                  temHistorico: true,
                  onTap:       () => widget.onVerHistoricoPrecos(m),
                ))),
                _vDivider(context),
 
                // Custo m² última compra
                _colWrap(cols[widget.mostrarCategoria ? 12 : 11], maybeOpacity(_CustoCell(
                  valor:       m.ultimoValorPagoM2,
                  temHistorico: true,
                  onTap:       () => widget.onVerHistoricoPrecos(m),
                ))),
                _vDivider(context),
 
                // Status
                _colWrap(cols[widget.mostrarCategoria ? 13 : 12], maybeOpacity(Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: _StatusBadgeEstoque(status: m.status),
                  ),
                ))),

                // botão Histórico de audit por material
                _colWrap(
                  cols[widget.mostrarCategoria ? 14 : 13],
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


class _MaterialFormDialog extends StatefulWidget {
  final MaterialModel? material;
  final void Function(MaterialModel)? onDesativar;
  final void Function(MaterialModel)? onReativar;
  final void Function(MaterialModel)? onExcluir;
  final String? roleUsuario;
  /// Quando true, o formulário é exibido apenas para consulta: todos os
  /// campos ficam bloqueados e as ações de salvar/desativar/reativar/excluir
  /// ficam ocultas. Usado para permitir que o usuário COMPRAS visualize os
  /// dados de um material já cadastrado sem poder alterá-los.
  final bool somenteLeitura;
  /// Chaves opcionais usadas pelo tour de ajuda do robô, pra destacar cada
  /// campo deste formulário passo a passo. Null quando o dialog é aberto
  /// normalmente (fora do tour) — nesse caso as chaves simplesmente não
  /// fazem nada.
  final _MaterialFormTourKeys? tourKeys;
  const _MaterialFormDialog({this.material, this.onDesativar, this.onReativar, this.onExcluir, this.roleUsuario, this.somenteLeitura = false, this.tourKeys});

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog;

  // ── Fechamento automático quando o tour do robô termina ────────────────
  // Só relevante quando widget.tourKeys != null, ou seja, quando ESTE
  // dialog foi aberto pelo próprio tour (via aoEntrar do passo "Nome").
  // Nesse caso, quando o usuário concluir o tour (botão "Concluir" na
  // última parada) ou encerrá-lo de outra forma (Esc, X do robô), o
  // dialog deve fechar junto — sem isso ele ficaria aberto sozinho depois
  // do tour acabar. Guardamos a referência ao provider (não ao context)
  // pra poder remover o listener no dispose com segurança.
  RoboHelperProvider? _roboHelper;

  void _aoMudarRoboHelper() {
    // dispara só na transição tourAtivo:true → false, evitando fechar o
    // dialog no frame em que ele mesmo acabou de ser aberto pelo tour
    // (nesse momento tourAtivo já é true).
    if (widget.tourKeys != null &&
        !(_roboHelper?.tourAtivo ?? false) &&
        mounted) {
      Navigator.of(context).maybePop();
    }
  }

  // ── Detecção de possível material duplicado ───────────────────────────
  // Compara nome/identificador/medida/espessura digitados contra os
  // materiais já cadastrados (via busca no backend), avisando o usuário
  // antes de submeter — não bloqueia o salvamento, apenas alerta.
  Timer? _debounceDuplicata;
  bool _verificandoDuplicata = false;
  List<_PossivelDuplicata> _possiveisDuplicatas = [];

  // ── Modo Retalho (apenas no cadastro de material novo) ────────────────
  bool _modoRetalho = false;
  bool _hoverRetalho = false;

  late final TextEditingController _nome;
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
  late bool _estoqueConfirmado;
  bool _fornecedoresExpandido = false;

  /// COMPRAS não pode definir a quantidade no cadastro — a entrada de
  /// estoque deve ser feita pela página de Controle de Estoque (movimentação
  /// de ENTRADA vinculada a uma OS), garantindo rastreabilidade.
  /// Lê o role sempre do UsuarioProvider (fonte da verdade) em vez de
  /// widget.roleUsuario, que pode estar desatualizado se esta tela foi
  /// aberta antes de uma troca de usuário ("Trocar para").
  bool get _bloquearQuantidade =>
      (context.watch<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      !_editando;

  /// Mesma regra de [_bloquearQuantidade], mas usando `context.read` em vez
  /// de `context.watch`. Use esta versão fora do método build (por exemplo,
  /// dentro de handlers de evento como `_salvar`), já que `watch` só pode
  /// ser chamado durante a construção da árvore de widgets.
  bool get _bloquearQuantidadeAtual =>
      (context.read<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      !_editando;

  /// Mesma regra de [_bloquearEstoqueMinimo]: COMPRAS também não pode definir o
  /// estoque mínimo no cadastro — ambos ficam a cargo de quem faz a entrada
  /// real de estoque (Controle de Estoque / OS).
  bool get _bloquearEstoqueMinimo => _bloquearQuantidade;

  /// Versão `context.read` de [_bloquearEstoqueMinimo], para uso fora do build.
  bool get _bloquearEstoqueMinimoAtual => _bloquearQuantidadeAtual;

  /// COMPRAS, ao editar um material já existente, só pode alterar a
  /// Categoria e confirmar o Estoque — os demais campos (nome, identificador,
  /// unidade, medida, dimensões etc.) continuam bloqueados, pois seguem
  /// sendo de responsabilidade de quem cadastra/movimenta o material.
  /// Usa o mesmo padrão watch/read de [_bloquearQuantidade] pelos mesmos
  /// motivos (reagir a troca de usuário durante o build vs. em handlers).
  bool get _bloqueadoParaCompras =>
      (context.watch<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      _editando;

  bool get _bloqueadoParaComprasAtual =>
      (context.read<UsuarioProvider>().usuarioLogado?.role ?? widget.roleUsuario) ==
          'COMPRAS' &&
      _editando;

  /// Normaliza valores de unidade salvos com grafia antiga no banco de dados.
  /// Ex.: "M2" (sem símbolo Unicode) → "M²"
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
    return _aliasUnidade[norm] ?? norm; // preserva desconhecidos sem crash
  }

  /// Detecta se o texto contém a palavra "RETALHO" (ou variações próximas
  /// como "RETALHOS", "RETALH", "RETALHOO", "RETALHP" etc.) em qualquer
  /// palavra do texto. Usado para impedir que o usuário digite isso no campo
  /// Nome — retalhos devem ser identificados pelo campo Identificador, não
  /// pelo nome do material.
  ///
  /// A detecção usa distância de edição (Levenshtein) em vez de apenas uma
  /// regex exata, para pegar erros de digitação comuns (letra faltando,
  /// duplicada ou trocada), sem disparar em palavras muito diferentes.
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
    if (p.length < 5) return false; // evita falso-positivo em palavras curtas
    // Compara contra a raiz "RETALHO" e também contra "RETALHOS" (plural),
    // tolerando até 2 edições de diferença (insere/remove/troca letra).
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
    if (widget.tourKeys != null) {
      // addPostFrameCallback: evita ler o provider antes do primeiro frame
      // deste dialog terminar de montar (context ainda instável no meio
      // do initState), e garante que _roboHelper já reflita tourAtivo:true
      // (o passo "Nome" que abriu este dialog) antes de começarmos a
      // ouvir mudanças — senão o listener poderia disparar cedo demais.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _roboHelper = context.read<RoboHelperProvider>();
        _roboHelper!.addListener(_aoMudarRoboHelper);
      });
    }
    final m        = widget.material;
    _estoqueConfirmado = m?.estoqueConfirmado ?? false;
    _nome          = TextEditingController(text: m?.nome ?? '');
    _identificador = TextEditingController(text: m?.identificador ?? '');
    _unidade       = _normalizarUnidade(m?.unidade);
    // Se o material sendo editado já é um retalho (identificador "RETALHO"),
    // o formulário deve abrir com o modo Retalho já ativado.
    _modoRetalho   = (m?.identificador?.trim().toUpperCase() == _palavraRetalho);
    _categoria     = _NotifiableTextEditingController(text: m?.categoria ?? '');
    // Ao focar o campo vazio, força o RawAutocomplete a reavaliar as opções
    // (ele só reage a mudanças no texto do controller, não ao foco).
    _categoriaFocusNode.addListener(() {
      if (_categoriaFocusNode.hasFocus) {
        // Ao focar o campo (mesmo vazio), força o RawAutocomplete a
        // reavaliar as opções, para que a lista de categorias já apareça
        // antes mesmo do usuário digitar algo.
        _categoria.notify();
      }
    });
    // No modo Retalho o campo Medida sempre deve conter o sufixo fixo "m²";
    // se o material salvo já tiver um valor (ex.: "0.69m²"), preserva-o,
    // senão parte só do sufixo.
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

    // Campos que entram na comparação de duplicidade: qualquer alteração
    // reagenda a verificação (debounced).
    for (final c in [_nome, _identificador, _medida, _espessura, _largura, _comprimento]) {
      c.addListener(_agendarVerificacaoDuplicata);
    }
    // Roda uma verificação inicial (ex.: ao editar um material que já
    // tenha sido cadastrado em duplicidade por alguma falha anterior).
    WidgetsBinding.instance.addPostFrameCallback((_) => _agendarVerificacaoDuplicata());

    // ── Snapshot inicial para detectar alterações não salvas ──────────────
    // Usado para decidir se, ao tentar fechar o diálogo (X, "Cancelar",
    // clique fora ou tecla Esc), é preciso confirmar com o usuário antes de
    // descartar o que foi digitado.
    _snapshotInicial = _capturarEstadoAtual();
  }

  /// Estado "assinatura" de todos os campos editáveis do formulário, usado
  /// para comparar com o estado atual e saber se houve alguma alteração.
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
        _modoRetalho.toString(),
      ].join('␟');

  /// true se algum campo foi alterado em relação ao estado com que o
  /// diálogo foi aberto.
  bool get _temAlteracoesNaoSalvas => _capturarEstadoAtual() != _snapshotInicial;

  /// Verifica se há alterações não salvas e, em caso positivo, pergunta ao
  /// usuário se deseja descartá-las antes de fechar o diálogo. Retorna
  /// `true` quando o diálogo pode ser fechado (sem alterações, ou usuário
  /// confirmou o descarte / optou por salvar), e `false` quando o
  /// fechamento deve ser cancelado.
  Future<bool> _confirmarFechamento() async {
    if (widget.somenteLeitura || !_temAlteracoesNaoSalvas) return true;

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
            onPressed: () => Navigator.pop(context, 'continuar'),
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: Text(_editando ? 'Continuar editando' : 'Continuar cadastrando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'descartar'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'salvar'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: Text(_editando ? 'Salvar alterações' : 'Cadastrar'),
          ),
        ],
      ),
    );

    if (!mounted) return false;

    switch (resultado) {
      case 'descartar':
        return true;
      case 'salvar':
        // _salvar() já cuida de dar Navigator.pop(context, true) quando
        // a operação for concluída com sucesso; se falhar, o diálogo de
        // edição permanece aberto para o usuário corrigir/tentar de novo.
        await _salvar();
        return false;
      case 'continuar':
      default:
        return false;
    }
  }

  /// Tenta fechar o diálogo, passando pela confirmação de alterações não
  /// salvas quando necessário. Usado pelo botão "X", pelo botão
  /// "Cancelar"/"Fechar" e pelo PopScope (Esc / clique fora / botão voltar).
  Future<void> _tentarFechar() async {
    if (_salvando) return;
    final podeFechar = await _confirmarFechamento();
    if (!mounted) return;
    if (podeFechar) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _roboHelper?.removeListener(_aoMudarRoboHelper);
    _debounceDuplicata?.cancel();
    for (final c in [
      _nome, _identificador, _categoria, _medida, _espessura,
      _largura, _comprimento, _quantidade, _estoqueMinimo,
    ]) {
      c.dispose();
    }
    _categoriaFocusNode.dispose();
    super.dispose();
  }

  void _agendarVerificacaoDuplicata() {
    _debounceDuplicata?.cancel();
    _debounceDuplicata = Timer(const Duration(milliseconds: 450), _verificarDuplicatas);
  }

  /// Busca materiais com nome parecido no backend e classifica os
  /// resultados como "exato" (mesma combinação nome+identificador+medida+
  /// espessura — o backend bloquearia com 409) ou "similar" (nome muito
  /// parecido, ou mesmo identificador com nome diferente — possível erro
  /// de digitação ou duplicidade não intencional).
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

    // O backend faz busca por AND entre as palavras digitadas (todas as
    // palavras precisam estar contidas no nome). Isso significa que buscar
    // pela frase inteira falha em achar duplicatas quando o nome digitado
    // tem uma palavra a mais/a menos/diferente do material já cadastrado
    // (ex.: "ABS ACO ESCOVADO PRATA 2" não encontra "ABS ACO ESCOVADO
    // PRATA", pois nenhum material tem a palavra "2" no nome). Por isso
    // buscamos por cada palavra do nome separadamente (OR) e unificamos os
    // resultados — a similaridade real é decidida depois, via Levenshtein,
    // então um candidato a mais aqui não causa falso-positivo, só amplia
    // a chance de achar o material realmente parecido.
    final tokensUnicos = _nome.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // palavras mais longas (mais distintivas) primeiro

    // Limita a 5 palavras para não disparar buscas demais em nomes longos;
    // ignora tokens de 1 char (pouco distintivos, geram excesso de ruído).
    final termosBusca = tokensUnicos.where((t) => t.length >= 2).take(5).toList();
    if (termosBusca.isEmpty && _nome.text.trim().isNotEmpty) {
      termosBusca.add(_nome.text.trim());
    }

    final resultadosPorToken = await Future.wait(
      termosBusca.map((t) => provider.buscarSugestoes(t, limite: 30)),
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

    // Dimensões digitadas: usa os campos numéricos Comprimento/Largura/
    // Espessura como fonte principal e, quando algum deles estiver vazio,
    // cai para o que der pra extrair do texto livre "medida" (que pode
    // trazer tudo junto, em qualquer grafia: com ou sem "m"/"mm", com ou
    // sem casas decimais, com ou sem um terceiro "x" pra espessura).
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
      // Ignora o próprio material ao editar.
      if (_editando && m.id == widget.material!.id) continue;

      final mNomeNorm          = _normalizarTextoComparacao(m.nome);
      final mIdentificadorNorm = _normalizarTextoComparacao(m.identificador);
      final mMedidaNorm        = _normalizarTextoComparacao(m.medida);
      final mEspessuraNorm     = _normalizarTextoComparacao(m.espessura);

      // Mesma lógica de fallback do lado do material cadastrado: prioriza os
      // campos numéricos e, na falta deles, extrai do texto "medida" salvo.
      final mMedidaExtraida = _extrairDimensoesMedida(m.medida);
      final mComprimentoFinal = m.comprimento ?? mMedidaExtraida.comprimento;
      final mLarguraFinal     = m.largura ?? mMedidaExtraida.largura;
      final mEspessuraFinal   = _extrairNumeroDeTexto(m.espessura) ?? mMedidaExtraida.espessura;

      // Comprimento/largura batem se os valores numéricos coincidirem,
      // não importa como cada lado escreveu a medida (com/sem "m", com/sem
      // decimais, com/sem espessura embutida no texto).
      final dimensoesBatem = dimensaoBate(comprimentoDigitado, mComprimentoFinal) &&
          dimensaoBate(larguraDigitada, mLarguraFinal);
      final medidaOuDimensaoBate = mMedidaNorm == medidaNorm || dimensoesBatem;

      // Espessura: compara numericamente (ignorando "mm" e formatação) e só
      // cai para comparação de texto puro quando nenhum lado tem número
      // reconhecível (ex.: valor não numérico digitado por engano). Quando
      // ambos os lados estão vazios, conta como igual.
      final espessuraBate = (espessuraNorm.isEmpty && mEspessuraNorm.isEmpty)
          ? true
          : (espessuraDigitadaNum != null && mEspessuraFinal != null)
              ? dimensaoBate(espessuraDigitadaNum, mEspessuraFinal)
              : mEspessuraNorm == espessuraNorm;

      // Mesma regra de unicidade usada no backend (nome + identificador +
      // medida + espessura, normalizados): se bater, o cadastro será
      // rejeitado com 409 ao salvar.
      final exata = mNomeNorm == nomeNorm &&
          mIdentificadorNorm == identificadorNorm &&
          medidaOuDimensaoBate &&
          espessuraBate;

      final similaridadeNome = _similaridadeTexto(nomeNorm, mNomeNorm);
      // Similaridade que ignora a ordem das palavras (ex.: "TINTA DUPLA
      // FUNCAO PRETO FOSCO" vs "TINTA PRETO FOSCO DUPLA FUNCAO"), pra pegar
      // casos em que o texto inteiro mudou de posição mas as palavras são
      // as mesmas. Usa o maior dos dois scores como similaridade "efetiva".
      final similaridadePalavras = _similaridadePalavras(nomeNorm, mNomeNorm);
      final similaridadeEfetiva =
          similaridadeNome > similaridadePalavras ? similaridadeNome : similaridadePalavras;
      final mesmoIdentificador =
          identificadorNorm.isNotEmpty && identificadorNorm == mIdentificadorNorm;

      // Detecta se um nome é prefixo/trecho do outro. Importante para quando
      // o usuário ainda está no início da digitação (ex.: "ABS ACO" digitado
      // com "ABS ACO ESCOVADO DOURADO" já cadastrado): a similaridade
      // Levenshtein do texto inteiro fica baixa (o nome cadastrado é bem mais
      // longo), mas o texto digitado é claramente o começo de um nome já
      // existente, então isso também conta como "similar". Exige um mínimo
      // de 4 caracteres no texto mais curto pra não disparar em prefixos
      // genéricos demais (ex.: "AB").
      final curto = nomeNorm.length <= mNomeNorm.length ? nomeNorm : mNomeNorm;
      final longo = nomeNorm.length <= mNomeNorm.length ? mNomeNorm : nomeNorm;
      final contido = curto.length >= 4 && curto.isNotEmpty && longo.contains(curto);

      // Quantas palavras (>=2 chars, pra ignorar conectivos irrelevantes)
      // coincidem exatamente entre os dois nomes, não importa a ordem. Serve
      // como sinal adicional e explícito: "se 1, 2, 3 palavras coincidirem,
      // já vai acusando" — quanto mais palavras em comum, mais forte o
      // indício de duplicidade, mesmo com nome final bem diferente.
      final palavrasDigitadas = nomeNorm.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
      final palavrasCadastro  = mNomeNorm.split(RegExp(r'\s+')).where((t) => t.length >= 2).toSet();
      final palavrasComuns = palavrasDigitadas.intersection(palavrasCadastro).length;
      // Exige pelo menos 2 palavras em comum (1 palavra só é fraco demais e
      // gera excesso de falso-positivo com termos genéricos), e que essas
      // palavras comuns cubram uma fração razoável do nome mais curto — pra
      // não acusar "TINTA PRETO" (2 palavras) contra "TINTA VERMELHA PRETO
      // FOSCO BRILHANTE ACETINADA" (5 palavras) só porque 2 bateram.
      final menorQtdPalavras =
          palavrasDigitadas.length < palavrasCadastro.length ? palavrasDigitadas.length : palavrasCadastro.length;
      final cobreParcialPalavras = palavrasComuns >= 2 &&
          menorQtdPalavras > 0 &&
          (palavrasComuns / menorQtdPalavras) >= 0.6;

      // "Similar": nome muito parecido em sequência (>=72%), muito parecido
      // ignorando a ordem das palavras (>=72%), mesmo identificador com
      // alguma semelhança (evita falso-positivo de identificadores genéricos
      // reutilizados em materiais bem diferentes), um nome é prefixo/trecho
      // do outro (digitação em andamento), ou várias palavras batem
      // independente da ordem (>=2 palavras cobrindo >=60% do nome menor).
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

  /// Considera o campo Medida "vazio" quando não há valor digitado — seja
  /// porque o campo está realmente vazio (modo normal), seja porque no modo
  /// Retalho só contém o sufixo fixo "m²" sem número à esquerda.
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

  Future<void> _salvar() async {
    if (widget.somenteLeitura) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_modoRetalho && (_unidade == null || _unidade!.isEmpty)) {
      setState(() => _erroDialog = 'Selecione uma unidade antes de salvar.');
      return;
    }
    // Garante que a verificação de duplicidade mais recente já foi
    // concluída antes de decidir se pode salvar (evita salvar durante o
    // debounce, quando _possiveisDuplicatas ainda reflete o texto anterior
    // digitado, permitindo escapar da validação por timing).
    _debounceDuplicata?.cancel();
    await _verificarDuplicatas();
    if (!mounted) return;
    if (_possiveisDuplicatas.any((d) => d.exata)) {
      setState(() {
        _erroDialog = 'Já existe um material idêntico cadastrado. '
            'Ajuste a medida/espessura ou edite o material existente.';
      });
      return;
    }
    setState(() { _salvando = true; _erroDialog = null; });

    // Defesa em profundidade: além do readOnly na UI, garante que COMPRAS
    // editando um material existente não consiga enviar alterações para os
    // campos que não são de sua responsabilidade — preserva os valores
    // originais do material nesse caso. Categoria e Estoque confirmado
    // ficam de fora dessa lista propositalmente: são os únicos campos que
    // COMPRAS pode alterar.
    final material = widget.material;
    final bloqueado = _bloqueadoParaComprasAtual && material != null;

    final dados = {
      'nome':          bloqueado ? material.nome          : _nome.text.trim(),
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
    };

    final provider = context.read<MaterialProvider>();
    final bool ok;
    if (_editando) {
      ok = await provider.atualizar(widget.material!.id, dados);
    } else {
      ok = await provider.criar(dados);
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      Navigator.of(context, rootNavigator: true).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_editando ? 'Material atualizado.' : 'Material criado.'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      setState(() => _erroDialog = provider.erro ?? 'Erro ao salvar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final material      = widget.material;
    final fornecedores  = material?.fornecedorMateriais ?? <FornecedorMaterialModel>[];
    final temFornecedor = _editando && fornecedores.isNotEmpty;

    // ── Painel de formulário (sempre presente) ────────────────────────────
    Widget formPanel = Form(
      key: _formKey,
      child: SingleChildScrollView(
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
              autofocus: !_editando,
              readOnly: _bloqueadoParaCompras,
              decoration: const InputDecoration(labelText: 'Nome *'),
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
            const SizedBox(height: 10),
            KeyedSubtree(
              key: widget.tourKeys?.identificador,
              child: TextFormField(
              controller: _identificador,
              readOnly: _modoRetalho || _bloqueadoParaCompras,
              onChanged: (v) {
                // Ativa o modo Retalho automaticamente ao digitar essa
                // palavra no Identificador, travando os campos como se o
                // usuário tivesse clicado no botão "Modo Retalho".
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
            const SizedBox(height: 10),
            Row(children: [
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
                    : MouseRegion(
                        cursor: _bloqueadoParaCompras ? SystemMouseCursors.basic : SystemMouseCursors.click,
                        child: DropdownButtonFormField<String>(
                          initialValue: _unidade,
                          decoration: const InputDecoration(labelText: 'Unidade *'),
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
            ], // end if not ML/G (medida)
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
            ], // end if not ML/G
            const SizedBox(height: 10),
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
        ),
      ),
    );

    // Formata um valor monetário com separador de milhar (ex.: 1.000,00)
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

    // ── Painel lateral de possíveis duplicatas (esquerda, sempre visível) ─
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

    // ── Painel lateral de fornecedores (apenas no modo edição) ────────────
    Widget? fornecedorPanel;
    if (temFornecedor) {
      final ordenados = [...fornecedores]
        ..sort((a, b) => a.preco.compareTo(b.preco));

      // ── Preços médios entre fornecedores (considera apenas valores > 0) ──
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
            // Cabeçalho do painel (clicável para expandir/recolher)
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

            // Cabeçalho das colunas
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

            // Lista de fornecedores clicáveis
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

            // Linha de preço médio entre os fornecedores
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

    // ── Dialog com layout condicional ─────────────────────────────────────
    return PopScope(
      // Intercepta qualquer tentativa de fechar o diálogo que não passe
      // pelos botões (X/Cancelar), como a tecla Esc ou o gesto/botão
      // "voltar": sempre barra o pop automático e decide via
      // _confirmarFechamento se deve realmente fechar.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Quando este dialog foi aberto pelo tour do robô (tourKeys não
        // nulo) e o tour ainda está no ar, o Esc chega até aqui ANTES do
        // KeyboardListener do robô conseguir tratá-lo (o foco está dentro
        // do dialog). Se deixássemos cair em _confirmarFechamento, o
        // dialog fecharia mas o tour continuaria "ativo" apontando pra um
        // campo que não existe mais — daí a dica sumir e o dialog ficar
        // aberto, ou vice-versa, dependendo da corrida entre os dois
        // listeners. Em vez disso, tratamos Esc aqui como "sair do tour":
        // encerra o tour e fecha o dialog junto, de forma consistente.
        // (O listener _aoMudarRoboHelper cobre os demais jeitos de encerrar
        // o tour — ex.: "Concluir" na última parada — fechando o dialog
        // quando tourAtivo virar false por qualquer motivo.)
        //
        // IMPORTANTE: este handler também é acionado programaticamente
        // pelo próprio tour quando o usuário clica "Anterior" saindo de um
        // passo dentro deste dialog de volta pro passo do botão "Novo
        // Material" (fora dele) — nesse caso tourAtivo continua true, só
        // muda a parada. Tratar isso como a condição acima faria o
        // "Anterior" encerrar o tour inteiro em vez de só voltar um passo.
        // Distinguimos checando se a parada atual do tour ainda aponta pra
        // uma key deste dialog: se sim, é um Esc/fechamento manual de
        // verdade; se não (a parada já é a do botão "Novo Material", fora
        // do dialog), é o próprio tour navegando pra trás — só deixamos o
        // pop acontecer, sem encerrar o tour.
        final roboHelper =
            context.mounted ? context.read<RoboHelperProvider>() : null;
        final tourNavegandoParaFora = widget.tourKeys != null &&
            roboHelper != null &&
            roboHelper.tourAtivo &&
            roboHelper.paradaAtual != null &&
            !widget.tourKeys!.contemParada(roboHelper.paradaAtual!.key);
        if (tourNavegandoParaFora) {
          Navigator.pop(context);
          return;
        }
        if (widget.tourKeys != null &&
            context.mounted &&
            roboHelper != null &&
            roboHelper.tourAtivo) {
          roboHelper.encerrarTour();
          Navigator.pop(context);
          return;
        }
        final podeFechar = await _confirmarFechamento();
        if (!context.mounted) return;
        if (podeFechar) {
          Navigator.pop(context);
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
            // ── Título ────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    widget.somenteLeitura
                        ? 'Visualizar Material'
                        : (_editando ? 'Editar Material' : 'Novo Material'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (!_editando) ...[
                    const SizedBox(width: 12),
                    // ── Atalho RETALHO ────────────────────────────────────
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
                            Navigator.of(context, rootNavigator: true).pop();
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

            // ── Corpo: formulário + painel lateral ────────────────────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Painel lateral (possíveis duplicatas), à esquerda — sempre visível
                  avisoPanel,
                  // Formulário
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                      child: formPanel,
                    ),
                  ),
                  // Painel lateral (se houver fornecedores)
                  if (fornecedorPanel != null) fornecedorPanel,
                ],
              ),
            ),

            // ── Ações ─────────────────────────────────────────────────────
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
                                    Navigator.of(context, rootNavigator: true).pop(false);
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
                                Navigator.of(context, rootNavigator: true).pop(false);
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
                                    Navigator.of(context, rootNavigator: true).pop(false);
                                    widget.onExcluir!(widget.material!);
                                  },
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Excluir'),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.error)
                                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ),
                      ),
                  ],
                  if (_bloqueadoParaCompras) ...[
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
                    message: _editando ? 'Salvar alterações' : 'Cadastrar este material',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: FilledButton(
                        onPressed: _salvando ? null : _salvar,
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                            .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                        child: _salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_editando ? 'Salvar' : 'Cadastrar'),
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

/// Extrai o primeiro número de um texto, aceitando vírgula ou ponto como
/// separador decimal e ignorando qualquer sufixo de unidade colado nele
/// (ex.: "1.22m" -> 1.22, "3mm" -> 3, "2,00" -> 2.0). Retorna null se não
/// houver número reconhecível.
double? _extrairNumeroDeTexto(String? s) {
  if (s == null) return null;
  final match = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(s.trim());
  if (match == null) return null;
  return double.tryParse(match.group(0)!.replaceAll(',', '.'));
}

/// Dimensões numéricas extraídas do texto livre "medida".
class _DimensoesMedida {
  final double? comprimento;
  final double? largura;
  final double? espessura;
  const _DimensoesMedida({this.comprimento, this.largura, this.espessura});
}

/// Faz o parse do campo "medida" (texto livre) em até 3 números separados
/// por "x"/"X"/"×", tolerando qualquer combinação de: presença ou não do
/// sufixo de unidade ("m", "mm"), formatação decimal (2 vs 2.00 vs 2,00), e
/// um terceiro segmento opcional com a espessura embutida (ex.: "5x1.22x3mm",
/// "2x1x2mm", "2.00x1.00m", "2x1"). Todas essas grafias devem ser
/// reconhecidas como a mesma medida física.
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

/// Normaliza texto para comparação de duplicidade: maiúsculas, sem acentos,
/// espaços colapsados. Espelha a normalização usada no backend (nome,
/// identificador, medida, espessura comparados case-insensitive).
String _normalizarTextoComparacao(String? v) {
  if (v == null) return '';
  final upper = _UpperCaseFormatter._removerAcentos(v.trim().toUpperCase());
  return upper.replaceAll(RegExp(r'\s+'), ' ');
}

/// Distância de Levenshtein clássica (número mínimo de inserções, remoções
/// e substituições para transformar [a] em [b]).
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

/// Similaridade entre 0 (totalmente diferentes) e 1 (idênticos), baseada na
/// distância de Levenshtein normalizada pelo tamanho do maior texto.
///
/// Sensível à ORDEM das palavras: "TINTA PRETO FOSCO" x "PRETO FOSCO TINTA"
/// tem similaridade baixa aqui, mesmo contendo as mesmas palavras.
double _similaridadeTexto(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final distancia = _levenshteinDistance(a, b);
  final maiorTamanho = a.length > b.length ? a.length : b.length;
  return 1 - (distancia / maiorTamanho);
}

/// Similaridade por CONJUNTO DE PALAVRAS, ignorando a ordem em que aparecem.
///
/// Resolve o caso de nomes com as mesmas palavras escritas em ordem
/// diferente (ex.: "TINTA DUPLA FUNCAO PRETO FOSCO" vs "TINTA PRETO FOSCO
/// DUPLA FUNCAO"), que teriam distância de Levenshtein alta (o texto inteiro
/// muda de posição) apesar de serem, na prática, o mesmo material.
///
/// Cada palavra do texto mais curto é casada com a melhor correspondente
/// ainda não usada no texto mais longo (permitindo pequenas diferenças de
/// grafia por palavra, via Levenshtein por palavra), e o resultado é a
/// fração de palavras casadas ponderada pelo tamanho combinado dos dois
/// textos — combinação equivalente a um Jaccard/overlap tolerante a erros
/// de digitação em cada palavra individual.
double _similaridadePalavras(String a, String b) {
  final palavrasA = a.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final palavrasB = b.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (palavrasA.isEmpty && palavrasB.isEmpty) return 1;
  if (palavrasA.isEmpty || palavrasB.isEmpty) return 0;

  // Garante que iteramos sobre a lista menor (menos comparações) e usa a
  // maior como "disponível" para casar.
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
        // Palavra idêntica: casamento perfeito, não precisa procurar mais.
        melhorIdx = i;
        melhorScore = 1.0;
        break;
      }
      // Palavras de 1-2 letras são pouco distintivas (ex.: "DE", "M2"):
      // só aceita casamento parcial entre elas se muito parecidas, pra não
      // gerar falso-positivo (ex.: "DE" casando com "SE").
      final tamMin = palavra.length < maior[i].length ? palavra.length : maior[i].length;
      if (tamMin <= 2 && palavra != maior[i]) continue;
      final score = _similaridadeTexto(palavra, maior[i]);
      // Só considera casamento parcial (palavra diferente, mas parecida —
      // ex.: singular/plural, erro de digitação) acima de um limiar alto.
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
  // Multiplica por 2 porque cada palavra casada contribui peso de um lado
  // só (pesoCasado é somado a partir da lista "menor"), mas representa a
  // correspondência dos dois lados ao mesmo tempo.
  return (pesoCasado * 2) / pesoTotal;
}

/// Resultado de uma possível duplicata encontrada ao comparar os campos do
/// formulário com materiais já cadastrados.
class _PossivelDuplicata {
  final MaterialModel material;
  /// true quando nome + identificador + medida + espessura (normalizados)
  /// coincidem exatamente — o backend rejeitaria esse cadastro com 409.
  final bool exata;
  final double similaridade;
  /// true quando o nome digitado é um prefixo/trecho do nome já cadastrado
  /// (ou vice-versa) — sinal forte de duplicata mesmo no início da digitação,
  /// quando a similaridade Levenshtein do texto inteiro ainda é baixa.
  final bool contido;

  _PossivelDuplicata({
    required this.material,
    required this.exata,
    required this.similaridade,
    this.contido = false,
  });
}

/// Banner exibido no formulário de cadastro/edição de material quando o
/// algoritmo de comparação encontra materiais já cadastrados com nome,
/// identificador, medida ou espessura parecidos com os campos digitados.
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

            // Formata comprimento x largura (ex.: "2x1m") quando ambos os
            // valores numéricos estiverem disponíveis. Nesse caso, o texto
            // livre "medida" é omitido (evita repetir a mesma informação em
            // formatos diferentes, ex.: "2x1m" e "2.00x1.00x2").
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
                          TextSpan(text: m.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
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

/// Substitui o campo "Quantidade" no cadastro quando o usuário é COMPRAS.
/// Indica que a entrada de estoque deve ser feita pela página de Controle
/// de Estoque, garantindo que toda entrada fique vinculada a uma OS.
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

/// Substitui o campo "Estoque mínimo" no cadastro quando o usuário é COMPRAS.
/// Mesma lógica de [_QuantidadeBloqueadaInfo]: a definição do estoque mínimo
/// deve ser feita por quem tem acesso à entrada real de estoque.
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

/// Formata um valor monetário APENAS para exibição visual: sempre 2 casas
/// decimais, com separador de milhar '.' e decimal ',' (padrão BR).
/// Não altera o valor real do dado, apenas a string exibida na tela.
/// Ex: 1000 → "1.000,00" | 152.638889 → "152,64" | 1234567.8 → "1.234.567,80"
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

/// Formata uma quantidade de material SEM arredondar/truncar o valor real.
/// Diferente de `qtd.toStringAsFixed(2)` (que corta a precisão real do
/// estoque, ex.: 3.696 exibido como "3.70"), esta função mostra o número
/// exatamente como ele é: inteiro sem casas decimais, ou com o número de
/// casas necessário para representá-lo por completo (sem zeros à direita).
/// Mantida sem separador de milhar pois também é usada para inicializar/
/// parsear campos editáveis de largura/comprimento (dimensões em metros,
/// tipicamente pequenas), onde um ponto de milhar quebraria a edição.
/// Ex.: 3.696 → "3.696" | 3.70 → "3.7" | 4 → "4"
String formatarQuantidade(double valor) {
  if (valor == valor.truncateToDouble()) return valor.toStringAsFixed(0);
  // toString() do Dart já imprime a representação decimal completa e mínima
  // de um double (sem zeros à direita além do necessário), preservando a
  // precisão real do valor armazenado.
  return valor.toString();
}

/// Formata uma quantidade de estoque para EXIBIÇÃO como texto — com
/// separador de milhar (ponto) na parte inteira e vírgula como separador
/// decimal (padrão brasileiro). Diferente de [formatarQuantidade], que é
/// usada em campos editáveis de dimensão e por isso não pode ter milhar.
/// Ex.: 1000 → "1.000"; 3.696 → "3,696"; 4.0 → "4".
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

  // ── Inserção manual de custo ──────────────────────────────────────────────
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

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final ultimoHistorico = _historico.isNotEmpty ? _historico.first : null;
    final ultimoUsarM2    = ultimoHistorico?.usarM2 ?? false;
    // Usa o valor do próprio registro de histórico (já ordenado por criadoEm desc),
    // evitando depender de material.ultimoValorPago que pode ficar desatualizado.
    final ultimoCusto   = ultimoHistorico?.precoUnitario;
    final ultimoCustoM2 = ultimoHistorico?.precoM2;
    final temCusto   = !ultimoUsarM2 && ultimoCusto   != null && ultimoCusto   > 0;
    final temCustoM2 =  ultimoUsarM2 && ultimoCustoM2 != null && ultimoCustoM2 > 0;

    // ⚠️ Usamos Dialog (não AlertDialog) para evitar o bug em release mode onde
    // o content fica cinza/em branco. Em release, AlertDialog com SizedBox de
    // altura fixa no content não consegue resolver constraints corretamente.
    // Com Dialog direto controlamos o layout via Column + Flexible, que funciona
    // identicamente em debug e release.
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
            // ── Título ──────────────────────────────────────────────────────
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
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── Conteúdo scrollável ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            if (temCusto || temCustoM2)
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
                    Icon(Icons.payments_outlined, size: 16, color: Color(0xFFE85D04)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Último custo registrado:',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          if (temCusto)
                            RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 12),
                                children: [
                                  TextSpan(
                                    text: 'Custo: ',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  TextSpan(
                                    text: 'R\$ ${_formatarCustoVisual(ultimoCusto)}',
                                    style: const TextStyle(
                                      color: Color(0xFFE85D04),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (temCustoM2)
                            RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 12),
                                children: [
                                  TextSpan(
                                    text: 'Custo m²: ',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  TextSpan(
                                    text: 'R\$ ${_formatarCustoVisual(ultimoCustoM2)}',
                                    style: const TextStyle(
                                      color: Color(0xFFE85D04),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
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
                    width: 60,
                    child: Text(
                      'Qtd',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'm/l por unid.',
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
                      'Custo m²',
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
                    'Nenhum custo registrado.\nO histórico é criado automaticamente ao finalizar uma Ordem de Compra.',
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
                                  child: Text(
                                    h.usarM2 && h.precoM2 != null && h.precoM2! > 0
                                        ? 'R\$ ${_formatarCustoVisual(h.precoM2!)}'
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
                                  ),
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
            // ── Actions ────────────────────────────────────────────────────
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
                    label: Text(_mostrarFormCusto ? 'Cancelar inserção' : 'Inserir custo manualmente'),
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
// ─────────────────────────────────────────────────────────────────────────────
// BANNER INLINE DE ALERTAS — exibido no topo da EstoquePage
// ─────────────────────────────────────────────────────────────────────────────

class _AlertasBannerEstoque extends StatefulWidget {
  final AlertasEstoqueProvider provider;
  const _AlertasBannerEstoque({required this.provider});

  @override
  State<_AlertasBannerEstoque> createState() => _AlertasBannerEstoqueState();
}

class _AlertasBannerEstoqueState extends State<_AlertasBannerEstoque> {
  // Seleção por referência: os objetos de alerta vêm sempre da mesma lista
  // do provider entre rebuilds (só mudam quando chega um novo evento SSE),
  // então usar o próprio objeto como chave do Set é seguro aqui.
  final Set<dynamic> _selecionados = {};

  void _toggle(dynamic alerta) {
    setState(() {
      if (_selecionados.contains(alerta)) {
        _selecionados.remove(alerta);
      } else {
        _selecionados.add(alerta);
      }
    });
  }

  /// Lê um campo dinâmico do alerta sem quebrar caso o modelo não o possua.
  T? _campo<T>(dynamic obj, T Function() getter) {
    try {
      return getter();
    } catch (_) {
      return null;
    }
  }

  bool _mesmo(String? a, String? b) {
    final ta = (a ?? '').trim().toUpperCase();
    final tb = (b ?? '').trim().toUpperCase();
    if (ta.isEmpty || tb.isEmpty) return true; // campo não informado → não restringe
    return ta == tb;
  }

  Future<void> _orcarSelecionados() async {
    if (_selecionados.isEmpty) return;

    final todos = context.read<MaterialProvider>().materiais;
    final itens = <ItemOrcamentoData>[];
    final naoEncontrados = <String>[];

    for (final a in _selecionados) {
      final nome          = _campo<String>(a, () => a.nome as String) ?? '';
      final categoria     = _campo<String?>(a, () => a.categoria as String?);
      final identificador = _campo<String?>(a, () => a.identificador as String?);
      final medida        = _campo<String?>(a, () => a.medida as String?);
      final espessura      = _campo<String?>(a, () => a.espessura as String?);

      MaterialModel? encontrado;
      for (final m in todos) {
        final ok = _mesmo(m.nome, nome) &&
            _mesmo(m.categoria, categoria) &&
            _mesmo(m.identificador, identificador) &&
            _mesmo(m.medida, medida) &&
            _mesmo(m.espessura, espessura);
        if (ok) {
          encontrado = m;
          break;
        }
      }

      if (encontrado == null) {
        naoEncontrados.add(nome.isNotEmpty ? nome : 'material');
        continue;
      }

      final precos = <int, PrecoFornecedorData>{};
      for (final fm in encontrado.fornecedorMateriais) {
        precos[fm.fornecedorId] = PrecoFornecedorData(
          fornecedorNome: fm.fornecedorNome,
          preco:   fm.preco > 0 ? fm.preco : null,
        );
      }

      itens.add(ItemOrcamentoData(
        materialId:            encontrado.id,
        materialNome:          encontrado.nome,
        materialUnidade:       encontrado.unidade,
        materialCategoria:     encontrado.categoria,
        materialMedida:        encontrado.medida,
        materialEspessura:     encontrado.espessura,
        materialIdentificador: encontrado.identificador,
        materialStatus:        encontrado.status,
        materialLargura:       encontrado.largura,
        materialComprimento:   encontrado.comprimento,
        estoqueMinimo:         encontrado.estoqueMinimo,
        precos:                precos,
      ));
    }

    if (!mounted) return;

    if (itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível localizar os materiais selecionados.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final titulo = itens.length == 1
        ? 'Orç. ${itens.first.materialNome}'
        : 'Orç. materiais críticos (${itens.length})';

    context.read<OrcamentoProvider>().adicionarItensEmLote(titulo, itens);

    if (naoEncontrados.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${naoEncontrados.length} material(is) não encontrado(s) e não foram incluídos: ${naoEncontrados.join(', ')}',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }

    setState(() => _selecionados.clear());

    // Ao entrar em /orcamento, abre direto no editor (aba "abertos") com
    // este orçamento recém-criado, em vez da lista de aprovação.
    OrcamentoPage.abrirEditorAoEntrar = true;
    context.go('/orcamento');
  }

  @override
  Widget build(BuildContext context) {
    final criticos = widget.provider.alertas;
    const cor = Color(0xFFDC2626);

    return Container(
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(
            Icons.error_outline_rounded,
            color: cor,
            size: 20,
          ),
          title: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    children: [
                      TextSpan(
                        text: '${criticos.length} material${criticos.length > 1 ? 'is' : ''} com estoque crítico',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              if (_selecionados.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: OutlinedButton.icon(
                    onPressed: _orcarSelecionados,
                    icon: const Icon(Icons.request_quote, size: 16),
                    label: Text('Orçar selecionados (${_selecionados.length})'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E88E5),
                      side: const BorderSide(color: Color(0xFF1E88E5)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
            ],
          ),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (criticos.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(
                          'Toque em um ou mais materiais para selecioná-los e orçar.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      _BannerSecao(
                        label: 'CRÍTICO — abaixo do mínimo',
                        cor: cor,
                        alertas: criticos,
                        selecionados: _selecionados,
                        onToggle: _toggle,
                      ),
                    ],
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

class _BannerSecao extends StatelessWidget {
  final String label;
  final Color cor;
  final List<dynamic> alertas;
  final Set<dynamic> selecionados;
  final void Function(dynamic alerta) onToggle;
  const _BannerSecao({
    required this.label,
    required this.cor,
    required this.alertas,
    required this.selecionados,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cor,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: alertas.map<Widget>((a) {
              final unidade = formatarUnidadeExibicao(a.unidade as String?);
              final unidadeExibir = unidade == '—' ? '' : unidade;
              final qtd     = a.quantidade as double;
              final qtdStr  = formatarQuantidadeExibicao(qtd);
              final selecionado = selecionados.contains(a);
              return InkWell(
                onTap: () => onToggle(a),
                borderRadius: BorderRadius.circular(6),
                mouseCursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selecionado
                        ? cor.withValues(alpha: 0.22)
                        : cor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selecionado ? cor : cor.withValues(alpha: 0.25),
                      width: selecionado ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selecionado ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 14,
                        color: cor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        a.nome as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$qtdStr${unidadeExibir.isNotEmpty ? ' $unidadeExibir' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── _StatusBadgeEstoque ──────────────────────────────────────────────────────
// Badge de status de material (OK / LIMITE / CRITICO / INATIVO).
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