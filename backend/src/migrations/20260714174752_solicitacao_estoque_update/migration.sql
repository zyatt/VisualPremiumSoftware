-- AlterTable
ALTER TABLE "adicionais_solicitacao_material" ADD COLUMN     "estoque" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "estoqueEm" TIMESTAMP(3),
ADD COLUMN     "estoquePorId" INTEGER,
ADD COLUMN     "estoquePorNome" TEXT;

-- AlterTable
ALTER TABLE "itens_solicitacao_material" ADD COLUMN     "estoque" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "estoqueEm" TIMESTAMP(3),
ADD COLUMN     "estoquePorId" INTEGER,
ADD COLUMN     "estoquePorNome" TEXT;
