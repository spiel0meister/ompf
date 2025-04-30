#!/usr/bin/env bash

set -ex

version=$(git describe --always HEAD)

odin build . -debug -extra-linker-flags:-L$HOME/.local/lib/ "-define:VERSION=\"$version\""

