const svc = require('../services/estoqueProducao.service');
const prisma = require('../utils/prisma');

async function _nomeUsuario(req) {
  const usuario = await prisma.usuario.findUnique({
    where: { id: req.usuario.id },
    select: { nome: true },
  });
  return usuario?.nome ?? req.usuario?.username ?? 'Usuário';
}

function _resolverProducao(req, valorInformado) {
  const role = (req.usuario?.role || '').toUpperCase();
  if (role === 'PRODUCAO1') return '1';
  if (role === 'PRODUCAO2') return '2';
  if (valorInformado) return valorInformado;
  throw { status: 400, message: "Informe a linha de produção ('1' ou '2')" };
}

const transferir = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    const producao = _resolverProducao(req, req.body.producao);
    const resultado = await svc.transferirParaProducao({ ...req.body, producao, usuarioNome });
    res.status(201).json(resultado);
  } catch (e) { next(e); }
};

const devolver = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    const producao = _resolverProducao(req, req.body.producao);
    const resultado = await svc.devolverAoEstoquePadrao({ ...req.body, producao, usuarioNome });
    res.status(201).json(resultado);
  } catch (e) { next(e); }
};

const transferirEntreLinhas = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    const { materialId, quantidade, producaoOrigem, producaoDestino, observacao } = req.body;
    const resultado = await svc.transferirEntreLinhas({
      materialId: Number(materialId),
      quantidade,
      producaoOrigem,
      producaoDestino,
      observacao,
      usuarioNome,
    });
    res.status(201).json(resultado);
  } catch (e) { next(e); }
};

const listarEstoque = async (req, res, next) => {
  try {
    const producao = _resolverProducao(req, req.query.producao);
    res.json(await svc.listarEstoque({ ...req.query, producao }));
  } catch (e) { next(e); }
};

const darBaixa = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    const producao = _resolverProducao(req, req.body.producao);
    res.status(201).json(await svc.darBaixa({ ...req.body, producao, usuarioNome }));
  } catch (e) { next(e); }
};

const listarHistorico = async (req, res, next) => {
  try {
    res.json(await svc.listarHistorico(req.query));
  } catch (e) { next(e); }
};

const excluirHistorico = async (req, res, next) => {
  try {
    await svc.excluirHistorico(Number(req.params.id));
    res.status(204).send();
  } catch (e) { next(e); }
};

const listarPendentes = async (req, res, next) => {
  try {
    const { producao, tipo, status } = req.query;
    res.json(await svc.listarPendentes({ producao, tipo, status }));
  } catch (e) { next(e); }
};

const contarPendentes = async (req, res, next) => {
  try {
    const total = await svc.contarPendentes();
    res.json({ total });
  } catch (e) { next(e); }
};

const confirmarPendente = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    const resultado = await svc.confirmarEntradaPendente({ id: Number(req.params.id), usuarioNome });
    res.json(resultado);
  } catch (e) { next(e); }
};

const recusarPendente = async (req, res, next) => {
  try {
    const usuarioNome = await _nomeUsuario(req);
    const resultado = await svc.recusarEntradaPendente({ id: Number(req.params.id), usuarioNome });
    res.json(resultado);
  } catch (e) { next(e); }
};

module.exports = {
  transferir,
  devolver,
  transferirEntreLinhas,
  listarEstoque,
  darBaixa,
  listarHistorico,
  excluirHistorico,
  listarPendentes,
  contarPendentes,
  confirmarPendente,
  recusarPendente,
};