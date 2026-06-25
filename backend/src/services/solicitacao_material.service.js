const prisma = require('../utils/prisma');
const path  = require('path');
const fs    = require('fs');

// ─── SSE: mapa de clientes conectados ────────────────────────────────────────
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
  const evento = { tipo, ...dados };
  const payload = `data: ${JSON.stringify(evento)}\n\n`;
  
  let enviados = 0;
  for (const { res, usuarioId } of _sseClients.values()) {
    if (excludeUsuarioId !== undefined && usuarioId === excludeUsuarioId) {
      continue;
    }
    try {
      res.write(payload);
      enviados++;
    } catch (err) {
      console.error(`[SSE Solicitações] Erro ao enviar para usuário ${usuarioId}: ${err.message}`);
    }
  }
  
  console.log(`[SSE Solicitações] Evento '${tipo}' enviado para ${enviados} cliente(s)`);
}

// ─── Include base ─────────────────────────────────────────────────────────────
const _includeBase = {
  material: {
    select: {
      id: true,
      nome: true,
      unidade: true,
      identificador: true,
      medida: true,
      espessura: true,
      categoria: true,
      quantidade: true,
    },
  },
  usuario: {
    select: { id: true, nome: true, role: true },
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
      { material: { nome: { contains: busca, mode: 'insensitive' } } },
    ];
  }
  if (andamento)  where.andamento  = andamento;
  if (materialId) where.materialId = Number(materialId);
  if (numeroOS)   where.numeroOS   = { contains: numeroOS, mode: 'insensitive' };

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

// ─── Logs de edição ───────────────────────────────────────────────────────────
async function listarLogs(solicitacaoId) {
  return prisma.logEdicaoSolicitacao.findMany({
    where: { solicitacaoId },
    orderBy: { editadoEm: 'desc' },
  });
}

// ─── Snapshot legível dos campos relevantes ───────────────────────────────────
function _snapshot(sol) {
  return {
    materialId:      sol.materialId,
    quantidade:      sol.quantidade?.toString(),
    numeroOS:        sol.numeroOS,
    nomeCliente:     sol.nomeCliente,
    dataSolicitacao: sol.dataSolicitacao,
    dataNecessidade: sol.dataNecessidade,
    andamento:       sol.andamento,
    observacao:      sol.observacao ?? null,
    imagemUrl:       sol.imagemUrl  ?? null,
  };
}

// ─── Criar ────────────────────────────────────
async function criar(data, usuarioId, usuarioNome) {
  const material = await prisma.material.findUnique({
    where: { id: data.materialId },
    select: { id: true, nome: true, ativo: true },
  });
  if (!material)       throw { status: 404, message: 'Material não encontrado' };
  if (!material.ativo) throw { status: 400, message: 'Material inativo não pode ser solicitado' };

  const nova = await prisma.solicitacaoMaterial.create({
    data: {
      materialId:      data.materialId,
      quantidade:      data.quantidade,
      numeroOS:        data.numeroOS,
      nomeCliente:     data.nomeCliente,
      dataNecessidade: new Date(data.dataNecessidade),
      andamento:       'EM_ANDAMENTO',
      observacao:      data.observacao ?? null,
      imagemUrl:       data.imagemUrl  ?? null,
      usuarioId,
      usuarioNome,
    },
    include: _includeBase,
  });

  console.log(`[Solicitações] Nova solicitação criada: ID ${nova.id} por usuário ${usuarioId}`);

  // Notifica todos os outros usuários via SSE (exclui quem criou)
  _broadcast('nova_solicitacao', {
    id:          nova.id,
    numeroOS:    nova.numeroOS,
    nomeCliente: nova.nomeCliente,
    material:    nova.material?.nome,
    usuarioNome: nova.usuarioNome,
    criadoEm:    nova.criadoEm,
  }, usuarioId); // <-- passa usuarioId para excluir o criador do broadcast

  return nova;
}

