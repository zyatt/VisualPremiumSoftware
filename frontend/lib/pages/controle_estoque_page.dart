import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/estoque_model.dart';
import '../models/material_model.dart';
import '../models/estoque_producao_model.dart';
import '../providers/estoque_provider.dart';
import '../providers/estoque_producao_provider.dart';
import '../providers/material_provider.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';
import 'historico_movimentacoes_page.dart';

// ── Formatação de preço: até 6 casas decimais, sem zeros à direita ────────────

String _fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

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

/// Formata um valor de dimensão/quantidade sem arredondar ou cortar a
/// precisão real do valor. Antes usava `toStringAsFixed(2)`, que exibia
/// apenas 2 casas decimais mesmo quando o valor real tinha mais precisão
/// (ex.: 3.696 aparecia como "3.70" na tela, escondendo o valor exato
/// armazenado). Agora: inteiro sem casas quando não há parte decimal, ou
/// a representação decimal completa e mínima do double (via toString())
/// quando há.
/// Ex.: 1.0 → "1"; 0.5 → "0.5"; 3.696 → "3.696".
String _fmtDim(double v) =>
    v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Formata uma quantidade de material sem arredondar/cortar a precisão
/// real do valor (mesma lógica de _fmtDim, exposta com nome mais claro
/// para os pontos que exibem quantidade em estoque, não dimensão).
/// Ex.: 3.696 → "3.696"; 4.0 → "4".
String formatarQuantidade(double v) => _fmtDim(v);

/// Retorna a exibição de medida de um material: usa o campo [medida] quando
/// preenchido; caso contrário, monta a partir de [largura]/[comprimento]
/// cadastrados diretamente no material.
/// Exemplos: comprimento=50 e largura=1.22 → "50x1.22m"; só comprimento=50 → "50m";
/// só largura=1.22 → "1.22m". Retorna null se nada estiver disponível.
String? formatarMedidaOuDimensoes({
  required String? medida,
  required double? largura,
  required double? comprimento,
}) {
  if (medida != null && medida.trim().isNotEmpty) return medida.trim();

  final temLargura     = largura != null && largura > 0;
  final temComprimento = comprimento != null && comprimento > 0;

  if (temComprimento && temLargura) {
    return '${_fmtDim(comprimento)}x${_fmtDim(largura)}m';
  }
  if (temComprimento) return '${_fmtDim(comprimento)}m';
  if (temLargura)     return '${_fmtDim(largura)}m';
  return null;
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

// ── Formatter: maiúsculas sem acentos ─────────────────────────────────────────

/// TextEditingController que expõe [notify] publicamente. `notifyListeners()`
/// é `@protected` em `ChangeNotifier`, então não pode ser chamado de fora da
/// própria classe/subclasse — usamos essa subclasse só para forçar o
/// RawAutocomplete a reavaliar as opções ao focar o campo vazio.
class _NotifiableTextEditingController extends TextEditingController {
  _NotifiableTextEditingController();
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
    final texto = _removerAcentos(newValue.text).toUpperCase();
    final sel = newValue.selection.copyWith(
      baseOffset:   newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

// ── Diálogo: Renomear OS ───────────────────────────────────────────────────
// Controller próprio gerenciado pelo ciclo de vida do State, evitando o uso
// do controller após dispose quando o diálogo é fechado via ESC (a
// animação de saída ainda reconstrói o TextField por um frame a mais do
// que o Future de showDialog leva para completar).
class _RenomearOSDialog extends StatefulWidget {
  final String nomeAtual;
  const _RenomearOSDialog({required this.nomeAtual});

  @override
  State<_RenomearOSDialog> createState() => _RenomearOSDialogState();
}

class _RenomearOSDialogState extends State<_RenomearOSDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nomeAtual);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final nome = _ctrl.text.trim();
    if (nome.isEmpty) return;
    if (nome == widget.nomeAtual) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(nome);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.edit_outlined,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Renomear OS'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Novo número / nome da OS:',
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_UpperCaseFormatter()],
            decoration: const InputDecoration(
              hintText: 'Ex: 1234 ou MANUTENCAO',
              isDense: true,
            ),
            onSubmitted: (v) {
              final nome = v.trim();
              if (nome.isNotEmpty && nome != widget.nomeAtual) {
                Navigator.of(context).pop(nome);
              }
            },
          ),
        ],
      ),
      actions: [
        Tooltip(
          message: 'Cancelar sem alterar o nome',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom().copyWith(
                mouseCursor:
                    WidgetStateProperty.all(SystemMouseCursors.click)),
            child: const Text('Cancelar'),
          ),
        ),
        Tooltip(
          message: 'Salvar o novo nome da OS',
          child: FilledButton.icon(
            onPressed: _confirmar,
            style: FilledButton.styleFrom().copyWith(
                mouseCursor:
                    WidgetStateProperty.all(SystemMouseCursors.click)),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Renomear'),
          ),
        ),
      ],
    );
  }
}

// ── Formatter: medida/espessura (vírgula -> ponto, minúsculas, 1 ponto por número) ─────
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

/// Formata um valor de espessura garantindo o sufixo "mm" sem duplicar.
/// Dados antigos podem já ter sido salvos com "mm"/"MM" digitado manualmente
/// (ex.: "2MM", "2 mm"); removemos esse sufixo antes de reanexar o nosso.
String? formatarEspessuraComSufixo(String? valor) {
  final v = valor?.trim();
  if (v == null || v.isEmpty) return null;
  final numero = v.replaceAll(RegExp(r'\s*mm\s*$', caseSensitive: false), '').trim();
  if (numero.isEmpty) return null;
  return '${numero}mm';
}

/// Formatter para o campo Espessura: aceita apenas dígitos, ponto e vírgula
/// (vírgula é convertida em ponto), bloqueando letras e qualquer outro
/// caractere.
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
      baseOffset: newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

// ── Formatter: números decimais (aceita vírgula ou ponto) ─────────────────────

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
      baseOffset:   newValue.selection.baseOffset.clamp(0, texto.length),
      extentOffset: newValue.selection.extentOffset.clamp(0, texto.length),
    );
    return newValue.copyWith(text: texto, selection: sel);
  }
}

// ── Ordenação da listagem de OS ────────────────────────────────────────────────

enum _OrdenacaoOS { recente, criacao, numero }

extension on _OrdenacaoOS {
  String get label => switch (this) {
        _OrdenacaoOS.recente => 'Última alteração',
        _OrdenacaoOS.criacao => 'Data de criação',
        _OrdenacaoOS.numero  => 'Número da OS',
      };

  IconData get icon => switch (this) {
        _OrdenacaoOS.recente => Icons.update,
        _OrdenacaoOS.criacao => Icons.event,
        _OrdenacaoOS.numero  => Icons.tag,
      };
}

// ── Cores do status da OS ──────────────────────────────────────────────────────

const _corEmAndamento = Color(0xFF2196F3); // azul
const _corFechada     = Color(0xFF4CAF50); // verde

Color _corStatus(String status) =>
    status == 'FECHADA' ? _corFechada : _corEmAndamento;

String _labelStatus(String status) =>
    status == 'FECHADA' ? 'Fechada' : 'Em andamento';

