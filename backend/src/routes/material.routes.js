const router = require('express').Router();
const ctrl = require('../controllers/material.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA      = ['ADMIN', 'GERENTE', 'COMPRAS', 'ORCAMENTISTA'];
const CADASTRO     = ['ADMIN', 'GERENTE', 'COMPRAS'];
const ESCRITA      = ['ADMIN', 'GERENTE'];
const EXCLUSAO     = ['ADMIN', 'GERENTE'];
const CUSTO        = ['ADMIN', 'GERENTE', 'COMPRAS'];

router.get('/categorias',         authMiddleware, roleMiddleware(LEITURA),  ctrl.listarCategorias);
router.get('/para-movimentacao',  authMiddleware, roleMiddleware(LEITURA),  ctrl.listarParaMovimentacao);
router.get('/notificacoes',       authMiddleware, ctrl.notificacoes);
router.get('/',                   authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:id',                authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.get('/:id/historico-precos', authMiddleware, roleMiddleware(LEITURA), ctrl.listarHistoricoPrecos);
router.post('/',                  authMiddleware, roleMiddleware(CADASTRO), ctrl.criar);
router.put('/:id',                authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizar);
router.patch('/:id/desativar',    authMiddleware, roleMiddleware(ESCRITA),  ctrl.desativar);
router.patch('/:id/reativar',     authMiddleware, roleMiddleware(ESCRITA),  ctrl.reativar);
router.patch('/:id/confirmar',    authMiddleware, roleMiddleware(ESCRITA),  ctrl.confirmarEstoque);
router.patch('/:id/custo',        authMiddleware, roleMiddleware(CUSTO),    ctrl.atualizarCustoManual);
router.delete('/:id',             authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluir);

module.exports = router;