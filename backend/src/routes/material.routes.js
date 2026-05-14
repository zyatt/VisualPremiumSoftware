const router = require('express').Router();
const ctrl = require('../controllers/material.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const ESCRITA  = ['ADMIN','GERENTE','ESTOQUISTA'];
const EXCLUSAO = ['ADMIN','GERENTE'];

router.get('/categorias',          authMiddleware, roleMiddleware(LEITURA),  ctrl.listarCategorias);
router.get('/',                    authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:id',                 authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.post('/',                   authMiddleware, roleMiddleware(ESCRITA),  ctrl.criar);
router.put('/:id',                 authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizar);
router.patch('/:id/desativar',     authMiddleware, roleMiddleware(ESCRITA),  ctrl.desativar);
router.patch('/:id/reativar',      authMiddleware, roleMiddleware(ESCRITA),  ctrl.reativar);
router.patch('/:id/confirmar',     authMiddleware, roleMiddleware(ESCRITA),  ctrl.confirmarEstoque);
router.delete('/:id',              authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluir);

module.exports = router;