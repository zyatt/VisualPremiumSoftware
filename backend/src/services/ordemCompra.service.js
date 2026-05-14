const prisma = require('../utils/prisma');

async function listar(status) {
  const where = {};
  if (status) where.status = status;
  return prisma.ordemCompra.findMany({
    where,
    include: {
      fornecedor: { select: { id: true, nomeFantasia: true } },
      usuario:    { select: { id: true, nome: true } },
      itens: {
        include: { material: { select: { id: true, nome: true, unidade: true } } },
      },
      numerosOS: true,
    },
    orderBy: { criadoEm: 'desc' },
  });
}

async function buscarPorId(id) {
  return prisma.ordemCompra.findUnique({
    where: { id },
    include: {
      fornecedor: true,
      usuario:    { select: { id: true, nome: true } },
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
        },
      },
      numerosOS: true,
      orcamento: { select: { id: true, titulo: true } },
    },
  });
}

async function criar(data, usuarioId) {
  const { itens, numerosOS, ...ordemData } = data;

  // Calcula valor total
  const valorTotal = (itens || []).reduce((acc, item) => {
    return acc + Number(item.quantidade) * Number(item.precoUnitario);
  }, 0);

  return prisma.ordemCompra.create({
    data: {
      ...ordemData,
      usuarioId,
      valorTotal,
      numerosOS: numerosOS?.length
        ? { create: numerosOS.map((n) => ({ numeroOS: String(n) })) }
        : undefined,
      itens: itens?.length
        ? {
            create: itens.map((item) => ({
              materialId:        item.materialId,
              numeroOS:          item.numeroOS,
              quantidade:        item.quantidade,
              precoUnitario:     item.precoUnitario,
              precoMetroQuadrado: item.precoMetroQuadrado ?? null,
              precoTotal:        Number(item.quantidade) * Number(item.precoUnitario),
            })),
          }
        : undefined,
    },
    include: {
      itens:     { include: { material: true } },
      numerosOS: true,
      fornecedor: true,
    },
  });
}

async function atualizar(id, data) {
  const { itens, numerosOS, ...ordemData } = data;
  return prisma.ordemCompra.update({ where: { id }, data: ordemData });
}

async function adicionarItem(ordemCompraId, itemData) {
  const precoTotal = Number(itemData.quantidade) * Number(itemData.precoUnitario);
  const item = await prisma.ordemCompraItem.create({
    data: { ...itemData, ordemCompraId, precoTotal },
    include: { material: true },
  });
  await recalcularTotal(ordemCompraId);
  return item;
}

async function removerItem(ordemCompraId, itemId) {
  await prisma.ordemCompraItem.deleteMany({ where: { id: itemId, ordemCompraId } });
  await recalcularTotal(ordemCompraId);
}

async function atualizarItem(itemId, data) {
  const item = await prisma.ordemCompraItem.findUnique({ where: { id: itemId } });
  const quantidade     = data.quantidade     ?? item.quantidade;
  const precoUnitario  = data.precoUnitario  ?? item.precoUnitario;
  const precoTotal     = Number(quantidade) * Number(precoUnitario);
  const updated = await prisma.ordemCompraItem.update({
    where: { id: itemId },
    data: { ...data, precoTotal },
  });
  await recalcularTotal(item.ordemCompraId);
  return updated;
}

async function recalcularTotal(ordemCompraId) {
  const itens = await prisma.ordemCompraItem.findMany({ where: { ordemCompraId } });
  const valorTotal = itens.reduce((acc, i) => acc + Number(i.precoTotal), 0);
  await prisma.ordemCompra.update({ where: { id: ordemCompraId }, data: { valorTotal } });
}

async function finalizar(id) {
  const ordem = await prisma.ordemCompra.findUnique({
    where: { id },
    include: { itens: true },
  });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status !== 'EM_ANDAMENTO') throw { status: 400, message: 'Apenas ordens em andamento podem ser finalizadas' };

  // Finaliza a OC
  const finalizada = await prisma.ordemCompra.update({
    where: { id },
    data: { status: 'FINALIZADO' },
  });

  // Cria entradas de movimentação de estoque para cada item
  for (const item of ordem.itens) {
    // Garante que a RelacaoOS existe
    await prisma.relacaoOS.upsert({
      where: { numeroOS: item.numeroOS },
      create: { numeroOS: item.numeroOS },
      update: {},
    });

    const relacaoOS = await prisma.relacaoOS.findUnique({ where: { numeroOS: item.numeroOS } });

    await prisma.movimentacaoEstoque.create({
      data: {
        materialId:    item.materialId,
        tipo:          'ENTRADA',
        quantidade:    item.quantidade,
        numeroOS:      item.numeroOS,
        relacaoOSId:   relacaoOS.id,
        ordemCompraId: id,
        precoUnitario: item.precoUnitario,
        observacao:    `Entrada via OC #${id}`,
      },
    });

    // Atualiza quantidade e último valor pago do material
    const material = await prisma.material.findUnique({ where: { id: item.materialId } });
    const novaQuantidade = Number(material.quantidade) + Number(item.quantidade);
    const { calcularStatus } = require('./material.service');
    // recalcula status inline para não criar dependência circular
    const q = novaQuantidade;
    const min = Number(material.estoqueMinimo);
    let status = 'OK';
    if (!material.ativo) status = 'INATIVO';
    else if (q < min) status = 'CRITICO';
    else if (q === min) status = 'LIMITE';

    await prisma.material.update({
      where: { id: item.materialId },
      data: {
        quantidade:      novaQuantidade,
        ultimoValorPago: item.precoUnitario,
        status,
      },
    });
  }

  // Marca orçamento de origem como CONVERTIDO se houver
  if (ordem.orcamentoId) {
    await prisma.orcamento.update({
      where: { id: ordem.orcamentoId },
      data: { status: 'CONVERTIDO' },
    });
  }

  return finalizada;
}

async function cancelar(id) {
  const ordem = await prisma.ordemCompra.findUnique({ where: { id } });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status === 'FINALIZADO') throw { status: 400, message: 'Ordem finalizada não pode ser cancelada' };
  return prisma.ordemCompra.update({ where: { id }, data: { status: 'CANCELADO' } });
}

async function criarDeOrcamento(orcamentoId, dadosExtras, usuarioId) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id: orcamentoId },
    include: {
      itens: {
        include: {
          material:   { select: { id: true, nome: true } },
          fornecedor: true,
        },
      },
    },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  const { fornecedorId, requisitante, formaPagamento, prazoPagamento, observacoes, empresa, data, numerosOS } = dadosExtras;

  const itens = orcamento.itens.map((item) => ({
    materialId:    item.materialId,
    numeroOS:      dadosExtras.numeroOS || (numerosOS?.[0]) || 'OS-GERAL',
    quantidade:    item.quantidade,
    precoUnitario: item.precoUnitario || 0,
    precoMetroQuadrado: null,
  }));

  return criar({
    fornecedorId,
    requisitante,
    formaPagamento,
    prazoPagamento,
    observacoes,
    empresa,
    data:       data ? new Date(data) : new Date(),
    orcamentoId,
    numerosOS:  numerosOS || [],
    itens,
  }, usuarioId);
}

module.exports = { listar, buscarPorId, criar, atualizar, adicionarItem, removerItem, atualizarItem, finalizar, cancelar, criarDeOrcamento };