/*
  Warnings:

  - A unique constraint covering the columns `[nome,identificador,medida,espessura]` on the table `materiais` will be added. If there are existing duplicate values, this will fail.

*/
-- DropIndex
DROP INDEX "materiais_nome_medida_espessura_key";

-- CreateIndex
CREATE UNIQUE INDEX "materiais_nome_identificador_medida_espessura_key" ON "materiais"("nome", "identificador", "medida", "espessura");
