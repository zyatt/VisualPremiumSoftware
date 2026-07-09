const router = require('express').Router();
const ctrl   = require('../controllers/audit-log.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS'];

router.get('/', authMiddleware, roleMiddleware(LEITURA), ctrl.listar);

router.get('/material/:materialId', authMiddleware, roleMiddleware(LEITURA), ctrl.listarPorMaterial);

module.exports = router;