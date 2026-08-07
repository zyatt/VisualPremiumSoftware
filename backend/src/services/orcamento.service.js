const prisma = require('../utils/prisma');
const { EventEmitter } = require('events');

// ─── Broadcast SSE ──────────────────────────────────────────────────────────
// Mesmo padrão do módulo de chat: um EventEmitter interno que o controller
// usa para escrever nos streams SSE abertos. `emitir(tipo, payload)` é
// chamado por qualquer operação que muda o estado de um orçamento ABERTO
// (criar, editar item, travar/destravar, atualizar título, ocultar
// fornecedor etc.) para que todo cliente conectado receba a atualização em
// tempo real, sem precisar dar F5/poll.
const orcamentoEvents = new EventEmitter();
orcamentoEvents.setMaxListeners(0); // pode haver muitos clientes conectados

function emitir(tipo, payload) {
  orcamentoEvents.emit('evento', { tipo, ...payload });
}

// Duração da trava sem receber heartbeat do editor. Se o app fechar/cair
// sem chamar `destravarEdicao`, a trava expira sozinha após esse tempo e
// outro usuário pode assumir a edição.
const TRAVA_DURACAO_MS = 60 * 1000; // 60s (o editor deve renovar a cada ~20s)

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

/// Lista todos os orçamentos com status ABERTO, com o criador incluído,
/// para a seção "Orçamentos em Aberto" (agrupamento por usuário é feito
/// no cliente, mas devolvemos o criador para permitir isso).
async function listarAbertos() {
  return prisma.orcamento.findMany({
    where: { status: 'ABERTO' },
    include: {
      criador: { select: { id: true, nome: true } },
      travaUsuario: { select: { id: true, nome: true } },
      itens: { select: { id: true } },
    },
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarPorId(id) {
  return prisma.orcamento.findUnique({
    where: { id },
    include: {
      itens: {
        include: {
          material: {
            include: {
              fornecedorMateriais: {
                where: { ativo: true },
                include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
              },
            },
          },
          fornecedor: true,
        },
      },
      aprovador: { select: { id: true, nome: true } },
    },
  });
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
}

async function removerItem(orcamentoId, itemId, origemUsuarioId = null) {
  const resultado = await prisma.orcamentoItem.deleteMany({ where: { id: itemId, orcamentoId } });
  emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });
  return resultado;
}

async function limparItens(orcamentoId, origemUsuarioId = null) {
  const resultado = await prisma.orcamentoItem.deleteMany({ where: { orcamentoId } });
  emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });
  return resultado;
}

async function atualizarItem(itemId, data, origemUsuarioId = null) {
  const item = await prisma.orcamentoItem.update({ where: { id: itemId }, data });
  emitir('orcamento_item_alterado', { orcamentoId: item.orcamentoId, origemUsuarioId });
  return item;
}

/// Substitui TODOS os itens de um orçamento em uma única operação atômica
/// (delete + insert em uma transação) e emite UM ÚNICO evento SSE ao final.
///
/// Existe para resolver o problema de sincronização em tempo real causado
/// pelo padrão anterior "limparItens() + N x adicionarItem()" usado pelo
/// auto-save do editor ao fechar a guia (`_persistirItensDaAba`): cada uma
/// dessas N+1 chamadas emitia seu próprio evento `orcamento_item_alterado`,
/// então quem estava só visualizando o mesmo orçamento recebia uma rajada de
/// eventos com estados intermediários (às vezes o orçamento momentaneamente
/// SEM itens, logo após o limparItens e antes do primeiro adicionarItem de
/// volta). Isso fazia a tela de quem via "piscar" e, em caso de falha de
/// rede no meio da sequência, podia deixar o orçamento com itens pela
/// metade persistidos no banco.
///
/// [itens] é uma lista de objetos no mesmo formato aceito por
/// `adicionarItem`: { materialId, fornecedorId, quantidade, precoUnitario,
/// selecionado, descricaoItem, observacao, qtdUnidade }.
async function substituirItens(orcamentoId, itens, origemUsuarioId = null) {
  // `quantidade` é NOT NULL no schema (OrcamentoItem.quantidade Decimal
  // @default(1)) — valida aqui em vez de deixar o Postgres rejeitar com um
  // erro genérico de constraint, difícil de rastrear no cliente.
  for (const item of itens) {
    if (item.materialId == null) {
      throw { status: 400, message: 'Todo item precisa de materialId.' };
    }
    if (item.quantidade == null) {
      throw { status: 400, message: `Item do material ${item.materialId} sem quantidade.` };
    }
  }

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

  // `origemUsuarioId` identifica quem disparou esta mutação. O SSE é
  // broadcast para todo mundo conectado, inclusive o próprio autor (ver
  // orcamento.controller.js:streamSSE) — sem esse campo, o cliente que
  // acabou de salvar não tinha como distinguir "meu próprio auto-save
  // ecoando de volta" de "outra pessoa mudou o orçamento", e tratava os
  // dois casos como mudança externa, recarregando por cima de uma edição
  // local seguinte que ainda não tivesse sido persistida (ver
  // OrcamentoEditorPage._onProviderTempoRealChanged).
  emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });

  return prisma.orcamentoItem.findMany({ where: { orcamentoId } });
}

