// I2C Testbench Top Module
module i2c_tb;
    
    import uvm_pkg::*;
    import i2c_pkg::*;
    
    `include "uvm_macros.svh"
    
    // Clock and Reset
    reg clk;
    reg rst_n;
    
    // I2C Interface Instance
    i2c_if i2c_interface(.clk(clk), .rst_n(rst_n));
    
    // Simple Slave Model for testing
    i2c_slave_model slave_inst(
        .clk(clk),
        .rst_n(rst_n),
        .sda(i2c_interface.sda),
        .scl(i2c_interface.scl),
        .slave_sda_en(i2c_interface.slave_sda_en)
    );
    
    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10 ns period = 100 MHz
    end
    
    // Reset Generation
    initial begin
        rst_n = 0;
        #25 rst_n = 1;
    end
    
    // UVM Initial Block
    initial begin
        // Store interface in config_db
        uvm_config_db #(virtual i2c_if)::set(null, "*", "i2c_if", i2c_interface);
        
        // Run UVM test
        run_test();
    end
    
    // Dump waveforms
    initial begin
        if ($test$plusargs("dump_wave")) begin
            $dumpfile("sim/i2c_simulation.vcd");
            $dumpvars(0, i2c_tb);
        end
    end
    
endmodule : i2c_tb

// Enhanced I2C Slave Model for verification
module i2c_slave_model(
    input logic clk,
    input logic rst_n,
    inout wire sda,
    inout wire scl,
    output logic slave_sda_en
);
    
    // State machine definition
    typedef enum {
        IDLE,
        WAIT_ADDRESS_BIT,
        ADDRESS_RX,
        ACK_ADDRESS,
        WAIT_DATA_BIT,
        DATA_RX,
        ACK_DATA,
        DATA_TX,
        NACK_RX
    } slave_state_e;
    
    slave_state_e state, next_state;
    
    // Synchronized bus signals
    logic sda_r, scl_r;
    logic sda_rr, scl_rr;
    
    // Bus condition detection
    logic start_detected, stop_detected;
    logic scl_falling_edge, scl_rising_edge;
    
    // Internal registers
    logic [7:0] address_reg;
    logic [7:0] data_reg;
    logic [2:0] bit_counter;
    logic [7:0] shift_reg;
    logic [7:0] slave_mem[256];  // Simple 256-byte memory
    logic read_mode;
    
    // Open-drain output
    assign slave_sda_en = (state == ACK_ADDRESS || state == ACK_DATA) ? 1'b1 : 1'b0;
    
    // Initialize slave memory with test data
    initial begin
        for (int i = 0; i < 256; i++) begin
            slave_mem[i] = 8'hAA + i;
        end
    end
    
    // Synchronize inputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_r <= 1'b1;
            scl_r <= 1'b1;
            sda_rr <= 1'b1;
            scl_rr <= 1'b1;
        end else begin
            sda_r <= sda;
            scl_r <= scl;
            sda_rr <= sda_r;
            scl_rr <= scl_r;
        end
    end
    
    // Detect bus conditions
    assign start_detected = sda_rr && ~sda_r && scl_rr;
    assign stop_detected = ~sda_rr && sda_r && scl_rr;
    assign scl_falling_edge = scl_rr && ~scl_r;
    assign scl_rising_edge = ~scl_rr && scl_r;
    
    // State machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_counter <= 3'h0;
            address_reg <= 8'h0;
            data_reg <= 8'h0;
            shift_reg <= 8'h0;
            read_mode <= 1'b0;
        end else begin
            state <= next_state;
            
            // Capture data on SCL rising edge (when SCL is stable high)
            if (scl_rising_edge && (state == WAIT_ADDRESS_BIT || state == WAIT_DATA_BIT)) begin
                shift_reg[7 - bit_counter] <= sda_r;
            end
            
            // Manage bit counter on SCL falling edge
            if (scl_falling_edge && (state == WAIT_ADDRESS_BIT || state == WAIT_DATA_BIT)) begin
                if (bit_counter == 3'h7) begin
                    bit_counter <= 3'h0;
                    if (state == WAIT_ADDRESS_BIT)
                        address_reg <= shift_reg;
                    else if (state == WAIT_DATA_BIT)
                        data_reg <= shift_reg;
                end else begin
                    bit_counter <= bit_counter + 1;
                end
            end
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start_detected)
                    next_state = WAIT_ADDRESS_BIT;
            end
            
            WAIT_ADDRESS_BIT: begin
                if (scl_falling_edge && bit_counter == 3'h7)
                    next_state = ADDRESS_RX;
            end
            
            ADDRESS_RX: begin
                next_state = ACK_ADDRESS;
            end
            
            ACK_ADDRESS: begin
                if (scl_falling_edge)
                    next_state = WAIT_DATA_BIT;
                else if (stop_detected)
                    next_state = IDLE;
            end
            
            WAIT_DATA_BIT: begin
                if (stop_detected)
                    next_state = IDLE;
                else if (scl_falling_edge && bit_counter == 3'h7)
                    next_state = DATA_RX;
            end
            
            DATA_RX: begin
                next_state = ACK_DATA;
            end
            
            ACK_DATA: begin
                if (scl_falling_edge)
                    next_state = WAIT_DATA_BIT;
                else if (stop_detected)
                    next_state = IDLE;
            end
            
            default: begin
                if (stop_detected)
                    next_state = IDLE;
            end
        endcase
    end
    
endmodule : i2c_slave_model
