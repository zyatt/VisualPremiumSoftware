const router = require('express').Router();
const ctrl    = require('../controllers/estoque.controller');
const pdfCtrl = require('../controllers/estoque.pdf.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const ESCRITA  = ['ADMIN','GERENTE','ESTOQUISTA'];

router.get('/pdf',                                authMiddleware, roleMiddleware(LEITURA), pdfCtrl.gerarPdf);

router.get('/relacoes',                           authMiddleware, roleMiddleware(LEITURA), ctrl.listarRelacoesOS);
router.get('/relacoes/:numeroOS',                 authMiddleware, roleMiddleware(LEITURA), ctrl.buscarRelacaoOS);
router.delete('/relacoes/:numeroOS',              authMiddleware, roleMiddleware(ESCRITA), ctrl.excluirRelacaoOS);

router.post('/movimentacao',                      authMiddleware, roleMiddleware(ESCRITA), ctrl.registrarMovimentacao);
router.delete('/movimentacao/:id',                authMiddleware, roleMiddleware(ESCRITA), ctrl.removerMovimentacao);
router.get('/material/:materialId/movimentacoes', authMiddleware, roleMiddleware(LEITURA), ctrl.listarMovimentacoesPorMaterial);

module.exports = router;