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
 * Valida e normaliza o identificador de linha de produção ('1' ou '2').
 * Aceita string ou número (1, 2, '1', '2', 'PRODUCAO1', 'PRODUCAO2').
 */
function _normalizarProducao(producao) {
  const raw = String(producao ?? '').trim().toUpperCase();
  const match = raw.match(/^(?:PRODUCAO)?([12])$/);
  if (!match) {
    throw { status: 400, message: "Informe a linha de produção ('1' ou '2')" };
  }
  return match[1];
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

  // Resolve a RelacaoOS com data automática ANTES da transaction, pois
  // resolverRelacaoOSDescritiva usa o cliente prisma global (não o tx) e
  // pode fazer múltiplas queries internas. O resultado (id + numeroOS) é
  // passado para dentro da transaction via closure.
  //
  // Nome base por linha de produção: 'TRANSFERENCIA-PRODUCAO1' ou
  // 'TRANSFERENCIA-PRODUCAO2' → cria/reutiliza
  // 'TRANSFERENCIA-PRODUCAO<N>-DD-MM-YYYY', fechando no fim do dia como
  // qualquer outra OS descritiva. Mantém as duas linhas em relações
  // separadas para que o Controle de Estoque possa distinguir para onde
  // cada transferência foi.
  const NOME_BASE_TRANSFERENCIA = `TRANSFERENCIA-PRODUCAO${prod}`;
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
    //    do dia (ex: TRANSFERENCIA-PRODUCAO1-13-07-2026). Mantém rastreabilidade
    //    e o comportamento de fechamento automático ao virar o dia.
    //    A observação identifica a origem e o destino ("transferência do
    //    estoque padrão para produção <N>") para que o Histórico de
    //    Movimentações e o Controle de Estoque exibam a linha de produção
    //    correta, mesmo quando o usuário digita uma observação própria no
    //    diálogo, que é preservada como linha extra.
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

    // Atualiza atualizadoEm da RelacaoOS para refletir a última transferência
    await tx.relacaoOS.update({
      where: { id: relacao.id },
      data:  { atualizadoEm: new Date() },
    });

    // 3) Incrementa (ou cria) saldo no estoque de produção DA LINHA informada
    const estoqueProd = await tx.estoqueProducao.upsert({
      where:  { materialId_producao: { materialId, producao: prod } },
      create: { materialId, producao: prod, quantidade: qtd },
      update: { quantidade: { increment: qtd } },
    });

    // 4) Histórico do estoque de produção (compartilhado, com a linha marcada)
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
 * Devolve material do estoque de produção (linha '1' ou '2') de volta para
 * o ESTOQUE PADRÃO (Material.quantidade) — operação inversa de
 * [transferirParaProducao]. Usado quando sobrou material na produção e ele
 * precisa voltar a ficar disponível para qualquer uso normal.
 *
 * - Decrementa o saldo em EstoqueProducao da linha informada.
 * - Incrementa Material.quantidade (recalcula status do estoque normal).
 * - Registra uma MovimentacaoEstoque do tipo ENTRADA (histórico do estoque
 *   normal), vinculada à mesma RelacaoOS "interna" usada nas transferências
 *   dessa linha, e uma MovimentacaoProducao do tipo DEVOLUCAO (saída do
 *   estoque de produção) para o histórico compartilhado de produção.
 *
 * Segue o mesmo padrão de observação/rastreabilidade de
 * [transferirParaProducao], só que na direção contrária.
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

  // Mesmo agrupamento por dia usado em transferirParaProducao, mas com nome
  // base próprio ('DEVOLUCAO-PRODUCAO<N>'), para não misturar no Controle de
  // Estoque as transferências de SAÍDA (para produção) com as de ENTRADA
  // (devolução) na mesma RelacaoOS.
  const NOME_BASE_DEVOLUCAO = `DEVOLUCAO-PRODUCAO${prod}`;
  const relacao = await resolverRelacaoOSDescritiva(NOME_BASE_DEVOLUCAO);

  const obsBaseDevolucao =
    `Devolução da produção ${prod} para o estoque padrão – ${usuarioNome ?? 'Usuário'}`;
  const obsDevolucao = observacao?.trim()
    ? `${obsBaseDevolucao}\n${observacao.trim()}`
    : obsBaseDevolucao;

  const resultado = await prisma.$transaction(async (tx) => {
    // 1) Decrementa o saldo da linha de produção
    await tx.estoqueProducao.update({
      where: { materialId_producao: { materialId, producao: prod } },
      data:  { quantidade: { decrement: qtd } },
    });

    // 2) Incrementa estoque normal e recalcula status
    const matAtualizado = await tx.material.update({
      where: { id: materialId },
      data:  { quantidade: { increment: qtd } },
    });
    const novoStatus = _calcularStatus(
      matAtualizado.quantidade,
      matAtualizado.estoqueMinimo,
      matAtualizado.ativo,
    );
    await tx.material.update({ where: { id: materialId }, data: { status: novoStatus } });

    // 3) Registra entrada no histórico do estoque normal, vinculada à
    //    RelacaoOS do dia (ex: DEVOLUCAO-PRODUCAO1-23-07-2026).
    await tx.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo:        'ENTRADA',
        quantidade:  qtd,
        numeroOS:    relacao.numeroOS,
        relacaoOSId: relacao.id,
        observacao:  obsDevolucao,
        origemProducao: 'DEVOLUCAO',
        producao:       prod,
      },
    });

    await tx.relacaoOS.update({
      where: { id: relacao.id },
      data:  { atualizadoEm: new Date() },
    });

    // 4) Histórico do estoque de produção (compartilhado, com a linha marcada)
    await tx.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'DEVOLUCAO',
        quantidade: qtd,
        producao:   prod,
        observacao: observacao?.trim()
          ? `Devolução da produção ${prod} para o estoque padrão\n${observacao.trim()}`
          : `Devolução da produção ${prod} para o estoque padrão`,
        usuarioNome: usuarioNome ?? null,
      },
    });

    return matAtualizado;
  });

  return resultado;
}

