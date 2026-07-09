const express = require('express');
const router = express.Router();
const prisma = require('../utils/prisma');
const { authMiddleware: autenticar } = require('../middlewares/auth.middleware');

const sseClients = new Map();

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

  // A conexão SSE só existe enquanto o app está aberto/em primeiro plano,
  // então ela serve como sinal de presença: conectou = está online.
  broadcastTodos({ tipo: 'usuario_online', usuarioId: userId });

  req.on('close', () => {
    clearInterval(heartbeat);
    sseClients.delete(userId);

    // Ao desconectar (app fechado, aba fechada, perda de rede etc.),
    // registra o momento como "último acesso" e avisa os demais usuários
    // conectados para que atualizem o indicador de status na hora.
    const agora = new Date();
    prisma.usuario
      .update({ where: { id: userId }, data: { ultimoAcesso: agora } })
      .then(() => {
        broadcastTodos({
          tipo: 'usuario_offline',
          usuarioId: userId,
          ultimoAcesso: agora,
        });
      })
      .catch((err) => console.error('Erro ao registrar último acesso:', err));
  });
});

function notificarUsuario(destinatarioId, evento) {
  const client = sseClients.get(destinatarioId);
  if (client) {
    client.write(`data: ${JSON.stringify(evento)}\n\n`);
  }
}

// Envia um evento para TODOS os usuários conectados via SSE no momento —
// usado pelos eventos de presença (online/offline), que interessam a
// qualquer um que tenha a lista de usuários do chat aberta, não só ao
// remetente/destinatário de uma mensagem específica.
function broadcastTodos(evento) {
  for (const client of sseClients.values()) {
    client.write(`data: ${JSON.stringify(evento)}\n\n`);
  }
}

router.post('/typing', autenticar, (req, res) => {
  const remetenteId = req.usuario.id;
  const { destinatarioId } = req.body;
  if (!destinatarioId) {
    return res.status(400).json({ error: 'destinatarioId é obrigatório' });
  }
  notificarUsuario(parseInt(destinatarioId), {
    tipo: 'digitando',
    remetenteId,
  });
  res.json({ ok: true });
});

router.get('/usuarios', autenticar, async (req, res) => {
  try {
    const meuId = req.usuario.id;
    const usuarios = await prisma.usuario.findMany({
      where: { ativo: true, id: { not: meuId } },
      select: { id: true, nome: true, role: true, ultimoAcesso: true },
      orderBy: { nome: 'asc' },
    });

    const comNaoLidas = await Promise.all(
      usuarios.map(async (u) => {
        const naoLidas = await prisma.mensagemChat.count({
          where: { remetenteId: u.id, destinatarioId: meuId, lida: false },
        });
        // "Online" = tem uma conexão SSE ativa neste momento (app aberto
        // em primeiro plano). Não depende de nenhum campo no banco.
        return { ...u, naoLidas, online: sseClients.has(u.id) };
      })
    );

    res.json(comNaoLidas);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao buscar usuários' });
  }
});

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
        respondendoA: {
          select: { id: true, conteudo: true, remetente: { select: { nome: true } } },
        },
      },
    });

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

