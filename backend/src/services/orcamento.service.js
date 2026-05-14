const prisma = require('../utils/prisma');

async function listar() {
  return prisma.orcamento.findMany({
    where: { status: 'ABERTO' },
    include: {
      itens: {
        include: {
          material: { select: { id: true, nome: true, unidade: true } },
          fornecedor: { select: { id: true, nomeFantasia: true } },
        },
      },
    },
    orderBy: { criadoEm: 'desc' },
  });
}

async function buscarPorId(id) {
  return prisma.orcamento.findUnique({
    where: { id },
    include: {
      itens: {
        include: {
          material: {
            include: {
              fornecedorMateriais: {
                where: { ativo: true },
                include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
              },
            },
          },
          fornecedor: true,
        },
      },
    },
  });
}

async function criar(titulo) {
  return prisma.orcamento.create({ data: { titulo: titulo || 'Orçamento' } });
}

async function adicionarItem(orcamentoId, materialId, fornecedorId, quantidade, precoUnitario) {
  // Verifica se item já existe → atualiza, senão cria
  const existente = await prisma.orcamentoItem.findFirst({
    where: { orcamentoId, materialId },
  });

  if (existente) {
    return prisma.orcamentoItem.update({
      where: { id: existente.id },
      data: { fornecedorId, quantidade, precoUnitario },
    });
  }

  return prisma.orcamentoItem.create({
    data: { orcamentoId, materialId, fornecedorId, quantidade, precoUnitario },
  });
}

async function removerItem(orcamentoId, itemId) {
  return prisma.orcamentoItem.deleteMany({ where: { id: itemId, orcamentoId } });
}

async function atualizarItem(itemId, data) {
  return prisma.orcamentoItem.update({ where: { id: itemId }, data });
}

async function cancelar(id) {
  return prisma.orcamento.update({ where: { id }, data: { status: 'CANCELADO' } });
}

// Valida mínimo de 3 fornecedores distintos no orçamento
async function validarParaOC(orcamentoId) {
  const itens = await prisma.orcamentoItem.findMany({
    where: { orcamentoId },
    select: { fornecedorId: true },
  });

  const fornecedoresDistintos = new Set(itens.map((i) => i.fornecedorId).filter(Boolean));
  if (fornecedoresDistintos.size < 3) {
    throw { status: 400, message: 'É necessário pelo menos 3 fornecedores distintos para gerar uma OC' };
  }
  return true;
}

module.exports = { listar, buscarPorId, criar, adicionarItem, removerItem, atualizarItem, cancelar, validarParaOC };