// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

package core

import (
	"encoding/hex"
	"math/big"
	"os"
	"strings"

	"github.com/ava-labs/coreth/core/vm"
	"github.com/ethereum/go-ethereum/common"
)

var (
	flareChainID    = new(big.Int).SetUint64(14) // https://github.com/ethereum-lists/chains/blob/master/_data/chains/eip155-14.json
	songbirdChainID = new(big.Int).SetUint64(19) // https://github.com/ethereum-lists/chains/blob/master/_data/chains/eip155-19.json

	flareStateConnectorActivationTime    = new(big.Int).SetUint64(1000000000000)
	songbirdStateConnectorActivationTime = new(big.Int).SetUint64(1000000000000)
)

type AttestationVotes struct {
	reachedMajority    bool
	majorityDecision   string
	majorityAttestors  []common.Address
	divergentAttestors []common.Address
	abstainedAttestors []common.Address
}

func GetStateConnectorActivated(chainID *big.Int, blockTime *big.Int) bool {
	if chainID.Cmp(flareChainID) != 0 && chainID.Cmp(songbirdChainID) != 0 {
		return true
	} else if chainID.Cmp(flareChainID) == 0 {
		return blockTime.Cmp(flareStateConnectorActivationTime) >= 0
	} else if chainID.Cmp(songbirdChainID) == 0 {
		return blockTime.Cmp(songbirdStateConnectorActivationTime) >= 0
	}
	return false
}

func GetStateConnectorContract(chainID *big.Int, blockTime *big.Int) common.Address {
	switch {
	default:
		return common.HexToAddress("0x1000000000000000000000000000000000000001")
	}
}

func GetStateConnectorCoinbaseSignalAddr(chainID *big.Int, blockTime *big.Int) common.Address {
	switch {
	default:
		return common.HexToAddress("0x000000000000000000000000000000000000dEaD")
	}
}

func CheckAttestationRequestFee(chainID *big.Int, blockTime *big.Int, fee *big.Int) bool {
	switch {
	default:
		return fee.Cmp(big.NewInt(1*10^18)) >= 0
	}
}

func RequestAttestationsSelector(chainID *big.Int, blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x7c, 0x39, 0x31, 0xc6}
	}
}

func SubmitAttestationSelector(chainID *big.Int, blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0xcf, 0xd1, 0xfd, 0xad}
	}
}

func GetAttestationSelector(chainID *big.Int, blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x29, 0xbe, 0x4d, 0xb2}
	}
}

func FinaliseRoundSelector(chainID *big.Int, blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0xea, 0xeb, 0xf6, 0xd3}
	}
}

func GetVoterWhitelisterSelector(chainID *big.Int, blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x71, 0xe1, 0xfa, 0xd9}
	}
}

func GetFtsoWhitelistedPriceProvidersSelector(chainID *big.Int, blockTime *big.Int) []byte {
	switch {
	default:
		return []byte{0x09, 0xfc, 0xb4, 0x00}
	}
}

// The default attestors are the FTSO price providers
func (st *StateTransition) GetDefaultAttestors(chainID *big.Int, timestamp *big.Int) ([]common.Address, error) {
	// Get VoterWhitelister contract
	voterWhitelisterContractBytes, _, err := st.evm.Call(
		vm.AccountRef(st.msg.From()),
		common.HexToAddress(GetPrioritisedFTSOContract(st.evm.Context.BlockNumber)),
		GetVoterWhitelisterSelector(chainID, timestamp),
		GetFlareDaemonGasMultiplier(st.evm.Context.BlockNumber)*st.evm.Context.GasLimit,
		big.NewInt(0))
	if err != nil {
		return []common.Address{}, err
	}
	// Get FTSO prive providers
	voterWhitelisterContract := common.BytesToAddress(voterWhitelisterContractBytes)
	priceProvidersBytes, _, err := st.evm.Call(
		vm.AccountRef(st.msg.From()),
		voterWhitelisterContract,
		GetFtsoWhitelistedPriceProvidersSelector(chainID, timestamp),
		GetFlareDaemonMultiplier(st.evm.Context.BlockNumber)*st.evm.Context.GasLimit,
		big.NewInt(0))
	if err != nil {
		return []common.Address{}, err
	}
	NUM_ATTESTORS := len(priceProvidersBytes) / 32
	var attestors []common.Address
	for i := 0; i < NUM_ATTESTORS; i++ {
		attestors = append(attestors, common.BytesToAddress(priceProvidersBytes[i*32:(i+1)*32]))
	}
	return attestors, nil
}

