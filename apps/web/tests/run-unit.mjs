// Birim testlerini esbuild ile paketleyip çalıştırır (ek bağımlılık gerekmez)
import { build } from 'esbuild'
import { pathToFileURL, fileURLToPath } from 'node:url'
import path from 'node:path'
import fs from 'node:fs'
const here = path.dirname(fileURLToPath(import.meta.url))
const out = path.join(here, '.unit.bundle.mjs')
const entries = ['unit.test.js', 'unit.workout.test.js', 'unit.plan.test.js'].filter((f) => fs.existsSync(path.join(here, f)))
const tmp = path.join(here, '.unit.entry.js')
fs.writeFileSync(tmp, entries.map((f) => `import './${f}'`).join('\n'))
await build({ entryPoints: [tmp], bundle: true, platform: 'node', format: 'esm', outfile: out, logLevel: 'error', define: { 'import.meta.env': '{}' }, alias: { '@': path.join(here, '../src') } })
try { await import(pathToFileURL(out).href) } finally { fs.rmSync(tmp, { force: true }) }
