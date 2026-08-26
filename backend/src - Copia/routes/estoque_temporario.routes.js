// estoque_temporario.routes.js
const router = require('express').Router();
const ctrl   = require('../controllers/estoque_temporario.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// Leitura: todos os roles que acessam estoque
const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS', 'ORCAMENTISTA'];
// Escrita: quem pode criar/editar/remover
const ESCRITA = ['ADMIN', 'GERENTE', 'COMPRAS'];

router.get('/',       authMiddleware, roleMiddleware(LEITURA), ctrl.listar);
router.post('/',      authMiddleware, roleMiddleware(ESCRITA), ctrl.criar);
router.put('/:id',    authMiddleware, roleMiddleware(ESCRITA), ctrl.atualizar);
router.delete('/:id', authMiddleware, roleMiddleware(ESCRITA), ctrl.remover);
router.post('/:id/reativar', authMiddleware, roleMiddleware(ESCRITA), ctrl.reativar);

module.exports = router;