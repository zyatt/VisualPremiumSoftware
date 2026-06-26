const prisma = require('../utils/prisma');
const path   = require('path');
const fs     = require('fs');

// ─── SSE ──────────────────────────────────────────────────────────────────────
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
  for (const { res, usuarioId } of _sseClients.values()) {
    if (excludeUsuarioId !== undefined && usuarioId === excludeUsuarioId) continue;
    try { res.write(payload); enviados++; }
    catch (err) { console.error(`[SSE Solicitações] Erro para usuário ${usuarioId}: ${err.message}`); }
  }
  console.log(`[SSE Solicitações] Evento '${tipo}' enviado para ${enviados} cliente(s)`);
}

// ─── Include base ─────────────────────────────────────────────────────────────
const _materialSelect = {
  id: true, nome: true, unidade: true, identificador: true,
  medida: true, espessura: true, categoria: true, quantidade: true,
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

// ─── Listar ───────────────────────────────────
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

// ─── Buscar por ID ────────────────────────────────────────────────────────────
async function buscarPorId(id) {
  return prisma.solicitacaoMaterial.findUnique({
    where: { id },
    include: _includeBase,
  });
}

// ─── Logs ─────────────────────────────────────
async function listarLogs(solicitacaoId) {
  return prisma.logEdicaoSolicitacao.findMany({
    where: { solicitacaoId },
    orderBy: { editadoEm: 'desc' },
  });
}

// ─── Validar material ativo ───────────────────────────────────────────────────
async function _validarMaterial(materialId) {
  const mat = await prisma.material.findUnique({
    where: { id: materialId },
    select: { id: true, nome: true, ativo: true },
  });
  if (!mat)       throw { status: 404, message: 'Material não encontrado' };
  if (!mat.ativo) throw { status: 400, message: 'Material inativo não pode ser solicitado' };
  return mat;
}

// ─── Criar ────────────────────────────────────
// `data.itens` = [{ materialId, quantidade, observacao?, imagemUrl? }, ...]
async function criar(data, usuarioId, usuarioNome) {
  // OS única
  const existe = await prisma.solicitacaoMaterial.findUnique({
    where: { numeroOS: data.numeroOS },
  });
  if (existe) {
    throw {
      status: 409,
      message: `Já existe uma solicitação para a OS "${data.numeroOS}". Abra a solicitação existente e adicione novos materiais.`,
    };
  }

  // Valida todos os materiais antes de persistir
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
    criadoEm:    nova.criadoEm,
  }, usuarioId);

  return nova;
}

// ─── Atualizar cabeçalho (somente ADMIN) ─────────────────────────────────────
// Apenas campos do cabeçalho da solicitação (não os itens).
async function atualizar(id, data, editorId, editorNome, editorRole) {
  const sol = await prisma.solicitacaoMaterial.findUnique({ where: { id } });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };

  if (editorRole !== 'ADMIN') {
    throw { status: 403, message: 'Apenas administradores podem editar uma solicitação existente.' };
  }

  // Impede trocar numeroOS para uma OS já usada por outra solicitação
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
    // Valida os únicos estados permitidos
    if (!['EM_ANDAMENTO', 'FINALIZADO'].includes(data.andamento)) {
      throw { status: 400, message: 'Andamento inválido. Valores permitidos: EM_ANDAMENTO, FINALIZADO.' };
    }
    // Bloqueia finalizar se houver materiais não comprados
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
  }

  return atualizado;
}

// ─── Adicionar materiais extras (adicional) ───────────────────────────────────
// Apenas o criador da solicitação ou um ADMIN pode adicionar materiais.
// `itens` = [{ materialId, quantidade, observacao?, imagemUrl? }, ...]
async function adicionarMateriais(solicitacaoId, itens, usuarioId, usuarioNome, usuarioRole) {
  const sol = await prisma.solicitacaoMaterial.findUnique({ where: { id: solicitacaoId } });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };

  if (sol.usuarioId !== usuarioId && usuarioRole !== 'ADMIN') {
    throw { status: 403, message: 'Apenas o criador da solicitação ou um administrador pode adicionar materiais.' };
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
          // adicionadoEm = default(now())
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
    id:       solicitacaoId,
    numeroOS: sol.numeroOS,
    tipo:     'adicional',
  }, usuarioId);

  return atualizado;
}

