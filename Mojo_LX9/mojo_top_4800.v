module mojo_top(
/*
    input clk,
    input rst_n,
    input cclk,
    output[7:0]led,
    output spi_miso,
    input spi_ss,
    input spi_mosi,
    input spi_sck,
    output [3:0] spi_channel,
    input avr_tx,
    output avr_rx,
    input avr_rx_busy
*/
    input osc_clk,
    input RxD,
    output led1,
    output led2,
    output led3,
    output TxD
    );

// wire rst = ~rst_n;

//assign spi_miso = 1'bz;
//assign avr_rx = 1'bz;
//assign spi_channel = 4'bzzzz;
	 
// assign led = 8'b0;

//wire led1, led2, led3;

//assign led = { 5'b0, led3, led2, led1 };

fpgaminer_top #(.NUM_HASHERS(3),.LOOP(22),.SPEED_MHZ(50),.ICARUS(0),.KRAMBLE_TEST(1)) uut (osc_clk, RxD, TxD, led1, led2, led3);

endmodule