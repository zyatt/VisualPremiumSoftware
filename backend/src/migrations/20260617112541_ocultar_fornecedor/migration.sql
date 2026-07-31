-- AlterTable
ALTER TABLE "orcamentos" ADD COLUMN     "fornecedoresOcultos" INTEGER[] DEFAULT ARRAY[]::INTEGER[];
