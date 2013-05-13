/*
*
* Xilinx LX_9
* NB to change clock speed edit main_pll.v eg CLKFX_MULTIPLY(4) gives 80MHz (since 20MHz osc)
* and also set SPEED_MHZ=8 in async_transmitter.v and async_receiver.v
*
* 80MHz draws 230mA and toggles led1 every 9 secs ...
* This is a 1/44 core so expect 80/44 = 1.81 MHash/sec 2^24/1810000 = 9.27sec
* ... got a match but it was a 3xBadHash, and another the same
* BUT IT SIMULATED FINE !! DEBUGGING FOLLOWS...
* Reconfigure for 20MHz pass-through clock (see pll_blk below)...
* v09 TEST version hardcodes midstate/data for match on 1afda099 and 1e4c2ae6 - WORKS !!
* So what can be wrong? Either non-hardcoded hasher is broken or serrx is broken.
* v10 TEST version echoes midstate[255:224] back as golden nonce (b version - a version was
* still hardcoded).
* WEIRD ... fiddled with opto-isolator resistors, then added 74HC00 buffer ... now seeing
* correct data, but in WRONG position. Maybe 20Mhz is too slow (serial timing out). try 80MHz
* No change but noticed the offset is exactly 20 bytes ... AHA I'm using the original serial.v
* but I changed the number of bytes senot from 64 to 44. Replaced it with the hashers11 versiion.
* TEST it as v10c (80MHz) ... OK That's fine (with original opto-isolator)
*
* v11 LIVE version on nonce 2 range 1 (change DE0-Nano dip from range f..2 to e..1 so we can test)
* ... took 2 hours to find a match, then another came right away!
* Also built as nonce 3 range 1 (for use with modified EP4CE10 on range 4..6), 80MHz & 120MHz.
*
* v12 tweaked to build 6 hashers (NB need to replace index 21 with 6 in sha256 and fpgaminer_top)
* ... it actually compiled (unexpectedly!!), need to simulate before testing ... seems OK!
* HMMM the EP4CE10_Miner_140MHz_v09_osc=20MHz_range4-6.sof had poor fmax and gave BAD HASHES
* so reverted to EP4CE10_Miner_140MHz_v09_osc=20MHz_range3-6.sof and built a range 4 hashers2
* vis hashers22_serial_chain_range_3_80MHz.sof. So need a hashers6 for nonce=2 (80Mhz). Done.
*
* v13 Parameterises LOOP, NUM_HAHSERS and SPEED_MHZ. Set them below (grep CONFIGURATION).
* NB main_pll.v was tweaked individually for CLKFX_DIVIDE depending on resolution, and
*    I changed SPEED_MHZ from its orignal 10MHz units to 1Mhz units to allow 5Mhz steps 
*  80MHz max freq 33.9Mhz draws 260mA net (380mA gross inc board overheads of 120mA (60mA with byteblaster off))
* 100MHz max freq 27.1MHz draws 280mA net (400mA gross) ... hashes OK NB CLKFX_DIVIDE(1)
* 105MHz max freq 25.8MHz draws 330mA net (450mA gross) ... hashes OK NB CLKFX_DIVIDE(4)
* 110MHz max freq 24.7MHz draws 300mA net (420mA gross) ... hashes OK NB CLKFX_DIVIDE(2)
* 115MHz max freq 23.6MHz draws 310mA net (430mA gross) ... BAD HASHES
* 120MHz max freq TBA draws 340mA net (460mA gross) ... BAD HASHES
* 125MHz max freq 21.7Mhz ... cancelled build after 40 mins (taking too long!)
* 160Mhz max freq 16.9MHz draws 390mA new (510ma gross) ... BAD HASHES (assumed, since not run long enough to see any)
*
* As a check I rebuilt 110Mhz as "build2" using new 1MHz units version of SPEED_MHZ (which had
* required changes in the async_*.v files and main_pll.v). Same stats as above and seems OK.
*
* v14 By commenting out OFDDRCPE in main_pll.v I have eliminated unused_q.
* Did a 110Mhz build as per build2 above vis CLKFX_DIVIDE(2) ... EXCEPT it just hangs in the PAR
* phase 5 (even though fully routed). I gave up after 35 mins. Seems like voodoo is involved.
* Saved files as BAD_v14 and restored back to v13. Then did Project/CleanupProjectFiles and
* redid the 110Mhz build (as build3) to check. And it took just 12 minutes (ie same as usual)!
*
* Copyright (c) 2011 fpgaminer@bitcoin-mining.com
*
*
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
* 
*/


