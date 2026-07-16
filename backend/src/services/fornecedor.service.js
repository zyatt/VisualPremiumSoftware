const prisma = require('../utils/prisma');

function normalizarTelefone(tel) {
  if (!tel) return null;
  const digits = tel.replace(/\D/g, '');
  if (digits.length !== 10) {
    throw { status: 400, message: `Telefone inválido: use DDD (2 dígitos) + número (8 dígitos), ex: 4233091000` };
  }
  return digits;
}

async function listar(busca, tipo, id) {
  const where = { ativo: true };

  if (busca) {
    where.OR = [
      { nomeFantasia: { contains: busca, mode: 'insensitive' } },
      { nomeVendedor: { contains: busca, mode: 'insensitive' } },
      { cnpj:         { contains: busca, mode: 'insensitive' } },
    ];
  }

  if (tipo) {
    where.tipoFornecedor = tipo;
  }

  if (id) {
    where.id = Number(id);
  }

  return prisma.fornecedor.findMany({
    where,
    include: {
      materiais: {
        where: { ativo: true },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
            },
          },
        },
      },
    },
    orderBy: { nomeFantasia: 'asc' },
  });
}

async function buscarParaVinculo(busca, limite = 50) {
  const where = { ativo: true };

  if (busca && busca.trim()) {
    where.OR = [
      { nomeFantasia: { contains: busca.trim(), mode: 'insensitive' } },
      { nomeVendedor: { contains: busca.trim(), mode: 'insensitive' } },
    ];
  }

  return prisma.fornecedor.findMany({
    where,
    select: {
      id:             true,
      nomeFantasia:   true,
      tipoFornecedor: true,
      nomeVendedor:   true,
    },
    orderBy: { nomeFantasia: 'asc' },
    take: Number(limite),
  });
}

async function buscarPorId(id) {
  return prisma.fornecedor.findUnique({
    where: { id },
    include: {
      materiais: {
        where: { ativo: true },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
            },
          },
        },
      },
    },
  });
}

async function listarPorMaterial(materialId) {
  return prisma.fornecedor.findMany({
    where: {
      ativo: true,
      materiais: { some: { materialId, ativo: true } },
    },
    include: {
      materiais: {
        where: { materialId, ativo: true },
      },
    },
    orderBy: { nomeFantasia: 'asc' },
  });
}

async function criar(data) {
  const { nomeFantasia, tipoFornecedor, telefone, cnpj, razaoSocial, nomeVendedor, imagemUrl } = data;
  if (!nomeFantasia?.trim()) throw { status: 400, message: 'nomeFantasia é obrigatório' };

  return prisma.fornecedor.create({
    data: {
      nomeFantasia: nomeFantasia.trim(),
      tipoFornecedor: tipoFornecedor?.trim() ?? null,
      telefone: normalizarTelefone(telefone),
      cnpj: cnpj?.replace(/\D/g, '') || null,
      razaoSocial: razaoSocial?.trim() ?? null,
      nomeVendedor: nomeVendedor?.trim() ?? null,
      imagemUrl: imagemUrl?.trim() || null,
    },
  });
}

async function atualizar(id, data) {
  data = data || {};

  const atual = await prisma.fornecedor.findUnique({ where: { id } });
  if (!atual) throw { status: 404, message: 'Fornecedor não encontrado' };

  const updateData = {};
  if (data.nomeFantasia  !== undefined) updateData.nomeFantasia  = data.nomeFantasia.trim();
  if (data.tipoFornecedor!== undefined) updateData.tipoFornecedor= data.tipoFornecedor?.trim() ?? null;
  if (data.telefone      !== undefined) updateData.telefone      = normalizarTelefone(data.telefone);
  if (data.cnpj          !== undefined) updateData.cnpj          = data.cnpj?.replace(/\D/g, '') || null;
  if (data.razaoSocial   !== undefined) updateData.razaoSocial   = data.razaoSocial?.trim() ?? null;
  if (data.nomeVendedor  !== undefined) updateData.nomeVendedor  = data.nomeVendedor?.trim() ?? null;
  if (data.imagemUrl     !== undefined) updateData.imagemUrl     = data.imagemUrl?.trim() || null;

  return prisma.fornecedor.update({ where: { id }, data: updateData });
}

async function remover(id) {
  const atual = await prisma.fornecedor.findUnique({ where: { id } });
  if (!atual) throw { status: 404, message: 'Fornecedor não encontrado' };

  return prisma.$transaction([
    prisma.fornecedorMaterial.updateMany({
      where: { fornecedorId: id },
      data: { ativo: false },
    }),
    prisma.orcamentoItem.updateMany({
      where: {
        fornecedorId: id,
        orcamento: {
          status: { in: ['ABERTO', 'AGUARDANDO_APROVACAO'] },
        },
      },
      data: { fornecedorId: null, selecionado: false },
    }),
    prisma.fornecedor.update({
      where: { id },
      data: { ativo: false },
    }),
  ]);
}

function _normalizarPrecoDecimal(valor) {
  if (valor == null || valor === '') return null;
  const str = String(valor).trim();
  const num = Number(str);
  if (isNaN(num)) return null;
  return parseFloat(num.toFixed(6)).toString();
}

async function vincularMaterial(fornecedorId, materialId, preco, precoMetroQuadrado) {
  const precoVal   = _normalizarPrecoDecimal(preco);
  const precoM2Val = _normalizarPrecoDecimal(precoMetroQuadrado);

  return prisma.fornecedorMaterial.upsert({
    where: { fornecedorId_materialId: { fornecedorId, materialId } },
    create: { fornecedorId, materialId, preco: precoVal, precoMetroQuadrado: precoM2Val, ativo: true },
    update: { preco: precoVal, precoMetroQuadrado: precoM2Val, ativo: true },
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

module.exports = {
  listar,
  buscarParaVinculo,
  buscarPorId,
  listarPorMaterial,
  criar,
  atualizar,
  remover,
  vincularMaterial,
  desvincularMaterial,
  atualizarPrecoVinculo,
};