/// [usuarioId] é opcional para preservar chamadas internas/administrativas
/// existentes (ex: fluxo normal de "Cancelar" dentro do próprio editor, que
/// já passa por outras validações de trava). Quando informado, e o
/// orçamento ainda está ABERTO, só o próprio criador pode cancelá-lo por
/// aqui — impede que um usuário que apenas abriu a guia de outra pessoa
/// (via trava negada / modo somente-leitura) consiga cancelar/excluir o
/// orçamento alheio fechando a guia ou pela seção "Em Aberto".
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
    // P2025: registro não encontrado para o update — o orçamento já foi
    // excluído (ex: por outra guia/aba do próprio criador, ou por uma
    // corrida entre duas ações quase simultâneas). Não é um erro real do
    // ponto de vista de quem pediu o cancelamento: o resultado desejado
    // ("esse orçamento não está mais ABERTO/ativo") já é verdade. Tratamos
    // como no-op em vez de estourar 500 para o cliente.
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

/// Mesmo raciocínio de propriedade de [cancelar]: quando [usuarioId] é
/// informado e o orçamento (antes de excluir) ainda pertence a outro
/// criador, barra com 403 — protege contra excluir o orçamento de outra
/// pessoa mesmo que ele já esteja em um status "excluível".
async function excluir(id, usuarioId = null) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });
  if (!orcamento) {
    // Já não existe — do ponto de vista de quem pediu a exclusão, o
    // resultado desejado já é verdade. Trata como sucesso (idempotente)
    // em vez de forçar o cliente a tratar 404 como falha.
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
    // P2025: alguém mais rápido já excluiu no intervalo entre o
    // findUnique acima e este delete — resultado final desejado já foi
    // alcançado, então não é um erro para quem chamou.
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

// ─── Trava de edição colaborativa ──────────────────────────────────────────
// Garante que só um usuário por vez esteja editando um orçamento ABERTO.
// A trava é liberada explicitamente ao sair do editor (`destravarEdicao`) ou
// expira sozinha (`travaExpiraEm`) se o app fechar sem avisar.

function _travaAtivaEValida(orcamento) {
  if (!orcamento.travaUsuarioId || !orcamento.travaExpiraEm) return false;
  return new Date(orcamento.travaExpiraEm).getTime() > Date.now();
}

/// Tenta travar o orçamento para `userId`. Se já estiver travado por outro
/// usuário (e a trava não expirou), lança 409 com o nome de quem está
/// editando. Se o próprio `userId` já é o dono da trava, apenas renova
/// (heartbeat). Retorna o orçamento atualizado.
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

/// Renova a trava (heartbeat periódico enquanto o editor está aberto).
/// Silenciosamente não faz nada se a trava não pertence mais a `userId`
/// (ex: expirou e outro usuário já assumiu) — o chamador (editor) deve
/// tratar isso detectando divergência via SSE/erro na próxima ação de escrita.
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

/// Libera a trava. Só destrava de fato se `userId` for o dono atual (evita
/// que um destravamento atrasado de uma aba antiga derrube a trava de quem
/// assumiu depois). Chamado ao sair do editor (dispose) ou ao salvar/enviar
/// para aprovação/cancelar (o orçamento deixa de estar em edição livre).
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
  orcamentoEvents,
  emitir,
};