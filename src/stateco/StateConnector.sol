// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

contract StateConnector {

//====================================================================
// Data Structures
//====================================================================

    struct AttestationRequest {
        uint256     attestationWindowEndTime;
        bytes32     attestationHash;
    }

    address public constant GENESIS_COINBASE = address(0x0100000000000000000000000000000000000000);

    // For CYCLIC_BUFFER_SIZE==2048 it costs 524,288 SGB burned to cycle the buffer,
    // AND 65043 gas per buffer slot, i.e. 34,101,264,384 gas used to cycle the buffer.
    // If Flare blocks only contained requestAttestations txs, it would require
    // 4263 blocks to cycle the buffer.

    // This translates to an approx. lower-bound of 24 minutes required to cycle the buffer;
    // meaning that from the time a transaction is requested for attestation, a minimum of
    // 24 minutes is given to be able to both attest the transaction and then prove it to 
    // another contract using reconstructTransactionProof. This cyclic buffer mechanism
    // keeps the contract scalable due to bounding the storage used.

    uint256 public constant CYCLIC_BUFFER_SIZE = 2048; // Total number of buffer slots == 256*2048

    // The accumulation of attestations in response to an attestation request is given at minimum
    // 3 minutes before the vote count on attestations can be checked using the proveTransaction
    // function. Vote counting happens at the golang level in state_connector.go, and definition
    // of the valid voting set is locally-defined on every Flare node. This means that every
    // Flare validator can have a different definition of the voting set.

    uint256 public constant ATTESTATION_WINDOW = 3 minutes;

    // Cyclic index for attestation requests, (0 <= attestationRequestIndex < 256*CYCLIC_BUFFER_SIZE)
    uint256 public attestationRequestIndex;
    // Requested underlying chain transactions for attestation
    AttestationRequest[256*CYCLIC_BUFFER_SIZE] public attestationRequests;
    // Transaction attestations submitted from any account
    mapping(address => uint256[CYCLIC_BUFFER_SIZE]) public attestationSubmits;
    // Last block height checked per account, used for event retrieval
    mapping(address => uint256) public latestBlockHeightFulfilled;
    // Proven transactions, attestationRequestIndex => attestationHash
    bytes32[256*CYCLIC_BUFFER_SIZE] private provenTransactions;

//====================================================================
// Events
//====================================================================

    event AttestationRequested(
        uint256 n,
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
    ) external payable returns (
        uint256 _n
    ) {
        // Check for minimum fee burn
        require(msg.value >= 1 ether);
        // Check for empty inputs
        require(blockHeight > 0);
        require(txId > 0x0);
        require(payloadHash > 0x0);
        // Construst attestationHash used for uniquely defining this request
        bytes32 locationHash = keccak256(abi.encodePacked(
                keccak256(abi.encodePacked("FlareStateConnector_LOCATION")),
                keccak256(abi.encodePacked(chainId)),
                keccak256(abi.encodePacked(blockHeight)),
                keccak256(abi.encodePacked(txId)),
                keccak256(abi.encodePacked(utxo))
            ));
        bytes32 attestationHash = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_ATTESTATION")),
            locationHash,
            payloadHash
        ));
        // Store the request in the cyclic buffer at the current value of attestationRequestIndex
        uint256 n = attestationRequestIndex;
        attestationRequests[n] = AttestationRequest(
            block.timestamp + ATTESTATION_WINDOW,
            attestationHash
        );
        // Emit an event containing the details of the request, these details are not stored in 
        // contract storage so they must be retrieved using event retrieval.
        emit AttestationRequested(n, chainId, blockHeight, txId, utxo, payloadHash);
        // Increment the attestationRequestIndex, and roll the index back to 0 if at the end of the
        // cyclic buffer where the updated attestationRequestIndex == (256*CYCLIC_BUFFER_SIZE)
        attestationRequestIndex = (n + 1)%(256*CYCLIC_BUFFER_SIZE);

        return n;
    }

    // submitAttestations permits an account to submit 256 attestations in a single commit
    function submitAttestations(
        uint256 lowestAttestationRequestNumber,
        uint256 blockHeightFulfilled,
        uint256 booleanMap
    ) external {
        // Compute location in the cyclic buffer to store the attestations
        uint256 i = lowestAttestationRequestNumber/256;
        uint256 j = lowestAttestationRequestNumber%256;
        // Store the attestations without overwriting old attestations
        attestationSubmits[msg.sender][i] = attestationSubmits[msg.sender][i] | booleanMap >> j;
        attestationSubmits[msg.sender][(i+1)%CYCLIC_BUFFER_SIZE] = booleanMap << 256-j;
        // Update the latest block height on Flare that the sender has checked for 
        // attestation requests. This is useful for statelessly tracking AttestationRequested
        // events by always filtering from latestBlockHeightFulfilled[msg.sender] and up
        latestBlockHeightFulfilled[msg.sender] = blockHeightFulfilled;
    }

    // getAttestation is used by state_connector.go to retrieve the binary attestation vote
    // of an account in relation to an attestation request, n, in the cyclic buffer.
    function getAttestation(
        uint256 n
    ) external view returns (
        bool _attested
    ) {
        return (attestationSubmits[msg.sender][n/256] & (uint256(1) << 256-(n%256))) > 0;
    }

    function proveTransaction(
        uint256 n,
        bytes32 attestationHash
    ) external returns (
        uint256 _n
    ) {
        // Copy the attestation request to memory
        AttestationRequest memory attestationRequest = attestationRequests[n];
        // Require that the attestation request exists and that the proveTransaction tx
        // is not being submitted below the ATTESTATION_WINDOW time.
        require(attestationRequest.attestationWindowEndTime > 0);
        require(block.timestamp >= attestationRequest.attestationWindowEndTime);
        // Verify that the inputted attestationHash matches the request's attestationHash
        require(attestationRequest.attestationHash == attestationHash);
        // If the golang-level attestation voting check passes, block.coinbase will be
        // set to msg.sender, signalling to this function that the attestation request
        // should be deemed proven and included in provenTransactions
        if (block.coinbase == msg.sender && block.coinbase != GENESIS_COINBASE) {
            provenTransactions[n] = attestationHash;
        }
        return n;
    }

    function reconstructTransactionProof(
        uint64 chainId,
        uint64 blockHeight,
        bytes32 txId,
        uint16 utxo,
        bytes32 destinationHash,
        bytes32 dataHash,
        uint256 amount,
        uint256 gasUsed,
        uint256 errorCode,
        uint256 n
    ) external view returns (
        bool _proven
    ) {
        // Reconstruct the locationHash of the transaction
        bytes32 locationHash = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_LOCATION")),
            keccak256(abi.encodePacked(chainId)),
            keccak256(abi.encodePacked(blockHeight)),
            keccak256(abi.encodePacked(txId)),
            keccak256(abi.encodePacked(utxo))
        ));
        // Reconstruct the payloadHash of the transaction. The field 'dataHash' can
        // itself be reconstructed further as a catch-all field that varies in meaning
        // for different chains. For example, on Ethereum this could mean explicitly its
        // 'data' field, however on another chain this could reference a custom currency
        // code or a file storage reference.
        bytes32 payloadHash = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_PAYLOAD")),
            destinationHash,
            dataHash,
            keccak256(abi.encodePacked(amount)),
            keccak256(abi.encodePacked(gasUsed)),
            keccak256(abi.encodePacked(errorCode))
        ));
        // Reconstruct the attestationHash which uniquely identifies this underlying chain 
        // transaction.
        bytes32 attestationHash = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_ATTESTATION")),
            locationHash,
            payloadHash
        ));
        // Return a boolean defining if this reconstructed transaction proof has been proven
        // by the state connector contract.
        return (provenTransactions[n] == attestationHash);
    }

}