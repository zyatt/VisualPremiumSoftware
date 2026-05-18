// scripts/seedMateriais.js

require('dotenv').config();
console.log(process.env.DATABASE_URL);

const prisma = require('./src/utils/prisma');
function calcularStatus(quantidade, estoqueMinimo, ativo = true) {
  if (!ativo) return 'INATIVO';
  if (quantidade > estoqueMinimo) return 'OK';
  if (quantidade === estoqueMinimo) return 'LIMITE';
  return 'CRITICO';
}

const categorias = [
  'MDF',
  'Compensado',
  'Ferragem',
  'Parafuso',
  'Vidro',
  'Alumínio',
  'PVC',
  'Acessório',
];

const medidas = [
  '100x200',
  '120x220',
  '150x300',
  '200x275',
  '250x300',
];

const espessuras = [
  '3mm',
  '6mm',
  '9mm',
  '15mm',
  '18mm',
];

async function main() {
  const materiais = [];

  for (let i = 1; i <= 50; i++) {
    const quantidade = Math.floor(Math.random() * 100);
    const estoqueMinimo = Math.floor(Math.random() * 20) + 5;

    materiais.push({
      nome: `Material Teste ${i}`,
      categoria: categorias[i % categorias.length],
      medida: medidas[i % medidas.length],
      espessura: espessuras[i % espessuras.length],
      quantidade,
      estoqueMinimo,
      ativo: true,
      estoqueConfirmado: Math.random() > 0.5,
      status: calcularStatus(quantidade, estoqueMinimo, true),
    });
  }

  for (const material of materiais) {
    try {
      await prisma.material.create({
        data: material,
      });

      console.log(`✅ Inserido: ${material.nome}`);
    } catch (err) {
      console.error(`❌ Erro ao inserir ${material.nome}`, err.message);
    }
  }

  console.log('\n🚀 Seed finalizado!');
}

main()
  .catch((e) => {
    console.error(e);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });