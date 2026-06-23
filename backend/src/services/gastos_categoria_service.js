const prisma = require('../utils/prisma');

// ═════════════════════════════════════════════════════════════════════════════
// SEÇÃO 1 — VALOR ATUAL EM ESTOQUE
// Multiplica quantidade atual de cada material pelo custo da última compra.
// Agrupa por categoria e retorna totais.
// ═════════════════════════════════════════════════════════════════════════════

async function valorEmEstoque() {
  const materiais = await prisma.material.findMany({
    where: { ativo: true },
    select: {
      id:                true,
      nome:              true,
      categoria:         true,
      unidade:           true,
      identificador:     true,
      medida:            true,
      espessura:         true,
      quantidade:        true,
      estoqueMinimo:     true,
      status:            true,
      ultimoValorPago:   true,
      ultimoValorPagoM2: true,
      largura:           true,
      comprimento:       true,
    },
    orderBy: [{ categoria: 'asc' }, { nome: 'asc' }],
  });

  const porCategoria = {};

  for (const mat of materiais) {
    const cat = mat.categoria || '__SEM_CATEGORIA__';

    if (!porCategoria[cat]) {
      porCategoria[cat] = {
        categoria:    cat === '__SEM_CATEGORIA__' ? null : cat,
        totalValor:   0,
        qtdMateriais: 0,
        materiais:    [],
      };
    }

    const qtd      = Number(mat.quantidade);
    const custo    = Number(mat.ultimoValorPago   || 0);
    const custoM2  = Number(mat.ultimoValorPagoM2 || 0);

    // Regra de calculo:
    // 1. Se tem custo unitario -> qtd x custo (sempre preferido, qualquer unidade)
    // 2. Se SÓ tem custoM2 E unidade é M2 -> qtd x custoM2
    //    (a quantidade já representa m², então é direto)
    //    Se além disso tiver largura/comprimento, usa area unitaria × qtd × custoM2
    //    para materiais onde qty = numero de folhas (ex: vinil em chapas vendidas por m2)
    // 3. Qualquer outra unidade (ML, UNIDADE, KG, etc.) sem custo unitario -> sem custo
    const unidadeM2 = ['M2', 'M²', 'M2²', 'M 2', 'METRO QUADRADO'].includes(
      (mat.unidade || '').trim().toUpperCase()
    );
    let valorTotal = 0;
    if (custo > 0) {
      valorTotal = qtd * custo;
    } else if (custoM2 > 0 && unidadeM2) {
      if (mat.largura && mat.comprimento) {
        // qty = número de folhas; calcula área total em m²
        const area = Number(mat.largura) * Number(mat.comprimento);
        valorTotal = qtd * area * custoM2;
      } else {
        // qty já é em m²
        valorTotal = qtd * custoM2;
      }
    }
    // Se não caiu em nenhuma das condições acima: valorTotal permanece 0 (sem custo)

    porCategoria[cat].totalValor   += valorTotal;
    porCategoria[cat].qtdMateriais += 1;
    porCategoria[cat].materiais.push({
      id:            mat.id,
      nome:          mat.nome,
      unidade:       mat.unidade,
      identificador: mat.identificador,
      medida:        mat.medida,
      espessura:     mat.espessura,
      quantidade:    qtd,
      estoqueMinimo: Number(mat.estoqueMinimo),
      status:        mat.status,
      ultimoValorPago:   custo   > 0 ? custo   : null,
      ultimoValorPagoM2: custoM2 > 0 ? custoM2 : null,
      largura:       mat.largura   ? Number(mat.largura)   : null,
      comprimento:   mat.comprimento ? Number(mat.comprimento) : null,
      valorTotal,
    });
  }

  return Object.values(porCategoria)
    .map((g) => ({
      ...g,
      materiais: g.materiais.sort((a, b) => b.valorTotal - a.valorTotal),
    }))
    .sort((a, b) => b.totalValor - a.totalValor);
}

