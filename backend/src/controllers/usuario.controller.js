const usuarioService = require('../services/usuario.service');

async function login(req, res, next) {
  try {
    const { username, senha } = req.body;
    const result = await usuarioService.login(username, senha);
    res.json(result);
  } catch (err) { next(err); }
}

async function refresh(req, res, next) {
  try {
    const result = await usuarioService.refresh(req.usuario);
    res.json(result);
  } catch (err) { next(err); }
}

async function listar(req, res, next) {
  try {
    const usuarios = await usuarioService.listar();
    res.json(usuarios);
  } catch (err) { next(err); }
}

async function criar(req, res, next) {
  try {
    const usuario = await usuarioService.criar(req.body);
    res.status(201).json(usuario);
  } catch (err) { next(err); }
}

async function atualizar(req, res, next) {
  try {
    const usuario = await usuarioService.atualizar(Number(req.params.id), req.body);
    res.json(usuario);
  } catch (err) { next(err); }
}

async function remover(req, res, next) {
  try {
    await usuarioService.remover(Number(req.params.id));
    res.status(204).send();
  } catch (err) { next(err); }
}

module.exports = { login, refresh, listar, criar, atualizar, remover };