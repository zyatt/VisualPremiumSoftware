import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/usuario_provider.dart';
import '../widgets/app_shell.dart';

class InicioPage extends StatelessWidget {
  const InicioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<UsuarioProvider>().usuarioLogado;
    final scheme  = Theme.of(context).colorScheme;
    final isProducao = AppShell.isProducaoRole(usuario?.role);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Olá, ${usuario?.nome ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Bem-vindo ao Visual Premium', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 32),
            Expanded(
              child: isProducao
                  ? _buildProducaoCards()
                  : _buildGeralCards(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProducaoCards() {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.8,
      children: const [
        _DashCard(
          icon: Icons.precision_manufacturing_rounded,
          label: 'Produção',
          route: '/producao',
          color: Color(0xFF6C63FF),
        ),
      ],
    );
  }

  Widget _buildGeralCards() {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.8,
      children: const [
        _DashCard(icon: Icons.inventory_2,   label: 'Estoque',          route: '/estoque',          color: Color(0xFF6C63FF)),
        _DashCard(icon: Icons.people,        label: 'Fornecedores',      route: '/fornecedores',     color: Color(0xFF03DAC6)),
        _DashCard(icon: Icons.request_quote, label: 'Orçamento',         route: '/orcamento',        color: Color(0xFFFF9800)),
        _DashCard(icon: Icons.shopping_cart, label: 'Ordem de Compra',   route: '/ordem-compra',     color: Color(0xFF4CAF50)),
        _DashCard(icon: Icons.sync_alt,      label: 'Controle Estoque',  route: '/controle-estoque', color: Color(0xFFE91E63)),
        _DashCard(icon: Icons.history,       label: 'Histórico',         route: '/historico',        color: Color(0xFF9C27B0)),
        _DashCard(icon: Icons.description,   label: 'Relatório OS',      route: '/relatorio-os',     color: Color(0xFF2196F3)),
      ],
    );
  }
}

class _DashCard extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   route;
  final Color    color;
  const _DashCard({required this.icon, required this.label, required this.route, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}