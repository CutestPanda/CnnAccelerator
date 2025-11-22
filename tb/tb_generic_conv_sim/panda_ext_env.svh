`ifndef __PANDA_EXT_ENV_H
`define __PANDA_EXT_ENV_H

class FmapReqGenTestEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int rd_req_tr_mcd = UVM_STDOUT;
	
	local FmapAccessReqGenScoreboard scb;
	
	local panda_blk_ctrl_master_agent blk_ctrl_mst_agt;
	local panda_axis_slave_agent rd_req_axis_slv_agt;
	local panda_axis_slave_agent fm_cake_info_axis_slv_agt;
	
	local ConvCalCfg cal_cfg;
	
	local panda_blk_ctrl_configuration blk_ctrl_mst_cfg;
	local panda_axis_configuration rd_req_axis_slv_cfg;
	local panda_axis_configuration fm_cake_info_axis_slv_cfg;
	
	function new(string name = "FmapReqGenTestEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.blk_ctrl_tr_mcd = $fopen("fmap_blk_ctrl_tr_log.txt");
		this.rd_req_tr_mcd = $fopen("fmap_rd_req_tr_log_1.txt");
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(ConvCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		
		this.blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("blk_ctrl_mst_cfg");
		if(!this.blk_ctrl_mst_cfg.randomize() with {
			params_width == 212;
		})
			`uvm_fatal(this.get_name(), "cannot randomize blk_ctrl_mst_cfg!")
		this.blk_ctrl_mst_cfg.tr_factory = 
			panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		this.blk_ctrl_mst_cfg.complete_monitor_mode = 1'b0;
		
		this.rd_req_axis_slv_cfg = panda_axis_configuration::type_id::create("rd_req_axis_slv_cfg");
		if(!this.rd_req_axis_slv_cfg.randomize() with {
			data_width == 104;
			user_width == 0;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize rd_req_axis_slv_cfg!")
		
		this.fm_cake_info_axis_slv_cfg = panda_axis_configuration::type_id::create("fm_cake_info_axis_slv_cfg");
		if(!this.fm_cake_info_axis_slv_cfg.randomize() with {
			data_width == 8;
			user_width == 0;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize fm_cake_info_axis_slv_cfg!")
		
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(null, "", "fmap_blk_ctrl_vif", blk_ctrl_mst_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fmap_blk_ctrl_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fmap_rd_req_axis_vif", rd_req_axis_slv_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fmap_rd_req_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fm_cake_info_axis_vif", fm_cake_info_axis_slv_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fm_cake_info_axis_vif!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.scb = FmapAccessReqGenScoreboard::type_id::create("fmap_access_req_gen_scoreboard", this);
		this.scb.atomic_c = this.cal_cfg.atomic_c;
		
		this.blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("blk_ctrl_mst_agt", this);
		this.blk_ctrl_mst_agt.passive_agent();
		this.blk_ctrl_mst_agt.set_configuration(this.blk_ctrl_mst_cfg);
		
		this.rd_req_axis_slv_agt = panda_axis_slave_agent::type_id::create("rd_req_axis_slv_agt", this);
		this.rd_req_axis_slv_agt.passive_agent();
		this.rd_req_axis_slv_agt.set_configuration(this.rd_req_axis_slv_cfg);
		
		this.fm_cake_info_axis_slv_agt = panda_axis_slave_agent::type_id::create("fm_cake_info_axis_slv_agt", this);
		this.fm_cake_info_axis_slv_agt.passive_agent();
		this.fm_cake_info_axis_slv_agt.set_configuration(this.fm_cake_info_axis_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.blk_ctrl_mst_agt.item_port.connect(this.scb.blk_ctrl_port);
		this.rd_req_axis_slv_agt.item_port.connect(this.scb.rd_req_port);
		
		this.scb.set_blk_ctrl_tr_mcd(this.blk_ctrl_tr_mcd);
		this.scb.set_rd_req_tr_mcd(this.rd_req_tr_mcd);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.blk_ctrl_tr_mcd != UVM_STDOUT)
			$fclose(this.blk_ctrl_tr_mcd);
		
		if(this.rd_req_tr_mcd != UVM_STDOUT)
			$fclose(this.rd_req_tr_mcd);
	endfunction
	
	`uvm_component_utils(FmapReqGenTestEnv)
	
endclass

class KernalReqGenTestEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int rd_req_tr_mcd = UVM_STDOUT;
	
	local KernalAccessReqGenScoreboard scb;
	
	local panda_blk_ctrl_master_agent blk_ctrl_mst_agt;
	local panda_axis_slave_agent rd_req_axis_slv_agt;
	
	local ConvCalCfg cal_cfg;
	
	local panda_blk_ctrl_configuration blk_ctrl_mst_cfg;
	local panda_axis_configuration rd_req_axis_slv_cfg;
	
	function new(string name = "KernalReqGenTestEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.blk_ctrl_tr_mcd = $fopen("kernal_blk_ctrl_tr_log.txt");
		this.rd_req_tr_mcd = $fopen("kernal_rd_req_tr_log_1.txt");
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(ConvCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		
		this.blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("blk_ctrl_mst_cfg");
		if(!this.blk_ctrl_mst_cfg.randomize() with {
			params_width == 168;
		})
			`uvm_fatal(this.get_name(), "cannot randomize blk_ctrl_mst_cfg!")
		this.blk_ctrl_mst_cfg.tr_factory = 
			panda_kernal_access_req_gen_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		this.blk_ctrl_mst_cfg.complete_monitor_mode = 1'b0;
		
		this.rd_req_axis_slv_cfg = panda_axis_configuration::type_id::create("rd_req_axis_slv_cfg");
		if(!this.rd_req_axis_slv_cfg.randomize() with {
			data_width == 104;
			user_width == 0;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize rd_req_axis_slv_cfg!")
		
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(null, "", "kernal_blk_ctrl_vif", blk_ctrl_mst_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for kernal_blk_ctrl_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "kernal_rd_req_axis_vif", rd_req_axis_slv_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for kernal_rd_req_axis_vif!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.scb = KernalAccessReqGenScoreboard::type_id::create("kernal_access_req_gen_scoreboard", this);
		this.scb.atomic_c = this.cal_cfg.atomic_c;
		this.scb.atomic_k = this.cal_cfg.max_wgtblk_w;
		
		this.blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("blk_ctrl_mst_agt", this);
		this.blk_ctrl_mst_agt.passive_agent();
		this.blk_ctrl_mst_agt.set_configuration(this.blk_ctrl_mst_cfg);
		
		this.rd_req_axis_slv_agt = panda_axis_slave_agent::type_id::create("rd_req_axis_slv_agt", this);
		this.rd_req_axis_slv_agt.passive_agent();
		this.rd_req_axis_slv_agt.set_configuration(this.rd_req_axis_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.blk_ctrl_mst_agt.item_port.connect(this.scb.blk_ctrl_port);
		this.rd_req_axis_slv_agt.item_port.connect(this.scb.kwgtblk_rd_req_port);
		
		this.scb.set_blk_ctrl_tr_mcd(this.blk_ctrl_tr_mcd);
		this.scb.set_rd_req_tr_mcd(this.rd_req_tr_mcd);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.blk_ctrl_tr_mcd != UVM_STDOUT)
			$fclose(this.blk_ctrl_tr_mcd);
		
		if(this.rd_req_tr_mcd != UVM_STDOUT)
			$fclose(this.rd_req_tr_mcd);
	endfunction
	
	`uvm_component_utils(KernalReqGenTestEnv)
	
endclass

class ConvDataHubTestEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local int fmap_rd_req_tr_mcd = UVM_STDOUT;
	local int kernal_rd_req_tr_mcd = UVM_STDOUT;
	
	local DmaStrmAxisVsqr dma_axis_vsqr[2];
	
	local FmBufScoreboard fm_buf_scb;
	local KernalBufScoreboard kernal_buf_scb;
	
	local panda_axis_master_agent fm_rd_req_axis_mst_agt;
	local panda_axis_slave_agent fm_fout_axis_slv_agt;
	local panda_axis_master_agent kwgtblk_rd_req_axis_mst_agt;
	local panda_axis_slave_agent kout_wgtblk_axis_slv_agt;
	local panda_axis_master_agent dma_strm_axis_mst_agt[2];
	local panda_axis_slave_agent dma_cmd_axis_slv_agt[2];
	
	local panda_axis_configuration rd_req_axis_mst_cfg[2];
	local panda_axis_configuration dout_axis_slv_cfg[2];
	local panda_axis_configuration dma_strm_axis_mst_cfg[2];
	local panda_axis_configuration dma_cmd_axis_slv_cfg[2];
	
	local ConvCalCfg cal_cfg;
	local BufferCfg buf_cfg;
	
	function new(string name = "ConvDataHubTestEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.fmap_rd_req_tr_mcd = $fopen("fmap_rd_req_tr_log_2.txt");
		this.kernal_rd_req_tr_mcd = $fopen("kernal_rd_req_tr_log_2.txt");
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(ConvCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		if(!uvm_config_db #(BufferCfg)::get(null, "", "buf_cfg", this.buf_cfg))
			`uvm_fatal(this.get_name(), "cannot get buf_cfg!!!")
		
		this.rd_req_axis_mst_cfg[0] = panda_axis_configuration::type_id::create("rd_req_axis_mst_cfg");
		if(!this.rd_req_axis_mst_cfg[0].randomize() with {
			data_width == 104;
			user_width == 0;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize rd_req_axis_mst_cfg!")
		
		if(!$cast(this.rd_req_axis_mst_cfg[1], this.rd_req_axis_mst_cfg[0].clone()))
			`uvm_fatal(this.get_name(), "cannot cast rd_req_axis_mst_cfg_clone!!!")
		
		this.dout_axis_slv_cfg[0] = panda_axis_configuration::type_id::create("dout_axis_slv_cfg");
		if(!this.dout_axis_slv_cfg[0].randomize() with {
			data_width == (cal_cfg.atomic_c * 2 * 8);
			user_width == 0;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dout_axis_slv_cfg!")
		
		if(!$cast(this.dout_axis_slv_cfg[1], this.dout_axis_slv_cfg[0].clone()))
			`uvm_fatal(this.get_name(), "cannot cast dout_axis_slv_cfg_clone!!!")
		
		this.dma_strm_axis_mst_cfg[0] = panda_axis_configuration::type_id::create("dma_strm_axis_mst_cfg");
		if(!this.dma_strm_axis_mst_cfg[0].randomize() with {
			data_width == buf_cfg.stream_data_width;
			user_width == 0;
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 1;
			valid_delay.mid_delay[1] == 1;
			valid_delay.max_delay == 2;
			valid_delay.weight_zero_delay == 3;
			valid_delay.weight_short_delay == 2;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b1;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dma_strm_axis_mst_cfg!")
		
		if(!$cast(this.dma_strm_axis_mst_cfg[1], this.dma_strm_axis_mst_cfg[0].clone()))
			`uvm_fatal(this.get_name(), "cannot cast dma_strm_axis_mst_cfg_clone!!!")
		
		this.dma_cmd_axis_slv_cfg[0] = panda_axis_configuration::type_id::create("dma_cmd_axis_slv_cfg");
		if(!this.dma_cmd_axis_slv_cfg[0].randomize() with {
			data_width == 56;
			user_width == 1;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 30;
			ready_delay.mid_delay[1] == 50;
			ready_delay.max_delay == 60;
			ready_delay.weight_zero_delay == 1;
			ready_delay.weight_short_delay == 6;
			ready_delay.weight_long_delay == 3;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dma_cmd_axis_slv_cfg!")
		
		if(!$cast(this.dma_cmd_axis_slv_cfg[1], this.dma_cmd_axis_slv_cfg[0].clone()))
			`uvm_fatal(this.get_name(), "cannot cast dma_cmd_axis_slv_cfg_clone!!!")
		
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fmap_rd_req_axis_vif", rd_req_axis_mst_cfg[0].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fmap_rd_req_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "kernal_rd_req_axis_vif", rd_req_axis_mst_cfg[1].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for kernal_rd_req_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fm_fout_axis_vif", dout_axis_slv_cfg[0].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fm_fout_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "kout_wgtblk_axis_vif", dout_axis_slv_cfg[1].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for kout_wgtblk_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma0_strm_axis_vif", dma_strm_axis_mst_cfg[0].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma0_strm_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma1_strm_axis_vif", dma_strm_axis_mst_cfg[1].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma1_strm_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma0_cmd_axis_vif", dma_cmd_axis_slv_cfg[0].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma0_cmd_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma1_cmd_axis_vif", dma_cmd_axis_slv_cfg[1].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma1_cmd_axis_vif!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.dma_axis_vsqr[0] = DmaStrmAxisVsqr::type_id::create("dma_axis_vsqr_0", this);
		this.dma_axis_vsqr[1] = DmaStrmAxisVsqr::type_id::create("dma_axis_vsqr_1", this);
		
		this.fm_buf_scb = FmBufScoreboard::type_id::create("fm_buf_scb", this);
		this.kernal_buf_scb = KernalBufScoreboard::type_id::create("kernal_buf_scb", this);
		
		this.fm_rd_req_axis_mst_agt = panda_axis_master_agent::type_id::create("fm_rd_req_axis_mst_agt", this);
		this.fm_rd_req_axis_mst_agt.passive_agent();
		this.fm_rd_req_axis_mst_agt.set_configuration(this.rd_req_axis_mst_cfg[0]);
		
		this.fm_fout_axis_slv_agt = panda_axis_slave_agent::type_id::create("fm_fout_axis_slv_agt", this);
		this.fm_fout_axis_slv_agt.passive_agent();
		this.fm_fout_axis_slv_agt.set_configuration(this.dout_axis_slv_cfg[0]);
		
		this.kwgtblk_rd_req_axis_mst_agt = panda_axis_master_agent::type_id::create("kwgtblk_rd_req_axis_mst_agt", this);
		this.kwgtblk_rd_req_axis_mst_agt.passive_agent();
		this.kwgtblk_rd_req_axis_mst_agt.set_configuration(this.rd_req_axis_mst_cfg[1]);
		
		this.kout_wgtblk_axis_slv_agt = panda_axis_slave_agent::type_id::create("kout_wgtblk_axis_slv_agt", this);
		this.kout_wgtblk_axis_slv_agt.passive_agent();
		this.kout_wgtblk_axis_slv_agt.set_configuration(this.dout_axis_slv_cfg[1]);
		
		this.dma_strm_axis_mst_agt[0] = panda_axis_master_agent::type_id::create("dma_strm_axis_mst_agt_0", this);
		this.dma_strm_axis_mst_agt[0].active_agent();
		this.dma_strm_axis_mst_agt[0].set_configuration(this.dma_strm_axis_mst_cfg[0]);
		
		this.dma_cmd_axis_slv_agt[0] = panda_axis_slave_agent::type_id::create("dma_cmd_axis_slv_agt_0", this);
		this.dma_cmd_axis_slv_agt[0].active_agent();
		this.dma_cmd_axis_slv_agt[0].set_configuration(this.dma_cmd_axis_slv_cfg[0]);
		
		this.dma_strm_axis_mst_agt[1] = panda_axis_master_agent::type_id::create("dma_strm_axis_mst_agt_1", this);
		this.dma_strm_axis_mst_agt[1].active_agent();
		this.dma_strm_axis_mst_agt[1].set_configuration(this.dma_strm_axis_mst_cfg[1]);
		
		this.dma_cmd_axis_slv_agt[1] = panda_axis_slave_agent::type_id::create("dma_cmd_axis_slv_agt_1", this);
		this.dma_cmd_axis_slv_agt[1].active_agent();
		this.dma_cmd_axis_slv_agt[1].set_configuration(this.dma_cmd_axis_slv_cfg[1]);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.dma_axis_vsqr[0].dma_strm_axis_sqr = this.dma_strm_axis_mst_agt[0].sequencer;
		this.dma_axis_vsqr[0].dma_cmd_axis_sqr = this.dma_cmd_axis_slv_agt[0].sequencer;
		this.dma_axis_vsqr[1].dma_strm_axis_sqr = this.dma_strm_axis_mst_agt[1].sequencer;
		this.dma_axis_vsqr[1].dma_cmd_axis_sqr = this.dma_cmd_axis_slv_agt[1].sequencer;
		
		this.dma_axis_vsqr[0].set_default_sequence("main_phase", DmaStrmAxisVseq #(.MEM_NAME("fmap_mem"))::type_id::get());
		this.dma_axis_vsqr[1].set_default_sequence("main_phase", DmaStrmAxisVseq #(.MEM_NAME("kernal_mem"))::type_id::get());
		
		this.fm_rd_req_axis_mst_agt.item_port.connect(this.fm_buf_scb.rd_req_port);
		this.fm_fout_axis_slv_agt.item_port.connect(this.fm_buf_scb.fout_port);
		
		this.kwgtblk_rd_req_axis_mst_agt.item_port.connect(this.kernal_buf_scb.rd_req_port);
		this.kout_wgtblk_axis_slv_agt.item_port.connect(this.kernal_buf_scb.fout_port);
		
		this.fm_buf_scb.set_rd_req_tr_mcd(this.fmap_rd_req_tr_mcd);
		this.kernal_buf_scb.set_rd_req_tr_mcd(this.kernal_rd_req_tr_mcd);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.fmap_rd_req_tr_mcd != UVM_STDOUT)
			$fclose(this.fmap_rd_req_tr_mcd);
		
		if(this.kernal_rd_req_tr_mcd != UVM_STDOUT)
			$fclose(this.kernal_rd_req_tr_mcd);
	endfunction
	
	`uvm_component_utils(ConvDataHubTestEnv)
	
endclass

class GenericConvSimTestEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	typedef bit[1:0] bit2;
	typedef bit[2:0] bit3;
	typedef bit[3:0] bit4;
	
	local virtual generic_conv_sim_cfg_if cfg_vif;
	
	local int final_res_tr_mcd = UVM_STDOUT;
	
	local FinalResScoreboard final_res_scb;
	
	local panda_blk_ctrl_master_agent fmap_blk_ctrl_mst_agt;
	local panda_blk_ctrl_master_agent kernal_blk_ctrl_mst_agt;
	local panda_axis_slave_agent final_res_slv_agt;
	
	local panda_blk_ctrl_configuration fmap_blk_ctrl_mst_cfg;
	local panda_blk_ctrl_configuration kernal_blk_ctrl_mst_cfg;
	local panda_axis_configuration final_res_slv_cfg;
	
	local FmapCfg fmap_cfg;
	local KernalCfg kernal_cfg;
	local ConvCalCfg cal_cfg;
	local BufferCfg buf_cfg;
	
	local FmapOutPtCalProcListener cal_proc_listener = null;
	
	function void register_cal_proc_listener(FmapOutPtCalProcListener listener);
		this.cal_proc_listener = listener;
	endfunction
	
	function new(string name = "GenericConvSimTestEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.final_res_tr_mcd = $fopen("final_res_tr_log.txt");
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(FmapCfg)::get(null, "", "fmap_cfg", this.fmap_cfg))
			`uvm_fatal(this.get_name(), "cannot get fmap_cfg!!!")
		if(!uvm_config_db #(KernalCfg)::get(null, "", "kernal_cfg", this.kernal_cfg))
			`uvm_fatal(this.get_name(), "cannot get kernal_cfg!!!")
		if(!uvm_config_db #(ConvCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		if(!uvm_config_db #(BufferCfg)::get(null, "", "buf_cfg", this.buf_cfg))
			`uvm_fatal(this.get_name(), "cannot get buf_cfg!!!")
		
		this.fmap_blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("fmap_blk_ctrl_mst_cfg");
		if(!this.fmap_blk_ctrl_mst_cfg.randomize() with {
			params_width == 0;
			
			start_delay.min_delay == 0;
			start_delay.mid_delay[0] == 25;
			start_delay.mid_delay[1] == 40;
			start_delay.max_delay == 60;
			start_delay.weight_zero_delay == 1;
			start_delay.weight_short_delay == 3;
			start_delay.weight_long_delay == 2;
		})
			`uvm_fatal(this.get_name(), "cannot randomize fmap_blk_ctrl_mst_cfg!")
		this.fmap_blk_ctrl_mst_cfg.tr_factory = 
			panda_dummy_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		this.fmap_blk_ctrl_mst_cfg.complete_monitor_mode = 1'b0;
		
		this.kernal_blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("kernal_blk_ctrl_mst_cfg");
		if(!this.kernal_blk_ctrl_mst_cfg.randomize() with {
			params_width == 0;
			
			start_delay.min_delay == 0;
			start_delay.mid_delay[0] == 25;
			start_delay.mid_delay[1] == 40;
			start_delay.max_delay == 60;
			start_delay.weight_zero_delay == 1;
			start_delay.weight_short_delay == 3;
			start_delay.weight_long_delay == 2;
		})
			`uvm_fatal(this.get_name(), "cannot randomize kernal_blk_ctrl_mst_cfg!")
		this.kernal_blk_ctrl_mst_cfg.tr_factory = 
			panda_dummy_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		this.kernal_blk_ctrl_mst_cfg.complete_monitor_mode = 1'b0;
		
		this.final_res_slv_cfg = panda_axis_configuration::type_id::create("final_res_slv_cfg");
		if(!this.final_res_slv_cfg.randomize() with {
			data_width == buf_cfg.fnl_res_data_width;
			user_width == 5;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 2;
			ready_delay.weight_short_delay == 0;
			ready_delay.weight_long_delay == 1;
			
			default_ready == 1'b1;
			has_keep == 1'b1;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize final_res_slv_cfg!")
		
		if(!uvm_config_db #(virtual generic_conv_sim_cfg_if)::get(null, "", "cfg_vif", this.cfg_vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for cfg_vif!!!")
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(null, "", "fmap_blk_ctrl_vif_2", fmap_blk_ctrl_mst_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fmap_blk_ctrl_vif_2!!!")
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(null, "", "kernal_blk_ctrl_vif_2", kernal_blk_ctrl_mst_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for kernal_blk_ctrl_vif_2!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "final_res_axis_vif", final_res_slv_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for final_res_axis_vif!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.final_res_scb = FinalResScoreboard::type_id::create("final_res_scb", this);
		this.final_res_scb.register_cal_proc_listener(this.cal_proc_listener);
		
		this.fmap_blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("fmap_blk_ctrl_mst_agt", this);
		this.fmap_blk_ctrl_mst_agt.active_agent();
		this.fmap_blk_ctrl_mst_agt.set_configuration(this.fmap_blk_ctrl_mst_cfg);
		
		this.kernal_blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("kernal_blk_ctrl_mst_agt", this);
		this.kernal_blk_ctrl_mst_agt.active_agent();
		this.kernal_blk_ctrl_mst_agt.set_configuration(this.kernal_blk_ctrl_mst_cfg);
		
		this.final_res_slv_agt = panda_axis_slave_agent::type_id::create("final_res_slv_agt", this);
		this.final_res_slv_agt.active_agent();
		this.final_res_slv_agt.set_configuration(this.final_res_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.final_res_slv_agt.item_port.connect(this.final_res_scb.final_res_port);
		this.final_res_scb.set_final_res_tr_mcd(this.final_res_tr_mcd);
		
		this.fmap_blk_ctrl_mst_agt.sequencer.set_default_sequence("main_phase", ReqGenBlkCtrlDefaultSeq::type_id::get());
		this.kernal_blk_ctrl_mst_agt.sequencer.set_default_sequence("main_phase", ReqGenBlkCtrlDefaultSeq::type_id::get());
		this.final_res_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
	endfunction
	
	task reset_phase(uvm_phase phase);
		phase.raise_objection(this);
		
		this.cfg_vif.master_cb.en_mac_array <= 1'b0;
		this.cfg_vif.master_cb.en_packer <= 1'b0;
		
		repeat(4)
			@(this.cfg_vif.master_cb);
		
		phase.drop_objection(this);
	endtask
	
	task configure_phase(uvm_phase phase);
		int unsigned n_foreach_group; // 每组的通道数/核数
		int unsigned c_foreach_set; // 每个核组的通道数
		int unsigned ext_fmap_w; // 扩展特征图宽度
		int unsigned ext_fmap_h; // 扩展特征图高度
		int unsigned kernal_x_dilated; // (膨胀后)卷积核宽度或高度
		
		n_foreach_group = 
			this.kernal_cfg.kernal_chn_n / this.cal_cfg.group_n;
		c_foreach_set = 
			this.cal_cfg.is_grp_conv_mode ? n_foreach_group:this.kernal_cfg.kernal_chn_n;
		ext_fmap_w = 
			this.fmap_cfg.fmap_w + this.cal_cfg.external_padding_left + this.cal_cfg.external_padding_right + 
			(this.fmap_cfg.fmap_w - 1) * this.cal_cfg.inner_padding_left_right;
		ext_fmap_h = 
			this.fmap_cfg.fmap_h + this.cal_cfg.external_padding_top + this.cal_cfg.external_padding_bottom + 
			(this.fmap_cfg.fmap_h - 1) * this.cal_cfg.inner_padding_top_bottom;
		kernal_x_dilated = 
			Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape) + 
			(Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape) - 1) * this.cal_cfg.kernal_dilation_n;
		
		phase.raise_objection(this);
		
		this.cfg_vif.master_cb.calfmt <= bit2'(this.cal_cfg.calfmt);
		this.cfg_vif.master_cb.conv_vertical_stride <= this.cal_cfg.conv_vertical_stride - 1;
		this.cfg_vif.master_cb.conv_horizontal_stride <= this.cal_cfg.conv_horizontal_stride - 1;
		this.cfg_vif.master_cb.cal_round <= this.cal_cfg.cal_round - 1;
		
		this.cfg_vif.master_cb.is_grp_conv_mode <= this.cal_cfg.is_grp_conv_mode;
		this.cfg_vif.master_cb.group_n <= this.cal_cfg.group_n - 1;
		this.cfg_vif.master_cb.n_foreach_group <= n_foreach_group - 1;
		this.cfg_vif.master_cb.data_size_foreach_group <= 
			this.fmap_cfg.fmap_w * this.fmap_cfg.fmap_h * n_foreach_group * ((this.cal_cfg.calfmt == CAL_FMT_INT8) ? 1:2);
		
		this.cfg_vif.master_cb.fmap_baseaddr <= this.fmap_cfg.fmap_mem_baseaddr;
		this.cfg_vif.master_cb.ifmap_w <= this.fmap_cfg.fmap_w - 1;
		this.cfg_vif.master_cb.ifmap_size <= this.fmap_cfg.fmap_w * this.fmap_cfg.fmap_h - 1;
		this.cfg_vif.master_cb.fmap_chn_n <= this.fmap_cfg.fmap_c - 1;
		this.cfg_vif.master_cb.fmap_ext_i_bottom <= ext_fmap_h - this.cal_cfg.external_padding_bottom - 1;
		this.cfg_vif.master_cb.external_padding_left <= this.cal_cfg.external_padding_left;
		this.cfg_vif.master_cb.external_padding_top <= this.cal_cfg.external_padding_top;
		this.cfg_vif.master_cb.inner_padding_left_right <= this.cal_cfg.inner_padding_left_right;
		this.cfg_vif.master_cb.inner_padding_top_bottom <= this.cal_cfg.inner_padding_top_bottom;
		this.cfg_vif.master_cb.ofmap_w <= ((ext_fmap_w - kernal_x_dilated) / this.cal_cfg.conv_horizontal_stride) + 1 - 1;
		this.cfg_vif.master_cb.ofmap_h <= ((ext_fmap_h - kernal_x_dilated) / this.cal_cfg.conv_vertical_stride) + 1 - 1;
		
		this.cfg_vif.master_cb.kernal_wgt_baseaddr <= this.kernal_cfg.kernal_mem_baseaddr;
		this.cfg_vif.master_cb.kernal_shape <= bit3'(this.kernal_cfg.kernal_shape);
		this.cfg_vif.master_cb.kernal_dilation_hzt_n <= this.cal_cfg.kernal_dilation_n;
		this.cfg_vif.master_cb.kernal_w_dilated <= kernal_x_dilated - 1;
		this.cfg_vif.master_cb.kernal_dilation_vtc_n <= this.cal_cfg.kernal_dilation_n;
		this.cfg_vif.master_cb.kernal_h_dilated <= kernal_x_dilated - 1;
		this.cfg_vif.master_cb.kernal_chn_n <= this.kernal_cfg.kernal_chn_n - 1;
		this.cfg_vif.master_cb.cgrpn_foreach_kernal_set <= 
			(
				(c_foreach_set / this.cal_cfg.atomic_c) + 
				((c_foreach_set % this.cal_cfg.atomic_c) ? 1:0)
			) - 1;
		this.cfg_vif.master_cb.kernal_num_n <= this.kernal_cfg.kernal_num_n - 1;
		this.cfg_vif.master_cb.kernal_set_n <= 
			(
				this.cal_cfg.is_grp_conv_mode ? 
					this.cal_cfg.group_n:
					(
						(this.kernal_cfg.kernal_num_n / this.cal_cfg.max_wgtblk_w) + 
						((this.kernal_cfg.kernal_num_n % this.cal_cfg.max_wgtblk_w) ? 1:0)
					)
			) - 1;
		this.cfg_vif.master_cb.max_wgtblk_w <= this.cal_cfg.max_wgtblk_w;
		
		this.cfg_vif.master_cb.fmbufbankn <= this.buf_cfg.fmbufbankn;
		this.cfg_vif.master_cb.fmbufcoln <= bit4'(this.buf_cfg.fmbufcoln);
		this.cfg_vif.master_cb.fmbufrown <= this.buf_cfg.fmbufrown - 1;
		this.cfg_vif.master_cb.kbufgrpsz <= bit3'(this.kernal_cfg.kernal_shape);
		this.cfg_vif.master_cb.sfc_n_each_wgtblk <= bit3'(this.buf_cfg.sfc_n_each_wgtblk);
		this.cfg_vif.master_cb.kbufgrpn <= this.buf_cfg.kbufgrpn - 1;
		this.cfg_vif.master_cb.mid_res_item_n_foreach_row <= this.buf_cfg.mid_res_item_n_foreach_row - 1;
		this.cfg_vif.master_cb.mid_res_buf_row_n_bufferable <= this.buf_cfg.mid_res_buf_row_n_bufferable - 1;
		
		repeat(4)
			@(this.cfg_vif.master_cb);
		
		this.cfg_vif.master_cb.en_mac_array <= 1'b1;
		this.cfg_vif.master_cb.en_packer <= 1'b1;
		
		phase.drop_objection(this);
	endtask
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.final_res_tr_mcd != UVM_STDOUT)
			$fclose(this.final_res_tr_mcd);
	endfunction
	
	`uvm_component_utils(GenericConvSimTestEnv)
	
endclass

class MidResAcmltCalObsvEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local MidResAcmltCalScoreboard scb;
	
	local panda_axis_slave_agent acmlt_in_slv_agt;
	
	local panda_axis_configuration acmlt_in_cfg;
	
	function void register_cal_proc_listener(FmapOutPtCalProcListener listener);
		this.scb.register_cal_proc_listener(listener);
	endfunction
	
	function new(string name = "MidResAcmltCalObsvEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		this.acmlt_in_cfg = panda_axis_configuration::type_id::create("acmlt_in_cfg");
		if(!this.acmlt_in_cfg.randomize() with {
			data_width == 80;
			user_width == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize acmlt_in_cfg!")
		
		if(!uvm_config_db #(panda_axis_vif)::get(this, "", "acmlt_in_vif", this.acmlt_in_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for acmlt_in_vif!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.scb = MidResAcmltCalScoreboard::type_id::create("obsv_scb", this);
		
		this.acmlt_in_slv_agt = panda_axis_slave_agent::type_id::create("acmlt_in_slv_agt", this);
		this.acmlt_in_slv_agt.passive_agent();
		this.acmlt_in_slv_agt.set_configuration(this.acmlt_in_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.acmlt_in_slv_agt.item_port.connect(this.scb.acmlt_in_port);
	endfunction
	
	`uvm_component_utils(MidResAcmltCalObsvEnv)
	
endclass

`endif
