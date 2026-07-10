const svc = require('../services/orcamento.service');

const listar = async (req, res, next) => {
  try {
    const { status } = req.query;
    res.json(await svc.listar(status));
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
    res.json(await svc.cancelar(+req.params.id));
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
        { selecionado, descricaoItem, observacao, qtdUnidade }
      )
    );
  } catch (e) {
    next(e);
  }
};

const removerItem = async (req, res, next) => {
  try {
    await svc.removerItem(+req.params.id, +req.params.itemId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
};

const limparItens = async (req, res, next) => {
  try {
    await svc.limparItens(+req.params.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
};

const atualizarItem = async (req, res, next) => {
  try {
    res.json(await svc.atualizarItem(+req.params.itemId, req.body));
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
      
      const itensOC = grupo.itens.map(item => ({
        materialId: item.materialId,
        descricaoItem: item.descricaoItem || null,
        numeroOS: item.descricaoItem?.trim() || numerosOS[0],
        quantidade: item.quantidade,
        qtdUnidade: item.qtdUnidade ?? null,
        precoUnitario: item.precoUnitario || 0,
      }));
      
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
    await svc.excluir(+req.params.id);
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

module.exports = {
  listar,
  buscarPorId,
  criar,
  atualizar,
  cancelar,
  adicionarItem,
  removerItem,
  limparItens,
  atualizarItem,
  enviarParaAprovacao,
  aprovar,
  rejeitar,
  gerarOrdemCompra,
  reabrir,
  excluir,
  definirFornecedorOculto,
};