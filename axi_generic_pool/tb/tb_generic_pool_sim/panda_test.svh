`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class FmapCst0PackedReal extends PackedReal;
	
	rand int coef;
	
	constraint c_coef{
		coef dist {[-200:-1]:/3, 0:/1, [1:200]:/3};
	}
	
	virtual function bit do_rand(uvm_object rand_context);
		if(!this.randomize())
			return 1'b0;
		
		this.data = 0.1 * this.coef;
		
		return 1'b1;
	endfunction
	
	`tue_object_default_constructor(FmapCst0PackedReal)
	`uvm_object_utils(FmapCst0PackedReal)
	
endclass

class generic_pool_sim_base_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	protected int unsigned ATOMIC_C = 8; // 通道并行数
	protected int unsigned POST_MAC_PRL_N = 1; // 后乘加并行数
	protected int unsigned STREAM_DATA_WIDTH = 64; // DMA数据流的位宽(32 | 64 | 128 | 256)
	protected int unsigned FNL_RES_DATA_WIDTH = 64; // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	
	protected bit en_output_mem_bin = 1'b0; // 是否生成特征图BIN文件
	
	protected PoolDataHubTestEnv pool_data_hub_env;
	protected GenericPoolSimTestEnv top_sim_env;
	protected DMAS2MMEnv dma_s2mm_env;
	
	protected FmapCfg fmap_cfg;
	protected PoolCalCfg cal_cfg;
	protected PoolBufferCfg buf_cfg;
	
	function new(string name = "generic_pool_sim_base_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 100us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		int cfg_log_fid;
		int mem_bin_fid[1];
		
		FmapBuilderCfg fmap_builder_cfg;
		FmapBuilder fmap_builder;
		Fmap fmap;
		PandaMemoryAdapter fmap_mem_adpt;
		
		FmapCst0PackedReal fmap_data_gen;
		
		cfg_log_fid = $fopen("cfg_log.txt");
		
		if(this.en_output_mem_bin)
		begin
			mem_bin_fid[0] = $fopen("in_fmap.bin", "wb");
		end
		
		fmap_data_gen = FmapCst0PackedReal::type_id::create();
		
		this.build_test_cfg();
		
		fmap_builder_cfg = FmapBuilderCfg::type_id::create();
		fmap_builder_cfg.from_cfg_2(this.fmap_cfg, this.cal_cfg.atomic_c);
		
		fmap_builder = FmapBuilder::type_id::create();
		fmap_builder.set_data_gen(fmap_data_gen);
		fmap_builder.build_default_feature_map(fmap_builder_cfg);
		fmap = fmap_builder.get_feature_map();
		
		fmap_mem_adpt = new(fmap, "FmapPandaMemoryAdapter", 16);
		
		if(this.en_output_mem_bin)
		begin
			if(!fmap_mem_adpt.output_to_bin(
				mem_bin_fid[0], fmap_mem_adpt.data_blk.get_baseaddr(), fmap_mem_adpt.data_blk.get_len_in_byte()
			))
				`uvm_error(this.get_name(), "cannot output in_fmap.bin")
		end
		
		uvm_config_db #(FmapCfg)::set(null, "", "fmap_cfg", this.fmap_cfg);
		uvm_config_db #(PoolCalCfg)::set(null, "", "cal_cfg", this.cal_cfg);
		uvm_config_db #(PoolBufferCfg)::set(null, "", "buf_cfg", this.buf_cfg);
		uvm_config_db #(PandaMemoryAdapter)::set(null, "", "fmap_mem", fmap_mem_adpt);
		
		`panda_print_with(this.fmap_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(this.cal_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(this.buf_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(fmap_builder_cfg, cfg_log_fid, Util::get_object_printer())
		`panda_print_with(fmap, cfg_log_fid, Util::get_object_printer())
		
		$fclose(cfg_log_fid);
		
		if(this.en_output_mem_bin)
		begin
			foreach(mem_bin_fid[_i])
			begin
				$fclose(mem_bin_fid[_i]);
			end
		end
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.pool_data_hub_env = PoolDataHubTestEnv::type_id::create("pool_data_hub_env", this);
		
		this.top_sim_env = GenericPoolSimTestEnv::type_id::create("top_sim_env", this);
		this.top_sim_env.disable_connect_final_res_export();
		
		this.dma_s2mm_env = DMAS2MMEnv::type_id::create("dma_s2mm_env", this);
		this.dma_s2mm_env.en_output_mem_bin = this.en_output_mem_bin;
	endfunction
	
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction
	
	virtual protected function void build_test_cfg();
		// blank
	endfunction
	
	`uvm_component_utils(generic_pool_sim_base_test)
	
endclass

/**
最大池化CASE#0:

常规最大池化测试

使用配置参数#0

特征图 -> w30 h20 c10
特征图外填充 -> L0 R0 T0 B0
池化窗口 -> w2 h2
池化步长 -> h2 v2
**/
class generic_pool_sim_test_max_pool_0 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 30;
			fmap_h == 20;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_MAX;
			calfmt == CAL_FMT_FP16;
			
			pool_horizontal_stride == 2;
			pool_vertical_stride == 2;
			pool_window_w == 2;
			pool_window_h == 2;
			
			external_padding_left == 0;
			external_padding_right == 0;
			external_padding_top == 0;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_32;
			fmbufrown == 256;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_max_pool_0)
	`uvm_component_utils(generic_pool_sim_test_max_pool_0)
	
