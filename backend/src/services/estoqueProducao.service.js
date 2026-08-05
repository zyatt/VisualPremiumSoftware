const prisma = require('../utils/prisma');
const { resolverRelacaoOSDescritiva } = require('./estoque.service');

function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q   = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

function _formatarMedidaRetalho(areaM2) {
  // Não arredonda para um número fixo de casas — só limpa ruído de ponto
  // flutuante (ex.: 1.9999999999998) mantendo a precisão real da área.
  const arredondado = Math.round(Number(areaM2) * 10000) / 10000;
  return `${arredondado}m²`;
}

function _normalizarProducao(producao) {
  const raw = String(producao ?? '').trim().toUpperCase();
  const match = raw.match(/^(?:PRODUCAO)?([12])$/);
  if (!match) {
    throw { status: 400, message: "Informe a linha de produção ('1' ou '2')" };
  }
  return match[1];
}

async function transferirParaProducao({
  materialId,
  quantidade,
  producao,
  observacao,
  larguraUsada,
  comprimentoUsado,
  usuarioNome,
}) {
  const qtd = Number(quantidade);
  if (!qtd || qtd <= 0) {
    throw { status: 400, message: 'Informe uma quantidade válida' };
  }
  const prod = _normalizarProducao(producao);

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

  const NOME_BASE_TRANSFERENCIA = `TRANSFERENCIA-PRODUCAO${prod}`;
  const relacao = await resolverRelacaoOSDescritiva(NOME_BASE_TRANSFERENCIA);

  const resultado = await prisma.$transaction(async (tx) => {
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

    const obsBaseTransferencia =
      `Transferência do estoque padrão para produção ${prod} – ${usuarioNome ?? 'Usuário'}`;
    const obsTransferencia = observacao?.trim()
      ? `${obsBaseTransferencia}\n${observacao.trim()}`
      : obsBaseTransferencia;
    await tx.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo:        'SAIDA',
        quantidade:  qtd,
        numeroOS:    relacao.numeroOS,
        relacaoOSId: relacao.id,
        observacao:  obsTransferencia,
        origemProducao: 'TRANSFERENCIA',
        producao:       prod,
        larguraUsada:     larguraUsada != null ? Number(larguraUsada) : null,
        comprimentoUsado: comprimentoUsado != null ? Number(comprimentoUsado) : null,
      },
    });

    await tx.relacaoOS.update({
      where: { id: relacao.id },
      data:  { atualizadoEm: new Date() },
    });

    const estoqueProd = await tx.estoqueProducao.upsert({
      where:  { materialId_producao: { materialId, producao: prod } },
      create: { materialId, producao: prod, quantidade: qtd },
      update: { quantidade: { increment: qtd } },
    });

    await tx.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'TRANSFERENCIA',
        quantidade: qtd,
        producao:   prod,
        observacao: observacao?.trim()
          ? `Transferência do estoque padrão para produção ${prod}\n${observacao.trim()}`
          : `Transferência do estoque padrão para produção ${prod}`,
        usuarioNome: usuarioNome ?? null,
      },
    });

    return estoqueProd;
  });

  return resultado;
}

/**
 * Devolve material do estoque de produção de volta para o estoque padrão.
 * NÃO incrementa mais o Material diretamente: a quantidade sai do saldo
 * disponível da produção na hora (decrement em `quantidade`) mas fica
 * "no limbo" em `quantidadePendente`, e uma EntradaPendente (tipo
 * DEVOLUCAO) é criada. Só ao ser confirmada em Controle de Estoque é que
 * o Material do estoque padrão é de fato incrementado.
 */
