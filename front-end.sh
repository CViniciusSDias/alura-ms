#!/usr/bin/env bash

if [ ! -d node_modules ]; then
  npm install
fi

npm start -- --host=0.0.0.0 --port 4200