endclass

/**
最大池化CASE#1:

常规最大池化测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L1 R0 T1 B0
池化窗口 -> w2 h2
池化步长 -> h1 v1
**/
class generic_pool_sim_test_max_pool_1 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_MAX;
			calfmt == CAL_FMT_FP16;
			
			pool_horizontal_stride == 1;
			pool_vertical_stride == 1;
			pool_window_w == 2;
			pool_window_h == 2;
			
			external_padding_left == 1;
			external_padding_right == 0;
			external_padding_top == 1;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_max_pool_1)
	`uvm_component_utils(generic_pool_sim_test_max_pool_1)
	
endclass

/**
平均池化CASE#0:

常规平均池化测试

使用配置参数#0

特征图 -> w30 h20 c10
特征图外填充 -> L0 R0 T0 B0
池化窗口 -> w2 h2
池化步长 -> h2 v2
**/
class generic_pool_sim_test_avg_pool_0 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 30;
			fmap_h == 20;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_AVG;
			calfmt == CAL_FMT_FP16;
			
			pool_horizontal_stride == 2;
			pool_vertical_stride == 2;
			pool_window_w == 2;
			pool_window_h == 2;
			
			external_padding_left == 0;
			external_padding_right == 0;
			external_padding_top == 0;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_32;
			fmbufrown == 256;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_avg_pool_0)
	`uvm_component_utils(generic_pool_sim_test_avg_pool_0)
	
endclass

/**
平均池化CASE#1:

常规平均池化测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L1 R0 T1 B0
池化窗口 -> w2 h2
池化步长 -> h1 v1
**/
class generic_pool_sim_test_avg_pool_1 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_AVG;
			calfmt == CAL_FMT_FP16;
			
			pool_horizontal_stride == 1;
			pool_vertical_stride == 1;
			pool_window_w == 2;
			pool_window_h == 2;
			
			external_padding_left == 1;
			external_padding_right == 0;
			external_padding_top == 1;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_avg_pool_1)
	`uvm_component_utils(generic_pool_sim_test_avg_pool_1)
	
endclass

/**
平均池化CASE#2:

带后乘加处理的平均池化测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L1 R0 T1 B0
池化窗口 -> w2 h2
池化步长 -> h1 v1
**/
class generic_pool_sim_test_avg_pool_2 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			post_mac_prl_n == POST_MAC_PRL_N;
			
			pool_mode == POOL_MODE_AVG;
			calfmt == CAL_FMT_FP16;
			
			pool_horizontal_stride == 1;
			pool_vertical_stride == 1;
			pool_window_w == 2;
			pool_window_h == 2;
			
			external_padding_left == 1;
			external_padding_right == 0;
			external_padding_top == 1;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b1;
			post_mac_is_a_eq_1 == 1'b0;
			post_mac_is_b_eq_0 == 1'b0;
			post_mac_param_a == 32'h3E800000; // 0.25
			post_mac_param_b == 32'h3FE00000; // 1.75
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_avg_pool_2)
	`uvm_component_utils(generic_pool_sim_test_avg_pool_2)
	
endclass

