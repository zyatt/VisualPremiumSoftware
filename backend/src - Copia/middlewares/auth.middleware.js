const jwt    = require('jsonwebtoken');
const prisma = require('../utils/prisma');

async function authMiddleware(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader) return res.status(401).json({ error: 'Token não fornecido' });

  const token = authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Formato inválido: Bearer <token>' });

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    const usuario = await prisma.usuario.findUnique({
      where:  { id: decoded.id },
      select: { id: true, nome: true, role: true, ativo: true },
    });

    if (!usuario || !usuario.ativo) {
      return res.status(401).json({ error: 'Usuário inativo ou não encontrado' });
    }

    req.usuario = {
      id:   usuario.id,
      nome: usuario.nome,
      role: usuario.role,
    };

    next();
  } catch (err) {
    return res.status(401).json({ error: 'Token inválido ou expirado' });
  }
}

const _negacoesRecentes = new Map();
const JANELA_MS = 60_000;
const LIMITE_ANTES_DE_ESPACAR = 3;

function _limparEntradasAntigas() {
  const agora = Date.now();
  for (const [chave, info] of _negacoesRecentes) {
    if (agora - info.desde > JANELA_MS) _negacoesRecentes.delete(chave);
  }
}

function roleMiddleware(rolesPermitidas) {
  return (req, res, next) => {
    if (!req.usuario) return res.status(401).json({ error: 'Não autenticado' });
    if (!rolesPermitidas.includes(req.usuario.role)) {
      const chave = `${req.usuario.id}:${req.baseUrl}${req.route ? req.route.path : req.path}`;
      const agora = Date.now();

      let info = _negacoesRecentes.get(chave);
      if (!info || agora - info.desde > JANELA_MS) {
        info = { desde: agora, contagem: 0 };
      }
      info.contagem += 1;
      _negacoesRecentes.set(chave, info);
      if (_negacoesRecentes.size > 1000) _limparEntradasAntigas();

      if (info.contagem === 1) {
        console.warn(
          `[roleMiddleware] usuário id=${req.usuario.id} nome="${req.usuario.nome}" ` +
          `role="${req.usuario.role}" sem permissão para ${req.method} ${req.originalUrl}. ` +
          `Roles permitidas: [${rolesPermitidas.join(', ')}]`
        );
      }

      if (info.contagem > LIMITE_ANTES_DE_ESPACAR) {
        return setTimeout(() => {
          res.status(403).json({ error: 'Acesso negado para sua role' });
        }, 1500);
      }

      return res.status(403).json({ error: 'Acesso negado para sua role' });
    }
    next();
  };
}

module.exports = { authMiddleware, roleMiddleware };