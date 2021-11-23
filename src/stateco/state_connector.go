// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

package core

import (
	"math/big"
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

func ProveTransactionSelector(blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0xef, 0x3b, 0xa3, 0x28}
	}
}

func GetAttestationSelector(blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x48, 0x23, 0xfc, 0x52}
	}
}