// ═════════════════════════════════════════════════════════════════════════════
// SEÇÃO 2 — GASTOS (OS FECHADAS)
//
// Regra de negócio:
//   - Só contam SAÍDAS que tiveram origem em ENTRADA por Ordem de Compra (OC).
//   - Se um material teve 2 saídas e 2 entradas via controle de estoque,
//     o saldo líquido é 0 e NÃO vai para o gasto.
//   - Se entrou por OC e depois saiu, conta como gasto (saída líquida).
//
// Algoritmo por material dentro de cada OS:
//   1. Separa movimentações em ordem cronológica.
//   2. Mantém um "saldo OC" separado do "saldo controle".
//      - ENTRADA via OC  → incrementa saldoOC
//      - ENTRADA via controle → incrementa saldoControle
//   3. Para cada SAÍDA, consome primeiro do saldoOC (gera custo real),
//      depois do saldoControle (não gera custo — devolução/ajuste).
//   4. O gasto é: quantidade consumida do saldoOC × preço da saída.
// ═════════════════════════════════════════════════════════════════════════════

async function gastosPorCategoria({ dataInicio, dataFim } = {}) {
  const whereMovimentacao = { relacaoOS: { status: 'FECHADA' } };

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
          id: true, nome: true, categoria: true,
          unidade: true, identificador: true, medida: true, espessura: true,
        },
      },
    },
    orderBy: { criadoEm: 'asc' },
  });

  // Agrupa por OS → material para calcular o saldo correto por escopo
  const porOS = {};

  for (const mov of movimentacoes) {
    const osId  = mov.relacaoOSId;
    const matId = mov.materialId;
    if (!porOS[osId]) porOS[osId] = {};
    if (!porOS[osId][matId]) porOS[osId][matId] = { movs: [], material: mov.material };
    porOS[osId][matId].movs.push(mov);
  }

  const porCategoria = {};

  for (const [, materiaisDaOS] of Object.entries(porOS)) {
    for (const [, { movs, material }] of Object.entries(materiaisDaOS)) {
      const cat   = material.categoria || '__SEM_CATEGORIA__';
      const matId = material.id;

      if (!porCategoria[cat]) {
        porCategoria[cat] = {
          categoria:  cat === '__SEM_CATEGORIA__' ? null : cat,
          totalGasto: 0,
          materiais:  {},
        };
      }
      if (!porCategoria[cat].materiais[matId]) {
        porCategoria[cat].materiais[matId] = {
          id:            matId,
          nome:          material.nome,
          unidade:       material.unidade,
          identificador: material.identificador,
          medida:        material.medida,
          espessura:     material.espessura,
          totalGasto:    0,
          qtdGasta:      0,
        };
      }

      // ── Lógica de saldo líquido ───────────────────────────────────────────
      // Regra: toda saída gera gasto. Entradas posteriores à primeira saída
      // são devoluções e reduzem o saldo (independente da origem — OC ou controle).
      // Entradas ANTES da primeira saída são reposição de estoque e não entram
      // no cálculo (não havia consumo a ser coberto ainda).
      //
      // Algoritmo:
      //   - Percorre movs em ordem cronológica.
      //   - Acumula qtdSaida e qtdEntradaPosSaida separadamente.
      //   - qtdLiquida = max(0, qtdSaida - qtdEntradaPosSaida)
      //   - preço = maior preço de saída registrado para o material nessa OS.

      let primeiroSaidaVisto = false;
      let qtdSaida           = 0;
      let qtdDevolucao       = 0; // entradas após a primeira saída
      let precoRef           = 0; // maior preço de saída (unitário ou m²)

      const _ehEntradaOC = (m) =>
        m.ordemCompraId != null ||
        (m.observacao    && m.observacao.includes('via OC')) ||
        (m.descricaoItem && m.descricaoItem.includes('via OC'));

      for (const mov of movs) {
        const qtd = Number(mov.quantidade);

        if (mov.tipo === 'ENTRADA') {
          // Entradas via OC são reposição de estoque, não devolução — ignora
          if (_ehEntradaOC(mov)) continue;
          // Só conta como devolução se já houve ao menos uma saída nessa OS
          if (primeiroSaidaVisto) qtdDevolucao += qtd;
          continue;
        }

        // SAÍDA
        if (qtd <= 0) continue;
        primeiroSaidaVisto = true;
        qtdSaida += qtd;

        const pu    = Number(mov.precoUnitario || 0);
        const pm2   = Number(mov.precoM2       || 0);
        const preco = pu > 0 ? pu : pm2;
        if (preco > precoRef) precoRef = preco;
      }

      const qtdLiquida = Math.max(0, qtdSaida - qtdDevolucao);
      const gasto      = precoRef * qtdLiquida;

      if (gasto > 0) {
        porCategoria[cat].totalGasto                  += gasto;
        porCategoria[cat].materiais[matId].totalGasto += gasto;
        porCategoria[cat].materiais[matId].qtdGasta   += qtdLiquida;
      }
    }
  }

  return Object.values(porCategoria)
    .map((g) => ({
      ...g,
      materiais: Object.values(g.materiais)
        .filter((m) => m.totalGasto > 0)
        .sort((a, b) => b.totalGasto - a.totalGasto),
    }))
    .filter((g) => g.totalGasto > 0)
    .sort((a, b) => b.totalGasto - a.totalGasto);
}

