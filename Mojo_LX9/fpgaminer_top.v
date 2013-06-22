/*
*
* Xilinx LX_9 Mojo Port
*
* Copyright (c) 2011 fpgaminer@bitcoin-mining.com
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
	// CONFIGURATION - Do NOT change these here, set them in the calling module eg mojo-top.v
	parameter NUM_HASHERS = 3,		// 	NB specify 3,22 or 6,11 ONLY
	parameter LOOP = 22,
	// parameter NUM_HASHERS = 6,	// This WILL build, but its slow and needs XIL_PAR_ENABLE_LEGALIZER=1
	// parameter LOOP = 11,	
	parameter SPEED_MHZ = 50,	// PLL output clock, adjust as desired (up to 100MHz seems to work OK)
	parameter ICARUS = 0,		// Use 0 for kramble protocol (44 bytes). Set to 1 for icarus (64 bytes).
	// The following are for test and simulation ...
	parameter KRAMBLE_TEST = 0,	// Do not use (enables 4800 baud serial, which is NOT a Mojo feature)
	parameter SIM_SERIAL = 0,	// Enables serial_receive in simulation
	parameter SIM_SERIAL_NORESET = 0	// Disables nonce reset in simulation (to speed up cgminer sim)
	)
	(osc_clk, RxD, TxD, led1, led2, led3);

	input osc_clk;
	input RxD;
	output TxD;
	output led1;
	output led2;
	output led3;

	wire reset_in = 1'b1;	// UNUSED so hard code to 1 (NB active low)
	
	reg [255:0] state = 0;
	reg [127:0] data = 0;
	reg [31:0] nonce = 32'h00000000;
	wire [31:0] nonce_next;

	reg led_anymatch = 0;	// DEBUG set on a match (stays set)
	reg led_match = 0;		// DEBUG toggles led on match
	assign led1 = nonce[24];
	assign led2 = led_anymatch;
	assign led3 = led_match;


	//// PLL
	wire hash_clk;
	`ifndef SIM
   		main_pll #(.SPEED_MHZ(SPEED_MHZ)) pll_blk (.CLKIN_IN(osc_clk), .MJ_CLK_FX_OUT(hash_clk));
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
	wire [6:0] seq;
	wire [7:0] nonce_lsb;
	wire fullhash;
	
	// Deleayed output of sha256_transform
	reg [255:0] hash_d1;
	reg [6:0] seq_d1 = 0;		// Needs to be init to 0 else breaks nonce_next in simulation
	reg [7:0] nonce_lsb_d1 = 0;	// May be able to get away with 6 bits here, but its probably in RAM so no need

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
	wire load_flag;

	// NB Since already latched in serial_receive, can we get rid of these latches (or just use for simulation)? TODO !!
	
	// This is rather clunky as I want to use parameter SIM_SERIAL to control compilation, and its not as
	// obvious as it looks eg "if (SIM_SERIAL)" will silently fail if used to instantiate serial_receive!
	`ifdef SIM
	wire [255:0] midstate_buf_w;
	wire [95:0] data_buf_w;
	reg [255:0] midstate_buf = 0;
	reg [95:0] data_buf = 0;
	wire load_flag_mux;
	assign load_flag_mux = (SIM_SERIAL) ? 0 : load_flag;
	`else
	wire [255:0] midstate_buf_w;
	wire [95:0] data_buf_w;
	wire [255:0] midstate_buf;
	wire [95:0] data_buf;
	assign midstate_buf = midstate_vw;
	assign data_buf = data2_vw;
	wire load_flag_mux;
	assign load_flag_mux = load_flag;
	`endif

	assign midstate_buf_w = (SIM_SERIAL) ? midstate_vw : midstate_buf;
	assign data_buf_w = (SIM_SERIAL) ? data2_vw : data_buf;
	
	serial_receive #(.SPEED_MHZ(SPEED_MHZ), .ICARUS(ICARUS), .KRAMBLE_TEST(KRAMBLE_TEST)) serrx (.clk(hash_clk), .RxD(RxD), .midstate(midstate_vw), .data2(data2_vw), .load_flag(load_flag));

	// TEST ... hardcode the 1afda099 test data (NB needs DIP_in = 4'h1), will also match on 1e4c2ae6
	// assign midstate_vw = 256'h85a24391639705f42f64b3b688df3d147445123c323e62143d87e1908b3f07ef;
	// data_buf is actually 256 or 96 bits, but no harm giving 512 here (its truncated as appropriate)
	// assign data2_vw = 512'h00000280000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000c513051a02a99050bfec0373;
	

	//// Virtual Wire Output
	reg [31:0]	golden_nonce = 0;
	reg 		serial_send;
	wire		serial_busy;
	
	// Now including serial_transmit in simulation
	// `ifndef SIM
	serial_transmit #(.SPEED_MHZ(SPEED_MHZ), .KRAMBLE_TEST(KRAMBLE_TEST)) sertx (.clk(hash_clk), .TxD(TxD), .send(serial_send), .busy(serial_busy), .word(golden_nonce));
	// `endif

 	//// Control Unit
	reg load_flag_mux_d1 = 1'b0;
	wire reset = !reset_in | ((ICARUS&&!SIM_SERIAL_NORESET)?(load_flag_mux_d1!=load_flag_mux):1'b0);	// Reset nonce on load else cgminer fails to detect icarus
	wire phase_next;
	wire is_hash;
	wire is_fullhash;

	assign is_hash =(seq_d1[4:0] == (LOOP-1));

	assign is_fullhash = seq_d1[5] && is_hash;
	assign phase_next = is_hash ? ~seq_d1[5] : phase;		// Need to ensure phase does not change until
															// get hash else it breaks tx_hash calculation
	// NB applies nonce's in blocks of six (or three) ...
	// BUG?? Simulating with 3 hashers, nonce increments by 4 (no matter for mining as nonces
	// are indeterminate, but this may affect testing).
	assign nonce_next =
		reset ? 32'h00000000 :
		((~seq_d1[6] | is_fullhash) ? (nonce + 32'd1) : nonce);

	// Reconcile nonce and nonce_lsb_d1 from pipeline (ie account for rollover of lsb byte)
	// NB can initially load 6 nonce's into pipeline then one every 22 for approx 132 cycles so 8 bits is plenty
	// NB This does NOT account for full nonce rollover, but this is rare so ignore it.
	wire [31:0] golden_nonce_next =
		{ ( (nonce[7] | ~nonce_lsb[7]) ? nonce[31:8] : nonce[31:8] - 24'd1 ), nonce_lsb };		// FIXED v09

	always @ (posedge hash_clk)
	begin
		hash_d1 <= hash;
		seq_d1 <= seq;
		nonce_lsb_d1 <= nonce_lsb;
		phase <= phase_next;
		load_flag_mux_d1 <= load_flag_mux;
		
		// Give new data to the hasher
		state <= midstate_buf_w;
		data <= {nonce_next, data_buf_w[95:0]};
		nonce <= nonce_next;
		
		// NB I removed delays here ... add them back if it breaks critical path timing
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
		if (is_hash)
			$display ("is_hash: seq %d nonce: %8x\nhash: %64x\n", seq_d1, { nonce[31:8], nonce_lsb_d1 }, hash_d1);
`endif
	end

endmodule
