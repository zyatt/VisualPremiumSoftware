const svc = require('../services/ordemCompra.service');
const prisma = require('../utils/prisma');

const listar      = async (req, res, next) => { try { res.json(await svc.listar(req.query.status)); } catch(e){next(e);} };

const listarPagina = async (req, res, next) => {
  try {
    const {
      status, numero, material, identificador, medida,
      comprimento, largura, espessura, pagina, porPagina,
    } = req.query;
    res.json(await svc.listarPagina({
      status,
      numero,
      material,
      identificador,
      medida,
      comprimento,
      largura,
      espessura,
      pagina:    pagina    ? Number(pagina)    : 1,
      porPagina: porPagina ? Number(porPagina) : 50,
    }));
  } catch(e){next(e);}
};

const contarPorStatus = async (req, res, next) => {
  try { res.json(await svc.contarPorStatus()); } catch(e){next(e);}
};

const buscarPorId = async (req, res, next) => { try { res.json(await svc.buscarPorId(+req.params.id)); } catch(e){next(e);} };
const proximoId   = async (req, res, next) => {
  try {
    const ultima = await require('../utils/prisma').ordemCompra.findFirst({ orderBy: { id: 'desc' }, select: { id: true } });
    res.json({ proximoId: (ultima?.id ?? 0) + 1 });
  } catch(e){next(e);}
};

const criar = async (req, res, next) => {
  try {
    res.status(201).json(await svc.criar(req.body, req.usuario.id));
  } catch(e){next(e);}
};

const criarDeOrcamento = async (req, res, next) => {
  try {
    res.status(201).json(await svc.criarDeOrcamento(+req.params.orcamentoId, req.body, req.usuario.id));
  } catch(e){next(e);}
};

const atualizar = async (req, res, next) => {
  try {
    res.json(await svc.atualizar(+req.params.id, req.body));
  } catch(e){next(e);}
};

const adicionarItem = async (req, res, next) => {
  try {
    res.status(201).json(await svc.adicionarItem(+req.params.id, req.body));
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

const finalizar = async (req, res, next) => {
  try {
    const usuario = await prisma.usuario.findUnique({
      where: { id: req.usuario.id },
      select: { nome: true },
    });
    const usuarioNome = usuario?.nome ?? req.usuario?.username ?? 'Usuário';
    res.json(await svc.finalizar(+req.params.id, usuarioNome));
  } catch(e){next(e);}
};

const cancelar = async (req, res, next) => {
  try {
    res.json(await svc.cancelar(+req.params.id));
  } catch(e){next(e);}
};

const reverter = async (req, res, next) => {
  try {
    res.json(await svc.reverter(+req.params.id));
  } catch(e){next(e);}
};

const excluir = async (req, res, next) => {
  try {
    await svc.excluir(+req.params.id);
    res.status(204).send();
  } catch(e){next(e);}
};

module.exports = { listar, listarPagina, contarPorStatus, buscarPorId, proximoId, criar, criarDeOrcamento, atualizar, adicionarItem, removerItem, atualizarItem, finalizar, cancelar, reverter, excluir };