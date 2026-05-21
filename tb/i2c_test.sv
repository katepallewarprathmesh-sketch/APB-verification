// Base Test Class
class i2c_base_test extends uvm_test;
    `uvm_component_utils(i2c_base_test)
    
    i2c_env env;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
    virtual function void build_phase(uvm_build_phase phase);
        super.build_phase(phase);
        env = i2c_env::type_id::create("env", this);
    endfunction : build_phase
    
    virtual function void end_of_elaboration_phase(uvm_end_of_elaboration_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction : end_of_elaboration_phase
    
endclass : i2c_base_test

// Environment
class i2c_env extends uvm_env;
    `uvm_component_utils(i2c_env)
    
    virtual i2c_if vif;
    i2c_agent agent;
    i2c_scoreboard scoreboard;
    i2c_coverage coverage;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
    virtual function void build_phase(uvm_build_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db #(virtual i2c_if)::get(this, "", "i2c_if", vif))
            `uvm_fatal("I2C_ENV", "Failed to get i2c_if from config_db")
        
        agent = i2c_agent::type_id::create("agent", this);
        scoreboard = i2c_scoreboard::type_id::create("scoreboard", this);
        coverage = i2c_coverage::type_id::create("coverage", this);
    endfunction : build_phase
    
    virtual function void connect_phase(uvm_connect_phase phase);
        super.connect_phase(phase);
        agent.item_collected_port.connect(scoreboard.analysis_export);
        agent.item_collected_port.connect(coverage.analysis_export);
    endfunction : connect_phase
    
endclass : i2c_env

// Scoreboard
class i2c_scoreboard extends uvm_subscriber #(i2c_seq_item);
    `uvm_component_utils(i2c_scoreboard)
    
    int write_count = 0;
    int read_count = 0;
    int error_count = 0;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
    virtual function void write(i2c_seq_item t);
        `uvm_info("I2C_SCOREBOARD", $sformatf("Transaction: %s", t.convert2string()), UVM_MEDIUM)
        
        if (t.read_write == 0)
            write_count++;
        else
            read_count++;
        
        if (t.ack_error)
            error_count++;
    endfunction : write
    
    virtual function void report_phase(uvm_report_phase phase);
        super.report_phase(phase);
        
        `uvm_info("I2C_SCOREBOARD", "==== SCOREBOARD REPORT ====", UVM_MEDIUM)
        `uvm_info("I2C_SCOREBOARD", $sformatf("Write Operations: %0d", write_count), UVM_MEDIUM)
        `uvm_info("I2C_SCOREBOARD", $sformatf("Read Operations: %0d", read_count), UVM_MEDIUM)
        `uvm_info("I2C_SCOREBOARD", $sformatf("Error Count: %0d", error_count), UVM_MEDIUM)
        `uvm_info("I2C_SCOREBOARD", "==========================", UVM_MEDIUM)
    endfunction : report_phase
    
endclass : i2c_scoreboard

// Coverage
class i2c_coverage extends uvm_subscriber #(i2c_seq_item);
    `uvm_component_utils(i2c_coverage)
    
    covergroup i2c_cov;
        option.per_instance = 1;
        
        op_type: coverpoint last_item.read_write {
            bins write = {0};
            bins read = {1};
        }
        
        addr: coverpoint last_item.address {
            bins lower = {[0:63]};
            bins upper = {[64:127]};
        }
        
        data_pattern: coverpoint last_item.write_data.size() {
            bins single_byte = {1};
            bins multi_byte = {[2:$]};
        }
    endgroup : i2c_cov
    
    i2c_seq_item last_item;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        i2c_cov = new();
    endfunction : new
    
    virtual function void write(i2c_seq_item t);
        last_item = t;
        i2c_cov.sample();
    endfunction : write
    
    virtual function void report_phase(uvm_report_phase phase);
        super.report_phase(phase);
        `uvm_info("I2C_COVERAGE", "Coverage Report Generated", UVM_MEDIUM)
    endfunction : report_phase
    
endclass : i2c_coverage

// Write-Only Test
class i2c_write_test extends i2c_base_test;
    `uvm_component_utils(i2c_write_test)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
    virtual task run_phase(uvm_run_phase phase);
        i2c_write_seq write_seq = i2c_write_seq::type_id::create("write_seq");
        
        phase.raise_objection(this);
        
        `uvm_info("I2C_WRITE_TEST", "Starting write test", UVM_MEDIUM)
        write_seq.start(env.agent.sequencer);
        
        #200_000;
        phase.drop_objection(this);
    endtask : run_phase
    
endclass : i2c_write_test

// Read-Only Test
class i2c_read_test extends i2c_base_test;
    `uvm_component_utils(i2c_read_test)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
    virtual task run_phase(uvm_run_phase phase);
        i2c_read_seq read_seq = i2c_read_seq::type_id::create("read_seq");
        
        phase.raise_objection(this);
        
        `uvm_info("I2C_READ_TEST", "Starting read test", UVM_MEDIUM)
        read_seq.start(env.agent.sequencer);
        
        #200_000;
        phase.drop_objection(this);
    endtask : run_phase
    
endclass : i2c_read_test

// Random Test
class i2c_random_test extends i2c_base_test;
    `uvm_component_utils(i2c_random_test)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new
    
    virtual task run_phase(uvm_run_phase phase);
        i2c_random_seq random_seq = i2c_random_seq::type_id::create("random_seq");
        
        phase.raise_objection(this);
        
        `uvm_info("I2C_RANDOM_TEST", "Starting random test", UVM_MEDIUM)
        random_seq.start(env.agent.sequencer);
        
        #500_000;
        phase.drop_objection(this);
    endtask : run_phase
    
endclass : i2c_random_test

// Sequences
class i2c_base_seq extends uvm_sequence #(i2c_seq_item);
    `uvm_object_utils(i2c_base_seq)
    
    function new(string name = "i2c_base_seq");
        super.new(name);
    endfunction : new
    
endclass : i2c_base_seq

class i2c_write_seq extends i2c_base_seq;
    `uvm_object_utils(i2c_write_seq)
    
    function new(string name = "i2c_write_seq");
        super.new(name);
    endfunction : new
    
    virtual task body();
        repeat(5) begin
            `uvm_do_with(req, {
                req.read_write == 0;
                req.address == 7'h50;
                req.write_data.size() == 4;
                foreach (req.write_data[i]) req.write_data[i] inside {[0:255]};
            })
        end
    endtask : body
    
endclass : i2c_write_seq

class i2c_read_seq extends i2c_base_seq;
    `uvm_object_utils(i2c_read_seq)
    
    function new(string name = "i2c_read_seq");
        super.new(name);
    endfunction : new
    
    virtual task body();
        repeat(5) begin
            `uvm_do_with(req, {
                req.read_write == 1;
                req.address == 7'h50;
            })
        end
    endtask : body
    
endclass : i2c_read_seq

class i2c_random_seq extends i2c_base_seq;
    `uvm_object_utils(i2c_random_seq)
    
    function new(string name = "i2c_random_seq");
        super.new(name);
    endfunction : new
    
    virtual task body();
        repeat(10) begin
            `uvm_do(req)
        end
    endtask : body
    
endclass : i2c_random_seq
