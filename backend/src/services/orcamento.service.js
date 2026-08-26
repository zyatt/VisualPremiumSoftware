const prisma = require('../utils/prisma');
const { EventEmitter } = require('events');

const orcamentoEvents = new EventEmitter();
orcamentoEvents.setMaxListeners(0);

function emitir(tipo, payload) {
  orcamentoEvents.emit('evento', { tipo, ...payload });
}

const TRAVA_DURACAO_MS = 60 * 1000;

const _filasPorOrcamento = new Map();

function _enfileirar(orcamentoId, tarefa) {
  const anterior = _filasPorOrcamento.get(orcamentoId) || Promise.resolve();
  const atual = anterior
    .catch(() => {})
    .then(() => tarefa());
  _filasPorOrcamento.set(
    orcamentoId,
    atual.catch(() => {}),
  );
  return atual;
}

const _itensInclude = {
  itens: {
    include: {
      material: {
        select: {
          id: true,
          nome: true,
          unidade: true,
          categoria: true,
          medida: true,
          espessura: true,
          identificador: true,
          largura: true,
          comprimento: true,
        },
      },
      fornecedor: { select: { id: true, nomeFantasia: true } },
    },
  },
  aprovador: { select: { id: true, nome: true } },
  criador:   { select: { id: true, nome: true } },
};

async function listar(status) {
  const where = {};
  if (status) where.status = status;

  return prisma.orcamento.findMany({
    where,
    include: _itensInclude,
    orderBy: { criadoEm: 'desc' },
  });
}

function _semTravaExpirada(orcamento) {
  if (!orcamento) return orcamento;
  if (_travaAtivaEValida(orcamento)) return orcamento;
  return { ...orcamento, travaUsuarioId: null, travaUsuario: null };
}

async function listarAbertos() {
  const orcamentos = await prisma.orcamento.findMany({
    where: { status: 'ABERTO' },
    include: {
      criador: { select: { id: true, nome: true } },
      travaUsuario: { select: { id: true, nome: true } },
      itens: {
        select: {
          id: true,
          materialId: true,
          quantidade: true,
          qtdUnidade: true,
          precoUnitario: true,
          selecionado: true,
          material: {
            select: {
              id: true,
              nome: true,
              unidade: true,
              categoria: true,
              medida: true,
              espessura: true,
              identificador: true,
              largura: true,
              comprimento: true,
            },
          },
        },
      },
    },
    orderBy: { atualizadoEm: 'desc' },
  });
  return orcamentos.map(_semTravaExpirada);
}

async function buscarPorId(id) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id },
    include: {
      itens: {
        include: {
          material: {
            include: {
              // Não filtramos por `ativo: true` aqui na query: um vínculo
              // fornecedor-material inativo ainda precisa aparecer na tabela
              // comparativa se ele for o fornecedor já selecionado em algum
              // item deste orçamento. Filtrar no banco fazia a coluna do
              // fornecedor sumir assim que o orçamento era recarregado
              // (buscarPorId), mesmo com o item já salvo apontando pra ele.
              fornecedorMateriais: {
                include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
              },
            },
          },
          fornecedor: true,
        },
      },
      aprovador: { select: { id: true, nome: true } },
      criador: { select: { id: true, nome: true } },
      travaUsuario: { select: { id: true, nome: true } },
    },
  });

  if (orcamento) {
    for (const item of orcamento.itens || []) {
      const todos = item.material?.fornecedorMateriais;
      if (!Array.isArray(todos)) continue;

      // Mantém: vínculos ativos + o vínculo do fornecedor já escolhido no
      // item (mesmo que esteja inativo), pra ele nunca sumir da tabela.
      item.material.fornecedorMateriais = todos.filter(
        (fm) => fm.ativo || fm.fornecedorId === item.fornecedorId
      );
    }
  }

  return _semTravaExpirada(orcamento);
}

