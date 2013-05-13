/*
*
* Copyright (c) 2011 fpgaminer@bitcoin-mining.com
*           (c) 2012 Aidan Thornton
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

MJ (kramble)
------------
Swapped out USB interface code for serial interface.
Added poweron_reset, DIP_in and range_limit=8

120 Mhz build 55 mins 96% used fmax~120MHz @ 85C
140 Mhz build 65 mins 96% used fmax=123MHz @ 85C / 138MHz @ 0C
 80 Mhz build incomplete after 2+ hours.
 
*/


`timescale 1ns/1ps

module fpgaminer_top (osc_clk, reset_in, halt_in, DIP_in, LEDS_out,
	RxD, TxD, bias, bias2, RxD_slave, TxD_slave, bias3, bias4);

	// The LOOP_LOG2 parameter determines how unrolled the SHA-256
	// calculations are. For example, a setting of 0 will completely
	// unroll the calculations, resulting in 128 rounds and a large, but
	// fast design.
	//
	// A setting of 1 will result in 64 rounds, with half the size and
	// half the speed. 2 will be 32 rounds, with 1/4th the size and speed.
	// And so on.
	//
	// Valid range: [0, 5]
`ifdef CONFIG_LOOP_LOG2
	parameter LOOP_LOG2 = `CONFIG_LOOP_LOG2;
`else
	parameter LOOP_LOG2 = 0;
