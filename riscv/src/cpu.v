// RISCV32I CPU with basic pipeline implementation
// This is a simplified implementation that supports RV32I instruction set

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

// Register file (32 x 32-bit registers)
reg [31:0] regs [0:31];
integer i;

// Program counter
reg [31:0] pc;

// Pipeline registers
reg [31:0] if_pc;
reg [31:0] if_inst;
reg if_valid;

reg [31:0] id_pc;
reg [31:0] id_inst;
reg [6:0] id_opcode;
reg [4:0] id_rd, id_rs1, id_rs2;
reg [2:0] id_funct3;
reg [6:0] id_funct7;
reg [31:0] id_imm;
reg id_valid;

reg [31:0] ex_pc;
reg [31:0] ex_result;
reg [4:0] ex_rd;
reg ex_we;
reg [31:0] ex_mem_addr;
reg [31:0] ex_mem_data;
reg [2:0] ex_mem_op;  // 0=none, 1=load, 2=store
reg [2:0] ex_funct3;
reg ex_valid;

reg [31:0] mem_result;
reg [4:0] mem_rd;
reg mem_we;
reg mem_valid;

// State machine for memory access
reg [2:0] mem_state;
reg [1:0] mem_byte_cnt;
reg [31:0] mem_addr_reg;
reg [31:0] mem_data_reg;
reg [2:0] mem_funct3_reg;
reg mem_is_load;
reg mem_is_store;

// Instruction fetch state
reg [1:0] if_state;
reg [1:0] if_byte_cnt;
reg [31:0] if_inst_buffer;

// Stall signal
reg stall;

// Debug register
assign dbgreg_dout = regs[0];

// Initialize
initial begin
    pc = 0;
    if_valid = 0;
    id_valid = 0;
    ex_valid = 0;
    mem_valid = 0;
    mem_wr = 0;
    stall = 0;
    if_state = 0;
    mem_state = 0;

    for (i = 0; i < 32; i = i + 1) begin
        regs[i] = 0;
    end
end

