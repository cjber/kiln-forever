// Installation layout.
//
// The source addon, its live-update slots and the signal bells live under
// <data>/kiln-forever/addons. The game's Interface/AddOns folder only gets symlinks
// to those folders: addon managers skip symlinked folders, so the slots stay out of
// their lists and fingerprints. A real folder at one of those names is never
// overwritten; that's someone else's addon.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { ADDON, CTL_LONG, SlotBank } from './slots.js';

export const ADDONS_HOME_NAME = 'addons';
export const FOREVER_CORE = 'ForeverCore';

const FOREVER_CORE_RELEASE = 'https://api.github.com/repos/cjber/forever-core/releases/latest';

export function addonsHomeFor(dataDir) {
  return path.join(dataDir, ADDONS_HOME_NAME);
}

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name);
    const d = path.join(dst, e.name);
    if (e.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}

// Source folders that are for development only: specs, the vendoring tools and LuaLS types.
export const DEV_SKIP = new Set(['tests', 'tools', 'types']);

// Replace the addon code, leaving the generated Signals folder alone and the development folders out of the game.
// Everything else under the installed folder is ours, so it is cleared first: a file the new build dropped must not
// stay behind and load.
export function syncAddon(sourceAddon, addonsHome) {
  const dst = path.join(addonsHome, ADDON);
  fs.mkdirSync(dst, { recursive: true });
  for (const name of fs.readdirSync(dst)) {
    if (name !== 'Signals') fs.rmSync(path.join(dst, name), { recursive: true, force: true });
  }
  for (const e of fs.readdirSync(sourceAddon, { withFileTypes: true })) {
    if (e.name === 'Signals' || DEV_SKIP.has(e.name)) continue;
    const d = path.join(dst, e.name);
    const s = path.join(sourceAddon, e.name);
    if (e.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
  return dst;
}

function lstatOrNull(file) {
  try {
    return fs.lstatSync(file);
  } catch {
    return null;
  }
}

function isInside(child, parent) {
  const rel = path.relative(path.resolve(parent), path.resolve(child));
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
}

function linkTarget(file) {
  return path.resolve(path.dirname(file), fs.readlinkSync(file));
}

export function installedNames(addonsHome) {
  let entries;
  try {
    entries = fs.readdirSync(addonsHome, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((e) => e.isDirectory() && (e.name === ADDON || /^KilnForever_S\d+$/.test(e.name)))
    .map((e) => e.name)
    .sort();
}

// Point every installed folder into the game's AddOns. An existing symlink is only
// replaced when it already points into our addons home; a real folder or a link to
// somewhere else stops the install. Stale links of ours (for slots we no longer
// install) are removed.
export function linkAddons({ addonsHome, gameAddons }) {
  fs.mkdirSync(gameAddons, { recursive: true });
  const names = installedNames(addonsHome);
  const wanted = new Set(names);
  // Check every name before changing anything, so a conflict leaves the game untouched.
  for (const name of names) {
    const src = path.join(addonsHome, name);
    const dst = path.join(gameAddons, name);
    const existing = lstatOrNull(dst);
    if (!existing) continue;
    if (!existing.isSymbolicLink()) {
      throw new Error(`${dst} already exists and is not a link created by Kiln Forever. Move or remove it, then run install again.`);
    }
    const target = linkTarget(dst);
    if (!isInside(target, addonsHome)) {
      throw new Error(`${dst} is a link to ${target}, not to ${src}. Remove it or point it at ${src}, then run install again.`);
    }
  }
  const linked = [];
  for (const name of names) {
    const src = path.join(addonsHome, name);
    const dst = path.join(gameAddons, name);
    const existing = lstatOrNull(dst);
    if (existing) {
      if (linkTarget(dst) === src) {
        linked.push(name);
        continue;
      }
      fs.rmSync(dst, { force: true });
    }
    fs.symlinkSync(src, dst, 'dir');
    linked.push(name);
  }
  for (const name of fs.readdirSync(gameAddons)) {
    if (wanted.has(name) || name === FOREVER_CORE) continue;
    const dst = path.join(gameAddons, name);
    const st = lstatOrNull(dst);
    if (st?.isSymbolicLink() && isInside(linkTarget(dst), addonsHome)) fs.rmSync(dst, { force: true });
  }
  return linked;
}

// Remove only the links that point into our addons home.
export function removeOwnedLinks({ addonsHome, gameAddons }) {
  let entries;
  try {
    entries = fs.readdirSync(gameAddons);
  } catch {
    return [];
  }
  const removed = [];
  for (const name of entries) {
    const dst = path.join(gameAddons, name);
    const st = lstatOrNull(dst);
    if (!st?.isSymbolicLink()) continue;
    if (!isInside(linkTarget(dst), addonsHome)) continue;
    fs.rmSync(dst, { force: true });
    removed.push(name);
  }
  return removed;
}

// Unzip one archive with the system tool. Node has no unzip of its own, and the bridge keeps no npm dependencies.
function unzipArchive(archive, destination) {
  return new Promise((resolve, reject) => {
    execFile('unzip', ['-q', '-o', archive, '-d', destination], (error, _stdout, stderr) => {
      if (!error) return resolve();
      if (error.code === 'ENOENT') {
        reject(new Error('installing Forever Core needs the `unzip` command: install it (for example `sudo pacman -S unzip`), then run install again.'));
        return;
      }
      reject(new Error(`couldn't unzip Forever Core: ${(stderr || error.message).trim()}`));
    });
  });
}

// The latest Forever Core release, unzipped into the addons home as <addonsHome>/ForeverCore.
async function downloadForeverCore({ addonsHome, fetch, unzip = unzipArchive }) {
  let response;
  try {
    response = await fetch(FOREVER_CORE_RELEASE, { headers: { accept: 'application/vnd.github+json' } });
  } catch (error) {
    throw new Error(`couldn't reach GitHub for Forever Core: ${error.message}. Check your connection, then run install again.`);
  }
  if (!response.ok) {
    throw new Error(`couldn't read Forever Core's latest release: GitHub answered ${response.status}. Try again, or install Forever Core from CurseForge.`);
  }
  const release = await response.json();
  const asset = (release.assets || []).find((entry) => typeof entry.name === 'string' && entry.name.startsWith('ForeverCore-') && entry.name.endsWith('.zip'));
  if (!asset) {
    throw new Error("Forever Core's latest release has no ForeverCore-....zip download. Install Forever Core from CurseForge, then run install again.");
  }
  let archive;
  try {
    archive = await fetch(asset.browser_download_url);
  } catch (error) {
    throw new Error(`couldn't download Forever Core: ${error.message}. Check your connection, then run install again.`);
  }
  if (!archive.ok) {
    throw new Error(`couldn't download Forever Core: GitHub answered ${archive.status}. Try again, or install Forever Core from CurseForge.`);
  }
  fs.mkdirSync(addonsHome, { recursive: true });
  // A fresh copy each time, so files a newer release dropped do not linger beside it.
  fs.rmSync(path.join(addonsHome, FOREVER_CORE), { recursive: true, force: true });
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-forever-core-'));
  try {
    const zip = path.join(scratch, asset.name);
    fs.writeFileSync(zip, Buffer.from(await archive.arrayBuffer()));
    await unzip(zip, addonsHome);
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
  if (!fs.existsSync(path.join(addonsHome, FOREVER_CORE, 'ForeverCore.toc'))) {
    throw new Error(`Forever Core's download did not contain ${FOREVER_CORE}/ForeverCore.toc. Install Forever Core from CurseForge, then run install again.`);
  }
}

// Put Forever Core beside Kiln's own addon. A real folder from CurseForge at the game's ForeverCore path, or a symlink
// pointing anywhere but our addons home, is the player's own and is left alone. Otherwise the latest release is
// downloaded, unzipped into the addons home and linked into the game like Kiln's own folder; running install again
// refreshes that copy. `fetch` and `unzip` are injectable so tests never touch the network or the system tool.
export async function ensureForeverCore({ addonsHome, gameAddons, fetch = globalThis.fetch, unzip = unzipArchive }) {
  fs.mkdirSync(gameAddons, { recursive: true });
  const target = path.join(gameAddons, FOREVER_CORE);
  const st = lstatOrNull(target);
  const ours = st?.isSymbolicLink() && isInside(linkTarget(target), addonsHome);
  if (st && !ours) {
    return { status: 'kept', path: target };
  }
  await downloadForeverCore({ addonsHome, fetch, unzip });
  if (!ours) fs.symlinkSync(path.join(addonsHome, FOREVER_CORE), target, 'dir');
  return { status: ours ? 'updated' : 'installed', path: target };
}

// Write the addon, its slots and the bells under <data>/addons, then link them into
// the game. Returns what was written so install can report it and decide whether the
// game needs a full restart.
export function installAddons({ sourceAddon, dataDir, gameAddons, slots = 1200 }) {
  const addonsHome = addonsHomeFor(dataDir);
  fs.mkdirSync(addonsHome, { recursive: true });
  syncAddon(sourceAddon, addonsHome);
  const bank = new SlotBank(addonsHome, { slots });
  const had = bank.installedSlotCount();
  const bellsMissing = !fs.existsSync(bank.sigFile(CTL_LONG));
  const { made, kept, pruned } = bank.install();
  if (had > slots) bank.removeSlots(slots);
  const links = linkAddons({ addonsHome, gameAddons });
  return { addonsHome, bank, links, had, bellsMissing, made, kept, pruned };
}