async function devolverAoEstoquePadrao({
  materialId,
  quantidade,
  producao,
  observacao,
  usuarioNome,
}) {
  const qtd = Number(quantidade);
  if (!qtd || qtd <= 0) {
    throw { status: 400, message: 'Informe uma quantidade válida' };
  }
  const prod = _normalizarProducao(producao);

  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material || !material.ativo) {
    throw { status: 404, message: 'Material não encontrado ou inativo' };
  }

  const estoqueProd = await prisma.estoqueProducao.findUnique({
    where: { materialId_producao: { materialId, producao: prod } },
  });
  if (!estoqueProd || Number(estoqueProd.quantidade) < qtd) {
    const disponivel = estoqueProd ? Number(estoqueProd.quantidade) : 0;
    throw {
      status: 400,
      message: `Estoque de produção ${prod} insuficiente: disponível ${disponivel} ${material.unidade ?? ''}`.trim(),
    };
  }

  const obsBaseDevolucao =
    `Devolução da produção ${prod} para o estoque padrão – ${usuarioNome ?? 'Usuário'} (aguardando confirmação)`;
  const obsDevolucao = observacao?.trim()
    ? `${obsBaseDevolucao}\n${observacao.trim()}`
    : obsBaseDevolucao;

  const resultado = await prisma.$transaction(async (tx) => {
    await tx.estoqueProducao.update({
      where: { materialId_producao: { materialId, producao: prod } },
      data: {
        quantidade:        { decrement: qtd },
        quantidadePendente: { increment: qtd },
      },
    });

    const movProducao = await tx.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'DEVOLUCAO',
        quantidade: qtd,
        producao:   prod,
        observacao: observacao?.trim()
          ? `Devolução da produção ${prod} para o estoque padrão (aguardando confirmação)\n${observacao.trim()}`
          : `Devolução da produção ${prod} para o estoque padrão (aguardando confirmação)`,
        usuarioNome: usuarioNome ?? null,
      },
    });

    const pendencia = await tx.entradaPendente.create({
      data: {
        tipo:        'DEVOLUCAO',
        status:      'PENDENTE',
        materialId,
        quantidade:  qtd,
        producao:    prod,
        observacao:  obsDevolucao,
        usuarioNome: usuarioNome ?? null,
      },
    });

    return { movimentacaoProducao: movProducao, pendencia };
  });

  return resultado;
}

async function transferirEntreLinhas({
  materialId,
  quantidade,
  producaoOrigem,
  producaoDestino,
  observacao,
  usuarioNome,
}) {
  const qtd = Number(quantidade);
  if (!qtd || qtd <= 0) {
    throw { status: 400, message: 'Informe uma quantidade válida' };
  }
  const origem  = _normalizarProducao(producaoOrigem);
  const destino = _normalizarProducao(producaoDestino);
  if (origem === destino) {
    throw { status: 400, message: 'A linha de origem e a de destino devem ser diferentes' };
  }

  const estoqueOrigem = await prisma.estoqueProducao.findUnique({
    where: { materialId_producao: { materialId, producao: origem } },
  });
  if (!estoqueOrigem || Number(estoqueOrigem.quantidade) < qtd) {
    const disponivel = estoqueOrigem ? Number(estoqueOrigem.quantidade) : 0;
    throw {
      status: 400,
      message: `Estoque de produção ${origem} insuficiente: disponível ${disponivel}`,
    };
  }

  const obsBase = `Transferência da produção ${origem} para produção ${destino} – ${usuarioNome ?? 'Usuário'}`;
  const obsFinal = observacao?.trim() ? `${obsBase}\n${observacao.trim()}` : obsBase;

  const resultado = await prisma.$transaction(async (tx) => {
    await tx.estoqueProducao.update({
      where: { materialId_producao: { materialId, producao: origem } },
      data:  { quantidade: { decrement: qtd } },
    });

    const estoqueDestino = await tx.estoqueProducao.upsert({
      where:  { materialId_producao: { materialId, producao: destino } },
      create: { materialId, producao: destino, quantidade: qtd },
      update: { quantidade: { increment: qtd } },
    });

    await tx.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:        'TRANSFERENCIA_LINHA',
        quantidade:  qtd,
        producao:    destino,
        observacao:  obsFinal,
        usuarioNome: usuarioNome ?? null,
      },
    });

    return estoqueDestino;
  });

  return resultado;
}

async function listarEstoque({ producao, busca, categoria, identificador, medida, espessura, comprimento, largura } = {}) {
  const prod = _normalizarProducao(producao);
  const where = { quantidade: { gt: 0 }, producao: prod };

  const materialWhere = { ativo: true };
  if (busca)         materialWhere.nome          = { contains: busca,         mode: 'insensitive' };
  if (categoria)     materialWhere.categoria     = { equals:   categoria,     mode: 'insensitive' };
  if (identificador) materialWhere.identificador = { contains: identificador, mode: 'insensitive' };
  if (medida)        materialWhere.medida        = { contains: medida,        mode: 'insensitive' };
  if (espessura)     materialWhere.espessura     = { contains: espessura,     mode: 'insensitive' };
  // comprimento/largura são numéricos no banco — o filtro digitado (texto)
  // é convertido para número antes de comparar. Valores não numéricos são
  // ignorados (não filtram nada).
  if (comprimento) {
    const compNum = Number(String(comprimento).replace(',', '.'));
    if (Number.isFinite(compNum)) materialWhere.comprimento = compNum;
  }
  if (largura) {
    const largNum = Number(String(largura).replace(',', '.'));
    if (Number.isFinite(largNum)) materialWhere.largura = largNum;
  }

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
    quantidade:        r.quantidade,
    quantidadePendente: r.quantidadePendente,
    producao:          r.producao,
  }));
}

