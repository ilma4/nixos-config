#!/usr/bin/env bash

nix flake check --all-systems "path:$FLAKE_LOCATION"
