import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/fornecedor_model.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/orcamento_provider.dart';
import '../repositories/orcamento_repository.dart';
import '../theme/app_theme.dart';
import 'orcamento_historico_page.dart';
import 'orcamento_editor_page.dart';

/// Remove prefixos como "Exception:", "HttpException:" que o Dart adiciona
/// automaticamente ao fazer e.toString() em exceções. Quando o erro é de
/// conexão (sem internet / servidor fora do ar), retorna uma mensagem
/// amigável contextualizada com a ação que estava sendo feita.
String _mensagemErro(Object e, {required String acao}) {
  final raw = e.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset') ||
      raw.contains('Failed host lookup') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('Network is unreachable')) {
    return 'Erro ao $acao: Verifique a conexão com o servidor.';
  }
  final msg = raw.replaceFirst(RegExp(r'^[\w]*[Ee]xception:\s*'), '').trim();
  return 'Erro ao $acao: $msg';
}
// ─── Formatters ───────────────────────────────

/// Bloqueia a digitação de vírgula em campos de texto livre (busca, título, descrição, etc.)
class _NoCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.contains(',')) {
      return oldValue;
    }
    return newValue;
  }
}

class OrcamentoPage extends StatefulWidget {
  const OrcamentoPage({super.key});

  @override
  State<OrcamentoPage> createState() => _OrcamentoPageState();
}

