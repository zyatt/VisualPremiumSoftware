const router = require('express').Router();
const svc    = require('../services/alertas_estoque_service');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS'];

router.get('/', authMiddleware, roleMiddleware(LEITURA), async (req, res, next) => {
  try {
    res.json(await svc.listarAlertasEstoque());
  } catch (err) {
    next(err);
  }
});

module.exports = router;