# (c) 2021, Flare Networks Limited. All rights reserved.
# Please see the file LICENSE for licensing terms.

#!/bin/bash
if [[ $(pwd) =~ " " ]]; then echo "Working directory path contains a folder with a space in its name, please remove all spaces" && exit; fi
if [ -z ${GOPATH+x} ]; then echo "GOPATH is not set, visit https://github.com/golang/go/wiki/SettingGOPATH" && exit; fi
printf "\x1b[34mFlare Network 1-Node Local Deployment\x1b[0m\n\n"

LAUNCH_DIR=$(pwd)

# Ava has not tested and is thus not supporting rocksdb on Mac at this time.
DB_TYPE=rocksdb
if [ "$(uname)" == "Darwin" ]; then DB_TYPE=leveldb; fi

# Test and export underlying chain APIs you chose to use for the state connector
source ./conf/export_chain_apis.sh $LAUNCH_DIR/conf/local/chain_apis.json

export FBA_VALs=$LAUNCH_DIR/conf/local/fba_validators.json
AVALANCHE_DIR=$GOPATH/src/github.com/ava-labs/avalanchego
cd $AVALANCHE_DIR
if ! echo $1 | grep -e "--existing" -q
then
	rm -rf $LAUNCH_DIR/logs/local
	mkdir -p $LAUNCH_DIR/logs/local
	rm -rf $LAUNCH_DIR/db/local
	mkdir -p $LAUNCH_DIR/db/local
	mkdir -p $LAUNCH_DIR/logs/local/node1
	mkdir -p $LAUNCH_DIR/logs/local/node2
	mkdir -p $LAUNCH_DIR/logs/local/node3
	mkdir -p $LAUNCH_DIR/logs/local/node4
	mkdir -p $LAUNCH_DIR/logs/local/node5
	mkdir -p $LAUNCH_DIR/db/local/node1
	mkdir -p $LAUNCH_DIR/db/local/node2
	mkdir -p $LAUNCH_DIR/db/local/node3
	mkdir -p $LAUNCH_DIR/db/local/node4
	mkdir -p $LAUNCH_DIR/db/local/node5
fi

# NODE 1
printf "Launching Node 1 at 127.0.0.1:9650\n"
export WEB3_API=debug
./build/avalanchego \
--public-ip=127.0.0.1 \
--snow-sample-size=1 \
--snow-quorum-size=1 \
--http-port=9650 \
--staking-port=9651 \
--log-dir=$LAUNCH_DIR/logs/local/node1 \
--db-dir=$LAUNCH_DIR/db/local/node1 \
--bootstrap-ips= \
--bootstrap-ids= \
--staking-enabled=false \
--staking-tls-cert-file=$LAUNCH_DIR/conf/local/node1/node.crt \
--staking-tls-key-file=$LAUNCH_DIR/conf/local/node1/node.key \
--db-type=$DB_TYPE \
--log-level=info

