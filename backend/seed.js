const { PrismaClient } = require('@prisma/client');
const { PrismaPg } = require('@prisma/adapter-pg');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter });

async function main() {
  const hash = await bcrypt.hash('producao123', 10);

  const usuario = await prisma.usuario.upsert({
    where: { username: 'producao' },
    update: {},
    create: {
      nome:     'Produção',
      username: 'producao',
      senha:    hash,
      role:     'PRODUCAO',
      ativo:    true,
    },
  });

  console.log('✅ Usuário criado:', usuario.username, '| role:', usuario.role);
}

main()
  .catch((e) => { console.error('❌ Erro:', e.message); process.exit(1); })
  .finally(() => prisma.$disconnect());