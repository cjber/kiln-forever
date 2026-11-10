import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  escapeWow,
  fitFont,
  markdownToWow,
} from '../src/format.js';

const bold = (s) => `|cffffffff${s}|r`;
const italic = (s) => `|cffb8c7ff${s}|r`;
const strike = (s) => `|cff9d9d9d${s}|r`;
const code = (s) => `|cffa8c7fa${s}|r`;
const gold = (s) => `|cffffd100${s}|r`;

test('paragraph lines join with one space and a blank line separates paragraphs', () => {
  assert.equal(markdownToWow('one line\nsecond line\n\nnext paragraph'), 'one line second line\n\nnext paragraph');
  assert.equal(markdownToWow('one line\n\n\n\nnext paragraph'), 'one line\n\nnext paragraph');
});

test('a hard break keeps its newline, with two trailing spaces or a trailing backslash', () => {
  assert.equal(markdownToWow('first  \nsecond'), 'first\nsecond');
  assert.equal(markdownToWow('first\\\nsecond'), 'first\nsecond');
  assert.equal(markdownToWow('first\nsecond'), 'first second');
});

test('headings, emphasis, code, quotes and rules become their colours', () => {
  assert.equal(markdownToWow('# Title'), gold('Title'));
  assert.equal(markdownToWow('## Closed ##'), gold('Closed'));
  assert.equal(markdownToWow('**bold**'), bold('bold'));
  assert.equal(markdownToWow('__bold__'), bold('bold'));
  assert.equal(markdownToWow('***both***'), bold('both'));
  assert.equal(markdownToWow('*italic*'), italic('italic'));
  assert.equal(markdownToWow('_italic_'), italic('italic'));
  assert.equal(markdownToWow('~~gone~~'), strike('gone'));
  assert.equal(markdownToWow('`code`'), code('code'));
  assert.equal(markdownToWow('> quoted'), strike('quoted'));
  assert.equal(markdownToWow('---'), strike('-----'));
});

test('nested ordered and unordered lists keep continuation lines with their item', () => {
  const w = markdownToWow('- first line\n  continues here\n  - nested\n1. ordered\n2. second');
  assert.match(w, new RegExp(`${gold('•')} first line continues here`));
  assert.match(w, new RegExp(`  ${gold('•')} nested`));
  assert.match(w, new RegExp(`${gold('1.')} ordered`));
  assert.match(w, new RegExp(`${gold('2.')} second`));
});

test('task list items show an unchecked or checked box', () => {
  assert.equal(markdownToWow('- [ ] todo'), `${gold('•')} ${strike('[ ]')} todo`);
  assert.equal(markdownToWow('- [x] done'), `${gold('•')} ${gold('[x]')} done`);
});

test('tables join their cells, and links show their text', () => {
  const w = markdownToWow('| a | b |\n|---|---|\n| c | |');
  assert.equal(w, 'a  ·  b\nc  ·');
  assert.equal(markdownToWow('[docs](https://example.com)'), 'docs');
  assert.equal(markdownToWow('![alt](https://example.com/x.png)'), '[image: alt]');
  assert.equal(markdownToWow('<https://example.com>'), 'https://example.com');
});

test('fenced code keeps every line, and backslash escapes stay literal', () => {
  const w = markdownToWow('```js\nalpha\n\nbeta\n```');
  assert.equal(w, [code('  alpha'), code('  '), code('  beta')].join('\n'));
  assert.equal(markdownToWow('\\*not italic\\*'), '*not italic*');
  assert.equal(markdownToWow('a \\| b'), 'a || b');
});

test('pipes are always escaped for WoW markup', () => {
  assert.equal(escapeWow('a|b'), 'a||b');
  assert.match(markdownToWow('a | b'), /a \|\| b/);
});

test('fitFont keeps covered characters and rewrites or drops the rest', () => {
  assert.equal(fitFont('✓'), '+');
  assert.equal(fitFont('→'), '->');
  assert.equal(fitFont('🙂'), '');
  assert.equal(fitFont('é'), 'é');
  assert.equal(fitFont('e\u0301'), 'é', 'NFC first');
  assert.equal(fitFont('•'), '•');
  assert.equal(fitFont('…'), '…', 'ellipsis is in the font');
  assert.equal(fitFont('a 🙂 b'), 'a  b');
});

test('fitFont keeps tabs as spaces', () => {
  assert.equal(fitFont('a\tb'), 'a    b');
});
