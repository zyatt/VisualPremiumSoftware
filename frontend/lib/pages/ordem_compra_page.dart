import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/ordem_compra_model.dart';
import '../models/fornecedor_model.dart';
import '../providers/ordem_compra_provider.dart';
import '../providers/estoque_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/material_provider.dart';
import '../repositories/ordem_compra_repository.dart';
import '../repositories/fornecedor_repository.dart';
import '../theme/app_theme.dart';
import '../providers/robo_helper_provider.dart';
import 'controle_estoque_page.dart' show formatarMedidaOuDimensoes, formatarQuantidade;

String espessuraExibicao(String? espessura) {
  final e = (espessura ?? '').trim();
  if (e.isEmpty) return '';
  final semSufixo = e.replaceAll(RegExp(r'\s*mm\s*$', caseSensitive: false), '').trim();
  if (semSufixo.isEmpty) return '';
  return '${semSufixo}mm';
}

String unidadeExibicao(String? unidade) {
  final u = (unidade ?? '').trim();
  if (u.isEmpty) return '';
  final norm = u.toUpperCase();
  switch (norm) {
    case 'M/L':  return 'm/l';
    case 'ML':   return 'ml';
    case 'M2':
    case 'M²':   return 'm²';
    case 'KG':   return 'kg';
    case 'UN':
    case 'UNID':
    case 'UNIDADE': return u.length <= 4 ? norm.toLowerCase() : 'unidade';
    default:     return u.toLowerCase();
  }
}

