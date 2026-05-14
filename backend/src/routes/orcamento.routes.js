const router = require('express').Router();
const ctrl = require('../controllers/orcamento.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const ESCRITA = ['ADMIN','GERENTE','COMPRADOR'];

router.get('/',                              authMiddleware, roleMiddleware(LEITURA), ctrl.listar);
router.get('/:id',                           authMiddleware, roleMiddleware(LEITURA), ctrl.buscarPorId);
router.post('/',                             authMiddleware, roleMiddleware(ESCRITA), ctrl.criar);
router.patch('/:id/cancelar',                authMiddleware, roleMiddleware(ESCRITA), ctrl.cancelar);
router.post('/:id/itens',                    authMiddleware, roleMiddleware(ESCRITA), ctrl.adicionarItem);
router.delete('/:id/itens/:itemId',          authMiddleware, roleMiddleware(ESCRITA), ctrl.removerItem);
router.patch('/:id/itens/:itemId',           authMiddleware, roleMiddleware(ESCRITA), ctrl.atualizarItem);
router.post('/:id/gerar-ordem-compra',       authMiddleware, roleMiddleware(ESCRITA), ctrl.gerarOrdemCompra);

module.exports = router;