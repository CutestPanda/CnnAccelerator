`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class KernalAcsReqGenBlkCtrlTestcase0Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand bit is_zero_delay = 1'b0;
	
	function new(string name = "KernalAcsReqGenBlkCtrlTestcase0Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_kernal_access_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			kernal_wgt_baseaddr == 1024;
			kernal_chn_n == 7;
			kernal_num_n == 9;
			kernal_shape == KBUFGRPSZ_3x3;
			ofmap_h == 2;
			is_grp_conv_mode == 1'b0;
			cgrpn_foreach_kernal_set == 2;
			max_wgtblk_w == 8;
			
			if(is_zero_delay){
				process_start_delay == 0;
			}
		})
	endtask
	
	`uvm_object_utils(KernalAcsReqGenBlkCtrlTestcase0Seq)
	
endclass

class KernalAcsReqGenBlkCtrlTestcase1Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand bit is_zero_delay = 1'b0;
	
	function new(string name = "KernalAcsReqGenBlkCtrlTestcase1Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_kernal_access_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			kernal_wgt_baseaddr == 1024;
			kernal_chn_n == 12;
			kernal_num_n == 23;
			kernal_shape == KBUFGRPSZ_3x3;
			ofmap_h == 3;
			is_grp_conv_mode == 1'b0;
			cgrpn_foreach_kernal_set == 3;
			max_wgtblk_w == 8;
			
			if(is_zero_delay){
				process_start_delay == 0;
			}
		})
	endtask
	
	`uvm_object_utils(KernalAcsReqGenBlkCtrlTestcase1Seq)
	
endclass

class KernalAcsReqGenBlkCtrlTestcase2Seq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand bit is_zero_delay = 1'b0;
	
	function new(string name = "KernalAcsReqGenBlkCtrlTestcase2Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_kernal_access_req_gen_blk_ctrl_trans tr;
		
		`uvm_do_with(tr, {
			kernal_wgt_baseaddr == 1024;
			kernal_chn_n == 18;
			kernal_num_n == 18;
			kernal_shape == KBUFGRPSZ_3x3;
			ofmap_h == 3;
			is_grp_conv_mode == 1'b1;
			group_n == 3;
			cgrpn_foreach_kernal_set == 2;
			max_wgtblk_w == 8;
			
			if(is_zero_delay){
				process_start_delay == 0;
			}
		})
	endtask
	
	`uvm_object_utils(KernalAcsReqGenBlkCtrlTestcase2Seq)
	
endclass

class KernalAcsReqGenBlkCtrlAllcaseSeq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "KernalAcsReqGenBlkCtrlAllcaseSeq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		KernalAcsReqGenBlkCtrlTestcase0Seq seq0;
		KernalAcsReqGenBlkCtrlTestcase1Seq seq1;
		KernalAcsReqGenBlkCtrlTestcase2Seq seq2;
		
		`uvm_do_with(seq0, {
			is_zero_delay == 1'b1;
		})
		
		`uvm_do_with(seq1, {
			is_zero_delay == 1'b0;
		})
		
		`uvm_do_with(seq2, {
			is_zero_delay == 1'b1;
		})
	endtask
	
	`uvm_object_utils(KernalAcsReqGenBlkCtrlAllcaseSeq)
	
endclass

class kernal_access_req_gen_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int rd_req_tr_mcd = UVM_STDOUT;
	
	local KernalAccessReqGenScoreboard scb;
	
	local panda_blk_ctrl_master_agent blk_ctrl_mst_agt;
	local panda_axis_slave_agent kwgtblk_rd_req_axis_slv_agt;
	
	local panda_blk_ctrl_configuration blk_ctrl_mst_cfg;
	local panda_axis_configuration kwgtblk_rd_req_axis_slv_cfg;
	
	function new(string name = "kernal_access_req_gen_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 10us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.blk_ctrl_tr_mcd = $fopen("blk_ctrl_tr_log.txt");
		this.rd_req_tr_mcd = $fopen("rd_req_tr_log.txt");
	endfunction
	
	protected function void build_configuration();
		this.blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("blk_ctrl_mst_cfg");
		if(!this.blk_ctrl_mst_cfg.randomize() with {
			params_width == 139;
			
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
			panda_kernal_access_req_gen_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		
		this.kwgtblk_rd_req_axis_slv_cfg = panda_axis_configuration::type_id::create("kwgtblk_rd_req_axis_slv_cfg");
		if(!this.kwgtblk_rd_req_axis_slv_cfg.randomize() with {
			data_width == 104;
			user_width == 0;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 3;
			ready_delay.weight_short_delay == 0;
			ready_delay.weight_long_delay == 0;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize kwgtblk_rd_req_axis_slv_cfg!")
		
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(null, "", "blk_ctrl_vif_m", blk_ctrl_mst_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for blk_ctrl_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "kwgtblk_rd_req_axis_vif_s", kwgtblk_rd_req_axis_slv_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for kwgtblk_rd_req_axis_vif_s!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.scb = KernalAccessReqGenScoreboard::type_id::create("kernal_access_req_gen_scoreboard", this);
		this.scb.atomic_c = 4;
		this.scb.atomic_k = 8;
		
		this.blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("blk_ctrl_mst_agt", this);
		this.blk_ctrl_mst_agt.active_agent();
		this.blk_ctrl_mst_agt.set_configuration(this.blk_ctrl_mst_cfg);
		
		this.kwgtblk_rd_req_axis_slv_agt = panda_axis_slave_agent::type_id::create("kwgtblk_rd_req_axis_slv_agt", this);
		this.kwgtblk_rd_req_axis_slv_agt.active_agent();
		this.kwgtblk_rd_req_axis_slv_agt.set_configuration(this.kwgtblk_rd_req_axis_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.blk_ctrl_mst_agt.item_port.connect(this.scb.blk_ctrl_port);
		this.kwgtblk_rd_req_axis_slv_agt.item_port.connect(this.scb.kwgtblk_rd_req_port);
		
		this.blk_ctrl_mst_agt.sequencer.set_default_sequence("main_phase", KernalAcsReqGenBlkCtrlAllcaseSeq::type_id::get());
		this.kwgtblk_rd_req_axis_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
		
		this.scb.set_blk_ctrl_tr_mcd(this.blk_ctrl_tr_mcd);
		this.scb.set_rd_req_tr_mcd(this.rd_req_tr_mcd);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		$fclose(this.blk_ctrl_tr_mcd);
		$fclose(this.rd_req_tr_mcd);
	endfunction
	
	`uvm_component_utils(kernal_access_req_gen_test)
	
endclass

`endif
