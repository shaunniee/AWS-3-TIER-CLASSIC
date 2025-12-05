#!/bin/bash
set -xe

dnf update -y

dnf install -y nodejs git

mkdir -p /opt/todo-app
cd /opt/todo-app

if [ ! -f package.json ]; then
  npm init -y
fi

npm install express pg

cat > /opt/todo-app/server.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: {
    rejectUnauthorized: false,
  },
});

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

app.post('/api/todos', async (req, res) => {
  try {
    const { title, description, due_at } = req.body;

    if (!title || title.trim() === '') {
      return res.status(400).json({ error: 'TITLE_REQUIRED' });
    }

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
EOF

chown -R ec2-user:ec2-user /opt/todo-app

cat > /etc/systemd/system/todo-app.service << 'EOF'
[Unit]
Description=Todo App API (Node + Postgres)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/todo-app
Environment="DB_HOST=todo-rds-postgres.c5isy6kyq7c8.eu-west-1.rds.amazonaws.com"
Environment="DB_PORT=5432"
Environment="DB_USER=todo_user"
Environment="DB_PASSWORD=CHANGE_ME_DB_PASSWORD"
Environment="DB_NAME=todo_db"
Environment="PORT=3000"
ExecStart=/usr/bin/node /opt/todo-app/server.js
Restart=on-failure
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable todo-app
systemctl start todo-app
