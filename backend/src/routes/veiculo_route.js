const express = require('express');
const router  = express.Router();
const svc     = require('../services/veiculo_service');

router.get('/', async (req, res) => {
  try {
    res.json(await svc.listarVeiculos());
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    res.status(201).json(await svc.criarVeiculo(req.body));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    res.json(await svc.atualizarVeiculo(parseInt(req.params.id), req.body));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await svc.desativarVeiculo(parseInt(req.params.id));
    res.json({ ok: true });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.get('/:id/manutencoes', async (req, res) => {
  try {
    res.json(await svc.listarManutencoes(parseInt(req.params.id)));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/manutencoes', async (req, res) => {
  try {
    const payload = { ...req.body, veiculoId: parseInt(req.params.id) };
    res.status(201).json(await svc.criarManutencao(payload));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.put('/manutencoes/:mid', async (req, res) => {
  try {
    res.json(await svc.atualizarManutencao(parseInt(req.params.mid), req.body));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.delete('/manutencoes/:mid', async (req, res) => {
  try {
    await svc.deletarManutencao(parseInt(req.params.mid));
    res.json({ ok: true });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.put('/manutencoes/:mid/finalizar', async (req, res) => {
  try {
    const finalizada = req.body?.finalizada ?? true;
    res.json(await svc.finalizarManutencao(parseInt(req.params.mid), { finalizada }));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.get('/gastos', async (req, res) => {
  try {
    const { dataInicio, dataFim } = req.query;
    res.json(await svc.gastosPorVeiculo({ dataInicio, dataFim }));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.get('/gastos/resumo', async (req, res) => {
  try {
    res.json(await svc.resumoGastosVeiculo({ ano: req.query.ano }));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

module.exports = router;