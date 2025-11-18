`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class FmapCst0PackedReal extends PackedReal;
	
	rand bit is_neg;
	
	virtual function bit do_rand(uvm_object rand_context);
		FmapBuilderContext rand_context_this;
		
		if(!this.randomize())
			return 1'b0;
		
		if(!$cast(rand_context_this, rand_context))
			return 1'b0;
		
		this.data = 
			0.02 * real'(rand_context_this.row_id) + 0.001 * real'(rand_context_this.sfc_id) + 0.0001 * real'(rand_context_this.data_id);
		
		if(this.is_neg)
			this.data = -this.data;
		
		return 1'b1;
	endfunction
	
	`tue_object_default_constructor(FmapCst0PackedReal)
	`uvm_object_utils(FmapCst0PackedReal)
	
endclass

class KernalCst0PackedReal extends PackedReal;
	
	rand bit is_neg;
	rand bit is_zero;
	
	virtual function bit do_rand(uvm_object rand_context);
		KernalSetBuilderContext rand_context_this;
		
		if(!this.randomize() with{
			(data >= 0.0) && (data <= 0.1);
			
			is_zero dist{0:/7, 1:/1};
		})
			return 1'b0;
		
		if(!$cast(rand_context_this, rand_context))
			return 1'b0;
		
		this.data += 
			1.0 + 0.01 * real'(rand_context_this.set_id) + 0.001 * real'(rand_context_this.cgrp_id);
		
		if(this.is_zero)
			this.data = 0.0;
		else if(this.is_neg)
			this.data = -this.data;
		
		return 1'b1;
	endfunction
	
	`tue_object_default_constructor(KernalCst0PackedReal)
	`uvm_object_utils(KernalCst0PackedReal)
	
endclass

class ConcreteFmapOutPtCalProcListener extends FmapOutPtCalProcListener;
	
	int fid;
	
	virtual function void on_upd_out_pt_type0(
		uvm_object tr,
		int unsigned kset_id, int unsigned oy, int unsigned ox,
		int unsigned ky, int unsigned kx, int unsigned cgrp_id,
		int unsigned cal_rid
	);
		/*
		if((kset_id == 0) && (oy == 23) && (ox == 21) && (cal_rid == 0))
		begin
			panda_axis_trans axis_tr;
			FpMidResAccumInTr accum_in_tr;
			
			if(!$cast(axis_tr, tr))
			begin
				`uvm_error(this.get_name(), "cannot cast tr -> axis_tr")
				
				return;
			end
			
			accum_in_tr = FpMidResAccumInTr::type_id::create();
			accum_in_tr.from_axis_tr(axis_tr);
			
			$fdisplay(
				this.fid,
				"[kset_id = %0d, oy = %0d, ox = %0d, ky = %0d, kx = %0d, cgrp_id = %0d, cal_rid = %0d] %0s",
				kset_id, oy, ox, ky, kx, cgrp_id, cal_rid,
				accum_in_tr.convert2string()
			);
		end
		*/
	endfunction
	
	`tue_object_default_constructor(ConcreteFmapOutPtCalProcListener)
	`uvm_object_utils(ConcreteFmapOutPtCalProcListener)
	
endclass

class ConcreteExpFmapCalProcListener extends FmapOutPtCalProcListener;
	
	int fid;
	
	virtual function void on_upd_out_pt_type1(
		uvm_object tr,
		int unsigned kset_id, int unsigned oy, int unsigned ox,
		int unsigned ky, int unsigned kx, int unsigned cgrp_id,
		int unsigned sfc_id
	);
		/*
		if((kset_id == 0) && (oy == 23) && (ox == 21) && (sfc_id == 3))
		begin
			AbstractData data;
			
			if(!$cast(data, tr))
			begin
				`uvm_error(this.get_name(), "cannot cast tr -> data")
				
				return;
			end
			
			$fdisplay(
				this.fid,
				"[kset_id = %0d, oy = %0d, ox = %0d, ky = %0d, kx = %0d, cgrp_id = %0d, sfc_id = %0d] %0s",
				kset_id, oy, ox, ky, kx, cgrp_id, sfc_id,
				data.convert2string()
			);
		end
		*/
	endfunction
	
	`tue_object_default_constructor(ConcreteExpFmapCalProcListener)
	`uvm_object_utils(ConcreteExpFmapCalProcListener)
	
