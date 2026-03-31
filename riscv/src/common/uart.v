// Simple UART module for I/O simulation
// Handles character input/output at addresses 0x30000 and 0x30004

`timescale 1ns/1ps

module uart(
    input wire clk,
    input wire rst,

    // CPU interface
    input wire [31:0] addr,
    input wire [7:0] data_in,
    output reg [7:0] data_out,
    input wire wr_en,
    output reg buffer_full,

    // External I/O
    output reg [7:0] out_char,
    output reg out_valid,
    input wire [7:0] in_char,
    input wire in_valid
);

localparam UART_DATA = 32'h30000;  // Data register
localparam UART_STAT = 32'h30004;  // Status register

reg [7:0] rx_buffer;
reg rx_ready;
reg tx_busy;

initial begin
    buffer_full = 0;
    out_valid = 0;
    rx_ready = 0;
    tx_busy = 0;
end

always @(posedge clk) begin
    if (rst) begin
        buffer_full <= 0;
        out_valid <= 0;
        rx_ready <= 0;
        tx_busy <= 0;
        data_out <= 8'h00;
    end else begin
        out_valid <= 0;

        // Handle writes
        if (wr_en) begin
            if (addr == UART_DATA) begin
                // Write data to UART TX
                out_char <= data_in;
                out_valid <= 1;
                tx_busy <= 1;
            end
        end

        // Handle reads
        if (!wr_en) begin
            if (addr == UART_DATA) begin
                // Read data from UART RX
                data_out <= rx_buffer;
                rx_ready <= 0;
            end else if (addr == UART_STAT) begin
                // Read status
                // Bit 0: RX ready
                // Bit 1: TX busy
                data_out <= {6'b0, tx_busy, rx_ready};
            end else begin
                data_out <= 8'h00;
            end
        end

        // Handle input from external
        if (in_valid) begin
            rx_buffer <= in_char;
            rx_ready <= 1;
        end

        // Clear TX busy after transmission
        if (tx_busy) begin
            tx_busy <= 0;
        end

        // Update buffer_full signal
        buffer_full <= tx_busy;
    end
end

endmodule
