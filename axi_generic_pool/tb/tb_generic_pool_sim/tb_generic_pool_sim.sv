import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_defines.svh"
`include "utils.svh"

`include "panda_ext_cfg.svh"
`include "panda_data_obj.svh"
`include "panda_ext_trans.svh"

`include "panda_ext_default_seq.svh"
`include "panda_ext_scoreboard.svh"

`include "panda_ext_env.svh"

`include "panda_test.svh"

module tb_generic_pool_sim();
	
	/** 配置参数 **/
	/*
	配置参数#0:
		parameter INT8_SUPPORTED = 1'b0; // 是否支持INT8运算数据格式
		parameter INT16_SUPPORTED = 1'b0; // 是否支持INT16运算数据格式
		parameter FP16_SUPPORTED = 1'b1; // 是否支持FP16运算数据格式
		parameter integer ATOMIC_C = 8; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
		parameter integer POST_MAC_PRL_N = 1; // 后乘加并行数(1 | 2 | 4 | 8 | 16 | 32)
		parameter integer MM2S_STREAM_DATA_WIDTH = 64; // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
		parameter integer S2MM_STREAM_DATA_WIDTH = 64; // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
		parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
		parameter integer CBUF_DEPTH_FOREACH_BANK = 512; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
		parameter integer MAX_FMBUF_ROWN = 512; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
		parameter integer RBUF_BANK_N = 8; // 中间结果缓存MEM个数(>=2)
		parameter integer RBUF_DEPTH = 512; // 中间结果缓存MEM深度(16 | ...)
	*/
	parameter INT8_SUPPORTED = 1'b0; // 是否支持INT8运算数据格式
	parameter INT16_SUPPORTED = 1'b0; // 是否支持INT16运算数据格式
	parameter FP16_SUPPORTED = 1'b1; // 是否支持FP16运算数据格式
	parameter integer ATOMIC_C = 8; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer POST_MAC_PRL_N = 1; // 后乘加并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64; // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64; // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 8; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512; // 中间结果缓存MEM深度(16 | ...)
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	
	generic_pool_sim_cfg_if cfg_if(clk_if.clk_p, rst_if.reset_n);
	
	panda_blk_ctrl_if fmap_blk_ctrl_if(clk_if.clk_p, rst_if.reset_n);
	panda_blk_ctrl_if fnl_res_trans_blk_ctrl_if(clk_if.clk_p, rst_if.reset_n);
	
	panda_axis_if dma0_strm_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma0_cmd_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if final_res_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if final_res_post_mac_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma_s2mm_cmd_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma_s2mm_strm_axis_if(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial begin
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(virtual generic_pool_sim_cfg_if)::set(null, "uvm_test_top.top_sim_env", "cfg_vif", cfg_if);
		
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "uvm_test_top.top_sim_env", "fmap_blk_ctrl_vif", fmap_blk_ctrl_if);
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "uvm_test_top.top_sim_env", "fnl_res_trans_blk_ctrl_vif", fnl_res_trans_blk_ctrl_if);
		
		uvm_config_db #(panda_axis_vif)::set(null, "uvm_test_top.pool_data_hub_env", "dma0_strm_axis_vif", dma0_strm_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "uvm_test_top.pool_data_hub_env", "dma0_cmd_axis_vif", dma0_cmd_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "uvm_test_top.top_sim_env", "final_res_axis_vif", final_res_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "uvm_test_top.top_sim_env", "final_res_post_mac_axis_vif", final_res_post_mac_axis_if);
		
		uvm_config_db #(panda_axis_vif)::set(null, "uvm_test_top.dma_s2mm_env", "dma_s2mm_cmd_axis_vif", dma_s2mm_cmd_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "uvm_test_top.dma_s2mm_env", "dma_s2mm_strm_axis_vif", dma_s2mm_strm_axis_if);
		
		run_test();
	end
	
	/** 待测模块 **/
	// 运行时参数
	// [计算参数]
	wire[1:0] pool_mode; // 池化模式
	wire[1:0] calfmt; // 运算数据格式
	wire[2:0] pool_horizontal_stride; // 池化水平步长 - 1
	wire[2:0] pool_vertical_stride; // 池化垂直步长 - 1
	wire[7:0] pool_window_w; // 池化窗口宽度 - 1
	wire[7:0] pool_window_h; // 池化窗口高度 - 1
	// [后乘加处理参数]
	wire[4:0] post_mac_fixed_point_quat_accrc; // 定点数量化精度
	wire post_mac_is_a_eq_1; // 参数A的实际值为1(标志)
	wire post_mac_is_b_eq_0; // 参数B的实际值为0(标志)
	wire[31:0] post_mac_param_a; // 参数A
	wire[31:0] post_mac_param_b; // 参数B
	// [上采样参数]
	wire[7:0] upsample_horizontal_n; // 上采样水平复制量 - 1
	wire[7:0] upsample_vertical_n; // 上采样垂直复制量 - 1
	wire non_zero_const_padding_mode; // 是否处于非0常量填充模式
	wire[15:0] const_to_fill; // 待填充的常量
	// [特征图参数]
	wire[31:0] ifmap_baseaddr; // 输入特征图基地址
	wire[31:0] ofmap_baseaddr; // 输出特征图基地址
	wire is_16bit_data; // 是否16位(输入)特征图数据
	wire[15:0] ifmap_w; // 输入特征图宽度 - 1
	wire[15:0] ifmap_h; // 输入特征图高度 - 1
	wire[23:0] ifmap_size; // 输入特征图大小 - 1
	wire[15:0] ext_ifmap_w; // 扩展输入特征图宽度 - 1
	wire[15:0] ext_ifmap_h; // 扩展输入特征图高度 - 1
	wire[15:0] fmap_chn_n; // 通道数 - 1
	wire[2:0] external_padding_left; // 左部外填充数
	wire[2:0] external_padding_top; // 上部外填充数
	wire[15:0] ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] ofmap_h; // 输出特征图高度 - 1
	wire[1:0] ofmap_data_type; // 输出特征图数据大小类型
	// [特征图缓存参数]
	wire[3:0] fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] fmbufrown; // 可缓存的表面行数 - 1
	// [中间结果缓存参数]
	wire[3:0] mid_res_buf_row_n_bufferable; // 可缓存行数 - 1
	// 控制信号
	wire en_adapter; // 使能适配器
	wire en_post_mac; // 使能后乘加处理
	// 块级控制
	// [池化表面行缓存访问控制]
	wire sfc_row_access_blk_start;
	wire sfc_row_access_blk_idle;
	wire sfc_row_access_blk_done;
	// [最终结果传输请求生成单元]
	wire fnl_res_tr_req_gen_blk_start;
	wire fnl_res_tr_req_gen_blk_idle;
	wire fnl_res_tr_req_gen_blk_done;
	// S2MM方向DMA命令(AXIS主机)
	wire[55:0] m_dma_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_dma_s2mm_cmd_axis_user; // 固定(1'b1)/递增(1'b0)传输(1bit)
	wire m_dma_s2mm_cmd_axis_valid;
	wire m_dma_s2mm_cmd_axis_ready;
	// 最终结果输出(AXIS主机)
	wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_fnl_res_data;
	wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep;
	wire m_axis_fnl_res_last; // 本行最后1个最终结果(标志)
	wire m_axis_fnl_res_valid;
	wire m_axis_fnl_res_ready;
	// DMA(MM2S方向)命令流(AXIS主机)
	wire[55:0] m_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_dma_cmd_axis_last; // 帧尾标志
	wire m_dma_cmd_axis_valid;
	wire m_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流(AXIS从机)
	wire[MM2S_STREAM_DATA_WIDTH-1:0] s_dma_strm_axis_data;
	wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s_dma_strm_axis_keep;
	wire s_dma_strm_axis_last;
	wire s_dma_strm_axis_valid;
	wire s_dma_strm_axis_ready;
	
	assign pool_mode = cfg_if.pool_mode;
	assign calfmt = cfg_if.calfmt;
	assign pool_horizontal_stride = cfg_if.pool_horizontal_stride;
	assign pool_vertical_stride = cfg_if.pool_vertical_stride;
	assign pool_window_w = cfg_if.pool_window_w;
	assign pool_window_h = cfg_if.pool_window_h;
	assign post_mac_fixed_point_quat_accrc = cfg_if.post_mac_fixed_point_quat_accrc;
	assign post_mac_is_a_eq_1 = cfg_if.post_mac_is_a_eq_1;
	assign post_mac_is_b_eq_0 = cfg_if.post_mac_is_b_eq_0;
	assign post_mac_param_a = cfg_if.post_mac_param_a;
	assign post_mac_param_b = cfg_if.post_mac_param_b;
	assign upsample_horizontal_n = cfg_if.upsample_horizontal_n;
	assign upsample_vertical_n = cfg_if.upsample_vertical_n;
	assign non_zero_const_padding_mode = cfg_if.non_zero_const_padding_mode;
	assign const_to_fill = cfg_if.const_to_fill;
	assign ifmap_baseaddr = cfg_if.ifmap_baseaddr;
	assign ofmap_baseaddr = cfg_if.ofmap_baseaddr;
	assign is_16bit_data = cfg_if.is_16bit_data;
	assign ifmap_w = cfg_if.ifmap_w;
	assign ifmap_h = cfg_if.ifmap_h;
	assign ifmap_size = cfg_if.ifmap_size;
	assign ext_ifmap_w = cfg_if.ext_ifmap_w;
	assign ext_ifmap_h = cfg_if.ext_ifmap_h;
	assign fmap_chn_n = cfg_if.fmap_chn_n;
	assign external_padding_left = cfg_if.external_padding_left;
	assign external_padding_top = cfg_if.external_padding_top;
	assign ofmap_w = cfg_if.ofmap_w;
	assign ofmap_h = cfg_if.ofmap_h;
	assign ofmap_data_type = cfg_if.ofmap_data_type;
	assign fmbufcoln = cfg_if.fmbufcoln;
	assign fmbufrown = cfg_if.fmbufrown;
	assign mid_res_buf_row_n_bufferable = cfg_if.mid_res_buf_row_n_bufferable;
	assign en_adapter = cfg_if.en_adapter;
	assign en_post_mac = cfg_if.en_post_mac;
	
	assign sfc_row_access_blk_start = fmap_blk_ctrl_if.start;
	assign fmap_blk_ctrl_if.idle = sfc_row_access_blk_idle;
	assign fmap_blk_ctrl_if.done = sfc_row_access_blk_done;
	
	assign fnl_res_tr_req_gen_blk_start = fnl_res_trans_blk_ctrl_if.start;
	assign fnl_res_trans_blk_ctrl_if.idle = fnl_res_tr_req_gen_blk_idle;
	assign fnl_res_trans_blk_ctrl_if.done = fnl_res_tr_req_gen_blk_done;
	
	assign dma0_cmd_axis_if.data[55:0] = m_dma_cmd_axis_data;
	assign dma0_cmd_axis_if.user[0] = m_dma_cmd_axis_user;
	assign dma0_cmd_axis_if.last = m_dma_cmd_axis_last;
	assign dma0_cmd_axis_if.valid = m_dma_cmd_axis_valid;
	assign m_dma_cmd_axis_ready = dma0_cmd_axis_if.ready;
	
	assign final_res_axis_if.data[ATOMIC_C*32-1:0] = dut.m_axis_mid_res_buf_data;
	assign final_res_axis_if.keep[ATOMIC_C*4-1:0] = dut.m_axis_mid_res_buf_keep;
	assign final_res_axis_if.last = dut.m_axis_mid_res_buf_last;
	assign final_res_axis_if.valid = dut.m_axis_mid_res_buf_valid;
	assign final_res_axis_if.ready = dut.m_axis_mid_res_buf_ready;
	
	assign final_res_post_mac_axis_if.data[POST_MAC_PRL_N*32-1:0] = dut.m_axis_post_mac_data;
	assign final_res_post_mac_axis_if.keep[POST_MAC_PRL_N*4-1:0] = dut.m_axis_post_mac_keep;
	assign final_res_post_mac_axis_if.last = dut.m_axis_post_mac_last;
	assign final_res_post_mac_axis_if.valid = dut.m_axis_post_mac_valid;
	assign final_res_post_mac_axis_if.ready = dut.m_axis_post_mac_ready;
	
	assign dma_s2mm_cmd_axis_if.data[55:0] = m_dma_s2mm_cmd_axis_data;
	assign dma_s2mm_cmd_axis_if.user[0] = m_dma_s2mm_cmd_axis_user;
	assign dma_s2mm_cmd_axis_if.valid = m_dma_s2mm_cmd_axis_valid;
	assign m_dma_s2mm_cmd_axis_ready = dma_s2mm_cmd_axis_if.ready;
	
	assign dma_s2mm_strm_axis_if.data[S2MM_STREAM_DATA_WIDTH-1:0] = m_axis_fnl_res_data;
	assign dma_s2mm_strm_axis_if.keep[S2MM_STREAM_DATA_WIDTH/8-1:0] = m_axis_fnl_res_keep;
	assign dma_s2mm_strm_axis_if.last = m_axis_fnl_res_last;
	assign dma_s2mm_strm_axis_if.valid = m_axis_fnl_res_valid;
	assign m_axis_fnl_res_ready = dma_s2mm_strm_axis_if.ready;
	
	assign s_dma_strm_axis_data = dma0_strm_axis_if.data[MM2S_STREAM_DATA_WIDTH-1:0];
	assign s_dma_strm_axis_keep = dma0_strm_axis_if.keep[MM2S_STREAM_DATA_WIDTH/8-1:0];
	assign s_dma_strm_axis_last = dma0_strm_axis_if.last;
	assign s_dma_strm_axis_valid = dma0_strm_axis_if.valid;
	assign dma0_strm_axis_if.ready = s_dma_strm_axis_ready;
	
	generic_pool_sim #(
		.ATOMIC_C(ATOMIC_C),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		
		.pool_mode(pool_mode),
		.calfmt(calfmt),
		.pool_horizontal_stride(pool_horizontal_stride),
		.pool_vertical_stride(pool_vertical_stride),
		.pool_window_w(pool_window_w),
		.pool_window_h(pool_window_h),
		.post_mac_fixed_point_quat_accrc(post_mac_fixed_point_quat_accrc),
		.post_mac_is_a_eq_1(post_mac_is_a_eq_1),
		.post_mac_is_b_eq_0(post_mac_is_b_eq_0),
		.post_mac_param_a(post_mac_param_a),
		.post_mac_param_b(post_mac_param_b),
		.upsample_horizontal_n(upsample_horizontal_n),
		.upsample_vertical_n(upsample_vertical_n),
		.non_zero_const_padding_mode(non_zero_const_padding_mode),
		.const_to_fill(const_to_fill),
		.ifmap_baseaddr(ifmap_baseaddr),
		.ofmap_baseaddr(ofmap_baseaddr),
		.is_16bit_data(is_16bit_data),
		.ifmap_w(ifmap_w),
		.ifmap_h(ifmap_h),
		.ifmap_size(ifmap_size),
		.ext_ifmap_w(ext_ifmap_w),
		.ext_ifmap_h(ext_ifmap_h),
		.fmap_chn_n(fmap_chn_n),
		.external_padding_left(external_padding_left),
		.external_padding_top(external_padding_top),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		.mid_res_buf_row_n_bufferable(mid_res_buf_row_n_bufferable),
		
		.en_adapter(en_adapter),
		.en_post_mac(en_post_mac),
		
		.sfc_row_access_blk_start(sfc_row_access_blk_start),
		.sfc_row_access_blk_idle(sfc_row_access_blk_idle),
		.sfc_row_access_blk_done(sfc_row_access_blk_done),
		
		.fnl_res_tr_req_gen_blk_start(fnl_res_tr_req_gen_blk_start),
		.fnl_res_tr_req_gen_blk_idle(fnl_res_tr_req_gen_blk_idle),
		.fnl_res_tr_req_gen_blk_done(fnl_res_tr_req_gen_blk_done),
		
		.m_dma_s2mm_cmd_axis_data(m_dma_s2mm_cmd_axis_data),
		.m_dma_s2mm_cmd_axis_user(m_dma_s2mm_cmd_axis_user),
		.m_dma_s2mm_cmd_axis_valid(m_dma_s2mm_cmd_axis_valid),
		.m_dma_s2mm_cmd_axis_ready(m_dma_s2mm_cmd_axis_ready),
		
		.m_axis_fnl_res_data(m_axis_fnl_res_data),
		.m_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.m_axis_fnl_res_last(m_axis_fnl_res_last),
		.m_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.m_axis_fnl_res_ready(m_axis_fnl_res_ready),
		
		.m_dma_cmd_axis_data(m_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m_dma_cmd_axis_user),
		.m_dma_cmd_axis_last(m_dma_cmd_axis_last),
		.m_dma_cmd_axis_valid(m_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m_dma_cmd_axis_ready),
		
		.s_dma_strm_axis_data(s_dma_strm_axis_data),
		.s_dma_strm_axis_keep(s_dma_strm_axis_keep),
		.s_dma_strm_axis_last(s_dma_strm_axis_last),
		.s_dma_strm_axis_valid(s_dma_strm_axis_valid),
		.s_dma_strm_axis_ready(s_dma_strm_axis_ready)
	);
	
endmodule
