#!/bin/bash
git pull
rm -rf ./KernelSU
curl -LSs "https://raw.githubusercontent.com/5ec1cff/KernelSU/main/kernel/setup.sh" | bash -s main
git add .
git commit -m 升级MKSU
git push