const svc = require('../services/fornecedor.service');

const listar = async (req, res, next) => {
  try {
    res.json(
      await svc.listar(
        req.query.busca,
        req.query.tipo,
        req.query.id,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const buscarPorId = async (req, res, next) => {
  try {
    res.json(await svc.buscarPorId(+req.params.id));
  } catch (e) {
    next(e);
  }
};

const criar = async (req, res, next) => {
  try {
    res.status(201).json(await svc.criar(req.body));
  } catch (e) {
    next(e);
  }
};

const atualizar = async (req, res, next) => {
  try {
    res.json(await svc.atualizar(+req.params.id, req.body));
  } catch (e) {
    next(e);
  }
};

const remover = async (req, res, next) => {
  try {
    await svc.remover(+req.params.id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
};

const buscarParaVinculo = async (req, res, next) => {
  try {
    res.json(
      await svc.buscarParaVinculo(
        req.query.busca,
        req.query.limite,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const listarPorMaterial = async (req, res, next) => {
  try {
    res.json(await svc.listarPorMaterial(+req.params.materialId));
  } catch (e) {
    next(e);
  }
};

const vincularMaterial = async (req, res, next) => {
  try {
    const { materialId, preco, precoMetroQuadrado } = req.body;

    res.json(
      await svc.vincularMaterial(
        +req.params.id,
        materialId,
        preco,
        precoMetroQuadrado,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const desvincularMaterial = async (req, res, next) => {
  try {
    res.json(
      await svc.desvincularMaterial(
        +req.params.id,
        +req.params.materialId,
      ),
    );
  } catch (e) {
    next(e);
  }
};

const atualizarPreco = async (req, res, next) => {
  try {
    res.json(
      await svc.atualizarPrecoVinculo(
        +req.params.id,
        +req.params.materialId,
        req.body,
      ),
    );
  } catch (e) {
    next(e);
  }
};

module.exports = {
  listar,
  buscarParaVinculo,
  buscarPorId,
  criar,
  atualizar,
  remover,
  listarPorMaterial,
  vincularMaterial,
  desvincularMaterial,
  atualizarPreco,
};