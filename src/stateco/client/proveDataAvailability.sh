# (c) 2021, Flare Networks Limited. All rights reserved.
# Please see the file LICENSE for licensing terms.

#!/bin/bash

if [ $1 == 'btc' ]; then
  PORT=8000
elif [ $1 == 'ltc' ]; then
  PORT=8001
elif [ $1 == 'doge' ]; then
  PORT=8002
elif [ $1 == 'xrp' ]; then
  PORT=8003
fi;
while true; do
	nohup $(sleep 10; curl -s http://localhost:$PORT/?prove=$1) >& /dev/null &
	if ! lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
	    node stateConnector $PORT --unhandled-rejections=strict
	else
		echo "System already activated."
	fi;
	sleep 10
done
