# Flare

Flare is a next-generation blockchain which enables smart contracts with multiple non-Turing complete assets that settle on their native chain.

## Features

- Federated Byzantine Agreement based Avalanche consensus. Control over the Flare network is proportionally given to the miners that contribute the most to the safety of underlying blockchains on Flare, weighted by market cap.
- State-connector system to observe the state of underlying chains. State-connector proofs can be submitted by anyone, and all nodes independently compare this proof to their own view of an underlying chain before permitting the proof to be finalised onto Flare.

## Documentation & FAQ's

Information about how Flare works at the network-level is available at https://docs.flare.network/en/.

Join the Flare community on [Discord](https://discord.gg/XqNa7Rq) for FAQ's and if you have any other questions or feedback.

## Dependencies

- Hardware per Flare node: AMD64 processor, 2 GHz or faster CPU, 6 GB RAM, 200 GB hard disk.
- OS: Ubuntu >= 20.04.
- Flare validator software: [Go](https://golang.org/doc/install) version 1.15.14
    - Ensure that you set up [`$GOPATH`](https://github.com/golang/go/wiki/SettingGOPATH).
- State-connector software: [NodeJS](https://nodejs.org/en/download/package-manager/) version 10.24.0.
- NodeJS dependency management: [Yarn](https://classic.yarnpkg.com/en/docs/install) version 1.22.10.
- gcc, g++, cURL and jq: `sudo apt update && sudo apt -y install gcc g++ curl jq`

Clone Flare:
```
git clone https://gitlab.com/flarenetwork/flare
cd flare
```

## Deploy a Local Network

Run the following command to configure the node to use the `local` genesis file:

```
./compile.sh local
```

Configure and launch a 5-node network:

```
./cmd/local.sh
```

To restart a previously stopped network without resetting it, use the launch command above with the `--existing` flag.

One can change the underlying-chain API endpoints they use for the state-connector system by editing the contents of the file at: `conf/local/chain_apis.json`. This file can differ across all validators on a Flare Network, because these values represent the private choices that a validator has made concerning which API endpoints they wish to rely on for safety in verifying proofs of the state of an underlying-chain.

## Deploy a Songbird Canary-Network Node

Run the compile command with the `songbird` flag:

```
./compile.sh songbird
```

Launch a songbird node using the following command:

```
./cmd/songbird.sh
```

It may take some time for your node to bootstrap to the network, you can follow its progress at: http://127.0.0.1:9650/ext/health or by inspecting the logs in the `logs/` folder.

## License: MIT

Copyright 2021 Flare Foundation

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
