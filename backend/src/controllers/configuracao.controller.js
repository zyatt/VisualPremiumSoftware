const svc = require('../services/configuracao.service');

const listarFaixas = async (req, res, next) => {
  try { res.json(await svc.listarFaixas()); } catch (e) { next(e); }
};

const salvarFaixas = async (req, res, next) => {
  try { res.json(await svc.salvarFaixas(req.body.faixas)); } catch (e) { next(e); }
};

const listarConfiguracoes = async (req, res, next) => {
  try { res.json(await svc.listarConfiguracoes()); } catch (e) { next(e); }
};

const salvarConfiguracoes = async (req, res, next) => {
  try { res.json(await svc.salvarConfiguracoes(req.body)); } catch (e) { next(e); }
};

module.exports = { listarFaixas, salvarFaixas, listarConfiguracoes, salvarConfiguracoes };