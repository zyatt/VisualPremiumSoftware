const prisma = require('../utils/prisma');
const materialSvc = require('./material.service');

const _includeMovimentacoes = {
  movimentacoes: {
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true,
          identificador: true, medida: true, espessura: true,
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
        message: `Estoque insuficiente: disponível ${saldo} ${material.unidade ?? ''}`.trim(),
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
    const _d   = new Date();
    const hoje = `${String(_d.getDate()).padStart(2,'0')}-${String(_d.getMonth()+1).padStart(2,'0')}-${_d.getFullYear()}`;

    const relacaoAberta = await prisma.relacaoOS.findFirst({
      where: {
        status:   'EM_ANDAMENTO',
        OR: [
          { numeroOS: numeroOS },
          { numeroOS: { startsWith: `${numeroOS}-${hoje}` } },
        ],
      },
      orderBy: { criadoEm: 'asc' },
    });

    if (relacaoAberta) {
      relacao = relacaoAberta;
    } else {
      let candidato  = `${numeroOS}-${hoje}`;
      let sufixoSeq  = 1;

      while (true) {
        const existente = await prisma.relacaoOS.findUnique({ where: { numeroOS: candidato } });
        if (!existente) {
          relacao = await prisma.relacaoOS.create({ data: { numeroOS: candidato, status: 'EM_ANDAMENTO' } });
          break;
        }
        if (existente.status !== 'FECHADA') {
          relacao = existente;
          break;
        }
        sufixoSeq += 1;
        candidato = `${numeroOS}-${hoje}-${sufixoSeq}`;
      }
    }
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

  await prisma.$transaction([
    prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } }),
    prisma.material.update({
      where: { id: mov.materialId },
      data:  { quantidade: { increment: delta } },
    }),
    ...(retalhoParaReverter
      ? [prisma.material.update({
          where: { id: retalhoParaReverter.id },
          data:  { quantidade: { decrement: retalhoParaReverter.areaRetalho } },
        })]
      : []),
  ]);

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

  for (const mov of relacao.movimentacoes) {
    const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

    const statusAntes = mov.material?.status
      ?? (await prisma.material.findUnique({ where: { id: mov.materialId } }))?.status;

    await prisma.material.update({
      where: { id: mov.materialId },
      data:  { quantidade: { increment: delta } },
    });
    const mat = await prisma.material.findUnique({ where: { id: mov.materialId } });
    const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
    await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
    materialSvc.notificarSeCritico(statusAntes, { ...mat, status: novoStatus });
  }

  await prisma.movimentacaoEstoque.deleteMany({ where: { relacaoOSId: relacao.id } });
  await prisma.relacaoOS.delete({ where: { id: relacao.id } });
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
};