/**
 * Em vez de criar/incrementar o Material de retalho diretamente, registra
 * uma EntradaPendente (tipo RETALHO). O retalho só é de fato criado ou
 * incrementado no estoque padrão quando essa pendência for confirmada em
 * Controle de Estoque (ver confirmarEntradaPendente). Nenhum Material é
 * tocado aqui — o material original que gerou o retalho já teve sua baixa
 * registrada antes desta função ser chamada.
 */
async function _gerarOuIncrementarRetalhoEstoquePadrao(tx, {
  material, larguraUsada, comprimentoUsado, precoM2Final, precoUnitarioFinal,
  producao, numeroOS, relacaoOSId, usuarioNome,
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

  const obsRetalho =
    `Retalho de ${areaRetalho} m² gerado pela baixa da produção ${producao} (OS ${numeroOS}) – ${usuarioNome ?? 'Usuário'} (aguardando confirmação)`;

  await tx.entradaPendente.create({
    data: {
      tipo:               'RETALHO',
      status:             'PENDENTE',
      materialId:         material.id,
      quantidade:         areaRetalho,
      producao,
      numeroOS,
      relacaoOSId,
      larguraUsada:       larg,
      comprimentoUsado:   comp,
      precoM2Final:       precoM2Final != null ? Number(precoM2Final) : null,
      precoUnitarioFinal: precoUnitarioFinal != null ? Number(precoUnitarioFinal) : null,
      observacao:         obsRetalho,
      usuarioNome:        usuarioNome ?? null,
    },
  });
}

/**
 * Executa de fato a criação/incremento do Material de retalho no estoque
 * padrão, a partir dos dados de uma EntradaPendente do tipo RETALHO já
 * confirmada. Espelha a lógica que antes rodava direto em
 * _gerarOuIncrementarRetalhoEstoquePadrao.
 */
async function _efetivarRetalho(tx, pendencia) {
  const material = await tx.material.findUnique({ where: { id: pendencia.materialId } });
  if (!material) throw { status: 404, message: 'Material de origem do retalho não encontrado' };

  const areaRetalho = Number(pendencia.quantidade);
  const medidaRetalho = _formatarMedidaRetalho(areaRetalho);

  let retalhoMat = await tx.material.findFirst({
    where: {
      nome:          { equals: material.nome, mode: 'insensitive' },
      identificador: { equals: 'RETALHO',    mode: 'insensitive' },
      medida:        { equals: medidaRetalho, mode: 'insensitive' },
      espessura:     material.espessura
        ? { equals: material.espessura, mode: 'insensitive' }
        : null,
    },
  });

  const custoM2Retalho = (() => {
    const precoM2Final = pendencia.precoM2Final != null ? Number(pendencia.precoM2Final) : null;
    const precoUnitarioFinal = pendencia.precoUnitarioFinal != null ? Number(pendencia.precoUnitarioFinal) : null;
    if (precoM2Final != null && precoM2Final > 0) {
      const area = Number(pendencia.larguraUsada) * Number(pendencia.comprimentoUsado);
      if (area > 0) return precoM2Final / area;
    }
    const areaT = Number(material.largura) * Number(material.comprimento);
    if (precoUnitarioFinal != null && precoUnitarioFinal > 0 && areaT > 0) return precoUnitarioFinal / areaT;
    return material.ultimoValorPagoM2 != null ? Number(material.ultimoValorPagoM2) : null;
  })();

  if (!retalhoMat) {
    try {
      retalhoMat = await tx.material.create({
        data: {
          nome:              material.nome,
          unidade:           'M²',
          categoria:         material.categoria ?? null,
          medida:            medidaRetalho,
          espessura:         material.espessura ?? null,
          identificador:     'RETALHO',
          quantidade:        areaRetalho,
          estoqueMinimo:     0,
          status:            _calcularStatus(areaRetalho, 0, true),
          estoqueConfirmado: true,
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
            medida:    { equals: medidaRetalho, mode: 'insensitive' },
            espessura: material.espessura
              ? { equals: material.espessura, mode: 'insensitive' }
              : null,
          },
        });
        if (!retalhoMat) throw err;
        const novaQtd = Number(retalhoMat.quantidade) + areaRetalho;
        await tx.material.update({
          where: { id: retalhoMat.id },
          data: {
            quantidade: novaQtd,
            status:     _calcularStatus(novaQtd, Number(retalhoMat.estoqueMinimo), retalhoMat.ativo),
          },
        });
      } else {
        throw err;
      }
    }
  } else {
    const novaQtd = Number(retalhoMat.quantidade) + areaRetalho;
    await tx.material.update({
      where: { id: retalhoMat.id },
      data: {
        quantidade:        novaQtd,
        status:            _calcularStatus(novaQtd, Number(retalhoMat.estoqueMinimo), retalhoMat.ativo),
        ultimoValorPago:   null,
        ...(custoM2Retalho != null ? { ultimoValorPagoM2: custoM2Retalho } : {}),
      },
    });
  }

  await tx.movimentacaoEstoque.create({
    data: {
      materialId:  retalhoMat.id,
      tipo:        'ENTRADA',
      quantidade:  areaRetalho,
      numeroOS:    pendencia.numeroOS,
      relacaoOSId: pendencia.relacaoOSId,
      precoM2:     custoM2Retalho ?? undefined,
      observacao:  `Retalho confirmado de ${areaRetalho} m² gerado pela baixa da produção ${pendencia.producao}` +
        (pendencia.numeroOS ? ` (OS ${pendencia.numeroOS})` : '') +
        ` – ${pendencia.usuarioNome ?? 'Usuário'}`,
      origemProducao: 'BAIXA',
      producao:       pendencia.producao,
    },
  });

  if (pendencia.relacaoOSId) {
    await tx.relacaoOS.update({
      where: { id: pendencia.relacaoOSId },
      data:  { atualizadoEm: new Date() },
    });
  }

  return retalhoMat;
}

