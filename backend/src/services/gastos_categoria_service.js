const prisma = require('../utils/prisma');

/**
 * Retorna o gasto agrupado por categoria a partir das OS FECHADAS.
 *
 * Para cada categoria retorna:
 *  - totalEntrada : soma (precoUnitario ou precoM2) * quantidade  nas ENTRADAS
 *  - totalSaida   : soma (precoUnitario ou precoM2) * quantidade  nas SAIDAS
 *  - qtdEntrada   : quantidade total movimentada nas ENTRADAS
 *  - qtdSaida     : quantidade total movimentada nas SAIDAS
 *  - materiais    : lista de materiais distintos com seus sub-totais
 *
 * Filtros opcionais: dataInicio / dataFim (aplicados sobre criadoEm da movimentação)
 */
async function gastosPorCategoria({ dataInicio, dataFim } = {}) {
  // Monta o where para as movimentações
  const whereMovimentacao = {
    relacaoOS: { status: 'FECHADA' },
  };

  if (dataInicio || dataFim) {
    const filtroData = {};
    if (dataInicio) filtroData.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      filtroData.lte = fim;
    }
    whereMovimentacao.criadoEm = filtroData;
  }

  const movimentacoes = await prisma.movimentacaoEstoque.findMany({
    where: whereMovimentacao,
    include: {
      material: {
        select: {
          id: true,
          nome: true,
          categoria: true,
          unidade: true,
          identificador: true,
          medida: true,
          espessura: true,
        },
      },
    },
    orderBy: { criadoEm: 'asc' },
  });

  // Agrupa por categoria
  const porCategoria = {};

  for (const mov of movimentacoes) {
    const cat = mov.material.categoria || '__SEM_CATEGORIA__';

    if (!porCategoria[cat]) {
      porCategoria[cat] = {
        categoria:    cat === '__SEM_CATEGORIA__' ? null : cat,
        totalEntrada: 0,
        totalSaida:   0,
        qtdEntrada:   0,
        qtdSaida:     0,
        materiais:    {},
      };
    }

    const grupo = porCategoria[cat];
    const matId = mov.material.id;

    if (!grupo.materiais[matId]) {
      grupo.materiais[matId] = {
        id:           matId,
        nome:         mov.material.nome,
        unidade:      mov.material.unidade,
        identificador: mov.material.identificador,
        medida:       mov.material.medida,
        espessura:    mov.material.espessura,
        totalEntrada: 0,
        totalSaida:   0,
        qtdEntrada:   0,
        qtdSaida:     0,
      };
    }

    const matGrupo  = grupo.materiais[matId];
    const pu        = Number(mov.precoUnitario || 0);
    const pm2       = Number(mov.precoM2 || 0);
    const preco     = pu > 0 ? pu : pm2;
    const qtd       = Number(mov.quantidade);
    const subtotal  = preco * qtd;

    if (mov.tipo === 'ENTRADA') {
      grupo.totalEntrada  += subtotal;
      grupo.qtdEntrada    += qtd;
      matGrupo.totalEntrada += subtotal;
      matGrupo.qtdEntrada   += qtd;
    } else {
      grupo.totalSaida  += subtotal;
      grupo.qtdSaida    += qtd;
      matGrupo.totalSaida += subtotal;
      matGrupo.qtdSaida   += qtd;
    }
  }

  // Serializa para array e converte materiais de objeto para array
  return Object.values(porCategoria)
    .map((g) => ({
      ...g,
      materiais: Object.values(g.materiais).sort((a, b) =>
        (b.totalSaida + b.totalEntrada) - (a.totalSaida + a.totalEntrada)
      ),
    }))
    .sort((a, b) =>
      (b.totalSaida + b.totalEntrada) - (a.totalSaida + a.totalEntrada)
    );
}

module.exports = { gastosPorCategoria };

/**
 * Retorna o gasto total (entrada + saída) agrupado por mês para um dado ano.
 * Resultado ordenado de janeiro a dezembro.
 *
 * @param {number} ano  Ano desejado (default: ano corrente)
 */
async function gastosMensais({ ano } = {}) {
  const anoAlvo = Number(ano) || new Date().getFullYear();

  const inicio = new Date(`${anoAlvo}-01-01T00:00:00.000Z`);
  const fim    = new Date(`${anoAlvo}-12-31T23:59:59.999Z`);

  const movimentacoes = await prisma.movimentacaoEstoque.findMany({
    where: {
      relacaoOS: { status: 'FECHADA' },
      criadoEm:  { gte: inicio, lte: fim },
    },
    select: {
      tipo:          true,
      quantidade:    true,
      precoUnitario: true,
      precoM2:       true,
      criadoEm:      true,
    },
    orderBy: { criadoEm: 'asc' },
  });

  // Inicializa todos os 12 meses com zero
  const porMes = {};
  for (let m = 1; m <= 12; m++) {
    const key = `${anoAlvo}-${String(m).padStart(2, '0')}`;
    porMes[key] = { mesAno: key, totalEntrada: 0, totalSaida: 0 };
  }

  for (const mov of movimentacoes) {
    const mes    = mov.criadoEm.getMonth() + 1;
    const key    = `${anoAlvo}-${String(mes).padStart(2, '0')}`;
    const pu     = Number(mov.precoUnitario || 0);
    const pm2    = Number(mov.precoM2 || 0);
    const preco  = pu > 0 ? pu : pm2;
    const sub    = preco * Number(mov.quantidade);

    if (mov.tipo === 'ENTRADA') porMes[key].totalEntrada += sub;
    else                        porMes[key].totalSaida   += sub;
  }

  return Object.values(porMes);
}

module.exports = { gastosPorCategoria, gastosMensais };