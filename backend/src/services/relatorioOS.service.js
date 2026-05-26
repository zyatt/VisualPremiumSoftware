const prisma = require('../utils/prisma');

// ── include reutilizável ──────────────────────────────────────────────────────
const _includeCompleto = {
  movimentacoes: {
    include: {
      material: { select: { id: true, nome: true, unidade: true, categoria: true } },
    },
    orderBy: { criadoEm: 'asc' },
  },
};

// ── Listagem de relatórios (OS FECHADAS) ──────────────────────────────────────
async function listar(busca) {
  const where = { status: 'FECHADA' };
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        include: {
          material: { select: { id: true, nome: true, unidade: true, categoria: true } },
        },
        orderBy: { criadoEm: 'desc' },
      },
    },
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarPorNumeroOS(numeroOS) {
  return prisma.relacaoOS.findUnique({
    where: { numeroOS },
    include: _includeCompleto,
  });
}

// ── Fechar OS: muda status para FECHADA ───────────────────────────────────────
async function fecharOS(numeroOS) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Esta OS já está fechada' };
  }

  return prisma.relacaoOS.update({
    where:  { numeroOS },
    data:   { status: 'FECHADA' },
    include: _includeCompleto,
  });
}

// ── Dados para PDF ────────────────────────────────────────────────────────────
async function dadosParaPDF(numeroOS) {
  const relacao = await buscarPorNumeroOS(numeroOS);
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };

  const saidas = relacao.movimentacoes.filter((m) => m.tipo === 'SAIDA');

  const totalGeral = saidas.reduce((acc, m) => {
    const precoUnit = Number(m.precoUnitario || 0);
    const precoM2   = Number(m.precoM2       || 0);
    const preco     = precoUnit > 0 ? precoUnit : precoM2;
    const qtd       = Number(m.quantidade);
    return acc + preco * qtd;
  }, 0);

  return {
    numeroOS:  relacao.numeroOS,
    descricao: relacao.descricao,
    status:    relacao.status,
    fechadaEm: relacao.atualizadoEm,
    geradoEm:  new Date(),
    itens: saidas.map((m) => {
      const precoUnit = Number(m.precoUnitario || 0);
      const precoM2v  = Number(m.precoM2       || 0);
      const usarM2    = precoUnit === 0 && precoM2v > 0;
      const preco     = usarM2 ? precoM2v : precoUnit;
      return {
        material:      m.material.nome,
        unidade:       m.material.unidade,
        categoria:     m.material.categoria,
        quantidade:    Number(m.quantidade),
        precoUnitario: preco,
        usarM2,
        total:         Number(m.quantidade) * preco,
        data:          m.criadoEm,
        observacao:    m.observacao,
      };
    }),
    totalGeral,
  };
}

// ── Reverter OS: muda status de FECHADA para EM_ANDAMENTO ────────────────────
async function reverterOS(numeroOS) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status !== 'FECHADA') {
    throw { status: 400, message: 'Esta OS não está fechada' };
  }

  return prisma.relacaoOS.update({
    where:   { numeroOS },
    data:    { status: 'EM_ANDAMENTO' },
    include: _includeCompleto,
  });
}

module.exports = { listar, buscarPorNumeroOS, fecharOS, reverterOS, dadosParaPDF };