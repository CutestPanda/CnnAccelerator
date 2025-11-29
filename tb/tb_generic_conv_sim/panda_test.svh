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
			data inside {0.00, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09};
			
			is_zero dist{0:/4, 1:/1};
		})
			return 1'b0;
		
		if(!$cast(rand_context_this, rand_context))
			return 1'b0;
		
		this.data += 
			(1.0 + 0.01 * real'(rand_context_this.set_id) + 0.001 * real'(rand_context_this.cgrp_id));
		
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
		if((kset_id == 0) && (oy == 2) && (ox == 1) && (cal_rid == 0))
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
		if((kset_id == 0) && (oy == 2) && (ox == 1) && (sfc_id == 3))
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
	
	protected int unsigned ATOMIC_C = 4; // 通道并行数
	protected int unsigned ATOMIC_K = 4; // 核并行数
	protected int unsigned STREAM_DATA_WIDTH = 64; // DMA数据流的位宽(32 | 64 | 128 | 256)
	protected int unsigned FNL_RES_DATA_WIDTH = 64; // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	
	protected bit en_output_mem_bin = 1'b0; // 是否生成特征图与卷积核数据BIN文件
	
	protected FmapReqGenTestEnv fmap_req_gen_env;
	protected KernalReqGenTestEnv kernal_req_gen_env;
	protected FnlResTransReqGenTestEnv fnl_res_trans_req_gen_env;
	protected ConvDataHubTestEnv conv_data_hub_env;
	protected GenericConvSimTestEnv top_sim_env;
	protected MidResAcmltCalObsvEnv mid_res_acmlt_cal_obsv_env_arr[];
	
	protected DMAS2MMDataLenScoreboard dma_s2mm_data_len_scb;
	
	protected FmapCfg fmap_cfg;
	protected KernalCfg kernal_cfg;
	protected ConvCalCfg conv_cal_cfg;
	protected BufferCfg buf_cfg;
	
	protected ConvSts conv_sts;
	
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
		int mem_bin_fid[2];
		
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
		
		if(this.en_output_mem_bin)
		begin
			mem_bin_fid[0] = $fopen("in_fmap.bin", "wb");
			mem_bin_fid[1] = $fopen("kernal.bin", "wb");
		end
		
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
		
		if(this.en_output_mem_bin)
		begin
			if(!fmap_mem_adpt.output_to_bin(mem_bin_fid[0], fmap_mem_adpt.data_blk.get_baseaddr(), fmap_mem_adpt.data_blk.get_len_in_byte()))
				`uvm_error(this.get_name(), "cannot output in_fmap.bin")
			
			if(!kernal_mem_adpt.output_to_bin(mem_bin_fid[1], kernal_mem_adpt.data_blk.get_baseaddr(), kernal_mem_adpt.data_blk.get_len_in_byte()))
				`uvm_error(this.get_name(), "cannot output kernal.bin")
		end
		
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
		
		if(this.en_output_mem_bin)
		begin
			$fclose(mem_bin_fid[0]);
			$fclose(mem_bin_fid[1]);
		end
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.fmap_req_gen_env = FmapReqGenTestEnv::type_id::create("fmap_req_gen_env", this);
		this.kernal_req_gen_env = KernalReqGenTestEnv::type_id::create("kernal_req_gen_env", this);
		this.fnl_res_trans_req_gen_env = FnlResTransReqGenTestEnv::type_id::create("fnl_res_trans_req_gen_env", this);
		this.conv_data_hub_env = ConvDataHubTestEnv::type_id::create("conv_data_hub_env", this);
		this.top_sim_env = GenericConvSimTestEnv::type_id::create("top_sim_env", this);
		
		this.mid_res_acmlt_cal_obsv_env_arr = new[this.conv_cal_cfg.atomic_k];
		foreach(this.mid_res_acmlt_cal_obsv_env_arr[_i])
			this.mid_res_acmlt_cal_obsv_env_arr[_i] = MidResAcmltCalObsvEnv::type_id::create(
				$sformatf("mid_res_acmlt_cal_obsv_env[%0d]", _i),
				this
			);
		
		this.dma_s2mm_data_len_scb = DMAS2MMDataLenScoreboard::type_id::create("dma_s2mm_data_len_scb", this);
		
		if(this.en_output_mem_bin)
		begin
			this.conv_sts = ConvSts::type_id::create();
			this.dma_s2mm_data_len_scb.set_status(this.conv_sts);
			this.dma_s2mm_data_len_scb.to_upd_ofmap_mem = 1'b1;
		end
		
		this.exp_fmap_cal_proc_listener = ConcreteExpFmapCalProcListener::type_id::create();
		this.top_sim_env.register_cal_proc_listener(this.exp_fmap_cal_proc_listener);
		this.exp_fmap_cal_proc_listener.fid = $fopen("exp_fmap_cal_obsv_log.txt");
	endfunction
	
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.fnl_res_trans_req_gen_env.req_export.connect(this.dma_s2mm_data_len_scb.req_port);
		this.top_sim_env.final_res_export.connect(this.dma_s2mm_data_len_scb.final_res_port);
		
		this.fmap_out_pt_cal_proc_listener = ConcreteFmapOutPtCalProcListener::type_id::create();
		this.mid_res_acmlt_cal_obsv_env_arr[3].register_cal_proc_listener(this.fmap_out_pt_cal_proc_listener);
		this.fmap_out_pt_cal_proc_listener.fid = $fopen("mid_res_acmlt_cal_obsv_log.txt");
		
		$fclose(this.exp_fmap_cal_proc_listener.fid);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		$fclose(this.fmap_out_pt_cal_proc_listener.fid);
		
		if(this.en_output_mem_bin)
		begin
			int mem_bin_fid;
			
			mem_bin_fid = $fopen("out_fmap.bin", "wb");
			
			if(!this.conv_sts.ofmap_mem.output_to_bin(mem_bin_fid, this.fmap_cfg.ofmap_baseaddr, this.dma_s2mm_data_len_scb.total_bytes_n))
				`uvm_error(this.get_name(), "cannot output out_fmap.bin")
			
			$fclose(mem_bin_fid);
		end
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
			ofmap_baseaddr == 512;
			fmap_w == 30;
			fmap_h == 6;
			fmap_c == 19;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 30;
			fmap_h == 10;
			fmap_c == 26;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 30;
			fmap_h == 10;
			fmap_c == 26;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 40;
			fmap_h == 24;
			fmap_c == 37;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 16;
			fmap_h == 9;
			fmap_c == 11;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 50;
			fmap_h == 28;
			fmap_c == 2;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 24;
			fmap_h == 16;
			fmap_c == 16;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 24;
			fmap_h == 16;
			fmap_c == 32;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
			ofmap_baseaddr == 512;
			fmap_w == 24;
			fmap_h == 16;
			fmap_c == 6;
			ofmap_data_type == DATA_4_BYTE;
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
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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

class generic_conv_sim_test_9 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			fmap_w == 50;
			fmap_h == 28;
			fmap_c == 2;
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 14;
			kernal_chn_n == 2;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
	
	`tue_component_default_constructor(generic_conv_sim_test_9)
	`uvm_component_utils(generic_conv_sim_test_9)
	
endclass

class generic_conv_sim_test_10 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			fmap_w == 50;
			fmap_h == 28;
			fmap_c == 2;
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 12;
			kernal_chn_n == 2;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
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
	
	`tue_component_default_constructor(generic_conv_sim_test_10)
	`uvm_component_utils(generic_conv_sim_test_10)
	
endclass

class generic_conv_sim_test_11 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			fmap_w == 11;
			fmap_h == 6;
			fmap_c == 13;
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 7;
			kernal_chn_n == 13;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			fmbufbankn == 10;
			fmbufcoln == COLN_16;
			fmbufrown == 80;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 21;
			mid_res_item_n_foreach_row == 11;
			mid_res_buf_row_n_bufferable == 16;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_11)
	`uvm_component_utils(generic_conv_sim_test_11)
	
