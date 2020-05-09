#!/bin/zsh
'julia' --startup-file=no --sysimage=/usr/lib/julia/sys.so --output-ji=delete_this.ji --output-incremental=yes no_overwrite_mod.jl
