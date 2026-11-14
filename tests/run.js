// Runs the static check and every test in spec/ (or only the ones named:
// node run.js history tabs). Each spec runs in its own Lua 5.1 state
// (fengari) with stubs for the WoW client; it loads the addon's files from
// the folder above (global DIR) and prints "FAIL ..." lines and a final
// "ALL PASS" or "N FAILURES".
//
// Usage: npm test   (exit code 1 if anything fails)

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..').replace(/\\/g, '/');
const SPEC = path.join(__dirname, 'spec');

// Child mode: run one spec file.
if (process.argv[2] === '--one') {
  const { lua, lauxlib, lualib, to_luastring } = require('fengari');
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_pushstring(L, to_luastring(ROOT));
  lua.lua_setglobal(L, to_luastring('DIR'));
  const file = process.argv[3].replace(/\\/g, '/');
  if (lauxlib.luaL_dofile(L, to_luastring(file)) !== 0) {
    console.log('ERROR ' + lua.lua_tojsstring(L, -1));
  }
  return;
}

let failed = 0;

const check = spawnSync(process.execPath, [path.join(__dirname, 'check.js')], { encoding: 'utf8' });
process.stdout.write(check.stdout + check.stderr);
if (check.status !== 0) failed++;

const only = process.argv.slice(2);
const specs = fs.readdirSync(SPEC).filter(f => f.endsWith('.lua')).sort()
  .filter(f => only.length === 0 || only.includes(path.basename(f, '.lua')));

for (const f of specs) {
  const res = spawnSync(process.execPath, [__filename, '--one', path.join(SPEC, f)], { encoding: 'utf8' });
  const out = (res.stdout || '') + (res.stderr || '');
  const ok = res.status === 0 && /ALL PASS/.test(out) && !/^(FAIL|ERROR)|FAILURES|MISSING/m.test(out);
  console.log(`${ok ? 'pass' : 'FAIL'}  ${path.basename(f, '.lua')}`);
  if (!ok) {
    failed++;
    process.stdout.write(out.split(/\r?\n/).map(l => '      ' + l).join('\n') + '\n');
  }
}

console.log(failed === 0 ? 'All checks passed.' : `${failed} failed.`);
process.exitCode = failed === 0 ? 0 : 1;
