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

  // ── Filtro de período ─────────────────────────────────────────────────────
  // filtroData é extraído para o escopo da função pois é reutilizado tanto no
  // where (para selecionar quais OS aparecem) quanto no include (para que as
  // movimentações retornadas por OS respeitem o mesmo período — garantindo que
  // o total calculado no Flutter bata com o total de Gastos por Categoria).
  let filtroData = null;
  if (dataInicio || dataFim) {
    filtroData = {};
    if (dataInicio) filtroData.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      filtroData.lte = fim;
    }
    // Filtra OS que possuam ao menos uma movimentação criada no período
    where.movimentacoes = where.movimentacoes
      ? { some: { ...where.movimentacoes.some, criadoEm: filtroData } }
      : { some: { criadoEm: filtroData } };
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

  // Monta o where das movimentações no include:
  // - Se há filtro de data E de material, aplica ambos
  // - Se há só data, filtra por data
  // - Se há só material, filtra por material
  // Isso garante que as movimentações retornadas por cada OS coincidam
  // exatamente com os dados usados no cálculo de Gastos por Categoria.
  let whereMovimentacoesInclude = undefined;
  const temData     = filtroData !== null;
  const temMaterial = Object.keys(filtroMaterial).length > 0;

  if (temData && temMaterial) {
    whereMovimentacoesInclude = { criadoEm: filtroData, material: filtroMaterial };
  } else if (temData) {
    whereMovimentacoesInclude = { criadoEm: filtroData };
  } else if (temMaterial) {
    whereMovimentacoesInclude = { material: filtroMaterial };
  }

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        where: whereMovimentacoesInclude,
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

  const saidas   = relacao.movimentacoes.filter((m) => m.tipo === 'SAIDA');
  const entradas = relacao.movimentacoes.filter((m) => m.tipo === 'ENTRADA');

  const _precoMov = (m) => {
    const precoUnit = Number(m.precoUnitario || 0);
    const precoM2   = Number(m.precoM2       || 0);
    return precoUnit > 0 ? precoUnit : precoM2;
  };

  // ── Total líquido: saídas - entradas, agrupado por materialId ──────────────
  // Processa as movimentações em ordem cronológica para garantir que apenas
  // entradas que ocorreram APÓS a primeira saída do material sejam contadas
  // como devoluções (redutoras de custo). Entradas anteriores à primeira saída
  // são ignoradas no cálculo — eram movimentações independentes de estoque.
  const porMaterial = new Map(); // materialId → { preco, qtdSaida, qtdEntrada }

  // Ordena todas as movimentações por criadoEm (mais antiga primeiro)
  const todasOrdenadas = [...relacao.movimentacoes].sort(
    (a, b) => new Date(a.criadoEm) - new Date(b.criadoEm)
  );

  for (const m of todasOrdenadas) {
    const id = m.materialId;

    if (m.tipo === 'SAIDA') {
      if (!porMaterial.has(id)) {
        porMaterial.set(id, { preco: _precoMov(m), qtdSaida: 0, qtdEntrada: 0 });
      }
      const entry = porMaterial.get(id);
      // Caso haja múltiplas saídas com preços diferentes, usa o maior preço
      if (_precoMov(m) > entry.preco) entry.preco = _precoMov(m);
      entry.qtdSaida += Number(m.quantidade);

    } else if (m.tipo === 'ENTRADA') {
      // Entradas via OC são reposição de estoque, não devoluções — ignorar.
      const isEntradaOC =
        (m.observacao   && m.observacao.includes('via OC')) ||
        (m.descricaoItem && m.descricaoItem.includes('via OC'));
      if (isEntradaOC) continue;

      // Só conta como devolução se o material já teve ao menos uma saída nessa OS
      if (porMaterial.has(id)) {
        porMaterial.get(id).qtdEntrada += Number(m.quantidade);
      }
    }
  }

  const totalGeral = Array.from(porMaterial.values()).reduce((acc, { preco, qtdSaida, qtdEntrada }) => {
    const qtdLiquida = Math.max(0, qtdSaida - qtdEntrada);
    return acc + preco * qtdLiquida;
  }, 0);

  const _mapItem = (m) => {
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
  };

  // Data representativa = criadoEm da movimentação mais antiga (criação real da OS)
  const todasMovs = [...relacao.movimentacoes];
  const primeiraMovimentacaoEm = todasMovs.length > 0
    ? todasMovs.reduce((a, b) => new Date(a.criadoEm) < new Date(b.criadoEm) ? a : b).criadoEm
    : relacao.criadoEm;

  return {
    numeroOS:              relacao.numeroOS,
    descricao:             relacao.descricao,
    status:                relacao.status,
    criadoEm:              primeiraMovimentacaoEm,
    fechadaEm:             relacao.atualizadoEm,
    geradoEm:              new Date(),
    itens:                 saidas.map(_mapItem),
    entradas:              entradas.map(_mapItem),
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