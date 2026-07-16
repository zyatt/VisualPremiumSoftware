const router = require('express').Router();

const ctrl = require('../controllers/estoqueProducao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// Mesmos papéis usados em estoque.routes.js — ajuste se necessário.
const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS', 'ORCAMENTISTA', 'PRODUCAO'];
const ESCRITA = ['ADMIN', 'GERENTE', 'COMPRAS', 'PRODUCAO'];

// Transferência do estoque normal -> estoque de produção
// (chamada pela página de Controle de Estoque)
router.post('/transferir', authMiddleware, roleMiddleware(ESCRITA), ctrl.transferir);

// Estoque de produção (saldo atual)
router.get('/', authMiddleware, roleMiddleware(LEITURA), ctrl.listarEstoque);

// Baixa de material do estoque de produção para uma OS
router.post('/baixas', authMiddleware, roleMiddleware(ESCRITA), ctrl.darBaixa);

// Histórico (transferências recebidas + baixas por OS)
router.get('/historico', authMiddleware, roleMiddleware(LEITURA), ctrl.listarHistorico);

module.exports = router;