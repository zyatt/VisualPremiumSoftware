-- AlterTable
ALTER TABLE "manutencoes_veiculo" ADD COLUMN     "finalizada" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "finalizadaEm" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "mensagens_chat" ADD COLUMN     "respondendoAId" INTEGER;

-- AddForeignKey
ALTER TABLE "mensagens_chat" ADD CONSTRAINT "mensagens_chat_respondendoAId_fkey" FOREIGN KEY ("respondendoAId") REFERENCES "mensagens_chat"("id") ON DELETE SET NULL ON UPDATE CASCADE;
