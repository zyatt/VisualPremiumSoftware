import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoboTourStop {

  final GlobalKey Function() _chave;
  final String texto;
  final Offset offset;

  final Future<void> Function()? aoEntrar;

  final Future<void> Function()? aoSair;

  GlobalKey get key => _chave();

  const RoboTourStop({
    required GlobalKey Function() key,
    required this.texto,
    this.offset = const Offset(0, 0),
    this.aoEntrar,
    this.aoSair,
  }) : _chave = key;
}

class RoboHelpOption {
  final String titulo;
  final List<RoboTourStop> paradas;

  final Future<void> Function()? aoEncerrar;

  // Indica se esta opção deve continuar aparecendo no menu "Dúvidas"
  // quando uma tela sobreposta (ex.: um editor aberto por cima da
  // listagem) está ativa. Por padrão false: a opção é da tela de base
  // (listagem) e não faz sentido dentro do editor. Cada página marca
  // explicitamente como true apenas as opções que de fato pertencem ao
  // editor, em vez de depender de uma lista de títulos fixa e genérica.
  final bool visivelNoEditorSobreposto;

  const RoboHelpOption({
    required this.titulo,
    required this.paradas,
    this.aoEncerrar,
    this.visivelNoEditorSobreposto = false,
  });
}

class RoboHelperProvider extends ChangeNotifier {
  bool _oculto = false;
  bool get oculto => _oculto;

  static const _chavePrefsOculto = 'robo_helper_oculto';

  RoboHelperProvider() {
    _carregarEstadoOculto();
  }

  Future<void> _carregarEstadoOculto() async {
    final prefs = await SharedPreferences.getInstance();
    final oculto = prefs.getBool(_chavePrefsOculto) ?? false;
    if (oculto != _oculto) {
      _oculto = oculto;
      notifyListeners();
    }
  }

