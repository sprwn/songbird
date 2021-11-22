# (c) 2021, Flare Networks Limited. All rights reserved.
# Please see the file LICENSE for licensing terms.

#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Directory above this script
AVALANCHE_PATH=$( cd "$( dirname "${BASH_SOURCE[0]}" )"; cd .. && pwd )

# Load the versions
source "$AVALANCHE_PATH"/scripts/versions.sh

# Load the constants
source "$AVALANCHE_PATH"/scripts/constants.sh

# check if there's args defining different coreth source and build paths
if [[ $# -eq 2 ]]; then
    coreth_path=$1
    evm_path=$2
elif [[ $# -eq 0 ]]; then
    if [[ ! -d "$coreth_path" ]]; then
        go get "github.com/ava-labs/coreth@$coreth_version"
    fi
else
    echo "Invalid arguments to build coreth. Requires either no arguments (default) or two arguments to specify coreth directory and location to add binary."
    exit 1
fi

echo "Applying Flare-specific changes to Coreth..."
chmod -R 775 $coreth_path
cp $AVALANCHE_PATH/scripts/coreth_changes/vm.go $coreth_path/plugin/evm/vm.go
cp $AVALANCHE_PATH/scripts/coreth_changes/import_tx.go $coreth_path/plugin/evm/import_tx.go
rm $coreth_path/plugin/evm/import_tx_test.go
cp $AVALANCHE_PATH/scripts/coreth_changes/export_tx.go $coreth_path/plugin/evm/export_tx.go
rm $coreth_path/plugin/evm/export_tx_test.go
cp $AVALANCHE_PATH/scripts/coreth_changes/state_transition.go $coreth_path/core/state_transition.go
cp $AVALANCHE_PATH/scripts/coreth_changes/state_connector.go $coreth_path/core/state_connector.go
cp $AVALANCHE_PATH/scripts/coreth_changes/keeper.go $coreth_path/core/keeper.go
cp $AVALANCHE_PATH/scripts/coreth_changes/keeper_test.go $coreth_path/core/keeper_test.go

# Build Coreth
echo "Building Coreth @ ${coreth_version} ..."
cd "$coreth_path"
go build -ldflags "-X github.com/ava-labs/coreth/plugin/evm.Version=$coreth_version $static_ld_flags" -o "$evm_path" "plugin/"*.go
cd "$AVALANCHE_PATH"

# Building coreth + using go get can mess with the go.mod file.
go mod tidy
