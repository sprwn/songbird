# (c) 2021, Flare Networks Limited. All rights reserved.
# Please see the file LICENSE for licensing terms.

#!/bin/bash
if [[ $(pwd) =~ " " ]]; then echo "Working directory path contains a folder with a space in its name, please remove all spaces" && exit; fi
if [ -z ${GOPATH+x} ]; then echo "GOPATH is not set, visit https://github.com/golang/go/wiki/SettingGOPATH" && exit; fi
if [[ $(go version) != *"go1.15"* ]]; then echo "Go version is not go1.15" && exit; fi
if [ "$(uname -m)" != "x86_64" ]; then echo "Machine architecture is not x86_64" && exit; fi

WORKING_DIR=$(pwd)

if [ -d $GOPATH/src/github.com/ava-labs ]; then
  echo "Removing old version..."
  chmod -R 775 $GOPATH/src/github.com/ava-labs && rm -rf $GOPATH/src/github.com/ava-labs
  chmod -R 775 $GOPATH/pkg/mod/github.com/ava-labs && rm -rf $GOPATH/pkg/mod/github.com/ava-labs
fi

echo "Downloading AvalancheGo..."
go get -v -d github.com/ava-labs/avalanchego/... &> /dev/null
cd $GOPATH/src/github.com/ava-labs/avalanchego
git config --global advice.detachedHead false
# Hard-coded commit to tag v1.5.2, at the time of this authoring
# https://github.com/ava-labs/avalanchego/releases/tag/v1.5.2
git checkout f2e51d790430a171e6d39f72911d98f134942a55

echo "Applying Flare-specific changes to AvalancheGo..."

GENESIS_FILE=genesis_local.go
if [ $# -ne 0 ]
  then
    GENESIS_FILE=genesis_$1.go
fi

echo "Using ${GENESIS_FILE}"

# Apply changes to avalanchego
cp $WORKING_DIR/src/genesis/$GENESIS_FILE ./genesis/genesis_testnet.go
cp $WORKING_DIR/src/avalanchego/flags.go ./config/flags.go
cp $WORKING_DIR/src/avalanchego/genesis.go ./genesis/genesis.go
cp $WORKING_DIR/src/avalanchego/beacons.go ./genesis/beacons.go
cp $WORKING_DIR/src/avalanchego/genesis_fuji.go ./genesis/genesis_fuji.go
cp $WORKING_DIR/src/avalanchego/unparsed_config.go ./genesis/unparsed_config.go
cp $WORKING_DIR/src/avalanchego/node.go ./node/node.go
cp $WORKING_DIR/src/avalanchego/vm.go ./vms/platformvm/vm.go
cp $WORKING_DIR/src/avalanchego/set.go ./snow/validators/set.go
cp $WORKING_DIR/src/avalanchego/build_coreth.sh ./scripts/build_coreth.sh
mkdir ./scripts/coreth_changes
cp $WORKING_DIR/src/coreth/vm.go ./scripts/coreth_changes/vm.go
cp $WORKING_DIR/src/coreth/import_tx.go ./scripts/coreth_changes/import_tx.go
cp $WORKING_DIR/src/coreth/export_tx.go ./scripts/coreth_changes/export_tx.go
cp $WORKING_DIR/src/coreth/state_transition.go ./scripts/coreth_changes/state_transition.go
cp $WORKING_DIR/src/stateco/state_connector.go ./scripts/coreth_changes/state_connector.go
cp $WORKING_DIR/src/keeper/keeper.go ./scripts/coreth_changes/keeper.go
cp $WORKING_DIR/src/keeper/keeper_test.go ./scripts/coreth_changes/keeper_test.go

export ROCKSDBALLOWED=1
./scripts/build.sh
rm -rf ./scripts/coreth_changes
chmod -R 775 $GOPATH/src/github.com/ava-labs
chmod -R 775 $GOPATH/pkg/mod/github.com/ava-labs