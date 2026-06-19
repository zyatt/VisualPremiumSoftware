/*
  Warnings:

  - You are about to alter the column `ultimoValorPago` on the `estoque_especificos` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `ultimoValorPagoM2` on the `estoque_especificos` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `preco` on the `fornecedor_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoMetroQuadrado` on the `fornecedor_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `historico_precos_material` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoM2` on the `historico_precos_material` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `valor` on the `materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `valorMetroQuadrado` on the `materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `ultimoValorPago` on the `materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `ultimoValorPagoM2` on the `materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `qtdPadrao` on the `materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `movimentacoes_estoque` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoM2` on the `movimentacoes_estoque` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `orcamento_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoM2` on the `orcamento_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoMedio` on the `orcamento_venda_item_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoMedioM2` on the `orcamento_venda_item_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `orcamento_venda_item_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `ordem_compra_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoMetroQuadrado` on the `ordem_compra_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoTotal` on the `ordem_compra_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `valorTotal` on the `ordens_compra` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - A unique constraint covering the columns `[nome,identificador,medida,espessura]` on the table `materiais` will be added. If there are existing duplicate values, this will fail.

*/
-- DropIndex
DROP INDEX "materiais_nome_medida_espessura_key";

-- AlterTable
ALTER TABLE "estoque_especificos" ALTER COLUMN "ultimoValorPago" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "ultimoValorPagoM2" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "fornecedor_materiais" ALTER COLUMN "preco" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoMetroQuadrado" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "historico_precos_material" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "materiais" ALTER COLUMN "valor" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "valorMetroQuadrado" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "ultimoValorPago" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "ultimoValorPagoM2" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "qtdPadrao" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "movimentacoes_estoque" ADD COLUMN     "comprimentoUsado" DECIMAL(15,6),
ADD COLUMN     "larguraUsada" DECIMAL(15,6),
ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "orcamento_itens" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "orcamento_venda_item_materiais" ALTER COLUMN "precoMedio" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoMedioM2" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "orcamentos" ADD COLUMN     "fornecedoresOcultos" INTEGER[] DEFAULT ARRAY[]::INTEGER[];

-- AlterTable
ALTER TABLE "ordem_compra_itens" ADD COLUMN     "qtdUnidade" DECIMAL(15,6),
ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoMetroQuadrado" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoTotal" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "ordens_compra" ALTER COLUMN "valorTotal" SET DATA TYPE DECIMAL(15,6);

-- CreateTable
CREATE TABLE "markup_faixas" (
    "id" SERIAL NOT NULL,
    "ordem" INTEGER NOT NULL,
    "valorMin" DECIMAL(15,2) NOT NULL,
    "valorMax" DECIMAL(15,2),
    "percentual" DECIMAL(7,2) NOT NULL,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "markup_faixas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "configuracoes_sistema" (
    "chave" TEXT NOT NULL,
    "valor" TEXT NOT NULL,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "configuracoes_sistema_pkey" PRIMARY KEY ("chave")
);

-- CreateIndex
CREATE UNIQUE INDEX "materiais_nome_identificador_medida_espessura_key" ON "materiais"("nome", "identificador", "medida", "espessura");
