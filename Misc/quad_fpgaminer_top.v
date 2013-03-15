/*
********************************************************************************
* MJ This file is intended to illustrate a discussion point, not for actual use
*    see https://bitcointalk.org/index.php?topic=9047.msg1627840#msg1627840
********************************************************************************
* 
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
* 
*/


`timescale 1ns/1ps

module fpgaminer_top (osc_clk);

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
	// hash (except when LOOP_LOG2 == 0 or 1, where the offset is 131 or
	// 66 respectively).
	localparam [31:0] GOLDEN_NONCE_OFFSET = (32'd1 << (7 - LOOP_LOG2)) + 32'd1;

	input osc_clk;


	//// 
	reg [255:0] state = 0;
	reg [511:0] data0 = 0;
	reg [511:0] data1 = 0;
	reg [511:0] data2 = 0;
	reg [511:0] data3 = 0;
	reg [29:0] nonce = 30'h00000000;


	//// PLL
	wire hash_clk;
	`ifndef SIM
		main_pll pll_blk (osc_clk, hash_clk);
	`else
		assign hash_clk = osc_clk;
	`endif


	//// Hashers
	wire [255:0] hash0a, hash0b;
	wire [255:0] hash1a, hash1b;
	wire [255:0] hash2a, hash2b;
	wire [255:0] hash3a, hash3b;
	reg [5:0] cnt = 6'd0;
	reg feedback = 1'b0;

	sha256_transform #(.LOOP(LOOP)) uut0a (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(state),
		.rx_input(data0),
		.tx_hash(hash0a)
	);
	sha256_transform #(.LOOP(LOOP)) uut0b (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(256'h5be0cd191f83d9ab9b05688c510e527fa54ff53a3c6ef372bb67ae856a09e667),
		.rx_input({256'h0000010000000000000000000000000000000000000000000000000080000000, hash0a}),
		.tx_hash(hash0b)
	);

	sha256_transform #(.LOOP(LOOP)) uut1a (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(state),
		.rx_input(data1),
		.tx_hash(hash1a)
	);
	sha256_transform #(.LOOP(LOOP)) uut1b (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(256'h5be0cd191f83d9ab9b05688c510e527fa54ff53a3c6ef372bb67ae856a09e667),
		.rx_input({256'h0000010000000000000000000000000000000000000000000000000080000000, hash1a}),
		.tx_hash(hash1b)
	);
	
	sha256_transform #(.LOOP(LOOP)) uut2a (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(state),
		.rx_input(data2),
		.tx_hash(hash2a)
	);
	sha256_transform #(.LOOP(LOOP)) uut2b (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(256'h5be0cd191f83d9ab9b05688c510e527fa54ff53a3c6ef372bb67ae856a09e667),
		.rx_input({256'h0000010000000000000000000000000000000000000000000000000080000000, hash2a}),
		.tx_hash(hash2b)
	);

	sha256_transform #(.LOOP(LOOP)) uut3a (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(state),
		.rx_input(data3),
		.tx_hash(hash3a)
	);
	sha256_transform #(.LOOP(LOOP)) uut3b (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(256'h5be0cd191f83d9ab9b05688c510e527fa54ff53a3c6ef372bb67ae856a09e667),
		.rx_input({256'h0000010000000000000000000000000000000000000000000000000080000000, hash3a}),
		.tx_hash(hash3b)
	);

	//// Virtual Wire Control
	reg [255:0] midstate_buf = 0, data_buf = 0;
	wire [255:0] midstate_vw, data2_vw;

	`ifndef SIM
		virtual_wire # (.PROBE_WIDTH(0), .WIDTH(256), .INSTANCE_ID("STAT")) midstate_vw_blk(.probe(), .source(midstate_vw));
		virtual_wire # (.PROBE_WIDTH(0), .WIDTH(256), .INSTANCE_ID("DAT2")) data2_vw_blk(.probe(), .source(data2_vw));
	`endif


	//// Virtual Wire Output
	reg [31:0] golden_nonce = 0;
	
	`ifndef SIM
		virtual_wire # (.PROBE_WIDTH(32), .WIDTH(0), .INSTANCE_ID("GNON")) golden_nonce_vw_blk (.probe(golden_nonce), .source());
		virtual_wire # (.PROBE_WIDTH(32), .WIDTH(0), .INSTANCE_ID("NONC")) nonce_vw_blk (.probe(nonce), .source());
	`endif


	//// Control Unit
	reg is_golden_ticket0 = 1'b0;
	reg is_golden_ticket1 = 1'b0;
	reg is_golden_ticket2 = 1'b0;
	reg is_golden_ticket3 = 1'b0;
	reg feedback_d1 = 1'b1;
	wire [5:0] cnt_next;
	wire [29:0] nonce_next;
	wire feedback_next;
	`ifndef SIM
		wire reset;
		assign reset = 1'b0;
	`else
		reg reset = 1'b0;	// NOTE: Reset is not currently used in the actual FPGA; for simulation only.
	`endif

	assign cnt_next =  reset ? 6'd0 : (LOOP == 1) ? 6'd0 : (cnt + 6'd1) & (LOOP-1);
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// on 1..LOOP-1, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount
	assign feedback_next = (LOOP == 1) ? 1'b0 : (cnt_next != {(LOOP_LOG2){1'b0}});
	assign nonce_next =
		reset ? 30'd0 :
		feedback_next ? nonce : (nonce + 30'd1);

	wire[1:0] nonceprefix;
	wire[31:0] fullnonce;
	assign nonceprefix = is_golden_ticket0 ? 2'd0 : is_golden_ticket1 ? 2'd1 : is_golden_ticket2 ? 2'd2 : 2'd3;
	assign fullnonce = {nonceprefix,nonce};
	
	always @ (posedge hash_clk)
	begin
		`ifdef SIM
			//midstate_buf <= 256'h2b3f81261b3cfd001db436cfd4c8f3f9c7450c9a0d049bee71cba0ea2619c0b5;
			//data_buf <= 256'h00000000000000000000000080000000_00000000_39f3001b6b7b8d4dc14bfc31;
			//nonce <= 30411740;
		`else
			midstate_buf <= midstate_vw;
			data_buf <= data2_vw;
		`endif

		cnt <= cnt_next;
		feedback <= feedback_next;
		feedback_d1 <= feedback;

		// Give new data to the hasher
		state <= midstate_buf;
		data0 <= {384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, {2'd0,nonce_next}, data_buf[95:0]};
		data1 <= {384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, {2'd1,nonce_next}, data_buf[95:0]};
		data2 <= {384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, {2'd2,nonce_next}, data_buf[95:0]};
		data3 <= {384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, {2'd3,nonce_next}, data_buf[95:0]};
		nonce <= nonce_next;


		// Check to see if the last hash generated is valid.
		is_golden_ticket0 <= (hash0b[255:224] == 32'h00000000) && !feedback_d1;
		is_golden_ticket1 <= (hash1b[255:224] == 32'h00000000) && !feedback_d1;
		is_golden_ticket2 <= (hash2b[255:224] == 32'h00000000) && !feedback_d1;
		is_golden_ticket3 <= (hash3b[255:224] == 32'h00000000) && !feedback_d1;

		if(is_golden_ticket0 | is_golden_ticket1 | is_golden_ticket2 | is_golden_ticket3)
		begin
			// TODO: Find a more compact calculation for this
			if (LOOP == 1)
				golden_nonce <= fullnonce - 32'd131;
			else if (LOOP == 2)
				golden_nonce <= fullnonce - 32'd66;
			else
				golden_nonce <= fullnonce - GOLDEN_NONCE_OFFSET;
		end
`ifdef SIM
		if (!feedback_d1)
			$display ("nonce: %8x\nhash0b: %64x\nhash1b: %64x\n\nhash2b: %64x\nhash3b: %64x\n", fullnonce, hash0b, hash1b, hash2b, hash3b);
`endif
	end

endmodule

