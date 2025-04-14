#!/usr/bin/env bash

set -ex

odin build . -extra-linker-flags:-L$HOME/.local/lib/

