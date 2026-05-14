const jwt = require('jsonwebtoken');

/**
 * Middleware de autenticação JWT.
 * Verifica token e injeta req.usuario com { id, username, role }.
 */
function authMiddleware(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader) return res.status(401).json({ error: 'Token não fornecido' });

  const token = authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Formato inválido: Bearer <token>' });

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.usuario = decoded; // { id, username, role }
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Token inválido ou expirado' });
  }
}

/**
 * Middleware de autorização por role.
 * Uso: roleMiddleware(['ADMIN', 'GERENTE'])
 * 
 * Hierarquia de roles:
 *   ADMIN        -> tudo
 *   GERENTE      -> tudo exceto gerenciar usuários
 *   COMPRADOR    -> Orçamento, Ordem de Compra, Histórico
 *   ESTOQUISTA   -> Estoque, Controle de Estoque, Relatórios OS
 *   VISUALIZADOR -> somente leitura (GET)
 */
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