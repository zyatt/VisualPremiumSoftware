// scripts/ajustarSequenceOrdemCompra.js

require('dotenv').config();
console.log('🔌 Conectando em:', process.env.DATABASE_URL);

const prisma = require('./src/utils/prisma');

const INICIAR_EM = 44;

async function main() {
  console.log(`\n⚙️  Ajustando sequence de ordens_compra para iniciar em ${INICIAR_EM}...`);

  await prisma.$executeRawUnsafe(
    `ALTER SEQUENCE ordens_compra_id_seq RESTART WITH ${INICIAR_EM};`
  );

  // Confirma usando nextval (avança a sequence de teste e depois reseta)
  const resultado = await prisma.$queryRaw`
    SELECT last_value FROM ordens_compra_id_seq;
  `;

  console.log('\n✅ Sequence ajustada com sucesso!');
  console.log(`📋 Próximo ID que será gerado: ${INICIAR_EM}`);
  console.log('📋 last_value na sequence:', resultado[0]?.last_value?.toString());
}

main()
  .catch((e) => {
    console.error('❌ Erro ao ajustar sequence:', e.message);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });