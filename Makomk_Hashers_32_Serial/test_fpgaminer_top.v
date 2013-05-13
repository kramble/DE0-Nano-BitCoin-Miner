// Testbench for fpgaminer_top.v

`timescale 1ns/1ps

module test_fpgaminer_top ();

	reg clk = 1'b0;
	reg reset_in = 1'b1;	// Active low
	reg halt_in = 1'b1;		// Active low
	reg [3:0] DIP_in = 4'd0;
	reg RxD = 1'b0;
	reg RxD_slave = 1'b0;
	wire [7:0]LEDS_out;
	wire TxD, TxD_slave, bias1, bias2, bias3, bias4;
	
	// halt_in complicates things, need to toggle reset_in in order to clear the poweron_reset state
	fpgaminer_top uut (clk, reset_in, halt_in, DIP_in, LEDS_out,
	RxD, TxD, bias, bias2, RxD_slave, TxD_slave, bias3, bias4);

	reg [31:0] cycle = 32'd0;

	initial begin
		clk = 0;

		#100
		// Test data ...
		uut.midstate_buf = 256'h85a24391639705f42f64b3b688df3d147445123c323e62143d87e1908b3f07ef;
		// data_buf is actually 256 or 96 bits, but no harm giving 512 here (its truncated as appropriate)
		uut.data_buf = 512'h00000280000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000c513051a02a99050bfec0373;
		// This was prior to adding halt_in poweron_reset logic, but it is immediately reset, so we reapply it
		// a few cycles later (see below)
		uut.nonce = 32'h1afda098 - 2;
		
		while(1)
		begin
			#5 clk = 1; #5 clk = 0;
			
			// halt_in complicates things, need to toggle reset_in in order to clear the poweron_reset state
			if (cycle == 1) reset_in <= 0;	// Assert reset
			if (cycle == 2) reset_in <= 1;	// De-assert reset
			// Also need to reapply the initial nonce (NB reset is delayed by one, so wait a couple of cycles)
			if (cycle == 6) uut.nonce = 32'h1afda098 - 2;
			// ... Match at around 1500-1600nS nonce 1afda0af and one clock later it gives golden_nonce 1afda099.

		end
	end


	always @ (posedge clk)
	begin
		cycle <= cycle + 32'd1;
	end

endmodule

