`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class Cst0PackedReal extends PackedReal;
	
	constraint c_data{
		data dist{[-100.0:-1.0]:/2, 0.0:/1, [1.0:100.0]:/2};
	}
	
	`tue_object_default_constructor(Cst0PackedReal)
	`uvm_object_utils(Cst0PackedReal)
	
endclass

class Cst1PackedReal extends PackedReal;
	
	constraint c_data{
		data dist{0.0:/1};
	}
	
	`tue_object_default_constructor(Cst1PackedReal)
	`uvm_object_utils(Cst1PackedReal)
	
endclass

class ArrayInBaseSeq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	protected task run_tr(input int strm_len, input int sfc_depth, AbstractData local_data_gen);
		ArrayInTrans array_in_tr;
		
		`uvm_create(array_in_tr)
		
		array_in_tr.data_gen = local_data_gen;
		
		`uvm_rand_send_with(array_in_tr, {
			sfc_n == strm_len;
			vld_data_n_foreach_sfc == sfc_depth;
		})
	endtask
	
	`tue_object_default_constructor(ArrayInBaseSeq)
	
endclass

class ArrayInFtmTestcase0Seq extends ArrayInBaseSeq;
	
	function new(string name = "ArrayInFtmTestcase0Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		Cst0PackedReal normal_data_gen;
		Cst1PackedReal zero_data_gen;
		
		normal_data_gen = Cst0PackedReal::type_id::create("normal_data_gen");
		zero_data_gen = Cst1PackedReal::type_id::create("zero_data_gen");
		
		this.run_tr(1, 1, normal_data_gen);
		this.run_tr(1, 2, zero_data_gen);
		this.run_tr(1, 3, normal_data_gen);
		this.run_tr(1, 4, normal_data_gen);
		this.run_tr(2, 1, normal_data_gen);
		this.run_tr(2, 2, zero_data_gen);
		this.run_tr(2, 3, normal_data_gen);
		this.run_tr(2, 4, normal_data_gen);
		this.run_tr(3, 1, normal_data_gen);
		this.run_tr(3, 2, normal_data_gen);
		this.run_tr(3, 3, normal_data_gen);
		this.run_tr(3, 4, normal_data_gen);
		this.run_tr(4, 1, normal_data_gen);
		this.run_tr(4, 2, normal_data_gen);
		this.run_tr(4, 3, normal_data_gen);
		this.run_tr(4, 4, normal_data_gen);
	endtask
	
	`uvm_object_utils(ArrayInFtmTestcase0Seq)
	
endclass

class ArrayInFtmTestcase1Seq extends ArrayInBaseSeq;
	
	function new(string name = "ArrayInFtmTestcase1Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		Cst1PackedReal zero_data_gen;
		
		zero_data_gen = Cst1PackedReal::type_id::create("zero_data_gen");
		
		this.run_tr(1, 1, zero_data_gen);
		this.run_tr(1, 2, zero_data_gen);
		this.run_tr(1, 3, zero_data_gen);
		this.run_tr(1, 4, zero_data_gen);
		this.run_tr(2, 1, zero_data_gen);
		this.run_tr(2, 2, zero_data_gen);
		this.run_tr(2, 3, zero_data_gen);
		this.run_tr(2, 4, zero_data_gen);
		this.run_tr(3, 1, zero_data_gen);
		this.run_tr(3, 2, zero_data_gen);
		this.run_tr(3, 3, zero_data_gen);
		this.run_tr(3, 4, zero_data_gen);
		this.run_tr(4, 1, zero_data_gen);
		this.run_tr(4, 2, zero_data_gen);
		this.run_tr(4, 3, zero_data_gen);
		this.run_tr(4, 4, zero_data_gen);
	endtask
	
	`uvm_object_utils(ArrayInFtmTestcase1Seq)
	
endclass

class ArrayInKernalTestcase0Seq extends ArrayInBaseSeq;
	
	function new(string name = "ArrayInKernalTestcase0Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		Cst0PackedReal data_gen;
		
		data_gen = Cst0PackedReal::type_id::create("data_gen");
		
		this.run_tr(3, 1, data_gen);
		this.run_tr(3, 2, data_gen);
		this.run_tr(3, 3, data_gen);
		this.run_tr(3, 4, data_gen);
		this.run_tr(4, 1, data_gen);
		this.run_tr(4, 2, data_gen);
		this.run_tr(4, 3, data_gen);
		this.run_tr(4, 4, data_gen);
		this.run_tr(6, 1, data_gen);
		this.run_tr(6, 2, data_gen);
		this.run_tr(6, 3, data_gen);
		this.run_tr(6, 4, data_gen);
		this.run_tr(8, 1, data_gen);
		this.run_tr(8, 2, data_gen);
		this.run_tr(8, 3, data_gen);
		this.run_tr(8, 4, data_gen);
	endtask
	
	`uvm_object_utils(ArrayInKernalTestcase0Seq)
	
endclass

class ArrayInKernalTestcase1Seq extends ArrayInBaseSeq;
	
	function new(string name = "ArrayInKernalTestcase1Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		Cst0PackedReal data_gen;
		
		data_gen = Cst0PackedReal::type_id::create("data_gen");
		
		this.run_tr(6, 1, data_gen);
		this.run_tr(6, 2, data_gen);
		this.run_tr(6, 3, data_gen);
		this.run_tr(6, 4, data_gen);
		this.run_tr(8, 1, data_gen);
		this.run_tr(8, 2, data_gen);
		this.run_tr(8, 3, data_gen);
		this.run_tr(8, 4, data_gen);
		this.run_tr(12, 1, data_gen);
		this.run_tr(12, 2, data_gen);
		this.run_tr(12, 3, data_gen);
		this.run_tr(12, 4, data_gen);
		this.run_tr(16, 1, data_gen);
		this.run_tr(16, 2, data_gen);
		this.run_tr(16, 3, data_gen);
		this.run_tr(16, 4, data_gen);
	endtask
	
	`uvm_object_utils(ArrayInKernalTestcase1Seq)
	
endclass

class conv_mac_array_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local ConvMacArrayScoreboard scb;
	
	local panda_axis_master_agent array_i_ftm_agt;
	local panda_axis_master_agent array_i_kernal_agt;
	local panda_axis_slave_agent array_o_agt;
	
	local panda_axis_configuration array_i_ftm_cfg;
	local panda_axis_configuration array_i_kernal_cfg;
	local panda_axis_configuration array_o_cfg;
	
	function new(string name = "conv_mac_array_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 10us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		this.array_i_ftm_cfg = panda_axis_configuration::type_id::create("array_i_ftm_cfg");
		if(!this.array_i_ftm_cfg.randomize() with {
			data_width == 4*16;
			user_width == 4;
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 2;
			valid_delay.mid_delay[1] == 2;
			valid_delay.max_delay == 3;
			valid_delay.weight_zero_delay == 3;
			valid_delay.weight_short_delay == 2;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize array_i_ftm_cfg!")
		
		this.array_i_kernal_cfg = panda_axis_configuration::type_id::create("array_i_kernal_cfg");
		if(!this.array_i_kernal_cfg.randomize() with {
			data_width == 4*16;
			user_width == 0;
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 1;
			valid_delay.mid_delay[1] == 1;
			valid_delay.max_delay == 3;
			valid_delay.weight_zero_delay == 3;
			valid_delay.weight_short_delay == 1;
			valid_delay.weight_long_delay == 0;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize array_i_kernal_cfg!")
		
		this.array_o_cfg = panda_axis_configuration::type_id::create("array_o_cfg");
		if(!this.array_o_cfg.randomize() with {
			data_width == 8*48;
			user_width == 16;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 2;
			ready_delay.weight_short_delay == 1;
			ready_delay.weight_long_delay == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize array_o_cfg!")
		
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "array_i_ftm_vif_m", array_i_ftm_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for array_i_ftm_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "array_i_kernal_vif_m", array_i_kernal_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for array_i_kernal_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "array_o_vif_s", array_o_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for array_o_vif_s!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.scb = ConvMacArrayScoreboard::type_id::create("scoreboard", this);
		this.scb.cal_fmt = FP16;
		this.scb.atomic_c = 4;
		this.scb.atomic_k = 8;
		this.scb.cal_round_n = 2;
		
		this.array_i_ftm_agt = panda_axis_master_agent::type_id::create("array_i_ftm_agt", this);
		this.array_i_ftm_agt.active_agent();
		this.array_i_ftm_agt.set_configuration(this.array_i_ftm_cfg);
		
		this.array_i_kernal_agt = panda_axis_master_agent::type_id::create("array_i_kernal_agt", this);
		this.array_i_kernal_agt.active_agent();
		this.array_i_kernal_agt.set_configuration(this.array_i_kernal_cfg);
		
		this.array_o_agt = panda_axis_slave_agent::type_id::create("array_o_agt", this);
		this.array_o_agt.active_agent();
		this.array_o_agt.set_configuration(this.array_o_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.array_i_ftm_agt.item_port.connect(this.scb.array_i_ftm_port);
		this.array_i_kernal_agt.item_port.connect(this.scb.array_i_kernal_port);
		this.array_o_agt.item_port.connect(this.scb.array_o_port);
		
		this.array_i_ftm_agt.sequencer.set_default_sequence("main_phase", ArrayInFtmTestcase0Seq::type_id::get());
		this.array_i_kernal_agt.sequencer.set_default_sequence("main_phase", ArrayInKernalTestcase1Seq::type_id::get());
		this.array_o_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction
	
	`uvm_component_utils(conv_mac_array_test)
	
endclass

`endif
