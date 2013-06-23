Mojo port of fpgaminer.

I don't have a Mojo Board to test it myself but it is reported to work on the Mojo forum.

This is based on https://github.com/progranism/Open-Source-FPGA-Bitcoin-Miner
It also includes code from http://www.makomk.com/gitweb/?p=Open-Source-FPGA-Bitcoin-Miner.git

Discussion is at https://bitcointalk.org/index.php?topic=9047.0
Mojo at http://embeddedmicro.com/forum/ (Project Ideas)

This source code is supplied as a request for sharing from several bitcointalk users.
This code is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

I have included files from mojo_base, should these need to be removed due to copyright then
the following files are simply copied from mojo_base.

mojo.ucf
mojo_top.v
serial_rx.v
serial_tx.v
NB avr_interface.v is not needed as I call serial_rx and serial_rx directly.

In mojo_top.v I have commented out the line "assign led = 8'b0;" and pasted in the contents of
fpgaminer_stub.txt to follow that line, just before the endmodule line.

To compile, see notes in MojoCreateXSE.txt (I have precompiled .bit and .bin bitstreams).
Compilation time can be very variable (minor changes can have disproportionate effects).
I have been unable to compile with 6 hashers, so the current version is configured for
3 hashers. SOLVED: you need to set XIL_PAR_ENABLE_LEGALIZER=1 in your environment, so for
windows you change Computer/(rightclick)/Properties/AdvancedSystemSettings/EnvironmentVars.
Compilation then works OK. ADDENDUM: Xilinx PAR is extremely quirky, just a tiny change to
the design can make the difference between a 20 minute compile and forever. If you're having
problems, just try changing the clock speed slightly (say from 100MHz to 90, or 110), or make
a trivial change to the logic (eg change how the leds are driven, use different bits of nonce,
or a larger led_match counter, see below). Its completely arbitary but this often works.

I have configured the clock PLL at 50MHz which is fairly conservative, it will likely run at
100MHz or more. Hash rate is clock * hashers / 132, vis 1.13MHash/sec for 3 hashers at 50MHz

The mining interface is MiningSoftware/miner.py, you will need to install python 2.7, then ...

From the fpgaminer/project/Verilog_Xilinx_Port/README.txt I quote ...
  It requires a few non-standard libraries, pyserial and json-rpc.
  http://pyserial.sourceforge.net/
  (also generally available in Linux distributions)
  http://json-rpc.org/wiki/python-json-rpc

Since these are open source, I have included them in the MiningSoftware folder, vis

pyserial-2.6 from http://pyserial.sourceforge.net
python-json-rpc from http://json-rpc.org/browser/trunk/python-jsonrpc/jsonrpc

To install them run "python setup.py install" in each folder (sudo if on linux)

Edit miner.py and set the serial port to match your mojo port (eg COM2).
The miner.py script is preconfigured for the btcguild.com mining pool with the test account
mojotest. You should create your own account if you want to benefit from any shares you mine,
else they go to me, not that I expect many as the LX9 will only mine a few shares per hour!

Then run the miner via python miner.py (it takes 20 secs to startup since this is askrate).
At 1.13MHash/sec you can expect around one share per hour, so I have included a test hash in
the mining.py script. Uncomment the test_payload lines to try this (and BEWARE, python is
insanely sensitive to whitespace, keep the exact indentation and don't use tab characters).
There are some additional print statements for debugging. Comment these out if not needed.

To use with cgminer: I have added the option to use teknohog's original protocol, just set
ICARUS=1 in mojo_top.v. You will need to change the packet size in miner.py (trivial as
the required line is present but commented out) if you want to use that driver. Usage with
cgminer is more awkward. You will need version 3.1.1 as later versions do not support the
-S option. The documentation specifies a minimum speed of 2MHash/sec, so you will need one
of the faster builds (I assume this is because of the icarus auto-detection test). Also
the only baud rates supported are 57600 and 115200, but it *may* work with the Mojo as
Mojo docs state the baudrate parameter is ignored and it runs at 500 kbaud regardless.
It also needed a change to fpgaminer_top.v to reset the nonce on new work (this is needed
because cgminer sends a test block to the fpga on startup and expects the correct golden
nonce, else it fails the icarus detection). Note that this breaks the test_payload feature
in miner.py as not enough time is available to reach the test nonce, it just needs a new
test block in order to fix it - DONE see miner_icarus.py, or increase the askrate to match
(600sec should do it, but don't use this value live).
I have not implimented the work request feature (sends golden nonce 0 on wrap) as this will
never be needed at LX9 speeds.
I cannot test it myself as my rig only runs at 4800 baud (AHEM, well I did hack the
cgminer source to run at 4800, and it sort of worked, but required a change to the icarus
detection algorithm to send the work packet twice as the first was ignored. This may be
due to the use of a physical serial port on the raspberry pi rather than USB or may be a
fault in my version of the fpgaminer code. Feedback would be appreciated as to whether the
Mojo works with cgminer 3.1.1)

NB The current icarus build does not compile at 6 hashers, loop 11, 100MHz (it just sits
in PAR for hours and hours). See addendum above for some hints on how to fix it (I'll not
amend the current code as this could break other configurations).

The changes I made to get it to compile were ...

// fpgaminer_top.v
output [7:0]led3;
reg [7:0]led_match = 0;	
led_match <= led_match+1;	// Near the bottom of the file "if (is_fullhash && fullhash)"

// mojo_top.v
wire [7:0]led3;
assign led = { led3[6:0], led1 };

Changes
-------
2013-06-16:11:30 Initial release
2013-06-16:14:00 Changed CTR_SIZE from 7 to 8 in serial.v to support faster clock
                 Generated new bitsteams
                 Added serial_rx_debounce.v (used for testing @4800baud, not for Mojo)
2013-06-22:12:00 Added parameter to serial.v to revert back to teknohog/icarus protocol
                 Also reset nonce on new work in fpgaminer_top.v
                 And a whole load of tweaks to make simulation/testing easier.

---------------------------------------------------------------------------
TODO...
Simulate serial rx - DONE
Create btcminer a/c mojotest & config into miner.py - DONE
Check miner.py 44 byte protocol - DONE
Test miner.py on raspberry pi at 4800 baud - DONE
Do test build for my LX9 homebrew board (different project/top module due to pinout),
NB configure for 4800 baud to run using standard optoisolator interface - DONE (works)
Try at 100MHz - DONE (works)
Get 6 hasher variant to build - DONE
Revert to teknohog/icarus for use with cgminer instead of miner.py - DONE (UNTESTED)
---------------------------------------------------------------------------
