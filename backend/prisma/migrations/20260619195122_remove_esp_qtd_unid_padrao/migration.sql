/*
  Warnings:

  - You are about to drop the column `especifico` on the `materiais` table. All the data in the column will be lost.
  - You are about to drop the column `qtdPadrao` on the `materiais` table. All the data in the column will be lost.
  - You are about to drop the column `unidPadrao` on the `materiais` table. All the data in the column will be lost.
  - You are about to drop the `estoque_especificos` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropForeignKey
ALTER TABLE "estoque_especificos" DROP CONSTRAINT "estoque_especificos_materialId_fkey";

-- AlterTable
ALTER TABLE "materiais" DROP COLUMN "especifico",
DROP COLUMN "qtdPadrao",
DROP COLUMN "unidPadrao";

-- DropTable
DROP TABLE "estoque_especificos";
