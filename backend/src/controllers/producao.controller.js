// producao.controller.js
const svc = require('../services/producao.service');

// GET /producao/materiais?busca=&categoria=&status=&id=&identificador=&medida=&espessura=
const listarMateriais = async (req, res, next) => {
  try {
    const { busca, categoria, status, id, identificador, medida, espessura } = req.query;
    res.json(await svc.listarMateriais({ busca, categoria, status, id, identificador, medida, espessura }));
  } catch (e) { next(e); }
};

// GET /producao/categorias
const listarCategorias = async (req, res, next) => {
  try {
    res.json(await svc.listarCategorias());
  } catch (e) { next(e); }
};

// GET /producao/solicitacoes?status=ABERTA,EM_USO&busca=
const listarSolicitacoes = async (req, res, next) => {
  try {
    const { status, busca } = req.query;
    const statusArr = status ? status.split(',').map((s) => s.trim()) : undefined;
    const usuarioId = req.usuario.role === 'PRODUCAO' ? req.usuario.id : undefined;
    res.json(await svc.listarSolicitacoes({ usuarioId, status: statusArr, busca }));
  } catch (e) { next(e); }
};

const listarHistorico = async (req, res, next) => {
  try {
    const { busca } = req.query;
    const usuarioId = req.usuario.role === 'PRODUCAO' ? req.usuario.id : undefined;
    res.json(await svc.listarSolicitacoes({ usuarioId, status: ['FINALIZADA'], busca }));
  } catch (e) { next(e); }
};

// GET /producao/solicitacoes/:id
const buscarSolicitacao = async (req, res, next) => {
  try {
    res.json(await svc.buscarSolicitacao(Number(req.params.id)));
  } catch (e) { next(e); }
};

// POST /producao/solicitacoes
const criarSolicitacao = async (req, res, next) => {
  try {
    const { materialId, descricaoItem, quantidadeReservada, numeroOS } = req.body;
    const sol = await svc.criarSolicitacao({
      materialId:          Number(materialId),
      descricaoItem,
      quantidadeReservada: Number(quantidadeReservada),
      numeroOS,
      usuarioId:           req.usuario.id,
      usuarioNome:         req.usuario.nome ?? req.usuario.username,
    });
    res.status(201).json(sol);
  } catch (e) { next(e); }
};

// POST /producao/solicitacoes/:id/baixa
const registrarBaixa = async (req, res, next) => {
  try {
    const { quantidade, observacao } = req.body;
    const sol = await svc.registrarBaixa({
      solicitacaoId: Number(req.params.id),
      quantidade:    Number(quantidade),
      observacao,
    });
    res.json(sol);
  } catch (e) { next(e); }
};

// POST /producao/solicitacoes/:id/finalizar
const finalizarSolicitacao = async (req, res, next) => {
  try {
    const sol = await svc.finalizarSolicitacao({ solicitacaoId: Number(req.params.id) });
    res.json(sol);
  } catch (e) { next(e); }
};

// DELETE /producao/historico/:id
const excluirHistorico = async (req, res, next) => {
  try {
    await svc.excluirHistorico(Number(req.params.id));
    res.status(204).send();
  } catch (e) { next(e); }
};

module.exports = {
  listarMateriais,
  listarCategorias,
  listarSolicitacoes,
  listarHistorico,
  buscarSolicitacao,
  criarSolicitacao,
  registrarBaixa,
  finalizarSolicitacao,
  excluirHistorico,
};