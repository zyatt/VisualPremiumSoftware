const prisma = require('../utils/prisma');
const materialSvc = require('./material.service');
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
          descricao: true,
          unidade: true,
          categoria: true,
          medida: true,
          espessura: true,
          identificador: true,
          largura: true,
          comprimento: true,
          ehGenerico: true,
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
          descricaoItem: true,
          material: {
            select: {
              id: true,
              nome: true,
              descricao: true,
              unidade: true,
              categoria: true,
              medida: true,
              espessura: true,
              identificador: true,
              largura: true,
              comprimento: true,
              ehGenerico: true,
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
        orderBy: { id: 'asc' },
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
    const desc = descricaoItem != null && descricaoItem.trim() ? descricaoItem.trim() : null;

    const material = await prisma.material.findUnique({
      where: { id: materialId },
      select: { id: true, ehGenerico: true },
    });
    if (!material) throw { status: 404, message: 'Material não encontrado.' };

    if (material.ehGenerico && !desc) {
      throw { status: 400, message: 'Este material é genérico: preencha a descrição do item antes de salvar.' };
    }

    // Se o material referenciado é genérico, resolve (ou cria) o filho
    // concreto para a descrição informada e grava o materialId do filho
    // — não mais o do genérico. Isso é o que garante que cada variante
    // tenha seu próprio id (e, por consequência, seu próprio preço de
    // fornecedor, estoque e histórico, sem sobreposição entre variantes).
    const materialIdReal = material.ehGenerico
      ? (await materialSvc.resolverOuCriarFilho(materialId, desc)).id
      : materialId;

    const data = {
      fornecedorId: fid,
      quantidade,
      qtdUnidade: qtdUnidade ?? null,
      precoUnitario: precoUnitario ?? null,
      selecionado: selecionado ?? false,
      // descricaoItem deixa de ser a fonte de verdade para materiais
      // genéricos (a descrição já vive no Material filho via materialSvc).
      // Mantido nulo aqui; para materiais não-genéricos nunca foi usado
      // de qualquer forma neste fluxo.
      descricaoItem: null,
      observacao: observacao ?? null,
    };

    const resultado = await prisma.$transaction(async (tx) => {
      // materialIdReal agora é único por variante, então o dedupe volta a
      // ser simples: (orcamentoId, materialId, fornecedorId), sem precisar
      // do COALESCE de descricaoItem que era necessário quando um único
      // materialId genérico podia ter várias descrições diferentes.
      const linhas = await tx.$queryRaw`
        SELECT id FROM orcamento_itens
        WHERE "orcamentoId" = ${orcamentoId}
          AND "materialId" = ${materialIdReal}
          AND COALESCE("fornecedorId", -1) = ${fid ?? -1}
        FOR UPDATE
      `;

      if (linhas.length > 0) {
        return tx.orcamentoItem.update({ where: { id: linhas[0].id }, data });
      }

      return tx.orcamentoItem.create({
        data: { orcamentoId, materialId: materialIdReal, ...data },
      });
    });

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
    select: { orcamentoId: true, materialId: true },
  });
  if (!atual) {
    throw { status: 404, message: 'Item do orçamento não encontrado.' };
  }

  if (Object.prototype.hasOwnProperty.call(data, 'descricaoItem')) {
    const desc = data.descricaoItem != null && String(data.descricaoItem).trim()
      ? String(data.descricaoItem).trim()
      : null;
    const materialAtual = await prisma.material.findUnique({
      where: { id: atual.materialId },
      select: { id: true, ehGenerico: true, materialGenericoId: true },
    });

    // O materialId gravado num item já é sempre um material "folha"
    // (não-genérico) — se ele for filho de um genérico e a descrição
    // mudar, isso significa trocar de variante: resolve (ou cria) o
    // filho correspondente à nova descrição e troca o materialId do
    // item para ele. Isso preserva o histórico/estoque/preço de cada
    // variante como registros distintos e independentes.
    if (materialAtual?.materialGenericoId) {
      if (!desc) {
        throw { status: 400, message: 'Este material é genérico: a descrição não pode ficar vazia.' };
      }
      const filho = await materialSvc.resolverOuCriarFilho(materialAtual.materialGenericoId, desc);
      data = { ...data, materialId: filho.id, descricaoItem: null };
    } else if (materialAtual?.ehGenerico) {
      // Caso defensivo: item ainda aponta direto para o genérico (dado
      // legado, ou criado por um fluxo antigo). Resolve normalmente.
      if (!desc) {
        throw { status: 400, message: 'Este material é genérico: preencha a descrição antes de salvar.' };
      }
      const filho = await materialSvc.resolverOuCriarFilho(atual.materialId, desc);
      data = { ...data, materialId: filho.id, descricaoItem: null };
    } else {
      data = { ...data, descricaoItem: null };
    }
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

  const materiaisIds = [...new Set(itens.map((i) => i.materialId))];
  const materiais = await prisma.material.findMany({
    where: { id: { in: materiaisIds } },
    select: { id: true, ehGenerico: true, nome: true },
  });
  const genericosPorId = new Map(materiais.map((m) => [m.id, m]));

  // Resolve cada item de material genérico para o filho concreto
  // correspondente à descrição informada, do mesmo jeito que
  // adicionarItem/atualizarItem já fazem. Sem isso, o materialId
  // gravado ficava sendo o do pai genérico — o que fazia o vínculo
  // de preço com o fornecedor (e a descrição) se perder/misturar
  // entre variantes diferentes do mesmo material genérico.
  const itensResolvidos = [];
  const chavesVistas = new Set();
  for (const item of itens) {
    const material = genericosPorId.get(item.materialId);
    const desc = item.descricaoItem != null && String(item.descricaoItem).trim()
      ? String(item.descricaoItem).trim()
      : null;

    if (material?.ehGenerico && !desc) {
      throw { status: 400, message: `Material genérico "${material.nome}" precisa de uma descrição preenchida.` };
    }

    const materialIdReal = material?.ehGenerico
      ? (await materialSvc.resolverOuCriarFilho(item.materialId, desc)).id
      : item.materialId;

    const chave = `${materialIdReal}|${item.fornecedorId ?? -1}`;
    if (chavesVistas.has(chave)) {
      throw {
        status: 400,
        message: `Item duplicado para o material ${material?.nome || item.materialId}${desc ? ` (descrição "${desc}")` : ''}.`,
      };
    }
    chavesVistas.add(chave);

    itensResolvidos.push({ ...item, materialId: materialIdReal });
  }

  return _enfileirar(orcamentoId, async () => {
    await prisma.$transaction(async (tx) => {
      await tx.orcamentoItem.deleteMany({ where: { orcamentoId } });

      if (itensResolvidos.length > 0) {
        await tx.orcamentoItem.createMany({
          data: itensResolvidos.map((item) => ({
            orcamentoId,
            materialId: item.materialId,
            fornecedorId: item.fornecedorId ?? null,
            quantidade: item.quantidade,
            qtdUnidade: item.qtdUnidade ?? null,
            precoUnitario: item.precoUnitario ?? null,
            selecionado: item.selecionado ?? false,
            // descricaoItem não é mais a fonte de verdade para genéricos:
            // a descrição já ficou presa ao Material filho resolvido acima.
            descricaoItem: null,
            observacao: item.observacao ?? null,
          })),
        });
      }
    });

    emitir('orcamento_item_alterado', { orcamentoId, origemUsuarioId });

    return prisma.orcamentoItem.findMany({ where: { orcamentoId } });
  });
}