async function criar(titulo, criadorId) {
  const orc = await prisma.orcamento.create({
    data: { criadorId: criadorId ?? null },
  });
  const tituloFinal = titulo?.trim() ? titulo.trim() : `Orçamento #${orc.id}`;
  const criado = await prisma.orcamento.update({
    where: { id: orc.id },
    data: { titulo: tituloFinal },
    include: { criador: { select: { id: true, nome: true } } },
  });

  emitir('orcamento_criado', { orcamento: criado });

  return criado;
}

async function adicionarItem(
  orcamentoId, materialId, fornecedorId, quantidade, precoUnitario,
  { selecionado = false, descricaoItem = null, observacao = null, qtdUnidade = null, origemUsuarioId = null } = {}
  ) {
  return _enfileirar(orcamentoId, async () => {
    const fid = fornecedorId ?? null;

    const data = {
      fornecedorId: fid,
      quantidade,
      qtdUnidade: qtdUnidade ?? null,
      precoUnitario: precoUnitario ?? null,
      selecionado: selecionado ?? false,
      descricaoItem: descricaoItem ?? null,
      observacao: observacao ?? null,
    };

    let resultado;
    if (fid !== null) {
      resultado = await prisma.orcamentoItem.upsert({
        where: {
          orcamentoId_materialId_fornecedorId: {
            orcamentoId,
            materialId,
            fornecedorId: fid,
          },
        },
        update: data,
        create: { orcamentoId, materialId, ...data },
      });
    } else {
      resultado = await prisma.$transaction(async (tx) => {
        const linhas = await tx.$queryRaw`
          SELECT id FROM orcamento_itens
          WHERE "orcamentoId" = ${orcamentoId}
            AND "materialId" = ${materialId}
            AND "fornecedorId" IS NULL
          FOR UPDATE
        `;

        if (linhas.length > 0) {
          return tx.orcamentoItem.update({ where: { id: linhas[0].id }, data });
        }

        return tx.orcamentoItem.create({
          data: { orcamentoId, materialId, ...data },
        });
      });
    }

    emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });
    return resultado;
  });
}

async function removerItem(orcamentoId, itemId, origemUsuarioId = null) {
  return _enfileirar(orcamentoId, async () => {
    const resultado = await prisma.orcamentoItem.deleteMany({ where: { id: itemId, orcamentoId } });
    emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });
    return resultado;
  });
}

async function limparItens(orcamentoId, origemUsuarioId = null) {
  return _enfileirar(orcamentoId, async () => {
    const resultado = await prisma.orcamentoItem.deleteMany({ where: { orcamentoId } });
    emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });
    return resultado;
  });
}

async function atualizarItem(itemId, data, origemUsuarioId = null) {
  const atual = await prisma.orcamentoItem.findUnique({
    where: { id: itemId },
    select: { orcamentoId: true },
  });
  if (!atual) {
    throw { status: 404, message: 'Item do orçamento não encontrado.' };
  }
  return _enfileirar(atual.orcamentoId, async () => {
    const item = await prisma.orcamentoItem.update({ where: { id: itemId }, data });
    emitir('orcamento_item_alterado', { orcamentoId: item.orcamentoId, origemUsuarioId });
    return item;
  });
}

async function substituirItens(orcamentoId, itens, origemUsuarioId = null) {
  for (const item of itens) {
    if (item.materialId == null) {
      throw { status: 400, message: 'Todo item precisa de materialId.' };
    }
    if (item.quantidade == null) {
      throw { status: 400, message: `Item do material ${item.materialId} sem quantidade.` };
    }
  }

  return _enfileirar(orcamentoId, async () => {
    await prisma.$transaction(async (tx) => {
      await tx.orcamentoItem.deleteMany({ where: { orcamentoId } });

      if (itens.length > 0) {
        await tx.orcamentoItem.createMany({
          data: itens.map((item) => ({
            orcamentoId,
            materialId: item.materialId,
            fornecedorId: item.fornecedorId ?? null,
            quantidade: item.quantidade,
            qtdUnidade: item.qtdUnidade ?? null,
            precoUnitario: item.precoUnitario ?? null,
            selecionado: item.selecionado ?? false,
            descricaoItem: item.descricaoItem ?? null,
            observacao: item.observacao ?? null,
          })),
        });
      }
    });

    emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });

    return prisma.orcamentoItem.findMany({ where: { orcamentoId } });
  });
}

