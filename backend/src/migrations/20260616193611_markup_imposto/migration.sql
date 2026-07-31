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
