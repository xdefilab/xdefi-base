#!/bin/sh

source /etc/bashrc

truffle compile --all 

truffle migrate --reset --network development

truffle test test/num.js --network development

sleep 1s

truffle test test/factory.js --network development

sleep 1s

truffle test test/pool.js --network development

sleep 1s

truffle test test/math_with_fees.js --network development