async function cancelar(id, usuarioId = null) {
  if (usuarioId != null) {
    const atual = await prisma.orcamento.findUnique({ where: { id }, select: { criadorId: true, status: true } });
    if (!atual) {
      throw { status: 404, message: 'Orçamento não encontrado (pode já ter sido excluído).' };
    }
    if (atual.status === 'ABERTO' && atual.criadorId != null && atual.criadorId !== usuarioId) {
      throw { status: 403, message: 'Apenas o criador do orçamento pode cancelá-lo/excluí-lo.' };
    }
  }

  let orc;
  try {
    orc = await prisma.orcamento.update({
      where: { id },
      data: { status: 'CANCELADO', travaUsuarioId: null, travaExpiraEm: null },
    });
  } catch (e) {
    if (e && e.code === 'P2025') {
      throw { status: 404, message: 'Orçamento não encontrado (pode já ter sido excluído).' };
    }
    throw e;
  }
  emitir('orcamento_saiu_de_aberto', { orcamentoId: id });
  return orc;
}

async function enviarParaAprovacao(id) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id },
    include: { itens: true },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'ABERTO' && orcamento.status !== 'AGUARDANDO_APROVACAO')
    throw { status: 400, message: 'Apenas orçamentos abertos podem ser enviados para aprovação' };

  if (orcamento.itens.length === 0)
    throw { status: 400, message: 'Não é possível enviar um orçamento vazio para aprovação' };

  const atualizado = await prisma.orcamento.update({
    where: { id },
    data: { status: 'AGUARDANDO_APROVACAO', travaUsuarioId: null, travaExpiraEm: null },
  });
  emitir('orcamento_saiu_de_aberto', { orcamentoId: id });
  return atualizado;
}

async function aprovar(id, aprovadorId) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'AGUARDANDO_APROVACAO')
    throw { status: 400, message: 'Apenas orçamentos aguardando aprovação podem ser aprovados' };

  return prisma.orcamento.update({
    where: { id },
    data: {
      status: 'APROVADO',
      aprovadorId,
      aprovadoEm: new Date(),
      motivoRejeicao: null,
    },
  });
}

async function rejeitar(id, aprovadorId, motivo) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'AGUARDANDO_APROVACAO')
    throw { status: 400, message: 'Apenas orçamentos aguardando aprovação podem ser rejeitados' };

  return prisma.orcamento.update({
    where: { id },
    data: {
      status: 'NAO_APROVADO',
      aprovadorId,
      aprovadoEm: new Date(),
      motivoRejeicao: motivo || 'Não informado',
    },
  });
}

async function validarParaOC(orcamentoId) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id: orcamentoId },
    include: { itens: true },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'APROVADO' && orcamento.status !== 'ABERTO')
    throw { status: 400, message: 'Apenas orçamentos aprovados (ou reabertos de aprovado) podem gerar ordem de compra' };

  if (orcamento.itens.length === 0)
    throw { status: 400, message: 'Orçamento não possui itens' };

  return true;
}

async function reabrir(id) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  const statusPermitidos = ['AGUARDANDO_APROVACAO', 'APROVADO', 'NAO_APROVADO'];
  if (!statusPermitidos.includes(orcamento.status))
    throw {
      status: 400,
      message: 'Apenas orçamentos aguardando aprovação, aprovados ou não aprovados podem ser reabertos',
    };

  const reaberto = await prisma.orcamento.update({
    where: { id },
    data: {
      status: 'ABERTO',
      aprovadorId: null,
      aprovadoEm: null,
      motivoRejeicao: null,
    },
    include: _itensInclude,
  });
  emitir('orcamento_voltou_a_aberto', { orcamento: reaberto });
  return reaberto;
}