endclass

class generic_conv_sim_base_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	protected FmapReqGenTestEnv fmap_req_gen_env;
	protected KernalReqGenTestEnv kernal_req_gen_env;
	protected ConvDataHubTestEnv conv_data_hub_env;
	protected GenericConvSimTestEnv top_sim_env;
	protected MidResAcmltCalObsvEnv mid_res_acmlt_cal_obsv_env_arr[];
	
	protected FmapCfg fmap_cfg;
	protected KernalCfg kernal_cfg;
	protected ConvCalCfg conv_cal_cfg;
	protected BufferCfg buf_cfg;
	
	local ConcreteFmapOutPtCalProcListener fmap_out_pt_cal_proc_listener;
	local ConcreteExpFmapCalProcListener exp_fmap_cal_proc_listener;
	
	function new(string name = "generic_conv_sim_base_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 10us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		int cfg_log_fid;
		
		FmapBuilderCfg fmap_builder_cfg;
		KernalSetBuilderCfg kernal_builder_cfg;
		FmapBuilder fmap_builder;
		KernalSetBuilder kernal_builder;
		Fmap fmap;
		KernalSet kernal_set;
		PandaMemoryAdapter fmap_mem_adpt;
		PandaMemoryAdapter kernal_mem_adpt;
		
		FmapCst0PackedReal fmap_data_gen;
		KernalCst0PackedReal kernal_data_gen;
		
		cfg_log_fid = $fopen("cfg_log.txt");
		
		fmap_data_gen = FmapCst0PackedReal::type_id::create();
		kernal_data_gen = KernalCst0PackedReal::type_id::create();
		
		this.build_test_cfg();
		
		fmap_builder_cfg = FmapBuilderCfg::type_id::create();
		fmap_builder_cfg.from_cfg(this.fmap_cfg, this.conv_cal_cfg);
		
		kernal_builder_cfg = KernalSetBuilderCfg::type_id::create();
		kernal_builder_cfg.from_cfg(this.kernal_cfg, this.conv_cal_cfg);
		
		fmap_builder = FmapBuilder::type_id::create();
		fmap_builder.set_data_gen(fmap_data_gen);
		fmap_builder.build_default_feature_map(fmap_builder_cfg);
		fmap = fmap_builder.get_feature_map();
		
		kernal_builder = KernalSetBuilder::type_id::create();
		kernal_builder.set_data_gen(kernal_data_gen);
		kernal_builder.build_default_kernal_set(kernal_builder_cfg);
		kernal_set = kernal_builder.get_kernal_set();
		
		fmap_mem_adpt = new(fmap, "FmapPandaMemoryAdapter", 16);
		kernal_mem_adpt = new(kernal_set, "KernalPandaMemoryAdapter", 16);
		
		uvm_config_db #(FmapCfg)::set(null, "", "fmap_cfg", this.fmap_cfg);
		uvm_config_db #(KernalCfg)::set(null, "", "kernal_cfg", this.kernal_cfg);
		uvm_config_db #(ConvCalCfg)::set(null, "", "cal_cfg", this.conv_cal_cfg);
		uvm_config_db #(BufferCfg)::set(null, "", "buf_cfg", this.buf_cfg);
		uvm_config_db #(PandaMemoryAdapter)::set(null, "", "fmap_mem", fmap_mem_adpt);
		uvm_config_db #(PandaMemoryAdapter)::set(null, "", "kernal_mem", kernal_mem_adpt);
		
		`panda_print_with(this.fmap_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(this.kernal_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(this.conv_cal_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(this.buf_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(fmap_builder_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(kernal_builder_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(fmap, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(kernal_set, cfg_log_fid, Util::get_object_printer())
		
		$fclose(cfg_log_fid);
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.fmap_req_gen_env = FmapReqGenTestEnv::type_id::create("fmap_req_gen_env", this);
		this.kernal_req_gen_env = KernalReqGenTestEnv::type_id::create("kernal_req_gen_env", this);
		this.conv_data_hub_env = ConvDataHubTestEnv::type_id::create("conv_data_hub_env", this);
		this.top_sim_env = GenericConvSimTestEnv::type_id::create("top_sim_env", this);
		
		this.mid_res_acmlt_cal_obsv_env_arr = new[this.conv_cal_cfg.atomic_k];
		foreach(this.mid_res_acmlt_cal_obsv_env_arr[_i])
			this.mid_res_acmlt_cal_obsv_env_arr[_i] = MidResAcmltCalObsvEnv::type_id::create(
				$sformatf("mid_res_acmlt_cal_obsv_env[%0d]", _i),
				this
			);
		
		this.exp_fmap_cal_proc_listener = ConcreteExpFmapCalProcListener::type_id::create();
		this.top_sim_env.register_cal_proc_listener(this.exp_fmap_cal_proc_listener);
		this.exp_fmap_cal_proc_listener.fid = $fopen("exp_fmap_cal_obsv_log.txt");
	endfunction
	
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.fmap_out_pt_cal_proc_listener = ConcreteFmapOutPtCalProcListener::type_id::create();
		this.mid_res_acmlt_cal_obsv_env_arr[3].register_cal_proc_listener(this.fmap_out_pt_cal_proc_listener);
		this.fmap_out_pt_cal_proc_listener.fid = $fopen("mid_res_acmlt_cal_obsv_log.txt");
		
		$fclose(this.exp_fmap_cal_proc_listener.fid);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		$fclose(this.fmap_out_pt_cal_proc_listener.fid);
	endfunction
	
	virtual protected function void build_test_cfg();
		// blank
	endfunction
	
	`uvm_component_utils(generic_conv_sim_base_test)
	
endclass

class generic_conv_sim_test_0 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 30;
			fmap_h == 6;
			fmap_c == 19;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 7;
			kernal_chn_n == 19;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 1;
			is_grp_conv_mode == 1'b0;
			group_n == 1;
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 0;
			max_wgtblk_w == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 10;
			fmbufcoln == COLN_32;
			fmbufrown == 40;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 21;
			mid_res_item_n_foreach_row == 30;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_0)
	`uvm_component_utils(generic_conv_sim_test_0)
	
endclass

class generic_conv_sim_test_1 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 30;
			fmap_h == 10;
			fmap_c == 26;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 7;
			kernal_chn_n == 26;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 1;
			is_grp_conv_mode == 1'b0;
			group_n == 1;
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 0;
			max_wgtblk_w == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 12;
			fmbufcoln == COLN_32;
			fmbufrown == 48;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 14;
			mid_res_item_n_foreach_row == 30;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_1)
	`uvm_component_utils(generic_conv_sim_test_1)
	
