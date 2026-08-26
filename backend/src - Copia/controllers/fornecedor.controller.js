const path   = require('path');
const fs     = require('fs');
const multer = require('multer');
const svc = require('../services/fornecedor.service');

const _uploadDir = path.join(__dirname, '..', 'uploads', 'fornecedores');
fs.mkdirSync(_uploadDir, { recursive: true });

const _storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, _uploadDir),
  filename:    (_req, file, cb) => {
    const ext  = path.extname(file.originalname).toLowerCase();
    const name = `forn_${Date.now()}_${Math.random().toString(36).slice(2)}${ext}`;
    cb(null, name);
  },
});

const _fileFilter = (_req, file, cb) => {
  const ok = /^\.(jpe?g|png|webp|gif)$/.test(path.extname(file.originalname).toLowerCase());
  cb(ok ? null : new Error('Tipo de arquivo não permitido'), ok);
};

const upload = multer({ storage: _storage, fileFilter: _fileFilter, limits: { fileSize: 10 * 1024 * 1024 } });

const uploadImagem = (req, res, next) => {
  upload.single('imagem')(req, res, (err) => {
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

function _comImagem(req) {
  const dados = { ...req.body };
  if (req.file) {
    dados.imagemUrl = `/uploads/fornecedores/${req.file.filename}`;
  }
  return dados;
}

const listar = async (req, res, next) => {
  try {
    res.json(
      await svc.listar(
        req.query.busca,
        req.query.tipo,
        req.query.id,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const listarPaginado = async (req, res, next) => {
  try {
    res.json(
      await svc.listarPaginado({
        busca:     req.query.busca,
        tipo:      req.query.tipo,
        id:        req.query.id,
        pagina:    req.query.pagina,
        porPagina: req.query.porPagina,
      }),
    );
  } catch (e) {
    next(e);
  }
};

const listarTipos = async (req, res, next) => {
  try {
    res.json(await svc.listarTipos());
  } catch (e) {
    next(e);
  }
};

const buscarPorId = async (req, res, next) => {
  try {
    res.json(await svc.buscarPorId(+req.params.id));
  } catch (e) {
    next(e);
  }
};

const criar = async (req, res, next) => {
  try {
    res.status(201).json(await svc.criar(_comImagem(req)));
  } catch (e) {
    if (req.file) fs.unlink(req.file.path, () => {});
    next(e);
  }
};

const atualizar = async (req, res, next) => {
  try {
    res.json(await svc.atualizar(+req.params.id, _comImagem(req)));
  } catch (e) {
    if (req.file) fs.unlink(req.file.path, () => {});
    next(e);
  }
};

const remover = async (req, res, next) => {
  try {
    await svc.remover(+req.params.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
};

const buscarParaVinculo = async (req, res, next) => {
  try {
    res.json(
      await svc.buscarParaVinculo(
        req.query.busca,
        req.query.limite,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const listarPorMaterial = async (req, res, next) => {
  try {
    res.json(await svc.listarPorMaterial(+req.params.materialId));
  } catch (e) {
    next(e);
  }
};

const vincularMaterial = async (req, res, next) => {
  try {
    const { materialId, preco, precoMetroQuadrado, precoUnidadeMedida } = req.body;

    res.json(
      await svc.vincularMaterial(
        +req.params.id,
        materialId,
        preco,
        precoMetroQuadrado,
        precoUnidadeMedida,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const desvincularMaterial = async (req, res, next) => {
  try {
    res.json(
      await svc.desvincularMaterial(
        +req.params.id,
        +req.params.materialId,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const atualizarPreco = async (req, res, next) => {
  try {
    res.json(
      await svc.atualizarPrecoVinculo(
        +req.params.id,
        +req.params.materialId,
        req.body,
      ),
    );
  } catch (e) {
    next(e);
  }
};

module.exports = {
  uploadImagem,
  listar,
  listarPaginado,
  listarTipos,
  buscarParaVinculo,
  buscarPorId,
  criar,
  atualizar,
  remover,
  listarPorMaterial,
  vincularMaterial,
  desvincularMaterial,
  atualizarPreco,
};