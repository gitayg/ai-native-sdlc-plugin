#!/usr/bin/env node
// usage: widget <command> [options]
const commands = {
  list: 'list every widget',
  create: 'create one widget',
  remove: 'remove one widget',
  serve: 'serve the HTTP interface',
};

function main(argv) {
  const cmd = argv[2];
  if (!cmd) throw new Error('no command given');
  if (!commands[cmd]) throw new Error('unknown command');
  return cmd;
}

module.exports = { main, commands };
