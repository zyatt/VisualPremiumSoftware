const router = require('express').Router();
const ctrl   = require('../controllers/producao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// Fluxo antigo de "solicitação de produção" (reserva/baixa direto do
// ESTOQUE NORMAL). Os cargos PRODUCAO1/PRODUCAO2 NÃO têm acesso ao fluxo de
// solicitações/baixas/histórico aqui — eles operam o estoque de produção
// separado (ver estoqueProducao.routes.js). Mantido apenas para
// ADMIN/GERENTE/COMPRAS consultarem/gerenciarem o histórico legado.
const LEITURA_ROLES    = ['ADMIN', 'GERENTE', 'COMPRAS'];
const OPERACAO_ROLES   = ['ADMIN', 'GERENTE'];

// Leitura de materiais/categorias É liberada também para PRODUCAO1/PRODUCAO2:
// a tela de Produção (aba "Geral"/"Sem categoria" e o botão "Retalhos") usa
// estas duas rotas só para leitura, sem passar pelo menu Estoque (que
// continua bloqueado para esses cargos no frontend).
const LEITURA_MATERIAIS_ROLES = ['ADMIN', 'GERENTE', 'COMPRAS', 'PRODUCAO1', 'PRODUCAO2'];

router.get('/materiais',   authMiddleware, roleMiddleware(LEITURA_MATERIAIS_ROLES), ctrl.listarMateriais);
router.get('/categorias',  authMiddleware, roleMiddleware(LEITURA_MATERIAIS_ROLES), ctrl.listarCategorias);

router.get('/solicitacoes',      authMiddleware, roleMiddleware(LEITURA_ROLES),  ctrl.listarSolicitacoes);
router.get('/solicitacoes/:id',  authMiddleware, roleMiddleware(LEITURA_ROLES),  ctrl.buscarSolicitacao);
router.post('/solicitacoes',     authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.criarSolicitacao);

router.post('/solicitacoes/:id/baixa',     authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.registrarBaixa);
router.post('/solicitacoes/:id/finalizar', authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.finalizarSolicitacao);

router.get('/historico',        authMiddleware, roleMiddleware(LEITURA_ROLES),           ctrl.listarHistorico);
router.delete('/historico/:id', authMiddleware, roleMiddleware(['ADMIN', 'GERENTE']),    ctrl.excluirHistorico);

module.exports = router;