import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { addonsHomeFor, installAddons, linkAddons, removeOwnedLinks } from '../src/install.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const sourceAddon = path.resolve(here, '../../addon/KilnForever');

function temp() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-install-'));
  return {
    root,
    dataDir: path.join(root, 'data'),
    gameAddons: path.join(root, 'game', '_forever_', 'Interface', 'AddOns'),
    outside: path.join(root, 'outside'),
  };
}

function linkNames(gameAddons) {
  return fs.readdirSync(gameAddons).filter((n) => fs.lstatSync(path.join(gameAddons, n)).isSymbolicLink()).sort();
}

test('install writes the addon and slots under the data dir and links them into the game', () => {
  const t = temp();
  try {
    const result = installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 2 });
    const home = addonsHomeFor(t.dataDir);
    assert.equal(result.addonsHome, home);
    assert.ok(fs.existsSync(path.join(home, 'KilnForever', 'KilnForever.toc')));
    assert.ok(fs.existsSync(path.join(home, 'KilnForever', 'Signals', '03999.wav')));
    for (const name of ['tests', 'tools', 'types']) {
      assert.equal(fs.existsSync(path.join(home, 'KilnForever', name)), false, `${name} must not reach the game`);
    }
    assert.deepEqual(linkNames(t.gameAddons), ['KilnForever', 'KilnForever_S001', 'KilnForever_S002']);
    for (const name of linkNames(t.gameAddons)) {
      const target = fs.readlinkSync(path.join(t.gameAddons, name));
      assert.equal(path.resolve(path.dirname(path.join(t.gameAddons, name)), target), path.join(home, name));
    }
    assert.equal(fs.lstatSync(path.join(t.gameAddons, 'KilnForever')).isSymbolicLink(), true);
  } finally {
    fs.rmSync(t.root, { recursive: true, force: true });
  }
});

test('re-install drops files the new build no longer has and keeps the signals', () => {
  const t = temp();
  try {
    installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 1 });
    const addon = path.join(addonsHomeFor(t.dataDir), 'KilnForever');
    fs.mkdirSync(path.join(addon, 'Media'));
    fs.writeFileSync(path.join(addon, 'Media', 'old.tga'), '');
    installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 1 });
    assert.equal(fs.existsSync(path.join(addon, 'Media')), false);
    assert.ok(fs.existsSync(path.join(addon, 'Signals', '03999.wav')));
  } finally {
    fs.rmSync(t.root, { recursive: true, force: true });
  }
});

test('a real folder at a name we use blocks the install', () => {
  const t = temp();
  try {
    const home = addonsHomeFor(t.dataDir);
    fs.mkdirSync(home, { recursive: true });
    fs.mkdirSync(t.gameAddons, { recursive: true });
    fs.mkdirSync(path.join(t.gameAddons, 'KilnForever'));
    fs.writeFileSync(path.join(t.gameAddons, 'KilnForever', 'someone-else.txt'), 'keep me');
    assert.throws(
      () => installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 1 }),
      /already exists and is not a link created by Kiln Forever/,
    );
    assert.equal(fs.readFileSync(path.join(t.gameAddons, 'KilnForever', 'someone-else.txt'), 'utf8'), 'keep me');
  } finally {
    fs.rmSync(t.root, { recursive: true, force: true });
  }
});

test('a link to somewhere else blocks the install', () => {
  const t = temp();
  try {
    fs.mkdirSync(t.outside, { recursive: true });
    fs.mkdirSync(t.gameAddons, { recursive: true });
    fs.symlinkSync(t.outside, path.join(t.gameAddons, 'KilnForever'), 'dir');
    assert.throws(
      () => installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 1 }),
      /is a link to .* not to/,
    );
    assert.equal(fs.realpathSync(path.join(t.gameAddons, 'KilnForever')), fs.realpathSync(t.outside));
  } finally {
    fs.rmSync(t.root, { recursive: true, force: true });
  }
});

test('re-install replaces our links and leaves other links alone', () => {
  const t = temp();
  try {
    const first = installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 2 });
    fs.mkdirSync(t.outside, { recursive: true });
    fs.symlinkSync(t.outside, path.join(t.gameAddons, 'KeepMe'), 'dir');
    fs.symlinkSync(path.join(first.addonsHome, 'KilnForever_S009'), path.join(t.gameAddons, 'KilnForever_S009'), 'dir');

    const second = installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 2 });
    assert.deepEqual(linkNames(t.gameAddons), ['KeepMe', 'KilnForever', 'KilnForever_S001', 'KilnForever_S002']);
    assert.equal(fs.realpathSync(path.join(t.gameAddons, 'KeepMe')), fs.realpathSync(t.outside), 'a foreign link is untouched');
    assert.equal(fs.existsSync(path.join(t.gameAddons, 'KilnForever_S009')), false, 'our stale link is gone');
    for (const name of ['KilnForever', 'KilnForever_S001', 'KilnForever_S002']) {
      assert.equal(fs.readlinkSync(path.join(t.gameAddons, name)), path.join(second.addonsHome, name));
    }
  } finally {
    fs.rmSync(t.root, { recursive: true, force: true });
  }
});

test('uninstall removes only the links that point into our addons home', () => {
  const t = temp();
  try {
    const { addonsHome } = installAddons({ sourceAddon, dataDir: t.dataDir, gameAddons: t.gameAddons, slots: 2 });
    fs.mkdirSync(t.outside, { recursive: true });
    fs.symlinkSync(t.outside, path.join(t.gameAddons, 'KeepMe'), 'dir');
    fs.mkdirSync(path.join(t.gameAddons, 'SomeoneElse'));

    const removed = removeOwnedLinks({ addonsHome, gameAddons: t.gameAddons });
    assert.deepEqual(removed.sort(), ['KilnForever', 'KilnForever_S001', 'KilnForever_S002']);
    assert.deepEqual(fs.readdirSync(t.gameAddons).sort(), ['KeepMe', 'SomeoneElse']);
    assert.equal(fs.lstatSync(path.join(t.gameAddons, 'KeepMe')).isSymbolicLink(), true);
  } finally {
    fs.rmSync(t.root, { recursive: true, force: true });
  }
});

test('linkAddons creates the game AddOns folder when it is missing', () => {
  const t = temp();
  try {
    fs.mkdirSync(path.join(addonsHomeFor(t.dataDir), 'KilnForever'), { recursive: true });
    const linked = linkAddons({ addonsHome: addonsHomeFor(t.dataDir), gameAddons: t.gameAddons });
    assert.deepEqual(linked, ['KilnForever']);
    assert.ok(fs.lstatSync(path.join(t.gameAddons, 'KilnForever')).isSymbolicLink());
  } finally {
    fs.rmSync(t.root, { recursive: true, force: true });
  }
});
