const prisma = require('../utils/prisma');
const path   = require('path');
const fs     = require('fs');

const _sseClients = new Map();
let _nextSseId = 1;

function registrarSseCliente(res, usuarioId) {
  const id = _nextSseId++;
  _sseClients.set(id, { res, usuarioId });
  console.log(`[SSE Solicitações] Cliente ${usuarioId} conectado (total: ${_sseClients.size})`);
  try {
    res.write(`data: ${JSON.stringify({ tipo: 'conectado', usuarioId })}\n\n`);
  } catch (err) {
    console.error(`[SSE Solicitações] Erro ao enviar confirmação: ${err.message}`);
  }
  return () => {
    _sseClients.delete(id);
    console.log(`[SSE Solicitações] Cliente ${usuarioId} desconectado (total: ${_sseClients.size})`);
  };
}

function _broadcast(tipo, dados, excludeUsuarioId) {
  const payload = `data: ${JSON.stringify({ tipo, ...dados })}\n\n`;
  let enviados  = 0;
  // Compara como string: o id do usuário conectado via SSE e o id do autor
  // da ação podem chegar com tipos diferentes (number vs string, dependendo
  // de como cada rota/middleware os produz) — comparar com === direto faz
  // a exclusão falhar silenciosamente e o próprio autor acaba recebendo
  // (e vendo) o banner da sua própria ação.
  const excludeStr = excludeUsuarioId !== undefined && excludeUsuarioId !== null
    ? String(excludeUsuarioId)
    : undefined;
  for (const { res, usuarioId } of _sseClients.values()) {
    if (excludeStr !== undefined && String(usuarioId) === excludeStr) continue;
    try { res.write(payload); enviados++; }
    catch (err) { console.error(`[SSE Solicitações] Erro para usuário ${usuarioId}: ${err.message}`); }
  }
  console.log(`[SSE Solicitações] Evento '${tipo}' enviado para ${enviados} cliente(s)`);
}

const _materialSelect = {
  id: true, nome: true, unidade: true, identificador: true,
  medida: true, espessura: true, categoria: true, quantidade: true,
  largura: true, comprimento: true,
};

const _includeBase = {
  usuario: { select: { id: true, nome: true, role: true } },
  itens: {
    orderBy: { criadoEm: 'asc' },
    include: { material: { select: _materialSelect } },
  },
  adicionais: {
    orderBy: { adicionadoEm: 'asc' },
    include: { material: { select: _materialSelect } },
  },
};

async function listar(filtros = {}) {
  const { busca, andamento, materialId, numeroOS, dataInicio, dataFim } = filtros;
  const where = {};

  if (busca) {
    where.OR = [
      { numeroOS:    { contains: busca, mode: 'insensitive' } },
      { nomeCliente: { contains: busca, mode: 'insensitive' } },
      { itens:     { some: { material: { nome: { contains: busca, mode: 'insensitive' } } } } },
      { adicionais: { some: { material: { nome: { contains: busca, mode: 'insensitive' } } } } },
    ];
  }
  if (andamento)  where.andamento = andamento;
  if (numeroOS)   where.numeroOS  = { contains: numeroOS, mode: 'insensitive' };
  if (materialId) {
    const mid = Number(materialId);
    where.OR = [
      ...(where.OR ?? []),
      { itens:     { some: { materialId: mid } } },
      { adicionais: { some: { materialId: mid } } },
    ];
  }
  if (dataInicio || dataFim) {
    where.dataNecessidade = {};
    if (dataInicio) where.dataNecessidade.gte = new Date(dataInicio);
    if (dataFim)    where.dataNecessidade.lte = new Date(dataFim);
  }

  return prisma.solicitacaoMaterial.findMany({
    where,
    include: _includeBase,
    orderBy: [{ dataNecessidade: 'asc' }, { criadoEm: 'desc' }],
  });
}

async function buscarPorId(id) {
  return prisma.solicitacaoMaterial.findUnique({
    where: { id },
    include: _includeBase,
  });
}

async function listarLogs(solicitacaoId) {
  return prisma.logEdicaoSolicitacao.findMany({
    where: { solicitacaoId },
    orderBy: { editadoEm: 'desc' },
  });
}

