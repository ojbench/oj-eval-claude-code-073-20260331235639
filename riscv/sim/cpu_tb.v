// Simple testbench for RISC-V CPU
`timescale 1ns/1ps

module cpu_tb;

reg clk;
reg rst;
reg rdy;

wire [7:0] mem_din;
wire [7:0] mem_dout;
wire [31:0] mem_a;
wire mem_wr;
wire io_buffer_full;
wire [31:0] dbgreg_dout;

// Memory instance (128KB)
reg [7:0] memory [0:131071];  // 128KB
integer i;

// CPU instance
cpu cpu_inst(
    .clk_in(clk),
    .rst_in(rst),
    .rdy_in(rdy),
    .mem_din(mem_din),
    .mem_dout(mem_dout),
    .mem_a(mem_a),
    .mem_wr(mem_wr),
    .io_buffer_full(io_buffer_full),
    .dbgreg_dout(dbgreg_dout)
);

// Memory read/write logic
assign mem_din = (mem_a < 32'h20000) ? memory[mem_a[16:0]] : 8'h00;
assign io_buffer_full = 0;  // Never full in simulation

always @(posedge clk) begin
    if (mem_wr && mem_a < 32'h20000) begin
        memory[mem_a[16:0]] <= mem_dout;
    end

    // UART output
    if (mem_wr && mem_a == 32'h30000) begin
        $write("%c", mem_dout);
    end
end

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz clock
end

// Test sequence
initial begin
    // Initialize
    rst = 1;
    rdy = 1;

    // Initialize memory
    for (i = 0; i < 131072; i = i + 1) begin
        memory[i] = 8'h00;
    end

    // Load a simple test program
    // ADDI x1, x0, 42  (load 42 into x1)
    memory[0] = 8'h93;  // 0x02a00093
    memory[1] = 8'h00;
    memory[2] = 8'ha0;
    memory[3] = 8'h02;

    // LUI x2, 0x12345  (load upper immediate)
    memory[4] = 8'hb7;  // 0x12345137
    memory[5] = 8'h51;
    memory[6] = 8'h34;
    memory[7] = 8'h12;

    // ADD x3, x1, x2
    memory[8] = 8'hb3;  // 0x002081b3
    memory[9] = 8'h81;
    memory[10] = 8'h20;
    memory[11] = 8'h00;

    // Release reset
    #20 rst = 0;

    // Run for some time
    #1000;

    // Check results
    $display("Test completed");
    $display("Debug register (x10/a0): %h", dbgreg_dout);

    $finish;
end

// Timeout watchdog
initial begin
    #100000;
    $display("Timeout!");
    $finish;
end

endmodule
