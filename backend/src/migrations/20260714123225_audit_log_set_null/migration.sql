-- DropForeignKey
ALTER TABLE "audit_log_materiais" DROP CONSTRAINT "audit_log_materiais_materialId_fkey";

-- AlterTable
ALTER TABLE "audit_log_materiais" ALTER COLUMN "materialId" DROP NOT NULL;

-- AddForeignKey
ALTER TABLE "audit_log_materiais" ADD CONSTRAINT "audit_log_materiais_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE SET NULL ON UPDATE CASCADE;
