const router  = require('express').Router();
const ctrl    = require('../controllers/orcamento.controller');
const pdfCtrl = require('../controllers/orcamento_pdf.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRAS'];
const ESCRITA  = ['ADMIN','GERENTE','COMPRAS'];
const APROVACAO = ['ADMIN','GERENTE','COMPRAS'];
const EXCLUSAO = ['ADMIN','GERENTE','COMPRAS'];

router.post('/pdf',                      authMiddleware, roleMiddleware(LEITURA),  pdfCtrl.gerarPdf);

router.get('/',                          authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:id',                       authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.post('/',                         authMiddleware, roleMiddleware(ESCRITA),  ctrl.criar);
router.patch('/:id',                     authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizar);      // ← aqui, antes das subrotas
router.patch('/:id/cancelar',            authMiddleware, roleMiddleware(EXCLUSAO), ctrl.cancelar);
router.delete('/:id',                    authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluir);

router.post('/:id/itens',                authMiddleware, roleMiddleware(ESCRITA),  ctrl.adicionarItem);
router.delete('/:id/itens',              authMiddleware, roleMiddleware(ESCRITA),  ctrl.limparItens);   // ← limpa todos de uma vez
router.delete('/:id/itens/:itemId',      authMiddleware, roleMiddleware(ESCRITA),  ctrl.removerItem);
router.patch('/:id/itens/:itemId',       authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizarItem);

router.patch('/:id/enviar-aprovacao',    authMiddleware, roleMiddleware(ESCRITA),  ctrl.enviarParaAprovacao);
router.patch('/:id/aprovar',             authMiddleware, roleMiddleware(APROVACAO), ctrl.aprovar);
router.patch('/:id/rejeitar',            authMiddleware, roleMiddleware(APROVACAO), ctrl.rejeitar);
router.patch('/:id/reabrir',             authMiddleware, roleMiddleware(APROVACAO), ctrl.reabrir);

router.patch('/:id/fornecedores-ocultos', authMiddleware, roleMiddleware(ESCRITA), ctrl.definirFornecedorOculto);

router.post('/:id/gerar-oc',             authMiddleware, roleMiddleware(ESCRITA),  ctrl.gerarOrdemCompra);

module.exports = router;