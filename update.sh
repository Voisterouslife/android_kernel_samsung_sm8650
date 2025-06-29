#!/bin/bash
git pull
rm -rf ./KernelSU
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s main
git add .
git commit -m 升级KSU
git push