async function darBaixa({
  materialId,
  quantidade,
  producao,
  numeroOS,
  observacao,
  usuarioNome,
  larguraUsada,
  comprimentoUsado,
}) {
  const temQuantidadeInformada = quantidade != null && quantidade !== '';
  const qtdInteira = temQuantidadeInformada ? Number(quantidade) : 0;
  if (temQuantidadeInformada && (!Number.isFinite(qtdInteira) || qtdInteira <= 0)) {
    throw { status: 400, message: 'Informe uma quantidade válida' };
  }

  const temDimensao = larguraUsada != null && larguraUsada !== '' &&
    comprimentoUsado != null && comprimentoUsado !== '';

  if (qtdInteira <= 0 && !temDimensao) {
    throw {
      status: 400,
      message: 'Informe a quantidade e/ou a dimensão usada',
    };
  }

  const qtd = qtdInteira + (temDimensao ? 1 : 0);

  const prod = _normalizarProducao(producao);
  const numeroOSNorm = (numeroOS ?? '').trim().toUpperCase();
  if (!numeroOSNorm) {
    throw { status: 400, message: 'Informe o número da OS' };
  }

  const estoqueProd = await prisma.estoqueProducao.findUnique({
    where: { materialId_producao: { materialId, producao: prod } },
  });
  if (!estoqueProd || Number(estoqueProd.quantidade) < qtd) {
    const disponivel = estoqueProd ? Number(estoqueProd.quantidade) : 0;
    throw {
      status: 400,
      message: `Estoque de produção ${prod} insuficiente: disponível ${disponivel}`,
    };
  }

  const material = await prisma.material.findUnique({ where: { id: materialId } });

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

  const precoUnitarioFinal = material?.ultimoValorPago != null ? Number(material.ultimoValorPago) : null;
  let precoM2Dimensional = material?.ultimoValorPagoM2 != null ? Number(material.ultimoValorPagoM2) : null;

  const _unidadeMat = (material?.unidade ?? '').toLowerCase().trim();
  const _eMetroLinear = ['m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'].includes(_unidadeMat);
  if (_eMetroLinear) precoM2Dimensional = null;

  if (
    temDimensao &&
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
      const custoM2 = precoM2Dimensional != null
        ? precoM2Dimensional
        : (precoUnitarioFinal != null && areaTotal > 0 ? precoUnitarioFinal / areaTotal : null);
      if (custoM2 != null) {
        precoM2Dimensional = Math.round(custoM2 * areaUsada * 1000000) / 1000000;
      }
    }
  }

  const usuarioLabel = usuarioNome ?? 'Usuário';

  const movimentacao = await prisma.$transaction(async (tx) => {
    await tx.estoqueProducao.update({
      where: { materialId_producao: { materialId, producao: prod } },
      data:  { quantidade: { decrement: qtd } },
    });

    let primeiraMov = null;

    if (qtdInteira > 0) {
      const obsBaseInteira = `Baixa da produção ${prod} – ${usuarioLabel}`;
      const obsInteiraFinal = observacao?.trim()
        ? `${obsBaseInteira}\n${observacao.trim()}`
        : obsBaseInteira;

      const movInteira = await tx.movimentacaoProducao.create({
        data: {
          materialId,
          tipo:       'BAIXA',
          quantidade: qtdInteira,
          numeroOS:   numeroOSNorm,
          producao:   prod,
          observacao: observacao?.trim()
            ? `Baixa da produção ${prod}\n${observacao.trim()}`
            : `Baixa da produção ${prod}`,
          usuarioNome: usuarioNome ?? null,
        },
      });
      primeiraMov = primeiraMov ?? movInteira;

      await tx.movimentacaoEstoque.create({
        data: {
          materialId,
          tipo:        'SAIDA',
          quantidade:  qtdInteira,
          numeroOS:    numeroOSNorm,
          relacaoOSId: relacao.id,
          observacao:  obsInteiraFinal,
          origemProducao: 'BAIXA',
          producao:       prod,
          precoUnitario: precoUnitarioFinal ?? undefined,
          larguraUsada:     null,
          comprimentoUsado: null,
        },
      });
    }

    if (temDimensao) {
      const obsBaseDimensional = `Baixa da produção ${prod} – ${usuarioLabel}`;
      const obsDimensionalFinal = observacao?.trim()
        ? `${obsBaseDimensional}\n${observacao.trim()}`
        : obsBaseDimensional;

      const movDimensional = await tx.movimentacaoProducao.create({
        data: {
          materialId,
          tipo:       'BAIXA',
          quantidade: 1,
          numeroOS:   numeroOSNorm,
          producao:   prod,
          observacao: observacao?.trim()
            ? `Baixa da produção ${prod}\n${observacao.trim()}`
            : `Baixa da produção ${prod}`,
          usuarioNome: usuarioNome ?? null,
        },
      });
      primeiraMov = primeiraMov ?? movDimensional;

      await tx.movimentacaoEstoque.create({
        data: {
          materialId,
          tipo:        'SAIDA',
          quantidade:  1,
          numeroOS:    numeroOSNorm,
          relacaoOSId: relacao.id,
          observacao:  obsDimensionalFinal,
          origemProducao: 'BAIXA',
          producao:       prod,
          precoM2: precoM2Dimensional ?? undefined,
          larguraUsada:     Number(larguraUsada),
          comprimentoUsado: Number(comprimentoUsado),
        },
      });
    }

    await tx.relacaoOS.update({
      where: { id: relacao.id },
      data:  { atualizadoEm: new Date() },
    });

    await _gerarOuIncrementarRetalhoEstoquePadrao(tx, {
      material,
      larguraUsada:     temDimensao ? Number(larguraUsada)     : null,
      comprimentoUsado: temDimensao ? Number(comprimentoUsado) : null,
      precoM2Final: precoM2Dimensional,
      precoUnitarioFinal,
      producao: prod,
      numeroOS: numeroOSNorm,
      relacaoOSId: relacao.id,
      usuarioNome,
    });

    return primeiraMov;
  });

  return movimentacao;
}

