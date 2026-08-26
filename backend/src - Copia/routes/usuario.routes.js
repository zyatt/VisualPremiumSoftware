const router = require('express').Router();
const ctrl = require('../controllers/usuario.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

router.post('/login',         ctrl.login);
router.post('/refresh',       authMiddleware, ctrl.refresh);
router.post('/trocar-usuario', authMiddleware, ctrl.trocarUsuario);
router.get('/',    authMiddleware, roleMiddleware(['ADMIN']), ctrl.listar);
router.post('/',   authMiddleware, roleMiddleware(['ADMIN']), ctrl.criar);
router.put('/:id', authMiddleware, roleMiddleware(['ADMIN']), ctrl.atualizar);
router.delete('/:id', authMiddleware, roleMiddleware(['ADMIN']), ctrl.remover);

module.exports = router;