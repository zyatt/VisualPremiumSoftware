const prisma = require('../utils/prisma');

/**
 * Normaliza valores de preço: converte 0 para null (ausência de informação)
 */
function _normalizarPreco(valor) {
  if (valor == null) return null;
  const num = Number(valor);
  return num > 0 ? num : null;
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

function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

async function listar(status) {
  const where = {};
  if (status) where.status = status;
  return prisma.ordemCompra.findMany({
    where,
    include: {
      fornecedor: { select: { id: true, nomeFantasia: true } },
      usuario:    { select: { id: true, nome: true } },
      itens: {
        include: { 
          material: { 
            select: { 
              id: true, 
              nome: true, 
              unidade: true,
              especifico: true,
            } 
          } 
        },
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

  if (ordemData.data !== undefined && ordemData.data !== null) {
    ordemData.data = new Date(ordemData.data);
  }

  if (!ordemData.fornecedorId) {
    throw { status: 400, message: 'Campo obrigatório ausente: fornecedorId' };
  }
  
  ordemData.requisitante = ordemData.requisitante?.trim() || 'Não informado';
  ordemData.formaPagamento = ordemData.formaPagamento ?? null;
  ordemData.prazoPagamento = ordemData.prazoPagamento ?? null;
  ordemData.observacoes    = ordemData.observacoes    ?? null;
  ordemData.empresa        = ordemData.empresa        ?? null;
  ordemData.status         = ordemData.status         ?? 'EM_ANDAMENTO';

  const osArray = _normalizarNumerosOS(numerosOS);

  const valorTotal = (itens || []).reduce((acc, item) => {
    const precoBase = item.usarM2 && Number(item.precoMetroQuadrado) > 0
      ? Number(item.precoMetroQuadrado)
      : Number(item.precoUnitario);
    return acc + Number(item.quantidade) * precoBase;
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
              descricaoItem:      item.descricaoItem?.trim() || null,
              numeroOS:           item.numeroOS,
              quantidade:         item.quantidade,
              precoUnitario:      item.precoUnitario,
              precoMetroQuadrado: item.precoMetroQuadrado ?? null,
              usarM2:             item.usarM2 ?? false,
              precoTotal:         item.usarM2 && Number(item.precoMetroQuadrado) > 0
                ? Number(item.quantidade) * Number(item.precoMetroQuadrado)
                : Number(item.quantidade) * Number(item.precoUnitario),
            })),
          }
        : undefined,
    },
    include: {
      itens:     { 
        include: { 
          material: {
            select: {
              id: true,
              nome: true,
              unidade: true,
              especifico: true,
            }
          }
        } 
      },
      numerosOS: true,
      fornecedor: true,
    },
  });
}