// ─── Marcar item/adicional como comprado ──────────────────────────────────────
// Qualquer usuário com role ACESSO pode marcar. Só ADMIN pode desmarcar.
// tipo = 'item' | 'adicional'
async function marcarComprado(tipo, itemId, usuarioId, usuarioNome, usuarioRole, comprado) {
  if (comprado === false && usuarioRole !== 'ADMIN') {
    throw { status: 403, message: 'Apenas administradores podem desmarcar um item como comprado.' };
  }

  const model = tipo === 'item'
    ? prisma.itemSolicitacaoMaterial
    : prisma.adicionalSolicitacaoMaterial;

  const registro = await model.findUnique({ where: { id: itemId } });
  if (!registro) throw { status: 404, message: 'Item não encontrado.' };

  const atualizado = await model.update({
    where: { id: itemId },
    data: {
      comprado,
      compradoEm:      comprado ? new Date() : null,
      compradoPorId:   comprado ? usuarioId  : null,
      compradoPorNome: comprado ? usuarioNome : null,
    },
    include: { material: { select: _materialSelect } },
  });

  _broadcast('item_comprado', {
    solicitacaoId: registro.solicitacaoId,
    tipo,
    itemId,
    comprado,
  });

  // Se marcou como comprado, verifica se todos os itens estão comprados e auto-finaliza
  if (comprado) {
    try {
      await _verificarTodosComprados(registro.solicitacaoId);
      // _verificarTodosComprados não lançou: todos comprados — finaliza automaticamente
      const sol = await prisma.solicitacaoMaterial.findUnique({
        where: { id: registro.solicitacaoId },
        select: { andamento: true },
      });
      if (sol && sol.andamento !== 'FINALIZADO') {
        await prisma.solicitacaoMaterial.update({
          where: { id: registro.solicitacaoId },
          data: { andamento: 'FINALIZADO' },
        });
        console.log(`[Solicitações] Solicitação ${registro.solicitacaoId} auto-finalizada (todos os itens comprados)`);
        _broadcast('solicitacao_finalizada', { solicitacaoId: registro.solicitacaoId });
      }
    } catch {
      // Ainda há itens pendentes — não finaliza
    }
  }

  return atualizado;
}

// ─── Verificar se todos os materiais estão comprados ─────────────────────────
async function _verificarTodosComprados(solicitacaoId) {
  const [itens, adicionais] = await Promise.all([
    prisma.itemSolicitacaoMaterial.findMany({ where: { solicitacaoId }, select: { comprado: true } }),
    prisma.adicionalSolicitacaoMaterial.findMany({ where: { solicitacaoId }, select: { comprado: true } }),
  ]);

  const todos = [...itens, ...adicionais];
  if (todos.length === 0) return; // sem materiais, pode finalizar

  const pendentes = todos.filter((i) => !i.comprado);
  if (pendentes.length > 0) {
    throw {
      status: 400,
      message: `Não é possível finalizar: ${pendentes.length} material(is) ainda não marcado(s) como comprado.`,
    };
  }
}

// ─── Excluir ──────────────────────────────────────────────────────────────────
async function excluir(id) {
  const sol = await prisma.solicitacaoMaterial.findUnique({
    where: { id },
    include: {
      itens:     { select: { imagemUrl: true } },
      adicionais: { select: { imagemUrl: true } },
    },
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };

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
  criar,
  atualizar,
  adicionarMateriais,
  marcarComprado,
  excluir,
  listarLogs,
  registrarSseCliente,
  contarNovas,
  marcarTodasComoVisualizadas,
};