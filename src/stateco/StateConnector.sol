// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

contract StateConnector {

//====================================================================
// Data Structures
//====================================================================

    struct Payload {
        bool        exists;
        uint256     attestationTime;
        bytes32     payloadHash;
    }

    uint256 private constant ATTESTATION_WINDOW = 5 minutes;
    address private constant GENESIS_COINBASE = address(0x0100000000000000000000000000000000000000);

    // Requested transactions
    mapping(bytes32 => Payload) private requestedTransactions;
    // Proven transactions
    mapping(bytes32 => Payload) private provenTransactions;
    // Transaction attestations
    mapping(bytes32 => bool) private attestations;

//====================================================================
// Events
//====================================================================

    event AttestationRequested(
        address sender,
        uint64 chainId,
        uint64 blockHeight,
        bytes32 txId,
        uint16 utxo,
        bytes32 payloadHash
    );

    event AttestationSubmitted(
        address sender,
        bytes32 requestLocation,
        bytes32 payloadHash
    );

    event TransactionProven(
        address requester,
        uint64 chainId,
        uint64 blockHeight,
        bytes32 txId,
        uint16 utxo,
        bytes32 payloadHash
    );

//====================================================================
// Constructor
//====================================================================

    constructor() {
    }

//====================================================================
// Functions
//====================================================================  

    function requestAttestations(
        uint64 chainId,
        uint64 blockHeight,
        bytes32 txId,
        uint16 utxo,
        bytes32 payloadHash
    ) external payable {
        // Check for correct fee burn
        require(msg.value == 1 ether);
        // Check for empty inputs
        require(blockHeight > 0, "blockHeight == 0");
        require(txId > 0x0, "txId == 0x0");
        require(payloadHash > 0x0, "payloadHash == 0x0");

        // Check if this transaction has already been proven
        bytes32 location = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_LOCATION")),
            keccak256(abi.encodePacked(chainId)),
            keccak256(abi.encodePacked(blockHeight)),
            keccak256(abi.encodePacked(txId)),
            keccak256(abi.encodePacked(utxo))
        ));
        require(!provenTransactions[location].exists, "transaction already proven");

        // Store the attestation request
        bytes32 requestLocation = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_REQUEST")),
            keccak256(abi.encodePacked(msg.sender)),
            location
        ));
        requestedTransactions[requestLocation] = Payload(
            true,
            block.timestamp + ATTESTATION_WINDOW,
            payloadHash
        );

        // Emit the AttestationRequested event
        emit AttestationRequested(msg.sender, chainId, blockHeight, txId, utxo, payloadHash);
    }

    function submitAttestation(
        bytes32 requestLocation,
        bytes32 payloadHash
    ) external {
        // Store the attestation submission
        attestations[keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_ATTEST")),
            keccak256(abi.encodePacked(msg.sender)),
            requestLocation,
            payloadHash
        ))] = true;

        // Emit the AttestationSubmitted event
        emit AttestationSubmitted(msg.sender, requestLocation, payloadHash);
    }

    function getAttestation(
        bytes32 requestLocation,
        bytes32 payloadHash
    ) external view returns (
        bool _attested
    ) {
        return attestations[keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_ATTEST")),
            keccak256(abi.encodePacked(msg.sender)),
            requestLocation,
            payloadHash
        ))];
    }

    function proveTransaction(
        uint64 chainId,
        uint64 blockHeight,
        bytes32 txId,
        uint16 utxo,
        bytes32 payloadHash
    ) external returns (
        bytes32 _requestLocation,
        bytes32 _payloadHash
     ) {
        // Check for empty inputs
        require(blockHeight > 0, "blockHeight == 0");
        require(txId > 0x0, "txId == 0x0");
        require(payloadHash > 0x0, "payloadHash == 0x0");

        // Check for valid block.coinbase variable
        require(block.coinbase == msg.sender || block.coinbase == GENESIS_COINBASE, "invalid block.coinbase value");

        // Check if this transaction has already been proven
        bytes32 location = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_LOCATION")),
            keccak256(abi.encodePacked(chainId)),
            keccak256(abi.encodePacked(blockHeight)),
            keccak256(abi.encodePacked(txId)),
            keccak256(abi.encodePacked(utxo))
        ));
        require(!provenTransactions[location].exists, "transaction already proven");

        // Check the validity of the transaction proof request 
        bytes32 requestLocation = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_REQUEST")),
            keccak256(abi.encodePacked(msg.sender)),
            location
        ));
        require(requestedTransactions[requestLocation].exists == true, 
            "requested transaction has not been requested");
        require(block.timestamp >= requestedTransactions[requestLocation].attestationTime, 
            "proveTransaction too early");
        require(requestedTransactions[requestLocation].payloadHash == payloadHash, 
            "payloadHash does not match attestation request");

        if (block.coinbase == msg.sender && block.coinbase != GENESIS_COINBASE) {
            provenTransactions[location] = Payload(
                true,
                block.timestamp,
                payloadHash
            );
            emit TransactionProven(msg.sender, chainId, blockHeight, txId, utxo, payloadHash);
        }

        return (requestLocation, payloadHash);
    }

    function constructTransactionProof(
        uint64 chainId,
        uint64 blockHeight,
        bytes32 txId,
        uint16 utxo,
        bytes32 destinationHash,
        bytes32 dataHash,
        uint256 amount
    ) external view returns (
        bool _proven
    ) {
        bytes32 location = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_LOCATION")),
            keccak256(abi.encodePacked(chainId)),
            keccak256(abi.encodePacked(blockHeight)),
            keccak256(abi.encodePacked(txId)),
            keccak256(abi.encodePacked(utxo))
        ));
        require(provenTransactions[location].exists, "transaction not proven");
        bytes32 payloadHash = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_PAYLOAD")),
            destinationHash,
            dataHash,
            keccak256(abi.encodePacked(amount))
        ));
        require(provenTransactions[location].payloadHash == payloadHash, "invalid payloadHash");

        return (provenTransactions[location].exists);
    }

}
