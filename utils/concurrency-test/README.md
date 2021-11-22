# Concurrency Test
This utility will run a concurrency test against the Flare network.

## Synopsis
The concurrency test will create one instance of the Counter contract located in the contracts directory for every "thread" specified by the `-t` parameter, for every endpoint specified by the `-e` parameter. The test will then repeatedly call the `increment()` method on the contract for each "thread", in a loop, measuring transaction throughput over time. Note that "threads" are meant to denote simultaneous transactions.

## Usage

### Single Node
Start `../../cmd/single.sh` script to run a 1-node local network.

Then run `npm start -- -t 40 -e 'http://127.0.0.1:9650/ext/bc/C/rpc'`. This will run 40 simultaneous transactions against one endpoint.

### 5 Nodes
Start `../../cmd/local.sh` script to run a 5-node local network.

Then run `npm start -- -t 40 -e 'http://127.0.0.1:9650/ext/bc/C/rpc' -e 'http://127.0.0.1:9652/ext/bc/C/rpc' -e 'http://127.0.0.1:9654/ext/bc/C/rpc' -e 'http://127.0.0.1:9656/ext/bc/C/rpc' -e 'http://127.0.0.1:9658/ext/bc/C/rpc'`. This will run 40 simultaneous transactions against five endpoints.