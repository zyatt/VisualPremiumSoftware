const router  = require('express').Router();
const ctrl    = require('../controllers/relatorioOS.controller');
const pdfCtrl = require('../controllers/relatorioOS.pdf.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA   = ['ADMIN', 'GERENTE', 'COMPRAS'];
const RELATORIO = ['ADMIN', 'GERENTE', 'COMPRAS'];

router.get('/',                          authMiddleware, roleMiddleware(LEITURA),   ctrl.listar);
router.get('/:numeroOS',                 authMiddleware, roleMiddleware(LEITURA),   ctrl.buscarPorNumeroOS);

router.get('/:numeroOS/pdf',             authMiddleware, roleMiddleware(RELATORIO), pdfCtrl.gerarPdf);

router.get('/:numeroOS/pdf-data',        authMiddleware, roleMiddleware(RELATORIO), ctrl.dadosParaPDF);
router.patch('/:numeroOS/fechar',        authMiddleware, roleMiddleware(RELATORIO), ctrl.fecharOS);
router.patch('/:numeroOS/reverter',      authMiddleware, roleMiddleware(RELATORIO), ctrl.reverterOS);

module.exports = router;