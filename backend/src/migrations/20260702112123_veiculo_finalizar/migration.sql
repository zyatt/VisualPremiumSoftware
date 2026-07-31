-- AlterTable
ALTER TABLE "manutencoes_veiculo" ADD COLUMN     "finalizada" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "finalizadaEm" TIMESTAMP(3);
