// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

package genesis

var (
	testnetCChainGenesis = `{
		"config": {
			"chainId": 19,
			"homesteadBlock": 0,
			"daoForkBlock": 0,
			"daoForkSupport": true,
			"eip150Block": 0,
			"eip150Hash": "0x2086799aeebeae135c246c65021c82b4e15a2c451340993aacfd2751886514f0",
			"eip155Block": 0,
			"eip158Block": 0,
			"byzantiumBlock": 0,
			"constantinopleBlock": 0,
			"petersburgBlock": 0,
			"istanbulBlock": 0,
			"muirGlacierBlock": 0,
			"apricotPhase1BlockTimestamp": 0,
			"apricotPhase2BlockTimestamp": 0
		},
		"nonce": "0x0",
		"timestamp": "0x0",
		"extraData": "0x00",
		"gasLimit": "0x5f5e100",
		"difficulty": "0x0",
		"mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
		"coinbase": "0x0100000000000000000000000000000000000000",
		"alloc": {
<DATA>			
		},
		"number": "0x0",
		"gasUsed": "0x0",
		"parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
	}`
)