/**
 * Histórico de movimentações do estoque de produção (transferências + baixas).
 * Compartilhado entre as duas linhas de produção — cada registro carrega o
 * campo [producao] para identificar de qual linha veio. [producao] aqui é
 * um filtro OPCIONAL: quando informado, restringe a apenas uma linha;
 * quando omitido, retorna o histórico das duas.
 */
async function listarHistorico({ producao, busca, numeroOS } = {}) {
  const where = {};
  if (producao) where.producao = _normalizarProducao(producao);
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
        select: {
          id: true, nome: true, unidade: true, identificador: true,
          medida: true, espessura: true, largura: true, comprimento: true,
        },
      },
    },
    orderBy: { criadoEm: 'desc' },
  });
}

/**
 * Exclui um registro do histórico do estoque de produção (transferência ou
 * baixa). Apenas remove o registro da MovimentacaoProducao — não altera o
 * saldo do EstoqueProducao nem gera qualquer estorno, diferente de uma
 * remoção feita a partir do Controle de Estoque (que reverte a
 * transferência). Aqui a exclusão é puramente de histórico.
 */
async function excluirHistorico(movimentacaoId) {
  const mov = await prisma.movimentacaoProducao.findUnique({
    where: { id: movimentacaoId },
  });
  if (!mov) throw { status: 404, message: 'Registro não encontrado' };

  await prisma.movimentacaoProducao.delete({ where: { id: movimentacaoId } });
}

