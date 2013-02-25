# Run mine with correct parameters
nohup ./mine /dev/ttyAMA0 4800 8 0 0 config-live2.tcl >/tmp/mine.log 2>&1 &
echo "Running nohup in background, log is /tmp/mine.log"
