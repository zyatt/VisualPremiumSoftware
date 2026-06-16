const svc = require('../services/produto.service');

const listar = async (req, res, next) => {
  try { res.json(await svc.listar(req.query)); } catch (e) { next(e); }
};

const buscarPorId = async (req, res, next) => {
  try { res.json(await svc.buscarPorId(+req.params.id)); } catch (e) { next(e); }
};

const criar = async (req, res, next) => {
  try { res.status(201).json(await svc.criar(req.body)); } catch (e) { next(e); }
};

const atualizar = async (req, res, next) => {
  try { res.json(await svc.atualizar(+req.params.id, req.body)); } catch (e) { next(e); }
};

const desativar = async (req, res, next) => {
  try { res.json(await svc.desativar(+req.params.id)); } catch (e) { next(e); }
};

const reativar = async (req, res, next) => {
  try { res.json(await svc.reativar(+req.params.id)); } catch (e) { next(e); }
};

const excluir = async (req, res, next) => {
  try { res.json(await svc.excluir(+req.params.id)); } catch (e) { next(e); }
};

const adicionarMaterial = async (req, res, next) => {
  try { res.status(201).json(await svc.adicionarMaterial(+req.params.id, req.body)); } catch (e) { next(e); }
};

const atualizarMaterial = async (req, res, next) => {
  try { res.json(await svc.atualizarMaterial(+req.params.id, +req.params.materialItemId, req.body)); } catch (e) { next(e); }
};

const removerMaterial = async (req, res, next) => {
  try { await svc.removerMaterial(+req.params.id, +req.params.materialItemId); res.status(204).send(); } catch (e) { next(e); }
};

const listarCategorias = async (req, res, next) => {
  try { res.json(await svc.listarCategorias()); } catch (e) { next(e); }
};

module.exports = {
  listar,
  buscarPorId,
  criar,
  atualizar,
  desativar,
  reativar,
  excluir,
  adicionarMaterial,
  atualizarMaterial,
  removerMaterial,
  listarCategorias,
};