/**
 * Lista as pendências (RETALHO e/ou DEVOLUCAO) aguardando confirmação no
 * Controle de Estoque. Por padrão traz todas as linhas de produção e
 * apenas status PENDENTE — o card de "Pendentes" do dialog de Saída p/
 * Produção mostra todas, independente da linha.
 */
async function listarPendentes({ producao, tipo, status } = {}) {
  const where = { status: status ?? 'PENDENTE' };
  if (producao) where.producao = _normalizarProducao(producao);
  if (tipo)     where.tipo = tipo;

  const registros = await prisma.entradaPendente.findMany({
    where,
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true, categoria: true,
          identificador: true, medida: true, espessura: true,
          largura: true, comprimento: true,
        },
      },
    },
    orderBy: { criadoEm: 'desc' },
  });

  // Para RETALHO, o `material` incluído é o material de ORIGEM (que gerou
  // a sobra) — sua unidade/medida/dimensões não são as do retalho em si.
  // O retalho é sempre M², com medida calculada a partir da área sobrante,
  // sem largura/comprimento próprios (é uma peça irregular). Sobrescreve
  // esses campos para refletir o retalho, mantendo nome/categoria/
  // espessura do material de origem (o retalho herda esses atributos).
  return registros.map((r) => {
    if (r.tipo === 'RETALHO') {
      const areaRetalho = Number(r.quantidade);
      return {
        ...r,
        material: {
          ...r.material,
          unidade:       'M²',
          identificador: 'RETALHO',
          medida:        _formatarMedidaRetalho(areaRetalho),
          largura:       null,
          comprimento:   null,
        },
      };
    }

    // DEVOLUCAO de um material RETALHO cuja quantidade devolvida diverge da
    // medida do retalho original: ao confirmar, será criado (ou somado) um
    // retalho NOVO do tamanho devolvido (ver confirmarEntradaPendente). Aqui
    // é só exibição — mostra essa medida nova em vez da medida do material
    // de origem, pra refletir o que realmente vai ser criado.
    if (r.tipo === 'DEVOLUCAO' && r.material?.identificador === 'RETALHO') {
      const qtd = Number(r.quantidade);
      const medidaOrigemNum = parseFloat(
        String(r.material.medida ?? '').replace('m²', '').replace(',', '.').trim()
      );
      const medidaDiverge =
        Number.isFinite(medidaOrigemNum) && Math.abs(medidaOrigemNum - qtd) > 0.0001;

      if (medidaDiverge) {
        return {
          ...r,
          material: {
            ...r.material,
            medida: _formatarMedidaRetalho(qtd),
          },
        };
      }
    }

    return r;
  });
}

/** Conta quantas pendências existem, para o badge do botão. */
async function contarPendentes() {
  return prisma.entradaPendente.count({ where: { status: 'PENDENTE' } });
}

/**
 * Confirma uma EntradaPendente: efetiva o impacto real no estoque padrão.
 * - RETALHO: cria/incrementa o Material de retalho (lógica que antes
 *   rodava direto em darBaixa).
 * - DEVOLUCAO: incrementa o Material do estoque padrão e zera a
 *   quantidadePendente correspondente em EstoqueProducao.
 */
