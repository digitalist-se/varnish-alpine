#!/bin/sh
set -e
exec sh -c \
  "exec varnishd -F \
  -f $VCL_CONFIG \
  -s malloc,$CACHE_SIZE \
  -S $SECRET_FILE \
  $VARNISHD_PARAMS"
