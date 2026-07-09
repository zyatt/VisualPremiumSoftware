const path   = require('path');
const fs     = require('fs');
const multer = require('multer');
const svc    = require('../services/solicitacao_material.service');

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
  const ok = /^\.(jpe?g|png|webp|gif)$/.test(path.extname(file.originalname).toLowerCase());
  cb(ok ? null : new Error('Tipo de arquivo não permitido'), ok);
};

const upload = multer({ storage: _storage, fileFilter: _fileFilter, limits: { fileSize: 10 * 1024 * 1024 } });

const uploadAny = (req, res, next) => {
  upload.any()(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError) {
      const mensagens = {
        LIMIT_FILE_SIZE: 'Imagem muito grande. O limite é 10MB.',
      };
      return res.status(400).json({ message: mensagens[err.code] || `Erro no upload: ${err.message}` });
    }
    return res.status(400).json({ message: err.message || 'Arquivo inválido.' });
  });
};

const _usuario = (req) => ({
  usuarioId:   req.usuario?.id,
  usuarioNome: req.usuario?.nome,
  usuarioRole: req.usuario?.role,
});

function _responderErro(res, e) {
  const status = e?.status && Number.isInteger(e.status) ? e.status : 500;
  const message = e?.message || 'Erro interno ao processar a solicitação.';
  if (status >= 500) {
    console.error('[Solicitações] Erro inesperado:', e);
  }
  res.status(status).json({ message });
}

function _parseItens(body, files) {
  let itens = body.itens;
  if (typeof itens === 'string') {
    try { itens = JSON.parse(itens); } catch { itens = []; }
  }
  if (!Array.isArray(itens)) itens = [];

  if (files && Array.isArray(files)) {
    files.forEach((file) => {
      const match = file.fieldname.match(/imagens\[(\d+)\]/);
      if (match) {
        const idx = Number(match[1]);
        if (itens[idx]) {
          itens[idx].imagemUrl = `/uploads/solicitacoes/${file.filename}`;
        }
      }
    });
  }

  return itens;
}

const listar = async (req, res, next) => {
  try { res.json(await svc.listar(req.query)); }
  catch (e) { next(e); }
};

const buscarPorId = async (req, res, next) => {
  try { res.json(await svc.buscarPorId(+req.params.id)); }
  catch (e) { next(e); }
};

const verificarOS = async (req, res, next) => {
  try {
    const numeroOS = String(req.params.numeroOS || '').trim();
    if (!numeroOS) return res.json({ existe: false });
    const ignorarId = req.query.ignorarId ? +req.query.ignorarId : undefined;
    res.json(await svc.verificarOSExiste(numeroOS, ignorarId));
  } catch (e) { _responderErro(res, e); }
};

const criar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome } = _usuario(req);
    const itens = _parseItens(req.body, req.files);
    res.status(201).json(await svc.criar({ ...req.body, itens }, usuarioId, usuarioNome));
  } catch (e) {
    if (req.files) req.files.forEach((f) => fs.unlink(f.path, () => {}));
    _responderErro(res, e);
  }
};

const atualizar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    res.json(await svc.atualizar(+req.params.id, req.body, usuarioId, usuarioNome, usuarioRole));
  } catch (e) { _responderErro(res, e); }
};

const adicionarMateriais = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    const itens = _parseItens(req.body, req.files);
    res.status(201).json(await svc.adicionarMateriais(+req.params.id, itens, usuarioId, usuarioNome, usuarioRole));
  } catch (e) {
    if (req.files) req.files.forEach((f) => fs.unlink(f.path, () => {}));
    _responderErro(res, e);
  }
};

const marcarItemComprado = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    const comprado = req.body.comprado === true || req.body.comprado === 'true';
    res.json(await svc.marcarComprado('item', +req.params.itemId, usuarioId, usuarioNome, usuarioRole, comprado));
  } catch (e) { _responderErro(res, e); }
};

const marcarAdicionalComprado = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    const comprado = req.body.comprado === true || req.body.comprado === 'true';
    res.json(await svc.marcarComprado('adicional', +req.params.adicionalId, usuarioId, usuarioNome, usuarioRole, comprado));
  } catch (e) { _responderErro(res, e); }
};

const atualizarItem = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    res.json(await svc.atualizarItem('item', +req.params.itemId, req.body, usuarioId, usuarioNome, usuarioRole));
  } catch (e) { _responderErro(res, e); }
};

const atualizarAdicional = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    res.json(await svc.atualizarItem('adicional', +req.params.adicionalId, req.body, usuarioId, usuarioNome, usuarioRole));
  } catch (e) { _responderErro(res, e); }
};

const excluirItem = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    res.json(await svc.excluirItem('item', +req.params.itemId, usuarioId, usuarioNome, usuarioRole));
  } catch (e) { _responderErro(res, e); }
};

const excluirAdicional = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    res.json(await svc.excluirItem('adicional', +req.params.adicionalId, usuarioId, usuarioNome, usuarioRole));
  } catch (e) { _responderErro(res, e); }
};

const excluir = async (req, res, next) => {
  try {
    const { usuarioId, usuarioRole } = _usuario(req);
    await svc.excluir(+req.params.id, usuarioId, usuarioRole);
    res.status(204).send();
  } catch (e) { _responderErro(res, e); }
};

const listarLogs = async (req, res, next) => {
  try { res.json(await svc.listarLogs(+req.params.id)); }
  catch (e) { next(e); }
};

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
    try { res.write(': heartbeat\n\n'); }
    catch (err) {
      console.error(`[SSE] Erro no heartbeat para ${usuarioId}: ${err.message}`);
      clearInterval(heartbeat);
    }
  }, 25_000);

  req.on('close', () => { clearInterval(heartbeat); remover(); });
};

const contarNovas = async (req, res, next) => {
  try { res.json({ count: await svc.contarNovas(req.usuario.id) }); }
  catch (e) { next(e); }
};

const marcarVisualizadas = async (req, res, next) => {
  try { res.json({ marcadas: await svc.marcarTodasComoVisualizadas(req.usuario.id) }); }
  catch (e) { next(e); }
};

module.exports = {
  upload,
  uploadAny,
  listar,
  buscarPorId,
  verificarOS,
  criar,
  atualizar,
  adicionarMateriais,
  marcarItemComprado,
  marcarAdicionalComprado,
  atualizarItem,
  atualizarAdicional,
  excluirItem,
  excluirAdicional,
  excluir,
  listarLogs,
  notificacoes,
  contarNovas,
  marcarVisualizadas,
};