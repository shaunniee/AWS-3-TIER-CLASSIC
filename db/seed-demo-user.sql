INSERT INTO users (id, email, name)
VALUES ('11111111-2222-3333-4444-555555555555',
        'demo.user@example.com',
        'Demo User')
ON CONFLICT (id) DO NOTHING;
