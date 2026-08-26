const prisma = require('../utils/prisma');

const _includeCompleto = {
  movimentacoes: {
    include: {
      material: { select: { id: true, nome: true, unidade: true, categoria: true, identificador: true, medida: true, espessura: true } },
      materialOrigem: { select: { id: true, nome: true } },
    },
    orderBy: { criadoEm: 'asc' },
  },
};

async function listar({ busca, cliente, materialId, materialNome, materialIdentificador, materialMedida, materialEspessura, dataInicio, dataFim } = {}) {
  const where = { status: 'FECHADA' };

  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };
  if (cliente) where.cliente = { contains: cliente, mode: 'insensitive' };

  let filtroData = null;
  if (dataInicio || dataFim) {
    filtroData = {};
    if (dataInicio) filtroData.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      filtroData.lte = fim;
    }
    // Filtra pela data de CRIAÇÃO da OS, não da movimentação individual,
    // para que o gasto de uma OS caia sempre no período em que ela foi aberta
    // (mesma regra usada em gastos_categoria_service.js).
    where.criadoEm = filtroData;
  }

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

  let whereMovimentacoesInclude = undefined;
  const temMaterial = Object.keys(filtroMaterial).length > 0;

  if (temMaterial) {
    whereMovimentacoesInclude = { material: filtroMaterial };
  }

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        where: whereMovimentacoesInclude,
        include: {
          material: { select: { id: true, nome: true, unidade: true, categoria: true, identificador: true, medida: true, espessura: true } },
          materialOrigem: { select: { id: true, nome: true } },
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

async function fecharOS(numeroOS, fechadoPorNome) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Esta OS já está fechada' };
  }

  return prisma.relacaoOS.update({
    where:  { numeroOS },
    data:   { status: 'FECHADA', fechadoPorNome: fechadoPorNome ?? null },
    include: _includeCompleto,
  });
}

