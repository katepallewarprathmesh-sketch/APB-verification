// I2C Verification Package
package i2c_pkg;
    
    import uvm_pkg::*;
    
    `include "uvm_macros.svh"
    
    // Include all verification components
    `include "i2c_agent.sv"
    `include "i2c_test.sv"
    
endpackage : i2c_pkg
