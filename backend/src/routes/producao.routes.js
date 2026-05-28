const router = require('express').Router();
const ctrl   = require('../controllers/producao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// Roles que acessam produção
const PRODUCAO_ROLES = ['ADMIN', 'GERENTE', 'PRODUCAO'];

// Materiais (somente leitura)
router.get('/materiais',   authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.listarMateriais);
router.get('/categorias',  authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.listarCategorias);

// Solicitações ativas
router.get('/solicitacoes',      authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.listarSolicitacoes);
router.get('/solicitacoes/:id',  authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.buscarSolicitacao);
router.post('/solicitacoes',     authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.criarSolicitacao);

// Baixas e finalização
router.post('/solicitacoes/:id/baixa',     authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.registrarBaixa);
router.post('/solicitacoes/:id/finalizar', authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.finalizarSolicitacao);

// Histórico (finalizadas)
router.get('/historico', authMiddleware, roleMiddleware(PRODUCAO_ROLES), ctrl.listarHistorico);

module.exports = router;