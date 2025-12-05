#!/bin/bash
set -xe

dnf update -y
dnf install -y nginx

# Simple static index + health + reverse proxy to internal app ALB
cat > /etc/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    access_log    /var/log/nginx/access.log;
    sendfile      on;
    keepalive_timeout  65;

    upstream todo_app {
        # Replace with your real internal app ALB DNS
        server internal-todo-alb-app-XXXXXXXX.eu-west-1.elb.amazonaws.com:80;
    }

    server {
        listen 80 default_server;
        server_name _;

        # Health check for web ALB
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }

        # Static placeholder root (later React build)
        root /usr/share/nginx/html;
        index index.html;

        # API → internal app ALB
        location /api/ {
            proxy_pass http://todo_app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

# Simple placeholder index
cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
  <head>
    <title>Todo App - Web Tier</title>
  </head>
  <body>
    <h1>Todo App Web Tier</h1>
    <p>This is the Phase 1 placeholder page served from Nginx on the web EC2 instances.</p>
    <p>API is available under <code>/api/todos</code>.</p>
  </body>
</html>
EOF

systemctl enable nginx
systemctl restart nginx
