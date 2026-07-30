import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/producao_model.dart';
import '../models/estoque_producao_model.dart';
import '../providers/producao_provider.dart';
import '../providers/estoque_producao_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

/// Formata um valor monetário com até 6 casas decimais, removendo zeros
/// à direita desnecessários (mínimo 2 casas). Ex.: 1.5 → "R$ 1,50";
/// 0.000125 → "R$ 0,000125"; 1.234560 → "R$ 1,23456".
String _brl6(double v) {
  final s6 = v.toStringAsFixed(6);
  final trimmed = s6.replaceAll(RegExp(r'0+$'), '');
  final partes = trimmed.split('.');
  final dec = partes.length > 1 ? partes[1] : '';
  final decFinal = dec.length < 2 ? dec.padRight(2, '0') : dec;
  return 'R\$ ${partes[0].replaceAll('.', ',')},$decFinal';
}

/// Formata a unidade para exibição (o valor interno permanece em maiúsculo,
/// usado para comparações/enum). Ex.: 'UNIDADE' → 'Unidade'; 'M' → 'm';
/// 'M/L' → 'm/l'; 'ML' → 'ml'; 'M²' → 'm²'; 'KG' → 'Kg'; 'G' → 'g'.
String formatarUnidadeExibicao(String? unidade) {
  if (unidade == null || unidade.trim().isEmpty) return '';
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
      baseOffset:   newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

/// Formata o valor de espessura para exibição, acrescentando o sufixo
/// 'mm'. Retorna null/vazio inalterado.
String? _fmtEspessura(String? espessura) {
  if (espessura == null || espessura.trim().isEmpty) return espessura;
  return '${espessura.trim()}mm';
}

/// Formata um campo decimal: converte vírgula em ponto e impede pontos
/// seguidos (ex.: "1..2" nunca é produzido, digitar um segundo ponto
/// seguido é ignorado).
class _DecimalCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(',', '.');
    // Remove pontos consecutivos, mantendo apenas o primeiro.
    texto = texto.replaceAll(RegExp(r'\.{2,}'), '.');
    if (texto == newValue.text) return newValue;
    final offset = newValue.selection.end - (newValue.text.length - texto.length);
    final novoOffset = offset.clamp(0, texto.length);
    return newValue.copyWith(
      text: texto,
      selection: TextSelection.collapsed(offset: novoOffset),
    );
  }
}

/// Formata o campo de espessura: aplica as mesmas regras do
/// [_DecimalCommaFormatter] (vírgula → ponto, sem pontos seguidos) e ainda
/// bloqueia letras e qualquer caractere que não seja dígito ou ponto.
class _EspessuraFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text.replaceAll(',', '.');
    texto = texto.replaceAll(RegExp(r'[^0-9.]'), '');
    texto = texto.replaceAll(RegExp(r'\.{2,}'), '.');
    if (texto == newValue.text) return newValue;
    final offset = newValue.selection.end - (newValue.text.length - texto.length);
    final novoOffset = offset.clamp(0, texto.length);
    return newValue.copyWith(
      text: texto,
      selection: TextSelection.collapsed(offset: novoOffset),
    );
  }
}

/// Corrige o texto de um campo de dimensão usada para não ultrapassar o
/// [maximo] da chapa. Se o valor digitado exceder o máximo, o controller é
/// truncado para o próprio máximo (formatado) e a seleção movida para o fim.
void _limitarDimensao(TextEditingController ctrl, double maximo) {
  final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
  if (v == null || v <= maximo) return;
  final fmt = maximo == maximo.truncateToDouble()
      ? maximo.toStringAsFixed(0)
      : maximo.toStringAsFixed(2);
  ctrl.value = TextEditingValue(
    text: fmt,
    selection: TextSelection.collapsed(offset: fmt.length),
  );
}

// Sentinels para categorias especiais
const _kCategoriaGeral        = '__GERAL__';
const _kCategoriaSemCategoria = '__SEM_CATEGORIA__';

// Sentinels para identificadores especiais
const _kIdentificadorTodos           = '__TODOS__';
const _kIdentificadorSemIdentificador = '__SEM_IDENTIFICADOR__';

// O antigo seletor "Produção 1 / Produção 2" no cabeçalho foi substituído
// por abas próprias — "Estoque Produção 1" e "Estoque Produção 2" — quando
// o usuário logado é ADMIN/GERENTE/COMPRAS (ver _ProducaoPageState), então
// esse widget não é mais necessário.

class ProducaoPage extends StatefulWidget {
  const ProducaoPage({super.key});

  @override
  State<ProducaoPage> createState() => _ProducaoPageState();
}

class _ProducaoPageState extends State<ProducaoPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Guarda de qual usuário/role a linha de produção foi definida por
  // último, para detectar troca de usuário (login diferente) mesmo que
  // esta página não seja remontada — StatefulShellRoute preserva o estado
  // do branch '/producao' entre navegações e entre logins, então o
  // initState só roda uma vez por sessão do app.
  String? _ultimoUsuarioId;

  // Guarda se o usuário logado enxerga as duas linhas combinadas em uma só
  // lista (ADMIN/GERENTE/COMPRAS) ou apenas a própria linha (PRODUCAO1/
  // PRODUCAO2). Em ambos os casos a TabBar sempre tem 2 abas — Estoque
  // (Produção) e Histórico — a diferença é só o conteúdo da 1ª aba: para
  // duas linhas, mostra a lista combinada com uma coluna extra indicando de
  // qual linha (1 ou 2) cada material é; para uma linha, mostra só o que
  // pertence à linha do usuário.
  bool? _duasLinhasAtual;

  void _configurarTabController(bool duasLinhas) {
    _tabController.dispose();
    // Sempre 2 abas: [Estoque (Produção), Histórico].
    _tabController = TabController(length: 2, vsync: this);
    _duasLinhasAtual = duasLinhas;
  }

  @override
  void initState() {
    super.initState();
    // Tamanho inicial (2 abas) — igual para os dois modos, então não
    // precisa ser recriado quando _definirProducaoDoUsuario rodar,
    // exceto para atualizar a flag _duasLinhasAtual.
    _tabController = TabController(length: 2, vsync: this);
    // Não é preciso agendar _definirProducaoDoUsuario aqui: o Flutter chama
    // didChangeDependencies logo após initState (antes do primeiro frame),
    // e didChangeDependencies já agenda essa chamada via
    // addPostFrameCallback.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reexecuta sempre que as dependências (incl. UsuarioProvider, via
    // context.watch mais abaixo no build) mudarem — isto é, sempre que o
    // usuário logado mudar — e não apenas na primeira montagem da página.
    //
    // IMPORTANTE: didChangeDependencies pode disparar durante a fase de
    // build (ex.: no _firstBuild da página, ou quando outro provider
    // notifica ouvintes enquanto a árvore ainda está sendo construída).
    // _definirProducaoDoUsuario chama estoqueProvider.definirProducao(...),
    // que dispara notifyListeners() — e, se isso acontecer durante o
    // build, o Flutter lança "setState() or markNeedsBuild() called during
    // build". Por isso adiamos a chamada com addPostFrameCallback, que só
    // executa depois que o frame atual terminar de ser construído.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _definirProducaoDoUsuario();
    });
  }

  /// Define no [EstoqueProducaoProvider] qual linha de produção ('1' ou '2')
  /// o usuário logado enxerga, a partir do seu cargo (PRODUCAO1/PRODUCAO2).
  /// ADMIN, GERENTE e COMPRAS não têm linha própria — podem ver as duas,
  /// escolhendo pelo seletor no topo da tela; aqui só definimos um padrão
  /// ('1') na primeira vez que esse tipo de usuário abre a tela.
  ///
  /// Sempre que detecta que o usuário logado mudou desde a última chamada,
  /// força a redefinição da linha e recarrega estoque/histórico — isso é o
  /// que evita o bug de um usuário PRODUCAO2 herdar a linha '1' que ficou
  /// setada no provider por um usuário anterior (PRODUCAO1, ADMIN, etc.),
  /// já que o provider e esta página não são recriados a cada login.
  void _definirProducaoDoUsuario() {
    final usuario = context.read<UsuarioProvider>().usuarioLogado;
    // Usa o id real do usuário (UsuarioModel.id) como chave de detecção de
    // troca — mais robusto que identityHashCode, pois continua funcionando
    // mesmo se o provider recriar o objeto UsuarioModel com os mesmos dados
    // (ex.: refresh de token).
    final usuarioId = usuario?.id.toString();
    final trocouUsuario = usuarioId != _ultimoUsuarioId;
    if (!trocouUsuario) return;
    _ultimoUsuarioId = usuarioId;

    // Se a página de Produção estiver com alguma categoria/identificador
    // aberto (ex.: dentro de "Estoque Produção 1"), volta para a tela
    // principal ao trocar de usuário — o detalhe aberto pode não fazer mais
    // sentido para quem logou agora (ex.: estava vendo a Produção 1 e o
    // novo usuário é PRODUCAO2, que só pode ver a própria linha). Vale para
    // qualquer troca de usuário, não só quando o cargo muda, e não afeta a
    // navegação de outras abas do app: cada branch do StatefulShellRoute
    // tem seu próprio Navigator, então isto só fecha telas empilhadas
    // dentro da própria aba de Produção.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    final role = usuario?.role.trim().toUpperCase() ?? '';
    final duasLinhas = role == 'ADMIN' || role == 'GERENTE' || role == 'COMPRAS';
    final producao = switch (role) {
      'PRODUCAO1' => '1',
      'PRODUCAO2' => '2',
      _           => '1', // ADMIN/GERENTE/COMPRAS: linha ativa "padrão", usada por telas de detalhe/baixa que ainda dependem de uma única linha
    };
    final estoqueProvider = context.read<EstoqueProducaoProvider>();
    estoqueProvider.definirProducao(producao);
    if (duasLinhas) {
      estoqueProvider.carregarEstoqueAmbasLinhas();
    } else {
      estoqueProvider.carregarEstoque();
    }
    estoqueProvider.carregarHistorico();

    // Atualiza a flag (usada para trocar o conteúdo da 1ª aba entre "lista
    // combinada com coluna Produção" e "lista da própria linha"). O
    // TabController em si não precisa ser recriado — sempre tem 2 abas —,
    // mas passamos por _configurarTabController na primeira vez (quando
    // ainda é null) e sempre que o modo mudar, por clareza.
    if (_duasLinhasAtual != duasLinhas) {
      setState(() => _configurarTabController(duasLinhas));
    }
  }

  // Não há mais listener de troca de aba recarregando estoque/histórico:
  // os dados das duas linhas e do histórico já são carregados por completo
  // assim que a tela abre (em _definirProducaoDoUsuario) e também pelo
  // botão de atualizar manual. O listener antigo (_onTabChanged), registrado
  // com `_tabController.addListener`, disparava a cada tick da ANIMAÇÃO de
  // troca de aba — não só quando o índice mudava de fato — então cada troca
  // (ou até o gesto de arrastar entre abas) dispirava vários recarregamentos
  // em sequência. Cada um marcava "carregando = true" por um instante,
  // trocando a lista pelo spinner e de volta, várias vezes por segundo: daí
  // o piscar ao trocar de aba/abrir a tela, e também o motivo de não dar
  // pra clicar no histórico — a lista era reconstruída no meio do toque e o
  // gesto era cancelado antes do botão "excluir" registrar o clique.
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANTE: este watch é o que faz didChangeDependencies disparar
    // sempre que o usuário logado mudar — inclusive via "Trocar para" no
    // menu do app_shell, e mesmo com esta página offstage (invisível) no
    // IndexedStack do StatefulShellRoute, que a mantém sempre montada.
    //
    // Sem este watch, o build desta página não ficava registrado como
    // dependente do UsuarioProvider (só alguns widgets FILHOS faziam
    // watch, só para exibir/ocultar botões conforme o cargo) — e
    // didChangeDependencies só é chamado pelo Flutter quando o widget
    // realmente depende do InheritedWidget que mudou. Resultado: ao trocar
    // de usuário (ex. de PRODUCAO1 para GERENTE) sem relogar, o
    // _tabController continuava com 2 abas (modo "uma linha") e a aba
    // "Estoque Produção 2" nunca aparecia, porque _definirProducaoDoUsuario
    // nunca era chamado — só era executado o reload correto ao relogar
    // (quando a página remonta do zero via initState).
    context.watch<UsuarioProvider>();

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
                      'Produção',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Estoque e baixas de materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const _RetalhosPage(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00897B),
                    side: const BorderSide(color: Color(0xFF00897B)),
                    backgroundColor: const Color(0xFF00897B).withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                  child: const Text('RETALHOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final provider = context.read<EstoqueProducaoProvider>();
                    if (_duasLinhasAtual == true) {
                      provider.carregarEstoqueAmbasLinhas();
                    } else {
                      provider.carregarEstoque();
                    }
                    provider.carregarHistorico();
                  },
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 2,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'Estoque'),
                  Tab(text: 'Histórico'),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // combinada=true (ADMIN/GERENTE/COMPRAS): uma única lista
                  // com as duas linhas juntas, cada material com uma coluna
                  // "Produção" indicando de qual linha ele é. combinada=false
                  // (PRODUCAO1/PRODUCAO2): só a própria linha, sem essa
                  // coluna extra (redundante, já que é sempre a mesma linha).
                  _EstoqueProducaoTab(combinada: _duasLinhasAtual == true),
                  const _HistoricoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ABA ESTOQUE — grade de categorias
// ─────────────────────────────────────────────────────────────────────

class _EstoqueTab extends StatefulWidget {
  const _EstoqueTab();

  @override
  State<_EstoqueTab> createState() => _EstoqueTabState();
}

class _EstoqueTabState extends State<_EstoqueTab> {
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria    = '';

