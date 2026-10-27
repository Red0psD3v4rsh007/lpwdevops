const express = require('express');
const fs = require('fs');
const client = require('prom-client');

const app = express();
const port = 4000;
const logFile = '/logs/app.log';

fs.mkdirSync('/logs', { recursive: true });
client.collectDefaultMetrics();

const httpRequests = new client.Counter({
  name: 'app_http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status']
});

const httpDuration = new client.Histogram({
  name: 'app_http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5]
});

function writeLog(level, message, extra = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'observability-demo',
    message,
    ...extra
  };
  fs.appendFileSync(logFile, JSON.stringify(entry) + '\n');
  console.log(JSON.stringify(entry));
}

app.use((req, res, next) => {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    const route = req.route?.path || req.path;
    httpRequests.inc({ method: req.method, route, status: String(res.statusCode) });
    httpDuration.observe({ method: req.method, route, status: String(res.statusCode) }, seconds);
    writeLog(res.statusCode >= 500 ? 'ERROR' : 'INFO', 'request_completed', {
      method: req.method, route, status: res.statusCode, duration_ms: Math.round(seconds * 1000)
    });
  });
  next();
});

app.get('/', (req, res) => res.json({ message: 'Observability lab application is running' }));
app.get('/health', (req, res) => res.json({ status: 'UP' }));

app.get('/work', async (req, res) => {
  const delay = Math.floor(Math.random() * 900) + 100;
  await new Promise(resolve => setTimeout(resolve, delay));
  res.json({ status: 'completed', delay_ms: delay });
});

app.get('/error', (req, res) => {
  writeLog('ERROR', 'controlled_test_error', { errorCode: 'LAB-500' });
  res.status(500).json({ error: 'Controlled lab error' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.listen(port, () => writeLog('INFO', 'server_started', { port }));
