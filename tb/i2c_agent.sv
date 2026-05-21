// I2C Bus Functional Model (BFM)
class i2c_agent extends uvm_agent;
    `uvm_component_utils(i2c_agent)
    
    virtual i2c_if vif;
    i2c_driver driver;
    i2c_sequencer sequencer;
    i2c_monitor monitor;
    
    uvm_analysis_port #(i2c_seq_item) item_collected_port;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction : new
    
    virtual function void build_phase(uvm_build_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db #(virtual i2c_if)::get(this, "", "i2c_if", vif))
            `uvm_fatal("I2C_AGENT", "Failed to get i2c_if from config_db")
        
        sequencer = i2c_sequencer::type_id::create("sequencer", this);
        driver = i2c_driver::type_id::create("driver", this);
        monitor = i2c_monitor::type_id::create("monitor", this);
    endfunction : build_phase
    
    virtual function void connect_phase(uvm_connect_phase phase);
        super.connect_phase(phase);
        
        driver.seq_item_port.connect(sequencer.seq_item_export);
        driver.vif = vif;
        monitor.vif = vif;
        monitor.item_collected_port.connect(item_collected_port);
    endfunction : connect_phase
    
endclass : i2c_agent

// I2C Sequencer
class i2c_sequencer extends uvm_sequencer #(i2c_seq_item);
    `uvm_component_utils(i2c_sequencer)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
endclass : i2c_sequencer

// I2C Sequence Item
class i2c_seq_item extends uvm_sequence_item;
    `uvm_object_utils(i2c_seq_item)
    
    typedef enum {WRITE, READ, WRITE_READ} op_type_e;
    
    rand op_type_e op_type;
    rand bit [6:0] address;  // 7-bit I2C address
    rand bit read_write;      // 0 = write, 1 = read
    rand bit [7:0] write_data[$];
    bit [7:0] read_data[$];
    bit ack_error;
    
    constraint addr_valid {
        address != 7'h00;  // Reserved address
        address != 7'h7F;  // Reserved address
    }
    
    function new(string name = "i2c_seq_item");
        super.new(name);
    endfunction : new
    
    virtual function string convert2string();
        return $sformatf("addr=0x%2h, %s, data=%p, ack_error=%0d",
                        address, read_write ? "READ" : "WRITE", 
                        read_write ? read_data : write_data, ack_error);
    endfunction : convert2string
    
endclass : i2c_seq_item

