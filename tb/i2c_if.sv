// I2C Interface Definition
interface i2c_if(input logic clk, input logic rst_n);

    // I2C Bus Signals (Open Drain)
    wire sda;
    wire scl;
    
    // Logical control signals
    logic sda_en;  // sda_en = 1 -> pull low, sda_en = 0 -> release (open drain)
    logic scl_en;  // scl_en = 1 -> pull low, scl_en = 0 -> release (open drain)
    
    // Separate enable signals for master and slave
    logic master_sda_en;
    logic master_scl_en;
    logic slave_sda_en;
    logic slave_scl_en;
    
    // Monitor signals
    logic mon_sda;
    logic mon_scl;
    
    // Modports for different components
    modport master(
        input clk, rst_n,
        output master_sda_en, master_scl_en,
        input sda, scl
    );
    
    modport slave(
        input clk, rst_n,
        output slave_sda_en,
        input sda, scl, scl_en
    );
    
    modport monitor(
        input clk, rst_n, sda, scl
    );
    
    // Open drain implementation
    assign sda = (master_sda_en || slave_sda_en) ? 1'b0 : 1'bz;
    assign scl = (master_scl_en || slave_scl_en) ? 1'b0 : 1'bz;
    
    assign mon_sda = sda;
    assign mon_scl = scl;
    
endinterface : i2c_if