`endif

	// No need to adjust these parameters
	localparam [5:0] LOOP = (6'd1 << LOOP_LOG2);
	// The nonce will always be larger at the time we discover a valid
	// hash. This is its offset from the nonce that gave rise to the valid
	// hash (except when LOOP_LOG2 == 0, where the offset is 66).
	localparam [31:0] GOLDEN_NONCE_OFFSET = (32'd1 << (6 - LOOP_LOG2)) + 32'd1;

	input osc_clk;
	input reset_in;
	input halt_in;
	input [3:0] DIP_in;

	input RxD;				// Pin_D3 GPIO_00 End pin, JP1 outside row
	output TxD;				// Pin_C3 GPIO_01 Second to end pin, JP1 outside row
	output bias;			// Pin_A3 GPIO_03 Third to end pin, JP1 outside row
	output bias2;			// Pin_B4 GPIO_05 Fourth to end pin, JP1 outside row

	// We use the pins on the USB/PowerConnector end of the board (just like JP1)
	// CARE the JP2 header pin 1 is on the OPPOSITE end of the board to JP1 so
	// we need to use the pins on the bottom right in the DE0-Manual diagram p17.
	input RxD_slave;		// Pin_J14 GPIO_133 End pin, JP2 outside row (NB use weak pullup)
	output TxD_slave;		// Pin_K15 GPIO_131 Second to end pin, JP2 outside row
	output bias3;			// Pin_L13 GPIO_129 Third to end pin, JP2 outside row
	output bias4;			// Pin_N14 GPIO_127 Fourth to end pin, JP2 outside row

	output [7:0] LEDS_out;

	assign bias = 1'b1;		// Logic high output
	assign bias2 = 1'b1;	// Logic high output
	assign bias3 = 1'b1;	// Logic high output
	assign bias4 = 1'b1;	// Logic high output
	
	assign TxD_slave = RxD;	// Passthrough work to slave

	//// 
	reg [255:0] state = 0;
	reg [127:0] data = 0;
	reg [31:0] nonce = 32'h00000000;

	assign LEDS_out = nonce[31:24];

	//// PLL
	wire hash_clk;
	`ifndef SIM
		main_pll pll_blk (osc_clk, hash_clk);
	`else
		assign hash_clk = osc_clk;
	`endif


	//// Hashers
	wire [255:0] hash;
	reg [6:0] cnt = 7'd0;
	reg feedback = 1'b0;
	reg internal_feedback = 1'b0;
	reg feedback_d1 = 1'b0;

	sha256_transform #(.LOOP(LOOP), .NUM_ROUNDS(64)) uut (
		.clk(hash_clk),
		.feedback(internal_feedback),
		.fb_second(cnt[LOOP_LOG2]),
		.cnt(cnt[5:0] & (LOOP-7'd1)),
		.rx_state_1(state),
		.rx_input_1({384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, data}),
		.tx_hash(hash)
	);

	//// Virtual Wire Control
	wire [255:0] midstate_vw;
	wire [95:0] data2_vw;

	// NB Since already latched in serial_receive, can we get rid of these latches (just use for simulation)
	`ifdef SIM
	reg [255:0] midstate_buf = 0;
	reg [95:0] data_buf = 0;
	`else
	wire [255:0] midstate_buf = midstate_vw;
	wire [95:0] data_buf = data2_vw;
	`endif

	`ifndef SIM
	serial_receive serrx (.clk(hash_clk), .RxD(RxD), .midstate(midstate_vw), .data2(data2_vw));
	`endif

	//// Virtual Wire Output
	reg [31:0]	golden_nonce = 0;
	reg 		serial_send;
	wire		serial_busy;
	
   wire TxD_internal;
	`ifndef SIM
   serial_transmit sertx (.clk(hash_clk), .TxD(TxD_internal), .send(serial_send), .busy(serial_busy), .word(golden_nonce));
	`endif

   assign TxD = TxD_internal & RxD_slave;

	//// Control Unit
	reg poweron_reset = 1'b1;
	reg is_golden_ticket = 1'b0;
	wire [6:0] cnt_next;
	wire [31:0] nonce_next;
	wire feedback_next;
	wire internal_feedback_next;
	reg reset_d1 = 1'b1;
	wire reset = !reset_in;

	assign cnt_next =  reset ? 7'd0 : (cnt + 7'd1) & {(LOOP-1), 1'b1};
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// on 1..LOOP-1, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount
	assign feedback_next = (cnt_next != {(LOOP_LOG2){1'b0}});
   assign internal_feedback_next = ((cnt_next & {1'b1, (LOOP-1)}) != {(LOOP_LOG2){1'b0}});


	// HARD CODED CONFIGURATION ...
	// wire range_limit = 1'b0;		// Uncomment to DISABLE range_limit
	wire range_limit = nonce[31:28] == DIP_in[3:0] + 4'd8;	// Limit range (HARD CODED) = range 8
	
	assign nonce_next =
		(reset | poweron_reset | range_limit) ? { DIP_in[3:0], 28'h000000 } :
		feedback_next ? nonce : (nonce + 32'd1);

	
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

		// We hold poweron_reset until reset is pressed. Pressing halt reapplies the initial
		// poweron_reset hold state.
		poweron_reset <= reset ? 0 : (halt_in ? poweron_reset : 1);		// halt_in is active low
		reset_d1 <= reset | poweron_reset;

		cnt <= cnt_next;
		feedback <= feedback_next;
		internal_feedback <= internal_feedback_next;
		feedback_d1 <= feedback;

		// Give new data to the hasher
		state <= midstate_buf;
		data <= {nonce_next, data_buf[95:0]};
		nonce <= nonce_next;

		// Check to see if the last hash generated is valid.
		is_golden_ticket <= (hash[255:224] == 32'ha41f32e7) && !feedback_d1;
		if(is_golden_ticket)
		begin
			// TODO: Find a more compact calculation for this
			if (LOOP == 1)
				golden_nonce <= nonce - 32'd66;
			else
				golden_nonce <= nonce - GOLDEN_NONCE_OFFSET;
			if (!serial_busy)
				serial_send <= 1;
		end // if (is_golden_ticket)
		else
		  serial_send <= 0;
`ifdef SIM
		if (!feedback_d1)
			$display ("nonce: %8x\nhash: %64x\n", nonce, hash);
`endif
	end

endmodule