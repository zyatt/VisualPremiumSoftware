const svc = require('../services/estoqueProducao.service');
const prisma = require('../utils/prisma');

async function _nomeUsuario(req) {
  const usuario = await prisma.usuario.findUnique({
    where: { id: req.usuario.id },
    select: { nome: true },
  });
  return usuario?.nome ?? req.usuario?.username ?? 'Usuário';
}

const transferir = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    const resultado = await svc.transferirParaProducao({ ...req.body, usuarioNome });
    res.status(201).json(resultado);
  } catch (e) { next(e); }
};

const listarEstoque = async (req, res, next) => {
  try { res.json(await svc.listarEstoque(req.query)); } catch (e) { next(e); }
};

const darBaixa = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    res.status(201).json(await svc.darBaixa({ ...req.body, usuarioNome }));
  } catch (e) { next(e); }
};

const listarHistorico = async (req, res, next) => {
  try { res.json(await svc.listarHistorico(req.query)); } catch (e) { next(e); }
};

module.exports = { transferir, listarEstoque, darBaixa, listarHistorico };
