// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

'use strict';
process.env.NODE_ENV = 'production';
const Web3 = require('web3');
const web3 = new Web3();
const Tx = require('ethereumjs-tx').Transaction;
const Common = require('ethereumjs-common').default;
const fs = require('fs');
const fetch = require('node-fetch');

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
	stateConnector,
	api,
	username,
	password;

async function postData(url = '', username = '', password = '', data = {}) {
	const response = await fetch(url, {
		method: 'POST',
		headers: new fetch.Headers({
			'Authorization': 'Basic ' + Buffer.from(username + ':' + password).toString('base64'),
			'Content-Type': "application/json"
		}),
		credentials: 'include',
		body: JSON.stringify(data)
	}).catch(processFailure);
	return response.json();
}

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
			if (chainId >= 0 && chainId < 3) {
				const method = 'getrawtransaction';
				const params = [txId, true];
				postData(api, username, password, { method: method, params: params })
					.then(tx => {
						const method = 'getblockheader';
						const params = [tx.result.blockhash];
						postData(api, username, password, { method: method, params: params })
							.then(block => {
								const leafPromise = new Promise((resolve, reject) => {
									const amount = Math.floor(parseFloat(tx.result.vout[voutN].value).toFixed(8)*Math.pow(10,8));
									console.log('\nchainId: \t\t', chainId, '\n',
										'ledger: \t\t', block.result.height, '\n',
										'txId: \t\t\t', tx.result.txid, '\n',
										'destination: \t\t', tx.result.vout[voutN].scriptPubKey.addresses[0], '\n',
										'amount: \t\t', amount, '\n',
										'currency: \t\t', chainName, '\n');
									const voutNhex = web3.utils.toHex(parseInt(voutN));
									const txIdFormatted = voutNhex.slice(-1) + tx.result.txid;
									const txIdHash = web3.utils.soliditySha3(txIdFormatted);
									const destinationHash = web3.utils.soliditySha3(tx.result.vout[voutN].scriptPubKey.addresses[0]);
									const amountHash = web3.utils.soliditySha3(amount);
									const currencyHash = web3.utils.soliditySha3(chainName);
									const paymentHash = web3.utils.soliditySha3(txIdHash, destinationHash, amountHash, currencyHash);
									const leaf = {
										"chainId": chainId,
										"txId": txIdFormatted,
										"ledger": parseInt(block.result.height),
										"destination": destinationHash,
										"amount": amount,
										"currency": currencyHash,
										"paymentHash": paymentHash,
									}
									resolve(leaf);
								})
								leafPromise.then(leaf => {
									if (leaf.ledger >= result[0] && leaf.ledger < result[3]) {
										stateConnector.methods.getPaymentFinality(
											leaf.chainId,
											web3.utils.soliditySha3(leaf.txId),
											leaf.destination,
											leaf.amount.toString(),
											leaf.currency).call({
												from: config.accounts[1].address,
												gas: config.flare.gas,
												gasPrice: config.flare.gasPrice
											}).catch(() => {
											})
											.then(paymentResult => {
												if (typeof paymentResult != "undefined") {
													if ("finality" in paymentResult) {
														if (paymentResult.finality == true) {
															console.log('Payment already proven.');
															setTimeout(() => { return process.exit() }, 2500);
														} else {
															return provePaymentFinality(leaf);
														}
													} else {
														return processFailure('Bad response from underlying chain.')
													}
												} else {
													return provePaymentFinality(leaf);
												}
											})
									} else {
										return processFailure('Transaction not yet finalised on Flare.')
									}
								})
							})
					})
			} else if (chainId == 3) {
				const method = 'tx';
				const params = [{
					'transaction': txId,
					'binary': false
				}];
				postData(api, config.chains.xrp.username, config.chains.xrp.password, { method: method, params: params })
					.then(tx => {
						if (tx.result.TransactionType == 'Payment') {
							const leafPromise = new Promise((resolve, reject) => {
								var destinationTag;
								if (!("DestinationTag" in tx.result)) {
									destinationTag = 0;
								} else {
									destinationTag = parseInt(tx.result.DestinationTag);
								}
								var currency;
								var amount;
								if (typeof tx.result.meta.delivered_amount == "string") {
									currency = "xrp";
									amount = parseInt(tx.result.meta.delivered_amount);
								} else {
									currency = tx.result.meta.delivered_amount.currency + tx.result.meta.delivered_amount.issuer;
									amount = parseFloat(tx.result.meta.delivered_amount.value).toFixed(15)*Math.pow(10,15);
								}
								console.log('\nchainId: \t\t', chainId, '\n',
									'ledger: \t\t', tx.result.inLedger, '\n',
									'txId: \t\t\t', tx.result.hash, '\n',
									'destination: \t\t', tx.result.Destination, '\n',
									'destinationTag: \t', destinationTag, '\n',
									'amount: \t\t', amount, '\n',
									'currency: \t\t', currency, '\n');
								const txIdHash = web3.utils.soliditySha3(tx.result.hash);
								const destinationHash = web3.utils.soliditySha3(web3.utils.soliditySha3(tx.result.Destination), web3.utils.soliditySha3(destinationTag));
								const amountHash = web3.utils.soliditySha3(amount);
								const currencyHash = web3.utils.soliditySha3(currency);
								const paymentHash = web3.utils.soliditySha3(txIdHash, destinationHash, amountHash, currencyHash);
								const leaf = {
									"chainId": chainId,
									"txId": tx.result.hash,
									"ledger": parseInt(tx.result.inLedger),
									"destination": destinationHash,
									"amount": amount,
									"currency": currencyHash,
									"paymentHash": paymentHash,
								}
								resolve(leaf);
							})
							leafPromise.then(leaf => {
								if (leaf.ledger >= result[0] && leaf.ledger < result[3]) {
									stateConnector.methods.getPaymentFinality(
										leaf.chainId,
										web3.utils.soliditySha3(leaf.txId),
										leaf.destination,
										leaf.amount.toString(),
										leaf.currency).call({
											from: config.accounts[1].address,
											gas: config.flare.gas,
											gasPrice: config.flare.gasPrice
										}).catch(() => {
										})
										.then(paymentResult => {
											if (typeof paymentResult != "undefined") {
												if ("finality" in paymentResult) {
													if (paymentResult.finality == true) {
														console.log('Payment already proven.');
														setTimeout(() => { return process.exit() }, 2500);
													} else {
														return provePaymentFinality(leaf);
													}
												} else {
													return processFailure('Bad response from underlying chain.')
												}
											} else {
												return provePaymentFinality(leaf);
											}
										})
								} else {
									return processFailure('Transaction not yet finalised on Flare.')
								}
							})
						} else {
							console.log('Transaction type not yet supported.');
							setTimeout(() => { return process.exit() }, 2500);
						}
					})
			} else {
				return processFailure('Invalid chainId.');
			}
		})
}

