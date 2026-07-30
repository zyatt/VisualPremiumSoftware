import 'package:flutter/foundation.dart';
import 'package:visual_premium/providers/orcamento_provider.dart';
import '../models/usuario_model.dart';
import '../repositories/usuario_repository.dart';
import '../utils/api_client.dart';
import 'solicitacao_material_provider.dart';
import 'chat_provider.dart';

/// Converte exceções técnicas (SocketException, ClientException, TimeoutException
/// etc.) em uma mensagem amigável para o usuário. Mensagens de erro vindas do
/// próprio servidor (ex: "Credenciais inválidas") são mantidas como estão.
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
  /// Liga o ChatProvider global a este provider, para que login/logout/troca
  /// de usuário controlem diretamente o ciclo de vida da conexão de chat
  /// (SSE + heartbeat + lista de usuários), em vez de depender da ChatPage
  /// ter sido aberta pelo menos uma vez.
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
  /// Usuários que já logaram nesta máquina (para troca rápida).
  List<UsuarioModel> get usuariosSalvos => _usuariosSalvos;

  /// Atualiza a lista de usuários salvos; chamado na inicialização e após login.
  Future<void> _refreshUsuariosSalvos() async {
    _usuariosSalvos = await _repo.getUsuariosSalvos();
  }

  // Chamado em main() antes de runApp — tenta restaurar sessão salva
  Future<void> restaurarSessao() async {
    await _refreshUsuariosSalvos();
    try {
      final sessao = await _repo.carregarSessao();
      if (sessao != null) {
        // Seta o token salvo para poder chamar /auth/refresh
        ApiClient.setToken(sessao.token);
        try {
          // Renova o token (útil para usuários que tinham token com expiresIn antigo)
          final data = await ApiClient.post('/auth/refresh', {});
          final novoToken = data['token'] as String;
          _token         = novoToken;
          _usuarioLogado = sessao.usuario;
          ApiClient.setToken(novoToken);
          await _repo.salvarSessao(novoToken, sessao.usuario);
          await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id);
          await _chatProvider?.inicializar(_usuarioLogado!.id, novoToken);
        } catch (_) {
          // Token rejeitado pelo servidor — limpa e vai para login
          _token         = null;
          _usuarioLogado = null;
          ApiClient.setToken(null);
          await _repo.limparSessao();
          _chatProvider?.limparToken();
        }
      }
    } catch (_) {
      // Sessão corrompida — ignora e segue para login
      await _repo.limparSessao();
    } finally {
      _restaurando = false;
      notifyListeners();
    }
  }

  /// Remove um usuário salvo da lista de troca rápida (não afeta o usuário no servidor).
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
      // Garante que não existe SSE/estado residual de uma sessão anterior
      // antes de autenticar o novo usuário.
      await _solicitacaoMaterialProvider?.resetarConexao();
      _chatProvider?.limparToken();
      final result   = await _repo.login(username, senha);
      _token         = result.token;
      _usuarioLogado = result.usuario;
      ApiClient.setToken(_token);
      await _repo.adicionarUsuarioSalvo(result.usuario);
      await _refreshUsuariosSalvos();
      await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id);
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
    // Encerra a conexão SSE e zera o estado de solicitações do usuário que
    // saiu, para que o próximo usuário a logar comece do zero.
    await _solicitacaoMaterialProvider?.resetarConexao();
    notifyListeners();
  }

  /// Troca diretamente para outro usuário que já logou nesta máquina,
  /// sem precisar de senha. Requer que haja um token ativo no momento.
  Future<bool> loginComoUsuario(UsuarioModel alvo) async {
    // Não chama notifyListeners() aqui: como o GoRouter escuta este provider
    // via refreshListenable, uma notificação intermediária (com o usuário
    // antigo ainda ativo e _carregando=true) dispara um redirect no meio da
    // troca — concorrendo com o Navigator.pop() do diálogo de seleção e com
    // o rebuild do AppShell/sidebar que acontece na notificação final. Essa
    // corrida entre dois Navigators mexendo na árvore quase ao mesmo tempo
    // é o que produz o erro '_elements.contains(element): is not true'.
    _carregando = true;
    _erro       = null;
    try {
      await _solicitacaoMaterialProvider?.resetarConexao();
      // Zera o estado de chat do usuário anterior (SSE, heartbeat, lista de
      // usuários e conversas) ANTES de logar como o novo usuário, para não
      // vazar dados de uma sessão para a outra durante a troca.
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
      await _orcamentoProvider?.trocarUsuario(_usuarioLogado!.id);
      await _chatProvider?.inicializar(_usuarioLogado!.id, token);
      return true;
    } catch (e) {
      _erro = _mensagemErro(e);
      return false;
    } finally {
      _carregando = false;
      // Notificação única, no final, já com o usuário/role definitivos.
      // Garante que o redirect do GoRouter e o rebuild do AppShell vejam
      // exatamente o mesmo estado consistente, em vez de dois estados
      // intermediários conflitantes.
      notifyListeners();
    }
  }

  /// Efetua logout do usuário atual sem limpar a lista de usuários salvos,
  /// sinalizando ao router que deve ir para a tela de login.
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