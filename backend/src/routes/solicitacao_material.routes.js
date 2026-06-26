const router = require('express').Router();
const ctrl   = require('../controllers/solicitacao_material.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const ACESSO = ['ADMIN', 'GERENTE', 'COMPRAS'];

// ─── SSE ─────────────────────────────────────────────────────────────────────
router.get('/notificacoes', authMiddleware, ctrl.notificacoes);

// ─── Contagem e visualização ──────────────────────────────────────────────────
router.get('/novas/count',        authMiddleware, ctrl.contarNovas);
router.post('/marcar-visualizadas', authMiddleware, ctrl.marcarVisualizadas);

// ─── Comprado: itens originais ────────────────────────────────────────────────
// Qualquer usuário ACESSO pode marcar; só ADMIN pode desmarcar (validação no service).
router.patch(
  '/itens/:itemId/comprado',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.marcarItemComprado,
);

// ─── Comprado: adicionais ─────────────────────────────────────────────────────
router.patch(
  '/adicionais/:adicionalId/comprado',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.marcarAdicionalComprado,
);

// ─── CRUD ─────────────────────────────────────────────────────────────────────
router.get('/',    authMiddleware, roleMiddleware(ACESSO), ctrl.listar);
router.get('/:id', authMiddleware, roleMiddleware(ACESSO), ctrl.buscarPorId);

// Criar: aceita múltiplos arquivos (imagens[0], imagens[1], …)
router.post(
  '/',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.uploadAny,
  ctrl.criar,
);

// Atualizar cabeçalho (somente ADMIN — validação no service)
router.put(
  '/:id',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.atualizar,
);

// Adicionar materiais extras
router.post(
  '/:id/adicionais',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.uploadAny,
  ctrl.adicionarMateriais,
);

router.delete('/:id', authMiddleware, roleMiddleware(ACESSO), ctrl.excluir);

// ─── Logs ─────────────────────────────────────────────────────────────────────
router.get('/:id/logs', authMiddleware, roleMiddleware(ACESSO), ctrl.listarLogs);

module.exports = router;