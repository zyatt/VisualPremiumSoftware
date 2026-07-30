const express = require('express');
const router = express.Router();
const prisma = require('../utils/prisma');
const { authMiddleware: autenticar } = require('../middlewares/auth.middleware');

const sseClients = new Map();

// ── Presença baseada em heartbeat (TTL) ─────────────────────────────────────
// Antes, "online" dependia inteiramente de existir uma conexão SSE viva no
// Map acima. Se a reconexão do app travar num estado intermediário (erro
// silencioso, rede oscilando), o cliente pode nunca voltar a entrar nesse
// Map — mesmo com o app aberto — deixando o usuário preso como offline.
// Agora a presença é decidida por um "último heartbeat" recebido via
// POST /chat/heartbeat, enviado periodicamente pelo app independente do
// estado da conexão SSE. Um sweep periódico marca como offline quem parou
// de mandar heartbeat.
const PRESENCA_TTL_MS   = 45_000; // sem heartbeat há mais que isso = offline
const PRESENCA_SWEEP_MS = 15_000;

const presenca = new Map(); // usuarioId -> timestamp (ms) do último heartbeat
const jaOnline = new Set(); // usuarioId atualmente online (evita broadcast repetido a cada heartbeat)

function marcarOnline(userId) {
  presenca.set(userId, Date.now());
  if (!jaOnline.has(userId)) {
    jaOnline.add(userId);
    broadcastTodos({ tipo: 'usuario_online', usuarioId: userId });
  }
}

function estaOnline(userId) {
  const ts = presenca.get(userId);
  return ts != null && (Date.now() - ts) < PRESENCA_TTL_MS;
}

function verificarPresencaExpirada() {
  const agora = Date.now();
  for (const [userId, ts] of presenca) {
    if (agora - ts > PRESENCA_TTL_MS) {
      presenca.delete(userId);
      jaOnline.delete(userId);

      const ultimoAcesso = new Date();
      prisma.usuario
        .update({ where: { id: userId }, data: { ultimoAcesso } })
        .then(() => {
          broadcastTodos({
            tipo: 'usuario_offline',
            usuarioId: userId,
            ultimoAcesso,
          });
        })
        .catch((err) => console.error('Erro ao registrar último acesso:', err));
    }
  }
}
setInterval(verificarPresencaExpirada, PRESENCA_SWEEP_MS);

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

  // Abrir a conexão SSE também conta como sinal de presença, mas quem
  // efetivamente mantém o status "online" atualizado é o heartbeat HTTP
  // abaixo — não a conexão em si.
  marcarOnline(userId);

  req.on('close', () => {
    clearInterval(heartbeat);
    sseClients.delete(userId);
    // Não marca offline aqui de propósito: perder a conexão SSE não
    // significa necessariamente que o app foi fechado (rede oscilando,
    // troca de rede, app em background momentâneo etc.). Quem decide
    // offline agora é exclusivamente o sweep de presença acima.
  });
});

// Ping periódico enviado pelo app enquanto está aberto, independente do
// estado da conexão SSE. É isso que evita o usuário ficar preso como
// offline quando o SSE está com problema de reconexão.
router.post('/heartbeat', autenticar, (req, res) => {
  marcarOnline(req.usuario.id);
  res.json({ ok: true });
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
        // "Online" = recebemos um heartbeat desse usuário há menos que
        // PRESENCA_TTL_MS. Não depende mais de existir uma conexão SSE
        // viva no Map (ver bloco de presença acima).
        return { ...u, naoLidas, online: estaOnline(u.id) };
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