async function _validarMaterial(materialId) {
  const mat = await prisma.material.findUnique({
    where: { id: materialId },
    select: { id: true, nome: true, ativo: true },
  });
  if (!mat)       throw { status: 404, message: 'Material não encontrado' };
  if (!mat.ativo) throw { status: 400, message: 'Material inativo não pode ser solicitado' };
  return mat;
}

async function verificarOSExiste(numeroOS, ignorarId) {
  const sol = await prisma.solicitacaoMaterial.findUnique({
    where: { numeroOS },
    select: { id: true, numeroOS: true, nomeCliente: true, andamento: true },
  });
  if (!sol) return { existe: false };
  if (ignorarId && sol.id === Number(ignorarId)) return { existe: false };
  return {
    existe: true,
    id: sol.id,
    numeroOS: sol.numeroOS,
    nomeCliente: sol.nomeCliente,
    andamento: sol.andamento,
  };
}

async function criar(data, usuarioId, usuarioNome) {
  const existe = await prisma.solicitacaoMaterial.findUnique({
    where: { numeroOS: data.numeroOS },
  });
  if (existe) {
    throw {
      status: 409,
      message: `Já existe uma solicitação para a OS "${data.numeroOS}". Abra a solicitação existente e adicione novos materiais.`,
    };
  }

  const itensRaw = Array.isArray(data.itens) ? data.itens : [];
  if (itensRaw.length === 0) throw { status: 400, message: 'Informe ao menos um material.' };
  for (const item of itensRaw) {
    await _validarMaterial(Number(item.materialId));
  }

  const nova = await prisma.solicitacaoMaterial.create({
    data: {
      numeroOS:        data.numeroOS,
      nomeCliente:     data.nomeCliente,
      dataNecessidade: new Date(data.dataNecessidade),
      andamento:       'EM_ANDAMENTO',
      observacao:      data.observacao ?? null,
      usuarioId,
      usuarioNome,
      itens: {
        create: itensRaw.map((item) => ({
          materialId: Number(item.materialId),
          quantidade:  item.quantidade,
          observacao:  item.observacao  ?? null,
          imagemUrl:   item.imagemUrl   ?? null,
        })),
      },
    },
    include: _includeBase,
  });

  console.log(`[Solicitações] Nova solicitação criada: OS=${nova.numeroOS} por usuário ${usuarioId}`);

  _broadcast('nova_solicitacao', {
    id:          nova.id,
    numeroOS:    nova.numeroOS,
    nomeCliente: nova.nomeCliente,
    usuarioNome: nova.usuarioNome,
    observacao:  nova.observacao,
    qtdMateriais: nova.itens.length,
    criadoEm:    nova.criadoEm,
  }, usuarioId);

  return nova;
}

