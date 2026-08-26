/*
  Warnings:

  - You are about to drop the column `dataSolicitacao` on the `solicitacoes_material` table. All the data in the column will be lost.
  - You are about to drop the column `imagemUrl` on the `solicitacoes_material` table. All the data in the column will be lost.
  - You are about to drop the column `materialId` on the `solicitacoes_material` table. All the data in the column will be lost.
  - You are about to drop the column `quantidade` on the `solicitacoes_material` table. All the data in the column will be lost.
  - A unique constraint covering the columns `[numeroOS]` on the table `solicitacoes_material` will be added. If there are existing duplicate values, this will fail.

*/
-- DropForeignKey
ALTER TABLE "solicitacoes_material" DROP CONSTRAINT "solicitacoes_material_materialId_fkey";

-- AlterTable
ALTER TABLE "solicitacoes_material" DROP COLUMN "dataSolicitacao",
DROP COLUMN "imagemUrl",
DROP COLUMN "materialId",
DROP COLUMN "quantidade";

-- CreateTable
CREATE TABLE "itens_solicitacao_material" (
    "id" SERIAL NOT NULL,
    "solicitacaoId" INTEGER NOT NULL,
    "materialId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL,
    "observacao" TEXT,
    "imagemUrl" TEXT,
    "comprado" BOOLEAN NOT NULL DEFAULT false,
    "compradoEm" TIMESTAMP(3),
    "compradoPorId" INTEGER,
    "compradoPorNome" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "itens_solicitacao_material_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "adicionais_solicitacao_material" (
    "id" SERIAL NOT NULL,
    "solicitacaoId" INTEGER NOT NULL,
    "materialId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL,
    "observacao" TEXT,
    "imagemUrl" TEXT,
    "adicionadoPorId" INTEGER NOT NULL,
    "adicionadoPorNome" TEXT NOT NULL,
    "adicionadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "comprado" BOOLEAN NOT NULL DEFAULT false,
    "compradoEm" TIMESTAMP(3),
    "compradoPorId" INTEGER,
    "compradoPorNome" TEXT,

    CONSTRAINT "adicionais_solicitacao_material_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "itens_solicitacao_material_solicitacaoId_idx" ON "itens_solicitacao_material"("solicitacaoId");

-- CreateIndex
CREATE INDEX "adicionais_solicitacao_material_solicitacaoId_idx" ON "adicionais_solicitacao_material"("solicitacaoId");

-- CreateIndex
CREATE UNIQUE INDEX "solicitacoes_material_numeroOS_key" ON "solicitacoes_material"("numeroOS");

-- AddForeignKey
ALTER TABLE "itens_solicitacao_material" ADD CONSTRAINT "itens_solicitacao_material_solicitacaoId_fkey" FOREIGN KEY ("solicitacaoId") REFERENCES "solicitacoes_material"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "itens_solicitacao_material" ADD CONSTRAINT "itens_solicitacao_material_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "adicionais_solicitacao_material" ADD CONSTRAINT "adicionais_solicitacao_material_solicitacaoId_fkey" FOREIGN KEY ("solicitacaoId") REFERENCES "solicitacoes_material"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "adicionais_solicitacao_material" ADD CONSTRAINT "adicionais_solicitacao_material_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
