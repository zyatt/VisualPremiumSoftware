import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/material_model.dart';
import '../models/fornecedor_model.dart';
import '../providers/material_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/orcamento_provider.dart';
import '../repositories/fornecedor_repository.dart';
import '../repositories/orcamento_repository.dart';
import '../repositories/ordem_compra_repository.dart';
import '../theme/app_theme.dart';
import 'orcamento_historico_page.dart';
import '../models/ordem_compra_model.dart';
import 'ordem_compra_page.dart';

// ─── Helpers ──────────────────────────────────

String _brl(double? v) {
  if (v == null || v == 0) return '—';
  return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

// ─── Page ─────────────────────────────────────

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

  List<MaterialModel> _resultadosBusca = [];
  bool _buscando = false;
  bool _salvandoPreco = false;
  bool _mostrarResultados = false;

  // Modo de edição: null = lista inicial, true = editando orçamento
  bool? _modoEdicao;
  
  // ID do orçamento sendo editado (quando reabrindo do servidor)
  int? _orcamentoServidorId;

  // Impede que o build() restaure o modo edição quando o usuário voltou intencionalmente
  bool _ignorarRestauracaoAba = false;

  // true somente quando o orçamento foi reaberto com status AGUARDANDO_APROVACAO
  // (nesse caso faz sentido aprovar diretamente, em vez de reenviar)
  bool _orcamentoAguardandoAprovacao = false;
  
  // Modo especial: gerar OC de orçamento aprovado
  bool _modoGerarOC = false;

  // Campos de busca avançada de materiais
  final _searchIdCtrl = TextEditingController();
  final _searchNomeCtrl = TextEditingController();
  final _searchIdentificadorCtrl = TextEditingController();
  final _searchMedidaCtrl = TextEditingController();
  final _searchEspCtrl = TextEditingController();
  Timer? _debounceMatBusca;

  // Modo de ordenação da tabela de totais por fornecedor
  String _ordemTotais = 'unitario';

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
      if (mounted) setState(() => _erroAprovacao = e.toString());
    } finally {
      if (mounted) setState(() => _carregandoAprovacao = false);
    }
  }

  // ── Enviar para aprovação ─────────────────────────────────────────────────────

  Future<void> _enviarParaAprovacao() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um material antes de enviar para aprovação.')),
      );
      return;
    }

    final tituloCtrl = TextEditingController(text: tab.titulo);
    final novoTitulo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          bool vazio = false;
          return AlertDialog(
            title: const Text('Enviar para Aprovação',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nome do orçamento:',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tituloCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Ex: Orçamento Obra Abril',
                      isDense: true,
                      errorText: null,
                    ),
                    onChanged: (_) {
                      if (vazio && tituloCtrl.text.trim().isNotEmpty) {
                        setSt(() => vazio = false);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Após o envio, aguarde Admin/Gerente aprovar antes de gerar a Ordem de Compra.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () {
                  if (tituloCtrl.text.trim().isEmpty) {
                    setSt(() => vazio = true);
                    return;
                  }
                  Navigator.pop(ctx, tituloCtrl.text.trim());
                },
                child: const Text('Enviar para Aprovação'),
              ),
            ],
          );
        },
      ),
    );
    if (novoTitulo == null) return;

    provider.renomearAba(provider.abaAtiva, novoTitulo);

    setState(() => _salvandoPreco = true);
    try {
      final repo = OrcamentoRepository();
      int orcId;

      if (_orcamentoServidorId != null) {
        orcId = _orcamentoServidorId!;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});
        final atual = await repo.buscarPorId(orcId);
        final itensAtuais =
            (atual['itens'] as List? ?? []).cast<Map<String, dynamic>>();
        for (final item in itensAtuais) {
          try {
            await repo.removerItem(orcId, item['id'] as int);
          } catch (_) {}
        }
      } else {
        final criado = await repo.criar(novoTitulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});
      }

      for (final item in tab.itens) {
        if (item.precos.isEmpty) {
          // Item sem fornecedor/preço — envia mesmo assim para não perder o material
          await repo.adicionarItem(orcId, {
            'materialId': item.materialId,
            'fornecedorId': null,
            'quantidade': item.quantidade,
            'precoUnitario': null,
            'precoM2': null,
            'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado,
            'selecionado': false,
            'descricaoItem': item.descricao,
          });
        } else {
          for (final entry in item.precos.entries) {
            final fId = entry.key;
            final pf = entry.value;
            await repo.adicionarItem(orcId, {
              'materialId': item.materialId,
              'fornecedorId': fId,
              'quantidade': item.quantidade,
              'precoUnitario': pf.preco,
              'precoM2': pf.precoM2,
              'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado,
              'selecionado': item.fornecedorSelecionado == fId,
              'descricaoItem': item.descricao,
            });
          }
        }
      }

      await repo.enviarParaAprovacao(orcId);

      // Limpa o orçamento local
      provider.limparAba();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$orcId enviado para aprovação com sucesso!'),
          backgroundColor: AppTheme.success,
        ),
      );
      
      // Volta para lista inicial
      setState(() {
        _modoEdicao = null;
        _orcamentoServidorId = null;
        _modoGerarOC = false;
        _ignorarRestauracaoAba = false;
        _orcamentoAguardandoAprovacao = false;
      });
      await _carregarOrcamentosServidor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar para aprovação: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

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
            content: Text('Erro ao aprovar: $e'),
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
            content: Text('Erro ao rejeitar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
        setState(() => _carregandoAprovacao = false);
      }
    }
  }

  // ── Gerar OC a partir de orçamento aprovado ───────────────────────────────────

  Future<void> _gerarOCDeOrcamentoAprovado(Map<String, dynamic> orc) async {
    setState(() => _salvandoPreco = true);
    try {
      final result = await OrcamentoRepository().gerarOrdemCompra(orc['id'] as int);
      if (!mounted) return;
      if (result['pronto'] == true) {
        final orcamento = result['orcamento'] as Map<String, dynamic>;
        final itens = (orcamento['itens'] as List? ?? []);
        
        // Agrupa por material, usando chave composta para não colapsar
        // materiais específicos com mesmo materialId.
        final Map<String, ItemOrcamentoData> itensPorChave = {};
        
        for (final item in itens) {
          final materialId = item['materialId'] as int;
          final materialData = item['material'] as Map<String, dynamic>?;
          final fornecedorId = item['fornecedorId'] as int?;
          final fornecedorData = item['fornecedor'] as Map<String, dynamic>?;
          final especifico = materialData?['especifico'] as bool? ?? false;

          final chave = especifico ? 'esp_${item['id']}' : 'mat_$materialId';
          
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

        final provider = context.read<OrcamentoProvider>();
        provider.adicionarItensEmLote(
          'OC - ${orcamento['titulo'] ?? '#${orcamento['id']}'}',
          itensPorChave.values.toList(),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Itens carregados no orçamento. Agora gere a OC normalmente.'),
            backgroundColor: AppTheme.success,
          ),
        );
        
        setState(() {
          _modoEdicao = true;
          _modoGerarOC = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar OC: $e'),
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
    setState(() => _salvandoPreco = true);
    try {
      // Busca o orçamento completo SEM alterar o status no servidor
      final orcamentoCompleto =
          await OrcamentoRepository().buscarPorId(orc['id'] as int);

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

        // Materiais específicos podem aparecer mais de uma vez com o mesmo
        // materialId — cada ocorrência é um item independente.
        final chave = especifico ? 'esp_${item['id']}' : 'mat_$materialId';

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

      final provider = context.read<OrcamentoProvider>();
      provider.adicionarItensEmLote(
        orcamentoCompleto['titulo'] as String? ?? 'Orçamento #${orc['id']}',
        itensPorChave.values.toList(),
      );

      provider.setServidorIdTab(orc['id'] as int);

      setState(() {
        _modoEdicao = true;
        _ignorarRestauracaoAba = false;
        _orcamentoServidorId = orc['id'] as int;
        _orcamentoAguardandoAprovacao =
            (orc['status'] as String? ?? '') == 'AGUARDANDO_APROVACAO';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #${orc['id']} carregado para edição.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar orçamento: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  // ── Busca de materiais ────────────────────────────────────────────────────────

  void _agendarBuscaMateriais() {
    _debounceMatBusca?.cancel();
    _debounceMatBusca = Timer(
      const Duration(milliseconds: 400),
      _executarBuscaMateriais,
    );
  }

  Future<void> _executarBuscaMateriais() async {
    final id = _searchIdCtrl.text.trim();
    final nome = _searchNomeCtrl.text.trim();
    final identificador = _searchIdentificadorCtrl.text.trim();
    final medida = _searchMedidaCtrl.text.trim();
    final esp = _searchEspCtrl.text.trim();

    final algumFiltro = id.isNotEmpty || nome.isNotEmpty || identificador.isNotEmpty ||
        medida.isNotEmpty || esp.isNotEmpty;

    if (!algumFiltro) {
      setState(() {
        _resultadosBusca = [];
        _mostrarResultados = false;
      });
      return;
    }

    setState(() {
      _buscando = true;
      _mostrarResultados = true;
    });

    try {
      await context.read<MaterialProvider>().carregar(
        busca: nome.isNotEmpty ? nome : '',
        id: id.isNotEmpty ? id : '',
        identificador: identificador.isNotEmpty ? identificador : '',
        medida: medida.isNotEmpty ? medida : '',
        espessura: esp.isNotEmpty ? esp : '',
      );
      if (!mounted) return;
      final todos = context.read<MaterialProvider>().materiais;
      final provider = context.read<OrcamentoProvider>();

      final idsNormaisJaAdicionados = provider.tabAtual?.itens
              .where((i) => !i.materialEspecifico)
              .map((i) => i.materialId)
              .toSet() ??
          {};

      setState(() {
        _resultadosBusca = todos
            .where((m) => m.especifico || !idsNormaisJaAdicionados.contains(m.id))
            .toList();
      });
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _adicionarMaterial(MaterialModel material) {
    final provider = context.read<OrcamentoProvider>();
    final precos = <int, PrecoFornecedorData>{};
    for (final fm in material.fornecedorMateriais) {
      precos[fm.fornecedorId] = PrecoFornecedorData(
        fornecedorNome: fm.fornecedorNome,
        preco: fm.preco > 0 ? fm.preco : null,
        precoM2: fm.precoMetroQuadrado > 0 ? fm.precoMetroQuadrado : null,
      );
    }
    provider.adicionarItem(ItemOrcamentoData(
      materialId: material.id,
      materialNome: material.nome,
      materialUnidade: material.unidade,
      materialCategoria: material.categoria,
      materialMedida: material.medida,
      materialEspessura: material.espessura,
      materialIdentificador: material.identificador,
      materialStatus: material.status,
      materialEspecifico: material.especifico,
      precos: precos,
    ));
    _searchIdCtrl.clear();
    _searchNomeCtrl.clear();
    _searchIdentificadorCtrl.clear();
    _searchMedidaCtrl.clear();
    _searchEspCtrl.clear();
    setState(() {
      _resultadosBusca = [];
      _mostrarResultados = false;
    });
  }

  // ── Vincular fornecedores ─────────────────────────────────────────────────────

  Future<void> _vincularFornecedores(int itemIndex) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || itemIndex >= tab.itens.length) return;

    final item = tab.itens[itemIndex];
    final fornecedores = context.read<FornecedorProvider>().fornecedores;
    final idsJaVinculados = item.precos.keys.toSet();

    final selecionados = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _DialogVincularFornecedores(
        fornecedores: fornecedores,
        idsJaVinculados: idsJaVinculados,
        materialNome: item.materialNome,
      ),
    );

    if (selecionados == null || selecionados.isEmpty) return;

    final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
    for (final fId in selecionados) {
      if (!novosPrecos.containsKey(fId)) {
        final f = fornecedores.firstWhere((f) => f.id == fId);
        novosPrecos[fId] = PrecoFornecedorData(fornecedorNome: f.nomeFantasia);
      }
    }
    provider.atualizarItemParcial(item.itemId, precos: novosPrecos);

    final repo = FornecedorRepository();
    for (final fId in selecionados) {
      if (!idsJaVinculados.contains(fId)) {
        try {
          await repo.vincularMaterial(fId, {'materialId': item.materialId});
        } catch (_) {}
      }
    }
  }

  // ── Editar preço ──────────────────────────────────────────────────────────────

  Future<void> _editarPreco(int itemIndex, int fornecedorId) async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || itemIndex >= tab.itens.length) return;
    final item = tab.itens[itemIndex];
    final pf = item.precos[fornecedorId]!;

    final result = await showDialog<Map<String, double?>>(
      context: context,
      builder: (ctx) => _DialogEditarPreco(
        fornecedorNome: pf.fornecedorNome,
        materialNome: item.materialNome,
        precoAtual: pf.preco,
        precoM2Atual: pf.precoM2,
      ),
    );

    if (result == null) return;

    final novosPrecos = Map<int, PrecoFornecedorData>.from(item.precos);
    novosPrecos[fornecedorId] = PrecoFornecedorData(
      fornecedorNome: pf.fornecedorNome,
      preco: result['preco'],
      precoM2: result['precoM2'],
    );
    provider.atualizarItemParcial(item.itemId, precos: novosPrecos);

    setState(() => _salvandoPreco = true);
    try {
      await FornecedorRepository().atualizarPreco(
        fornecedorId,
        item.materialId,
        {
          if (result['preco'] != null) 'preco': result['preco'],
          if (result['precoM2'] != null) 'precoMetroQuadrado': result['precoM2'],
        },
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  // ── Gerar OC ─────────────────────────────────

  Future<void> _gerarOrdemCompra() async {
    final provider = context.read<OrcamentoProvider>();
    final itens = provider.tabAtual?.itens ?? [];
    final opcao = await showDialog<String>(
      context: context,
      builder: (ctx) => _DialogOpcaoOC(itens: itens),
    );
    if (opcao == null) return;

    if (opcao == 'nova') {
      await _criarNovaOC(itens);
    } else {
      await _adicionarOCExistente(itens);
    }
  }

  // ── Exportar PDF ─────────────────────────────────────────────────────────────

  Future<void> _exportarPdf() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Adicione ao menos um material antes de exportar.')),
      );
      return;
    }

    setState(() => _salvandoPreco = true);

    try {
      final dadosOrcamento = {
        'titulo': tab.titulo,
        'itens': tab.itens.map((item) => item.toJson()).toList(),
      };

      final pdfBytes = await OrcamentoRepository().gerarPdf(dadosOrcamento);

      final hoje = DateTime.now();
      final dataStr =
          '${hoje.day.toString().padLeft(2, '0')}-'
          '${hoje.month.toString().padLeft(2, '0')}-'
          '${hoje.year}';
      final nomeArquivo = 'orcamento($dataStr).pdf';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$nomeArquivo');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (Platform.isWindows) {
        await Process.run('explorer', [file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF exportado com sucesso!'),
            backgroundColor: AppTheme.success,
          ),
        );
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
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  Future<void> _criarNovaOC(List<ItemOrcamentoData> itens) async {
    final fornecedorId = itens.first.fornecedorSelecionado!;
    final fornecedores = context.read<FornecedorProvider>().fornecedores;
    final FornecedorModel? fornecedorInicial = fornecedores.cast<FornecedorModel?>()
        .firstWhere((f) => f?.id == fornecedorId, orElse: () => null);

    final itensPre = itens.map((item) {
      final fId = item.fornecedorSelecionado!;
      final pf = item.precos[fId]!;
      final usarM2 = item.modoOrcamento == ModoOrcamento.metroQuadrado
          || (item.modoOrcamento == null && pf.precoM2 != null && pf.precoM2! > 0);
      return ItemPreCarregadoOC(
        materialId: item.materialId,
        materialNome: item.materialNome,
        materialEspecifico: item.materialEspecifico,
        quantidade: item.quantidade,
        precoUnitario: pf.preco ?? 0,
        precoMetroQuadrado: pf.precoM2,
        usarM2: usarM2,
        descricao: item.descricao,
      );
    }).toList();

    final resultado = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => NovaOrdemCompraPage(
          itensPreCarregados: itensPre,
          fornecedorInicial: fornecedorInicial,
        ),
      ),
    );

    if (resultado == null || !mounted) return;

    context.read<OrcamentoProvider>().limparAba();

    if (resultado is OrdemCompraModel) {
      context.go('/ordem-compra', extra: resultado.id);
    } else {
      context.go('/ordem-compra');
    }
  }

  Future<void> _adicionarOCExistente(List<ItemOrcamentoData> itens) async {
    List<dynamic> ocsEmAndamento = [];
    try {
      final repo = OrdemCompraRepository();
      final todas = await repo.listar();
      ocsEmAndamento = todas.where((o) => o['status'] == 'EM_ANDAMENTO').toList();
    } catch (_) {}

    if (!mounted) return;

    if (ocsEmAndamento.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nenhuma OC em andamento encontrada. Crie uma nova OC.')),
      );
      return;
    }

    final ocSelecionada = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _DialogSelecionarOC(ocs: ocsEmAndamento),
    );
    if (ocSelecionada == null) return;

    if (!mounted) return;

    final fornecedorIdOrcamento = itens.first.fornecedorSelecionado!;
    final fornecedorIdOC = ocSelecionada['fornecedor']?['id'] as int?;

    if (fornecedorIdOC != null && fornecedorIdOC != fornecedorIdOrcamento) {
      final fornecedorNomeAtual =
          ocSelecionada['fornecedor']?['nomeFantasia'] as String? ?? '—';
      final fornecedorNomeNovo =
          itens.first.precos[fornecedorIdOrcamento]?.fornecedorNome ?? '—';

      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Substituir fornecedor?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Text(
            'Esta OC está vinculada a "$fornecedorNomeAtual".\n\n'
            'Ao continuar, o fornecedor será substituído por "$fornecedorNomeNovo".',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Substituir e continuar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
      if (!mounted) return;
    }

    try {
      final repo = OrdemCompraRepository();
      final ocId = ocSelecionada['id'] as int;

      for (final item in itens) {
        final fId = item.fornecedorSelecionado!;
        final pf = item.precos[fId]!;
        final usarM2 = item.modoOrcamento == ModoOrcamento.metroQuadrado
            || (item.modoOrcamento == null && pf.precoM2 != null && pf.precoM2! > 0);
        await repo.adicionarItem(ocId, {
          'materialId': item.materialId,
          'numeroOS': 'OS-GERAL',
          'quantidade': item.quantidade,
          'precoUnitario': pf.preco ?? 0,
          'precoMetroQuadrado': pf.precoM2,
          'usarM2': usarM2,
          if (item.descricao != null && item.descricao!.isNotEmpty)
            'descricaoItem': item.descricao,
        });
      }

      await repo.atualizar(ocId, {'fornecedorId': fornecedorIdOrcamento});

      if (mounted) {
        context.read<OrcamentoProvider>().limparAba();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Itens adicionados à OC #$ocId com sucesso!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar à OC: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  // ── Salvar / Cancelar ────────────────────────────────────────────────────────

  Future<void> _salvarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;
    if (tab == null || tab.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Adicione ao menos um material para salvar.')),
      );
      return;
    }

    // Dialog com campo para o nome do orçamento
    final tituloCtrl = TextEditingController(text: tab.titulo);
    final novoTitulo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          bool vazio = false;
          return AlertDialog(
            title: Text(
              tab.servidorId != null ? 'Atualizar Orçamento' : 'Salvar Orçamento',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nome do orçamento:',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tituloCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Ex: Orçamento Obra Abril',
                      isDense: true,
                      errorText: null,
                    ),
                    onChanged: (_) {
                      if (vazio && tituloCtrl.text.trim().isNotEmpty) {
                        setSt(() => vazio = false);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                onPressed: () {
                  if (tituloCtrl.text.trim().isEmpty) {
                    setSt(() => vazio = true);
                    return;
                  }
                  Navigator.pop(ctx, tituloCtrl.text.trim());
                },
                child: Text(tab.servidorId != null ? 'Atualizar' : 'Salvar'),
              ),
            ],
          );
        },
      ),
    );
    if (novoTitulo == null) return;

    provider.renomearAba(provider.abaAtiva, novoTitulo);

    setState(() => _salvandoPreco = true);
    try {
      final repo = OrcamentoRepository();
      int orcId;

      if (tab.servidorId != null) {
        orcId = tab.servidorId!;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});

        final atual = await repo.buscarPorId(orcId);
        final itensAtuais =
            (atual['itens'] as List? ?? []).cast<Map<String, dynamic>>();
        for (final item in itensAtuais) {
          try {
            await repo.removerItem(orcId, item['id'] as int);
          } catch (_) {}
        }
      } else {
        final criado = await repo.criar(novoTitulo);
        orcId = criado['id'] as int;
        await repo.atualizarOrcamento(orcId, {'titulo': novoTitulo});
      }

      final tabAtualizado = provider.tabAtual!;
      for (final item in tabAtualizado.itens) {
        if (item.precos.isEmpty) {
          // Item sem fornecedor/preço — envia mesmo assim para não perder o material
          await repo.adicionarItem(orcId, {
            'materialId': item.materialId,
            'fornecedorId': null,
            'quantidade': item.quantidade,
            'precoUnitario': null,
            'precoM2': null,
            'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado,
            'selecionado': false,
            'descricaoItem': item.descricao,
          });
        } else {
          for (final entry in item.precos.entries) {
            final fId = entry.key;
            final pf = entry.value;
            await repo.adicionarItem(orcId, {
              'materialId': item.materialId,
              'fornecedorId': fId,
              'quantidade': item.quantidade,
              'precoUnitario': pf.preco,
              'precoM2': pf.precoM2,
              'usarM2': item.modoOrcamento == ModoOrcamento.metroQuadrado,
              'selecionado': item.fornecedorSelecionado == fId,
              'descricaoItem': item.descricao,
            });
          }
        }
      }

      provider.fecharAbaAposOperacao();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento #$orcId salvo com sucesso!'),
          backgroundColor: AppTheme.success,
        ),
      );
      setState(() {
        _modoEdicao = null;
        _orcamentoServidorId = null;
        _modoGerarOC = false;
        _ignorarRestauracaoAba = false;
        _orcamentoAguardandoAprovacao = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  Future<void> _cancelarOrcamento() async {
    final provider = context.read<OrcamentoProvider>();
    final tab = provider.tabAtual;

    // Pede motivo apenas se o orçamento já existe no servidor
    final temServidorId = tab?.servidorId != null;

    String? motivo;
    if (temServidorId) {
      motivo = await showDialog<String>(
        context: context,
        builder: (_) => const _DialogDescartarOrcamento(),
      );
      if (motivo == null) return; // usuário fechou o dialog
    } else {
      // Rascunho local puro: confirma descarte simples
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar Orçamento',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: const Text(
            'Este orçamento ainda não foi salvo no servidor.\n'
            'Deseja descartar o rascunho?',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não')),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    setState(() => _salvandoPreco = true);
    try {
      if (temServidorId) {
        // Cancela no servidor
        await OrcamentoRepository().cancelar(tab!.servidorId!);
      }

      // Fecha aba local
      provider.fecharAbaAposOperacao();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(temServidorId
              ? 'Orçamento #${tab!.servidorId} cancelado.'
              : 'Rascunho descartado.'),
          backgroundColor: AppTheme.error,
        ),
      );
      setState(() {
        _modoEdicao = null;
        _orcamentoServidorId = null;
        _modoGerarOC = false;
        _ignorarRestauracaoAba = false;
        _orcamentoAguardandoAprovacao = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cancelar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoPreco = false);
    }
  }

  // ── Totais ────────────────────────────────────────────────────────────────────

  Map<int, Map<String, dynamic>> _calcularTotaisPorFornecedor(
      List<ItemOrcamentoData> itens) {
    final Map<int, Map<String, dynamic>> totais = {};
    
    // Conta materiais únicos (não duplicados por fornecedor)
    final totalMateriais = itens.length;
    
    for (final item in itens) {
      for (final entry in item.precos.entries) {
        final fId = entry.key;
        final pf = entry.value;
        if (!totais.containsKey(fId)) {
          totais[fId] = {
            'nome': pf.fornecedorNome,
            'total': 0.0,
            'totalM2': 0.0,
            'totalEfetivo': 0.0,
            'materiais': 0,
            'materiaisComPreco': 0,
            'totalMateriais': totalMateriais,
            'temTodosPrecos': true,
          };
        }
        totais[fId]!['materiais'] = (totais[fId]!['materiais'] as int) + 1;

        if (pf.preco != null) {
          totais[fId]!['total'] =
              (totais[fId]!['total'] as double) + pf.preco! * item.quantidade;
          totais[fId]!['totalEfetivo'] =
              (totais[fId]!['totalEfetivo'] as double) + pf.preco! * item.quantidade;
          totais[fId]!['materiaisComPreco'] =
              (totais[fId]!['materiaisComPreco'] as int) + 1;
        } else {
          totais[fId]!['temTodosPrecos'] = false;
        }

        if (pf.precoM2 != null) {
          totais[fId]!['totalM2'] =
              (totais[fId]!['totalM2'] as double) + pf.precoM2! * item.quantidade;
        }
      }
    }
    return totais;
  }

  double? _mediaPreco(ItemOrcamentoData item) {
    final precos =
        item.precos.values.map((p) => p.preco).whereType<double>().toList();
    if (precos.isEmpty) return null;
    return precos.reduce((a, b) => a + b) / precos.length;
  }

  double? _mediaPrecoM2(ItemOrcamentoData item) {
    final precos =
        item.precos.values.map((p) => p.precoM2).whereType<double>().toList();
    if (precos.isEmpty) return null;
    return precos.reduce((a, b) => a + b) / precos.length;
  }

  Set<int> _todosFornecedoresIds(List<ItemOrcamentoData> itens) {
    final ids = <int>{};
    for (final item in itens) {
      ids.addAll(item.precos.keys);
    }
    return ids;
  }

  bool _podeGerarOC(List<ItemOrcamentoData> itens) {
    if (itens.isEmpty) return false;
    if (!itens.every((i) => i.fornecedorSelecionado != null)) return false;
    
    for (final item in itens) {
      if (item.materialEspecifico && 
          (item.descricao == null || item.descricao!.trim().isEmpty)) {
        return false;
      }
    }
    
    final ids = itens.map((i) => i.fornecedorSelecionado!).toSet();
    return ids.length == 1;
  }

  int _fornecedoresSelecionados(List<ItemOrcamentoData> itens) {
    return itens
        .where((i) => i.fornecedorSelecionado != null)
        .map((i) => i.fornecedorSelecionado!)
        .toSet()
        .length;
  }

  // ── Build ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<OrcamentoProvider>(
      builder: (context, provider, _) {
        if (!provider.carregado) {
          return const Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }

        // Restaura estado ao voltar para a página (ex: navegou para outra rota e voltou)
        if (_modoEdicao == null && !_ignorarRestauracaoAba) {
          final tab = provider.tabAtual;
          // Considera "em edição" se tiver itens OU se já tiver um servidorId
          // (usuário criou, adicionou itens, navegou, voltou)
          if (tab != null && (tab.itens.isNotEmpty || tab.servidorId != null)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _modoEdicao = true;
                  _orcamentoServidorId = tab.servidorId;
                });
              }
            });
          }
        }

        // Se está em modo de edição, mostra o editor
        if (_modoEdicao == true) {
          final tab = provider.tabAtual;
          final itens = tab?.itens ?? [];
          
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderEdicao(provider, itens),
                  const SizedBox(height: 16),
                  _buildBarraAcoes(provider, itens),
                  const SizedBox(height: 16),
                  _buildSelecaoMateriais(provider, itens),
                  const SizedBox(height: 16),
                  Expanded(
                    child: itens.isEmpty
                        ? _buildEmptyState()
                        : _buildConteudo(provider, itens),
                  ),
                ],
              ),
            ),
          );
        }

        // Caso contrário, mostra a lista inicial de orçamentos
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),

                Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(bottom: BorderSide(color: AppTheme.divider)),
                  ),
                  child: TabBar(
                    controller: _mainTabController,
                    labelColor: AppTheme.primary,
                    unselectedLabelColor: AppTheme.textSecondary,
                    indicatorColor: AppTheme.primary,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Aguardando Aprovação'),
                            if (_aguardandoAprovacao.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
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
                    children:[
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
            ),
          ),
        );
      },
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
                  ?.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Orçar e comparar valores entre fornecedores',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () {
            // Apenas inicializa a aba local — o servidor SÓ é chamado
            // ao salvar ou enviar para aprovação.
            context.read<OrcamentoProvider>().novoOrcamento('Novo Orçamento');
            setState(() {
              _modoEdicao = true;
              _orcamentoServidorId = null; // ainda não existe no banco
              _modoGerarOC = false;
            });
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Novo Orçamento', style: TextStyle(fontSize: 13)),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final resultado = await Navigator.of(context).push<dynamic>(
              MaterialPageRoute(
                  builder: (_) => const OrcamentoHistoricoPage()),
            );
            if (!mounted) return;
            if (resultado is Map && resultado['reabrirServidorId'] != null) {
              setState(() {
                _modoEdicao = true;
                _orcamentoServidorId = resultado['reabrirServidorId'] as int;
                _modoGerarOC = false;
              });
            }
          },
          icon: const Icon(Icons.history, size: 16),
          label: const Text('Histórico', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            side: const BorderSide(color: AppTheme.divider),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
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

  Widget _buildHeaderEdicao(OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () {
            setState(() {
              _modoEdicao = null;
              _modoGerarOC = false;
              _ignorarRestauracaoAba = true;
              _orcamentoAguardandoAprovacao = false;
            });
          },
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.textSecondary),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: const BorderSide(color: AppTheme.divider),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.tabAtual?.titulo ?? 'Orçamento',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Orçar e comparar valores entre fornecedores',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary),
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
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Text('Erro ao carregar: $_erroAprovacao',
                style: const TextStyle(color: AppTheme.error)),
            const SizedBox(height: 12),
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
            const SizedBox(height: 20),
            Text(
              emptyMessage,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _carregarOrcamentosServidor,
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
              onPressed: _carregarOrcamentosServidor,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Atualizar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
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

  Widget _buildSelecaoMateriais(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Selecionar Materiais',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (itens.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${itens.length} selecionados',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (itens.isNotEmpty)
                  TextButton.icon(
                    onPressed: provider.limparAba,
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Limpar', style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _searchIdCtrl,
                        decoration: InputDecoration(
                          labelText: 'ID',
                          prefixIcon: const Icon(Icons.tag, size: 16, color: AppTheme.textHint),
                          isDense: true,
                          suffixIcon: _buscando && _searchIdCtrl.text.isNotEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppTheme.primary),
                                  ),
                                )
                              : null,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => _agendarBuscaMateriais(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchNomeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nome do material',
                          prefixIcon: _buscando && _searchNomeCtrl.text.isNotEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppTheme.primary),
                                  ),
                                )
                              : const Icon(Icons.search, size: 18, color: AppTheme.textHint),
                          isDense: true,
                        ),
                        onChanged: (_) => _agendarBuscaMateriais(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchIdentificadorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Identificador',
                          prefixIcon: Icon(Icons.qr_code_outlined,
                              size: 16, color: AppTheme.textHint),
                          isDense: true,
                        ),
                        onChanged: (_) => _agendarBuscaMateriais(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchMedidaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Medida',
                          prefixIcon: Icon(Icons.straighten_outlined,
                              size: 16, color: AppTheme.textHint),
                          isDense: true,
                        ),
                        onChanged: (_) => _agendarBuscaMateriais(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchEspCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Espessura',
                          prefixIcon: Icon(Icons.layers_outlined,
                              size: 16, color: AppTheme.textHint),
                          isDense: true,
                        ),
                        onChanged: (_) => _agendarBuscaMateriais(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Limpar filtros',
                      icon: const Icon(Icons.filter_alt_off,
                          size: 18, color: AppTheme.textHint),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _searchIdCtrl.clear();
                        _searchNomeCtrl.clear();
                        _searchIdentificadorCtrl.clear();
                        _searchMedidaCtrl.clear();
                        _searchEspCtrl.clear();
                        setState(() {
                          _resultadosBusca = [];
                          _mostrarResultados = false;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_mostrarResultados && (_buscando || _resultadosBusca.isNotEmpty))
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 4)),
                ],
              ),
              child: _buscando
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: CircularProgressIndicator(color: AppTheme.primary)),
                    )
                  : _resultadosBusca.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.search_off,
                                  size: 16, color: AppTheme.textHint),
                              SizedBox(width: 8),
                              Text('Nenhum material encontrado.',
                                  style: TextStyle(
                                      color: AppTheme.textHint, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _resultadosBusca.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppTheme.divider),
                          itemBuilder: (ctx, i) {
                            final m = _resultadosBusca[i];
                            final sub = [
                              m.categoria,
                              m.medida,
                              m.espessura,
                              m.identificador,
                              m.unidade
                            ].where((s) => s != null && s.isNotEmpty).join(' · ');
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 2),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      m.nome,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary),
                                    ),
                                  ),
                                  if (m.especifico)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Específico',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: sub.isNotEmpty
                                  ? Text(sub,
                                      style: const TextStyle(
                                          fontSize: 11, color: AppTheme.textSecondary))
                                  : null,
                              trailing: _StatusChip(status: m.status),
                              onTap: () => _adicionarMaterial(m),
                            );
                          },
                        ),
            ),

          if (itens.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: itens.asMap().entries.map((e) {
                  final item = e.value;
                  final selecionado = item.fornecedorSelecionado != null;
                  return _MaterialChip(
                    nome: item.materialNome,
                    selecionado: selecionado,
                    especifico: item.materialEspecifico,
                    descricao: item.descricao,
                    onRemover: () => provider.removerItem(item.itemId),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBarraAcoes(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    final podeGerar = _podeGerarOC(itens);
    final fornsSel = _fornecedoresSelecionados(itens);
    
    final materiaisEspecificosSemDescricao = itens
        .where((i) => i.materialEspecifico && 
                     (i.descricao == null || i.descricao!.trim().isEmpty))
        .length;

    // Determina qual botão mostrar: "Enviar para Aprovação" ou "Aprovar"
    // Só mostra "Aprovar" se o orçamento foi reaberto com status AGUARDANDO_APROVACAO
    final bool mostrarBotaoAprovar = _orcamentoAguardandoAprovacao;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${itens.length} ${itens.length == 1 ? 'material' : 'materiais'} — '
                    '$fornsSel ${fornsSel == 1 ? 'fornecedor selecionado' : 'fornecedores selecionados'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _salvarOrcamento,
                  icon: const Icon(Icons.save_outlined, size: 15),
                  label: const Text('Salvar', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.success,
                    side: const BorderSide(color: AppTheme.success),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),

                OutlinedButton.icon(
                  onPressed: _cancelarOrcamento,
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),

                OutlinedButton.icon(
                  onPressed: itens.isEmpty ? null : _exportarPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                  label: const Text('Exportar PDF', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.divider),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),

                if (mostrarBotaoAprovar)
                  OutlinedButton.icon(
                    onPressed: itens.isEmpty ? null : () async {
                      if (_orcamentoServidorId == null) return;
                      await _aprovarOrcamento(_orcamentoServidorId!, provider.tabAtual?.titulo ?? '');
                      setState(() {
                        _modoEdicao = null;
                        _orcamentoServidorId = null;
                        _modoGerarOC = false;
                        _ignorarRestauracaoAba = false;
                        _orcamentoAguardandoAprovacao = false;
                      });
                      provider.limparAba();
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 15),
                    label: const Text('Aprovar', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.success,
                      side: const BorderSide(color: AppTheme.success),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: itens.isEmpty ? null : _enviarParaAprovacao,
                    icon: const Icon(Icons.send_outlined, size: 15),
                    label: const Text('Enviar para Aprovação', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.warning,
                      side: const BorderSide(color: AppTheme.warning),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                const SizedBox(width: 8),
                if (_modoGerarOC)
                  Tooltip(
                    message: podeGerar
                        ? 'Gerar Ordem de Compra'
                        : materiaisEspecificosSemDescricao > 0
                            ? 'Preencha a descrição dos materiais específicos'
                            : 'Selecione o MESMO fornecedor para todos os materiais',
                    child: FilledButton.icon(
                      onPressed: podeGerar ? _gerarOrdemCompra : null,
                      icon: const Icon(Icons.shopping_cart_checkout, size: 16),
                      label: Text(
                        'Gerar OC (${itens.length})',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.request_quote_outlined,
                size: 36, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhum material adicionado',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use a busca acima para adicionar materiais ao orçamento\ne comparar valores entre fornecedores.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudo(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    return ListView(
      children: [
        if (_todosFornecedoresIds(itens).isNotEmpty) ...[
          _buildTabelaComparativa(provider, itens),
          const SizedBox(height: 16),
        ],
        ...itens.asMap().entries.map(
            (e) => _buildItemCard(provider, e.key, e.value, itens)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildItemCard(OrcamentoProvider provider, int index,
      ItemOrcamentoData item, List<ItemOrcamentoData> todosItens) {
    final usarM2 = item.modoOrcamento == ModoOrcamento.metroQuadrado;
    final allFornIds = item.precos.keys.toList();

    final menorPreco = allFornIds
        .map((id) => item.precos[id]?.preco)
        .whereType<double>()
        .fold<double?>(
            null, (min, v) => min == null || v < min ? v : min);

    final menorPrecoM2 = allFornIds
        .map((id) => item.precos[id]?.precoM2)
        .whereType<double>()
        .fold<double?>(
            null, (min, v) => min == null || v < min ? v : min);

    allFornIds.sort((a, b) {
      final aMenorUnit = menorPreco != null && item.precos[a]?.preco == menorPreco;
      final aMenorM2 = menorPrecoM2 != null && item.precos[a]?.precoM2 == menorPrecoM2;
      final bMenorUnit = menorPreco != null && item.precos[b]?.preco == menorPreco;
      final bMenorM2 = menorPrecoM2 != null && item.precos[b]?.precoM2 == menorPrecoM2;
      final aAmbos = aMenorUnit && aMenorM2;
      final bAmbos = bMenorUnit && bMenorM2;
      if (aAmbos && !bAmbos) return -1;
      if (bAmbos && !aAmbos) return 1;
      final pa = usarM2
          ? (item.precos[a]?.precoM2 ?? double.infinity)
          : (item.precos[a]?.preco ?? double.infinity);
      final pb = usarM2
          ? (item.precos[b]?.precoM2 ?? double.infinity)
          : (item.precos[b]?.preco ?? double.infinity);
      return pa.compareTo(pb);
    });

    final media = _mediaPreco(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      size: 16, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.materialNome,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (item.materialEspecifico)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Específico',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if ([
                        item.materialCategoria,
                        item.materialMedida,
                        item.materialEspessura,
                        item.materialIdentificador,
                        item.materialUnidade
                      ].any((s) => s != null && s.isNotEmpty))
                        Text(
                          [
                            item.materialCategoria,
                            item.materialMedida,
                            item.materialEspessura,
                            item.materialIdentificador,
                            item.materialUnidade
                          ].where((s) => s != null && s.isNotEmpty).join(' · '),
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Text('Quantidade',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: _QuantidadeField(
                        value: item.quantidade,
                        onChanged: (v) => provider.atualizarItemParcial(item.itemId,
                            quantidade: v),
                      ),
                    ),
                    if (item.materialUnidade != null &&
                        item.materialUnidade!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(item.materialUnidade!,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
                const SizedBox(width: 12),
                if (item.modoOrcamento == ModoOrcamento.unitario &&
                    media != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bar_chart,
                            size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Média unitária ${_brl(media)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ] else if (item.modoOrcamento == ModoOrcamento.metroQuadrado &&
                    _mediaPrecoM2(item) != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.square_foot,
                            size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Média m² ${_brl(_mediaPrecoM2(item))}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                _StatusChip(status: item.materialStatus ?? ''),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Remover material',
                  color: AppTheme.textHint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => provider.removerItem(item.itemId),
                ),
              ],
            ),
          ),

          if (item.materialEspecifico)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.03),
                border: const Border(
                  bottom: BorderSide(color: AppTheme.divider),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.description_outlined, size: 14, color: AppTheme.primary),
                      SizedBox(width: 6),
                      Text(
                        'Descrição do material específico *',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DescricaoField(
                    valorInicial: item.descricao,
                    onChanged: (v) => provider.atualizarItemParcial(
                      item.itemId,
                      descricao: v,
                    ),
                  ),
                ],
              ),
            ),

          if (allFornIds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppTheme.textHint),
                  SizedBox(width: 8),
                  Text(
                    'Nenhum fornecedor vinculado. Clique em "Adicionar Fornecedor" para comparar valores.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      const Text(
                        'Orçar por:',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      _ModoButton(
                        label: 'Unidade',
                        icon: Icons.tag,
                        selecionado: item.modoOrcamento == ModoOrcamento.unitario,
                        onTap: () => provider.atualizarItemParcial(
                          item.itemId,
                          modoOrcamento: item.modoOrcamento == ModoOrcamento.unitario
                              ? null
                              : ModoOrcamento.unitario,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ModoButton(
                        label: 'm²',
                        icon: Icons.square_foot,
                        selecionado: item.modoOrcamento == ModoOrcamento.metroQuadrado,
                        onTap: () => provider.atualizarItemParcial(
                          item.itemId,
                          modoOrcamento: item.modoOrcamento == ModoOrcamento.metroQuadrado
                              ? null
                              : ModoOrcamento.metroQuadrado,
                        ),
                      ),
                    ],
                  ),
                ),

                if (item.modoOrcamento != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 24),
                        const Expanded(
                          child: Text('Fornecedor',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary)),
                        ),
                        if (item.modoOrcamento == ModoOrcamento.unitario) ...[
                          const SizedBox(
                            width: 110,
                            child: Text('Valor Unitário',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                          const SizedBox(
                            width: 120,
                            child: Text('Total',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                        ] else ...[
                          const SizedBox(
                            width: 110,
                            child: Text('Valor m²',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                          const SizedBox(
                            width: 120,
                            child: Text('Total m²',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                        ],
                        const SizedBox(width: 80),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.divider),
                  ...allFornIds.map((fId) {
                    final pf = item.precos[fId]!;
                    final isMenorPreco =
                        menorPreco != null && pf.preco != null && pf.preco == menorPreco;
                    final isMenorPrecoM2Efetivo =
                        menorPrecoM2 != null && pf.precoM2 != null && pf.precoM2 == menorPrecoM2;
                    final isSelected = item.fornecedorSelecionado == fId;

                    return _FornecedorRow(
                      fornecedorNome: pf.fornecedorNome,
                      preco: pf.preco,
                      precoM2: pf.precoM2,
                      quantidade: item.quantidade,
                      isMenorPreco: isMenorPreco,
                      isMenorPrecoM2: isMenorPrecoM2Efetivo,
                      isSelected: isSelected,
                      modoOrcamento: item.modoOrcamento!,
                      onSelect: () => provider.atualizarItemParcial(
                        item.itemId,
                        fornecedorSelecionado: isSelected ? null : fId,
                        clearFornecedor: isSelected,
                      ),
                      onEditarPreco: () => _editarPreco(index, fId),
                    );
                  }),
                ],
              ],
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.person_add_outlined, size: 14),
                  label: const Text('Adicionar Fornecedor',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _vincularFornecedores(index),
                ),
                const Spacer(),
                if (item.fornecedorSelecionado != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.statusOk.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppTheme.statusOk.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            size: 12, color: AppTheme.statusOk),
                        const SizedBox(width: 5),
                        Text(
                          'Escolhido: ${item.precos[item.fornecedorSelecionado!]?.fornecedorNome}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.statusOk,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabelaComparativa(
      OrcamentoProvider provider, List<ItemOrcamentoData> itens) {
    final totais = _calcularTotaisPorFornecedor(itens);
    if (totais.isEmpty) return const SizedBox.shrink();

    final ordenarPorM2 = _ordemTotais == 'm2';

    final sortedIds = totais.keys.toList()
      ..sort((a, b) {
        if (ordenarPorM2) {
          final ta = totais[a]!['totalM2'] as double;
          final tb = totais[b]!['totalM2'] as double;
          if (ta == 0 && tb == 0) return 0;
          if (ta == 0) return 1;
          if (tb == 0) return -1;
          return ta.compareTo(tb);
        } else {
          final ta = totais[a]!['totalEfetivo'] as double;
          final tb = totais[b]!['totalEfetivo'] as double;
          if (ta == 0 && tb == 0) return 0;
          if (ta == 0) return 1;
          if (tb == 0) return -1;
          return ta.compareTo(tb);
        }
      });

    final valoresEfetivos = sortedIds
        .map((id) => totais[id]!['totalEfetivo'] as double)
        .where((v) => v > 0)
        .toList();

    final menorTotal =
        valoresEfetivos.isNotEmpty ? valoresEfetivos.first : null;

    final valoresM2Validos = sortedIds
        .map((id) => totais[id]!['totalM2'] as double)
        .where((v) => v > 0)
        .toList();

    final menorTotalM2 = valoresM2Validos.isNotEmpty
        ? valoresM2Validos.reduce((a, b) => a < b ? a : b)
        : null;

    final bestIdAtual = ordenarPorM2
        ? (menorTotalM2 != null
            ? sortedIds.firstWhere(
                (id) => (totais[id]!['totalM2'] as double) == menorTotalM2,
                orElse: () => sortedIds.first)
            : null)
        : (menorTotal != null ? sortedIds.first : null);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bar_chart, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Totais por Fornecedor',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '— soma dos valores em todos os materiais',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _OrdemTotaisBtn(
                        label: 'Unitário',
                        icon: Icons.straighten,
                        ativo: !ordenarPorM2,
                        onTap: () {
                          setState(() => _ordemTotais = 'unitario');
                          for (final item in itens) {
                            provider.atualizarItemParcial(
                              item.itemId,
                              modoOrcamento: ModoOrcamento.unitario,
                            );
                          }
                        },
                      ),
                      Container(width: 1, height: 24, color: AppTheme.divider),
                      _OrdemTotaisBtn(
                        label: 'm²',
                        icon: Icons.square_foot,
                        ativo: ordenarPorM2,
                        onTap: () {
                          setState(() => _ordemTotais = 'm2');
                          for (final item in itens) {
                            provider.atualizarItemParcial(
                              item.itemId,
                              modoOrcamento: ModoOrcamento.metroQuadrado,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Expanded(
                    child: Text('Fornecedor',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary))),
                const SizedBox(
                    width: 100,
                    child: Text('Materiais',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary))),
                SizedBox(
                  width: 130,
                  child: Row(
                    children: [
                      Text(
                        'Total Unitário',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: !ordenarPorM2
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      if (!ordenarPorM2) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_upward,
                            size: 10, color: AppTheme.primary),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Row(
                    children: [
                      Text(
                        'Total m²',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ordenarPorM2
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      if (ordenarPorM2) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_upward,
                            size: 10, color: AppTheme.primary),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),

          ...sortedIds.asMap().entries.map((entry) {
            final rank = entry.key;
            final fId = entry.value;
            final t = totais[fId]!;
            final total = t['total'] as double;
            final totalM2 = t['totalM2'] as double;
            final totalEfetivo = t['totalEfetivo'] as double;
            final mats = t['materiais'] as int;
            final temTodos = t['temTodosPrecos'] as bool;

            final isMelhor = menorTotal != null &&
                totalEfetivo == menorTotal &&
                totalEfetivo > 0;
            final isMelhorM2 = menorTotalM2 != null &&
                totalM2 == menorTotalM2 &&
                totalM2 > 0;

            final diff =
                (menorTotal != null && totalEfetivo > 0 && !isMelhor)
                    ? totalEfetivo - menorTotal
                    : null;
            final diffM2 =
                (menorTotalM2 != null && totalM2 > 0 && !isMelhorM2)
                    ? totalM2 - menorTotalM2
                    : null;

            final isDestaque = ordenarPorM2 ? isMelhorM2 : isMelhor;

            final itensComEsteForn =
                itens.where((i) => i.precos.containsKey(fId)).toList();
            final isSelecionadoEmTodos = itensComEsteForn.isNotEmpty &&
                itensComEsteForn.every((i) => i.fornecedorSelecionado == fId);

            return _TabelaComparativaRow(
              rank: rank + 1,
              nome: t['nome'] as String,
              total: total,
              totalM2: totalM2,
              materiais: mats,
              materiaisComPreco: t['materiaisComPreco'] as int,
              totalMateriais: t['totalMateriais'] as int,
              isMelhor: isMelhor,
              isMelhorM2: isMelhorM2,
              isDestaqueAtual: isDestaque,
              isSelecionadoEmTodos: isSelecionadoEmTodos,
              diff: diff,
              diffM2: diffM2,
              temTodosPrecos: temTodos,
              ordenarPorM2: ordenarPorM2,
              onSelectAll: () {
                for (final item in itens) {
                  if (item.fornecedorSelecionado != null) {
                    provider.atualizarItemParcial(
                      item.itemId,
                      fornecedorSelecionado: null,
                      clearFornecedor: true,
                    );
                  }
                }
                if (!isSelecionadoEmTodos) {
                  for (final item in itens) {
                    if (item.precos.containsKey(fId)) {
                      provider.atualizarItemParcial(
                        item.itemId,
                        fornecedorSelecionado: fId,
                      );
                    }
                  }
                }
              },
            );
          }),

          if ((menorTotal != null && menorTotal > 0) ||
              (menorTotalM2 != null && menorTotalM2 > 0))
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!ordenarPorM2 && menorTotal != null && menorTotal > 0)
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: AppTheme.statusOk),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textPrimary),
                            children: [
                              const TextSpan(text: 'Melhor total unitário: '),
                              TextSpan(
                                text:
                                    '${totais[sortedIds.first]!['nome']} com ${_brl(menorTotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.statusOk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (ordenarPorM2 &&
                      menorTotalM2 != null &&
                      menorTotalM2 > 0 &&
                      bestIdAtual != null)
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textPrimary),
                            children: [
                              const TextSpan(text: 'Melhor total m²: '),
                              TextSpan(
                                text:
                                    '${totais[bestIdAtual]!['nome']} com ${_brl(menorTotalM2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
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

          if (!_podeGerarOC(itens) && itens.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppTheme.primary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Selecione um fornecedor em cada material para habilitar o botão "Gerar OC".',
                      style: TextStyle(fontSize: 12, color: AppTheme.primary),
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
      decoration: InputDecoration(
        hintText: 'Especificação do material',
        isDense: true,
        filled: true,
        fillColor: AppTheme.surface,
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (criadoEm != null)
                        Text(
                          [
                            'Criado em ${criadoEm.day.toString().padLeft(2, '0')}/${criadoEm.month.toString().padLeft(2, '0')}/${criadoEm.year}',
                            if (criadorNome != null) 'por $criadorNome',
                          ].join(' '),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                        ),
                      if (aprovadoEm != null)                                      // ← adicionar bloco
                        Text(
                          [
                            'Aprovado em ${aprovadoEm.day.toString().padLeft(2, '0')}/${aprovadoEm.month.toString().padLeft(2, '0')}/${aprovadoEm.year}',
                            if (aprovadorNome != null) 'por $aprovadorNome',
                          ].join(' '),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                        ),
                    ],
                  ),
                ),
                Text(
                  '#${orcamento['id']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${materiaisUnicos.length} ${materiaisUnicos.length == 1 ? 'material' : 'materiais'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (aprovadorNome != null) ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.person_outline,
                          size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        aprovadorNome,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
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
                              const SizedBox(height: 2),
                              Text(
                                motivoRejeicao,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
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

                    if (mostrarAcoes) ...[
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
                    ],
                    
                    if (onGerarOC != null) ...[
                      const SizedBox(width: 8),
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
                    ],
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
    this.descricao,
    required this.onRemover,
  });

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

class _ModoButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selecionado;
  final VoidCallback onTap;

  const _ModoButton({
    required this.label,
    required this.icon,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado ? AppTheme.primary : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selecionado ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selecionado ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status) {
      case 'OK':
        bg = AppTheme.statusOk.withValues(alpha: 0.1);
        fg = AppTheme.statusOk;
      case 'LIMITE':
        bg = AppTheme.statusBaixo.withValues(alpha: 0.1);
        fg = AppTheme.statusBaixo;
      case 'CRITICO':
        bg = AppTheme.statusCritico.withValues(alpha: 0.1);
        fg = AppTheme.statusCritico;
      default:
        bg = AppTheme.surfaceVariant;
        fg = AppTheme.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
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
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
      ],
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        isDense: true,
        filled: true,
        fillColor: AppTheme.surface,
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: (v) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        if (parsed != null && parsed > 0) widget.onChanged(parsed);
      },
    );
  }
}

class _FornecedorRow extends StatelessWidget {
  final String fornecedorNome;
  final double? preco;
  final double? precoM2;
  final double quantidade;
  final bool isMenorPreco;
  final bool isMenorPrecoM2;
  final bool isSelected;
  final ModoOrcamento modoOrcamento;
  final VoidCallback onSelect;
  final VoidCallback onEditarPreco;

  const _FornecedorRow({
    required this.fornecedorNome,
    this.preco,
    this.precoM2,
    required this.quantidade,
    required this.isMenorPreco,
    required this.isMenorPrecoM2,
    required this.isSelected,
    required this.modoOrcamento,
    required this.onSelect,
    required this.onEditarPreco,
  });

  @override
  Widget build(BuildContext context) {
    final totalUnit = preco != null ? preco! * quantidade : null;
    final totalM2v = precoM2 != null ? precoM2! * quantidade : null;
    final isUnit = modoOrcamento == ModoOrcamento.unitario;

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.04) : null,
          border: const Border(
            top: BorderSide(color: AppTheme.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: isSelected ? AppTheme.primary : AppTheme.textHint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      fornecedorNome,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'Selecionado',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: isUnit
                  ? (preco != null
                      ? Text(_brl(preco),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPreco
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isMenorPreco
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textHint)))
                  : (precoM2 != null
                      ? Text(_brl(precoM2),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPrecoM2
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isMenorPrecoM2
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textHint))),
            ),
            SizedBox(
              width: 120,
              child: isUnit
                  ? (totalUnit != null
                      ? Text(_brl(totalUnit),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPreco
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isMenorPreco
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textHint)))
                  : (totalM2v != null
                      ? Text(_brl(totalM2v),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isMenorPrecoM2
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isMenorPrecoM2
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                          ))
                      : const Text('—',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textHint))),
            ),
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onEditarPreco,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.divider),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Editar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabelaComparativaRow extends StatelessWidget {
  final int rank;
  final String nome;
  final double total;
  final double totalM2;
  final int materiais;
  final int materiaisComPreco;
  final int totalMateriais;
  final bool isMelhor;
  final bool isMelhorM2;
  final bool isDestaqueAtual;
  final bool isSelecionadoEmTodos;
  final bool ordenarPorM2;
  final double? diff;
  final double? diffM2;
  final bool temTodosPrecos;
  final VoidCallback onSelectAll;

  const _TabelaComparativaRow({
    required this.rank,
    required this.nome,
    required this.total,
    required this.totalM2,
    required this.materiais,
    required this.materiaisComPreco,
    required this.totalMateriais,
    required this.isMelhor,
    required this.isMelhorM2,
    required this.isDestaqueAtual,
    required this.isSelecionadoEmTodos,
    required this.ordenarPorM2,
    this.diff,
    this.diffM2,
    required this.temTodosPrecos,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final cobreTotal = materiais >= totalMateriais;
    final temPrecoTotal = materiaisComPreco >= totalMateriais;

    return GestureDetector(
      onTap: onSelectAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelecionadoEmTodos
              ? AppTheme.primary.withValues(alpha: 0.06)
              : isDestaqueAtual
                  ? AppTheme.statusOk.withValues(alpha: 0.05)
                  : null,
          border: Border(
            top: const BorderSide(color: AppTheme.divider),
            left: isSelecionadoEmTodos
                ? const BorderSide(color: AppTheme.primary, width: 3)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                isSelecionadoEmTodos
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: isSelecionadoEmTodos
                    ? AppTheme.primary
                    : AppTheme.textHint,
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  if (isDestaqueAtual && !isSelecionadoEmTodos)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.emoji_events,
                          size: 16, color: AppTheme.statusOk),
                    )
                  else if (!isSelecionadoEmTodos)
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 8),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surfaceVariant,
                      ),
                      child: Text(
                        '$rank°',
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      nome,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: (isDestaqueAtual || isSelecionadoEmTodos)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelecionadoEmTodos
                            ? AppTheme.primary
                            : isDestaqueAtual
                                ? AppTheme.statusOk
                                : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (isSelecionadoEmTodos)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'Selecionado',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  if (!temTodosPrecos)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: 'Valor de algum material não informado',
                        child: Icon(Icons.warning_amber_rounded,
                            size: 13, color: AppTheme.warning),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: Tooltip(
                message: cobreTotal
                    ? temPrecoTotal
                        ? 'Cobre todos os $totalMateriais materiais com preço'
                        : 'Cobre todos os $totalMateriais materiais, mas ${materiais - materiaisComPreco} sem preço'
                    : 'Cobre apenas $materiais de $totalMateriais materiais — total parcial',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          cobreTotal
                              ? (temPrecoTotal
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_rounded)
                              : Icons.remove_circle_outline,
                          size: 13,
                          color: cobreTotal
                              ? (temPrecoTotal
                                  ? AppTheme.statusOk
                                  : AppTheme.warning)
                              : AppTheme.statusCritico,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$materiais/$totalMateriais',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cobreTotal
                                ? AppTheme.textPrimary
                                : AppTheme.statusCritico,
                          ),
                        ),
                      ],
                    ),
                    if (!cobreTotal)
                      Text(
                        'incompleto',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.statusCritico.withValues(alpha: 0.8),
                        ),
                      )
                    else if (!temPrecoTotal)
                      Text(
                        '${materiais - materiaisComPreco} sem preço',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.warning.withValues(alpha: 0.9),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    total > 0 ? _brl(total) : '—',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (isMelhor && !ordenarPorM2) ? FontWeight.w700 : FontWeight.w500,
                      color: (isMelhor && !ordenarPorM2)
                          ? AppTheme.statusOk
                          : (!ordenarPorM2
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary),
                    ),
                  ),
                  if (diff != null && !ordenarPorM2)
                    Text('+${_brl(diff)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.statusCritico)),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    totalM2 > 0 ? _brl(totalM2) : '—',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (isMelhorM2 && ordenarPorM2) ? FontWeight.w700 : FontWeight.w500,
                      color: (isMelhorM2 && ordenarPorM2)
                          ? AppTheme.statusOk
                          : (ordenarPorM2
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary),
                    ),
                  ),
                  if (diffM2 != null && ordenarPorM2)
                    Text('+${_brl(diffM2)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.statusCritico)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Diálogos ─────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    final disponiveis = widget.fornecedores
        .where((f) => !widget.idsJaVinculados.contains(f.id))
        .toList();

    return AlertDialog(
      title: Text('Adicionar Fornecedores — ${widget.materialNome}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: disponiveis.isEmpty
              ? const Text(
                  'Todos os fornecedores já estão vinculados a este material.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: disponiveis.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppTheme.divider),
                  itemBuilder: (ctx, i) {
                    final f = disponiveis[i];
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
    this.precoAtual,
    this.precoM2Atual,
  });

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
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.materialNome,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
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
      title: const Text('Cancelar Orçamento',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Este orçamento será movido para o histórico como cancelado.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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

class _OrdemTotaisBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool ativo;
  final VoidCallback onTap;

  const _OrdemTotaisBtn({
    required this.label,
    required this.icon,
    required this.ativo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: ativo ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ativo ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogSelecionarOC extends StatelessWidget {
  final List<dynamic> ocs;
  const _DialogSelecionarOC({required this.ocs});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar OC existente',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: ocs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (ctx, i) {
              final oc = ocs[i] as Map<String, dynamic>;
              final fornNome = oc['fornecedor']?['nomeFantasia'] ?? '—';
              final valorTotal =
                  double.tryParse(oc['valorTotal']?.toString() ?? '0') ?? 0;
              return InkWell(
                onTap: () => Navigator.pop(context, oc),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '#${oc['id']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fornNome,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Total: ${_brl(valorTotal)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: AppTheme.textHint),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}