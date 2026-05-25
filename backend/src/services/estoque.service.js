const prisma = require('../utils/prisma');

// ── include reutilizável ──────────────────────────────────────────────────────
const _includeMovimentacoes = {
  movimentacoes: {
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true,
          identificador: true, medida: true, espessura: true,
        },
      },
    },
    orderBy: { criadoEm: 'desc' },
  },
};

// ── Controle de Estoque: apenas OS EM_ANDAMENTO ───────────────────────────────
async function listarEmAndamento(busca) {
  const where = { status: 'EM_ANDAMENTO' };
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: _includeMovimentacoes,
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarPorNumeroOS(numeroOS) {
  return prisma.relacaoOS.findUnique({
    where: { numeroOS },
    include: _includeMovimentacoes,
  });
}

// ── Registrar movimentação ────────────────────────────────────────────────────
async function registrarMovimentacao({
  materialId, tipo, quantidade, numeroOS,
  precoUnitario, precoM2, observacao, ordemCompraId, descricaoItem,
}) {
  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };

  // Verifica se OS não está fechada
  const relacaoExistente = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (relacaoExistente?.status === 'FECHADA') {
    throw { status: 400, message: `A OS ${numeroOS} está fechada e não aceita novas movimentações` };
  }

  if (tipo === 'SAIDA') {
    const saldo = Number(material.quantidade);
    if (saldo < quantidade) {
      throw {
        status: 400,
        message: `Estoque insuficiente: disponível ${saldo} ${material.unidade ?? ''}`.trim(),
      };
    }
  }

  const delta = tipo === 'ENTRADA' ? quantidade : -quantidade;

  // Upsert da RelacaoOS (cria com EM_ANDAMENTO se não existir)
  const relacao = await prisma.relacaoOS.upsert({
    where:  { numeroOS },
    create: { numeroOS, status: 'EM_ANDAMENTO' },
    update: {},
  });

  const [movimentacao] = await prisma.$transaction([
    prisma.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo,
        quantidade,
        numeroOS,
        relacaoOSId:   relacao.id,
        precoUnitario: precoUnitario ?? null,
        precoM2:       precoM2 ?? null,
        observacao:    observacao ?? null,
        ordemCompraId: ordemCompraId ?? null,
        descricaoItem: descricaoItem ?? null,
      },
    }),
    prisma.material.update({
      where: { id: materialId },
      data:  { quantidade: { increment: delta } },
    }),
  ]);

  // Recalcula e atualiza status do material
  const atualizado = await prisma.material.findUnique({ where: { id: materialId } });
  const novoStatus = _calcularStatus(atualizado.quantidade, atualizado.estoqueMinimo, atualizado.ativo);
  await prisma.material.update({ where: { id: materialId }, data: { status: novoStatus } });

  return movimentacao;
}

// ── Remover movimentação ──────────────────────────────────────────────────────
async function removerMovimentacao(movimentacaoId) {
  const mov = await prisma.movimentacaoEstoque.findUnique({ where: { id: movimentacaoId } });
  if (!mov) throw { status: 404, message: 'Movimentação não encontrada' };

  // Verifica se OS não está fechada
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS: mov.numeroOS } });
  if (relacao?.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível remover movimentações de uma OS fechada' };
  }

  // Reverte o delta no material
  const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

  await prisma.$transaction([
    prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } }),
    prisma.material.update({
      where: { id: mov.materialId },
      data:  { quantidade: { increment: delta } },
    }),
  ]);

  // Recalcula status do material
  const mat = await prisma.material.findUnique({ where: { id: mov.materialId } });
  const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
  await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });

  // Se a RelacaoOS ficou sem movimentações, exclui ela
  const count = await prisma.movimentacaoEstoque.count({ where: { relacaoOSId: relacao.id } });
  if (count === 0) {
    await prisma.relacaoOS.delete({ where: { id: relacao.id } });
    return { relacaoExcluida: true };
  }

  return { relacaoExcluida: false };
}

// ── Excluir RelacaoOS inteira ─────────────────────────────────────────────────
async function excluirRelacaoOS(numeroOS) {
  const relacao = await prisma.relacaoOS.findUnique({
    where:   { numeroOS },
    include: { movimentacoes: true },
  });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível excluir uma OS fechada' };
  }

  // Reverte todas as movimentações no estoque
  for (const mov of relacao.movimentacoes) {
    const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);
    await prisma.material.update({
      where: { id: mov.materialId },
      data:  { quantidade: { increment: delta } },
    });
    const mat = await prisma.material.findUnique({ where: { id: mov.materialId } });
    const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
    await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
  }

  await prisma.movimentacaoEstoque.deleteMany({ where: { relacaoOSId: relacao.id } });
  await prisma.relacaoOS.delete({ where: { id: relacao.id } });
}

// ── Fechar OS ─────────────────────────────────────────────────────────────────
async function fecharOS(numeroOS) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Esta OS já está fechada' };
  }

  return prisma.relacaoOS.update({
    where:   { numeroOS },
    data:    { status: 'FECHADA' },
    include: _includeMovimentacoes,
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q   = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

module.exports = {
  listarEmAndamento,
  buscarPorNumeroOS,
  registrarMovimentacao,
  removerMovimentacao,
  excluirRelacaoOS,
  fecharOS,
};