async function atualizar(id, data, editorId, editorNome, editorRole) {
  const sol = await prisma.solicitacaoMaterial.findUnique({ where: { id } });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };

  const ehAdmin   = editorRole === 'ADMIN' || editorRole === 'GERENTE';
  const ehCriador = sol.usuarioId === editorId;
  if (!ehAdmin && !ehCriador) {
    throw { status: 403, message: 'Apenas o criador da solicitação, um gerente ou um administrador pode editar os dados.' };
  }

  if (data.numeroOS && data.numeroOS !== sol.numeroOS) {
    const conflito = await prisma.solicitacaoMaterial.findUnique({
      where: { numeroOS: data.numeroOS },
    });
    if (conflito) throw { status: 409, message: `OS "${data.numeroOS}" já pertence a outra solicitação.` };
  }

  const updateData = {};
  if (data.numeroOS        !== undefined) updateData.numeroOS        = data.numeroOS;
  if (data.nomeCliente     !== undefined) updateData.nomeCliente     = data.nomeCliente;
  if (data.dataNecessidade !== undefined) updateData.dataNecessidade = new Date(data.dataNecessidade);
  if (data.andamento       !== undefined) {
    if (!['EM_ANDAMENTO', 'EM_NEGOCIACAO', 'FINALIZADO'].includes(data.andamento)) {
      throw { status: 400, message: 'Andamento inválido. Valores permitidos: EM_ANDAMENTO, EM_NEGOCIACAO, FINALIZADO.' };
    }
    if (data.andamento === 'FINALIZADO') {
      await _verificarTodosComprados(id);
    }
    updateData.andamento = data.andamento;
  }
  if (data.observacao !== undefined) updateData.observacao = data.observacao;

  const antes   = { numeroOS: sol.numeroOS, nomeCliente: sol.nomeCliente, dataNecessidade: sol.dataNecessidade, andamento: sol.andamento, observacao: sol.observacao };
  const atualizado = await prisma.solicitacaoMaterial.update({
    where: { id },
    data:  updateData,
    include: _includeBase,
  });
  const depois  = { numeroOS: atualizado.numeroOS, nomeCliente: atualizado.nomeCliente, dataNecessidade: atualizado.dataNecessidade, andamento: atualizado.andamento, observacao: atualizado.observacao };

  const houveMudanca = JSON.stringify(antes) !== JSON.stringify(depois);
  if (houveMudanca && editorId) {
    await prisma.logEdicaoSolicitacao.create({
      data: { solicitacaoId: id, editorId, editorNome: editorNome ?? 'Desconhecido', antes, depois },
    });

    _broadcast('solicitacao_atualizada', {
      id:          atualizado.id,
      numeroOS:    atualizado.numeroOS,
      nomeCliente: atualizado.nomeCliente,
      editorNome:  editorNome ?? 'Desconhecido',
      acao:        'edicao_dados',
      antes,
      depois,
    }, editorId);
  }

  return atualizado;
}

async function adicionarMateriais(solicitacaoId, itens, usuarioId, usuarioNome, usuarioRole) {
  const sol = await prisma.solicitacaoMaterial.findUnique({ where: { id: solicitacaoId } });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };

  // Mesma regra usada para editar/excluir o cabeçalho e os materiais
  // (ver _autorizarEdicaoMaterial acima): ADMIN, GERENTE ou o próprio
  // criador da solicitação.
  const ehAdmin = usuarioRole === 'ADMIN' || usuarioRole === 'GERENTE';
  if (sol.usuarioId !== usuarioId && !ehAdmin) {
    throw { status: 403, message: 'Apenas o criador da solicitação, um gerente ou um administrador pode adicionar materiais.' };
  }

  if (sol.andamento === 'FINALIZADO') throw { status: 400, message: 'Solicitação já finalizada.' };

  if (!Array.isArray(itens) || itens.length === 0) {
    throw { status: 400, message: 'Informe ao menos um material.' };
  }

  for (const item of itens) {
    await _validarMaterial(Number(item.materialId));
  }

  const criados = await prisma.$transaction(
    itens.map((item) =>
      prisma.adicionalSolicitacaoMaterial.create({
        data: {
          solicitacaoId,
          materialId:        Number(item.materialId),
          quantidade:        item.quantidade,
          observacao:        item.observacao        ?? null,
          imagemUrl:         item.imagemUrl         ?? null,
          adicionadoPorId:   usuarioId,
          adicionadoPorNome: usuarioNome,
        },
        include: { material: { select: _materialSelect } },
      })
    )
  );

  // Retorna a solicitação atualizada
  const atualizado = await prisma.solicitacaoMaterial.findUnique({
    where: { id: solicitacaoId },
    include: _includeBase,
  });

  _broadcast('solicitacao_atualizada', {
    id:          solicitacaoId,
    numeroOS:    sol.numeroOS,
    nomeCliente: sol.nomeCliente,
    editorNome:  usuarioNome ?? 'Desconhecido',
    acao:        'adicao_material',
  }, usuarioId);

  return atualizado;
}

// ─── Rótulo amigável de um status de compra, usado no histórico ──────────────
function _labelStatus(status) {
  switch (status) {
    case 'COMPRADO': return 'Comprado';
    case 'ESTOQUE':   return 'Estoque';
    default:          return 'Pendente';
  }
}

// Deriva o status ('PENDENTE' | 'COMPRADO' | 'ESTOQUE') a partir dos campos
// booleanos comprado/estoque de um registro (item ou adicional).
function _statusDe(registro) {
  if (registro.estoque)  return 'ESTOQUE';
  if (registro.comprado) return 'COMPRADO';
  return 'PENDENTE';
}

