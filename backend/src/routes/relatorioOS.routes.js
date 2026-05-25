const router = require('express').Router();
const ctrl   = require('../controllers/relatorioOS.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA   = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const RELATORIO = ['ADMIN','GERENTE','ESTOQUISTA'];

router.get('/',                       authMiddleware, roleMiddleware(LEITURA),   ctrl.listar);
router.get('/:numeroOS',              authMiddleware, roleMiddleware(LEITURA),   ctrl.buscarPorNumeroOS);
router.get('/:numeroOS/pdf-data',     authMiddleware, roleMiddleware(RELATORIO), ctrl.dadosParaPDF);
// Fechar OS: muda status para FECHADA e gera o relatório
router.patch('/:numeroOS/fechar',     authMiddleware, roleMiddleware(RELATORIO), ctrl.fecharOS);

module.exports = router;