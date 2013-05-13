/*
*
* EP4CE10_Hashers_11_serial
* 03-Feb-2013 using 5MHz osc input (change both main_pll.v and fpgaminer.sdc but not async_rx/tx)
* 01-Apr-2013 (v08) using 20MHz osc input (changes as above) - runs OK at 100Mhz
* 09-Apr-2013 (v09) Fixed BUG causing triple BAD HASH (grep golden_nonce_next)
* ... 100Mhz took 89 mins (yes eighty-9) to compile (Fmax 71MHz @ 85C ... PLL though)
* ... 120Mhz took 17 mins (yes seventeen) to compile (Fmax 98MHz @ 85C)
* ... 140Mhz took 17 mins (yes seventeen) to compile (Fmax 85MHz @ 85C)
* 13-Apr-2013 Changed to DIP_in=4 range 3 (ie 4..6) for use with xilinx LX_9
* ... 140Mhz took 35 mins to compile (Fmax 69MHz @ 85C). Gives BAD HASHES!!
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

module fpgaminer_top (osc_clk, led_out, RxD, TxD);

	// The LOOP_LOG2 parameter is now ignored and we hard configure LOOP=6 for EP4CE10

	input osc_clk;
	output led_out;
	input RxD;
	output TxD;

	// Hacks to allow use of hashers22 fpgaminer_top.v on EP4CE10
	wire reset_in = 1'b1;
	//wire [3:0] DIP_in = 4'h1;	// TEST start 1 range 1
	wire [3:0] DIP_in = 4'h3;	// With range 4 this gives nonce prefix range 3..6
	//wire [3:0] DIP_in = 4'h4;	// With range 3 this gives nonce prefix range 4..6 (BAD)
	
	// Specific to EP4CE10 ...
	reg led_match = 0;		// DEBUG toggles led on match
	// assign led_out = nonce[24:24];	// DEBUG - use to adjust osc freq
	assign led_out = led_match;	// LIVE 

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
		main_pll pll_blk (osc_clk, hash_clk);
	`else
	 	assign hash_clk = osc_clk;
	`endif
	
	//// Hashers
	
	// HASHERS 11 for EP4CE10 based on hashers 22, vis LOOP=6, NUM_HASHERS=11
	// NB Unlike in hashers 22, we cannot easily synchronise the need to input a nonce
	// every 6 cycles with the 12 cycle (including state_first) feedback delay. Instead we
	// use a sequence variable to track the hash through the pipeline. Top level cnt and feedback
	// are no longer used, but phase is still handled at top level. We need to track the nonce,
	// so pass lowest 8 bits through pipeline and reconcile with top 24 bits later.
	
	// Output of sha256_transform
	wire [255:0] hash;
	wire [4:0] seq;
	wire [7:0] nonce_lsb;
	wire fullhash;
	
	// Deleayed output of sha256_transform
	reg [255:0] hash_d1;
	reg [4:0] seq_d1 = 0;		// Needs to be init to 0 else breaks nonce_next in simulation
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
	sha256_transform uut (
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


	// No need to simulate serial_receive and serial_transmit as we set midstate_buf and data_buf directly
	`ifndef SIM
	serial_receive serrx (.clk(hash_clk), .RxD(RxD), .midstate(midstate_vw), .data2(data2_vw));
	`endif

	//// Virtual Wire Output
	reg [31:0]	golden_nonce = 0;
	reg 		serial_send;
	wire		serial_busy;
	
	`ifndef SIM
	serial_transmit sertx (.clk(hash_clk), .TxD(TxD), .send(serial_send), .busy(serial_busy), .word(golden_nonce));
	`endif

 	//// Control Unit
	wire reset = !reset_in;
	wire phase_next;
	wire is_hash;
	wire is_fullhash;

	// HARD CODED CONFIGURATION ...
	// wire range_limit = 1'b0;		// Uncomment to DISABLE range_limit
	// wire range_limit = nonce[31:28] == DIP_in[3:0] + 4'd3;	// Limit range (HARD CODED = 3) - BAD
	wire range_limit = nonce[31:28] == DIP_in[3:0] + 4'd4;	// Limit range (HARD CODED = 4)

	assign is_hash =(seq_d1[2:0] == 3'd5);
	assign is_fullhash = seq_d1[3] && is_hash;
	assign phase_next = is_hash ? ~seq_d1[3] : phase;		// Need to ensure phase does not change until
															// get hash else it breaks tx_hash calculation
	// NB applies nonce's in blocks of eleven ...
	assign nonce_next =
		(reset | poweron_reset | range_limit) ? { DIP_in[3:0], 28'h0000000 } :
		((~seq_d1[4] | is_fullhash) ? (nonce + 32'd1) : nonce);

	// Reconcile nonce and nonce_lsb_d1 from pipeline (ie account for rollover of lsb byte)
	// NB can initially load 11 nonce's into pipeline then one every 12 for approx 150 cycles so 8 bits is plenty
	// NB This does NOT account for full nonce rollover, but this is rare so ignore it.
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

		// NB I removed delays here ... add them back if it breaks critical path timing
		if (is_fullhash && fullhash)
		begin
			// golden_nonce <= { nonce[31:8], nonce_lsb_d1 };		// Unreconciled
			golden_nonce <= golden_nonce_next;
			led_match <= !led_match;
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

