-- CreateEnum
CREATE TYPE "Role" AS ENUM ('ADMIN', 'GERENTE', 'COMPRADOR', 'ESTOQUISTA', 'VISUALIZADOR');

-- CreateEnum
CREATE TYPE "StatusEstoque" AS ENUM ('OK', 'LIMITE', 'CRITICO', 'INATIVO');

-- CreateEnum
CREATE TYPE "StatusOrcamento" AS ENUM ('ABERTO', 'CONVERTIDO', 'CANCELADO');

-- CreateEnum
CREATE TYPE "StatusOrdemCompra" AS ENUM ('EM_ANDAMENTO', 'FINALIZADO', 'CANCELADO');

-- CreateEnum
CREATE TYPE "TipoMovimentacao" AS ENUM ('ENTRADA', 'SAIDA');

-- CreateTable
CREATE TABLE "usuarios" (
    "id" SERIAL NOT NULL,
    "nome" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "senha" TEXT NOT NULL,
    "role" "Role" NOT NULL DEFAULT 'VISUALIZADOR',
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "usuarios_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "materiais" (
    "id" SERIAL NOT NULL,
    "nome" TEXT NOT NULL,
    "unidade" TEXT,
    "categoria" TEXT,
    "medida" TEXT,
    "espessura" TEXT,
    "valor" DECIMAL(10,2),
    "valorMetroQuadrado" DECIMAL(10,2),
    "quantidade" DECIMAL(10,3) NOT NULL DEFAULT 0,
    "estoqueMinimo" DECIMAL(10,3) NOT NULL DEFAULT 0,
    "status" "StatusEstoque" NOT NULL DEFAULT 'OK',
    "estoqueConfirmado" BOOLEAN NOT NULL DEFAULT false,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "ultimoValorPago" DECIMAL(10,2),
    "ultimoValorPagoM2" DECIMAL(10,2),
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "materiais_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "historico_precos_material" (
    "id" SERIAL NOT NULL,
    "materialId" INTEGER NOT NULL,
    "ordemCompraId" INTEGER NOT NULL,
    "fornecedorId" INTEGER NOT NULL,
    "precoUnitario" DECIMAL(10,2) NOT NULL,
    "precoM2" DECIMAL(10,2),
    "quantidade" DECIMAL(10,3) NOT NULL,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "historico_precos_material_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "fornecedores" (
    "id" SERIAL NOT NULL,
    "nomeFantasia" TEXT NOT NULL,
    "tipoFornecedor" TEXT,
    "telefone" TEXT,
    "cnpj" TEXT,
    "razaoSocial" TEXT,
    "nomeVendedor" TEXT,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "fornecedores_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "fornecedor_materiais" (
    "id" SERIAL NOT NULL,
    "fornecedorId" INTEGER NOT NULL,
    "materialId" INTEGER NOT NULL,
    "preco" DECIMAL(10,2),
    "precoMetroQuadrado" DECIMAL(10,2),
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "fornecedor_materiais_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "orcamentos" (
    "id" SERIAL NOT NULL,
    "titulo" TEXT NOT NULL DEFAULT 'Orçamento',
    "status" "StatusOrcamento" NOT NULL DEFAULT 'ABERTO',
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "orcamentos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "orcamento_itens" (
    "id" SERIAL NOT NULL,
    "orcamentoId" INTEGER NOT NULL,
    "materialId" INTEGER NOT NULL,
    "fornecedorId" INTEGER,
    "quantidade" DECIMAL(10,3) NOT NULL DEFAULT 1,
    "precoUnitario" DECIMAL(10,2),
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "orcamento_itens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ordens_compra" (
    "id" SERIAL NOT NULL,
    "data" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fornecedorId" INTEGER NOT NULL,
    "requisitante" TEXT NOT NULL,
    "formaPagamento" TEXT,
    "prazoPagamento" TEXT,
    "observacoes" TEXT,
    "empresa" TEXT,
    "status" "StatusOrdemCompra" NOT NULL DEFAULT 'EM_ANDAMENTO',
    "usuarioId" INTEGER,
    "orcamentoId" INTEGER,
    "valorTotal" DECIMAL(10,2) NOT NULL DEFAULT 0,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ordens_compra_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ordem_compra_os" (
    "id" SERIAL NOT NULL,
    "ordemCompraId" INTEGER NOT NULL,
    "numeroOS" TEXT NOT NULL,

    CONSTRAINT "ordem_compra_os_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ordem_compra_itens" (
    "id" SERIAL NOT NULL,
    "ordemCompraId" INTEGER NOT NULL,
    "materialId" INTEGER NOT NULL,
    "numeroOS" TEXT NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL,
    "precoUnitario" DECIMAL(10,2) NOT NULL,
    "precoMetroQuadrado" DECIMAL(10,2),
    "usarM2" BOOLEAN NOT NULL DEFAULT false,
    "precoTotal" DECIMAL(10,2) NOT NULL,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ordem_compra_itens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "relacoes_os" (
    "id" SERIAL NOT NULL,
    "numeroOS" TEXT NOT NULL,
    "descricao" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "relacoes_os_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "movimentacoes_estoque" (
    "id" SERIAL NOT NULL,
    "materialId" INTEGER NOT NULL,
    "tipo" TEXT NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL,
    "numeroOS" TEXT NOT NULL,
    "relacaoOSId" INTEGER NOT NULL,
    "ordemCompraId" INTEGER,
    "precoUnitario" DECIMAL(10,2),
    "precoM2" DECIMAL(65,30),
    "observacao" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "movimentacoes_estoque_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "usuarios_username_key" ON "usuarios"("username");

-- CreateIndex
CREATE UNIQUE INDEX "materiais_nome_medida_espessura_key" ON "materiais"("nome", "medida", "espessura");

-- CreateIndex
CREATE UNIQUE INDEX "fornecedores_cnpj_key" ON "fornecedores"("cnpj");

-- CreateIndex
CREATE UNIQUE INDEX "fornecedor_materiais_fornecedorId_materialId_key" ON "fornecedor_materiais"("fornecedorId", "materialId");

-- CreateIndex
CREATE UNIQUE INDEX "relacoes_os_numeroOS_key" ON "relacoes_os"("numeroOS");

-- AddForeignKey
ALTER TABLE "historico_precos_material" ADD CONSTRAINT "historico_precos_material_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "historico_precos_material" ADD CONSTRAINT "historico_precos_material_ordemCompraId_fkey" FOREIGN KEY ("ordemCompraId") REFERENCES "ordens_compra"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "historico_precos_material" ADD CONSTRAINT "historico_precos_material_fornecedorId_fkey" FOREIGN KEY ("fornecedorId") REFERENCES "fornecedores"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "fornecedor_materiais" ADD CONSTRAINT "fornecedor_materiais_fornecedorId_fkey" FOREIGN KEY ("fornecedorId") REFERENCES "fornecedores"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "fornecedor_materiais" ADD CONSTRAINT "fornecedor_materiais_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamento_itens" ADD CONSTRAINT "orcamento_itens_orcamentoId_fkey" FOREIGN KEY ("orcamentoId") REFERENCES "orcamentos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamento_itens" ADD CONSTRAINT "orcamento_itens_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orcamento_itens" ADD CONSTRAINT "orcamento_itens_fornecedorId_fkey" FOREIGN KEY ("fornecedorId") REFERENCES "fornecedores"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ordens_compra" ADD CONSTRAINT "ordens_compra_fornecedorId_fkey" FOREIGN KEY ("fornecedorId") REFERENCES "fornecedores"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ordens_compra" ADD CONSTRAINT "ordens_compra_usuarioId_fkey" FOREIGN KEY ("usuarioId") REFERENCES "usuarios"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ordens_compra" ADD CONSTRAINT "ordens_compra_orcamentoId_fkey" FOREIGN KEY ("orcamentoId") REFERENCES "orcamentos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ordem_compra_os" ADD CONSTRAINT "ordem_compra_os_ordemCompraId_fkey" FOREIGN KEY ("ordemCompraId") REFERENCES "ordens_compra"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ordem_compra_itens" ADD CONSTRAINT "ordem_compra_itens_ordemCompraId_fkey" FOREIGN KEY ("ordemCompraId") REFERENCES "ordens_compra"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ordem_compra_itens" ADD CONSTRAINT "ordem_compra_itens_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_relacaoOSId_fkey" FOREIGN KEY ("relacaoOSId") REFERENCES "relacoes_os"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_ordemCompraId_fkey" FOREIGN KEY ("ordemCompraId") REFERENCES "ordens_compra"("id") ON DELETE SET NULL ON UPDATE CASCADE;
