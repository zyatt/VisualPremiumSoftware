const router = require('express').Router();
const ctrl = require('../controllers/fornecedor.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA  = ['ADMIN','GERENTE','COMPRADOR','ESTOQUISTA','VISUALIZADOR'];
const ESCRITA  = ['ADMIN','GERENTE','COMPRADOR'];

router.get('/',    authMiddleware, roleMiddleware(LEITURA), ctrl.listar);
router.get('/:id', authMiddleware, roleMiddleware(LEITURA), ctrl.buscarPorId);
router.post('/',   authMiddleware, roleMiddleware(ESCRITA), ctrl.criar);
router.put('/:id', authMiddleware, roleMiddleware(ESCRITA), ctrl.atualizar);
router.delete('/:id', authMiddleware, roleMiddleware(['ADMIN','GERENTE']), ctrl.remover);

// Vínculos de materiais
router.post('/:id/materiais',                    authMiddleware, roleMiddleware(ESCRITA), ctrl.vincularMaterial);
router.delete('/:id/materiais/:materialId',      authMiddleware, roleMiddleware(ESCRITA), ctrl.desvincularMaterial);
router.patch('/:id/materiais/:materialId/preco', authMiddleware, roleMiddleware(ESCRITA), ctrl.atualizarPreco);

module.exports = router;