// ─── Marcar item/adicional como comprado ou retirado do estoque ──────────────
// Qualquer usuário com role ACESSO pode marcar. Só ADMIN pode desmarcar (voltar
// para PENDENTE) ou trocar um status já salvo por outro.
// tipo   = 'item' | 'adicional'
// status = 'PENDENTE' | 'COMPRADO' | 'ESTOQUE'
async function marcarStatusCompra(tipo, itemId, usuarioId, usuarioNome, usuarioRole, status) {
  if (!['PENDENTE', 'COMPRADO', 'ESTOQUE'].includes(status)) {
    throw { status: 400, message: 'Status inválido. Valores permitidos: PENDENTE, COMPRADO, ESTOQUE.' };
  }

  const model = tipo === 'item'
    ? prisma.itemSolicitacaoMaterial
    : prisma.adicionalSolicitacaoMaterial;

  const registro = await model.findUnique({ where: { id: itemId } });
  if (!registro) throw { status: 404, message: 'Item não encontrado.' };

  const statusAnterior = _statusDe(registro);

  // Voltar para PENDENTE (desmarcar) ou trocar um status já salvo por outro
  // são ações restritas a ADMIN/GERENTE. Sair de PENDENTE para COMPRADO ou
  // ESTOQUE é permitido a qualquer usuário com acesso à tela.
  const ehAdmin = usuarioRole === 'ADMIN' || usuarioRole === 'GERENTE';
  if (statusAnterior !== 'PENDENTE' && statusAnterior !== status && !ehAdmin) {
    throw {
      status: 403,
      message: status === 'PENDENTE'
        ? 'Apenas administradores podem desmarcar um item já salvo como comprado ou estoque.'
        : 'Apenas administradores podem alterar um item que já foi marcado como comprado ou estoque.',
    };
  }

  if (statusAnterior === status) {
    // Nada muda — evita gravar log/broadcast à toa.
    return model.findUnique({ where: { id: itemId }, include: { material: { select: _materialSelect } } });
  }

  const agora = new Date();
  const data = {
    comprado:        status === 'COMPRADO',
    compradoEm:      status === 'COMPRADO' ? agora : null,
    compradoPorId:   status === 'COMPRADO' ? usuarioId : null,
    compradoPorNome: status === 'COMPRADO' ? usuarioNome : null,
    estoque:         status === 'ESTOQUE',
    estoqueEm:       status === 'ESTOQUE' ? agora : null,
    estoquePorId:    status === 'ESTOQUE' ? usuarioId : null,
    estoquePorNome:  status === 'ESTOQUE' ? usuarioNome : null,
  };

  const atualizado = await model.update({
    where: { id: itemId },
    data,
    include: { material: { select: _materialSelect } },
  });

  // Log de histórico da transição de status (comprado <-> pendente <-> estoque).
  if (usuarioId) {
    await prisma.logEdicaoSolicitacao.create({
      data: {
        solicitacaoId: registro.solicitacaoId,
        editorId:      usuarioId,
        editorNome:    usuarioNome ?? 'Desconhecido',
        antes:  { status: _labelStatus(statusAnterior) },
        depois: { status: _labelStatus(status) },
        item: `${atualizado.material?.nome ?? 'Material'}${tipo === 'adicional' ? ' (adicional)' : ''}`,
      },
    });
  }

  _broadcast('item_comprado', {
    solicitacaoId: registro.solicitacaoId,
    tipo,
    itemId,
    status,
    comprado: status === 'COMPRADO', // mantido por compatibilidade com clientes antigos
  }, usuarioId);

  // Se o item passou a estar resolvido (comprado ou estoque), verifica se
  // todos os materiais da solicitação estão resolvidos e auto-finaliza.
  if (status === 'COMPRADO' || status === 'ESTOQUE') {
    try {
      await _verificarTodosResolvidos(registro.solicitacaoId);
      // _verificarTodosResolvidos não lançou: tudo resolvido — finaliza automaticamente
      const sol = await prisma.solicitacaoMaterial.findUnique({
        where: { id: registro.solicitacaoId },
      });
      if (sol && sol.andamento !== 'FINALIZADO') {
        await prisma.solicitacaoMaterial.update({
          where: { id: registro.solicitacaoId },
          data: { andamento: 'FINALIZADO' },
        });

        // Registra no histórico a transição de andamento, igual ao fluxo manual em `atualizar`.
        await prisma.logEdicaoSolicitacao.create({
          data: {
            solicitacaoId: registro.solicitacaoId,
            editorId:      usuarioId,
            editorNome:    usuarioNome ?? 'Desconhecido',
            antes:         { andamento: sol.andamento },
            depois:        { andamento: 'FINALIZADO' },
          },
        });

        console.log(`[Solicitações] Solicitação ${registro.solicitacaoId} auto-finalizada (todos os itens comprados/estoque) por ${usuarioNome ?? usuarioId}`);
        _broadcast('solicitacao_atualizada', {
          id:          registro.solicitacaoId,
          numeroOS:    sol.numeroOS,
          nomeCliente: sol.nomeCliente,
          editorNome:  usuarioNome ?? 'Desconhecido',
          acao:        'auto_finalizacao',
          antes:       { andamento: sol.andamento },
          depois:      { andamento: 'FINALIZADO' },
        }, usuarioId);
        _broadcast('solicitacao_finalizada', { solicitacaoId: registro.solicitacaoId }, usuarioId);
      }
    } catch {
      // Ainda há itens pendentes — não finaliza
    }
  }

  return atualizado;
}

