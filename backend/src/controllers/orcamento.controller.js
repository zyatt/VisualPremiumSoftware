const svc = require('../services/orcamento.service');

const listar = async (req, res, next) => {
  try {
    const { status } = req.query;
    res.json(await svc.listar(status));
  } catch (e) {
    next(e);
  }
};

/// GET /orcamentos/abertos — usado pela seção "Orçamentos em Aberto" da
/// página de Orçamento, para montar os cards agrupados por usuário criador.
const listarAbertos = async (req, res, next) => {
  try {
    res.json(await svc.listarAbertos());
  } catch (e) {
    next(e);
  }
};

const atualizar = async (req, res, next) => {
  try {
    res.json(await svc.atualizar(+req.params.id, req.body));
  } catch (e) {
    next(e);
  }
};


const buscarPorId = async (req, res, next) => {
  try {
    res.json(await svc.buscarPorId(+req.params.id));
  } catch (e) {
    next(e);
  }
};

const criar = async (req, res, next) => {
  try {
    const criadorId = req.usuario.id;
    res.status(201).json(await svc.criar(req.body.titulo, criadorId));
  } catch (e) {
    next(e);
  }
};

const cancelar = async (req, res, next) => {
  try {
    // Passa o usuário atual para o service validar propriedade: apenas o
    // criador pode cancelar um orçamento ainda ABERTO (ver comentário em
    // orcamento.service.js:cancelar). ADMIN/GERENTE continuam liberados —
    // ver checagem de role no próprio service futuramente, se necessário;
    // por ora a regra pedida é "só o criador".
    res.json(await svc.cancelar(+req.params.id, req.usuario.id));
  } catch (e) {
    next(e);
  }
};

const adicionarItem = async (req, res, next) => {
  try {
    const {
      materialId,
      fornecedorId,
      quantidade,
      precoUnitario,
      selecionado,
      descricaoItem,
      observacao,
      qtdUnidade,
    } = req.body;

    res.status(201).json(
      await svc.adicionarItem(
        +req.params.id, materialId, fornecedorId, quantidade, precoUnitario,
        { selecionado, descricaoItem, observacao, qtdUnidade, origemUsuarioId: req.usuario.id }
      )
    );
  } catch (e) {
    next(e);
  }
};

