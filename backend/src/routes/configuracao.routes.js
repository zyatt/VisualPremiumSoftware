const router = require('express').Router();
const ctrl   = require('../controllers/configuracao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const ADMIN_GERENTE = ['ADMIN', 'GERENTE'];

router.get( '/markup',  authMiddleware, ctrl.listarFaixas);
router.put( '/markup',  authMiddleware, roleMiddleware(ADMIN_GERENTE), ctrl.salvarFaixas);

router.get( '/config',  authMiddleware, ctrl.listarConfiguracoes);
router.put( '/config',  authMiddleware, roleMiddleware(ADMIN_GERENTE), ctrl.salvarConfiguracoes);

module.exports = router;