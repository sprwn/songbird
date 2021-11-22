// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

'use strict';
process.env.NODE_ENV = 'production';
const Web3 = require('web3');
const web3 = new Web3();
const Tx = require('ethereumjs-tx').Transaction;
const Common = require('ethereumjs-common').default;
const fs = require('fs');

const stateConnectorContract = "0x1000000000000000000000000000000000000001";
const chains = {
	'btc': {
		chainId: 0
	},
	'ltc': {
		chainId: 1
	},
	'doge': {
		chainId: 2
	},
	'xrp': {
		chainId: 3
	}
};
var config,
	customCommon,
	stateConnector;


// ===============================================================
// Chain Common Functions
// ===============================================================

async function run(chainId) {
	stateConnector.methods.getLatestIndex(parseInt(chainId)).call({
		from: config.accounts[1].address,
		gas: config.flare.gas,
		gasPrice: config.flare.gasPrice
	}).catch(processFailure)
		.then(result => {
			const leafPromise = new Promise((resolve, reject) => {
				console.log('\nchainId: \t\t', chainId, '\n',
					'ledger: \t\t', ledgerBoundary, '\n',
					'txId: \t\t\t', txId, '\n',
					'destination: \t\t', destinationAddress, '\n',
					'destinationTag: \t', destinationTag, '\n',
					'amount: \t\t', parseInt(amount), '\n',
					'currency: \t\t', currency, '\n');
				var destinationHash,
					txIdFormatted;
				if (chainId >= 0 && chainId < 3) {
					txIdFormatted = destinationTag + txId;
					destinationHash = web3.utils.soliditySha3(destinationAddress);
				} else if (chainId == 3) {
					txIdFormatted = txId;
					destinationHash = web3.utils.soliditySha3(web3.utils.soliditySha3(destinationAddress), web3.utils.soliditySha3(destinationTag));
				}
				const txIdHash = web3.utils.soliditySha3(txIdFormatted);
				const amountHash = web3.utils.soliditySha3(parseInt(amount));
				const currencyHash = web3.utils.soliditySha3(currency);
				const paymentHash = web3.utils.soliditySha3(txIdHash, destinationHash, amountHash, currencyHash);
				const leaf = {
					"chainId": chainId,
					"txId": txIdFormatted,
					"ledger": ledgerBoundary,
					"destination": destinationHash,
					"amount": parseInt(amount),
					"currency": currencyHash,
					"paymentHash": paymentHash,
				}
				resolve(leaf);
			})
			leafPromise.then(leaf => {
				if (parseInt(leaf.ledger) >= result[0] || parseInt(leaf.ledger) < result[3]) {
					stateConnector.methods.getPaymentFinality(
						leaf.chainId,
						web3.utils.soliditySha3(leaf.txId),
						leaf.destination,
						leaf.amount,
						leaf.currency).call({
							from: config.accounts[1].address,
							gas: config.flare.gas,
							gasPrice: config.flare.gasPrice
						})
						.catch(() => {
						})
						.then(result => {
							if (typeof result != "undefined") {
								console.log("Disproven up to:\t", result.ledger);
							}
							return disprovePaymentFinality(leaf);
						})
				} else {
					return processFailure('Ledger data not yet available on Flare.')
				}
			})
		})
}

async function disprovePaymentFinality(leaf) {
	web3.eth.getTransactionCount(config.accounts[1].address)
		.then(nonce => {
			return [stateConnector.methods.disprovePaymentFinality(
				leaf.chainId,
				leaf.paymentHash,
				leaf.ledger,
				leaf.txId).encodeABI(), nonce];
		})
		.then(txData => {
			var rawTx = {
				nonce: txData[1],
				gasPrice: web3.utils.toHex(parseInt(config.flare.gasPrice)),
				gas: web3.utils.toHex(config.flare.gas),
				to: stateConnector.options.address,
				from: config.accounts[1].address,
				data: txData[0]
			};
			var tx = new Tx(rawTx, { common: customCommon });
			var key = Buffer.from(config.accounts[1].privateKey, 'hex');
			tx.sign(key);
			var serializedTx = tx.serialize();
			const txHash = web3.utils.sha3(serializedTx);
			console.log('Delivering proof:\t\x1b[33m', txHash, '\x1b[0m');
			web3.eth.getTransaction(txHash)
				.then(txResult => {
					if (txResult == null) {
						web3.eth.sendSignedTransaction('0x' + serializedTx.toString('hex'))
							.on('receipt', receipt => {
								if (receipt.status == false) {
									return processFailure('receipt.status == false');
								} else {
									console.log('Proof delivered:\t \x1b[33m' + receipt.transactionHash + '\x1b[0m');
								}
							})
							.on('error', error => {
								return processFailure(error);
							});
					} else {
						return processFailure('Already waiting for this transaction to be delivered.');
					}
				})
		})
}

async function configure(chainId) {
	web3Config().catch(processFailure)
		.then(run(chainId).catch(processFailure));
}

async function web3Config() {
	let rawConfig = fs.readFileSync('config.json');
	config = JSON.parse(rawConfig);
	web3.setProvider(new web3.providers.HttpProvider(config.flare.url));
	web3.eth.handleRevert = true;
	customCommon = Common.forCustomChain('ropsten',
		{
			name: 'coston',
			networkId: config.flare.chainId,
			chainId: config.flare.chainId,
		},
		'petersburg');
	// Read the compiled contract code
	let source = fs.readFileSync("../../../bin/src/stateco/StateConnector.json");
	let contract = JSON.parse(source);
	// Create Contract proxy class
	stateConnector = new web3.eth.Contract(contract.abi);
	// Smart contract EVM bytecode as hex
	stateConnector.options.data = '0x' + contract.deployedBytecode;
	stateConnector.options.from = config.accounts[1].address;
	stateConnector.options.address = stateConnectorContract;
	web3.eth.getBalance(config.accounts[1].address)
		.then(balance => {
			if (parseInt(web3.utils.fromWei(balance, "ether")) < 1000) {
				console.log("Not enough FLR reserved in your account, need 1k FLR.");
				sleep(1000);
				process.exit();
			}
		})
}


async function processFailure(error) {
	console.error('error:', error);
	setTimeout(() => { return process.exit() }, 2500);
}

async function sleep(ms) {
	return new Promise((resolve) => {
		setTimeout(resolve, ms);
	});
}

const chainName = process.argv[2];
const txId = process.argv[3];
const amount = process.argv[4];
const currency = process.argv[5];
const ledgerBoundary = process.argv[6];
const destinationAddress = process.argv[7];
const destinationTag = process.argv[8];
if (chainName in chains) {
	return configure(chains[chainName].chainId);
} else {
	processFailure('Invalid chainName');
}