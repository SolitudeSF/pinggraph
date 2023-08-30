# pinggraph

**pinggraph** is a nim reimplementation of [lagraph](https://github.com/Calinou/lagraph), command-line utility that draws a ping graph.

## Motivation
Why rust and not nim?

## Installation
With [Nim](https://nim-lang.org) toolchain installed: `nimble install pinggraph`

To run the binary without root rights, it needs raw socket capability: `setcap cap_net_raw+ep $(which pinggraph)`

Windows isnt supported.
