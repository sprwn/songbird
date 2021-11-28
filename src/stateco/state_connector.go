// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

package core

import (
	"encoding/binary"
	"math"
	"math/big"
	"os"
	"strings"

	"github.com/ava-labs/coreth/core/vm"
	"github.com/ethereum/go-ethereum/common"
)

var (
	testingChainID               = new(big.Int).SetUint64(16)
	stateConnectorActivationTime = new(big.Int).SetUint64(1636070400)
)

func GetStateConnectorActivated(chainID *big.Int, blockTime *big.Int) bool {
	// Return true if chainID is 16 or if block.timestamp is greater than the state connector activation time on any chain
	return chainID.Cmp(testingChainID) == 0
}

func GetStateConnectorGasDivisor(blockTime *big.Int) uint64 {
	switch {
	default:
		return 6
	}
}

func GetStateConnectorContractAddr(blockTime *big.Int) string {
	switch {
	default:
		return "0x1000000000000000000000000000000000000001"
	}
}

func ProveTransactionSelector(blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0xb7, 0x2f, 0x8e, 0x15}
	}
}

func GetAttestationSelector(blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x29, 0xbe, 0x4d, 0xb2}
	}
}

// If you know you're about to fork from the default set, first create a backup of the db/ folder before having a different
// state transition. This permits an easy way to repair your node if you incorrectly forked.

func (st *StateTransition) CountVotes(attestors []string, instructions []byte) bool {
	N := uint32(len(attestors))
	if N == 0 {
		return false
	}
	K := uint64(math.Ceil(float64((2*N + 1) / 3)))
	var attestations uint64
	for _, attestationProvider := range attestors {
		if attestationProvider == "" {
			continue
		}
		isAttested, _, checkAttestationErr := st.evm.Call(vm.AccountRef(common.HexToAddress(attestationProvider)), st.to(), instructions, 20000, st.value)
		if checkAttestationErr != nil {
			continue
		}
		if binary.BigEndian.Uint64(isAttested[0:32]) == 1 {
			attestations += 1
		}
	}
	if attestations >= K {
		return true
	}
	return false
}

func (st *StateTransition) VerifyAttestations(checkRet []byte, checkVmerr error) bool {
	if checkVmerr != nil {
		return false
	}
	chainConfig := st.evm.ChainConfig()
	if !GetStateConnectorActivated(chainConfig.ChainID, st.evm.Context.Time) {
		return false
	}
	instructions := append(GetAttestationSelector(st.evm.Context.Time), checkRet...)

	// Locally-defined attestation providers (can be a unique set on every Flare node)
	localAttestationProvidersString := os.Getenv("LOCAL_ATTESTATION_PROVIDERS")
	var localResult bool
	if localAttestationProvidersString == "" {
		localResult = true
	} else {
		localAttestationProviders := strings.Split(localAttestationProvidersString, ",")
		localResult = st.CountVotes(localAttestationProviders, instructions)
	}

	// Default attestation providers (must be uniform on every Flare node)
	defaultAttestationProvidersString := "GET CURRENT FTSO PROVIDER ADDRESSES HERE"
	defaultAttestationProviders := strings.Split(defaultAttestationProvidersString, ",")
	defaultResult := st.CountVotes(defaultAttestationProviders, instructions)

	if defaultResult && localResult {
		// Reward all FTSO providers used in the current default set that are consistent
		// with the voting result. Rewards should be based on participation rate and not
		// on total number of transactions correctly attested, in order to avoid
		// incentivising disused transaction proofs from underlying chains.
		return true
	} else if defaultResult && !localResult {
		// Save a snapshot of the current db/ folder, as returning false in the next step
		// will create a new forked-branch on the Flare network state
	}
	return false
}