class _OrcamentoPageState extends State<OrcamentoPage>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;

  // ── Dados server-side ─────────────────────────────────────────────────────
  List<dynamic> _aguardandoAprovacao = [];
  List<dynamic> _aprovados = [];
  List<dynamic> _naoAprovados = [];
  bool _carregandoAprovacao = false;
  String? _erroAprovacao;

  bool _salvandoPreco = false;
  // (flags de edição foram movidos para OrcamentoTab no provider)

  // Campos de busca avançada de materiais
  final _searchIdCtrl = TextEditingController();
  final _searchNomeCtrl = TextEditingController();
  final _searchIdentificadorCtrl = TextEditingController();
  final _searchMedidaCtrl = TextEditingController();
  final _searchEspCtrl = TextEditingController();
  Timer? _debounceMatBusca;

  // Modo de ordenação da tabela de totais por fornecedor

  // _abaVisivel controla a visibilidade do editor inline (quando usado)

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this);
    _mainTabController.addListener(() {
      if (_mainTabController.indexIsChanging) return;
      _carregarOrcamentosServidor();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FornecedorProvider>().carregar();
      _carregarOrcamentosServidor();
    });
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _debounceMatBusca?.cancel();
    _searchIdCtrl.dispose();
    _searchNomeCtrl.dispose();
    _searchIdentificadorCtrl.dispose();
    _searchMedidaCtrl.dispose();
    _searchEspCtrl.dispose();
    super.dispose();
  }

  // ── Carregar orçamentos do servidor ──────────────────────────────────────────

  Future<void> _carregarOrcamentosServidor() async {
    if (!mounted) return;
    setState(() {
      _carregandoAprovacao = true;
      _erroAprovacao = null;
    });
    try {
      final repo = OrcamentoRepository();
      final aguardando = await repo.listar(status: 'AGUARDANDO_APROVACAO');
      final aprovados = await repo.listar(status: 'APROVADO');
      final naoAprovados = await repo.listar(status: 'NAO_APROVADO');
      if (!mounted) return;
      setState(() {
        _aguardandoAprovacao = aguardando;
        _aprovados = aprovados;
        _naoAprovados = naoAprovados;
      });
    } catch (e) {
      if (mounted) setState(() => _erroAprovacao = _mensagemErro(e, acao: 'carregar orçamentos'));
    } finally {
      if (mounted) setState(() => _carregandoAprovacao = false);
    }
  }

  // ── Enviar para aprovação ─────────────────────────────────────────────────────


  // ── Aprovar orçamento ─────────────────────────────────────────────────────────

  Future<void> _aprovarOrcamento(int id, String titulo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar Orçamento',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text(
          'Deseja aprovar este orçamento?\n\n'
          'Após a aprovação, o usuário Compras poderá gerar uma Ordem de Compra.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _carregandoAprovacao = true);
    try {
      await OrcamentoRepository().aprovar(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$id aprovado com sucesso!'),
          backgroundColor: AppTheme.success,
        ),
      );
      await _carregarOrcamentosServidor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'aprovar orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _carregandoAprovacao = false);
      }
    }
  }

  // ── Rejeitar orçamento ────────────────────────────────────────────────────────

  Future<void> _rejeitarOrcamento(int id, String titulo) async {
    final motivoCtrl = TextEditingController();
    bool mostrarErro = false;
    
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Rejeitar Orçamento',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informe o motivo da rejeição do orçamento "$titulo":',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Motivo *',
                  isDense: true,
                  errorText: mostrarErro && motivoCtrl.text.trim().isEmpty
                      ? 'O motivo é obrigatório'
                      : null,
                ),
                onChanged: (_) {
                  if (mostrarErro) {
                    setSt(() => mostrarErro = false);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () {
                if (motivoCtrl.text.trim().isEmpty) {
                  setSt(() => mostrarErro = true);
                  return;
                }
                Navigator.pop(ctx, motivoCtrl.text.trim());
              },
              child: const Text('Rejeitar'),
            ),
          ],
        ),
      ),
    );
    if (motivo == null || motivo.isEmpty) return;

    setState(() => _carregandoAprovacao = true);
    try {
      await OrcamentoRepository().rejeitar(id, motivo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$id rejeitado.'),
          backgroundColor: AppTheme.error,
        ),
      );
      await _carregarOrcamentosServidor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'rejeitar orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _carregandoAprovacao = false);
      }
    }
  }

  // ── Gerar OC a partir de orçamento aprovado ───────────────────────────────────
  // Abre o orçamento no editor com modoGerarOC=true para que a OC seja gerada
  // de lá, após o usuário selecionar os fornecedores desejados.

  Future<void> _gerarOCDeOrcamentoAprovado(Map<String, dynamic> orc) async {
    final provider = context.read<OrcamentoProvider>();
    final orcId = orc['id'] as int;

    // Se já existe uma aba aberta com esse servidorId, apenas navega para ela
    final abaExistente = provider.ativarAbaExistente(orcId);
    if (abaExistente >= 0) {
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
        );
        if (mounted) _carregarOrcamentosServidor();
      }
      return;
    }

    setState(() => _salvandoPreco = true);
    try {
      // Busca o orçamento completo sem alterar o status no servidor
      final orcamentoCompleto = await OrcamentoRepository().buscarPorId(orcId);
      final itens = (orcamentoCompleto['itens'] as List? ?? []);

      final Map<String, ItemOrcamentoData> itensPorChave = {};

      for (final item in itens) {
        final materialId = item['materialId'] as int;
        final materialData = item['material'] as Map<String, dynamic>?;
        final fornecedorId = item['fornecedorId'] as int?;
        final fornecedorData = item['fornecedor'] as Map<String, dynamic>?;
        final especifico = materialData?['especifico'] as bool? ?? false;

        final chave = especifico
            ? 'esp_${materialId}_${(item['descricaoItem'] as String? ?? '').trim().toLowerCase()}'
            : 'mat_$materialId';

        if (!itensPorChave.containsKey(chave)) {
          itensPorChave[chave] = ItemOrcamentoData(
            materialId: materialId,
            materialNome: materialData?['nome'] as String? ?? '',
            materialUnidade: materialData?['unidade'] as String?,
            materialCategoria: materialData?['categoria'] as String?,
            materialMedida: materialData?['medida'] as String?,
            materialEspessura: materialData?['espessura'] as String?,
            materialIdentificador: materialData?['identificador'] as String?,
            materialEspecifico: especifico,
            descricao: item['descricaoItem'] as String?,
            quantidade: double.tryParse(item['quantidade'].toString()) ?? 1,
            precos: {},
            modoOrcamento: (item['usarM2'] as bool? ?? false)
                ? ModoOrcamento.metroQuadrado
                : ModoOrcamento.unitario,
          );
        }

        if (fornecedorId != null && fornecedorData != null) {
          itensPorChave[chave]!.precos[fornecedorId] = PrecoFornecedorData(
            fornecedorNome: fornecedorData['nomeFantasia'] as String? ?? '',
            preco: item['precoUnitario'] != null
                ? double.tryParse(item['precoUnitario'].toString())
                : null,
            precoM2: item['precoM2'] != null
                ? double.tryParse(item['precoM2'].toString())
                : null,
          );

          if (item['selecionado'] as bool? ?? false) {
            itensPorChave[chave]!.fornecedorSelecionado = fornecedorId;
          }
        }
      }

      if (!mounted) return;

      provider.adicionarItensEmLote(
        orcamentoCompleto['titulo'] as String? ?? 'Orçamento #$orcId',
        itensPorChave.values.toList(),
      );

      provider.setServidorIdTab(orcId);
      provider.setFornecedoresOcultosTab(
        (orcamentoCompleto['fornecedoresOcultos'] as List? ?? []).map((e) => e as int).toList(),
      );
      // jaFinalizado=true mantém o orçamento somente-leitura, modoGerarOC=true
      // exibe o botão "Gerar OC" no editor.
      provider.atualizarFlagsTab(jaFinalizado: true, modoGerarOC: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$orcId aberto. Selecione os fornecedores e gere a OC.'),
          backgroundColor: AppTheme.success,
        ),
      );

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
      );
      if (mounted) _carregarOrcamentosServidor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'abrir orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  // ── Reabrir orçamento ─────────────────────────────────────────────────────────

  Future<void> _reabrirOrcamento(Map<String, dynamic> orc) async {
    final provider = context.read<OrcamentoProvider>();
    final orcId = orc['id'] as int;

    // Se já existe uma aba aberta com esse servidorId, apenas navega para ela
    final abaExistente = provider.ativarAbaExistente(orcId);
    if (abaExistente >= 0) {
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
        );
        if (mounted) _carregarOrcamentosServidor();
      }
      return;
    }

    setState(() => _salvandoPreco = true);
    try {
      // Busca o orçamento completo SEM alterar o status no servidor
      final orcamentoCompleto =
          await OrcamentoRepository().buscarPorId(orcId);

      final itens = (orcamentoCompleto['itens'] as List? ?? []);

      // Agrupa por materialId: cada material vira 1 ItemOrcamentoData com N precos
      // (um por fornecedor). Usa String como chave para suportar material específico
      // salvo mais de uma vez (usa itemId do DB como desambiguador).
      final Map<String, ItemOrcamentoData> itensPorChave = {};

      for (final item in itens) {
        final materialId = item['materialId'] as int;
        final materialData = item['material'] as Map<String, dynamic>?;
        final fornecedorId = item['fornecedorId'] as int?;
        final fornecedorData = item['fornecedor'] as Map<String, dynamic>?;
        final especifico = materialData?['especifico'] as bool? ?? false;

        // Materiais específicos são agrupados por materialId + descricaoItem,
        // pois cada combinação é um item distinto mas seus fornecedores devem
        // aparecer juntos. Genéricos: agrupados por materialId.
        final chave = especifico
            ? 'esp_${materialId}_${(item['descricaoItem'] as String? ?? '').trim().toLowerCase()}'
            : 'mat_$materialId';

        if (!itensPorChave.containsKey(chave)) {
          itensPorChave[chave] = ItemOrcamentoData(
            materialId: materialId,
            materialNome: materialData?['nome'] as String? ?? '',
            materialUnidade: materialData?['unidade'] as String?,
            materialCategoria: materialData?['categoria'] as String?,
            materialMedida: materialData?['medida'] as String?,
            materialEspessura: materialData?['espessura'] as String?,
            materialIdentificador: materialData?['identificador'] as String?,
            materialEspecifico: especifico,
            descricao: item['descricaoItem'] as String?,
            quantidade: double.tryParse(item['quantidade'].toString()) ?? 1,
            precos: {},
            modoOrcamento: (item['usarM2'] as bool? ?? false)
                ? ModoOrcamento.metroQuadrado
                : ModoOrcamento.unitario,
          );
        }

        if (fornecedorId != null && fornecedorData != null) {
          itensPorChave[chave]!.precos[fornecedorId] = PrecoFornecedorData(
            fornecedorNome: fornecedorData['nomeFantasia'] as String? ?? '',
            preco: item['precoUnitario'] != null
                ? double.tryParse(item['precoUnitario'].toString())
                : null,
            precoM2: item['precoM2'] != null
                ? double.tryParse(item['precoM2'].toString())
                : null,
          );

          if (item['selecionado'] as bool? ?? false) {
            itensPorChave[chave]!.fornecedorSelecionado = fornecedorId;
          }
        }
      }

      if (!mounted) return;

      provider.adicionarItensEmLote(
        orcamentoCompleto['titulo'] as String? ?? 'Orçamento #$orcId',
        itensPorChave.values.toList(),
      );

      provider.setServidorIdTab(orcId);
      provider.setFornecedoresOcultosTab(
        (orcamentoCompleto['fornecedoresOcultos'] as List? ?? []).map((e) => e as int).toList(),
      );

      final statusReaberto = orc['status'] as String? ?? '';
      provider.atualizarFlagsTab(
        aguardandoAprovacao: statusReaberto == 'AGUARDANDO_APROVACAO',
        jaFinalizado: statusReaberto == 'APROVADO' || statusReaberto == 'NAO_APROVADO',
        modoGerarOC: statusReaberto == 'APROVADO',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$orcId carregado para edição.'),
          backgroundColor: AppTheme.success,
        ),
      );

      // Navega para o editor
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
      );
      if (mounted) _carregarOrcamentosServidor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e, acao: 'carregar orçamento')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OrcamentoProvider>(
      builder: (context, provider, _) {
        if (!provider.carregado) {
          return Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho global ─────────────────────────────────────
                _buildHeader(),
                const SizedBox(height: 12),

                // ── Conteúdo: sempre o painel de aprovação ────────────────
                Expanded(child: _buildPainelAprovacao()),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Guias de orçamentos ──────────────────────────────────────────────────────


  // ── Painel de aprovação (exibido quando a aba ativa está vazia) ──────────────

  Widget _buildPainelAprovacao() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: TabBar(
            controller: _mainTabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Aguardando Aprovação'),
                    if (_aguardandoAprovacao.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.warning,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_aguardandoAprovacao.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'Aprovados'),
              const Tab(text: 'Não Aprovados'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _mainTabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildListaAprovacao(
                lista: _aguardandoAprovacao,
                emptyMessage: 'Nenhum orçamento aguardando aprovação',
                emptyIcon: Icons.pending_outlined,
                statusColor: AppTheme.warning,
                mostrarAcoes: true,
              ),
              _buildListaAprovacao(
                lista: _aprovados,
                emptyMessage: 'Nenhum orçamento aprovado',
                emptyIcon: Icons.check_circle_outline,
                statusColor: AppTheme.success,
              ),
              _buildListaAprovacao(
                lista: _naoAprovados,
                emptyMessage: 'Nenhum orçamento não aprovado',
                emptyIcon: Icons.cancel_outlined,
                statusColor: AppTheme.error,
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orçamento',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            SizedBox(height: 2),
            Text(
              'Orçar e comparar valores entre fornecedores',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),

        const Spacer(),

        // Botão Orçamentos em andamento
        Consumer<OrcamentoProvider>(
          builder: (context, provider, _) {
            final temAbas = provider.abas.isNotEmpty;
            return OutlinedButton.icon(
              onPressed: temAbas
                  ? () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const OrcamentoEditorPage()),
                      );
                      if (mounted) _carregarOrcamentosServidor();
                    }
                  : null,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.edit_note, size: 16),
                  if (temAbas)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppTheme.warning,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${provider.abas.length}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              label: Text(
                'Aberto',
                style: TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: temAbas ? AppTheme.warning : Theme.of(context).colorScheme.outline,
                side: BorderSide(
                    color: temAbas ? AppTheme.warning : Theme.of(context).colorScheme.outlineVariant),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            );
          },
        ),

        const SizedBox(width: 12),

        FilledButton.icon(
          onPressed: () async {
            final p = context.read<OrcamentoProvider>();
            p.adicionarAba();
            p.atualizarFlagsTab(modoEdicao: true);
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrcamentoEditorPage()),
            );
            if (mounted) _carregarOrcamentosServidor();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text(
            'Novo Orçamento',
            style: TextStyle(fontSize: 13),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),

        const SizedBox(width: 12),

        OutlinedButton.icon(
          onPressed: () async {
            final resultado = await Navigator.of(context).push<dynamic>(
              MaterialPageRoute(
                builder: (_) => const OrcamentoHistoricoPage(),
              ),
            );

            if (!mounted) return;

            if (resultado is Map &&
                resultado['reabrirServidorId'] != null) {
              // A reabertura já configura a aba no provider via _reabrirOrcamento
            }
          },
          icon: Icon(Icons.history, size: 16),
          label: Text(
            'Histórico',
            style: TextStyle(fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
          ),
        ),

        SizedBox(width: 12),

        IconButton(
          onPressed: () => _carregarOrcamentosServidor(),
          icon: Icon(
            Icons.refresh,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          tooltip: 'Atualizar',
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),

        if (_salvandoPreco) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  // ignore: unused_element
  Widget _buildHeaderEdicao(OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () {
            context.read<OrcamentoProvider>().atualizarFlagsTab(
              aguardandoAprovacao: false, jaFinalizado: false, modoGerarOC: false);
            context.read<OrcamentoProvider>().fecharAbaAposOperacao();
          },
          icon: Icon(Icons.arrow_back_ios_new, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.tabAtual?.titulo ?? 'Orçamento',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            SizedBox(height: 2),
            Text(
              'Orçar e comparar valores entre fornecedores',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const Spacer(),
        if (_salvandoPreco) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
          ),
        ],
      ],
    );
  }

  Widget _buildListaAprovacao({
    required List<dynamic> lista,
    required String emptyMessage,
    required IconData emptyIcon,
    required Color statusColor,
    bool mostrarAcoes = false,
  }) {
    if (_carregandoAprovacao) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_erroAprovacao != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: AppTheme.error),
            SizedBox(height: 12),
            Text(
              'Erro ao carregar orçamentos',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              _erroAprovacao!.contains(': ')
                  ? _erroAprovacao!.substring(_erroAprovacao!.indexOf(': ') + 2)
                  : _erroAprovacao!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _carregarOrcamentosServidor,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }

    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(emptyIcon, size: 36, color: statusColor),
            ),
            SizedBox(height: 20),
            Text(
              emptyMessage,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _carregarOrcamentosServidor(),
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Atualizar'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => _carregarOrcamentosServidor(),
              icon: Icon(Icons.refresh, size: 15),
              label: Text('Atualizar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.separated(
            itemCount: lista.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final orc = lista[i] as Map<String, dynamic>;
              return _OrcamentoAprovacaoCard(
                orcamento: orc,
                statusColor: statusColor,
                mostrarAcoes: mostrarAcoes,
                onAprovar: mostrarAcoes
                    ? () => _aprovarOrcamento(orc['id'] as int, orc['titulo'] as String? ?? '')
                    : null,
                onRejeitar: mostrarAcoes
                    ? () => _rejeitarOrcamento(orc['id'] as int, orc['titulo'] as String? ?? '')
                    : null,
                onReabrir: () => _reabrirOrcamento(orc),
                onGerarOC: orc['status'] == 'APROVADO' ? () => _gerarOCDeOrcamentoAprovado(orc) : null,
              );
            },
          ),
        ),
      ],
    );
  }






}

