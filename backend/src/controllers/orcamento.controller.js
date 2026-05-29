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
    const criadorId = req.usuario.id;  // ← adicionar
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
      precoM2,
      usarM2,
      selecionado,
      descricaoItem,
    } = req.body;

    res.status(201).json(
      await svc.adicionarItem(
        +req.params.id, materialId, fornecedorId, quantidade, precoUnitario,
        { precoM2, usarM2, selecionado, descricaoItem }  // ← renomear
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

// DELETE /orcamentos/:id/itens — remove TODOS os itens do orçamento de uma vez
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
    await svc.validarParaOC(+req.params.id);
    const orcamento = await svc.buscarPorId(+req.params.id);
    res.json({ orcamento, pronto: true });
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
};