async function confirmarEntradaPendente({ id, usuarioNome }) {
  const pendencia = await prisma.entradaPendente.findUnique({ where: { id: Number(id) } });
  if (!pendencia) throw { status: 404, message: 'Pendência não encontrada' };
  if (pendencia.status !== 'PENDENTE') {
    throw { status: 400, message: 'Esta pendência já foi resolvida' };
  }

  const resultado = await prisma.$transaction(async (tx) => {
    if (pendencia.tipo === 'RETALHO') {
      const retalhoMat = await _efetivarRetalho(tx, pendencia);
      await tx.entradaPendente.update({
        where: { id: pendencia.id },
        data:  { status: 'CONFIRMADA', resolvidoEm: new Date() },
      });
      return retalhoMat;
    }

    if (pendencia.tipo === 'DEVOLUCAO') {
      const qtd = Number(pendencia.quantidade);

      await tx.estoqueProducao.update({
        where: { materialId_producao: { materialId: pendencia.materialId, producao: pendencia.producao } },
        data:  { quantidadePendente: { decrement: qtd } },
      });

      const materialOrigem = await tx.material.findUnique({ where: { id: pendencia.materialId } });
      if (!materialOrigem) throw { status: 404, message: 'Material da devolução não encontrado' };

      // Se o material devolvido é um RETALHO e a quantidade devolvida não bate
      // com a medida (área) gravada nele, não faz sentido somar direto no
      // material original — a "medida" de um retalho É o seu tamanho. Ex.: um
      // retalho de 3.5m² enviado à produção mas devolvido com só 1.5m² (o
      // resto foi usado/gerou outro retalho lá) deve virar um retalho NOVO,
      // de 1.5m², e não inflar o registro de 3.5m² com quantidade que na
      // prática é de outro tamanho.
      const ehRetalho = materialOrigem.identificador === 'RETALHO';
      const medidaOrigemNum = ehRetalho
        ? parseFloat(String(materialOrigem.medida ?? '').replace('m²', '').replace(',', '.').trim())
        : NaN;
      const medidaDiverge =
        ehRetalho && Number.isFinite(medidaOrigemNum) && Math.abs(medidaOrigemNum - qtd) > 0.0001;

      let matAtualizado;

      if (medidaDiverge) {
        const medidaNova = _formatarMedidaRetalho(qtd);

        let retalhoNovo = await tx.material.findFirst({
          where: {
            nome:          { equals: materialOrigem.nome, mode: 'insensitive' },
            identificador: { equals: 'RETALHO', mode: 'insensitive' },
            medida:        { equals: medidaNova, mode: 'insensitive' },
            espessura:     materialOrigem.espessura
              ? { equals: materialOrigem.espessura, mode: 'insensitive' }
              : null,
          },
        });

        if (!retalhoNovo) {
          try {
            retalhoNovo = await tx.material.create({
              data: {
                nome:              materialOrigem.nome,
                unidade:           'M²',
                categoria:         materialOrigem.categoria ?? null,
                medida:            medidaNova,
                espessura:         materialOrigem.espessura ?? null,
                identificador:     'RETALHO',
                quantidade:        qtd,
                estoqueMinimo:     0,
                status:            _calcularStatus(qtd, 0, true),
                estoqueConfirmado: true,
                ativo:             true,
                ultimoValorPago:   null,
                ultimoValorPagoM2: materialOrigem.ultimoValorPagoM2 ?? null,
              },
            });
          } catch (err) {
            if (err?.code === 'P2002') {
              retalhoNovo = await tx.material.findFirst({
                where: {
                  nome:      { equals: materialOrigem.nome, mode: 'insensitive' },
                  medida:    { equals: medidaNova, mode: 'insensitive' },
                  espessura: materialOrigem.espessura
                    ? { equals: materialOrigem.espessura, mode: 'insensitive' }
                    : null,
                },
              });
              if (!retalhoNovo) throw err;
              const novaQtd = Number(retalhoNovo.quantidade) + qtd;
              retalhoNovo = await tx.material.update({
                where: { id: retalhoNovo.id },
                data: {
                  quantidade: novaQtd,
                  status:     _calcularStatus(novaQtd, Number(retalhoNovo.estoqueMinimo), retalhoNovo.ativo),
                },
              });
            } else {
              throw err;
            }
          }
        } else {
          const novaQtd = Number(retalhoNovo.quantidade) + qtd;
          retalhoNovo = await tx.material.update({
            where: { id: retalhoNovo.id },
            data: {
              quantidade: novaQtd,
              status:     _calcularStatus(novaQtd, Number(retalhoNovo.estoqueMinimo), retalhoNovo.ativo),
            },
          });
        }

        matAtualizado = retalhoNovo;
      } else {
        matAtualizado = await tx.material.update({
          where: { id: pendencia.materialId },
          data:  { quantidade: { increment: qtd } },
        });
        const novoStatus = _calcularStatus(
          matAtualizado.quantidade,
          matAtualizado.estoqueMinimo,
          matAtualizado.ativo,
        );
        matAtualizado = await tx.material.update({
          where: { id: pendencia.materialId },
          data:  { status: novoStatus },
        });
      }

      const NOME_BASE_DEVOLUCAO = `DEVOLUCAO-PRODUCAO${pendencia.producao}`;
      const relacao = await resolverRelacaoOSDescritiva(NOME_BASE_DEVOLUCAO);

      const obsConfirmacao = medidaDiverge
        ? `Devolução confirmada da produção ${pendencia.producao} para o estoque padrão – gerou retalho novo de ${_formatarMedidaRetalho(qtd)} (medida original do retalho enviado: ${materialOrigem.medida}) – ${usuarioNome ?? pendencia.usuarioNome ?? 'Usuário'}`
        : `Devolução confirmada da produção ${pendencia.producao} para o estoque padrão – ${usuarioNome ?? pendencia.usuarioNome ?? 'Usuário'}`;

      await tx.movimentacaoEstoque.create({
        data: {
          materialId: matAtualizado.id,
          tipo:        'ENTRADA',
          quantidade:  qtd,
          numeroOS:    relacao.numeroOS,
          relacaoOSId: relacao.id,
          observacao:  obsConfirmacao,
          origemProducao: 'DEVOLUCAO',
          producao:       pendencia.producao,
        },
      });
      await tx.relacaoOS.update({
        where: { id: relacao.id },
        data:  { atualizadoEm: new Date() },
      });

      await tx.entradaPendente.update({
        where: { id: pendencia.id },
        data:  { status: 'CONFIRMADA', resolvidoEm: new Date() },
      });

      return matAtualizado;
    }

    throw { status: 400, message: `Tipo de pendência desconhecido: ${pendencia.tipo}` };
  });

  return resultado;
}

