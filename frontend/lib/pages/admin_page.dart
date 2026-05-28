import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../repositories/usuario_repository.dart';
import '../theme/app_theme.dart';

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
    _tabController = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gerencie usuários e configurações do sistema',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── TabBar ──────────────────────────────────────────────────────
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppTheme.primary,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
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
              ],
            ),
            const Divider(height: 1, color: AppTheme.divider),
            const SizedBox(height: 16),

            // ── Conteúdo ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _UsuariosTab(),
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
      setState(() => _erro = e.toString().replaceFirst('Exception: ', ''));
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
    showDialog(
      context: context,
      builder: (_) => _UsuarioFormDialog(usuario: usuario, onSalvo: _carregar),
    );
  }

  Future<void> _excluir(Map<String, dynamic> usuario) async {
    final nome = usuario['nome'] as String? ?? 'usuário';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Excluir usuário'),
        content: Text(
          'Deseja excluir "$nome"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      await _repo.excluir(usuario['id'] as int);
      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Usuário excluído.'),
          backgroundColor: AppTheme.textSecondary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.error,
        ));
      }
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
                    ?.copyWith(color: AppTheme.textSecondary),
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
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                          const Icon(Icons.cloud_off_outlined,
                              size: 48, color: AppTheme.error),
                          const SizedBox(height: 12),
                          Text(
                            _erro!,
                            style: const TextStyle(
                                color: AppTheme.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _carregar,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tentar novamente'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    )
                  : _usuarios.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_outline_rounded,
                                  size: 64, color: AppTheme.textHint),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum usuário cadastrado',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: AppTheme.textSecondary),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Clique em "Novo usuário" para começar.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppTheme.textHint),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            // Cabeçalho
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppTheme.background,
              child: const Row(
                children: [
                  Expanded(flex: 3, child: _HeaderCell('Nome')),
                  Expanded(flex: 2, child: _HeaderCell('Username')),
                  Expanded(flex: 2, child: _HeaderCell('Cargo')),
                  Expanded(flex: 2, child: _HeaderCell('Status')),
                  SizedBox(width: 80, child: _HeaderCell('Ações')),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.divider),

            // Linhas
            Expanded(
              child: ListView.separated(
                itemCount: usuarios.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppTheme.divider),
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
        : AppTheme.surface;

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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          u['nome'] as String? ?? '-',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
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
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
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

                // Ações
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBtn(
                      icon: Icons.edit_rounded,
                      color: AppTheme.primary,
                      tooltip: 'Editar',
                      onPressed: () => widget.onEditar(u),
                    ),
                    const SizedBox(width: 4),
                    _IconBtn(
                      icon: Icons.delete_outline_rounded,
                      color: AppTheme.error,
                      tooltip: 'Excluir',
                      onPressed: () => widget.onExcluir(u),
                    ),
                  ],
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
      color: AppTheme.surface,
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
      style: const TextStyle(
        color: AppTheme.textSecondary,
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
      'ADMIN'               => ('Administrador'),
      'GERENTE'             => ('Gerente'),
      'COMPRAS'             => ('Compras'),
      'PRODUCAO' || 'PRODUÇÃO' => ('Produção'),
      _                     => (role),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.textSecondary,
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
  final VoidCallback onSalvo;

  const _UsuarioFormDialog({this.usuario, required this.onSalvo});

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
  bool _mostrarSenha = false;
  String? _erroDialog;

  bool get _isEdicao => widget.usuario != null;

  static const _roles = ['ADMIN', 'GERENTE', 'COMPRAS', 'PRODUCAO'];

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
        'ativo': _ativo,
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

  String _roleLabel(String role) => switch (role) {
        'ADMIN'    => 'Administrador',
        'GERENTE'  => 'Gerente',
        'COMPRAS'  => 'Compras',
        'PRODUCAO' => 'Produção',
        _          => role,
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
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
                        color: AppTheme.textHint,
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
                  items: _roles
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(_roleLabel(r)),
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
                      onChanged: (v) => setState(() => _ativo = v),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Usuário ativo',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _ativo
                              ? 'Pode realizar login'
                              : 'Não pode realizar login',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
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
    );
  }
}