const removerItem = async (req, res, next) => {
  try {
    await svc.removerItem(+req.params.id, +req.params.itemId, req.usuario.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
};

const limparItens = async (req, res, next) => {
  try {
    await svc.limparItens(+req.params.id, req.usuario.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
};

/// PUT /orcamentos/:id/itens — substitui todos os itens em uma operação
/// atômica (1 evento SSE só). Usado pelo auto-save do editor ao fechar a
/// guia, no lugar do antigo limparItens + N adicionarItem, que gerava uma
/// rajada de eventos com estados intermediários (orçamento momentaneamente
/// vazio) para quem estivesse só visualizando o mesmo orçamento.
const substituirItens = async (req, res, next) => {
  try {
    const { itens } = req.body;
    if (!Array.isArray(itens)) {
      return res.status(400).json({ message: 'Campo "itens" deve ser um array.' });
    }
    // Repassa quem fez a chamada para o evento SSE (ver comentário em
    // orcamento.service.js:substituirItens) — permite o próprio cliente
    // que originou a mudança ignorar o eco do seu próprio auto-save.
    res.json(await svc.substituirItens(+req.params.id, itens, req.usuario.id));
  } catch (e) {
    next(e);
  }
};

const atualizarItem = async (req, res, next) => {
  try {
    res.json(await svc.atualizarItem(+req.params.itemId, req.body, req.usuario.id));
  } catch (e) {
    next(e);
  }
};

const enviarParaAprovacao = async (req, res, next) => {
  try {
    res.json(await svc.enviarParaAprovacao(+req.params.id));
  } catch (e) {
    next(e);
  }
};

const aprovar = async (req, res, next) => {
  try {
    const aprovadorId = req.usuario.id;
    res.json(await svc.aprovar(+req.params.id, aprovadorId));
  } catch (e) {
    next(e);
  }
};

const rejeitar = async (req, res, next) => {
  try {
    const aprovadorId = req.usuario.id;
    const { motivo } = req.body;
    res.json(await svc.rejeitar(+req.params.id, aprovadorId, motivo));
  } catch (e) {
    next(e);
  }
};

const gerarOrdemCompra = async (req, res, next) => {
  try {
    const orcamentoId = +req.params.id;
    
    await svc.validarParaOC(orcamentoId);
    
    const orcamento = await svc.buscarPorId(orcamentoId);
    const modoPreco = orcamento.modoPrecificacao === 'METRO_LINEAR' ? 'METRO_LINEAR' : 'UNIDADE';

    const ocultos = new Set(orcamento.fornecedoresOcultos || []);

    const itensPorFornecedor = new Map();
    
    for (const item of orcamento.itens || []) {
      if (!item.selecionado || !item.fornecedorId) continue;
      if (ocultos.has(item.fornecedorId)) continue;
      
      if (!itensPorFornecedor.has(item.fornecedorId)) {
        itensPorFornecedor.set(item.fornecedorId, {
          fornecedorId: item.fornecedorId,
          fornecedorNome: item.fornecedor?.nomeFantasia || `Fornecedor #${item.fornecedorId}`,
          itens: [],
        });
      }
      
      itensPorFornecedor.get(item.fornecedorId).itens.push(item);
    }
    
    if (itensPorFornecedor.size === 0) {
      throw { status: 400, message: 'Nenhum item com fornecedor selecionado no orçamento' };
    }
    
    const ocsCriadas = [];
    const ocService = require('../services/ordemCompra.service');
    
    for (const [fornecedorId, grupo] of itensPorFornecedor) {
      const numerosOS = [...new Set(
        grupo.itens
          .map(i => i.descricaoItem?.trim())
          .filter(Boolean)
      )];
      
      if (numerosOS.length === 0) {
        numerosOS.push('EMPRESA');
      }
      
      const itensOC = grupo.itens.map(item => {
        const qtdUnidade = item.qtdUnidade ?? null;
        const precoOrcamento = item.precoUnitario || 0;
        const precoUnitarioOC = modoPreco === 'METRO_LINEAR'
          ? precoOrcamento
          : (qtdUnidade && qtdUnidade > 0 ? precoOrcamento / qtdUnidade : precoOrcamento);

        return {
          materialId: item.materialId,
          descricaoItem: item.descricaoItem || null,
          numeroOS: item.descricaoItem?.trim() || numerosOS[0],
          quantidade: item.quantidade,
          qtdUnidade,
          precoUnitario: precoUnitarioOC,
        };
      });
      
      const oc = await ocService.criar({
        fornecedorId,
        requisitante: req.usuario.nome,
        formaPagamento: null,
        prazoPagamento: null,
        observacoes: `Gerada a partir do orçamento #${orcamentoId}`,
        empresa: 'VISUAL PREMIUM',
        data: new Date(),
        status: 'EM_ANDAMENTO',
        orcamentoId,
        numerosOS,
        itens: itensOC,
      }, req.usuario.id);
      
      ocsCriadas.push({
        id: oc.id,
        fornecedorId,
        fornecedorNome: grupo.fornecedorNome,
        quantidadeItens: itensOC.length,
      });
    }
    
    await svc.atualizar(orcamentoId, { status: 'CONVERTIDO' });
    
    res.json({
      pronto: true,
      orcamento,
      ocsCriadas,
      mensagem: `${ocsCriadas.length} ${ocsCriadas.length === 1 ? 'OC criada' : 'OCs criadas'} com sucesso`,
    });
  } catch (e) {
    next(e);
  }
};


const excluir = async (req, res, next) => {
  try {
    await svc.excluir(+req.params.id, req.usuario.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
};

const reabrir = async (req, res, next) => {
  try {
    res.json(await svc.reabrir(+req.params.id));
  } catch (e) {
    next(e);
  }
};

const definirFornecedorOculto = async (req, res, next) => {
  try {
    const { fornecedorId, oculto } = req.body;
    if (fornecedorId == null || typeof oculto !== 'boolean') {
      return res.status(400).json({ message: 'fornecedorId e oculto (boolean) são obrigatórios.' });
    }
    res.json(await svc.definirFornecedorOculto(+req.params.id, +fornecedorId, oculto));
  } catch (e) {
    next(e);
  }
};

// ─── Trava de edição colaborativa ──────────────────────────────────────────

const travarEdicao = async (req, res, next) => {
  try {
    const orcamento = await svc.travarEdicao(+req.params.id, req.usuario.id);
    res.json(orcamento);
  } catch (e) {
    // 409 (travado por outro usuário) precisa chegar ao Flutter com o corpo
    // de erro completo (travaUsuarioNome), não só uma mensagem genérica —
    // o next(e) padrão do errorHandler global já repassa e.message, então
    // aqui só garantimos que os campos extras também vão no corpo da resposta.
    if (e && e.status === 409) {
      return res.status(409).json({
        message: e.message,
        travaUsuarioId: e.travaUsuarioId,
        travaUsuarioNome: e.travaUsuarioNome,
      });
    }
    next(e);
  }
};

const renovarTravaEdicao = async (req, res, next) => {
  try {
    res.json(await svc.renovarTravaEdicao(+req.params.id, req.usuario.id));
  } catch (e) {
    next(e);
  }
};

const destravarEdicao = async (req, res, next) => {
  try {
    res.json(await svc.destravarEdicao(+req.params.id, req.usuario.id));
  } catch (e) {
    next(e);
  }
};

// ─── SSE ─────────────────────────────────────────────────────────────────
// Mesmo padrão do módulo de chat: mantém a conexão HTTP aberta e escreve um
// evento `data: {...}\n\n` a cada mudança relevante em orçamentos ABERTO
// (criação, edição de item, trava/destrava, saída do pool "aberto"). O
// cliente Flutter (OrcamentoProvider._conectarSSE) consome isso para manter
// a seção "Orçamentos em Aberto" e o editor sincronizados sem polling.
const streamSSE = async (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  res.write('\n');

  const enviar = (evento) => {
    try {
      res.write(`data: ${JSON.stringify(evento)}\n\n`);
    } catch (_) {
      // conexão pode já ter caído; o listener 'close' abaixo cuida da limpeza
    }
  };

  const listener = (evento) => enviar(evento);
  svc.orcamentoEvents.on('evento', listener);

  // Ping periódico para manter a conexão viva atrás de proxies/túneis que
  // fecham streams ociosos (mesmo padrão do heartbeat de conexão do chat).
  const keepAlive = setInterval(() => {
    try {
      res.write(': ping\n\n');
    } catch (_) {}
  }, 20000);

  req.on('close', () => {
    clearInterval(keepAlive);
    svc.orcamentoEvents.removeListener('evento', listener);
  });
};

module.exports = {
  listar,
  listarAbertos,
  buscarPorId,
  criar,
  atualizar,
  cancelar,
  adicionarItem,
  removerItem,
  limparItens,
  substituirItens,
  atualizarItem,
  enviarParaAprovacao,
  aprovar,
  rejeitar,
  gerarOrdemCompra,
  reabrir,
  excluir,
  definirFornecedorOculto,
  travarEdicao,
  renovarTravaEdicao,
  destravarEdicao,
  streamSSE,
};