/**
 * Recusa uma EntradaPendente, estornando o que for necessário:
 * - RETALHO: apenas cancela o registro — o retalho nunca saiu de lugar
 *   nenhum, então não há nada a estornar no estoque.
 * - DEVOLUCAO: devolve a quantidade para EstoqueProducao.quantidade
 *   (volta pra produção de origem), tirando de quantidadePendente.
 */
async function recusarEntradaPendente({ id, usuarioNome }) {
  const pendencia = await prisma.entradaPendente.findUnique({ where: { id: Number(id) } });
  if (!pendencia) throw { status: 404, message: 'Pendência não encontrada' };
  if (pendencia.status !== 'PENDENTE') {
    throw { status: 400, message: 'Esta pendência já foi resolvida' };
  }

  const resultado = await prisma.$transaction(async (tx) => {
    if (pendencia.tipo === 'DEVOLUCAO') {
      const qtd = Number(pendencia.quantidade);
      await tx.estoqueProducao.update({
        where: { materialId_producao: { materialId: pendencia.materialId, producao: pendencia.producao } },
        data: {
          quantidade:         { increment: qtd },
          quantidadePendente: { decrement: qtd },
        },
      });

      await tx.movimentacaoProducao.create({
        data: {
          materialId: pendencia.materialId,
          tipo:       'DEVOLUCAO',
          quantidade: qtd,
          producao:   pendencia.producao,
          observacao: `Estorno: devolução recusada, material retorna à produção ${pendencia.producao} – ${usuarioNome ?? 'Usuário'}`,
          usuarioNome: usuarioNome ?? null,
        },
      });
    }
    // RETALHO: nada a estornar no estoque — só cancela o registro abaixo.

    return tx.entradaPendente.update({
      where: { id: pendencia.id },
      data:  { status: 'RECUSADA', resolvidoEm: new Date() },
    });
  });

  return resultado;
}

module.exports = {
  transferirParaProducao,
  devolverAoEstoquePadrao,
  transferirEntreLinhas,
  listarEstoque,
  darBaixa,
  listarHistorico,
  excluirHistorico,
  listarPendentes,
  contarPendentes,
  confirmarEntradaPendente,
  recusarEntradaPendente,
};