// ─── Campo de descrição com controller persistente ───────────────────────────

class _DescricaoField extends StatefulWidget {
  final String? valorInicial;
  final ValueChanged<String> onChanged;

  const _DescricaoField({
    required this.valorInicial,
    required this.onChanged,
  });

  @override
  State<_DescricaoField> createState() => _DescricaoFieldState();
}

class _DescricaoFieldState extends State<_DescricaoField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.valorInicial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:_ctrl,
      maxLines: 2,
      inputFormatters: [_NoCommaFormatter()],
      decoration: InputDecoration(
        hintText: 'Especificação do material',
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        errorText: _ctrl.text.trim().isEmpty ? 'Descrição obrigatória' : null,
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
    );
  }
}

// ─── Card de orçamento para aprovação ────────────────────────────────────────

class _OrcamentoAprovacaoCard extends StatelessWidget {
  final Map<String, dynamic> orcamento;
  final Color statusColor;
  final bool mostrarAcoes;
  final VoidCallback? onAprovar;
  final VoidCallback? onRejeitar;
  final VoidCallback? onReabrir;
  final VoidCallback? onGerarOC;

  const _OrcamentoAprovacaoCard({
    required this.orcamento,
    required this.statusColor,
    this.mostrarAcoes = false,
    this.onAprovar,
    this.onRejeitar,
    this.onReabrir,
    this.onGerarOC,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = orcamento['titulo'] as String? ?? 'Orçamento';
    final itens = (orcamento['itens'] as List? ?? []);
    
    // Conta materiais únicos (não duplicados por fornecedor)
    final materiaisUnicos = <int>{};
    for (final item in itens) {
      final materialId = item['materialId'] as int?;
      if (materialId != null) materiaisUnicos.add(materialId);
    }
    
    final criadoEm = orcamento['criadoEm'] != null
        ? DateTime.tryParse(orcamento['criadoEm'] as String)
        : null;
    final criadorNome = orcamento['criador']?['nome'] as String?;
    final aprovadoEm = orcamento['aprovadoEm'] != null
        ? DateTime.tryParse(orcamento['aprovadoEm'] as String)
        : null;
    final aprovadorNome = orcamento['aprovador']?['nome'] as String?;
    final motivoRejeicao = orcamento['motivoRejeicao'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: statusColor.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.description_outlined,
                      size: 18, color: statusColor),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (criadoEm != null)
                        Text(
                          [
                            'Criado em ${criadoEm.day.toString().padLeft(2, '0')}/${criadoEm.month.toString().padLeft(2, '0')}/${criadoEm.year}',
                            if (criadorNome != null) 'por $criadorNome',
                          ].join(' '),
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                        ),
                      if (aprovadoEm != null)                                      // ← adicionar bloco
                        Text(
                          [
                            'Aprovado em ${aprovadoEm.day.toString().padLeft(2, '0')}/${aprovadoEm.month.toString().padLeft(2, '0')}/${aprovadoEm.year}',
                            if (aprovadorNome != null) 'por $aprovadorNome',
                          ].join(' '),
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                        ),
                    ],
                  ),
                ),
                Text(
                  '#${orcamento['id']}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    SizedBox(width: 6),
                    Text(
                      '${materiaisUnicos.length} ${materiaisUnicos.length == 1 ? 'material' : 'materiais'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (aprovadorNome != null) ...[
                      SizedBox(width: 16),
                      Icon(Icons.person_outline,
                          size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(width: 4),
                      Text(
                        aprovadorNome,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),

                if (motivoRejeicao != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: AppTheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Motivo da rejeição',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.error,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                motivoRejeicao,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Aba "Aguardando Aprovação": Reabrir + Rejeitar + Aprovar
                    if (mostrarAcoes) ...[
                      OutlinedButton.icon(
                        onPressed: onReabrir,
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text('Reabrir', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: onRejeitar,
                        icon: const Icon(Icons.close, size: 14),
                        label: const Text('Rejeitar',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: onAprovar,
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text('Aprovar',
                            style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                      ),
                    ]
                    // Aba "Aprovados": apenas Gerar OC
                    else if (onGerarOC != null) ...[
                      FilledButton.icon(
                        onPressed: onGerarOC,
                        icon: const Icon(Icons.shopping_cart_checkout, size: 14),
                        label: const Text('Gerar OC',
                            style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                      ),
                    ]
                    // Demais abas (Não Aprovados, etc.): apenas Reabrir
                    else
                      FilledButton.icon(
                        onPressed: onReabrir,
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text('Reabrir', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
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

// ─── Sub-widgets (reutilizados) ───────────────────────────────────────────────

// ignore: unused_element
class _MaterialChip extends StatelessWidget {
  final String nome;
  final bool selecionado;
  final bool especifico;
  final String? descricao;
  final VoidCallback onRemover;

  const _MaterialChip({
    required this.nome,
    required this.selecionado,
    required this.especifico,
    required this.onRemover,
  }) : descricao = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selecionado
            ? AppTheme.statusOk.withValues(alpha: 0.08)
            : AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selecionado
              ? AppTheme.statusOk.withValues(alpha: 0.4)
              : AppTheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selecionado)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, size: 11, color: AppTheme.statusOk),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nome,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selecionado ? AppTheme.statusOk : AppTheme.primary,
                    ),
                  ),
                  if (especifico) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'ESP',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (especifico && descricao != null && descricao!.isNotEmpty)
                Text(
                  descricao!,
                  style: TextStyle(
                    fontSize: 10,
                    color: selecionado
                        ? AppTheme.statusOk.withValues(alpha: 0.8)
                        : AppTheme.primary.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemover,
            child: Icon(
              Icons.close,
              size: 13,
              color: selecionado
                  ? AppTheme.statusOk.withValues(alpha: 0.7)
                  : AppTheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantidadeField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _QuantidadeField({required this.value, required this.onChanged});

  @override
  State<_QuantidadeField> createState() => _QuantidadeFieldState();
}

class _QuantidadeFieldState extends State<_QuantidadeField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value.toStringAsFixed(widget.value % 1 == 0 ? 0 : 2));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
      ],
      decoration: InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        if (parsed != null && parsed > 0) widget.onChanged(parsed);
      },
    );
  }
}

class _DialogVincularFornecedores extends StatefulWidget {
  final List<FornecedorModel> fornecedores;
  final Set<int> idsJaVinculados;
  final String materialNome;

  const _DialogVincularFornecedores({
    required this.fornecedores,
    required this.idsJaVinculados,
    required this.materialNome,
  });

  @override
  State<_DialogVincularFornecedores> createState() =>
      _DialogVincularFornecedoresState();
}

class _DialogVincularFornecedoresState
    extends State<_DialogVincularFornecedores> {
  final Set<int> _selecionados = {};
  final _buscaCtrl = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disponiveis = widget.fornecedores
        .where((f) => !widget.idsJaVinculados.contains(f.id))
        .toList();

    final filtrados = _filtro.isEmpty
        ? disponiveis
        : disponiveis
            .where((f) =>
                f.nomeFantasia.toLowerCase().contains(_filtro.toLowerCase()) ||
                (f.cnpj != null && f.cnpj!.contains(_filtro)))
            .toList();

    return AlertDialog(
      title: Text('Adicionar Fornecedores — ${widget.materialNome}',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _buscaCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar fornecedor...',
                prefixIcon: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.outline),
                suffixIcon: _filtro.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.outline),
                        onPressed: () {
                          _buscaCtrl.clear();
                          setState(() => _filtro = '');
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            if (_selecionados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 13, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${_selecionados.length} selecionado${_selecionados.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 280),
              child: disponiveis.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                          'Todos os fornecedores já estão vinculados a este material.',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  : filtrados.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              Icon(Icons.search_off, size: 16, color: Theme.of(context).colorScheme.outline),
                              SizedBox(width: 8),
                              Text(
                                'Nenhum fornecedor encontrado para "$_filtro".',
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                          itemBuilder: (ctx, i) {
                            final f = filtrados[i];
                            return CheckboxListTile(
                              dense: true,
                              title: Text(f.nomeFantasia,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: f.cnpj != null
                                  ? Text(f.cnpj!, style: const TextStyle(fontSize: 11))
                                  : null,
                              value: _selecionados.contains(f.id),
                              activeColor: AppTheme.primary,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selecionados.add(f.id);
                                } else {
                                  _selecionados.remove(f.id);
                                }
                              }),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _selecionados.isEmpty
              ? null
              : () => Navigator.pop(context, _selecionados.toList()),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

class _DialogEditarPreco extends StatefulWidget {
  final String fornecedorNome;
  final String materialNome;
  final double? precoAtual;
  final double? precoM2Atual;

  const _DialogEditarPreco({
    required this.fornecedorNome,
    required this.materialNome,
  }) : precoAtual = null, precoM2Atual = null;

  @override
  State<_DialogEditarPreco> createState() => _DialogEditarPrecoState();
}

class _DialogEditarPrecoState extends State<_DialogEditarPreco> {
  late final TextEditingController _precoCtrl;
  late final TextEditingController _precoM2Ctrl;

  @override
  void initState() {
    super.initState();
    _precoCtrl = TextEditingController(
        text: widget.precoAtual != null
            ? widget.precoAtual!.toStringAsFixed(2)
            : '');
    _precoM2Ctrl = TextEditingController(
        text: widget.precoM2Atual != null
            ? widget.precoM2Atual!.toStringAsFixed(2)
            : '');
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
    _precoM2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Editar Preço — ${widget.fornecedorNome}',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.materialNome,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: _precoCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Preço unitário (R\$)',
                prefixText: 'R\$ ',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _precoM2Ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Preço por m² (R\$)',
                prefixText: 'R\$ ',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () {
            final preco = double.tryParse(
                _precoCtrl.text.replaceAll(',', '.'));
            final precoM2 = double.tryParse(
                _precoM2Ctrl.text.replaceAll(',', '.'));
            Navigator.pop(context, {
              'preco': preco,
              'precoM2': precoM2,
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _DialogDescartarOrcamento extends StatefulWidget {
  const _DialogDescartarOrcamento();

  @override
  State<_DialogDescartarOrcamento> createState() =>
      _DialogDescartarOrcamentoState();
}

class _DialogDescartarOrcamentoState
    extends State<_DialogDescartarOrcamento> {
  final _ctrl = TextEditingController();
  bool _vazio = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cancelar Orçamento',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Este orçamento será movido para o histórico como cancelado.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Motivo do cancelamento *',
              hintText: 'Explique o motivo pelo qual está cancelando...',
              isDense: true,
              errorText: _vazio ? 'Informe o motivo do cancelamento' : null,
            ),
            onChanged: (_) {
              if (_vazio && _ctrl.text.trim().isNotEmpty) {
                setState(() => _vazio = false);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: () {
            if (_ctrl.text.trim().isEmpty) {
              setState(() => _vazio = true);
              return;
            }
            Navigator.pop(context, _ctrl.text.trim());
          },
          child: const Text('Cancelar Orçamento'),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _DialogOpcaoOC extends StatelessWidget {
  final List<ItemOrcamentoData> itens;
  const _DialogOpcaoOC({required this.itens});

  @override
  Widget build(BuildContext context) {
    final fornecedores = itens
        .where((i) => i.fornecedorSelecionado != null)
        .map((i) => i.precos[i.fornecedorSelecionado!]?.fornecedorNome ?? '')
        .toSet();

    return AlertDialog(
      title: const Text('Gerar Ordem de Compra',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${itens.length} ${itens.length == 1 ? 'material' : 'materiais'} selecionados · '
            '${fornecedores.length} ${fornecedores.length == 1 ? 'fornecedor' : 'fornecedores'}',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const Text('Como deseja gerar a OC?',
              style: TextStyle(fontSize: 13)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, 'existente'),
          child: const Text('Adicionar a OC existente'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () => Navigator.pop(context, 'nova'),
          child: const Text('Criar nova OC'),
        ),
      ],
    );
  }
}