async function dadosParaPDF(numeroOS) {
  const relacao = await buscarPorNumeroOS(numeroOS);
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };

  const saidas   = relacao.movimentacoes.filter((m) => m.tipo === 'SAIDA');
  const entradas = relacao.movimentacoes.filter((m) => m.tipo === 'ENTRADA');

  // _modoMov/_precoMov continuam existindo só para EXIBIÇÃO por linha
  // (mostrar "1,22x0,92m" e o preço por m2 na listagem). O CÁLCULO do
  // total (netting de devolução/retalho) não usa mais essas funções —
  // veja o bloco de totalização abaixo, que replica exatamente a regra
  // financeira de gastos_categoria_service.js.
  const _modoMov = (m) => {
    const largura     = Number(m.larguraUsada     || 0);
    const comprimento = Number(m.comprimentoUsado || 0);
    return (largura > 0 && comprimento > 0) ? 'm2' : 'un';
  };

  const _precoMov = (m) => {
    const precoUnit = Number(m.precoUnitario || 0);
    const precoM2   = Number(m.precoM2       || 0);
    return _modoMov(m) === 'm2'
      ? (precoM2 > 0 ? precoM2 : precoUnit)
      : (precoUnit > 0 ? precoUnit : precoM2);
  };

  // Regra FINANCEIRA (idêntica a gastos_categoria_service.js): sempre
  // quantidade bruta × (precoUnitario>0 ? precoUnitario : precoM2),
  // nunca área × precoM2, independentemente de a saída ter dimensões
  // preenchidas ou não.
  const _precoFinanceiro = (m) => {
    const pu  = Number(m.precoUnitario || 0);
    const pm2 = Number(m.precoM2       || 0);
    return pu > 0 ? pu : pm2;
  };

  const todasOrdenadas = [...relacao.movimentacoes].sort(
    (a, b) => new Date(a.criadoEm) - new Date(b.criadoEm)
  );

  // Agrupa as movimentações por materialId APENAS (sem distinguir modo
  // un/m2), na MESMA granularidade usada em gastos_categoria_service.js,
  // para que o netting de devolução/retalho e o total batam entre as
  // duas telas. (Antes agrupava por `${id}::${_modoMov(m)}`, separando
  // saídas do mesmo material em grupos diferentes sempre que uma tinha
  // larguraUsada/comprimentoUsado preenchidos e outra não — a devolução
  // de um grupo nunca compensava a saída do outro.)
  const gruposPorChave = new Map();
  const ultimaChavePorMaterial = new Map();

  for (const m of todasOrdenadas) {
    const id    = m.materialId;
    const chave = `${id}`;

    if (m.tipo === 'SAIDA') {
      if (!gruposPorChave.has(chave)) gruposPorChave.set(chave, { movs: [], valorRetalho: 0 });
      gruposPorChave.get(chave).movs.push(m);
      ultimaChavePorMaterial.set(id, chave);

    } else if (m.tipo === 'ENTRADA') {
      if (m.materialOrigemId != null) {
        const chaveOrigem = ultimaChavePorMaterial.get(m.materialOrigemId);
        if (chaveOrigem != null && gruposPorChave.has(chaveOrigem)) {
          // Regra financeira, não a dimensional.
          gruposPorChave.get(chaveOrigem).valorRetalho += _precoFinanceiro(m) * Number(m.quantidade);
        }
        continue;
      }

      const isEntradaOC =
        (m.observacao   && m.observacao.includes('via OC')) ||
        (m.descricaoItem && m.descricaoItem.includes('via OC'));
      if (isEntradaOC) continue;

      if (gruposPorChave.has(chave)) {
        gruposPorChave.get(chave).movs.push(m);
      }
    }
  }

  const _ehEntradaOC = (m) =>
    (m.observacao    && m.observacao.includes('via OC')) ||
    (m.descricaoItem && m.descricaoItem.includes('via OC'));

  let totalSaidas = 0;

  for (const { movs, valorRetalho } of gruposPorChave.values()) {
    // Primeira passagem: soma a devolução total (entradas não-OC, sem
    // materialOrigemId, ocorridas após a primeira saída) para descontar
    // das saídas mais recentes primeiro — mesma regra de gastos_categoria.
    let primeiroSaidaVisto   = false;
    let qtdDevolucaoRestante = 0;
    for (const mov of movs) {
      if (mov.tipo === 'ENTRADA' && !_ehEntradaOC(mov) && primeiroSaidaVisto) {
        qtdDevolucaoRestante += Number(mov.quantidade);
      }
      if (mov.tipo === 'SAIDA') primeiroSaidaVisto = true;
    }

    // Segunda passagem: valora cada SAÍDA pela regra FINANCEIRA
    // (quantidade bruta × pu/pm2 — nunca área × precoM2), descontando a
    // devolução da(s) saída(s) mais recente(s) primeiro.
    const saidasLiquidas = [];
    for (const mov of movs) {
      if (mov.tipo !== 'SAIDA') continue;
      const qtd = Number(mov.quantidade);
      if (qtd <= 0) continue;

      const devDesc         = Math.min(qtd, qtdDevolucaoRestante);
      qtdDevolucaoRestante -= devDesc;
      const qtdLiquida      = qtd - devDesc;

      if (qtdLiquida > 0) {
        saidasLiquidas.push({ valor: _precoFinanceiro(mov) * qtdLiquida });
      }
    }

    // Desconta o valor do retalho reaproveitado, começando pelas saídas
    // mais recentes (mesma ordem usada em gastos_categoria_service.js).
    let valorRetalhoRestante = valorRetalho || 0;
    for (let i = saidasLiquidas.length - 1; i >= 0 && valorRetalhoRestante > 0; i--) {
      const desconto = Math.min(saidasLiquidas[i].valor, valorRetalhoRestante);
      saidasLiquidas[i].valor -= desconto;
      valorRetalhoRestante    -= desconto;
    }

    totalSaidas += saidasLiquidas.reduce((s, x) => s + Math.max(0, x.valor), 0);
  }

  const totalGeral = totalSaidas;

  // A exibição por linha (itens/entradas do PDF) continua usando a regra
  // DIMENSIONAL (_modoMov/_precoMov) — o usuário precisa ver "1,22x0,92m"
  // e o preço por m2 na listagem, mesmo que o TOTAL acima não use essa
  // valoração. Isso é só apresentação; não afeta totalSaidas/totalGeral.
  const _mapItem = (m) => {
    const precoUnit = Number(m.precoUnitario || 0);
    const precoM2v  = Number(m.precoM2       || 0);
    const dimensional = _modoMov(m) === 'm2';
    const usarM2 = dimensional;
    const preco  = usarM2
      ? (precoM2v  > 0 ? precoM2v  : precoUnit)
      : (precoUnit > 0 ? precoUnit : precoM2v);
    const qtd = dimensional
      ? Number(m.larguraUsada || 0) * Number(m.comprimentoUsado || 0)
      : Number(m.quantidade);
    const medidaExibida = dimensional
      ? `${Number(m.larguraUsada || 0)}x${Number(m.comprimentoUsado || 0)}m`
      : (m.material.medida ?? null);

    return {
      material:      m.material.nome,
      identificador: m.material.identificador ?? null,
      medida:        medidaExibida,
      espessura:     m.material.espessura     ?? null,
      unidade:       m.material.unidade,
      categoria:     m.material.categoria,
      quantidade:    qtd,
      precoUnitario: preco,
      usarM2,
      modoDimensional: dimensional,
      total:         qtd * preco,
      data:          m.criadoEm,
      observacao:    m.observacao,
      materialOrigemId:   m.materialOrigemId   ?? null,
      materialOrigemNome: m.materialOrigem?.nome ?? null,
    };
  };

  const _agruparPorMaterial = (itensMapeados, movsOriginais) => {
    const grupos = new Map();
    const linhasDimensionais = [];

    for (let i = 0; i < itensMapeados.length; i++) {
      const item = itensMapeados[i];

      if (item.modoDimensional) {
        linhasDimensionais.push(item);
        continue;
      }

      const materialId = movsOriginais[i].materialId;
      const chave = `${materialId}::un`;
      if (!grupos.has(chave)) {
        grupos.set(chave, { ...item, observacoes: new Set(), origens: new Set() });
        const novoGrupo = grupos.get(chave);
        if (item.observacao) novoGrupo.observacoes.add(item.observacao);
        if (item.materialOrigemNome) novoGrupo.origens.add(item.materialOrigemNome);
        continue;
      }
      const grupo = grupos.get(chave);
      grupo.quantidade += item.quantidade;
      grupo.total       += item.total;
      if (new Date(item.data) > new Date(grupo.data)) grupo.data = item.data;
      if (item.observacao) grupo.observacoes.add(item.observacao);
      if (item.materialOrigemNome) grupo.origens.add(item.materialOrigemNome);
    }

    const linhasUnidade = Array.from(grupos.values()).map((g) => {
      const { observacoes, origens, ...resto } = g;
      return {
        ...resto,
        precoUnitario:       resto.quantidade > 0 ? resto.total / resto.quantidade : resto.precoUnitario,
        observacao:         observacoes.size > 0 ? Array.from(observacoes).join(' | ') : null,
        materialOrigemNome: origens.size > 0 ? Array.from(origens).join(', ') : null,
      };
    });

    return [...linhasUnidade, ...linhasDimensionais].sort(
      (a, b) => new Date(a.data) - new Date(b.data)
    );
  };

  const todasMovs = [...relacao.movimentacoes];
  const primeiraMovimentacaoEm = todasMovs.length > 0
    ? todasMovs.reduce((a, b) => new Date(a.criadoEm) < new Date(b.criadoEm) ? a : b).criadoEm
    : relacao.criadoEm;

  return {
    numeroOS:              relacao.numeroOS,
    descricao:             relacao.descricao,
    cliente:               relacao.cliente,
    status:                relacao.status,
    criadoEm:              primeiraMovimentacaoEm,
    fechadaEm:             relacao.atualizadoEm,
    geradoEm:              new Date(),
    itens:                 _agruparPorMaterial(saidas.map(_mapItem), saidas),
    entradas:              _agruparPorMaterial(entradas.map(_mapItem), entradas),
    totalSaidas,
    totalGeral,
  };
}

async function reverterOS(numeroOS) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status !== 'FECHADA') {
    throw { status: 400, message: 'Esta OS não está fechada' };
  }

  return prisma.relacaoOS.update({
    where:   { numeroOS },
    data:    { status: 'EM_ANDAMENTO', fechadoPorNome: null },
    include: _includeCompleto,
  });
}

module.exports = { listar, buscarPorNumeroOS, fecharOS, reverterOS, dadosParaPDF };