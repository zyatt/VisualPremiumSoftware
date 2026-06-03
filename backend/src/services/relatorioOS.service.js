const prisma = require('../utils/prisma');

// ── include reutilizável ──────────────────────────────────────────────────────
const _includeCompleto = {
  movimentacoes: {
    include: {
      material: { select: { id: true, nome: true, unidade: true, categoria: true, identificador: true, medida: true, espessura: true } },
    },
    orderBy: { criadoEm: 'asc' },
  },
};

// ── Listagem de relatórios (OS FECHADAS) ──────────────────────────────────────
async function listar({ busca, materialId, materialNome, materialIdentificador, materialMedida, materialEspessura, dataInicio, dataFim } = {}) {
  const where = { status: 'FECHADA' };

  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  // ── Filtro de período (fechamento = atualizadoEm) ─────────────────────────
  if (dataInicio || dataFim) {
    where.atualizadoEm = {};
    if (dataInicio) where.atualizadoEm.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      where.atualizadoEm.lte = fim;
    }
  }

  // Filtra OS que possuam ao menos uma movimentação cujo material satisfaça
  // todos os critérios informados (AND dentro do some).
  const filtroMaterial = {};
  if (materialId)            filtroMaterial.id            = Number(materialId);
  if (materialNome) {
    const tokens = materialNome.trim().split(/\s+/).filter(Boolean);
    if (tokens.length === 1) {
      filtroMaterial.nome = { contains: tokens[0], mode: 'insensitive' };
    } else {
      filtroMaterial.AND = tokens.map((t) => ({ nome: { contains: t, mode: 'insensitive' } }));
    }
  }
  if (materialIdentificador) filtroMaterial.identificador = { contains: materialIdentificador, mode: 'insensitive' };
  if (materialMedida)        filtroMaterial.medida        = { contains: materialMedida,        mode: 'insensitive' };
  if (materialEspessura)     filtroMaterial.espessura     = { contains: materialEspessura,     mode: 'insensitive' };

  if (Object.keys(filtroMaterial).length > 0) {
    where.movimentacoes = { some: { material: filtroMaterial } };
  }

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        include: {
          material: { select: { id: true, nome: true, unidade: true, categoria: true, identificador: true, medida: true, espessura: true } },
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
        identificador: m.material.identificador ?? null,
        medida:        m.material.medida        ?? null,
        espessura:     m.material.espessura     ?? null,
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