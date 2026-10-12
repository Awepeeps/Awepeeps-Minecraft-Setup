// Run inside the MCSManager web container:
//   docker exec -i mcsm-web node - <RemoteServiceConfig.json> <instance UUID>
// Opens a saved MCSManager instance through its own lifecycle API. Never prints
// config values: the referenced file contains the panel API key.
'use strict';
const fs = require('fs');

const pick = (...values) => values.find(v => typeof v === 'string' && v.length);
const validOverrideHost = host => typeof host === 'string' && host.length <= 253 &&
  host.split('.').every(label => label.length >= 1 && label.length <= 63 &&
    /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label));
const resolveConnection = (config, override) => {
  const savedHost = pick(config.ip, config.host, config.nodeIp, config.nodeIP, config.address);
  if (override !== undefined && !validOverrideHost(override)) return null;
  const host = override === undefined ? savedHost : override;
  const rawPort = config.port || config.nodePort;
  const port = typeof rawPort === 'number' ? rawPort :
    (typeof rawPort === 'string' && /^[0-9]{1,5}$/.test(rawPort) ? Number(rawPort) : NaN);
  const apiKey = pick(config.apiKey, config.key, config.token);
  if (!validOverrideHost(host) || !Number.isInteger(port) || port < 1 || port > 65535 || !apiKey) return null;
  return { host, port, apiKey };
};

function main() {
  const [configPath, instanceUuid] = process.argv.slice(2);
  if (!configPath || !instanceUuid) process.exit(2);
  let config;
  try { config = JSON.parse(fs.readFileSync(configPath, 'utf8')); }
  catch (_) { process.exit(2); }
  const connection = resolveConnection(config, process.env.MCSM_HOST_OVERRIDE);
  if (!connection) process.exit(2);
  const { host, port, apiKey } = connection;
  const timeoutMs = Number(process.env.MCSM_OPEN_TIMEOUT_MS || 15000);
  const uuid = require('crypto').randomUUID();
  const socket = require('/opt/mcsmanager/web/node_modules/socket.io-client').io(
    `http://${host}:${port}`, { transports: ['websocket'], timeout: timeoutMs,
      reconnection: false, auth: { token: apiKey } });
  let done = false;
  const finish = ok => { if (done) return; done = true; socket.close(); process.exit(ok ? 0 : 1); };
  const timer = setTimeout(() => finish(false), timeoutMs);
  socket.on('connect', () => socket.emit('auth', { uuid, data: apiKey }));
  socket.on('auth', packet => {
    if (!packet || packet.uuid !== uuid || packet.data !== true) return finish(false);
    socket.emit('instance/open', { uuid, data: { instanceUuids: [instanceUuid] } });
  });
  socket.on('instance/open', packet => {
    if (packet && packet.uuid === uuid && packet.status === 200) finish(true);
    else if (packet && packet.uuid === uuid) finish(false);
  });
  socket.on('connect_error', () => finish(false));
  process.on('exit', () => clearTimeout(timer));
}

module.exports = { validOverrideHost, resolveConnection };
if (require.main === module || process.argv[1] === '-') main();