`timescale 1ns/1ps

module fpgaminer_top #(
	// CONFIGURATION
	parameter LOOP = 11,
	parameter NUM_HASHERS = 6,
	// NB main_pll.v will need to be tweaked depending on desired resolution
	//    currently configured for 10Mhz steps CLKFX_DIVIDE(2)
	parameter SPEED_MHZ = 110		// NB now in units of 1MHz
	)
	(osc_clk, RxD, TxD, led1, led2, led3, unused_q);

	input osc_clk;
	input RxD;
	output TxD;
	output led1;
	output led2;
	output led3;
	output unused_q;	// Fudge as I don't know how to get rid of unwanted Q pin

	// Hacks to allow use of hashers22 fpgaminer_top.v on EP4CE10
	wire reset_in = 1'b1;
	wire [3:0] DIP_in = 4'h2;	// Start 2 range 1
	
	reg led_anymatch = 0;	// DEBUG set on a match (stays set)
	reg led_match = 0;		// DEBUG toggles led on match
	assign led1 = nonce[24];
	assign led2 = led_anymatch;
	assign led3 = led_match;

	reg [255:0] state = 0;
	reg [127:0] data = 0;
	reg [31:0] nonce = 32'h00000000;
	wire [31:0] nonce_next;

	`ifndef SIM
	reg poweron_reset = 1;
	`else
	reg poweron_reset = 0;	// Disabled for simulation
	`endif
	
	//// PLL ... before clk_enable
	wire hash_clk;
	`ifndef SIM
// Original - this WORKS but adds a Q port which we do not want ...
//   		main_pll pll_blk (.CLKIN_IN(osc_clk), .CLK0_OUT(hash_clk));

// So connect it up so we can assign it to an unused pin - BUT this is 20MHz (unmultiplied osc)!!
//   		main_pll pll_blk (.CLKIN_IN(osc_clk), .CLK0_OUT(hash_clk), .DDR_CLK0_OUT(unused_q));

// So I hacked the main_pll.v to add MJ_CLK_FX_OUT at 80MHz
   		main_pll #(.SPEED_MHZ(SPEED_MHZ)) pll_blk (.CLKIN_IN(osc_clk), .MJ_CLK_FX_OUT(hash_clk), .DDR_CLK0_OUT(unused_q));

// This was in original but commented out ...
//     		main_pll pll_blk (.CLKIN_IN(osc_clk), .CLK2X_OUT(hash_clk));
	`else
	 	assign hash_clk = osc_clk;
	`endif
	
	//// Hashers
	
	// NB Unlike in hashers 22, we cannot easily synchronise the need to input a nonce
	// every 6 cycles with the 12 cycle (including state_first) feedback delay. Instead we
	// use a sequence variable to track the hash through the pipeline. Top level cnt and feedback
	// are no longer used, but phase is still handled at top level. We need to track the nonce,
	// so pass lowest 8 bits through pipeline and reconcile with top 24 bits later.
	
	// Output of sha256_transform
	wire [255:0] hash;
	wire [6:0] seq;			// HASHERS_6 increased from [4:0] to [6:0]
	wire [7:0] nonce_lsb;
	wire fullhash;
	
	// Deleayed output of sha256_transform
	reg [255:0] hash_d1;
	// HASHERS_6 increased from [4:0] to [6:0]
	reg [6:0] seq_d1 = 0;		// Needs to be init to 0 else breaks nonce_next in simulation
	reg [7:0] nonce_lsb_d1 = 0;	// May be able to get away with 6 bits here, but its probably in RAM so no need
	reg fullhash_d1 = 0;

	reg phase = 1'b0;			// Alternates function between first and second SHA256

	// MJ SHA256. NB this is the second of two rounds hashing an 80 byte message (the block header), padded
	// to 128 bytes (JSON data field) and hashed in two rounds of 64 bits each. The first is round is done by
	// the JSON server, giving us midstate. We insert the nonce into the correct position in the second 64
	// 64 bytes of data then SHA256 hash it with midstate. NB sha256_transform performs the internal SHA256
	// transform, it is NOT the complete SHA256 algorithm (which involves multiple rounds of sha256_transform).

	// Using just ONE sha256_transform which alternates according to phase to perform the two SHA256 transforms.
	// NB hash is only valid for phase==0, hence tx_fullhash
	sha256_transform #(.LOOP(LOOP), .NUM_HASHERS(NUM_HASHERS)) uut (
		.clk(hash_clk),
		.phase_in(phase),
		.nonce_lsb_in(phase ? nonce_lsb_d1 : nonce[7:0]),	// NB nonce, not nonce_next so as to match data latency
		.rx_state(state),			// Always pass in midstate, mux for phase is handled internally
		.rx_input(phase ? {256'h0000010000000000000000000000000000000000000000000000000080000000, hash_d1} :
		{384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, data}),
		.tx_hash(hash),
		.tx_seq(seq),
		.tx_nonce_lsb(nonce_lsb),
		.tx_fullhash(fullhash)
	);

	//// Virtual Wire Control

	wire [255:0] midstate_vw;
	wire [95:0] data2_vw;

	// NB Since already latched in serial_receive, can we get rid of these latches (or just use for simulation)? TODO !!
	
	`ifdef SIM
	reg [255:0] midstate_buf = 0;
	reg [95:0] data_buf = 0;
	`else
	wire [255:0] midstate_buf = midstate_vw;
	wire [95:0] data_buf = data2_vw;
	`endif

	// reg [31:0] test_prev_midstate = 0;
	
	// No need to simulate serial_receive and serial_transmit as we set midstate_buf and data_buf directly
	`ifndef SIM
	serial_receive #(.SPEED_MHZ(SPEED_MHZ)) serrx (.clk(hash_clk), .RxD(RxD), .midstate(midstate_vw), .data2(data2_vw));
	// TEST ... hardcode the 1afda099 test data (NB needs DIP_in = 4'h1), will also match on 1e4c2ae6
	// assign midstate_vw = 256'h85a24391639705f42f64b3b688df3d147445123c323e62143d87e1908b3f07ef;
	// data_buf is actually 256 or 96 bits, but no harm giving 512 here (its truncated as appropriate)
	// assign data2_vw = 512'h00000280000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000c513051a02a99050bfec0373;
	`endif

	//// Virtual Wire Output
	reg [31:0]	golden_nonce = 0;
	reg 		serial_send;
	wire		serial_busy;
	
	`ifndef SIM
	serial_transmit #(.SPEED_MHZ(SPEED_MHZ)) sertx (.clk(hash_clk), .TxD(TxD), .send(serial_send), .busy(serial_busy), .word(golden_nonce));
	`endif

 	//// Control Unit
	wire reset = !reset_in;
	wire phase_next;
	wire is_hash;
	wire is_fullhash;

	// HARD CODED CONFIGURATION ...
	// wire range_limit = 1'b0;		// Uncomment to DISABLE range_limit
	wire range_limit = nonce[31:28] == DIP_in[3:0] + 4'd1;	// Limit range (HARD CODED = 1)

	// assign is_hash =(seq_d1[2:0] == 3'd5);	// OLD hashers_11
	// For hashers_3 ...
	// assign is_hash =(seq_d1[4:0] == 5'd21);	// HASHERS_3 increased from [2:0] to [4:0] and change compare from 5 to 21
	// For hashers_6...
	// assign is_hash =(seq_d1[4:0] == 5'd10);	// HASHERS_6 increased from [2:0] to [4:0] and change compare from 5 to 10
	// Now parameterised ...
	assign is_hash =(seq_d1[4:0] == (LOOP-1));	// Increased from [2:0] to [4:0]

	assign is_fullhash = seq_d1[5] && is_hash;	// HASHERS_6 uses [5] cf [3]
	assign phase_next = is_hash ? ~seq_d1[5] : phase;		// Need to ensure phase does not change until
															// get hash else it breaks tx_hash calculation
	// NB applies nonce's in blocks of three ...
	// OLD applies nonce's in blocks of eleven ...
	assign nonce_next =
		(reset | poweron_reset | range_limit) ? { DIP_in[3:0], 28'h0000000 } :
		((~seq_d1[6] | is_fullhash) ? (nonce + 32'd1) : nonce);	// HASHERS_6 uses [6] cf [4]

	// Reconcile nonce and nonce_lsb_d1 from pipeline (ie account for rollover of lsb byte)
	// NB can initially load 11 nonce's into pipeline then one every 12 for approx 150 cycles so 8 bits is plenty
	// NB This does NOT account for full nonce rollover, but this is rare so ignore it.
	// TEST: wire [31:0] golden_nonce_next = (test_prev_midstate != midstate_buf[255:224]) ? midstate_buf[255:224] :
	wire [31:0] golden_nonce_next =
		{ ( (nonce[7] | ~nonce_lsb[7]) ? nonce[31:8] : nonce[31:8] - 24'd1 ), nonce_lsb };		// FIXED v09
		// BUG BUG BUG This is the cause of the triple BAD HASH (approx 1 in 16 matches) BUG BUG BUG
		// { ( (nonce[7] == nonce_lsb[7]) ? nonce[31:8] : nonce[31:8] - 24'd1 ), nonce_lsb };	// BUG, see above !!

	always @ (posedge hash_clk)
	begin
		`ifdef SIM
			//midstate_buf <= 256'h2b3f81261b3cfd001db436cfd4c8f3f9c7450c9a0d049bee71cba0ea2619c0b5;
			//data_buf <= 256'h00000000000000000000000080000000_00000000_39f3001b6b7b8d4dc14bfc31;
			//nonce <= 30411740;
		`else
			// NOW DISABLED, see above
			//midstate_buf <= midstate_vw;
			//data_buf <= data2_vw;
		`endif

		// MJ These register updates occur on posedge hash_clk

		// We hold poweron_reset until reset is pressed. Pressing halt reapplies the initial
		// poweron_reset hold state...
		// poweron_reset <= reset ? 0 : (halt_in ? poweron_reset : 1);	// halt_in is active low

		poweron_reset <= 0;		// EP4CE10 has no reset_in, so clear immediately

		hash_d1 <= hash;
		seq_d1 <= seq;
		nonce_lsb_d1 <= nonce_lsb;
		phase <= phase_next;
		fullhash_d1 <= fullhash;
		
		// Give new data to the hasher
		state <= midstate_buf;
		data <= {nonce_next, data_buf[95:0]};
		nonce <= nonce_next;
		
		// test_prev_midstate <= midstate_buf[255:224];
		
		// NB I removed delays here ... add them back if it breaks critical path timing
		// TEST: if ((is_fullhash && fullhash) || (test_prev_midstate != midstate_buf[255:224]))
		if (is_fullhash && fullhash)
		begin
			// golden_nonce <= { nonce[31:8], nonce_lsb_d1 };		// Unreconciled
			golden_nonce <= golden_nonce_next;
			led_match <= !led_match;
			led_anymatch <= 1'b1;
			if (!serial_busy)
				serial_send <= 1;
		end // if (is_golden_ticket)
		else
		  serial_send <= 0;

`ifdef SIM
		// if (!feedback)
		//	$display ("at feedback_d0 nonce: %8x\nhash: %64x\n", nonce, hash);
		// if (!feedback_d1)
		//	$display ("at feedback_d1 nonce: %8x\nhash: %64x\n", nonce, hash);
		if (is_hash)
			$display ("is_hash: seq %d nonce: %8x\nhash: %64x\n", seq_d1, { nonce[31:8], nonce_lsb_d1 }, hash_d1);
`endif
	end

endmodule

