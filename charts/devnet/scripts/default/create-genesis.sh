#!/bin/bash

set -eux

DENOM="${DENOM:=uosmo}"
COINS="${COINS:=100000000000000000uosmo}"
CHAIN_ID="${CHAIN_ID:=osmosis}"
CHAIN_BIN="${CHAIN_BIN:=osmosisd}"
CHAIN_DIR="${CHAIN_DIR:=$HOME/.osmosisd}"
KEYS_CONFIG="${KEYS_CONFIG:=configs/keys.json}"

FAUCET_ENABLED="${FAUCET_ENABLED:=true}"
NUM_VALIDATORS="${NUM_VALIDATORS:=1}"

# check if the binary has genesis subcommand or not, if not, set CHAIN_GENESIS_CMD to empty
CHAIN_GENESIS_CMD=$($CHAIN_BIN 2>&1 | grep -q "genesis-related subcommands" && echo "genesis" || echo "")

jq -r ".genesis[0].mnemonic" $KEYS_CONFIG | $CHAIN_BIN init $CHAIN_ID --chain-id $CHAIN_ID --recover

# Add genesis keys to the keyring and self delegate initial coins
echo "Adding key...." $(jq -r ".genesis[0].name" $KEYS_CONFIG)
jq -r ".genesis[0].mnemonic" $KEYS_CONFIG | $CHAIN_BIN keys add $(jq -r ".genesis[0].name" $KEYS_CONFIG) --recover --keyring-backend="test"
$CHAIN_BIN $CHAIN_GENESIS_CMD add-genesis-account $($CHAIN_BIN keys show -a $(jq -r .genesis[0].name $KEYS_CONFIG) --keyring-backend="test") $COINS --keyring-backend="test"

## if facuet not enabled then add validator and relayer with index as keys and into gentx
if [[ $FAUCET_ENABLED == "false" && $NUM_VALIDATORS -gt "1" ]];
then
  ## Add validators key and delegate tokens
  for i in $(seq 0 $NUM_VALIDATORS);
  do
    VAL_KEY_NAME="$(jq -r '.validators[0].name' $KEYS_CONFIG)-$i"
    echo "Adding validator key.... $VAL_KEY_NAME"
    jq -r ".validators[0].mnemonic" $KEYS_CONFIG | $CHAIN_BIN keys add $VAL_KEY_NAME --index $i --recover --keyring-backend="test"
    $CHAIN_BIN $CHAIN_GENESIS_CMD add-genesis-account $($CHAIN_BIN keys show -a $VAL_KEY_NAME --keyring-backend="test") $COINS --keyring-backend="test"
  done
  ## Add relayer key and delegate tokens
  echo "Adding key...." $(jq -r ".relayers[0].name" $KEYS_CONFIG)
  jq -r ".relayers[0].mnemonic" $KEYS_CONFIG | $CHAIN_BIN keys add $(jq -r ".relayers[0].name" $KEYS_CONFIG) --recover --keyring-backend="test"
  $CHAIN_BIN $CHAIN_GENESIS_CMD add-genesis-account $($CHAIN_BIN keys show -a $(jq -r .relayers[0].name $KEYS_CONFIG) --keyring-backend="test") $COINS --keyring-backend="test"
fi

echo "Creating gentx..."
COIN=$(echo $COINS | cut -d ',' -f1)
AMT=$(echo ${COIN//[!0-9]/} | sed -e "s/0000$//")
$CHAIN_BIN $CHAIN_GENESIS_CMD gentx $(jq -r ".genesis[0].name" $KEYS_CONFIG) $AMT$DENOM --keyring-backend="test" --chain-id $CHAIN_ID

echo "Output of gentx"
cat $CHAIN_DIR/config/gentx/*.json | jq

echo "Running collect-gentxs"
$CHAIN_BIN $CHAIN_GENESIS_CMD collect-gentxs

ls $CHAIN_DIR/config
