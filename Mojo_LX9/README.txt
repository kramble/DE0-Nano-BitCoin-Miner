Mojo port of fpgaminer. NB This is untested code (I don't have a Mojo Board).

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
3 hashers. Once this is tested and working, I will work on the 6 hasher version (it should
compile as the ../Xilinx_LX9 project is essentially the same and works, so it just needs
some manual intervention in the placement using FPGA Editor).

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

I would appreciate feedback on the Mojo forum as to whether this works!

Changes
-------
2013-06-16:11:30	Initial release
2013-06-16:14:30	Changed CTR_SIZE from 7 to 8 in serial.v to support faster clock
					Generated new bitsteams (NB the previous .bin is invalid, do not use)
					Added serial_rx_debounce.v (used for testing @4800baud, not for Mojo)

---------------------------------------------------------------------------
TODO...
Simulate serial rx - DONE
Create btcminer a/c mojotest & config into miner.py - DONE
Check miner.py 44 byte protocol - DONE
Test miner.py on raspberry pi at 4800 baud - DONE
Do test build for my LX9 homebrew board (different project/top module due to pinout),
NB configure for 4800 baud to run using standard optoisolator interface - DONE (works)
Try at 100MHz - DONE (works)
Get 6 hasher variant to build - TODO
Investigate Icarus/Ztex protocol for use with cgminer instead of miner.py (see technohog) - TODO
---------------------------------------------------------------------------
