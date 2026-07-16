const prisma = require('../utils/prisma');

// Formata a unidade para exibição em mensagens ao usuário (o valor salvo no
// banco permanece em maiúsculo). Ex.: 'M/L' → 'm/l'; 'ML' → 'ml'; 'M²'/'M2'
// → 'm²'; 'KG' → 'Kg'; 'G' → 'g'. Espelha `formatarUnidadeExibicao` do app.
function formatUnidade(unidade) {
  if (!unidade || !unidade.trim()) return '';
  const u = unidade.trim().toUpperCase();
  switch (u) {
    case 'UNIDADE': return 'Unidade';
    case 'M/L':     return 'm/l';
    case 'M':       return 'm';
    case 'ML':      return 'ml';
    case 'M²':
    case 'M2':      return 'm²';
    case 'KG':      return 'Kg';
    case 'G':       return 'g';
    default:        return unidade;
  }
}
const materialSvc = require('./material.service');

const _includeMovimentacoes = {
  movimentacoes: {
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true,
          identificador: true, medida: true, espessura: true,
          largura: true, comprimento: true,
        },
      },
      materialOrigem: {
        select: { id: true, nome: true },
      },
    },
    orderBy: { criadoEm: 'desc' },
  },
};

async function listarEmAndamento(busca) {
  const where = { status: 'EM_ANDAMENTO' };
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: _includeMovimentacoes,
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarPorNumeroOS(numeroOS) {
  return prisma.relacaoOS.findFirst({
    where:   { numeroOS },
    orderBy: { criadoEm: 'desc' },
    include: _includeMovimentacoes,
  });
}

/**
 * Resolve (ou cria) uma RelacaoOS para OS descritivas (não-numéricas, sem sufixo
 * #OC/#S/#E). Aplica data automática no nome: "NOME-DD-MM-YYYY".
 *
 * Regras:
 *  - Se já existir uma relação EM_ANDAMENTO com esse nome-base ou nome-base+hoje,
 *    reutiliza ela (acumula movimentações do dia).
 *  - Se não existir, cria "NOME-DD-MM-YYYY". Se já estiver FECHADA, acrescenta
 *    sufixo sequencial: "NOME-DD-MM-YYYY-2", "-3", etc.
 *
 * Exportada para que outros serviços (ex: estoqueProducao.service.js) possam
 * reutilizar a mesma lógica sem duplicação.
 */
async function resolverRelacaoOSDescritiva(nomeBase) {
  const _d   = new Date();
  const hoje = `${String(_d.getDate()).padStart(2,'0')}-${String(_d.getMonth()+1).padStart(2,'0')}-${_d.getFullYear()}`;

  const relacaoAberta = await prisma.relacaoOS.findFirst({
    where: {
      status: 'EM_ANDAMENTO',
      OR: [
        { numeroOS: nomeBase },
        { numeroOS: { startsWith: `${nomeBase}-${hoje}` } },
      ],
    },
    orderBy: { criadoEm: 'asc' },
  });

  if (relacaoAberta) return relacaoAberta;

  let candidato = `${nomeBase}-${hoje}`;
  let sufixoSeq = 1;

  while (true) {
    const existente = await prisma.relacaoOS.findUnique({ where: { numeroOS: candidato } });
    if (!existente) {
      return prisma.relacaoOS.create({ data: { numeroOS: candidato, status: 'EM_ANDAMENTO' } });
    }
    if (existente.status !== 'FECHADA') return existente;
    sufixoSeq += 1;
    candidato = `${nomeBase}-${hoje}-${sufixoSeq}`;
  }
}

async function registrarMovimentacao({
  materialId, tipo, quantidade, numeroOS,
  precoUnitario, precoM2, observacao, ordemCompraId, descricaoItem,
  larguraUsada, comprimentoUsado,
  materialOrigemId,
  usuarioNome,
}) {
  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };
  
  const osEhNumerica = /^\d+$/.test(numeroOS);
  const osTemSufixo  = /#(OC|S|E)/.test(numeroOS);
  if (osEhNumerica) {
    const relacaoExistente = await prisma.relacaoOS.findFirst({
      where: { numeroOS },
      orderBy: { criadoEm: 'desc' },
    });

    if (relacaoExistente?.status === 'FECHADA') {
      throw {
        status: 400,
        message: `A OS ${numeroOS} está fechada e não aceita novas movimentações`,
      };
    }
  }

  if (tipo === 'SAIDA') {
    const saldo = Number(material.quantidade);
    if (saldo < quantidade) {
      throw {
        status: 400,
        message: `Estoque insuficiente: disponível ${saldo} ${formatUnidade(material.unidade)}`.trim(),
      };
    }
  }

  const delta = tipo === 'ENTRADA' ? quantidade : -quantidade;

  let relacao;

  if (osEhNumerica || osTemSufixo) {
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS },
      create: { numeroOS, status: 'EM_ANDAMENTO' },
      update: {},
    });
  } else {
    relacao = await resolverRelacaoOSDescritiva(numeroOS);
  }
  const precoUnitarioFinal = precoUnitario ?? null;

  const _unidadeMat = (material.unidade ?? '').toLowerCase().trim();
  const _eMetroLinear = ['m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'].includes(_unidadeMat);

  let precoM2Final = precoM2 ?? null;
  if (
    tipo === 'SAIDA' &&
    !_eMetroLinear &&
    larguraUsada != null && comprimentoUsado != null &&
    material.largura != null && material.comprimento != null
  ) {
    const larg      = Number(larguraUsada);
    const comp      = Number(comprimentoUsado);
    const largTotal = Number(material.largura);
    const compTotal = Number(material.comprimento);

    if (larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0) {
      const areaUsada = larg * comp;
      const areaTotal = largTotal * compTotal;
      const custoM2 = precoM2 != null
        ? Number(precoM2)
        : (precoUnitario != null && areaTotal > 0
            ? Number(precoUnitario) / areaTotal
            : null);
      if (custoM2 != null) {
        precoM2Final = Math.round(custoM2 * areaUsada * 1000000) / 1000000;
      }
    }
  }

  const obsAutomatica = `${tipo === 'SAIDA' ? 'Saída' : 'Entrada'} via controle de estoque – ${usuarioNome ?? 'Usuário'}`;
  const obsFinal = (observacao && observacao.trim())
    ? `${obsAutomatica}\n${observacao.trim()}`
    : obsAutomatica;

  const [movimentacao] = await prisma.$transaction([
    prisma.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo,
        quantidade,
        numeroOS,
        relacaoOSId:      relacao.id,
        precoUnitario:    precoUnitarioFinal,
        precoM2:          precoM2Final,
        observacao:       obsFinal,
        ordemCompraId:    ordemCompraId ?? null,
        descricaoItem:    descricaoItem ?? null,
        larguraUsada:     (larguraUsada    != null ? Number(larguraUsada)    : null),
        comprimentoUsado: (comprimentoUsado != null ? Number(comprimentoUsado) : null),
        materialOrigemId: materialOrigemId ?? null,
      },
    }),
    prisma.material.update({
      where: { id: materialId },
      data:  { quantidade: { increment: delta } },
    }),
    prisma.relacaoOS.update({
      where: { id: relacao.id },
      data:  { atualizadoEm: new Date() },
    }),
  ]);

  const atualizado = await prisma.material.findUnique({ where: { id: materialId } });
  const novoStatus = _calcularStatus(atualizado.quantidade, atualizado.estoqueMinimo, atualizado.ativo);
  await prisma.material.update({ where: { id: materialId }, data: { status: novoStatus } });
  materialSvc.notificarSeCritico(material.status, { ...atualizado, status: novoStatus });

  if (
    tipo === 'SAIDA' &&
    larguraUsada != null && comprimentoUsado != null &&
    material.largura != null && material.comprimento != null
  ) {
    const larg      = Number(larguraUsada);
    const comp      = Number(comprimentoUsado);
    const largTotal = Number(material.largura);
    const compTotal = Number(material.comprimento);

    if (larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0) {
      const areaTotal   = largTotal * compTotal;
      const areaUsada   = larg * comp;
      const areaRetalho = Math.round((areaTotal - areaUsada) * 10000) / 10000;

      if (areaRetalho > 0.0001) {
        let retalhoMat = await prisma.material.findFirst({
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
            const areaUsada = Number(larguraUsada) * Number(comprimentoUsado);
            if (areaUsada > 0) return precoM2Final / areaUsada;
          }
          const pu = precoUnitario != null ? Number(precoUnitario) : null;
          const areaT = Number(material.largura) * Number(material.comprimento);
          if (pu != null && pu > 0 && areaT > 0) return pu / areaT;
          return material.ultimoValorPagoM2 != null ? Number(material.ultimoValorPagoM2) : null;
        })();

        if (!retalhoMat) {
          try {
            retalhoMat = await prisma.material.create({
              data: {
                nome:              material.nome,
                unidade:           'M²',
                categoria:         material.categoria   ?? null,
                medida:            null,
                espessura:         material.espessura   ?? null,
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
              retalhoMat = await prisma.material.findFirst({
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
              await prisma.material.update({
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
          await prisma.material.update({
            where: { id: retalhoMat.id },
            data: {
              quantidade:        novaQtd,
              status:            _calcularStatus(novaQtd, Number(retalhoMat.estoqueMinimo), retalhoMat.ativo),
              ultimoValorPago:   null,
              ...(custoM2Retalho != null ? { ultimoValorPagoM2: custoM2Retalho } : {}),
            },
          });
        }
      }
    }
  }

  return movimentacao;
}

async function removerMovimentacao(movimentacaoId) {
  const mov = await prisma.movimentacaoEstoque.findUnique({ where: { id: movimentacaoId } });
  if (!mov) throw { status: 404, message: 'Movimentação não encontrada' };

  const relacao = await prisma.relacaoOS.findUnique({ where: { id: mov.relacaoOSId } });
  if (relacao?.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível remover movimentações de uma OS fechada' };
  }

  const material = await prisma.material.findUnique({ where: { id: mov.materialId } });

  const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

  // Se esta SAÍDA usou o modo dimensional (larguraUsada/comprimentoUsado),
  // ela pode ter gerado/incrementado um material RETALHO com a área
  // sobrante (ver registrarMovimentacao). Ao excluir a movimentação,
  // essa área precisa ser revertida do retalho também — senão o retalho
  // fica com uma quantidade "fantasma" que nunca existiu.
  let retalhoParaReverter = null;
  if (
    mov.tipo === 'SAIDA' &&
    mov.larguraUsada != null && mov.comprimentoUsado != null &&
    material?.largura != null && material?.comprimento != null
  ) {
    const larg      = Number(mov.larguraUsada);
    const comp      = Number(mov.comprimentoUsado);
    const largTotal = Number(material.largura);
    const compTotal = Number(material.comprimento);

    if (larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0) {
      const areaTotal   = largTotal * compTotal;
      const areaUsada   = larg * comp;
      const areaRetalho = Math.round((areaTotal - areaUsada) * 10000) / 10000;

      if (areaRetalho > 0.0001) {
        const retalhoMat = await prisma.material.findFirst({
          where: {
            nome:          { equals: material.nome, mode: 'insensitive' },
            identificador: { equals: 'RETALHO',    mode: 'insensitive' },
            espessura:     material.espessura
              ? { equals: material.espessura, mode: 'insensitive' }
              : null,
          },
        });
        if (retalhoMat) {
          retalhoParaReverter = { id: retalhoMat.id, areaRetalho };
        }
      }
    }
  }

  // Se a movimentação removida é uma SAÍDA vinculada a uma OS de
  // transferência para produção (numeroOS começa com 'TRANSFERENCIA-PRODUCAO'),
  // precisa também decrementar o EstoqueProducao — a quantidade que havia
  // entrado lá ao fazer a transferência deixa de existir.
  const ehTransferenciaProducao =
    mov.tipo === 'SAIDA' &&
    (mov.numeroOS ?? '').startsWith('TRANSFERENCIA-PRODUCAO');

  // Se a movimentação removida é a SAÍDA de registro/relatório gerada
  // automaticamente quando uma solicitação de Produção é finalizada
  // (ver _registrarSaidaControleEstoque em producao.service.js), essa
  // saída NUNCA decrementou o estoque normal — o material já havia saído
  // do estoque normal antes, na transferência para o EstoqueProducao, e
  // foi consumido de lá. Deletar essa movimentação, portanto, não deve
  // devolver quantidade ao estoque normal; deve devolver ao EstoqueProducao,
  // de onde ela realmente foi baixada.
  const ehSaidaDeProducao =
    mov.tipo === 'SAIDA' &&
    /^(Saída via produção|Baixa do estoque de produção)/i.test((mov.observacao ?? '').trim());

  await prisma.$transaction([
    prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } }),
    // Para saídas originadas da Produção, NÃO mexe em material.quantidade
    // (estoque normal) — o saldo correto a reverter é o do EstoqueProducao.
    ...(ehSaidaDeProducao
      ? []
      : [prisma.material.update({
          where: { id: mov.materialId },
          data:  { quantidade: { increment: delta } },
        })]),
    ...(retalhoParaReverter
      ? [prisma.material.update({
          where: { id: retalhoParaReverter.id },
          data:  { quantidade: { decrement: retalhoParaReverter.areaRetalho } },
        })]
      : []),
    // Reverte o saldo no EstoqueProducao se for uma transferência desfeita.
    // Usa Math.max(0) via update condicional — se o saldo já tiver sido
    // consumido por baixas posteriores, protege contra negativo fazendo
    // um segundo update logo após a transaction.
    ...(ehTransferenciaProducao
      ? [prisma.estoqueProducao.updateMany({
          where: { materialId: mov.materialId },
          data:  { quantidade: { decrement: Number(mov.quantidade) } },
        }),
         prisma.movimentacaoProducao.create({
          data: {
            materialId:  mov.materialId,
            tipo:       'BAIXA',
            quantidade:  Number(mov.quantidade),
            observacao:  'Estorno automático: transferência removida do controle de estoque',
            usuarioNome: null,
          },
        })]
      : []),
    // Devolve a quantidade ao EstoqueProducao (não ao estoque normal) quando
    // a saída removida é a de registro de uma baixa de produção.
    ...(ehSaidaDeProducao
      ? [prisma.estoqueProducao.upsert({
          where:  { materialId: mov.materialId },
          create: { materialId: mov.materialId, quantidade: Number(mov.quantidade) },
          update: { quantidade: { increment: Number(mov.quantidade) } },
        }),
         prisma.movimentacaoProducao.create({
          data: {
            materialId:  mov.materialId,
            tipo:        'TRANSFERENCIA',
            quantidade:  Number(mov.quantidade),
            numeroOS:    mov.numeroOS ?? null,
            observacao:  'Estorno automático: saída removida do controle de estoque',
            usuarioNome: null,
          },
        })]
      : []),
  ]);

  // Protege EstoqueProducao contra quantidade negativa (caso o material já
  // tenha sido parcialmente ou totalmente consumido por baixas antes da
  // remoção da transferência).
  if (ehTransferenciaProducao) {
    const ep = await prisma.estoqueProducao.findUnique({ where: { materialId: mov.materialId } });
    if (ep && Number(ep.quantidade) < 0) {
      await prisma.estoqueProducao.update({
        where: { materialId: mov.materialId },
        data:  { quantidade: 0 },
      });
    }
  }

  const mat      = await prisma.material.findUnique({ where: { id: mov.materialId } });
  const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
  await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
  materialSvc.notificarSeCritico(material.status, { ...mat, status: novoStatus });

  if (retalhoParaReverter) {
    const retalhoMatAntes = await prisma.material.findUnique({ where: { id: retalhoParaReverter.id } });
    // Protege contra quantidade negativa caso o retalho já tenha sido
    // parcialmente consumido por outras movimentações antes da exclusão.
    const qtdFinal = Math.max(0, Number(retalhoMatAntes.quantidade));
    const statusRetalho = _calcularStatus(qtdFinal, Number(retalhoMatAntes.estoqueMinimo), retalhoMatAntes.ativo);
    await prisma.material.update({
      where: { id: retalhoParaReverter.id },
      data:  { quantidade: qtdFinal, status: statusRetalho },
    });
    materialSvc.notificarSeCritico(retalhoMatAntes.status, { ...retalhoMatAntes, quantidade: qtdFinal, status: statusRetalho });
  }

  const count = await prisma.movimentacaoEstoque.count({ where: { relacaoOSId: relacao.id } });
  if (count === 0) {
    await prisma.relacaoOS.delete({ where: { id: relacao.id } });
    return { relacaoExcluida: true };
  }

  await prisma.relacaoOS.update({
    where: { id: relacao.id },
    data:  { atualizadoEm: new Date() },
  });

  return { relacaoExcluida: false };
}

async function excluirRelacaoOS(relacaoOSId) {
  const relacao = await prisma.relacaoOS.findUnique({
    where:   { id: relacaoOSId },
    include: { movimentacoes: { include: { material: true } } },
  });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível excluir uma OS fechada' };
  }

  // Acumula quanto precisa ser revertido do EstoqueProducao por material
  // (pode haver múltiplas transferências/baixas do mesmo material na mesma OS).
  // - TRANSFERENCIA-PRODUCAO desfeita: registra como BAIXA no histórico de produção
  //   (a transferência que teria entrado lá é estornada).
  // - Saída de produção desfeita: registra como TRANSFERENCIA no histórico de produção
  //   (a quantidade volta a ficar disponível no estoque de produção, de onde saiu).
  const estornoProducaoTransferencia = new Map(); // materialId → qtd a decrementar (BAIXA)
  const estornoProducaoBaixa         = new Map(); // materialId → qtd a incrementar (TRANSFERENCIA)

  for (const mov of relacao.movimentacoes) {
    const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

    // Se esta SAÍDA é o registro/relatório automático de uma baixa feita a
    // partir do Estoque de Produção (ver _registrarSaidaControleEstoque em
    // producao.service.js), ela NUNCA decrementou o estoque normal — o
    // material já havia saído dele na transferência anterior. Excluir a OS,
    // portanto, não deve devolver quantidade ao estoque normal; deve
    // devolver ao EstoqueProducao, de onde ela realmente foi baixada.
    const ehSaidaDeProducao =
      mov.tipo === 'SAIDA' &&
      /^(Saída via produção|Baixa do estoque de produção)/i.test((mov.observacao ?? '').trim());

    const statusAntes = mov.material?.status
      ?? (await prisma.material.findUnique({ where: { id: mov.materialId } }))?.status;

    if (!ehSaidaDeProducao) {
      await prisma.material.update({
        where: { id: mov.materialId },
        data:  { quantidade: { increment: delta } },
      });
      const mat = await prisma.material.findUnique({ where: { id: mov.materialId } });
      const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
      await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
      materialSvc.notificarSeCritico(statusAntes, { ...mat, status: novoStatus });
    }

    // Marca para reverter no EstoqueProducao se for uma transferência desfeita.
    if (
      mov.tipo === 'SAIDA' &&
      (mov.numeroOS ?? '').startsWith('TRANSFERENCIA-PRODUCAO')
    ) {
      const acumulado = estornoProducaoTransferencia.get(mov.materialId) ?? 0;
      estornoProducaoTransferencia.set(mov.materialId, acumulado + Number(mov.quantidade));
    }

    // Marca para devolver ao EstoqueProducao se for uma saída de produção desfeita.
    if (ehSaidaDeProducao) {
      const acumulado = estornoProducaoBaixa.get(mov.materialId) ?? 0;
      estornoProducaoBaixa.set(mov.materialId, acumulado + Number(mov.quantidade));
    }
  }

  await prisma.movimentacaoEstoque.deleteMany({ where: { relacaoOSId: relacao.id } });
  await prisma.relacaoOS.delete({ where: { id: relacao.id } });

  // Reverte EstoqueProducao para cada material afetado por transferências
  // desfeitas e registra estorno no histórico de produção. Protege contra
  // negativo caso o material já tenha sido parcialmente consumido por baixas.
  for (const [materialId, qtdEstorno] of estornoProducaoTransferencia) {
    await prisma.estoqueProducao.updateMany({
      where: { materialId },
      data:  { quantidade: { decrement: qtdEstorno } },
    });
    await prisma.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'BAIXA',
        quantidade: qtdEstorno,
        observacao: 'Estorno automático: OS de transferência excluída do controle de estoque',
        usuarioNome: null,
      },
    });
    // Protege contra negativo
    const ep = await prisma.estoqueProducao.findUnique({ where: { materialId } });
    if (ep && Number(ep.quantidade) < 0) {
      await prisma.estoqueProducao.update({
        where: { materialId },
        data:  { quantidade: 0 },
      });
    }
  }

  // Devolve ao EstoqueProducao a quantidade das saídas de produção desfeitas
  // (baixas feitas a partir do estoque de produção que estavam registradas
  // nesta OS excluída).
  for (const [materialId, qtdDevolver] of estornoProducaoBaixa) {
    await prisma.estoqueProducao.upsert({
      where:  { materialId },
      create: { materialId, quantidade: qtdDevolver },
      update: { quantidade: { increment: qtdDevolver } },
    });
    await prisma.movimentacaoProducao.create({
      data: {
        materialId,
        tipo:       'TRANSFERENCIA',
        quantidade: qtdDevolver,
        observacao: 'Estorno automático: OS excluída do controle de estoque',
        usuarioNome: null,
      },
    });
  }
}

