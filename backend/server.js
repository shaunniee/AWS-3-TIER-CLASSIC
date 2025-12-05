const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

// Postgres connection pool using env vars
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: {
    // RDS enforces SSL by default; for dev we skip CA verification.
    rejectUnauthorized: false,
  },
});

// Health check used by app ALB
app.get('/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT 1 AS ok');
    return res.status(200).json({
      status: 'ok',
      db: result.rows[0].ok,
    });
  } catch (err) {
    console.error('Health check failed:', err);
    return res.status(500).json({
      status: 'error',
      error: 'DB_CHECK_FAILED',
    });
  }
});

// List latest todos
app.get('/api/todos', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, user_id, title, description, is_done, created_at, due_at
       FROM todos
       ORDER BY created_at DESC
       LIMIT 50;`
    );
    return res.status(200).json(result.rows);
  } catch (err) {
    console.error('Error fetching todos:', err);
    return res.status(500).json({ error: 'FAILED_TO_FETCH_TODOS' });
  }
});

// Create a new todo
app.post('/api/todos', async (req, res) => {
  try {
    const { title, description, due_at } = req.body;

    if (!title || title.trim() === '') {
      return res.status(400).json({ error: 'TITLE_REQUIRED' });
    }

    // Phase 1: fixed demo user; Phase 2 will map from Cognito
    const userId = '11111111-2222-3333-4444-555555555555';

    const result = await pool.query(
      `INSERT INTO todos (user_id, title, description, due_at)
       VALUES ($1, $2, $3, $4)
       RETURNING id, user_id, title, description, is_done, created_at, due_at;`,
      [userId, title, description || null, due_at || null]
    );

    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error creating todo:', err);
    return res.status(500).json({ error: 'FAILED_TO_CREATE_TODO' });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Todo API listening on port ${port}`);
});
