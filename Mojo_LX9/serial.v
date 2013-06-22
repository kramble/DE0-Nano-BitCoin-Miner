// by teknohog, replaces virtual_wire by rs232
/*
 * 20-Jun-2013 ... Now configurable for either kramble or teknokog (icarus) protocol. Use parameter ICARUS.
 * 15-Nov-2012 ...
 * Removed 20 bytes (160 bits) from async_receiver.v with matching changes in fpgaminer_top.v
 * Added timeout counter to reset if demux_state is active, but no data received in approx 80ms
 */

module serial_receive # (
parameter SPEED_MHZ = 50,	// Must match PLL hash_clk
parameter ICARUS = 0,		// Use 0 for kramble protocol (44 bytes). Set to 1 for icarus (64 bytes).
parameter KRAMBLE_TEST = 0	// Do not use (enables 4800 baud serial)
)
(clk, RxD, midstate, data2, load_flag);
   input      clk;
   input      RxD;
   
   wire       RxD_data_ready;
   wire [7:0] RxD_data;

   reg rst = 1'b1;

   // async_receiver #(.SPEED_MHZ(SPEED_MHZ)) deserializer(.clk(clk), .RxD(RxD), .RxD_data_ready(RxD_data_ready), .RxD_data(RxD_data));

   // Increased CTR_SIZE from 7 to 8 to support clocks > 63MHz
   serial_rx #(.CLK_PER_BIT(KRAMBLE_TEST?208*SPEED_MHZ:2*SPEED_MHZ), .CTR_SIZE(KRAMBLE_TEST?16:8)) serial_rx (
	.clk(clk),
	.rst(rst),
	.rx(RxD),
	.data(RxD_data),
	.new_data(RxD_data_ready)
);

   output [255:0] midstate;
   output [95:0] data2;
   output load_flag;		// Toggles when data is loaded
   
   // 256 bits midstate + 256 bits data at the same time = 64 bytes

   // Might be a good idea to add some fixed start and stop sequences,
   // so we really know we got all the data and nothing more. If a
   // test for these fails, should ask for new data, so it needs more
   // logic on the return side too. The check bits could be legible
   // 7seg for quick feedback :)
   
   reg [((ICARUS == 1)?511:351):0] input_buffer;
   reg [351:0] input_copy;
   reg [6:0]   demux_state = 7'b000000;
   reg [23:0]  demux_timeout = 23'd0;		// MJ Timeout if idle & reset state
   reg load_flag_reg = 0;					// MJ Flag toggles when data is loaded
   
   assign load_flag = load_flag_reg;
	
	// NB While not absolutely essential (could just live with invalid data during loading),
	// using input_copy buffer costs almost nothing as registers are present in LE's anyway.
	
   assign midstate = input_copy[351:96];
   assign data2 = input_copy[95:0];
   
   // we probably don't need a busy signal here, just read the latest
   // complete input that is available.
   
   always @(posedge clk)
		rst <= 1'b0;

	   
   always @(posedge clk)
		case (demux_state)
			((ICARUS == 1) ? 7'b1000000 :	// teknohog/icarus protocol 64 bytes
			7'b0101100 ):					// kramble protocol 44 bytes
			begin
				if(ICARUS == 1)
					input_copy <= { input_buffer[511:256], input_buffer[95:0] };
				else
					input_copy <= input_buffer;
				demux_state <= 0;
				demux_timeout <= 0;
				load_flag_reg <= !load_flag_reg;	// Toggle the flag to indicate data loaded
			end
       
			default:
				if (RxD_data_ready)
				begin
					input_buffer <= input_buffer << 8;
					input_buffer[7:0] <= RxD_data;
					demux_state <= demux_state + 6'd1;
					demux_timeout <= 0;
				end
				else
				begin
					demux_timeout <= demux_timeout + 24'd1;
					// Timeout after 8 million clock at 100Mhz is 80ms, which should be
					// OK for all sensible clock speeds eg 20MHz is 400ms, 200MHz is 40ms
					// TODO ought to parameterise, but this should be fine (4800 baud is
					// one byte every 2ms approx)
					if (demux_timeout & 24'h800000)
					begin
						demux_state <= 0;
						demux_timeout <= 0;
					end
				end
		endcase // case (demux_state)
   
endmodule // serial_receive

module serial_transmit  # (
parameter SPEED_MHZ = 50,	// Must match PLL hash_clk
parameter KRAMBLE_TEST = 0	// Do not use (enables 4800 baud serial)
)
(clk, TxD, busy, send, word);

   // split 4-byte output into bytes

   wire TxD_start;
   wire TxD_busy;
   
   reg rst = 1'b1;
   reg [7:0]  out_byte;
   reg        serial_start;
   reg [3:0]  mux_state = 4'b0000;

   assign TxD_start = serial_start;

   input      clk;
   output     TxD;
   
   input [31:0] word;
   input 	send;
   output 	busy;

   reg [31:0] 	word_copy;
   
   assign busy = (|mux_state);

   always @(posedge clk)
		rst <= 1'b0;

   always @(posedge clk)
     begin
	/*
	case (mux_state)
	  4'b0000:
	    if (send)
	      begin
		 mux_state <= 4'b1000;
		 word_copy <= word;
	      end  
	  4'b1000: out_byte <= word_copy[31:24];
	  4'b1010: out_byte <= word_copy[23:16];
	  4'b1100: out_byte <= word_copy[15:8];
	  4'b1110: out_byte <= word_copy[7:0];
	  default: mux_state <= 4'b0000;
	endcase // case (mux_state)
	 */

	// Testing for busy is problematic if we are keeping the
	// module busy all the time :-/ So we need some wait stages
	// between the bytes.

	if (!busy && send)
	  begin
	     mux_state <= 4'b1000;
	     word_copy <= word;
	  end  

	else if (mux_state[3] && ~mux_state[0] && !TxD_busy)
	  begin
	     serial_start <= 1;
	     mux_state <= mux_state + 4'd1;

	     out_byte <= word_copy[31:24];
	     word_copy <= (word_copy << 8);
	  end
	
	// wait stages
	else if (mux_state[3] && mux_state[0])
	  begin
	     serial_start <= 0;
	     if (!TxD_busy) mux_state <= mux_state + 4'd1;
	  end
     end

   // async_transmitter #(.SPEED_MHZ(SPEED_MHZ)) serializer(.clk(clk), .TxD(TxD), .TxD_start(TxD_start), .TxD_data(out_byte), .TxD_busy(TxD_busy));

   // Increased CTR_SIZE from 7 to 8 to support clocks > 63MHz
   serial_tx #(.CLK_PER_BIT(KRAMBLE_TEST?208*SPEED_MHZ:2*SPEED_MHZ), .CTR_SIZE(KRAMBLE_TEST?16:8)) serial_tx (
	.clk(clk),
	.rst(rst),
	.tx(TxD),
	.block(1'b0),
	.busy(TxD_busy),
	.data(out_byte),
	.new_data(TxD_start)
);

endmodule // serial_send
