-- AlterTable
ALTER TABLE "solicitacoes_producao" ADD COLUMN     "observacao" TEXT,
ALTER COLUMN "status" SET DEFAULT 'FINALIZADA';