// Mantido por compatibilidade: usado internamente e por chamadores antigos
// que ainda pensam em termos de um booleano "comprado".
async function marcarComprado(tipo, itemId, usuarioId, usuarioNome, usuarioRole, comprado) {
  return marcarStatusCompra(tipo, itemId, usuarioId, usuarioNome, usuarioRole, comprado ? 'COMPRADO' : 'PENDENTE');
}

async function marcarEstoque(tipo, itemId, usuarioId, usuarioNome, usuarioRole, estoque) {
  return marcarStatusCompra(tipo, itemId, usuarioId, usuarioNome, usuarioRole, estoque ? 'ESTOQUE' : 'PENDENTE');
}

// ─── Verificar se todos os materiais estão comprados ou retirados do estoque ──
async function _verificarTodosResolvidos(solicitacaoId) {
  const [itens, adicionais] = await Promise.all([
    prisma.itemSolicitacaoMaterial.findMany({ where: { solicitacaoId }, select: { comprado: true, estoque: true } }),
    prisma.adicionalSolicitacaoMaterial.findMany({ where: { solicitacaoId }, select: { comprado: true, estoque: true } }),
  ]);

  const todos = [...itens, ...adicionais];
  if (todos.length === 0) return; // sem materiais, pode finalizar

  const pendentes = todos.filter((i) => !i.comprado && !i.estoque);
  if (pendentes.length > 0) {
    throw {
      status: 400,
      message: `Não é possível finalizar: ${pendentes.length} material(is) ainda não marcado(s) como comprado ou estoque.`,
    };
  }
}

// Alias mantido por compatibilidade com o nome anterior da função.
const _verificarTodosComprados = _verificarTodosResolvidos;