// ═════════════════════════════════════════════════════════════════════════════
// SEÇÃO 3 — GASTOS MENSAIS (para gráfico) — mesma regra de saldo líquido
// ═════════════════════════════════════════════════════════════════════════════

async function gastosMensais({ ano } = {}) {
  const anoAlvo = Number(ano) || new Date().getFullYear();
  const inicio  = new Date(`${anoAlvo}-01-01T00:00:00.000Z`);
  const fim     = new Date(`${anoAlvo}-12-31T23:59:59.999Z`);

  const movimentacoes = await prisma.movimentacaoEstoque.findMany({
    where: {
      relacaoOS: { status: 'FECHADA' },
      criadoEm:  { gte: inicio, lte: fim },
    },
    select: {
      relacaoOSId:   true,
      materialId:    true,
      tipo:          true,
      quantidade:    true,
      precoUnitario: true,
      precoM2:       true,
      criadoEm:      true,
      ordemCompraId: true,
      observacao:    true,
      descricaoItem: true,
    },
    orderBy: { criadoEm: 'asc' },
  });

  // Inicializa todos os 12 meses
  const porMes = {};
  for (let m = 1; m <= 12; m++) {
    const key  = `${anoAlvo}-${String(m).padStart(2, '0')}`;
    porMes[key] = { mesAno: key, totalGasto: 0 };
  }

  // Agrupa por (osId, materialId) para calcular saldo líquido por mês da saída
  const grupos = {};

  for (const mov of movimentacoes) {
    const chave = `${mov.relacaoOSId}-${mov.materialId}`;
    if (!grupos[chave]) grupos[chave] = { movs: [] };
    grupos[chave].movs.push(mov);
  }

  const _ehEntradaOC = (m) =>
    m.ordemCompraId != null ||
    (m.observacao    && m.observacao.includes('via OC')) ||
    (m.descricaoItem && m.descricaoItem.includes('via OC'));

  for (const { movs } of Object.values(grupos)) {
    // Mesma lógica de saldo líquido, mas precisamos distribuir por mês de saída
    // Estratégia: calcula qtdLiquida total e debita proporcionalmente das saídas
    // em ordem cronológica (mais simples: atribui o gasto ao mês da última saída
    // que tiver saldo positivo após descontar devoluções).

    let primeiroSaidaVisto = false;
    let qtdDevolucaoRestante = 0;

    // Primeiro pass: conta devoluções totais
    for (const mov of movs) {
      if (mov.tipo === 'ENTRADA' && !_ehEntradaOC(mov) && primeiroSaidaVisto) {
        qtdDevolucaoRestante += Number(mov.quantidade);
      }
      if (mov.tipo === 'SAIDA') primeiroSaidaVisto = true;
    }

    // Segundo pass: distribui saídas líquidas por mês
    primeiroSaidaVisto = false;
    for (const mov of movs) {
      if (mov.tipo === 'ENTRADA') {
        if (!_ehEntradaOC(mov) && primeiroSaidaVisto) {
          // devolução já contada acima
        }
        continue;
      }
      if (mov.tipo !== 'SAIDA') continue;

      primeiroSaidaVisto = true;
      const qtd = Number(mov.quantidade);
      if (qtd <= 0) continue;

      // Quantas dessas unidades são "líquidas" (não devolvidas)
      const devDesc    = Math.min(qtd, qtdDevolucaoRestante);
      qtdDevolucaoRestante -= devDesc;
      const qtdLiquida = qtd - devDesc;

      if (qtdLiquida > 0) {
        const pu    = Number(mov.precoUnitario || 0);
        const pm2   = Number(mov.precoM2       || 0);
        const preco = pu > 0 ? pu : pm2;
        const mes   = mov.criadoEm.getMonth() + 1;
        const key   = `${anoAlvo}-${String(mes).padStart(2, '0')}`;
        if (porMes[key]) porMes[key].totalGasto += preco * qtdLiquida;
      }
    }
  }

  return Object.values(porMes);
}

module.exports = { valorEmEstoque, gastosPorCategoria, gastosMensais };