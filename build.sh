#!/usr/bin/env bash

set -ex

odin build . -debug -extra-linker-flags:-L$HOME/.local/lib/

