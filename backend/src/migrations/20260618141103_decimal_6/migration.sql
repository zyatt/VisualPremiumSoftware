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
  - You are about to alter the column `comprimentoUsado` on the `movimentacoes_estoque` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `larguraUsada` on the `movimentacoes_estoque` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `orcamento_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoM2` on the `orcamento_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoMedio` on the `orcamento_venda_item_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoMedioM2` on the `orcamento_venda_item_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `orcamento_venda_item_materiais` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoUnitario` on the `ordem_compra_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoMetroQuadrado` on the `ordem_compra_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `precoTotal` on the `ordem_compra_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `qtdUnidade` on the `ordem_compra_itens` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.
  - You are about to alter the column `valorTotal` on the `ordens_compra` table. The data in that column could be lost. The data in that column will be cast from `Decimal(15,5)` to `Decimal(15,6)`.

*/
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
ALTER TABLE "movimentacoes_estoque" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "comprimentoUsado" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "larguraUsada" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "orcamento_itens" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "orcamento_venda_item_materiais" ALTER COLUMN "precoMedio" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoMedioM2" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "ordem_compra_itens" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoMetroQuadrado" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "precoTotal" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "qtdUnidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "ordens_compra" ALTER COLUMN "valorTotal" SET DATA TYPE DECIMAL(15,6);
