const prisma = require('../utils/prisma');

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

    const unidadeM2 = ['M2', 'M²', 'M2²', 'M 2', 'METRO QUADRADO'].includes(
      (mat.unidade || '').trim().toUpperCase()
    );
    let valorTotal = 0;
    if (custo > 0) {
      valorTotal = qtd * custo;
    } else if (custoM2 > 0 && unidadeM2) {
      if (mat.largura && mat.comprimento) {
        const area = Number(mat.largura) * Number(mat.comprimento);
        valorTotal = qtd * area * custoM2;
      } else {
        valorTotal = qtd * custoM2;
      }
    }

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

async function gastosPorCategoria({ dataInicio, dataFim } = {}) {
  const whereRelacaoOS = { status: 'FECHADA' };

  if (dataInicio || dataFim) {
    const filtroData = {};
    if (dataInicio) filtroData.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      filtroData.lte = fim;
    }
    // Filtra pela data de CRIAÇÃO da OS, não da movimentação individual,
    // para que o gasto de uma OS caia sempre no período em que ela foi aberta.
    whereRelacaoOS.criadoEm = filtroData;
  }

  const movimentacoes = await prisma.movimentacaoEstoque.findMany({
    where: { relacaoOS: whereRelacaoOS },
    include: {
      material: {
        select: {
          id: true, nome: true, categoria: true,
          unidade: true, identificador: true, medida: true, espessura: true,
          largura: true, comprimento: true,
        },
      },
      materialOrigem: { select: { id: true } },
    },
    orderBy: { criadoEm: 'asc' },
  });

  const valorRetalhoPorOSMaterial = {};
  const movimentacoesSemRetalho = [];

  for (const mov of movimentacoes) {
    if (mov.tipo === 'ENTRADA' && mov.materialOrigemId != null) {
      const pu    = Number(mov.precoUnitario || 0);
      const pm2   = Number(mov.precoM2       || 0);
      const preco = pu > 0 ? pu : pm2;
      const chave = `${mov.relacaoOSId}-${mov.materialOrigemId}`;
      valorRetalhoPorOSMaterial[chave] =
        (valorRetalhoPorOSMaterial[chave] || 0) + preco * Number(mov.quantidade);
      continue;
    }
    movimentacoesSemRetalho.push(mov);
  }

  const porOS = {};

  for (const mov of movimentacoesSemRetalho) {
    const osId  = mov.relacaoOSId;
    const matId = mov.materialId;
    if (!porOS[osId]) porOS[osId] = {};
    if (!porOS[osId][matId]) porOS[osId][matId] = { movs: [], material: mov.material };
    porOS[osId][matId].movs.push(mov);
  }

  const porCategoria = {};

  for (const [osId, materiaisDaOS] of Object.entries(porOS)) {
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
          largura:       material.largura   ? Number(material.largura)   : null,
          comprimento:   material.comprimento ? Number(material.comprimento) : null,
          totalGasto:    0,
          qtdGasta:      0,
        };
      }

      const _ehEntradaOC = (m) =>
        m.ordemCompraId != null ||
        (m.observacao    && m.observacao.includes('via OC')) ||
        (m.descricaoItem && m.descricaoItem.includes('via OC'));

      // Primeira passagem: soma a devolução total (entradas não-OC após a
      // primeira saída) para descontar das saídas mais recentes primeiro.
      let primeiroSaidaVisto   = false;
      let qtdDevolucaoRestante = 0;
      for (const mov of movs) {
        if (mov.tipo === 'ENTRADA' && !_ehEntradaOC(mov) && primeiroSaidaVisto) {
          qtdDevolucaoRestante += Number(mov.quantidade);
        }
        if (mov.tipo === 'SAIDA') primeiroSaidaVisto = true;
      }

      // Segunda passagem: valora cada SAÍDA pelo seu próprio preço (não pelo
      // maior preço da OS), descontando a devolução da(s) saída(s) mais recente(s).
      const saidasLiquidas = [];
      let qtdLiquidaTotal   = 0;
      for (const mov of movs) {
        if (mov.tipo !== 'SAIDA') continue;
        const qtd = Number(mov.quantidade);
        if (qtd <= 0) continue;

        const devDesc         = Math.min(qtd, qtdDevolucaoRestante);
        qtdDevolucaoRestante -= devDesc;
        const qtdLiquida      = qtd - devDesc;

        if (qtdLiquida > 0) {
          const pu    = Number(mov.precoUnitario || 0);
          const pm2   = Number(mov.precoM2       || 0);
          const preco = pu > 0 ? pu : pm2;
          saidasLiquidas.push({ valor: preco * qtdLiquida, qtd: qtdLiquida });
          qtdLiquidaTotal += qtdLiquida;
        }
      }

      // Desconta o valor do retalho reaproveitado, começando pelas saídas
      // mais recentes (mesma ordem usada em gastosMensais).
      let valorRetalhoRestante = valorRetalhoPorOSMaterial[`${osId}-${matId}`] || 0;
      for (let i = saidasLiquidas.length - 1; i >= 0 && valorRetalhoRestante > 0; i--) {
        const desconto = Math.min(saidasLiquidas[i].valor, valorRetalhoRestante);
        saidasLiquidas[i].valor -= desconto;
        valorRetalhoRestante    -= desconto;
      }

      const gasto = saidasLiquidas.reduce((s, x) => s + Math.max(0, x.valor), 0);

      if (gasto > 0) {
        porCategoria[cat].totalGasto                  += gasto;
        porCategoria[cat].materiais[matId].totalGasto += gasto;
        porCategoria[cat].materiais[matId].qtdGasta   += qtdLiquidaTotal;
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

async function gastosMensais({ ano } = {}) {
  const anoAlvo = Number(ano) || new Date().getFullYear();
  const inicio  = new Date(`${anoAlvo}-01-01T00:00:00.000Z`);
  const fim     = new Date(`${anoAlvo}-12-31T23:59:59.999Z`);

  // Filtra pela data de CRIAÇÃO da OS (não da movimentação nem do fechamento),
  // pois o gasto deve ser atribuído ao mês em que a OS foi aberta.
  const movimentacoes = await prisma.movimentacaoEstoque.findMany({
    where: {
      relacaoOS: {
        status: 'FECHADA',
        criadoEm: { gte: inicio, lte: fim },
      },
    },
    select: {
      relacaoOSId:      true,
      materialId:       true,
      materialOrigemId: true,
      tipo:             true,
      quantidade:       true,
      precoUnitario:    true,
      precoM2:          true,
      criadoEm:         true,
      ordemCompraId:    true,
      observacao:       true,
      descricaoItem:    true,
      relacaoOS: { select: { criadoEm: true } },
    },
    orderBy: { criadoEm: 'asc' },
  });

  const porMes = {};
  for (let m = 1; m <= 12; m++) {
    const key  = `${anoAlvo}-${String(m).padStart(2, '0')}`;
    porMes[key] = { mesAno: key, totalGasto: 0 };
  }

  const grupos = {};

  const _grupo = (osId, matId) => {
    const chave = `${osId}-${matId}`;
    if (!grupos[chave]) grupos[chave] = { movs: [], valorRetalho: 0, osCriadoEm: null };
    return grupos[chave];
  };

  for (const mov of movimentacoes) {
    if (mov.tipo === 'ENTRADA' && mov.materialOrigemId != null) {
      const pu    = Number(mov.precoUnitario || 0);
      const pm2   = Number(mov.precoM2       || 0);
      const preco = pu > 0 ? pu : pm2;
      const g = _grupo(mov.relacaoOSId, mov.materialOrigemId);
      g.valorRetalho += preco * Number(mov.quantidade);
      g.osCriadoEm = mov.relacaoOS.criadoEm;
      continue;
    }
    const g = _grupo(mov.relacaoOSId, mov.materialId);
    g.movs.push(mov);
    g.osCriadoEm = mov.relacaoOS.criadoEm;
  }

  const _ehEntradaOC = (m) =>
    m.ordemCompraId != null ||
    (m.observacao    && m.observacao.includes('via OC')) ||
    (m.descricaoItem && m.descricaoItem.includes('via OC'));

  for (const { movs, valorRetalho, osCriadoEm } of Object.values(grupos)) {
    let primeiroSaidaVisto = false;
    let qtdDevolucaoRestante = 0;

    for (const mov of movs) {
      if (mov.tipo === 'ENTRADA' && !_ehEntradaOC(mov) && primeiroSaidaVisto) {
        qtdDevolucaoRestante += Number(mov.quantidade);
      }
      if (mov.tipo === 'SAIDA') primeiroSaidaVisto = true;
    }

    primeiroSaidaVisto = false;
    const saidasLiquidas = [];
    for (const mov of movs) {
      if (mov.tipo === 'ENTRADA') continue;
      if (mov.tipo !== 'SAIDA') continue;

      primeiroSaidaVisto = true;
      const qtd = Number(mov.quantidade);
      if (qtd <= 0) continue;

      const devDesc    = Math.min(qtd, qtdDevolucaoRestante);
      qtdDevolucaoRestante -= devDesc;
      const qtdLiquida = qtd - devDesc;

      if (qtdLiquida > 0) {
        const pu    = Number(mov.precoUnitario || 0);
        const pm2   = Number(mov.precoM2       || 0);
        const preco = pu > 0 ? pu : pm2;
        // Atribui ao mês de CRIAÇÃO da OS, não ao mês da movimentação em si.
        const mes   = osCriadoEm.getMonth() + 1;
        saidasLiquidas.push({ mes, valor: preco * qtdLiquida });
      }
    }

    let valorRetalhoRestante = valorRetalho || 0;
    for (let i = saidasLiquidas.length - 1; i >= 0 && valorRetalhoRestante > 0; i--) {
      const desconto = Math.min(saidasLiquidas[i].valor, valorRetalhoRestante);
      saidasLiquidas[i].valor -= desconto;
      valorRetalhoRestante    -= desconto;
    }

    for (const { mes, valor } of saidasLiquidas) {
      if (valor <= 0) continue;
      const key = `${anoAlvo}-${String(mes).padStart(2, '0')}`;
      if (porMes[key]) porMes[key].totalGasto += valor;
    }
  }

  return Object.values(porMes);
}

module.exports = { valorEmEstoque, gastosPorCategoria, gastosMensais };