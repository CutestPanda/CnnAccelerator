`ifndef __PANDA_EXT_ENV_H
`define __PANDA_EXT_ENV_H

class GenericPoolSimTestEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	typedef bit[1:0] bit2;
	typedef bit[3:0] bit4;
	
	uvm_analysis_export #(panda_axis_trans) final_res_export;
	
	local virtual generic_pool_sim_cfg_if cfg_vif;
	
	local int final_res_tr_mcd = UVM_STDOUT;
	
	local FinalResScoreboard final_res_scb;
	
	local panda_blk_ctrl_master_agent fmap_blk_ctrl_mst_agt;
	local panda_blk_ctrl_master_agent fnl_res_trans_blk_ctrl_mst_agt;
	local panda_axis_slave_agent final_res_slv_agt;
	
	local panda_blk_ctrl_configuration fmap_blk_ctrl_mst_cfg;
	local panda_blk_ctrl_configuration fnl_res_trans_blk_ctrl_mst_cfg;
	local panda_axis_configuration final_res_slv_cfg;
	
	local FmapCfg fmap_cfg;
	local PoolCalCfg cal_cfg;
	local PoolBufferCfg buf_cfg;
	
	local bit to_connect_final_res_export;
	
	function new(string name = "GenericPoolSimTestEnv", uvm_component parent = null);
		super.new(name, parent);
		
		this.to_connect_final_res_export = 1'b0;
	endfunction
	
	function void enable_connect_final_res_export();
		this.to_connect_final_res_export = 1'b1;
	endfunction
	
	function void disable_connect_final_res_export();
		this.to_connect_final_res_export = 1'b0;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if(this.to_connect_final_res_export)
			this.final_res_export = new("final_res_export", this);
		
		this.final_res_tr_mcd = $fopen("final_res_tr_log.txt");
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(FmapCfg)::get(null, "", "fmap_cfg", this.fmap_cfg))
			`uvm_fatal(this.get_name(), "cannot get fmap_cfg!!!")
		if(!uvm_config_db #(PoolCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		if(!uvm_config_db #(PoolBufferCfg)::get(null, "", "buf_cfg", this.buf_cfg))
			`uvm_fatal(this.get_name(), "cannot get buf_cfg!!!")
		
		this.fmap_blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("fmap_blk_ctrl_mst_cfg");
		if(!this.fmap_blk_ctrl_mst_cfg.randomize() with {
			params_width == 0;
			
			start_delay.min_delay == 0;
			start_delay.mid_delay[0] == 25;
			start_delay.mid_delay[1] == 40;
			start_delay.max_delay == 60;
			start_delay.weight_zero_delay == 1;
			start_delay.weight_short_delay == 0;
			start_delay.weight_long_delay == 0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize fmap_blk_ctrl_mst_cfg!")
		this.fmap_blk_ctrl_mst_cfg.tr_factory = 
			panda_dummy_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		this.fmap_blk_ctrl_mst_cfg.complete_monitor_mode = 1'b0;
		
		this.fnl_res_trans_blk_ctrl_mst_cfg = panda_blk_ctrl_configuration::type_id::create("fnl_res_trans_blk_ctrl_mst_cfg");
		if(!this.fnl_res_trans_blk_ctrl_mst_cfg.randomize() with {
			params_width == 0;
			
			start_delay.min_delay == 0;
			start_delay.mid_delay[0] == 25;
			start_delay.mid_delay[1] == 512;
			start_delay.max_delay == 550;
			start_delay.weight_zero_delay == 0;
			start_delay.weight_short_delay == 0;
			start_delay.weight_long_delay == 1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize fnl_res_trans_blk_ctrl_mst_cfg!")
		this.fnl_res_trans_blk_ctrl_mst_cfg.tr_factory = 
			panda_dummy_blk_ctrl_trans_factory::type_id::create("blk_ctrl_trans_factory");
		this.fnl_res_trans_blk_ctrl_mst_cfg.complete_monitor_mode = 1'b0;
		
		this.final_res_slv_cfg = panda_axis_configuration::type_id::create("final_res_slv_cfg");
		if(!this.final_res_slv_cfg.randomize() with {
			data_width == (cal_cfg.enable_post_mac ? cal_cfg.post_mac_prl_n*32:cal_cfg.atomic_c*32);
			user_width == 0;
			
			has_keep == 1'b1;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize final_res_slv_cfg!")
		
		if(!uvm_config_db #(virtual generic_pool_sim_cfg_if)::get(this, "", "cfg_vif", this.cfg_vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for cfg_vif!!!")
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(this, "", "fmap_blk_ctrl_vif", this.fmap_blk_ctrl_mst_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fmap_blk_ctrl_vif!!!")
		if(!uvm_config_db #(panda_blk_ctrl_vif)::get(this, "", "fnl_res_trans_blk_ctrl_vif", this.fnl_res_trans_blk_ctrl_mst_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for fnl_res_trans_blk_ctrl_vif!!!")
		
		if(this.cal_cfg.enable_post_mac)
		begin
			if(!uvm_config_db #(panda_axis_vif)::get(this, "", "final_res_post_mac_axis_vif", this.final_res_slv_cfg.vif))
				`uvm_fatal(this.get_name(), "virtual interface must be set for final_res_post_mac_axis_vif!!!")
		end
		else
		begin
			if(!uvm_config_db #(panda_axis_vif)::get(this, "", "final_res_axis_vif", this.final_res_slv_cfg.vif))
				`uvm_fatal(this.get_name(), "virtual interface must be set for final_res_axis_vif!!!")
		end
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.final_res_scb = FinalResScoreboard::type_id::create("final_res_scb", this);
		
		this.fmap_blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("fmap_blk_ctrl_mst_agt", this);
		this.fmap_blk_ctrl_mst_agt.active_agent();
		this.fmap_blk_ctrl_mst_agt.set_configuration(this.fmap_blk_ctrl_mst_cfg);
		
		this.fnl_res_trans_blk_ctrl_mst_agt = panda_blk_ctrl_master_agent::type_id::create("fnl_res_trans_blk_ctrl_mst_agt", this);
		this.fnl_res_trans_blk_ctrl_mst_agt.active_agent();
		this.fnl_res_trans_blk_ctrl_mst_agt.set_configuration(this.fnl_res_trans_blk_ctrl_mst_cfg);
		
		this.final_res_slv_agt = panda_axis_slave_agent::type_id::create("final_res_slv_agt", this);
		this.final_res_slv_agt.passive_agent();
		this.final_res_slv_agt.set_configuration(this.final_res_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.to_connect_final_res_export)
			this.final_res_slv_agt.item_port.connect(this.final_res_export);
		
		this.final_res_slv_agt.item_port.connect(this.final_res_scb.final_res_port);
		this.final_res_scb.set_final_res_tr_mcd(this.final_res_tr_mcd);
		
		if(this.fmap_blk_ctrl_mst_agt.is_active_agent())
			this.fmap_blk_ctrl_mst_agt.sequencer.set_default_sequence("main_phase", ReqGenBlkCtrlDefaultSeq::type_id::get());
		if(this.fnl_res_trans_blk_ctrl_mst_agt.is_active_agent())
			this.fnl_res_trans_blk_ctrl_mst_agt.sequencer.set_default_sequence("main_phase", ReqGenBlkCtrlDefaultSeq::type_id::get());
		if(this.final_res_slv_agt.is_active_agent())
			this.final_res_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
	endfunction
	
	task reset_phase(uvm_phase phase);
		phase.raise_objection(this);
		
		this.cfg_vif.master_cb.en_adapter <= 1'b0;
		this.cfg_vif.master_cb.en_post_mac <= 1'b0;
		
		repeat(4)
			@(this.cfg_vif.master_cb);
		
		phase.drop_objection(this);
	endtask
	
	task configure_phase(uvm_phase phase);
		int unsigned ext_fmap_w; // 扩展特征图宽度
		int unsigned ext_fmap_h; // 扩展特征图高度
		int unsigned ofmap_w; // 输出特征图宽度
		int unsigned ofmap_h; // 输出特征图高度
		
		ext_fmap_w = this.fmap_cfg.fmap_w + this.cal_cfg.external_padding_left + this.cal_cfg.external_padding_right;
		ext_fmap_h = this.fmap_cfg.fmap_h + this.cal_cfg.external_padding_top + this.cal_cfg.external_padding_bottom;
		
		if(this.cal_cfg.pool_mode == POOL_MODE_UPSP)
		begin
			ofmap_w = ext_fmap_w * this.cal_cfg.upsample_horizontal_n;
			ofmap_h = ext_fmap_h * this.cal_cfg.upsample_vertical_n;
		end
		else
		begin
			ofmap_w = ((ext_fmap_w - this.cal_cfg.pool_window_w) / this.cal_cfg.pool_horizontal_stride) + 1;
			ofmap_h = ((ext_fmap_h - this.cal_cfg.pool_window_h) / this.cal_cfg.pool_vertical_stride) + 1;
		end
		
		phase.raise_objection(this);
		
		this.cfg_vif.master_cb.pool_mode <= bit2'(this.cal_cfg.pool_mode);
		this.cfg_vif.master_cb.calfmt <= bit2'(this.cal_cfg.calfmt);
		this.cfg_vif.master_cb.pool_horizontal_stride <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP) ? 3'dx:(this.cal_cfg.pool_horizontal_stride-1);
		this.cfg_vif.master_cb.pool_vertical_stride <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP) ? 3'dx:(this.cal_cfg.pool_vertical_stride-1);
		this.cfg_vif.master_cb.pool_window_w <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP) ? 8'dx:(this.cal_cfg.pool_window_w-1);
		this.cfg_vif.master_cb.pool_window_h <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP) ? 8'dx:(this.cal_cfg.pool_window_h-1);
		
		this.cfg_vif.master_cb.post_mac_fixed_point_quat_accrc <= 
			(this.cal_cfg.enable_post_mac && (this.cal_cfg.calfmt == CAL_FMT_INT8 || this.cal_cfg.calfmt == CAL_FMT_INT16)) ? 
				this.cal_cfg.post_mac_fixed_point_quat_accrc:
				5'bxxxxx;
		this.cfg_vif.master_cb.post_mac_is_a_eq_1 <= 
			this.cal_cfg.enable_post_mac ? 
				this.cal_cfg.post_mac_is_a_eq_1:
				1'bx;
		this.cfg_vif.master_cb.post_mac_is_b_eq_0 <= 
			this.cal_cfg.enable_post_mac ? 
				this.cal_cfg.post_mac_is_b_eq_0:
				1'bx;
		this.cfg_vif.master_cb.post_mac_param_a <= 
			(this.cal_cfg.enable_post_mac && (!this.cal_cfg.post_mac_is_a_eq_1)) ? 
				this.cal_cfg.post_mac_param_a:
				32'dx;
		this.cfg_vif.master_cb.post_mac_param_b <= 
			(this.cal_cfg.enable_post_mac && (!this.cal_cfg.post_mac_is_b_eq_0)) ? 
				this.cal_cfg.post_mac_param_b:
				32'dx;
		
		this.cfg_vif.master_cb.upsample_horizontal_n <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP) ? (this.cal_cfg.upsample_horizontal_n-1):8'dx;
		this.cfg_vif.master_cb.upsample_vertical_n <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP) ? (this.cal_cfg.upsample_vertical_n-1):8'dx;
		this.cfg_vif.master_cb.non_zero_const_padding_mode <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP) ? this.cal_cfg.non_zero_const_padding_mode:1'bx;
		this.cfg_vif.master_cb.const_to_fill <= 
			(this.cal_cfg.pool_mode == POOL_MODE_UPSP && this.cal_cfg.non_zero_const_padding_mode) ? 
				this.cal_cfg.const_to_fill:
				16'dx;
		
		this.cfg_vif.master_cb.ifmap_baseaddr <= this.fmap_cfg.fmap_mem_baseaddr;
		this.cfg_vif.master_cb.ofmap_baseaddr <= this.fmap_cfg.ofmap_baseaddr;
		this.cfg_vif.master_cb.is_16bit_data <= this.cal_cfg.calfmt != CAL_FMT_INT8;
		this.cfg_vif.master_cb.ifmap_w <= this.fmap_cfg.fmap_w - 1;
		this.cfg_vif.master_cb.ifmap_h <= this.fmap_cfg.fmap_h - 1;
		this.cfg_vif.master_cb.ifmap_size <= (this.fmap_cfg.fmap_w * this.fmap_cfg.fmap_h) - 1;
		this.cfg_vif.master_cb.ext_ifmap_w <= ext_fmap_w - 1;
		this.cfg_vif.master_cb.ext_ifmap_h <= ext_fmap_h - 1;
		this.cfg_vif.master_cb.fmap_chn_n <= this.fmap_cfg.fmap_c - 1;
		this.cfg_vif.master_cb.external_padding_left <= this.cal_cfg.external_padding_left;
		this.cfg_vif.master_cb.external_padding_top <= this.cal_cfg.external_padding_top;
		this.cfg_vif.master_cb.ofmap_w <= ofmap_w - 1;
		this.cfg_vif.master_cb.ofmap_h <= ofmap_h - 1;
		this.cfg_vif.master_cb.ofmap_data_type <= bit2'(this.fmap_cfg.ofmap_data_type);
		
		this.cfg_vif.master_cb.fmbufcoln <= bit4'(this.buf_cfg.fmbufcoln);
		this.cfg_vif.master_cb.fmbufrown <= this.buf_cfg.fmbufrown - 1;
		this.cfg_vif.master_cb.mid_res_buf_row_n_bufferable <= this.buf_cfg.mid_res_buf_row_n_bufferable - 1;
		
		repeat(4)
			@(this.cfg_vif.master_cb);
		
		this.cfg_vif.master_cb.en_adapter <= 1'b1;
		this.cfg_vif.master_cb.en_post_mac <= this.cal_cfg.enable_post_mac;
		
		phase.drop_objection(this);
	endtask
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.final_res_tr_mcd != UVM_STDOUT)
			$fclose(this.final_res_tr_mcd);
	endfunction
	
	`uvm_component_utils(GenericPoolSimTestEnv)
	
endclass

class PoolDataHubTestEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local DmaStrmAxisVsqr dma_axis_vsqr[1];
	
	local panda_axis_master_agent dma_strm_axis_mst_agt[1];
	local panda_axis_slave_agent dma_cmd_axis_slv_agt[1];
	
	local panda_axis_configuration dma_strm_axis_mst_cfg[1];
	local panda_axis_configuration dma_cmd_axis_slv_cfg[1];
	
	local PoolCalCfg cal_cfg;
	local PoolBufferCfg buf_cfg;
	
	function new(string name = "PoolDataHubTestEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(PoolCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		if(!uvm_config_db #(PoolBufferCfg)::get(null, "", "buf_cfg", this.buf_cfg))
			`uvm_fatal(this.get_name(), "cannot get buf_cfg!!!")
		
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
		
		if(!uvm_config_db #(panda_axis_vif)::get(this, "", "dma0_strm_axis_vif", this.dma_strm_axis_mst_cfg[0].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma0_strm_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(this, "", "dma0_cmd_axis_vif", this.dma_cmd_axis_slv_cfg[0].vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma0_cmd_axis_vif!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.dma_axis_vsqr[0] = DmaStrmAxisVsqr::type_id::create("dma_axis_vsqr_0", this);
		
		this.dma_strm_axis_mst_agt[0] = panda_axis_master_agent::type_id::create("dma_strm_axis_mst_agt_0", this);
		this.dma_strm_axis_mst_agt[0].active_agent();
		this.dma_strm_axis_mst_agt[0].set_configuration(this.dma_strm_axis_mst_cfg[0]);
		
		this.dma_cmd_axis_slv_agt[0] = panda_axis_slave_agent::type_id::create("dma_cmd_axis_slv_agt_0", this);
		this.dma_cmd_axis_slv_agt[0].active_agent();
		this.dma_cmd_axis_slv_agt[0].set_configuration(this.dma_cmd_axis_slv_cfg[0]);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.dma_axis_vsqr[0].dma_strm_axis_sqr = this.dma_strm_axis_mst_agt[0].sequencer;
		this.dma_axis_vsqr[0].dma_cmd_axis_sqr = this.dma_cmd_axis_slv_agt[0].sequencer;
		
		this.dma_axis_vsqr[0].set_default_sequence("main_phase", DmaStrmAxisVseq #(.MEM_NAME("fmap_mem"))::type_id::get());
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction
	
	`uvm_component_utils(PoolDataHubTestEnv)
	
endclass

class DMAS2MMEnv extends panda_env #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local DMAS2MMDataLenScoreboard dma_s2mm_data_len_scb;
	
	bit en_output_mem_bin = 1'b0; // 是否生成输出特征图BIN文件
	
	local FmapCfg fmap_cfg;
	local PoolBufferCfg buf_cfg;
	
	local panda_axis_slave_agent dma_s2mm_cmd_slv_agt;
	local panda_axis_slave_agent dma_s2mm_strm_slv_agt;
	
	local panda_axis_configuration dma_s2mm_cmd_slv_cfg;
	local panda_axis_configuration dma_s2mm_strm_slv_cfg;
	
	local ConvSts pool_sts;
	
	function new(string name = "DMAS2MMEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(FmapCfg)::get(null, "", "fmap_cfg", this.fmap_cfg))
			`uvm_fatal(this.get_name(), "cannot get fmap_cfg!!!")
		if(!uvm_config_db #(PoolBufferCfg)::get(null, "", "buf_cfg", this.buf_cfg))
			`uvm_fatal(this.get_name(), "cannot get buf_cfg!!!")
		
		this.dma_s2mm_cmd_slv_cfg = panda_axis_configuration::type_id::create("dma_s2mm_cmd_slv_cfg");
		if(!this.dma_s2mm_cmd_slv_cfg.randomize() with {
			data_width == 56;
			user_width == 1;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 25;
			ready_delay.mid_delay[1] == 32;
			ready_delay.max_delay == 68;
			ready_delay.weight_zero_delay == 1;
			ready_delay.weight_short_delay == 3;
			ready_delay.weight_long_delay == 2;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dma_s2mm_cmd_slv_cfg!")
		
		this.dma_s2mm_strm_slv_cfg = panda_axis_configuration::type_id::create("dma_s2mm_strm_slv_cfg");
		if(!this.dma_s2mm_strm_slv_cfg.randomize() with {
			data_width == buf_cfg.fnl_res_data_width;
			user_width == 0;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 2;
			ready_delay.mid_delay[1] == 3;
			ready_delay.max_delay == 4;
			ready_delay.weight_zero_delay == 2;
			ready_delay.weight_short_delay == 1;
			ready_delay.weight_long_delay == 1;
			
			default_ready == 1'b1;
			has_keep == 1'b1;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dma_s2mm_strm_slv_cfg!")
		
		if(!uvm_config_db #(panda_axis_vif)::get(this, "", "dma_s2mm_cmd_axis_vif", this.dma_s2mm_cmd_slv_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma_s2mm_cmd_axis_vif!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(this, "", "dma_s2mm_strm_axis_vif", this.dma_s2mm_strm_slv_cfg.vif))
			`uvm_fatal(this.get_name(), "virtual interface must be set for dma_s2mm_strm_axis_vif!!!")
	endfunction
	
	protected function void build_status();
		if(this.en_output_mem_bin)
		begin
			this.pool_sts = ConvSts::type_id::create();
		end
	endfunction
	
	protected function void build_agents();
		this.dma_s2mm_data_len_scb = DMAS2MMDataLenScoreboard::type_id::create("dma_s2mm_data_len_scb", this);
		
		if(this.en_output_mem_bin)
		begin
			this.dma_s2mm_data_len_scb.set_status(this.pool_sts);
			this.dma_s2mm_data_len_scb.to_upd_ofmap_mem = 1'b1;
		end
		
		this.dma_s2mm_cmd_slv_agt = panda_axis_slave_agent::type_id::create("dma_s2mm_cmd_slv_agt", this);
		this.dma_s2mm_cmd_slv_agt.active_agent();
		this.dma_s2mm_cmd_slv_agt.set_configuration(this.dma_s2mm_cmd_slv_cfg);
		
		this.dma_s2mm_strm_slv_agt = panda_axis_slave_agent::type_id::create("dma_s2mm_strm_slv_agt", this);
		this.dma_s2mm_strm_slv_agt.active_agent();
		this.dma_s2mm_strm_slv_agt.set_configuration(this.dma_s2mm_strm_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.dma_s2mm_cmd_slv_agt.item_port.connect(this.dma_s2mm_data_len_scb.req_port);
		this.dma_s2mm_strm_slv_agt.item_port.connect(this.dma_s2mm_data_len_scb.final_res_port);
		
		if(this.dma_s2mm_cmd_slv_agt.is_active_agent())
			this.dma_s2mm_cmd_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
		if(this.dma_s2mm_strm_slv_agt.is_active_agent())
			this.dma_s2mm_strm_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.en_output_mem_bin)
		begin
			int mem_bin_fid;
			
			mem_bin_fid = $fopen("out_fmap.bin", "wb");
			
			if(!this.pool_sts.ofmap_mem.output_to_bin(mem_bin_fid, this.fmap_cfg.ofmap_baseaddr, this.dma_s2mm_data_len_scb.total_bytes_n))
				`uvm_error(this.get_name(), "cannot output out_fmap.bin")
			
			$fclose(mem_bin_fid);
		end
	endfunction
	
	`uvm_component_utils(DMAS2MMEnv)
	
endclass

`endif
