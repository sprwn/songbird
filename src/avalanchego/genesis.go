// (c) 2021, Flare Networks Limited. All rights reserved.
//
// This file is a derived work, based on the avalanchego library whose original
// notice appears below. It is distributed under a license compatible with the
// licensing terms of the original code from which it is derived.
// Please see the file LICENSE_AVALABS for licensing terms of the original work.
// Please see the file LICENSE for licensing terms.
//
// (c) 2019-2020, Ava Labs, Inc. All rights reserved.

package genesis

import (
	"bytes"
	"errors"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/ava-labs/avalanchego/codec"
	"github.com/ava-labs/avalanchego/codec/linearcodec"
	"github.com/ava-labs/avalanchego/codec/reflectcodec"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/utils/constants"
	"github.com/ava-labs/avalanchego/utils/formatting"
	"github.com/ava-labs/avalanchego/utils/json"
	"github.com/ava-labs/avalanchego/utils/wrappers"
	"github.com/ava-labs/avalanchego/vms/avm"
	"github.com/ava-labs/avalanchego/vms/evm"
	"github.com/ava-labs/avalanchego/vms/nftfx"
	"github.com/ava-labs/avalanchego/vms/platformvm"
	"github.com/ava-labs/avalanchego/vms/propertyfx"
	"github.com/ava-labs/avalanchego/vms/secp256k1fx"
)

const (
	defaultEncoding    = formatting.Hex
	codecVersion       = 0
	configChainIDAlias = "X"
)

// validateConfig returns an error if the provided
// *Config is not considered valid.
func validateConfig(networkID uint32, config *Config) error {
	if networkID != config.NetworkID {
		return fmt.Errorf(
			"networkID %d specified but genesis config contains networkID %d",
			networkID,
			config.NetworkID,
		)
	}

	startTime := time.Unix(int64(config.StartTime), 0)
	if time.Since(startTime) < 0 {
		return fmt.Errorf(
			"start time cannot be in the future: %s",
			startTime,
		)
	}

	offsetTimeRequired := config.InitialStakeDurationOffset * uint64(len(config.InitialStakers)-1)
	if offsetTimeRequired > config.InitialStakeDuration {
		return fmt.Errorf(
			"initial stake duration is %d but need at least %d with offset of %d",
			config.InitialStakeDuration,
			offsetTimeRequired,
			config.InitialStakeDurationOffset,
		)
	}

	if len(config.CChainGenesis) == 0 {
		return errors.New("C-Chain genesis cannot be empty")
	}

	return nil
}

// Genesis returns the genesis data of the Platform Chain.
//
// Since an Avalanche network has exactly one Platform Chain, and the Platform
// Chain defines the genesis state of the network (who is staking, which chains
// exist, etc.), defining the genesis state of the Platform Chain is the same as
// defining the genesis state of the network.
//
// Genesis accepts:
// 1) The ID of the new network. [networkID]
// 2) The location of a custom genesis config to load. [filepath]
//
// If [filepath] is empty or the given network ID is Mainnet, Testnet, or Local, loads the
// network genesis state from predefined configs. If [filepath] is non-empty and networkID
// isn't Mainnet, Testnet, or Local, loads the network genesis data from the config at [filepath].
//
// Genesis returns:
// 1) The byte representation of the genesis state of the platform chain
//    (ie the genesis state of the network)
// 2) The asset ID of AVAX
func Genesis(networkID uint32, filepath string) ([]byte, ids.ID, error) {
	config := GetConfig(networkID)
	if len(filepath) > 0 {
		switch networkID {
		case constants.MainnetID, constants.TestnetID, constants.LocalID:
			return nil, ids.ID{}, fmt.Errorf(
				"cannot override genesis config for standard network %s (%d)",
				constants.NetworkName(networkID),
				networkID,
			)
		}

		customConfig, err := GetConfigFile(filepath)
		if err != nil {
			return nil, ids.ID{}, fmt.Errorf("unable to load provided genesis config at %s: %w", filepath, err)
		}

		config = customConfig
	}

	if err := validateConfig(networkID, config); err != nil {
		return nil, ids.ID{}, fmt.Errorf("genesis config validation failed: %w", err)
	}

	return FromConfig(config)
}

