A DE0-Nano port of the Open-Source-FPGA-Bitcoin-Miner.

This is based on https://github.com/progranism/Open-Source-FPGA-Bitcoin-Miner
Includes code from http://www.makomk.com/gitweb/?p=Open-Source-FPGA-Bitcoin-Miner.git

Discussion is at https://bitcointalk.org/index.php?topic=9047.0
Creation note at https://bitcointalk.org/index.php?topic=9047.msg1558141#msg1558141

This source code is supplied as a request for sharing from several bitcointalk users.
This code is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

NEWS - BLOCKFINDER - On 31-July-2013 my EP4CE10 running at 12MHash/sec found block 249499
with a 1.6 billion difficulty hash ...
00000000000000029dfde2ddc7f233ef71671bf15d98d44690bc39ecf8818bf1
This is just so absurdly improbable that I wanted to share that news! PS checkout my new
Litecoin scrypt mining project at https://github.com/kramble/FPGA-Litecoin-Miner

IMPORTANT You will need to press the KEY-0 pushbutton on the DE0-Nano board to start the
miner. The LEDs display a binary count (top byte of nonce) to indicate mining in-progress

A quick note to help you find your way around this stuff ...

Hashers22 - is a port of the Open-Source-FPGA-Bitcoin-Miner to the DE0-Nano, hard coded
with 22 sha256_transform modules, giving one full bitcoin hash per 6 clock cycles. It
uses the USB/JTAG driver (scripts\mine.tcl) as described in the original project. I have
not incuded the program and mine scripts as these are available from the
Open-Source-FPGA-Bitcoin- Miner which is linked above and should be referred to for
operating instructions.

Hashers22_serial - this impliments a custom serial interface instead of the USB/JTAG
driver used above. It requires a Raspberry pi single-board computer (since that's what I
had to hand) and a homebrew interface board. It should not be too difficult to port it to
some other configuration, though beware the voltage limits of the DE0-Nano I/O (Do NOT
connect it directly to a standard PC RS232 serial port as you will destroy the DE0-Nano
board.)

serial_solo - the raspberry pi mining driver written in C (rather crude and basic).

FpgaminerOnPi.txt - describes how to setup the serial interface on the pi.

Various other ports including EP4CE10, LX9 (both using my serial interface) and MOJO_LX9
Of note is Makomk_Hashers_22_Serial which has reliably performed at 35MHash/sec for three
months now (code is entirely Makomk's, I just added my raspberry pi serial interface).

The PLL clock speed is set by the parameter (Verilog macro) SPEED_MHZ in units of 10MHz,
eg SPEED_MHZ=4 runs at 40MHz, which is the default setting. This gives 6.67MHash/s
throughput. This is the fastest that I recommend running an unmodified DE0-Nano. You may
clock faster at your own risk, but you should monitor the temperature of the the onboard
regulator chips as these will get VERY hot unless additional cooling is applied (eg fan
blown air). The fpga chip may also need cooling. BEWARE, you risk destroying your board
due to overheating if you increase SPEED_MHZ, and the actual speed in MHz is 10 times the
value set for SPEED_MHZ.

Current draw is approx 10mA per MHz (eg 40MHz will draw approx 400mA). Beware that a
typical USB port may only be able to supply 500mA so a 5.0 Volt external power supply
connected to the DE0-Nano white PSU header (JP4) is advised if overclocking. I have not
myself run this configuration any faster than 80MHz (SPEED_MHZ=8), and fan cooling was
essential.

After programming, the miner starts up in a halted state (it does NOT mine in this state)
Pressing the KEY0 pushbutton on the DE0-Nano board will start the miner (and reset the
nonce). Pressing KEY1 will halt it. This allows some control of power and thermal
management as the halted state draws considerably less current from the power supply.
This was of importance when extreme overclocking was applied to the Hashers22_serial
version as follows.

I have run the Hashers22_serial version at up to 140Mhz (SPEED_MHZ=14) using an external
3.3 Volt supply (the USB cable must be disconnected after programming and prior to
starting the miner else it will attempt to draw approx 1.5amps from the USB port which
may cause damage). Cooling is essential as the regulators run VERY hot. I also heatsinked
the fpga chip.

I have also run at 170MHz (SPEED_MHZ=17) using a custom hardwired 1.2 volt core supply
which gave my maximum achived throughput of 28.3 MHash/s. Attempting to run at 180MHz
gave bad hash results, so this is the limit. Note that this draws 1.7amps which is
outside the spec of the DE0-Nano regulators, hence the custom power supply hack.

The latter two extreme overclocking results are only mentioned since you may come across
comments to this effect on the bitcontalk blog linked above. I do NOT recommend you
attempt either of these things as there is a high risk of destroying your DE0-Nano board
and possibly the USB host computer as well. Don't go blaming me, you have been warned.
