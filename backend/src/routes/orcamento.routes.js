const router  = require('express').Router();
const ctrl    = require('../controllers/orcamento.controller');
const pdfCtrl = require('../controllers/orcamento_pdf.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const ESCRITA  = ['ADMIN','GERENTE','COMPRADOR'];
const EXCLUSAO = ['ADMIN','GERENTE'];

router.post('/pdf',                      authMiddleware, roleMiddleware(LEITURA),  pdfCtrl.gerarPdf);

router.get('/',                          authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:id',                       authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.post('/',                         authMiddleware, roleMiddleware(ESCRITA),  ctrl.criar);
router.patch('/:id/cancelar',            authMiddleware, roleMiddleware(EXCLUSAO), ctrl.cancelar);

router.post('/:id/itens',               authMiddleware, roleMiddleware(ESCRITA),  ctrl.adicionarItem);
router.delete('/:id/itens/:itemId',     authMiddleware, roleMiddleware(ESCRITA),  ctrl.removerItem);
router.patch('/:id/itens/:itemId',      authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizarItem);

router.post('/:id/gerar-oc',            authMiddleware, roleMiddleware(ESCRITA),  ctrl.gerarOrdemCompra);

module.exports = router;