/**
 * Transfere material de UMA linha de produção para A OUTRA (ex.: sobrou
 * material na produção 1 e a produção 2 precisa dele). Restrito a
 * ADMIN/GERENTE (ver roleMiddleware na rota) — diferente da transferência
 * do estoque padrão, aqui NÃO mexe em Material.quantidade nem gera
 * MovimentacaoEstoque: é uma movimentação interna, só entre as duas linhas
 * do estoque de produção.
 *
 * Gera UM único registro de histórico (MovimentacaoProducao, tipo
 * TRANSFERENCIA_LINHA) com `producao` = linha de DESTINO (a que recebeu o
 * saldo). Não é preciso guardar a origem em coluna própria: como só existem
 * duas linhas, o frontend deriva a origem como "a outra linha" a partir do
 * destino (ver `producaoOrigemDerivada` no model Dart) — evita precisar de
 * migração de schema para este recurso.
 */
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
    // 1) Decrementa a linha de origem
    await tx.estoqueProducao.update({
      where: { materialId_producao: { materialId, producao: origem } },
      data:  { quantidade: { decrement: qtd } },
    });

    // 2) Incrementa (ou cria) a linha de destino
    const estoqueDestino = await tx.estoqueProducao.upsert({
      where:  { materialId_producao: { materialId, producao: destino } },
      create: { materialId, producao: destino, quantidade: qtd },
      update: { quantidade: { increment: qtd } },
    });

    // 3) Histórico do estoque de produção — um único registro, com
    //    `producao` apontando para a linha de destino.
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

/**
 * Lista os materiais atualmente disponíveis no estoque de produção.
 * [producao] ('1' ou '2') é OBRIGATÓRIO — cada linha de produção só pode
 * ver o próprio saldo, nunca o da outra nem o estoque normal.
 */
async function listarEstoque({ producao, busca, categoria, identificador, medida, espessura } = {}) {
  const prod = _normalizarProducao(producao);
  const where = { quantidade: { gt: 0 }, producao: prod };

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
    producao:      r.producao,
  }));
}

