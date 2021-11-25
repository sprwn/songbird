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
		return 3
	}
}

func GetStateConnectorContractAddr(blockTime *big.Int) string {
	switch {
	default:
		return "0x1000000000000000000000000000000000000001"
	}
}

func RequestAttestationsSelector(blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x06, 0x95, 0xef, 0x28}
	}
}

func ProveTransactionSelector(blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0xf6, 0x03, 0x58, 0x6a}
	}
}

func GetAttestationSelector(blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x29, 0xbe, 0x4d, 0xb2}
	}
}

func (st *StateTransition) VerifyAttestations(checkRet []byte, checkVmerr error) bool {
	if checkVmerr != nil {
		return false
	}
	chainConfig := st.evm.ChainConfig()
	if GetStateConnectorActivated(chainConfig.ChainID, st.evm.Context.Time) {
		attestationProvidersString := os.Getenv("LOCAL_ATTESTATION_PROVIDERS")
		attestationProviders := strings.Split(attestationProvidersString, ",")
		N := uint32(len(attestationProviders))
		if N > 0 {
			attestationInstructions := append(GetAttestationSelector(st.evm.Context.Time), checkRet...)
			K := uint64(math.Ceil(float64((2*N + 1) / 3)))
			var attestations uint64
			for _, attestationProvider := range attestationProviders {
				if attestationProvider == "" {
					continue
				}
				isAttested, _, checkAttestationErr := st.evm.Call(vm.AccountRef(common.HexToAddress(attestationProvider)), st.to(), attestationInstructions, 20000, st.value)
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
		}
	}
	return false
}
