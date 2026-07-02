module.exports = {
  apps: [
    {
      name: 'mathmate-api',
      script: './proxy_server.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'production',
        PORT: 3001,
      },
      env_file: '.env',
      error_file: '/var/log/mathmate/pm2-error.log',
      out_file: '/var/log/mathmate/pm2-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      max_memory_restart: '500M',
      node_args: '--max-old-space-size=512',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
    },
  ],
};