String unidadeDescricaoCompleta(String? unidade) {
  final u = (unidade ?? '').trim();
  if (u.isEmpty) return '';
  final norm = u.toUpperCase();
  switch (norm) {
    case 'M/L':     return 'm/l (metro linear)';
    case 'M':        return 'm (metro)';
    case 'ML':       return 'ml (mililitro)';
    case 'M2':
    case 'M²':       return 'm² (metro quadrado)';
    case 'G':        return 'g (grama)';
    case 'KG':       return 'kg (quilograma)';
    case 'UN':
    case 'UNID':
    case 'UNIDADE':  return u.length <= 4 ? norm.toLowerCase() : 'unidade';
    default:         return u.toLowerCase();
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

double? parseNumeroBr(String texto) {
  final limpo = texto.trim();
  if (limpo.isEmpty) return null;

  final semMilhar = limpo.replaceAll('.', '');
  final comPontoDecimal = semMilhar.replaceAll(',', '.');
  return double.tryParse(comPontoDecimal);
}

String formatarNumeroBr(double valor, int casas) {
  final fixo = valor.toStringAsFixed(casas);
  final partes = fixo.split('.');
  final inteiro = partes[0];
  final decimal = partes.length > 1 ? partes[1] : '';

  final negativo = inteiro.startsWith('-');
  final digitosInteiro = negativo ? inteiro.substring(1) : inteiro;

  final buffer = StringBuffer();
  for (var i = 0; i < digitosInteiro.length; i++) {
    if (i > 0 && (digitosInteiro.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digitosInteiro[i]);
  }

  final inteiroFormatado = '${negativo ? '-' : ''}${buffer.toString()}';
  return casas > 0 ? '$inteiroFormatado,$decimal' : inteiroFormatado;
}

class _NumeroBrFormatter extends TextInputFormatter {

  final int casasDecimais;

  _NumeroBrFormatter({this.casasDecimais = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    if (newValue.text.length > oldValue.text.length) {
      final cursorFim = newValue.selection.baseOffset < 0
          ? newValue.text.length
          : newValue.selection.baseOffset;
      final qtdInserida = newValue.text.length - oldValue.text.length;
      final inicioInserido = (cursorFim - qtdInserida).clamp(0, newValue.text.length);
      final trechoInserido = newValue.text.substring(
        inicioInserido.clamp(0, newValue.text.length),
        cursorFim.clamp(0, newValue.text.length),
      );
      if (trechoInserido.contains('.')) {
        final novoTrecho = trechoInserido.replaceAll('.', ',');
        final novoTexto = newValue.text.replaceRange(
          inicioInserido,
          cursorFim.clamp(0, newValue.text.length),
          novoTrecho,
        );
        final delta = novoTrecho.length - trechoInserido.length;
        newValue = TextEditingValue(
          text: novoTexto,
          selection: TextSelection.collapsed(
            offset: (cursorFim + delta).clamp(0, novoTexto.length),
          ),
        );
      }
    }

    var texto = newValue.text.replaceAll(RegExp(r'[^\d,]'), '');
    final primeiraVirgula = texto.indexOf(',');
    if (primeiraVirgula != -1) {
      final antes = texto.substring(0, primeiraVirgula + 1);
      final depois = texto
          .substring(primeiraVirgula + 1)
          .replaceAll(',', '')
          .substring(0, texto.substring(primeiraVirgula + 1).replaceAll(',', '').length.clamp(0, casasDecimais));
      texto = antes + depois;
    }

    final partes = texto.split(',');
    var inteiro = partes[0].replaceAll(RegExp(r'^0+(?=\d)'), '');
    final decimal = partes.length > 1 ? partes[1] : null;

    final cursorCru = newValue.selection.baseOffset < 0
        ? texto.length
        : newValue.text
            .substring(0, newValue.selection.baseOffset.clamp(0, newValue.text.length))
            .replaceAll(RegExp(r'[^\d,]'), '')
            .length;

    final buffer = StringBuffer();
    for (var i = 0; i < inteiro.length; i++) {
      if (i > 0 && (inteiro.length - i) % 3 == 0) buffer.write('.');
      buffer.write(inteiro[i]);
    }
    var resultado = buffer.toString();
    if (decimal != null) resultado += ',$decimal';
    if (texto.endsWith(',') && decimal == null) resultado += ',';

    var restantes = cursorCru;
    var novoCursor = resultado.length;
    for (var i = 0; i < resultado.length; i++) {
      final c = resultado[i];
      if (c == '.') continue;
      restantes--;
      if (restantes <= 0) {
        novoCursor = i + 1;
        break;
      }
    }
    if (cursorCru == 0) novoCursor = 0;

    return TextEditingValue(
      text: resultado,
      selection: TextSelection.collapsed(offset: novoCursor.clamp(0, resultado.length)),
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

    texto = texto.replaceAll(RegExp(r'\.{2,}'), '.');

    final primeiroPonto = texto.indexOf('.');
    if (primeiroPonto != -1) {
      texto = texto.substring(0, primeiroPonto + 1) +
          texto.substring(primeiroPonto + 1).replaceAll('.', '');
    }

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
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

class OrdemCompraPage extends StatefulWidget {

  final int? ocIdParaAbrir;

  const OrdemCompraPage({super.key, this.ocIdParaAbrir});

  @override
  State<OrdemCompraPage> createState() => OrdemCompraPageState();
}

class OrdemCompraPageState extends State<OrdemCompraPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _buscaNumeroCtrl      = TextEditingController();
  final _buscaNomeCtrl        = TextEditingController();
  final _buscaComprimentoCtrl = TextEditingController();
  final _buscaLarguraCtrl     = TextEditingController();
  final _buscaEspessuraCtrl   = TextEditingController();
  final _buscaMedidaCtrl      = TextEditingController();
  final _buscaIdentificadorCtrl = TextEditingController();
  String _filtroBuscaNumero      = '';
  String _filtroBuscaNome        = '';
  String _filtroBuscaComprimento = '';
  String _filtroBuscaLargura     = '';
  String _filtroBuscaEspessura   = '';
  String _filtroBuscaMedida      = '';
  String _filtroBuscaIdentificador = '';

  final _tourKeyNovaOc = GlobalKey();
  final _tourKeyBuscaNumero = GlobalKey();
  final _tourKeyBuscaNome = GlobalKey();
  final _tourKeyBuscaFiltrosAvancados = GlobalKey();
  final _tourKeyAbas = GlobalKey();
  final _novaOcTourKeys = NovaOcTourKeys();
  final GlobalKey<NovaOrdemCompraPageState> _novaOcPageKey =
      GlobalKey<NovaOrdemCompraPageState>();

  bool _dialogTourAberto = false;
  bool _dialogTourEmTransicao = false;
  RoboHelperProvider? _roboHelperPagina;

  GoRouter? _goRouter;
  bool _rotaEstaAtiva = false;
  Timer? _debounceFiltros;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final helper = context.read<RoboHelperProvider>();
      helper.notificarRota('/ordem-compra');
      _roboHelperPagina = helper;
      _roboHelperPagina!.addListener(_onRoboHelperPaginaChanged);
      if (mounted) _registrarAjudaRoboOC();

      // A tela vive dentro de uma StatefulShellBranch (IndexedStack), então
      // o widget nunca é recriado ao trocar de aba — initState só roda uma
      // vez. Para recarregar sempre que o usuário volta pra essa aba,
      // escutamos o próprio GoRouter e detectamos quando a rota atual
      // volta a ser '/ordem-compra'.
      _goRouter = GoRouter.of(context);
      _goRouter!.routerDelegate.addListener(_onRotaMudou);
      _rotaEstaAtiva = _rotaAtualEhOrdemCompra();

      await _carregarInicial();
    });
  }

  Future<void> _carregarInicial() async {
    if (!mounted) return;
    final provider = context.read<OrdemCompraProvider>();
    await provider.carregar();

    if (mounted) {
      await context.read<EstoqueProvider>().carregarRelacoesOS();
    }
    if (!mounted) return;

    final ocPendente = provider.consumirOcPendente();
    final idAlvo = ocPendente ?? widget.ocIdParaAbrir;

    if (idAlvo != null) {
      final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
      dynamic raw = todas.cast<dynamic>().firstWhere(
        (o) {
          final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
          return m.id == idAlvo;
        },
        orElse: () => null,
      );
      raw ??= await _buscarOcDiretoOuNulo(idAlvo);
      if (raw != null && mounted) {
        _verDetalhes(context, raw);
      }
    }
  }

  bool _rotaAtualEhOrdemCompra() {
    final location = _goRouter?.routerDelegate.currentConfiguration.uri.toString() ?? '';
    return location.startsWith('/ordem-compra');
  }

  /// Chamado toda vez que a URL do GoRouter muda (troca de aba do shell,
  /// navegação para o detalhe/edição e volta, etc). Recarrega a listagem
  /// sempre que a rota volta a ser '/ordem-compra' vinda de outra rota.
  void _onRotaMudou() {
    if (!mounted) return;
    final ativaAgora = _rotaAtualEhOrdemCompra();
    if (ativaAgora && !_rotaEstaAtiva) {
      context.read<OrdemCompraProvider>().carregar();
    }
    _rotaEstaAtiva = ativaAgora;
  }

  Future<void> abrirOcPorId(int id) async {
    if (!mounted) return;

    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((r) => r.isFirst);
    }

    final provider = context.read<OrdemCompraProvider>();
    await provider.carregar();
    if (!mounted) return;
    final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
    dynamic raw = todas.cast<dynamic>().firstWhere(
      (o) {
        final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
        return m.id == id;
      },
      orElse: () => null,
    );

    // A OC pode não estar entre os primeiros itens carregados de cada aba
    // (listagem agora é paginada). Se não achou localmente, busca direto.
    raw ??= await _buscarOcDiretoOuNulo(id);

    if (raw != null && mounted) {
      _verDetalhes(context, raw);
    }
  }

  Future<dynamic> _buscarOcDiretoOuNulo(int id) async {
    try {
      return await OrdemCompraRepository().buscarPorId(id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _verificarOcPendente() async {
    if (!mounted) return;
    final provider = context.read<OrdemCompraProvider>();

    if (provider.ocPendente == null) return;
    final id = provider.consumirOcPendente()!;
    await abrirOcPorId(id);
  }

  @override
  void dispose() {
    _debounceFiltros?.cancel();
    _goRouter?.routerDelegate.removeListener(_onRotaMudou);
    _tabController.dispose();
    _buscaNumeroCtrl.dispose();
    _buscaNomeCtrl.dispose();
    _buscaComprimentoCtrl.dispose();
    _buscaLarguraCtrl.dispose();
    _buscaEspessuraCtrl.dispose();
    _buscaMedidaCtrl.dispose();
    _buscaIdentificadorCtrl.dispose();
    _roboHelperPagina?.removeListener(_onRoboHelperPaginaChanged);
    try {
      context.read<RoboHelperProvider>().encerrarTour();
      context.read<RoboHelperProvider>().limparOpcoes('/ordem-compra');
    } catch (_) {}
    super.dispose();
  }

  void _onRoboHelperPaginaChanged() {
    if (!mounted) return;
    if (_roboHelperPagina!.tourAtivo) return;
    _novaOcPageKey.currentState?.fecharAdicionarItemTourSeAberto();
    if (_dialogTourAberto) {
      _dialogTourAberto = false;
      Navigator.of(context).maybePop();
      _roboHelperPagina!.definirTelaSobreposta(false);
    }
  }

  Future<void> _abrirDialogTour() async {
    if (_dialogTourAberto || _dialogTourEmTransicao) return;
    _dialogTourAberto = true;
    _dialogTourEmTransicao = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogTourEmTransicao = false;
    });

    // O editor "Nova OC" é uma tela sobreposta: as opções registradas em
    // '/ordem-compra' (fazer/buscar uma ordem) são da listagem, não fazem
    // sentido dentro do editor. Marcando telaSobrepostaAtiva, o menu
    // "Dúvidas" some as opções da listagem enquanto o editor está aberto.
    context.read<RoboHelperProvider>().definirTelaSobreposta(true);

    final pushFuture = Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => NovaOrdemCompraPage(
          key: _novaOcPageKey,
          tourKeys: _novaOcTourKeys,
        ),
      ),
    );

    pushFuture.then((_) {
      if (mounted) {
        _dialogTourAberto = false;
        context.read<RoboHelperProvider>().definirTelaSobreposta(false);
      }
    });

    const tentativasMax = 30;
    for (var i = 0; i < tentativasMax; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (_novaOcTourKeys.fornecedor.currentContext != null) break;
    }
  }

  Future<void> _fecharDialogTourSeAberto() async {
    if (!_dialogTourAberto || _dialogTourEmTransicao) return;
    _dialogTourAberto = false;
    _dialogTourEmTransicao = true;
    // Usa o mesmo Navigator (sem rootNavigator) que fez o push em
    // _abrirDialogTour. Popar com rootNavigator: true aqui podia mirar um
    // Navigator diferente do que empilhou a rota do editor, fazendo o
    // maybePop() não fechar nada (ou fechar a rota errada) quando o app
    // tem navigators aninhados.
    await Navigator.of(context).maybePop();
    if (mounted) context.read<RoboHelperProvider>().definirTelaSobreposta(false);
    _dialogTourEmTransicao = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  RoboTourStop _stopOC({
    required GlobalKey Function() key,
    required String texto,
    Offset offset = const Offset(0, 0),
    Future<void> Function()? aoEntrar,
    Future<void> Function()? aoSair,
  }) {
    return RoboTourStop(
      key: key,
      texto: texto,
      offset: offset,
      aoEntrar: () async {
        if (aoEntrar != null) await aoEntrar();
        await _scrollAteChaveTour(key());
      },
      aoSair: aoSair,
    );
  }

  Future<void> _scrollAteChaveTour(GlobalKey key) async {
    for (var i = 0; i < 20; i++) {
      final ctx = key.currentContext;
      if (ctx != null) {
        if (!ctx.mounted) return;
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  void _registrarAjudaRoboOC() {
    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isCurrent) return;

    final helper = context.read<RoboHelperProvider>();
    helper.registrarOpcoes('/ordem-compra', [
      RoboHelpOption(
        titulo: 'Como fazer uma ordem de compra',
        paradas: [
          _stopOC(
            key: () => _tourKeyNovaOc,
            texto: 'Toque aqui para abrir o formulário de criação de uma '
                'nova ordem de compra.',
            aoEntrar: _fecharDialogTourSeAberto,
          ),
          _stopOC(
            key: () => _novaOcTourKeys.fornecedor,
            texto: 'Selecione o fornecedor principal desta ordem de compra.',
            aoEntrar: _abrirDialogTour,
          ),
          _stopOC(
            key: () => _novaOcTourKeys.requisitante,
            texto: 'Nome de quem está requisitando esta compra.',
            aoEntrar: () async {
              _novaOcPageKey.currentState?.simularFornecedorTour();
              await Future<void>.delayed(const Duration(milliseconds: 80));
            },
          ),
          _stopOC(
            key: () => _novaOcTourKeys.formaPagamento,
            texto: 'Forma de pagamento combinada com o fornecedor '
                '(ex: Boleto, À Vista, Crédito...).',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.prazoPagamento,
            texto: 'Prazo de pagamento combinado (ex: 30 dias, 15/30/45...).',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.observacoes,
            texto: 'Observações gerais sobre esta ordem de compra '
                '(opcional).',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.empresa,
            texto: 'Selecione a empresa que aparecerá no cabeçalho da '
                'ordem de compra: Visual Premium ou Visual Guindaste.',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.numerosOS,
            texto: 'Preencha ao menos um número de OS. Se houver apenas '
                'uma, ela será atribuída automaticamente aos itens.',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.atalhoEmpresa,
            texto: 'Use este atalho para preencher rapidamente uma OS '
                'com "EMPRESA".',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.atalhoOutros,
            texto: 'E este para preencher com "OUTROS".',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.campoOS,
            texto: 'Ou digite o número da OS diretamente no campo.',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.adicionarItem,
            texto: 'Com o fornecedor selecionado, toque aqui para '
                'adicionar itens à ordem de compra.',
            aoEntrar: () async {
              await _novaOcPageKey.currentState?.fecharAdicionarItemTourSeAberto();
            },
          ),
          _stopOC(
            key: () => _novaOcTourKeys.verTodoEstoque,
            texto: 'Ative aqui se quiser adicionar um material novo, '
                'ainda não vinculado a este fornecedor. Deixe desativado '
                'para escolher entre os materiais já vinculados a ele.',
            aoEntrar: () async {
              await _novaOcPageKey.currentState?.abrirAdicionarItemTour();
            },
          ),
          _stopOC(
            key: () => _novaOcTourKeys.buscaMaterial,
            texto: 'Busque o material pelo nome, identificador, medida, '
                'comprimento, largura ou espessura — pode preencher '
                'vários filtros ao mesmo tempo.',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.botaoAdicionarMaterial,
            texto: 'Toque no "+" para selecionar um material da lista.',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.botaoConfirmarAdicionar,
            texto: 'Depois de escolher os materiais desejados, toque em '
                '"Adicionar" para incluí-los na ordem de compra.',
            aoEntrar: () async {
              _novaOcPageKey.currentState?.selecionarItensParaConfirmarTour();
              await Future<void>.delayed(const Duration(milliseconds: 120));
            },
          ),
          _stopOC(
            key: () => _novaOcTourKeys.itemUnidadeCampos,
            texto: 'Para materiais com unidade "Unidade", preencha a '
                'Quantidade e o Preço por Unidade — o Valor Total é '
                'calculado automaticamente.',
            aoEntrar: () async {
              await _novaOcPageKey.currentState?.confirmarESairDoDialogTour();
            },
            aoSair: () async {
              await _novaOcPageKey.currentState?.desfazerConfirmacaoEReabrirDialogTour();
            },
          ),
          _stopOC(
            key: () => _novaOcTourKeys.itemOutraUnidadeCampos,
            texto: 'Já para materiais com outra unidade (m/l, ml, g, '
                'etc.), além da Quantidade, informe quanto dessa unidade '
                'tem em cada peça, o Valor por unidade e o Valor Total.',
          ),
          _stopOC(
            key: () => _novaOcTourKeys.criarOc,
            texto: 'Por fim, revise os dados e toque em "Criar OC" para '
                'salvar a ordem de compra.',
          ),
        ],
        aoEncerrar: () async {
          await _novaOcPageKey.currentState?.fecharAdicionarItemTourSeAberto();
          await _fecharDialogTourSeAberto();
        },
      ),
      RoboHelpOption(
        titulo: 'Como buscar uma ordem de compra',
        paradas: [
          RoboTourStop(
            key: () => _tourKeyBuscaNumero,
            texto: 'Filtre pelo número da OC.',
          ),
          RoboTourStop(
            key: () => _tourKeyBuscaNome,
            texto: 'Ou pelo nome do material presente na ordem de compra.',
          ),
          RoboTourStop(
            key: () => _tourKeyBuscaFiltrosAvancados,
            texto: 'Use os filtros avançados para refinar por '
                'identificador, medida, comprimento, largura ou espessura '
                'do material.',
          ),
          RoboTourStop(
            key: () => _tourKeyAbas,
            texto: 'E alterne entre as abas para ver as ordens Em '
                'Andamento, Finalizadas ou Canceladas.',
          ),
        ],
      ),
    ]);
  }

  bool _dependenciasInicializadas = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_dependenciasInicializadas) {
      _verificarOcPendente();
    }
    _dependenciasInicializadas = true;
  }

  /// Dispara a busca no servidor (com debounce) usando os filtros atuais
  /// dos campos de texto. Substitui a filtragem local por uma busca
  /// paginada de verdade, para não precisar carregar todas as OCs.
  void _agendarBuscaComFiltros() {
    _debounceFiltros?.cancel();
    _debounceFiltros = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<OrdemCompraProvider>().aplicarFiltros(
        OrdemCompraFiltros(
          numero: _filtroBuscaNumero.trim().isEmpty ? null : _filtroBuscaNumero.trim(),
          material: _filtroBuscaNome.trim().isEmpty ? null : _filtroBuscaNome.trim(),
          identificador: _filtroBuscaIdentificador.trim().isEmpty ? null : _filtroBuscaIdentificador.trim(),
          medida: _filtroBuscaMedida.trim().isEmpty ? null : _filtroBuscaMedida.trim(),
          comprimento: _filtroBuscaComprimento.trim().isEmpty ? null : _filtroBuscaComprimento.trim(),
          largura: _filtroBuscaLargura.trim().isEmpty ? null : _filtroBuscaLargura.trim(),
          espessura: _filtroBuscaEspessura.trim().isEmpty ? null : _filtroBuscaEspessura.trim(),
        ),
      );
    });
  }

  Future<void> _abrirCriacaoOC() async {
    final helper = context.read<RoboHelperProvider>();
    helper.definirTelaSobreposta(true);
    final resultado = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => NovaOrdemCompraPage()),
    );
    if (mounted) helper.definirTelaSobreposta(false);

    if (resultado != null && mounted) {
      context.read<OrdemCompraProvider>().carregar();
    }
    if (mounted) _registrarAjudaRoboOC();
  }

  @override
  Widget build(BuildContext context) {
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
                      'Ordens de Compra',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Consumer<OrdemCompraProvider>(
                      builder: (_, p, __) {
                        final total = p.totalEmAndamento + p.totalFinalizadas + p.totalCanceladas;
                        return Text(
                          '$total ${total == 1 ? 'ordem' : 'ordens'} no total',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        );
                      },
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Criar nova ordem de compra',
                  child: Container(
                    key: _tourKeyNovaOc,
                    child: FilledButton.icon(
                      onPressed: _abrirCriacaoOC,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nova Ordem de Compra'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                IconButton(
                  onPressed: () => context.read<OrdemCompraProvider>().carregar(),
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

            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: Container(
                    key: _tourKeyBuscaNumero,
                    child: TextField(
                      controller: _buscaNumeroCtrl,
                      decoration: InputDecoration(
                        hintText: 'Nº da OC',
                        prefixIcon: Icon(Icons.tag, color: Theme.of(context).colorScheme.outline, size: 18),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) {
                      setState(() => _filtroBuscaNumero = v);
                      _agendarBuscaComFiltros();
                    },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    key: _tourKeyBuscaNome,
                    child: TextField(
                      controller: _buscaNomeCtrl,
                      decoration: InputDecoration(
                        hintText: 'Nome do material',
                        prefixIcon: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.outline, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) {
                      setState(() => _filtroBuscaNome = v);
                      _agendarBuscaComFiltros();
                    },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              key: _tourKeyBuscaFiltrosAvancados,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaIdentificadorCtrl,
                    decoration: InputDecoration(
                      hintText: 'Identificador',
                      prefixIcon: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (v) {
                      setState(() => _filtroBuscaIdentificador = v);
                      _agendarBuscaComFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaMedidaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Medida',
                      prefixIcon: Icon(Icons.straighten, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    inputFormatters: [_MedidaEspessuraFormatter()],
                    onChanged: (v) {
                      setState(() => _filtroBuscaMedida = v);
                      _agendarBuscaComFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaComprimentoCtrl,
                    decoration: InputDecoration(
                      hintText: 'Comprimento',
                      suffixText: 'm',
                      prefixIcon: Icon(Icons.height, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (v) {
                      setState(() => _filtroBuscaComprimento = v);
                      _agendarBuscaComFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaLarguraCtrl,
                    decoration: InputDecoration(
                      hintText: 'Largura',
                      suffixText: 'm',
                      prefixIcon: Icon(Icons.width_normal, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (v) {
                      setState(() => _filtroBuscaLargura = v);
                      _agendarBuscaComFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaEspessuraCtrl,
                    decoration: InputDecoration(
                      hintText: 'Espessura',
                      suffixText: 'mm',
                      prefixIcon: Icon(Icons.layers, color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (v) {
                      setState(() => _filtroBuscaEspessura = v);
                      _agendarBuscaComFiltros();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Builder(
                  builder: (context) {
                    final temFiltro = _filtroBuscaNumero.isNotEmpty || _filtroBuscaNome.isNotEmpty || _filtroBuscaComprimento.isNotEmpty || _filtroBuscaLargura.isNotEmpty || _filtroBuscaEspessura.isNotEmpty || _filtroBuscaMedida.isNotEmpty || _filtroBuscaIdentificador.isNotEmpty;
                    return IconButton.outlined(
                      tooltip: 'Limpar filtros',
                      icon: Icon(
                        Icons.filter_alt_off,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: temFiltro
                          ? () {
                              _buscaNumeroCtrl.clear();
                              _buscaNomeCtrl.clear();
                              _buscaComprimentoCtrl.clear();
                              _buscaLarguraCtrl.clear();
                              _buscaEspessuraCtrl.clear();
                              _buscaMedidaCtrl.clear();
                              _buscaIdentificadorCtrl.clear();
                              setState(() {
                                _filtroBuscaNumero = '';
                                _filtroBuscaNome = '';
                                _filtroBuscaComprimento = '';
                                _filtroBuscaLargura = '';
                                _filtroBuscaEspessura = '';
                                _filtroBuscaMedida = '';
                                _filtroBuscaIdentificador = '';
                              });
                              _debounceFiltros?.cancel();
                              context.read<OrdemCompraProvider>().aplicarFiltros(
                                    const OrdemCompraFiltros(),
                                  );
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
            SizedBox(height: 16),

            Container(
              key: _tourKeyAbas,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: Consumer<OrdemCompraProvider>(
                builder: (_, p, __) {
                  return TabBar(
                    controller: _tabController,
                    labelColor: AppTheme.primary,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    indicatorColor: AppTheme.primary,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    tabs: [
                      _tabComContagem('Em Andamento', p.totalEmAndamento),
                      _tabComContagem('Finalizadas', p.totalFinalizadas),
                      _tabComContagem('Canceladas', p.totalCanceladas),
                    ],
                  );
                },
              ),
            ),

            Expanded(
              child: Consumer<OrdemCompraProvider>(
                builder: (context, provider, _) {
                  if (provider.carregando) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
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
                              'Erro ao carregar ordens de compra',
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
                              onPressed: () => provider.carregar(),
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

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _OcList(
                        ordens: provider.emAndamento,
                        statusColor: AppTheme.primary,
                        emptyMessage: 'Nenhuma ordem em andamento',
                        onFinalizar: (id) => _confirmarFinalizar(context, provider, id),
                        onCancelar: (id) => _confirmarCancelar(context, provider, id),
                        onEditar: (ordem) => _abrirEdicao(context, ordem),
                        onAbrirPdf: (ordem) => _abrirPdf(ordem),
                        onTap: (ordem) => _verDetalhes(context, ordem),
                        mostrarAcoes: true,
                        paginaAtual: provider.paginaAtual('EM_ANDAMENTO'),
                        totalPaginas: provider.totalPaginas('EM_ANDAMENTO'),
                        totalItens: provider.totalEmAndamento,
                        carregandoPagina: provider.carregandoPagina('EM_ANDAMENTO'),
                        onPaginaChanged: (p) => provider.irParaPagina('EM_ANDAMENTO', p),
                      ),
                      _OcList(
                        ordens: provider.finalizadas,
                        statusColor: AppTheme.success,
                        emptyMessage: 'Nenhuma ordem finalizada',
                        onTap: (ordem) => _verDetalhes(context, ordem),
                        onReverter: (id) => _confirmarReverter(context, provider, id),
                        onAbrirPdf: (ordem) => _abrirPdf(ordem),
                        mostrarAcoes: false,
                        mostrarReverter: true,
                        paginaAtual: provider.paginaAtual('FINALIZADO'),
                        totalPaginas: provider.totalPaginas('FINALIZADO'),
                        totalItens: provider.totalFinalizadas,
                        carregandoPagina: provider.carregandoPagina('FINALIZADO'),
                        onPaginaChanged: (p) => provider.irParaPagina('FINALIZADO', p),
                      ),
                      _OcList(
                        ordens: provider.canceladas,
                        statusColor: AppTheme.error,
                        emptyMessage: 'Nenhuma ordem cancelada',
                        onTap: (ordem) => _verDetalhes(context, ordem),
                        mostrarAcoes: false,
                        paginaAtual: provider.paginaAtual('CANCELADO'),
                        totalPaginas: provider.totalPaginas('CANCELADO'),
                        totalItens: provider.totalCanceladas,
                        carregandoPagina: provider.carregandoPagina('CANCELADO'),
                        onPaginaChanged: (p) => provider.irParaPagina('CANCELADO', p),
                      ),
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

  void _verDetalhes(BuildContext context, dynamic ordem) async {
    final model = ordem is OrdemCompraModel
        ? ordem
        : OrdemCompraModel.fromJson(ordem as Map<String, dynamic>);
    final recarregar = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrdemCompraDetalhePage(ordem: model)),
    );
    if (recarregar == true && context.mounted) {
      context.read<OrdemCompraProvider>().carregar();
    }
  }

  void _mostrarDialogOSFechada(BuildContext context, List<String> osBloqueadas) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.lock_outline, color: AppTheme.error, size: 22),
          SizedBox(width: 8),
          Text('OS Fechada', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não é possível finalizar esta OC porque ${osBloqueadas.length == 1 ? 'a seguinte OS já foi fechada' : 'as seguintes OS já foram fechadas'} no controle de estoque:',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: osBloqueadas.map((os) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                ),
                child: Text(os, style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13)),
              )).toList(),
            ),
            SizedBox(height: 12),
            Text(
              'Para prosseguir, reabra essa OS no controle de estoque antes de finalizar a OC.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _confirmarFinalizar(
      BuildContext context, OrdemCompraProvider provider, int id) {
    final ordem = provider.emAndamento.firstWhere(
      (o) {
        final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
        return m.id == id;
      },
      orElse: () => null,
    );
    if (ordem != null) {
      final model = ordem is OrdemCompraModel ? ordem : OrdemCompraModel.fromJson(ordem as Map<String, dynamic>);
      if (model.itens.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não é possível finalizar uma OC sem itens.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      final osFechadas = context.read<EstoqueProvider>().numerosOSFechadas;
      final osBloqueadas = model.numerosOS
          .where((os) => RegExp(r'^\d+$').hasMatch(os) && osFechadas.contains(os))
          .toList();
      if (osBloqueadas.isNotEmpty) {
        _mostrarDialogOSFechada(context, osBloqueadas);
        return;
      }

    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Finalizar Ordem'),
        content: Text(
            'Ao finalizar, os itens serão adicionados ao estoque. Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.finalizar(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Ordem finalizada com sucesso!'),
                      backgroundColor: AppTheme.success),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
  }

  void _confirmarCancelar(
      BuildContext context, OrdemCompraProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar Ordem'),
        content: Text(
            'Tem certeza que deseja cancelar esta ordem de compra?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Voltar',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.cancelar(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Ordem cancelada.'),
                      backgroundColor: AppTheme.error),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Cancelar OC'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirPdf(OrdemCompraModel ordem) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );
    try {
      final bytes = await OrdemCompraRepository().baixarPdf(ordem.id);

      final fornecedor = (ordem.fornecedorNome ?? 'FORNECEDOR')
          .toUpperCase()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = 'OC_${ordem.id}_$fornecedor.pdf';

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (Platform.isWindows) {
        await Process.run('explorer', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _abrirEdicao(BuildContext context, dynamic ordem) async {
    final model = ordem is OrdemCompraModel
        ? ordem
        : OrdemCompraModel.fromJson(ordem as Map<String, dynamic>);
    final atualizado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditarOrdemCompraPage(ordem: model)),
    );
    if (atualizado == true && context.mounted) {
      context.read<OrdemCompraProvider>().carregar();
    }
  }

  void _confirmarReverter(
      BuildContext context, OrdemCompraProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reverter Ordem Finalizada'),
        content: Text(
            'Esta ação irá desfazer a finalização: os itens serão removidos do estoque e a ordem voltará para "Em Andamento". Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Voltar',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await provider.reverter(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Ordem revertida para Em Andamento.'),
                        backgroundColor: AppTheme.primary),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
  }
}

Tab _tabComContagem(String texto, int contagem) {
  return Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(texto),
        const SizedBox(width: 6),
        Container(
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
        ),
      ],
    ),
  );
}

class _OcList extends StatelessWidget {
  final List<dynamic> ordens;
  final Color statusColor;
  final String emptyMessage;
  final void Function(dynamic)? onTap;
  final void Function(int)? onFinalizar;
  final void Function(int)? onCancelar;
  final void Function(dynamic)? onEditar;
  final void Function(int)? onReverter;
  final void Function(OrdemCompraModel)? onAbrirPdf;
  final bool mostrarAcoes;
  final bool mostrarReverter;

  /// Página atual (1-based), total de páginas e total de itens da aba,
  /// usados para exibir a barra de paginação numerada (igual à tela de
  /// Estoque). Se [totalPaginas] for null ou <= 1, a barra não é exibida.
  final int paginaAtual;
  final int? totalPaginas;
  final int totalItens;
  final bool carregandoPagina;
  final void Function(int pagina)? onPaginaChanged;

  const _OcList({
    required this.ordens,
    required this.statusColor,
    required this.emptyMessage,
    this.onTap,
    this.onFinalizar,
    this.onCancelar,
    this.onEditar,
    this.onReverter,
    this.onAbrirPdf,
    required this.mostrarAcoes,
    this.mostrarReverter = false,
    this.paginaAtual = 1,
    this.totalPaginas,
    this.totalItens = 0,
    this.carregandoPagina = false,
    this.onPaginaChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (ordens.isEmpty && !carregandoPagina) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 12),
            Text(emptyMessage,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
          ],
        ),
      );
    }

    final mostrarBarraPaginacao = (totalPaginas ?? 1) > 1;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: ordens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  try {
                    final raw = ordens[i];
                    final model = raw is OrdemCompraModel
                        ? raw
                        : OrdemCompraModel.fromJson(raw as Map<String, dynamic>);
                    return _OcCard(
                      ordem: model,
                      statusColor: statusColor,
                      mostrarAcoes: mostrarAcoes,
                      mostrarReverter: mostrarReverter,
                      onTap: () => onTap?.call(model),
                      onFinalizar: () => onFinalizar?.call(model.id),
                      onCancelar: () => onCancelar?.call(model.id),
                      onEditar: () => onEditar?.call(model),
                      onReverter: () => onReverter?.call(model.id),
                      onAbrirPdf: () => onAbrirPdf?.call(model),
                    );
                  } catch (e) {
                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.error)),
                      child: Text('Erro ao carregar ordem: $e', style: const TextStyle(color: AppTheme.error, fontSize: 12)),
                    );
                  }
                },
              ),
            ),
            if (mostrarBarraPaginacao) ...[
              const Divider(height: 1),
              _BarraPaginacaoOc(
                paginaAtual: paginaAtual - 1,
                totalPaginas: totalPaginas ?? 1,
                totalItens: totalItens,
                itensPorPagina: OrdemCompraProvider.porPagina,
                onPaginaChanged: (p) => onPaginaChanged?.call(p + 1),
              ),
            ],
          ],
        ),
        if (carregandoPagina)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
          ),
      ],
    );
  }
}

/// Barra de paginação numerada, com o mesmo design e layout dos botões de
/// paginação usados na tela de Estoque.
class _BarraPaginacaoOc extends StatelessWidget {
  final int paginaAtual;
  final int totalPaginas;
  final int totalItens;
  final int itensPorPagina;
  final void Function(int) onPaginaChanged;

  const _BarraPaginacaoOc({
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Exibindo $inicio–$fim de $totalItens ordens',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BotaoPaginaOc(
                icon: Icons.chevron_left,
                tooltip: 'Página anterior',
                enabled: paginaAtual > 0,
                onTap: () => onPaginaChanged(paginaAtual - 1),
              ),
              const SizedBox(width: 4),
              for (final p in paginas) ...[
                if (p == -1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  )
                else
                  _BotaoNumeroPaginaOc(
                    numero: p,
                    ativa: p == paginaAtual,
                    onTap: () => onPaginaChanged(p),
                  ),
                const SizedBox(width: 4),
              ],
              _BotaoPaginaOc(
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

class _BotaoPaginaOc extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _BotaoPaginaOc({
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

class _BotaoNumeroPaginaOc extends StatelessWidget {
  final int numero;
  final bool ativa;
  final VoidCallback onTap;

  const _BotaoNumeroPaginaOc({
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

class _OcCard extends StatefulWidget {
  final OrdemCompraModel ordem;
  final Color statusColor;
  final bool mostrarAcoes;
  final bool mostrarReverter;
  final VoidCallback onTap;
  final VoidCallback onFinalizar;
  final VoidCallback onCancelar;
  final VoidCallback? onEditar;
  final VoidCallback? onReverter;
  final VoidCallback? onAbrirPdf;

  const _OcCard({
    required this.ordem,
    required this.statusColor,
    required this.mostrarAcoes,
    this.mostrarReverter = false,
    required this.onTap,
    required this.onFinalizar,
    required this.onCancelar,
    this.onEditar,
    this.onReverter,
    this.onAbrirPdf,
  });

  @override
  State<_OcCard> createState() => _OcCardState();
}

class _OcCardState extends State<_OcCard> {
  bool _hovered = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final ordem = widget.ordem;
    final statusColor = widget.statusColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit: _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hovered
                ? Color(0xFFFF9800).withValues(alpha: 0.06)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [

              Positioned(
                left: 0, top: 0, bottom: 0, width: 4,
                child: ColoredBox(color: statusColor),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 16, top: 16, bottom: 16),
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'OC #${ordem.id} — ${ordem.fornecedorNome ?? 'Fornecedor'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  _formatMoeda(ordem.valorTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(Icons.person_outline, ordem.requisitante,
                    Theme.of(context).colorScheme.onSurfaceVariant),
                _chip(Icons.calendar_today_outlined, _formatData(ordem.data),
                    Theme.of(context).colorScheme.onSurfaceVariant),
                if (ordem.empresa != null)
                  _chip(Icons.business_outlined, ordem.empresa!,
                      Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
            if (ordem.numerosOS.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: ordem.numerosOS
                    .map((os) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(os,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
            if (ordem.itens.isNotEmpty) ...[
              const SizedBox(height: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ordem.itens.map((item) {

                  final nomeBase = item.materialNome.isNotEmpty
                      ? item.materialNome
                      : ((item.descricaoItem ?? '').isNotEmpty
                          ? item.descricaoItem!
                          : 'Material excluído');
                  final medidaOuDimensao = (item.materialMedida ?? '').isNotEmpty
                      ? item.materialMedida
                      : formatarMedidaOuDimensoes(
                          medida:      null,
                          largura:     item.materialLargura,
                          comprimento: item.materialComprimento,
                        );
                  final partes = <String>[
                    if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
                    if ((item.materialEspessura ?? '').isNotEmpty) espessuraExibicao(item.materialEspessura),
                  ];
                  final nomeComIdentificador = (item.materialIdentificador ?? '').isNotEmpty
                      ? '${item.materialIdentificador} · $nomeBase'
                      : nomeBase;
                  final desc = partes.isEmpty
                      ? nomeComIdentificador
                      : '$nomeComIdentificador · ${partes.join(' · ')}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (widget.mostrarAcoes) ...[
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Abrir PDF da ordem',
                    child: OutlinedButton.icon(
                      onPressed: widget.onAbrirPdf,
                      icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: Text('PDF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Editar ordem de compra',
                    child: OutlinedButton.icon(
                      onPressed: widget.onEditar,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Editar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Cancelar ordem de compra',
                    child: OutlinedButton.icon(
                      onPressed: widget.onCancelar,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Finalizar ordem de compra',
                    child: FilledButton.icon(
                      onPressed: widget.onFinalizar,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Finalizar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.mostrarReverter) ...[
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Abrir PDF da ordem',
                    child: OutlinedButton.icon(
                      onPressed: widget.onAbrirPdf,
                      icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: Text('PDF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Reverter ordem finalizada',
                    child: OutlinedButton.icon(
                      onPressed: widget.onReverter,
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Reverter'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB45309),
                        side: const BorderSide(color: Color(0xFFB45309)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13),
                      ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  String _formatData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatMoeda(double v) =>
      'R\$ ${formatarNumeroBr(v, 2)}';
}

class OrdemCompraDetalhePage extends StatefulWidget {
  final OrdemCompraModel ordem;
  const OrdemCompraDetalhePage({super.key, required this.ordem});
  @override
  State<OrdemCompraDetalhePage> createState() => OrdemCompraDetalhePageState();
}

class OrdemCompraDetalhePageState extends State<OrdemCompraDetalhePage> {
  late OrdemCompraModel _ordem;
  bool _processando = false;
  MaterialProvider? _materialProvider;

  @override
  void initState() {
    super.initState();
    _ordem = widget.ordem;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final novoProvider = context.read<MaterialProvider>();
    if (!identical(_materialProvider, novoProvider)) {
      _materialProvider?.removeListener(_onMateriaisAlterados);
      _materialProvider = novoProvider;
      _materialProvider!.addListener(_onMateriaisAlterados);
    }
  }

  void _onMateriaisAlterados() {
    if (!mounted || _processando) return;
    _recarregarOrdemAtual();
  }

  @override
  void dispose() {
    _materialProvider?.removeListener(_onMateriaisAlterados);
    super.dispose();
  }

  Future<void> _confirmarFinalizar() async {

    final osFechadas = context.read<EstoqueProvider>().numerosOSFechadas;
    final osBloqueadas = _ordem.numerosOS
        .where((os) => RegExp(r'^\d+$').hasMatch(os) && osFechadas.contains(os))
        .toList();
    if (osBloqueadas.isNotEmpty) {
      if (!mounted) return;
      showDialog(

        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(Icons.lock_outline, color: AppTheme.error, size: 22),
            SizedBox(width: 8),
            Text('OS Fechada', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Não é possível finalizar esta OC porque ${osBloqueadas.length == 1 ? 'a seguinte OS já foi fechada' : 'as seguintes OS já foram fechadas'} no controle de estoque:',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: osBloqueadas.map((os) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Text(os, style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13)),
                )).toList(),
              ),
              SizedBox(height: 12),
              Text(
                'Para prosseguir, reabra essa OS no controle de estoque antes de finalizar a OC.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Finalizar Ordem'),
        content: Text('Ao finalizar, os itens serão adicionados ao estoque. Confirmar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: Text('Cancelar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _processando = true);

    final provider = context.read<OrdemCompraProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await provider.finalizar(_ordem.id);
      messenger.showSnackBar(const SnackBar(content: Text('Ordem finalizada com sucesso!'), backgroundColor: AppTheme.success));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _confirmarCancelar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar Ordem'),
        content: Text('Tem certeza que deseja cancelar esta ordem de compra?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: Text('Voltar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar OC'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _processando = true);

    final provider = context.read<OrdemCompraProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await provider.cancelar(_ordem.id);
      messenger.showSnackBar(const SnackBar(content: Text('Ordem cancelada.'), backgroundColor: AppTheme.error));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _confirmarReverter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reverter Ordem Finalizada'),
        content: Text('Esta ação irá desfazer a finalização: os itens serão removidos do estoque e a ordem voltará para "Em Andamento". Confirmar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: Text('Voltar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _processando = true);

    final provider = context.read<OrdemCompraProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await provider.reverter(_ordem.id);
      messenger.showSnackBar(const SnackBar(content: Text('Ordem revertida para Em Andamento.'), backgroundColor: AppTheme.primary));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _abrirEdicao() async {
    final editado = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _EditarOrdemCompraPage(ordem: _ordem)));
    if (editado == true && mounted) {
      await _recarregarOrdemAtual();
    }
  }

  bool _recarregandoOrdem = false;

  Future<void> _recarregarOrdemAtual() async {
    if (_recarregandoOrdem) return;
    _recarregandoOrdem = true;
    try {
      final dados = await OrdemCompraRepository().buscarPorId(_ordem.id);
      final atualizado = OrdemCompraModel.fromJson(dados);
      if (mounted) setState(() => _ordem = atualizado);

      if (mounted) unawaited(context.read<OrdemCompraProvider>().carregar());
    } catch (e) {

      if (mounted) await context.read<OrdemCompraProvider>().carregar();
    } finally {
      _recarregandoOrdem = false;
    }
  }

  Future<void> _abrirPdf() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerando PDF…'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );
    try {
      final bytes = await OrdemCompraRepository().baixarPdf(_ordem.id);

      final fornecedor = (_ordem.fornecedorNome ?? 'FORNECEDOR')
          .toUpperCase()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = 'OC_${_ordem.id}_$fornecedor.pdf';

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (Platform.isWindows) {
        await Process.run('explorer', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emAndamento = _ordem.status == 'EM_ANDAMENTO';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              children: [
                _BotaoVoltar(
                  label: 'Ordens de Compra',
                  tooltip: 'Voltar para a lista de ordens de compra',
                  onTap: () => Navigator.of(context).pop(),
                ),
                SizedBox(width: 16),
                Text('OC #${_ordem.id}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
                SizedBox(width: 10),
                _statusBadge(_ordem.status),
                Spacer(),
                _headerActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: _abrirPdf,
                  tooltip: 'Gerar e abrir PDF desta ordem',
                ),
                if (emAndamento) ...[
                  const SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.cancel_outlined,
                    label: 'Cancelar',
                    color: AppTheme.error,
                    onPressed: _processando ? null : _confirmarCancelar,
                    tooltip: 'Cancelar esta ordem de compra',
                  ),
                  const SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Editar',
                    color: AppTheme.primary,
                    onPressed: _processando ? null : _abrirEdicao,
                    tooltip: 'Editar dados da ordem de compra',
                  ),
                  const SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.check_circle_outline,
                    label: 'Finalizar',
                    color: AppTheme.success,
                    filled: true,
                    onPressed: _processando ? null : _confirmarFinalizar,
                    tooltip: 'Finalizar e dar entrada no estoque',
                  ),
                ],
                if (_ordem.status == 'FINALIZADO') ...[
                  SizedBox(width: 8),
                  _headerActionButton(
                    icon: Icons.undo,
                    label: 'Reverter',
                    color: Color(0xFFB45309),
                    onPressed: _processando ? null : _confirmarReverter,
                    tooltip: 'Reverter finalização desta ordem',
                  ),
                ],
                SizedBox(width: 8),
                Tooltip(
                  message: 'Atualizar dados da ordem',
                  child: IconButton(
                    onPressed: _recarregar,
                    icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
        children: [
          _secaoCard('Informações Gerais', Icons.info_outline, [
            _infoRow(Icons.business_outlined, 'Fornecedor', _ordem.fornecedorNome ?? '—'),
            _infoRow(Icons.person_outline, 'Requisitante', _ordem.requisitante.isEmpty ? '—' : _ordem.requisitante),
            _infoRow(Icons.apartment_outlined, 'Empresa', _ordem.empresa ?? '—'),
            _infoRow(Icons.calendar_today_outlined, 'Data', _formatData(_ordem.data)),
            _infoRow(Icons.payment_outlined, 'Forma de Pagamento', _ordem.formaPagamento ?? '—'),
            _infoRow(Icons.schedule_outlined, 'Prazo de Pagamento', _ordem.prazoPagamento ?? '—'),
            if (_ordem.observacoes != null && _ordem.observacoes!.isNotEmpty)
              _infoRow(Icons.notes_outlined, 'Observações', _ordem.observacoes!),
          ]),
          const SizedBox(height: 16),
          if (_ordem.numerosOS.isNotEmpty) ...[
            _secaoCard('Números de OS', Icons.assignment_outlined, [
              Wrap(spacing: 6, runSpacing: 6, children: _ordem.numerosOS.map((os) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                child: Text(os, style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
              )).toList()),
            ]),
            SizedBox(height: 16),
          ],
          _secaoCard('Itens (${_ordem.itens.length})', Icons.inventory_2_outlined, [
            ..._ordem.itens.map((item) => Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (_) {
                          final nomeBase = item.materialNome.isNotEmpty ? item.materialNome : (item.descricaoItem ?? 'Material excluído');
                          final medidaOuDimensao = (item.materialMedida ?? '').isNotEmpty
                              ? item.materialMedida
                              : formatarMedidaOuDimensoes(
                                  medida:      null,
                                  largura:     item.materialLargura,
                                  comprimento: item.materialComprimento,
                                );
                          final detalhe = [
                            if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
                            if (item.materialEspessura != null && item.materialEspessura!.isNotEmpty) espessuraExibicao(item.materialEspessura),
                          ].join(' · ');
                          final prefixoIdentificador = (item.materialIdentificador != null && item.materialIdentificador!.isNotEmpty)
                              ? '${item.materialIdentificador}  ·  '
                              : '';
                          return Text.rich(
                            TextSpan(
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                              children: [
                                TextSpan(text: '$prefixoIdentificador$nomeBase'),
                                if (detalhe.isNotEmpty)
                                  TextSpan(text: '  ·  $detalhe'),
                              ],
                            ),
                          );
                        }),
                        if (item.materialNome.isNotEmpty && item.descricaoItem != null && item.descricaoItem!.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              item.descricaoItem!,
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text('R\$ ${formatarNumeroBr(item.precoTotal, 2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primary)),
                ]),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _itemChip(Icons.assignment_outlined, 'OS: ${item.numeroOS}'),
                    _itemChip(
                      Icons.format_list_numbered,
                      'Qtd: ${formatarQuantidade(item.quantidade)}',
                    ),

                    if (item.qtdUnidade != null && item.qtdUnidade! > 0)
                      _itemChipDestaque(
                        Icons.inventory_2_outlined,
                        '${formatarQuantidade(item.qtdUnidade!)} ${unidadeExibicao(item.materialUnidade).isEmpty ? 'unid.' : unidadeExibicao(item.materialUnidade)}/unidade',
                        ativo: true,
                      ),
                    _itemChipDestaque(
                      Icons.attach_money,
                      () {
                        if (item.qtdUnidade != null && item.qtdUnidade! > 0) {
                          return 'R\$ ${formatarNumeroBr(item.precoUnitario, 2)}/${unidadeExibicao(item.materialUnidade).isEmpty ? 'unid.' : unidadeExibicao(item.materialUnidade)}';
                        }
                        return item.precoUnitario > 0
                            ? 'Preço: R\$ ${formatarNumeroBr(item.precoUnitario, 2)}'
                            : 'Preço: —';
                      }(),
                      ativo: true,
                    ),
                  ],
                ),
              ]),
            )),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
                Text('R\$ ${formatarNumeroBr(_ordem.valorTotal, 2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.primary)),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
        ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recarregar() async {
    // Recarrega a listagem em segundo plano (não bloqueia a tela de
    // detalhe) e busca a OC atual diretamente por id — mais leve e
    // confiável do que procurar nas páginas já carregadas em memória,
    // já que a listagem agora é paginada.
    unawaited(context.read<OrdemCompraProvider>().carregar());
    try {
      final dados = await OrdemCompraRepository().buscarPorId(_ordem.id);
      if (mounted) {
        setState(() => _ordem = OrdemCompraModel.fromJson(dados));
      }
    } catch (_) {
      // Mantém os dados atuais em tela se a atualização falhar.
    }
  }

  Widget _secaoCard(String titulo, IconData icon, List<Widget> children) => Container(
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
    padding: EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 16, color: AppTheme.primary), SizedBox(width: 6), Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface))]),
      SizedBox(height: 12),
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
      SizedBox(height: 12),
      ...children,
    ]),
  );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: Theme.of(context).colorScheme.outline),
      SizedBox(width: 8),
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface))),
    ]),
  );

  Widget _itemChip(IconData icon, String label) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
          SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemChipDestaque(
    IconData icon,
    String label, {
    required bool ativo,
  }) {
    if (!ativo) {
      return SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
            SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return IntrinsicHeight(
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.primary),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerActionButton({
    required IconData icon,
    required String label,
    required Color color,
    bool filled = false,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    final button = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          );

    return Tooltip(
      message: tooltip ?? label,
      child: button,
    );
  }

  Widget _statusBadge(String status) {
    Color bg, fg; String label;
    switch (status) {
      case 'EM_ANDAMENTO': bg = AppTheme.primary.withValues(alpha: 0.10); fg = AppTheme.primary; label = 'Em Andamento'; break;
      case 'FINALIZADO': bg = const Color(0xFFF0FDF4); fg = AppTheme.success; label = 'Finalizada'; break;
      default: bg = const Color(0xFFFEF2F2); fg = AppTheme.error; label = 'Cancelada';
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)), child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)));
  }

  String _formatData(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

void _scrollToKey(GlobalKey key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  });
}

class _EditarOrdemCompraPage extends StatefulWidget {
  final OrdemCompraModel ordem;
  const _EditarOrdemCompraPage({required this.ordem});
  @override
  State<_EditarOrdemCompraPage> createState() => _EditarOrdemCompraPageState();
}

class _EditarOrdemCompraPageState extends State<_EditarOrdemCompraPage> {
  late DateTime _data;
  late final TextEditingController _requisitanteCtrl;
  late final TextEditingController _formaPagamentoCtrl;
  late final TextEditingController _prazoPagamentoCtrl;
  late final TextEditingController _observacoesCtrl;
  late String? _empresa;
  late List<String> _numerosOS;
  late List<_ItemRascunho> _itens;
  FornecedorModel? _fornecedor;
  bool _salvando = false;

  final GlobalKey _fornecedorKey = GlobalKey();
  final GlobalKey _empresaKey = GlobalKey();
  final GlobalKey _itensKey = GlobalKey();
  final GlobalKey _osSectionKey = GlobalKey();
  bool _erroFornecedor = false;
  bool _erroEmpresa = false;
  bool _erroItensVazio = false;
  bool _erroOS = false;

  List<FornecedorMaterialVinculoModel> get _materiaisDoFornecedor =>
      _fornecedor?.materiais ?? [];

  @override
  void initState() {
    super.initState();
    _data = widget.ordem.data;
    _empresa = widget.ordem.empresa;
    _numerosOS = List<String>.from(widget.ordem.numerosOS);
    _itens = _agruparItensEmRascunhos(widget.ordem.itens);
    _requisitanteCtrl = TextEditingController(text: widget.ordem.requisitante);
    _formaPagamentoCtrl = TextEditingController(text: widget.ordem.formaPagamento ?? '');
    _prazoPagamentoCtrl = TextEditingController(text: widget.ordem.prazoPagamento ?? '');
    _observacoesCtrl = TextEditingController(text: widget.ordem.observacoes ?? '');
    _carregarFornecedor();
  }

  List<_ItemRascunho> _agruparItensEmRascunhos(List<OrdemCompraItemModel> itens) {
    final grupos = <String, _ItemRascunho>{};
    for (final i in itens) {

      final materialId = i.materialId;
      if (materialId == null) continue;

      final chave = '$materialId|${i.precoUnitario}|${i.descricaoItem ?? ''}';
      if (grupos.containsKey(chave)) {

        final r = grupos[chave]!;
        r.distribuicao.add(_DistribuicaoLinha(os: i.numeroOS, quantidade: i.quantidade));
        r.quantidade += i.quantidade;
        r.numeroOS = r.distribuicao.first.os;
      } else {
        grupos[chave] = _ItemRascunho(
          materialId:            materialId,
          materialNome:          i.materialNome,
          materialUnidade:       i.materialUnidade,
          materialMedida:        i.materialMedida,
          materialEspessura:     i.materialEspessura,
          materialIdentificador: i.materialIdentificador,
          descricaoItem:         i.descricaoItem,
          numeroOS:              i.numeroOS,
          quantidade:            i.quantidade,
          qtdUnidade:            i.qtdUnidade,
          precoUnitario:         i.precoUnitario,
          precoMetroQuadrado:    i.precoMetroQuadrado,
          distribuicao: [_DistribuicaoLinha(os: i.numeroOS, quantidade: i.quantidade)],
        );
      }
    }
    return grupos.values.toList();
  }

  Future<void> _carregarFornecedor() async {
    final f = await context.read<FornecedorProvider>().buscarPorId(widget.ordem.fornecedorId);
    if (mounted) {
      setState(() {
        _fornecedor = f;
        if (f != null) {
          for (final item in _itens) {
            final vinculo = f.materiais.cast<FornecedorMaterialVinculoModel?>().firstWhere(
              (m) => m?.materialId == item.materialId,
              orElse: () => null,
            );
            if (vinculo != null) {
              item.materialLargura     = vinculo.materialLargura;
              item.materialComprimento = vinculo.materialComprimento;
            }
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _requisitanteCtrl.dispose();
    _formaPagamentoCtrl.dispose();
    _prazoPagamentoCtrl.dispose();
    _observacoesCtrl.dispose();
    super.dispose();
  }

  Future<void> _selecionarFornecedor() async {
    final provider = context.read<FornecedorProvider>();
    final selected = await showDialog<FornecedorModel>(
      context: context,
      builder: (_) => _FornecedorPicker(provider: provider),
    );
    if (selected != null) {
      final completo = await provider.buscarPorId(selected.id);
      if (mounted) {
        setState(() {
          _fornecedor = completo ?? selected;
          _erroFornecedor = false;
          final novosFornecedorMateriais = _fornecedor?.materiais ?? [];
          for (final item in _itens) {
            final vinculo = novosFornecedorMateriais
                .cast<FornecedorMaterialVinculoModel?>()
                .firstWhere(
                  (m) => m?.materialId == item.materialId,
                  orElse: () => null,
                );
            if (vinculo != null) {

              if (vinculo.preco > 0) {
                item.precoUnitario = vinculo.preco;
              }
            }
          }
        });
      }
    }
  }

  Future<void> _selecionarData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _data = d);
  }

  void _adicionarItem(FornecedorMaterialVinculoModel vinculo) {
    final osAuto = _numerosOS.length == 1 ? _numerosOS.first : '';
    setState(() {
      _erroItensVazio = false;
      _itens.add(_ItemRascunho(
        materialId:             vinculo.materialId,
        materialNome:           vinculo.materialNome ?? '',
        materialUnidade:        vinculo.materialUnidade,
        materialMedida:         vinculo.materialMedida,
        materialEspessura:      vinculo.materialEspessura,
        materialIdentificador:  vinculo.materialIdentificador,
        materialLargura:        vinculo.materialLargura,
        materialComprimento:    vinculo.materialComprimento,
        numeroOS:               osAuto,

        quantidade:             0,
        precoTotalInicial:      vinculo.preco > 0 ? vinculo.preco : null,
        precoMetroQuadrado:
            vinculo.precoMetroQuadrado > 0 ? vinculo.precoMetroQuadrado : null,
      ));
    });
  }

  void _removerItem(int idx) => setState(() => _itens.removeAt(idx));

  void _limparErros() {
    _erroFornecedor = false;
    _erroEmpresa = false;
    _erroItensVazio = false;
    _erroOS = false;
    for (final item in _itens) {
      item.erroOS = false;
      item.erroQtd = false;
      item.erroQtdUnidade = false;
      item.erroPreco = false;
    }
  }

  Future<void> _salvar() async {
    setState(_limparErros);

    if (_fornecedor == null) {
      setState(() => _erroFornecedor = true);
      _scrollToKey(_fornecedorKey);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um fornecedor.'), backgroundColor: AppTheme.error));
      return;
    }
    if (_empresa == null) {
      setState(() => _erroEmpresa = true);
      _scrollToKey(_empresaKey);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione a empresa.'), backgroundColor: AppTheme.error));
      return;
    }
    if (_itens.isEmpty) {
      setState(() => _erroItensVazio = true);
      _scrollToKey(_itensKey);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adicione pelo menos um item à ordem de compra.'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }
    if (_numerosOS.isEmpty) {
      setState(() => _erroOS = true);
      _scrollToKey(_osSectionKey);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Preencha ao menos um número de OS.'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }
    for (final item in _itens) {

      final temOSSelecionada = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os),
      );
      if (!temOSSelecionada) {
        setState(() => item.erroOS = true);
        _scrollToKey(item.cardKey);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Selecione a OS para o item "${item.materialNome}".'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }

      final linhaComZero = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os) && l.quantidade <= 0,
      );
      if (linhaComZero) {
        setState(() => item.erroQtd = true);
        _scrollToKey(item.cardKey);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('A quantidade deve ser maior que 0 para todos os itens da distribuição em "${item.materialNome}".'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }

      final totalDistribuido = item.distribuicao.fold(0.0, (s, l) => s + l.quantidade);
      final diff = totalDistribuido - item.quantidade;
      if (diff > 0.0001) {
        setState(() => item.erroQtd = true);
        _scrollToKey(item.cardKey);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('A quantidade distribuída (${formatarQuantidade(totalDistribuido)}) excede a quantidade do item "${item.materialNome}" (${formatarQuantidade(item.quantidade)}).'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
      if (diff < -0.0001) {
        setState(() => item.erroQtd = true);
        _scrollToKey(item.cardKey);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'A soma das quantidades distribuídas (${formatarQuantidade(totalDistribuido)}) '
            'está abaixo da quantidade do item "${item.materialNome}" '
            '(${formatarQuantidade(item.quantidade)}). '
            'O total distribuído deve ser igual à quantidade.',
          ),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
    }
    for (final item in _itens) {
      {
        if (item.precoUnitario <= 0) {
          setState(() => item.erroPreco = true);
          _scrollToKey(item.cardKey);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preencha o preço unitário de todos os itens.'),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }
      }
    }
    for (final item in _itens) {
      if (item.precisaQtdUnidade && (item.qtdUnidade == null || item.qtdUnidade! <= 0)) {
        setState(() => item.erroQtdUnidade = true);
        _scrollToKey(item.cardKey);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preencha o campo "${item.labelQtdUnidade}" do item "${item.materialNome}".'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    }
    setState(() => _salvando = true);
    try {
      await context.read<OrdemCompraProvider>().atualizar(widget.ordem.id, {
        'data': _data.toUtc().toIso8601String(),
        'fornecedorId': _fornecedor!.id,
        'requisitante': _requisitanteCtrl.text.trim(),
        'formaPagamento': _formaPagamentoCtrl.text.trim().isEmpty ? null : _formaPagamentoCtrl.text.trim(),
        'prazoPagamento': _prazoPagamentoCtrl.text.trim().isEmpty ? null : _prazoPagamentoCtrl.text.trim(),
        'observacoes': _observacoesCtrl.text.trim().isEmpty ? null : _observacoesCtrl.text.trim(),
        'empresa': _empresa,
        'numerosOS': _numerosOS,
        'itens': _itens.map((i) => {
          'materialId': i.materialId,
          'descricaoItem': i.descricaoItem,
          'numeroOS': i.distribuicao.firstWhere((l) => l.os.isNotEmpty, orElse: () => _DistribuicaoLinha()).os,
          'quantidade': i.quantidade,
          'qtdUnidade': i.qtdUnidade,
          'precoUnitario': i.precoUnitario,
          'precoMetroQuadrado': i.precoM2Calculado,
          'usarM2': false,
          'distribuicao': i.distribuicao.where((l) => l.os.isNotEmpty && l.quantidade > 0).map((l) => {'os': l.os, 'quantidade': l.quantidade}).toList(),
        }).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ordem atualizada com sucesso!'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  InputDecoration _deco(String hint, {bool hasError = false}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14),
    filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant, width: hasError ? 1.5 : 1)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasError ? AppTheme.error : AppTheme.primary, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.error, width: 1.5)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.error, width: 1.5)),
  );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _aviso(String msg) => Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
  );

  Widget _card({ Key? key, required String titulo, String? subtitulo, required List<Widget> children, Widget? trailing, bool hasError = false }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant, width: hasError ? 1.5 : 1),
      ),
      padding: EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            if (subtitulo != null) ...[
              SizedBox(height: 2),
              Text(subtitulo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ])),
          if (trailing != null) trailing,
        ]),
        if (children.isNotEmpty) ...[const SizedBox(height: 14), ...children],
      ]),
    );
  }

  Widget _empresaOption(String value, String label) {
    final selected = _empresa == value;
    return Expanded(
      child: Tooltip(
        message: 'Selecionar $label como empresa emissora',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
          onTap: () => setState(() {
            _empresa = value;
            _erroEmpresa = false;
          }),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary.withValues(alpha: 0.06) : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant, width: selected ? 1.5 : 1),
            ),
            child: Column(children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant)),
              SizedBox(height: 6),
              Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outline, size: 20),
            ]),
          ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            _BotaoVoltar(
              label: 'Voltar',
              tooltip: 'Voltar',
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Editar OC #${widget.ordem.id}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
            ),
          ],
        ),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16), child: Tooltip(
            message: 'Salvar alterações da ordem de compra',
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              child: _salvando ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          )),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        _card(titulo: 'Dados da Ordem de Compra', children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Número da OC'),
              InputDecorator(
                decoration: _deco('').copyWith(
                  prefixIcon: Icon(Icons.tag, size: 18, color: Theme.of(context).colorScheme.outline),
                  suffixText: 'Fixo',
                  suffixStyle: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                child: Text('#${widget.ordem.id}', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
              ),
            ])),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Data'),
              InkWell(
                onTap: _selecionarData,
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: _deco('').copyWith(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18, color: Theme.of(context).colorScheme.outline)),
                  child: Text(
                    '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            ])),
          ]),
          SizedBox(height: 14),

          _label('Fornecedor'),
          InkWell(
            key: _fornecedorKey,
            onTap: _selecionarFornecedor,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _deco('Buscar fornecedor...', hasError: _erroFornecedor).copyWith(prefixIcon: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.outline)),
              child: Text(
                _fornecedor?.nomeFantasia ?? widget.ordem.fornecedorNome ?? '',
                style: TextStyle(fontSize: 14, color: _fornecedor == null ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
          const SizedBox(height: 14),

          _label('Requisitante'),
          TextFormField(controller: _requisitanteCtrl, decoration: _deco('Nome do requisitante')),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Forma de Pagamento'),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: TextFormField(
                        controller: _formaPagamentoCtrl,
                        decoration: _deco(
                          'Ex: Boleto, À Vista, Crédito...',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Prazo de Pagamento'),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: TextFormField(
                        controller: _prazoPagamentoCtrl,
                        decoration: _deco(
                          'Ex: 30 dias, 15/30/45...',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _label('Observações'),
          TextFormField(
            controller: _observacoesCtrl,
            decoration: _deco('Observações gerais'),
            minLines: 3,
            maxLines: 20,
          ),
        ]),
        const SizedBox(height: 16),

        _card(
          key: _empresaKey,
          titulo: 'Empresa',
          subtitulo: 'Selecione a empresa que irá efetuar a ordem de compra.',
          hasError: _erroEmpresa,
          children: [
            Row(children: [
              _empresaOption('VISUAL PREMIUM', 'Visual Premium'),
              const SizedBox(width: 12),
              _empresaOption('VISUAL GUINDASTE', 'Visual Guindaste'),
            ]),
            if (_erroEmpresa) ...[
              const SizedBox(height: 8),
              Text('Selecione a empresa.', style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        const SizedBox(height: 16),

        _OsInputSection(
          key: _osSectionKey,
          numerosOS: _numerosOS,
          hasError: _erroOS,
          onChanged: () {
            setState(() {
              _erroOS = false;

              if (_numerosOS.length != 1) {
                for (final item in _itens) {
                  item.numeroOS = '';
                  for (final linha in item.distribuicao) {
                    linha.os = '';
                  }
                }
              }
            });
          },
        ),
        const SizedBox(height: 16),

        _card(
          key: _itensKey,
          titulo: 'Itens (${_itens.length})',
          hasError: _erroItensVazio && _itens.isEmpty,
          children: [
            if (_erroItensVazio && _itens.isEmpty) ...[
              Container(
                padding: EdgeInsets.all(10),
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, color: AppTheme.error, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Nenhum item adicionado.', style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ),
            ],
            if (_fornecedor == null)
              _aviso('Selecione um fornecedor para ver os materiais disponíveis.')
            else ...[
              SizedBox(
                width: double.infinity,
                child: Tooltip(
                  message: 'Adicionar item à ordem de compra',
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => _AdicionarItemDialog(
                          materiais: _materiaisDoFornecedor,
                          fornecedorId: _fornecedor!.id,
                          materiaisJaAdicionados: _itens.map((i) => i.materialId).toSet(),
                          onConfirmar: (lista) {
                            for (final v in lista) {
                              _adicionarItem(v);
                            }
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Adicionar Item'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                  ),
                ),
              ),
              if (_itens.isNotEmpty) ...[
                SizedBox(height: 16),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 8),
              ],
            ],
            ..._itens.asMap().entries.map((e) => _ItemFormCard(
              key: ValueKey(e.key),
              item: e.value,
              numerosOS: _numerosOS,
              onRemover: () => _removerItem(e.key),
              onChanged: () => setState(() {}),
            )),
            if (_itens.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                    Text(
                      'R\$ ${formatarNumeroBr(_itens.fold(0.0, (s, i) => s + i.precoTotal), 2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: Tooltip(
            message: 'Salvar as alterações desta ordem de compra',
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))
                  .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
              child: _salvando
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Salvar Alterações', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class ItemPreCarregadoOC {
  final int materialId;
  final String materialNome;
  final double quantidade;
  final double precoUnitario;
  final double? precoMetroQuadrado;
  final String? descricao;

  ItemPreCarregadoOC({
    required this.materialId,
    required this.materialNome,
    required this.quantidade,
    required this.precoUnitario,
    this.precoMetroQuadrado,
    this.descricao,
  });
}

class NovaOcTourKeys {
  final fornecedor              = GlobalKey();
  final requisitante            = GlobalKey();
  final formaPagamento          = GlobalKey();
  final prazoPagamento          = GlobalKey();
  final observacoes             = GlobalKey();
  final empresa                 = GlobalKey();
  final numerosOS               = GlobalKey();
  final atalhoEmpresa           = GlobalKey();
  final atalhoOutros            = GlobalKey();
  final campoOS                 = GlobalKey();
  final adicionarItem           = GlobalKey();
  final verTodoEstoque          = GlobalKey();
  final buscaMaterial           = GlobalKey();
  final botaoAdicionarMaterial  = GlobalKey();
  final botaoConfirmarAdicionar = GlobalKey();
  final itemUnidadeCampos       = GlobalKey();
  final itemOutraUnidadeCampos  = GlobalKey();
  final criarOc                 = GlobalKey();
}

class NovaOrdemCompraPage extends StatefulWidget {

  final List<ItemPreCarregadoOC> itensPreCarregados;

  final FornecedorModel? fornecedorInicial;

  final NovaOcTourKeys? tourKeys;

  const NovaOrdemCompraPage({
    super.key,
    this.itensPreCarregados = const [],
    this.fornecedorInicial,
    this.tourKeys,
  });

  @override
  State<NovaOrdemCompraPage> createState() => NovaOrdemCompraPageState();
}

class NovaOrdemCompraPageState extends State<NovaOrdemCompraPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = OrdemCompraRepository();

  DateTime _data = DateTime.now();
  FornecedorModel? _fornecedor;
  final _requisitanteCtrl    = TextEditingController();
  final _formaPagamentoCtrl  = TextEditingController();
  final _prazoPagamentoCtrl  = TextEditingController();
  final _observacoesCtrl     = TextEditingController();
  String? _empresa;
  final List<String> _numerosOS = [];
  final List<_ItemRascunho> _itens = [];
  bool _salvando = false;
  int? _proximoId;

  final GlobalKey _fornecedorKey = GlobalKey();
  final GlobalKey _empresaKey = GlobalKey();
  final GlobalKey _itensKey = GlobalKey();
  final GlobalKey _osSectionKey = GlobalKey();
  bool _erroFornecedor = false;
  bool _erroEmpresa = false;
  bool _erroItensVazio = false;
  bool _erroOS = false;

  bool _tourSimulado = false;
  bool _dialogItemTourAberto = false;
  bool _dialogItemTourEmTransicao = false;
  final GlobalKey<_AdicionarItemDialogState> _adicionarItemDialogTourKey =
      GlobalKey<_AdicionarItemDialogState>();

  static final _materiaisSimuladosTour = [
    FornecedorMaterialVinculoModel(
      id: -1,
      fornecedorId: -1,
      materialId: -1,
      materialNome: 'ABS AÇO ESCOVADO PRATA',
      materialIdentificador: 'IDEN-EXEMPLO',
      materialMedida: '1.20x0.60m',
      materialComprimento: 1.20,
      materialLargura: 0.60,
      materialEspessura: '13mm',
      materialUnidade: 'UNIDADE',
      preco: 170.11,
      precoMetroQuadrado: 0,
      ativo: true,
    ),
    FornecedorMaterialVinculoModel(
      id: -2,
      fornecedorId: -1,
      materialId: -2,
      materialNome: 'ADESIVO ORACAL 053 LIME TREE GREEN',
      materialIdentificador: '',
      materialMedida: '1.27m',
      materialUnidade: 'M/L',
      preco: 0,
      precoMetroQuadrado: 0,
      ativo: true,
    ),
  ];

  List<FornecedorMaterialVinculoModel> get _materiaisDoFornecedor =>
      _tourSimulado ? _materiaisSimuladosTour : (_fornecedor?.materiais ?? []);

  void simularFornecedorTour() {
    if (_fornecedor != null) return;
    setState(() {
      _tourSimulado = true;
      _fornecedor = FornecedorModel(
        id: -1,
        nomeFantasia: 'FORNECEDOR DE EXEMPLO',
        materiais: _materiaisSimuladosTour,
        ativo: true,
      );
      _erroFornecedor = false;
    });
  }

  Future<void> abrirAdicionarItemTour() async {
    if (_dialogItemTourAberto || _dialogItemTourEmTransicao) return;
    _dialogItemTourAberto = true;
    _dialogItemTourEmTransicao = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogItemTourEmTransicao = false;
    });
    showDialog(
      context: context,
      builder: (_) => _AdicionarItemDialog(
        key: _adicionarItemDialogTourKey,
        materiais: _materiaisDoFornecedor,
        fornecedorId: _fornecedor?.id ?? -1,
        materiaisJaAdicionados: _itens.map((i) => i.materialId).toSet(),
        tourKeys: widget.tourKeys,
        onConfirmar: (lista) {
          for (final v in lista) {
            _adicionarItem(v);
          }
        },
      ),
    ).then((_) {
      if (mounted) _dialogItemTourAberto = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> fecharAdicionarItemTourSeAberto() async {
    if (!_dialogItemTourAberto || _dialogItemTourEmTransicao) return;
    _dialogItemTourAberto = false;
    _dialogItemTourEmTransicao = true;
    await Navigator.of(context, rootNavigator: true).maybePop();
    _dialogItemTourEmTransicao = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// Marca os itens do tour como selecionados no diálogo "Adicionar Itens",
  /// deixando o botão "Adicionar" habilitado e destacável pelo tour — sem
  /// fechar o diálogo nem confirmar a adição. O diálogo só é de fato
  /// fechado quando o usuário (ou o próprio avanço do tour) aciona o botão
  /// real, como em qualquer outro stop.
  void selecionarItensParaConfirmarTour() {
    if (_itens.isNotEmpty) return;
    final dialogState = _adicionarItemDialogTourKey.currentState;
    dialogState?.selecionarTodosTour();
  }

  /// Confirma de fato a adição dos itens simulados/selecionados e fecha o
  /// diálogo "Adicionar Itens". Chamado ao entrar no stop seguinte ao
  /// botão "Adicionar" (depois do highlight nesse botão já ter sido
  /// mostrado), simulando o efeito real do clique no botão: os materiais
  /// de exemplo do tour passam a aparecer de verdade na lista "Itens" da
  /// página, e não só marcados visualmente dentro do diálogo.
  Future<void> confirmarESairDoDialogTour() async {
    if (_itens.isEmpty) {
      for (final v in _materiaisSimuladosTour) {
        _adicionarItem(v);
      }
    }
    await fecharAdicionarItemTourSeAberto();
  }

  /// Desfaz a confirmação simulada (remove os itens de exemplo adicionados
  /// por [confirmarESairDoDialogTour]) e reabre o diálogo "Adicionar Itens"
  /// com os materiais já marcados/selecionados, deixando o tour de volta
  /// exatamente no estado do stop "botaoConfirmarAdicionar" (diálogo aberto,
  /// highlight no botão "Adicionar"). Espelha o padrão usado em
  /// orcamento_editor_page.dart (_reabrirDialogPrecoAoVoltar).
  Future<void> desfazerConfirmacaoEReabrirDialogTour() async {
    setState(() {
      _itens.removeWhere((i) => i.materialId == -1 || i.materialId == -2);
    });
    await abrirAdicionarItemTour();
    selecionarItensParaConfirmarTour();
  }

  @override
  void initState() {
    super.initState();
    _carregarProximoId();

    if (widget.fornecedorInicial != null) {
      _fornecedor = widget.fornecedorInicial;
    }
    for (final item in widget.itensPreCarregados) {
        _itens.add(_ItemRascunho(
          materialId:         item.materialId,
          materialNome:       item.materialNome,
          numeroOS:           '',
          quantidade:         item.quantidade,
          precoUnitario:      item.precoUnitario,
          precoMetroQuadrado: item.precoMetroQuadrado,
          descricaoItem:      item.descricao,
        ));
      }
    }

  Future<void> _carregarProximoId() async {
    final id = await _repo.proximoId();
    if (mounted) setState(() => _proximoId = id);
  }

  @override
  void dispose() {
    _requisitanteCtrl.dispose();
    _formaPagamentoCtrl.dispose();
    _prazoPagamentoCtrl.dispose();
    _observacoesCtrl.dispose();
    super.dispose();
  }

  void _limparErros() {
    _erroFornecedor = false;
    _erroEmpresa = false;
    _erroItensVazio = false;
    _erroOS = false;
    for (final item in _itens) {
      item.erroOS = false;
      item.erroQtd = false;
      item.erroQtdUnidade = false;
      item.erroPreco = false;
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(_limparErros);

    if (_fornecedor == null) {
      setState(() => _erroFornecedor = true);
      _scrollToKey(_fornecedorKey);
      _showErro('Selecione um fornecedor.');
      return;
    }
    if (_empresa == null) {
      setState(() => _erroEmpresa = true);
      _scrollToKey(_empresaKey);
      _showErro('Selecione a empresa.');
      return;
    }

    if (_itens.isEmpty) {
      setState(() => _erroItensVazio = true);
      _scrollToKey(_itensKey);
      _showErro('Adicione pelo menos um item à ordem de compra.');
      return;
    }

    if (_numerosOS.isEmpty) {
      setState(() => _erroOS = true);
      _scrollToKey(_osSectionKey);
      _showErro('Preencha ao menos um número de OS.');
      return;
    }

    for (final item in _itens) {

      final temOSSelecionada = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os),
      );
      if (!temOSSelecionada) {
        setState(() => item.erroOS = true);
        _scrollToKey(item.cardKey);
        _showErro('Selecione a OS para o item "${item.materialNome}".');
        return;
      }

      final linhaComZero = item.distribuicao.any(
        (l) => l.os.isNotEmpty && _numerosOS.contains(l.os) && l.quantidade <= 0,
      );
      if (linhaComZero) {
        setState(() => item.erroQtd = true);
        _scrollToKey(item.cardKey);
        _showErro('A quantidade deve ser maior que 0 para todos os itens da distribuição em "${item.materialNome}".');
        return;
      }

      final totalDistribuido = item.distribuicao.fold(0.0, (s, l) => s + l.quantidade);
      final diff = totalDistribuido - item.quantidade;
      if (diff > 0.0001) {
        setState(() => item.erroQtd = true);
        _scrollToKey(item.cardKey);
        _showErro('A quantidade distribuída (${formatarQuantidade(totalDistribuido)}) excede a quantidade do item "${item.materialNome}" (${formatarQuantidade(item.quantidade)}).');
        return;
      }
      if (diff < -0.0001) {
        setState(() => item.erroQtd = true);
        _scrollToKey(item.cardKey);
        _showErro(
          'A soma das quantidades distribuídas (${formatarQuantidade(totalDistribuido)}) '
          'está abaixo da quantidade do item "${item.materialNome}" '
          '(${formatarQuantidade(item.quantidade)}). '
          'O total distribuído deve ser igual à quantidade.',
        );
        return;
      }
    }
    for (final item in _itens) {
      {
        if (item.precoUnitario <= 0) {
          setState(() => item.erroPreco = true);
          _scrollToKey(item.cardKey);
          _showErro('Preencha o preço unitário de todos os itens.');
          return;
        }
      }
    }
    for (final item in _itens) {
      if (item.precisaQtdUnidade && (item.qtdUnidade == null || item.qtdUnidade! <= 0)) {
        setState(() => item.erroQtdUnidade = true);
        _scrollToKey(item.cardKey);
        _showErro('Preencha o campo "${item.labelQtdUnidade}" do item "${item.materialNome}".');
        return;
      }
    }

    setState(() => _salvando = true);
    try {
      await context.read<OrdemCompraProvider>().criar({
        'data': _data.toUtc().toIso8601String(),
        'fornecedorId': _fornecedor!.id,
        'requisitante': _requisitanteCtrl.text.trim(),
        'formaPagamento': _formaPagamentoCtrl.text.trim().isEmpty
            ? null
            : _formaPagamentoCtrl.text.trim(),
        'prazoPagamento': _prazoPagamentoCtrl.text.trim().isEmpty
            ? null
            : _prazoPagamentoCtrl.text.trim(),
        'observacoes': _observacoesCtrl.text.trim().isEmpty
            ? null
            : _observacoesCtrl.text.trim(),
        'empresa': _empresa,
        'numerosOS': _numerosOS,
        'itens': _itens
            .map((i) => {
                  'materialId': i.materialId,
                  'descricaoItem': i.descricaoItem,
                  'numeroOS': i.distribuicao.firstWhere((l) => l.os.isNotEmpty, orElse: () => _DistribuicaoLinha()).os,
                  'quantidade': i.quantidade,
                  'qtdUnidade': i.qtdUnidade,
                  'precoUnitario': i.precoUnitario,
                  'precoMetroQuadrado': i.precoM2Calculado,
                  'usarM2': false,
                  'distribuicao': i.distribuicao.where((l) => l.os.isNotEmpty && l.quantidade > 0).map((l) => {'os': l.os, 'quantidade': l.quantidade}).toList(),
                })
            .toList(),
      });

      if (!mounted) return;

      final provider = context.read<OrdemCompraProvider>();
      await provider.carregar();

      if (!mounted) return;

      OrdemCompraModel? ocCriada;

      if (_proximoId != null) {
        final todas = [...provider.emAndamento, ...provider.finalizadas, ...provider.canceladas];
        final raw = todas.cast<dynamic>().firstWhere(
          (o) {
            if (o == null) return false;
            final m = o is OrdemCompraModel ? o : OrdemCompraModel.fromJson(o as Map<String, dynamic>);
            return m.id == _proximoId;
          },
          orElse: () => null,
        );
        if (raw != null) {
          ocCriada = raw is OrdemCompraModel
              ? raw
              : OrdemCompraModel.fromJson(raw as Map<String, dynamic>);
        }
      }

      ocCriada ??= provider.emAndamento.isNotEmpty
          ? (provider.emAndamento.first is OrdemCompraModel
              ? provider.emAndamento.first as OrdemCompraModel
              : OrdemCompraModel.fromJson(provider.emAndamento.first as Map<String, dynamic>))
          : null;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ordem de compra criada com sucesso!'),
            backgroundColor: AppTheme.success),
      );

      Navigator.of(context).pop(ocCriada ?? true);
    } catch (e) {
      _showErro(e.toString());
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _showErro(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.error));
  }

   void _adicionarItem(FornecedorMaterialVinculoModel vinculo) {

    final osAuto = _numerosOS.length == 1 ? _numerosOS.first : '';
    setState(() {
      _erroItensVazio = false;
      _itens.add(_ItemRascunho(
        materialId:             vinculo.materialId,
        materialNome:           vinculo.materialNome ?? '',
        materialUnidade:        vinculo.materialUnidade,
        materialMedida:         vinculo.materialMedida,
        materialEspessura:      vinculo.materialEspessura,
        materialIdentificador:  vinculo.materialIdentificador,
        materialLargura:        vinculo.materialLargura,
        materialComprimento:    vinculo.materialComprimento,
        numeroOS:               osAuto,

        quantidade:             0,
        precoTotalInicial:      vinculo.preco > 0 ? vinculo.preco : null,
        precoMetroQuadrado:
            vinculo.precoMetroQuadrado > 0 ? vinculo.precoMetroQuadrado : null,
      ));
    });
  }

  void _removerItem(int idx) {
    setState(() => _itens.removeAt(idx));
  }

  Future<void> _selecionarFornecedor() async {
    final provider = context.read<FornecedorProvider>();
    final selected = await showDialog<FornecedorModel>(
      context: context,
      builder: (_) => _FornecedorPicker(provider: provider),
    );
    if (selected != null) {
      final completo = await provider.buscarPorId(selected.id);
      if (mounted) {
        setState(() {
          _fornecedor = completo ?? selected;
          _erroFornecedor = false;
          _itens.clear();
        });
      }
    }
  }

  Future<void> _selecionarData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            _BotaoVoltar(
              label: 'Voltar',
              tooltip: 'Voltar',
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.itensPreCarregados.isNotEmpty
                    ? 'Nova OC — do Orçamento'
                    : 'Nova Ordem de Compra',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Criar esta ordem de compra',
              child: FilledButton(
                onPressed: _salvando ? null : _salvar,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                child: _salvando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Criar OC',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [

            if (widget.itensPreCarregados.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.itensPreCarregados.length} '
                        '${widget.itensPreCarregados.length == 1 ? 'item importado' : 'itens importados'} '
                        'do orçamento. Adicione o número de OS e salve.',
                        style: const TextStyle(fontSize: 13, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            _card(
              titulo: 'Dados da Ordem de Compra',
              children: [

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Número da OC'),
                          InputDecorator(
                            decoration: _deco('').copyWith(
                              prefixIcon: Icon(Icons.tag,
                                  size: 18, color: Theme.of(context).colorScheme.outline),
                              suffixText: 'Automático',
                              suffixStyle: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                            child: Text(
                              _proximoId != null ? '$_proximoId' : '—',
                              style: TextStyle(
                                color: _proximoId != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.outline,
                                fontSize: 14,
                              )
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Data'),
                          InkWell(
                            onTap: _selecionarData,
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: _deco('').copyWith(
                                suffixIcon: Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.outline),
                              ),
                              child: Text(
                                '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),

                Container(
                  key: widget.tourKeys?.fornecedor ?? _fornecedorKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Fornecedor principal'),
                      InkWell(
                        onTap: _selecionarFornecedor,
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: _deco('Buscar fornecedor...', hasError: _erroFornecedor).copyWith(
                            prefixIcon: Icon(Icons.search,
                                size: 18, color: Theme.of(context).colorScheme.outline),
                          ),
                          child: Text(
                            _fornecedor?.nomeFantasia ?? '',
                            style: TextStyle(
                                fontSize: 14,
                                color: _fornecedor == null
                                    ? Theme.of(context).colorScheme.outline
                                    : Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                Container(
                  key: widget.tourKeys?.requisitante,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Requisitante'),
                      TextFormField(
                        controller: _requisitanteCtrl,
                        decoration: _deco('Nome do requisitante'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        key: widget.tourKeys?.formaPagamento,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Forma de Pagamento'),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              child: TextFormField(
                                controller: _formaPagamentoCtrl,
                                decoration: _deco(
                                  'Ex: Boleto, À Vista, Crédito...',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        key: widget.tourKeys?.prazoPagamento,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Prazo de Pagamento'),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              child: TextFormField(
                                controller: _prazoPagamentoCtrl,
                                decoration: _deco(
                                  'Ex: 30 dias, 15/30/45...',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Container(
                  key: widget.tourKeys?.observacoes,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Observações'),
                      TextFormField(
                        controller: _observacoesCtrl,
                        decoration: _deco('Observações gerais'),
                        minLines: 3,
                        maxLines: null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _card(
              key: widget.tourKeys?.empresa ?? _empresaKey,
              titulo: 'Empresa',
              subtitulo:
                  'Selecione a empresa que aparecerá no cabeçalho da Ordem de Compra:',
              hasError: _erroEmpresa,
              children: [
                Row(
                  children: [
                    _empresaOption('VISUAL PREMIUM', 'Visual Premium'),
                    const SizedBox(width: 12),
                    _empresaOption('VISUAL GUINDASTE', 'Visual Guindaste'),
                  ],
                ),
                if (_erroEmpresa) ...[
                  const SizedBox(height: 8),
                  Text('Selecione a empresa.', style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
            const SizedBox(height: 16),

            _OsInputSection(
              key: widget.tourKeys?.numerosOS ?? _osSectionKey,
              numerosOS: _numerosOS,
              hasError: _erroOS,
              tourKeys: widget.tourKeys,
              onChanged: () {
                setState(() {
                  _erroOS = false;

                  if (_numerosOS.length != 1) {
                    for (final item in _itens) {
                      item.numeroOS = '';
                      for (final linha in item.distribuicao) {
                        linha.os = '';
                      }
                    }
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            _card(
              key: _itensKey,
              titulo: 'Itens (${_itens.length})',
              hasError: _erroItensVazio && _itens.isEmpty,
              children: [
                if (_erroItensVazio && _itens.isEmpty) ...[
                  Container(
                    padding: EdgeInsets.all(10),
                    margin: EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.error),
                    ),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: AppTheme.error, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text('Nenhum item adicionado.', style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ],
                if (_fornecedor == null)
                  _aviso(
                      'Selecione um fornecedor para ver os materiais disponíveis.')
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: Tooltip(
                      message: 'Adicionar item à ordem de compra',
                      child: OutlinedButton.icon(
                        key: widget.tourKeys?.adicionarItem,
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => _AdicionarItemDialog(
                              materiais: _materiaisDoFornecedor,
                              fornecedorId: _fornecedor!.id,
                              materiaisJaAdicionados: _itens.map((i) => i.materialId).toSet(),
                              onConfirmar: (lista) {
                                for (final v in lista) {
                                  _adicionarItem(v);
                                }
                              },
                            ),
                          );
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar Item'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                      ),
                    ),
                  ),
                  if (_itens.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Divider(color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                  ],
                ],
                ..._itens.asMap().entries.map((e) {
                  final idx = e.key;
                  final item = e.value;
                  return _ItemFormCard(
                    key: ValueKey('${item.materialId}_$idx'),
                    item: item,
                    numerosOS: _numerosOS,
                    onRemover: () => _removerItem(idx),
                    onChanged: () => setState(() {}),
                    tourKeys: widget.tourKeys,
                  );
                }),
                if (_itens.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface)),
                        Text(
                          'R\$ ${formatarNumeroBr(_itens.fold(0.0, (s, i) => s + i.precoTotal), 2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: Tooltip(
                message: 'Criar esta ordem de compra',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: widget.tourKeys?.criarOc,
                    onTap: _salvando ? null : _salvar,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: _salvando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Criar Ordem de Compra',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _card({
    Key? key,
    required String titulo,
    String? subtitulo,
    required List<Widget> children,
    Widget? trailing,
    bool hasError = false,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant, width: hasError ? 1.5 : 1),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                    if (subtitulo != null) ...[
                      SizedBox(height: 2),
                      Text(subtitulo,
                          style: TextStyle(
                              fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...children,
          ],
        ],
      ),
    );
  }

  Widget _empresaOption(String value, String label) {
    final selected = _empresa == value;
    return Expanded(
      child: Tooltip(
        message: 'Selecionar $label como empresa emissora',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
          onTap: () => setState(() {
            _empresa = value;
            _erroEmpresa = false;
          }),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.06)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: selected ? AppTheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 6),
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                  size: 20,
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _aviso(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(msg,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
      );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  InputDecoration _deco(String hint, {bool hasError = false}) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant, width: hasError ? 1.5 : 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? AppTheme.error : AppTheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

class _OsInputSection extends StatefulWidget {
  final List<String> numerosOS;
  final VoidCallback onChanged;
  final bool hasError;
  final NovaOcTourKeys? tourKeys;

  const _OsInputSection({super.key, required this.numerosOS, required this.onChanged, this.hasError = false, this.tourKeys});

  @override
  State<_OsInputSection> createState() => _OsInputSectionState();
}

class _OsInputSectionState extends State<_OsInputSection> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();

    _controllers = [
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
    ];

    for (int i = 0; i < widget.numerosOS.length; i++) {
      if (i < _controllers.length) {
        _controllers[i].text = widget.numerosOS[i];
      } else {
        _controllers.add(TextEditingController(text: widget.numerosOS[i]));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _sincronizar() {
    final novos = _controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    widget.numerosOS
      ..clear()
      ..addAll(novos);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged();
    });
  }

  void _adicionarCampo() {
    setState(() => _controllers.add(TextEditingController()));
  }

  void _removerCampo(int idx) {
    setState(() {
      _controllers[idx].dispose();
      _controllers.removeAt(idx);
    });
    _sincronizar();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        prefixIcon: Icon(Icons.assignment_outlined, size: 18, color: Theme.of(context).colorScheme.outline),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final hasValue = _controllers.any((c) => c.text.trim().isNotEmpty);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.hasError
              ? AppTheme.error
              : (!hasValue ? AppTheme.primary.withValues(alpha: 0.5) : Theme.of(context).colorScheme.outlineVariant),
          width: widget.hasError || !hasValue ? 1.5 : 1,
        ),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Números de OS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          ]),
          SizedBox(height: 4),
          Text(
            'Preencha ao menos uma OS. Se houver apenas uma, ela será atribuída automaticamente aos itens.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            children: [
              Tooltip(
                message: "Preenche automaticamente com 'EMPRESA'",
                child: _AtalhoChip(
                  key: widget.tourKeys?.atalhoEmpresa,
                  label: 'Empresa',
                  onTap: () {

                    final idx = _controllers.indexWhere((c) => c.text.trim().isEmpty);
                    if (idx != -1) {
                      setState(() => _controllers[idx].text = 'EMPRESA');
                    } else {
                      setState(() => _controllers.add(TextEditingController(text: 'EMPRESA')));
                    }
                    _sincronizar();
                  },
                ),
              ),
              Tooltip(
                message: "Preenche automaticamente com 'OUTROS'",
                child: _AtalhoChip(
                  key: widget.tourKeys?.atalhoOutros,
                  label: 'Outros',
                  onTap: () {
                    final idx = _controllers.indexWhere((c) => c.text.trim().isEmpty);
                    if (idx != -1) {
                      setState(() => _controllers[idx].text = 'OUTROS');
                    } else {
                      setState(() => _controllers.add(TextEditingController(text: 'OUTROS')));
                    }
                    _sincronizar();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ...List.generate(_controllers.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: i == 0 ? widget.tourKeys?.campoOS : null,
                      controller: _controllers[i],
                      decoration: _deco('OS ${i + 1}'),
                      onChanged: (_) => _sincronizar(),
                    ),
                  ),
                  if (_controllers.length > 1) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => _removerCampo(i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Remover campo',
                      icon: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: const Icon(
                          Icons.remove_circle_outline,
                          color: AppTheme.error,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

         Tooltip(
          message: 'Adicionar mais um campo para informar outra OS',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _adicionarCampo,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.add,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Adicionar campo de OS',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
          if (widget.hasError) ...[
            const SizedBox(height: 8),
            Text('Preencha ao menos um número de OS.', style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

}

class _AtalhoChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _AtalhoChip({super.key, required this.label, required this.onTap});

  @override
  State<_AtalhoChip> createState() => _AtalhoChipState();
}

class _AtalhoChipState extends State<_AtalhoChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      opaque: false,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? AppTheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(
              color: _hover ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.6),
              width: _hover ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _hover ? AppTheme.primary : Theme.of(context).colorScheme.onSurface,
              fontWeight: _hover ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _DistribuicaoLinha {
  String os;
  double quantidade;
  _DistribuicaoLinha({this.os = '', this.quantidade = 0});
}

class _ItemRascunho {
  int materialId;
  String materialNome;
  String? materialUnidade;
  String? materialMedida;
  String? materialEspessura;
  String? materialIdentificador;
  double? materialLargura;
  double? materialComprimento;
  String? descricaoItem;
  String numeroOS;
  double quantidade;
  double? qtdUnidade;
  double precoUnitario;
  double? precoMetroQuadrado;
  double? precoTotalInicial;
  List<_DistribuicaoLinha> distribuicao;

  final GlobalKey cardKey = GlobalKey();

  bool erroOS = false;
  bool erroQtd = false;
  bool erroQtdUnidade = false;
  bool erroPreco = false;

  _ItemRascunho({
    required this.materialId,
    required this.materialNome,
    this.materialUnidade,
    this.materialMedida,
    this.materialEspessura,
    this.materialIdentificador,
    this.materialLargura,
    this.materialComprimento,
    this.descricaoItem,
    required this.numeroOS,
    required this.quantidade,
    this.qtdUnidade,
    this.precoUnitario = 0,
    this.precoMetroQuadrado,
    this.precoTotalInicial,
    List<_DistribuicaoLinha>? distribuicao,
  }) : distribuicao = distribuicao ?? [_DistribuicaoLinha(os: numeroOS, quantidade: quantidade)];

  bool get temDimensoes =>
      materialLargura != null && materialLargura! > 0 &&
      materialComprimento != null && materialComprimento! > 0;

  double? get precoM2Calculado {
    if (!temDimensoes || precoUnitario <= 0) return null;
    return precoUnitario / (materialLargura! * materialComprimento!);
  }

  bool get precisaQtdUnidade {
    final u = (materialUnidade ?? '').toUpperCase().trim();
    return u.isNotEmpty && u != 'UNIDADE';
  }

  String get labelQtdUnidade {
    final u = unidadeDescricaoCompleta(materialUnidade);
    return u.isEmpty ? 'Qtd por unidade' : '$u por unidade';
  }

  double get quantidadeEstoque {
    if (qtdUnidade != null && qtdUnidade! > 0) return quantidade * qtdUnidade!;
    return quantidade;
  }

  double get precoTotal {
    if (precisaQtdUnidade && qtdUnidade != null && qtdUnidade! > 0) {
      return quantidade * qtdUnidade! * precoUnitario;
    }
    return quantidade * precoUnitario;
  }
}

class _ItemFormCard extends StatefulWidget {
  final _ItemRascunho item;
  final List<String> numerosOS;
  final VoidCallback onRemover;
  final VoidCallback onChanged;
  final NovaOcTourKeys? tourKeys;

  const _ItemFormCard({
    super.key,
    required this.item,
    required this.numerosOS,
    required this.onRemover,
    required this.onChanged,
    this.tourKeys,
  });

  @override
  State<_ItemFormCard> createState() => _ItemFormCardState();
}

class _ItemFormCardState extends State<_ItemFormCard> {
  late TextEditingController _qtdCtrl;
  late TextEditingController _qtdUnidadeCtrl;
  late TextEditingController _precoCtrl;
  late TextEditingController _precoTotalCtrl;
  late TextEditingController _descricaoCtrl;

  bool _ignorarCalculo = false;
  String _campoEditado = 'unitario';

  @override
  void initState() {
    super.initState();
    _qtdCtrl = TextEditingController(
        text: widget.item.quantidade == 0
            ? ''
            : formatarNumeroBr(widget.item.quantidade,
                widget.item.quantidade % 1 == 0 ? 0 : 2));
    _qtdUnidadeCtrl = TextEditingController(
        text: widget.item.qtdUnidade == null || widget.item.qtdUnidade == 0
            ? ''
            : formatarNumeroBr(widget.item.qtdUnidade!,
                widget.item.qtdUnidade! % 1 == 0 ? 0 : 3));
    _precoCtrl = TextEditingController(
        text: widget.item.precoUnitario == 0
            ? ''
            : formatarNumeroBr(widget.item.precoUnitario, 2));

    final precoTotalCalculado = _calcularPrecoTotal();
    final usarPrecoTotalInicial = precoTotalCalculado == 0 &&
        widget.item.precoUnitario == 0 &&
        widget.item.precoTotalInicial != null &&
        widget.item.precoTotalInicial! > 0;

    _precoTotalCtrl = TextEditingController(
        text: usarPrecoTotalInicial
            ? formatarNumeroBr(widget.item.precoTotalInicial!, 2)
            : (precoTotalCalculado == 0
                ? ''
                : formatarNumeroBr(precoTotalCalculado, 2)));

    if (usarPrecoTotalInicial) {
      _campoEditado = 'total';
    }

    _descricaoCtrl = TextEditingController(
        text: widget.item.descricaoItem ?? '');

    _precoCtrl.addListener(_onPrecoUnitarioChanged);
    _precoTotalCtrl.addListener(_onPrecoTotalChanged);
  }

  @override
  void dispose() {
    _precoCtrl.removeListener(_onPrecoUnitarioChanged);
    _precoTotalCtrl.removeListener(_onPrecoTotalChanged);
    _qtdCtrl.dispose();
    _qtdUnidadeCtrl.dispose();
    _precoCtrl.dispose();
    _precoTotalCtrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  double _calcularPrecoTotal() {
    final qtd = parseNumeroBr(_qtdCtrl.text) ?? 0;
    final qtdUnit = parseNumeroBr(_qtdUnidadeCtrl.text);
    final preco = parseNumeroBr(_precoCtrl.text) ?? 0;

    if (qtd <= 0 || preco <= 0) return 0;

    if (qtdUnit != null && qtdUnit > 0) {
      return qtd * qtdUnit * preco;
    }
    return qtd * preco;
  }

  void _onPrecoUnitarioChanged() {
    if (_ignorarCalculo) return;

    final preco = parseNumeroBr(_precoCtrl.text);
    if (preco == null || preco <= 0) {
      if (_campoEditado == 'unitario' && _precoTotalCtrl.text.isNotEmpty) {
        _ignorarCalculo = true;
        _precoTotalCtrl.clear();
        _ignorarCalculo = false;
      }
      return;
    }

    _campoEditado = 'unitario';

    final total = _calcularPrecoTotal();
    if (total > 0) {
      final novoTexto = formatarNumeroBr(total, 2);
      if (_precoTotalCtrl.text != novoTexto) {
        _ignorarCalculo = true;
        _precoTotalCtrl.text = novoTexto;
        _ignorarCalculo = false;
      }
    }
  }

  void _onPrecoTotalChanged() {
    if (_ignorarCalculo) return;

    final total = parseNumeroBr(_precoTotalCtrl.text);
    if (total == null || total <= 0) {
      return;
    }

    _campoEditado = 'total';

    final qtd = parseNumeroBr(_qtdCtrl.text) ?? 0;
    final qtdUnit = parseNumeroBr(_qtdUnidadeCtrl.text);

    if (qtd <= 0) return;

    double precoUnitario;
    if (qtdUnit != null && qtdUnit > 0) {
      precoUnitario = total / (qtd * qtdUnit);
    } else {
      precoUnitario = total / qtd;
    }

    final novoTexto = formatarNumeroBr(precoUnitario, 2);
    if (_precoCtrl.text != novoTexto) {
      _ignorarCalculo = true;
      _precoCtrl.text = novoTexto;
      widget.item.precoUnitario = precoUnitario;
      _ignorarCalculo = false;
      widget.onChanged();
      setState(() {});
    }
  }

  void _recalcularComBaseNaPrioridade() {
    if (_campoEditado == 'total') {
      final total = parseNumeroBr(_precoTotalCtrl.text);
      if (total != null && total > 0) {
        final qtd = parseNumeroBr(_qtdCtrl.text) ?? 0;
        final qtdUnit = parseNumeroBr(_qtdUnidadeCtrl.text);

        if (qtd > 0) {
          double precoUnitario;
          if (qtdUnit != null && qtdUnit > 0) {
            precoUnitario = total / (qtd * qtdUnit);
          } else {
            precoUnitario = total / qtd;
          }

          _ignorarCalculo = true;
          _precoCtrl.text = formatarNumeroBr(precoUnitario, 2);
          widget.item.precoUnitario = precoUnitario;
          _ignorarCalculo = false;
        }
      }
    } else {
      final preco = parseNumeroBr(_precoCtrl.text);
      if (preco != null && preco > 0) {
        final total = _calcularPrecoTotal();
        if (total > 0) {
          _ignorarCalculo = true;
          _precoTotalCtrl.text = formatarNumeroBr(total, 2);
          _ignorarCalculo = false;
        }
      }
    }
  }

  InputDecoration _deco(String hint, {bool hasError = false}) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hasError ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant, width: hasError ? 1.5 : 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hasError ? AppTheme.error : AppTheme.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final total = item.precoTotal;
    final unidade = unidadeExibicao(item.materialUnidade);
    final labelQtd = 'Quantidade';

    return Container(
      key: item.cardKey,
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (_) {
                      final medidaOuDimensao = (item.materialMedida ?? '').isNotEmpty
                          ? item.materialMedida
                          : formatarMedidaOuDimensoes(
                              medida:      null,
                              largura:     item.materialLargura,
                              comprimento: item.materialComprimento,
                            );
                      final detalhe = [
                        if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
                        if (item.materialEspessura != null && item.materialEspessura!.isNotEmpty) espessuraExibicao(item.materialEspessura),
                      ].join(' · ');
                      final prefixoIdentificador = (item.materialIdentificador != null && item.materialIdentificador!.isNotEmpty)
                          ? '${item.materialIdentificador}  ·  '
                          : '';
                      return Text.rich(
                        TextSpan(
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface),
                          children: [
                            TextSpan(text: '$prefixoIdentificador${item.materialNome}'),
                            if (detalhe.isNotEmpty)
                              TextSpan(text: '  ·  $detalhe'),
                          ],
                        ),
                      );
                    }),
                    if (unidade.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(unidade, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: IconButton(
                  onPressed: widget.onRemover,
                  icon: const Icon(Icons.delete_outline,
                      color: AppTheme.error, size: 20),
                  tooltip: 'Excluir item',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                  style: IconButton.styleFrom().copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DistribuicaoSection(
            item: item,
            numerosOS: widget.numerosOS,
            onChanged: () {
              final primeira = item.distribuicao
                  .firstWhere((l) => l.os.isNotEmpty, orElse: () => _DistribuicaoLinha());
              item.numeroOS = primeira.os;
              widget.onChanged();
              setState(() {});
            },
          ),
          SizedBox(height: 8),
          if (item.precisaQtdUnidade) ...[
            Container(
              key: item.materialId == -2 ? widget.tourKeys?.itemOutraUnidadeCampos : null,
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(labelQtd,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _qtdCtrl,
                        decoration: _deco('0', hasError: item.erroQtd),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_NumeroBrFormatter(casasDecimais: 2)],
                        onChanged: (v) {
                          item.quantidade = parseNumeroBr(v) ?? 0;
                          item.erroQtd = false;
                          if (widget.numerosOS.length == 1 && item.distribuicao.length == 1) {
                            item.distribuicao[0].os = widget.numerosOS.first;
                            item.distribuicao[0].quantidade = item.quantidade;
                          }
                          _recalcularComBaseNaPrioridade();
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          text: item.labelQtdUnidade,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _qtdUnidadeCtrl,
                        decoration: _deco('0,000', hasError: item.erroQtdUnidade),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_NumeroBrFormatter(casasDecimais: 6)],
                        onChanged: (v) {
                          item.qtdUnidade = parseNumeroBr(v);
                          item.erroQtdUnidade = false;

                          final totalJaPreenchido =
                              (parseNumeroBr(_precoTotalCtrl.text) ?? 0) > 0;
                          if (totalJaPreenchido) _campoEditado = 'total';
                          _recalcularComBaseNaPrioridade();
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor por ${unidade.isNotEmpty ? unidade : 'unid.'}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _precoCtrl,
                        decoration: _deco('0,000000', hasError: item.erroPreco).copyWith(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 4),
                            child: Center(
                              widthFactor: 1,
                              child: Text('R\$',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontSize: 14)),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_NumeroBrFormatter(casasDecimais: 6)],
                        onChanged: (v) {
                          item.precoUnitario = parseNumeroBr(v) ?? 0;
                          item.erroPreco = false;
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor total (R\$)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _precoTotalCtrl,
                        decoration: _deco('0,00').copyWith(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 4),
                            child: Center(
                              widthFactor: 1,
                              child: Text('R\$',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontSize: 14)),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_NumeroBrFormatter(casasDecimais: 2)],
                        onChanged: (_) {
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
            if (item.qtdUnidade != null && item.qtdUnidade! > 0 && item.quantidade > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 13, color: AppTheme.primary),
                      SizedBox(width: 5),
                      Text(
                        'Entrará no estoque: ${formatarQuantidade(item.quantidadeEstoque)} $unidade',
                        style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ] else ...[
            Container(
              key: item.materialId == -1 ? widget.tourKeys?.itemUnidadeCampos : null,
              child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quantidade',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _qtdCtrl,
                        decoration: _deco('0', hasError: item.erroQtd),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_NumeroBrFormatter(casasDecimais: 2)],
                        onChanged: (v) {
                          item.quantidade = parseNumeroBr(v) ?? 0;
                          item.erroQtd = false;
                          if (widget.numerosOS.length == 1 && item.distribuicao.length == 1) {
                            item.distribuicao[0].os = widget.numerosOS.first;
                            item.distribuicao[0].quantidade = item.quantidade;
                          }

                          _recalcularComBaseNaPrioridade();
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Preço por Unidade',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      SizedBox(height: 4),
                      TextFormField(
                        controller: _precoCtrl,
                        decoration: _deco('0,00', hasError: item.erroPreco).copyWith(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 4),
                            child: Center(
                              widthFactor: 1,
                              child: Text('R\$',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontSize: 14)),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_NumeroBrFormatter(casasDecimais: 6)],
                        onChanged: (v) {
                          item.precoUnitario = parseNumeroBr(v) ?? 0;
                          item.erroPreco = false;
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor total (R\$)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      SizedBox(height: 4),
                      TextFormField(
                        controller: _precoTotalCtrl,
                        decoration: _deco('0,00').copyWith(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 4),
                            child: Center(
                              widthFactor: 1,
                              child: Text('R\$',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontSize: 14)),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_NumeroBrFormatter(casasDecimais: 2)],
                        onChanged: (_) {
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: R\$ ${formatarNumeroBr(total, 2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistribuicaoSection extends StatefulWidget {
  final _ItemRascunho item;
  final List<String> numerosOS;
  final VoidCallback onChanged;

  const _DistribuicaoSection({
    required this.item,
    required this.numerosOS,
    required this.onChanged,
  });

  @override
  State<_DistribuicaoSection> createState() => _DistribuicaoSectionState();
}

class _DistribuicaoSectionState extends State<_DistribuicaoSection> {
  late List<TextEditingController> _qtdCtrls;

  @override
  void initState() {
    super.initState();
    _autoFillSeUmaOS();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _DistribuicaoSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    final preencheuAuto = _autoFillSeUmaOS();
    if (preencheuAuto) {

      if (_qtdCtrls.isNotEmpty) {
        final qtd = widget.item.distribuicao[0].quantidade;
        final novoTexto = qtd == 0 ? '' : formatarNumeroBr(qtd, qtd % 1 == 0 ? 0 : 2);
        if (_qtdCtrls[0].text != novoTexto) {
          _qtdCtrls[0].text = novoTexto;
        }
      }
    }

    if (widget.numerosOS.length == 1 &&
        widget.item.distribuicao.length == 1 &&
        _qtdCtrls.isNotEmpty) {
      final qtd = widget.item.distribuicao[0].quantidade;
      final novoTexto = qtd == 0 ? '' : formatarNumeroBr(qtd, qtd % 1 == 0 ? 0 : 2);
      if (_qtdCtrls[0].text != novoTexto) {
        _qtdCtrls[0].text = novoTexto;
      }
    }
  }

  bool _autoFillSeUmaOS() {
    if (widget.numerosOS.length != 1) return false;
    final umaOS = widget.numerosOS.first;
    final dist = widget.item.distribuicao;

    if (dist.isEmpty) {
      dist.add(_DistribuicaoLinha(os: umaOS, quantidade: widget.item.quantidade));
      return true;
    }
    bool changed = false;

    while (dist.length > 1) {
      dist.removeLast();
      changed = true;
    }

    if (dist[0].os != umaOS) {
      dist[0].os = umaOS;
      changed = true;
    }
    if ((dist[0].quantidade - widget.item.quantidade).abs() > 0.0001) {
      dist[0].quantidade = widget.item.quantidade;
      changed = true;
    }
    return changed;
  }

  void _syncControllers() {
    _qtdCtrls = widget.item.distribuicao.map((l) {
      final v = l.quantidade == 0 ? '' : formatarNumeroBr(l.quantidade, l.quantidade % 1 == 0 ? 0 : 2);
      return TextEditingController(text: v);
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _qtdCtrls) { c.dispose(); }
    super.dispose();
  }

  void _adicionarLinha() {
    final ctrl = TextEditingController();
    setState(() {
      widget.item.distribuicao.add(_DistribuicaoLinha());
      _qtdCtrls.add(ctrl);
    });
    widget.onChanged();
  }

  void _removerLinha(int idx) {
    _qtdCtrls[idx].dispose();
    setState(() {
      widget.item.distribuicao.removeAt(idx);
      _qtdCtrls.removeAt(idx);
    });
    widget.onChanged();
  }

  void _limpar() {
    for (final c in _qtdCtrls) { c.dispose(); }
    setState(() {
      widget.item.distribuicao
        ..clear()
        ..add(_DistribuicaoLinha());
      _qtdCtrls = [TextEditingController()];
    });
    widget.onChanged();
  }

  double get _totalDistribuido =>
      widget.item.distribuicao.fold(0.0, (s, l) => s + l.quantidade);

  @override
  Widget build(BuildContext context) {
    final total = widget.item.quantidade;
    final distribuido = _totalDistribuido;
    final excesso = distribuido - total;
    final ok = (distribuido - total).abs() < 0.0001;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Distribuição por OS',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: ok
                        ? AppTheme.success.withValues(alpha: 0.12)
                        : AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${distribuido % 1 == 0 ? distribuido.toInt() : distribuido}/${total % 1 == 0 ? total.toInt() : total} distribuído',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ok ? AppTheme.success : AppTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (excesso > 0.0001)
            Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Excede em ${formatarQuantidade(excesso)}',
                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (excesso > 0.0001) SizedBox(height: 6),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(child: Text('OS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                SizedBox(width: 8),
                SizedBox(width: 80, child: Text('Quantidade', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center)),
                SizedBox(width: 28),
              ],
            ),
          ),
          SizedBox(height: 4),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: widget.item.distribuicao.asMap().entries.map((e) {
                final idx = e.key;
                final linha = e.value;
                final InputDecoration decoSmall = InputDecoration(
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppTheme.primary)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: widget.numerosOS.isEmpty

                            ? Container(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                ),
                                child: Text(
                                  'Preencha os números de OS acima',
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic),
                                ),
                              )

                            : DropdownButtonFormField<String>(
                                key: ValueKey('os_dd_${idx}_${widget.numerosOS.join(",")}_${widget.item.distribuicao.length}_${linha.os}'),
                                initialValue: linha.os.isNotEmpty && widget.numerosOS.contains(linha.os) ? linha.os : null,
                                decoration: InputDecoration(
                                  hintText: 'Selecione a OS',
                                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: widget.item.erroOS ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: widget.item.erroOS ? AppTheme.error : Theme.of(context).colorScheme.outlineVariant, width: widget.item.erroOS ? 1.5 : 1)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: widget.item.erroOS ? AppTheme.error : AppTheme.primary)),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  isDense: true,
                                ),
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                items: widget.numerosOS
                                    .map((os) => DropdownMenuItem(value: os, child: Text(os)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      linha.os = v;
                                      widget.item.erroOS = false;
                                    });
                                    widget.onChanged();
                                  }
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _qtdCtrls[idx],
                          decoration: decoSmall.copyWith(hintText: '0'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_NumeroBrFormatter(casasDecimais: 2)],
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            linha.quantidade = parseNumeroBr(v) ?? 0;
                            setState(() {});
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 24,
                        child: widget.item.distribuicao.length > 1
                            ? Tooltip(
                                message: 'Remover esta linha de distribuição',
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => _removerLinha(idx),
                                    child: const Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.error),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                Tooltip(
                  message: 'Adicionar nova linha de distribuição por OS',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: TextButton.icon(
                      onPressed: _adicionarLinha,
                      icon: const Icon(Icons.add, size: 14, color: AppTheme.primary),
                      label: Text('Adicionar OS', style: TextStyle(fontSize: 12, color: AppTheme.primary)),
                      style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Tooltip(
                  message: 'Limpar toda a distribuição de OS deste item',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: TextButton.icon(
                      onPressed: _limpar,
                      icon: Icon(Icons.close, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      label: Text('Limpar distribuição', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap).copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FornecedorPicker extends StatefulWidget {
  final FornecedorProvider provider;

  const _FornecedorPicker({required this.provider});

  @override
  State<_FornecedorPicker> createState() => _FornecedorPickerState();
}

class _FornecedorPickerState extends State<_FornecedorPicker> {
  final _searchCtrl = TextEditingController();
  List<FornecedorModel> _resultados = [];
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    setState(() => _buscando = true);
    final r = await widget.provider
        .buscarFornecedores(busca: q.isEmpty ? null : q);
    if (mounted) {
      setState(() {
        _resultados = r;
        _buscando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text('Selecionar Fornecedor',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          ),
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
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar fornecedor...',
                prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.outline),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _buscar(v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buscando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : ListView.builder(
                      itemCount: _resultados.length,
                      itemBuilder: (_, i) {
                        final f = _resultados[i];
                        return ListTile(
                          title: Text(f.nomeFantasia,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface)),
                          subtitle: f.tipoFornecedor != null
                              ? Text(f.tipoFornecedor!,
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant))
                              : null,
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () => Navigator.pop(context, f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        Tooltip(
          message: 'Fechar sem selecionar fornecedor',
          child: TextButton(
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }
}

class _AdicionarItemDialog extends StatefulWidget {
  final List<FornecedorMaterialVinculoModel> materiais;
  final int fornecedorId;
  final void Function(List<FornecedorMaterialVinculoModel>) onConfirmar;

  final Set<int> materiaisJaAdicionados;
  final NovaOcTourKeys? tourKeys;

  const _AdicionarItemDialog({
    super.key,
    required this.materiais,
    required this.fornecedorId,
    required this.onConfirmar,
    this.materiaisJaAdicionados = const {},
    this.tourKeys,
  });

  @override
  State<_AdicionarItemDialog> createState() => _AdicionarItemDialogState();
}

class _AdicionarItemDialogState extends State<_AdicionarItemDialog> {
  final _identificadorCtrl = TextEditingController();
  final _nomeCtrl          = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _comprimentoCtrl   = TextEditingController();
  final _larguraCtrl       = TextEditingController();
  final _espessuraCtrl     = TextEditingController();

  final Map<int, int> _quantidades = {};

  late bool _verTodoEstoque;
  bool _buscando = false;
  List<Map<String, dynamic>> _todosOsMateriais = [];

  Set<int> get _idsVinculados =>
      widget.materiais.map((m) => m.materialId).toSet();

  @override
  void initState() {
    super.initState();

    _verTodoEstoque = widget.materiais.isEmpty;
    if (_verTodoEstoque) _carregarTodoEstoque();
  }

  @override
  void dispose() {
    _identificadorCtrl.dispose();
    _nomeCtrl.dispose();
    _medidaCtrl.dispose();
    _comprimentoCtrl.dispose();
    _larguraCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  List<FornecedorMaterialVinculoModel> get _filtradosVinculados {
    var lista = widget.materiais;
    final ident       = _identificadorCtrl.text.trim().toLowerCase();
    final nome        = _nomeCtrl.text.trim().toLowerCase();
    final medida      = _medidaCtrl.text.trim().toLowerCase();
    final comprimento = _comprimentoCtrl.text.trim().toLowerCase();
    final largura     = _larguraCtrl.text.trim().toLowerCase();
    final espessura   = _espessuraCtrl.text.trim().toLowerCase();

    if (ident.isNotEmpty)     lista = lista.where((m) => (m.materialIdentificador ?? '').toLowerCase().contains(ident)).toList();
    if (nome.isNotEmpty) {
      final tokens = nome.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      lista = lista.where((m) {
        final desc = m.descricaoCompleta.toLowerCase();
        return tokens.every((t) => desc.contains(t));
      }).toList();
    }
    if (medida.isNotEmpty)      lista = lista.where((m) => (m.materialMedida ?? '').toLowerCase().contains(medida)).toList();
    if (comprimento.isNotEmpty) lista = lista.where((m) => m.descricaoCompleta.toLowerCase().contains(comprimento)).toList();
    if (largura.isNotEmpty)     lista = lista.where((m) => m.descricaoCompleta.toLowerCase().contains(largura)).toList();
    if (espessura.isNotEmpty)   lista = lista.where((m) => m.descricaoCompleta.toLowerCase().contains(espessura)).toList();
    return lista;
  }

  List<Map<String, dynamic>> get _filtradosTodos {
    var lista = _todosOsMateriais;
    final ident       = _identificadorCtrl.text.trim().toLowerCase();
    final nome        = _nomeCtrl.text.trim().toLowerCase();
    final medida      = _medidaCtrl.text.trim().toLowerCase();
    final comprimento = _comprimentoCtrl.text.trim().toLowerCase();
    final largura     = _larguraCtrl.text.trim().toLowerCase();
    final espessura   = _espessuraCtrl.text.trim().toLowerCase();

    if (ident.isNotEmpty)     lista = lista.where((m) => (m['identificador'] ?? '').toString().toLowerCase().contains(ident)).toList();
    if (medida.isNotEmpty)    lista = lista.where((m) => (m['medida'] ?? '').toString().toLowerCase().contains(medida)).toList();
    if (espessura.isNotEmpty) lista = lista.where((m) => (m['espessura'] ?? '').toString().toLowerCase().contains(espessura)).toList();
    if (comprimento.isNotEmpty) lista = lista.where((m) => (m['comprimento'] ?? '').toString().toLowerCase().contains(comprimento)).toList();
    if (largura.isNotEmpty)     lista = lista.where((m) => (m['largura'] ?? '').toString().toLowerCase().contains(largura)).toList();
    if (nome.isNotEmpty) {
      final tokens = nome.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      lista = lista.where((m) {
        final n = (m['nome'] ?? '').toString().toLowerCase();
        return tokens.every((t) => n.contains(t));
      }).toList();
    }
    return lista;
  }

  Future<void> _carregarTodoEstoque() async {
    setState(() { _buscando = true; });
    try {
      final repo = FornecedorRepository();
      final todos = await repo.buscarMateriais();

      if (mounted) setState(() { _todosOsMateriais = todos; });
    } catch (_) {

    } finally {
      if (mounted) setState(() { _buscando = false; });
    }
  }

  int get _totalItens => _quantidades.length;

  bool get _temFiltro =>
      _identificadorCtrl.text.isNotEmpty ||
      _nomeCtrl.text.isNotEmpty ||
      _medidaCtrl.text.isNotEmpty ||
      _comprimentoCtrl.text.isNotEmpty ||
      _larguraCtrl.text.isNotEmpty ||
      _espessuraCtrl.text.isNotEmpty;

  void _limparFiltros() => setState(() {
        _identificadorCtrl.clear();
        _nomeCtrl.clear();
        _medidaCtrl.clear();
        _comprimentoCtrl.clear();
        _larguraCtrl.clear();
        _espessuraCtrl.clear();
      });

  void selecionarTodosTour() {
    setState(() {
      for (final m in widget.materiais) {
        _quantidades[m.materialId] = 1;
      }
    });
  }

  void _confirmar() {
    final escolhidos = <FornecedorMaterialVinculoModel>[];

    if (!_verTodoEstoque) {

      for (final m in widget.materiais) {
        if (_quantidades.containsKey(m.materialId)) {
          escolhidos.add(m);
        }
      }
    } else {

      final vinculadosPorId = { for (final m in widget.materiais) m.materialId: m };
      for (final m in _todosOsMateriais) {
        final mid = m['id'] as int;
        if (!_quantidades.containsKey(mid)) continue;
        final vinculo = vinculadosPorId[mid] ?? FornecedorMaterialVinculoModel(
          id:                   0,
          fornecedorId:         widget.fornecedorId,
          materialId:           mid,
          materialNome:         m['nome'] as String?,
          materialIdentificador: m['identificador'] as String?,
          materialMedida:       m['medida'] as String?,
          materialEspessura:    m['espessura'] as String?,
          preco:                0,
          precoMetroQuadrado:   0,
          ativo:                true,
          materialUnidade:      m['unidade'] as String?,
          materialLargura:      m['largura'] != null
              ? double.tryParse(m['largura'].toString())
              : null,
          materialComprimento:  m['comprimento'] != null
              ? double.tryParse(m['comprimento'].toString())
              : null,
        );
        escolhidos.add(vinculo);
      }
    }

    widget.onConfirmar(escolhidos);
    Navigator.pop(context);
  }

  InputDecoration _deco(String hint, {IconData? icon, String? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
        prefixIcon: icon != null ? Icon(icon, size: 15, color: Theme.of(context).colorScheme.outline) : null,
        suffixText: suffix,
        suffixStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
      );

  Widget _buildItem({
    required int materialId,
    required String descricao,
    required String preco,
    required bool eNovo,
  }) {
    final jaNaOC      = widget.materiaisJaAdicionados.contains(materialId);
    final selecionado = _quantidades.containsKey(materialId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        descricao,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: selecionado
                              ? AppTheme.primary
                              : jaNaOC
                                  ? Theme.of(context).colorScheme.outline
                                  : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (jaNaOC) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Já adicionado',
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ] else if (eNovo) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Novo vínculo',
                          style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  preco,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (jaNaOC)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, size: 22, color: Theme.of(context).colorScheme.outline),
            )
          else
            Tooltip(
              message: selecionado ? 'Remover' : 'Adicionar',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: materialId == -1 ? widget.tourKeys?.botaoAdicionarMaterial : null,
                  onTap: () {
                    setState(() {
                      if (selecionado) {
                        _quantidades.remove(materialId);
                      } else {
                        _quantidades[materialId] = 1;
                      }
                    });
                  },
                  child: Icon(
                    selecionado
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                    size: 22,
                    color: selecionado ? AppTheme.error : AppTheme.primary,
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtradosVinc = _filtradosVinculados;
    final filtradosTodos = _verTodoEstoque ? _filtradosTodos : <Map<String, dynamic>>[];
    final vinculadosIds = _idsVinculados;

    return AlertDialog(
      title: Row(
        children: [
          Text('Adicionar Itens',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_totalItens > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_totalItens ${_totalItens == 1 ? 'selecionado' : 'selecionados'}',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Fechar',
            style: IconButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 800,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              key: widget.tourKeys?.verTodoEstoque,
              children: [
                Switch(
                  value: _verTodoEstoque,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (v) {
                    setState(() { _verTodoEstoque = v; });
                    if (v && _todosOsMateriais.isEmpty) _carregarTodoEstoque();
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  'Ver todo o estoque',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                ),
                if (_verTodoEstoque && widget.materiais.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${widget.materiais.length} já vinculados)',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            Column(
              key: widget.tourKeys?.buscaMaterial,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nomeCtrl,
                        autofocus: widget.tourKeys == null,
                        decoration: _deco('Nome do material', icon: Icons.inventory_2_outlined),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _identificadorCtrl,
                        decoration: _deco('Identificador', icon: Icons.qr_code),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _medidaCtrl,
                        decoration: _deco('Medida', icon: Icons.straighten),
                        inputFormatters: [_MedidaEspessuraFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _comprimentoCtrl,
                        decoration: _deco('Comprimento', icon: Icons.height, suffix: 'm'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_EspessuraFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _larguraCtrl,
                        decoration: _deco('Largura', icon: Icons.width_normal, suffix: 'm'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_EspessuraFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _espessuraCtrl,
                        decoration: _deco('Espessura', icon: Icons.layers, suffix: 'mm'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_EspessuraFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(width: 4),
                    IconButton(
                      onPressed: _temFiltro ? _limparFiltros : null,
                      icon: Icon(
                        Icons.filter_alt_off,
                        size: 18,
                        color: _temFiltro ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.outline,
                      ),
                      tooltip: 'Limpar filtros',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      style: IconButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(
                          _temFiltro ? SystemMouseCursors.click : SystemMouseCursors.basic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),

            Text(
              _verTodoEstoque
                  ? '${filtradosTodos.length} ${filtradosTodos.length == 1 ? 'material encontrado' : 'materiais encontrados'}'
                  : '${filtradosVinc.length} ${filtradosVinc.length == 1 ? 'material encontrado' : 'materiais encontrados'}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

            Expanded(
              child: _verTodoEstoque
                  ? _buscando
                      ? const Center(child: CircularProgressIndicator())
                      : filtradosTodos.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum material encontrado.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtradosTodos.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                              itemBuilder: (_, i) {
                                final m = filtradosTodos[i];
                                final mid = m['id'] as int;
                                final eNovo = !vinculadosIds.contains(mid);
                                final medidaOuDimensao = (m['medida'] ?? '').toString().isNotEmpty
                                    ? m['medida'].toString()
                                    : formatarMedidaOuDimensoes(
                                        medida:      null,
                                        largura:     m['largura'] != null ? double.tryParse(m['largura'].toString()) : null,
                                        comprimento: m['comprimento'] != null ? double.tryParse(m['comprimento'].toString()) : null,
                                      );
                                final partes = <String>[
                                  if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty) medidaOuDimensao,
                                  if ((m['espessura'] ?? '').toString().isNotEmpty) espessuraExibicao(m['espessura'].toString()),
                                ];
                                final nomeComIdentificador = (m['identificador'] ?? '').toString().isNotEmpty
                                    ? '${m['identificador']} · ${m['nome'] ?? ''}'
                                    : (m['nome'] ?? '').toString();
                                final desc = partes.isEmpty
                                    ? nomeComIdentificador
                                    : '$nomeComIdentificador · ${partes.join(' · ')}';

                                final vinculo = widget.materiais.cast<FornecedorMaterialVinculoModel?>()
                                    .firstWhere((v) => v?.materialId == mid, orElse: () => null);
                                final precoStr = vinculo != null
                                    ? (vinculo.preco > 0
                                        ? 'R\$ ${formatarNumeroBr(vinculo.preco, 2)}${vinculo.precoMetroQuadrado > 0 ? '  •  m²: R\$ ${formatarNumeroBr(vinculo.precoMetroQuadrado, 2)}' : ''}'
                                        : vinculo.precoMetroQuadrado > 0
                                            ? 'm²: R\$ ${formatarNumeroBr(vinculo.precoMetroQuadrado, 2)}'
                                            : 'Sem preço cadastrado')
                                    : 'Sem preço — será vinculado ao salvar';

                                return _buildItem(
                                  materialId: mid,
                                  descricao: desc,
                                  preco: precoStr,
                                  eNovo: eNovo,
                                );
                              },
                            )

                  : filtradosVinc.isEmpty
                      ? Center(
                          child: Text(
                            widget.materiais.isEmpty
                                ? 'Este fornecedor não possui materiais vinculados.\nUse "Ver todo o estoque" para adicionar.'
                                : 'Nenhum material encontrado com esses filtros.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtradosVinc.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                          itemBuilder: (_, i) {
                            final m = filtradosVinc[i];
                            final precoStr = m.preco > 0
                                ? 'R\$ ${formatarNumeroBr(m.preco, 2)}${m.precoMetroQuadrado > 0 ? '  •  m²: R\$ ${formatarNumeroBr(m.precoMetroQuadrado, 2)}' : ''}'
                                : m.precoMetroQuadrado > 0
                                    ? 'm²: R\$ ${formatarNumeroBr(m.precoMetroQuadrado, 2)}'
                                    : 'Sem preço cadastrado';
                            return _buildItem(
                              materialId: m.materialId,
                              descricao: m.descricaoCompleta,
                              preco: precoStr,
                              eNovo: false,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        Tooltip(
          message: 'Fechar sem adicionar itens',
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom()
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: Text('Cancelar',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
        Tooltip(
          message: _totalItens == 0 ? 'Selecione ao menos um item' : 'Adicionar os itens selecionados à ordem de compra',
          child: FilledButton(
            key: widget.tourKeys?.botaoConfirmarAdicionar,
            onPressed: _totalItens == 0 ? null : _confirmar,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
                .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
            child: Text(
              _totalItens == 0 ? 'Adicionar' : 'Adicionar ($_totalItens)',
            ),
          ),
        ),
      ],
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
  static const _accent = Color(0xFFF59E0B);

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
                  ? _accent.withValues(alpha: 0.15)
                  : _accent.withValues(alpha: 0.08),
              border: Border.all(
                color: _accent.withValues(alpha: _hovered ? 0.9 : 0.5),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: _accent,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _accent,
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