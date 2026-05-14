const prisma = require('../utils/prisma');

// Normaliza telefone: remove tudo que não é dígito, valida DDD(2) + número(8) = 10 dígitos
function normalizarTelefone(tel) {
  if (!tel) return null;
  const digits = tel.replace(/\D/g, '');
  if (digits.length !== 10) {
    throw { status: 400, message: `Telefone inválido: use DDD (2 dígitos) + número (8 dígitos), ex: 4233091000` };
  }
  return digits;
}

async function listar(busca) {
  const where = { ativo: true };
  if (busca) {
    where.OR = [
      { nomeFantasia: { contains: busca, mode: 'insensitive' } },
      { nomeVendedor: { contains: busca, mode: 'insensitive' } },
    ];
  }
  return prisma.fornecedor.findMany({
    where,
    include: {
      materiais: {
        where: { ativo: true },
        include: { material: { select: { id: true, nome: true } } },
      },
    },
    orderBy: { nomeFantasia: 'asc' },
  });
}

async function buscarPorId(id) {
  return prisma.fornecedor.findUnique({
    where: { id },
    include: {
      materiais: {
        include: { material: true },
      },
    },
  });
}

async function criar(data) {
  data.telefone = normalizarTelefone(data.telefone);
  return prisma.fornecedor.create({ data });
}

async function atualizar(id, data) {
  if (data.telefone) data.telefone = normalizarTelefone(data.telefone);
  return prisma.fornecedor.update({ where: { id }, data });
}

async function remover(id) {
  return prisma.fornecedor.update({ where: { id }, data: { ativo: false } });
}

// Vincula um material ao fornecedor com preço
async function vincularMaterial(fornecedorId, materialId, preco, precoMetroQuadrado, prazoEntrega) {
  return prisma.fornecedorMaterial.upsert({
    where: { fornecedorId_materialId: { fornecedorId, materialId } },
    create: { fornecedorId, materialId, preco, precoMetroQuadrado, prazoEntrega, ativo: true },
    update: { preco, precoMetroQuadrado, prazoEntrega, ativo: true },
  });
}

async function desvincularMaterial(fornecedorId, materialId) {
  return prisma.fornecedorMaterial.update({
    where: { fornecedorId_materialId: { fornecedorId, materialId } },
    data: { ativo: false },
  });
}

async function atualizarPrecoVinculo(fornecedorId, materialId, data) {
  return prisma.fornecedorMaterial.update({
    where: { fornecedorId_materialId: { fornecedorId, materialId } },
    data,
  });
}

module.exports = { listar, buscarPorId, criar, atualizar, remover, vincularMaterial, desvincularMaterial, atualizarPrecoVinculo };