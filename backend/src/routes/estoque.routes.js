const router = require('express').Router();
const ctrl = require('../controllers/estoque.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const ESCRITA  = ['ADMIN','GERENTE','ESTOQUISTA'];

// Relações OS (grid de cards)
router.get('/relacoes',                           authMiddleware, roleMiddleware(LEITURA), ctrl.listarRelacoesOS);
router.get('/relacoes/:numeroOS',                 authMiddleware, roleMiddleware(LEITURA), ctrl.buscarRelacaoOS);

// Movimentações
router.post('/movimentacao',                      authMiddleware, roleMiddleware(ESCRITA), ctrl.registrarMovimentacao);
router.get('/material/:materialId/movimentacoes', authMiddleware, roleMiddleware(LEITURA), ctrl.listarMovimentacoesPorMaterial);

module.exports = router;