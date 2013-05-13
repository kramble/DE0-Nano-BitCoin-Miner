// Testbench for fpgaminer_top.v

`timescale 1ns/1ps

module test_fpgaminer_top ();

	reg clk = 1'b0;
	reg RxD = 1'b1;	// Active low
	wire led_out;
	wire TxD;
	
	fpgaminer_top uut (clk, led_out, RxD, TxD);

	reg [31:0] cycle = 32'd0;

	initial begin
		clk = 0;

		#100
		// v9 test of work_BAD_30d9da77 from cpuhash on tvpi (see reversehex.cpp)
		// NB BUGGY code gives golden nonce 30d9da77 however correct nonce is 30d9db77 (0x100 larger)
		//  ... NOT a FULL test of the fix, more cases are required (including the ORIGINAL reference case below)
		//      but this will do for now (will test it in live FPGA ... lazy!!)
		
		// C:\altera\MJ-Projects\EP4CE10_Hashers_11_Serial>reversehex
		// e1531a6da87888e644e1f97c0389de5e51a3d2a73117c0988a7c51ecd58085d2
		// 00000280000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000be2f021aa0726351545aad2efc84ba489a8b2c067d05a0c6b490d43a0aaeecf3c4b62c3f0ce24ee900000000d9010000294057cea20385f349ff27265dcd9ca4bc1ae704784ca88802000000

	//	uut.midstate_buf = 256'he1531a6da87888e644e1f97c0389de5e51a3d2a73117c0988a7c51ecd58085d2;
		// data_buf is actually 256 or 96 bits, but no harm giving 512 here (its truncated as appropriate)
	//	uut.data_buf = 512'h00000280000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000be2f021aa0726351545aad2e;

		// NB We simulate CORRECT golden nonce 30d9db77 (BUGGY code will report golden nonce 30d9da77, ie 0x100 less)
	//	uut.nonce = 32'h30d9db77 - 3;	// fullhash flag at 1560nS and golden_nonce 30d9db77 at 1570nS
		

		// ====================================================================================================
		
		// ORIGINAL Test data (v5 and later) ...
		uut.midstate_buf = 256'h85a24391639705f42f64b3b688df3d147445123c323e62143d87e1908b3f07ef;
		// data_buf is actually 256 or 96 bits, but no harm giving 512 here (its truncated as appropriate)
		uut.data_buf = 512'h00000280000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000c513051a02a99050bfec0373;
		
		// v5 results ...
		// uut.nonce = 32'h1afda099;	// NO MATCH, but we do see nonce_lsb output for 99
										// Perhaps data and nonce_lsb are out of sync?
										// Or maybe midstate has not fully propagated yet (more likely)
		// uut.nonce = 32'h1afda098;	// fullhash flag at 1540nS and golden_nonce 1afda099 at 1550nS
		// uut.nonce = 32'h1afda097;	// fullhash flag at 1550nS and golden_nonce 1afda099 at 1560nS
		uut.nonce = 32'h1afda096;	// fullhash flag at 1560nS and golden_nonce 1afda099 at 1570nS [REFERENCE nonce]
		// uut.nonce = 32'h1afda095;	// fullhash flag at 1570nS and golden_nonce 1afda099 at 1580nS
		// uut.nonce = 32'h1afda090;	// fullhash flag at 1620nS and golden_nonce 1afda099 at 1630nS
		// uut.nonce = 32'h1afda08f;	// fullhash flag at 1630nS and golden_nonce 1afda099 at 1640nS
		// uut.nonce = 32'h1afda08e;	// fullhash flag at 1630nS and golden_nonce 1afda099 at 1640nS
		// uut.nonce = 32'h1afda08d;	// fullhash flag at 2970nS and golden_nonce 1afda099 at 2980nS
		// uut.nonce = 32'h1afda08c;	// fullhash flag at 2980nS and golden_nonce 1afda099 at 2890nS
		// uut.nonce = 32'h1afda08b;	// fullhash flag at 2990nS and golden_nonce 1afda099 at 3000nS
		
		while(1)
		begin
			#5 clk = 1; #5 clk = 0;
		end
	end


	always @ (posedge clk)
	begin
		cycle <= cycle + 32'd1;
	end

endmodule

