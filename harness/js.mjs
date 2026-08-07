#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
//
// Runs a .zy program through the playground's JavaScript engine, so that it can
// be driven from the command line like the other engines.  The engine itself
// lives in web/, which ZyQuality does not own — the path is resolved at run
// time and a clear message is printed if that checkout is missing.

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// The engine takes a resolver rather than reading the filesystem itself — in
// the playground there is no filesystem to read.  Without one, every `<#`
// fails, and a harness that omits it manufactures divergences the engine is
// not responsible for.  Shape mirrors web/tests/test_runner.mjs.
function makeModuleResolver(baseDir) {
  return async (importPath) => {
    const absPath = resolve(baseDir, importPath + '.zy');
    try {
      return {
        src: readFileSync(absPath, 'utf8'),
        resolver: makeModuleResolver(dirname(absPath)),
        resolvedPath: absPath,
      };
    } catch {
      return { notFound: true, path: absPath };
    }
  };
}

const here = dirname(fileURLToPath(import.meta.url));
const enginePath = process.env.ZY_JS_ENGINE
  ?? resolve(join(here, '../../web/src/zymbol/zymbol.js'));

if (!existsSync(enginePath)) {
  process.stderr.write(
    `zyquality: JavaScript engine not found at ${enginePath}\n` +
    `  set ZY_JS_ENGINE, or check out zymbol-lang/web next to this repo\n`);
  process.exit(127);
}

const file = process.argv[2];
if (!file) { process.stderr.write('usage: js.mjs FILE.zy\n'); process.exit(2); }

const { runZymbol } = await import(enginePath);

// Stdin is read up front: the engine's input callback is synchronous, so it
// cannot await a chunk that has not arrived yet.
let stdin = '';
if (!process.stdin.isTTY) {
  for await (const chunk of process.stdin) stdin += chunk;
}
const lines = stdin.split('\n');
let line = 0;

let out = '';
try {
  const abs = resolve(file);
  await runZymbol(
    readFileSync(abs, 'utf8'),
    async () => (line < lines.length ? lines[line++] : null),
    (s) => { out += s; },
    makeModuleResolver(dirname(abs)),
    abs);
  process.stdout.write(out);
} catch (e) {
  // Output produced before the failure still counts: the reference engines
  // print as they go, so discarding it would manufacture a divergence.
  process.stdout.write(out);
  process.stderr.write(String(e && e.message ? e.message : e) + '\n');
  process.exit(1);
}