Widget _badgeContagem(int contagem) {
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

// ═════════════════════════════════════════════════════════════════════════════
// Página principal
// ═════════════════════════════════════════════════════════════════════════════

class ControleEstoquePage extends StatefulWidget {
  const ControleEstoquePage({super.key});

  @override
  State<ControleEstoquePage> createState() => _ControleEstoquePageState();
}

class _ControleEstoquePageState extends State<ControleEstoquePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _buscaCtrl        = TextEditingController();
  final TextEditingController _buscaNomeCtrl    = TextEditingController();
  final TextEditingController _identificadorCtrl = TextEditingController();
  final TextEditingController _medidaCtrl        = TextEditingController();
  final TextEditingController _comprimentoCtrl   = TextEditingController();
  final TextEditingController _larguraCtrl       = TextEditingController();
  final TextEditingController _espessuraCtrl     = TextEditingController();
  late TabController _tabController;
  Timer? _timerFechamentoAutomatico;
  Timer? _debounceTimer;

  // ── Ordenação e filtro de período ───────────────────────────────────────
  _OrdenacaoOS _ordenacao = _OrdenacaoOS.recente;
  bool _decrescente = true;
  DateTime? _dataInicio;
  DateTime? _dataFim;

  Duration get _duracaoAteMeiaNoite {
    final agora = DateTime.now();
    final meiaNoite = DateTime(agora.year, agora.month, agora.day + 1);
    return meiaNoite.difference(agora);
  }

  bool _osEhTextual(String numeroOS) {
    final semSufixo = numeroOS.replaceAll(RegExp(r'#(OC|S|E)\d*$'), '').trim();
    return int.tryParse(semSufixo) == null;
  }

  Future<void> _fecharOSTextuaisAtrasadas() async {
    if (!mounted) return;
    final provider = context.read<EstoqueProvider>();

    final hoje = DateTime.now();
    final inicioDia = DateTime(hoje.year, hoje.month, hoje.day);

    final atrasadas = provider.relacoesOS.where((r) {
      if (r.status != 'EM_ANDAMENTO') return false;
      if (!_osEhTextual(r.numeroOS)) return false;
      final criacao = r.criadoEm;
      if (criacao == null) return false;
      return criacao.toLocal().isBefore(inicioDia);
    }).toList();

    for (final os in atrasadas) {
      await provider.fecharOSSilencioso(os.id);
    }

    if (mounted && atrasadas.isNotEmpty) {
      await provider.recarregarRelacoesOSSilencioso();
    }
  }

  Future<void> _fecharOSTextuaisAutomaticamente() async {
    if (!mounted) return;
    final provider = context.read<EstoqueProvider>();

    // Busca o estado mais recente em silêncio (sem acionar o spinner de
    // tela cheia) antes de decidir quais OS fechar.
    await provider.recarregarRelacoesOSSilencioso();
    if (!mounted) return;

    final osTextuaisEmAndamento = provider.relacoesOS
        .where((r) => r.status == 'EM_ANDAMENTO' && _osEhTextual(r.numeroOS))
        .toList();

    for (final os in osTextuaisEmAndamento) {
      await provider.fecharOSSilencioso(os.id);
    }

    if (mounted && osTextuaisEmAndamento.isNotEmpty) {
      await provider.recarregarRelacoesOSSilencioso();
    }

    if (mounted) _agendarFechamentoAutomatico();
  }

  void _agendarFechamentoAutomatico() {
    _timerFechamentoAutomatico?.cancel();
    _timerFechamentoAutomatico = Timer(
      _duracaoAteMeiaNoite,
      _fecharOSTextuaisAutomaticamente,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<EstoqueProvider>().carregarRelacoesOS();
      if (!mounted) return;
      await context.read<EstoqueProducaoProvider>().carregarContadorPendentes();
      if (!mounted) return;
      await _fecharOSTextuaisAtrasadas();
      _agendarFechamentoAutomatico();
    });
  }

  @override
  void dispose() {
    _timerFechamentoAutomatico?.cancel();
    _debounceTimer?.cancel();
    _tabController.dispose();
    _buscaCtrl.dispose();
    _buscaNomeCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _comprimentoCtrl.dispose();
    _larguraCtrl.dispose();
    _espessuraCtrl.dispose();
    super.dispose();
  }

  void _buscar(String v) {
    context
        .read<EstoqueProvider>()
        .carregarRelacoesOS(busca: v.trim().isEmpty ? null : v.trim());
  }

  void _abrirMovimentacaoGlobal(String tipo) {
    showDialog(
      context: context,
      builder: (_) => _MovimentacaoGlobalDialog(tipo: tipo),
    );
  }

  void _abrirTransferenciaProducao() {
    showDialog(
      context: context,
      builder: (_) => const _TransferenciaProducaoDialog(),
    );
  }

  Future<void> _abrirCadastroMaterial() async {
    final salvou = await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CadastroMaterialDialog(),
    );
    if (!mounted) return;
    if (salvou == true) {
      context.read<MaterialProvider>().carregarCategorias();
    }
  }

  bool get _temFiltroData => _dataInicio != null || _dataFim != null;

  /// Filtra pela data de criação da OS, igual ao filtro de período usado
  /// na página de Relatórios.
  List<RelacaoOSModel> _filtrarPorData(List<RelacaoOSModel> lista) {
    if (!_temFiltroData) return lista;
    return lista.where((r) {
      final criacao = r.criadoEm;
      if (criacao == null) return false;
      final dia = DateTime(criacao.year, criacao.month, criacao.day);
      if (_dataInicio != null) {
        final ini = DateTime(_dataInicio!.year, _dataInicio!.month, _dataInicio!.day);
        if (dia.isBefore(ini)) return false;
      }
      if (_dataFim != null) {
        final fim = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day);
        if (dia.isAfter(fim)) return false;
      }
      return true;
    }).toList();
  }

  /// Ordena a lista conforme a opção selecionada. "Última alteração" usa
  /// atualizadoEm (com fallback para criadoEm), para que uma OS criada há
  /// dias mas com uma saída registrada agora apareça no topo — evitando
  /// esquecer qual foi a movimentação mais recente.
  List<RelacaoOSModel> _ordenarRelacoes(List<RelacaoOSModel> lista) {
    final ordenada = [...lista];
    int cmp(RelacaoOSModel a, RelacaoOSModel b) {
      switch (_ordenacao) {
        case _OrdenacaoOS.recente:
          final da = a.atualizadoEm ?? a.criadoEm ?? DateTime(1970);
          final db = b.atualizadoEm ?? b.criadoEm ?? DateTime(1970);
          return da.compareTo(db);
        case _OrdenacaoOS.criacao:
          final da = a.criadoEm ?? DateTime(1970);
          final db = b.criadoEm ?? DateTime(1970);
          return da.compareTo(db);
        case _OrdenacaoOS.numero:
          final na = int.tryParse(a.numeroOS.trim());
          final nb = int.tryParse(b.numeroOS.trim());
          if (na != null && nb != null) return na.compareTo(nb);
          if (na != null) return -1;
          if (nb != null) return 1;
          return a.numeroOS.toLowerCase().compareTo(b.numeroOS.toLowerCase());
      }
    }
    ordenada.sort(_decrescente ? (a, b) => cmp(b, a) : cmp);
    return ordenada;
  }

  List<RelacaoOSModel> _filtrarPorMaterial(List<RelacaoOSModel> lista) {
    final nome          = _buscaNomeCtrl.text.trim().toLowerCase();
    final identificador = _identificadorCtrl.text.trim().toUpperCase();
    final medida        = _medidaCtrl.text.trim().toUpperCase();
    final comprimento   = _comprimentoCtrl.text.trim().toUpperCase();
    final largura       = _larguraCtrl.text.trim().toUpperCase();
    final espessura     = _espessuraCtrl.text.trim().toUpperCase();

    final temFiltro = nome.isNotEmpty ||
        identificador.isNotEmpty ||
        medida.isNotEmpty ||
        comprimento.isNotEmpty ||
        largura.isNotEmpty ||
        espessura.isNotEmpty;

    if (!temFiltro) return lista;

    return lista.where((r) {
      return r.movimentacoes.any((m) {
        if (nome.isNotEmpty &&
            !m.materialNome.toLowerCase().contains(nome)) {
          return false;
        }
        if (identificador.isNotEmpty) {
          final v = (m.materialIdentificador ?? '').toUpperCase();
          if (!v.contains(identificador)) return false;
        }
        if (medida.isNotEmpty) {
          final v = (m.materialMedida ?? '').toUpperCase();
          if (!v.contains(medida)) return false;
        }
        if (comprimento.isNotEmpty) {
          final v = (m.materialComprimento?.toString() ?? '').toUpperCase();
          if (!v.contains(comprimento)) return false;
        }
        if (largura.isNotEmpty) {
          final v = (m.materialLargura?.toString() ?? '').toUpperCase();
          if (!v.contains(largura)) return false;
        }
        if (espessura.isNotEmpty) {
          final v = (m.materialEspessura ?? '').toUpperCase();
          if (!v.contains(espessura)) return false;
        }
        return true;
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();

    final emAndamento = _ordenarRelacoes(_filtrarPorData(_filtrarPorMaterial(
      provider.relacoesOS.where((r) => r.status == 'EM_ANDAMENTO').toList(),
    )));
    final fechadas = _ordenarRelacoes(_filtrarPorData(_filtrarPorMaterial(
      provider.relacoesOS.where((r) => r.status == 'FECHADA').toList(),
    )));

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
                      'Controle de Estoque',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Movimentações por Ordem de Serviço',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Transferir material do estoque normal para o estoque de produção',
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FilledButton.icon(
                        onPressed: _abrirTransferenciaProducao,
                        icon: const Icon(Icons.factory_outlined, size: 18),
                        label: const Text('Saída p/ Produção'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.warning,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ).copyWith(
                          mouseCursor:
                              WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                      if (context.watch<EstoqueProducaoProvider>().totalPendentes > 0)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.error,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            constraints: const BoxConstraints(minWidth: 20),
                            child: Text(
                              '${context.watch<EstoqueProducaoProvider>().totalPendentes}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Cadastrar um novo material no estoque',
                  child: FilledButton.icon(
                    onPressed: _abrirCadastroMaterial,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Novo Material'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ).copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Registrar entrada ou reentrada de material no estoque',
                  child: FilledButton.icon(
                    onPressed: () => _abrirMovimentacaoGlobal('ENTRADA'),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Entrada/Reentrada'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ).copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Registrar saída de material do estoque',
                  child: FilledButton.icon(
                    onPressed: () => _abrirMovimentacaoGlobal('SAIDA'),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Saída'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ).copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Tooltip(
                  message: 'Ver histórico de movimentações',
                  child: OutlinedButton.icon(
                    onPressed: _abrirHistoricoMovimentacoes,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Histórico'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ).copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Atualizar lista de ordens de serviço',
                  child: IconButton(
                    onPressed: () => context.read<EstoqueProvider>().carregarRelacoesOS(),
                    icon: Icon(Icons.refresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ).copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaCtrl,
                    onChanged: (v) {
                      _buscar(v);
                      setState(() {});
                    },
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Buscar por número da OS',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaNomeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Nome do material',
                      prefixIcon: Icon(Icons.filter_alt_outlined,
                          color: Theme.of(context).colorScheme.outline, size: 20),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Builder(
                  builder: (context) {
                    final temFiltro = _buscaCtrl.text.isNotEmpty ||
                        _buscaNomeCtrl.text.isNotEmpty ||
                        _identificadorCtrl.text.isNotEmpty ||
                        _medidaCtrl.text.isNotEmpty ||
                        _comprimentoCtrl.text.isNotEmpty ||
                        _larguraCtrl.text.isNotEmpty ||
                        _espessuraCtrl.text.isNotEmpty ||
                        _temFiltroData ||
                        _ordenacao != _OrdenacaoOS.recente ||
                        !_decrescente;
                    return IconButton.outlined(
                      tooltip: 'Limpar filtros',
                      icon: Icon(Icons.filter_alt_off,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: temFiltro
                          ? () {
                              _buscaCtrl.clear();
                              _buscaNomeCtrl.clear();
                              _identificadorCtrl.clear();
                              _medidaCtrl.clear();
                              _comprimentoCtrl.clear();
                              _larguraCtrl.clear();
                              _espessuraCtrl.clear();
                              setState(() {
                                _dataInicio = null;
                                _dataFim    = null;
                                _ordenacao  = _OrdenacaoOS.recente;
                                _decrescente = true;
                              });
                              context.read<EstoqueProvider>().carregarRelacoesOS();
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

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _identificadorCtrl,
                    decoration: InputDecoration(
                      hintText:   'Identificador',
                      prefixIcon: Icon(Icons.qr_code,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _medidaCtrl,
                    decoration: InputDecoration(
                      hintText:   'Medida',
                      prefixIcon: Icon(Icons.straighten,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    inputFormatters: [_MedidaEspessuraFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _comprimentoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText:   'Comprimento',
                      suffixText: 'm',
                      prefixIcon: Icon(Icons.height,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _larguraCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText:   'Largura',
                      suffixText: 'm',
                      prefixIcon: Icon(Icons.width_normal,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _espessuraCtrl,
                    decoration: InputDecoration(
                      hintText:   'Espessura',
                      suffixText: 'mm',
                      prefixIcon: Icon(Icons.layers,
                          color: Theme.of(context).colorScheme.outline, size: 18),
                      isDense: true,
                    ),
                    inputFormatters: [_EspessuraFormatter()],
                    onChanged: (_) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        Duration(milliseconds: 300),
                        () => setState(() {}),
                      );
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // ── Filtro por período de criação + ordenação ────────────────────
            Row(
              children: [
                _DatePickerField(
                  label: 'Criado de',
                  value: _dataInicio,
                  firstDate: DateTime(2020),
                  lastDate: _dataFim ?? DateTime.now(),
                  onPicked: (d) => setState(() => _dataInicio = d),
                  onCleared: () => setState(() => _dataInicio = null),
                ),
                const SizedBox(width: 12),
                _DatePickerField(
                  label: 'até',
                  value: _dataFim,
                  firstDate: _dataInicio ?? DateTime(2020),
                  lastDate: DateTime.now(),
                  onPicked: (d) => setState(() => _dataFim = d),
                  onCleared: () => setState(() => _dataFim = null),
                ),
                const Spacer(),
                _OrdenacaoControl(
                  ordenacao: _ordenacao,
                  decrescente: _decrescente,
                  onOrdenacaoChanged: (o) => setState(() => _ordenacao = o),
                  onDirecaoToggled: () =>
                      setState(() => _decrescente = !_decrescente),
                ),
              ],
            ),
            SizedBox(height: 16),

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
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Em Andamento'),
                        const SizedBox(width: 6),
                        _badgeContagem(provider.carregando ? 0 : emAndamento.length),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Fechadas'),
                        const SizedBox(width: 6),
                        _badgeContagem(provider.carregando ? 0 : fechadas.length),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: provider.carregando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : provider.erro != null
                      ? SizedBox(
                          height: 300,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_off_outlined,
                                    size: 48, color: AppTheme.error),
                                SizedBox(height: 12),
                                Text(
                                  'Erro ao carregar controle de estoque',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  () {
                                    final partes = provider.erro!.split(': ');
                                    return partes.length > 1
                                        ? partes.sublist(1).join(': ')
                                        : provider.erro!;
                                  }(),
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => context
                                      .read<EstoqueProvider>()
                                      .carregarRelacoesOS(),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Tentar novamente'),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.primary)
                                    .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                                ),
                              ],
                            ),
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _OsGrid(
                              relacoes: emAndamento,
                              emptyMessage: 'Nenhuma OS em andamento',
                              onTap: _abrirDetalhe,
                            ),
                            _OsGrid(
                              relacoes: fechadas,
                              emptyMessage: 'Nenhuma OS fechada',
                              onTap: _abrirDetalhe,
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirDetalhe(RelacaoOSModel rel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _RelacaoDetalhe(relacaoOSId: rel.id, numeroOS: rel.numeroOS),
      ),
    );
  }

  /// Abre a página de histórico geral de movimentações (todas as OS, em
  /// ordem cronológica). Se o usuário tocar no número de uma OS dentro do
  /// histórico, a página retorna esse numeroOS e abrimos o detalhe dela aqui.
  Future<void> _abrirHistoricoMovimentacoes() async {
    final numeroOS = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const HistoricoMovimentacoesPage()),
    );
    if (numeroOS == null || !mounted) return;
    final rel = context.read<EstoqueProvider>().relacoesOS.firstWhere(
          (r) => r.numeroOS == numeroOS,
          orElse: () => RelacaoOSModel(id: 0, numeroOS: '', movimentacoes: const []),
        );
    if (rel.id != 0) _abrirDetalhe(rel);
  }
}

// ─── Seletor de período (mesmo padrão usado em Relatórios) ───────────────────

class _DatePickerField extends StatelessWidget {
  final String    label;
  final DateTime? value;
  final DateTime  firstDate;
  final DateTime  lastDate;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback           onCleared;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onPicked,
    required this.onCleared,
  });

  Future<void> _pick(BuildContext context) async {
    final now     = DateTime.now();
    final initial = value != null
        ? (value!.isAfter(lastDate) ? lastDate : value!)
        : (now.isBefore(lastDate) ? now : lastDate);
    final picked = await showDatePicker(
      context:     context,
      initialDate: initial,
      firstDate:   firstDate,
      lastDate:    lastDate,
      builder: (context, child) {
        final base = Theme.of(context);
        final clickCursor = WidgetStateProperty.resolveWith<MouseCursor>(
          (states) => states.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
        );
        return Theme(
          data: base.copyWith(
            textButtonTheme: TextButtonThemeData(
              style: (base.textButtonTheme.style ?? const ButtonStyle())
                  .copyWith(mouseCursor: clickCursor),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: (base.iconButtonTheme.style ?? const ButtonStyle())
                  .copyWith(mouseCursor: clickCursor),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
                  .copyWith(mouseCursor: clickCursor),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Tooltip(
      message: hasValue
          ? 'Alterar data ($label)'
          : 'Selecionar data ($label)',
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(8),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color:  Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: hasValue ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today,
                size:  16,
                color: hasValue ? AppTheme.primary : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Text(
                hasValue ? '$label: ${_fmtData(value)}' : label,
                style: TextStyle(
                  fontSize:   13,
                  color:      hasValue ? AppTheme.primary : Theme.of(context).colorScheme.outline,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (hasValue) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Limpar data',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onCleared,
                      child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Controle de ordenação (dropdown + toggle asc/desc) ──────────────────────

class _OrdenacaoControl extends StatelessWidget {
  final _OrdenacaoOS ordenacao;
  final bool decrescente;
  final ValueChanged<_OrdenacaoOS> onOrdenacaoChanged;
  final VoidCallback onDirecaoToggled;

  const _OrdenacaoControl({
    required this.ordenacao,
    required this.decrescente,
    required this.onOrdenacaoChanged,
    required this.onDirecaoToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Ordenar lista de ordens de serviço',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_OrdenacaoOS>(
                  value: ordenacao,
                  isDense: true,
                  mouseCursor: SystemMouseCursors.click,
                  icon: Icon(Icons.arrow_drop_down,
                      size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  items: _OrdenacaoOS.values
                      .map((o) => DropdownMenuItem(
                            value: o,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(o.icon, size: 15, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Text('Ordenar: ${o.label}'),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (o) {
                    if (o != null) onOrdenacaoChanged(o);
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: decrescente ? 'Ordem decrescente (clique para inverter)' : 'Ordem crescente (clique para inverter)',
          onPressed: onDirecaoToggled,
          icon: Icon(
            decrescente ? Icons.arrow_downward : Icons.arrow_upward,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ).copyWith(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
        ),
      ],
    );
  }
}

// ─── Grid de OS (widget auxiliar para as abas) ────────────────────────────────

bool _osEhNumerica(String numeroOS) => int.tryParse(numeroOS.trim()) != null;

/// Classifica uma OS textual em uma das categorias grandes exibidas dentro
/// de "Empresa": "EMPRESA-(DATA)" → EMPRESA, "INVESTIMENTO-(DATA)" →
/// INVESTIMENTO, qualquer outra coisa → OUTROS.
String _categoriaEmpresa(String numeroOS) {
  final upper = numeroOS.trim().toUpperCase();
  if (upper.startsWith('EMPRESA-') || upper == 'EMPRESA') return 'EMPRESA';
  if (upper.startsWith('INVESTIMENTO-') || upper == 'INVESTIMENTO') return 'INVESTIMENTO';
  return 'OUTROS';
}

class _CategoriaEmpresaInfo {
  final String chave;
  final String label;
  final IconData icone;
  final Color cor;
  const _CategoriaEmpresaInfo(this.chave, this.label, this.icone, this.cor);
}

final _categoriasEmpresa = <_CategoriaEmpresaInfo>[
  _CategoriaEmpresaInfo('EMPRESA', 'Empresa', Icons.business_outlined, AppTheme.primary),
  _CategoriaEmpresaInfo('INVESTIMENTO', 'Investimento', Icons.trending_up, const Color(0xFF2E7D32)),
  _CategoriaEmpresaInfo('OUTROS', 'Outros', Icons.category_outlined, const Color(0xFF6D4C41)),
];

class _OsGrid extends StatefulWidget {
  final List<RelacaoOSModel> relacoes;
  final String emptyMessage;
  final void Function(RelacaoOSModel) onTap;

  const _OsGrid({
    required this.relacoes,
    required this.emptyMessage,
    required this.onTap,
  });

  @override
  State<_OsGrid> createState() => _OsGridState();
}

class _OsGridState extends State<_OsGrid> {
  /// Categoria de "Empresa" atualmente aberta (null = mostra os 3 cards grandes).
  String? _categoriaAberta;

  // Chaves usadas para rolar automaticamente a tela: ao expandir uma
  // categoria, rola até o conteúdo expandido (mini-cards); ao recolher,
  // rola de volta até o topo dos 3 cards grandes.
  final GlobalKey _cardsCategoriaKey = GlobalKey();
  final GlobalKey _conteudoExpandidoKey = GlobalKey();

  void _alternarCategoria(String chave, bool estaSelecionada) {
    final abrindo = !estaSelecionada;
    setState(() => _categoriaAberta = abrindo ? chave : null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = abrindo ? _conteudoExpandidoKey : _cardsCategoriaKey;
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: abrindo ? 1.0 : 0.0,
        );
      }
    });
  }

  SliverToBoxAdapter _cabecalho(String titulo, int count, BuildContext context) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 20, bottom: 10),
          child: Row(
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
            ],
          ),
        ),
      );

  @override
  void didUpdateWidget(covariant _OsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se a categoria aberta deixou de ter itens nos dados atuais (ex.: a
    // última OS dela foi fechada/excluída), volta para os 3 cards grandes.
    if (_categoriaAberta != null) {
      final aindaExiste = widget.relacoes.any((r) =>
          !_osEhNumerica(r.numeroOS) &&
          _categoriaEmpresa(r.numeroOS) == _categoriaAberta);
      if (!aindaExiste) {
        _categoriaAberta = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.relacoes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            SizedBox(height: 12),
            Text(
              widget.emptyMessage,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final numericas = widget.relacoes.where((r) => _osEhNumerica(r.numeroOS)).toList();
    final textuais  = widget.relacoes.where((r) => !_osEhNumerica(r.numeroOS)).toList();

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1,
    );

    // Agrupa as OS textuais por categoria (EMPRESA / INVESTIMENTO / OUTROS).
    final porCategoria = <String, List<RelacaoOSModel>>{
      for (final c in _categoriasEmpresa) c.chave: <RelacaoOSModel>[],
    };
    for (final r in textuais) {
      porCategoria[_categoriaEmpresa(r.numeroOS)]!.add(r);
    }

    final categoriaInfo = _categoriaAberta == null
        ? null
        : _categoriasEmpresa.firstWhere((c) => c.chave == _categoriaAberta);
    final itensCategoria =
        _categoriaAberta == null ? const <RelacaoOSModel>[] : porCategoria[_categoriaAberta]!;

    return CustomScrollView(
      slivers: [
        if (numericas.isNotEmpty) ...[
          _cabecalho('Ordens de Serviço', numericas.length, context),
          SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final rel = numericas[i];
                return _RelacaoOSCard(relacao: rel, onTap: () => widget.onTap(rel));
              },
              childCount: numericas.length,
            ),
            gridDelegate: gridDelegate,
          ),
        ],
        if (textuais.isNotEmpty) ...[
          _cabecalho('Outros', textuais.length, context),
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final largura = constraints.maxWidth;
                final colunas = largura >= 640 ? 3 : (largura >= 420 ? 2 : 1);
                return Container(
                  key: _cardsCategoriaKey,
                  child: GridView.count(
                    crossAxisCount: colunas,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.9,
                    children: _categoriasEmpresa.map((cat) {
                      final itens = porCategoria[cat.chave]!;
                      final selecionado = _categoriaAberta == cat.chave;
                      return _CategoriaEmpresaCard(
                        info: cat,
                        count: itens.length,
                        selecionado: selecionado,
                        onTap: itens.isEmpty
                            ? null
                            : () => _alternarCategoria(cat.chave, selecionado),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
          if (_categoriaAberta != null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: categoriaInfo!.cor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OS em ${categoriaInfo.label}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final rel = itensCategoria[i];
                  final card = _RelacaoOSCard(relacao: rel, onTap: () => widget.onTap(rel));
                  // A chave fica no primeiro card da linha para que o auto-scroll
                  // role até a linha de mini-cards realmente aparecer, não só o rótulo.
                  return i == 0 ? KeyedSubtree(key: _conteudoExpandidoKey, child: card) : card;
                },
                childCount: itensCategoria.length,
              ),
              gridDelegate: gridDelegate,
            ),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

// ─── Card grande de categoria (Empresa / Investimento / Outros) ──────────────

class _CategoriaEmpresaCard extends StatelessWidget {
  final _CategoriaEmpresaInfo info;
  final int count;
  final bool selecionado;
  final VoidCallback? onTap;

  const _CategoriaEmpresaCard({
    required this.info,
    required this.count,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return Tooltip(
      message: habilitado
          ? (selecionado ? 'Recolher ${info.label}' : 'Ver ordens de ${info.label}')
          : 'Nenhuma ordem em ${info.label}',
      child: Card(
      elevation: selecionado ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selecionado
            ? BorderSide(color: info.cor, width: 1.6)
            : BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
      color: selecionado ? info.cor.withValues(alpha: 0.06) : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        mouseCursor: habilitado
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Opacity(
          opacity: habilitado ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: info.cor.withValues(alpha: selecionado ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(info.icone, color: info.cor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: selecionado
                              ? info.cor
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        '$count ${count == 1 ? 'ordem' : 'ordens'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (habilitado)
                  Icon(
                    selecionado ? Icons.expand_less : Icons.expand_more,
                    color: selecionado ? info.cor : Theme.of(context).colorScheme.outline,
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

// ─── Card de OS ────────────────────────────────────────────────────────────────

class _RelacaoOSCard extends StatelessWidget {
  final RelacaoOSModel relacao;
  final VoidCallback onTap;

  const _RelacaoOSCard({required this.relacao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final foiAlterada = relacao.atualizadoEm != null &&
        relacao.criadoEm != null &&
        relacao.atualizadoEm!.difference(relacao.criadoEm!).inMinutes.abs() > 1;
    final dataStr = _fmtData(relacao.atualizadoEm ?? relacao.criadoEm);
    final criadoEmStr = _fmtData(relacao.criadoEm);

    // Remove sufixo interno "#OCx" / "#Sx" / "#Ex" de OS textuais antes de exibir
    final numeroOSRaw = relacao.numeroOS;
    final idxSufixo   = [
      numeroOSRaw.indexOf('#OC'),
      numeroOSRaw.indexOf('#S'),
      numeroOSRaw.indexOf('#E'),
    ].where((i) => i > 0)
     .fold<int>(-1, (best, i) => best == -1 ? i : (i < best ? i : best));
    final numeroOSDisplay = idxSufixo > 0
        ? numeroOSRaw.substring(0, idxSufixo)
        : numeroOSRaw;

    final materiaisUnicos = relacao.movimentacoes.map((m) => m.materialId).toSet().length;

    final corSt = _corStatus(relacao.status);

    final tituloCard = int.tryParse(numeroOSDisplay) != null
        ? 'OS $numeroOSDisplay'
        : numeroOSDisplay;

    return Tooltip(
      message: 'Abrir $tituloCard',
      child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Ícone + badge de status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_outlined,
                        color: AppTheme.primary, size: 20),
                  ),
                  const Spacer(),
                  // Badge status
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: corSt.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: corSt.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      _labelStatus(relacao.status),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: corSt,
                      ),
                    ),
                  ),
                ],
              ),
              // Título + contagem + data
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    int.tryParse(numeroOSDisplay) != null
                        ? 'OS $numeroOSDisplay'
                        : numeroOSDisplay,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    '$materiaisUnicos '
                    '${materiaisUnicos == 1 ? 'material' : 'materiais'}',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 11,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 3),
                      Text(
                        'Criado em $criadoEmStr',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  if (foiAlterada) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(Icons.update, size: 11, color: AppTheme.primary),
                        ),
                        Text(
                          'Alterada em $dataStr',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ─── Tela de detalhe da OS ────────────────────────────────────────────────────

class _RelacaoDetalhe extends StatefulWidget {
  final int relacaoOSId;
  final String numeroOS;
  const _RelacaoDetalhe({required this.relacaoOSId, required this.numeroOS});

  @override
  State<_RelacaoDetalhe> createState() => _RelacaoDetalheState();
}

class _RelacaoDetalheState extends State<_RelacaoDetalhe> {
  bool _revertendo = false;

  /// Remove sufixo interno "#OCx" / "#Sx" / "#Ex" usado para distinguir OS textuais no banco.
  String get _numeroOSDisplay {
    final n = widget.numeroOS;
    final candidates = [n.indexOf('#OC'), n.indexOf('#S'), n.indexOf('#E')]
        .where((i) => i > 0)
        .toList();
    if (candidates.isEmpty) return n;
    candidates.sort();
    return n.substring(0, candidates.first);
  }

  String get _tituloOS => int.tryParse(_numeroOSDisplay) != null
      ? 'OS $_numeroOSDisplay'
      : _numeroOSDisplay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstoqueProvider>().selecionarRelacaoOS(widget.numeroOS);
    });
  }

  // ── Reverter OS ────────────────────────────────────────────────────────────
  Future<void> _confirmarReverterOS() async {
    const corReverter = Color(0xFFED6C02);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: corReverter.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.undo_rounded, color: corReverter, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Reverter OS'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja reverter "$_tituloOS" para Em Andamento?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Cancelar e manter a OS fechada',
            child: TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              style: TextButton.styleFrom().copyWith(
                  mouseCursor:
                      WidgetStateProperty.all(SystemMouseCursors.click)),
              child: const Text('Cancelar'),
            ),
          ),
          Tooltip(
            message: 'Reverter OS para Em Andamento',
            child: FilledButton.icon(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: FilledButton.styleFrom().copyWith(
                  mouseCursor:
                      WidgetStateProperty.all(SystemMouseCursors.click)),
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text('Reverter OS'),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!mounted) return;

    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _revertendo = true);

    final ok = await provider.reverterOS(widget.numeroOS);

    if (!mounted) return;
    setState(() => _revertendo = false);

    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$_tituloOS revertida — disponível em Em Andamento'),
          backgroundColor: corReverter,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao reverter OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Fechar OS ──────────────────────────────────────────────────────────────
  Future<void> _confirmarFecharOS(BuildContext context) async {
    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _corEmAndamento.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.lock_outline,
                  color: _corEmAndamento, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Fechar OS'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja fechar "$_tituloOS"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _corEmAndamento.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _corEmAndamento.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Após fechar:\n'
                '• A OS não aceitará novas movimentações\n'
                '• Ela será movida para a página de Relatórios\n'
                '• Um relatório PDF poderá ser gerado',
                style:
                    TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Cancelar e manter a OS em andamento',
            child: TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              style: TextButton.styleFrom().copyWith(
                  mouseCursor:
                      WidgetStateProperty.all(SystemMouseCursors.click)),
              child: const Text('Cancelar'),
            ),
          ),
          Tooltip(
            message: 'Fechar esta ordem de serviço',
            child: FilledButton.icon(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Fechar OS'),
              style: FilledButton.styleFrom(
                backgroundColor: _corEmAndamento,
                foregroundColor: Colors.white,
              ).copyWith(
                  mouseCursor:
                      WidgetStateProperty.all(SystemMouseCursors.click)),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await provider.fecharOS(widget.relacaoOSId);

    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$_tituloOS fechada — disponível em Relatórios'),
          backgroundColor: _corEmAndamento,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao fechar OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Excluir OS ─────────────────────────────────────────────────────────────
  Future<void> _confirmarExcluirOS(BuildContext context) async {
    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir OS'),
        content: Text(
          'Deseja excluir "$_tituloOS" e todas as suas '
          'movimentações? Esta ação não pode ser desfeita.',
        ),
        actions: [
          Tooltip(
            message: 'Cancelar e manter a OS',
            child: TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              style: TextButton.styleFrom().copyWith(
                  mouseCursor:
                      WidgetStateProperty.all(SystemMouseCursors.click)),
              child: const Text('Cancelar'),
            ),
          ),
          Tooltip(
            message: 'Excluir permanentemente esta OS',
            child: FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error)
                  .copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click)),
              child: const Text('Excluir'),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await provider.excluirRelacaoOS(widget.relacaoOSId);

    if (ok) {
      provider.limparSelecao();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$_tituloOS excluída'),
          backgroundColor: AppTheme.error,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao excluir OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Renomear OS ────────────────────────────────────────────────────────────
  Future<void> _abrirRenomearOS(BuildContext context, RelacaoOSModel rel) async {
    final provider  = context.read<EstoqueProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Remove sufixo interno antes de exibir no campo
    final nomeAtual = _numeroOSDisplay;

    final novoNome = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => _RenomearOSDialog(nomeAtual: nomeAtual),
    );

    if (novoNome == null || novoNome.isEmpty || novoNome == nomeAtual) return;
    if (!mounted) return;

    final ok = await provider.renomearOS(rel.id, novoNome);
    if (!mounted) return;

    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('OS renomeada para "$novoNome"'),
          backgroundColor: AppTheme.primary,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.erro ?? 'Erro ao renomear OS'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstoqueProvider>();
    final rel      = provider.relacaoSelecionada;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BotaoVoltar(
              label: 'Voltar',
              tooltip: 'Voltar para a lista de ordens de serviço',
              onTap: () {
                provider.limparSelecao();
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(width: 12),
            Text(_tituloOS),
            if (rel != null) ...[
              const SizedBox(width: 10),
              _StatusBadgeOS(status: rel.status),
            ],
          ],
        ),
        actions: [
          // Botão Reverter OS (só para OS fechadas)
          if (rel != null && rel.estaFechada)
            _revertendo
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFED6C02)),
                    ),
                  )
                : Tooltip(
                    message: 'Reabrir esta OS para novas movimentações',
                    child: TextButton.icon(
                      onPressed: _confirmarReverterOS,
                      icon: const Icon(Icons.undo_rounded,
                          size: 18, color: Color(0xFFED6C02)),
                      label: const Text(
                        'Reverter OS',
                        style: TextStyle(
                          color: Color(0xFFED6C02),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom().copyWith(
                        mouseCursor:
                            WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                    ),
                  ),
          // Botões Entrada / Saída por OS foram removidos deste local: o
          // registro de movimentação agora é feito sempre a partir do card
          // do material (ver diálogo do material), evitando ambiguidade
          // sobre a que estoque/OS a ação se refere.
          // Botão Fechar OS (só exibe se EM_ANDAMENTO)
          if (rel != null && !rel.estaFechada)
            Tooltip(
              message: 'Finalizar e fechar esta ordem de serviço',
              child: TextButton.icon(
                onPressed: provider.fechandoOS
                    ? null
                    : () => _confirmarFecharOS(context),
                icon: provider.fechandoOS
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _corEmAndamento))
                    : Icon(Icons.lock_outline,
                        size: 18, color: _corEmAndamento),
                label: Text(
                  'Finalizar OS',
                  style: TextStyle(
                    color: provider.fechandoOS
                        ? Theme.of(context).colorScheme.outline
                        : _corEmAndamento,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom().copyWith(
                  mouseCursor:
                      WidgetStateProperty.all(SystemMouseCursors.click),
                ),
              ),
            ),
          // Botão renomear (só para OS em andamento)
          if (rel != null && !rel.estaFechada)
            Tooltip(
              message: 'Renomear esta ordem de serviço',
              child: IconButton(
                icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onPressed: () => _abrirRenomearOS(context, rel),
                style: IconButton.styleFrom().copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
              ),
            ),
          // Botão excluir (só para OS em andamento)
          if (rel != null && !rel.estaFechada)
            Tooltip(
              message: 'Excluir esta ordem de serviço',
              child: IconButton(
                icon: Icon(Icons.delete_outline, color: AppTheme.error),
                onPressed: () => _confirmarExcluirOS(context),
                style: IconButton.styleFrom().copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
              ),
            ),
        ],
      ),
      body: provider.carregandoDetalhe
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : rel == null
              ? Center(
                  child: Text(
                    'Relação não encontrada',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : _RelacaoDetalheBody(rel: rel),
    );
  }
}

// ─── Badge de status da OS ────────────────────────────────────────────────────

class _StatusBadgeOS extends StatelessWidget {
  final String status;
  const _StatusBadgeOS({required this.status});

  @override
  Widget build(BuildContext context) {
    final cor   = _corStatus(status);
    final label = _labelStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}

// ─── Corpo do detalhe ─────────────────────────────────────────────────────────

class _RelacaoDetalheBody extends StatefulWidget {
  final RelacaoOSModel rel;
  const _RelacaoDetalheBody({required this.rel});

  @override
  State<_RelacaoDetalheBody> createState() => _RelacaoDetalheBodyState();
}

class _RelacaoDetalheBodyState extends State<_RelacaoDetalheBody> {
  // Chave: materialId
  String _chaveGrupo(MovimentacaoModel mov) => '${mov.materialId}';

  final TextEditingController _filtroCtrl = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  bool _entradaCorresponde(MapEntry<String, List<MovimentacaoModel>> entry) {
    if (_filtro.isEmpty) return true;
    final mov = entry.value.first;
    final campos = [
      mov.materialNome,
      mov.materialIdentificador ?? '',
      mov.materialMedida ?? '',
      mov.materialEspessura ?? '',
    ].join(' ').toLowerCase();
    return campos.contains(_filtro);
  }

  @override
  Widget build(BuildContext context) {
    final materiaisMap = <String, List<MovimentacaoModel>>{};
    for (final mov in widget.rel.movimentacoes) {
      materiaisMap.putIfAbsent(_chaveGrupo(mov), () => []).add(mov);
    }

    if (materiaisMap.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma movimentação registrada',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    final entries = materiaisMap.entries.where(_entradaCorresponde).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: TextField(
            controller: _filtroCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_UpperCaseFormatter()],
            decoration: InputDecoration(
              hintText: 'Filtrar materiais por nome, identificador, medida ou espessura',
              prefixIcon: Icon(Icons.filter_alt_outlined,
                  color: Theme.of(context).colorScheme.outline, size: 20),
              isDense: true,
              suffixIcon: _filtro.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar filtro',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _filtroCtrl.clear();
                        setState(() => _filtro = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum material encontrado para o filtro.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    final movs  = List<MovimentacaoModel>.from(entry.value)
                      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
                    return _MaterialGridCard(
                      key: ValueKey(entry.key),
                      movimentacoes: movs,
                      numeroOS: widget.rel.numeroOS,
                      // OS fechada: bloqueia ações de movimentação/remoção
                      somenteLeitura: widget.rel.estaFechada,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Card de material em grid ──────────────────────────────────────────────────

class _MaterialGridCard extends StatefulWidget {
  final List<MovimentacaoModel> movimentacoes;
  final String numeroOS;
  final bool somenteLeitura;

  const _MaterialGridCard({
    super.key,
    required this.movimentacoes,
    required this.numeroOS,
    this.somenteLeitura = false,
  });

  @override
  State<_MaterialGridCard> createState() => _MaterialGridCardState();
}

class _MaterialGridCardState extends State<_MaterialGridCard> {
  MovimentacaoModel get _primeira => widget.movimentacoes.first;

  /// True quando o material desta movimentação foi excluído do cadastro.
  /// Ações que dependem do cadastro (nova movimentação, retalho, atualizar custo)
  /// ficam desabilitadas para evitar erros.
  bool get _materialFoiExcluido =>
      _primeira.materialNome == '(material excluído)' ||
      _primeira.materialNome.isEmpty;

  String get _subtitulo {
    final medidaOuDimensao = (_primeira.materialMedida ?? '').isNotEmpty
        ? _primeira.materialMedida
        : formatarMedidaOuDimensoes(
            medida:      null,
            largura:     _primeira.materialLargura,
            comprimento: _primeira.materialComprimento,
          );
    final partes = <String>[
      if ((_primeira.materialIdentificador ?? '').isNotEmpty)
        _primeira.materialIdentificador!,
      if (medidaOuDimensao != null && medidaOuDimensao.isNotEmpty)
        medidaOuDimensao,
      if (formatarEspessuraComSufixo(_primeira.materialEspessura) != null)
        formatarEspessuraComSufixo(_primeira.materialEspessura)!,
    ];
    return partes.join(' · ');
  }

  String _formatQtd(double qtd, String? unidade) {
    final qStr = formatarQuantidade(qtd);
    final unFmt = formatarUnidadeExibicao(unidade);
    return unFmt.isNotEmpty ? '$qStr $unFmt' : qStr;
  }

  String _formatData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  void _abrirMovimentacao(BuildContext context, String tipo) {
    if (_materialFoiExcluido) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Material excluído — não é possível registrar novas movimentações.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    // Busca último preço registrado nas movimentações desta OS,
    // ou recorre ao último valor pago do material.
    final ultimaMovOS = widget.movimentacoes
        .where((m) =>
            m.materialId == _primeira.materialId &&
            (m.precoUnitario != null && m.precoUnitario! > 0 ||
             m.precoM2 != null && m.precoM2! > 0))
        .fold<MovimentacaoModel?>(
            null,
            (prev, m) =>
                prev == null || m.criadoEm.isAfter(prev.criadoEm) ? m : prev);

    if (ultimaMovOS != null) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => _MovimentacaoItemDialog(
          tipo:          tipo,
          materialId:    _primeira.materialId,
          materialNome:  _primeira.materialNome,
          unidade:       _primeira.materialUnidade,
          numeroOS:      widget.numeroOS,
          precoUnitario: ultimaMovOS.precoUnitario,
          precoM2:       ultimaMovOS.precoM2,
        ),
      );
    } else {
      context.read<MaterialProvider>().buscarPorId(_primeira.materialId).then((mat) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (_) => _MovimentacaoItemDialog(
            tipo:          tipo,
            materialId:    _primeira.materialId,
            materialNome:  _primeira.materialNome,
            unidade:       _primeira.materialUnidade,
            numeroOS:      widget.numeroOS,
            precoUnitario: mat?.ultimoValorPago   ?? _primeira.precoUnitario,
            precoM2:       mat?.ultimoValorPagoM2 ?? _primeira.precoM2,
          ),
        );
      });
    }
  }

  Future<void> _confirmarRemoverMovimentacao(
      BuildContext context, MovimentacaoModel mov) async {
    // Captura tudo que será necessário ANTES do await que dispara
    // notifyListeners(). O `context` recebido aqui é o do _MaterialGridCard
    // que disparou a ação (vindo do painel de detalhe do material); se essa
    // for a última movimentação do material, o rebuild causado por
    // removerMovimentacao() remove esse card da árvore (e fecha o painel)
    // ENQUANTO ainda estamos no meio deste método. Qualquer uso de
    // `context`/`messenger` depois do await pode então operar sobre um
    // widget já desativado, daí os erros de "deactivated widget" e
    // "setState() called during build".
    final provider  = context.read<EstoqueProvider>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final rootContext =
        Navigator.of(context, rootNavigator: true).context;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remover movimentação'),
        content: Text(
          'Remover ${mov.tipo == 'ENTRADA' ? 'entrada' : 'saída'} de '
          '${_formatQtd(mov.quantidade, _primeira.materialUnidade)} '
          'de "${mov.materialNome}"?\n\n'
          'Atenção: o saldo de estoque do material será revertido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ok = await provider.removerMovimentacao(
      movimentacaoId: mov.id,
      numeroOS: widget.numeroOS,
    );

    // Não usa mais o `context` original (pode ter sido desativado pelo
    // rebuild acima). Usa o messenger já capturado e, como fallback, exibe
    // via o context raiz do app — que nunca é desmontado por esse fluxo.
    final feedback = SnackBar(
      content: Text(ok ? 'Movimentação removida' : (provider.erro ?? 'Erro')),
      backgroundColor: ok ? AppTheme.success : AppTheme.error,
    );
    if (messenger != null) {
      messenger.showSnackBar(feedback);
    } else if (rootContext.mounted) {
      ScaffoldMessenger.maybeOf(rootContext)?.showSnackBar(feedback);
    }
  }


  // ── Atualizar custo da última compra em todas as movimentações do card ──────
  Future<void> _abrirAtualizarCusto(BuildContext context) async {
    if (_materialFoiExcluido) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Material excluído — não é possível atualizar o custo.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    final materialProvider = context.read<MaterialProvider>();
    final estoqueProvider  = context.read<EstoqueProvider>();
    final messenger        = ScaffoldMessenger.of(context);

    // Busca o material para obter o último valor pago
    final mat = await materialProvider.buscarPorId(_primeira.materialId);
    if (!context.mounted) return;

    final temPrecoUnit = mat?.ultimoValorPago    != null && mat!.ultimoValorPago!    > 0;
    final temPrecoM2   = mat?.ultimoValorPagoM2 != null && mat!.ultimoValorPagoM2! > 0;

    if (!temPrecoUnit && !temPrecoM2) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Nenhum custo de última compra registrado para este material'),
          backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
      return;
    }

    String brl(double v) =>
        _brl6(v);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.price_change_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Atualizar custo'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Atualizar o custo de todas as movimentações de "${_primeira.materialNome}" nesta OS?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Novo custo (última compra):',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Builder(builder: (_) {
                    const mlU = {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'};
                    final eML = mlU.contains(mat.unidade?.toLowerCase().trim() ?? '');
                    if (eML) {
                      final valML = mat.ultimoValorPago ?? mat.ultimoValorPagoM2;
                      if (valML != null && valML > 0) {
                        return Text(
                          'm/l: ${brl(valML)}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (temPrecoUnit)
                          Text(
                            'Unit.: ${brl(mat.ultimoValorPago!)}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary),
                          ),
                        if (temPrecoM2)
                          Text(
                            'M²: ${brl(mat.ultimoValorPagoM2!)}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Somente o custo registrado nas movimentações será alterado — '
              'as quantidades e o saldo de estoque não mudam.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Atualizar custo'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!context.mounted) return;

    // Atualiza todas as movimentações do card em sequência
    int sucessos = 0;
    int falhas   = 0;
    for (final mov in widget.movimentacoes) {
      final ok = await estoqueProvider.atualizarPrecoMovimentacao(
        mov.id,
        precoUnitario: temPrecoUnit ? mat.ultimoValorPago  : null,
        precoM2:       temPrecoM2  ? mat.ultimoValorPagoM2 : null,
      );
      if (ok) {
        sucessos++;
      } else {
        falhas++;
      }
    }

    if (!context.mounted) return;

    // Recarrega o detalhe da OS para refletir os novos preços
    await estoqueProvider.selecionarRelacaoOS(widget.numeroOS);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          falhas == 0
              ? 'Custo atualizado em $sucessos movimentação(ões)'
              : '$sucessos atualizada(s), $falhas com erro',
        ),
        backgroundColor: falhas == 0 ? AppTheme.success : AppTheme.error,
      ),
    );
  }

  Future<void> _abrirReentradaRetalho(BuildContext context) async {
    if (_materialFoiExcluido) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Material excluído — não é possível criar reentrada de retalho.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }
    final material = _primeira;

    final messenger       = ScaffoldMessenger.of(context);
    final estoqueProvider = context.read<EstoqueProvider>();
    final materialProvider = context.read<MaterialProvider>();

    // Busca dados do material (dimensões e custo m²)
    final mat = await materialProvider.buscarPorId(material.materialId);
    if (!context.mounted) return;

    final largura     = mat?.largura;
    final comprimento = mat?.comprimento;

    // Se não há dimensões, não é possível calcular área — avisa e sai.
    if (largura == null || comprimento == null || largura <= 0 || comprimento <= 0) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Este material não tem largura/comprimento cadastrados. '
          'Cadastre as dimensões para usar a reentrada de retalho.',
        ),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }

    // Custo m²: prioriza o valor real das movimentações de saída desta OS
    // (para refletir o custo que foi realmente lançado), com fallback no
    // cadastro do material.
    final custoM2 = () {
      // Pega o precoM2 da movimentação de saída mais recente que tenha valor
      final ultimaSaidaComPreco = widget.movimentacoes
          .where((m) => m.tipo == 'SAIDA' && m.precoM2 != null && m.precoM2! > 0)
          .fold<MovimentacaoModel?>(
              null,
              (prev, m) => prev == null || m.criadoEm.isAfter(prev.criadoEm) ? m : prev);
      if (ultimaSaidaComPreco != null) {
        // precoM2 nas saídas com modo dimensional é o custo proporcional da área
        // usada (não o custo/m²). Recalculamos o custo/m² dividindo pela área usada.
        if (ultimaSaidaComPreco.usouModoDimensional) {
          final lu = ultimaSaidaComPreco.larguraUsada!;
          final cu = ultimaSaidaComPreco.comprimentoUsado!;
          final area = lu * cu;
          return area > 0 ? ultimaSaidaComPreco.precoM2! / area : mat?.ultimoValorPagoM2;
        }
        return ultimaSaidaComPreco.precoM2;
      }
      // Fallback: custo unitário ÷ área da chapa
      if (mat?.ultimoValorPago != null && mat!.ultimoValorPago! > 0) {
        final areaChapa = largura * comprimento;
        return areaChapa > 0 ? mat.ultimoValorPago! / areaChapa : null;
      }
      return mat?.ultimoValorPagoM2;
    }();

    final areaUnitaria = largura * comprimento;

    // Calcula área total das saídas desta OS para este material
    final totalSaidasUnid = widget.movimentacoes
        .where((m) => m.tipo == 'SAIDA')
        .fold<double>(0, (s, m) => s + m.quantidade);

    final areaTotalSaida = totalSaidasUnid * areaUnitaria;

    // Custo total registrado nas saídas desta OS (soma dos precoUnitario ou
    // precoM2 reais de cada movimentação, independente do custo/m² atual).
    final custoTotalSaidas = widget.movimentacoes
        .where((m) => m.tipo == 'SAIDA')
        .fold<double>(0, (s, m) {
          if (m.usouModoDimensional && m.precoM2 != null) {
            // precoM2 aqui já é o custo proporcional total da área usada
            return s + m.precoM2!;
          }
          if (m.precoUnitario != null && m.precoUnitario! > 0) {
            return s + m.precoUnitario! * m.quantidade;
          }
          if (m.precoM2 != null && m.precoM2! > 0) {
            return s + m.precoM2! * m.quantidade;
          }
          return s;
        });

    final m2Ctrl = TextEditingController();

    String fmt6(double v) => _brl6(v);
    String fmtQtd(double v) =>
        v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(4);

    final resultado = await showDialog<double>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) {
          final m2TextoRaw = m2Ctrl.text.replaceAll(',', '.');
          final m2Retalho  = double.tryParse(m2TextoRaw);

          // M² líquido = total saído − retalho de volta (mín. 0)
          final liquidoM2 = (m2Retalho != null && m2Retalho > 0)
              ? (areaTotalSaida - m2Retalho).clamp(0.0, double.infinity).toDouble()
              : null;

          // Custo líquido proporcional: custoTotal × (liquidoM2 / areaTotalSaida)
          final custoLiquido = (liquidoM2 != null && areaTotalSaida > 0 && custoTotalSaidas > 0)
              ? custoTotalSaidas * (liquidoM2 / areaTotalSaida)
              : (liquidoM2 != null && custoM2 != null && custoM2 > 0)
                  ? liquidoM2 * custoM2
                  : null;

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.content_cut, color: AppTheme.success, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Reentrada de Retalho'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    material.materialNome,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  if (formatarEspessuraComSufixo(material.materialEspessura) != null)
                    Text(
                      formatarEspessuraComSufixo(material.materialEspessura)!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  const SizedBox(height: 12),

                  // ── Resumo das saídas ──────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total saído nesta OS',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${fmtQtd(totalSaidasUnid)} unid. '
                          '× ${fmtQtd(areaUnitaria)} m²/unid. '
                          '= ${fmtQtd(areaTotalSaida)} m²',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.error,
                          ),
                        ),
                        if (custoTotalSaidas > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Custo total registrado: ${fmt6(custoTotalSaidas)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ] else if (custoM2 != null && custoM2 > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Custo m²: ${fmt6(custoM2)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  TextField(
                    controller: m2Ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'M² de retalho que sobrou *',
                      suffixText: 'm²',
                      isDense: true,
                    ),
                    onChanged: (_) => setDlg(() {}),
                  ),

                  // ── Preview do cálculo líquido ─────────────────────────────
                  if (liquidoM2 != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'M² realmente utilizado nesta OS',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${fmtQtd(areaTotalSaida)} m² − ${fmtQtd(m2Retalho!)} m² '
                            '= ${fmtQtd(liquidoM2)} m²',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          if (custoLiquido != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Custo líquido no relatório: ${fmt6(custoLiquido)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      'Será criado (ou somado ao existente) um material '
                      '"${material.materialNome}" com unidade M² '
                      'e a quantidade informada será adicionada ao estoque dele.',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: m2Retalho == null || m2Retalho <= 0
                    ? null
                    : () => Navigator.of(dlgCtx).pop(m2Retalho),
                icon: const Icon(Icons.content_cut, size: 16),
                label: const Text('Confirmar Reentrada'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
              ),
            ],
          );
        },
      ),
    );

    if (resultado == null || resultado <= 0) return;
    if (!context.mounted) return;

    final m2Retalho = resultado;

    // ── Busca ou cria o material RETALHO ──────────────────────────────────────
    // Nome padrão: usa literalmente o nome do material original (sem sufixo).
    // Mesma espessura e categoria, unidade M², identificador RETALHO,
    // custo/m² do original.

    final nomeRetalho = material.materialNome;
    final espessura   = material.materialEspessura;
    final categoria   = mat?.categoria;

    // Tenta encontrar o retalho existente pelo nome + espessura + identificador
    final sugestoes = await materialProvider.buscarSugestoes(
      nomeRetalho,
      limite: 20,
      apenasAtivos: true,
    );
    if (!context.mounted) return;

    MaterialModel? retalhoExistente;
    for (final s in sugestoes) {
      final nomeNorm   = _normalizarTextoComparacaoCE(s.nome);
      final nomeAlvo   = _normalizarTextoComparacaoCE(nomeRetalho);
      final mesmoIdent = (s.identificador?.toUpperCase() ?? '') == 'RETALHO';
      final mesmaEsp   = espessura == null ||
          espessura.isEmpty ||
          _normalizarTextoComparacaoCE(s.espessura) ==
              _normalizarTextoComparacaoCE(espessura);
      if (nomeNorm == nomeAlvo && mesmoIdent && mesmaEsp) {
        retalhoExistente = s;
        break;
      }
    }

    int retalhoMaterialId;

    if (retalhoExistente != null) {
      retalhoMaterialId = retalhoExistente.id;
    } else {
      // Cria o material RETALHO
      final ok = await materialProvider.criar({
        'nome':              nomeRetalho,
        'identificador':     'RETALHO',
        'unidade':           'M²',
        'categoria':         categoria,
        'espessura':         espessura,
        'quantidade':        0.0,
        'estoqueMinimo':     0.0,
        'estoqueConfirmado': false,
        if (custoM2 != null && custoM2 > 0) 'ultimoValorPagoM2': custoM2,
      });
      if (!context.mounted) return;
      if (!ok) {
        messenger.showSnackBar(SnackBar(
          content: Text(materialProvider.erro ?? 'Erro ao criar material "$nomeRetalho"'),
          backgroundColor: AppTheme.error,
        ));
        return;
      }
      // Busca o material recém-criado
      final lista = await materialProvider.buscarSugestoes(nomeRetalho, limite: 5);
      if (!context.mounted) return;
      final criado = lista.firstWhere(
        (s) =>
            _normalizarTextoComparacaoCE(s.nome) ==
                _normalizarTextoComparacaoCE(nomeRetalho) &&
            (s.identificador?.toUpperCase() ?? '') == 'RETALHO',
        orElse: () => lista.first,
      );
      retalhoMaterialId = criado.id;
    }

    // ── Custo proporcional do retalho ─────────────────────────────────────────
    // precoM2 na entrada do RETALHO = custo/m² do material original,
    // de forma que: quantidade(m²) × precoM2 = custo proporcional no relatório.
    final custoM2Retalho = custoM2;

    // ── Registra ENTRADA do retalho vinculada a esta OS ───────────────────────
    final entradaOk = await estoqueProvider.registrarMovimentacaoSilencioso(
      materialId:       retalhoMaterialId,
      tipo:             'ENTRADA',
      quantidade:       m2Retalho,
      numeroOS:         widget.numeroOS,
      precoUnitario:    null,
      precoM2:          custoM2Retalho,
      observacao:       'Retalho de ${material.materialNome}',
      materialOrigemId: material.materialId,
    );
    if (!context.mounted) return;

    if (!entradaOk) {
      messenger.showSnackBar(SnackBar(
        content: Text(estoqueProvider.erro ?? 'Erro ao registrar reentrada'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }

    // Recarrega a OS para refletir a nova movimentação
    await estoqueProvider.carregarRelacoesOS();
    if (!context.mounted) return;
    await estoqueProvider.selecionarRelacaoOS(widget.numeroOS);
    if (!context.mounted) return;

    // Custo líquido final para o snackbar (mesmo cálculo do preview)
    final liquidoM2Final = (areaTotalSaida - m2Retalho).clamp(0.0, double.infinity).toDouble();
    final custoLiquidoFinal = custoTotalSaidas > 0 && areaTotalSaida > 0
        ? custoTotalSaidas * (liquidoM2Final / areaTotalSaida)
        : (custoM2 != null && custoM2 > 0 ? liquidoM2Final * custoM2 : null);

    messenger.showSnackBar(SnackBar(
      content: Text(
        custoLiquidoFinal != null
            ? 'Retalho registrado. Líquido utilizado: ${liquidoM2Final.toStringAsFixed(4)} m²'
              ' — Custo: ${_brl6(custoLiquidoFinal)}'
            : 'Retalho registrado. M² líquido utilizado: ${liquidoM2Final.toStringAsFixed(4)} m²',
      ),
      backgroundColor: AppTheme.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final unidade = _primeira.materialUnidade;
    final totais  = _TotaisMovimentacao.calcular(widget.movimentacoes);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _mostrarPainel(context),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _primeira.materialNome,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_subtitulo.isNotEmpty) ...[
                          SizedBox(height: 2),
                          Text(
                            _subtitulo,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.expand_more,
                      size: 18, color: Theme.of(context).colorScheme.outline),
                ],
              ),
              Spacer(),
              _UltimoPrecoRow(movimentacoes: widget.movimentacoes, unidade: unidade),
              SizedBox(height: 6),
              _TotaisResumoMini(totais: totais, unidade: unidade),
              SizedBox(height: 4),
              Text(
                '${widget.movimentacoes.length} '
                '${widget.movimentacoes.length == 1 ? 'movimentação' : 'movimentações'}',
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarPainel(BuildContext context) async {
    // Dados estáticos do card (nome, subtítulo) — não mudam
    final materialNome   = _primeira.materialNome;
    final subtitulo      = _subtitulo;
    final unidade        = _primeira.materialUnidade;
    final somenteLeitura = widget.somenteLeitura;
    final chaveGrupo     = widget.movimentacoes.isNotEmpty
        ? '${_primeira.materialId}'
        : '';

    await showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Consumer<EstoqueProvider>(
        builder: (ctx, provider, _) {
          // Busca as movimentações atualizadas do provider
          final rel = provider.relacaoSelecionada;
          final movsAtuais = rel == null
              ? <MovimentacaoModel>[]
              : rel.movimentacoes
                  .where((m) => '${m.materialId}' == chaveGrupo)
                  .toList()
            ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

          // Se todas as movimentações foram removidas, fecha o dialog.
          // Verifica ctx.mounted (não apenas canPop()) porque, quando esta
          // era a última movimentação do material, o MESMO notifyListeners()
          // que zerou `movsAtuais` também remove o _MaterialGridCard (pai)
          // da árvore no GridView. Os dois rebuilds (deste Consumer e o do
          // pai) podem ser processados no mesmo frame; sem essa checagem,
          // o Navigator.of(ctx) pode operar sobre um elemento já desativado.
          if (movsAtuais.isEmpty && rel != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              final navigator = Navigator.of(ctx);
              if (navigator.canPop()) navigator.pop();
            });
          }

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: SizedBox(
              width: 560,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                materialNome,
                                style: Theme.of(ctx).textTheme.titleLarge,
                              ),
                              if (subtitulo.isNotEmpty)
                                Text(
                                  subtitulo,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              if (unidade != null && formatarUnidadeExibicao(unidade).isNotEmpty)
                                Text(
                                  formatarUnidadeExibicao(unidade),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Fechar',
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                            },
                            style: IconButton.styleFrom().copyWith(
                              mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _UltimoPrecoRow(
                      movimentacoes: movsAtuais,
                      unidade: unidade,
                      expanded: true,
                    ),
                    const SizedBox(height: 10),
                    _TotaisResumoCompleto(
                      movimentacoes: movsAtuais,
                      unidade: unidade,
                    ),
                    const SizedBox(height: 16),

                    // Botões entrada / saída (ocultados se somente leitura)
                    if (!somenteLeitura) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: 'Registrar entrada deste material',
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  _abrirMovimentacao(context, 'ENTRADA');
                                },
                                icon: const Icon(Icons.add,
                                    size: 16, color: AppTheme.success),
                                label: const Text('Entrada para o estoque',
                                    style: TextStyle(color: AppTheme.success)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: AppTheme.success),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ).copyWith(
                                  mouseCursor: WidgetStateProperty.all(
                                      SystemMouseCursors.click),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message: 'Registrar saída deste material',
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  _abrirMovimentacao(context, 'SAIDA');
                                },
                                icon: const Icon(Icons.remove,
                                    size: 16, color: AppTheme.error),
                                label: const Text('Saída para a OS',
                                    style: TextStyle(color: AppTheme.error)),
                                style: OutlinedButton.styleFrom(
                                  side:
                                      const BorderSide(color: AppTheme.error),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ).copyWith(
                                  mouseCursor: WidgetStateProperty.all(
                                      SystemMouseCursors.click),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ── Atualizar custo da última compra ─────────────────
                      SizedBox(
                        width: double.infinity,
                        child: Tooltip(
                          message: 'Atualizar o custo com base na última compra',
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _abrirAtualizarCusto(context);
                            },
                            icon: Icon(Icons.price_change_outlined,
                                size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            label: Text(
                              'Atualizar custo (última compra)',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ).copyWith(
                              mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click),
                            ),
                          ),
                        ),
                      ),
                      // ── Reentrada de Retalho (só para UNIDADE) ───────────────────────────
                      // A verificação de dimensão (largura × comprimento) é feita
                      // dentro de _abrirReentradaRetalho, com feedback adequado ao usuário.
                      if (_primeira.materialUnidade?.toUpperCase() == 'UNIDADE')
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _abrirReentradaRetalho(context);
                            },
                            icon: const Icon(Icons.content_cut, size: 16, color: AppTheme.success),
                            label: const Text(
                              'Reentrada de Retalho',
                              style: TextStyle(color: AppTheme.success),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.success),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ).copyWith(
                              mouseCursor: WidgetStateProperty.all(
                                  SystemMouseCursors.click),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _corFechada.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _corFechada.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 14, color: _corFechada),
                            SizedBox(width: 6),
                            Text(
                              'OS fechada — somente leitura',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _corFechada,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                    ],

                    Divider(height: 1),
                    SizedBox(height: 12),

                    Text(
                      'Histórico (${movsAtuais.length})',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.35,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: movsAtuais.length,
                        itemBuilder: (_, i) {
                          final mov = movsAtuais[i];
                          return _MovimentacaoRow(
                            mov: mov,
                            unidade: unidade,
                            formatData: _formatData,
                            formatQtd: _formatQtd,
                            onRemove: somenteLeitura
                                ? null
                                : () => _confirmarRemoverMovimentacao(
                                    context, mov),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

  }
}

// ─── Último preço do material (unit. e/ou m²) ────────────────────────────────
// Lê o preço mais recente das movimentações passadas para exibir no card.

class _UltimoPrecoRow extends StatelessWidget {
  final List<MovimentacaoModel> movimentacoes;
  /// Unidade do material (ex: 'M/L', 'm', 'UNIDADE', 'M2'…).
  /// Usado para escolher o label correto nos badges de custo.
  final String? unidade;
  /// [expanded] = true no painel popup (layout horizontal mais largo).
  final bool expanded;

  const _UltimoPrecoRow({
    required this.movimentacoes,
    this.unidade,
    this.expanded = false,
  });

  static String _brl(double v) =>
      _brl6(v);

  static const _unidadesMetroLinear = {
    'm', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares',
  };

  bool get _eMetroLinear =>
      _unidadesMetroLinear.contains(unidade?.toLowerCase().trim() ?? '');

  @override
  Widget build(BuildContext context) {
    // Pega a movimentação mais recente com preço (ENTRADA ou SAIDA)
    final todas = List<MovimentacaoModel>.from(movimentacoes)
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

    double? pu;
    double? pm2;
    for (final mov in todas) {
      if (pu == null && mov.precoUnitario != null && mov.precoUnitario! > 0) {
        pu = mov.precoUnitario;
      }
      if (pm2 == null && mov.precoM2 != null && mov.precoM2! > 0) {
        pm2 = mov.precoM2;
      }
      if (pu != null && pm2 != null) break;
    }

    if (pu == null && pm2 == null) return const SizedBox.shrink();

    // Para metro linear:
    //   • precoUnitario = custo por metro linear (R$/m) → badge "M/L"
    //   • precoM2 gravado = custo por metro linear também (mesmo valor)
    //     → não exibir separado; mostrar o verdadeiro custo/m² do material
    //       que é precoM2 / largura — mas como não temos largura aqui,
    //       exibimos apenas o badge M/L e omitimos o badge M² redundante.
    // Para materiais UNIDADE (chapa):
    //   • precoUnitario → badge "Unit."
    //   • precoM2 → badge "M²"
    final chips = <Widget>[];
    if (_eMetroLinear) {
      // Prefere precoUnitario (custo/metro linear); fallback para precoM2
      final valorML = pu ?? pm2;
      if (valorML != null) {
        chips.add(_PrecoBadge(label: 'm/l', valor: _brl(valorML)));
      }
    } else {
      if (pu != null) {
        chips.add(_PrecoBadge(label: 'Unit.', valor: _brl(pu)));
      }
      if (pm2 != null) {
        if (chips.isNotEmpty) chips.add(const SizedBox(width: 4));
        chips.add(_PrecoBadge(label: 'M²', valor: _brl(pm2)));
      }
    }

    return Row(children: chips);
  }
}

class _PrecoBadge extends StatelessWidget {
  final String label;
  final String valor;
  const _PrecoBadge({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: valor,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Totais de entrada/saída ──────────────────────────────────────────────────

class _TotaisMovimentacao {
  final double qtdEntrada;
  final double qtdSaida;
  final double valorEntrada;
  final double valorSaida;

  const _TotaisMovimentacao({
    required this.qtdEntrada,
    required this.qtdSaida,
    required this.valorEntrada,
    required this.valorSaida,
  });

  static String _brl(double v) =>
      _brl6(v);

  String get qtdEntradaStr => qtdEntrada == qtdEntrada.truncate()
      ? qtdEntrada.toStringAsFixed(0)
      : qtdEntrada.toStringAsFixed(2);

  String get qtdSaidaStr => qtdSaida == qtdSaida.truncate()
      ? qtdSaida.toStringAsFixed(0)
      : qtdSaida.toStringAsFixed(2);

  String get valorEntradaStr => _brl(valorEntrada);
  String get valorSaidaStr   => _brl(valorSaida);

  static _TotaisMovimentacao calcular(List<MovimentacaoModel> movs) {
    double qtdE = 0, qtdS = 0, valE = 0, valS = 0;
    const mlUnits = {
      'm', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares',
    };
    for (final m in movs) {
      final pm2  = m.precoM2;
      final pu   = m.precoUnitario;
      final unid = (m.materialUnidade ?? '').toLowerCase().trim();
      // Metro linear: a quantidade está em metros, então o fator correto é
      // precoUnitario (custo por metro linear). precoM2, quando presente,
      // é apenas referência de custo/m² do material e NÃO deve ser
      // multiplicado pela quantidade em metros — fazer isso gera o valor
      // errado (qtd × custo/m² em vez de qtd × custo/metro).
      final eMetroLinear = mlUnits.contains(unid);
      // M²: a quantidade já está em área, então precoM2 é o fator correto.
      final eM2 = unid == 'm²' || unid == 'm2';
      // UNIDADE (chapa, peça…): a quantidade é em unidades; o custo por unidade
      // é precoUnitario. precoM2 é apenas referência (custo/m²) e NÃO deve ser
      // multiplicado pela quantidade de unidades.
      // Modo dimensional (chapa com largura×comprimento usados): precoM2 já é
      // o custo proporcional TOTAL da área consumida (não custo/m² do
      // material), e quantidade é sempre 1. Usar precoUnitario aqui contaria
      // o valor da chapa inteira em vez do retalho realmente usado.
      final preco = m.usouModoDimensional
          ? (pm2 ?? 0.0)
          : (eMetroLinear
              ? ((pu  != null && pu  > 0) ? pu  : (pm2 ?? 0.0))
              : (eM2
                  ? ((pm2 != null && pm2 > 0) ? pm2 : (pu ?? 0.0))
                  : ((pu  != null && pu  > 0) ? pu  : (pm2 ?? 0.0))));
      if (m.tipo == 'ENTRADA') {
        qtdE += m.quantidade;
        valE += m.quantidade * preco;
      } else {
        qtdS += m.quantidade;
        valS += m.quantidade * preco;
      }
    }
    return _TotaisMovimentacao(
      qtdEntrada: qtdE, qtdSaida: qtdS,
      valorEntrada: valE, valorSaida: valS,
    );
  }
}

/// Chips compactos exibidos no card fechado.
class _TotaisResumoMini extends StatelessWidget {
  final _TotaisMovimentacao totais;
  final String? unidade;
  const _TotaisResumoMini({required this.totais, required this.unidade});

  @override
  Widget build(BuildContext context) {
    final unStr      = formatarUnidadeExibicao(unidade);
    final temEntrada = totais.qtdEntrada > 0;
    final temSaida   = totais.qtdSaida   > 0;
    if (!temEntrada && !temSaida) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (temEntrada)
          _TotalChip(
            icon: Icons.arrow_upward,
            cor: AppTheme.success,
            qtd: '${totais.qtdEntradaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
            valor: totais.valorEntradaStr,
          ),
        if (temSaida)
          _TotalChip(
            icon: Icons.arrow_downward,
            cor: AppTheme.error,
            qtd: '${totais.qtdSaidaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
            valor: totais.valorSaidaStr,
          ),
      ],
    );
  }
}

/// Bloco expandido exibido no modal de detalhe do material.
class _TotaisResumoCompleto extends StatelessWidget {
  final List<MovimentacaoModel> movimentacoes;
  final String? unidade;
  const _TotaisResumoCompleto({required this.movimentacoes, required this.unidade});

  @override
  Widget build(BuildContext context) {
    final totais     = _TotaisMovimentacao.calcular(movimentacoes);
    final unStr      = formatarUnidadeExibicao(unidade);
    final temEntrada = totais.qtdEntrada > 0;
    final temSaida   = totais.qtdSaida   > 0;
    if (!temEntrada && !temSaida) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (temEntrada)
            Expanded(
              child: _TotalLinha(
                icon: Icons.arrow_upward,
                cor: AppTheme.success,
                label: 'Entrada total',
                qtd: '${totais.qtdEntradaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
                valor: totais.valorEntradaStr,
              ),
            ),
          if (temEntrada && temSaida)
            Container(
              width: 1,
              height: 36,
              margin: EdgeInsets.symmetric(horizontal: 10),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          if (temSaida)
            Expanded(
              child: _TotalLinha(
                icon: Icons.arrow_downward,
                cor: AppTheme.error,
                label: 'Saída total',
                qtd: '${totais.qtdSaidaStr}${unStr.isNotEmpty ? ' $unStr' : ''}',
                valor: totais.valorSaidaStr,
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final IconData icon;
  final Color cor;
  final String qtd;
  final String valor;
  const _TotalChip({required this.icon, required this.cor, required this.qtd, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: cor),
          const SizedBox(width: 3),
          Text(qtd,    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cor)),
          const SizedBox(width: 3),
          Text(valor,  style: TextStyle(fontSize: 9,  fontWeight: FontWeight.w500, color: cor.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

class _TotalLinha extends StatelessWidget {
  final IconData icon;
  final Color cor;
  final String label;
  final String qtd;
  final String valor;
  const _TotalLinha({required this.icon, required this.cor, required this.label, required this.qtd, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: cor),
        ),
        SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            Text(qtd,   style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cor)),
            Text(valor, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor.withValues(alpha: 0.75))),
          ],
        ),
      ],
    );
  }
}

// ─── Row de movimentação ──────────────────────────────────────────────────────

class _MovimentacaoRow extends StatelessWidget {
  final MovimentacaoModel mov;
  final String? unidade;
  final String Function(DateTime) formatData;
  final String Function(double, String?) formatQtd;
  // null = somente leitura (OS fechada)
  final VoidCallback? onRemove;

  const _MovimentacaoRow({
    required this.mov,
    required this.unidade,
    required this.formatData,
    required this.formatQtd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isEntrada = mov.tipo == 'ENTRADA';
    final cor  = isEntrada ? AppTheme.success : AppTheme.error;
    final icon = isEntrada ? Icons.arrow_upward : Icons.arrow_downward;

    return Container(
      margin: EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: cor),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isEntrada ? 'Entrada' : 'Saída',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      mov.usouModoDimensional
                          ? '${formatQtd(mov.quantidade, unidade)} - (${_fmtDim(mov.comprimentoUsado!)}x${_fmtDim(mov.larguraUsada!)}m)'
                          : formatQtd(mov.quantidade, unidade),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    // Badge de preço desta movimentação
                    Builder(builder: (_) {
                      final pu  = mov.precoUnitario;
                      final pm2 = mov.precoM2;
                      const mlUnits = {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'};
                      final eML = mlUnits.contains(unidade?.toLowerCase().trim() ?? '');
                      final partes = <String>[];
                      if (mov.usouModoDimensional) {
                        // Modo dimensional: precoM2 é o custo TOTAL proporcional
                        // ao retalho usado (não custo por m²), então exibe sem
                        // sufixo "/m²" — e ignora precoUnitario (preço da chapa
                        // inteira), que não corresponde ao valor desta saída.
                        if (pm2 != null && pm2 > 0) {
                          partes.add(_brl6(pm2));
                        }
                      } else if (eML) {
                        // Metro linear: mostra apenas um valor (custo/m linear) com label M/L
                        final val = (pu != null && pu > 0) ? pu : (pm2 != null && pm2 > 0 ? pm2 : null);
                        if (val != null) partes.add('R\$ ${_brl6(val).substring(3)} /m/l');
                      } else {
                        if (pu  != null && pu  > 0) partes.add(_brl6(pu));
                        if (pm2 != null && pm2 > 0) partes.add('R\$ ${_brl6(pm2).substring(3)} /m²');
                      }
                      if (partes.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            partes.join(' · '),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  formatData(mov.criadoEm),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline, fontSize: 11),
                ),
                if (mov.observacao != null &&
                    mov.observacao!.isNotEmpty) ...[
                  SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes,
                          size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          mov.observacao!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Botão remover — oculto quando OS está fechada
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppTheme.error),
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(28, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ).copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              tooltip: 'Remover movimentação',
            )
          else
            const SizedBox(width: 28),
        ],
      ),
    );
  }
}

// ─── Dialog: movimentação de item específico ──────────────────────────────────

class _MovimentacaoItemDialog extends StatefulWidget {
  final String tipo;
  final int materialId;
  final String materialNome;
  final String? unidade;
  final String numeroOS;
  final double? precoUnitario;
  final double? precoM2;

  const _MovimentacaoItemDialog({
    required this.tipo,
    required this.materialId,
    required this.materialNome,
    required this.numeroOS,
    this.unidade,
    this.precoUnitario,
    this.precoM2,
  });

  @override
  State<_MovimentacaoItemDialog> createState() =>
      _MovimentacaoItemDialogState();
}

class _MovimentacaoItemDialogState extends State<_MovimentacaoItemDialog> {
  final _formKey   = GlobalKey<FormState>();
  final _quantCtrl = TextEditingController();
  final _obsCtrl   = TextEditingController();
  bool _enviando   = false;
  String? _erroEstoque;

  @override
  void dispose() {
    _quantCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() => _erroEstoque = null);
    if (!_formKey.currentState!.validate()) return;

    final quant = double.tryParse(_quantCtrl.text.replaceAll(',', '.'));

    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _enviando = true);
    
    // ╔════════════════════════════════════════════════════════════════════╗
    // ║ Usa o numeroOS completo (com sufixo) que veio do context          ║
    // ╚════════════════════════════════════════════════════════════════════╝
    final ok = await provider.registrarMovimentacao(
      materialId:    widget.materialId,
      tipo:          widget.tipo,
      quantidade:    quant!,
      numeroOS:      widget.numeroOS,
      precoUnitario: widget.precoUnitario,
      precoM2:       widget.precoM2,
      observacao:    _obsCtrl.text.trim().isEmpty
          ? null
          : _obsCtrl.text.trim(),
    );
    
    if (!mounted) return;
    setState(() => _enviando = false);
    
    if (ok) {
      provider.selecionarRelacaoOS(widget.numeroOS);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${widget.tipo == 'ENTRADA' ? 'Entrada' : 'Saída'} registrada'),
        backgroundColor:
            widget.tipo == 'ENTRADA' ? AppTheme.success : AppTheme.error,
      ));
    } else {
      final erro = provider.erro ?? 'Erro desconhecido';
      if (erro.toLowerCase().contains('estoque')) {
        setState(() => _erroEstoque = erro);
        _formKey.currentState!.validate();
      } else {
        messenger.showSnackBar(
            SnackBar(content: Text(erro), backgroundColor: AppTheme.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEntrada = widget.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEntrada
                ? Icons.add_circle_outline
                : Icons.remove_circle_outline,
            color: cor,
          ),
          SizedBox(width: 8),
          Text(isEntrada ? 'Registrar Entrada' : 'Registrar Saída'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.materialNome,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 4),
            Text('OS ${widget.numeroOS}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _quantCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantidade'),
              validator: (v) {
                if (_erroEstoque != null) return _erroEstoque;
                final quant =
                    double.tryParse((v ?? '').replaceAll(',', '.'));
                if (quant == null || quant <= 0) {
                  return 'Informe uma quantidade válida';
                }
                return null;
              },
              onChanged: (_) {
                if (_erroEstoque != null) setState(() => _erroEstoque = null);
              },
            ),
            // Exibe o preço que será gravado com a movimentação
            Builder(builder: (_) {
              final pu  = widget.precoUnitario;
              final pm2 = widget.precoM2;

              const mlUD = {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'};
              final eMLDlg = mlUD.contains(widget.unidade?.toLowerCase().trim() ?? '');
              final partes = <String>[];
              if (eMLDlg) {
                final valML = (pu != null && pu > 0) ? pu : (pm2 != null && pm2 > 0 ? pm2 : null);
                if (valML != null) partes.add('m/l: R\$ ${_brl6(valML).substring(3)}');
              } else {
                if (pu != null && pu > 0) {
                  partes.add('Unidade: R\$ ${_brl6(pu).substring(3)}');
                }
                if (pm2 != null && pm2 > 0) {
                  partes.add('M²: R\$ ${_brl6(pm2).substring(3)}');
                }
              }
              if (partes.isEmpty) return SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.price_check, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        partes.join('  ·  '),
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _obsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Observação (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        Tooltip(
          message: 'Cancelar',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Cancelar'),
          ),
        ),
        Tooltip(
          message: isEntrada
              ? 'Confirmar entrada de material'
              : 'Confirmar saída de material',
          child: FilledButton(
            onPressed: _enviando ? null : _confirmar,
            style: FilledButton.styleFrom(backgroundColor: cor).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(isEntrada ? 'Confirmar Entrada' : 'Confirmar Saída'),
          ),
        ),
      ],
    );
  }
}

class _MovimentacaoGlobalDialog extends StatefulWidget {
  final String tipo;
  final String? numeroOSFixo;

  const _MovimentacaoGlobalDialog({required this.tipo}) : numeroOSFixo = null;

  @override
  State<_MovimentacaoGlobalDialog> createState() =>
      _MovimentacaoGlobalDialogState();
}

class _MovimentacaoGlobalDialogState
    extends State<_MovimentacaoGlobalDialog> {
  final _formKey      = GlobalKey<FormState>();
  final _numeroOSCtrl = TextEditingController();
  final List<_ItemMovimentacao> _itensSelecionados = [];
  bool _enviando = false;

  final _nomeCtrl          = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl        = TextEditingController();
  final _comprimentoCtrl   = TextEditingController();
  final _larguraCtrl       = TextEditingController();
  final _espessuraCtrl     = TextEditingController();
  String? _categoriaFiltro;
  List<String> _categorias = [];

  List<MaterialModel> _resultados = [];
  bool _buscando    = false;
  bool _buscouUmaVez = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Adia para depois do build atual: chamar direto aqui faria o
    // notifyListeners() do MaterialProvider disparar ainda dentro do
    // initState (antes de qualquer await real), o que tenta reconstruir
    // widgets enquanto o Flutter ainda está montando a árvore — gerando
    // "setState()/markNeedsBuild() called during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _carregarCategorias();
    });
    if (widget.numeroOSFixo != null) {
      final raw = widget.numeroOSFixo!;
      final candidates = [raw.indexOf('#OC'), raw.indexOf('#S'), raw.indexOf('#E')]
          .where((i) => i > 0)
          .toList();
      candidates.sort();
      _numeroOSCtrl.text = candidates.isEmpty
          ? raw
          : raw.substring(0, candidates.first);
    }
  }

  @override
  void dispose() {
    _numeroOSCtrl.dispose();
    _nomeCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _comprimentoCtrl.dispose();
    _larguraCtrl.dispose();
    _espessuraCtrl.dispose();
    _debounce?.cancel();
    for (final i in _itensSelecionados) {
      i.dispose();
    }
    super.dispose();
  }

  Set<String> get _chavesSelecionadas =>
      _itensSelecionados.map((i) => i.chaveUnica).toSet();

  Future<void> _carregarCategorias() async {
    try {
      await context.read<MaterialProvider>().carregarCategorias();
      if (mounted) {
        setState(() =>
            _categorias = context.read<MaterialProvider>().categorias);
      }
    } catch (_) {}
  }

  void _agendarBusca() {
    _debounce?.cancel();
    final temValor = _nomeCtrl.text.isNotEmpty ||
        _identificadorCtrl.text.isNotEmpty ||
        _medidaCtrl.text.isNotEmpty ||
        _comprimentoCtrl.text.isNotEmpty ||
        _larguraCtrl.text.isNotEmpty ||
        _espessuraCtrl.text.isNotEmpty;
    if (!temValor && _categoriaFiltro == null) {
      setState(() {
        _buscouUmaVez = false;
        _resultados   = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _buscar);
  }

  Future<void> _buscar() async {
    if (!mounted) return;
    setState(() {
      _buscando     = true;
      _buscouUmaVez = true;
    });
    try {
      // Usa buscarParaMovimentacao em vez de carregar() por dois motivos:
      // 1. Não polui o estado global do MaterialProvider (sem notifyListeners).
      // 2. Inclui materiais temporários ativos, que devem aparecer aqui mas
      //    não no catálogo padrão de materiais.
      final lista = await context.read<MaterialProvider>().buscarParaMovimentacao(
        busca:         _nomeCtrl.text.trim(),
        identificador: _identificadorCtrl.text.trim(),
        medida:        _medidaCtrl.text.trim(),
        comprimento:   _comprimentoCtrl.text.trim(),
        largura:       _larguraCtrl.text.trim(),
        espessura:     _espessuraCtrl.text.trim(),
        categoria:     _categoriaFiltro,
      );
      if (mounted) {
        setState(() {
          _resultados = lista; // backend já filtra ativo=true
          _buscando   = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _limparFiltros() {
    _nomeCtrl.clear();
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _comprimentoCtrl.clear();
    _larguraCtrl.clear();
    _espessuraCtrl.clear();
    _debounce?.cancel();
    setState(() {
      _categoriaFiltro = null;
      _buscouUmaVez    = false;
      _resultados      = [];
    });
  }

  void _selecionarMaterial(MaterialModel m) {
    final chave = '${m.id}';
    if (_chavesSelecionadas.contains(chave)) return;
    setState(() {
      _itensSelecionados.add(_ItemMovimentacao(material: m));
    });
  }

  void _removerItem(int index) {
    setState(() {
      _itensSelecionados[index].dispose();
      _itensSelecionados.removeAt(index);
    });
  }

 Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_itensSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um material')),
      );
      return;
    }

    String numeroOS = widget.numeroOSFixo ?? _numeroOSCtrl.text.trim();

    if (widget.numeroOSFixo == null) {
      numeroOS = numeroOS.trim();
    }

    final provider  = context.read<EstoqueProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _enviando = true);
    bool todosOk = true;

    for (final item in _itensSelecionados) {
      final quant = double.parse(item.quantCtrl.text.replaceAll(',', '.'));
      final obs = item.obsCtrl.text.trim().isEmpty
          ? null
          : item.obsCtrl.text.trim();

      double? largUsada;
      double? compUsado;
      if (widget.tipo == 'SAIDA' && item.usarModoDimensional && item.podeInformarDimensao) {
        final l = double.tryParse(item.larguraUsadaCtrl.text.replaceAll(',', '.'));
        final c = double.tryParse(item.alturaUsadaCtrl.text.replaceAll(',', '.'));
        if (l != null && l > 0 && c != null && c > 0) {
          if (l > item.material.largura! || c > item.material.comprimento!) {
            todosOk = false;
            final compMax = item.material.comprimento!;
            final largMax = item.material.largura!;
            String fmtDim(double v) => v == v.truncateToDouble()
                ? v.toStringAsFixed(0)
                : v.toStringAsFixed(2);
            setState(() {
              item.erroEstoque = 'Dimensão usada não pode ultrapassar a da chapa '
                  '(${fmtDim(compMax)}×${fmtDim(largMax)} m)';
            });
            _formKey.currentState!.validate();
            continue;
          }
          largUsada = l;
          compUsado = c;
        }
      }

      final ok = await provider.registrarMovimentacaoSilencioso(
        materialId:       item.material.id,
        tipo:             widget.tipo,
        quantidade:       quant,
        numeroOS:         numeroOS,
        precoUnitario:    item.precoUnitarioSugerido,
        precoM2:          item.precoM2Sugerido,
        observacao:       obs,
        larguraUsada:     largUsada,
        comprimentoUsado: compUsado,
      );
      
      if (!ok) {
        todosOk = false;
        final erro = provider.erro ?? 'Erro desconhecido';
        if (erro.toLowerCase().contains('estoque')) {
          setState(() => item.erroEstoque = erro);
          _formKey.currentState!.validate();
        } else {
          messenger.showSnackBar(
              SnackBar(content: Text(erro), backgroundColor: AppTheme.error));
        }
        break;
      }
    }

    if (todosOk) {
      await provider.carregarRelacoesOS();
    }

    if (!mounted) return;
    setState(() => _enviando = false);

    if (todosOk) {
      final numeroOSDisplay = numeroOS;
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${widget.tipo == 'ENTRADA' ? 'Entrada' : 'Saída'} '
            'registrada para OS $numeroOSDisplay'),
        backgroundColor:
            widget.tipo == 'ENTRADA' ? AppTheme.success : AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEntrada = widget.tipo == 'ENTRADA';
    final cor = isEntrada ? AppTheme.success : AppTheme.error;

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: 1320,
        height: MediaQuery.of(context).size.height * 0.88,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      isEntrada
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                      color: cor,
                    ),
                    SizedBox(width: 8),
                    Text(
                      isEntrada ? 'Nova Entrada' : 'Nova Saída',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 260,
                      child: TextFormField(
                        controller: _numeroOSCtrl,
                        enabled: widget.numeroOSFixo == null,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Número da OS *',
                          prefixText: 'OS ',
                          isDense: true,
                          filled: widget.numeroOSFixo != null,
                          fillColor: widget.numeroOSFixo != null
                              ? AppTheme.primary.withValues(alpha: 0.07)
                              : null,
                          suffixIcon: widget.numeroOSFixo != null
                              ? const Tooltip(
                                  message: 'OS fixada por esta janela',
                                  child: Icon(Icons.lock_outline,
                                      size: 14, color: AppTheme.primary),
                                )
                              : null,
                        ),
                        validator: (v) => (widget.numeroOSFixo == null &&
                                (v == null || v.trim().isEmpty))
                            ? 'Informe o número da OS'
                            : null,
                      ),
                    ),
                    if (widget.numeroOSFixo == null) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Preencher OS como Investimento',
                        child: TextButton.icon(
                          onPressed: () {
                            _numeroOSCtrl.text = 'INVESTIMENTO';
                          },
                          icon: const Icon(Icons.south_west, size: 14),
                          label: const Text('INVESTIMENTO'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ).copyWith(
                            mouseCursor:
                                WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Preencher OS como Empresa',
                        child: TextButton.icon(
                          onPressed: () {
                            _numeroOSCtrl.text = 'EMPRESA';
                          },
                          icon: const Icon(Icons.business, size: 14),
                          label: const Text('EMPRESA'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ).copyWith(
                            mouseCursor:
                                WidgetStateProperty.all(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _nomeCtrl,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: 'Buscar por nome',
                                      prefixIcon: Icon(Icons.search,
                                          color: Theme.of(context).colorScheme.outline, size: 18),
                                      isDense: true,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    inputFormatters: [_UpperCaseFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                SizedBox(
                                  width: 190,
                                  child: _CategoriaFiltroDropdownCE(
                                    categorias: _categorias,
                                    valorSelecionado: _categoriaFiltro,
                                    onSelecionar: (v) {
                                      setState(() => _categoriaFiltro = v);
                                      if (_buscouUmaVez) _buscar();
                                    },
                                  ),
                                ),
                                SizedBox(width: 4),
                                Builder(
                                  builder: (context) {
                                    final temFiltro = _nomeCtrl.text.isNotEmpty ||
                                        _identificadorCtrl.text.isNotEmpty ||
                                        _medidaCtrl.text.isNotEmpty ||
                                        _comprimentoCtrl.text.isNotEmpty ||
                                        _larguraCtrl.text.isNotEmpty ||
                                        _espessuraCtrl.text.isNotEmpty ||
                                        _categoriaFiltro != null;
                                    return IconButton.outlined(
                                      tooltip: 'Limpar filtros',
                                      icon: Icon(Icons.filter_alt_off,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                                      onPressed: temFiltro ? _limparFiltros : null,
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
                            const SizedBox(height: 8),

                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _identificadorCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Identificador',
                                      prefixIcon: Icon(Icons.qr_code,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    inputFormatters: [_UpperCaseFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _medidaCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Medida',
                                      prefixIcon: Icon(Icons.straighten,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    inputFormatters: [_MedidaEspessuraFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _comprimentoCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      hintText: 'Comprimento',
                                      suffixText: 'm',
                                      prefixIcon: Icon(Icons.height,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    inputFormatters: [_EspessuraFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _larguraCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      hintText: 'Largura',
                                      suffixText: 'm',
                                      prefixIcon: Icon(Icons.width_normal,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    inputFormatters: [_EspessuraFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _espessuraCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Espessura',
                                      suffixText: 'mm',
                                      prefixIcon: Icon(Icons.layers,
                                          color: Theme.of(context).colorScheme.outline, size: 16),
                                      isDense: true,
                                    ),
                                    inputFormatters: [_EspessuraFormatter()],
                                    onChanged: (_) => _agendarBusca(),
                                    onSubmitted: (_) => _buscar(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            Expanded(
                              child: _buscando
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                          color: AppTheme.primary,
                                          strokeWidth: 2),
                                    )
                                  : !_buscouUmaVez
                                      ? Center(
                                          child: Text(
                                            'Digite para buscar materiais',
                                            style: TextStyle(
                                                color: Theme.of(context).colorScheme.outline,
                                                fontSize: 13),
                                          ),
                                        )
                                      : _resultados.isEmpty
                                          ? Center(
                                              child: Text(
                                                'Nenhum material encontrado',
                                                style: TextStyle(
                                                    color: Theme.of(context).colorScheme.outline,
                                                    fontSize: 13),
                                              ),
                                            )
                                          : Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Theme.of(context).colorScheme.outlineVariant),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child:
                                                    Builder(builder: (context) {
                                                  final itens = <Widget>[];
                                                  for (int ri = 0;
                                                      ri < _resultados.length;
                                                      ri++) {
                                                    final m = _resultados[ri];
                                                    if (ri > 0) {
                                                      itens.add(const Divider(
                                                          height: 0,
                                                          thickness: 0.5,
                                                          color: AppTheme
                                                              .divider));
                                                    }
                                                    final jaSelecionado =
                                                        _chavesSelecionadas
                                                            .contains(
                                                                '${m.id}');
                                                    itens.add(
                                                        _MaterialResultadoTile(
                                                      material: m,
                                                      selecionado:
                                                          jaSelecionado,
                                                      onTap: jaSelecionado
                                                          ? () {}
                                                          : () =>
                                                              _selecionarMaterial(
                                                                  m),
                                                    ));
                                                  }
                                                  return ListView(
                                                    children: itens,
                                                  );
                                                }),
                                              ),
                                            ),
                                        ),
                          ],
                        ),
                      ),

                      const VerticalDivider(width: 24, thickness: 1),

                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 16, color: AppTheme.primary),
                                SizedBox(width: 6),
                                Text(
                                  'Selecionados (${_itensSelecionados.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: AppTheme.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            Expanded(
                              child: _itensSelecionados.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.inventory_2_outlined,
                                              size: 36,
                                              color: Theme.of(context).colorScheme.outline
                                                  .withValues(alpha: 0.4)),
                                          SizedBox(height: 10),
                                          Text(
                                            'Nenhum material\nadicionado ainda',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: Theme.of(context).colorScheme.outline,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _itensSelecionados.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (_, i) {
                                        final item = _itensSelecionados[i];
                                        return _ItemSelecionadoCard(
                                          key: ValueKey(item.chaveUnica),
                                          item: item,
                                          tipo: widget.tipo,
                                          onRemover: () => _removerItem(i),
                                        );
                                      },
                                    ),
                            ),

                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Tooltip(
                                  message: 'Cancelar',
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    style: TextButton.styleFrom().copyWith(
                                      mouseCursor: WidgetStateProperty.all(
                                          SystemMouseCursors.click),
                                    ),
                                    child: const Text('Cancelar'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: isEntrada
                                      ? 'Confirmar entrada de materiais'
                                      : 'Confirmar saída de materiais',
                                  child: FilledButton(
                                    onPressed: _enviando ? null : _confirmar,
                                    style: FilledButton.styleFrom(
                                            backgroundColor: cor)
                                        .copyWith(
                                      mouseCursor: WidgetStateProperty.all(
                                          SystemMouseCursors.click),
                                    ),
                                    child: _enviando
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : Text(isEntrada
                                            ? 'Confirmar Entrada'
                                            : 'Confirmar Saída'),
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}

// Alias público — permite importar via `show MaterialFormDialog` em outras páginas.
// ignore: camel_case_types
typedef MaterialFormDialog = _CadastroMaterialDialog;

class _CadastroMaterialDialog extends StatefulWidget {
  const _CadastroMaterialDialog();

  @override
  State<_CadastroMaterialDialog> createState() => _CadastroMaterialDialogState();
}

class _CadastroMaterialDialogState extends State<_CadastroMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;
  String? _erroDialog;

  // ── Modo Retalho ──────────────────────────────────────────────────────
  bool _modoRetalho = false;
  bool _hoverRetalho = false;

  // ── Detecção de possível material duplicado ───────────────────────────
  Timer? _debounceDuplicata;
  bool _verificandoDuplicata = false;
  List<_PossivelDuplicataCE> _possiveisDuplicatas = [];

  late final TextEditingController _nome;
  late final TextEditingController _identificador;
  String? _unidade;
  late final _NotifiableTextEditingController _categoria;
  final FocusNode _categoriaFocusNode = FocusNode();
  late final TextEditingController _medida;
  late final TextEditingController _espessura;
  late final TextEditingController _largura;
  late final TextEditingController _comprimento;
  late final TextEditingController _estoqueMinimo;
  late final TextEditingController _custoCtrl;

  /// COMPRAS não pode definir o estoque mínimo no cadastro — essa definição
  /// fica a cargo de quem faz a entrada real de estoque (Controle de
  /// Estoque / OS), garantindo rastreabilidade. Mesma regra usada no
  /// cadastro de materiais em Estoque.
  bool get _bloquearEstoqueMinimo =>
      context.watch<UsuarioProvider>().usuarioLogado?.role == 'COMPRAS';

  /// Versão `context.read` de [_bloquearEstoqueMinimo], para uso fora do
  /// build (ex.: dentro de `_salvar`).
  bool get _bloquearEstoqueMinimoAtual =>
      context.read<UsuarioProvider>().usuarioLogado?.role == 'COMPRAS';

  @override
  void initState() {
    super.initState();
    _nome          = TextEditingController();
    _identificador = TextEditingController();
    _categoria     = _NotifiableTextEditingController();
    _categoriaFocusNode.addListener(() {
      if (_categoriaFocusNode.hasFocus) {
        _categoria.notify();
      }
    });
    _medida        = TextEditingController();
    _espessura     = TextEditingController();
    _largura       = TextEditingController();
    _comprimento   = TextEditingController();
    _estoqueMinimo = TextEditingController(text: '0');
    _custoCtrl     = TextEditingController();

    // Campos que entram na comparação de duplicidade: qualquer alteração
    // reagenda a verificação (debounced).
    for (final c in [_nome, _identificador, _medida, _espessura, _largura, _comprimento]) {
      c.addListener(_agendarVerificacaoDuplicata);
    }
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
        _estoqueMinimo.text,
        _custoCtrl.text,
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
    if (!_temAlteracoesNaoSalvas) return true;

    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Você preencheu dados deste material que ainda não foram salvos. '
          'O que deseja fazer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'continuar'),
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Continuar cadastrando'),
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
            child: const Text('Cadastrar'),
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
        // a operação for concluída com sucesso; se falhar, o diálogo
        // permanece aberto para o usuário corrigir/tentar de novo.
        await _salvar();
        return false;
      case 'continuar':
      default:
        return false;
    }
  }

  /// Tenta fechar o diálogo, passando pela confirmação de alterações não
  /// salvas quando necessário. Usado pelo botão "X", pelo botão "Cancelar"
  /// e pelo PopScope (Esc / clique fora / botão voltar).
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
    _debounceDuplicata?.cancel();
    _categoriaFocusNode.dispose();
    for (final c in [
      _nome, _identificador, _categoria, _medida, _espessura,
      _largura, _comprimento, _estoqueMinimo, _custoCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _agendarVerificacaoDuplicata() {
    _debounceDuplicata?.cancel();
    _debounceDuplicata = Timer(const Duration(milliseconds: 450), _verificarDuplicatas);
  }

  Future<void> _verificarDuplicatas() async {
    if (!mounted) return;
    final nomeNorm = _normalizarTextoComparacaoCE(_nome.text);

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
    final candidatos = await provider.buscarSugestoes(_nome.text.trim(), limite: 30);
    if (!mounted) return;

    final identificadorNorm = _normalizarTextoComparacaoCE(_identificador.text);
    final medidaNorm        = _normalizarTextoComparacaoCE(_medida.text);
    final espessuraNorm     = _normalizarTextoComparacaoCE(_espessura.text);

    // Dimensões digitadas: usa os campos numéricos Comprimento/Largura/
    // Espessura como fonte principal e, quando algum deles estiver vazio,
    // cai para o que der pra extrair do texto livre "medida" (que pode
    // trazer tudo junto, em qualquer grafia: com ou sem "m"/"mm", com ou
    // sem casas decimais, com ou sem um terceiro "x" pra espessura).
    final medidaDigitadaExtraida = _extrairDimensoesMedidaCE(_medida.text);
    final comprimentoDigitado = double.tryParse(_comprimento.text.trim().replaceAll(',', '.'))
        ?? medidaDigitadaExtraida.comprimento;
    final larguraDigitada = double.tryParse(_largura.text.trim().replaceAll(',', '.'))
        ?? medidaDigitadaExtraida.largura;
    final espessuraDigitadaNum = _extrairNumeroDeTextoCE(_espessura.text)
        ?? medidaDigitadaExtraida.espessura;

    bool dimensaoBate(double? a, double? b) {
      if (a == null || b == null) return false;
      return (a - b).abs() < 0.001;
    }

    final encontrados = <_PossivelDuplicataCE>[];
    for (final m in candidatos) {
      final mNomeNorm          = _normalizarTextoComparacaoCE(m.nome);
      final mIdentificadorNorm = _normalizarTextoComparacaoCE(m.identificador);
      final mMedidaNorm        = _normalizarTextoComparacaoCE(m.medida);
      final mEspessuraNorm     = _normalizarTextoComparacaoCE(m.espessura);

      // Mesma lógica de fallback do lado do material cadastrado: prioriza os
      // campos numéricos e, na falta deles, extrai do texto "medida" salvo.
      final mMedidaExtraida = _extrairDimensoesMedidaCE(m.medida);
      final mComprimentoFinal = m.comprimento ?? mMedidaExtraida.comprimento;
      final mLarguraFinal     = m.largura ?? mMedidaExtraida.largura;
      final mEspessuraFinal   = _extrairNumeroDeTextoCE(m.espessura) ?? mMedidaExtraida.espessura;

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

      final similaridadeNome = _similaridadeTextoCE(nomeNorm, mNomeNorm);
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

      // "Similar": nome muito parecido (>=72%), mesmo identificador com
      // alguma semelhança (evita falso-positivo de identificadores genéricos
      // reutilizados em materiais bem diferentes), ou um nome é prefixo/
      // trecho do outro (digitação em andamento).
      final similar = !exata &&
          (similaridadeNome >= 0.72 ||
              (mesmoIdentificador && similaridadeNome >= 0.4) ||
              contido);

      if (exata || similar) {
        encontrados.add(_PossivelDuplicataCE(
          material: m,
          exata: exata,
          similaridade: similaridadeNome,
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

  void _ativarModoRetalho() {
    setState(() {
      _modoRetalho = true;
      _identificador.text = 'RETALHO';
      _unidade = 'M²';
      _medida.clear();
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
    });
  }

  Future<void> _salvar() async {
    // Trava o botão IMEDIATAMENTE, antes de qualquer "await" — inclusive
    // antes da validação e da verificação de duplicidade. Isso fecha a
    // janela em que um duplo clique (ou duplo toque no mobile) disparava
    // _salvar() duas vezes antes que _salvando virasse true, resultando
    // em dois materiais idênticos cadastrados a partir de um único clique.
    if (_salvando) return;
    setState(() { _salvando = true; });

    if (!_formKey.currentState!.validate()) {
      setState(() => _salvando = false);
      return;
    }
    if (!_modoRetalho && (_unidade == null || _unidade!.isEmpty)) {
      setState(() {
        _salvando = false;
        _erroDialog = 'Selecione uma unidade antes de salvar.';
      });
      return;
    }
    // Garante que a verificação de duplicidade mais recente já foi
    // concluída antes de decidir se pode salvar (evita salvar durante o
    // debounce, quando _possiveisDuplicatas ainda reflete o texto anterior).
    _debounceDuplicata?.cancel();
    await _verificarDuplicatas();
    if (!mounted) return;
    if (_possiveisDuplicatas.any((d) => d.exata)) {
      setState(() {
        _salvando = false;
        _erroDialog = 'Já existe um material idêntico cadastrado. '
            'Ajuste a medida/espessura ou edite o material existente.';
      });
      return;
    }
    setState(() { _erroDialog = null; });

    final custoValor = _custoCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_custoCtrl.text.trim().replaceAll(',', '.'));

    final dados = {
      'nome':          _nome.text.trim(),
      'identificador': _identificador.text.trim().isEmpty ? null : _identificador.text.trim(),
      'unidade':       (_unidade == null || _unidade!.isEmpty) ? null : _unidade,
      'categoria':     _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
      'medida':        _modoRetalho ? null : (_medida.text.trim().isEmpty ? null : _medida.text.trim()),
      'espessura':     _espessura.text.trim().isEmpty ? null : _espessura.text.trim(),
      'largura':       _modoRetalho ? null : (_largura.text.trim().isEmpty ? null : double.tryParse(_largura.text.trim())),
      'comprimento':   _modoRetalho ? null : (_comprimento.text.trim().isEmpty ? null : double.tryParse(_comprimento.text.trim())),
      'quantidade':    0.0,
      'estoqueMinimo': (_modoRetalho || _bloquearEstoqueMinimoAtual) ? 0.0 : (double.tryParse(_estoqueMinimo.text) ?? 0),
      'estoqueConfirmado': false,
      if (_modoRetalho) 'ultimoValorPagoM2': custoValor
      else 'ultimoValorPago': custoValor,
    };

    final provider = context.read<MaterialProvider>();
    final ok = await provider.criar(dados);

    if (!mounted) return;
    setState(() => _salvando = false);

    if (ok) {
      Navigator.of(context, rootNavigator: true).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Material cadastrado. Use a página de Controle de Estoque para registrar a entrada.'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      setState(() => _erroDialog = provider.erro ?? 'Erro ao salvar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Intercepta qualquer tentativa de fechar o diálogo que não passe pelos
    // botões (X/Cancelar), como a tecla Esc ou o gesto/botão "voltar":
    // sempre barra o pop automático e decide via _confirmarFechamento se
    // deve realmente fechar.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _tentarFechar();
      },
      child: Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: SizedBox(
        width: 560,
        height: 680,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Cadastrar Material',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
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
                  const Spacer(),
                  IconButton(
                    onPressed: _salvando ? null : _tentarFechar,
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    style: IconButton.styleFrom().copyWith(
                      mouseCursor:
                          WidgetStateProperty.all(SystemMouseCursors.click),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 0),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                child: Form(
                  key: _formKey,
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
                      TextFormField(
                        controller: _nome,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Nome *'),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                        onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Nome é obrigatório' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _identificador,
                        readOnly: _modoRetalho,
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
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: LayoutBuilder(
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: _modoRetalho
                              ? InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Unidade',
                                    suffixIcon: const Tooltip(
                                      message: 'Bloqueado no modo Retalho',
                                      child: Icon(Icons.lock_outline, size: 16),
                                    ),
                                  ),
                                  child: const Text('M²', style: TextStyle(fontSize: 14)),
                                )
                              : MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _unidade,
                                    decoration: const InputDecoration(labelText: 'Unidade *'),
                                    hint: const Text('Selecione'),
                                    icon: const Icon(Icons.arrow_drop_down),
                                    mouseCursor: SystemMouseCursors.click,
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
                                    onChanged: (v) => setState(() => _unidade = v),
                                  ),
                                ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      if (_unidade != 'ML' && _unidade != 'G') ...[
                      TextFormField(
                        controller: _medida,
                        readOnly: _modoRetalho,
                        decoration: InputDecoration(
                          labelText: 'Medida',
                          suffixIcon: _modoRetalho
                              ? const Tooltip(
                                  message: 'Bloqueado no modo Retalho',
                                  child: Icon(Icons.lock_outline, size: 16),
                                )
                              : null,
                        ),
                        textCapitalization: TextCapitalization.none,
                        inputFormatters: [_MedidaEspessuraFormatter()],
                        onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                      ),
                      ], // end if not ML/G (medida)
                      if (_verificandoDuplicata || _possiveisDuplicatas.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _AvisoPossivelDuplicataCE(
                          carregando: _verificandoDuplicata,
                          duplicatas: _possiveisDuplicatas,
                        ),
                      ],
                      if (_unidade != 'ML' && _unidade != 'G') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _comprimento,
                            readOnly: _modoRetalho,
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _largura,
                            readOnly: _modoRetalho,
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _espessura,
                            decoration: const InputDecoration(
                              labelText: 'Espessura',
                              suffixText: 'mm',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [_EspessuraFormatter()],
                            onChanged: (_) { if (_erroDialog != null) setState(() => _erroDialog = null); },
                          ),
                        ),
                      ]),
                      ], // end if not ML/G
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: _bloquearEstoqueMinimo
                              ? const _EstoqueMinimoBloqueadoInfo()
                              : TextFormField(
                            controller: _estoqueMinimo,
                            readOnly: _modoRetalho,
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _custoCtrl,
                            decoration: InputDecoration(
                              labelText: _modoRetalho
                                  ? 'Custo m² (última compra)'
                                  : 'Custo (última compra)',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [_DecimalInputFormatter()],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                'A entrada de quantidade inicial deve ser feita na página de Controle de Estoque, vinculada a uma OS.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Cancelar cadastro',
                    child: TextButton(
                      onPressed: _salvando ? null : _tentarFechar,
                      style: TextButton.styleFrom().copyWith(
                        mouseCursor:
                            WidgetStateProperty.all(SystemMouseCursors.click),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Criar material',
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
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
                          : const Text('Criar'),
                    ),
                  ),
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

// ─── Modelo de item de movimentação ──────────────────────────────────────────

// ═════════════════════════════════════════════════════════════════════════
// Diálogo: Saída para Produção (transferência de estoque)
// ═════════════════════════════════════════════════════════════════════════
//
// Move uma quantidade de um material do estoque normal para o estoque de
// produção (EstoqueProducao). Não vincula a uma OS — a OS só é informada
// depois, quando a produção der baixa a partir do estoque de produção.
class _TransferenciaProducaoDialog extends StatefulWidget {
  const _TransferenciaProducaoDialog();

  @override
  State<_TransferenciaProducaoDialog> createState() =>
      _TransferenciaProducaoDialogState();
}

class _TransferenciaProducaoDialogState
    extends State<_TransferenciaProducaoDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Filtros de busca ──────────────────────────────────────────────────
  final _nomeCtrl         = TextEditingController();
  final _identificadorCtrl = TextEditingController();
  final _medidaCtrl       = TextEditingController();
  final _comprimentoCtrl  = TextEditingController();
  final _larguraCtrl      = TextEditingController();
  final _espessuraCtrl    = TextEditingController();
  Timer? _debounce;
  bool _buscando = false;
  bool _buscouUmaVez = false;
  List<MaterialModel> _resultados = [];

  // ── Material selecionado e campos do formulário ───────────────────────
  MaterialModel? _selecionado;
  final _quantCtrl            = TextEditingController();
  final _obsCtrl              = TextEditingController();
  // Linha de produção de destino ('1' ou '2'). Obrigatório escolher antes
  // de confirmar — não há mais um "estoque de produção" único.
  String? _producaoSelecionada;

  bool _enviando = false;
  String? _erro;

  // ── Card "Pendentes de confirmação" ────────────────────────────────────
  int? _resolvendoPendenteId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstoqueProducaoProvider>().carregarPendentes();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nomeCtrl.dispose();
    _identificadorCtrl.dispose();
    _medidaCtrl.dispose();
    _comprimentoCtrl.dispose();
    _larguraCtrl.dispose();
    _espessuraCtrl.dispose();
    _quantCtrl.dispose();
    _obsCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _confirmarPendente(EntradaPendenteModel p) async {
    setState(() => _resolvendoPendenteId = p.id);
    final provider  = context.read<EstoqueProducaoProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.confirmarPendente(p.id);
    if (!mounted) return;
    setState(() => _resolvendoPendenteId = null);
    if (ok) {
      messenger.showSnackBar(SnackBar(
        content: Text('Entrada de ${p.materialNome} confirmada e adicionada ao estoque'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(provider.erro ?? 'Erro ao confirmar entrada'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  bool get _temFiltroAtivo =>
      _identificadorCtrl.text.trim().isNotEmpty ||
      _medidaCtrl.text.trim().isNotEmpty ||
      _comprimentoCtrl.text.trim().isNotEmpty ||
      _larguraCtrl.text.trim().isNotEmpty ||
      _espessuraCtrl.text.trim().isNotEmpty;

  void _agendarBusca() {
    _debounce?.cancel();
    final temQualquerFiltro = _nomeCtrl.text.trim().isNotEmpty ||
        _identificadorCtrl.text.trim().isNotEmpty ||
        _medidaCtrl.text.trim().isNotEmpty ||
        _comprimentoCtrl.text.trim().isNotEmpty ||
        _larguraCtrl.text.trim().isNotEmpty ||
        _espessuraCtrl.text.trim().isNotEmpty;
    if (!temQualquerFiltro) {
      setState(() {
        _buscouUmaVez = false;
        _resultados = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _buscar);
  }

  Future<void> _buscar() async {
    if (!mounted) return;
    setState(() {
      _buscando = true;
      _buscouUmaVez = true;
    });
    try {
      final lista = await context.read<MaterialProvider>().buscarParaMovimentacao(
        busca:         _nomeCtrl.text.trim(),
        identificador: _identificadorCtrl.text.trim(),
        medida:        _medidaCtrl.text.trim(),
        comprimento:   _comprimentoCtrl.text.trim(),
        largura:       _larguraCtrl.text.trim(),
        espessura:     _espessuraCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _resultados = lista;
          _buscando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _limparFiltros() {
    _identificadorCtrl.clear();
    _medidaCtrl.clear();
    _comprimentoCtrl.clear();
    _larguraCtrl.clear();
    _espessuraCtrl.clear();
    _agendarBusca();
  }

  void _selecionar(MaterialModel m) {
    setState(() {
      _selecionado = m;
      _resultados = [];
      _erro = null;
    });
  }

  Future<void> _confirmar() async {
    final material = _selecionado;
    if (material == null) {
      setState(() => _erro = 'Selecione um material');
      return;
    }
    final qtd = double.tryParse(_quantCtrl.text.replaceAll(',', '.'));
    if (qtd == null || qtd <= 0) {
      setState(() => _erro = 'Informe uma quantidade válida');
      return;
    }
    final producao = _producaoSelecionada;
    if (producao == null) {
      setState(() => _erro = 'Selecione para qual produção transferir');
      return;
    }

    setState(() { _enviando = true; _erro = null; });

    final provider  = context.read<EstoqueProducaoProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final ok = await provider.transferir(
      materialId:       material.id,
      quantidade:       qtd,
      producao:         producao,
      observacao:       _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (ok) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
          '${qtd.toStringAsFixed(qtd == qtd.truncateToDouble() ? 0 : 3)} '
          '${formatarUnidadeExibicao(material.unidade)} de ${material.nome} transferido(s) para a produção $producao',
        ),
        backgroundColor: AppTheme.success,
      ));
    } else {
      setState(() => _erro = provider.erro ?? 'Erro ao transferir material');
    }
  }

  Widget _buildAbaSaida(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move uma quantidade do estoque para a produção 1 ou produção 2. '
                'Não é necessário informar OS agora.',
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              // ── Busca / seleção de material ───────────────────────────
              if (_selecionado == null) ...[
                // Busca por nome
                TextField(
                  controller: _nomeCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar material por nome',
                    prefixIcon: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.outline),
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperCaseFormatter()],
                  onChanged: (_) { _agendarBusca(); setState(() {}); },
                  onSubmitted: (_) => _buscar(),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _identificadorCtrl,
                        decoration: InputDecoration(
                          hintText:   'Identificador',
                          prefixIcon: Icon(Icons.qr_code,
                              color: Theme.of(context).colorScheme.outline, size: 18),
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_UpperCaseFormatter()],
                        onChanged: (_) { _agendarBusca(); setState(() {}); },
                        onSubmitted: (_) => _buscar(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _medidaCtrl,
                        decoration: InputDecoration(
                          hintText:   'Medida',
                          prefixIcon: Icon(Icons.straighten,
                              color: Theme.of(context).colorScheme.outline, size: 18),
                          isDense: true,
                        ),
                        inputFormatters: [_MedidaEspessuraFormatter()],
                        onChanged: (_) { _agendarBusca(); setState(() {}); },
                        onSubmitted: (_) => _buscar(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comprimentoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText:   'Comprimento',
                          suffixText: 'm',
                          prefixIcon: Icon(Icons.height,
                              color: Theme.of(context).colorScheme.outline, size: 18),
                          isDense: true,
                        ),
                        inputFormatters: [_EspessuraFormatter()],
                        onChanged: (_) { _agendarBusca(); setState(() {}); },
                        onSubmitted: (_) => _buscar(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _larguraCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText:   'Largura',
                          suffixText: 'm',
                          prefixIcon: Icon(Icons.width_normal,
                              color: Theme.of(context).colorScheme.outline, size: 18),
                          isDense: true,
                        ),
                        inputFormatters: [_EspessuraFormatter()],
                        onChanged: (_) { _agendarBusca(); setState(() {}); },
                        onSubmitted: (_) => _buscar(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _espessuraCtrl,
                        decoration: InputDecoration(
                          hintText:   'Espessura',
                          suffixText: 'mm',
                          prefixIcon: Icon(Icons.layers,
                              color: Theme.of(context).colorScheme.outline, size: 18),
                          isDense: true,
                        ),
                        inputFormatters: [_EspessuraFormatter()],
                        onChanged: (_) { _agendarBusca(); setState(() {}); },
                        onSubmitted: (_) => _buscar(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Lista de resultados ───────────────────────────────
                SizedBox(
                  height: 220,
                  child: _buscando
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                      : !_buscouUmaVez
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search, size: 32, color: Theme.of(context).colorScheme.outlineVariant),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Digite para buscar materiais',
                                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                                  ),
                                  Text(
                                    'Use os filtros avançados para refinar por identificador, medida ou espessura',
                                    style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 11),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : _resultados.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off, size: 32, color: Theme.of(context).colorScheme.outlineVariant),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Nenhum material encontrado',
                                        style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                                      ),
                                      if (_temFiltroAtivo)
                                        TextButton(
                                          onPressed: () { _limparFiltros(); setState(() {}); },
                                          style: TextButton.styleFrom().copyWith(
                                            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                                          ),
                                          child: const Text('Limpar filtros avançados', style: TextStyle(fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListView.separated(
                                    itemCount: _resultados.length,
                                    separatorBuilder: (_, __) => const Divider(height: 0, thickness: 0.5),
                                    itemBuilder: (_, i) {
                                      final m = _resultados[i];
                                      final medidaFmt = formatarMedidaOuDimensoes(
                                        medida:      m.medida,
                                        largura:     m.largura,
                                        comprimento: m.comprimento,
                                      );
                                      final detalhes = [
                                        if (m.identificador != null && m.identificador!.isNotEmpty) m.identificador!,
                                        if (medidaFmt != null) medidaFmt,
                                        if (formatarEspessuraComSufixo(m.espessura) != null) formatarEspessuraComSufixo(m.espessura)!,
                                      ].join(' • ');
                                      final qtdStr = formatarQuantidade(m.quantidade);
                                      final corQtd = m.quantidade <= 0
                                          ? AppTheme.error
                                          : Theme.of(context).colorScheme.onSurfaceVariant;
                                      return ListTile(
                                        dense: true,
                                        title: Text(m.nome, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                        subtitle: detalhes.isEmpty ? null : Text(detalhes, style: const TextStyle(fontSize: 11)),
                                        trailing: Text(
                                          '$qtdStr ${formatarUnidadeExibicao(m.unidade)}',
                                          style: TextStyle(fontSize: 12, color: corQtd, fontWeight: FontWeight.w500),
                                        ),
                                        onTap: () => _selecionar(m),
                                      );
                                    },
                                  ),
                                ),
                ),
              ] else ...[
                // ── Material selecionado ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selecionado!.nome,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(
                              [
                                'Disponível: ${formatarQuantidade(_selecionado!.quantidade)} ${formatarUnidadeExibicao(_selecionado!.unidade)}',
                                if (_selecionado!.identificador != null && _selecionado!.identificador!.isNotEmpty)
                                  _selecionado!.identificador!,
                                if (formatarMedidaOuDimensoes(
                                      medida:      _selecionado!.medida,
                                      largura:     _selecionado!.largura,
                                      comprimento: _selecionado!.comprimento,
                                    ) !=
                                    null)
                                  formatarMedidaOuDimensoes(
                                    medida:      _selecionado!.medida,
                                    largura:     _selecionado!.largura,
                                    comprimento: _selecionado!.comprimento,
                                  )!,
                                if (formatarEspessuraComSufixo(_selecionado!.espessura) != null)
                                  formatarEspessuraComSufixo(_selecionado!.espessura)!,
                              ].join(' • '),
                              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Trocar material',
                        onPressed: () => setState(() {
                          _selecionado = null;
                          _nomeCtrl.clear();
                        }),
                        style: IconButton.styleFrom().copyWith(
                          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _quantCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_DecimalInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Quantidade *',
                    suffixText: formatarUnidadeExibicao(_selecionado!.unidade),
                    isDense: true,
                  ),
                ),

                const SizedBox(height: 10),
                TextField(
                  controller: _obsCtrl,
                  decoration: const InputDecoration(labelText: 'Observação (opcional)', isDense: true),
                ),

                const SizedBox(height: 14),
                Text(
                  'Transferir para *',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _CartaoProducaoSelecionavel(
                        label: 'Produção 1',
                        selecionado: _producaoSelecionada == '1',
                        onTap: () => setState(() => _producaoSelecionada = '1'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CartaoProducaoSelecionavel(
                        label: 'Produção 2',
                        selecionado: _producaoSelecionada == '2',
                        onTap: () => setState(() => _producaoSelecionada = '2'),
                      ),
                    ),
                  ],
                ),
              ],

              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: const TextStyle(color: AppTheme.error, fontSize: 12.5)),
              ],
            ],
      ),
    );
  }

  Widget _buildAbaPendentes(BuildContext context) {
    final provider = context.watch<EstoqueProducaoProvider>();
    final pendentes = provider.pendentes;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Retalhos gerados por baixas e devoluções aguardando confirmação antes de '
            'entrarem no estoque padrão.',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 380,
            child: provider.carregandoPendentes
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                : pendentes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined, size: 32, color: Theme.of(context).colorScheme.outlineVariant),
                            const SizedBox(height: 8),
                            Text(
                              'Nenhuma entrada aguardando confirmação',
                              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: pendentes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = pendentes[i];
                          final resolvendo = _resolvendoPendenteId == p.id;
                          final corTipo = p.ehRetalho ? AppTheme.primary : AppTheme.warning;

                          final medidaFmt = formatarMedidaOuDimensoes(
                            medida:      p.materialMedida,
                            largura:     p.materialLargura,
                            comprimento: p.materialComprimento,
                          );
                          final espessuraFmt = formatarEspessuraComSufixo(p.materialEspessura);
                          final detalhes = [
                            if (medidaFmt != null) medidaFmt,
                            if (espessuraFmt != null) espessuraFmt,
                          ].join(' • ');

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: corTipo.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: corTipo.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  p.ehRetalho ? Icons.content_cut : Icons.undo,
                                  size: 16,
                                  color: corTipo,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                if (p.materialIdentificador != null && p.materialIdentificador!.isNotEmpty) ...[
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: corTipo.withValues(alpha: 0.14),
                                                      borderRadius: BorderRadius.circular(5),
                                                    ),
                                                    child: Text(
                                                      p.materialIdentificador!,
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: corTipo,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                ],
                                                Flexible(
                                                  child: Text(
                                                    p.materialNome,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${formatarQuantidade(p.quantidade)} ${formatarUnidadeExibicao(p.materialUnidade)}',
                                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: corTipo),
                                          ),
                                        ],
                                      ),
                                      if (detalhes.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          detalhes,
                                          style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          p.descricaoTipo,
                                          if (p.numeroOS != null && p.numeroOS!.isNotEmpty) 'OS ${p.numeroOS}',
                                        ].join(' • '),
                                        style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                      if (p.usuarioNome != null && p.usuarioNome!.isNotEmpty)
                                        Text(
                                          p.usuarioNome!,
                                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (resolvendo)
                                  const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                                  )
                                else
                                  FilledButton(
                                    onPressed: () => _confirmarPendente(p),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.success,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ).copyWith(
                                      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                                    ),
                                    child: const Text('Confirmar', style: TextStyle(fontSize: 12.5)),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPendentes = context.watch<EstoqueProducaoProvider>().totalPendentes;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        // Limita a altura do diálogo ao espaço disponível na tela (descontando
        // o insetPadding acima). Antes, a área das abas tinha altura FIXA
        // (SizedBox(height: 560)), que não se adaptava a telas/janelas menores.
        // Em resoluções baixas, cabeçalho + 560 + rodapé ultrapassava a altura
        // da janela e o rodapé com "Confirmar Transferência" era empurrado
        // para fora (overflow), ficando inacessível.
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: MediaQuery.of(context).size.height - 48,
        ),
        child: SizedBox(
          width: 880,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho ─────────────────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.factory_outlined, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Text('Saída para Produção', style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  labelColor: AppTheme.warning,
                  indicatorColor: AppTheme.warning,
                  tabs: [
                    const Tab(text: 'Saída'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Pendentes de confirmação'),
                          if (totalPendentes > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.error,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$totalPendentes',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // Antes: SizedBox(height: 560, ...) — altura fixa que causava o
                // overflow em telas menores. Agora: Flexible dentro da Column
                // (mainAxisSize.min), então essa área ocupa o espaço restante
                // até o limite do ConstrainedBox acima, sem nunca empurrar o
                // rodapé (Cancelar / Confirmar Transferência) para fora da
                // área visível. Se o conteúdo interno não couber, ele rola
                // (SingleChildScrollView já usado em cada aba).
                Flexible(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      SingleChildScrollView(child: _buildAbaSaida(context)),
                      SingleChildScrollView(child: _buildAbaPendentes(context)),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    if (_tabController.index != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom().copyWith(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: (_selecionado == null || _producaoSelecionada == null || _enviando) ? null : _confirmar,
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning).copyWith(
                              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                            ),
                            child: _enviando
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Confirmar Transferência'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão selecionável simples usado para escolher a linha de produção
/// ('1' ou '2') de destino no diálogo de transferência.
class _CartaoProducaoSelecionavel extends StatelessWidget {
  final String label;
  final bool selecionado;
  final VoidCallback onTap;

  const _CartaoProducaoSelecionavel({
    required this.label,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selecionado
              ? AppTheme.warning.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: selecionado
                ? AppTheme.warning
                : Theme.of(context).colorScheme.outlineVariant,
            width: selecionado ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selecionado ? Icons.check_circle : Icons.factory_outlined,
              size: 16,
              color: selecionado ? AppTheme.warning : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                color: selecionado ? AppTheme.warning : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
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

class _ItemMovimentacao {
  final MaterialModel material;
  final TextEditingController quantCtrl        = TextEditingController();
  final TextEditingController obsCtrl          = TextEditingController();
  final TextEditingController larguraUsadaCtrl = TextEditingController();
  final TextEditingController alturaUsadaCtrl  = TextEditingController();
  bool usarModoDimensional = false;
  String? erroEstoque;

  /// True se a unidade do material é metro linear (m, m/l, ml, etc.).
  bool get _eMetroLinear {
    final u = material.unidade?.toLowerCase().trim() ?? '';
    return const {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'}.contains(u);
  }

  /// True se o material é UNIDADE (chapa/peça) e tem largura + comprimento
  /// cadastrados.
  bool get podeInformarDimensao {
    final m = material;
    if (_eMetroLinear) return false;
    return (m.unidade?.toUpperCase() == 'UNIDADE') &&
        m.largura != null && m.largura! > 0 &&
        m.comprimento != null && m.comprimento! > 0;
  }

  /// Área usada em m² (larguraUsadaCtrl × alturaUsadaCtrl), quando ativo.
  double? get areaUsadaM2 {
    if (!usarModoDimensional) return null;
    final l = double.tryParse(larguraUsadaCtrl.text.replaceAll(',', '.'));
    final c = double.tryParse(alturaUsadaCtrl.text.replaceAll(',', '.'));
    if (l == null || c == null || l <= 0 || c <= 0) return null;
    return l * c;
  }

  /// Custo proporcional desta saída = custoM2 × areaUsada.
  double? get precoM2Proporcional {
    final area    = areaUsadaM2;
    final custoM2 = precoM2Sugerido;
    if (area == null || custoM2 == null || custoM2 <= 0) return null;
    return custoM2 * area;
  }

  double? get precoUnitarioSugerido => material.ultimoValorPago;

  double? get precoM2Sugerido {
    final custoM2Gravado = material.ultimoValorPagoM2;

    final unidadeLinear = _eMetroLinear;
    if (unidadeLinear) {
      final larg = material.largura;
      if (larg != null && larg > 0) {
        if (custoM2Gravado != null && custoM2Gravado > 0) {
          return custoM2Gravado * larg;
        }
        final pu = precoUnitarioSugerido;
        if (pu != null && pu > 0) {
          return pu;
        }
      }
      return null;
    }

    if (custoM2Gravado != null && custoM2Gravado > 0) return custoM2Gravado;

    final larg = material.largura;
    final comp = material.comprimento;
    if (larg != null && comp != null && larg > 0 && comp > 0) {
      final pu = precoUnitarioSugerido;
      if (pu != null && pu > 0) {
        return pu / (larg * comp);
      }
    }
    return null;
  }

  _ItemMovimentacao({required this.material});

  String get chaveUnica => '${material.id}';

  void dispose() {
    quantCtrl.dispose();
    obsCtrl.dispose();
    larguraUsadaCtrl.dispose();
    alturaUsadaCtrl.dispose();
  }
}

/// Substitui o campo "Estoque mínimo" no cadastro quando o usuário é COMPRAS.
/// A definição do estoque mínimo deve ser feita por quem tem acesso à
/// entrada real de estoque (Controle de Estoque / OS vinculada).
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

// ─── Card de item selecionado ─────────────────────────────────────────────────

class _ItemSelecionadoCard extends StatefulWidget {
  final _ItemMovimentacao item;
  final VoidCallback onRemover;
  /// 'ENTRADA' ou 'SAIDA' — controla se o modo retalho é exibido.
  final String tipo;

  const _ItemSelecionadoCard({
    super.key,
    required this.item,
    required this.onRemover,
    required this.tipo,
  });

  @override
  State<_ItemSelecionadoCard> createState() => _ItemSelecionadoCardState();
}

class _ItemSelecionadoCardState extends State<_ItemSelecionadoCard> {
  _ItemMovimentacao get item => widget.item;

  // Materiais metro linear (M/L, m, ml…) NUNCA entram no modo dimensional —
  // a largura deles é fixa e o comprimento cortado já é a quantidade
  // informada pelo usuário.
  bool get _eMetroLinear {
    final unidade = item.material.unidade?.toLowerCase().trim() ?? '';
    const unidadesMetroLinear = {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'};
    return unidadesMetroLinear.contains(unidade);
  }

  /// Retorna (largura, comprimento) da chapa/peça, em metros.
  /// Prioriza os campos largura/comprimento cadastrados diretamente no
  /// material (igual à tela de Produção); quando ausentes, tenta extrair do
  /// campo medida no formato "LxA" ou "LxAM" (ex: "2X1", "1.20X0.80M") como
  /// fallback de compatibilidade.
  /// Retorna null se inválido ou se o material for metro linear.
  (double l, double a)? get _medidaChapa {
    if (_eMetroLinear) return null;

    final m = item.material;
    if (m.largura != null && m.largura! > 0 &&
        m.comprimento != null && m.comprimento! > 0) {
      return (m.largura!, m.comprimento!);
    }

    final medida = m.medida;
    if (medida == null || medida.isEmpty) return null;
    // Aceita sufixo opcional "M" no final (ex: 1.20X0.80M, 2X1M)
    if (!RegExp(r'^\d+([.,]\d+)?\s*[xX]\s*\d+([.,]\d+)?\s*M?$', caseSensitive: false)
        .hasMatch(medida.trim())) {
      return null;
    }
    // Remove sufixo "M" antes de parsear
    final semSufixo = medida.trim().replaceFirst(RegExp(r'M\s*$', caseSensitive: false), '').trim();
    final partes = semSufixo.split(RegExp(r'\s*[xX]\s*'));
    if (partes.length < 2) return null;
    final l = double.tryParse(partes[0].replaceAll(',', '.'));
    final a = double.tryParse(partes[1].replaceAll(',', '.'));
    if (l == null || l <= 0 || a == null || a <= 0) return null;
    return (l, a);
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final m = item.material;
    final medidaFmt = formatarMedidaOuDimensoes(
      medida:      m.medida,
      largura:     m.largura,
      comprimento: m.comprimento,
    );
    final partes = <String>[
      if (medidaFmt != null) medidaFmt,
      if (formatarEspessuraComSufixo(m.espessura) != null) formatarEspessuraComSufixo(m.espessura)!,
      if (m.categoria != null && m.categoria!.isNotEmpty) m.categoria!,
    ].join(' · ');

    final chapa        = _medidaChapa;
    final podeDimensao = chapa != null;

    // ── Preview do cálculo dimensional ───────────────────────────────────────
    Widget? previewDimensional;
    if (item.usarModoDimensional && podeDimensao) {
      final largStr = item.larguraUsadaCtrl.text.replaceAll(',', '.');
      final altStr  = item.alturaUsadaCtrl.text.replaceAll(',', '.');
      final larg    = double.tryParse(largStr);
      final alt     = double.tryParse(altStr);

      if (larg != null && larg > 0 && alt != null && alt > 0) {
        final areaUsada   = larg * alt;
        final areaTotal   = chapa.$1 * chapa.$2;
        final areaRetalho = double.parse((areaTotal - areaUsada).toStringAsFixed(4));
        final temRetalho  = areaRetalho > 0.0001;

        // Custo proporcional (só para SAÍDA)
        final custoProporcional = widget.tipo == 'SAIDA'
            ? item.precoM2Proporcional
            : null;

        previewDimensional = Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Icon(Icons.calculate_outlined,
                  size: 14, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho: nome + botão remover ──────────────────────────────
          Row(
            children: [
              const Icon(Icons.check_circle,
                  size: 15, color: AppTheme.primary),
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
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (partes.isNotEmpty)
                      Text(
                        partes,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onRemover,
                icon: Icon(Icons.close,
                    size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(28, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ).copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
                tooltip: 'Remover',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Toggle modo dimensional (só chapas com medida LxA) ───────────
          if (podeDimensao) ...[
            InkWell(
              onTap: () => setState(() {
                item.usarModoDimensional = !item.usarModoDimensional;
                // Ao ativar o modo dimensional, a quantidade é sempre 1
                // (uma chapa/peça inteira é "usada", a área que sai do
                // estoque é controlada pela largura × comprimento usados).
                // O campo fica bloqueado para edição manual.
                if (item.usarModoDimensional) {
                  item.quantCtrl.text = '1';
                }
              }),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.usarModoDimensional
                          ? Icons.toggle_on
                          : Icons.toggle_off_outlined,
                      size: 20,
                      color: item.usarModoDimensional
                          ? AppTheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Informar dimensão usada',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: item.usarModoDimensional
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
                        'Chapa ${_fmt(chapa.$2)}×${_fmt(chapa.$1)} m',
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
            const SizedBox(height: 8),
          ],

          // ── Campos de dimensão (quando modo ativo) ────────────────────────
          if (item.usarModoDimensional && podeDimensao) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item.alturaUsadaCtrl,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Comprimento usado (m)',
                      isDense: true,
                      suffixText: '/ ${_fmt(chapa.$2)} m',
                      suffixStyle: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.outline),
                    ),
                    onChanged: (_) => setState(() {
                      _limitarDimensao(item.alturaUsadaCtrl, chapa.$2);
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
                    controller: item.larguraUsadaCtrl,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Largura usada (m)',
                      isDense: true,
                      suffixText: '/ ${_fmt(chapa.$1)} m',
                      suffixStyle: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.outline),
                    ),
                    onChanged: (_) => setState(() {
                      _limitarDimensao(item.larguraUsadaCtrl, chapa.$1);
                    }),
                  ),
                ),
              ],
            ),
            if (previewDimensional != null) previewDimensional,
            const SizedBox(height: 10),
          ],
          // ── Campos de quantidade e observação ─────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextFormField(
                  controller: item.quantCtrl,
                  enabled: !item.usarModoDimensional,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Quantidade *',
                    isDense: true,
                    suffixText: formatarUnidadeExibicao(m.unidade),
                  ),
                  validator: (v) {
                    if (item.erroEstoque != null) return item.erroEstoque;
                    final quant =
                        double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (quant == null || quant <= 0) return 'Qtd. inválida';
                    return null;
                  },
                  onChanged: (_) {
                    if (item.erroEstoque != null) item.erroEstoque = null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: item.obsCtrl,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                    isDense: true,
                    prefixIcon: Icon(Icons.notes, size: 16),
                  ),
                ),
              ),
            ],
          ),


          // ── Preço sugerido ────────────────────────────────────────────────
          Builder(builder: (_) {
            final pu  = item.precoUnitarioSugerido;
            final pm2 = item.precoM2Sugerido;
            if (pu == null && pm2 == null) return const SizedBox.shrink();

            final partesBrl = <String>[];

            const mlUnitsCard = {'m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'};
            final eMLCard = mlUnitsCard.contains(m.unidade?.toLowerCase().trim() ?? '');

            if (eMLCard) {
              final valML = pm2 ?? pu;
              if (valML != null && valML > 0) {
                partesBrl.add('m/l: R\$ ${_brl6(valML).substring(3)}');
              }
            } else {
              if (pu != null && pu > 0) {
                partesBrl.add('Unit.: R\$ ${_brl6(pu).substring(3)}');
              }
              if (pm2 != null && pm2 > 0) {
                partesBrl.add('M²: R\$ ${_brl6(pm2).substring(3)}');
              }
            }
            if (partesBrl.isEmpty) return SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.price_check,
                      size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      partesBrl.join('  ·  '),
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}


// ─── Tile de resultado de busca ───────────────────────────────────────────────

class _MaterialResultadoTile extends StatefulWidget {
  final MaterialModel material;
  final bool selecionado;
  final VoidCallback onTap;

  const _MaterialResultadoTile({
    required this.material,
    required this.selecionado,
    required this.onTap,
  });

  @override
  State<_MaterialResultadoTile> createState() =>
      _MaterialResultadoTileState();
}

class _MaterialResultadoTileState extends State<_MaterialResultadoTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m   = widget.material;
    final sel = widget.selecionado;
    final bg  = sel
        ? AppTheme.primary.withValues(alpha: 0.10)
        : _hovered
            ? AppTheme.primary.withValues(alpha: 0.05)
            : Colors.transparent;

    final medidaFmt = formatarMedidaOuDimensoes(
      medida:      m.medida,
      largura:     m.largura,
      comprimento: m.comprimento,
    );
    final partes = <String>[
      if (m.identificador != null && m.identificador!.isNotEmpty)
        '${m.identificador}',
      if (medidaFmt != null) medidaFmt,
      if (formatarEspessuraComSufixo(m.espessura) != null) formatarEspessuraComSufixo(m.espessura)!,
      if (m.categoria != null && m.categoria!.isNotEmpty) m.categoria!,
    ].join(' · ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: bg,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (sel)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_circle,
                      size: 15, color: AppTheme.primary),
                )
              else
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle_outlined,
                      size: 15, color: Theme.of(context).colorScheme.outline),
                ),
              SizedBox(
                width: 36,
                child: Text(
                  '#${m.id}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.nome,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            sel ? FontWeight.w700 : FontWeight.w500,
                        color:
                            sel ? AppTheme.primary : Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (partes.isNotEmpty)
                      Text(
                        partes,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatarQuantidade(m.quantidade),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                  if (m.unidade != null)
                    Text(
                      formatarUnidadeExibicao(m.unidade),
                      style: TextStyle(
                          fontSize: 10, color: Theme.of(context).colorScheme.outline),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              _StatusBadgeMini(status: m.status),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Badge de status mini (material) ─────────────────────────────────────────

class _StatusBadgeMini extends StatelessWidget {
  final String status;
  const _StatusBadgeMini({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'OK'      => ('OK',      AppTheme.statusOk),
      'LIMITE'  => ('LIMITE',  AppTheme.statusBaixo),
      'CRITICO' => ('CRITICO', AppTheme.statusCritico),
      'INATIVO' => ('INATIVO', Theme.of(context).colorScheme.outline),
      _         => ('—',       Theme.of(context).colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS — Detecção de materiais semelhantes (Cadastro de Material)
// ─────────────────────────────────────────────────────────────────────────────

/// Extrai o primeiro número de um texto, aceitando vírgula ou ponto como
/// separador decimal e ignorando qualquer sufixo de unidade colado nele
/// (ex.: "1.22m" -> 1.22, "3mm" -> 3, "2,00" -> 2.0). Retorna null se não
/// houver número reconhecível.
double? _extrairNumeroDeTextoCE(String? s) {
  if (s == null) return null;
  final match = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(s.trim());
  if (match == null) return null;
  return double.tryParse(match.group(0)!.replaceAll(',', '.'));
}

/// Dimensões numéricas extraídas do texto livre "medida".
class _DimensoesMedidaCE {
  final double? comprimento;
  final double? largura;
  final double? espessura;
  const _DimensoesMedidaCE({this.comprimento, this.largura, this.espessura});
}

/// Faz o parse do campo "medida" (texto livre) em até 3 números separados
/// por "x"/"X"/"×", tolerando qualquer combinação de: presença ou não do
/// sufixo de unidade ("m", "mm"), formatação decimal (2 vs 2.00 vs 2,00), e
/// um terceiro segmento opcional com a espessura embutida (ex.: "5x1.22x3mm",
/// "2x1x2mm", "2.00x1.00m", "2x1"). Todas essas grafias devem ser
/// reconhecidas como a mesma medida física.
_DimensoesMedidaCE _extrairDimensoesMedidaCE(String? medida) {
  if (medida == null || medida.trim().isEmpty) return const _DimensoesMedidaCE();
  final partes = medida.trim().split(RegExp(r'[xX×]'));
  final numeros = partes.map(_extrairNumeroDeTextoCE).toList();
  return _DimensoesMedidaCE(
    comprimento: numeros.isNotEmpty ? numeros[0] : null,
    largura:     numeros.length > 1 ? numeros[1] : null,
    espessura:   numeros.length > 2 ? numeros[2] : null,
  );
}

/// Normaliza texto para comparação: remove acentos, converte para maiúsculas
/// e colapsa espaços múltiplos.
String _normalizarTextoComparacaoCE(String? v) {
  if (v == null) return '';
  final upper = _UpperCaseFormatter._removerAcentos(v.trim().toUpperCase());
  return upper.replaceAll(RegExp(r'\s+'), ' ');
}

/// Distância de Levenshtein clássica (número mínimo de inserções, remoções
/// e substituições para transformar [a] em [b]).
int _levenshteinDistanceCE(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> anterior = List<int>.generate(b.length + 1, (j) => j);
  List<int> atual    = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    atual[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final custo      = a[i - 1] == b[j - 1] ? 0 : 1;
      final remocao    = anterior[j] + 1;
      final insercao   = atual[j - 1] + 1;
      final substituicao = anterior[j - 1] + custo;
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
double _similaridadeTextoCE(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final distancia    = _levenshteinDistanceCE(a, b);
  final maiorTamanho = a.length > b.length ? a.length : b.length;
  return 1 - (distancia / maiorTamanho);
}

/// Resultado de uma possível duplicata encontrada ao comparar os campos do
/// formulário com materiais já cadastrados.
class _PossivelDuplicataCE {
  final MaterialModel material;

  /// true quando nome + identificador + medida + espessura (normalizados)
  /// coincidem exatamente — o backend rejeitaria esse cadastro com 409.
  final bool exata;
  final double similaridade;
  /// true quando o nome digitado é prefixo/trecho do nome já cadastrado
  /// (ou vice-versa) — indica digitação em andamento.
  final bool contido;

  _PossivelDuplicataCE({
    required this.material,
    required this.exata,
    required this.similaridade,
    this.contido = false,
  });
}

/// Banner exibido no formulário de cadastro de material quando o algoritmo
/// de comparação encontra materiais já cadastrados com nome, identificador,
/// medida ou espessura parecidos com os campos digitados.
class _AvisoPossivelDuplicataCE extends StatelessWidget {
  final bool carregando;
  final List<_PossivelDuplicataCE> duplicatas;
  const _AvisoPossivelDuplicataCE({required this.carregando, required this.duplicatas});

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

    if (duplicatas.isEmpty) return const SizedBox.shrink();

    final temExata = duplicatas.any((d) => d.exata);
    final cor      = temExata ? AppTheme.error : AppTheme.warning;

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
            // livre "medida" é omitido, para não repetir a mesma informação
            // em formatos diferentes.
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
              if (formatarEspessuraComSufixo(m.espessura) != null)   formatarEspessuraComSufixo(m.espessura)!,
            ].join(' • ');

            final qtdTxt = formatarQuantidade(m.quantidade);

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
// ── Dropdown de categoria (filtro no diálogo de Entrada/Saída) ─────────────
// Mesmo padrão visual do dropdown de categoria usado nas outras páginas do
// sistema (ex.: estoque_page.dart): campo com o mesmo estilo de
// InputDecorator dos demais filtros, cursor de mão no campo inteiro, seta
// que destaca no hover e busca embutida no próprio menu. Diferente do
// dropdown de estoque_page.dart, aqui há 3 estados possíveis: null = Todas,
// '' = Sem categoria, e o nome da categoria selecionada.
class _CategoriaFiltroDropdownCE extends StatefulWidget {
  final List<String> categorias;
  final String? valorSelecionado; // null = Todas; '' = Sem categoria
  final ValueChanged<String?> onSelecionar;
  const _CategoriaFiltroDropdownCE({
    required this.categorias,
    required this.valorSelecionado,
    required this.onSelecionar,
  });

  @override
  State<_CategoriaFiltroDropdownCE> createState() => _CategoriaFiltroDropdownCEState();
}

class _CategoriaFiltroDropdownCEState extends State<_CategoriaFiltroDropdownCE> {
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

  String get _labelExibido {
    if (widget.valorSelecionado == null) return 'Todas';
    if (widget.valorSelecionado!.isEmpty) return 'Sem categoria';
    return widget.valorSelecionado!;
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
                            onPressed: () {
                              widget.onSelecionar(null);
                              _menuController.close();
                            },
                            trailingIcon: widget.valorSelecionado == null
                                ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                                : null,
                            child: const SizedBox(
                              width: 208,
                              child: Text('Todas'),
                            ),
                          ),
                          MenuItemButton(
                            onPressed: () {
                              widget.onSelecionar('');
                              _menuController.close();
                            },
                            trailingIcon: widget.valorSelecionado != null &&
                                    widget.valorSelecionado!.isEmpty
                                ? Icon(Icons.check, size: 16, color: AppTheme.primary)
                                : null,
                            child: const SizedBox(
                              width: 208,
                              child: Text('Sem categoria'),
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
                          if (filtradas.isEmpty && _busca.trim().isNotEmpty)
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
                _labelExibido,
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

// ── Botão "voltar" com hover, cursor de mão e tooltip ───────────────────────
// Mesmo padrão usado no cabeçalho das outras páginas do sistema.
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