-- DropForeignKey
ALTER TABLE "mensagens_chat" DROP CONSTRAINT "mensagens_chat_destinatarioId_fkey";

-- DropForeignKey
ALTER TABLE "mensagens_chat" DROP CONSTRAINT "mensagens_chat_remetenteId_fkey";

-- AddForeignKey
ALTER TABLE "mensagens_chat" ADD CONSTRAINT "mensagens_chat_remetenteId_fkey" FOREIGN KEY ("remetenteId") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mensagens_chat" ADD CONSTRAINT "mensagens_chat_destinatarioId_fkey" FOREIGN KEY ("destinatarioId") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE CASCADE;
