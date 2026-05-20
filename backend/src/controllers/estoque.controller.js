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

const removerMovimentacao = async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!id) return res.status(400).json({ message: 'ID inválido' });
    res.json(await svc.removerMovimentacao(id));
  } catch(e) {
    if (e.status) return res.status(e.status).json({ message: e.message });
    next(e);
  }
};

const excluirRelacaoOS = async (req, res, next) => {
  try {
    const numeroOS = decodeURIComponent(req.params.numeroOS);
    res.json(await svc.excluirRelacaoOS(numeroOS));
  } catch(e) {
    if (e.status) return res.status(e.status).json({ message: e.message });
    next(e);
  }
};

const listarMovimentacoesPorMaterial = async (req, res, next) => {
  try {
    res.json(await svc.listarMovimentacoesPorMaterial(+req.params.materialId));
  } catch(e){next(e);}
};

module.exports = {
  listarRelacoesOS,
  buscarRelacaoOS,
  registrarMovimentacao,
  removerMovimentacao,
  excluirRelacaoOS,
  listarMovimentacoesPorMaterial,
};