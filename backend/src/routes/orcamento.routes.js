const router  = require('express').Router();
const ctrl    = require('../controllers/orcamento.controller');
const pdfCtrl = require('../controllers/orcamento_pdf.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRAS'];
const ESCRITA  = ['ADMIN','GERENTE','COMPRAS'];
const APROVACAO = ['ADMIN','GERENTE','COMPRAS'];
const EXCLUSAO = ['ADMIN','GERENTE','COMPRAS'];

router.post('/pdf',                      authMiddleware, roleMiddleware(LEITURA),  pdfCtrl.gerarPdf);

// SSE precisa vir antes de '/:id' para não ser capturado por ele.
router.get('/stream',                    authMiddleware, roleMiddleware(LEITURA),  ctrl.streamSSE);
router.get('/abertos',                   authMiddleware, roleMiddleware(LEITURA),  ctrl.listarAbertos);

router.get('/',                          authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:id',                       authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.post('/',                         authMiddleware, roleMiddleware(ESCRITA),  ctrl.criar);
router.patch('/:id',                     authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizar);
router.patch('/:id/cancelar',            authMiddleware, roleMiddleware(EXCLUSAO), ctrl.cancelar);
router.delete('/:id',                    authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluir);

router.post('/:id/itens',                authMiddleware, roleMiddleware(ESCRITA),  ctrl.adicionarItem);
router.put('/:id/itens',                 authMiddleware, roleMiddleware(ESCRITA),  ctrl.substituirItens);
router.delete('/:id/itens',              authMiddleware, roleMiddleware(ESCRITA),  ctrl.limparItens);
router.delete('/:id/itens/:itemId',      authMiddleware, roleMiddleware(ESCRITA),  ctrl.removerItem);
router.patch('/:id/itens/:itemId',       authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizarItem);

router.patch('/:id/enviar-aprovacao',    authMiddleware, roleMiddleware(ESCRITA),  ctrl.enviarParaAprovacao);
router.patch('/:id/aprovar',             authMiddleware, roleMiddleware(APROVACAO), ctrl.aprovar);
router.patch('/:id/rejeitar',            authMiddleware, roleMiddleware(APROVACAO), ctrl.rejeitar);
router.patch('/:id/reabrir',             authMiddleware, roleMiddleware(APROVACAO), ctrl.reabrir);

router.patch('/:id/fornecedores-ocultos', authMiddleware, roleMiddleware(ESCRITA), ctrl.definirFornecedorOculto);

router.post('/:id/travar',               authMiddleware, roleMiddleware(ESCRITA),  ctrl.travarEdicao);
router.post('/:id/travar/heartbeat',     authMiddleware, roleMiddleware(ESCRITA),  ctrl.renovarTravaEdicao);
router.post('/:id/destravar',            authMiddleware, roleMiddleware(ESCRITA),  ctrl.destravarEdicao);

router.post('/:id/gerar-oc',             authMiddleware, roleMiddleware(ESCRITA),  ctrl.gerarOrdemCompra);

module.exports = router;