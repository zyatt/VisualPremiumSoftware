// removerOrcamentos.js

require('dotenv').config();

const prisma = require('./src/utils/prisma');

async function main() {
  try {
    console.log('🔄 Removendo relação de orçamentos das OCs...');

    await prisma.ordemCompra.updateMany({
      data: {
        orcamentoId: null,
      },
    });

    console.log('🔄 Removendo itens dos orçamentos...');

    await prisma.orcamentoItem.deleteMany();

    console.log('🔄 Removendo orçamentos...');

    const resultado = await prisma.orcamento.deleteMany();

    console.log(`✅ ${resultado.count} orçamentos removidos.`);
  } catch (err) {
    console.error('❌ Erro:', err);
  } finally {
    await prisma.$disconnect();
  }
}

main();