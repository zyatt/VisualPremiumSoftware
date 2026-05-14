const prisma = require('../utils/prisma');

// Lista todas as relações OS que têm saídas (para o grid de cards)
async function listar(busca) {
  const where = {
    movimentacoes: { some: { tipo: 'SAIDA' } },
  };
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        where: { tipo: 'SAIDA' },
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
    include: {
      movimentacoes: {
        include: {
          material: { select: { id: true, nome: true, unidade: true, categoria: true } },
        },
        orderBy: { criadoEm: 'asc' },
      },
    },
  });
}

// Monta dados estruturados para o PDF
async function dadosParaPDF(numeroOS) {
  const relacao = await buscarPorNumeroOS(numeroOS);
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };

  const saidas = relacao.movimentacoes.filter((m) => m.tipo === 'SAIDA');

  const totalGeral = saidas.reduce((acc, m) => {
    const preco = Number(m.precoUnitario || 0);
    const qtd   = Number(m.quantidade);
    return acc + preco * qtd;
  }, 0);

  return {
    numeroOS: relacao.numeroOS,
    descricao: relacao.descricao,
    geradoEm: new Date(),
    itens: saidas.map((m) => ({
      material:     m.material.nome,
      unidade:      m.material.unidade,
      categoria:    m.material.categoria,
      quantidade:   Number(m.quantidade),
      precoUnitario: Number(m.precoUnitario || 0),
      total:        Number(m.quantidade) * Number(m.precoUnitario || 0),
      data:         m.criadoEm,
      observacao:   m.observacao,
    })),
    totalGeral,
  };
}

module.exports = { listar, buscarPorNumeroOS, dadosParaPDF };