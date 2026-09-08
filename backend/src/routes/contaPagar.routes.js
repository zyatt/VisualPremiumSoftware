// routes/contaPagar.routes.js
const express = require('express');
const multer = require('multer');
const router = express.Router();
const ctrl = require('../controllers/contaPagar.controller');

// XML fica só em memória — vai direto pro parser e o conteúdo é persistido
// no banco (campo xmlOriginal), não precisa de arquivo em disco.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB é bem folgado pra um XML de NF-e
  fileFilter: (req, file, cb) => {
    const nomeOk = /\.xml$/i.test(file.originalname);
    const tipoOk = ['text/xml', 'application/xml', 'application/octet-stream'].includes(file.mimetype);
    if (nomeOk || tipoOk) return cb(null, true);
    cb(new Error('Envie um arquivo .xml de Nota Fiscal Eletrônica.'));
  },
});

router.get('/resumo', ctrl.resumo);
router.get('/', ctrl.listar);
router.get('/:id', ctrl.buscarPorId);

router.post('/', ctrl.criar);
router.post('/importar-xml', upload.single('arquivo'), ctrl.importarXml);
router.post('/confirmar-nota/:notaFiscalId', ctrl.confirmarContaDeNota);
router.post('/:id/pagar', ctrl.marcarComoPaga);
router.post('/:id/status', ctrl.atualizarStatus);
router.post('/:id/cancelar', ctrl.cancelar);

router.patch('/:id', ctrl.atualizar);
router.delete('/:id', ctrl.excluir);

module.exports = router;