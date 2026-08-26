// estoque_temporario.controller.js
const svc = require('../services/estoque_temporario.service');

const _usuarioNome = (req) =>
  req.usuario?.nome ?? req.usuario?.username ?? 'Usuário';

const listar = async (req, res, next) => {
  try {
    // Desativa expirados a cada listagem (sem custo perceptível)
    await svc.desativarExpirados();
    res.json(await svc.listar(req.query.busca));
  } catch (e) { next(e); }
};

const criar = async (req, res, next) => {
  try {
    res.status(201).json(await svc.criar(req.body, _usuarioNome(req)));
  } catch (e) { next(e); }
};

const atualizar = async (req, res, next) => {
  try {
    res.json(await svc.atualizar(+req.params.id, req.body));
  } catch (e) { next(e); }
};

const remover = async (req, res, next) => {
  try {
    await svc.remover(+req.params.id);
    res.status(204).send();
  } catch (e) { next(e); }
};

const reativar = async (req, res, next) => {
  try {
    res.json(await svc.reativar(+req.params.id));
  } catch (e) { next(e); }
};

module.exports = { listar, criar, atualizar, remover, reativar };