const assert = require('assert');
const { createWidget, getWidget } = require('../src/index.js');

test('createWidget refuses an empty body', () => {
  assert.throws(() => createWidget(null));
});

test('getWidget refuses a missing id', () => {
  assert.throws(() => getWidget(''));
});

test('createWidget returns what it was given', () => {
  assert.deepEqual(createWidget({ a: 1 }), { a: 1 });
});