endclass

class generic_conv_sim_test_2 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 30;
			fmap_h == 10;
			fmap_c == 26;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_1x1;
			kernal_num_n == 7;
			kernal_chn_n == 26;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 1;
			is_grp_conv_mode == 1'b0;
			group_n == 1;
			external_padding_left == 0;
			external_padding_right == 0;
			external_padding_top == 0;
			external_padding_bottom == 0;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 0;
			max_wgtblk_w == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 12;
			fmbufcoln == COLN_32;
			fmbufrown == 48;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 128;
			mid_res_item_n_foreach_row == 30;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_2)
	`uvm_component_utils(generic_conv_sim_test_2)
	
endclass

class generic_conv_sim_test_3 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 40;
			fmap_h == 24;
			fmap_c == 37;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 10;
			kernal_chn_n == 37;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 2;
			conv_horizontal_stride == 2;
			cal_round == 1;
			is_grp_conv_mode == 1'b0;
			group_n == 1;
			external_padding_left == 1;
			external_padding_right == 0;
			external_padding_top == 1;
			external_padding_bottom == 0;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 0;
			max_wgtblk_w == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 12;
			fmbufcoln == COLN_64;
			fmbufrown == 24;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 14;
			mid_res_item_n_foreach_row == 20;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_3)
	`uvm_component_utils(generic_conv_sim_test_3)
	
