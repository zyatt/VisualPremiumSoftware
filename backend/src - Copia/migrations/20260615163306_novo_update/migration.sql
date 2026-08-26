-- CreateEnum
CREATE TYPE "StatusOrcamentoVenda" AS ENUM ('EM_ANDAMENTO', 'APROVADO', 'NAO_APROVADO');

-- AlterEnum
ALTER TYPE "Role" ADD VALUE 'ORCAMENTISTA';

-- CreateTable
CREATE TABLE "clientes" (
    "id" SERIAL NOT NULL,
    "nome" TEXT NOT NULL,
    "telefone" TEXT,
    "email" TEXT,
    "documento" TEXT,
    "observacao" TEXT,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "clientes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "produtos" (
    "id" SERIAL NOT NULL,
    "nome" TEXT NOT NULL,
    "descricao" TEXT,
    "categoria" TEXT,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "produtos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "produto_materiais" (
    "id" SERIAL NOT NULL,
    "produtoId" INTEGER NOT NULL,
    "materialId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,4) NOT NULL DEFAULT 1,
    "observacao" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "produto_materiais_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "orcamentos_venda" (
    "id" SERIAL NOT NULL,
    "numero" TEXT NOT NULL,
    "clienteId" INTEGER,
    "criadorId" INTEGER,
    "status" "StatusOrcamentoVenda" NOT NULL DEFAULT 'EM_ANDAMENTO',
    "observacao" TEXT,
    "valorTotal" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "margemLucro" DECIMAL(5,2),
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "orcamentos_venda_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "orcamento_venda_itens" (
    "id" SERIAL NOT NULL,
    "orcamentoVendaId" INTEGER NOT NULL,
    "produtoId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL DEFAULT 1,
    "observacao" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "orcamento_venda_itens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "orcamento_venda_item_materiais" (
    "id" SERIAL NOT NULL,
    "orcamentoVendaItemId" INTEGER NOT NULL,
    "materialId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,4) NOT NULL,
    "precoMedio" DECIMAL(15,5),
    "precoMedioM2" DECIMAL(15,5),
    "precoUnitario" DECIMAL(15,5),
    "usarM2" BOOLEAN NOT NULL DEFAULT false,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "orcamento_venda_item_materiais_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "produto_materiais_produtoId_materialId_key" ON "produto_materiais"("produtoId", "materialId");

-- CreateIndex
CREATE UNIQUE INDEX "orcamentos_venda_numero_key" ON "orcamentos_venda"("numero");

-- CreateIndex
CREATE UNIQUE INDEX "orcamento_venda_item_materiais_orcamentoVendaItemId_materia_key" ON "orcamento_venda_item_materiais"("orcamentoVendaItemId", "materialId");

-- AddForeignKey
ALTER TABLE "produto_materiais" ADD CONSTRAINT "produto_materiais_produtoId_fkey" FOREIGN KEY ("produtoId") REFERENCES "produtos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "produto_materiais" ADD CONSTRAINT "produto_materiais_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamentos_venda" ADD CONSTRAINT "orcamentos_venda_clienteId_fkey" FOREIGN KEY ("clienteId") REFERENCES "clientes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamentos_venda" ADD CONSTRAINT "orcamentos_venda_criadorId_fkey" FOREIGN KEY ("criadorId") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamento_venda_itens" ADD CONSTRAINT "orcamento_venda_itens_orcamentoVendaId_fkey" FOREIGN KEY ("orcamentoVendaId") REFERENCES "orcamentos_venda"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamento_venda_itens" ADD CONSTRAINT "orcamento_venda_itens_produtoId_fkey" FOREIGN KEY ("produtoId") REFERENCES "produtos"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamento_venda_item_materiais" ADD CONSTRAINT "orcamento_venda_item_materiais_orcamentoVendaItemId_fkey" FOREIGN KEY ("orcamentoVendaItemId") REFERENCES "orcamento_venda_itens"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamento_venda_item_materiais" ADD CONSTRAINT "orcamento_venda_item_materiais_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