// ─── Excluir ──────────────────────────────────
async function excluir(id, usuarioId, usuarioRole) {
  const sol = await prisma.solicitacaoMaterial.findUnique({
    where: { id },
    include: {
      itens:     { select: { imagemUrl: true } },
      adicionais: { select: { imagemUrl: true } },
    },
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };

  // Permite ADMIN, GERENTE ou o próprio criador da solicitação excluir
  const ehAdmin   = usuarioRole === 'ADMIN' || usuarioRole === 'GERENTE';
  const ehCriador = sol.usuarioId === usuarioId;
  if (!ehAdmin && !ehCriador) {
    throw { status: 403, message: 'Apenas o criador da solicitação, um gerente ou um administrador pode excluir.' };
  }

  // Remove arquivos de imagem do disco
  const _rmImagem = (url) => {
    if (!url) return;
    const disco = path.join(__dirname, '..', 'uploads', 'solicitacoes', path.basename(url));
    fs.unlink(disco, () => {});
  };
  sol.itens.forEach((i)      => _rmImagem(i.imagemUrl));
  sol.adicionais.forEach((a) => _rmImagem(a.imagemUrl));

  return prisma.solicitacaoMaterial.delete({ where: { id } });
}

// ─── Autorização para editar/excluir um material de uma solicitação ─────────
// Regra igual à edição do cabeçalho: ADMIN/GERENTE ou o próprio criador da
// solicitação, e apenas enquanto ela não estiver FINALIZADA.
async function _autorizarEdicaoMaterial(solicitacaoId, usuarioId, usuarioRole) {
  const sol = await prisma.solicitacaoMaterial.findUnique({ where: { id: solicitacaoId } });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };

  const ehAdmin   = usuarioRole === 'ADMIN' || usuarioRole === 'GERENTE';
  const ehCriador = sol.usuarioId === usuarioId;
  if (!ehAdmin && !ehCriador) {
    throw { status: 403, message: 'Apenas o criador da solicitação, um gerente ou um administrador pode editar os materiais.' };
  }
  if (sol.andamento === 'FINALIZADO') {
    throw { status: 400, message: 'Solicitação finalizada. Reabra-a para editar os materiais.' };
  }
  return sol;
}

// ─── Editar quantidade/observação de um item ou adicional ───────────────────
async function atualizarItem(tipo, itemId, data, usuarioId, usuarioNome, usuarioRole) {
  const model = tipo === 'item'
    ? prisma.itemSolicitacaoMaterial
    : prisma.adicionalSolicitacaoMaterial;

  const registro = await model.findUnique({
    where: { id: itemId },
    include: { material: { select: _materialSelect } },
  });
  if (!registro) throw { status: 404, message: 'Item não encontrado.' };

  const sol = await _autorizarEdicaoMaterial(registro.solicitacaoId, usuarioId, usuarioRole);

  const updateData = {};
  const antes = { quantidade: registro.quantidade, observacao: registro.observacao };

  if (data.quantidade !== undefined) {
    const qtd = Number(data.quantidade);
    if (!Number.isFinite(qtd) || qtd <= 0) {
      throw { status: 400, message: 'Quantidade inválida.' };
    }
    updateData.quantidade = qtd;
  }
  if (data.observacao !== undefined) {
    updateData.observacao = data.observacao === '' ? null : data.observacao;
  }

  const depois = {
    quantidade: updateData.quantidade !== undefined ? updateData.quantidade : registro.quantidade,
    observacao: updateData.observacao !== undefined ? updateData.observacao : registro.observacao,
  };
  const houveMudanca = JSON.stringify(antes) !== JSON.stringify(depois);

  if (houveMudanca) {
    updateData.editadoEm = new Date();
    updateData.editadoPorNome = usuarioNome ?? 'Desconhecido';
  }

  const atualizado = await model.update({
    where: { id: itemId },
    data: updateData,
    include: { material: { select: _materialSelect } },
  });

  if (houveMudanca && usuarioId) {
    await prisma.logEdicaoSolicitacao.create({
      data: {
        solicitacaoId: registro.solicitacaoId,
        editorId:      usuarioId,
        editorNome:    usuarioNome ?? 'Desconhecido',
        antes,
        depois,
        // Contexto (não é um campo alterado em si, mas identifica qual
        // material foi editado — usado pela aba Histórico para exibir
        // uma legenda antes do diff de campos).
        item: `${registro.material?.nome ?? 'Material'}${tipo === 'adicional' ? ' (adicional)' : ''}`,
      },
    });

    _broadcast('solicitacao_atualizada', {
      id:          registro.solicitacaoId,
      numeroOS:    sol.numeroOS,
      nomeCliente: sol.nomeCliente,
      editorNome:  usuarioNome ?? 'Desconhecido',
      acao:        'edicao_material',
      item:        `${registro.material?.nome ?? 'Material'}${tipo === 'adicional' ? ' (adicional)' : ''}`,
      antes,
      depois,
    }, usuarioId);
  }

  return atualizado;
}

