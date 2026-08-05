import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../repositories/usuario_repository.dart';
import '../repositories/configuracao_repository.dart';
import '../providers/usuario_provider.dart';
import '../theme/app_theme.dart';

String _mensagemErro(Object e) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Verifique a conexão com o servidor';
  }
  return raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            // ── Cabeçalho ──────────────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Administração',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Gerencie usuários e configurações do sistema',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20),

            // ── TabBar ──────────────────────────────────────────────────────
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppTheme.primary,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              indicatorWeight: 2,
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Usuários'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Configurações'),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),

            // ── Conteúdo ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _UsuariosTab(),
                  _ConfiguracaoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Aba de Usuários ──────────────────────────────────────────────────────────

class _UsuariosTab extends StatefulWidget {
  const _UsuariosTab();

  @override
  State<_UsuariosTab> createState() => _UsuariosTabState();
}

class _UsuariosTabState extends State<_UsuariosTab> {
  final _repo = UsuarioRepository();

  List<Map<String, dynamic>> _usuarios = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await _repo.listar();
      setState(() => _usuarios = lista.cast<Map<String, dynamic>>());
    } catch (e) {
      setState(() => _erro = _mensagemErro(e));
    } finally {
      setState(() => _carregando = false);
    }
  }

  void _abrirFormularioCriacao() {
    showDialog(
      context: context,
      builder: (_) => _UsuarioFormDialog(onSalvo: _carregar),
    );
  }

  void _abrirFormularioEdicao(Map<String, dynamic> usuario) {
    final idUsuarioLogado = context.read<UsuarioProvider>().usuarioLogado?.id;
    showDialog(
      context: context,
      builder: (_) => _UsuarioFormDialog(
        usuario: usuario,
        idUsuarioLogado: idUsuarioLogado,
        onSalvo: _carregar,
        onExcluir: (onConfirmado) =>
            _excluir(usuario, onConfirmado: onConfirmado),
      ),
    );
  }

  Future<bool> _excluir(
    Map<String, dynamic> usuario, {
    VoidCallback? onConfirmado,
  }) async {
    final nome = usuario['nome'] as String? ?? 'usuário';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Excluir usuário'),
        content: Text(
          'Deseja excluir "$nome"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom().copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
            ).copyWith(
              mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return false;
    onConfirmado?.call();

    try {
      await _repo.excluir(usuario['id'] as int);
      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Usuário excluído.'),
          backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mensagemErro(e)),
          backgroundColor: AppTheme.error,
        ));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barra: contagem + botão
        Row(
          children: [
            if (!_carregando && _erro == null)
              Text(
                '${_usuarios.length} ${_usuarios.length == 1 ? 'usuário' : 'usuários'}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _abrirFormularioCriacao,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Novo usuário'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ).copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
            ),
            SizedBox(width: 10),
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
        const SizedBox(height: 16),

        // Conteúdo
        Expanded(
          child: _carregando
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _erro != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          SizedBox(height: 12),
                          Text(
                            'Erro ao carregar usuários',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            _erro!.contains(': ')
                                ? _erro!.substring(_erro!.indexOf(': ') + 2)
                                : _erro!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _carregar,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary)
                              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
                          ),
                        ],
                      ),
                    )
                  : _usuarios.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline_rounded,
                                  size: 64, color: Theme.of(context).colorScheme.outline),
                              SizedBox(height: 16),
                              Text(
                                'Nenhum usuário cadastrado',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Clique em "Novo usuário" para começar.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
                              ),
                            ],
                          ),
                        )
                      : _TabelaUsuarios(
                          usuarios: _usuarios,
                          onEditar: _abrirFormularioEdicao,
                          onExcluir: _excluir,
                        ),
        ),
      ],
    );
  }
}

// ─── Tabela ───────────────────────────────────────────────────────────────────

class _TabelaUsuarios extends StatelessWidget {
  final List<Map<String, dynamic>> usuarios;
  final void Function(Map<String, dynamic>) onEditar;
  final void Function(Map<String, dynamic>) onExcluir;