// I2C Driver
class i2c_driver extends uvm_driver #(i2c_seq_item);
    `uvm_component_utils(i2c_driver)
    
    virtual i2c_if vif;
    
    parameter TIME_PERIOD_NS = 10;
    parameter SCL_PERIOD_NS = 2500;  // ~400 kHz
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
    virtual task run_phase(uvm_run_phase phase);
        super.run_phase(phase);
        
        // Wait for reset
        @(posedge vif.rst_n);
        
        forever begin
            seq_item_port.get_next_item(req);
            
            if (req.read_write == 0)
                write_data(req.address, req.write_data);
            else
                read_data(req.address, req.read_data);
            
            seq_item_port.item_done();
        end
    endtask : run_phase
    
    virtual task write_data(bit [6:0] address, bit [7:0] data[$]);
        `uvm_info("I2C_DRIVER", $sformatf("Writing address=0x%2h, data=%p", 
                                          address, data), UVM_MEDIUM)
        
        send_start_condition();
        send_address(address, 0);  // 0 = write
        
        foreach (data[i]) begin
            send_byte(data[i]);
        end
        
        send_stop_condition();
    endtask : write_data
    
    virtual task read_data(bit [6:0] address, ref bit [7:0] data[$]);
        `uvm_info("I2C_DRIVER", $sformatf("Reading address=0x%2h", address), UVM_MEDIUM)
        
        send_start_condition();
        send_address(address, 1);  // 1 = read
        
        for (int i = 0; i < 2; i++) begin  // Read 2 bytes as example
            bit [7:0] byte_data;
            receive_byte();
            data.push_back(byte_data);
            
            if (i < 1)
                send_ack();
            else
                send_nack();
        end
        
        send_stop_condition();
    endtask : read_data
    
    virtual task send_start_condition();
        `uvm_info("I2C_DRIVER", "Sending START condition", UVM_HIGH)
        
        // Release both lines
        vif.master_sda_en <= 0;
        vif.master_scl_en <= 0;
        wait_clock_cycles(1);
        
        // SDA goes low while SCL is high
        vif.master_sda_en <= 1;
        wait_clock_cycles(1);
        vif.master_scl_en <= 1;
        wait_clock_cycles(1);
    endtask : send_start_condition
    
    virtual task send_stop_condition();
        `uvm_info("I2C_DRIVER", "Sending STOP condition", UVM_HIGH)
        
        vif.master_sda_en <= 1;
        vif.master_scl_en <= 1;
        wait_clock_cycles(1);
        
        // SDA goes high while SCL is high
        vif.master_scl_en <= 0;
        wait_clock_cycles(1);
        vif.master_sda_en <= 0;
        wait_clock_cycles(1);
    endtask : send_stop_condition
    
    virtual task send_address(bit [6:0] address, bit read_write);
        bit [7:0] address_byte = {address, read_write};
        send_byte(address_byte);
    endtask : send_address
    
    virtual task send_byte(bit [7:0] data);
        for (int i = 7; i >= 0; i--) begin
            send_bit(data[i]);
        end
        receive_ack();  // Expect ACK from slave
    endtask : send_byte
    
    virtual task send_bit(bit bit_val);
        // Release SCL to allow slave to pull it (clock stretching tolerance)
        vif.master_scl_en <= 0;
        wait_clock_cycles(1);
        
        // Set SDA before releasing SCL
        vif.master_sda_en <= ~bit_val;  // 0 = low, 1 = release (open-drain)
        wait_clock_cycles(1);
        
        // Pull SCL low after SDA is stable
        vif.master_scl_en <= 1;
        wait_clock_cycles(1);
    endtask : send_bit
    
    virtual task receive_ack();
        bit ack_bit;
        
        // Release SDA for slave to pull low (ACK)
        vif.master_sda_en <= 0;  
        wait_clock_cycles(1);
        
        // SCL high for slave to acknowledge
        vif.master_scl_en <= 0;  // Release SCL
        wait_clock_cycles(1);
        
        // Wait for stable SCL high
        repeat(10) @(posedge vif.clk);
        
        ack_bit = vif.sda;
        `uvm_info("I2C_DRIVER", $sformatf("ACK bit received: %0d", ~ack_bit), UVM_HIGH)
        
        // Pull SCL low to complete the bit
        vif.master_scl_en <= 1;
        wait_clock_cycles(1);
    endtask : receive_ack
    
    virtual task receive_byte();
        bit [7:0] data = 0;
        
        for (int i = 7; i >= 0; i--) begin
            receive_bit(data[i]);
        end
    endtask : receive_byte
    
    virtual task receive_bit(output bit bit_val);
        // Release SDA for slave to control
        vif.master_sda_en <= 0;  
        wait_clock_cycles(1);
        
        // Release SCL to allow slave data
        vif.master_scl_en <= 0;
        wait_clock_cycles(1);
        
        // Wait for stable SCL high
        repeat(10) @(posedge vif.clk);
        
        // Read SDA on stable SCL high
        bit_val = vif.sda;
        
        // Pull SCL low to complete the bit
        vif.master_scl_en <= 1;
        wait_clock_cycles(1);
    endtask : receive_bit
    
    virtual task send_ack();
        vif.master_sda_en <= 1;  // Pull SDA low
        wait_clock_cycles(1);
        
        vif.master_scl_en <= 0;
        wait_clock_cycles(1);
        
        vif.master_sda_en <= 0;  // Release SDA
        wait_clock_cycles(1);
    endtask : send_ack
    
    virtual task send_nack();
        vif.master_sda_en <= 0;  // Release SDA
        wait_clock_cycles(1);
        
        vif.master_scl_en <= 0;
        wait_clock_cycles(1);
    endtask : send_nack
    
    virtual task wait_clock_cycles(int num);
        repeat (num * (SCL_PERIOD_NS / (2 * TIME_PERIOD_NS))) begin
            @(posedge vif.clk);
        end
    endtask : wait_clock_cycles
    
endclass : i2c_driver

// I2C Monitor
class i2c_monitor extends uvm_monitor;
    `uvm_component_utils(i2c_monitor)
    
    virtual i2c_if vif;
    uvm_analysis_port #(i2c_seq_item) item_collected_port;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction : new
    
    virtual task run_phase(uvm_run_phase phase);
        super.run_phase(phase);
        
        forever begin
            @(posedge vif.clk);
            // Monitor implementation would go here
        end
    endtask : run_phase
    
endclass : i2c_monitor