/**
 * Gera (ou incrementa) o retalho M² correspondente à área não utilizada de
 * uma baixa dimensional feita a partir do estoque de produção. Segue a
 * mesma regra de identificação/criação do material RETALHO usada em
 * estoque.service.js#registrarMovimentacao, e o saldo resultante entra no
 * ESTOQUE PADRÃO (Material.quantidade) — não fica preso à linha de produção
 * que fez a baixa. Quem quiser usar o retalho em produção precisa
 * transferi-lo normalmente (tela de Controle de Estoque), do mesmo jeito
 * que qualquer outro material.
 *
 * Deve ser chamada dentro da mesma transaction de darBaixa.
 *
 * Também registra uma MovimentacaoEstoque do tipo ENTRADA (vinculada à
 * mesma RelacaoOS da saída/baixa que gerou o retalho), para que o Histórico
 * de Movimentações do Controle de Estoque mostre explicitamente que aquele
 * m² foi criado/incrementado no estoque padrão a partir da baixa da
 * produção — sem essa entrada, o acréscimo ficava "invisível" no
 * histórico, aparecendo só como um incremento silencioso em
 * Material.quantidade.
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

  // Observação da entrada de retalho no histórico do estoque padrão,
  // seguindo o mesmo padrão "<descrição> – <usuário>" usado nas demais
  // movimentações de produção, para exibição consistente na tela de
  // Histórico de Movimentações.
  const obsRetalho =
    `Retalho de ${areaRetalho} m² gerado pela baixa da produção ${producao} (OS ${numeroOS}) – ${usuarioNome ?? 'Usuário'}`;

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
          quantidade:        areaRetalho,
          estoqueMinimo:     0,
          status:            _calcularStatus(areaRetalho, 0, true),
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
    // O retalho já existia (item "modelo" do estoque padrão) — incrementa o
    // saldo direto em Material.quantidade, igual a uma saída dimensional
    // feita direto no Controle de Estoque.
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

  // Registra a entrada do retalho no Histórico de Movimentações do estoque
  // padrão, vinculada à MESMA RelacaoOS da baixa de produção que o
  // originou, para deixar claro de onde veio esse m². origemProducao +
  // producao são o que alimenta o badge de origem ("Produção 1"/"Produção
  // 2") na tela de Histórico — sem eles a coluna Origem fica vazia, como
  // a saída/baixa que gerou este retalho.
  await tx.movimentacaoEstoque.create({
    data: {
      materialId:  retalhoMat.id,
      tipo:        'ENTRADA',
      quantidade:  areaRetalho,
      numeroOS,
      relacaoOSId,
      precoM2:     custoM2Retalho ?? undefined,
      observacao:  obsRetalho,
      origemProducao: 'BAIXA',
      producao,
    },
  });
  await tx.relacaoOS.update({
    where: { id: relacaoOSId },
    data:  { atualizadoEm: new Date() },
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
  producao,
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

  // A observação identifica de qual linha de produção é a baixa (ex.:
  // "Baixa da produção 1 – <usuário>") para que o Histórico de
  // Movimentações e o Controle de Estoque exibam a origem corretamente —
  // mesmo quando o usuário digita uma observação própria no diálogo, que é
  // preservada como linha extra.
  const obsBaseBaixa = `Baixa da produção ${prod} – ${usuarioNome ?? 'Usuário'}`;
  const obsFinal = observacao?.trim()
    ? `${obsBaseBaixa}\n${observacao.trim()}`
    : obsBaseBaixa;

  const movimentacao = await prisma.$transaction(async (tx) => {
    await tx.estoqueProducao.update({
      where: { materialId_producao: { materialId, producao: prod } },
      data:  { quantidade: { decrement: qtd } },
    });

    const mov = await tx.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'BAIXA',
        quantidade: qtd,
        numeroOS:   numeroOSNorm,
        producao:   prod,
        observacao: observacao?.trim()
          ? `Baixa da produção ${prod}\n${observacao.trim()}`
          : `Baixa da produção ${prod}`,
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
        origemProducao: 'BAIXA',
        producao:       prod,
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

    // Gera/incrementa o retalho M² (sobra da área não utilizada) no ESTOQUE
    // PADRÃO — mesmo comportamento da saída dimensional feita pelo estoque
    // normal (ver estoque.service.js#registrarMovimentacao). O retalho não
    // fica mais preso à linha de produção que fez a baixa.
    await _gerarOuIncrementarRetalhoEstoquePadrao(tx, {
      material,
      larguraUsada,
      comprimentoUsado,
      precoM2Final,
      precoUnitarioFinal,
      producao: prod,
      numeroOS: numeroOSNorm,
      relacaoOSId: relacao.id,
      usuarioNome,
    });

    return mov;
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

module.exports = {
  transferirParaProducao,
  devolverAoEstoquePadrao,
  transferirEntreLinhas,
  listarEstoque,
  darBaixa,
  listarHistorico,
  excluirHistorico,
};