  const _TabelaUsuarios({
    required this.usuarios,
    required this.onEditar,
    required this.onExcluir,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            // Cabeçalho
            Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const Row(
                children: [
                  Expanded(flex: 3, child: _HeaderCell('Nome')),
                  Expanded(flex: 2, child: _HeaderCell('Username')),
                  Expanded(flex: 2, child: _HeaderCell('Cargo')),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _HeaderCell('Status'),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

            // Linhas
            Expanded(
              child: ListView.separated(
                itemCount: usuarios.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                itemBuilder: (context, i) => _LinhaUsuario(
                  usuario: usuarios[i],
                  onEditar: onEditar,
                  onExcluir: onExcluir,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Linha clicável com hover ─────────────────────────────────────────────────

class _LinhaUsuario extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final void Function(Map<String, dynamic>) onEditar;
  final void Function(Map<String, dynamic>) onExcluir;

  const _LinhaUsuario({
    required this.usuario,
    required this.onEditar,
    required this.onExcluir,
  });

  @override
  State<_LinhaUsuario> createState() => _LinhaUsuarioState();
}

class _LinhaUsuarioState extends State<_LinhaUsuario> {
  bool _hovered = false;

  void _onHover(PointerHoverEvent _) {
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent _) {
    if (_hovered) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    final ativo = u['ativo'] as bool? ?? true;
    final role = (u['role'] as String? ?? '').toUpperCase();

    final bgColor = _hovered
        ? AppTheme.primary.withValues(alpha: 0.06)
        : Theme.of(context).colorScheme.surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _onHover,
      onExit: _onExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEditar(u),
        onSecondaryTapUp: (details) => _mostrarMenu(context, details.globalPosition),
        child: ColoredBox(
          color: bgColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Nome + avatar
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.12),
                        child: Text(
                          ((u['nome'] as String? ?? 'U')[0]).toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          u['nome'] as String? ?? '-',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Username
                Expanded(
                  flex: 2,
                  child: Text(
                    u['username'] as String? ?? '-',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),

                // Role
                Expanded(
                  flex: 2,
                  child: _RoleLabel(role: role),
                ),

                // Status
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ativo ? AppTheme.success : AppTheme.error,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ativo ? 'Ativo' : 'Inativo',
                        style: TextStyle(
                          color: ativo ? AppTheme.success : AppTheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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

  void _mostrarMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      color: Theme.of(context).colorScheme.surface,
      items: [
        PopupMenuItem(
          onTap: () => widget.onEditar(widget.usuario),
          child: const Row(
            children: [
              Icon(Icons.edit_rounded, size: 16, color: AppTheme.primary),
              SizedBox(width: 10),
              Text('Editar', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => widget.onExcluir(widget.usuario),
          child: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error),
              SizedBox(width: 10),
              Text('Excluir',
                  style: TextStyle(fontSize: 13, color: AppTheme.error)),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

// ─── Botão de ação com hover ──────────────────────────────────────────────────

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.10)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: 17, color: widget.color),
          ),
        ),
      ),
    );
  }
}

// ─── Badge de cargo ───────────────────────────────────────────────────────────

class _RoleLabel extends StatelessWidget {
  final String role;
  const _RoleLabel({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label) = switch (role) {
      'ADMIN'                   => ('Administrador'),
      'GERENTE'                 => ('Gerente'),
      'COMPRAS'                 => ('Compras'),
      'ORCAMENTISTA'            => ('Orçamentista'),
      'PRODUCAO1'               => ('Produção 1'),
      'PRODUCAO2'               => ('Produção 2'),
      _                         => (role),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─── Dialog de criação/edição ─────────────────────────────────────────────────

class _UsuarioFormDialog extends StatefulWidget {
  final Map<String, dynamic>? usuario;
  final int? idUsuarioLogado;
  final VoidCallback onSalvo;
  final Future<bool> Function(VoidCallback onConfirmado)? onExcluir;

  const _UsuarioFormDialog({
    this.usuario,
    this.idUsuarioLogado,
    required this.onSalvo,
    this.onExcluir,
  });

  @override
  State<_UsuarioFormDialog> createState() => _UsuarioFormDialogState();
}

class _UsuarioFormDialogState extends State<_UsuarioFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _repo = UsuarioRepository();

  late final TextEditingController _nomeCtrl;
  late final TextEditingController _usernameCtrl;
  final TextEditingController _senhaCtrl = TextEditingController();

  String _role = 'COMPRAS';
  bool _ativo = true;
  bool _salvando = false;
  bool _excluindo = false;
  bool _mostrarSenha = false;
  String? _erroDialog;

  bool get _isEdicao => widget.usuario != null;

  /// True quando o usuário sendo editado é o próprio usuário logado —
  /// nesse caso ele não pode se autodesativar nem se autoexcluir, pois
  /// perderia acesso ao sistema sem outro admin ativo para reverter.
  bool get _isSelf =>
      _isEdicao &&
      widget.idUsuarioLogado != null &&
      widget.usuario!['id'] == widget.idUsuarioLogado;

  static const _roles = [
    'ADMIN',
    'GERENTE',
    'COMPRAS',
    'ORCAMENTISTA',
    'PRODUCAO1',
    'PRODUCAO2',
  ];

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    _nomeCtrl = TextEditingController(text: u?['nome'] as String? ?? '');
    _usernameCtrl =
        TextEditingController(text: u?['username'] as String? ?? '');
    _role = (u?['role'] as String? ?? 'COMPRAS').toUpperCase();
    if (!_roles.contains(_role)) _role = 'COMPRAS';
    _ativo = u?['ativo'] as bool? ?? true;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _usernameCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erroDialog = null;
    });

    try {
      final dados = <String, dynamic>{
        'nome': _nomeCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'role': _role,
        // Garante que o próprio usuário nunca seja salvo como inativo,
        // mesmo que _ativo tenha sido alterado por algum caminho que não
        // passe pelo Switch (defesa extra além do onChanged desabilitado).
        'ativo': _isSelf ? true : _ativo,
      };
      if (_senhaCtrl.text.isNotEmpty) dados['senha'] = _senhaCtrl.text;

      if (_isEdicao) {
        await _repo.atualizar(widget.usuario!['id'] as int, dados);
      } else {
        await _repo.criar(dados);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSalvo();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            _isEdicao
                ? 'Usuário atualizado com sucesso.'
                : 'Usuário criado com sucesso.',
          ),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erroDialog = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _excluir() async {
    if (widget.onExcluir == null) return;
    final excluido = await widget.onExcluir!(() {
      if (mounted) setState(() => _excluindo = true);
    });
    if (!mounted) return;
    if (excluido) {
      Navigator.of(context).pop();
    } else {
      setState(() => _excluindo = false);
    }
  }

  String _roleLabel(String role) => switch (role) {
    'ADMIN'        => 'Administrador',
    'GERENTE'      => 'Gerente',
    'COMPRAS'      => 'Compras',
    'ORCAMENTISTA' => 'Orçamentista',
    'PRODUCAO1'    => 'Produção 1',
    'PRODUCAO2'    => 'Produção 2',
    _              => role,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(_isEdicao ? 'Editar usuário' : 'Novo usuário'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Erro inline
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
                          onTap: () => setState(() => _erroDialog = null),
                          child: const Icon(Icons.close,
                              color: AppTheme.error, size: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Nome
                TextFormField(
                  controller: _nomeCtrl,
                  // Só autofoca ao criar um usuário novo; na edição não
                  // força o teclado/foco de cara.
                  autofocus: !_isEdicao,
                  decoration:
                      const InputDecoration(labelText: 'Nome'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Informe o nome'
                      : null,
                ),
                const SizedBox(height: 12),

                // Username
                TextFormField(
                  controller: _usernameCtrl,
                  enabled: !_isEdicao,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    helperText: _isEdicao
                        ? 'O username não pode ser alterado'
                        : null,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Informe o username'
                      : null,
                ),
                const SizedBox(height: 12),

                // Senha
                TextFormField(
                  controller: _senhaCtrl,
                  obscureText: !_mostrarSenha,
                  decoration: InputDecoration(
                    labelText:
                        _isEdicao ? 'Nova senha (opcional)' : 'Senha',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _mostrarSenha
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      onPressed: () =>
                          setState(() => _mostrarSenha = !_mostrarSenha),
                    ),
                  ),
                  validator: (v) {
                    if (!_isEdicao && (v == null || v.isEmpty)) {
                      return 'Informe uma senha';
                    }
                    if (v != null && v.isNotEmpty && v.length < 6) {
                      return 'A senha deve ter ao menos 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Cargo
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Cargo *'),
                  mouseCursor: SystemMouseCursors.click,
                  icon: const Icon(Icons.arrow_drop_down),
                  items: _roles
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(_roleLabel(r)),
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _role = v ?? _role),
                  validator: (v) =>
                      v == null ? 'Selecione um cargo' : null,
                ),
                const SizedBox(height: 16),

                // Status ativo
                Row(
                  children: [
                    Switch(
                      value: _ativo,
                      // Impede que o próprio usuário logado se desative:
                      // ele perderia acesso imediatamente e ninguém
                      // conseguiria reverter sem mexer direto no banco.
                      onChanged: _isSelf
                          ? null
                          : (v) => setState(() => _ativo = v),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppTheme.primary,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Usuário ativo',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _isSelf
                                ? 'Você não pode desativar seu próprio usuário'
                                : (_ativo
                                    ? 'Pode realizar login'
                                    : 'Não pode realizar login'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            if (_isEdicao && widget.onExcluir != null)
              TextButton(
                onPressed: (_salvando || _excluindo || _isSelf) ? null : _excluir,
                style: TextButton.styleFrom(foregroundColor: AppTheme.error).copyWith(
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                ),
                child: _excluindo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Excluir'),
              ),
            const Expanded(child: SizedBox.shrink()),
            TextButton(
              onPressed: (_salvando || _excluindo) ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom().copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_salvando || _excluindo) ? null : _salvar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary).copyWith(
                mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEdicao ? 'Salvar alterações' : 'Criar usuário'),
            ),
          ],
        ),
      ],
    );
  }
}
// ─── Aba de Configurações ─────────────────────────────────────────────────────

class _ConfiguracaoTab extends StatefulWidget {
  const _ConfiguracaoTab();

  @override
  State<_ConfiguracaoTab> createState() => _ConfiguracaoTabState();
}

class _ConfiguracaoTabState extends State<_ConfiguracaoTab> {
  final _repo = ConfiguracaoRepository();

  // ── Estado das faixas de markup ────────────────────────────────────────────
  List<MarkupFaixa> _faixas     = [];
  bool _carregandoFaixas        = true;
  bool _salvandoFaixas          = false;
  String? _erroFaixas;

  // ── Estado do imposto sobre sobra ──────────────────────────────────────────
  final _impostoCtrl = TextEditingController();
  bool _carregandoConfig        = true;
  bool _salvandoConfig          = false;
  String? _erroConfig;

  // ── Controladores das linhas de faixa ─────────────────────────────────────
  // Cada faixa tem 3 controladores: valorMin, valorMax, percentual
  final List<TextEditingController> _minCtrls   = [];
  final List<TextEditingController> _maxCtrls   = [];
  final List<TextEditingController> _pctCtrls   = [];

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  @override
  void dispose() {
    _impostoCtrl.dispose();
    for (final c in _minCtrls) {
      c.dispose();
    }
    for (final c in _maxCtrls) {
      c.dispose();
    }
    for (final c in _pctCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarTudo() async {
    await Future.wait([_carregarFaixas(), _carregarConfig()]);
  }

  Future<void> _carregarFaixas() async {
    setState(() { _carregandoFaixas = true; _erroFaixas = null; });
    try {
      final lista = await _repo.listarFaixas();
      _sincronizarControladores(lista);
      setState(() { _faixas = lista; _carregandoFaixas = false; });
    } catch (e) {
      setState(() { _erroFaixas = _mensagemErro(e); _carregandoFaixas = false; });
    }
  }

  Future<void> _carregarConfig() async {
    setState(() { _carregandoConfig = true; _erroConfig = null; });
    try {
      final cfg = await _repo.listarConfiguracoes();
      final v   = cfg['impostoSobra']?.toString() ?? '0';
      _impostoCtrl.text = v == '0' ? '' : v;
      setState(() => _carregandoConfig = false);
    } catch (e) {
      setState(() { _erroConfig = _mensagemErro(e); _carregandoConfig = false; });
    }
  }

  void _sincronizarControladores(List<MarkupFaixa> faixas) {
    // Limpa antigos
    for (final c in _minCtrls) {
      c.dispose();
    }
    for (final c in _maxCtrls) {
      c.dispose();
    }
    for (final c in _pctCtrls) {
      c.dispose();
    }
    _minCtrls.clear();
    _maxCtrls.clear();
    _pctCtrls.clear();

    for (final f in faixas) {
      _minCtrls.add(TextEditingController(text: _fmtNum(f.valorMin)));
      _maxCtrls.add(TextEditingController(text: f.valorMax != null ? _fmtNum(f.valorMax!) : ''));
      _pctCtrls.add(TextEditingController(text: _fmtNum(f.percentual)));
    }
  }

  void _adicionarFaixa() {
    final ultima = _faixas.isNotEmpty ? _faixas.last : null;
    // A nova faixa começa onde a anterior termina
    final novoMin = (ultima?.valorMax != null) ? ultima!.valorMax! + 0.01 : 0.0;
    final novaFaixa = MarkupFaixa(valorMin: novoMin, percentual: 0);
    setState(() {
      _faixas.add(novaFaixa);
      _minCtrls.add(TextEditingController(text: _fmtNum(novoMin)));
      _maxCtrls.add(TextEditingController(text: ''));  // aberta por padrão
      _pctCtrls.add(TextEditingController(text: ''));
    });
  }

  void _removerFaixa(int index) {
    setState(() {
      _minCtrls[index].dispose();
      _maxCtrls[index].dispose();
      _pctCtrls[index].dispose();
      _minCtrls.removeAt(index);
      _maxCtrls.removeAt(index);
      _pctCtrls.removeAt(index);
      _faixas.removeAt(index);
    });
  }

  Future<void> _salvarFaixas() async {
    // Constrói lista de faixas a partir dos controladores
    final List<MarkupFaixa> novas = [];
    for (int i = 0; i < _faixas.length; i++) {
      final min = double.tryParse(_minCtrls[i].text.replaceAll(',', '.'));
      final max = _maxCtrls[i].text.trim().isEmpty
          ? null
          : double.tryParse(_maxCtrls[i].text.replaceAll(',', '.'));
      final pct = double.tryParse(_pctCtrls[i].text.replaceAll(',', '.'));

      if (min == null || pct == null) {
        _snack('Preencha valorMin e percentual em todas as faixas.', erro: true);
        return;
      }
      if (max != null && max <= min) {
        _snack('O valor máximo da faixa ${i + 1} deve ser maior que o mínimo.', erro: true);
        return;
      }
      // Somente a última pode ter max nulo
      if (max == null && i < _faixas.length - 1) {
        _snack('Somente a última faixa pode ficar sem valor máximo.', erro: true);
        return;
      }
      novas.add(MarkupFaixa(valorMin: min, valorMax: max, percentual: pct));
    }

    setState(() => _salvandoFaixas = true);
    try {
      final salvas = await _repo.salvarFaixas(novas);
      _sincronizarControladores(salvas);
      setState(() { _faixas = salvas; _salvandoFaixas = false; });
      _snack('Faixas de markup salvas com sucesso.', erro: false);
    } catch (e) {
      setState(() => _salvandoFaixas = false);
      _snack(_mensagemErro(e), erro: true);
    }
  }

  Future<void> _salvarConfig() async {
    final txt = _impostoCtrl.text.trim().replaceAll(',', '.');
    final v   = double.tryParse(txt.isEmpty ? '0' : txt);
    if (v == null || v < 0 || v > 100) {
      _snack('O imposto sobre sobra deve ser um número entre 0 e 100.', erro: true);
      return;
    }
    setState(() => _salvandoConfig = true);
    try {
      await _repo.salvarConfiguracoes({'impostoSobra': v.toString()});
      setState(() => _salvandoConfig = false);
      _snack('Configuração salva com sucesso.', erro: false);
    } catch (e) {
      setState(() => _salvandoConfig = false);
      _snack(_mensagemErro(e), erro: true);
    }
  }

  void _snack(String msg, {required bool erro}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Seção Markup ────────────────────────────────────────────────
          _SecaoCard(
            titulo: 'Markup por faixa de valor',
            subtitulo:
                'Define o percentual de markup aplicado ao custo base do orçamento conforme o valor total. '
                'A última faixa (sem valor máximo) serve como padrão para qualquer valor acima.',
            icone: Icons.stacked_bar_chart_rounded,
            child: _carregandoFaixas
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                  )
                : _erroFaixas != null
                    ? _ErroInline(mensagem: _erroFaixas!, onRetry: _carregarFaixas)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Cabeçalho da tabela ──
                          if (_faixas.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  _ColLabel('De (R\$)',     flex: 2),
                                  const SizedBox(width: 8),
                                  _ColLabel('Até (R\$)',    flex: 2),
                                  const SizedBox(width: 8),
                                  _ColLabel('Markup (%)',   flex: 2),
                                  const SizedBox(width: 40), // espaço do botão excluir
                                ],
                              ),
                            ),

                          // ── Linhas de faixa ──
                          for (int i = 0; i < _faixas.length; i++)
                            _FaixaLinha(
                              key: ValueKey(i),
                              index:       i,
                              total:       _faixas.length,
                              minCtrl:     _minCtrls[i],
                              maxCtrl:     _maxCtrls[i],
                              pctCtrl:     _pctCtrls[i],
                              onRemover:   () => _removerFaixa(i),
                            ),

                          if (_faixas.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Nenhuma faixa cadastrada. Adicione ao menos uma faixa aberta '
                                '(sem valor máximo) para que o markup padrão seja aplicado.',
                                style: GoogleFonts.nunito(
                                    fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ),

                          const SizedBox(height: 12),

                          // ── Botões ──
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _adicionarFaixa,
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: Text('Adicionar faixa',
                                    style: GoogleFonts.nunito(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: const BorderSide(color: AppTheme.primary),
                                ).copyWith(
                                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                                ),
                              ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _salvandoFaixas ? null : _salvarFaixas,
                                icon: _salvandoFaixas
                                    ? const SizedBox(
                                        width: 14, height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.save_rounded, size: 16),
                                label: Text('Salvar faixas',
                                    style: GoogleFonts.nunito(fontSize: 13)),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary).copyWith(
                                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
          ),

          const SizedBox(height: 20),

          // ─── Seção Imposto sobre Sobra ────────────────────────────────────
          _SecaoCard(
            titulo: 'Imposto sobre sobra de material',
            subtitulo:
                'Percentual adicional aplicado ao custo de desperdício (sobra de chapas). '
                'Informe 0 para não aplicar imposto.',
            icone: Icons.content_cut_rounded,
            child: _carregandoConfig
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                  )
                : _erroConfig != null
                    ? _ErroInline(mensagem: _erroConfig!, onRetry: _carregarConfig)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 260,
                            child: TextField(
                              controller: _impostoCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]')),
                              ],
                              style: GoogleFonts.nunito(fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Imposto sobre sobra (%)',
                                hintText:  'Ex: 15',
                                suffixText: '%',
                                isDense:   true,
                                border:    OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AppTheme.primary, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _salvandoConfig ? null : _salvarConfig,
                                icon: _salvandoConfig
                                    ? const SizedBox(
                                        width: 14, height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.save_rounded, size: 16),
                                label: Text('Salvar',
                                    style: GoogleFonts.nunito(fontSize: 13)),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary).copyWith(
                                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Widget: linha de faixa de markup ─────────────────────────────────────────

class _FaixaLinha extends StatelessWidget {
  final int                    index;
  final int                    total;
  final TextEditingController  minCtrl;
  final TextEditingController  maxCtrl;
  final TextEditingController  pctCtrl;
  final VoidCallback           onRemover;

  const _FaixaLinha({
    super.key,
    required this.index,
    required this.total,
    required this.minCtrl,
    required this.maxCtrl,
    required this.pctCtrl,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    final cs          = Theme.of(context).colorScheme;
    final isUltima    = index == total - 1;

    Widget campo({
      required TextEditingController ctrl,
      required String hint,
      bool enabled = true,
      int flex = 2,
    }) =>
        Expanded(
          flex: flex,
          child: TextField(
            controller: ctrl,
            enabled:    enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: GoogleFonts.nunito(fontSize: 13),
            decoration: InputDecoration(
              hintText:   hint,
              hintStyle:  GoogleFonts.nunito(
                  fontSize: 12, color: cs.onSurfaceVariant),
              isDense:    true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(
                    color: cs.outline.withValues(alpha: 0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(
                    color: cs.outline.withValues(alpha: 0.4)),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(
                    color: cs.outline.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: const BorderSide(
                    color: AppTheme.primary, width: 1.5),
              ),
              filled:     true,
              fillColor:  enabled
                  ? cs.surface
                  : cs.surfaceContainerLow,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          campo(ctrl: minCtrl, hint: '0,00'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('→', style: TextStyle(color: Colors.grey)),
          ),
          isUltima
              ? Expanded(
                  flex: 2,
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Em aberto (padrão)',
                      style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              : campo(ctrl: maxCtrl, hint: '9999,99'),
          const SizedBox(width: 8),
          campo(ctrl: pctCtrl, hint: '400'),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: AppTheme.error,
            visualDensity: VisualDensity.compact,
            tooltip: 'Remover faixa',
            onPressed: onRemover,
            style: const ButtonStyle(
              mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widget: card de seção ────────────────────────────────────────────────────

class _SecaoCard extends StatelessWidget {
  final String   titulo;
  final String   subtitulo;
  final IconData icone;
  final Widget   child;

  const _SecaoCard({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color:        cs.surface,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(
            color: cs.outline.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color:        AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icone, size: 18, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: GoogleFonts.raleway(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    Text(subtitulo,
                        style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ─── Widget: label de coluna ──────────────────────────────────────────────────

class _ColLabel extends StatelessWidget {
  final String texto;
  final int    flex;

  const _ColLabel(this.texto, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        texto,
        style: GoogleFonts.nunito(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.5),
      ),
    );
  }
}

// ─── Widget: erro inline com retry ───────────────────────────────────────────

class _ErroInline extends StatelessWidget {
  final String       mensagem;
  final VoidCallback onRetry;

  const _ErroInline({required this.mensagem, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: AppTheme.error, size: 32),
          const SizedBox(height: 8),
          Text(mensagem,
              style: GoogleFonts.nunito(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Tentar novamente'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)
              .copyWith(mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click)),
          ),
        ],
      ),
    );
  }
}

// ─── Helper local ─────────────────────────────────────────────────────────────

String _fmtNum(double v) =>
    v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);