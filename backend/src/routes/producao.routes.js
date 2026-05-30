const router = require('express').Router();
const ctrl   = require('../controllers/producao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// Leitura: todos os roles que acessam produção (incluindo COMPRAS como somente leitura)
const LEITURA_ROLES    = ['ADMIN', 'GERENTE', 'PRODUCAO', 'COMPRAS'];
// Escrita: somente quem pode realmente solicitar/operar
const OPERACAO_ROLES   = ['ADMIN', 'GERENTE', 'PRODUCAO'];

// Materiais (somente leitura)
router.get('/materiais',   authMiddleware, roleMiddleware(LEITURA_ROLES), ctrl.listarMateriais);
router.get('/categorias',  authMiddleware, roleMiddleware(LEITURA_ROLES), ctrl.listarCategorias);

// Solicitações ativas — leitura liberada para COMPRAS, escrita não
router.get('/solicitacoes',      authMiddleware, roleMiddleware(LEITURA_ROLES),  ctrl.listarSolicitacoes);
router.get('/solicitacoes/:id',  authMiddleware, roleMiddleware(LEITURA_ROLES),  ctrl.buscarSolicitacao);
router.post('/solicitacoes',     authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.criarSolicitacao);

// Baixas e finalização — somente operadores
router.post('/solicitacoes/:id/baixa',     authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.registrarBaixa);
router.post('/solicitacoes/:id/finalizar', authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.finalizarSolicitacao);

// Histórico (finalizadas) — leitura para todos, exclusão apenas ADMIN/GERENTE
router.get('/historico',        authMiddleware, roleMiddleware(LEITURA_ROLES),           ctrl.listarHistorico);
router.delete('/historico/:id', authMiddleware, roleMiddleware(['ADMIN', 'GERENTE']),    ctrl.excluirHistorico);

module.exports = router;