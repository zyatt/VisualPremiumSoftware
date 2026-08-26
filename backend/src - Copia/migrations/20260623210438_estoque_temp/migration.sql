-- CreateTable
CREATE TABLE "estoque_temporario" (
    "id" SERIAL NOT NULL,
    "nome" TEXT NOT NULL,
    "unidade" TEXT NOT NULL DEFAULT 'UNIDADE',
    "observacao" TEXT,
    "criadoPorId" INTEGER,
    "criadoPorNome" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiraEm" TIMESTAMP(3) NOT NULL,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "estoque_temporario_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "estoque_temporario" ADD CONSTRAINT "estoque_temporario_criadoPorId_fkey" FOREIGN KEY ("criadoPorId") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE CASCADE;
