#!/bin/sh
exec log stream --predicate 'subsystem =="com.keminglabs.whispertron"' --debug
