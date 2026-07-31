const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const prisma = require('../utils/prisma');

async function login(username, senha) {
  const usuario = await prisma.usuario.findUnique({ where: { username } });
  if (!usuario || !usuario.ativo) throw { status: 401, message: 'Credenciais inválidas' };

  const senhaOk = await bcrypt.compare(senha, usuario.senha);
  if (!senhaOk) throw { status: 401, message: 'Credenciais inválidas' };

  const token = jwt.sign(
    { id: usuario.id, username: usuario.username, role: usuario.role },
    process.env.JWT_SECRET
  );

  return {
    token,
    usuario: { id: usuario.id, nome: usuario.nome, username: usuario.username, role: usuario.role },
  };
}

async function refresh(payload) {
  const token = jwt.sign(
    { id: payload.id, username: payload.username, role: payload.role },
    process.env.JWT_SECRET
  );
  return { token };
}

async function trocarUsuario(idAlvo) {
  const usuario = await prisma.usuario.findUnique({ where: { id: idAlvo } });
  if (!usuario || !usuario.ativo) throw { status: 404, message: 'Usuário não encontrado ou inativo' };

  const token = jwt.sign(
    { id: usuario.id, username: usuario.username, role: usuario.role },
    process.env.JWT_SECRET
  );

  return {
    token,
    usuario: { id: usuario.id, nome: usuario.nome, username: usuario.username, role: usuario.role },
  };
}

async function listar() {
  return prisma.usuario.findMany({
    select: { id: true, nome: true, username: true, role: true, ativo: true, criadoEm: true },
    orderBy: { nome: 'asc' },
  });
}

async function criar(data) {
  const hash = await bcrypt.hash(data.senha, 10);
  return prisma.usuario.create({
    data: { ...data, senha: hash },
    select: { id: true, nome: true, username: true, role: true, ativo: true },
  });
}

async function atualizar(id, data) {
  if (data.senha) data.senha = await bcrypt.hash(data.senha, 10);
  return prisma.usuario.update({ where: { id }, data });
}

async function remover(id) {
  return prisma.usuario.delete({ where: { id } });
}

module.exports = { login, refresh, trocarUsuario, listar, criar, atualizar, remover };