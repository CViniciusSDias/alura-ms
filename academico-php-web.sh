#!/usr/bin/env bash

if [ ! -d vendor ]; then
  composer install
fi

php artisan migrate
php artisan db:seed --force
php -S web-academico:8080 -t public
