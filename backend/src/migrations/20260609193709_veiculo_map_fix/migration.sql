/*
  Warnings:

  - You are about to drop the `ManutencaoVeiculo` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `Veiculo` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropForeignKey
ALTER TABLE "ManutencaoVeiculo" DROP CONSTRAINT "ManutencaoVeiculo_veiculoId_fkey";

-- DropTable
DROP TABLE "ManutencaoVeiculo";

-- DropTable
DROP TABLE "Veiculo";

-- CreateTable
CREATE TABLE "veiculos" (
    "id" SERIAL NOT NULL,
    "nome" TEXT NOT NULL,
    "placa" TEXT NOT NULL,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "veiculos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "manutencoes_veiculo" (
    "id" SERIAL NOT NULL,
    "veiculoId" INTEGER NOT NULL,
    "tipo" TEXT NOT NULL,
    "descricao" TEXT,
    "valor" DECIMAL(10,2) NOT NULL,
    "dataEnvio" TIMESTAMP(3) NOT NULL,
    "dataRetirada" TIMESTAMP(3),
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "manutencoes_veiculo_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "veiculos_placa_key" ON "veiculos"("placa");

-- AddForeignKey
ALTER TABLE "manutencoes_veiculo" ADD CONSTRAINT "manutencoes_veiculo_veiculoId_fkey" FOREIGN KEY ("veiculoId") REFERENCES "veiculos"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
