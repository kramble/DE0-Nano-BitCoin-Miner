Released on request by Personal Message from bitcointalk user Ersch

NB This is makomk's code from http://www.makomk.com/gitweb/?p=Open-Source-FPGA-Bitcoin-Miner.git;a=tree;h=refs/heads/de0-nano-usb;hb=de0-nano-usb

All I have done is swapped out his USB interface for my Raspberry Pi serial interface, and added my poweron_reset logic (which I use to limit the power drawn while programming the board using the USB cable).

If you want to use it with the original mine.tcl jtag driver instead of my serial interface, you will need to replace this with the original virtual_wire code (I haven't tried it myself). You may find it easier just to work from makomk's code at the link above.

BEWARE!! Don't try to run this at full speed just powered from the usb cable as its going to try to draw around 2 amps at 35MHash/sec (140MHz). I haven't actually measured it myself, but that's a rough guess. I recommend using makomk's 1.2V core psu mod at http://www.makomk.com/2011/10/06/de0-nano-power-efficiency-mod/#more-55 (though I didn't bother removing R61 myself, just ran both PSUs in parallel).

Good Luck
Mark