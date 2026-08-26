const router = require('express').Router();
const ctrl    = require('../controllers/ordemCompra.controller');
const pdfCtrl = require('../controllers/ordemCompra.pdf.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRAS'];
const ESCRITA  = ['ADMIN','GERENTE','COMPRAS'];
const EXCLUSAO = ['ADMIN','GERENTE','COMPRAS'];

router.get('/',                                       authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/proximo-id',                             authMiddleware, roleMiddleware(LEITURA),  ctrl.proximoId);
router.get('/:id/pdf',                                authMiddleware, roleMiddleware(LEITURA),  pdfCtrl.gerarPdf);
router.get('/:id',                                    authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.post('/',                                      authMiddleware, roleMiddleware(ESCRITA),  ctrl.criar);
router.post('/de-orcamento/:orcamentoId',              authMiddleware, roleMiddleware(ESCRITA),  ctrl.criarDeOrcamento);
router.put('/:id',                                    authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizar);
router.patch('/:id/finalizar',                        authMiddleware, roleMiddleware(ESCRITA),  ctrl.finalizar);
router.patch('/:id/cancelar',                         authMiddleware, roleMiddleware(EXCLUSAO), ctrl.cancelar);
router.patch('/:id/reverter',                         authMiddleware, roleMiddleware(EXCLUSAO), ctrl.reverter);
router.delete('/:id',                                 authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluir);
router.post('/:id/itens',                             authMiddleware, roleMiddleware(ESCRITA),  ctrl.adicionarItem);
router.delete('/:id/itens/:itemId',                   authMiddleware, roleMiddleware(ESCRITA),  ctrl.removerItem);
router.patch('/:id/itens/:itemId',                    authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizarItem);

module.exports = router;