async function atualizar(id, data) {
  const { itens, numerosOS, ...ordemData } = data;

  const ordem = await prisma.ordemCompra.update({ where: { id }, data: ordemData });

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

  if (Array.isArray(itens)) {
    await prisma.ordemCompraItem.deleteMany({ where: { ordemCompraId: id } });
    if (itens.length){
      await prisma.ordemCompraItem.createMany({
        data: itens.map((item) => ({
          ordemCompraId: id,
          materialId:         item.materialId,
          descricaoItem:      item.descricaoItem?.trim() || null,
          numeroOS:           item.numeroOS,
          quantidade:         item.quantidade,
          precoUnitario:      item.precoUnitario,
          precoMetroQuadrado: item.precoMetroQuadrado ?? null,
          usarM2:             item.usarM2 ?? false,
          precoTotal:         item.usarM2 && Number(item.precoMetroQuadrado) > 0
            ? Number(item.quantidade) * Number(item.precoMetroQuadrado)
            : Number(item.quantidade) * Number(item.precoUnitario),
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
    include: { 
      material: {
        select: {
          id: true,
          nome: true,
          unidade: true,
          especifico: true,
        }
      }
    },
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
    include: {
      itens: {
        include: {
          material: true,
        }
      },
      fornecedor: { select: { id: true, nomeFantasia: true } },
    },
  });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status !== 'EM_ANDAMENTO') throw { status: 400, message: 'Apenas ordens em andamento podem ser finalizadas' };

  if (!ordem.itens || ordem.itens.length === 0) {
    throw { status: 400, message: 'Não é possível finalizar uma OC sem itens' };
  }

  const itensSemOS = ordem.itens.filter(item => !item.numeroOS || item.numeroOS.trim() === '');
  if (itensSemOS.length > 0) {
    throw { 
      status: 400, 
      message: `${itensSemOS.length} ${itensSemOS.length === 1 ? 'item não possui' : 'itens não possuem'} número de OS atribuído. Edite a ordem e atribua uma OS para todos os itens antes de finalizar.` 
    };
  }

  const finalizada = await prisma.ordemCompra.update({
    where: { id },
    data: { status: 'FINALIZADO' },
  });

  for (const item of ordem.itens) {
    const numeroOSLimpo = item.numeroOS.trim();
    if (!numeroOSLimpo) {
      throw { status: 400, message: `Item "${item.material?.nome || item.materialId}" sem número de OS` };
    }

    await prisma.relacaoOS.upsert({
      where:  { numeroOS: numeroOSLimpo },
      create: { numeroOS: numeroOSLimpo },
      update: {},
    });
    const relacaoOS = await prisma.relacaoOS.findUnique({ where: { numeroOS: numeroOSLimpo } });

    // Normaliza preços: 0 vira null
    const precoUnitarioValor = _normalizarPreco(item.precoUnitario);
    const precoM2Valor = _normalizarPreco(item.precoMetroQuadrado);

    await prisma.movimentacaoEstoque.create({
      data: {
        materialId:    item.materialId,
        tipo:          'ENTRADA',
        quantidade:    item.quantidade,
        numeroOS:      numeroOSLimpo,
        relacaoOSId:   relacaoOS.id,
        ordemCompraId: id,
        precoUnitario: precoUnitarioValor,
        precoM2:       precoM2Valor,
        descricaoItem: item.descricaoItem ?? null,
        observacao:    `Entrada via OC #${id}`,
      },
    });

    const material = await prisma.material.findUnique({ where: { id: item.materialId } });
    const novaQuantidade = Number(material.quantidade) + Number(item.quantidade);
    const status = _calcularStatus(novaQuantidade, material.estoqueMinimo, material.ativo);

    // Atualiza custos apenas se houver valores válidos (> 0)
    const novoUltimoValorPago = precoUnitarioValor ?? material.ultimoValorPago;
    const novoUltimoValorPagoM2 = precoM2Valor ?? material.ultimoValorPagoM2;

    await prisma.material.update({
      where: { id: item.materialId },
      data: {
        quantidade:        novaQuantidade,
        ultimoValorPago:   novoUltimoValorPago,
        ultimoValorPagoM2: novoUltimoValorPagoM2,
        status,
      },
    });

    // Cria histórico apenas se houver pelo menos um preço válido
    await prisma.historicoPrecoMaterial.create({
      data: {
        materialId:    item.materialId,
        ordemCompraId: id,
        fornecedorId:  ordem.fornecedorId,
        precoUnitario: precoUnitarioValor,
        precoM2:       precoM2Valor,
        quantidade:    item.quantidade,
        usarM2:        item.usarM2 ?? false,
      },
    });
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

  for (const item of ordem.itens) {
    const material = await prisma.material.findUnique({ where: { id: item.materialId } });
    if (!material) continue;

    const relacaoOS = await prisma.relacaoOS.upsert({
      where:  { numeroOS: item.numeroOS },
      create: { numeroOS: item.numeroOS },
      update: {},
    });

    // Normaliza preços: 0 vira null
    const precoUnitarioValor = _normalizarPreco(item.precoUnitario);
    const precoM2Valor = _normalizarPreco(item.precoMetroQuadrado);

    await prisma.movimentacaoEstoque.create({
      data: {
        materialId:    item.materialId,
        tipo:          'SAIDA',
        quantidade:    item.quantidade,
        numeroOS:      item.numeroOS,
        relacaoOSId:   relacaoOS.id,
        ordemCompraId: id,
        precoUnitario: precoUnitarioValor,
        precoM2:       precoM2Valor,
        descricaoItem: item.descricaoItem ?? null,
        observacao:    `Estorno via reversão OC #${id}`,
      },
    });

    const novaQuantidade = Math.max(0, Number(material.quantidade) - Number(item.quantidade));
    const status = _calcularStatus(novaQuantidade, material.estoqueMinimo, material.ativo);

    await prisma.historicoPrecoMaterial.deleteMany({
      where: { materialId: item.materialId, ordemCompraId: id },
    });

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

  const {
    fornecedorId,
    requisitante,
    formaPagamento,
    prazoPagamento,
    observacoes,
    empresa,
    data,
    numerosOS,
  } = dadosExtras;

  if (!fornecedorId) {
    throw { status: 400, message: 'Campo obrigatório ausente: fornecedorId' };
  }

  const osNormalizado = _normalizarNumerosOS(numerosOS);
  const numeroOSPadrao = dadosExtras.numeroOS
    || osNormalizado[0]
    || 'OS-GERAL';

  const itens = orcamento.itens.map((item) => ({
    materialId:         item.materialId,
    descricaoItem:      null,
    numeroOS:           item.numeroOS || numeroOSPadrao,
    quantidade:         item.quantidade,
    precoUnitario:      Number(item.precoUnitario) > 0 ? item.precoUnitario : 0,
    precoMetroQuadrado: null,
    usarM2:             false,
  }));

  return criar({
    fornecedorId:   Number(fornecedorId),
    requisitante:   requisitante?.trim() || 'Não informado',
    formaPagamento: formaPagamento  ?? null,
    prazoPagamento: prazoPagamento  ?? null,
    observacoes:    observacoes     ?? null,
    empresa:        empresa         ?? null,
    data:           data ? new Date(data) : new Date(),
    status:         'EM_ANDAMENTO',
    orcamentoId,
    numerosOS:      osNormalizado,
    itens,
  }, usuarioId);
}

module.exports = { listar, buscarPorId, criar, atualizar, adicionarItem, removerItem, atualizarItem, finalizar, cancelar, reverter, criarDeOrcamento };