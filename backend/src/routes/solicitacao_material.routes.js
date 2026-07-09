const router = require('express').Router();
const ctrl   = require('../controllers/solicitacao_material.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const ACESSO = ['ADMIN', 'GERENTE', 'COMPRAS'];

router.get('/notificacoes', authMiddleware, ctrl.notificacoes);

router.get('/novas/count',        authMiddleware, ctrl.contarNovas);
router.post('/marcar-visualizadas', authMiddleware, ctrl.marcarVisualizadas);

router.patch(
  '/itens/:itemId/comprado',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.marcarItemComprado,
);

router.patch(
  '/adicionais/:adicionalId/comprado',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.marcarAdicionalComprado,
);

router.patch(
  '/itens/:itemId',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.atualizarItem,
);

router.delete(
  '/itens/:itemId',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.excluirItem,
);

router.patch(
  '/adicionais/:adicionalId',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.atualizarAdicional,
);

router.delete(
  '/adicionais/:adicionalId',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.excluirAdicional,
);

router.get(
  '/verificar-os/:numeroOS',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.verificarOS,
);

router.get('/',    authMiddleware, roleMiddleware(ACESSO), ctrl.listar);
router.get('/:id', authMiddleware, roleMiddleware(ACESSO), ctrl.buscarPorId);

router.post(
  '/',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.uploadAny,
  ctrl.criar,
);

router.put(
  '/:id',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.atualizar,
);

router.post(
  '/:id/adicionais',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.uploadAny,
  ctrl.adicionarMateriais,
);

router.delete('/:id', authMiddleware, roleMiddleware(ACESSO), ctrl.excluir);

router.get('/:id/logs', authMiddleware, roleMiddleware(ACESSO), ctrl.listarLogs);

module.exports = router;