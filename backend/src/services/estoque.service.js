const prisma = require('../utils/prisma');

/**
 * Normaliza valores de preço: converte 0 para null (ausência de informação)
 */
function _normalizarPreco(valor) {
  if (valor == null) return null;
  const num = Number(valor);
  return num > 0 ? num : null;
}

async function listarRelacoesOS(busca) {
  const where = {};
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        include: {
          material: { select: { id: true, nome: true, unidade: true, identificador: true, medida: true, espessura: true } },
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
          material: { select: { id: true, nome: true, unidade: true, categoria: true, identificador: true, medida: true, espessura: true } },
          ordemCompra: { select: { id: true } },
        },
        orderBy: { criadoEm: 'desc' },
      },
    },
  });
}

async function registrarMovimentacao({ materialId, tipo, quantidade, numeroOS, precoUnitario, precoM2, observacao, ordemCompraId, descricaoItem }) {
  if (!['ENTRADA', 'SAIDA'].includes(tipo)) throw { status: 400, message: 'Tipo deve ser ENTRADA ou SAIDA' };
  if (!materialId || !quantidade || !numeroOS) throw { status: 400, message: 'materialId, quantidade e numeroOS são obrigatórios' };

  const relacaoOS = await prisma.relacaoOS.upsert({
    where: { numeroOS: String(numeroOS) },
    create: { numeroOS: String(numeroOS) },
    update: { atualizadoEm: new Date() },
  });

  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };
  if (!material.ativo) throw { status: 400, message: 'Material inativo' };

  if (tipo === 'SAIDA' && Number(material.quantidade) < Number(quantidade)) {
    throw { status: 400, message: `Estoque insuficiente. Disponível: ${material.quantidade}` };
  }

  // Normaliza os valores de preço: 0 vira null
  const precoUnitarioValor = _normalizarPreco(precoUnitario);
  const precoM2Valor = _normalizarPreco(precoM2);

  const movimentacao = await prisma.movimentacaoEstoque.create({
    data: {
      materialId,
      tipo,
      quantidade,
      numeroOS,
      relacaoOSId: relacaoOS.id,
      ordemCompraId: ordemCompraId ?? null,
      precoUnitario:  precoUnitarioValor,
      precoM2:        precoM2Valor,
      observacao:     observacao     ?? null,
      descricaoItem:  descricaoItem  ?? null,
    },
    include: { material: true },
  });

  const delta = tipo === 'ENTRADA' ? Number(quantidade) : -Number(quantidade);
  const novaQuantidade = Number(material.quantidade) + delta;

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
      estoqueConfirmado: false,
    },
  });

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

async function removerMovimentacao(movimentacaoId) {
  const mov = await prisma.movimentacaoEstoque.findUnique({
    where: { id: movimentacaoId },
    include: { material: true },
  });
  if (!mov) throw { status: 404, message: 'Movimentação não encontrada' };

  // Reverte o saldo: ENTRADA vira -delta, SAIDA vira +delta
  const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);
  const novaQuantidade = Math.max(0, Number(mov.material.quantidade) + delta);

  const min = Number(mov.material.estoqueMinimo);
  let status = 'OK';
  if (!mov.material.ativo)       status = 'INATIVO';
  else if (novaQuantidade < min) status = 'CRITICO';
  else if (novaQuantidade === min) status = 'LIMITE';

  await prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } });

  await prisma.material.update({
    where: { id: mov.materialId },
    data: { quantidade: novaQuantidade, status, estoqueConfirmado: false },
  });

  // Se a RelacaoOS ficou sem movimentações, remove-a automaticamente
  const restantes = await prisma.movimentacaoEstoque.count({
    where: { relacaoOSId: mov.relacaoOSId },
  });
  if (restantes === 0) {
    await prisma.relacaoOS.delete({ where: { id: mov.relacaoOSId } });
  }

  return { ok: true };
}

async function excluirRelacaoOS(numeroOS) {
  const relacao = await prisma.relacaoOS.findUnique({
    where: { numeroOS },
    include: { movimentacoes: { include: { material: true } } },
  });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };

  // Reverte o estoque de cada movimentação
  for (const mov of relacao.movimentacoes) {
    const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);
    const novaQuantidade = Math.max(0, Number(mov.material.quantidade) + delta);

    const min = Number(mov.material.estoqueMinimo);
    let status = 'OK';
    if (!mov.material.ativo)       status = 'INATIVO';
    else if (novaQuantidade < min) status = 'CRITICO';
    else if (novaQuantidade === min) status = 'LIMITE';

    await prisma.material.update({
      where: { id: mov.materialId },
      data: { quantidade: novaQuantidade, status, estoqueConfirmado: false },
    });
  }

  // Cascade: deleta movimentações e a relação
  await prisma.movimentacaoEstoque.deleteMany({ where: { relacaoOSId: relacao.id } });
  await prisma.relacaoOS.delete({ where: { id: relacao.id } });

  return { ok: true };
}

module.exports = {
  listarRelacoesOS,
  buscarRelacaoOS,
  registrarMovimentacao,
  listarMovimentacoesPorMaterial,
  removerMovimentacao,
  excluirRelacaoOS,
};