async function atualizar(id, dados) {
  const saindoDeAberto = dados.status && dados.status !== 'ABERTO';
  const atualizado = await prisma.orcamento.update({
    where: { id },
    data: saindoDeAberto ? { ...dados, travaUsuarioId: null, travaExpiraEm: null } : dados,
  });
  if (atualizado.status === 'ABERTO') {
    emitir('orcamento_item_alterado', { orcamentoId: id });
  } else {
    emitir('orcamento_saiu_de_aberto', { orcamentoId: id });
  }
  return atualizado;
}

async function excluir(id, usuarioId = null) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });
  if (!orcamento) {
    return;
  }

  if (usuarioId != null && orcamento.criadorId != null && orcamento.criadorId !== usuarioId) {
    throw { status: 403, message: 'Apenas o criador do orçamento pode excluí-lo.' };
  }

  const statusPermitidos = ['CANCELADO', 'NAO_APROVADO', 'CONVERTIDO'];
  if (!statusPermitidos.includes(orcamento.status)) {
    throw {
      status: 400,
      message: 'Apenas orçamentos cancelados, rejeitados ou convertidos podem ser excluídos',
    };
  }

  await prisma.orcamentoItem.deleteMany({ where: { orcamentoId: id } });
  try {
    await prisma.orcamento.delete({ where: { id } });
  } catch (e) {
    if (e && e.code === 'P2025') return;
    throw e;
  }
}

async function definirFornecedorOculto(orcamentoId, fornecedorId, oculto) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id: orcamentoId },
    select: { fornecedoresOcultos: true },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  const atual = new Set(orcamento.fornecedoresOcultos);
  if (oculto) atual.add(fornecedorId);
  else atual.delete(fornecedorId);

  const atualizado = await prisma.orcamento.update({
    where: { id: orcamentoId },
    data: { fornecedoresOcultos: Array.from(atual) },
  });
  emitir('orcamento_item_alterado', { orcamentoId });
  return atualizado;
}

function _travaAtivaEValida(orcamento) {
  if (!orcamento.travaUsuarioId || !orcamento.travaExpiraEm) return false;
  return new Date(orcamento.travaExpiraEm).getTime() > Date.now();
}

async function travarEdicao(orcamentoId, userId) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id: orcamentoId },
    include: { travaUsuario: { select: { id: true, nome: true } } },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };
  if (orcamento.status !== 'ABERTO')
    throw { status: 400, message: 'Apenas orçamentos em aberto podem ser travados para edição' };

  if (_travaAtivaEValida(orcamento) && orcamento.travaUsuarioId !== userId) {
    throw {
      status: 409,
      message: `Orçamento está sendo editado por ${orcamento.travaUsuario?.nome || 'outro usuário'} no momento.`,
      travaUsuarioId: orcamento.travaUsuarioId,
      travaUsuarioNome: orcamento.travaUsuario?.nome || null,
    };
  }

  const atualizado = await prisma.orcamento.update({
    where: { id: orcamentoId },
    data: {
      travaUsuarioId: userId,
      travaExpiraEm: new Date(Date.now() + TRAVA_DURACAO_MS),
    },
    include: { travaUsuario: { select: { id: true, nome: true } } },
  });

  emitir('orcamento_travado', {
    orcamentoId,
    travaUsuarioId: userId,
    travaUsuarioNome: atualizado.travaUsuario?.nome || null,
  });

  return atualizado;
}

const TRAVA_VARREDURA_INTERVALO_MS = 10 * 1000;

