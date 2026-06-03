const router = require('express').Router();
const ctrl = require('../controllers/material.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// COMPRAS pode apenas criar (cadastrar) e ler materiais.
// Editar, desativar, reativar, excluir e gerir filhos específicos exigem ADMIN ou GERENTE.
const LEITURA      = ['ADMIN', 'GERENTE', 'COMPRAS'];
const CADASTRO     = ['ADMIN', 'GERENTE', 'COMPRAS']; // criar novo material
const ESCRITA      = ['ADMIN', 'GERENTE'];             // editar / manter
const EXCLUSAO     = ['ADMIN', 'GERENTE'];             // desativar / excluir

router.get('/categorias',                  authMiddleware, roleMiddleware(LEITURA),   ctrl.listarCategorias);
router.get('/',                            authMiddleware, roleMiddleware(LEITURA),   ctrl.listar);
router.get('/:id',                         authMiddleware, roleMiddleware(LEITURA),   ctrl.buscarPorId);
router.get('/:id/historico-precos',        authMiddleware, roleMiddleware(LEITURA),   ctrl.listarHistoricoPrecos);
router.post('/',                           authMiddleware, roleMiddleware(CADASTRO),  ctrl.criar);
router.put('/:id',                         authMiddleware, roleMiddleware(ESCRITA),   ctrl.atualizar);
router.patch('/:id/desativar',             authMiddleware, roleMiddleware(ESCRITA),   ctrl.desativar);
router.patch('/:id/reativar',              authMiddleware, roleMiddleware(ESCRITA),   ctrl.reativar);
router.patch('/:id/confirmar',             authMiddleware, roleMiddleware(ESCRITA),   ctrl.confirmarEstoque);
router.delete('/:id',                      authMiddleware, roleMiddleware(EXCLUSAO),  ctrl.excluir);
router.patch('/:id/especificos/:filhoId',  authMiddleware, roleMiddleware(ESCRITA),   ctrl.atualizarFilhoEspecifico);
router.delete('/:id/especificos/:filhoId', authMiddleware, roleMiddleware(EXCLUSAO),  ctrl.excluirFilhoEspecifico);

module.exports = router;