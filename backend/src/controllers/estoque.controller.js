const svc = require('../services/estoque.service');

const listarRelacoesOS = async (req, res, next) => {
  try { res.json(await svc.listarRelacoesOS(req.query.busca)); } catch(e){next(e);}
};

const buscarRelacaoOS = async (req, res, next) => {
  try { res.json(await svc.buscarRelacaoOS(req.params.numeroOS)); } catch(e){next(e);}
};

const registrarMovimentacao = async (req, res, next) => {
  try {
    res.status(201).json(await svc.registrarMovimentacao(req.body));
  } catch(e){next(e);}
};

const listarMovimentacoesPorMaterial = async (req, res, next) => {
  try {
    res.json(await svc.listarMovimentacoesPorMaterial(+req.params.materialId));
  } catch(e){next(e);}
};

module.exports = { listarRelacoesOS, buscarRelacaoOS, registrarMovimentacao, listarMovimentacoesPorMaterial };