-- DropForeignKey
ALTER TABLE "ordem_compra_itens" DROP CONSTRAINT "ordem_compra_itens_materialId_fkey";

-- AlterTable
ALTER TABLE "ordem_compra_itens" ALTER COLUMN "materialId" DROP NOT NULL;

-- AddForeignKey
ALTER TABLE "ordem_compra_itens" ADD CONSTRAINT "ordem_compra_itens_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE SET NULL ON UPDATE CASCADE;
