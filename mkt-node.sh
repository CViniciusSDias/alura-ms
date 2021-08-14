#!/usr/bin/env bash

if [ ! -d node_modules ]; then
  npm install
fi

npm start
