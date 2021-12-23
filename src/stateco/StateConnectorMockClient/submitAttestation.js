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
stateConnector.options.from = config.accounts[0].address;
stateConnector.options.address = config.stateConnectorContract;

web3.eth.getBlockNumber()
.then(fromBlockNumber => {
    collectEvents(fromBlockNumber, -1, {bufferNumber:[], attestationLeaf:[]});
})

async function collectEvents(fromBlockNumber, openBufferNumber, openAttestationLeaves) {
    web3.eth.getBlock("latest")
    .then(block => {
        var bufferNumber = Math.floor((block.timestamp-config.bufferTimestampOffset)/config.bufferWindow);
        var wallTimestamp = Math.round(+new Date()/1000);
        if ((bufferNumber > openBufferNumber || wallTimestamp - block.timestamp > config.bufferWindow) && openBufferNumber > -1) {
            // Time to finalise the previous buffer
        } else if (fromBlockNumber >= block.number) {
            console.log("Awaiting the creation of new blocks...");
            setTimeout(() => {collectEvents(block.number, openBufferNumber, openAttestationLeaves)}, 10000);
        } else {
            console.log("Collecting attestation requests from block ", fromBlockNumber, "to ", block.number);
            web3.eth.getPastLogs({
                fromBlock: fromBlockNumber,
                toBlock: block.number,
                address: stateConnector.options.address
            })
            .then(events => {
                if (events.length == 0) {
                    setTimeout(() => {collectEvents(block.number+1, openBufferNumber, openAttestationLeaves)}, 10000);
                } else {
                    events.forEach((event, i) => {
                        return parseEventData(event.data, event.blockNumber)
                        .then(parsedEvent => {
                            if (openBufferNumber == -1) {
                                return collectEvents(event.blockNumber, parsedEvent[0]+1, openAttestationLeaves);
                            } else if (parsedEvent[0] == openBufferNumber) {
                                openAttestationLeaves.bufferNumber.concat(parsedEvent[0]);
                                openAttestationLeaves.attestationLeaf.concat(parsedEvent[1]);
                                if (i+1 == events.length) {
                                    setTimeout(() => {collectEvents(block.number+1, openBufferNumber, openAttestationLeaves)}, 10000);
                                }
                            } else if (parsedEvent[0] > openBufferNumber) {
                                // attestationLeaves is now a complete merkle tree
                                // send attestation using openAttestationLeaves
                                // begin operating on next buffer number
                                setTimeout(() => {collectEvents(fromBlockNumber, parsedEvent[0], {bufferNumber:[], attestationLeaf:[]})}, 10000);
                            }
                        })
                    })
                }
            })
        }
    })
}

async function parseEventData(eventData, eventBlockNumber) {
    var bufferNumber = Math.floor((web3.utils.hexToNumber(eventData.slice(0,66))-config.bufferTimestampOffset)/config.bufferWindow);
    var instructions = "0x" + eventData.slice(66,130);
    var id = "0x" + eventData.slice(130,194);
    var dataAvailabilityProof = "0x" + eventData.slice(194,258);
    console.log("Buffer Round:\t", bufferNumber, '\nInstructions:\t', instructions, '\nID:\t\t', id, '\nData Availability Proof:\t', dataAvailabilityProof, '\n');
    if (instructions == "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") {
        // Mock event interface
        return [bufferNumber, web3.utils.soliditySha3(eventBlockNumber, bufferNumber, instructions, id, dataAvailabilityProof)];
    } else {
        // Include custom event types as unique function calls here:
        return [bufferNumber, "0x0000000000000000000000000000000000000000000000000000000000000000"];
    }
}

async function submitAttestation(attestationLeaves) {

}

async function prepareMerkleTree(attestationLeaves) {

}

// stateConnector.methods.buffers(stateConnector.options.from).call()
// .then(console.log);
