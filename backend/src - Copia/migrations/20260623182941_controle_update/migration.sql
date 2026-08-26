-- AlterTable
ALTER TABLE "movimentacoes_estoque" ADD COLUMN     "materialOrigemId" INTEGER;

-- CreateIndex
CREATE INDEX "movimentacoes_estoque_materialOrigemId_idx" ON "movimentacoes_estoque"("materialOrigemId");

-- AddForeignKey
ALTER TABLE "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_materialOrigemId_fkey" FOREIGN KEY ("materialOrigemId") REFERENCES "materiais"("id") ON DELETE SET NULL ON UPDATE CASCADE;
