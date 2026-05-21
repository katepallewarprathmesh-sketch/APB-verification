// APB slave register file (AMBA APB protocol)
// 4 x 32-bit registers at word-aligned offsets 0x00, 0x04, 0x08, 0x0C

module apb_slave_regfile #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 4,
    parameter int READY_DELAY_MIN = 0,
    parameter int READY_DELAY_MAX = 2
) (
    input  logic                  pclk,
    input  logic                  presetn,
    input  logic [ADDR_WIDTH-1:0] paddr,
    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [DATA_WIDTH-1:0] pwdata,
    output logic [DATA_WIDTH-1:0] prdata,
    output logic                  pready,
    output logic                  pslverr
);

    localparam int REG_ADDR_W = $clog2(NUM_REGS);
    localparam logic [ADDR_WIDTH-1:0] ADDR_MASK = ~(DATA_WIDTH/8 - 1);

    logic [DATA_WIDTH-1:0] regs [NUM_REGS];
    logic [REG_ADDR_W-1:0] reg_idx;
    logic                  addr_ok;
    logic [3:0]            wait_cnt;
    logic [3:0]            wait_load;

    assign reg_idx  = paddr[REG_ADDR_W+1:2];
    assign addr_ok  = (paddr[ADDR_WIDTH-1:REG_ADDR_W+2] == '0) &&
                      (paddr[1:0] == 2'b00) &&
                      (reg_idx < NUM_REGS);

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            for (int i = 0; i < NUM_REGS; i++)
                regs[i] <= '0;
        end else if (psel && penable && pready && pwrite && addr_ok) begin
            regs[reg_idx] <= pwdata;
        end
    end

    assign prdata = (psel && penable && pready && !pwrite && addr_ok)
                    ? regs[reg_idx] : '0;

    always_comb begin
        integer span, sel;
        span = READY_DELAY_MAX - READY_DELAY_MIN + 1;
        sel  = addr_ok ? reg_idx : 0;
        wait_load = READY_DELAY_MIN + (sel % span);
    end

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            wait_cnt <= '0;
        else if (psel && !penable)
            wait_cnt <= wait_load;
        else if (psel && penable && !pready && wait_cnt != 0)
            wait_cnt <= wait_cnt - 1'b1;
        else if (!psel || pready)
            wait_cnt <= '0;
    end

    assign pready  = !(psel && penable) || (wait_cnt == 0);
    assign pslverr = psel && penable && pready && !addr_ok;

endmodule
