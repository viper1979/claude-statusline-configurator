'use strict';
/**
 * Conformance harness for the preview Render Adapter.
 *
 * Extracts the pure rendering block between `// @conformance-begin` and
 * `// @conformance-end` from statusline-configurator.html and evaluates it in an
 * empty VM context. The context deliberately has no `document`, `window` or
 * `state`: any DOM access inside the block surfaces as a ReferenceError here.
 *
 * Usage:
 *   node render-harness.js --check <html>             -> {"functions":[...]}
 *   node render-harness.js <html> <fixture.json>      -> [{"name":..., "text":...}, ...]
 */
const fs   = require('fs');
const vm   = require('vm');
const path = require('path');

const MARKER_BEGIN = '// @conformance-begin';
const MARKER_END   = '// @conformance-end';

// Functions the harness itself relies on; reported by --check so the Pester guard
// can assert the block exposes the adapter surface.
const REQUIRED_FUNCTIONS = ['formatFieldValue', 'formatAgo', 'renderFieldHtml'];

/**
 * Cuts the rendering block out of the HTML source.
 * @param {string} htmlPath
 * @returns {string} JavaScript source between the two markers
 */
function extractBlock(htmlPath) {
  const html = fs.readFileSync(htmlPath, 'utf8');
  const count = marker => html.split(marker).length - 1;
  if (count(MARKER_BEGIN) !== 1 || count(MARKER_END) !== 1) {
    throw new Error(`expected exactly one ${MARKER_BEGIN} and one ${MARKER_END} in ${path.basename(htmlPath)}`);
  }
  const start = html.indexOf(MARKER_BEGIN) + MARKER_BEGIN.length;
  const end   = html.indexOf(MARKER_END);
  if (end < start) throw new Error('end marker precedes begin marker');
  return html.slice(start, end);
}

/**
 * Evaluates the block in a fresh context and returns that context.
 * Top-level `function` and `const` declarations of the block stay reachable for
 * later scripts run in the same context.
 * @param {string} source
 * @returns {vm.Context}
 */
function evaluateBlock(source) {
  const context = vm.createContext({});
  vm.runInContext(source, context, { filename: 'conformance-block.js' });
  return context;
}

/**
 * Resolves a function declared in the block.
 * @param {vm.Context} context
 * @param {string} name
 * @returns {Function|undefined}
 */
function getBlockFunction(context, name) {
  return vm.runInContext(`typeof ${name} === 'function' ? ${name} : undefined`, context);
}

/**
 * Reduces a rendered HTML snippet to its visible text: tags removed, the five
 * entities escapeHtml() produces turned back into characters. Tags go first so an
 * escaped '<' in the content can never be mistaken for markup.
 * @param {string} html
 * @returns {string}
 */
function htmlToText(html) {
  return html
    .replace(/<[^>]*>/g, '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&');
}

/**
 * Escapes every non-ASCII character as \uXXXX so the JSON survives any console
 * encoding between Node and PowerShell.
 * @param {string} json
 * @returns {string}
 */
function toAsciiJson(json) {
  // split('') yields UTF-16 code units, which is exactly what JSON \uXXXX escapes encode.
  return json.split('').map(ch => ch.charCodeAt(0) > 126
    ? '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0')
    : ch).join('');
}

/**
 * --check mode: proves the block evaluates DOM-free and lists the required functions found.
 * @param {string} htmlPath
 */
function runCheck(htmlPath) {
  const context = evaluateBlock(extractBlock(htmlPath));
  const functions = REQUIRED_FUNCTIONS.filter(name => typeof getBlockFunction(context, name) === 'function');
  process.stdout.write(JSON.stringify({ functions }));
}

/**
 * Render mode: renders every case of a Conformance Fixture through the preview adapter.
 * Writes [{name, text}] to stdout.
 * @param {string} htmlPath
 * @param {string} fixturePath
 */
function runFixture(htmlPath, fixturePath) {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
  const context = evaluateBlock(extractBlock(htmlPath));
  const renderFieldHtml = getBlockFunction(context, 'renderFieldHtml');
  if (typeof renderFieldHtml !== 'function') throw new Error('block does not define renderFieldHtml');
  const nowSeconds = fixture.now ?? null;
  const results = fixture.cases.map(c => ({
    name: c.name,
    text: htmlToText(renderFieldHtml(c.field, c.payload, null, null, nowSeconds)),
  }));
  process.stdout.write(toAsciiJson(JSON.stringify(results)));
}

/**
 * Entry point.
 */
function main() {
  const args = process.argv.slice(2);
  try {
    if (args[0] === '--check') {
      runCheck(args[1]);
      return;
    }
    if (args.length === 2) {
      runFixture(args[0], args[1]);
      return;
    }
    throw new Error('usage: render-harness.js --check <html> | <html> <fixture.json>');
  } catch (error) {
    process.stderr.write(`render-harness: ${error.message}\n`);
    process.exit(1);
  }
}

main();
