const prisma = require('../utils/prisma');
const { resolverRelacaoOSDescritiva } = require('./estoque.service');

// Mesma lógica de status usada em material.service / producao.service, mas
// aplicada apenas ao ESTOQUE NORMAL — o estoque de produção nunca fica
// CRÍTICO nem tem estoque mínimo próprio.
function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q   = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

/**
 * Transfere material do estoque normal para o estoque de produção.
 * - Decrementa Material.quantidade (recalcula status do estoque normal).
 * - Incrementa (ou cria) o saldo em EstoqueProducao.
 * - Registra uma MovimentacaoEstoque do tipo SAIDA (para manter o histórico
 *   do estoque normal consistente com qualquer outra saída), vinculada a uma
 *   RelacaoOS "interna" de transferências (numeroOS fixo), e uma
 *   MovimentacaoProducao do tipo TRANSFERENCIA (entrada no estoque de produção).
 *
 * Não gera OS de destino — é apenas uma movimentação interna entre estoques.
 */
async function transferirParaProducao({
  materialId,
  quantidade,
  observacao,
  larguraUsada,
  comprimentoUsado,
  usuarioNome,
}) {
  const qtd = Number(quantidade);
  if (!qtd || qtd <= 0) {
    throw { status: 400, message: 'Informe uma quantidade válida' };
  }

  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material || !material.ativo) {
    throw { status: 404, message: 'Material não encontrado ou inativo' };
  }

  const saldo = Number(material.quantidade);
  if (saldo < qtd) {
    throw {
      status: 400,
      message: `Estoque insuficiente: disponível ${saldo} ${material.unidade ?? ''}`.trim(),
    };
  }

  // Resolve a RelacaoOS com data automática ANTES da transaction, pois
  // resolverRelacaoOSDescritiva usa o cliente prisma global (não o tx) e
  // pode fazer múltiplas queries internas. O resultado (id + numeroOS) é
  // passado para dentro da transaction via closure.
  //
  // Nome base: 'TRANSFERENCIA-PRODUCAO' → cria/reutiliza
  // 'TRANSFERENCIA-PRODUCAO-DD-MM-YYYY', fechando no fim do dia como
  // qualquer outra OS descritiva.
  const NOME_BASE_TRANSFERENCIA = 'TRANSFERENCIA-PRODUCAO';
  const relacao = await resolverRelacaoOSDescritiva(NOME_BASE_TRANSFERENCIA);

  const resultado = await prisma.$transaction(async (tx) => {
    // 1) Decrementa estoque normal e recalcula status
    const matAtualizado = await tx.material.update({
      where: { id: materialId },
      data:  { quantidade: { decrement: qtd } },
    });
    const novoStatus = _calcularStatus(
      matAtualizado.quantidade,
      matAtualizado.estoqueMinimo,
      matAtualizado.ativo,
    );
    await tx.material.update({ where: { id: materialId }, data: { status: novoStatus } });

    // 2) Registra saída no histórico do estoque normal vinculada à RelacaoOS
    //    do dia (ex: TRANSFERENCIA-PRODUCAO-13-07-2026). Mantém rastreabilidade
    //    e o comportamento de fechamento automático ao virar o dia.
    await tx.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo:        'SAIDA',
        quantidade:  qtd,
        numeroOS:    relacao.numeroOS,
        relacaoOSId: relacao.id,
        observacao:  observacao?.trim() || `Transferência para estoque de produção – ${usuarioNome ?? 'Usuário'}`,
        larguraUsada:     larguraUsada != null ? Number(larguraUsada) : null,
        comprimentoUsado: comprimentoUsado != null ? Number(comprimentoUsado) : null,
      },
    });

    // Atualiza atualizadoEm da RelacaoOS para refletir a última transferência
    await tx.relacaoOS.update({
      where: { id: relacao.id },
      data:  { atualizadoEm: new Date() },
    });

    // 3) Incrementa (ou cria) saldo no estoque de produção
    const estoqueProd = await tx.estoqueProducao.upsert({
      where:  { materialId },
      create: { materialId, quantidade: qtd },
      update: { quantidade: { increment: qtd } },
    });

    // 4) Histórico do estoque de produção
    await tx.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'TRANSFERENCIA',
        quantidade: qtd,
        observacao: observacao?.trim() || null,
        usuarioNome: usuarioNome ?? null,
      },
    });

    return estoqueProd;
  });

  return resultado;
}