async function _varrerTravasExpiradas() {
  try {
    const expiradas = await prisma.orcamento.findMany({
      where: {
        status: 'ABERTO',
        travaUsuarioId: { not: null },
        travaExpiraEm: { lt: new Date() },
      },
      select: { id: true },
    });

    for (const { id } of expiradas) {
      const resultado = await prisma.orcamento.updateMany({
        where: { id, status: 'ABERTO', travaUsuarioId: { not: null }, travaExpiraEm: { lt: new Date() } },
        data: { travaUsuarioId: null, travaExpiraEm: null },
      });
      if (resultado.count > 0) {
        emitir('orcamento_destravado', { orcamentoId: id });
      }
    }
  } catch (e) {
    console.error('Erro na varredura de travas expiradas:', e);
  }
}

let _travaVarreduraTimer = null;
function iniciarVarreduraDeTravas() {
  if (_travaVarreduraTimer) return;
  _travaVarreduraTimer = setInterval(_varrerTravasExpiradas, TRAVA_VARREDURA_INTERVALO_MS);
  if (_travaVarreduraTimer.unref) _travaVarreduraTimer.unref();
}

async function renovarTravaEdicao(orcamentoId, userId) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id: orcamentoId } });
  if (!orcamento || orcamento.travaUsuarioId !== userId) {
    return { renovada: false };
  }
  await prisma.orcamento.update({
    where: { id: orcamentoId },
    data: { travaExpiraEm: new Date(Date.now() + TRAVA_DURACAO_MS) },
  });
  return { renovada: true };
}

async function destravarEdicao(orcamentoId, userId) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id: orcamentoId } });
  if (!orcamento || orcamento.travaUsuarioId !== userId) {
    return { destravada: false };
  }
  await prisma.orcamento.update({
    where: { id: orcamentoId },
    data: { travaUsuarioId: null, travaExpiraEm: null },
  });

  emitir('orcamento_destravado', { orcamentoId });

  return { destravada: true };
}

const TRAVA_GRACA_DESCONEXAO_MS = 3 * 1000;
const _liberacaoPendentePorUsuario = new Map();

function agendarLiberacaoPorDesconexao(userId) {
  if (!userId) return;

  const existente = _liberacaoPendentePorUsuario.get(userId);
  if (existente) clearTimeout(existente);

  const timer = setTimeout(async () => {
    _liberacaoPendentePorUsuario.delete(userId);
    try {
      await liberarTravasDoUsuario(userId);
    } catch (e) {
      console.error('Erro ao liberar travas por desconexão SSE:', e);
    }
  }, TRAVA_GRACA_DESCONEXAO_MS);

  if (timer.unref) timer.unref();
  _liberacaoPendentePorUsuario.set(userId, timer);
}

function adiarLiberacaoPorDesconexao(userId) {
  if (!userId) return;
  const existente = _liberacaoPendentePorUsuario.get(userId);
  if (existente) {
    clearTimeout(existente);
    _liberacaoPendentePorUsuario.delete(userId);
  }
}

async function liberarTravasDoUsuario(userId) {
  const travados = await prisma.orcamento.findMany({
    where: { status: 'ABERTO', travaUsuarioId: userId },
    select: { id: true },
  });

  for (const { id } of travados) {
    const resultado = await prisma.orcamento.updateMany({
      where: { id, status: 'ABERTO', travaUsuarioId: userId },
      data: { travaUsuarioId: null, travaExpiraEm: null },
    });
    if (resultado.count > 0) {
      emitir('orcamento_destravado', { orcamentoId: id });
    }
  }
}

module.exports = {
  listar,
  listarAbertos,
  buscarPorId,
  criar,
  atualizar,
  excluir,
  adicionarItem,
  removerItem,
  limparItens,
  atualizarItem,
  substituirItens,
  cancelar,
  enviarParaAprovacao,
  aprovar,
  rejeitar,
  validarParaOC,
  reabrir,
  definirFornecedorOculto,
  travarEdicao,
  renovarTravaEdicao,
  destravarEdicao,
  iniciarVarreduraDeTravas,
  liberarTravasDoUsuario,
  agendarLiberacaoPorDesconexao,
  adiarLiberacaoPorDesconexao,
  orcamentoEvents,
  emitir,
};