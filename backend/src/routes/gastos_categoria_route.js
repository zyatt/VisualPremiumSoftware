const express = require('express');
const router  = express.Router();
const svc = require('../services/gastos_categoria_service');


// GET /gastos-categoria?dataInicio=YYYY-MM-DD&dataFim=YYYY-MM-DD
router.get('/', async (req, res) => {
  try {
    const { dataInicio, dataFim } = req.query;
    const dados = await svc.gastosPorCategoria({ dataInicio, dataFim });
    res.json(dados);
  } catch (err) {
    const status = err.status || 500;
    res.status(status).json({ error: err.message || 'Erro interno' });
  }
});

// GET /gastos-categoria/mensal?ano=2024
router.get('/mensal', async (req, res) => {
  try {
    const { ano } = req.query;
    const dados = await svc.gastosMensais({ ano });
    res.json(dados);
  } catch (err) {
    const status = err.status || 500;
    res.status(status).json({ error: err.message || 'Erro interno' });
  }
});

module.exports = router;