// FromConfig returns:
// 1) The byte representation of the genesis state of the platform chain
//    (ie the genesis state of the network)
// 2) The asset ID of AVAX
func FromConfig(config *Config) ([]byte, ids.ID, error) {

	// Specify the genesis state of the AVM
	avmArgs := avm.BuildGenesisArgs{
		NetworkID: json.Uint32(config.NetworkID),
		Encoding:  defaultEncoding,
	}
	{
		avax := avm.AssetDefinition{
			Name:         "Avalanche",
			Symbol:       "AVAX",
			Denomination: 9,
			InitialState: map[string][]interface{}{},
		}
		memoBytes := []byte{}

		var err error
		avax.Memo, err = formatting.EncodeWithChecksum(defaultEncoding, memoBytes)
		if err != nil {
			return nil, ids.Empty, fmt.Errorf("couldn't parse memo bytes to string: %w", err)
		}
		avmArgs.GenesisData = map[string]avm.AssetDefinition{
			"AVAX": avax, // The AVM starts out with one asset: AVAX
		}
	}
	avmReply := avm.BuildGenesisReply{}

	avmSS := avm.CreateStaticService()
	err := avmSS.BuildGenesis(nil, &avmArgs, &avmReply)
	if err != nil {
		return nil, ids.ID{}, err
	}

	bytes, err := formatting.Decode(defaultEncoding, avmReply.Bytes)
	if err != nil {
		return nil, ids.ID{}, fmt.Errorf("couldn't parse avm genesis reply: %w", err)
	}
	avaxAssetID, err := AVAXAssetID(bytes)
	if err != nil {
		return nil, ids.ID{}, fmt.Errorf("couldn't generate AVAX asset ID: %w", err)
	}

	// Specify the initial state of the Platform Chain
	platformvmArgs := platformvm.BuildGenesisArgs{
		AvaxAssetID:   avaxAssetID,
		NetworkID:     json.Uint32(config.NetworkID),
		Time:          json.Uint64(config.StartTime),
		InitialSupply: json.Uint64(1),
		Message:       config.Message,
		Encoding:      defaultEncoding,
	}

	// Specify the chains that exist upon this network's creation
	genesisStr, err := formatting.EncodeWithChecksum(defaultEncoding, []byte(config.CChainGenesis))
	if err != nil {
		return nil, ids.Empty, fmt.Errorf("couldn't encode message: %w", err)
	}
	platformvmArgs.Chains = []platformvm.APIChain{
		{
			GenesisData: avmReply.Bytes,
			SubnetID:    constants.PrimaryNetworkID,
			VMID:        avm.ID,
			FxIDs: []ids.ID{
				secp256k1fx.ID,
				nftfx.ID,
				propertyfx.ID,
			},
			Name: "X-Chain",
		},
		{
			GenesisData: genesisStr,
			SubnetID:    constants.PrimaryNetworkID,
			VMID:        evm.ID,
			Name:        "C-Chain",
		},
	}

	platformvmReply := platformvm.BuildGenesisReply{}
	platformvmSS := platformvm.StaticService{}
	if err := platformvmSS.BuildGenesis(nil, &platformvmArgs, &platformvmReply); err != nil {
		return nil, ids.ID{}, fmt.Errorf("problem while building platform chain's genesis state: %w", err)
	}

	genesisBytes, err := formatting.Decode(platformvmReply.Encoding, platformvmReply.Bytes)
	if err != nil {
		return nil, ids.ID{}, fmt.Errorf("problem parsing platformvm genesis bytes: %w", err)
	}

	return genesisBytes, avaxAssetID, nil
}

func VMGenesis(genesisBytes []byte, vmID ids.ID) (*platformvm.Tx, error) {
	genesis := platformvm.Genesis{}
	if _, err := platformvm.GenesisCodec.Unmarshal(genesisBytes, &genesis); err != nil {
		return nil, fmt.Errorf("couldn't unmarshal genesis bytes due to: %w", err)
	}
	if err := genesis.Initialize(); err != nil {
		return nil, err
	}
	for _, chain := range genesis.Chains {
		uChain := chain.UnsignedTx.(*platformvm.UnsignedCreateChainTx)
		if uChain.VMID == vmID {
			return chain, nil
		}
	}
	return nil, fmt.Errorf("couldn't find blockchain with VM ID %s", vmID)
}

func AVAXAssetID(avmGenesisBytes []byte) (ids.ID, error) {
	c := linearcodec.New(reflectcodec.DefaultTagName, 1<<20)
	m := codec.NewManager(math.MaxUint32)
	errs := wrappers.Errs{}
	errs.Add(
		c.RegisterType(&avm.BaseTx{}),
		c.RegisterType(&avm.CreateAssetTx{}),
		c.RegisterType(&avm.OperationTx{}),
		c.RegisterType(&avm.ImportTx{}),
		c.RegisterType(&avm.ExportTx{}),
		c.RegisterType(&secp256k1fx.TransferInput{}),
		c.RegisterType(&secp256k1fx.MintOutput{}),
		c.RegisterType(&secp256k1fx.TransferOutput{}),
		c.RegisterType(&secp256k1fx.MintOperation{}),
		c.RegisterType(&secp256k1fx.Credential{}),
		m.RegisterCodec(codecVersion, c),
	)
	if errs.Errored() {
		return ids.ID{}, errs.Err
	}

	genesis := avm.Genesis{}
	if _, err := m.Unmarshal(avmGenesisBytes, &genesis); err != nil {
		return ids.ID{}, err
	}

	if len(genesis.Txs) == 0 {
		return ids.ID{}, errors.New("genesis creates no transactions")
	}
	genesisTx := genesis.Txs[0]

	tx := avm.Tx{UnsignedTx: &genesisTx.CreateAssetTx}
	unsignedBytes, err := m.Marshal(codecVersion, tx.UnsignedTx)
	if err != nil {
		return ids.ID{}, err
	}
	signedBytes, err := m.Marshal(codecVersion, &tx)
	if err != nil {
		return ids.ID{}, err
	}
	tx.Initialize(unsignedBytes, signedBytes)

	return tx.ID(), nil
}

type innerSortXAllocation []Allocation

func (xa innerSortXAllocation) Less(i, j int) bool {
	return xa[i].InitialAmount < xa[j].InitialAmount ||
		(xa[i].InitialAmount == xa[j].InitialAmount &&
			bytes.Compare(xa[i].AVAXAddr.Bytes(), xa[j].AVAXAddr.Bytes()) == -1)
}

func (xa innerSortXAllocation) Len() int      { return len(xa) }
func (xa innerSortXAllocation) Swap(i, j int) { xa[j], xa[i] = xa[i], xa[j] }

func sortXAllocation(a []Allocation) { sort.Sort(innerSortXAllocation(a)) }
