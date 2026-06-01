const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
require('dotenv').config();

const app = express();

app.use(helmet());
app.use(cors({ origin: '*' }));
app.use(express.json());
app.use(morgan('dev'));

app.use('/auth', require('./routes/usuario.routes'));
app.use('/api/usuarios',        require('./routes/usuario.routes'));
app.use('/api/materiais',       require('./routes/material.routes'));
app.use('/api/fornecedores',    require('./routes/fornecedor.routes'));
app.use('/api/orcamentos',      require('./routes/orcamento.routes'));
app.use('/api/ordens-compra',   require('./routes/ordemCompra.routes'));
app.use('/api/estoque',         require('./routes/estoque.routes'));
app.use('/api/historico',       require('./routes/historico.routes'));
app.use('/api/relatorios-os',   require('./routes/relatorioOS.routes'));
app.use('/api/producao',        require('./routes/producao.routes'));

app.get('/health', (req, res) => res.json({ status: 'ok', timestamp: new Date() }));

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(err.status || 500).json({
    error: err.message || 'Erro interno do servidor',
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Visual Premium API rodando na porta ${PORT}`);
});

module.exports = app;