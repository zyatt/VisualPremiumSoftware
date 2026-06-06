/*
  Warnings:

  - The `comprimento` column on the `materiais` table would be dropped and recreated. This will lead to data loss if there is data in the column.
  - The `largura` column on the `materiais` table would be dropped and recreated. This will lead to data loss if there is data in the column.

*/
-- AlterTable
ALTER TABLE "materiais" DROP COLUMN "comprimento",
ADD COLUMN     "comprimento" DECIMAL(10,4),
DROP COLUMN "largura",
ADD COLUMN     "largura" DECIMAL(10,4);