func GetLocalAttestors() []common.Address {
	localAttestationAttestorsString := os.Getenv("LOCAL_ATTESTATION_PROVIDERS")
	if localAttestationAttestorsString == "" {
		return []common.Address{}
	}
	localAttestationProviders := strings.Split(localAttestationAttestorsString, ",")
	NUM_ATTESTORS := len(localAttestationProviders)
	var attestors []common.Address
	for i := 0; i < NUM_ATTESTORS; i++ {
		attestors = append(attestors, common.HexToAddress(localAttestationProviders[i]))
	}
	return attestors
}

func (st *StateTransition) GetAttestation(attestor common.Address, instructions []byte) (string, error) {
	merkleRootHash, _, err := st.evm.Call(vm.AccountRef(attestor), st.to(), instructions, 20000, big.NewInt(0))
	return hex.EncodeToString(merkleRootHash), err
}

func (st *StateTransition) CountAttestations(attestors []common.Address, instructions []byte) (AttestationVotes, error) {
	var attestationVotes AttestationVotes
	hashFrequencies := make(map[string][]common.Address)
	for i, a := range attestors {
		h, err := st.GetAttestation(a, instructions)
		if err != nil {
			attestationVotes.abstainedAttestors = append(attestationVotes.abstainedAttestors, a)
		}
		hashFrequencies[h] = append(hashFrequencies[h], attestors[i])
	}
	// Find the plurality
	var pluralityNum int
	var pluralityKey string
	for key, val := range hashFrequencies {
		if len(val) > pluralityNum {
			pluralityNum = len(val)
			pluralityKey = key
		}
	}
	if pluralityNum > len(attestors)/2 {
		attestationVotes.reachedMajority = true
		attestationVotes.majorityDecision = pluralityKey
		attestationVotes.majorityAttestors = hashFrequencies[pluralityKey]
	}
	for key, val := range hashFrequencies {
		if key != pluralityKey {
			attestationVotes.divergentAttestors = append(attestationVotes.divergentAttestors, val...)
		}
	}
	return attestationVotes, nil
}

func (st *StateTransition) FinalisePreviousRound(chainID *big.Int, timestamp *big.Int, currentRoundNumber []byte) (AttestationVotes, error) {
	instructions := append(GetAttestationSelector(chainID, timestamp), currentRoundNumber...)
	defaultAttestors, err := st.GetDefaultAttestors(chainID, timestamp)
	if err != nil {
		return AttestationVotes{}, err
	}
	defaultAttestationVotes, err := st.CountAttestations(defaultAttestors, instructions)
	if err != nil {
		return AttestationVotes{}, err
	}
	localAttestors := GetLocalAttestors()
	var finalityReached bool
	if len(localAttestors) > 0 {
		localAttestationVotes, err := st.CountAttestations(localAttestors, instructions)
		if defaultAttestationVotes.reachedMajority && localAttestationVotes.reachedMajority && defaultAttestationVotes.majorityDecision == localAttestationVotes.majorityDecision {
			finalityReached = true
		} else if err != nil || (defaultAttestationVotes.reachedMajority && defaultAttestationVotes.majorityDecision != localAttestationVotes.majorityDecision) {
			// Make a back-up of the current state database, because this node is about to fork from the default set
		}
	} else if defaultAttestationVotes.reachedMajority {
		finalityReached = true
	}
	if finalityReached {
		// Finalise defaultAttestationVotes.majorityDecision
		merkleRootHashBytes, err := hex.DecodeString(defaultAttestationVotes.majorityDecision)
		if err != nil {
			return AttestationVotes{}, err
		}
		finalisedData := append(append(FinaliseRoundSelector(chainID, timestamp), currentRoundNumber...), merkleRootHashBytes...)
		coinbaseSignal := GetStateConnectorCoinbaseSignalAddr(chainID, timestamp)
		originalCoinbase := st.evm.Context.Coinbase
		defer func() {
			st.evm.Context.Coinbase = originalCoinbase
		}()
		st.evm.Context.Coinbase = coinbaseSignal
		_, _, err = st.evm.Call(vm.AccountRef(coinbaseSignal), st.to(), finalisedData, st.gas, st.value)
		return defaultAttestationVotes, err
	}
	return AttestationVotes{}, nil
}