/// Salva o estado do orçamento como RASCUNHO — usado por voltar, abrir/
/// fechar outra guia e fechar o app. Ao contrário de substituirItens,
/// NUNCA chama materialSvc.resolverOuCriarFilho: itens de material
/// genérico continuam apontando para o materialId do PAI genérico e a
/// descrição digitada é gravada crua em descricaoItem. Isso é o que
/// impede que uma descrição só "de passagem" (usuário ainda decidindo,
/// ou saiu sem confirmar) crie um Material filho real no estoque.
///
/// A resolução para Material filho definitivo só acontece em
/// enviarParaAprovacao / substituirItens (chamado a partir do fluxo de
/// "Enviar para aprovação").
async function salvarRascunho(orcamentoId, itens, origemUsuarioId = null) {
  for (const item of itens) {
    if (item.materialId == null) {
      throw { status: 400, message: 'Todo item precisa de materialId.' };
    }
    if (item.quantidade == null) {
      throw { status: 400, message: `Item do material ${item.materialId} sem quantidade.` };
    }
  }

  const materiaisIds = [...new Set(itens.map((i) => i.materialId))];
  const materiais = await prisma.material.findMany({
    where: { id: { in: materiaisIds } },
    select: { id: true, ehGenerico: true, nome: true },
  });
  const materiaisPorId = new Map(materiais.map((m) => [m.id, m]));

  // IMPORTANTE: ao contrário de substituirItens/enviarParaAprovacao, o
  // rascunho NÃO exige descrição preenchida para materiais genéricos.
  // Ele existe justamente para guardar o estado "ainda incompleto" do
  // usuário (voltar, trocar de aba, fechar o app) — barrar aqui com um
  // 400 fazia o autosave (OrcamentoEditorPage._persistirItensDaAba)
  // falhar por inteiro toda vez que houvesse um item genérico sem
  // descrição na lista, e como o autosave silencia o erro (só loga),
  // NENHUM item era persistido, nem os que já tinham descrição — na
  // próxima recarga (SSE, reabrir a aba) o servidor devolvia o último
  // rascunho que tinha conseguido salvar antes daquele item genérico
  // aparecer, fazendo tudo "sumir" da tela. A obrigatoriedade da
  // descrição é responsabilidade de enviarParaAprovacao (e, no PDF, do
  // controller de PDF) — não do rascunho.
  const itensPreparados = [];
  const chavesVistas = new Set();
  let indiceSemDesc = 0;
  for (const item of itens) {
    const material = materiaisPorId.get(item.materialId);
    const desc = item.descricaoItem != null && String(item.descricaoItem).trim()
      ? String(item.descricaoItem).trim()
      : null;

    // Diferença crucial em relação a substituirItens: NÃO resolve/cria
    // o filho aqui. materialId permanece o do genérico (ou o material
    // normal, se não for genérico) e a descrição fica em descricaoItem.
    //
    // Quando o material é genérico e ainda não tem descrição, vários
    // itens desse mesmo pai podem coexistir no rascunho (o usuário pode
    // ter adicionado mais de uma linha do mesmo material genérico antes
    // de decidir as descrições) — por isso incluímos um índice sequencial
    // na chave nesse caso, para não colapsar itens distintos que ainda
    // não têm nada que os diferencie.
    const chave = desc
      ? `${item.materialId}|${item.fornecedorId ?? -1}|${desc}`
      : `${item.materialId}|${item.fornecedorId ?? -1}|semdesc|${indiceSemDesc++}`;
    if (material?.ehGenerico && desc && chavesVistas.has(chave)) {
      throw {
        status: 400,
        message: `Item duplicado para o material ${material?.nome || item.materialId} (descrição "${desc}").`,
      };
    }
    if (!material?.ehGenerico && chavesVistas.has(chave)) {
      throw {
        status: 400,
        message: `Item duplicado para o material ${material?.nome || item.materialId}.`,
      };
    }
    chavesVistas.add(chave);

    itensPreparados.push({ ...item, descricaoItem: desc, descricaoConfirmada: !!item.descricaoConfirmada });
  }

  return _enfileirar(orcamentoId, async () => {
    await prisma.$transaction(async (tx) => {
      await tx.orcamentoItem.deleteMany({ where: { orcamentoId } });

      if (itensPreparados.length > 0) {
        await tx.orcamentoItem.createMany({
          data: itensPreparados.map((item) => ({
            orcamentoId,
            materialId: item.materialId,
            fornecedorId: item.fornecedorId ?? null,
            quantidade: item.quantidade,
            qtdUnidade: item.qtdUnidade ?? null,
            precoUnitario: item.precoUnitario ?? null,
            selecionado: item.selecionado ?? false,
            descricaoItem: item.descricaoItem,
            // Fonte da verdade: o que o cliente já tinha confirmado antes
            // (persistido em rascunhos anteriores) OU acabou de confirmar
            // agora no diálogo. Como salvarRascunho recria todos os itens
            // a cada chamada (delete + createMany), o cliente é responsável
            // por reenviar esse valor a cada save — ver
            // OrcamentoEditorPage._persistirItensDaAba.
            descricaoConfirmada: item.descricaoConfirmada,
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
    include: {
      itens: {
        include: {
          material: {
            select: { id: true, nome: true, ehGenerico: true, materialGenericoId: true },
          },
        },
      },
    },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'ABERTO' && orcamento.status !== 'AGUARDANDO_APROVACAO')
    throw { status: 400, message: 'Apenas orçamentos abertos podem ser enviados para aprovação' };

  if (orcamento.itens.length === 0)
    throw { status: 400, message: 'Não é possível enviar um orçamento vazio para aprovação' };

  // O materialId gravado num item já é sempre um material "folha": para
  // genéricos, adicionarItem/atualizarItem/substituirItens resolvem para
  // o filho concreto antes de salvar, e descricaoItem fica null (a
  // descrição passa a viver no nome do próprio Material filho). Por
  // isso a checagem aqui não pode mais olhar item.descricaoItem nem
  // item.material.ehGenerico (o filho nunca é ehGenerico=true) — o que
  // precisa ser validado é um item ainda apontando direto para o pai
  // genérico (caso defensivo/dado legado que não deveria acontecer no
  // fluxo normal, mas indicaria descrição não preenchida).
  const genericosSemDescricao = orcamento.itens.filter((item) => item.material?.ehGenerico);
  if (genericosSemDescricao.length > 0) {
    const nomes = [...new Set(genericosSemDescricao.map((i) => i.material.nome))].join(', ');
    throw {
      status: 400,
      message: `Preencha a descrição dos materiais genéricos antes de enviar para aprovação: ${nomes}.`,
    };
  }

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
  salvarRascunho,
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