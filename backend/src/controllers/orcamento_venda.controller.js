const svc = require('../services/orcamento_venda.service');

const listar = async (req, res, next) => {
  try { res.json(await svc.listar(req.query)); } catch (e) { next(e); }
};

const buscarPorId = async (req, res, next) => {
  try { res.json(await svc.buscarPorId(+req.params.id)); } catch (e) { next(e); }
};

const criar = async (req, res, next) => {
  try { res.status(201).json(await svc.criar({ ...req.body, criadorId: req.user?.id })); }
  catch (e) { next(e); }
};

const atualizar = async (req, res, next) => {
  try { res.json(await svc.atualizar(+req.params.id, req.body)); } catch (e) { next(e); }
};

const excluir = async (req, res, next) => {
  try { await svc.excluir(+req.params.id); res.status(204).send(); } catch (e) { next(e); }
};

const aprovar = async (req, res, next) => {
  try { res.json(await svc.alterarStatus(+req.params.id, 'APROVADO')); } catch (e) { next(e); }
};

const reprovar = async (req, res, next) => {
  try { res.json(await svc.alterarStatus(+req.params.id, 'NAO_APROVADO')); } catch (e) { next(e); }
};

const adicionarItem = async (req, res, next) => {
  try { res.status(201).json(await svc.adicionarItem(+req.params.id, req.body)); }
  catch (e) { next(e); }
};

const atualizarItem = async (req, res, next) => {
  try { res.json(await svc.atualizarItem(+req.params.id, +req.params.itemId, req.body)); }
  catch (e) { next(e); }
};

const removerItem = async (req, res, next) => {
  try { await svc.removerItem(+req.params.id, +req.params.itemId); res.status(204).send(); }
  catch (e) { next(e); }
};

const listarClientes = async (req, res, next) => {
  try { res.json(await svc.listarClientes(req.query.busca)); } catch (e) { next(e); }
};

module.exports = {
  listar,
  buscarPorId,
  criar,
  atualizar,
  excluir,
  aprovar,
  reprovar,
  adicionarItem,
  atualizarItem,
  removerItem,
  listarClientes,
};