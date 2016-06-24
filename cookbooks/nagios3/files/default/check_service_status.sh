#!/bin/bash
##-------------------------------------------------------------------
## File: check_service_status.sh
## Author : Denny <denny@dennyzhang.com>
## Description :
## --
## Created : <2015-02-24>
## Updated: Time-stamp: <2016-06-24 20:44:32>
##-------------------------------------------------------------------
# TODO: move to common library
service_name=${1?}

sudo "/etc/init.d/$service_name" status
exit_code=$?
if [ $exit_code = 0 ]; then
    echo "OK: service $service_name is running | status=0"
else
    echo "CRITICAL: service $service_name has stopped | status=2"
    exit 2
fi
## File: check_service_status.sh ends
