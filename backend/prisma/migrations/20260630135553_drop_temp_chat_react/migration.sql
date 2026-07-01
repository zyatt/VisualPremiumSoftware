/*
  Warnings:

  - You are about to drop the column `criadoPorNome` on the `materiais` table. All the data in the column will be lost.
  - You are about to drop the column `desativaEm` on the `materiais` table. All the data in the column will be lost.
  - You are about to drop the column `observacaoTemporario` on the `materiais` table. All the data in the column will be lost.
  - You are about to drop the column `temporario` on the `materiais` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "materiais" DROP COLUMN "criadoPorNome",
DROP COLUMN "desativaEm",
DROP COLUMN "observacaoTemporario",
DROP COLUMN "temporario";

-- AlterTable
ALTER TABLE "mensagens_chat" ADD COLUMN     "reacoes" JSONB NOT NULL DEFAULT '{}';
