const prisma = require('../utils/prisma');

async function listar(filtros = {}) {
  const { fornecedorId, dataInicio, dataFim, busca } = filtros;

  const where = { status: 'FINALIZADO' };

  if (fornecedorId) where.fornecedorId = +fornecedorId;

  if (dataInicio || dataFim) {
    where.data = {};
    if (dataInicio) where.data.gte = new Date(dataInicio);
    if (dataFim)    where.data.lte = new Date(dataFim);
  }

  return prisma.ordemCompra.findMany({
    where,
    include: {
      fornecedor: { select: { id: true, nomeFantasia: true, cnpj: true } },
      usuario:    { select: { id: true, nome: true } },
      itens: {
        include: {
          material: { select: { id: true, nome: true, unidade: true, categoria: true } },
        },
      },
      numerosOS: true,
    },
    orderBy: { data: 'desc' },
  });
}

async function buscarPorId(id) {
  return prisma.ordemCompra.findUnique({
    where: { id, status: 'FINALIZADO' },
    include: {
      fornecedor: true,
      usuario:    { select: { id: true, nome: true } },
      itens: {
        include: { material: true },
      },
      numerosOS: true,
    },
  });
}

module.exports = { listar, buscarPorId };