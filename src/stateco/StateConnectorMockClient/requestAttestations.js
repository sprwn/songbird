// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

'use strict';
process.env.NODE_ENV = 'production';
const Web3 = require('web3');
const web3 = new Web3();
const fs = require('fs');

let rawConfig = fs.readFileSync('config.json');
let config = JSON.parse(rawConfig);

web3.setProvider(new web3.providers.HttpProvider(config.url));
web3.eth.handleRevert = true;

// Read the compiled contract code
let source = fs.readFileSync(config.stateConnectorABI);
let contract = JSON.parse(source);
// Create Contract proxy class
let stateConnector = new web3.eth.Contract(contract.abi);
// Smart contract EVM bytecode as hex
stateConnector.options.data = '0x' + contract.deployedBytecode;
stateConnector.options.from = config.accounts[1].address;
stateConnector.options.address = config.stateConnectorContract;

let instructions = process.argv[2];
let id = process.argv[3];
let dataAvailabilityProof = process.argv[4];

return requestAttestations(instructions, id, dataAvailabilityProof);

async function requestAttestations(instructions, id, dataAvailabilityProof) {
	web3.eth.getTransactionCount(stateConnector.options.from)
    .then(nonce => {
        return [nonce, 
            stateConnector.methods.requestAttestations(
            instructions,
            id,
            dataAvailabilityProof).encodeABI()];
    })
    .then(txData => {
        var rawTx = {
            chainId: config.chainId,
            nonce: txData[0],
            gasPrice: web3.utils.toHex(web3.utils.toWei(config.gasPrice, 'gwei')),
            gas: web3.utils.toHex(config.gas),
            to: stateConnector.options.address,
            from: stateConnector.options.from,
            data: txData[1]
        };
        web3.eth.accounts.signTransaction(rawTx, config.accounts[1].privateKey)
        .then(signedTx => {
            web3.eth.sendSignedTransaction(signedTx.rawTransaction)
            .then(result => {
                console.log(result);
                setTimeout(() => {requestAttestations(instructions, id, dataAvailabilityProof)}, 5000);
            });
        })
    })
}