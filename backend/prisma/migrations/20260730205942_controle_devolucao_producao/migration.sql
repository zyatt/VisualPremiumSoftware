-- AlterTable
ALTER TABLE "estoque_producao" ADD COLUMN     "quantidadePendente" DECIMAL(10,3) NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "entradas_pendentes" (
    "id" SERIAL NOT NULL,
    "tipo" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDENTE',
    "materialId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL,
    "producao" TEXT NOT NULL,
    "numeroOS" TEXT,
    "relacaoOSId" INTEGER,
    "larguraUsada" DECIMAL(15,6),
    "comprimentoUsado" DECIMAL(15,6),
    "precoM2Final" DECIMAL(15,6),
    "precoUnitarioFinal" DECIMAL(15,6),
    "observacao" TEXT,
    "usuarioNome" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvidoEm" TIMESTAMP(3),

    CONSTRAINT "entradas_pendentes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "entradas_pendentes_status_idx" ON "entradas_pendentes"("status");

-- CreateIndex
CREATE INDEX "entradas_pendentes_tipo_idx" ON "entradas_pendentes"("tipo");

-- CreateIndex
CREATE INDEX "entradas_pendentes_materialId_idx" ON "entradas_pendentes"("materialId");

-- AddForeignKey
ALTER TABLE "entradas_pendentes" ADD CONSTRAINT "entradas_pendentes_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE CASCADE ON UPDATE CASCADE;
