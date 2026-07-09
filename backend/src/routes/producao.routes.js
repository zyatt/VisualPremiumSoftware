const router = require('express').Router();
const ctrl   = require('../controllers/producao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA_ROLES    = ['ADMIN', 'GERENTE', 'PRODUCAO', 'COMPRAS'];
const OPERACAO_ROLES   = ['ADMIN', 'GERENTE', 'PRODUCAO'];

router.get('/materiais',   authMiddleware, roleMiddleware(LEITURA_ROLES), ctrl.listarMateriais);
router.get('/categorias',  authMiddleware, roleMiddleware(LEITURA_ROLES), ctrl.listarCategorias);

router.get('/solicitacoes',      authMiddleware, roleMiddleware(LEITURA_ROLES),  ctrl.listarSolicitacoes);
router.get('/solicitacoes/:id',  authMiddleware, roleMiddleware(LEITURA_ROLES),  ctrl.buscarSolicitacao);
router.post('/solicitacoes',     authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.criarSolicitacao);

router.post('/solicitacoes/:id/baixa',     authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.registrarBaixa);
router.post('/solicitacoes/:id/finalizar', authMiddleware, roleMiddleware(OPERACAO_ROLES), ctrl.finalizarSolicitacao);

router.get('/historico',        authMiddleware, roleMiddleware(LEITURA_ROLES),           ctrl.listarHistorico);
router.delete('/historico/:id', authMiddleware, roleMiddleware(['ADMIN', 'GERENTE']),    ctrl.excluirHistorico);

module.exports = router;