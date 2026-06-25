const router = require('express').Router();
const ctrl = require('../controllers/material.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// COMPRAS pode apenas criar (cadastrar) e ler materiais.
// Editar, desativar, reativar, excluir e gerir filhos específicos exigem ADMIN ou GERENTE.
const LEITURA      = ['ADMIN', 'GERENTE', 'COMPRAS', 'ORCAMENTISTA'];
const CADASTRO     = ['ADMIN', 'GERENTE', 'COMPRAS']; // criar novo material
const ESCRITA      = ['ADMIN', 'GERENTE'];             // editar / manter
const EXCLUSAO     = ['ADMIN', 'GERENTE'];             // desativar / excluir

router.get('/categorias',         authMiddleware, roleMiddleware(LEITURA),  ctrl.listarCategorias);
// Rota específica para o dialog de entrada/saída do controle de estoque.
// Inclui materiais temporários ativos — deve vir ANTES de '/:id' para não
// ser capturada pelo parâmetro dinâmico.
router.get('/para-movimentacao',  authMiddleware, roleMiddleware(LEITURA),  ctrl.listarParaMovimentacao);
router.get('/',                   authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:id',                authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.get('/:id/historico-precos', authMiddleware, roleMiddleware(LEITURA), ctrl.listarHistoricoPrecos);
router.post('/',                  authMiddleware, roleMiddleware(CADASTRO), ctrl.criar);
router.put('/:id',                authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizar);
router.patch('/:id/desativar',    authMiddleware, roleMiddleware(ESCRITA),  ctrl.desativar);
router.patch('/:id/reativar',     authMiddleware, roleMiddleware(ESCRITA),  ctrl.reativar);
router.patch('/:id/confirmar',    authMiddleware, roleMiddleware(ESCRITA),  ctrl.confirmarEstoque);
router.patch('/:id/custo',        authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizarCustoManual);
router.delete('/:id',             authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluir);

module.exports = router;