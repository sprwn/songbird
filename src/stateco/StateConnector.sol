// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

contract StateConnector {

//====================================================================
// Data Structures
//====================================================================

    address public constant GENESIS_COINBASE = address(0x0100000000000000000000000000000000000000); // Default block.coinbase value
    address public constant SIGNAL_COINBASE = address(0x0200000000000000000000000000000000000000); //  Signalling block.coinbase value
    uint256 public constant BUFFER_TIMESTAMP_OFFSET = 1636070400 seconds; // November 5th, 2021
    uint256 public constant BUFFER_WINDOW = 90 seconds; // Amount of time a buffer is active before cycling to the next one
    uint256 public constant TOTAL_STORED_BUFFERS = 3; // {Requests, Votes, Reveals}
    uint256 public constant TOTAL_STORED_PROOFS = (1 weeks)/BUFFER_WINDOW; // Store a proof for one week
    uint256 public constant ATTESTATION_REQUEST_FEE = 1 ether; // This fee must be burned to issue an attestation request

    //=======================
    // VOTING DATA STRUCTURES
    //=======================

    struct Vote { // Struct for Vote in round 'R'
        bytes32 maskedMerkleHash; // Masked hash of the merkle tree that contains valid requests from round 'R-1' 
        bytes32 committedRandom; // Hash of random value that masks 'maskedMerkleHash' above
        bytes32 revealedRandom; // Reveal of 'committedRandom' from round 'R-1' Votes struct, used in 'R-2' request voting
    }
    struct Buffers {
        Vote[TOTAL_STORED_BUFFERS] votes; // {Requests, Votes, Reveals}
        uint256 latestVote;  // The latest buffer number that this account has voted on, used for determining relevant votes
    }
    mapping(address => Buffers) public buffers;

    //=============================
    // MERKLE PROOF DATA STRUCTURES
    //=============================

    uint256 public totalBuffers; // The total number of buffers that have elapsed over time such that the latest buffer
                                 // has been proven using finaliseRound()
    bytes32[TOTAL_STORED_PROOFS] public merkleRoots; // The proven merkle roots for each buffer number,
                                                     // accessed using: bufferNumber % TOTAL_STORED_PROOFS
                                                     // within one week of proving the merkle root.

//====================================================================
// Events
//====================================================================

    // instructions: (uint64 chainId, uint64 blockHeight, uint16 utxo, bool full)
    // The variable 'full' defines whether to provide the complete transaction details
    // in the attestation response
    event AttestationRequest(
        uint256 timestamp,
        uint256 instructions,
        bytes32 txId
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
        uint256 instructions,
        bytes32 txId
    ) external payable {
        // Check for minimum fee burn
        require(msg.value >= ATTESTATION_REQUEST_FEE);
        // Check for empty inputs
        require(instructions > 0);
        require(txId > 0x0);
        // Emit an event containing the details of the request, these details are not stored in 
        // contract storage so they must be retrieved using event filtering.
        emit AttestationRequest(block.timestamp, instructions, txId); 
    }

    function submitAttestation(
        uint256 bufferNumber,
        bytes32 maskedMerkleHash,
        bytes32 committedRandom,
        bytes32 revealedRandom
    ) external returns (
        bool _initialBufferSlot
    ) {
        require(bufferNumber == (block.timestamp - BUFFER_TIMESTAMP_OFFSET) / BUFFER_WINDOW);
        buffers[msg.sender].latestVote = bufferNumber;
        buffers[msg.sender].votes[bufferNumber % TOTAL_STORED_BUFFERS] = Vote(
            maskedMerkleHash,
            committedRandom,
            revealedRandom
        );
        // Determine if this is the first attestation submitted in a new buffer round.
        // If so, the golang code will automatically finalise the previous round using finaliseRound()
        if (bufferNumber > totalBuffers) {
            return true;
        }
        return false;
    }

    function getAttestation(
        uint256 bufferNumber
    ) external view returns (
        bytes32 _unmaskedMerkleHash
    ) {
        require(buffers[msg.sender].latestVote >= bufferNumber);
        bytes32 revealedRandom = buffers[msg.sender].votes[bufferNumber % TOTAL_STORED_BUFFERS].revealedRandom;
        bytes32 committedRandom = buffers[msg.sender].votes[(bufferNumber-1) % TOTAL_STORED_BUFFERS].committedRandom;
        require(committedRandom == keccak256(abi.encodePacked(revealedRandom)));
        bytes32 maskedMerkleHash = buffers[msg.sender].votes[(bufferNumber-1) % TOTAL_STORED_BUFFERS].maskedMerkleHash;
        return (maskedMerkleHash ^ revealedRandom);
    }

    function finaliseRound(
        uint256 bufferNumber,
        bytes32 merkleHash
    ) external {
        require(bufferNumber == (block.timestamp - BUFFER_TIMESTAMP_OFFSET) / BUFFER_WINDOW);
        require(bufferNumber > totalBuffers);
        // The following region can only be called from the golang code
        if (block.coinbase == msg.sender && block.coinbase == SIGNAL_COINBASE) {
            totalBuffers = bufferNumber;
            merkleRoots[(bufferNumber-1) % TOTAL_STORED_PROOFS] = merkleHash;
        }
    }

}