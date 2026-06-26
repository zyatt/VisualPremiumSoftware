const path   = require('path');
const fs     = require('fs');
const multer = require('multer');
const svc    = require('../services/solicitacao_material.service');

// ─── Multer ───────────────────────────────────────────────────────────────────
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

// Envolve upload.any() para capturar erros do multer (tipo de arquivo inválido,
// arquivo grande demais, etc.) e responder no mesmo formato { message } usado
// pelo resto da API, em vez de deixá-los vazar para o middleware de erro global.
const uploadAny = (req, res, next) => {
  upload.any()(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError) {
      const mensagens = {
        LIMIT_FILE_SIZE: 'Imagem muito grande. O limite é 10MB.',
      };
      return res.status(400).json({ message: mensagens[err.code] || `Erro no upload: ${err.message}` });
    }
    // Erro lançado pelo fileFilter (extensão não permitida)
    return res.status(400).json({ message: err.message || 'Arquivo inválido.' });
  });
};

// ─── Helpers ──────────────────────────────────────────────────────────────────
const _usuario = (req) => ({
  usuarioId:   req.usuario?.id,
  usuarioNome: req.usuario?.nome,
  usuarioRole: req.usuario?.role,
});

// Responde um erro de forma padronizada garantindo que `message` sempre
// chegue ao cliente, independentemente do shape do erro (Error nativo,
// objeto simples { status, message } lançado pelo service, ou erro do multer).
// Evita depender do comportamento do middleware de erro global.
function _responderErro(res, e) {
  const status = e?.status && Number.isInteger(e.status) ? e.status : 500;
  const message = e?.message || 'Erro interno ao processar a solicitação.';
  if (status >= 500) {
    console.error('[Solicitações] Erro inesperado:', e);
  }
  res.status(status).json({ message });
}

// Faz parse de `itens` que pode vir como JSON string (multipart) ou array (JSON body).
// Também injeta imagemUrl nos itens quando há uploads múltiplos (req.files[]).
function _parseItens(body, files) {
  let itens = body.itens;
  if (typeof itens === 'string') {
    try { itens = JSON.parse(itens); } catch { itens = []; }
  }
  if (!Array.isArray(itens)) itens = [];

  // Se o frontend enviou arquivos múltiplos (campo "imagens[0]", "imagens[1]" …)
  // injeta no item correspondente pelo índice.
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

// ─── CRUD ─────────────────────────────────────────────────────────────────────

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
    const itens = _parseItens(req.body, req.files);
    res.status(201).json(await svc.criar({ ...req.body, itens }, usuarioId, usuarioNome));
  } catch (e) {
    // Limpa uploads em caso de erro
    if (req.files) req.files.forEach((f) => fs.unlink(f.path, () => {}));
    _responderErro(res, e);
  }
};

// Atualiza apenas o cabeçalho da solicitação (somente ADMIN)
const atualizar = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    res.json(await svc.atualizar(+req.params.id, req.body, usuarioId, usuarioNome, usuarioRole));
  } catch (e) { _responderErro(res, e); }
};

// Adiciona novos materiais (adicional) a uma solicitação existente
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

// Marca um item original como comprado/descomprado
// PATCH /solicitacoes-material/itens/:itemId/comprado
const marcarItemComprado = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    const comprado = req.body.comprado === true || req.body.comprado === 'true';
    res.json(await svc.marcarComprado('item', +req.params.itemId, usuarioId, usuarioNome, usuarioRole, comprado));
  } catch (e) { _responderErro(res, e); }
};

// Marca um adicional como comprado/descomprado
// PATCH /solicitacoes-material/adicionais/:adicionalId/comprado
const marcarAdicionalComprado = async (req, res, next) => {
  try {
    const { usuarioId, usuarioNome, usuarioRole } = _usuario(req);
    const comprado = req.body.comprado === true || req.body.comprado === 'true';
    res.json(await svc.marcarComprado('adicional', +req.params.adicionalId, usuarioId, usuarioNome, usuarioRole, comprado));
  } catch (e) { _responderErro(res, e); }
};

const excluir = async (req, res, next) => {
  try {
    await svc.excluir(+req.params.id);
    res.status(204).send();
  } catch (e) { _responderErro(res, e); }
};

const listarLogs = async (req, res, next) => {
  try { res.json(await svc.listarLogs(+req.params.id)); }
  catch (e) { next(e); }
};

// ─── SSE ─────────────────────────────────────────────────────────────────────
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
  criar,
  atualizar,
  adicionarMateriais,
  marcarItemComprado,
  marcarAdicionalComprado,
  excluir,
  listarLogs,
  notificacoes,
  contarNovas,
  marcarVisualizadas,
};