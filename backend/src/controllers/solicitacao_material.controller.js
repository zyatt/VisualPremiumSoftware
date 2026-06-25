const path    = require('path');
const fs      = require('fs');
const multer  = require('multer');
const svc     = require('../services/solicitacao_material.service');

// ─── Multer: upload de imagem ──────────────────────────────────────────────
const _uploadDir = path.join(__dirname, '..', 'uploads', 'solicitacoes');
fs.mkdirSync(_uploadDir, { recursive: true });

const _storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, _uploadDir),
  filename:    (_req, file, cb) => {
    const ext  = path.extname(file.originalname).toLowerCase();
    const name = `sol_${Date.now()}_${Math.random().toString(36).slice(2)}${ext}`;
    cb(null, name);
  },
});

const _fileFilter = (_req, file, cb) => {
  const ext = path.extname(file.originalname).toLowerCase();
  const ok  = /^\.(jpe?g|png|webp|gif)$/.test(ext);
  cb(ok ? null : new Error('Tipo de arquivo não permitido'), ok);
};

const upload = multer({
  storage:   _storage,
  fileFilter: _fileFilter,
  limits:    { fileSize: 10 * 1024 * 1024 },
});

// ─── Helper ────────────────────────────────────────────────────────────────
const _usuario = (req) => ({
  usuarioId:   req.usuario?.id,
  usuarioNome: req.usuario?.nome,
});

// ─── Controllers ──────────────────────────────────────────────────────────

const listar = async (req, res, next) => {
  try { res.json(await svc.listar(req.query)); }
  catch (e) { next(e); }
};

const buscarPorId = async (req, res, next) => {
  try { res.json(await svc.buscarPorId(+req.params.id)); }
  catch (e) { next(e); }
};

const criar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    if (req.file) {
      req.body.imagemUrl = `/uploads/solicitacoes/${req.file.filename}`;
    }
    res.status(201).json(await svc.criar(req.body, usuarioId, usuarioNome));
  } catch (e) {
    if (req.file) fs.unlink(req.file.path, () => {});
    next(e);
  }
};

const atualizar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    if (req.file) {
      req.body.imagemUrl = `/uploads/solicitacoes/${req.file.filename}`;
    }
    res.json(await svc.atualizar(+req.params.id, req.body, usuarioId, usuarioNome));
  } catch (e) {
    if (req.file) fs.unlink(req.file.path, () => {});
    next(e);
  }
};

const excluir = async (req, res, next) => {
  try {
    await svc.excluir(+req.params.id);
    res.status(204).send();
  } catch (e) { next(e); }
};

// ─── Logs de edição ────────────────────────────────────────────────────────
const listarLogs = async (req, res, next) => {
  try { res.json(await svc.listarLogs(+req.params.id)); }
  catch (e) { next(e); }
};

// ─── SSE: stream de notificações ───────────────────────────────────────────
const notificacoes = (req, res) => {
  const usuarioId = req.usuario?.id;
  
  console.log(`[SSE Solicitações] Nova conexão do usuário ${usuarioId}`);
  
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
    try {
      res.write(': heartbeat\n\n');
    } catch (err) {
      console.error(`[SSE Solicitações] Erro no heartbeat para usuário ${usuarioId}: ${err.message}`);
      clearInterval(heartbeat);
    }
  }, 25_000);

  req.on('close', () => {
    clearInterval(heartbeat);
    remover();
  });
};

// ─── Contar novas (não visualizadas) ───────────────────────────────────────
const contarNovas = async (req, res, next) => {
  try {
    const count = await svc.contarNovas(req.usuario.id);
    res.json({ count });
  } catch (e) { next(e); }
};

// ─── Marcar todas como visualizadas ────────────────────────────────────────
// Chamado pelo Flutter quando o usuário entra na página de Solicitações.
// Persiste no banco para que reconexões SSE não restaurem o badge.
const marcarVisualizadas = async (req, res, next) => {
  try {
    const total = await svc.marcarTodasComoVisualizadas(req.usuario.id);
    res.json({ marcadas: total });
  } catch (e) { next(e); }
};

module.exports = {
  upload,
  listar,
  buscarPorId,
  criar,
  atualizar,
  excluir,
  listarLogs,
  notificacoes,
  contarNovas,
  marcarVisualizadas,
};