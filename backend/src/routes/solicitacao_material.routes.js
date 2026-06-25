const router = require('express').Router();
const ctrl   = require('../controllers/solicitacao_material.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const ACESSO = ['ADMIN', 'GERENTE', 'COMPRAS'];

// ─── SSE ─────────────────────────────────────────────────────────────────────
router.get('/notificacoes', authMiddleware, ctrl.notificacoes);

// ─── Contagem e visualização (sem roleMiddleware — qualquer autenticado) ──────
router.get('/novas/count', authMiddleware, ctrl.contarNovas);

// Chamado pelo Flutter ao entrar na página — persiste no banco quem visualizou
router.post('/marcar-visualizadas', authMiddleware, ctrl.marcarVisualizadas);

// ─── CRUD ─────────────────────────────────────────────────────────────────────
router.get('/',    authMiddleware, roleMiddleware(ACESSO), ctrl.listar);
router.get('/:id', authMiddleware, roleMiddleware(ACESSO), ctrl.buscarPorId);

router.post(
  '/',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.upload.single('imagem'),
  ctrl.criar,
);
router.put(
  '/:id',
  authMiddleware,
  roleMiddleware(ACESSO),
  ctrl.upload.single('imagem'),
  ctrl.atualizar,
);
router.delete('/:id', authMiddleware, roleMiddleware(ACESSO), ctrl.excluir);

// ─── Logs de edição ───────────────────────────────────────────────────────────
router.get('/:id/logs', authMiddleware, roleMiddleware(ACESSO), ctrl.listarLogs);

module.exports = router;