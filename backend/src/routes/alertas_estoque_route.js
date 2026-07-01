const router = require('express').Router();
const svc    = require('../services/alertas_estoque_service');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS'];

// GET /api/alertas-estoque
// Retorna materiais com status CRITICO, ordenados por nome.
router.get('/', authMiddleware, roleMiddleware(LEITURA), async (req, res, next) => {
  try {
    res.json(await svc.listarAlertasEstoque());
  } catch (err) {
    next(err);
  }
});

module.exports = router;