endclass

class generic_conv_sim_test_12 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			fmap_w == 25;
			fmap_h == 25;
			fmap_c == 13;
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 9;
			kernal_chn_n == 13;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			fmbufbankn == 1;
			fmbufcoln == COLN_32;
			fmbufrown == 32;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_4;
			kbufgrpn == 256;
			mid_res_item_n_foreach_row == 25;
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_12)
	`uvm_component_utils(generic_conv_sim_test_12)
	
endclass

class generic_conv_sim_test_13 extends generic_conv_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			fmap_w == 25;
			fmap_h == 25;
			fmap_c == 13;
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.kernal_cfg = KernalCfg::type_id::create();
		if(!kernal_cfg.randomize() with{
			kernal_mem_baseaddr == 2048;
			kernal_shape == KBUFGRPSZ_3x3;
			kernal_num_n == 9;
			kernal_chn_n == 13;
		})
			`uvm_error(this.get_name(), "cannot randomize kernal_cfg!")
		
		this.conv_cal_cfg = ConvCalCfg::type_id::create();
		if(!conv_cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
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
			max_wgtblk_w == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize conv_cal_cfg!")
		
		this.buf_cfg = BufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			fmbufbankn == 2;
			fmbufcoln == COLN_32;
			fmbufrown == 32;
			sfc_n_each_wgtblk == WGTBLK_SFC_N_8;
			kbufgrpn == 99;
			mid_res_item_n_foreach_row == 25;
			mid_res_buf_row_n_bufferable == 4;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_conv_sim_test_13)
	`uvm_component_utils(generic_conv_sim_test_13)
	
endclass

`endif
