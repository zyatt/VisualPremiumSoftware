const router = require('express').Router();

const ctrl    = require('../controllers/estoque.controller');
const pdfCtrl = require('../controllers/estoque.pdf.controller');

const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRAS'];
const ESCRITA  = ['ADMIN','GERENTE','COMPRAS'];
const EXCLUSAO = ['ADMIN','GERENTE','COMPRAS'];

router.get('/pdf', authMiddleware, roleMiddleware(LEITURA), pdfCtrl.gerarPdf);

router.get('/',          authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/todas', authMiddleware, roleMiddleware(LEITURA), ctrl.listarTodas);
router.get('/:numeroOS', authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorNumeroOS);

router.post('/movimentacoes',                    authMiddleware, roleMiddleware(ESCRITA),  ctrl.registrarMovimentacao);
router.delete('/movimentacoes/:movimentacaoId',  authMiddleware, roleMiddleware(ESCRITA),  ctrl.removerMovimentacao);
router.patch('/:id/renomear', authMiddleware, roleMiddleware(['ADMIN', 'GERENTE', 'COMPRAS']), ctrl.renomearOS);
// ↓ Usam o id numérico da RelacaoOS (não o numeroOS) para identificar unicamente a relação
router.delete('/:relacaoOSId',         authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluirRelacaoOS);
router.patch('/:relacaoOSId/fechar',   authMiddleware, roleMiddleware(ESCRITA),  ctrl.fecharOS);


module.exports = router;