const prisma = require('../utils/prisma');

// ── include reutilizável ──────────────────────────────────────────────────────
const _includeMovimentacoes = {
  movimentacoes: {
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true,
          identificador: true, medida: true, espessura: true,
          especifico: true,
        },
      },
    },
    orderBy: { criadoEm: 'desc' },
  },
};

// ── Controle de Estoque: apenas OS EM_ANDAMENTO ───────────────────────────────
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

// ── Registrar movimentação ────────────────────────────────────────────────────
async function registrarMovimentacao({
  materialId, tipo, quantidade, numeroOS,
  precoUnitario, precoM2, observacao, ordemCompraId, descricaoItem,
}) {
  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };

  // Verifica se OS não está fechada (busca a mais recente com esse numeroOS)
  const relacaoExistente = await prisma.relacaoOS.findFirst({
    where:   { numeroOS },
    orderBy: { criadoEm: 'desc' },
  });
  if (relacaoExistente?.status === 'FECHADA') {
    throw { status: 400, message: `A OS ${numeroOS} está fechada e não aceita novas movimentações` };
  }

  // Material específico: descricaoItem obrigatória
  if (material.especifico) {
    const desc = (descricaoItem ?? '').trim();
    if (!desc) {
      throw { status: 400, message: 'Materiais específicos exigem uma descrição para movimentação de estoque' };
    }
  }

  if (tipo === 'SAIDA') {
    if (material.especifico) {
      // Verifica saldo do filho específico
      const desc  = (descricaoItem ?? '').trim();
      const filho = await prisma.estoqueEspecifico.findUnique({
        where: { materialId_descricao: { materialId, descricao: desc } },
      });
      const saldoFilho = filho ? Number(filho.quantidade) : 0;
      if (saldoFilho < quantidade) {
        throw {
          status: 400,
          message: `Estoque insuficiente para "${desc}": disponível ${saldoFilho} ${material.unidade ?? ''}`.trim(),
        };
      }
    } else {
      const saldo = Number(material.quantidade);
      if (saldo < quantidade) {
        throw {
          status: 400,
          message: `Estoque insuficiente: disponível ${saldo} ${material.unidade ?? ''}`.trim(),
        };
      }
    }
  }

  const delta = tipo === 'ENTRADA' ? quantidade : -quantidade;

  // OS numérica → mescla na RelacaoOS existente; OS textual → reutiliza a aberta existente
  // ou cria nova se vier de movimentação manual sem relação prévia
  const osEhNumerica = /^\d+$/.test(numeroOS);
  // OS "com sufixo" = já tem #OC..., #S... ou #E... → veio de uma sessão com sufixo gerado pelo cliente
  const osTemSufixo  = /#(OC|S|E)/.test(numeroOS);
  let relacao;

  if (osEhNumerica || osTemSufixo) {
    // OS numérica ou com sufixo: upsert garante uma única relação por chave
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS },
      create: { numeroOS, status: 'EM_ANDAMENTO' },
      update: {},
    });
  } else {
    // OS textual sem sufixo: o cliente deveria ter adicionado um sufixo antes de
    // enviar o lote. Chegando aqui sem sufixo (chamada avulsa), cria uma relação
    // nova com sufixo de timestamp para não misturar com outras relações dessa OS.
    const sufixo = tipo === 'SAIDA' ? `#S${Date.now()}` : `#E${Date.now()}`;
    const numeroOSComSufixo = `${numeroOS}${sufixo}`;
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS: numeroOSComSufixo },
      create: { numeroOS: numeroOSComSufixo, status: 'EM_ANDAMENTO' },
      update: {},
    });
  }

  // Cria a movimentação
  const [movimentacao] = await prisma.$transaction([
    prisma.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo,
        quantidade,
        numeroOS,
        relacaoOSId:   relacao.id,
        precoUnitario: precoUnitario ?? null,
        precoM2:       precoM2       ?? null,
        observacao:    observacao    ?? null,
        ordemCompraId: ordemCompraId ?? null,
        descricaoItem: descricaoItem ?? null,
      },
    }),
    // Para material normal: atualiza quantidade direta; para específico: será feito abaixo
    ...(material.especifico
      ? []
      : [
          prisma.material.update({
            where: { id: materialId },
            data:  { quantidade: { increment: delta } },
          }),
        ]),
  ]);

  if (material.especifico) {
    // Atualiza ou cria filho em EstoqueEspecifico
    const desc = (descricaoItem ?? '').trim();
    if (tipo === 'ENTRADA') {
      await prisma.estoqueEspecifico.upsert({
        where:  { materialId_descricao: { materialId, descricao: desc } },
        create: { materialId, descricao: desc, quantidade },
        update: { quantidade: { increment: Number(quantidade) } },
      });
    } else {
      const filho    = await prisma.estoqueEspecifico.findUnique({
        where: { materialId_descricao: { materialId, descricao: desc } },
      });
      const novaQtd  = Math.max(0, Number(filho?.quantidade ?? 0) - Number(quantidade));
      if (novaQtd === 0) {
        await prisma.estoqueEspecifico.delete({
          where: { materialId_descricao: { materialId, descricao: desc } },
        });
      } else {
        await prisma.estoqueEspecifico.update({
          where: { materialId_descricao: { materialId, descricao: desc } },
          data:  { quantidade: novaQtd },
        });
      }
    }
    // Não recalcula status de material específico (ele não tem quantidade própria)
  } else {
    // Recalcula status do material normal
    const atualizado = await prisma.material.findUnique({ where: { id: materialId } });
    const novoStatus = _calcularStatus(atualizado.quantidade, atualizado.estoqueMinimo, atualizado.ativo);
    await prisma.material.update({ where: { id: materialId }, data: { status: novoStatus } });
  }

  return movimentacao;
}

