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

  // Garante que `data` é sempre um objeto Date válido
  if (ordemData.data !== undefined && ordemData.data !== null) {
    ordemData.data = new Date(ordemData.data);
  }

  // Normaliza numerosOS: aceita string, array de strings ou array de objetos
  const osArray = _normalizarNumerosOS(numerosOS);

  // Calcula valor total
  const valorTotal = (itens || []).reduce((acc, item) => {
    return acc + Number(item.quantidade) * Number(item.precoUnitario);
  }, 0);

  return prisma.ordemCompra.create({
    data: {
      ...ordemData,
      usuarioId,
      valorTotal,
      numerosOS: osArray.length
        ? { create: osArray.map((n) => ({ numeroOS: String(n) })) }
        : undefined,
      itens: itens?.length
        ? {
            create: itens.map((item) => ({
              materialId:         item.materialId,
              numeroOS:           item.numeroOS,
              quantidade:         item.quantidade,
              precoUnitario:      item.precoUnitario,
              precoMetroQuadrado: item.precoMetroQuadrado ?? null,
              precoTotal:         Number(item.quantidade) * Number(item.precoUnitario),
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

/**
 * Normaliza o campo numerosOS independente do formato recebido:
 * - undefined / null            → []
 * - "OS-001"                   → ["OS-001"]
 * - ["OS-001", "OS-002"]       → ["OS-001", "OS-002"]
 * - [{ numeroOS: "OS-001" }]   → ["OS-001"]
 */
function _normalizarNumerosOS(numerosOS) {
  if (!numerosOS) return [];
  if (typeof numerosOS === 'string') return numerosOS.trim() ? [numerosOS.trim()] : [];
  if (!Array.isArray(numerosOS)) return [];
  return numerosOS
    .map((n) => (typeof n === 'object' && n !== null ? n.numeroOS : n))
    .map((n) => String(n).trim())
    .filter(Boolean);
}

async function atualizar(id, data) {
  const { itens, numerosOS, ...ordemData } = data;

  // Atualiza dados principais
  const ordem = await prisma.ordemCompra.update({ where: { id }, data: ordemData });

  // Atualiza numerosOS se foram enviados
  if (Array.isArray(numerosOS)) {
    const osArray = _normalizarNumerosOS(numerosOS);
    await prisma.ordemCompra.update({
      where: { id },
      data: {
        numerosOS: {
          deleteMany: {},
          ...(osArray.length ? { create: osArray.map((n) => ({ numeroOS: String(n) })) } : {}),
        },
      },
    });
  }

  // Atualiza itens se foram enviados: remove todos e recria
  if (Array.isArray(itens)) {
    await prisma.ordemCompraItem.deleteMany({ where: { ordemCompraId: id } });
    if (itens.length) {
      await prisma.ordemCompraItem.createMany({
        data: itens.map((item) => ({
          ordemCompraId: id,
          materialId:         item.materialId,
          numeroOS:           item.numeroOS,
          quantidade:         item.quantidade,
          precoUnitario:      item.precoUnitario,
          precoMetroQuadrado: item.precoMetroQuadrado ?? null,
          precoTotal:         Number(item.quantidade) * Number(item.precoUnitario),
        })),
      });
    }
    await recalcularTotal(id);
  }

  return ordem;
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

function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

async function finalizar(id) {
  const ordem = await prisma.ordemCompra.findUnique({
    where: { id },
    include: {
      itens:     true,
      fornecedor: { select: { id: true, nomeFantasia: true } },
    },
  });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status !== 'EM_ANDAMENTO') throw { status: 400, message: 'Apenas ordens em andamento podem ser finalizadas' };

  const finalizada = await prisma.ordemCompra.update({
    where: { id },
    data: { status: 'FINALIZADO' },
  });

  for (const item of ordem.itens) {
    await prisma.relacaoOS.upsert({
      where:  { numeroOS: item.numeroOS },
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

    const material = await prisma.material.findUnique({ where: { id: item.materialId } });
    const novaQuantidade = Number(material.quantidade) + Number(item.quantidade);
    const status = _calcularStatus(novaQuantidade, material.estoqueMinimo, material.ativo);

    const novoUltimoValorPago   = Number(item.precoUnitario) > 0
      ? item.precoUnitario
      : material.ultimoValorPago;

    const novoUltimoValorPagoM2 = item.precoMetroQuadrado != null && Number(item.precoMetroQuadrado) > 0
      ? item.precoMetroQuadrado
      : material.ultimoValorPagoM2;

    await prisma.material.update({
      where: { id: item.materialId },
      data: {
        quantidade:        novaQuantidade,
        ultimoValorPago:   novoUltimoValorPago,
        ultimoValorPagoM2: novoUltimoValorPagoM2,
        status,
      },
    });

    if (Number(item.precoUnitario) > 0) {
      await prisma.historicoPrecoMaterial.create({
        data: {
          materialId:    item.materialId,
          ordemCompraId: id,
          fornecedorId:  ordem.fornecedorId,
          precoUnitario: item.precoUnitario,
          precoM2:       item.precoMetroQuadrado ?? null,
          quantidade:    item.quantidade,
        },
      });
    }
  }

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

async function reverter(id) {
  const ordem = await prisma.ordemCompra.findUnique({
    where: { id },
    include: { itens: true },
  });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status !== 'FINALIZADO') throw { status: 400, message: 'Apenas ordens finalizadas podem ser revertidas' };

  // Desfaz cada item: cria movimentação de SAÍDA e subtrai do estoque
  for (const item of ordem.itens) {
    const material = await prisma.material.findUnique({ where: { id: item.materialId } });
    if (!material) continue;

    const relacaoOS = await prisma.relacaoOS.upsert({
      where:  { numeroOS: item.numeroOS },
      create: { numeroOS: item.numeroOS },
      update: {},
    });

    await prisma.movimentacaoEstoque.create({
      data: {
        materialId:    item.materialId,
        tipo:          'SAIDA',
        quantidade:    item.quantidade,
        numeroOS:      item.numeroOS,
        relacaoOSId:   relacaoOS.id,
        ordemCompraId: id,
        precoUnitario: item.precoUnitario,
        observacao:    `Estorno via reversão OC #${id}`,
      },
    });

    const novaQuantidade = Math.max(0, Number(material.quantidade) - Number(item.quantidade));
    const status = _calcularStatus(novaQuantidade, material.estoqueMinimo, material.ativo);

    // Remove registro do histórico de preço criado pela finalização
    await prisma.historicoPrecoMaterial.deleteMany({
      where: { materialId: item.materialId, ordemCompraId: id },
    });

    // Restaura ultimoValorPago / ultimoValorPagoM2 para o registro mais
    // recente do histórico que ainda reste (após a deleção acima).
    // Se não houver histórico anterior, zera os campos.
    const historicoAnterior = await prisma.historicoPrecoMaterial.findFirst({
      where: { materialId: item.materialId },
      orderBy: { criadoEm: 'desc' },
    });

    await prisma.material.update({
      where: { id: item.materialId },
      data: {
        quantidade:        novaQuantidade,
        status,
        ultimoValorPago:   historicoAnterior?.precoUnitario ?? null,
        ultimoValorPagoM2: historicoAnterior?.precoM2       ?? null,
      },
    });
  }

  // Se havia orçamento vinculado, reverte seu status
  if (ordem.orcamentoId) {
    await prisma.orcamento.update({
      where: { id: ordem.orcamentoId },
      data: { status: 'PENDENTE' },
    });
  }

  return prisma.ordemCompra.update({
    where: { id },
    data: { status: 'EM_ANDAMENTO' },
  });
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
    materialId:         item.materialId,
    numeroOS:           dadosExtras.numeroOS || (numerosOS?.[0]) || 'OS-GERAL',
    quantidade:         item.quantidade,
    precoUnitario:      item.precoUnitario || 0,
    precoMetroQuadrado: null,
  }));

  return criar({
    fornecedorId,
    requisitante,
    formaPagamento,
    prazoPagamento,
    observacoes,
    empresa,
    data:      data ? new Date(data) : new Date(),
    orcamentoId,
    numerosOS: numerosOS || [],
    itens,
  }, usuarioId);
}

module.exports = { listar, buscarPorId, criar, atualizar, adicionarItem, removerItem, atualizarItem, finalizar, cancelar, reverter, criarDeOrcamento };