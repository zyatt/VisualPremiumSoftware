// audit-log.routes.js
// Registre no app.js:
//   app.use('/api/audit-log', require('./routes/audit-log.routes'));

const router = require('express').Router();
const ctrl   = require('../controllers/audit-log.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS'];

// GET /api/audit-log?materialId=&acao=&busca=&dataInicio=&dataFim=&limite=
router.get('/', authMiddleware, roleMiddleware(LEITURA), ctrl.listar);

// GET /api/audit-log/material/:materialId
router.get('/material/:materialId', authMiddleware, roleMiddleware(LEITURA), ctrl.listarPorMaterial);

module.exports = router;