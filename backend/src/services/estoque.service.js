const prisma = require('../utils/prisma');

// ── include reutilizável ──────────────────────────────────────────────────────
const _includeMovimentacoes = {
  movimentacoes: {
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true,
          identificador: true, medida: true, espessura: true,
          especifico: true, qtdPadrao: true, unidPadrao: true,
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
  
  const osEhNumerica = /^\d+$/.test(numeroOS);
  const osTemSufixo  = /#(OC|S|E)/.test(numeroOS);
  // Verifica se OS não está fechada (busca a mais recente com esse numeroOS)
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

  // Resolve qual RelacaoOS usar:
  // 1. OS numérica ou com sufixo (#OC/#S/#E): upsert direto pelo numeroOS exato.
  // 2. OS textual sem sufixo: verifica se já existe uma RelacaoOS EM_ANDAMENTO
  //    com esse numeroOS (ex: criada pela produção). Se existir, reutiliza.
  //    Só cria nova com sufixo de timestamp quando não houver nenhuma aberta.
  
  let relacao;

  if (osEhNumerica || osTemSufixo) {
    // OS numérica ou com sufixo: upsert garante uma única relação por chave exata
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS },
      create: { numeroOS, status: 'EM_ANDAMENTO' },
      update: {},
    });
  } else {
    // OS textual sem sufixo: tenta reutilizar RelacaoOS EM_ANDAMENTO existente
    // (inclui a OS com o nome exato OU com sufixo de data do dia de hoje)
    const _d   = new Date();
    const hoje = `${String(_d.getDate()).padStart(2,'0')}-${String(_d.getMonth()+1).padStart(2,'0')}-${_d.getFullYear()}`; // "DD-MM-YYYY"

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
      // Já existe uma OS aberta com esse nome (ou com sufixo de data de hoje) — reutiliza
      relacao = relacaoAberta;
    } else {
      // Não existe nenhuma aberta: cria nova com sufixo de data (mesmo padrão do producao_service)
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
  // ── Custo por unidade menor ───────────────────────────────────────────────
  // Se o material tem qtdPadrao (ex: thinner 18 L = 18000 ml), o precoUnitario
  // registrado no estoque deve ser o custo por unidade menor (R$/ml, R$/m etc.).
  // O front envia o precoUnitarioSugerido que já vem do campo ultimoValorPago
  // do material — que é o custo por unidade menor gravado pela OC.
  // Portanto, para movimentações manuais, apenas repassamos o valor sem alterar.
  // O único ajuste necessário é: se o front ainda não tiver o custo por unidade
  // menor disponível (ex: primeiro uso, sem OC prévia) e enviar o preço de
  // embalagem com o flag `precoEhEmbalagem: true`, aí dividimos aqui.
  // Na prática, o front passa item.precoUnitarioSugerido = material.ultimoValorPago
  // que a OC já gravou como custo/unidade — logo não é necessário dividir novamente.
  const precoUnitarioFinal = precoUnitario ?? null;

  // Cria a movimentação
  const [movimentacao] = await prisma.$transaction([
    prisma.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo,
        quantidade,
        numeroOS,
        relacaoOSId:   relacao.id,
        precoUnitario: precoUnitarioFinal,
        precoM2:       precoM2 ?? null,
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

// ── Atualizar preço de uma movimentação existente ─────────────────────────────
// Permite corrigir o custo de uma movimentação sem precisar removê-la e
// recriá-la. A OS deve estar EM_ANDAMENTO.
async function atualizarPrecoMovimentacao(movimentacaoId, { precoUnitario, precoM2 }) {
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

  return prisma.movimentacaoEstoque.update({
    where: { id: movimentacaoId },
    data,
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true,
          identificador: true, medida: true, espessura: true,
          especifico: true,
        },
      },
    },
  });
}

// ── Renomear OS ───────────────────────────────────────────────────────────────
async function renomearOS(id, novoNumeroOS) {
  const novoNome = (novoNumeroOS ?? '').trim().toUpperCase();
  if (!novoNome) throw { status: 400, message: 'Nome da OS não pode ser vazio' };

  const relacao = await prisma.relacaoOS.findUnique({ where: { id } });
  if (!relacao) throw { status: 404, message: 'OS não encontrada' };

  // Garante que não existe outra RelacaoOS com o mesmo nome
  const conflito = await prisma.relacaoOS.findUnique({ where: { numeroOS: novoNome } });
  if (conflito && conflito.id !== id) {
    throw { status: 409, message: `Já existe uma OS com o nome "${novoNome}"` };
  }

  // Atualiza o nome na RelacaoOS
  const atualizada = await prisma.relacaoOS.update({
    where: { id },
    data:  { numeroOS: novoNome },
    include: _includeMovimentacoes,
  });

  // Sincroniza o campo numeroOS em todas as movimentações vinculadas
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