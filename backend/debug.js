require('dotenv').config();
const prisma = require('./src/utils/prisma');


async function main() {
  try {
    const result = await prisma.ordemCompra.findMany({
      include: {
        fornecedor: { select: { id: true, nomeFantasia: true } },
        usuario:    { select: { id: true, nome: true } },
        itens: { include: { material: true } },
        numerosOS: true,
      },
      orderBy: { criadoEm: 'desc' },
    });
    console.log('OK, registros encontrados:', result.length);
  } catch (e) {
    console.log('--- ERRO COMPLETO ---');
    console.log('name:', e.name);
    console.log('code:', e.code);
    console.log('message:', e.message);
    console.log('meta:', e.meta);
  } finally {
    await prisma.$disconnect();
  }
}

main();