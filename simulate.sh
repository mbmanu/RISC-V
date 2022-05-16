#!/bin/bash -e
iverilog -Wall -g2012 -o run testbench.sv alu.v cond.v ram.v rvcore.v && vvp run +firmware=/d/Projects/MajorProject/test.bin