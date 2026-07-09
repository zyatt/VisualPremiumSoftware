-- AlterTable
ALTER TABLE "adicionais_solicitacao_material" ADD COLUMN     "editadoEm" TIMESTAMP(3),
ADD COLUMN     "editadoPorNome" TEXT;

-- AlterTable
ALTER TABLE "itens_solicitacao_material" ADD COLUMN     "editadoEm" TIMESTAMP(3),
ADD COLUMN     "editadoPorNome" TEXT;

-- AlterTable
ALTER TABLE "logs_edicao_solicitacao" ADD COLUMN     "item" TEXT;
