const svc = require('../services/historico.service');

const listar      = async (req, res, next) => { try { res.json(await svc.listar(req.query)); } catch(e){next(e);} };
const buscarPorId = async (req, res, next) => { try { res.json(await svc.buscarPorId(+req.params.id)); } catch(e){next(e);} };

module.exports = { listar, buscarPorId };