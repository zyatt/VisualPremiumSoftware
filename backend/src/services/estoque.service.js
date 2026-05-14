const prisma = require('../utils/prisma');

// Lista todas as relações OS com contagem de movimentações
async function listarRelacoesOS(busca) {
  const where = {};
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        include: {
          material: { select: { id: true, nome: true, unidade: true } },
          ordemCompra: { select: { id: true } },
        },
        orderBy: { criadoEm: 'desc' },
      },
    },
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarRelacaoOS(numeroOS) {
  return prisma.relacaoOS.findUnique({
    where: { numeroOS },
    include: {
      movimentacoes: {
        include: {
          material: { select: { id: true, nome: true, unidade: true, categoria: true } },
          ordemCompra: { select: { id: true } },
        },
        orderBy: { criadoEm: 'desc' },
      },
    },
  });
}

async function registrarMovimentacao({ materialId, tipo, quantidade, numeroOS, precoUnitario, observacao, ordemCompraId }) {
  if (!['ENTRADA', 'SAIDA'].includes(tipo)) throw { status: 400, message: 'Tipo deve ser ENTRADA ou SAIDA' };
  if (!materialId || !quantidade || !numeroOS) throw { status: 400, message: 'materialId, quantidade e numeroOS são obrigatórios' };

  // Garante que a relação OS existe (cria se necessário)
  const relacaoOS = await prisma.relacaoOS.upsert({
    where: { numeroOS: String(numeroOS) },
    create: { numeroOS: String(numeroOS) },
    update: { atualizadoEm: new Date() },
  });

  // Verifica material
  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };
  if (!material.ativo) throw { status: 400, message: 'Material inativo' };

  // Para SAÍDA, verifica se há estoque suficiente
  if (tipo === 'SAIDA' && Number(material.quantidade) < Number(quantidade)) {
    throw { status: 400, message: `Estoque insuficiente. Disponível: ${material.quantidade}` };
  }

  // Cria movimentação
  const movimentacao = await prisma.movimentacaoEstoque.create({
    data: {
      materialId,
      tipo,
      quantidade,
      numeroOS:    String(numeroOS),
      relacaoOSId: relacaoOS.id,
      ordemCompraId: ordemCompraId ?? null,
      precoUnitario: precoUnitario ?? null,
      observacao:    observacao ?? null,
    },
    include: { material: true },
  });

  // Atualiza quantidade do material
  const delta = tipo === 'ENTRADA' ? Number(quantidade) : -Number(quantidade);
  const novaQuantidade = Number(material.quantidade) + delta;

  // Recalcula status
  const min = Number(material.estoqueMinimo);
  let status = 'OK';
  if (!material.ativo) status = 'INATIVO';
  else if (novaQuantidade < min) status = 'CRITICO';
  else if (novaQuantidade === min) status = 'LIMITE';

  await prisma.material.update({
    where: { id: materialId },
    data: {
      quantidade: novaQuantidade,
      status,
      estoqueConfirmado: false, // movimentação desconfirma até nova confirmação
    },
  });

  // Se for SAÍDA, cria/atualiza relatório de OS
  if (tipo === 'SAIDA') {
    await prisma.relacaoOS.update({
      where: { id: relacaoOS.id },
      data: { atualizadoEm: new Date() },
    });
  }

  return movimentacao;
}

async function listarMovimentacoesPorMaterial(materialId) {
  return prisma.movimentacaoEstoque.findMany({
    where: { materialId },
    include: {
      relacaoOS:  { select: { numeroOS: true } },
      ordemCompra: { select: { id: true } },
    },
    orderBy: { criadoEm: 'desc' },
  });
}

module.exports = { listarRelacoesOS, buscarRelacaoOS, registrarMovimentacao, listarMovimentacoesPorMaterial };