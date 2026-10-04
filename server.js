#!/usr/bin/env node

'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');

const HOST = '127.0.0.1';
const PORT = Number.parseInt(process.env.PORT || '4173', 10);
const projectRoot = __dirname;
const scriptPath = path.join(projectRoot, 'cleanup.sh');
const historyPath = path.join(projectRoot, 'cleanup-history.json');
const maxHistoryEntries = 100;

const phases = [
  { id: 'homebrew', name: 'Homebrew', description: 'Remove old Homebrew downloads and unused formula versions.', warning: false },
  { id: 'xcode-derived-data', name: 'Xcode DerivedData', description: 'Clear build products, indexes, and intermediate files.', warning: false },
  { id: 'xcode-derived-data-workaround', name: 'Xcode DerivedDataWorkaround', description: 'Clear the Xcode DerivedDataWorkaround folder.', warning: false },
  { id: 'xcode-archives', name: 'Xcode Archives', description: 'Remove locally stored Xcode app archives.', warning: false },
  { id: 'unavailable-simulators', name: 'Unavailable iOS simulators', description: 'Delete unavailable Simulator device records.', warning: false },
  { id: 'core-simulator-caches', name: 'CoreSimulator caches', description: 'Remove CoreSimulator cache data.', warning: false },
  { id: 'cocoapods-cache', name: 'CocoaPods cache', description: 'Remove downloaded CocoaPods artifacts.', warning: false },
  { id: 'npm-cache', name: 'npm cache', description: 'Remove npm’s local package cache.', warning: false },
  { id: 'yarn-cache', name: 'Yarn cache', description: 'Remove Yarn’s local cache.', warning: false },
  { id: 'macos-app-caches', name: 'macOS application caches', description: 'Remove cache files for all macOS applications.', warning: true },
  { id: 'spotlight', name: 'Spotlight index', description: 'Reset and rebuild Spotlight’s disk index. Requires administrator authentication.', warning: true },
  { id: 'gradle-caches', name: 'Gradle caches', description: 'Remove Gradle’s downloaded and generated cache data.', warning: false },
  { id: 'gradle-daemon', name: 'Gradle daemon data', description: 'Remove Gradle daemon state.', warning: false },
  { id: 'android-studio', name: 'Old Android Studio folders', description: 'Keep the newest Android Studio support folder and remove older ones.', warning: false },
];

const phaseIds = new Set(phases.map(({ id }) => id));
let activeJob = null;

function getHistory() {
  try {
    const rawHistory = fs.readFileSync(historyPath, 'utf8');
    const history = JSON.parse(rawHistory);
    return Array.isArray(history) ? history : [];
  } catch (error) {
    return error.code === 'ENOENT' ? [] : [];
  }
}

function addHistoryEntry(entry) {
  const history = getHistory();
  history.unshift(entry);
  fs.writeFileSync(historyPath, `${JSON.stringify(history.slice(0, maxHistoryEntries), null, 2)}\n`);
}

function sendJson(response, status, payload) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  response.end(JSON.stringify(payload));
}

function sendFile(response, filePath, contentType) {
  fs.readFile(filePath, (error, content) => {
    if (error) {
      sendJson(response, 500, { error: 'Unable to load the interface.' });
      return;
    }

    response.writeHead(200, {
      'Content-Type': contentType,
      'Cache-Control': 'no-store',
    });
    response.end(content);
  });
}

function finishPhase(response, result) {
  const entry = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    startedAt: result.startedAt,
    finishedAt: new Date().toISOString(),
    phase: result.phase,
    dryRun: result.dryRun,
    success: result.success,
    exitCode: result.exitCode ?? null,
    signal: result.signal ?? null,
    output: result.output.trim() || 'No output was produced.',
  };

  addHistoryEntry(entry);
  sendJson(response, result.success ? 200 : 500, entry);
}

function runPhase(phase, dryRun, response) {
  const args = [scriptPath, `--phase=${phase}`];
  if (dryRun) args.push('--dry-run');

  const childProcess = spawn('/bin/bash', args, {
    cwd: projectRoot,
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  activeJob = { process: childProcess, phase };
  const startedAt = new Date().toISOString();
  let output = '';

  const appendOutput = (chunk) => {
    output += chunk.toString();
  };

  childProcess.stdout.on('data', appendOutput);
  childProcess.stderr.on('data', appendOutput);

  childProcess.on('error', (error) => {
    activeJob = null;
    finishPhase(response, {
      startedAt,
      phase,
      dryRun,
      success: false,
      output: `${output}\nUnable to start cleanup: ${error.message}`,
    });
  });

  childProcess.on('close', (code, signal) => {
    activeJob = null;
    finishPhase(response, {
      startedAt,
      phase,
      dryRun,
      success: code === 0,
      exitCode: code,
      signal,
      output,
    });
  });
}

const server = http.createServer((request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || HOST}`);

  if (request.method === 'GET' && url.pathname === '/') {
    sendFile(response, path.join(projectRoot, 'index.html'), 'text/html; charset=utf-8');
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/phases') {
    sendJson(response, 200, { phases, activePhase: activeJob?.phase ?? null });
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/history') {
    sendJson(response, 200, { history: getHistory() });
    return;
  }

  if (request.method === 'POST' && url.pathname === '/api/run') {
    let body = '';

    request.on('data', (chunk) => {
      body += chunk;
      if (body.length > 10_000) request.destroy();
    });

    request.on('end', () => {
      let payload;
      try {
        payload = JSON.parse(body);
      } catch {
        sendJson(response, 400, { error: 'Request body must be valid JSON.' });
        return;
      }

      if (!phaseIds.has(payload.phase)) {
        sendJson(response, 400, { error: 'Unknown cleanup phase.' });
        return;
      }

      if (activeJob) {
        sendJson(response, 409, { error: `A cleanup phase is already running: ${activeJob.phase}.` });
        return;
      }

      runPhase(payload.phase, payload.dryRun !== false, response);
    });
    return;
  }

  sendJson(response, 404, { error: 'Not found.' });
});

server.listen(PORT, HOST, () => {
  console.log(`Dev Decrufter for Mac is running at http://${HOST}:${PORT}`);
  console.log('Press Ctrl+C to stop the server.');
});
