const router = require('express').Router();
const ctrl = require('../controllers/historico.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA = ['ADMIN','GERENTE','COMPRAS'];

router.get('/',     authMiddleware, roleMiddleware(LEITURA), ctrl.listar);
router.get('/:id',  authMiddleware, roleMiddleware(LEITURA), ctrl.buscarPorId);

module.exports = router;