import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  StripCapture,
  cropImage,
  gamescopeScreenshotArgs,
  grimRegionArgs,
  grimToplevelArgs,
  magickCropArgs,
} from '../src/capture.js';

function ppm(width, height, value = 0) {
  const data = Buffer.alloc(width * height * 3, value);
  return Buffer.concat([Buffer.from(`P6\n${width} ${height}\n255\n`, 'ascii'), data]);
}

const PX = StripCapture.stripPixels(4);
const IMAGE = ppm(PX.width, PX.height);

function window(extra = {}) {
  return { found: true, visible: true, x: 100, y: 50, width: 1920, height: 1080, scale: 1, stableId: '0xabc', ...extra };
}

test('KILN_FOREVER_CAPTURE selects gamescope; an explicit backend wins', () => {
  const before = process.env.KILN_FOREVER_CAPTURE;
  try {
    process.env.KILN_FOREVER_CAPTURE = 'gamescope';
    assert.equal(new StripCapture({}).resolveBackend(), 'gamescope');
    assert.equal(new StripCapture({ backend: 'hyprland' }).resolveBackend(), 'hyprland');
  } finally {
    if (before === undefined) delete process.env.KILN_FOREVER_CAPTURE;
    else process.env.KILN_FOREVER_CAPTURE = before;
  }
});

test('capture command lines', () => {
  assert.deepEqual(grimToplevelArgs('0xabc'), ['-t', 'ppm', '-T', '0xabc', '-']);
  assert.deepEqual(grimRegionArgs(10, 20, 672, 192), ['-t', 'ppm', '-g', '10,20 672x192', '-']);
  assert.deepEqual(gamescopeScreenshotArgs('/run/user/1/shot.png'), ['screenshot', '/run/user/1/shot.png']);
  assert.deepEqual(magickCropArgs('/run/user/1/shot.png', 672, 192), ['/run/user/1/shot.png', '-crop', '672x192+0+0', '+repage', 'ppm:-']);
});

test('grim captures the toplevel when it supports -T', async () => {
  const calls = [];
  const exec = async (cmd, args) => {
    calls.push([cmd, args]);
    if (args[0] === '-h') return Buffer.from('  -t <type>  output type\n  -T <id>  capture a toplevel\n');
    return IMAGE;
  };
  const cap = new StripCapture({ backend: 'hyprland', exec, windowFn: async () => window() });
  const res = await cap.grab(42);
  assert.equal(res.status, 'ok');
  assert.deepEqual(calls.map((c) => c[1]), [['-h'], ['-t', 'ppm', '-T', '0xabc', '-']]);
});

test('grim falls back to the screen region when -T is missing', async () => {
  const calls = [];
  const exec = async (cmd, args) => {
    calls.push([cmd, args]);
    if (args[0] === '-h') return Buffer.from('usage: grim [options]\n  -t <type>  output type\n');
    return IMAGE;
  };
  const cap = new StripCapture({ backend: 'hyprland', exec, windowFn: async () => window({ scale: 2 }) });
  const res = await cap.grab(42);
  assert.equal(res.status, 'ok');
  assert.deepEqual(calls.map((c) => c[1]), [['-h'], ['-t', 'ppm', '-g', '100,50 336x96', '-']]);
});

test('a failed toplevel capture falls back to the region', async () => {
  const calls = [];
  const exec = async (cmd, args) => {
    calls.push([cmd, args]);
    if (args[0] === '-h') return Buffer.from('  -T <id>  capture a toplevel\n');
    if (args.includes('-T')) throw new Error('no such toplevel');
    return IMAGE;
  };
  const cap = new StripCapture({ backend: 'hyprland', exec, windowFn: async () => window() });
  const res = await cap.grab(42);
  assert.equal(res.status, 'ok');
  assert.match(cap.lastError, /toplevel capture failed/);
  assert.deepEqual(calls.at(-1)[1], ['-t', 'ppm', '-g', '100,50 672x192', '-']);
});

test('gamescope reads the session, screenshots, crops and cleans up', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-gamescope-'));
  const sessionFile = path.join(dir, 'session.json');
  fs.writeFileSync(sessionFile, JSON.stringify({ gamescope_socket: 'gamescope-0', display: 'wayland-9' }));
  const beforeRuntime = process.env.XDG_RUNTIME_DIR;
  process.env.XDG_RUNTIME_DIR = dir;
  const calls = [];
  try {
    const exec = async (cmd, args, opts = {}) => {
      calls.push({ cmd, args, opts });
      if (cmd === 'gamescopectl') fs.writeFileSync(args[1], 'png');
      return IMAGE;
    };
    const cap = new StripCapture({
      backend: 'gamescope',
      sessionFile,
      exec,
      has: (bin) => bin === 'magick',
    });
    const res = await cap.grab();
    assert.equal(res.status, 'ok');
    assert.equal(calls.length, 2);
    assert.equal(calls[0].cmd, 'gamescopectl');
    assert.equal(calls[0].args[0], 'screenshot');
    assert.equal(calls[0].opts.env.GAMESCOPE_WAYLAND_DISPLAY, 'gamescope-0');
    assert.equal(calls[1].cmd, 'magick');
    assert.deepEqual(calls[1].args, [calls[0].args[1], '-crop', '672x192+0+0', '+repage', 'ppm:-']);
    assert.equal(fs.existsSync(calls[0].args[1]), false, 'temporary screenshot removed');
  } finally {
    if (beforeRuntime === undefined) delete process.env.XDG_RUNTIME_DIR;
    else process.env.XDG_RUNTIME_DIR = beforeRuntime;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('gamescope falls back to convert when magick is missing', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-gamescope-'));
  const sessionFile = path.join(dir, 'session.json');
  fs.writeFileSync(sessionFile, JSON.stringify({ gamescope_socket: 'gamescope-0' }));
  const beforeRuntime = process.env.XDG_RUNTIME_DIR;
  process.env.XDG_RUNTIME_DIR = dir;
  const calls = [];
  try {
    const exec = async (cmd, args) => {
      calls.push({ cmd, args });
      if (cmd === 'gamescopectl') fs.writeFileSync(args[1], 'png');
      return IMAGE;
    };
    const cap = new StripCapture({
      backend: 'gamescope',
      sessionFile,
      exec,
      has: (bin) => bin === 'convert',
    });
    assert.equal((await cap.grab()).status, 'ok');
    assert.equal(calls[1].cmd, 'convert');
  } finally {
    if (beforeRuntime === undefined) delete process.env.XDG_RUNTIME_DIR;
    else process.env.XDG_RUNTIME_DIR = beforeRuntime;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('cropImage keeps the top-left corner and its rows', () => {
  const full = { width: 4, height: 3, data: Buffer.from([...Array(4 * 3 * 3).keys()]) };
  const small = cropImage(full, 2, 2);
  assert.equal(small.width, 2);
  assert.equal(small.height, 2);
  assert.deepEqual([...small.data], [0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 16, 17]);
});
