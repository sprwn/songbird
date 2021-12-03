// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

contract StateConnector {

//====================================================================
// Data Structures
//====================================================================

    uint256 public constant BUFFER_TIMESTAMP_OFFSET = 1636070400 seconds; // November 5th, 2021
    uint256 public constant BUFFER_WINDOW = 90 seconds; // Amount of time a buffer is active before cycling to the next one
    uint256 public constant TOTAL_STORED_BUFFERS = 3; // {Requests, Votes, Reveals}

    // Struct for Vote in round 'R'
    struct Vote {
        bytes32 maskedMerkleHash; // Masked hash of the merkle tree that contains valid requests from round 'R-1' 
        bytes32 committedRandom; // Hash of random value that masks 'maskedMerkleHash' above
        bytes32 revealedRandom; // Reveal of 'committedRandom' from round 'R-1' Votes struct, used in 'R-2' request voting
    }

    struct Buffers {
        Vote[TOTAL_STORED_BUFFERS] votes; // {Requests, Votes, Reveals}
        uint256 latestVoteBlockNumber;  // The block.number of the last time each address voted
    }

    mapping(address => Buffers) public buffers;
    uint256 public totalBuffers; // The total number of buffers that have been used by new attestation requests. 
                                 // totalBuffers == (block.timestamp / BUFFER_WINDOW)
    uint256[TOTAL_STORED_BUFFERS] public earliestBufferBlockNumber; // For the last NUM_VOTING_PHASES buffers, this value defines
                                                                 // the block.number that each buffer was first used by a
                                                                 // new attestation request. This value is used for event filtering
                                                                 // by defining block.number windows for filtering attestation
                                                                 // request events.

//====================================================================
// Events
//====================================================================

    // instructions: (uint64 chainId, uint64 blockHeight, uint16 utxo, bool full)
    // The variable 'full' defines whether to provide the complete transaction details
    // in the attestation response
    event AttestationRequest(
        uint256 timestamp,
        uint256 bufferNumber,
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
        require(msg.value >= 1 ether);
        // Check for empty inputs
        require(instructions > 0);
        require(txId > 0x0);

        uint256 updatedBufferNumber = ((block.timestamp - BUFFER_TIMESTAMP_OFFSET) / BUFFER_WINDOW);
        if (updatedBufferNumber > totalBuffers) {
            earliestBufferBlockNumber[updatedBufferNumber % TOTAL_STORED_BUFFERS] = block.number;
            totalBuffers = updatedBufferNumber;
        }

        // Emit an event containing the details of the request, these details are not stored in 
        // contract storage so they must be retrieved using event filtering.
        emit AttestationRequest(block.timestamp, totalBuffers, instructions, txId); 
    }

    function submitAttestation(
        uint256 bufferNumber,
        bytes32 maskedMerkleHash,
        bytes32 committedRandom,
        bytes32 revealedRandom
    ) external {
        require(bufferNumber == (block.timestamp - BUFFER_TIMESTAMP_OFFSET) / BUFFER_WINDOW);
        buffers[msg.sender].latestVoteBlockNumber = block.number;
        buffers[msg.sender].votes[bufferNumber % TOTAL_STORED_BUFFERS] = Vote(
            maskedMerkleHash,
            committedRandom,
            revealedRandom
        );
    }

}