router.post('/mensagem', autenticar, async (req, res) => {
  try {
    const remetenteId    = req.usuario.id;
    const { destinatarioId, conteudo, respondendoAId } = req.body;

    if (!destinatarioId || !conteudo?.trim()) {
      return res.status(400).json({ error: 'destinatarioId e conteudo são obrigatórios' });
    }

    let respondendoAIdValido = undefined;
    if (respondendoAId) {
      const citada = await prisma.mensagemChat.findUnique({
        where: { id: parseInt(respondendoAId) },
      });
      const mesmaConversa = citada && (
        (citada.remetenteId === remetenteId && citada.destinatarioId === parseInt(destinatarioId)) ||
        (citada.destinatarioId === remetenteId && citada.remetenteId === parseInt(destinatarioId))
      );
      if (mesmaConversa) respondendoAIdValido = citada.id;
    }

    const mensagem = await prisma.mensagemChat.create({
      data: {
        remetenteId,
        destinatarioId: parseInt(destinatarioId),
        conteudo: conteudo.trim(),
        ...(respondendoAIdValido ? { respondendoAId: respondendoAIdValido } : {}),
      },
      include: {
        remetente:    { select: { id: true, nome: true } },
        destinatario: { select: { id: true, nome: true } },
        respondendoA: {
          select: { id: true, conteudo: true, remetente: { select: { nome: true } } },
        },
      },
    });

    notificarUsuario(parseInt(destinatarioId), {
      tipo: 'nova_mensagem',
      mensagem,
    });

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

router.patch('/mensagem/:id/reacao', autenticar, async (req, res) => {
  try {
    const meuId       = req.usuario.id;
    const mensagemId  = parseInt(req.params.id);
    const { emoji }   = req.body;

    const mensagem = await prisma.mensagemChat.findUnique({
      where: { id: mensagemId },
    });
    if (!mensagem) {
      return res.status(404).json({ error: 'Mensagem não encontrada' });
    }
    if (mensagem.remetenteId !== meuId && mensagem.destinatarioId !== meuId) {
      return res.status(403).json({ error: 'Sem permissão para reagir a esta mensagem' });
    }

    const reacoesAtuais = mensagem.reacoes && typeof mensagem.reacoes === 'object'
      ? { ...mensagem.reacoes }
      : {};

    if (emoji) {
      reacoesAtuais[String(meuId)] = emoji;
    } else {
      delete reacoesAtuais[String(meuId)];
    }

    const atualizada = await prisma.mensagemChat.update({
      where: { id: mensagemId },
      data:  { reacoes: reacoesAtuais },
      include: {
        remetente:    { select: { id: true, nome: true } },
        destinatario: { select: { id: true, nome: true } },
        respondendoA: {
          select: { id: true, conteudo: true, remetente: { select: { nome: true } } },
        },
      },
    });

    const evento = { tipo: 'reacao_atualizada', mensagem: atualizada };

    notificarUsuario(atualizada.remetenteId, evento);
    notificarUsuario(atualizada.destinatarioId, evento);

    res.json(atualizada);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao reagir à mensagem' });
  }
});

router.patch('/mensagem/:id', autenticar, async (req, res) => {
  try {
    const meuId      = req.usuario.id;
    const mensagemId = parseInt(req.params.id);
    const { conteudo } = req.body;

    if (!conteudo?.trim()) {
      return res.status(400).json({ error: 'conteudo é obrigatório' });
    }

    const mensagem = await prisma.mensagemChat.findUnique({
      where: { id: mensagemId },
    });
    if (!mensagem) {
      return res.status(404).json({ error: 'Mensagem não encontrada' });
    }
    // Só o próprio remetente pode editar sua mensagem.
    if (mensagem.remetenteId !== meuId) {
      return res.status(403).json({ error: 'Sem permissão para editar esta mensagem' });
    }
    if (mensagem.apagada) {
      return res.status(400).json({ error: 'Não é possível editar uma mensagem apagada' });
    }

    const atualizada = await prisma.mensagemChat.update({
      where: { id: mensagemId },
      data: { conteudo: conteudo.trim(), editadaEm: new Date() },
      include: {
        remetente:    { select: { id: true, nome: true } },
        destinatario: { select: { id: true, nome: true } },
        respondendoA: {
          select: { id: true, conteudo: true, remetente: { select: { nome: true } } },
        },
      },
    });

    const evento = { tipo: 'mensagem_editada', mensagem: atualizada };
    notificarUsuario(atualizada.remetenteId, evento);
    notificarUsuario(atualizada.destinatarioId, evento);

    res.json(atualizada);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao editar mensagem' });
  }
});

router.delete('/mensagem/:id', autenticar, async (req, res) => {
  try {
    const meuId      = req.usuario.id;
    const mensagemId = parseInt(req.params.id);

    const mensagem = await prisma.mensagemChat.findUnique({
      where: { id: mensagemId },
    });
    if (!mensagem) {
      return res.status(404).json({ error: 'Mensagem não encontrada' });
    }
    // Só o próprio remetente pode excluir sua mensagem.
    if (mensagem.remetenteId !== meuId) {
      return res.status(403).json({ error: 'Sem permissão para excluir esta mensagem' });
    }

    // Exclusão lógica: mantém a linha (preserva o histórico/citações de
    // quem respondeu a ela) mas marca como apagada e esvazia o conteúdo,
    // para a UI trocar pelo texto "Mensagem apagada".
    const atualizada = await prisma.mensagemChat.update({
      where: { id: mensagemId },
      data: { conteudo: '', apagada: true, reacoes: {} },
      include: {
        remetente:    { select: { id: true, nome: true } },
        destinatario: { select: { id: true, nome: true } },
        respondendoA: {
          select: { id: true, conteudo: true, remetente: { select: { nome: true } } },
        },
      },
    });

    const evento = { tipo: 'mensagem_apagada', mensagem: atualizada };
    notificarUsuario(atualizada.remetenteId, evento);
    notificarUsuario(atualizada.destinatarioId, evento);

    res.json(atualizada);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erro ao excluir mensagem' });
  }
});

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
module.exports.broadcastTodos = broadcastTodos;