async function provePaymentFinality(leaf) {
	web3.eth.getTransactionCount(config.accounts[1].address)
		.then(nonce => {
			return [stateConnector.methods.provePaymentFinality(
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
									setTimeout(() => { return process.exit() }, 2500);
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
	let rawConfig = fs.readFileSync('config.json');
	config = JSON.parse(rawConfig);
	if (chainId == 0) {
		api = config.chains.btc.api;
		username = config.chains.btc.username;
		password = config.chains.btc.password;
	} else if (chainId == 1) {
		api = config.chains.ltc.api;
		username = config.chains.ltc.username;
		password = config.chains.ltc.password;
	} else if (chainId == 2) {
		api = config.chains.doge.api;
		username = config.chains.doge.username;
		password = config.chains.doge.password;
	} else if (chainId == 3) {
		api = config.chains.xrp.api;
		username = config.chains.xrp.username;
		password = config.chains.xrp.password;
	}
	web3.setProvider(new web3.providers.HttpProvider(config.flare.url));
	web3.eth.handleRevert = true;
	customCommon = Common.forCustomChain('ropsten',
		{
			name: 'coston',
			networkId: config.flare.chainId,
			chainId: config.flare.chainId,
		},
		'petersburg');
	web3.eth.getBalance(config.accounts[1].address)
		.then(balance => {
			if (parseInt(web3.utils.fromWei(balance, "ether")) < 1000) {
				console.log("Not enough FLR reserved in your account, need 1k FLR.");
				sleep(5000);
				process.exit();
			} else {
				// Read the compiled contract code
				let source = fs.readFileSync("../../../bin/src/stateco/StateConnector.json");
				let contract = JSON.parse(source);
				// Create Contract proxy class
				stateConnector = new web3.eth.Contract(contract.abi);
				// Smart contract EVM bytecode as hex
				stateConnector.options.data = '0x' + contract.deployedBytecode;
				stateConnector.options.from = config.accounts[1].address;
				stateConnector.options.address = stateConnectorContract;
				return run(chainId);
			}
		})
}

async function processFailure(error) {
	console.error('error:', error);
	setTimeout(() => { return process.exit() }, 2500);
}

const chainName = process.argv[2];
const txId = process.argv[3];
const voutN = process.argv[4];
if (parseInt(voutN) >= 16) {
	processFailure('Proof-of-work payment index too large, must be lower than 16.');
} else if (parseInt(voutN) < 0) {
	processFailure('Proof-of-work payment index must be positive.');
}
if (chainName in chains) {
	return configure(chains[chainName].chainId);
} else {
	processFailure('Invalid chainName');
}