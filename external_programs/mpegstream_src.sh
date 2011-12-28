#!/bin/bash

# example for external stream source.
# streams remote VDR 1.6 recordings over slow bandwidth line.
# (Web-UI + Daemon: https://github.com/jjYBdx4IL/VDR-Streamer)

killall curl >& /dev/null

exec curl http://i5:3001/playback 2>/dev/null

