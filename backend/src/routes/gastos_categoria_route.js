const express = require('express');
const router  = express.Router();
const svc     = require('../services/gastos_categoria_service');

// GET /gastos-categoria/estoque
// Retorna valor atual em estoque (qtd × custo última compra) agrupado por categoria
router.get('/estoque', async (req, res) => {
  try {
    const dados = await svc.valorEmEstoque();
    res.json(dados);
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message || 'Erro interno' });
  }
});

// GET /gastos-categoria?dataInicio=YYYY-MM-DD&dataFim=YYYY-MM-DD
// Retorna gastos reais (saídas com origem em OC) de OS fechadas
router.get('/', async (req, res) => {
  try {
    const { dataInicio, dataFim } = req.query;
    const dados = await svc.gastosPorCategoria({ dataInicio, dataFim });
    res.json(dados);
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message || 'Erro interno' });
  }
});

// GET /gastos-categoria/mensal?ano=2024
router.get('/mensal', async (req, res) => {
  try {
    const { ano } = req.query;
    const dados   = await svc.gastosMensais({ ano });
    res.json(dados);
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message || 'Erro interno' });
  }
});

module.exports = router;