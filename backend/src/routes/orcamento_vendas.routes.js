const router = require('express').Router();
const ctrl   = require('../controllers/orcamento_venda.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN', 'GERENTE', 'ORCAMENTISTA'];
const ESCRITA  = ['ADMIN', 'GERENTE', 'ORCAMENTISTA'];
const APROVACAO = ['ADMIN', 'GERENTE'];

router.get('/clientes',                     authMiddleware, roleMiddleware(LEITURA),   ctrl.listarClientes);

router.get('/',                             authMiddleware, roleMiddleware(LEITURA),   ctrl.listar);
router.get('/:id',                          authMiddleware, roleMiddleware(LEITURA),   ctrl.buscarPorId);
router.post('/',                            authMiddleware, roleMiddleware(ESCRITA),   ctrl.criar);
router.put('/:id',                          authMiddleware, roleMiddleware(ESCRITA),   ctrl.atualizar);
router.delete('/:id',                       authMiddleware, roleMiddleware(APROVACAO), ctrl.excluir);

router.patch('/:id/aprovar',                authMiddleware, roleMiddleware(APROVACAO), ctrl.aprovar);
router.patch('/:id/reprovar',               authMiddleware, roleMiddleware(APROVACAO), ctrl.reprovar);

router.post('/:id/itens',                   authMiddleware, roleMiddleware(ESCRITA),   ctrl.adicionarItem);
router.put('/:id/itens/:itemId',            authMiddleware, roleMiddleware(ESCRITA),   ctrl.atualizarItem);
router.delete('/:id/itens/:itemId',         authMiddleware, roleMiddleware(ESCRITA),   ctrl.removerItem);

module.exports = router;