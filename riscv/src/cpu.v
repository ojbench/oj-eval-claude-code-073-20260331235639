// RISCV32I CPU - Simplified single-cycle-ish implementation
// Supports all RV32I instructions with proper I/O handling

`timescale 1ns/1ps

module cpu(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    // Memory interface
    input wire [7:0] mem_din,
    output reg [7:0] mem_dout,
    output reg [31:0] mem_a,
    output reg mem_wr,

    // UART interface (I/O at 0x30000 and 0x30004)
    input wire io_buffer_full,

    // Debug output
    output wire [31:0] dbgreg_dout
);

// Register file (x0 is always 0)
reg [31:0] regs [0:31];
integer i;

// Program counter
reg [31:0] pc;

// Current instruction being executed
reg [31:0] inst;

// CPU state machine
localparam STATE_IF = 0;      // Instruction fetch
localparam STATE_ID = 1;      // Instruction decode
localparam STATE_EX = 2;      // Execute
localparam STATE_MEM = 3;     // Memory access
localparam STATE_WB = 4;      // Write back

reg [2:0] state;

// Instruction fetch state
reg [1:0] if_byte_count;
reg [31:0] inst_buffer;

// Decoded instruction fields
reg [6:0] opcode;
reg [4:0] rd, rs1, rs2;
reg [2:0] funct3;
reg [6:0] funct7;
reg [31:0] imm;

// Execution results
reg [31:0] alu_result;
reg [31:0] mem_addr;
reg [31:0] mem_wdata;
reg [31:0] mem_rdata;

// Memory access state
reg [1:0] mem_byte_count;
reg [31:0] mem_buffer;
reg mem_is_load;
reg mem_is_store;

// Branch/jump control
reg take_branch;
reg [31:0] branch_target;

// Debug output
assign dbgreg_dout = regs[10];  // a0 register

// Initialize
initial begin
    pc = 0;
    state = STATE_IF;
    mem_wr = 0;

    for (i = 0; i < 32; i = i + 1) begin
        regs[i] = 0;
    end
end

always @(posedge clk_in) begin
    if (rst_in) begin
        pc <= 0;
        state <= STATE_IF;
        mem_wr <= 0;
        if_byte_count <= 0;

        for (i = 0; i < 32; i = i + 1) begin
            regs[i] <= 0;
        end
    end else if (rdy_in) begin

        case (state)

            // ===== INSTRUCTION FETCH =====
            STATE_IF: begin
                mem_wr <= 0;

                if (if_byte_count == 0) begin
                    // Start fetching instruction
                    mem_a <= pc;
                    if_byte_count <= 1;
                    inst_buffer <= 0;
                end else begin
                    // Collect instruction bytes
                    inst_buffer[(if_byte_count-1)*8 +: 8] <= mem_din;

                    if (if_byte_count == 4) begin
                        // Complete instruction fetched
                        inst <= {mem_din, inst_buffer[23:0]};
                        if_byte_count <= 0;
                        state <= STATE_ID;
                    end else begin
                        mem_a <= pc + if_byte_count;
                        if_byte_count <= if_byte_count + 1;
                    end
                end
            end

            // ===== INSTRUCTION DECODE =====
            STATE_ID: begin
                // Extract fields
                opcode <= inst[6:0];
                rd <= inst[11:7];
                funct3 <= inst[14:12];
                rs1 <= inst[19:15];
                rs2 <= inst[24:20];
                funct7 <= inst[31:25];

                // Decode immediate based on instruction type
                case (inst[6:0])
                    7'b0110111, 7'b0010111: begin // U-type (LUI, AUIPC)
                        imm <= {inst[31:12], 12'b0};
                    end
                    7'b1101111: begin // J-type (JAL)
                        imm <= {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
                    end
                    7'b1100111, 7'b0000011, 7'b0010011: begin // I-type
                        imm <= {{20{inst[31]}}, inst[31:20]};
                    end
                    7'b1100011: begin // B-type (Branch)
                        imm <= {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
                    end
                    7'b0100011: begin // S-type (Store)
                        imm <= {{20{inst[31]}}, inst[31:25], inst[11:7]};
                    end
                    default: begin
                        imm <= 0;
                    end
                endcase

                state <= STATE_EX;
            end

            // ===== EXECUTE =====
            STATE_EX: begin
                take_branch <= 0;
                mem_is_load <= 0;
                mem_is_store <= 0;

                case (opcode)
                    // LUI
                    7'b0110111: begin
                        alu_result <= imm;
                        state <= STATE_WB;
                    end

                    // AUIPC
                    7'b0010111: begin
                        alu_result <= pc + imm;
                        state <= STATE_WB;
                    end

                    // JAL
                    7'b1101111: begin
                        alu_result <= pc + 4;
                        take_branch <= 1;
                        branch_target <= pc + imm;
                        state <= STATE_WB;
                    end

                    // JALR
                    7'b1100111: begin
                        alu_result <= pc + 4;
                        take_branch <= 1;
                        branch_target <= (regs[rs1] + imm) & ~1;
                        state <= STATE_WB;
                    end

                    // Branch instructions
                    7'b1100011: begin
                        case (funct3)
                            3'b000: take_branch <= (regs[rs1] == regs[rs2]); // BEQ
                            3'b001: take_branch <= (regs[rs1] != regs[rs2]); // BNE
                            3'b100: take_branch <= ($signed(regs[rs1]) < $signed(regs[rs2])); // BLT
                            3'b101: take_branch <= ($signed(regs[rs1]) >= $signed(regs[rs2])); // BGE
                            3'b110: take_branch <= (regs[rs1] < regs[rs2]); // BLTU
                            3'b111: take_branch <= (regs[rs1] >= regs[rs2]); // BGEU
                        endcase
                        branch_target <= pc + imm;
                        state <= STATE_WB;
                    end

                    // Load instructions
                    7'b0000011: begin
                        mem_addr <= regs[rs1] + imm;
                        mem_is_load <= 1;
                        mem_byte_count <= 0;
                        mem_buffer <= 0;
                        state <= STATE_MEM;
                    end

                    // Store instructions
                    7'b0100011: begin
                        mem_addr <= regs[rs1] + imm;
                        mem_wdata <= regs[rs2];
                        mem_is_store <= 1;
                        mem_byte_count <= 0;
                        state <= STATE_MEM;
                    end

                    // Immediate ALU operations
                    7'b0010011: begin
                        case (funct3)
                            3'b000: alu_result <= regs[rs1] + imm; // ADDI
                            3'b001: alu_result <= regs[rs1] << imm[4:0]; // SLLI
                            3'b010: alu_result <= ($signed(regs[rs1]) < $signed(imm)) ? 1 : 0; // SLTI
                            3'b011: alu_result <= (regs[rs1] < imm) ? 1 : 0; // SLTIU
                            3'b100: alu_result <= regs[rs1] ^ imm; // XORI
                            3'b101: begin
                                if (funct7[5])
                                    alu_result <= $signed(regs[rs1]) >>> imm[4:0]; // SRAI
                                else
                                    alu_result <= regs[rs1] >> imm[4:0]; // SRLI
                            end
                            3'b110: alu_result <= regs[rs1] | imm; // ORI
                            3'b111: alu_result <= regs[rs1] & imm; // ANDI
                        endcase
                        state <= STATE_WB;
                    end

                    // Register ALU operations
                    7'b0110011: begin
                        case (funct3)
                            3'b000: begin
                                if (funct7[5])
                                    alu_result <= regs[rs1] - regs[rs2]; // SUB
                                else
                                    alu_result <= regs[rs1] + regs[rs2]; // ADD
                            end
                            3'b001: alu_result <= regs[rs1] << regs[rs2][4:0]; // SLL
                            3'b010: alu_result <= ($signed(regs[rs1]) < $signed(regs[rs2])) ? 1 : 0; // SLT
                            3'b011: alu_result <= (regs[rs1] < regs[rs2]) ? 1 : 0; // SLTU
                            3'b100: alu_result <= regs[rs1] ^ regs[rs2]; // XOR
                            3'b101: begin
                                if (funct7[5])
                                    alu_result <= $signed(regs[rs1]) >>> regs[rs2][4:0]; // SRA
                                else
                                    alu_result <= regs[rs1] >> regs[rs2][4:0]; // SRL
                            end
                            3'b110: alu_result <= regs[rs1] | regs[rs2]; // OR
                            3'b111: alu_result <= regs[rs1] & regs[rs2]; // AND
                        endcase
                        state <= STATE_WB;
                    end

                    default: begin
                        // Unknown instruction, skip
                        state <= STATE_WB;
                    end
                endcase
            end

            // ===== MEMORY ACCESS =====
            STATE_MEM: begin
                if (mem_is_load) begin
                    // Load operation
                    if (mem_byte_count == 0) begin
                        // Check for I/O addresses
                        if (mem_addr == 32'h30000 || mem_addr == 32'h30004) begin
                            // I/O read
                            mem_a <= mem_addr;
                            mem_wr <= 0;
                            mem_byte_count <= 1;
                        end else begin
                            // Regular memory read
                            mem_a <= mem_addr;
                            mem_wr <= 0;
                            mem_byte_count <= 1;
                        end
                    end else begin
                        // Collect bytes based on load type
                        mem_buffer[(mem_byte_count-1)*8 +: 8] <= mem_din;

                        case (funct3)
                            3'b000, 3'b100: begin // LB, LBU
                                if (mem_byte_count == 1) begin
                                    // Sign/zero extend
                                    if (funct3 == 3'b000) // LB
                                        mem_rdata <= {{24{mem_din[7]}}, mem_din};
                                    else // LBU
                                        mem_rdata <= {24'b0, mem_din};
                                    state <= STATE_WB;
                                end else begin
                                    mem_byte_count <= mem_byte_count + 1;
                                end
                            end

                            3'b001, 3'b101: begin // LH, LHU
                                if (mem_byte_count == 2) begin
                                    if (funct3 == 3'b001) // LH
                                        mem_rdata <= {{16{mem_din[7]}}, mem_din, mem_buffer[7:0]};
                                    else // LHU
                                        mem_rdata <= {16'b0, mem_din, mem_buffer[7:0]};
                                    state <= STATE_WB;
                                end else begin
                                    mem_a <= mem_addr + mem_byte_count;
                                    mem_byte_count <= mem_byte_count + 1;
                                end
                            end

                            3'b010: begin // LW
                                if (mem_byte_count == 4) begin
                                    mem_rdata <= {mem_din, mem_buffer[23:0]};
                                    state <= STATE_WB;
                                end else begin
                                    mem_a <= mem_addr + mem_byte_count;
                                    mem_byte_count <= mem_byte_count + 1;
                                end
                            end
                        endcase
                    end

                end else if (mem_is_store) begin
                    // Store operation
                    if (mem_addr == 32'h30000 || mem_addr == 32'h30004) begin
                        // I/O write - check if buffer is full
                        if (mem_addr == 32'h30000 && io_buffer_full) begin
                            // Wait for buffer to be ready
                            mem_byte_count <= 0;
                        end else begin
                            // Write to I/O
                            mem_a <= mem_addr + mem_byte_count;
                            mem_dout <= mem_wdata[(mem_byte_count*8) +: 8];
                            mem_wr <= 1;

                            case (funct3)
                                3'b000: state <= STATE_WB; // SB - single byte
                                3'b001: begin // SH - 2 bytes
                                    if (mem_byte_count == 1)
                                        state <= STATE_WB;
                                    else
                                        mem_byte_count <= mem_byte_count + 1;
                                end
                                3'b010: begin // SW - 4 bytes
                                    if (mem_byte_count == 3)
                                        state <= STATE_WB;
                                    else
                                        mem_byte_count <= mem_byte_count + 1;
                                end
                            endcase
                        end
                    end else begin
                        // Regular memory write
                        mem_a <= mem_addr + mem_byte_count;
                        mem_dout <= mem_wdata[(mem_byte_count*8) +: 8];
                        mem_wr <= 1;

                        case (funct3)
                            3'b000: state <= STATE_WB; // SB
                            3'b001: begin // SH
                                if (mem_byte_count == 1)
                                    state <= STATE_WB;
                                else
                                    mem_byte_count <= mem_byte_count + 1;
                            end
                            3'b010: begin // SW
                                if (mem_byte_count == 3)
                                    state <= STATE_WB;
                                else
                                    mem_byte_count <= mem_byte_count + 1;
                            end
                        endcase
                    end
                end
            end

            // ===== WRITE BACK =====
            STATE_WB: begin
                mem_wr <= 0;

                // Write to register file
                if (opcode == 7'b0000011) begin
                    // Load instruction
                    if (rd != 0)
                        regs[rd] <= mem_rdata;
                end else if (opcode != 7'b0100011 && opcode != 7'b1100011) begin
                    // Not a store or branch
                    if (rd != 0)
                        regs[rd] <= alu_result;
                end

                // Update PC
                if (take_branch) begin
                    pc <= branch_target;
                end else begin
                    pc <= pc + 4;
                end

                // Move to next instruction
                state <= STATE_IF;
                if_byte_count <= 0;
            end

        endcase
    end
end

endmodule
