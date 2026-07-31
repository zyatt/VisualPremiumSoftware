-- CreateTable
CREATE TABLE "audit_log_materiais" (
    "id" SERIAL NOT NULL,
    "materialId" INTEGER NOT NULL,
    "acao" TEXT NOT NULL,
    "campo" TEXT,
    "valorAntes" TEXT,
    "valorDepois" TEXT,
    "usuarioId" INTEGER,
    "usuarioNome" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_log_materiais_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "audit_log_materiais_materialId_idx" ON "audit_log_materiais"("materialId");

-- CreateIndex
CREATE INDEX "audit_log_materiais_criadoEm_idx" ON "audit_log_materiais"("criadoEm");

-- AddForeignKey
ALTER TABLE "audit_log_materiais" ADD CONSTRAINT "audit_log_materiais_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE CASCADE ON UPDATE CASCADE;
