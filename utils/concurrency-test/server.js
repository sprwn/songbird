// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

const fs = require('fs');
const ethers = require('ethers');
const solc = require('solc');
const accounts = require('./test-1020-accounts.json');
const providers = [];
const wallets = [];
const counterFactories = [];
const counters = [];
const promises = [];
const stats = [];
let executionTimeMs = 0;
let maxTimeMs = 0;
let minTimeMs = Number.MAX_VALUE;
let startMs = Date.now();

const makeIncrementPromise = (i) => {
  return new Promise(async (resolve) => {
    stats[i].attempts += 1;
    stats[i].lastStartTs = Date.now();
    await counters[i].increment([])
      .then(async (tx) => {
        // wait until the transaction is mined
        await tx.wait()
          .then(async (receipt) => {
            await counters[i].count([])
              .then((count) => {
                let elapsed = Date.now() - stats[i].lastStartTs;
                executionTimeMs += elapsed;
                if (elapsed < minTimeMs) {
                  minTimeMs = elapsed;
                }
                if (elapsed > maxTimeMs) {
                  maxTimeMs = elapsed;
                }
                stats[i].successes = count;
                console.log(`counters[${i}] = ${counters[i].address}; count = ${count.toString()}`);
                resolve(i);
              })
              .catch((err) => {
                console.log(`Error getting count for counters[${i}] = ${err}`);
                resolve(i);
              });
          })
          .catch((err) => {
            console.log(`Error waiting for increment to mine for counters[${i}] = ${err}`);
            resolve(i);
          });
      })
      .catch((err) => {
        console.log(`Error waiting for increment tx for counters[${i}] = ${err}`);
        resolve(i);
      });
  });      
};

async function main() {
  // Get command line arguments from command line parser
  const {threads, endpoints} = require("./cl").getArgs("node server.js");

  // Read in counter contract
  const source = fs.readFileSync('./contracts/Counter.sol', 'utf8');

  // Compile Counter contract
  const input = {
    language: 'Solidity',
    sources: {
        'Counter.sol': {
          content: source,
        },
    },
    settings: {
        outputSelection: {
          '*': {
              '*': ['*'],
          },
        },
    },
  };
  const compilerResult = JSON.parse(solc.compile(JSON.stringify(input)));
  const counterArtifact = compilerResult.contracts['Counter.sol']['Counter'];
  const counterBytecode = counterArtifact.evm.bytecode.object;
  const counterABI = counterArtifact.abi;

  endpoints.forEach((endpoint) => {
    const provider = new ethers.providers.StaticJsonRpcProvider(endpoint);
    providers.push(provider);
  });

  // Create a wallet for each "thread" of execution, across all providers, and
  // associate wallet to a contract factory.
  let accountIdx = 0;
  providers.forEach((provider) => {
    for(let thread = 0; thread < threads; thread++) {
      const wallet = new ethers.Wallet(accounts[accountIdx++].privateKey, provider);
      wallets.push(wallet);  
      // Create factory for Counter contract
      const counterFactory = new ethers.ContractFactory(counterABI, counterBytecode, wallet);
      counterFactories.push(counterFactory);
    }
  });

  // Deploy all contracts
  deploys = [];
  for (let i = 0; i < counterFactories.length; i++) {
    counters[i] = await counterFactories[i].deploy([]);
    deploys.push(counters[i].deployed());
  }
  await Promise.all(deploys);
  
  // Prime promises and stats for each contract
  for (let i = 0; i < counters.length; i++) {
    stats[i] = { attempts: 0, successes: 0, lastStartTs: 0 }
    promises[i] = makeIncrementPromise(i);
  }

  // Spew out stats
  setInterval(() => {
    let txCount = 0;
    let txAttempt = 0;
    stats.map((stat) => {txCount += Number(stat.successes)});
    stats.map((stat) => {txAttempt += Number(stat.attempts)});
    console.log(`Attempts = ${txAttempt}; Tx count = ${txCount}; TPS = ${txCount / ((Date.now() - startMs) / 1000)}; Avg ms = ${executionTimeMs / txCount}; Max ms = ${maxTimeMs}; Min ms = ${minTimeMs}`)
  }, 5000);

  // Spin forever and pound the validator with transactions
  while(true) {
    const index = await Promise.race(promises);
    promises[index] = makeIncrementPromise(index);
  }  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
