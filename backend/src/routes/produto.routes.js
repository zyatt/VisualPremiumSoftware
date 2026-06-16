const router = require('express').Router();
const ctrl   = require('../controllers/produto.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN', 'GERENTE', 'COMPRAS', 'ORCAMENTISTA'];
const ESCRITA  = ['ADMIN', 'GERENTE'];
const EXCLUSAO = ['ADMIN', 'GERENTE'];

router.get('/categorias',                         authMiddleware, roleMiddleware(LEITURA),  ctrl.listarCategorias);
router.get('/',                                   authMiddleware, roleMiddleware(LEITURA),  ctrl.listar);
router.get('/:id',                                authMiddleware, roleMiddleware(LEITURA),  ctrl.buscarPorId);
router.post('/',                                  authMiddleware, roleMiddleware(ESCRITA),  ctrl.criar);
router.put('/:id',                                authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizar);
router.patch('/:id/desativar',                    authMiddleware, roleMiddleware(ESCRITA),  ctrl.desativar);
router.patch('/:id/reativar',                     authMiddleware, roleMiddleware(ESCRITA),  ctrl.reativar);
router.delete('/:id',                             authMiddleware, roleMiddleware(EXCLUSAO), ctrl.excluir);
router.post('/:id/materiais',                     authMiddleware, roleMiddleware(ESCRITA),  ctrl.adicionarMaterial);
router.patch('/:id/materiais/:materialItemId',    authMiddleware, roleMiddleware(ESCRITA),  ctrl.atualizarMaterial);
router.delete('/:id/materiais/:materialItemId',   authMiddleware, roleMiddleware(EXCLUSAO), ctrl.removerMaterial);

module.exports = router;