// routes/chat.routes.js
const express = require('express');
const router = express.Router();
const prisma = require('../utils/prisma');
const { authMiddleware: autenticar } = require('../middlewares/auth.middleware');

// SSE clients map: userId -> res
const sseClients = new Map();

// GET /api/chat/sse - Server-Sent Events stream para mensagens em tempo real
router.get('/sse', autenticar, (req, res) => {
  const userId = req.usuario.id;

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.flushHeaders();

  res.write(`data: ${JSON.stringify({ tipo: 'conectado', userId })}\n\n`);

  const heartbeat = setInterval(() => {
    res.write(': heartbeat\n\n');
  }, 25000);

  sseClients.set(userId, res);

  req.on('close', () => {
    clearInterval(heartbeat);
    sseClients.delete(userId);
  });
});

function notificarUsuario(destinatarioId, evento) {
  const client = sseClients.get(destinatarioId);
  if (client) {
    client.write(`data: ${JSON.stringify(evento)}\n\n`);
  }
}

// GET /api/chat/usuarios - Lista todos os usuários ativos (exceto o próprio)
router.get('/usuarios', autenticar, async (req, res) => {
  try {
    const meuId = req.usuario.id;
    const usuarios = await prisma.usuario.findMany({
      where: { ativo: true, id: { not: meuId } },
      select: { id: true, nome: true, role: true },
      orderBy: { nome: 'asc' },
    });

    // Para cada usuário, conta mensagens não lidas enviadas por ele para mim
    const comNaoLidas = await Promise.all(
      usuarios.map(async (u) => {
        const naoLidas = await prisma.mensagemChat.count({
          where: { remetenteId: u.id, destinatarioId: meuId, lida: false },
        });
        return { ...u, naoLidas };
      })
    );

    res.json(comNaoLidas);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao buscar usuários' });
  }
});

// GET /api/chat/conversa/:outroId - Histórico de conversa entre dois usuários
router.get('/conversa/:outroId', autenticar, async (req, res) => {
  try {
    const meuId   = req.usuario.id;
    const outroId = parseInt(req.params.outroId);
    const limit   = parseInt(req.query.limit) || 50;
    const before  = req.query.before ? new Date(req.query.before) : undefined;

    const where = {
      OR: [
        { remetenteId: meuId,   destinatarioId: outroId },
        { remetenteId: outroId, destinatarioId: meuId   },
      ],
      ...(before ? { criadoEm: { lt: before } } : {}),
    };

    const mensagens = await prisma.mensagemChat.findMany({
      where,
      orderBy: { criadoEm: 'desc' },
      take: limit,
      include: {
        remetente:    { select: { id: true, nome: true } },
        destinatario: { select: { id: true, nome: true } },
      },
    });

    // Marca como lidas as mensagens do outro para mim
    await prisma.mensagemChat.updateMany({
      where: { remetenteId: outroId, destinatarioId: meuId, lida: false },
      data:  { lida: true },
    });

    res.json(mensagens.reverse());
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao buscar conversa' });
  }
});

// POST /api/chat/mensagem - Envia uma mensagem
router.post('/mensagem', autenticar, async (req, res) => {
  try {
    const remetenteId    = req.usuario.id;
    const { destinatarioId, conteudo } = req.body;

    if (!destinatarioId || !conteudo?.trim()) {
      return res.status(400).json({ error: 'destinatarioId e conteudo são obrigatórios' });
    }

    const mensagem = await prisma.mensagemChat.create({
      data: {
        remetenteId,
        destinatarioId: parseInt(destinatarioId),
        conteudo: conteudo.trim(),
      },
      include: {
        remetente:    { select: { id: true, nome: true } },
        destinatario: { select: { id: true, nome: true } },
      },
    });

    // Notifica destinatário via SSE
    notificarUsuario(parseInt(destinatarioId), {
      tipo: 'nova_mensagem',
      mensagem,
    });

    // Notifica o próprio remetente (para sync multi-dispositivo)
    notificarUsuario(remetenteId, {
      tipo: 'mensagem_enviada',
      mensagem,
    });

    res.status(201).json(mensagem);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao enviar mensagem' });
  }
});

// PATCH /api/chat/lidas/:outroId - Marca todas as mensagens de outroId para mim como lidas
router.patch('/lidas/:outroId', autenticar, async (req, res) => {
  try {
    const meuId   = req.usuario.id;
    const outroId = parseInt(req.params.outroId);
    await prisma.mensagemChat.updateMany({
      where: { remetenteId: outroId, destinatarioId: meuId, lida: false },
      data:  { lida: true },
    });
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao marcar como lidas' });
  }
});

// GET /api/chat/nao-lidas - Total de mensagens não lidas para o usuário logado
router.get('/nao-lidas', autenticar, async (req, res) => {
  try {
    const meuId = req.usuario.id;
    const total = await prisma.mensagemChat.count({
      where: { destinatarioId: meuId, lida: false },
    });
    res.json({ total });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao contar não lidas' });
  }
});

module.exports = router;
module.exports.notificarUsuario = notificarUsuario;