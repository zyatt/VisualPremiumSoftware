-- AlterTable
ALTER TABLE "materiais" ADD COLUMN     "especifico" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "ordem_compra_itens" ADD COLUMN     "descricaoItem" TEXT;
