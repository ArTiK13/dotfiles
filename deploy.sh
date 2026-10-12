#!/bin/sh
MACHINE=$1
TYPE=$2
if [ "$TYPE" == "" ]; then
  TYPE="switch"
fi
shift
if [ "$#" -gt 0 ]; then
  shift
fi

# Assumes passwordless sudo on the remote host for nixos-rebuild --sudo.
# Forward optional rebuild arguments, e.g. Nix download timeouts.
nixos-rebuild "$TYPE" --flake ".#$MACHINE" --target-host $MACHINE --build-host $MACHINE --sudo --no-reexec --show-trace "$@"
