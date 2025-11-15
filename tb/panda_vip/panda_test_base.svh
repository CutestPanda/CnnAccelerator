`ifndef __PANDA_TEST_BASE_H
`define __PANDA_TEST_BASE_H

virtual class panda_test_single_clk_base #(
	type CONFIGURATION = tue_configuration_dummy,
	type STATUS = tue_status_dummy
)extends tue_test #(CONFIGURATION, STATUS);
	
	protected realtime clk_period = 10ns;
	protected realtime rst_duration = 1us;
	protected realtime main_phase_drain_time = 10us;
	
	protected panda_clock_vif clk_vif;
	protected panda_reset_vif rst_vif;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if(!uvm_config_db #(panda_clock_vif)::get(null, "", "clk_vif", this.clk_vif))
			`uvm_fatal("panda_test_single_clk_base", "virtual interface must be set for clk_vif!!!")
		
		if(!uvm_config_db #(panda_reset_vif)::get(null, "", "rst_vif", this.rst_vif))
			`uvm_fatal("panda_test_single_clk_base", "virtual interface must be set for rst_vif!!!")
		
		this.build_configuration();
		this.build_status();
		this.build_agents();
	endfunction
	
	virtual task reset_phase(uvm_phase phase);
		phase.raise_objection(this);
		
		this.clk_vif.start(this.clk_period);
		this.rst_vif.initiate(this.rst_duration, 1'b1);
		
		phase.drop_objection(this);
	endtask
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		phase.phase_done.set_drain_time(this, main_phase_drain_time/`TIMEPRECISION);
	endtask
	
	virtual function void create_configuration();
		super.create_configuration();
    endfunction
	
	virtual function void create_status();
		super.create_status();
	endfunction
	
	virtual protected function void build_configuration();
		// blank
	endfunction
	
	virtual protected function void build_status();
		// blank
	endfunction
	
	virtual protected function void build_agents();
		// blank
	endfunction
	
	`tue_component_default_constructor(panda_test_single_clk_base)
	
endclass

virtual class panda_env #(
	type CONFIGURATION = tue_configuration_dummy,
	type STATUS = tue_status_dummy
)extends tue_component_base #(uvm_env, CONFIGURATION, STATUS);
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.build_configuration();
		this.build_status();
		this.build_agents();
	endfunction
	
	function void create_configuration();
		this.configuration = CONFIGURATION::type_id::create("configuration");
	endfunction
	
	virtual protected function void build_configuration();
		// blank
	endfunction
	
	virtual protected function void build_status();
		// blank
	endfunction
	
	virtual protected function void build_agents();
		// blank
	endfunction
	
	`tue_component_default_constructor(panda_env)
	
endclass

`endif
