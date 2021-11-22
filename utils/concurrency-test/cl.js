// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

module.exports.getArgs = function (_scriptName) {
  const { argv } = require("yargs")
  .scriptName(_scriptName)
  .usage("Usage: $0 -t num")
  .example(
    "$0 -t 10 -e 'http://127.0.0.1:9650/ext/bc/C/rpc'",
    "Runs a stress test to send simultaneous transactions to Ava validator."
  )
  .option("t", {
    alias: "threads",
    describe: "The number of threads to start for each endpoint.",
    demandOption: "The number of threads are required.",
    type: "number",
    nargs: 1,
  })
  .array("e")
  .option("e", {
    alias: "endpoints",
    default: null,
    type: "string",
    describe: "The url(s) of the endpoint(s) for the chain.",
    demandOption: "At lease one endpoint is required."
  })
  .describe("help", "Show help."); // Override --help usage message.
  return argv;
}