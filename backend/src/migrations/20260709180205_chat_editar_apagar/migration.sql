-- AlterTable
ALTER TABLE "mensagens_chat" ADD COLUMN     "apagada" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "editadaEm" TIMESTAMP(3);
