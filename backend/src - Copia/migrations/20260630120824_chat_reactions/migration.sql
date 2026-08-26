-- AlterTable
ALTER TABLE "mensagens_chat" ADD COLUMN     "reacoes" JSONB NOT NULL DEFAULT '{}';
