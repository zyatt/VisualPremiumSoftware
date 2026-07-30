const svc = require('../services/material.service');

const _usuario = (req) => ({
  usuarioId:   req.usuario?.id,
  usuarioNome: req.usuario?.nome,
});

const listar = async (req, res, next) => {
  try { res.json(await svc.listar(req.query)); } catch (e) { next(e); }
};

const listarPaginado = async (req, res, next) => {
  try { res.json(await svc.listarPaginado(req.query)); } catch (e) { next(e); }
};

const buscarPorId = async (req, res, next) => {
  try { res.json(await svc.buscarPorId(+req.params.id)); } catch (e) { next(e); }
};

const listarParaMovimentacao = async (req, res, next) => {
  try { res.json(await svc.listarParaMovimentacao(req.query)); } catch (e) { next(e); }
};

const criar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    res.status(201).json(await svc.criar(req.body, usuarioId, usuarioNome));
  } catch (e) { next(e); }
};

const atualizar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    res.json(await svc.atualizar(+req.params.id, req.body, usuarioId, usuarioNome));
  } catch (e) { next(e); }
};

const desativar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    res.json(await svc.desativar(+req.params.id, usuarioId, usuarioNome));
  } catch (e) { next(e); }
};

const reativar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    res.json(await svc.reativar(+req.params.id, usuarioId, usuarioNome));
  } catch (e) { next(e); }
};

const excluir = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    res.json(await svc.excluir(+req.params.id, usuarioId, usuarioNome));
  } catch (e) { next(e); }
};

const confirmarEstoque = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    res.json(await svc.confirmarEstoque(+req.params.id, usuarioId, usuarioNome));
  } catch (e) { next(e); }
};

const atualizarCustoManual = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    res.json(await svc.atualizarCustoManual(+req.params.id, req.body, usuarioId, usuarioNome));
  } catch (e) { next(e); }
};

const listarCategorias = async (req, res, next) => {
  try { res.json(await svc.listarCategorias()); } catch (e) { next(e); }
};

const listarHistoricoPrecos = async (req, res, next) => {
  try {
    const limite = req.query.limite ? Number(req.query.limite) : 50;
    res.json(await svc.listarHistoricoPrecos(+req.params.id, limite));
  } catch (e) { next(e); }
};

const notificacoes = (req, res) => {
  const usuarioId = req.usuario?.id;
  console.log(`[SSE Materiais] Nova conexão do usuário ${usuarioId}`);

  res.writeHead(200, {
    'Content-Type':  'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection:      'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });
  res.flushHeaders();
  res.write(': heartbeat\n\n');

  const remover = svc.registrarSseCliente(res, usuarioId);

  const heartbeat = setInterval(() => {
    try { res.write(': heartbeat\n\n'); }
    catch (err) {
      console.error(`[SSE Materiais] Erro no heartbeat para ${usuarioId}: ${err.message}`);
      clearInterval(heartbeat);
    }
  }, 25_000);

  req.on('close', () => { clearInterval(heartbeat); remover(); });
};

module.exports = {
  listar,
  listarPaginado,
  buscarPorId,
  listarParaMovimentacao,
  criar,
  atualizar,
  desativar,
  reativar,
  excluir,
  confirmarEstoque,
  atualizarCustoManual,
  listarCategorias,
  listarHistoricoPrecos,
  notificacoes,
};