async function fecharOS(relacaoOSId) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { id: relacaoOSId } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Esta OS já está fechada' };
  }

  return prisma.relacaoOS.update({
    where:   { id: relacaoOSId },
    data:    { status: 'FECHADA' },
    include: _includeMovimentacoes,
  });
}

function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q   = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

async function listarTodas(busca) {
  const where = {};
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: _includeMovimentacoes,
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function atualizarPrecoMovimentacao(movimentacaoId, { precoUnitario, precoM2 }, usuario) {
  const mov = await prisma.movimentacaoEstoque.findUnique({
    where:   { id: movimentacaoId },
    include: { relacaoOS: true },
  });
  if (!mov) throw { status: 404, message: 'Movimentação não encontrada' };
  if (mov.relacaoOS?.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível editar movimentações de uma OS fechada' };
  }

  const data = {};
  if (precoUnitario !== undefined) data.precoUnitario = precoUnitario != null && Number(precoUnitario) > 0 ? Number(precoUnitario) : null;
  if (precoM2       !== undefined) data.precoM2       = precoM2       != null && Number(precoM2)       > 0 ? Number(precoM2)       : null;

  if (Object.keys(data).length === 0) {
    throw { status: 400, message: 'Nenhum campo de preço informado' };
  }

  const _fmt = (v) => v != null ? `R$ ${Number(v).toFixed(6)}` : null;

  const auditEntries = [];

  if ('precoUnitario' in data) {
    auditEntries.push({
      materialId:  mov.materialId,
      acao:        'CUSTO_MANUAL',
      campo:       'Custo unit. (mov.)',
      valorAntes:  _fmt(mov.precoUnitario),
      valorDepois: _fmt(data.precoUnitario),
      usuarioId:   usuario?.id   ?? null,
      usuarioNome: usuario?.nome ?? null,
    });
  }

  if ('precoM2' in data) {
    auditEntries.push({
      materialId:  mov.materialId,
      acao:        'CUSTO_MANUAL',
      campo:       'Custo m² (mov.)',
      valorAntes:  _fmt(mov.precoM2),
      valorDepois: _fmt(data.precoM2),
      usuarioId:   usuario?.id   ?? null,
      usuarioNome: usuario?.nome ?? null,
    });
  }

  const [movimentacaoAtualizada] = await prisma.$transaction([
    prisma.movimentacaoEstoque.update({
      where: { id: movimentacaoId },
      data,
      include: {
        material: {
          select: {
            id: true, nome: true, unidade: true,
            identificador: true, medida: true, espessura: true,
          },
        },
      },
    }),
    ...auditEntries.map((entry) => prisma.auditLogMaterial.create({ data: entry })),
    prisma.relacaoOS.update({
      where: { id: mov.relacaoOSId },
      data:  { atualizadoEm: new Date() },
    }),
  ]);

  return movimentacaoAtualizada;
}

async function renomearOS(id, novoNumeroOS) {
  const novoNome = (novoNumeroOS ?? '').trim().toUpperCase();
  if (!novoNome) throw { status: 400, message: 'Nome da OS não pode ser vazio' };

  const relacao = await prisma.relacaoOS.findUnique({ where: { id } });
  if (!relacao) throw { status: 404, message: 'OS não encontrada' };

  const conflito = await prisma.relacaoOS.findUnique({ where: { numeroOS: novoNome } });
  if (conflito && conflito.id !== id) {
    throw { status: 409, message: `Já existe uma OS com o nome "${novoNome}"` };
  }

  const atualizada = await prisma.relacaoOS.update({
    where: { id },
    data:  { numeroOS: novoNome },
    include: _includeMovimentacoes,
  });

  await prisma.movimentacaoEstoque.updateMany({
    where: { relacaoOSId: id },
    data:  { numeroOS: novoNome },
  });

  return atualizada;
}

module.exports = {
  listarEmAndamento,
  buscarPorNumeroOS,
  registrarMovimentacao,
  removerMovimentacao,
  excluirRelacaoOS,
  fecharOS,
  listarTodas,
  renomearOS,
  atualizarPrecoMovimentacao,
  resolverRelacaoOSDescritiva,
};