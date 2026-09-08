// routes/certificadoA1.routes.js
const express = require('express');
const multer = require('multer');
const router = express.Router();
const ctrl = require('../controllers/certificadoA1.controller');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ok = /\.(pfx|p12)$/i.test(file.originalname);
    if (ok) return cb(null, true);
    cb(new Error('Envie um arquivo de certificado .pfx ou .p12.'));
  },
});

router.get('/', ctrl.listar);
router.post('/', upload.single('arquivo'), ctrl.cadastrar);
router.post('/:id/ativar', ctrl.ativar);
router.post('/:id/buscar-notas', ctrl.buscarNotas);

module.exports = router;