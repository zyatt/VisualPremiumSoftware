/*
  Warnings:

  - The values [PRODUCAO] on the enum `Role` will be removed. If these variants are still used in the database, this will fail.
  - A unique constraint covering the columns `[materialId,producao]` on the table `estoque_producao` will be added. If there are existing duplicate values, this will fail.
  - Added the required column `producao` to the `estoque_producao` table without a default value. This is not possible if the table is not empty.
  - Added the required column `producao` to the `movimentacoes_producao` table without a default value. This is not possible if the table is not empty.

*/

-- AlterEnum
BEGIN;
CREATE TYPE "Role_new" AS ENUM ('ADMIN', 'GERENTE', 'COMPRAS', 'PRODUCAO1', 'PRODUCAO2', 'ORCAMENTISTA');
ALTER TABLE "public"."usuarios" ALTER COLUMN "role" DROP DEFAULT;
ALTER TABLE "usuarios" ALTER COLUMN "role" TYPE "Role_new" USING (
  CASE WHEN "role"::text = 'PRODUCAO' THEN 'PRODUCAO1' ELSE "role"::text END
)::"Role_new";
ALTER TYPE "Role" RENAME TO "Role_old";
ALTER TYPE "Role_new" RENAME TO "Role";
DROP TYPE "public"."Role_old";
ALTER TABLE "usuarios" ALTER COLUMN "role" SET DEFAULT 'COMPRAS';
COMMIT;

-- DropIndex
DROP INDEX "estoque_producao_materialId_key";

-- AlterTable: estoque_producao (nullable -> popular -> NOT NULL)
ALTER TABLE "estoque_producao" ADD COLUMN "producao" TEXT;
UPDATE "estoque_producao" SET "producao" = '1';
ALTER TABLE "estoque_producao" ALTER COLUMN "producao" SET NOT NULL;

-- AlterTable
ALTER TABLE "movimentacoes_estoque" ADD COLUMN     "producao" TEXT;

-- AlterTable: movimentacoes_producao (nullable -> popular -> NOT NULL)
ALTER TABLE "movimentacoes_producao" ADD COLUMN "producao" TEXT;
UPDATE "movimentacoes_producao" SET "producao" = '1';
ALTER TABLE "movimentacoes_producao" ALTER COLUMN "producao" SET NOT NULL;

-- CreateIndex
CREATE INDEX "estoque_producao_producao_idx" ON "estoque_producao"("producao");

-- CreateIndex
CREATE UNIQUE INDEX "estoque_producao_materialId_producao_key" ON "estoque_producao"("materialId", "producao");

-- CreateIndex
CREATE INDEX "movimentacoes_producao_producao_idx" ON "movimentacoes_producao"("producao");