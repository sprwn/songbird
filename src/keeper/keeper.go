// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

package core

import (
	"fmt"
	"math/big"

	"github.com/ava-labs/coreth/core/vm"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/log"
)

// Define errors
type ErrInvalidFlareDaemonData struct{}

func (e *ErrInvalidFlareDaemonData) Error() string {
	return "invalid return data from flareDaemon trigger"
}

type ErrFlareDaemonDataEmpty struct{}

func (e *ErrFlareDaemonDataEmpty) Error() string { return "return data from flareDaemon trigger empty" }

type ErrMaxMintExceeded struct {
	mintMax     *big.Int
	mintRequest *big.Int
}

func (e *ErrMaxMintExceeded) Error() string {
	return fmt.Sprintf("mint request of %s exceeded max of %s", e.mintRequest.Text(10), e.mintMax.Text(10))
}

type ErrMintNegative struct{}

func (e *ErrMintNegative) Error() string { return "mint request cannot be negative" }

// Define interface for dependencies
type EVMCaller interface {
	Call(caller vm.ContractRef, addr common.Address, input []byte, gas uint64, value *big.Int) (ret []byte, leftOverGas uint64, err error)
	GetBlockNumber() *big.Int
	GetGasLimit() uint64
	AddBalance(addr common.Address, amount *big.Int)
}

// Define maximums that can change by block height
func GetFlareDaemonGasMultiplier(blockNumber *big.Int) uint64 {
	switch {
	default:
		return 100
	}
}

func GetFlareDaemonContract(blockNumber *big.Int) string {
	switch {
	default:
		return "0x1000000000000000000000000000000000000002"
	}
}

func GetFlareDaemonSelector(blockNumber *big.Int) []byte {
	switch {
	default:
		return []byte{0x7f, 0xec, 0x8d, 0x38}
	}
}

func GetPrioritisedFTSOContract(blockTime *big.Int) string {
	switch {
	default:
		return "0x1000000000000000000000000000000000000003"
	}
}

func GetMaximumMintRequest(blockNumber *big.Int) *big.Int {
	switch {
	default:
		maxRequest, _ := new(big.Int).SetString("50000000000000000000000000", 10)
		return maxRequest
	}
}

func triggerFlareDaemon(evm EVMCaller) (*big.Int, error) {
	bigZero := big.NewInt(0)
	// Get the contract to call
	flareDaemonContract := common.HexToAddress(GetFlareDaemonContract(evm.GetBlockNumber()))
	// Call the method
	triggerRet, _, triggerErr := evm.Call(
		vm.AccountRef(flareDaemonContract),
		flareDaemonContract,
		GetFlareDaemonSelector(evm.GetBlockNumber()),
		GetFlareDaemonGasMultiplier(evm.GetBlockNumber())*evm.GetGasLimit(),
		bigZero)
	// If no error and a value came back...
	if triggerErr == nil && triggerRet != nil {
		// Did we get one big int?
		if len(triggerRet) == 32 {
			// Convert to big int
			// Mint request cannot be less than 0 as SetBytes treats value as unsigned
			mintRequest := new(big.Int).SetBytes(triggerRet)
			// return the mint request
			return mintRequest, nil
		} else {
			// Returned length was not 32 bytes
			return bigZero, &ErrInvalidFlareDaemonData{}
		}
	} else {
		if triggerErr != nil {
			return bigZero, triggerErr
		} else {
			return bigZero, &ErrFlareDaemonDataEmpty{}
		}
	}
}

func mint(evm EVMCaller, mintRequest *big.Int) error {
	// If the mint request is greater than zero and less than max
	max := GetMaximumMintRequest(evm.GetBlockNumber())
	if mintRequest.Cmp(big.NewInt(0)) > 0 &&
		mintRequest.Cmp(max) <= 0 {
		// Mint the amount asked for on to the flareDaemon contract
		evm.AddBalance(common.HexToAddress(GetFlareDaemonContract(evm.GetBlockNumber())), mintRequest)
	} else if mintRequest.Cmp(max) > 0 {
		// Return error
		return &ErrMaxMintExceeded{
			mintRequest: mintRequest,
			mintMax:     max,
		}
	} else if mintRequest.Cmp(big.NewInt(0)) < 0 {
		// Cannot mint negatives
		return &ErrMintNegative{}
	}
	// No error
	return nil
}

func triggerFlareDaemonAndMint(evm EVMCaller, log log.Logger, attestationVotes AttestationVotes) {
	// If attestationVotes.reachedMajority == true, then rewards should be distributed to attestation providers
	// Call the flareDaemon
	mintRequest, triggerErr := triggerFlareDaemon(evm)
	// If no error...
	if triggerErr == nil {
		// time to mint
		if mintError := mint(evm, mintRequest); mintError != nil {
			log.Warn("Error minting inflation request", "error", mintError)
		}
	} else {
		log.Warn("FlareDaemon trigger in error", "error", triggerErr)
	}
}