endclass

class generic_conv_sim_test_4 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 16;
			fmap_h == 9;
			fmap_c == 11;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 5;
			kernal_chn_n == 11;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 1;
			is_grp_conv_mode == 1'b0;
			group_n == 1;
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			inner_padding_left_right == 1;
			inner_padding_top_bottom == 1;
			kernal_dilation_n == 0;
			max_wgtblk_w == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 12;
			fmbufcoln == COLN_16;
			fmbufrown == 96;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 14;
			mid_res_item_n_foreach_row == 31;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_4)
	`uvm_component_utils(generic_conv_sim_test_4)
	
endclass

class generic_conv_sim_test_5 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 50;
			fmap_h == 28;
			fmap_c == 2;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 32;
			kernal_chn_n == 2;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 2;
			is_grp_conv_mode == 1'b0;
			group_n == 1;
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 0;
			max_wgtblk_w == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 10;
			fmbufcoln == COLN_64;
			fmbufrown == 20;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_8;
			kbufgrpn == 10;
			mid_res_item_n_foreach_row == 100;
			mid_res_buf_row_n_bufferable == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_5)
	`uvm_component_utils(generic_conv_sim_test_5)
	
endclass

class generic_conv_sim_test_6 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 24;
			fmap_h == 16;
			fmap_c == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 16;
			kernal_chn_n == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 1;
			is_grp_conv_mode == 1'b1;
			group_n == 4;
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 0;
			max_wgtblk_w == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 6;
			fmbufcoln == COLN_32;
			fmbufrown == 24;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 35;
			mid_res_item_n_foreach_row == 24;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_6)
	`uvm_component_utils(generic_conv_sim_test_6)
	
endclass

class generic_conv_sim_test_7 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 24;
			fmap_h == 16;
			fmap_c == 32;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 32;
			kernal_chn_n == 32;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 2;
			is_grp_conv_mode == 1'b1;
			group_n == 4;
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 0;
			max_wgtblk_w == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 6;
			fmbufcoln == COLN_32;
			fmbufrown == 24;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_8;
			kbufgrpn == 17;
			mid_res_item_n_foreach_row == 48;
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_7)
	`uvm_component_utils(generic_conv_sim_test_7)
	
endclass

class generic_conv_sim_test_8 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			fmap_w == 24;
			fmap_h == 16;
			fmap_c == 6;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 16;
			kernal_chn_n == 6;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == 2;
			atomic_k == 4;
			calfmt == CAL_FMT_FP16;
			conv_vertical_stride == 1;
			conv_horizontal_stride == 1;
			cal_round == 1;
			is_grp_conv_mode == 1'b0;
			group_n == 1;
			external_padding_left == 0;
			external_padding_right == 0;
			external_padding_top == 0;
			external_padding_bottom == 0;
			inner_padding_left_right == 0;
			inner_padding_top_bottom == 0;
			kernal_dilation_n == 1;
			max_wgtblk_w == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == 32;
			fmbufbankn == 6;
			fmbufcoln == COLN_32;
			fmbufrown == 24;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 35;
			mid_res_item_n_foreach_row == 20;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_8)
	`uvm_component_utils(generic_conv_sim_test_8)
	
endclass

`endif