/** Lista os materiais atualmente disponíveis no estoque de produção. */
async function listarEstoque({ busca, categoria, identificador, medida, espessura } = {}) {
  const where = { quantidade: { gt: 0 } };

  const materialWhere = { ativo: true };
  if (busca)         materialWhere.nome          = { contains: busca,         mode: 'insensitive' };
  if (categoria)     materialWhere.categoria     = { equals:   categoria,     mode: 'insensitive' };
  if (identificador) materialWhere.identificador = { contains: identificador, mode: 'insensitive' };
  if (medida)        materialWhere.medida        = { contains: medida,        mode: 'insensitive' };
  if (espessura)     materialWhere.espessura     = { contains: espessura,     mode: 'insensitive' };

  const registros = await prisma.estoqueProducao.findMany({
    where: { ...where, material: materialWhere },
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true, categoria: true,
          identificador: true, medida: true, espessura: true,
          largura: true, comprimento: true,
          ultimoValorPago: true, ultimoValorPagoM2: true,
        },
      },
    },
    orderBy: { atualizadoEm: 'desc' },
  });

  return registros.map((r) => ({
    id:            r.material.id,
    nome:          r.material.nome,
    unidade:       r.material.unidade,
    categoria:     r.material.categoria,
    identificador: r.material.identificador,
    medida:        r.material.medida,
    espessura:     r.material.espessura,
    largura:       r.material.largura,
    comprimento:   r.material.comprimento,
    ultimoValorPago:   r.material.ultimoValorPago,
    ultimoValorPagoM2: r.material.ultimoValorPagoM2,
    quantidade:    r.quantidade,
  }));
}

/**
 * Gera (ou incrementa) o retalho M² correspondente à área não utilizada de
 * uma baixa dimensional feita a partir do estoque de produção. Segue a
 * mesma regra de identificação/criação do material RETALHO usada em
 * estoque.service.js#registrarMovimentacao, mas o saldo resultante entra no
 * EstoqueProducao (não no estoque normal) — a sobra fica disponível para uso
 * imediato em produção, sem precisar ser transferida de volta.
 *
 * Deve ser chamada dentro da mesma transaction de darBaixa.
 */
async function _gerarOuIncrementarRetalhoProducao(tx, {
  material, larguraUsada, comprimentoUsado, precoM2Final, precoUnitarioFinal,
}) {
  if (larguraUsada == null || comprimentoUsado == null) return;
  if (material?.largura == null || material?.comprimento == null) return;

  const larg      = Number(larguraUsada);
  const comp      = Number(comprimentoUsado);
  const largTotal = Number(material.largura);
  const compTotal = Number(material.comprimento);
  if (!(larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0)) return;

  const areaTotal   = largTotal * compTotal;
  const areaUsada   = larg * comp;
  const areaRetalho = Math.round((areaTotal - areaUsada) * 10000) / 10000;
  if (areaRetalho <= 0.0001) return;

  let retalhoMat = await tx.material.findFirst({
    where: {
      nome:          { equals: material.nome, mode: 'insensitive' },
      identificador: { equals: 'RETALHO',    mode: 'insensitive' },
      espessura:     material.espessura
        ? { equals: material.espessura, mode: 'insensitive' }
        : null,
    },
  });

  const custoM2Retalho = (() => {
    if (precoM2Final != null && precoM2Final > 0) {
      const area = Number(larguraUsada) * Number(comprimentoUsado);
      if (area > 0) return precoM2Final / area;
    }
    const pu    = precoUnitarioFinal != null ? Number(precoUnitarioFinal) : null;
    const areaT = Number(material.largura) * Number(material.comprimento);
    if (pu != null && pu > 0 && areaT > 0) return pu / areaT;
    return material.ultimoValorPagoM2 != null ? Number(material.ultimoValorPagoM2) : null;
  })();

  if (!retalhoMat) {
    try {
      retalhoMat = await tx.material.create({
        data: {
          nome:              material.nome,
          unidade:           'M²',
          categoria:         material.categoria ?? null,
          medida:            null,
          espessura:         material.espessura ?? null,
          identificador:     'RETALHO',
          quantidade:        0,
          estoqueMinimo:     0,
          status:            _calcularStatus(0, 0, true),
          estoqueConfirmado: false,
          ativo:             true,
          ultimoValorPago:   null,
          ultimoValorPagoM2: custoM2Retalho,
        },
      });
    } catch (err) {
      if (err?.code === 'P2002') {
        retalhoMat = await tx.material.findFirst({
          where: {
            nome:      { equals: material.nome, mode: 'insensitive' },
            medida:    null,
            espessura: material.espessura
              ? { equals: material.espessura, mode: 'insensitive' }
              : null,
          },
        });
        if (!retalhoMat) throw err;
      } else {
        throw err;
      }
    }
  } else if (custoM2Retalho != null) {
    await tx.material.update({
      where: { id: retalhoMat.id },
      data:  { ultimoValorPagoM2: custoM2Retalho },
    });
  }

  // O retalho não entra no estoque normal (Material.quantidade permanece 0
  // para este item "modelo") — o saldo vai direto para o estoque de produção.
  await tx.estoqueProducao.upsert({
    where:  { materialId: retalhoMat.id },
    create: { materialId: retalhoMat.id, quantidade: areaRetalho },
    update: { quantidade: { increment: areaRetalho } },
  });

  await tx.movimentacaoProducao.create({
    data: {
      materialId:  retalhoMat.id,
      tipo:        'TRANSFERENCIA',
      quantidade:  areaRetalho,
      observacao:  `Retalho gerado a partir de baixa dimensional de "${material.nome}"`,
    },
  });
}

