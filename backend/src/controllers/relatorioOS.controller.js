const svc = require('../services/relatorioOS.service');

const listar            = async (req, res, next) => { try { res.json(await svc.listar(req.query)); } catch(e){next(e);} };
const buscarPorNumeroOS = async (req, res, next) => { try { res.json(await svc.buscarPorNumeroOS(req.params.numeroOS)); } catch(e){next(e);} };
const dadosParaPDF      = async (req, res, next) => { try { res.json(await svc.dadosParaPDF(req.params.numeroOS)); } catch(e){next(e);} };
const fecharOS          = async (req, res, next) => { try { res.json(await svc.fecharOS(req.params.numeroOS)); } catch(e){next(e);} };
const reverterOS        = async (req, res, next) => { try { res.json(await svc.reverterOS(req.params.numeroOS)); } catch(e){next(e);} };

module.exports = { listar, buscarPorNumeroOS, dadosParaPDF, fecharOS, reverterOS };