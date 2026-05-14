const svc = require('../services/orcamento.service');

const listar        = async (req, res, next) => { try { res.json(await svc.listar()); } catch(e){next(e);} };
const buscarPorId   = async (req, res, next) => { try { res.json(await svc.buscarPorId(+req.params.id)); } catch(e){next(e);} };
const criar         = async (req, res, next) => { try { res.status(201).json(await svc.criar(req.body.titulo)); } catch(e){next(e);} };
const cancelar      = async (req, res, next) => { try { res.json(await svc.cancelar(+req.params.id)); } catch(e){next(e);} };

const adicionarItem = async (req, res, next) => {
  try {
    const { materialId, fornecedorId, quantidade, precoUnitario } = req.body;
    res.status(201).json(await svc.adicionarItem(+req.params.id, materialId, fornecedorId, quantidade, precoUnitario));
  } catch(e){next(e);}
};

const removerItem = async (req, res, next) => {
  try {
    await svc.removerItem(+req.params.id, +req.params.itemId);
    res.status(204).send();
  } catch(e){next(e);}
};

const atualizarItem = async (req, res, next) => {
  try {
    res.json(await svc.atualizarItem(+req.params.itemId, req.body));
  } catch(e){next(e);}
};

const gerarOrdemCompra = async (req, res, next) => {
  try {
    await svc.validarParaOC(+req.params.id);
    // Redireciona para criação de OC com os dados do orçamento
    const orcamento = await svc.buscarPorId(+req.params.id);
    res.json({ orcamento, pronto: true });
  } catch(e){next(e);}
};

module.exports = { listar, buscarPorId, criar, cancelar, adicionarItem, removerItem, atualizarItem, gerarOrdemCompra };