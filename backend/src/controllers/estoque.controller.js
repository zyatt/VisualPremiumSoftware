const svc = require('../services/estoque.service');

const listar                = async (req, res, next) => { try { res.json(await svc.listarEmAndamento(req.query.busca)); } catch(e){next(e);} };
const buscarPorNumeroOS     = async (req, res, next) => { try { res.json(await svc.buscarPorNumeroOS(req.params.numeroOS)); } catch(e){next(e);} };
const registrarMovimentacao = async (req, res, next) => { try { res.status(201).json(await svc.registrarMovimentacao(req.body)); } catch(e){next(e);} };
const removerMovimentacao   = async (req, res, next) => { try { res.json(await svc.removerMovimentacao(+req.params.movimentacaoId)); } catch(e){next(e);} };
const excluirRelacaoOS      = async (req, res, next) => { try { await svc.excluirRelacaoOS(+req.params.relacaoOSId); res.status(204).send(); } catch(e){next(e);} };
const fecharOS              = async (req, res, next) => { try { res.json(await svc.fecharOS(+req.params.relacaoOSId)); } catch(e){next(e);} };
const listarTodas = async (req, res, next) => { try { res.json(await svc.listarTodas(req.query.busca)); } catch(e){next(e);} };
const renomearOS = async (req, res, next) => {
  try {
    res.json(await svc.renomearOS(Number(req.params.id), req.body.novoNumeroOS));
  } catch (e) { next(e); }
};

module.exports = { listar, buscarPorNumeroOS, registrarMovimentacao, removerMovimentacao, excluirRelacaoOS, fecharOS, listarTodas, renomearOS };