  static IconData _iconePara(String categoria) {
    final c = categoria.toUpperCase();
    if (c.contains('LONA'))      return Icons.straighten;
    if (c.contains('BANNER'))    return Icons.flag;
    if (c.contains('VINIL'))     return Icons.layers;
    if (c.contains('PERFIL'))    return Icons.square_foot;
    if (c.contains('TINTA'))     return Icons.format_paint;
    if (c.contains('PAPEL'))     return Icons.description;
    if (c.contains('ACESSORIO')) return Icons.handyman;
    if (c.contains('COLA'))      return Icons.water_drop;
    if (c.contains('TECIDO'))    return Icons.texture;
    if (c.contains('MADEIRA'))   return Icons.foundation;
    if (c.contains('METAL'))     return Icons.hardware;
    return Icons.inventory_2;
  }

  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  @override
  void dispose() {
    _filtroCategoriaCtrl.dispose();
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => pularIdentificadores
            ? _ProducaoCategoriaPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
              )
            : _ProducaoIdentificadorPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
              ),
      ),
    ).then((_) {
      if (mounted) {
        final p = context.read<ProducaoProvider>();
        // Só recarrega se já tinha carregado com sucesso — evita que o retorno
        // da navegação sobrescreva um estado de erro e cause rebuild espúrio.
        if (p.categoriasCarregadas) p.carregarCategorias();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),

        SizedBox(
          width: 360,
          child: TextField(
            controller: _filtroCategoriaCtrl,
            decoration: InputDecoration(
              hintText:   'Buscar categoria...',
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
            child: Consumer<ProducaoProvider>(
              builder: (_, provider, __) {
                if (provider.carregandoCategorias && !provider.categoriasCarregadas) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                  );
                }

                if (provider.erroCategorias != null && !provider.categoriasCarregadas) {
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
                            provider.erroCategorias!,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => provider.carregarCategorias(),
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

                // Só exibe categorias fixas se o servidor já respondeu com sucesso
                final servidorOk = provider.categoriasCarregadas;

                bool corresponde(String label) =>
                    _filtroCategoria.isEmpty ||
                    label.toLowerCase().contains(_filtroCategoria);

                final cards = <Widget>[
                  if (servidorOk && corresponde('Geral'))
                    _CategoriaCardProducao(
                      categoria: 'Geral',
                      cor:       const Color(0xFF5E35B1),
                      icone:     Icons.grid_view_rounded,
                      onTap: () => _navegarParaCategoria(
                        categoriaId:    _kCategoriaGeral,
                        categoriaLabel: 'Geral',
                        cor:            const Color(0xFF5E35B1),
                        icone:          Icons.grid_view_rounded,
                      ),
                    ),
                  if (servidorOk && corresponde('Sem categoria'))
                    _CategoriaCardProducao(
                      categoria: 'Sem categoria',
                      cor:       const Color(0xFF546E7A),
                      icone:     Icons.help_outline,
                      onTap: () => _navegarParaCategoria(
                        categoriaId:    _kCategoriaSemCategoria,
                        categoriaLabel: 'Sem categoria',
                        cor:            const Color(0xFF546E7A),
                        icone:          Icons.help_outline,
                      ),
                    ),
                  for (int i = 0; i < provider.categorias.length; i++)
                    if (corresponde(provider.categorias[i]))
                      _CategoriaCardProducao(
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
                ];

                if (cards.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
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
                  children:         cards,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// CARD DE CATEGORIA
// ─────────────────────────────────────────────────────────────────────────────

class _CategoriaCardProducao extends StatefulWidget {
  final String     categoria;
  final Color      cor;
  final IconData   icone;
  final VoidCallback onTap;

  const _CategoriaCardProducao({
    required this.categoria,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_CategoriaCardProducao> createState() => _CategoriaCardProducaoState();
}

class _CategoriaCardProducaoState extends State<_CategoriaCardProducao> {
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
            color: ativo ? widget.cor.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo ? widget.cor : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
                ? [BoxShadow(color: widget.cor.withValues(alpha: 0.20), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
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

// ─────────────────────────────────────────────────────────────────────────────
// PÁGINA DE IDENTIFICADORES (nível 2 da hierarquia: categoria → identificador)
// ─────────────────────────────────────────────

class _ProducaoIdentificadorPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;

  const _ProducaoIdentificadorPage({
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
  });

  @override
  State<_ProducaoIdentificadorPage> createState() => _ProducaoIdentificadorPageState();
}

class _ProducaoIdentificadorPageState extends State<_ProducaoIdentificadorPage> {
  final _filtroCtrl = TextEditingController();
  String _filtro = '';
  bool _carregando = true;
  List<dynamic> _materiais = [];

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral)        return null;
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  static const _cores = [
    Color(0xFF1E88E5), Color(0xFF00897B), Color(0xFFE53935),
    Color(0xFFF4511E), Color(0xFF8E24AA), Color(0xFF039BE5),
    Color(0xFF43A047), Color(0xFFFFB300), Color(0xFF6D4C41),
    Color(0xFF546E7A), Color(0xFFD81B60), Color(0xFF5E35B1),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      await context.read<ProducaoProvider>().carregarMateriais(
        categoria: _categoriaParaProvider(),
      );
      if (!mounted) return;
      setState(() {
        _materiais = context.read<ProducaoProvider>().materiais;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<String?> _identificadoresUnicos() {
    final set = <String?>{};
    for (final m in _materiais) {
      final ident = m.identificador as String?;
      set.add(ident?.trim().isNotEmpty == true ? ident!.trim() : null);
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
      return _materiais.where((m) {
        final ident = m.identificador as String?;
        return ident == null || ident.trim().isEmpty;
      }).length;
    }
    return _materiais.where((m) => (m.identificador as String?)?.trim() == identificador).length;
  }

  void _navegarParaIdentificador({
    required String identificadorId,
    required String? identificadorReal,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProducaoCategoriaPage(
          categoriaId:                 widget.categoriaId,
          categoriaLabel:              widget.categoriaLabel,
          cor:                         widget.cor,
          icone:                       widget.icone,
          identificadorFiltro:         identificadorReal,
          identificadorLabel:          identificadorId == _kIdentificadorTodos
              ? null
              : identificadorId == _kIdentificadorSemIdentificador
                  ? 'Sem identificador'
                  : identificadorId,
          mostrarBotaoIdentificadores: true,
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
                  tooltip: 'Voltar para a lista de categorias',
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
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Campo de busca ────────────────────────────────────────────────
            SizedBox(
              width: 360,
              child: TextField(
                controller: _filtroCtrl,
                decoration: InputDecoration(
                  hintText:   'Buscar identificador...',
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
      cards.add(_IdentificadorCardProducao(
        label:      'Todos',
        quantidade: _materiais.length,
        cor:        widget.cor,
        icone:      Icons.grid_view_rounded,
        onTap: () => _navegarParaIdentificador(
          identificadorId:   _kIdentificadorTodos,
          identificadorReal: null,
        ),
      ));
    }

    // Identificadores reais
    for (int i = 0; i < identificadores.length; i++) {
      final ident = identificadores[i];
      final label = ident ?? 'Sem identificador';
      if (!corresponde(label)) continue;
      final cor = ident == null ? const Color(0xFF546E7A) : _cores[i % _cores.length];
      cards.add(_IdentificadorCardProducao(
        label:      label,
        quantidade: _contarMateriais(ident),
        cor:        cor,
        icone:      ident == null ? Icons.help_outline : Icons.qr_code,
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

// ─────────────────────────────────────────────
// CARD DE IDENTIFICADOR
// ─────────────────────────────────────────────

class _IdentificadorCardProducao extends StatefulWidget {
  final String     label;
  final int        quantidade;
  final Color      cor;
  final IconData   icone;
  final VoidCallback onTap;

  const _IdentificadorCardProducao({
    required this.label,
    required this.quantidade,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  @override
  State<_IdentificadorCardProducao> createState() => _IdentificadorCardProducaoState();
}

class _IdentificadorCardProducaoState extends State<_IdentificadorCardProducao> {
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
            color: ativo ? widget.cor.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ativo ? widget.cor : widget.cor.withValues(alpha: 0.25),
              width: ativo ? 2 : 1.5,
            ),
            boxShadow: ativo
                ? [BoxShadow(color: widget.cor.withValues(alpha: 0.20), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
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
                  color: ativo ? widget.cor.withValues(alpha: 0.8) : Theme.of(context).colorScheme.outline,
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

// ─────────────────────────────────────────────
// PÁGINA DE MATERIAIS POR CATEGORIA
// ─────────────────────────────────────────────────────────────────────────────

class _ProducaoCategoriaPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String?  identificadorFiltro;
  final String?  identificadorLabel;
  final bool     mostrarBotaoIdentificadores;

  const _ProducaoCategoriaPage({
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    this.identificadorFiltro,
    this.identificadorLabel,
    this.mostrarBotaoIdentificadores = false,
  });

  @override
  State<_ProducaoCategoriaPage> createState() => _ProducaoCategoriaPageState();
}

class _ProducaoCategoriaPageState extends State<_ProducaoCategoriaPage> {
  final _buscaCtrl         = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  String  _statusFiltro    = '';
  bool    _statusHovered   = false;
  Timer?  _debounce;

  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  String? _colunaOrdem;
  bool    _crescente = true;

  void _toggleOrdem(String sortKey) {
    setState(() {
      if (_colunaOrdem == sortKey) {
        _crescente = !_crescente;
      } else {
        _colunaOrdem = sortKey;
        _crescente   = true;
      }
    });
  }

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral)        return null;
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  @override
  void initState() {
    super.initState();
    if (widget.identificadorFiltro != null) {
      _identificadorCtrl.text = widget.identificadorFiltro!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarFiltros());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  void _aplicarFiltros() {
    setState(() {}); // atualiza estado do botão "Limpar filtros" imediatamente
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _paginaAtual = 0);
      context.read<ProducaoProvider>().carregarMateriais(
            busca:         _buscaCtrl.text.trim(),
            categoria:     _categoriaParaProvider(),
            status:        _statusFiltro.isEmpty ? null : _statusFiltro,
            identificador: _identificadorCtrl.text.trim(),
            medida:        _medidaCtrl.text.trim(),
            espessura:     _espessuraCtrl.text.trim(),
          );
    });
  }

  void _limparFiltros() {
    _buscaCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _espessuraCtrl.clear();
    setState(() => _statusFiltro = '');
    context.read<ProducaoProvider>().carregarMateriais(categoria: _categoriaParaProvider());
  }

  bool get _temFiltroAtivo =>
      _buscaCtrl.text.trim().isNotEmpty ||
      _identificadorCtrl.text.trim().isNotEmpty ||
      _medidaCtrl.text.trim().isNotEmpty ||
      _espessuraCtrl.text.trim().isNotEmpty ||
      _statusFiltro.isNotEmpty;

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
                _BotaoVoltar(
                  label: widget.mostrarBotaoIdentificadores
                      ? widget.categoriaLabel
                      : 'Categorias',
                  tooltip: 'Voltar para a lista de categorias',
                  onTap: () => Navigator.of(context).pop(),
                ),
                if (widget.mostrarBotaoIdentificadores && widget.identificadorLabel != null) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.outline),
                  ),
                  Text(
                    widget.identificadorLabel!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.cor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icone, color: widget.cor, size: 22),
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
                      'Solicitação e controle de materiais',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  onPressed: _aplicarFiltros,
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
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
                    decoration: InputDecoration(
                      hintText:   'Buscar material...',
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense:    true,
                    ),
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 12),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _statusHovered = true),
                  onExit:  (_) => setState(() => _statusHovered = false),
                  child: SizedBox(
                    width: 150,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        isDense:   true,
                      ),
                      isEmpty: _statusFiltro.isEmpty,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _statusFiltro.isEmpty ? null : _statusFiltro,
                          isDense: true,
                          isExpanded: true,
                          mouseCursor: SystemMouseCursors.click,
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: _statusHovered
                                ? AppTheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          items: const [
                            DropdownMenuItem(value: '',        child: Text('TODOS')),
                            DropdownMenuItem(value: 'OK',      child: Text('OK')),
                            DropdownMenuItem(value: 'LIMITE',  child: Text('LIMITE')),
                            DropdownMenuItem(value: 'CRITICO', child: Text('CRITICO')),
                          ],
                          onChanged: (v) {
                            setState(() => _statusFiltro = v ?? '');
                            _aplicarFiltros();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off, color: scheme.onSurfaceVariant),
                  onPressed: _temFiltroAtivo ? _limparFiltros : null,
                  style: IconButton.styleFrom(
                    side: BorderSide(color: scheme.outline),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return SystemMouseCursors.basic;
                      }
                      return SystemMouseCursors.click;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: InputDecoration(
                      hintText:   'Identificador...',
                      prefixIcon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: InputDecoration(
                      hintText:   'Medida...',
                      prefixIcon: Icon(Icons.straighten, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    inputFormatters: [_DecimalCommaFormatter()],
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: InputDecoration(
                      hintText:   'Espessura...',
                      prefixIcon: Icon(Icons.layers, color: Theme.of(context).colorScheme.outline, size: 18),
                      suffixText: 'mm',
                      isDense:    true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: Consumer<ProducaoProvider>(
                builder: (_, provider, __) {
                  // Só mostra o spinner no primeiro carregamento (lista ainda
                  // vazia). Em reloads subsequentes (troca de filtro/status,
                  // atualização manual) a lista antiga continua visível até
                  // os novos dados chegarem — evita trocar a lista pelo
                  // spinner e de volta a cada reload, que é o que causava o
                  // "piscar" ao selecionar categoria/filtros.
                  if (provider.carregandoMateriais && provider.materiais.isEmpty) {
                    return const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary));
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
                                ? provider.erro!.substring(
                                    provider.erro!.indexOf(': ') + 2)
                                : provider.erro!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => provider.carregarMateriais(),
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
                  if (provider.materiais.isEmpty) {
                    return Center(
                      child: Text(
                        'Nenhum material encontrado',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      ),
                    );
                  }

                  final todos        = _ordenarMateriaisProducao(provider.materiais, _colunaOrdem, _crescente);
                  final totalPaginas = (todos.length / _itensPorPagina).ceil();
                  final paginaSegura = _paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
                  final inicio       = paginaSegura * _itensPorPagina;
                  final fim          = (inicio + _itensPorPagina).clamp(0, todos.length);
                  final paginados    = todos.sublist(inicio, fim);

                  return Column(
                    children: [
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: _TabelaMateriais(
                            materiais: paginados,
                            mostrarCategoria: widget.categoriaId == _kCategoriaGeral,
                            colunaOrdem: _colunaOrdem,
                            crescente: _crescente,
                            onToggleOrdem: _toggleOrdem,
                          ),
                        ),
                      ),
                      if (totalPaginas > 1) ...[
                        const SizedBox(height: 12),
                        _BarraPaginacao(
                          paginaAtual:     paginaSegura,
                          totalPaginas:    totalPaginas,
                          totalItens:      todos.length,
                          itensPorPagina:  _itensPorPagina,
                          onPaginaChanged: (p) => setState(() => _paginaAtual = p),
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

// ─────────────────────────────────────────────────────────────────────────────
// TABELA DE MATERIAIS
// ─────────────────────────────────────────────────────────────────────────────

class _ColDef {
  final String label;
  final double? fixed;
  final double? flex;
  /// Identificador de ordenação; null = coluna não ordenável
  final String? sortKey;
  const _ColDef({required this.label, this.fixed, this.flex, this.sortKey});
}

// ─────────────────────────────────────────────────────────────────────────────
// CABEÇALHO ORDENÁVEL (compartilhado pelas tabelas da página de Produção)
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

int _compareNullableStr(String? a, String? b) =>
    (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());

int _compareNullableNum(num? a, num? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}

/// Ordena a lista de materiais de produção conforme a chave de ordenação
/// selecionada (label da coluna clicada) e a direção.
List<MaterialProducaoModel> _ordenarMateriaisProducao(
  List<MaterialProducaoModel> lista,
  String? sortKey,
  bool crescente,
) {
  if (sortKey == null) return lista;
  final copia = List<MaterialProducaoModel>.from(lista);
  int cmp(MaterialProducaoModel a, MaterialProducaoModel b) {
    switch (sortKey) {
      case 'id':            return a.id.compareTo(b.id);
      case 'identificador':  return _compareNullableStr(a.identificador, b.identificador);
      case 'nome':           return _compareNullableStr(a.nome, b.nome);
      case 'categoria':      return _compareNullableStr(a.categoria, b.categoria);
      case 'medida':         return _compareNullableStr(a.medida, b.medida);
      case 'espessura':      return _compareNullableStr(a.espessura, b.espessura);
      case 'comprimento':    return _compareNullableNum(a.comprimento, b.comprimento);
      case 'largura':        return _compareNullableNum(a.largura, b.largura);
      case 'quantidade':     return a.quantidade.compareTo(b.quantidade);
      case 'unidade':        return _compareNullableStr(a.unidade, b.unidade);
      case 'statusReal':     return _compareNullableStr(a.statusReal, b.statusReal);
      default:               return 0;
    }
  }
  copia.sort((a, b) => crescente ? cmp(a, b) : cmp(b, a));
  return copia;
}

class _TabelaMateriais extends StatefulWidget {
  final List<MaterialProducaoModel> materiais;
  final bool mostrarCategoria;
  final String? colunaOrdem;
  final bool crescente;
  final void Function(String sortKey) onToggleOrdem;

  const _TabelaMateriais({
    required this.materiais,
    this.mostrarCategoria = true,
    required this.colunaOrdem,
    required this.crescente,
    required this.onToggleOrdem,
  });

  static const List<_ColDef> _todosColsDef = [
    _ColDef(label: 'Identificador', flex: 0.9, sortKey: 'identificador'),
    _ColDef(label: 'Material',      flex: 2.0, sortKey: 'nome'),
    _ColDef(label: 'Categoria',     flex: 1.0, sortKey: 'categoria'),
    _ColDef(label: 'Medida',        flex: 0.8, sortKey: 'medida'),
    _ColDef(label: 'Espessura',     flex: 0.7, sortKey: 'espessura'),
    _ColDef(label: 'Comprimento',   flex: 0.8, sortKey: 'comprimento'),
    _ColDef(label: 'Largura',       flex: 0.8, sortKey: 'largura'),
    _ColDef(label: 'Estoque atual', flex: 0.7, sortKey: 'quantidade'),
    _ColDef(label: 'Unidade',       flex: 0.9, sortKey: 'unidade'),
    _ColDef(label: 'Status',        flex: 0.8, sortKey: 'statusReal'),
  ];

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  @override
  State<_TabelaMateriais> createState() => _TabelaMateriaisState();
}

class _TabelaMateriaisState extends State<_TabelaMateriais> {
  List<_ColDef> get _cols => widget.mostrarCategoria
      ? _TabelaMateriais._todosColsDef
      : _TabelaMateriais._todosColsDef.where((c) => c.label != 'Categoria').toList();

  Widget _cabecalho() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            for (final col in _cols)
              _TabelaMateriais._colWrap(
                col,
                col.sortKey != null
                    ? _CabecalhoOrdenavel(
                        label:     col.label,
                        ativo:     widget.colunaOrdem == col.sortKey,
                        crescente: widget.crescente,
                        onTap:     () => widget.onToggleOrdem(col.sortKey!),
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
    final cols      = _cols;
    final materiais = widget.materiais;

    Widget corpoRolavel = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < materiais.length; i++) ...[
            if (i > 0)
              Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
            _LinhaMateria(
              material: materiais[i],
              cols: cols,
              mostrarCategoria: widget.mostrarCategoria,
            ),
          ],
          if (materiais.isNotEmpty)
            Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho fixo — não entra no scroll vertical
        _cabecalho(),
        Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
        // Corpo rolável ocupa o espaço restante
        Expanded(child: corpoRolavel),
      ],
    );
  }
}

class _LinhaMateria extends StatefulWidget {
  final MaterialProducaoModel material;
  final List<_ColDef> cols;
  final bool mostrarCategoria;

  const _LinhaMateria({
    required this.material,
    required this.cols,
    this.mostrarCategoria = true,
  });

  @override
  State<_LinhaMateria> createState() => _LinhaMateriaState();
}

class _LinhaMateriaState extends State<_LinhaMateria> {
  bool _hovered = false;

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  Widget _cell(String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
        ),
      );

  Widget _vDivider() => VerticalDivider(
        width: 1, thickness: 0.5, color: Theme.of(context).colorScheme.outlineVariant,
      );

  void _abrirSolicitacao(BuildContext context) {
    final role = context.read<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    if (role == 'COMPRAS') return;
    showDialog(
      context: context,
      builder: (_) => _SolicitarMaterialDialog(material: widget.material),
    );
  }

  static String _fmtDim(double? v) {
    if (v == null) return '—';
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final m          = widget.material;
    final cols       = widget.cols;

    final role       = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    final podeOperar = role != 'COMPRAS';

    final bgColor = _hovered && podeOperar
        ? Color(0xFF009800).withValues(alpha: 0.10)
        : Theme.of(context).colorScheme.surface;

    // Índice incremental — evita erros de offset manual quando a coluna
    // "Categoria" é ocultada (widget.mostrarCategoria == false).
    var i = 0;
    Widget nextCol(Widget child) => _colWrap(cols[i++], child);

    return MouseRegion(
      cursor: podeOperar ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: podeOperar ? () => _abrirSolicitacao(context) : null,
        child: ColoredBox(
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                nextCol(Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    m.nome,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                )),
                _vDivider(),

                if (widget.mostrarCategoria) ...[
                  nextCol(_cell(m.categoria ?? '—')),
                  _vDivider(),
                ],

                nextCol(_cell(m.medida ?? '—')),
                _vDivider(),

                nextCol(_cell(_fmtEspessura(m.espessura) ?? '—')),
                _vDivider(),

                nextCol(_cell(_fmtDim(m.comprimento))),
                _vDivider(),

                nextCol(_cell(_fmtDim(m.largura))),
                _vDivider(),

                nextCol(_cell(
                  m.quantidade.toStringAsFixed(m.quantidade % 1 == 0 ? 0 : 2),
                )),
                _vDivider(),

                nextCol(_cell(formatarUnidadeExibicao(m.unidade).isEmpty ? '—' : formatarUnidadeExibicao(m.unidade))),
                _vDivider(),

                nextCol(Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: _StatusBadge(status: m.statusReal),
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color cor;
    switch (status) {
      case 'OK':      cor = AppTheme.statusOk;      break;
      case 'LIMITE':  cor = AppTheme.statusBaixo;   break;
      case 'CRITICO': cor = AppTheme.statusCritico; break;
      default:        cor = Theme.of(context).colorScheme.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG — SOLICITAR MATERIAL (baixa imediata)
// ─────────────────────────────────────────────

class _SolicitarMaterialDialog extends StatefulWidget {
  final MaterialProducaoModel material;
  const _SolicitarMaterialDialog({required this.material});

  @override
  State<_SolicitarMaterialDialog> createState() =>
      _SolicitarMaterialDialogState();
}

class _SolicitarMaterialDialogState extends State<_SolicitarMaterialDialog> {
  final _formKey     = GlobalKey<FormState>();
  final _osCtrl      = TextEditingController();
  final _qtdCtrl     = TextEditingController();
  final _obsCtrl     = TextEditingController();
  final _larguraCtrl = TextEditingController();
  final _alturaCtrl  = TextEditingController();
  bool  _enviando         = false;
  bool  _modoDimensional  = false;
  String? _erro;

  @override
  void dispose() {
    _osCtrl.dispose();
    _qtdCtrl.dispose();
    _obsCtrl.dispose();
    _larguraCtrl.dispose();
    _alturaCtrl.dispose();
    super.dispose();
  }

  /// True se a unidade do material é metro linear (m, m/l, ml, etc.).
  bool get _eMetroLinear {
    final u = widget.material.unidade?.toLowerCase().trim() ?? '';
    return const {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'}.contains(u);
  }

  /// True se o material é UNIDADE (chapa/peça) e tem largura + comprimento
  /// cadastrados.
  bool get _podeInformarDimensao {
    final m = widget.material;
    if (_eMetroLinear) return false;
    return (m.unidade?.toUpperCase() == 'UNIDADE') &&
        m.largura != null && m.largura! > 0 &&
        m.comprimento != null && m.comprimento! > 0;
  }

  /// Custo por m² sugerido para este material (gravado ou derivado do
  /// custo unitário / área da chapa).
  double? get _custoM2Sugerido {
    final m = widget.material;
    final custoM2Gravado = m.ultimoValorPagoM2;
    if (custoM2Gravado != null && custoM2Gravado > 0) return custoM2Gravado;

    final larg = m.largura;
    final comp = m.comprimento;
    if (larg != null && comp != null && larg > 0 && comp > 0) {
      final pu = m.ultimoValorPago;
      if (pu != null && pu > 0) return pu / (larg * comp);
    }
    return null;
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    final os = _osCtrl.text.trim();
    
    final qtd = _modoDimensional 
        ? 1.0 
        : double.tryParse(_qtdCtrl.text.replaceAll(',', '.'));

    if (qtd == null || qtd <= 0) {
      setState(() => _erro = 'Quantidade inválida');
      return;
    }

    setState(() { _enviando = true; _erro = null; });

    double? largUsada;
    double? compUsado;
    if (_modoDimensional && _podeInformarDimensao) {
      final l = double.tryParse(_larguraCtrl.text.replaceAll(',', '.'));
      final c = double.tryParse(_alturaCtrl.text.replaceAll(',', '.'));
      if (l != null && l > 0 && c != null && c > 0) {
        if (l > widget.material.largura! || c > widget.material.comprimento!) {
          setState(() {
            _enviando = false;
            _erro = 'Dimensão usada não pode ultrapassar a da chapa '
                '(${_fmt(widget.material.comprimento!)}×${_fmt(widget.material.largura!)} m)';
          });
          return;
        }
        largUsada = l;
        compUsado = c;
      }
    }

    final ok = await context.read<ProducaoProvider>().criarSolicitacao(
          materialId:          widget.material.id,
          quantidadeReservada: qtd,
          numeroOS:            os,
          larguraUsada:        largUsada,
          comprimentoUsado:    compUsado,
        );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material baixado com sucesso'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() =>
          _erro = context.read<ProducaoProvider>().erro ?? 'Erro ao solicitar');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final disponivel = m.quantidade + m.emUso;
    final unidade = formatarUnidadeExibicao(m.unidade);

    final detalhes = <String>[];
    if (m.identificador != null && m.identificador!.isNotEmpty) {
      detalhes.add(m.identificador!);
    }
    if (m.medida != null && m.medida!.isNotEmpty) {
      detalhes.add(m.medida!);
    } else {
      final comp = m.comprimento;
      final larg = m.largura;
      if (comp != null && comp > 0 && larg != null && larg > 0) {
        detalhes.add('${_fmt(comp)}x${_fmt(larg)}m');
      } else if (comp != null && comp > 0) {
        detalhes.add('${_fmt(comp)}m');
      } else if (larg != null && larg > 0) {
        detalhes.add('${_fmt(larg)}m');
      }
    }
    if (m.espessura != null) detalhes.add(_fmtEspessura(m.espessura)!);

    return AlertDialog(
      title: const Text('Baixa de Material'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    m.nome,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (detalhes.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detalhes.join(' · '),
                        style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _osCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número da OS *',
                  isDense:   true,
                ),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseFormatter()],
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Informe a OS' : null,
              ),
              const SizedBox(height: 12),

              Builder(builder: (_) {
                final m = widget.material;
                if (!_podeInformarDimensao) {
                  return const SizedBox.shrink();
                }
                final largura     = m.largura!;
                final comprimento = m.comprimento!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: _modoDimensional
                          ? 'Desativar e informar a quantidade diretamente'
                          : 'Ativar para calcular pela dimensão usada da chapa',
                      child: InkWell(
                        onTap: () => setState(() {
                          _modoDimensional = !_modoDimensional;
                          if (_modoDimensional) {
                            _qtdCtrl.text = '1';
                            _larguraCtrl.clear();
                            _alturaCtrl.clear();
                          } else {
                            _larguraCtrl.clear();
                            _alturaCtrl.clear();
                            _qtdCtrl.clear();
                          }
                        }),
                        borderRadius: BorderRadius.circular(6),
                        mouseCursor: SystemMouseCursors.click,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _modoDimensional
                                    ? Icons.toggle_on
                                    : Icons.toggle_off_outlined,
                                size: 20,
                                color: _modoDimensional
                                    ? AppTheme.primary
                                    : Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Informar dimensão usada',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _modoDimensional
                                      ? AppTheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Chapa ${_fmt(comprimento)}×${_fmt(largura)} m',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (_modoDimensional) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _alturaCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Comprimento usado (m)',
                                isDense:    true,
                                suffixText: '/ ${_fmt(comprimento)} m',
                                suffixStyle: TextStyle(
                                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
                              ),
                              onChanged: (_) => setState(() {
                                _limitarDimensao(_alturaCtrl, comprimento);
                              }),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('×',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _larguraCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Largura usada (m)',
                                isDense:    true,
                                suffixText: '/ ${_fmt(largura)} m',
                                suffixStyle: TextStyle(
                                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
                              ),
                              onChanged: (_) => setState(() {
                                _limitarDimensao(_larguraCtrl, largura);
                              }),
                            ),
                          ),
                        ],
                      ),

                      Builder(builder: (_) {
                        final comp = double.tryParse(
                            _alturaCtrl.text.replaceAll(',', '.'));
                        final larg = double.tryParse(
                            _larguraCtrl.text.replaceAll(',', '.'));
                        if (larg == null || larg <= 0 ||
                            comp == null || comp <= 0) {
                          return const SizedBox.shrink();
                        }
                        final areaUsada   = larg * comp;
                        final areaTotal   = largura * comprimento;
                        final areaRetalho = double.parse(
                            (areaTotal - areaUsada).toStringAsFixed(4));
                        final temRetalho  = areaRetalho > 0.0001;

                        final custoM2 = _custoM2Sugerido;
                        final custoProporcional =
                            (custoM2 != null && custoM2 > 0)
                                ? custoM2 * areaUsada
                                : null;

                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.20)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calculate_outlined,
                                  size: 14, color: AppTheme.primary),
                              SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    children: [
                                      TextSpan(text: 'Área usada: '),
                                      TextSpan(
                                        text: '${_fmt(areaUsada)} m²',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context).colorScheme.onSurface),
                                      ),
                                      if (temRetalho) ...[
                                        TextSpan(text: '  ·  Retalho: '),
                                        TextSpan(
                                          text: '${_fmt(areaRetalho)} m²',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.success),
                                        ),
                                      ],
                                      if (custoProporcional != null) ...[
                                        TextSpan(text: '  ·  Custo: '),
                                        TextSpan(
                                          text: _brl6(custoProporcional),
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.error),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 4),
                  ],
                );
              }),

              TextFormField(
                controller: _qtdCtrl,
                decoration: InputDecoration(
                  labelText: 'Quantidade *',
                  isDense:   true,
                  suffixText: unidade,
                  helperText: _modoDimensional
                      ? 'Bloqueado: quantidade fixa em 1'
                      : null,
                  helperStyle: TextStyle(
                      fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                readOnly: _modoDimensional,
                validator: (v) {
                  if (_erro != null) return _erro;
                  final qtd =
                      double.tryParse((v ?? '').replaceAll(',', '.'));
                  if (qtd == null || qtd <= 0) return 'Quantidade inválida';
                  return null;
                },
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
              ),
              SizedBox(height: 8),
              Text(
                'Disponível: ${disponivel.toStringAsFixed(disponivel % 1 == 0 ? 0 : 2)} $unidade',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _obsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  isDense:   true,
                ),
                maxLines: 2,
              ),

              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(
                  _erro!,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.statusCritico),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Tooltip(
          message: 'Cancelar e fechar sem enviar',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Cancelar'),
          ),
        ),
        Tooltip(
          message: 'Confirmar a saída deste material',
          child: FilledButton(
            onPressed: _enviando ? null : _confirmar,
            style: ButtonStyle(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirmar Saída'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ABA HISTÓRICO
// ─────────────────────────────────────────────────────────────────────────

/// Item genérico da timeline unificada de histórico: pode representar tanto
/// uma OS finalizada (SolicitacaoProducaoModel) quanto uma movimentação do
/// estoque de produção (MovimentacaoProducaoModel — transferência/baixa/estorno).
class _HistoricoItem {
  final DateTime data;
  final SolicitacaoProducaoModel? solicitacao;
  final MovimentacaoProducaoModel? movimentacao;

  _HistoricoItem.solicitacao(SolicitacaoProducaoModel s)
      : data = s.finalizadoEm ?? s.atualizadoEm,
        solicitacao = s,
        movimentacao = null;

  _HistoricoItem.movimentacao(MovimentacaoProducaoModel m)
      : data = m.criadoEm,
        solicitacao = null,
        movimentacao = m;
}

class _HistoricoTab extends StatefulWidget {
  const _HistoricoTab();

  @override
  State<_HistoricoTab> createState() => _HistoricoTabState();
}

class _HistoricoTabState extends State<_HistoricoTab> {
  final _buscaCtrl = TextEditingController();
  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _buscar(String v) {
    setState(() => _paginaAtual = 0);
    final busca = v.trim();
    context.read<ProducaoProvider>().carregarHistorico(busca: busca);
    context.read<EstoqueProducaoProvider>().carregarHistorico(busca: busca);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 16),
        TextField(
          controller: _buscaCtrl,
          decoration: InputDecoration(
            hintText:   'Buscar por material, OS ou usuário...',
            prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
            isDense:    true,
          ),
          onChanged: _buscar,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Consumer2<ProducaoProvider, EstoqueProducaoProvider>(
            builder: (_, producaoProv, estoqueProv, __) {
              final carregando = producaoProv.carregandoHistorico || estoqueProv.carregandoHistorico;
              if (carregando) {
                return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary));
              }

              // Solicitações (baixas pelo estoque padrão, aba "Estoque") e
              // movimentações do estoque de produção (aba "Estoque Produção")
              // são gravadas em tabelas totalmente independentes no backend —
              // mesmo quando referenciam a mesma OS, uma nunca é espelho da
              // outra. Por isso a timeline unificada apenas concatena as duas
              // listas. (Antes havia um filtro que escondia a solicitação
              // sempre que a mesma OS também tivesse uma baixa do estoque de
              // produção, o que descartava baixas legítimas do estoque
              // padrão.)
              final itens = <_HistoricoItem>[
                ...producaoProv.historico.map((s) => _HistoricoItem.solicitacao(s)),
                ...estoqueProv.historico.map((m) => _HistoricoItem.movimentacao(m)),
              ]..sort((a, b) => b.data.compareTo(a.data));

              if (itens.isEmpty) {
                return Center(
                  child: Text(
                    'Nenhuma movimentação registrada ainda',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                );
              }

              final totalPaginas = (itens.length / _itensPorPagina).ceil();
              final paginaSegura = _paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
              final inicio       = paginaSegura * _itensPorPagina;
              final fim          = (inicio + _itensPorPagina).clamp(0, itens.length);
              final paginados    = itens.sublist(inicio, fim);

              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: paginados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = paginados[i];
                        if (item.solicitacao != null) {
                          return _HistoricoCard(solicitacao: item.solicitacao!);
                        }
                        return _MovimentacaoEstoqueProducaoCard(movimentacao: item.movimentacao!);
                      },
                    ),
                  ),
                  if (totalPaginas > 1) ...[
                    const SizedBox(height: 12),
                    _BarraPaginacao(
                      paginaAtual:     paginaSegura,
                      totalPaginas:    totalPaginas,
                      totalItens:      itens.length,
                      itensPorPagina:  _itensPorPagina,
                      onPaginaChanged: (p) => setState(() => _paginaAtual = p),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// CARD DO HISTÓRICO
// ─────────────────────────────────────────────

class _HistoricoCard extends StatelessWidget {
  final SolicitacaoProducaoModel solicitacao;
  const _HistoricoCard({required this.solicitacao});

  // Datas já chegam convertidas para fuso local via .toLocal() no model.

  Future<void> _confirmarExclusao(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro'),
        content: Text(
          'Excluir o histórico da OS ${solicitacao.numeroOS}?\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom().copyWith(
                mouseCursor:
                    WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                .copyWith(
                    mouseCursor: WidgetStateProperty.all(
                        SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true || !context.mounted) return;

    final ok = await context
        .read<ProducaoProvider>()
        .excluirHistorico(solicitacao.id);

    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<ProducaoProvider>().erro ?? 'Erro ao excluir',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s      = solicitacao;
    final data   = s.finalizadoEm ?? s.atualizadoEm;
    final dataStr = '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year} '
        '${data.hour.toString().padLeft(2, '0')}:'
        '${data.minute.toString().padLeft(2, '0')}';

    final detalhes = <String>[];
    if (s.materialIdentificador != null&& s.materialIdentificador!.isNotEmpty) {
      detalhes.add(s.materialIdentificador!);
    }
    if (s.materialMedida != null) detalhes.add(s.materialMedida!);
    if (s.materialEspessura != null) detalhes.add(_fmtEspessura(s.materialEspessura)!);

    final role = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    final podeExcluir = role == 'ADMIN' || role == 'GERENTE';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.call_made,
                  color: AppTheme.error, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Baixa para OS ${s.numeroOS}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    s.materialNome,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (detalhes.isNotEmpty)
                    Text(
                      detalhes.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (s.descricaoItem != null)
                    Text(
                      s.descricaoItem!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (s.baixas.isNotEmpty && s.baixas.last.observacao != null)
                    Text(
                      s.baixas.last.observacao!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  Text(
                    'Usuário: ${s.usuarioNome}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '-${s.quantidadeUsada.toStringAsFixed(s.quantidadeUsada % 1 == 0 ? 0 : 2)} ${formatarUnidadeExibicao(s.materialUnidade)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.error,
                  ),
                ),
                Text(
                  dataStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                if (podeExcluir) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Tooltip(
                      message: 'Excluir registro',
                      child: IconButton(
                        onPressed: () => _confirmarExclusao(context),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.error.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: AppTheme.error,
                          ),
                        ),
                        style: IconButton.styleFrom().copyWith(
                            mouseCursor: WidgetStateProperty.all(
                                SystemMouseCursors.click)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINAÇÃO
// ─────────────────────────────────────────────

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
            'Exibindo $inicio–$fim de $totalItens',
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
// ═════════════════════════════════════════════════════════════════════════
// ABA: Estoque Produção — materiais transferidos do estoque normal,
// disponíveis para dar baixa em uma OS.
// ═════════════════════════════════════════════════════════════════════════
String _fmtQtdProducao(double v) =>
    v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

// ─────────────────────────────────────────────
// ABA: Estoque Produção — nível 1 da hierarquia (categorias)
// ─────────────────────────────────────────────

class _EstoqueProducaoTab extends StatefulWidget {
  /// true para ADMIN/GERENTE/COMPRAS: exibe a lista COMBINADA das duas
  /// linhas de produção (1 e 2 juntas), com uma coluna extra "Produção"
  /// identificando de qual linha cada material é. false para PRODUCAO1/
  /// PRODUCAO2: exibe apenas a própria linha (a "ativa" do provider), sem
  /// a coluna extra.
  final bool combinada;

  const _EstoqueProducaoTab({required this.combinada});

  @override
  State<_EstoqueProducaoTab> createState() => _EstoqueProducaoTabState();
}

class _EstoqueProducaoTabState extends State<_EstoqueProducaoTab> {
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria    = '';

  static IconData _iconePara(String categoria) {
    final c = categoria.toUpperCase();
    if (c.contains('LONA'))      return Icons.straighten;
    if (c.contains('BANNER'))    return Icons.flag;
    if (c.contains('VINIL'))     return Icons.layers;
    if (c.contains('PERFIL'))    return Icons.square_foot;
    if (c.contains('TINTA'))     return Icons.format_paint;
    if (c.contains('PAPEL'))     return Icons.description;
    if (c.contains('ACESSORIO')) return Icons.handyman;
    if (c.contains('COLA'))      return Icons.water_drop;
    if (c.contains('TECIDO'))    return Icons.texture;
    if (c.contains('MADEIRA'))   return Icons.foundation;
    if (c.contains('METAL'))     return Icons.hardware;
    return Icons.inventory_2;
  }

  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  @override
  void dispose() {
    _filtroCategoriaCtrl.dispose();
    super.dispose();
  }

  List<String> _categoriasUnicas(List<MaterialEstoqueProducaoModel> estoque) {
    final set = <String>{};
    for (final m in estoque) {
      if (m.categoria != null && m.categoria!.trim().isNotEmpty) {
        set.add(m.categoria!.trim());
      }
    }
    final lista = set.toList()..sort();
    return lista;
  }

  bool _temSemCategoria(List<MaterialEstoqueProducaoModel> estoque) =>
      estoque.any((m) => m.categoria == null || m.categoria!.trim().isEmpty);

  void _navegarParaCategoria({
    required String categoriaId,
    required String categoriaLabel,
    required Color cor,
    required IconData icone,
  }) {
    final pularIdentificadores =
        categoriaId == _kCategoriaGeral ||
        categoriaId == _kCategoriaSemCategoria;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => pularIdentificadores
            ? _EstoqueProducaoCategoriaPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
                combinada:      widget.combinada,
              )
            : _EstoqueProducaoIdentificadorPage(
                categoriaId:    categoriaId,
                categoriaLabel: categoriaLabel,
                cor:            cor,
                icone:          icone,
                combinada:      widget.combinada,
              ),
      ),
    ).then((_) {
      if (mounted) {
        final provider = context.read<EstoqueProducaoProvider>();
        if (widget.combinada) {
          provider.carregarEstoqueAmbasLinhas();
        } else {
          provider.carregarEstoque();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProducaoProvider>();
    // combinada=true (ADMIN/GERENTE/COMPRAS): lista das duas linhas juntas.
    // combinada=false (PRODUCAO1/PRODUCAO2): só a linha "ativa" do usuário.
    final estoqueLista = widget.combinada
        ? provider.estoqueCombinado
        : provider.estoque;
    final carregando = widget.combinada
        ? provider.carregandoEstoqueCombinado
        : provider.carregandoEstoque;
    final erro = widget.combinada
        ? provider.erroEstoqueCombinado
        : provider.erro;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              controller: _filtroCategoriaCtrl,
              decoration: InputDecoration(
                hintText:   'Buscar categoria...',
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
            child: carregando
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : erro != null && estoqueLista.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
                            SizedBox(height: 12),
                            Text(
                              'Erro ao carregar estoque de produção',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 4),
                            Text(
                              erro,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => widget.combinada
                                  ? provider.carregarEstoqueAmbasLinhas()
                                  : provider.carregarEstoque(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Tentar novamente'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                            ),
                          ],
                        ),
                      )
                    : estoqueLista.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.factory_outlined, size: 40, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
                                const SizedBox(height: 10),
                                Text(
                                  'Nenhum material na sua produção.\nUse "Saída p/ Produção" no Controle de Estoque para transferir.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: Builder(builder: (context) {
                              final categorias     = _categoriasUnicas(estoqueLista);
                              final temSemCategoria = _temSemCategoria(estoqueLista);

                              bool corresponde(String label) =>
                                  _filtroCategoria.isEmpty ||
                                  label.toLowerCase().contains(_filtroCategoria);

                              final cards = <Widget>[
                                if (corresponde('Geral'))
                                  _CategoriaCardProducao(
                                    categoria: 'Geral',
                                    cor:       const Color(0xFF5E35B1),
                                    icone:     Icons.grid_view_rounded,
                                    onTap: () => _navegarParaCategoria(
                                      categoriaId:    _kCategoriaGeral,
                                      categoriaLabel: 'Geral',
                                      cor:            const Color(0xFF5E35B1),
                                      icone:          Icons.grid_view_rounded,
                                    ),
                                  ),
                                if (temSemCategoria && corresponde('Sem categoria'))
                                  _CategoriaCardProducao(
                                    categoria: 'Sem categoria',
                                    cor:       const Color(0xFF546E7A),
                                    icone:     Icons.help_outline,
                                    onTap: () => _navegarParaCategoria(
                                      categoriaId:    _kCategoriaSemCategoria,
                                      categoriaLabel: 'Sem categoria',
                                      cor:            const Color(0xFF546E7A),
                                      icone:          Icons.help_outline,
                                    ),
                                  ),
                                for (int i = 0; i < categorias.length; i++)
                                  if (corresponde(categorias[i]))
                                    _CategoriaCardProducao(
                                      categoria: categorias[i],
                                      cor:       _cores[i % _cores.length],
                                      icone:     _iconePara(categorias[i]),
                                      onTap: () => _navegarParaCategoria(
                                        categoriaId:    categorias[i],
                                        categoriaLabel: categorias[i],
                                        cor:            _cores[i % _cores.length],
                                        icone:          _iconePara(categorias[i]),
                                      ),
                                    ),
                              ];

                              if (cards.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 80),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
                                        SizedBox(height: 16),
                                        Text(
                                          'Nenhuma categoria encontrada',
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
                                children:         cards,
                              );
                            }),
                          ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ESTOQUE PRODUÇÃO — PÁGINA DE IDENTIFICADORES (nível 2)
// ─────────────────────────────────────────────

class _EstoqueProducaoIdentificadorPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final bool     combinada;

  const _EstoqueProducaoIdentificadorPage({
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    required this.combinada,
  });

  @override
  State<_EstoqueProducaoIdentificadorPage> createState() => _EstoqueProducaoIdentificadorPageState();
}

class _EstoqueProducaoIdentificadorPageState extends State<_EstoqueProducaoIdentificadorPage> {
  final _filtroCtrl = TextEditingController();
  String _filtro = '';

  static const _cores = [
    Color(0xFF1E88E5), Color(0xFF00897B), Color(0xFFE53935),
    Color(0xFFF4511E), Color(0xFF8E24AA), Color(0xFF039BE5),
    Color(0xFF43A047), Color(0xFFFFB300), Color(0xFF6D4C41),
    Color(0xFF546E7A), Color(0xFFD81B60), Color(0xFF5E35B1),
  ];

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  List<MaterialEstoqueProducaoModel> _materiaisDaCategoria(EstoqueProducaoProvider provider) {
    final lista = widget.combinada ? provider.estoqueCombinado : provider.estoque;
    return lista.where((m) => (m.categoria?.trim() ?? '') == widget.categoriaId).toList();
  }

  List<String?> _identificadoresUnicos(List<MaterialEstoqueProducaoModel> materiais) {
    final set = <String?>{};
    for (final m in materiais) {
      final ident = m.identificador;
      set.add(ident?.trim().isNotEmpty == true ? ident!.trim() : null);
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

  int _contarMateriais(List<MaterialEstoqueProducaoModel> materiais, String? identificador) {
    if (identificador == null) {
      return materiais.where((m) => m.identificador == null || m.identificador!.trim().isEmpty).length;
    }
    return materiais.where((m) => m.identificador?.trim() == identificador).length;
  }

  void _navegarParaIdentificador({
    required String identificadorId,
    required String? identificadorReal,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EstoqueProducaoCategoriaPage(
          categoriaId:                 widget.categoriaId,
          categoriaLabel:              widget.categoriaLabel,
          cor:                         widget.cor,
          icone:                       widget.icone,
          identificadorFiltro:         identificadorReal,
          identificadorLabel:          identificadorId == _kIdentificadorTodos
              ? null
              : identificadorId == _kIdentificadorSemIdentificador
                  ? 'Sem identificador'
                  : identificadorId,
          mostrarBotaoIdentificadores: true,
          combinada:                   widget.combinada,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProducaoProvider>();
    final materiais = _materiaisDaCategoria(provider);

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
                  tooltip: 'Voltar para a lista de categorias',
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
                  onPressed: () {
                    final provider = context.read<EstoqueProducaoProvider>();
                    widget.combinada
                        ? provider.carregarEstoqueAmbasLinhas()
                        : provider.carregarEstoque();
                  },
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: 360,
              child: TextField(
                controller: _filtroCtrl,
                decoration: InputDecoration(
                  hintText:   'Buscar identificador...',
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
              child: (widget.combinada
                      ? provider.carregandoEstoqueCombinado
                      : provider.carregandoEstoque)
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _buildGrid(materiais),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<MaterialEstoqueProducaoModel> materiais) {
    final identificadores = _identificadoresUnicos(materiais);

    bool corresponde(String label) =>
        _filtro.isEmpty || label.toLowerCase().contains(_filtro);

    final cards = <Widget>[];

    if (corresponde('todos')) {
      cards.add(_IdentificadorCardProducao(
        label:      'Todos',
        quantidade: materiais.length,
        cor:        widget.cor,
        icone:      Icons.grid_view_rounded,
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
      final cor = ident == null ? const Color(0xFF546E7A) : _cores[i % _cores.length];
      cards.add(_IdentificadorCardProducao(
        label:      label,
        quantidade: _contarMateriais(materiais, ident),
        cor:        cor,
        icone:      ident == null ? Icons.help_outline : Icons.qr_code,
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

// ─────────────────────────────────────────────
// ESTOQUE PRODUÇÃO — PÁGINA DE MATERIAIS POR CATEGORIA (nível 3, com busca completa)
// ─────────────────────────────────────────────

class _EstoqueProducaoCategoriaPage extends StatefulWidget {
  final String   categoriaId;
  final String   categoriaLabel;
  final Color    cor;
  final IconData icone;
  final String?  identificadorFiltro;
  final String?  identificadorLabel;
  final bool     mostrarBotaoIdentificadores;
  /// true para ADMIN/GERENTE/COMPRAS: exibe a lista COMBINADA das duas
  /// linhas de produção (1 e 2 juntas), com a coluna extra "Produção".
  /// false para PRODUCAO1/PRODUCAO2: exibe apenas a própria linha ativa.
  final bool     combinada;

  const _EstoqueProducaoCategoriaPage({
    required this.categoriaId,
    required this.categoriaLabel,
    required this.cor,
    required this.icone,
    this.identificadorFiltro,
    this.identificadorLabel,
    this.mostrarBotaoIdentificadores = false,
    required this.combinada,
  });

  @override
  State<_EstoqueProducaoCategoriaPage> createState() => _EstoqueProducaoCategoriaPageState();
}

class _EstoqueProducaoCategoriaPageState extends State<_EstoqueProducaoCategoriaPage> {
  final _buscaCtrl         = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  Timer? _debounce;

  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  String? _colunaOrdem;
  bool    _crescente = true;

  void _toggleOrdem(String sortKey) {
    setState(() {
      if (_colunaOrdem == sortKey) {
        _crescente = !_crescente;
      } else {
        _colunaOrdem = sortKey;
        _crescente   = true;
      }
    });
  }

  String? _categoriaParaProvider() {
    if (widget.categoriaId == _kCategoriaGeral)        return null;
    if (widget.categoriaId == _kCategoriaSemCategoria) return '';
    return widget.categoriaId;
  }

  /// Transferir material entre as duas linhas de produção é restrito a
  /// ADMIN/GERENTE — nem COMPRAS (que também vê a visão combinada) pode.
  /// Regra reforçada no backend (rota /transferir-linha).
  bool get _podeTransferirEntreLinhas {
    if (!widget.combinada) return false;
    final role = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    return role == 'ADMIN' || role == 'GERENTE';
  }

  /// Devolver material da produção para o estoque padrão segue a mesma
  /// regra de ESCRITA usada em transferir/dar baixa (ADMIN, GERENTE,
  /// COMPRAS, PRODUCAO1, PRODUCAO2) — reforçada no backend (rota
  /// /estoque-producao/devolver). Diferente de [_podeTransferirEntreLinhas],
  /// não exige a visão combinada: PRODUCAO1/PRODUCAO2 também podem devolver
  /// a própria linha para o estoque padrão.
  bool get _podeDevolver {
    final role = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    return ['ADMIN', 'GERENTE', 'COMPRAS', 'PRODUCAO1', 'PRODUCAO2'].contains(role);
  }

  @override
  void initState() {
    super.initState();
    if (widget.identificadorFiltro != null) {
      _identificadorCtrl.text = widget.identificadorFiltro!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarFiltros());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  void _aplicarFiltros() {
    setState(() {}); // atualiza estado do botão "Limpar filtros" imediatamente
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _paginaAtual = 0);
      final provider = context.read<EstoqueProducaoProvider>();
      if (widget.combinada) {
        // ADMIN/GERENTE/COMPRAS: aplica o mesmo filtro nas duas linhas.
        provider.carregarEstoque(
          producao:      '1',
          busca:         _buscaCtrl.text.trim(),
          categoria:     _categoriaParaProvider(),
          identificador: _identificadorCtrl.text.trim(),
          medida:        _medidaCtrl.text.trim(),
          espessura:     _espessuraCtrl.text.trim(),
        );
        provider.carregarEstoque(
          producao:      '2',
          busca:         _buscaCtrl.text.trim(),
          categoria:     _categoriaParaProvider(),
          identificador: _identificadorCtrl.text.trim(),
          medida:        _medidaCtrl.text.trim(),
          espessura:     _espessuraCtrl.text.trim(),
        );
      } else {
        provider.carregarEstoque(
          busca:         _buscaCtrl.text.trim(),
          categoria:     _categoriaParaProvider(),
          identificador: _identificadorCtrl.text.trim(),
          medida:        _medidaCtrl.text.trim(),
          espessura:     _espessuraCtrl.text.trim(),
        );
      }
    });
  }

  void _limparFiltros() {
    _buscaCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _espessuraCtrl.clear();
    final provider = context.read<EstoqueProducaoProvider>();
    if (widget.combinada) {
      provider.carregarEstoque(producao: '1', categoria: _categoriaParaProvider());
      provider.carregarEstoque(producao: '2', categoria: _categoriaParaProvider());
    } else {
      provider.carregarEstoque(categoria: _categoriaParaProvider());
    }
  }

  bool get _temFiltroAtivo =>
      _buscaCtrl.text.trim().isNotEmpty ||
      _identificadorCtrl.text.trim().isNotEmpty ||
      _medidaCtrl.text.trim().isNotEmpty ||
      _espessuraCtrl.text.trim().isNotEmpty;

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
                _BotaoVoltar(
                  label: widget.mostrarBotaoIdentificadores
                      ? widget.categoriaLabel
                      : 'Categorias',
                  tooltip: 'Voltar para a lista de categorias',
                  onTap: () => Navigator.of(context).pop(),
                ),
                if (widget.mostrarBotaoIdentificadores && widget.identificadorLabel != null) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.outline),
                  ),
                  Text(
                    widget.identificadorLabel!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.cor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icone, color: widget.cor, size: 22),
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
                      'Estoque de produção',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Spacer(),
                IconButton(
                  onPressed: _aplicarFiltros,
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
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
                    decoration: InputDecoration(
                      hintText:   'Buscar material...',
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense:    true,
                    ),
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Limpar filtros',
                  icon: Icon(Icons.filter_alt_off, color: scheme.onSurfaceVariant),
                  onPressed: _temFiltroAtivo ? _limparFiltros : null,
                  style: IconButton.styleFrom(
                    side: BorderSide(color: scheme.outline),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return SystemMouseCursors.basic;
                      }
                      return SystemMouseCursors.click;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: InputDecoration(
                      hintText:   'Identificador...',
                      prefixIcon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: InputDecoration(
                      hintText:   'Medida...',
                      prefixIcon: Icon(Icons.straighten, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense:    true,
                    ),
                    inputFormatters: [_DecimalCommaFormatter()],
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: InputDecoration(
                      hintText:   'Espessura...',
                      prefixIcon: Icon(Icons.layers, color: Theme.of(context).colorScheme.outline, size: 18),
                      suffixText: 'mm',
                      isDense:    true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) => _aplicarFiltros(),
                    onSubmitted: (_) => _aplicarFiltros(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: Consumer<EstoqueProducaoProvider>(
                builder: (_, provider, __) {
                  // Resolve getters pela visão combinada (ADMIN/GERENTE/COMPRAS)
                  // ou pela linha ativa do usuário (PRODUCAO1/PRODUCAO2).
                  final carregando = widget.combinada
                      ? provider.carregandoEstoqueCombinado
                      : provider.carregandoEstoque;
                  final erroLinha = widget.combinada
                      ? provider.erroEstoqueCombinado
                      : provider.erro;
                  final estoqueLinha = widget.combinada
                      ? provider.estoqueCombinado
                      : provider.estoque;

                  if (carregando) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }
                  if (erroLinha != null && estoqueLinha.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.error),
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
                            erroLinha,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => widget.combinada
                                ? provider.carregarEstoqueAmbasLinhas()
                                : provider.carregarEstoque(),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ],
                      ),
                    );
                  }
                  if (estoqueLinha.isEmpty) {
                    return Center(
                      child: Text(
                        'Nenhum material encontrado',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      ),
                    );
                  }

                  final todos        = _ordenarEstoqueProducao(estoqueLinha, _colunaOrdem, _crescente);
                  final totalPaginas = (todos.length / _itensPorPagina).ceil();
                  final paginaSegura = _paginaAtual.clamp(0, (totalPaginas - 1).clamp(0, 999));
                  final inicio       = paginaSegura * _itensPorPagina;
                  final fim          = (inicio + _itensPorPagina).clamp(0, todos.length);
                  final paginados    = todos.sublist(inicio, fim);

                  return Column(
                    children: [
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: _TabelaEstoqueProducao(
                            materiais: paginados,
                            mostrarCategoria: widget.categoriaId == _kCategoriaGeral,
                            mostrarColunaProducao: widget.combinada,
                            podeTransferirEntreLinhas: _podeTransferirEntreLinhas,
                            podeDevolver: _podeDevolver,
                            colunaOrdem: _colunaOrdem,
                            crescente: _crescente,
                            onToggleOrdem: _toggleOrdem,
                          ),
                        ),
                      ),
                      if (totalPaginas > 1) ...[
                        const SizedBox(height: 12),
                        _BarraPaginacao(
                          paginaAtual:     paginaSegura,
                          totalPaginas:    totalPaginas,
                          totalItens:      todos.length,
                          itensPorPagina:  _itensPorPagina,
                          onPaginaChanged: (p) => setState(() => _paginaAtual = p),
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

// ─────────────────────────────────────────────
// ESTOQUE PRODUÇÃO — TABELA (mesmo layout do Estoque padrão)
// ─────────────────────────────────────────────

/// Ordena a lista de materiais de estoque de produção conforme a chave
/// de ordenação selecionada e a direção.
List<MaterialEstoqueProducaoModel> _ordenarEstoqueProducao(
  List<MaterialEstoqueProducaoModel> lista,
  String? sortKey,
  bool crescente,
) {
  if (sortKey == null) return lista;
  final copia = List<MaterialEstoqueProducaoModel>.from(lista);
  int cmp(MaterialEstoqueProducaoModel a, MaterialEstoqueProducaoModel b) {
    switch (sortKey) {
      case 'producao':      return a.producao.compareTo(b.producao);
      case 'id':            return a.id.compareTo(b.id);
      case 'identificador':  return _compareNullableStr(a.identificador, b.identificador);
      case 'nome':           return _compareNullableStr(a.nome, b.nome);
      case 'categoria':      return _compareNullableStr(a.categoria, b.categoria);
      case 'medida':         return _compareNullableStr(a.medida, b.medida);
      case 'espessura':      return _compareNullableStr(a.espessura, b.espessura);
      case 'comprimento':    return _compareNullableNum(a.comprimento, b.comprimento);
      case 'largura':        return _compareNullableNum(a.largura, b.largura);
      case 'quantidade':     return a.quantidade.compareTo(b.quantidade);
      case 'unidade':        return _compareNullableStr(a.unidade, b.unidade);
      default:               return 0;
    }
  }
  copia.sort((a, b) => crescente ? cmp(a, b) : cmp(b, a));
  return copia;
}

class _TabelaEstoqueProducao extends StatefulWidget {
  final List<MaterialEstoqueProducaoModel> materiais;
  final bool mostrarCategoria;
  /// true quando a lista é a visão COMBINADA (ADMIN/GERENTE/COMPRAS vendo
  /// as duas linhas juntas) — exibe a coluna "Produção" à esquerda do ID,
  /// indicando de qual linha (1 ou 2) é cada material.
  final bool mostrarColunaProducao;
  /// true para ADMIN/GERENTE na visão combinada: exibe a coluna "Ações" à
  /// direita com o botão de transferir o material para a outra linha de
  /// produção. COMPRAS também vê a visão combinada, mas NÃO pode
  /// transferir — só ADMIN/GERENTE (regra também reforçada no backend).
  final bool podeTransferirEntreLinhas;
  /// true para quem pode devolver material da produção para o estoque
  /// padrão (ADMIN/GERENTE/COMPRAS/PRODUCAO1/PRODUCAO2 — mesma regra de
  /// ESCRITA usada em transferir/dar baixa, reforçada no backend). Ao
  /// contrário de [podeTransferirEntreLinhas], não é restrito a
  /// ADMIN/GERENTE, pois devolver ao estoque padrão é uma ação simétrica à
  /// transferência original, disponível a quem já pode transferir.
  final bool podeDevolver;
  final String? colunaOrdem;
  final bool crescente;
  final void Function(String sortKey) onToggleOrdem;

  const _TabelaEstoqueProducao({
    required this.materiais,
    this.mostrarCategoria = true,
    this.mostrarColunaProducao = false,
    this.podeTransferirEntreLinhas = false,
    this.podeDevolver = false,
    required this.colunaOrdem,
    required this.crescente,
    required this.onToggleOrdem,
  });

  static const _ColDef _colProducao =
      _ColDef(label: 'Produção', fixed: 90, sortKey: 'producao');
  // Largura da coluna de Ações cresce quando os dois botões (transferir
  // entre linhas + devolver ao estoque padrão) aparecem juntos.
  static const _ColDef _colAcoes =
      _ColDef(label: 'Ações', fixed: 56);
  static const _ColDef _colAcoesDuplas =
      _ColDef(label: 'Ações', fixed: 92);

  static const List<_ColDef> _todosColsDef = [
    _ColDef(label: 'Identificador', flex: 0.9, sortKey: 'identificador'),
    _ColDef(label: 'Material',      flex: 2.0, sortKey: 'nome'),
    _ColDef(label: 'Categoria',     flex: 1.0, sortKey: 'categoria'),
    _ColDef(label: 'Medida',        flex: 0.8, sortKey: 'medida'),
    _ColDef(label: 'Espessura',     flex: 0.7, sortKey: 'espessura'),
    _ColDef(label: 'Comprimento',   flex: 0.8, sortKey: 'comprimento'),
    _ColDef(label: 'Largura',       flex: 0.8, sortKey: 'largura'),
    _ColDef(label: 'Estoque atual', flex: 0.7, sortKey: 'quantidade'),
    _ColDef(label: 'Unidade',       flex: 0.9, sortKey: 'unidade'),
  ];

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  @override
  State<_TabelaEstoqueProducao> createState() => _TabelaEstoqueProducaoState();
}

class _TabelaEstoqueProducaoState extends State<_TabelaEstoqueProducao> {
  List<_ColDef> get _cols {
    final base = widget.mostrarCategoria
        ? _TabelaEstoqueProducao._todosColsDef
        : _TabelaEstoqueProducao._todosColsDef.where((c) => c.label != 'Categoria').toList();
    final comProducao = widget.mostrarColunaProducao
        ? [_TabelaEstoqueProducao._colProducao, ...base]
        : base;
    if (widget.podeTransferirEntreLinhas && widget.podeDevolver) {
      return [...comProducao, _TabelaEstoqueProducao._colAcoesDuplas];
    }
    if (widget.podeTransferirEntreLinhas || widget.podeDevolver) {
      return [...comProducao, _TabelaEstoqueProducao._colAcoes];
    }
    return comProducao;
  }

  Widget _cabecalho() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            for (final col in _cols)
              _TabelaEstoqueProducao._colWrap(
                col,
                col.sortKey != null
                    ? _CabecalhoOrdenavel(
                        label:     col.label,
                        ativo:     widget.colunaOrdem == col.sortKey,
                        crescente: widget.crescente,
                        onTap:     () => widget.onToggleOrdem(col.sortKey!),
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
    final cols      = _cols;
    final materiais = widget.materiais;

    Widget corpoRolavel = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < materiais.length; i++) ...[
            if (i > 0)
              Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
            _LinhaEstoqueProducao(
              material: materiais[i],
              cols: cols,
              mostrarCategoria: widget.mostrarCategoria,
              mostrarColunaProducao: widget.mostrarColunaProducao,
              podeTransferirEntreLinhas: widget.podeTransferirEntreLinhas,
              podeDevolver: widget.podeDevolver,
            ),
          ],
          if (materiais.isNotEmpty)
            Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho fixo — não entra no scroll vertical
        _cabecalho(),
        Divider(height: 0, thickness: 0.8, color: Theme.of(context).colorScheme.outlineVariant),
        // Corpo rolável ocupa o espaço restante
        Expanded(child: corpoRolavel),
      ],
    );
  }
}

class _LinhaEstoqueProducao extends StatefulWidget {
  final MaterialEstoqueProducaoModel material;
  final List<_ColDef> cols;
  final bool mostrarCategoria;
  final bool mostrarColunaProducao;
  final bool podeTransferirEntreLinhas;
  final bool podeDevolver;

  const _LinhaEstoqueProducao({
    required this.material,
    required this.cols,
    this.mostrarCategoria = true,
    this.mostrarColunaProducao = false,
    this.podeTransferirEntreLinhas = false,
    this.podeDevolver = false,
  });

  @override
  State<_LinhaEstoqueProducao> createState() => _LinhaEstoqueProducaoState();
}

class _LinhaEstoqueProducaoState extends State<_LinhaEstoqueProducao> {
  bool _hovered = false;

  static Widget _colWrap(_ColDef col, Widget child) => col.fixed != null
      ? SizedBox(width: col.fixed, child: child)
      : Expanded(flex: (col.flex! * 10).round(), child: child);

  Widget _cell(String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
        ),
      );

  Widget _vDivider() => VerticalDivider(
        width: 1, thickness: 0.5, color: Theme.of(context).colorScheme.outlineVariant,
      );

  void _abrirBaixa(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _BaixaEstoqueProducaoDialog(material: widget.material),
    );
  }

  void _abrirTransferirEntreLinhas(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _TransferirEntreLinhasDialog(material: widget.material),
    );
  }

  void _abrirDevolver(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _DevolverEstoquePadraoDialog(material: widget.material),
    );
  }

  static String _fmtDim(double? v) {
    if (v == null) return '—';
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final m    = widget.material;
    final cols = widget.cols;

    final bgColor = _hovered
        ? Color(0xFF009800).withValues(alpha: 0.10)
        : Theme.of(context).colorScheme.surface;

    var i = 0;
    Widget nextCol(Widget child) => _colWrap(cols[i++], child);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _abrirBaixa(context),
        child: ColoredBox(
          color: bgColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.mostrarColunaProducao) ...[
                  nextCol(Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (m.producao == '2' ? Color(0xFF1E88E5) : Color(0xFF00897B))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Produção ${m.producao}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: m.producao == '2' ? Color(0xFF1E88E5) : Color(0xFF00897B),
                        ),
                      ),
                    ),
                  )),
                  _vDivider(),
                ],
                nextCol(_cell(m.identificador?.isNotEmpty == true ? m.identificador! : '—')),
                _vDivider(),

                nextCol(Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    m.nome,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                )),
                _vDivider(),

                if (widget.mostrarCategoria) ...[
                  nextCol(_cell(m.categoria ?? '—')),
                  _vDivider(),
                ],

                nextCol(_cell(m.medida ?? '—')),
                _vDivider(),

                nextCol(_cell(_fmtEspessura(m.espessura) ?? '—')),
                _vDivider(),

                nextCol(_cell(_fmtDim(m.comprimento))),
                _vDivider(),

                nextCol(_cell(_fmtDim(m.largura))),
                _vDivider(),

                nextCol(_cell(_fmtQtdProducao(m.quantidade))),
                _vDivider(),

                nextCol(_cell(formatarUnidadeExibicao(m.unidade).isEmpty ? '—' : formatarUnidadeExibicao(m.unidade))),
                if (widget.podeTransferirEntreLinhas || widget.podeDevolver) ...[
                  _vDivider(),
                  nextCol(
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.podeTransferirEntreLinhas)
                            IconButton(
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              tooltip: 'Transferir para Produção ${m.producao == '1' ? '2' : '1'}',
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: () => _abrirTransferirEntreLinhas(context),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                              ).copyWith(
                                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                              ),
                            ),
                          if (widget.podeDevolver)
                            IconButton(
                              icon: const Icon(Icons.undo, size: 18),
                              tooltip: 'Devolver ao estoque padrão',
                              color: Theme.of(context).colorScheme.secondary,
                              onPressed: () => _abrirDevolver(context),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                              ).copyWith(
                                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo de baixa: informa quantidade (ou dimensão usada, para materiais
/// UNIDADE com chapa cadastrada) e número da OS. Decrementa apenas o
/// estoque de produção (o material já saiu do estoque normal na transferência)
/// e registra a saída vinculada à OS informada.
/// Tipo de baixa escolhido pelo usuário para materiais UNIDADE com chapa
/// cadastrada (ver [_BaixaEstoqueProducaoDialogState._podeInformarDimensao]):
/// baixa de unidade(s) inteira(s), baixa de chapa parcial (por dimensão
/// usada) ou as duas combinadas numa única operação.
enum _TipoBaixaChapa { inteira, parcial, combinada }

class _BaixaEstoqueProducaoDialog extends StatefulWidget {
  final MaterialEstoqueProducaoModel material;
  const _BaixaEstoqueProducaoDialog({required this.material});

  @override
  State<_BaixaEstoqueProducaoDialog> createState() => _BaixaEstoqueProducaoDialogState();
}

class _BaixaEstoqueProducaoDialogState extends State<_BaixaEstoqueProducaoDialog> {
  final _quantCtrl   = TextEditingController();
  final _osCtrl      = TextEditingController();
  final _obsCtrl     = TextEditingController();
  final _larguraCtrl = TextEditingController();
  final _alturaCtrl  = TextEditingController();
  bool  _enviando        = false;
  // Tipo de baixa escolhido nos cards (null = ainda não escolhido, exibe os
  // 3 cards). Só se aplica quando [_podeInformarDimensao] é true; para os
  // demais materiais a baixa é sempre só por quantidade.
  _TipoBaixaChapa? _tipoBaixaChapa;
  String? _erro;

  /// True quando a seção de dimensão usada deve ser exibida/considerada —
  /// ou seja, quando o usuário escolheu "Chapa parcial" ou "Chapa(s)
  /// inteira(s) + Chapa parcial" nos cards.
  bool get _modoDimensional =>
      _tipoBaixaChapa == _TipoBaixaChapa.parcial || _tipoBaixaChapa == _TipoBaixaChapa.combinada;
  // Erros de validação exibidos embaixo dos campos de dimensão usada
  // (comprimento/largura), acionados em tempo real ao digitar.
  String? _erroComprimento;
  String? _erroLargura;
  // Erro de validação exibido embaixo do campo de quantidade (unidades
  // inteiras), no mesmo padrão dos campos de dimensão acima — em vez de
  // aparecer solto no rodapé do diálogo, longe do campo que originou o erro.
  String? _erroQuantidade;

  @override
  void dispose() {
    _quantCtrl.dispose();
    _osCtrl.dispose();
    _obsCtrl.dispose();
    _larguraCtrl.dispose();
    _alturaCtrl.dispose();
    super.dispose();
  }

  /// True se a unidade do material é metro linear (m, m/l, ml, etc.).
  bool get _eMetroLinear {
    final u = widget.material.unidade?.toLowerCase().trim() ?? '';
    return const {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'}.contains(u);
  }

  /// True se o material é UNIDADE (chapa/peça) e tem largura + comprimento
  /// cadastrados — mesma regra usada no diálogo de solicitação.
  bool get _podeInformarDimensao {
    final m = widget.material;
    if (_eMetroLinear) return false;
    return (m.unidade?.toUpperCase() == 'UNIDADE') &&
        m.largura != null && m.largura! > 0 &&
        m.comprimento != null && m.comprimento! > 0;
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Valida o texto de um campo de dimensão (comprimento/largura usada)
  /// contra o [maximo] da chapa, retornando a mensagem de erro (ou null se
  /// válido/vazio). Diferente de [_limitarDimensao] (usado no diálogo de
  /// solicitação), aqui NÃO truncamos o texto digitado — apenas sinalizamos
  /// o erro em tempo real, permitindo que o usuário veja e corrija o que
  /// digitou (ex.: "2" já no limite e o usuário continua digitando "3"
  /// formando "23", que deve acusar erro imediatamente).
  String? _validarDimensao(String texto, double maximo) {
    if (texto.trim().isEmpty) return null;
    final v = double.tryParse(texto.replaceAll(',', '.'));
    if (v == null) return null;
    if (v > maximo) {
      return 'Não pode ultrapassar ${_fmt(maximo)} m';
    }
    return null;
  }

  /// Valida em tempo real se a quantidade total a dar baixa (unidades
  /// inteiras + 1 unidade parcial, se houver dimensão informada) não excede
  /// o disponível em estoque, atualizando [_erro] imediatamente — sem
  /// esperar o usuário clicar em "Confirmar Baixa". Mesma regra aplicada em
  /// [_confirmar].
  void _validarQuantidadeTotal() {
    final qtdTexto = _quantCtrl.text.trim();
    final qtdInteira = qtdTexto.isEmpty ? null : double.tryParse(qtdTexto.replaceAll(',', '.'));

    final temDimensao = _modoDimensional &&
        _erroComprimento == null &&
        _erroLargura == null &&
        (double.tryParse(_alturaCtrl.text.replaceAll(',', '.')) ?? 0) > 0 &&
        (double.tryParse(_larguraCtrl.text.replaceAll(',', '.')) ?? 0) > 0;

    final qtdTotal = (qtdInteira ?? 0) + (temDimensao ? 1 : 0);
    if (qtdTotal > widget.material.quantidade) {
      _erro = 'Quantidade maior que o disponível (${_fmt(widget.material.quantidade)})';
    } else if (_erro != null && _erro!.startsWith('Quantidade maior que o disponível')) {
      _erro = null;
    }
  }

  /// Seção superior do diálogo: quantidade inteira a dar baixa. Sempre
  /// opcional — a obrigatoriedade (pelo menos uma das duas seções) é
  /// validada em conjunto com a seção de dimensão em [_confirmar].
  static Widget _celTabHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  static Widget _celTab(BuildContext context, String text, {bool negrito = false, Color? cor, bool wrap = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          softWrap: wrap,
          overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: negrito ? FontWeight.w700 : FontWeight.w400,
            color: cor ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );

  Widget _secaoQuantidade(MaterialEstoqueProducaoModel m) {
    final disponivel = m.quantidade == m.quantidade.truncateToDouble()
        ? m.quantidade.toStringAsFixed(0)
        : m.quantidade.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _podeInformarDimensao ? 'Unidades inteiras' : 'Quantidade',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _quantCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantidade',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  isDense: true,
                  suffixText: formatarUnidadeExibicao(m.unidade),
                  helperText: _erroQuantidade ??
                      ((_erro != null && _erro!.startsWith('Quantidade maior que o disponível'))
                          ? _erro
                          : 'Disponível: $disponivel ${formatarUnidadeExibicao(m.unidade)}'),
                  helperStyle: TextStyle(
                    fontSize: 10,
                    color: (_erroQuantidade != null ||
                            (_erro != null && _erro!.startsWith('Quantidade maior que o disponível')))
                        ? AppTheme.error
                        : Theme.of(context).colorScheme.outline,
                  ),
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {
                  if (_erroQuantidade != null) _erroQuantidade = null;
                  _validarQuantidadeTotal();
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Card individual de escolha do tipo de baixa (usado em
  /// [_cardsEscolhaTipoBaixa]).
  Widget _cardEscolha({
    required IconData icone,
    required String titulo,
    required String descricao,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 24, color: AppTheme.primary),
              const SizedBox(height: 8),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                descricao,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tela de escolha do tipo de baixa: 3 cards numa única linha. Exibida
  /// apenas para materiais UNIDADE com chapa cadastrada, antes de mostrar os
  /// campos de quantidade e/ou dimensão.
  Widget _cardsEscolhaTipoBaixa() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Escolha o tipo de baixa de material',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardEscolha(
                icone: Icons.layers_outlined,
                titulo: 'Chapa(s) inteira(s)',
                descricao: 'Baixa por quantidade de unidades',
                onTap: () => setState(() => _tipoBaixaChapa = _TipoBaixaChapa.inteira),
              ),
              const SizedBox(width: 8),
              _cardEscolha(
                icone: Icons.content_cut,
                titulo: 'Chapa parcial',
                descricao: 'Baixa pela dimensão usada',
                onTap: () => setState(() => _tipoBaixaChapa = _TipoBaixaChapa.parcial),
              ),
              const SizedBox(width: 8),
              _cardEscolha(
                icone: Icons.dashboard_customize_outlined,
                titulo: 'Chapa(s) inteira(s) + Chapa parcial',
                descricao: 'Quantidade e dimensão usada',
                onTap: () => setState(() => _tipoBaixaChapa = _TipoBaixaChapa.combinada),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Botão para sair da seção de quantidade/dimensão escolhida e voltar
  /// para a tela dos 3 cards, limpando os campos e erros preenchidos.
  Widget _botaoVoltarTipoBaixa() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _tipoBaixaChapa = null;
            _quantCtrl.clear();
            _larguraCtrl.clear();
            _alturaCtrl.clear();
            _erro = null;
            _erroComprimento = null;
            _erroLargura = null;
            _erroQuantidade = null;
          }),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          icon: const Icon(Icons.arrow_back, size: 15),
          label: const Text('Voltar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  /// Seção inferior do diálogo (só para materiais UNIDADE com medida
  /// cadastrada — ver [_podeInformarDimensao]): baixa por dimensão usada,
  /// que sempre representa 1 unidade parcial adicional (gera retalho com a
  /// sobra). Também opcional; combinável com a quantidade inteira da seção
  /// acima numa única baixa.
  Widget _secaoDimensao(MaterialEstoqueProducaoModel m) {
    final largura     = m.largura!;
    final comprimento = m.comprimento!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.content_cut, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Dimensão usada',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '(chapa ${_fmt(comprimento)}×${_fmt(largura)} m)',
                  style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _alturaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Comprimento',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                    suffixText: 'm',
                    helperText: _erroComprimento ?? 'Máx: ${_fmt(comprimento)} m',
                    helperStyle: TextStyle(
                      fontSize: 10,
                      color: _erroComprimento != null ? AppTheme.error : Theme.of(context).colorScheme.outline,
                    ),
                    helperMaxLines: 3,
                  ),
                  onChanged: (v) => setState(() {
                    _erroComprimento = _validarDimensao(v, comprimento);
                    _validarQuantidadeTotal();
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _larguraCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Largura',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                    suffixText: 'm',
                    helperText: _erroLargura ?? 'Máx: ${_fmt(largura)} m',
                    helperStyle: TextStyle(
                      fontSize: 10,
                      color: _erroLargura != null ? AppTheme.error : Theme.of(context).colorScheme.outline,
                    ),
                    helperMaxLines: 3,
                  ),
                  onChanged: (v) => setState(() {
                    _erroLargura = _validarDimensao(v, largura);
                    _validarQuantidadeTotal();
                  }),
                ),
              ),
            ],
          ),
          Builder(builder: (_) {
            final comp = double.tryParse(_alturaCtrl.text.replaceAll(',', '.'));
            final larg = double.tryParse(_larguraCtrl.text.replaceAll(',', '.'));
            if (larg == null || larg <= 0 || comp == null || comp <= 0) {
              return const SizedBox.shrink();
            }
            if (comp > comprimento || larg > largura) {
              return const SizedBox.shrink();
            }
            final areaUsada   = larg * comp;
            final areaTotal   = largura * comprimento;
            final areaRetalho = double.parse((areaTotal - areaUsada).toStringAsFixed(4));
            final temRetalho  = areaRetalho > 0.0001;

            final detalhesRetalho = <String>[];
            if (m.identificador != null && m.identificador!.isNotEmpty) {
              detalhesRetalho.add(m.identificador!);
            }
            if (m.espessura != null && m.espessura!.isNotEmpty) {
              detalhesRetalho.add(_fmtEspessura(m.espessura)!);
            }

            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      children: [
                        const TextSpan(text: 'Total utilizado: '),
                        TextSpan(
                          text: '${_fmt(areaUsada)}m²',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (temRetalho) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        children: [
                          const TextSpan(text: 'Gera retalho de '),
                          TextSpan(
                            text: '${_fmt(areaRetalho)}m²',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.success),
                          ),
                          const TextSpan(text: ' (ver detalhes abaixo)'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  Future<void> _confirmar() async {
    final os = _osCtrl.text.trim();
    setState(() => _erroQuantidade = null);

    // Para materiais UNIDADE com chapa cadastrada, o tipo de baixa precisa
    // ter sido escolhido nos cards antes de confirmar.
    if (_podeInformarDimensao && _tipoBaixaChapa == null) {
      setState(() => _erro = 'Escolha o tipo de baixa de material');
      return;
    }

    double? largUsada;
    double? compUsado;
    double? qtdInteira;

    // Quantidade (unidades inteiras) é exigida quando o material não tem
    // chapa cadastrada, ou quando o card escolhido foi "Chapa(s) inteira(s)"
    // ou "Chapa(s) inteira(s) + Chapa parcial".
    final exigeQuantidade = !_podeInformarDimensao ||
        _tipoBaixaChapa == _TipoBaixaChapa.inteira ||
        _tipoBaixaChapa == _TipoBaixaChapa.combinada;

    // Valida quantidade e dimensão ANTES de decidir se retorna, e aplica
    // os erros de todos os campos vazios num único setState. Sem isso (modo
    // "combinada", com quantidade E dimensão exigidas ao mesmo tempo), um
    // "return" antecipado logo após checar a quantidade fazia o usuário ver
    // só "Informe a quantidade" e, ao corrigir, só então "Informe o
    // comprimento usado" — em vez de ver os três avisos de uma vez.
    String? erroQtd;
    double? qtdParsed;
    if (exigeQuantidade) {
      final qtdTexto = _quantCtrl.text.trim();
      qtdParsed = qtdTexto.isEmpty ? null : double.tryParse(qtdTexto.replaceAll(',', '.'));
      erroQtd = (qtdParsed == null || qtdParsed <= 0) ? 'Informe a quantidade' : null;
    }

    String? erroComp;
    String? erroLarg;
    double? l, c;
    if (_modoDimensional && _podeInformarDimensao) {
      l = double.tryParse(_larguraCtrl.text.replaceAll(',', '.'));
      c = double.tryParse(_alturaCtrl.text.replaceAll(',', '.'));
      erroComp = (c == null || c <= 0) ? 'Informe o comprimento usado' : null;
      erroLarg = (l == null || l <= 0) ? 'Informe a largura usada' : null;
    }

    if (erroQtd != null || erroComp != null || erroLarg != null) {
      setState(() {
        _erroQuantidade  = erroQtd;
        _erroComprimento = erroComp;
        _erroLargura     = erroLarg;
      });
      return;
    }

    if (exigeQuantidade) qtdInteira = qtdParsed;

    if (_modoDimensional && _podeInformarDimensao) {
      if (l! > widget.material.largura! || c! > widget.material.comprimento!) {
        final largMax = widget.material.largura!;
        final compMax = widget.material.comprimento!;
        setState(() {
          _erroComprimento = c! > compMax ? 'Não pode ultrapassar ${_fmt(compMax)} m' : null;
          _erroLargura     = l! > largMax ? 'Não pode ultrapassar ${_fmt(largMax)} m' : null;
        });
        return;
      }
      largUsada = l;
      compUsado = c;
    }

    // Total baixado do estoque: unidades inteiras + 1 unidade parcial (se
    // houver dimensão informada) — mesma regra aplicada no backend.
    final qtdTotal = (qtdInteira ?? 0) + (largUsada != null ? 1 : 0);
    if (qtdTotal > widget.material.quantidade) {
      setState(() => _erro = 'Quantidade maior que o disponível (${widget.material.quantidade})');
      return;
    }
    if (os.isEmpty) {
      setState(() => _erro = 'Informe o número da OS');
      return;
    }

    setState(() { _enviando = true; _erro = null; });
    final provider = context.read<EstoqueProducaoProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final ok = await provider.darBaixa(
      materialId: widget.material.id,
      quantidade: qtdInteira,
      numeroOS: os,
      producao: widget.material.producao,
      observacao: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
      larguraUsada: largUsada,
      comprimentoUsado: compUsado,
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (ok) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Baixa registrada para a OS $os'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      setState(() => _erro = provider.erro ?? 'Erro ao registrar baixa');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final detalhes = <String>[];
    if (m.identificador != null && m.identificador!.isNotEmpty) {
      detalhes.add(m.identificador!);
    }
    if (m.medida != null && m.medida!.isNotEmpty) {
      detalhes.add(m.medida!);
    } else {
      final comp = m.comprimento;
      final larg = m.largura;
      if (comp != null && comp > 0 && larg != null && larg > 0) {
        detalhes.add('${_fmt(comp)}x${_fmt(larg)}m');
      } else if (comp != null && comp > 0) {
        detalhes.add('${_fmt(comp)}m');
      } else if (larg != null && larg > 0) {
        detalhes.add('${_fmt(larg)}m');
      }
    }
    if (m.espessura != null && m.espessura!.isNotEmpty) detalhes.add(_fmtEspessura(m.espessura)!);
    final subtitulo = detalhes.join(' · ');

    return AlertDialog(
      title: const Text('Baixa de Material'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _osCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseFormatter()],
                decoration: const InputDecoration(labelText: 'Número da OS *', isDense: true),
              ),
              const SizedBox(height: 14),

              // ── Card do material — mesmo padrão visual do diálogo de
              // Nova Saída no Controle de Estoque: fundo laranja translúcido,
              // borda laranja, ícone de check e nome/detalhes empilhados,
              // cada um em um Wrap para nunca cortar texto com "...".
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Cabeçalho: ícone + nome + detalhes ──────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, size: 15, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.nome,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                                softWrap: true,
                              ),
                              if (subtitulo.isNotEmpty)
                                Text(
                                  subtitulo,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  softWrap: true,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Para materiais UNIDADE com chapa cadastrada, o
                    // usuário primeiro escolhe o tipo de baixa em 3 cards
                    // (Chapa(s) inteira(s) / Chapa parcial / combinada). A
                    // escolha define quais seções (quantidade e/ou dimensão)
                    // aparecem e se tornam obrigatórias. Quando as duas são
                    // exigidas (combinada), a baixa soma as unidades
                    // inteiras + 1 unidade parcial (dimensional) numa única
                    // operação (ex.: chapa 2x1, estoque=3: quantidade=2 +
                    // dimensão 1x1 → baixa total = 3, sobrando um retalho de
                    // 1 m² sobre a unidade parcial).
                    if (!_podeInformarDimensao)
                      _secaoQuantidade(m)
                    else if (_tipoBaixaChapa == null)
                      _cardsEscolhaTipoBaixa()
                    else ...[
                      _botaoVoltarTipoBaixa(),
                      const SizedBox(height: 10),
                      if (_tipoBaixaChapa == _TipoBaixaChapa.combinada)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _secaoQuantidade(m)),
                              SizedBox(
                                width: 28,
                                child: Column(
                                  children: [
                                    // Pula parte da altura do cabeçalho das seções
                                    // ao lado ("Unidades inteiras" / "Dimensão usada",
                                    // 44px) pra aproximar o centro dos CAMPOS, não do
                                    // bloco inteiro. 22 (metade de 44) é o ponto
                                    // calibrado: pular os 44px inteiros deslocava o +
                                    // pra baixo demais, e não pular nada deslocava pra
                                    // cima demais.
                                    const SizedBox(height: 22),
                                    Expanded(
                                      child: Center(
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppTheme.primary.withValues(alpha: 0.12),
                                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                                          ),
                                          child: const Text(
                                            '+',
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(child: _secaoDimensao(m)),
                            ],
                          ),
                        )
                      else if (_tipoBaixaChapa == _TipoBaixaChapa.inteira)
                        _secaoQuantidade(m)
                      else
                        _secaoDimensao(m),
                    ],

                    if (_modoDimensional)
                      Builder(builder: (_) {
                        final comp = double.tryParse(_alturaCtrl.text.replaceAll(',', '.'));
                        final larg = double.tryParse(_larguraCtrl.text.replaceAll(',', '.'));
                        if (larg == null || larg <= 0 || comp == null || comp <= 0) {
                          return const SizedBox.shrink();
                        }
                        if (comp > m.comprimento! || larg > m.largura!) {
                          return const SizedBox.shrink();
                        }
                        final areaUsada   = larg * comp;
                        final areaTotal   = m.largura! * m.comprimento!;
                        final areaRetalho = double.parse((areaTotal - areaUsada).toStringAsFixed(4));
                        final temRetalho  = areaRetalho > 0.0001;
                        if (!temRetalho) return const SizedBox.shrink();

                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Retalho gerado',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Table(
                                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                  columnWidths: const {
                                    0: FlexColumnWidth(0.9), // Identificador
                                    1: FlexColumnWidth(2.2), // Material
                                    2: FlexColumnWidth(0.8), // Medida
                                    3: FlexColumnWidth(0.8), // Espessura
                                    4: FlexColumnWidth(0.9), // Quantidade
                                  },
                                  children: [
                                    TableRow(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      ),
                                      children: [
                                        _celTabHeader(context, 'Identificador'),
                                        _celTabHeader(context, 'Material'),
                                        _celTabHeader(context, 'Medida'),
                                        _celTabHeader(context, 'Espessura'),
                                        _celTabHeader(context, 'Quantidade'),
                                      ],
                                    ),
                                    TableRow(
                                      children: [
                                        _celTab(context, 'RETALHO'),
                                        _celTab(context, m.nome, negrito: true, wrap: true),
                                        _celTab(context, '${_fmt(areaRetalho)}m²'),
                                        _celTab(context, m.espessura != null && m.espessura!.isNotEmpty ? _fmtEspessura(m.espessura)! : '—'),
                                        _celTab(context, '${_fmt(areaRetalho)}m²', cor: AppTheme.success, negrito: true),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _obsCtrl,
                      maxLines: 1,
                      decoration: const InputDecoration(
                        labelText: 'Observação (opcional)',
                        isDense: true,
                        prefixIcon: Icon(Icons.notes, size: 16),
                      ),
                    ),

                    Builder(builder: (_) {
                      final qtdInteira = double.tryParse(_quantCtrl.text.trim().replaceAll(',', '.'));
                      final temQtdInteira = qtdInteira != null && qtdInteira > 0;

                      final comp = double.tryParse(_alturaCtrl.text.replaceAll(',', '.'));
                      final larg = double.tryParse(_larguraCtrl.text.replaceAll(',', '.'));
                      final temDimensao = _modoDimensional &&
                          _erroComprimento == null &&
                          _erroLargura == null &&
                          comp != null && comp > 0 &&
                          larg != null && larg > 0;

                      if (!temQtdInteira && !temDimensao) {
                        return const SizedBox.shrink();
                      }

                      final unidade = formatarUnidadeExibicao(m.unidade);
                      final partes = <String>[];
                      if (temQtdInteira) {
                        final qtdFmt = qtdInteira % 1 == 0 ? qtdInteira.toStringAsFixed(0) : _fmt(qtdInteira);
                        partes.add('$qtdFmt ${qtdInteira == 1 ? unidade : '${unidade}s'} inteira${qtdInteira == 1 ? '' : 's'}');
                      }
                      if (temDimensao) {
                        final area = comp * larg;
                        partes.add('${_fmt(comp)}×${_fmt(larg)}m (${_fmt(area)}m²)');
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.error.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
                                    children: [
                                      const TextSpan(text: 'Você está dando baixa de '),
                                      TextSpan(
                                        text: partes.join(' + '),
                                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.error),
                                      ),
                                      const TextSpan(text: '.'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              if (_erro != null && !_erro!.startsWith('Quantidade maior que o disponível')) ...[
                const SizedBox(height: 10),
                Text(_erro!, style: const TextStyle(color: AppTheme.error, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirmar Baixa'),
        ),
      ],
    );
  }
}

/// Diálogo de devolução de material do estoque de produção de volta para o
/// estoque padrão (operação inversa da transferência feita no Controle de
/// Estoque). Disponível para quem pode transferir/dar baixa (ADMIN,
/// GERENTE, COMPRAS, PRODUCAO1, PRODUCAO2 — ver `_podeDevolver`), regra
/// também reforçada no backend (rota /estoque-producao/devolver). Gera um
/// registro tanto no histórico do estoque padrão (ENTRADA) quanto no
/// histórico compartilhado de produção (DEVOLUCAO).
class _DevolverEstoquePadraoDialog extends StatefulWidget {
  final MaterialEstoqueProducaoModel material;
  const _DevolverEstoquePadraoDialog({required this.material});

  @override
  State<_DevolverEstoquePadraoDialog> createState() => _DevolverEstoquePadraoDialogState();
}

class _DevolverEstoquePadraoDialogState extends State<_DevolverEstoquePadraoDialog> {
  final _quantCtrl = TextEditingController();
  final _obsCtrl   = TextEditingController();
  bool _enviando = false;
  String? _erro;

  String get _origem => widget.material.producao;

  @override
  void dispose() {
    _quantCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _confirmar() async {
    final qtd = double.tryParse(_quantCtrl.text.replaceAll(',', '.'));
    if (qtd == null || qtd <= 0) {
      setState(() => _erro = 'Informe uma quantidade válida');
      return;
    }
    if (qtd > widget.material.quantidade) {
      setState(() => _erro = 'Quantidade maior que o disponível (${_fmt(widget.material.quantidade)})');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    final ok = await context.read<EstoqueProducaoProvider>().devolver(
          materialId: widget.material.id,
          quantidade: qtd,
          producao: _origem,
          observacao: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        );

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_fmt(qtd)} ${formatarUnidadeExibicao(widget.material.unidade)} devolvido(s) ao estoque padrão'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() {
        _enviando = false;
        _erro = context.read<EstoqueProducaoProvider>().erro ?? 'Erro ao devolver';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    return AlertDialog(
      title: const Text('Devolver ao estoque padrão'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.nome,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Disponível na Produção $_origem: ${_fmt(m.quantidade)} ${formatarUnidadeExibicao(m.unidade)}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('De', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                        Text('Produção $_origem', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('Para', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                        Text('Estoque padrão',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quantCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantidade',
                suffixText: formatarUnidadeExibicao(m.unidade),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obsCtrl,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
                isDense: true,
              ),
              maxLines: 2,
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirmar Devolução'),
        ),
      ],
    );
  }
}

/// Diálogo de transferência de material entre as duas linhas de produção
/// (ex.: sobrou na produção 1, transferir para a produção 2). Restrito a
/// ADMIN/GERENTE — o botão que abre este diálogo só aparece pra esses
/// cargos (ver `podeTransferirEntreLinhas` em _TabelaEstoqueProducao), e o
/// backend reforça a mesma regra. A linha de destino é sempre "a outra"
/// (só existem duas linhas), então não há seletor — só confirmação.
class _TransferirEntreLinhasDialog extends StatefulWidget {
  final MaterialEstoqueProducaoModel material;
  const _TransferirEntreLinhasDialog({required this.material});

  @override
  State<_TransferirEntreLinhasDialog> createState() => _TransferirEntreLinhasDialogState();
}

class _TransferirEntreLinhasDialogState extends State<_TransferirEntreLinhasDialog> {
  final _quantCtrl = TextEditingController();
  final _obsCtrl   = TextEditingController();
  bool _enviando = false;
  String? _erro;

  String get _origem  => widget.material.producao;
  String get _destino => widget.material.producao == '1' ? '2' : '1';

  @override
  void dispose() {
    _quantCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _confirmar() async {
    final qtd = double.tryParse(_quantCtrl.text.replaceAll(',', '.'));
    if (qtd == null || qtd <= 0) {
      setState(() => _erro = 'Informe uma quantidade válida');
      return;
    }
    if (qtd > widget.material.quantidade) {
      setState(() => _erro = 'Quantidade maior que o disponível (${_fmt(widget.material.quantidade)})');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    final ok = await context.read<EstoqueProducaoProvider>().transferirEntreLinhas(
          materialId: widget.material.id,
          quantidade: qtd,
          producaoOrigem: _origem,
          producaoDestino: _destino,
          observacao: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        );

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_fmt(qtd)} ${formatarUnidadeExibicao(widget.material.unidade)} transferido(s) para Produção $_destino'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() {
        _enviando = false;
        _erro = context.read<EstoqueProducaoProvider>().erro ?? 'Erro ao transferir';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    return AlertDialog(
      title: const Text('Transferir entre produções'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.nome,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Disponível na Produção $_origem: ${_fmt(m.quantidade)} ${formatarUnidadeExibicao(m.unidade)}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('De', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                        Text('Produção $_origem', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('Para', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                        Text('Produção $_destino',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quantCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantidade',
                suffixText: formatarUnidadeExibicao(m.unidade),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obsCtrl,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
                isDense: true,
              ),
              maxLines: 2,
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
          child: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirmar Transferência'),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// PÁGINA DE RETALHOS — grade de categorias com filtro automático por RETALHO
// ═════════════════════════════════════════════════════════════════════════

class _RetalhosPage extends StatefulWidget {
  const _RetalhosPage();

  @override
  State<_RetalhosPage> createState() => _RetalhosPageState();
}

class _RetalhosPageState extends State<_RetalhosPage> {
  final _filtroCategoriaCtrl = TextEditingController();
  String _filtroCategoria    = '';

  static IconData _iconePara(String categoria) {
    final c = categoria.toUpperCase();
    if (c.contains('LONA'))      return Icons.straighten;
    if (c.contains('BANNER'))    return Icons.flag;
    if (c.contains('VINIL'))     return Icons.layers;
    if (c.contains('PERFIL'))    return Icons.square_foot;
    if (c.contains('TINTA'))     return Icons.format_paint;
    if (c.contains('PAPEL'))     return Icons.description;
    if (c.contains('ACESSORIO')) return Icons.handyman;
    if (c.contains('COLA'))      return Icons.water_drop;
    if (c.contains('TECIDO'))    return Icons.texture;
    if (c.contains('MADEIRA'))   return Icons.foundation;
    if (c.contains('METAL'))     return Icons.hardware;
    return Icons.inventory_2;
  }

  static const _cores = [
    Color(0xFF5E35B1), Color(0xFF1E88E5), Color(0xFF00897B),
    Color(0xFFE53935), Color(0xFFF4511E), Color(0xFF8E24AA),
    Color(0xFF039BE5), Color(0xFF43A047), Color(0xFFFFB300),
    Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFFD81B60),
  ];

  static const Color _corRetalho = Color(0xFF00897B);

  @override
  void dispose() {
    _filtroCategoriaCtrl.dispose();
    super.dispose();
  }

  void _navegarParaRetalhos({
    required String categoriaId,
    required String categoriaLabel,
    required Color cor,
    required IconData icone,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProducaoCategoriaPage(
          categoriaId:             categoriaId,
          categoriaLabel:          categoriaLabel,
          cor:                     cor,
          icone:                   icone,
          identificadorFiltro:     'RETALHO',
          identificadorLabel:      'RETALHO',
          mostrarBotaoIdentificadores: false,
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
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                _BotaoVoltar(
                  label:   'Produção',
                  tooltip: 'Voltar para Produção',
                  onTap:   () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _corRetalho.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _corRetalho.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'RETALHOS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _corRetalho,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Selecione uma categoria para ver os retalhos',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => context.read<ProducaoProvider>().carregarCategorias(),
                  icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ).copyWith(
                    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Campo de busca de categoria ──────────────────────────────────
            SizedBox(
              width: 360,
              child: TextField(
                controller: _filtroCategoriaCtrl,
                decoration: InputDecoration(
                  hintText:   'Buscar categoria...',
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

            // ── Grid de categorias ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Consumer<ProducaoProvider>(
                  builder: (_, provider, __) {
                    if (provider.carregandoCategorias && !provider.categoriasCarregadas) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                      );
                    }

                    bool corresponde(String label) =>
                        _filtroCategoria.isEmpty ||
                        label.toLowerCase().contains(_filtroCategoria);

                    final cards = <Widget>[
                      // Card Geral — mostra TODOS os retalhos, sem filtro de categoria
                      if (corresponde('Geral'))
                        _CategoriaCardProducao(
                          categoria: 'Geral',
                          cor:       const Color(0xFF5E35B1),
                          icone:     Icons.grid_view_rounded,
                          onTap: () => _navegarParaRetalhos(
                            categoriaId:    _kCategoriaGeral,
                            categoriaLabel: 'Geral',
                            cor:            const Color(0xFF5E35B1),
                            icone:          Icons.grid_view_rounded,
                          ),
                        ),
                      // Card Sem categoria — retalhos sem categoria
                      if (corresponde('Sem categoria'))
                        _CategoriaCardProducao(
                          categoria: 'Sem categoria',
                          cor:       const Color(0xFF546E7A),
                          icone:     Icons.help_outline,
                          onTap: () => _navegarParaRetalhos(
                            categoriaId:    _kCategoriaSemCategoria,
                            categoriaLabel: 'Sem categoria',
                            cor:            const Color(0xFF546E7A),
                            icone:          Icons.help_outline,
                          ),
                        ),
                      // Cards de cada categoria real
                      for (int i = 0; i < provider.categorias.length; i++)
                        if (corresponde(provider.categorias[i]))
                          _CategoriaCardProducao(
                            categoria: provider.categorias[i],
                            cor:       _cores[i % _cores.length],
                            icone:     _iconePara(provider.categorias[i]),
                            onTap: () => _navegarParaRetalhos(
                              categoriaId:    provider.categorias[i],
                              categoriaLabel: provider.categorias[i],
                              cor:            _cores[i % _cores.length],
                              icone:          _iconePara(provider.categorias[i]),
                            ),
                          ),
                    ];

                    if (cards.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhuma categoria encontrada',
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
                      children:         cards,
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

// ═════════════════════════════════════════════════════════════════════════
// ABA: Histórico Estoque Produção — agora incorporada à aba "Histórico"
// unificada acima. Este widget renderiza apenas o card de uma movimentação
// (transferência/baixa/estorno) do estoque de produção.
// ═════════════════════════════════════════════════════════════════════════
class _MovimentacaoEstoqueProducaoCard extends StatefulWidget {
  final MovimentacaoProducaoModel movimentacao;
  const _MovimentacaoEstoqueProducaoCard({required this.movimentacao});

  @override
  State<_MovimentacaoEstoqueProducaoCard> createState() => _MovimentacaoEstoqueProducaoCardState();
}

class _MovimentacaoEstoqueProducaoCardState extends State<_MovimentacaoEstoqueProducaoCard> {
  String _fmtData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _fmtQtd(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _confirmarExclusao(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro'),
        content: const Text(
          'Excluir este registro do histórico do estoque de produção?\n\n'
          'A quantidade não será devolvida nem removida do estoque — '
          'apenas o registro do histórico será apagado.\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                .copyWith(
                    mouseCursor: WidgetStateProperty.all(
                        SystemMouseCursors.click)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true || !context.mounted) return;

    final ok = await context
        .read<EstoqueProducaoProvider>()
        .excluirHistorico(widget.movimentacao.id);

    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<EstoqueProducaoProvider>().erro ?? 'Erro ao excluir',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mov = widget.movimentacao;
    final ehTransferencia = mov.ehTransferencia;
    final ehTransferenciaLinha = mov.ehTransferenciaLinha;
    final ehEstorno = mov.ehEstorno;
    final cor = ehTransferenciaLinha
        ? AppTheme.primary
        : ehTransferencia
            ? AppTheme.success
            : (ehEstorno ? Theme.of(context).colorScheme.outline : AppTheme.error);

    final detalhes = <String>[];
    if (mov.materialIdentificador != null && mov.materialIdentificador!.isNotEmpty) {
      detalhes.add(mov.materialIdentificador!);
    }
    if (mov.materialMedida != null && mov.materialMedida!.isNotEmpty) {
      detalhes.add(mov.materialMedida!);
    } else {
      final comp = mov.materialComprimento;
      final larg = mov.materialLargura;
      if (comp != null && comp > 0 && larg != null && larg > 0) {
        detalhes.add('${_fmt(comp)}x${_fmt(larg)}m');
      } else if (comp != null && comp > 0) {
        detalhes.add('${_fmt(comp)}m');
      } else if (larg != null && larg > 0) {
        detalhes.add('${_fmt(larg)}m');
      }
    }
    if (mov.materialEspessura != null && mov.materialEspessura!.isNotEmpty) {
      detalhes.add(_fmtEspessura(mov.materialEspessura)!);
    }

    // Histórico é compartilhado entre as duas linhas de produção, então
    // cada rótulo precisa deixar explícito de/para qual linha (1 ou 2) a
    // movimentação se refere — sem isso, ADMIN/GERENTE/COMPRAS (que veem
    // as duas linhas juntas) não conseguem saber a qual das duas o registro
    // pertence. O texto é diferente para cada tipo (transferência aponta o
    // destino, baixa aponta a origem, estorno aponta de onde foi retirado).
    final rotulo = ehTransferenciaLinha
        ? 'Transferência: Produção ${mov.producaoOrigemDerivada} → Produção ${mov.producao}'
        : (ehTransferencia
            ? 'Transferência para Produção ${mov.producao}'
            : (ehEstorno
                ? 'Estorno: devolvido ao estoque padrão (retirado da Produção ${mov.producao})'
                : 'Baixa para OS ${mov.numeroOS} — Produção ${mov.producao}'));

    final role = context.watch<UsuarioProvider>().usuarioLogado?.role.trim().toUpperCase() ?? '';
    final podeExcluir = role == 'ADMIN' || role == 'GERENTE';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                ehTransferenciaLinha
                    ? Icons.swap_horiz
                    : (ehTransferencia
                        ? Icons.call_received
                        : (ehEstorno ? Icons.undo : Icons.call_made)),
                color: cor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rotulo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    mov.materialNome,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (detalhes.isNotEmpty)
                    Text(
                      detalhes.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (mov.usuarioNome != null)
                    Text(
                      'Usuário: ${mov.usuarioNome}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(ehTransferencia || ehTransferenciaLinha) ? '+' : '-'}${_fmtQtd(mov.quantidade)} ${formatarUnidadeExibicao(mov.materialUnidade)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cor,
                  ),
                ),
                Text(
                  _fmtData(mov.criadoEm),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                if (podeExcluir) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Tooltip(
                      message: 'Excluir registro',
                      child: IconButton(
                        onPressed: () => _confirmarExclusao(context),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.error.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: AppTheme.error,
                          ),
                        ),
                        style: IconButton.styleFrom().copyWith(
                            mouseCursor: WidgetStateProperty.all(
                                SystemMouseCursors.click)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}