// ─── Remover um item ou adicional de uma solicitação ─────────────────────────
async function excluirItem(tipo, itemId, usuarioId, usuarioNome, usuarioRole) {
  const model = tipo === 'item'
    ? prisma.itemSolicitacaoMaterial
    : prisma.adicionalSolicitacaoMaterial;

  const registro = await model.findUnique({
    where: { id: itemId },
    include: { material: { select: _materialSelect } },
  });
  if (!registro) throw { status: 404, message: 'Item não encontrado.' };

  const sol = await _autorizarEdicaoMaterial(registro.solicitacaoId, usuarioId, usuarioRole);

  const [itensCount, adicionaisCount] = await Promise.all([
    prisma.itemSolicitacaoMaterial.count({ where: { solicitacaoId: registro.solicitacaoId } }),
    prisma.adicionalSolicitacaoMaterial.count({ where: { solicitacaoId: registro.solicitacaoId } }),
  ]);
  if (itensCount + adicionaisCount <= 1) {
    throw {
      status: 400,
      message: 'Não é possível excluir o único material da solicitação. Exclua a solicitação inteira, se necessário.',
    };
  }

  if (registro.imagemUrl) {
    const disco = path.join(__dirname, '..', 'uploads', 'solicitacoes', path.basename(registro.imagemUrl));
    fs.unlink(disco, () => {});
  }

  await model.delete({ where: { id: itemId } });

  if (usuarioId) {
    await prisma.logEdicaoSolicitacao.create({
      data: {
        solicitacaoId: registro.solicitacaoId,
        editorId:      usuarioId,
        editorNome:    usuarioNome ?? 'Desconhecido',
        antes: { quantidade: registro.quantidade, observacao: registro.observacao },
        depois: { excluido: true },
        // Contexto: nome do material removido — consumido pela aba Histórico
        // para exibir "Material removido: <nome>" em vez de um diff de campos.
        item: `${registro.material?.nome ?? 'Material'}${tipo === 'adicional' ? ' (adicional)' : ''}`,
      },
    });
  }

  _broadcast('solicitacao_atualizada', {
    id:          registro.solicitacaoId,
    numeroOS:    sol.numeroOS,
    nomeCliente: sol.nomeCliente,
    editorNome:  usuarioNome ?? 'Desconhecido',
    acao:        'exclusao_material',
    materialNome: registro.material?.nome,
    item:        `${registro.material?.nome ?? 'Material'}${tipo === 'adicional' ? ' (adicional)' : ''}`,
    antes:       { quantidade: registro.quantidade, observacao: registro.observacao },
    depois:      { excluido: true },
  }, usuarioId);
  return { solicitacaoId: registro.solicitacaoId };
}

// ─── Contar novas ─────────────────────────────────────────────────────────────
async function contarNovas(usuarioId) {
  const dataCorte = new Date();
  dataCorte.setDate(dataCorte.getDate() - 7);

  return prisma.solicitacaoMaterial.count({
    where: {
      criadoEm:  { gte: dataCorte },
      usuarioId: { not: usuarioId },
      NOT: { visualizacoes: { some: { usuarioId } } },
    },
  });
}

// ─── Marcar todas como visualizadas ──────────────────────────────────────────
async function marcarTodasComoVisualizadas(usuarioId) {
  const dataCorte = new Date();
  dataCorte.setDate(dataCorte.getDate() - 7);

  const naoVistas = await prisma.solicitacaoMaterial.findMany({
    where: {
      criadoEm:  { gte: dataCorte },
      usuarioId: { not: usuarioId },
      NOT: { visualizacoes: { some: { usuarioId } } },
    },
    select: { id: true },
  });

  if (naoVistas.length === 0) return 0;

  await prisma.visualizacaoSolicitacao.createMany({
    data: naoVistas.map((s) => ({ usuarioId, solicitacaoId: s.id })),
    skipDuplicates: true,
  });

  console.log(`[Solicitações] ${naoVistas.length} solicitação(ões) marcada(s) como visualizada(s) para usuário ${usuarioId}`);
  return naoVistas.length;
}

module.exports = {
  listar,
  buscarPorId,
  verificarOSExiste,
  criar,
  atualizar,
  adicionarMateriais,
  marcarComprado,
  marcarEstoque,
  marcarStatusCompra,
  atualizarItem,
  excluirItem,
  excluir,
  listarLogs,
  registrarSseCliente,
  contarNovas,
  marcarTodasComoVisualizadas,
};