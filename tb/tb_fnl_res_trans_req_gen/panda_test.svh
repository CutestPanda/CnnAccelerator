`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class FnlResTransReqGenBlkCtrlTestcase0Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase0Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 3;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 7;
			max_wgtblk_w == 4;
			
			is_grp_conv_mode == 1'b0;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase0Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase1Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase1Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 7;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 36;
			max_wgtblk_w == 8;
			
			is_grp_conv_mode == 1'b0;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase1Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase2Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase2Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 7;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 37;
			max_wgtblk_w == 8;
			
			is_grp_conv_mode == 1'b0;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase2Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase3Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase3Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 3;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 8;
			max_wgtblk_w == 4;
			
			is_grp_conv_mode == 1'b0;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase3Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase4Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase4Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 3;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 9;
			max_wgtblk_w == 4;
			
			is_grp_conv_mode == 1'b0;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase4Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase5Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase5Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 7;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 40;
			max_wgtblk_w == 8;
			
			is_grp_conv_mode == 1'b0;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase5Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase6Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase6Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 7;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 64;
			
			is_grp_conv_mode == 1'b1;
			group_n == 8;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase6Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase7Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase7Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 7;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 60;
			
			is_grp_conv_mode == 1'b1;
			group_n == 10;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase7Seq)
	
endclass

class FnlResTransReqGenBlkCtrlTestcase8Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlTestcase8Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_fnl_res_trans_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			ofmap_baseaddr == 512;
			
			ofmap_w == 13;
			ofmap_h == 7;
			ofmap_data_type == DATA_4_BYTE;
			
			kernal_num_n == 27;
			
			is_grp_conv_mode == 1'b1;
			group_n == 9;
		})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlTestcase8Seq)
	
endclass

class FnlResTransReqGenBlkCtrlAllcaseSeq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FnlResTransReqGenBlkCtrlAllcaseSeq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		FnlResTransReqGenBlkCtrlTestcase0Seq seq0;
		FnlResTransReqGenBlkCtrlTestcase1Seq seq1;
		FnlResTransReqGenBlkCtrlTestcase2Seq seq2;
		FnlResTransReqGenBlkCtrlTestcase3Seq seq3;
		FnlResTransReqGenBlkCtrlTestcase4Seq seq4;
		FnlResTransReqGenBlkCtrlTestcase5Seq seq5;
		FnlResTransReqGenBlkCtrlTestcase6Seq seq6;
		FnlResTransReqGenBlkCtrlTestcase7Seq seq7;
		FnlResTransReqGenBlkCtrlTestcase8Seq seq8;
		
		`uvm_do_with(seq0, {})
		`uvm_do_with(seq1, {})
		`uvm_do_with(seq2, {})
		`uvm_do_with(seq3, {})
		`uvm_do_with(seq4, {})
		`uvm_do_with(seq5, {})
		`uvm_do_with(seq6, {})
		`uvm_do_with(seq7, {})
		`uvm_do_with(seq8, {})
	endtask
	
	`uvm_object_utils(FnlResTransReqGenBlkCtrlAllcaseSeq)
	
endclass

class fnl_res_trans_req_gen_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int req_tr_mcd = UVM_STDOUT;
	
	local FnlResTransReqGenScoreboard scb;
	
	local panda_blk_ctrl_master_agent blk_ctrl_mst_agt;
	local panda_axis_slave_agent req_axis_slv_agt;
	local panda_axis_slave_agent msg_axis_slv_agt;
	
	local panda_blk_ctrl_configuration blk_ctrl_mst_cfg;
	local panda_axis_configuration req_axis_slv_cfg;
	local panda_axis_configuration msg_axis_slv_cfg;
	
	function new(string name = "fnl_res_trans_req_gen_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 10us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.blk_ctrl_tr_mcd = $fopen("blk_ctrl_tr_log.txt");
		this.req_tr_mcd = $fopen("req_tr_log.txt");
	endfunction
	
	protected function void build_configuration();
		this.blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("blk_ctrl_mst_cfg");
		if(!this.blk_ctrl_mst_cfg.randomize() with {
			params_width == 121;
			
			start_delay.min_delay == 0;
			start_delay.mid_delay[0] == 25;
			start_delay.mid_delay[1] == 40;
			start_delay.max_delay == 60;
			start_delay.weight_zero_delay == 1;
			start_delay.weight_short_delay == 3;
			start_delay.weight_long_delay == 2;
		})
			`uvm_fatal(this.get_name(), "cannot randomize blk_ctrl_mst_cfg!")
		this.blk_ctrl_mst_cfg.tr_factory = 
			panda_fnl_res_trans_req_gen_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		this.blk_ctrl_mst_cfg.complete_monitor_mode = 1'b0;
		
		this.req_axis_slv_cfg = panda_axis_configuration::type_id::create("req_axis_slv_cfg");
		if(!this.req_axis_slv_cfg.randomize() with {
			data_width == 56;
			user_width == 25;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 3;
			ready_delay.weight_short_delay == 1;
			ready_delay.weight_long_delay == 1;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize req_axis_slv_cfg!")
		
		this.msg_axis_slv_cfg = panda_axis_configuration::type_id::create("msg_axis_slv_cfg");
		if(!this.msg_axis_slv_cfg.randomize() with {
			data_width == 16;
			user_width == 0;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 3;
			ready_delay.weight_short_delay == 1;
			ready_delay.weight_long_delay == 1;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize msg_axis_slv_cfg!")
		
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(null, "", "blk_ctrl_vif_m", this.blk_ctrl_mst_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for blk_ctrl_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "req_axis_vif_s", this.req_axis_slv_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for req_axis_vif_s!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "msg_axis_vif_s", this.msg_axis_slv_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for msg_axis_vif_s!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.scb = FnlResTransReqGenScoreboard::type_id::create("fnl_res_trans_req_gen_scoreboard", this);
		this.scb.atomic_k = 4;
		
		this.blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("blk_ctrl_mst_agt", this);
		this.blk_ctrl_mst_agt.active_agent();
		this.blk_ctrl_mst_agt.set_configuration(this.blk_ctrl_mst_cfg);
		
		this.req_axis_slv_agt = panda_axis_slave_agent::type_id::create("req_axis_slv_agt", this);
		this.req_axis_slv_agt.active_agent();
		this.req_axis_slv_agt.set_configuration(this.req_axis_slv_cfg);
		
		this.msg_axis_slv_agt = panda_axis_slave_agent::type_id::create("msg_axis_slv_agt", this);
		this.msg_axis_slv_agt.active_agent();
		this.msg_axis_slv_agt.set_configuration(this.msg_axis_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.blk_ctrl_mst_agt.item_port.connect(this.scb.blk_ctrl_port);
		this.req_axis_slv_agt.item_port.connect(this.scb.req_port);
		
		this.blk_ctrl_mst_agt.sequencer.set_default_sequence("main_phase", FnlResTransReqGenBlkCtrlAllcaseSeq::type_id::get());
		this.req_axis_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
		this.msg_axis_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
		
		this.scb.set_blk_ctrl_tr_mcd(this.blk_ctrl_tr_mcd);
		this.scb.set_req_tr_mcd(this.req_tr_mcd);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.blk_ctrl_tr_mcd != UVM_STDOUT)
			$fclose(this.blk_ctrl_tr_mcd);
		
		if(this.req_tr_mcd != UVM_STDOUT)
			$fclose(this.req_tr_mcd);
	endfunction
	
	`uvm_component_utils(fnl_res_trans_req_gen_test)
	
endclass

`endif