// ── Remover movimentação ──────────────────────────────────────────────────────
async function removerMovimentacao(movimentacaoId) {
  const mov = await prisma.movimentacaoEstoque.findUnique({ where: { id: movimentacaoId } });
  if (!mov) throw { status: 404, message: 'Movimentação não encontrada' };

  // Busca a relação pelo id que está na própria movimentação (sempre preciso)
  const relacao = await prisma.relacaoOS.findUnique({ where: { id: mov.relacaoOSId } });
  if (relacao?.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível remover movimentações de uma OS fechada' };
  }

  const material = await prisma.material.findUnique({ where: { id: mov.materialId } });

  // Reverte o delta
  const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

  if (material?.especifico) {
    // Reverte no filho EstoqueEspecifico
    await prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } });

    const desc = (mov.descricaoItem ?? '').trim();
    if (desc) {
      const filho   = await prisma.estoqueEspecifico.findUnique({
        where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
      });
      const novaQtd = Math.max(0, Number(filho?.quantidade ?? 0) + delta);
      if (novaQtd === 0) {
        await prisma.estoqueEspecifico.delete({
          where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
        });
      } else {
        await prisma.estoqueEspecifico.upsert({
          where:  { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
          create: { materialId: mov.materialId, descricao: desc, quantidade: Math.max(0, delta) },
          update: { quantidade: novaQtd },
        });
      }
    }
  } else {
    await prisma.$transaction([
      prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } }),
      prisma.material.update({
        where: { id: mov.materialId },
        data:  { quantidade: { increment: delta } },
      }),
    ]);

    const mat      = await prisma.material.findUnique({ where: { id: mov.materialId } });
    const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
    await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
  }

  // Se a RelacaoOS ficou sem movimentações, exclui ela
  const count = await prisma.movimentacaoEstoque.count({ where: { relacaoOSId: relacao.id } });
  if (count === 0) {
    await prisma.relacaoOS.delete({ where: { id: relacao.id } });
    return { relacaoExcluida: true };
  }

  return { relacaoExcluida: false };
}

// ── Excluir RelacaoOS inteira ─────────────────────────────────────────────────
// Recebe o id da RelacaoOS (não o numeroOS) para identificar unicamente a relação,
// já que OS textuais podem ter múltiplas relações com o mesmo numeroOS.
async function excluirRelacaoOS(relacaoOSId) {
  const relacao = await prisma.relacaoOS.findUnique({
    where:   { id: relacaoOSId },
    include: { movimentacoes: { include: { material: true } } },
  });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível excluir uma OS fechada' };
  }

  // Reverte todas as movimentações
  for (const mov of relacao.movimentacoes) {
    const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

    if (mov.material?.especifico) {
      const desc = (mov.descricaoItem ?? '').trim();
      if (desc) {
        const filho   = await prisma.estoqueEspecifico.findUnique({
          where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
        });
        const novaQtd = Math.max(0, Number(filho?.quantidade ?? 0) + delta);
        if (novaQtd === 0) {
          await prisma.estoqueEspecifico.delete({
            where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
          }).catch(() => {}); // ignora se não existia
        } else {
          await prisma.estoqueEspecifico.upsert({
            where:  { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
            create: { materialId: mov.materialId, descricao: desc, quantidade: novaQtd },
            update: { quantidade: novaQtd },
          });
        }
      }
    } else {
      await prisma.material.update({
        where: { id: mov.materialId },
        data:  { quantidade: { increment: delta } },
      });
      const mat = await prisma.material.findUnique({ where: { id: mov.materialId } });
      const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
      await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
    }
  }

  await prisma.movimentacaoEstoque.deleteMany({ where: { relacaoOSId: relacao.id } });
  await prisma.relacaoOS.delete({ where: { id: relacao.id } });
}

// ── Fechar OS ─────────────────────────────────────────────────────────────────
// Recebe o id da RelacaoOS para identificar unicamente a relação.
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

// ── Helpers ───────────────────────────────────────────────────────────────────
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

module.exports = {
  listarEmAndamento,
  buscarPorNumeroOS,
  registrarMovimentacao,
  removerMovimentacao,
  excluirRelacaoOS,
  fecharOS,
  listarTodas,
};