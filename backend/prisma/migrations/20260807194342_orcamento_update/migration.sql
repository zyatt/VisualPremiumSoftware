-- AlterTable
ALTER TABLE "orcamentos" ADD COLUMN     "travaExpiraEm" TIMESTAMP(3),
ADD COLUMN     "travaUsuarioId" INTEGER;

-- AddForeignKey
ALTER TABLE "orcamentos" ADD CONSTRAINT "orcamentos_travaUsuarioId_fkey" FOREIGN KEY ("travaUsuarioId") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE CASCADE;