// ─── Atualizar ────────────────────────────────────────────────────────────────
async function atualizar(id, data, editorId, editorNome) {
  const solicitacao = await prisma.solicitacaoMaterial.findUnique({ where: { id } });
  if (!solicitacao) throw { status: 404, message: 'Solicitação não encontrada' };

  const snapshotAntes = _snapshot(solicitacao);
  const updateData    = {};

  if (data.materialId !== undefined) {
    const materialId = Number(data.materialId);
    const material   = await prisma.material.findUnique({
      where: { id: materialId },
      select: { id: true, nome: true, ativo: true },
    });
    if (!material)       throw { status: 404, message: 'Material não encontrado' };
    if (!material.ativo) throw { status: 400, message: 'Material inativo não pode ser solicitado' };
    updateData.material = { connect: { id: materialId } };
  }

  if (data.quantidade      !== undefined) updateData.quantidade      = data.quantidade;
  if (data.numeroOS        !== undefined) updateData.numeroOS        = data.numeroOS;
  if (data.nomeCliente     !== undefined) updateData.nomeCliente     = data.nomeCliente;
  if (data.dataNecessidade !== undefined) updateData.dataNecessidade = new Date(data.dataNecessidade);
  if (data.dataSolicitacao !== undefined) updateData.dataSolicitacao = new Date(data.dataSolicitacao);
  if (data.andamento       !== undefined) updateData.andamento       = data.andamento;
  if (data.observacao      !== undefined) updateData.observacao      = data.observacao;
  if (data.imagemUrl       !== undefined) updateData.imagemUrl       = data.imagemUrl;

  const atualizado = await prisma.solicitacaoMaterial.update({
    where: { id },
    data:  updateData,
    include: _includeBase,
  });

  if (editorId) {
    const snapshotDepois = _snapshot(atualizado);
    const houveMudanca = Object.keys(snapshotAntes).some((key) => {
      const a = snapshotAntes[key] instanceof Date
        ? snapshotAntes[key].toISOString()
        : String(snapshotAntes[key] ?? '');
      const d = snapshotDepois[key] instanceof Date
        ? snapshotDepois[key].toISOString()
        : String(snapshotDepois[key] ?? '');
      return a !== d;
    });
    if (houveMudanca) {
      await prisma.logEdicaoSolicitacao.create({
        data: {
          solicitacaoId: id,
          editorId,
          editorNome:    editorNome ?? 'Desconhecido',
          antes:         snapshotAntes,
          depois:        snapshotDepois,
        },
      });
    }
  }

  return atualizado;
}

// ─── Excluir ──────────────────────────────────
async function excluir(id) {
  const solicitacao = await prisma.solicitacaoMaterial.findUnique({ where: { id } });
  if (!solicitacao) throw { status: 404, message: 'Solicitação não encontrada' };

  if (solicitacao.imagemUrl) {
    const disco = path.join(
      __dirname, '..', 'uploads', 'solicitacoes',
      path.basename(solicitacao.imagemUrl),
    );
    fs.unlink(disco, () => {});
  }

  return prisma.solicitacaoMaterial.delete({ where: { id } });
}

// ─── Contar novas (não visualizadas pelo usuário nos últimos 7 dias) ──────────
// Igual à lógica de `lida` do Chat: conta apenas as que o usuário ainda não
// registrou como visualizadas E que não foram criadas por ele mesmo.
async function contarNovas(usuarioId) {
  const dataCorte = new Date();
  dataCorte.setDate(dataCorte.getDate() - 7);

  return prisma.solicitacaoMaterial.count({
    where: {
      criadoEm:  { gte: dataCorte },
      usuarioId: { not: usuarioId }, // ignora as próprias solicitações
      NOT: {
        visualizacoes: {
          some: { usuarioId }, // ignora as já visualizadas
        },
      },
    },
  });
}

// ─── Marcar todas as solicitações não visualizadas como vistas ────────────────
// Chamado quando o usuário entra na página. Insere registros de visualização
// para todas as solicitações dos últimos 7 dias que ele ainda não viu.
async function marcarTodasComoVisualizadas(usuarioId) {
  const dataCorte = new Date();
  dataCorte.setDate(dataCorte.getDate() - 7);

  // Busca IDs das solicitações não visualizadas por este usuário
  const naoVistas = await prisma.solicitacaoMaterial.findMany({
    where: {
      criadoEm:  { gte: dataCorte },
      usuarioId: { not: usuarioId },
      NOT: {
        visualizacoes: {
          some: { usuarioId },
        },
      },
    },
    select: { id: true },
  });

  if (naoVistas.length === 0) return 0;

  // Insere as visualizações em lote, ignorando duplicatas (upsert seguro)
  await prisma.visualizacaoSolicitacao.createMany({
    data: naoVistas.map((s) => ({
      usuarioId,
      solicitacaoId: s.id,
    })),
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
  excluir,
  listarLogs,
  registrarSseCliente,
  contarNovas,
  marcarTodasComoVisualizadas,
};