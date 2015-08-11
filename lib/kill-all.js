'use strict';

var kill = require('tree-kill');

process.argv.slice(2).forEach(function(pid) {
  kill(pid, function(err) {
    if (err) console.error(err);
  });
});
