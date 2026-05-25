const router = require('express').Router();
const ctrl   = require('../controllers/estoque.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const ESCRITA  = ['ADMIN','GERENTE','ESTOQUISTA'];
const EXCLUSAO = ['ADMIN','GERENTE'];

router.get('/',                                   authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:numeroOS',                          authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorNumeroOS);
router.post('/movimentacoes',                     authMiddleware, roleMiddleware(ESCRITA),  ctrl.registrarMovimentacao);
router.delete('/movimentacoes/:movimentacaoId',   authMiddleware, roleMiddleware(ESCRITA),  ctrl.removerMovimentacao);
router.delete('/:numeroOS',                       authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluirRelacaoOS);
// Fechar OS: migra para relatórios
router.patch('/:numeroOS/fechar',                 authMiddleware, roleMiddleware(ESCRITA),  ctrl.fecharOS);

module.exports = router;