const config = require('./settings.json');
module.exports = time => Math.floor(time / 12) % config.period;
