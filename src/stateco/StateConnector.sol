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

    uint256 private constant ATTESTATION_WINDOW = 3 minutes;
    address private constant GENESIS_COINBASE = address(0x0100000000000000000000000000000000000000);

    // Total number of attestations requested
    uint256 public attestationRequestNumber;
    // Requested transactions for attestation
    mapping(uint256 => AttestationRequest) public attestationRequests;
    // Transaction attestations sent per account
    mapping(address => mapping(uint256 => uint256)) attestationBooleanMap;
    // Last block height checked per account, used for event retrieval
    mapping(address => uint256) public latestBlockHeightFulfilled;
    // Last attestation request 
    mapping(address => uint256) public latestAttestationRequestFulfilled;
    // Proven transactions, locationHash => payloadHash
    mapping(bytes32 => bytes32) private provenTransactions;

//====================================================================
// Events
//====================================================================

    event AttestationRequested(
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
        // Check for minimum fee burn
        require(msg.value > 1 ether);
        // Check for empty inputs
        require(blockHeight > 0, "blockHeight == 0");
        require(txId > 0x0, "txId == 0x0");
        require(payloadHash > 0x0, "payloadHash == 0x0");

        // Check if this transaction has already been proven
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
        require(provenTransactions[attestationHash] == 0x0, "transaction already proven");

        attestationRequests[attestationRequestNumber] = AttestationRequest(
            block.timestamp + ATTESTATION_WINDOW,
            attestationHash
        );

        emit AttestationRequested(chainId, blockHeight, txId, utxo, payloadHash);
    }

    function submitAttestations(
        uint256 lowestAttestationRequestNumber,
        uint256 booleanMap
    ) external {
        uint256 i = lowestAttestationRequestNumber/256;
        uint256 j = lowestAttestationRequestNumber%256;
        attestationBooleanMap[msg.sender][i] = booleanMap >> j;
        attestationBooleanMap[msg.sender][i+1] = booleanMap << 256-j;
    }

    function getAttestation(
        uint256 n
    ) external view returns (
        bool _attested
    ) {
        return (attestationBooleanMap[msg.sender][n/256] & (uint256(1) << 256-(n%256))) > 0;
    }

    function proveTransaction(
        uint64 chainId,
        uint64 blockHeight,
        bytes32 txId,
        uint16 utxo,
        bytes32 payloadHash,
        uint256 n
    ) external returns (
        uint256 _n
    ) {
        require(n <= attestationRequestNumber, "n is too high");
        require(attestationRequests[n].attestationWindowEndTime > 0, "attestation request does not exist");
        require(block.timestamp >= attestationRequests[n].attestationWindowEndTime, "proveTransaction request too early");
        bytes32 locationHash = keccak256(abi.encodePacked(
                keccak256(abi.encodePacked("FlareStateConnector_LOCATION")),
                keccak256(abi.encodePacked(chainId)),
                keccak256(abi.encodePacked(blockHeight)),
                keccak256(abi.encodePacked(txId)),
                keccak256(abi.encodePacked(utxo))
            ));
        require(provenTransactions[locationHash] == 0x0, "transaction already proven");
        bytes32 attestationHash = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_ATTESTATION")),
            locationHash,
            payloadHash
        ));
        require(attestationRequests[n].attestationHash == attestationHash, "invalid attestation details");
        if (block.coinbase == msg.sender && block.coinbase != GENESIS_COINBASE) {
            provenTransactions[locationHash] = payloadHash;
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
        uint256 amount
    ) external view returns (
        bool _proven
    ) {
        bytes32 locationHash = keccak256(abi.encodePacked(
                keccak256(abi.encodePacked("FlareStateConnector_LOCATION")),
                keccak256(abi.encodePacked(chainId)),
                keccak256(abi.encodePacked(blockHeight)),
                keccak256(abi.encodePacked(txId)),
                keccak256(abi.encodePacked(utxo))
            ));
        require(provenTransactions[locationHash] > 0x0, "transaction not proven");
        bytes32 payloadHash = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked("FlareStateConnector_PAYLOAD")),
            destinationHash,
            dataHash,
            keccak256(abi.encodePacked(amount))
        ));
        require(provenTransactions[locationHash] == payloadHash, "invalid payloadHash");
        return (provenTransactions[locationHash] == payloadHash);
    }

}