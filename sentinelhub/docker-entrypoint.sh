#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"

  echo "Running init..."
  sentinelhub init "$MONIKER" --chain-id "$NETWORK" --home /cosmos --overwrite

  echo "Downloading config..."

  SEEDS=$(curl -s https://raw.githubusercontent.com/cosmos/chain-registry/master/sentinel/chain.json | jq -r '[.peers.seeds[] | "\(.id)@\(.address)"] | join(",")')

  cd /cosmos/config && \
  curl -sL -o genesis.zip "https://raw.githubusercontent.com/sentinel-official/networks/main/${NETWORK}/genesis.zip" && \
  unzip -o genesis.zip && rm genesis.zip

  dasel put -f /cosmos/config/config.toml -v "$SEEDS" p2p.seeds

  if [ -n "$SNAPSHOT" ]; then
    echo "Downloading snapshot..."
    curl -o - -L "$SNAPSHOT" | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos
  else
    echo "No snapshot URL defined."
  fi

  # Check whether we should rapid sync
  if [ -n "${RAPID_SYNC_URL}" ]; then
    echo "Configuring rapid state sync"
    # Get the latest height
    LATEST=$(curl -s "${RAPID_SYNC_URL}/block" | jq -r '.result.block.header.height')
    echo "LATEST=$LATEST"

    # Calculate the snapshot height
    SNAPSHOT_HEIGHT=$((LATEST - 2000));
    echo "SNAPSHOT_HEIGHT=$SNAPSHOT_HEIGHT"

    # Get the snapshot hash
    SNAPSHOT_HASH=$(curl -s "${RAPID_SYNC_URL}/block?height=${SNAPSHOT_HEIGHT}" | jq -r '.result.block_id.hash')
    echo "SNAPSHOT_HASH=$SNAPSHOT_HASH"

    dasel put -f /cosmos/config/config.toml -v true statesync.enable
    dasel put -f /cosmos/config/config.toml -v "${RAPID_SYNC_URL},${RAPID_SYNC_URL}" statesync.rpc_servers
    dasel put -f /cosmos/config/config.toml -v "$SNAPSHOT_HEIGHT" statesync.trust_height
    dasel put -f /cosmos/config/config.toml -v "$SNAPSHOT_HASH" statesync.trust_hash
  else
    echo "No rapid sync url defined."
  fi

  touch /cosmos/.initialized
else
  echo "Already initialized!"
fi

# Set other necessary configurations
dasel put -f /cosmos/config/config.toml -v "${MONIKER}" moniker
dasel put -f /cosmos/config/app.toml -v true api.enable
dasel put -f /cosmos/config/app.toml -v "tcp://0.0.0.0:${CL_REST_PORT:-1317}" api.address
dasel put -f /cosmos/config/app.toml -v true grpc.enable
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT:-9090}" grpc.address
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_RPC_PORT:-26657}" rpc.laddr
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_P2P_PORT:-26656}" p2p.laddr
dasel put -f /cosmos/config/app.toml -v "${MIN_RETAIN_BLOCKS}" min-retain-blocks
dasel put -f /cosmos/config/app.toml -v "${PRUNING}" pruning
dasel put -f /cosmos/config/config.toml -v "null" tx_index.indexer

exec sentinelhub start "$@" --home=/cosmos --log_format json "${EXTRA_FLAGS:-}"
