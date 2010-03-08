#!/bin/bash

launchctl stop com.frobware.cmd-key-happy
cmd-key-happy -p && launchctl start com.frobware.cmd-key-happy