always @(posedge clk_in) begin
    if (rst_in) begin
        pc <= 0;
        if_valid <= 0;
        id_valid <= 0;
        ex_valid <= 0;
        mem_valid <= 0;
        mem_wr <= 0;
        stall <= 0;
        if_state <= 0;
        mem_state <= 0;

        for (i = 0; i < 32; i = i + 1) begin
            regs[i] <= 0;
        end
    end else if (!rdy_in) begin
        // Wait for ready signal
    end else begin
        // ===== Write Back Stage =====
        if (mem_valid && mem_we && mem_rd != 0) begin
            regs[mem_rd] <= mem_result;
        end

        // ===== Memory Stage =====
        mem_valid <= 0;
        mem_we <= 0;

        if (mem_state == 0) begin
            // Check if there's a memory operation from EX stage
            if (ex_valid && ex_mem_op != 0 && !stall) begin
                mem_state <= 1;
                mem_addr_reg <= ex_mem_addr;
                mem_data_reg <= ex_mem_data;
                mem_funct3_reg <= ex_funct3;
                mem_is_load <= (ex_mem_op == 1);
                mem_is_store <= (ex_mem_op == 2);
                mem_byte_cnt <= 0;
                mem_data_reg <= 0;
                mem_rd <= ex_rd;
                stall <= 1;
            end else if (ex_valid && ex_we && !stall) begin
                // Non-memory instruction, just pass through
                mem_result <= ex_result;
                mem_rd <= ex_rd;
                mem_we <= 1;
                mem_valid <= 1;
            end
        end else if (mem_state == 1) begin
            // Memory access state machine
            if (mem_is_load) begin
                // Load operation
                case (mem_funct3_reg)
                    3'b000, 3'b100: begin // LB, LBU
                        mem_a <= mem_addr_reg;
                        mem_wr <= 0;
                        mem_state <= 2;
                    end
                    3'b001, 3'b101: begin // LH, LHU
                        mem_a <= mem_addr_reg + mem_byte_cnt;
                        mem_wr <= 0;
                        if (mem_byte_cnt == 0) begin
                            mem_state <= 2;
                        end
                    end
                    3'b010: begin // LW
                        mem_a <= mem_addr_reg + mem_byte_cnt;
                        mem_wr <= 0;
                        if (mem_byte_cnt == 0) begin
                            mem_state <= 2;
                        end
                    end
                endcase
            end else if (mem_is_store) begin
                // Store operation
                case (mem_funct3_reg)
                    3'b000: begin // SB
                        mem_a <= mem_addr_reg;
                        mem_dout <= mem_data_reg[7:0];
                        mem_wr <= 1;
                        mem_state <= 3;
                    end
                    3'b001: begin // SH
                        mem_a <= mem_addr_reg + mem_byte_cnt;
                        mem_dout <= (mem_byte_cnt == 0) ? mem_data_reg[7:0] : mem_data_reg[15:8];
                        mem_wr <= 1;
                        if (mem_byte_cnt == 1) begin
                            mem_state <= 3;
                        end else begin
                            mem_byte_cnt <= mem_byte_cnt + 1;
                        end
                    end
                    3'b010: begin // SW
                        mem_a <= mem_addr_reg + mem_byte_cnt;
                        case (mem_byte_cnt)
                            0: mem_dout <= mem_data_reg[7:0];
                            1: mem_dout <= mem_data_reg[15:8];
                            2: mem_dout <= mem_data_reg[23:16];
                            3: mem_dout <= mem_data_reg[31:24];
                        endcase
                        mem_wr <= 1;
                        if (mem_byte_cnt == 3) begin
                            mem_state <= 3;
                        end else begin
                            mem_byte_cnt <= mem_byte_cnt + 1;
                        end
                    end
                endcase
            end
        end else if (mem_state == 2) begin
            // Read data from memory
            if (mem_is_load) begin
                case (mem_funct3_reg)
                    3'b000: begin // LB (sign-extended)
                        mem_data_reg[7:0] <= mem_din;
                        mem_result <= {{24{mem_din[7]}}, mem_din};
                        mem_we <= 1;
                        mem_valid <= 1;
                        mem_state <= 0;
                        stall <= 0;
                    end
                    3'b001: begin // LH (sign-extended)
                        if (mem_byte_cnt == 0) begin
                            mem_data_reg[7:0] <= mem_din;
                            mem_byte_cnt <= 1;
                            mem_state <= 1;
                        end else begin
                            mem_data_reg[15:8] <= mem_din;
                            mem_result <= {{16{mem_din[7]}}, mem_din, mem_data_reg[7:0]};
                            mem_we <= 1;
                            mem_valid <= 1;
                            mem_state <= 0;
                            stall <= 0;
                        end
                    end
                    3'b010: begin // LW
                        if (mem_byte_cnt < 3) begin
                            mem_data_reg[mem_byte_cnt * 8 +: 8] <= mem_din;
                            mem_byte_cnt <= mem_byte_cnt + 1;
                            mem_state <= 1;
                        end else begin
                            mem_data_reg[31:24] <= mem_din;
                            mem_result <= {mem_din, mem_data_reg[23:0]};
                            mem_we <= 1;
                            mem_valid <= 1;
                            mem_state <= 0;
                            stall <= 0;
                        end
                    end
                    3'b100: begin // LBU (zero-extended)
                        mem_result <= {24'b0, mem_din};
                        mem_we <= 1;
                        mem_valid <= 1;
                        mem_state <= 0;
                        stall <= 0;
                    end
                    3'b101: begin // LHU (zero-extended)
                        if (mem_byte_cnt == 0) begin
                            mem_data_reg[7:0] <= mem_din;
                            mem_byte_cnt <= 1;
                            mem_state <= 1;
                        end else begin
                            mem_result <= {16'b0, mem_din, mem_data_reg[7:0]};
                            mem_we <= 1;
                            mem_valid <= 1;
                            mem_state <= 0;
                            stall <= 0;
                        end
                    end
                endcase
            end
        end else if (mem_state == 3) begin
            // Store complete
            mem_wr <= 0;
            mem_state <= 0;
            stall <= 0;
        end

        // ===== Execute Stage =====
        ex_valid <= 0;
        ex_we <= 0;
        ex_mem_op <= 0;

        if (id_valid && !stall) begin
            ex_valid <= 1;
            ex_pc <= id_pc;
            ex_rd <= id_rd;
            ex_funct3 <= id_funct3;

            case (id_opcode)
                // LUI
                7'b0110111: begin
                    ex_result <= id_imm;
                    ex_we <= 1;
                end

                // AUIPC
                7'b0010111: begin
                    ex_result <= id_pc + id_imm;
                    ex_we <= 1;
                end

                // JAL
                7'b1101111: begin
                    ex_result <= id_pc + 4;
                    ex_we <= 1;
                    pc <= id_pc + id_imm;
                    if_valid <= 0;  // Flush pipeline
                    id_valid <= 0;
                end

                // JALR
                7'b1100111: begin
                    ex_result <= id_pc + 4;
                    ex_we <= 1;
                    pc <= (regs[id_rs1] + id_imm) & ~1;
                    if_valid <= 0;  // Flush pipeline
                    id_valid <= 0;
                end

                // Branch instructions
                7'b1100011: begin
                    case (id_funct3)
                        3'b000: begin // BEQ
                            if (regs[id_rs1] == regs[id_rs2]) begin
                                pc <= id_pc + id_imm;
                                if_valid <= 0;
                                id_valid <= 0;
                            end
                        end
                        3'b001: begin // BNE
                            if (regs[id_rs1] != regs[id_rs2]) begin
                                pc <= id_pc + id_imm;
                                if_valid <= 0;
                                id_valid <= 0;
                            end
                        end
                        3'b100: begin // BLT
                            if ($signed(regs[id_rs1]) < $signed(regs[id_rs2])) begin
                                pc <= id_pc + id_imm;
                                if_valid <= 0;
                                id_valid <= 0;
                            end
                        end
                        3'b101: begin // BGE
                            if ($signed(regs[id_rs1]) >= $signed(regs[id_rs2])) begin
                                pc <= id_pc + id_imm;
                                if_valid <= 0;
                                id_valid <= 0;
                            end
                        end
                        3'b110: begin // BLTU
                            if (regs[id_rs1] < regs[id_rs2]) begin
                                pc <= id_pc + id_imm;
                                if_valid <= 0;
                                id_valid <= 0;
                            end
                        end
                        3'b111: begin // BGEU
                            if (regs[id_rs1] >= regs[id_rs2]) begin
                                pc <= id_pc + id_imm;
                                if_valid <= 0;
                                id_valid <= 0;
                            end
                        end
                    endcase
                end

                // Load instructions
                7'b0000011: begin
                    ex_mem_addr <= regs[id_rs1] + id_imm;
                    ex_mem_op <= 1;  // Load
                    ex_we <= 1;
                end

                // Store instructions
                7'b0100011: begin
                    ex_mem_addr <= regs[id_rs1] + id_imm;
                    ex_mem_data <= regs[id_rs2];
                    ex_mem_op <= 2;  // Store
                end

                // Immediate ALU instructions
                7'b0010011: begin
                    case (id_funct3)
                        3'b000: ex_result <= regs[id_rs1] + id_imm;  // ADDI
                        3'b001: ex_result <= regs[id_rs1] << id_imm[4:0];  // SLLI
                        3'b010: ex_result <= ($signed(regs[id_rs1]) < $signed(id_imm)) ? 1 : 0;  // SLTI
                        3'b011: ex_result <= (regs[id_rs1] < id_imm) ? 1 : 0;  // SLTIU
                        3'b100: ex_result <= regs[id_rs1] ^ id_imm;  // XORI
                        3'b101: begin
                            if (id_funct7[5]) begin
                                ex_result <= $signed(regs[id_rs1]) >>> id_imm[4:0];  // SRAI
                            end else begin
                                ex_result <= regs[id_rs1] >> id_imm[4:0];  // SRLI
                            end
                        end
                        3'b110: ex_result <= regs[id_rs1] | id_imm;  // ORI
                        3'b111: ex_result <= regs[id_rs1] & id_imm;  // ANDI
                    endcase
                    ex_we <= 1;
                end

                // Register ALU instructions
                7'b0110011: begin
                    case (id_funct3)
                        3'b000: begin
                            if (id_funct7[5]) begin
                                ex_result <= regs[id_rs1] - regs[id_rs2];  // SUB
                            end else begin
                                ex_result <= regs[id_rs1] + regs[id_rs2];  // ADD
                            end
                        end
                        3'b001: ex_result <= regs[id_rs1] << regs[id_rs2][4:0];  // SLL
                        3'b010: ex_result <= ($signed(regs[id_rs1]) < $signed(regs[id_rs2])) ? 1 : 0;  // SLT
                        3'b011: ex_result <= (regs[id_rs1] < regs[id_rs2]) ? 1 : 0;  // SLTU
                        3'b100: ex_result <= regs[id_rs1] ^ regs[id_rs2];  // XOR
                        3'b101: begin
                            if (id_funct7[5]) begin
                                ex_result <= $signed(regs[id_rs1]) >>> regs[id_rs2][4:0];  // SRA
                            end else begin
                                ex_result <= regs[id_rs1] >> regs[id_rs2][4:0];  // SRL
                            end
                        end
                        3'b110: ex_result <= regs[id_rs1] | regs[id_rs2];  // OR
                        3'b111: ex_result <= regs[id_rs1] & regs[id_rs2];  // AND
                    endcase
                    ex_we <= 1;
                end
            endcase
        end

        // ===== Decode Stage =====
        id_valid <= 0;

        if (if_valid && !stall) begin
            id_valid <= 1;
            id_pc <= if_pc;
            id_inst <= if_inst;
            id_opcode <= if_inst[6:0];
            id_rd <= if_inst[11:7];
            id_rs1 <= if_inst[19:15];
            id_rs2 <= if_inst[24:20];
            id_funct3 <= if_inst[14:12];
            id_funct7 <= if_inst[31:25];

            // Immediate generation
            case (if_inst[6:0])
                7'b0110111, 7'b0010111: begin // U-type (LUI, AUIPC)
                    id_imm <= {if_inst[31:12], 12'b0};
                end
                7'b1101111: begin // J-type (JAL)
                    id_imm <= {{12{if_inst[31]}}, if_inst[19:12], if_inst[20], if_inst[30:21], 1'b0};
                end
                7'b1100111, 7'b0000011, 7'b0010011: begin // I-type (JALR, Load, ALU-I)
                    id_imm <= {{20{if_inst[31]}}, if_inst[31:20]};
                end
                7'b1100011: begin // B-type (Branch)
                    id_imm <= {{20{if_inst[31]}}, if_inst[7], if_inst[30:25], if_inst[11:8], 1'b0};
                end
                7'b0100011: begin // S-type (Store)
                    id_imm <= {{20{if_inst[31]}}, if_inst[31:25], if_inst[11:7]};
                end
                default: begin
                    id_imm <= 0;
                end
            endcase
        end

        // ===== Fetch Stage =====
        if (!stall) begin
            if (if_state == 0) begin
                // Start fetching instruction
                mem_a <= pc;
                mem_wr <= 0;
                if_state <= 1;
                if_byte_cnt <= 0;
                if_inst_buffer <= 0;
                if_valid <= 0;
            end else if (if_state == 1) begin
                // Read instruction bytes
                if_inst_buffer[if_byte_cnt * 8 +: 8] <= mem_din;

                if (if_byte_cnt == 3) begin
                    if_inst <= {mem_din, if_inst_buffer[23:0]};
                    if_pc <= pc;
                    if_valid <= 1;
                    pc <= pc + 4;
                    if_state <= 0;
                end else begin
                    if_byte_cnt <= if_byte_cnt + 1;
                    mem_a <= pc + if_byte_cnt + 1;
                end
            end
        end
    end
end

endmodule