  Future<void> _salvarEstadoOculto(bool oculto) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chavePrefsOculto, oculto);
  }

  void ocultar() {
    _oculto = true;
    notifyListeners();
    _salvarEstadoOculto(true);
  }

  void mostrar() {
    _oculto = false;
    notifyListeners();
    _salvarEstadoOculto(false);
  }

  void alternarOculto() {
    _oculto = !_oculto;
    notifyListeners();
    _salvarEstadoOculto(_oculto);
  }

  bool _telaSobrepostaAtiva = false;
  bool get telaSobrepostaAtiva => _telaSobrepostaAtiva;

  void definirTelaSobreposta(bool ativa) {
    if (_telaSobrepostaAtiva == ativa) return;
    _telaSobrepostaAtiva = ativa;
    notifyListeners();
  }

  String _rotaAtual = '';

  String get rotaAtual => _rotaAtual;

  void notificarRota(String rota) {
    if (_rotaAtual == rota) return;
    _rotaAtual = rota;

    _encerrarTourInterno();
    notifyListeners();
  }

  final Map<String, List<RoboHelpOption>> _opcoesPorRota = {};

  List<RoboHelpOption> get opcoesAtuais =>
      _opcoesPorRota[_rotaAtual] ?? const [];

  List<RoboHelpOption> opcoesDaRota(String rota) =>
      _opcoesPorRota[rota] ?? const [];

  void registrarOpcoes(String rota, List<RoboHelpOption> opcoes) {

    _opcoesPorRota[rota] = opcoes;
    if (rota == _rotaAtual) notifyListeners();
  }

  void limparOpcoes(String rota) {
    _opcoesPorRota.remove(rota);
    if (rota == _rotaAtual) notifyListeners();
  }

  String? _tourRota;
  String? _tourTitulo;
  int _passoAtual = 0;

  List<RoboTourStop> get _paradasAtivas {
    if (_tourRota == null || _tourTitulo == null) return const [];
    final opcoes = _opcoesPorRota[_tourRota] ?? const [];
    final opcao = opcoes.where((o) => o.titulo == _tourTitulo).firstOrNull;
    return opcao?.paradas ?? const [];
  }

  bool get tourAtivo => _tourRota != null;
  int get passoAtual => _passoAtual;

  RoboTourStop? get paradaAtual {
    final paradas = _paradasAtivas;
    return (_tourRota != null && _passoAtual < paradas.length)
        ? paradas[_passoAtual]
        : null;
  }

  bool get ehUltimaParada {
    final paradas = _paradasAtivas;
    return _tourRota != null &&
        paradas.isNotEmpty &&
        _passoAtual == paradas.length - 1;
  }

  bool get ehPrimeiraParada => _passoAtual == 0;

  bool _navegando = false;

  bool get navegando => _navegando;

  Future<void> iniciarTour(String rota, String titulo) async {
    final opcoes = _opcoesPorRota[rota] ?? const [];
    final opcao = opcoes.where((o) => o.titulo == titulo).firstOrNull;
    if (opcao == null || opcao.paradas.isEmpty) return;
    _tourRota = rota;
    _tourTitulo = titulo;
    _passoAtual = 0;
    notifyListeners();
    await _chamarAoEntrarComTimeout(opcao.paradas[0].aoEntrar);
  }

  static const _timeoutAoEntrar = Duration(seconds: 5);

  Future<void> _chamarAoEntrarComTimeout(Future<void> Function()? aoEntrar) async {
    if (aoEntrar == null) return;
    try {
      await aoEntrar().timeout(_timeoutAoEntrar);
    } catch (_) {

    }
  }

  Future<void> _chamarAoSairComTimeout(Future<void> Function()? aoSair) async {
    if (aoSair == null) return;
    try {
      await aoSair().timeout(_timeoutAoEntrar);
    } catch (_) {

    }
  }

  Future<void> proximaParada() async {
    if (_tourRota == null || _navegando) return;
    final paradas = _paradasAtivas;
    if (paradas.isEmpty) return;
    if (_passoAtual < paradas.length - 1) {
      _navegando = true;
      try {
        _passoAtual++;
        notifyListeners();

        final parada = _paradaEm(_passoAtual);
        if (parada != null) {
          await _chamarAoEntrarComTimeout(parada.aoEntrar);
        } else {

          _encerrarTourInterno();
        }
      } finally {
        _navegando = false;

        if (_encerramentoPendente) {
          // ESC/"Fechar" foi acionado enquanto esta transição rodava.
          // Executa o encerramento de verdade agora (fecha diálogos,
          // editor etc.) em vez de deixar o estado inconsistente.
          await _encerrarTourAgora();
        } else {
          notifyListeners();
        }
      }
    } else {

      await encerrarTour();
    }
  }

  RoboTourStop? _paradaEm(int i) {
    final paradas = _paradasAtivas;
    if (i < 0 || i >= paradas.length) return null;
    return paradas[i];
  }

  Future<void> paradaAnterior() async {
    if (_tourRota == null || _passoAtual == 0 || _navegando) return;
    _navegando = true;
    try {

      final paradaAtualAntesDeMudar = _paradaEm(_passoAtual);
      await _chamarAoSairComTimeout(paradaAtualAntesDeMudar?.aoSair);

      final novoIndice = _passoAtual - 1;
      final paradaAnterior = _paradaEm(novoIndice);
      if (paradaAnterior == null) {

        _encerrarTourInterno();
        return;
      }

      _passoAtual = novoIndice;
      notifyListeners();
      await _chamarAoEntrarComTimeout(paradaAnterior.aoEntrar);
    } finally {
      _navegando = false;
      if (_encerramentoPendente) {
        await _encerrarTourAgora();
      } else {
        notifyListeners();
      }
    }
  }

  void _encerrarTourInterno() {
    _tourRota = null;
    _tourTitulo = null;
    _passoAtual = 0;
  }

  bool _encerramentoPendente = false;

  Future<void> encerrarTour() async {
    if (_tourRota == null) return;
    if (_navegando) {
      // Uma transição (proximaParada/paradaAnterior) já está em andamento.
      // Antes, encerrar aqui só zerava o estado interno sem rodar
      // aoSair/aoEncerrar — isso deixava diálogos/editores abertos na
      // tela "órfãos", pois quem fecharia essas telas nunca era chamado.
      // Em vez disso, marcamos o encerramento como pendente: assim que a
      // transição em curso terminar, ela mesma finaliza o tour de verdade
      // (rodando aoEncerrar) em vez de deixar o estado inconsistente.
      _encerramentoPendente = true;
      return;
    }
    await _encerrarTourAgora();
  }

  Future<void> _encerrarTourAgora() async {
    if (_tourRota == null) return;
    _navegando = true;
    try {
      final rota = _tourRota;
      final titulo = _tourTitulo;
      final parada = paradaAtual;

      await _chamarAoSairComTimeout(parada?.aoSair);

      if (rota != null && titulo != null) {
        final opcoes = _opcoesPorRota[rota] ?? const [];
        final opcao = opcoes.where((o) => o.titulo == titulo).firstOrNull;
        await _chamarAoSairComTimeout(opcao?.aoEncerrar);
      }
    } finally {
      _navegando = false;
      _encerramentoPendente = false;
      _encerrarTourInterno();
      notifyListeners();
    }
  }
}