DE0 Nano port of fpgaminer

This is based on https://github.com/progranism/Open-Source-FPGA-Bitcoin-Miner
It also includes code from http://www.makomk.com/gitweb/?p=Open-Source-FPGA-Bitcoin-Miner.git

Discussion is at https://bitcointalk.org/index.php?topic=9047.0
Creation note at https://bitcointalk.org/index.php?topic=9047.msg1558141#msg1558141

A quick note to help you find your way around this stuff.

Hashers22 - a port of the Open-Source-FPGA-Bitcoin-Miner to the DE0-Nano, hard coded with 22
sha256_transform modules, giving one full bitcoin hash per 6 clock cycles. It uses the USB/JTAG
driver (scripts\mine.tcl) as described in the original project. I have not incuded the program
and mine scripts as these are available from Open-Source-FPGA-Bitcoin-Miner linked above.

Hashers22_serial - this impliments a custom serial interface to a rasperry pi host instead of
the PC hosted USB/JTAG driver used above.

serial_solo - the raspberry pi driver (rather crude and basic).

FpgaminerOnPi.txt - describes how to setup the serial interface

PLL clock speed is set by the parameter (VHDL macro) SPEED_MHZ in units of 10MHz
eg SPEED_MHZ=4 runs at 40MHz. This is the fastest that I recommend for unmodified DE0-Nano,
any faster risks overheating the onboard regulators. You may clock faster at your own risk,
but cooling of the regulator chips is necessary, and an external power supply is recommended.
Current draw is approx 100mA per 10MHz (eg 80MHz will draw approx 800mA, which is more than
a typical USB port is rated for, and the board, especially the regulators, will run VERY hot).
I have run at up to 170MHz using a custom auxilliary 1.2 volt core supply and fan cooling,
but this is foolhardy and not at all to be recommened. It did give me 28.3 MHash/sec though :-)

Once programmed, the miner starts up in a halted state to reduce current draw. This allows
the USB cable to be disconnected before starting the miner (assuming an external supply is
connected), thus avoiding drawing excess current from the USB cable. This is only of practical
use in the serial version as the USB cable is needed for communication during PC hosted mining.
The KEY0/1 push buttons on the DE0-Nano board are used to start (reset) and halt the miner.