/**
上采样CASE#0:

常规上采样测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L0 R0 T0 B0
上采样复制量 -> h2 v2
**/
class generic_pool_sim_test_up_sample_0 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_UPSP;
			calfmt == CAL_FMT_FP16;
			
			upsample_horizontal_n == 2;
			upsample_vertical_n == 2;
			non_zero_const_padding_mode == 1'b0;
			
			external_padding_left == 0;
			external_padding_right == 0;
			external_padding_top == 0;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_up_sample_0)
	`uvm_component_utils(generic_pool_sim_test_up_sample_0)
	
endclass

/**
上采样CASE#1:

常规上采样测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L0 R0 T0 B0
上采样复制量 -> h2 v1
**/
class generic_pool_sim_test_up_sample_1 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_UPSP;
			calfmt == CAL_FMT_FP16;
			
			upsample_horizontal_n == 2;
			upsample_vertical_n == 1;
			non_zero_const_padding_mode == 1'b0;
			
			external_padding_left == 0;
			external_padding_right == 0;
			external_padding_top == 0;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_up_sample_1)
	`uvm_component_utils(generic_pool_sim_test_up_sample_1)
	
endclass

/**
上采样CASE#2:

常规上采样测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L0 R0 T0 B0
上采样复制量 -> h1 v2
**/
class generic_pool_sim_test_up_sample_2 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_UPSP;
			calfmt == CAL_FMT_FP16;
			
			upsample_horizontal_n == 1;
			upsample_vertical_n == 2;
			non_zero_const_padding_mode == 1'b0;
			
			external_padding_left == 0;
			external_padding_right == 0;
			external_padding_top == 0;
			external_padding_bottom == 0;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_up_sample_2)
	`uvm_component_utils(generic_pool_sim_test_up_sample_2)
	
endclass

/**
填充CASE#0:

零填充测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L1 R1 T1 B1
上采样复制量 -> h1 v1
**/
class generic_pool_sim_test_padding_0 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_UPSP;
			calfmt == CAL_FMT_FP16;
			
			upsample_horizontal_n == 1;
			upsample_vertical_n == 1;
			non_zero_const_padding_mode == 1'b0;
			
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_padding_0)
	`uvm_component_utils(generic_pool_sim_test_padding_0)
	
endclass

/**
填充CASE#1:

非零填充测试

使用配置参数#0

特征图 -> w16 h16 c10
特征图外填充 -> L1 R1 T1 B1
上采样复制量 -> h1 v1
**/
class generic_pool_sim_test_padding_1 extends generic_pool_sim_base_test;
	
	virtual protected function void build_test_cfg();
		this.fmap_cfg = FmapCfg::type_id::create();
		if(!fmap_cfg.randomize() with{
			fmap_mem_baseaddr == 1024;
			ofmap_baseaddr == 512;
			
			fmap_w == 16;
			fmap_h == 16;
			fmap_c == 10;
			
			ofmap_data_type == DATA_4_BYTE;
		})
			`uvm_error(this.get_name(), "cannot randomize fmap_cfg!")
		
		this.cal_cfg = PoolCalCfg::type_id::create();
		if(!cal_cfg.randomize() with{
			atomic_c == ATOMIC_C;
			
			pool_mode == POOL_MODE_UPSP;
			calfmt == CAL_FMT_FP16;
			
			upsample_horizontal_n == 1;
			upsample_vertical_n == 1;
			non_zero_const_padding_mode == 1'b1;
			const_to_fill == 16'h3c00;
			
			external_padding_left == 1;
			external_padding_right == 1;
			external_padding_top == 1;
			external_padding_bottom == 1;
			
			enable_post_mac == 1'b0;
		})
			`uvm_error(this.get_name(), "cannot randomize cal_cfg!")
		
		this.buf_cfg = PoolBufferCfg::type_id::create();
		if(!buf_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			fnl_res_data_width == FNL_RES_DATA_WIDTH;
			
			fmbufbankn == 16;
			fmbufcoln == COLN_16;
			fmbufrown == 512;
			
			mid_res_buf_row_n_bufferable == 8;
		})
			`uvm_error(this.get_name(), "cannot randomize buf_cfg!")
	endfunction
	
	`tue_component_default_constructor(generic_pool_sim_test_padding_1)
	`uvm_component_utils(generic_pool_sim_test_padding_1)
	
endclass

`endif
