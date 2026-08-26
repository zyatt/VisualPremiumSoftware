import 'package:flutter/foundation.dart';
import 'package:visual_premium/providers/orcamento_provider.dart';
import '../models/usuario_model.dart';
import '../repositories/usuario_repository.dart';
import '../utils/api_client.dart';
import 'solicitacao_material_provider.dart';
import 'chat_provider.dart';

String _mensagemErro(Object e) {
  final texto = e.toString();
  if (texto.contains('SocketException') ||
      texto.contains('ClientException') ||
      texto.contains('Connection refused') ||
      texto.contains('Connection reset') ||
      texto.contains('Failed host lookup') ||
      texto.contains('HandshakeException') ||
      texto.contains('TimeoutException') ||
      texto.contains('Network is unreachable')) {
    return 'Não foi possível acessar. Verifique sua conexão com o servidor';
  }
  return texto.replaceFirst('Exception: ', '');
}

class UsuarioProvider extends ChangeNotifier {
  final UsuarioRepository _repo = UsuarioRepository();
  OrcamentoProvider? _orcamentoProvider;
  SolicitacaoMaterialProvider? _solicitacaoMaterialProvider;
  ChatProvider? _chatProvider;

  void setOrcamentoProvider(OrcamentoProvider p) => _orcamentoProvider = p;
  void setSolicitacaoMaterialProvider(SolicitacaoMaterialProvider p) =>
      _solicitacaoMaterialProvider = p;
  void setChatProvider(ChatProvider p) => _chatProvider = p;

  UsuarioModel? _usuarioLogado;
  UsuarioModel? get usuarioLogado => _usuarioLogado;

  String? _token;
  String? get token => _token;

  bool _carregando = false;
  bool get carregando => _carregando;

  bool _restaurando = true;
  bool get restaurando => _restaurando;

  String? _erro;
  String? get erro => _erro;

  List<UsuarioModel> _usuariosSalvos = [];
  List<UsuarioModel> get usuariosSalvos => _usuariosSalvos;

  Future<void> _refreshUsuariosSalvos() async {
    _usuariosSalvos = await _repo.getUsuariosSalvos();
  }

  Future<void> restaurarSessao() async {
    await _refreshUsuariosSalvos();
    try {
      final sessao = await _repo.carregarSessao();
      if (sessao != null) {
        ApiClient.setToken(sessao.token);
        try {
          final data = await ApiClient.post('/auth/refresh', {});
          final novoToken = data['token'] as String;
          _token         = novoToken;
          _usuarioLogado = sessao.usuario;
          ApiClient.setToken(novoToken);
          await _repo.salvarSessao(novoToken, sessao.usuario);
          await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id, _usuarioLogado!.nome);
          await _chatProvider?.inicializar(_usuarioLogado!.id, novoToken);
        } catch (_) {
          _token         = null;
          _usuarioLogado = null;
          ApiClient.setToken(null);
          await _repo.limparSessao();
          _chatProvider?.limparToken();
        }
      }
    } catch (_) {
      await _repo.limparSessao();
    } finally {
      _restaurando = false;
      notifyListeners();
    }
  }

  Future<void> removerUsuarioSalvo(UsuarioModel usuario) async {
    await _repo.removerUsuarioSalvo(usuario.id);
    await _refreshUsuariosSalvos();
    notifyListeners();
  }

  Future<bool> login(String username, String senha) async {
    _carregando = true;
    _erro       = null;
    notifyListeners();
    try {
      await _solicitacaoMaterialProvider?.resetarConexao();
      _chatProvider?.limparToken();
      final result   = await _repo.login(username, senha);
      _token         = result.token;
      _usuarioLogado = result.usuario;
      ApiClient.setToken(_token);
      await _repo.adicionarUsuarioSalvo(result.usuario);
      await _refreshUsuariosSalvos();
      await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id, _usuarioLogado!.nome);
      await _chatProvider?.inicializar(_usuarioLogado!.id, _token!);
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      return false;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _usuarioLogado = null;
    _token         = null;
    ApiClient.setToken(null);
    await _repo.limparSessao();
    _orcamentoProvider?.trocarUsuario(null);
    _chatProvider?.limparToken();
    await _solicitacaoMaterialProvider?.resetarConexao();
    notifyListeners();
  }

  Future<bool> loginComoUsuario(UsuarioModel alvo) async {
    _carregando = true;
    _erro       = null;
    try {
      await _solicitacaoMaterialProvider?.resetarConexao();
      _chatProvider?.limparToken();
      final data    = await ApiClient.post('/auth/trocar-usuario', {'id': alvo.id});
      final token   = data['token'] as String;
      final usuario = UsuarioModel.fromJson(data['usuario'] as Map<String, dynamic>);
      _token         = token;
      _usuarioLogado = usuario;
      ApiClient.setToken(token);
      await _repo.salvarSessao(token, usuario);
      await _repo.adicionarUsuarioSalvo(usuario);
      await _refreshUsuariosSalvos();
      await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id, _usuarioLogado!.nome);
      await _chatProvider?.inicializar(_usuarioLogado!.id, token);
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      return false;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> iniciarTrocaUsuario() async {
    _usuarioLogado = null;
    _token         = null;
    _erro          = null;
    ApiClient.setToken(null);
    await _repo.limparSessao();
    _orcamentoProvider?.trocarUsuario(null);
    _chatProvider?.limparToken();
    await _solicitacaoMaterialProvider?.resetarConexao();
    notifyListeners();
  }
}