/**
 * Dá baixa (saída) no estoque de produção para uma OS específica.
 * Não mexe em Material.quantidade (o material já saiu do estoque normal no
 * momento da transferência), mas registra uma MovimentacaoEstoque do tipo
 * SAIDA vinculada à RelacaoOS informada — para que a baixa apareça no
 * Controle de Estoque daquela OS, do mesmo jeito que uma saída direta do
 * estoque normal ou uma solicitação de produção (ver
 * producao.service.js#_registrarSaidaControleEstoque). Sem essa ligação a
 * baixa ficava visível apenas no histórico do estoque de produção.
 *
 * Aceita larguraUsada/comprimentoUsado para materiais UNIDADE com dimensão
 * cadastrada, no mesmo padrão da tela de Controle de Estoque: quando
 * informados, quantidade é sempre 1 e o custo (precoM2) é calculado
 * proporcionalmente à área usada.
 */
async function darBaixa({
  materialId,
  quantidade,
  numeroOS,
  observacao,
  usuarioNome,
  larguraUsada,
  comprimentoUsado,
}) {
  const qtd = Number(quantidade);
  if (!qtd || qtd <= 0) {
    throw { status: 400, message: 'Informe uma quantidade válida' };
  }
  const numeroOSNorm = (numeroOS ?? '').trim().toUpperCase();
  if (!numeroOSNorm) {
    throw { status: 400, message: 'Informe o número da OS' };
  }

  const estoqueProd = await prisma.estoqueProducao.findUnique({ where: { materialId } });
  if (!estoqueProd || Number(estoqueProd.quantidade) < qtd) {
    const disponivel = estoqueProd ? Number(estoqueProd.quantidade) : 0;
    throw {
      status: 400,
      message: `Estoque de produção insuficiente: disponível ${disponivel}`,
    };
  }

  const material = await prisma.material.findUnique({ where: { id: materialId } });

  // Mesma regra de resolução de RelacaoOS usada em estoque.service.js
  // #registrarMovimentacao: OS numérica ou com sufixo (#OC/#S/#E) usa upsert
  // direto; OS descritiva usa o agrupamento por dia (resolverRelacaoOSDescritiva).
  const osEhNumerica = /^\d+$/.test(numeroOSNorm);
  const osTemSufixo  = /#(OC|S|E)/.test(numeroOSNorm);

  if (osEhNumerica) {
    const relacaoExistente = await prisma.relacaoOS.findFirst({
      where: { numeroOS: numeroOSNorm },
      orderBy: { criadoEm: 'desc' },
    });
    if (relacaoExistente?.status === 'FECHADA') {
      throw {
        status: 400,
        message: `A OS ${numeroOSNorm} está fechada e não aceita novas movimentações`,
      };
    }
  }

  let relacao;
  if (osEhNumerica || osTemSufixo) {
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS: numeroOSNorm },
      create: { numeroOS: numeroOSNorm, status: 'EM_ANDAMENTO' },
      update: {},
    });
  } else {
    relacao = await resolverRelacaoOSDescritiva(numeroOSNorm);
  }

  // Calcula precoUnitario/precoM2 (proporcional à área usada, se dimensional)
  // seguindo o mesmo cálculo de producao.service.js#_registrarSaidaControleEstoque.
  const precoUnitarioFinal = material?.ultimoValorPago != null ? Number(material.ultimoValorPago) : null;
  let precoM2Final = material?.ultimoValorPagoM2 != null ? Number(material.ultimoValorPagoM2) : null;

  const _unidadeMat = (material?.unidade ?? '').toLowerCase().trim();
  const _eMetroLinear = ['m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'].includes(_unidadeMat);
  if (_eMetroLinear) precoM2Final = null;

  if (
    larguraUsada != null && comprimentoUsado != null &&
    !_eMetroLinear &&
    material?.largura != null && material?.comprimento != null
  ) {
    const larg      = Number(larguraUsada);
    const comp      = Number(comprimentoUsado);
    const largTotal = Number(material.largura);
    const compTotal = Number(material.comprimento);

    if (larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0) {
      const areaUsada = larg * comp;
      const areaTotal = largTotal * compTotal;
      const custoM2 = precoM2Final != null
        ? precoM2Final
        : (precoUnitarioFinal != null && areaTotal > 0 ? precoUnitarioFinal / areaTotal : null);
      if (custoM2 != null) {
        precoM2Final = Math.round(custoM2 * areaUsada * 1000000) / 1000000;
      }
    }
  }

  const obsFinal = observacao?.trim() || `Baixa do estoque de produção – ${usuarioNome ?? 'Usuário'}`;

  const movimentacao = await prisma.$transaction(async (tx) => {
    await tx.estoqueProducao.update({
      where: { materialId },
      data:  { quantidade: { decrement: qtd } },
    });

    const mov = await tx.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'BAIXA',
        quantidade: qtd,
        numeroOS:   numeroOSNorm,
        observacao: observacao?.trim() || null,
        usuarioNome: usuarioNome ?? null,
      },
    });

    await tx.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo:        'SAIDA',
        quantidade:  qtd,
        numeroOS:    numeroOSNorm,
        relacaoOSId: relacao.id,
        observacao:  obsFinal,
        precoUnitario: precoUnitarioFinal ?? undefined,
        precoM2:       precoM2Final       ?? undefined,
        larguraUsada:     larguraUsada     != null ? Number(larguraUsada)     : null,
        comprimentoUsado: comprimentoUsado != null ? Number(comprimentoUsado) : null,
      },
    });

    await tx.relacaoOS.update({
      where: { id: relacao.id },
      data:  { atualizadoEm: new Date() },
    });

    // Gera/incrementa o retalho M² (sobra da área não utilizada) direto no
    // estoque de produção — mesmo comportamento da saída dimensional feita
    // pelo estoque normal (ver estoque.service.js#registrarMovimentacao).
    await _gerarOuIncrementarRetalhoProducao(tx, {
      material,
      larguraUsada,
      comprimentoUsado,
      precoM2Final,
      precoUnitarioFinal,
    });

    return mov;
  });

  return movimentacao;
}

/** Histórico de movimentações do estoque de produção (transferências + baixas). */
async function listarHistorico({ busca, numeroOS } = {}) {
  const where = {};
  if (numeroOS) where.numeroOS = { contains: numeroOS, mode: 'insensitive' };
  if (busca) {
    where.OR = [
      { numeroOS:    { contains: busca, mode: 'insensitive' } },
      { usuarioNome: { contains: busca, mode: 'insensitive' } },
      { material: { nome: { contains: busca, mode: 'insensitive' } } },
    ];
  }

  return prisma.movimentacaoProducao.findMany({
    where,
    include: {
      material: {
        select: { id: true, nome: true, unidade: true, identificador: true, medida: true, espessura: true },
      },
    },
    orderBy: { criadoEm: 'desc' },
  });
}

module.exports = {
  transferirParaProducao,
  listarEstoque,
  darBaixa,
  listarHistorico,
};