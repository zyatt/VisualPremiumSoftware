// audit-log.controller.js

const svc = require('../services/audit-log.service');

const listar = async (req, res, next) => {
  try {
    res.json(await svc.listar(req.query));
  } catch (e) { next(e); }
};

const listarPorMaterial = async (req, res, next) => {
  try {
    const limite = req.query.limite ? Number(req.query.limite) : 200;
    res.json(await svc.listarPorMaterial(+req.params.materialId, limite));
  } catch (e) { next(e); }
};

module.exports = { listar, listarPorMaterial };