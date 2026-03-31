// Simple RAM module for RISC-V CPU
// 128KB memory (0x00000 - 0x1FFFF)

`timescale 1ns/1ps

module ram #(
    parameter ADDR_WIDTH = 17  // 128KB = 2^17 bytes
)(
    input wire clk,
    input wire rst,
    input wire [31:0] addr,
    input wire [7:0] data_in,
    output reg [7:0] data_out,
    input wire wr_en
);

reg [7:0] memory [0:(1 << ADDR_WIDTH)-1];
integer i;

initial begin
    for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
        memory[i] = 8'h00;
    end
end

always @(posedge clk) begin
    if (rst) begin
        data_out <= 8'h00;
    end else begin
        if (wr_en && addr < (1 << ADDR_WIDTH)) begin
            memory[addr[ADDR_WIDTH-1:0]] <= data_in;
        end
        data_out <= memory[addr[ADDR_WIDTH-1:0]];
    end
end

endmodule
