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

function roleMiddleware(rolesPermitidas) {
  return (req, res, next) => {
    if (!req.usuario) return res.status(401).json({ error: 'Não autenticado' });
    if (!rolesPermitidas.includes(req.usuario.role)) {
      return res.status(403).json({ error: 'Acesso negado para sua role' });
    }
    next();
  };
}

module.exports = { authMiddleware, roleMiddleware };