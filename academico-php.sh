#!/usr/bin/env bash

if [ ! -d vendor ]; then
  composer install
fi

php receive.php
