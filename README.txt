A quick note to help you find your way around this stuff.

First a small apology ... I'm just a amateur at this, so its all rather messy,
and I'm not using any source control, so just a bunch of folders. I've deleted
the intermediate/output stuff as its huge, so its just the source code left.
You'll also find several README's ... that's just my working notes.

DE0-Nano		... this is quite out of date now and is probably
					only of interest for README_MJ_DE0_fpgaminer.txt

DE0_Nano_serial	... serial interface, again its out of date and the
					sha256_transform.v is buggy (it runs OK, but the
					max clock speed is slower Makomk's latest version).
					
CompareMakomk	... my most recent work comparing makomk's latest githib code
					with the original fpgaminer code. Probably a good place
					to start.

CompareMakomk/Hashers22_serial	... my latest (working) serial interface code.
					It completely abandons LOG_LOOP2 in favour of a hard-coded
					LOOP=3 implimetation using 22 hashers generating one hash
					every 6 clock cycles. My fastest version to date!

CompareMakomk/Hashers22			... as above but using the USB interface (for
					ease of testing as the serial code only runs off the
					raspberry pi).

DE0-Combo		... a bit of a kludge as it combines a miner with code to
					program a homebrew EP4CE10 board using a DE0-Nano via USB,
					and a bridge for testing the serial interface via USB (since
					my development platform is a laptop with no serial port).
					Only of note because it was my current mining code prior
					to Hashers22_serial, so is the most recent working code
					that uses the LOG_LOOP2 parameter.

spoof			... this is a test harness so I can feed consistent getwork to
					the miner locally (and avoid annoying the mining pool).
					Just use config-spoof.tcl for config.tcl in mine.
					
mine			... my (slightly) modified version of the jtag mining scripts.
					I've (hopefully) redacted the login details in config.tcl
					not that it really matters as I've only mined a whopping
					0.1BTC so far.
					
serial_solo		... this is the mining software for the raspberry pi (somewhat
					of a kludge, but it works quite reliably).

FpgaminerOnPi.txt	... I wrote this a while ago to document what I did to get
					the serial port working on the raspberry pi, (I thought
					somebody might ask for it so it reads a bit like an
					instruction manual).

Any questions, just drop me a line and I'll do my best. As I said its all rather
amateurish, but if its of any use to you then you're welcome to it.