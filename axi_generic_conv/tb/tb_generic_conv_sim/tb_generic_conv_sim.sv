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

module tb_generic_conv_sim();
	
	/** 配置参数 **/
	/*
	配置参数#0:
	parameter integer ATOMIC_K = 4; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 2; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1; // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2; // 最大的计算轮次(1~16)
	parameter integer STREAM_DATA_WIDTH = 64; // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer FNL_RES_DATA_WIDTH = 64; // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 128; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_KERNAL_N = 1024; // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 128; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 16; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 32; // 中间结果缓存MEM深度(16 | ...)
	
	配置参数#1:
	parameter integer ATOMIC_K = 4; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1; // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2; // 最大的计算轮次(1~16)
	parameter integer STREAM_DATA_WIDTH = 64; // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer FNL_RES_DATA_WIDTH = 64; // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 1024; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_KERNAL_N = 1024; // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 8; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512; // 中间结果缓存MEM深度(16 | ...)
	
	配置参数#2:
	parameter integer ATOMIC_K = 8; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 8; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1; // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2; // 最大的计算轮次(1~16)
	parameter integer STREAM_DATA_WIDTH = 64; // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer FNL_RES_DATA_WIDTH = 64; // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_KERNAL_N = 1024; // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 4; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512; // 中间结果缓存MEM深度(16 | ...)
	
	配置参数#3:
	parameter integer MAC_ARRAY_CLK_RATE = 2; // 计算核心时钟倍率(>=1)
	parameter integer ATOMIC_K = 16; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 16; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1; // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2; // 最大的计算轮次(1~16)
	parameter integer STREAM_DATA_WIDTH = 64; // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer FNL_RES_DATA_WIDTH = 64; // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 128; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_KERNAL_N = 1024; // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 128; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 16; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 32; // 中间结果缓存MEM深度(16 | ...)
	*/
	parameter integer MAC_ARRAY_CLK_RATE = 1; // 计算核心时钟倍率(>=1)
	parameter integer BN_ACT_CLK_RATE = 1; // BN与激活单元的时钟倍率(>=1)
	parameter integer ATOMIC_K = 16; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 16; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1; // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2; // 最大的计算轮次(1~16)
	parameter integer STREAM_DATA_WIDTH = 64; // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer FNL_RES_DATA_WIDTH = 64; // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 128; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_KERNAL_N = 1024; // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 128; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 16; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 32; // 中间结果缓存MEM深度(16 | ...)
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	
	generic_conv_sim_cfg_if cfg_if(clk_if.clk_p, rst_if.reset_n);
	
	panda_blk_ctrl_if fmap_blk_ctrl_if(clk_if.clk_p, rst_if.reset_n);
	panda_blk_ctrl_if kernal_blk_ctrl_if(clk_if.clk_p, rst_if.reset_n);
	panda_blk_ctrl_if fnl_res_trans_blk_ctrl_if(clk_if.clk_p, rst_if.reset_n);
	panda_blk_ctrl_if fmap_blk_ctrl_if_2(clk_if.clk_p, rst_if.reset_n);
	panda_blk_ctrl_if kernal_blk_ctrl_if_2(clk_if.clk_p, rst_if.reset_n);
	panda_blk_ctrl_if fnl_res_trans_blk_ctrl_if_2(clk_if.clk_p, rst_if.reset_n);
	
	panda_axis_if fmap_rd_req_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if fm_cake_info_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if kernal_rd_req_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if fm_fout_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if kout_wgtblk_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma0_strm_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma1_strm_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma0_cmd_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma1_cmd_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if final_res_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma_s2mm_strm_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma_s2mm_cmd_axis_if(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma_s2mm_cmd_axis_if_2(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if sub_row_msg_axis_if(clk_if.clk_p, rst_if.reset_n);
	
	panda_axis_if acmlt_in_if[ATOMIC_K-1:0](clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial begin
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(virtual generic_conv_sim_cfg_if)::set(null, "", "cfg_vif", cfg_if);
		
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "fmap_blk_ctrl_vif", fmap_blk_ctrl_if);
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "kernal_blk_ctrl_vif", kernal_blk_ctrl_if);
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "fnl_res_trans_blk_ctrl_vif", fnl_res_trans_blk_ctrl_if);
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "fmap_blk_ctrl_vif_2", fmap_blk_ctrl_if_2);
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "kernal_blk_ctrl_vif_2", kernal_blk_ctrl_if_2);
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "fnl_res_trans_blk_ctrl_vif_2", fnl_res_trans_blk_ctrl_if_2);
		
		uvm_config_db #(panda_axis_vif)::set(null, "", "fmap_rd_req_axis_vif", fmap_rd_req_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "fm_cake_info_axis_vif", fm_cake_info_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "kernal_rd_req_axis_vif", kernal_rd_req_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "fm_fout_axis_vif", fm_fout_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "kout_wgtblk_axis_vif", kout_wgtblk_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma0_strm_axis_vif", dma0_strm_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma1_strm_axis_vif", dma1_strm_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma0_cmd_axis_vif", dma0_cmd_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma1_cmd_axis_vif", dma1_cmd_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "final_res_axis_vif", final_res_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma_s2mm_strm_axis_vif", dma_s2mm_strm_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma_s2mm_cmd_axis_vif", dma_s2mm_cmd_axis_if);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma_s2mm_cmd_axis_vif_2", dma_s2mm_cmd_axis_if_2);
		uvm_config_db #(panda_axis_vif)::set(null, "", "sub_row_msg_axis_vif", sub_row_msg_axis_if);
		
		run_test();
	end
	
	/** 待测模块 **/
	// 使能信号
	wire en_mac_array; // 使能乘加阵列
	wire en_packer; // 使能打包器
	wire en_bn_act_proc; // 使能批归一化与激活处理单元
	// 运行时参数
	// [计算参数]
	wire[1:0] calfmt; // 运算数据格式
	wire[2:0] conv_vertical_stride; // 卷积垂直步长 - 1
	wire[2:0] conv_horizontal_stride; // 卷积水平步长 - 1
	wire[3:0] cal_round; // 计算轮次 - 1
	// [组卷积模式]
	wire is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] group_n; // 分组数 - 1
	wire[15:0] n_foreach_group; // 每组的通道数/核数 - 1
	wire[31:0] data_size_foreach_group; // (特征图)每组的数据量
	// [特征图参数]
	wire[31:0] ifmap_baseaddr; // 输入特征图基地址
	wire[31:0] ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] ifmap_w; // 输入特征图宽度 - 1
	wire[23:0] ifmap_size; // 输入特征图大小 - 1
	wire[15:0] fmap_chn_n; // 特征图通道数 - 1
	wire[15:0] fmap_ext_i_bottom; // 扩展后特征图的垂直边界
	wire[2:0] external_padding_left; // 左部外填充数
	wire[2:0] external_padding_top; // 上部外填充数
	wire[2:0] inner_padding_left_right; // 左右内填充数
	wire[2:0] inner_padding_top_bottom; // 上下内填充数
	wire[15:0] ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] ofmap_h; // 输出特征图高度 - 1
	wire[1:0] ofmap_data_type; // 输出特征图数据大小类型
	// [卷积核参数]
	wire[31:0] kernal_wgt_baseaddr; // 卷积核权重基地址
	wire[2:0] kernal_shape; // 卷积核形状
	wire[3:0] kernal_dilation_hzt_n; // 水平膨胀量
	wire[4:0] kernal_w_dilated; // (膨胀后)卷积核宽度 - 1
	wire[3:0] kernal_dilation_vtc_n; // 垂直膨胀量
	wire[4:0] kernal_h_dilated; // (膨胀后)卷积核高度 - 1
	wire[15:0] kernal_chn_n; // 通道数 - 1
	wire[15:0] cgrpn_foreach_kernal_set; // 每个核组的通道组数 - 1
	wire[15:0] kernal_num_n; // 核数 - 1
	wire[15:0] kernal_set_n; // 核组个数 - 1
	wire[5:0] max_wgtblk_w; // 权重块最大宽度
	// [缓存参数]
	wire[7:0] fmbufbankn; // 分配给特征图缓存的Bank数
	wire[3:0] fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] fmbufrown; // 可缓存的表面行数 - 1
	wire[2:0] sfc_n_each_wgtblk; // 每个权重块的表面个数的类型
	wire[7:0] kbufgrpn; // 可缓存的通道组数 - 1
	wire[15:0] mid_res_item_n_foreach_row; // 每个输出特征图表面行的中间结果项数 - 1
	wire[3:0] mid_res_buf_row_n_bufferable; // 可缓存行数 - 1
	// [批归一化参数]
	wire[4:0] bn_fixed_point_quat_accrc; // 定点数量化精度
	wire bn_is_a_eq_1; // 参数A的实际值为1(标志)
	wire bn_is_b_eq_0; // 参数B的实际值为0(标志)
	// BN参数MEM(写端口)
	wire bn_mem_wen_a;
	wire[15:0] bn_mem_addr_a;
	wire[63:0] bn_mem_din_a; // {参数B(32bit), 参数A(32bit)}
	// 块级控制
	// [卷积核权重访问请求生成单元]
	wire kernal_access_blk_start;
	wire kernal_access_blk_idle;
	wire kernal_access_blk_done;
	// [特征图表面行访问请求生成单元]
	wire fmap_access_blk_start;
	wire fmap_access_blk_idle;
	wire fmap_access_blk_done;
	// [最终结果传输请求生成单元]
	wire fnl_res_trans_blk_start;
	wire fnl_res_trans_blk_idle;
	wire fnl_res_trans_blk_done;
	// DMA(MM2S方向)命令流#0(AXIS主机)
	wire[55:0] m0_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m0_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m0_dma_cmd_axis_last; // 帧尾标志
	wire m0_dma_cmd_axis_valid;
	wire m0_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#0(AXIS从机)
	wire[STREAM_DATA_WIDTH-1:0] s0_dma_strm_axis_data;
	wire[STREAM_DATA_WIDTH/8-1:0] s0_dma_strm_axis_keep;
	wire s0_dma_strm_axis_last;
	wire s0_dma_strm_axis_valid;
	wire s0_dma_strm_axis_ready;
	// DMA(MM2S方向)命令流#1(AXIS主机)
	wire[55:0] m1_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m1_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m1_dma_cmd_axis_last; // 帧尾标志
	wire m1_dma_cmd_axis_valid;
	wire m1_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#1(AXIS从机)
	wire[STREAM_DATA_WIDTH-1:0] s1_dma_strm_axis_data;
	wire[STREAM_DATA_WIDTH/8-1:0] s1_dma_strm_axis_keep;
	wire s1_dma_strm_axis_last;
	wire s1_dma_strm_axis_valid;
	wire s1_dma_strm_axis_ready;
	// S2MM方向DMA命令(AXIS主机)
	wire[55:0] m_dma_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_dma_s2mm_cmd_axis_user; // 固定(1'b1)/递增(1'b0)传输(1bit)
	wire m_dma_s2mm_cmd_axis_valid;
	wire m_dma_s2mm_cmd_axis_ready;
	// 最终结果输出(AXIS主机)
	wire[FNL_RES_DATA_WIDTH-1:0] m_axis_fnl_res_data;
	wire[FNL_RES_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep;
	wire[4:0] m_axis_fnl_res_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_fnl_res_last; // 本行最后1个最终结果(标志)
	wire m_axis_fnl_res_valid;
	wire m_axis_fnl_res_ready;
	
	assign en_mac_array = cfg_if.en_mac_array;
	assign en_packer = cfg_if.en_packer;
	assign en_bn_act_proc = cfg_if.en_bn_act_proc;
	
	assign calfmt = cfg_if.calfmt;
	assign conv_vertical_stride = cfg_if.conv_vertical_stride;
	assign conv_horizontal_stride = cfg_if.conv_horizontal_stride;
	assign cal_round = cfg_if.cal_round;
	assign is_grp_conv_mode = cfg_if.is_grp_conv_mode;
	assign group_n = cfg_if.group_n;
	assign n_foreach_group = cfg_if.n_foreach_group;
	assign data_size_foreach_group = cfg_if.data_size_foreach_group;
	assign ifmap_baseaddr = cfg_if.ifmap_baseaddr;
	assign ofmap_baseaddr = cfg_if.ofmap_baseaddr;
	assign ifmap_w = cfg_if.ifmap_w;
	assign ifmap_size = cfg_if.ifmap_size;
	assign fmap_chn_n = cfg_if.fmap_chn_n;
	assign fmap_ext_i_bottom = cfg_if.fmap_ext_i_bottom;
	assign external_padding_left = cfg_if.external_padding_left;
	assign external_padding_top = cfg_if.external_padding_top;
	assign inner_padding_left_right = cfg_if.inner_padding_left_right;
	assign inner_padding_top_bottom = cfg_if.inner_padding_top_bottom;
	assign ofmap_w = cfg_if.ofmap_w;
	assign ofmap_h = cfg_if.ofmap_h;
	assign ofmap_data_type = cfg_if.ofmap_data_type;
	assign kernal_wgt_baseaddr = cfg_if.kernal_wgt_baseaddr;
	assign kernal_shape = cfg_if.kernal_shape;
	assign kernal_dilation_hzt_n = cfg_if.kernal_dilation_hzt_n;
	assign kernal_w_dilated = cfg_if.kernal_w_dilated;
	assign kernal_dilation_vtc_n = cfg_if.kernal_dilation_vtc_n;
	assign kernal_h_dilated = cfg_if.kernal_h_dilated;
	assign kernal_chn_n = cfg_if.kernal_chn_n;
	assign cgrpn_foreach_kernal_set = cfg_if.cgrpn_foreach_kernal_set;
	assign kernal_num_n = cfg_if.kernal_num_n;
	assign kernal_set_n = cfg_if.kernal_set_n;
	assign max_wgtblk_w = cfg_if.max_wgtblk_w;
	assign fmbufbankn = cfg_if.fmbufbankn;
	assign fmbufcoln = cfg_if.fmbufcoln;
	assign fmbufrown = cfg_if.fmbufrown;
	assign sfc_n_each_wgtblk = cfg_if.sfc_n_each_wgtblk;
	assign kbufgrpn = cfg_if.kbufgrpn;
	assign mid_res_item_n_foreach_row = cfg_if.mid_res_item_n_foreach_row;
	assign mid_res_buf_row_n_bufferable = cfg_if.mid_res_buf_row_n_bufferable;
	assign bn_fixed_point_quat_accrc = cfg_if.bn_fixed_point_quat_accrc;
	assign bn_is_a_eq_1 = cfg_if.bn_is_a_eq_1;
	assign bn_is_b_eq_0 = cfg_if.bn_is_b_eq_0;
	assign bn_mem_wen_a = cfg_if.bn_mem_wen_a;
	assign bn_mem_addr_a = cfg_if.bn_mem_addr_a;
	assign bn_mem_din_a = cfg_if.bn_mem_din_a;
	
	assign kernal_access_blk_start = kernal_blk_ctrl_if_2.start;
	assign kernal_blk_ctrl_if_2.idle = kernal_access_blk_idle;
	assign kernal_blk_ctrl_if_2.done = kernal_access_blk_done;
	
	assign fmap_access_blk_start = fmap_blk_ctrl_if_2.start;
	assign fmap_blk_ctrl_if_2.idle = fmap_access_blk_idle;
	assign fmap_blk_ctrl_if_2.done = fmap_access_blk_done;
	
	assign fnl_res_trans_blk_start = fnl_res_trans_blk_ctrl_if_2.start;
	assign fnl_res_trans_blk_ctrl_if_2.idle = fnl_res_trans_blk_idle;
	assign fnl_res_trans_blk_ctrl_if_2.done = fnl_res_trans_blk_done;
	
	assign dma0_cmd_axis_if.data[55:0] = m0_dma_cmd_axis_data;
	assign dma0_cmd_axis_if.user[0] = m0_dma_cmd_axis_user;
	assign dma0_cmd_axis_if.last = m0_dma_cmd_axis_last;
	assign dma0_cmd_axis_if.valid = m0_dma_cmd_axis_valid;
	assign m0_dma_cmd_axis_ready = dma0_cmd_axis_if.ready;
	
	assign s0_dma_strm_axis_data = dma0_strm_axis_if.data[STREAM_DATA_WIDTH-1:0];
	assign s0_dma_strm_axis_keep = dma0_strm_axis_if.keep[STREAM_DATA_WIDTH/8-1:0];
	assign s0_dma_strm_axis_last = dma0_strm_axis_if.last;
	assign s0_dma_strm_axis_valid = dma0_strm_axis_if.valid;
	assign dma0_strm_axis_if.ready = s0_dma_strm_axis_ready;
	
	assign dma1_cmd_axis_if.data[55:0] = m1_dma_cmd_axis_data;
	assign dma1_cmd_axis_if.user[0] = m1_dma_cmd_axis_user;
	assign dma1_cmd_axis_if.last = m1_dma_cmd_axis_last;
	assign dma1_cmd_axis_if.valid = m1_dma_cmd_axis_valid;
	assign m1_dma_cmd_axis_ready = dma1_cmd_axis_if.ready;
	
	assign s1_dma_strm_axis_data = dma1_strm_axis_if.data[STREAM_DATA_WIDTH-1:0];
	assign s1_dma_strm_axis_keep = dma1_strm_axis_if.keep[STREAM_DATA_WIDTH/8-1:0];
	assign s1_dma_strm_axis_last = dma1_strm_axis_if.last;
	assign s1_dma_strm_axis_valid = dma1_strm_axis_if.valid;
	assign dma1_strm_axis_if.ready = s1_dma_strm_axis_ready;
	
	assign dma_s2mm_cmd_axis_if.data[55:0] = m_dma_s2mm_cmd_axis_data;
	assign dma_s2mm_cmd_axis_if.user[0] = m_dma_s2mm_cmd_axis_user;
	assign dma_s2mm_cmd_axis_if.valid = m_dma_s2mm_cmd_axis_valid;
	assign m_dma_s2mm_cmd_axis_ready = dma_s2mm_cmd_axis_if.ready;
	
	assign final_res_axis_if.data[BN_ACT_PRL_N*32-1:0] = dut.conv_cal_sub_system_u.m_axis_bn_act_data;
	assign final_res_axis_if.keep[BN_ACT_PRL_N*4-1:0] = dut.conv_cal_sub_system_u.m_axis_bn_act_keep;
	assign final_res_axis_if.user[4:0] = dut.conv_cal_sub_system_u.m_axis_bn_act_user;
	assign final_res_axis_if.last = dut.conv_cal_sub_system_u.m_axis_bn_act_last;
	assign final_res_axis_if.valid = dut.conv_cal_sub_system_u.m_axis_bn_act_valid;
	assign final_res_axis_if.ready = dut.conv_cal_sub_system_u.m_axis_bn_act_ready;
	
	assign fmap_blk_ctrl_if.params[211:0] = 
	{
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.kernal_h_dilated,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.kernal_w, // 卷积核高度 = 卷积核宽度
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.kernal_w,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.kernal_dilation_vtc_n,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.kernal_set_n,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.inner_padding_top_bottom,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.external_padding_top,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.ext_i_bottom,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.fmap_chn_n,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.ofmap_h,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.ifmap_size,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.ifmap_w,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.is_16bit_data,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.fmap_baseaddr,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.data_size_foreach_group,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.n_foreach_group,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.is_grp_conv_mode,
		dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.conv_vertical_stride
	};
	assign fmap_blk_ctrl_if.start = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.blk_start;
	assign fmap_blk_ctrl_if.idle = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.blk_idle;
	assign fmap_blk_ctrl_if.done = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.blk_done;
	
	assign kernal_blk_ctrl_if.params[167:0] = 
	{
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.kernal_dilation_vtc_n,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.inner_padding_top_bottom,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.external_padding_top,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.ext_i_bottom,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.conv_vertical_stride,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.max_wgtblk_w,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.cgrpn_foreach_kernal_set,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.group_n,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.n_foreach_group,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.is_grp_conv_mode,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.ofmap_h,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.kernal_shape,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.kernal_num_n,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.kernal_chn_n,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.kernal_wgt_baseaddr,
		dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.is_16bit_wgt
	};
	assign kernal_blk_ctrl_if.start = dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.blk_start;
	assign kernal_blk_ctrl_if.idle = dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.blk_idle;
	assign kernal_blk_ctrl_if.done = dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.blk_done;
	
	assign fnl_res_trans_blk_ctrl_if.start = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.blk_start;
	assign fnl_res_trans_blk_ctrl_if.idle = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.blk_idle;
	assign fnl_res_trans_blk_ctrl_if.done = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.blk_done;
	
	assign fnl_res_trans_blk_ctrl_if.params[120:0] = {
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.n_foreach_group,
		dut.conv_ctrl_sub_system_u.group_n, // 模块fnl_res_trans_req_gen_u里没有group_n
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.is_grp_conv_mode,
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.max_wgtblk_w,
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.kernal_num_n,
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.ofmap_data_type,
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.ofmap_h,
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.ofmap_w,
		dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.ofmap_baseaddr
	};
	
	assign dma_s2mm_cmd_axis_if_2.data[55:0] = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_dma_cmd_axis_data;
	assign dma_s2mm_cmd_axis_if_2.user[24:0] = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_dma_cmd_axis_user;
	assign dma_s2mm_cmd_axis_if_2.last = 1'b1;
	assign dma_s2mm_cmd_axis_if_2.valid = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_dma_cmd_axis_valid;
	assign dma_s2mm_cmd_axis_if_2.ready = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_dma_cmd_axis_ready;
	
	assign sub_row_msg_axis_if.data[15:0] = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_sub_row_msg_axis_data;
	assign sub_row_msg_axis_if.last = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_sub_row_msg_axis_last;
	assign sub_row_msg_axis_if.valid = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_sub_row_msg_axis_valid;
	assign sub_row_msg_axis_if.ready = dut.conv_ctrl_sub_system_u.fnl_res_trans_req_gen_u.m_sub_row_msg_axis_ready;
	
	assign fmap_rd_req_axis_if.data[103:0] = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.m_fm_rd_req_axis_data;
	assign fmap_rd_req_axis_if.last = 1'b1;
	assign fmap_rd_req_axis_if.valid = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.m_fm_rd_req_axis_valid;
	assign fmap_rd_req_axis_if.ready = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.m_fm_rd_req_axis_ready;
	
	assign fm_cake_info_axis_if.data[7:0] = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.m_fm_cake_info_axis_data;
	assign fm_cake_info_axis_if.last = 1'b1;
	assign fm_cake_info_axis_if.valid = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.m_fm_cake_info_axis_valid;
	assign fm_cake_info_axis_if.ready = dut.conv_ctrl_sub_system_u.fmap_sfc_row_access_req_gen_u.m_fm_cake_info_axis_ready;
	
	assign kernal_rd_req_axis_if.data[103:0] = dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.m_kwgtblk_rd_req_axis_data;
	assign kernal_rd_req_axis_if.last = 1'b1;
	assign kernal_rd_req_axis_if.valid = dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.m_kwgtblk_rd_req_axis_valid;
	assign kernal_rd_req_axis_if.ready = dut.conv_ctrl_sub_system_u.kernal_access_req_gen_u.m_kwgtblk_rd_req_axis_ready;
	
	assign fm_fout_axis_if.data[ATOMIC_C*2*8-1:0] = dut.conv_data_hub_u.m_fm_fout_axis_data;
	assign fm_fout_axis_if.last = dut.conv_data_hub_u.m_fm_fout_axis_last;
	assign fm_fout_axis_if.valid = dut.conv_data_hub_u.m_fm_fout_axis_valid;
	assign fm_fout_axis_if.ready = dut.conv_data_hub_u.m_fm_fout_axis_ready;
	
	assign kout_wgtblk_axis_if.data[ATOMIC_C*2*8-1:0] = dut.conv_data_hub_u.m_kout_wgtblk_axis_data;
	assign kout_wgtblk_axis_if.last = dut.conv_data_hub_u.m_kout_wgtblk_axis_last;
	assign kout_wgtblk_axis_if.valid = dut.conv_data_hub_u.m_kout_wgtblk_axis_valid;
	assign kout_wgtblk_axis_if.ready = dut.conv_data_hub_u.m_kout_wgtblk_axis_ready;
	
	genvar mid_res_acmlt_i;
	generate
		for(mid_res_acmlt_i = 0;mid_res_acmlt_i < ATOMIC_K;mid_res_acmlt_i = mid_res_acmlt_i + 1)
		begin:mid_res_acmlt_blk
			assign acmlt_in_if[mid_res_acmlt_i].data[79:0] = 
				{
					dut.conv_cal_sub_system_u.acmlt_in_new_res[mid_res_acmlt_i*48+47:mid_res_acmlt_i*48+40],
					dut.conv_cal_sub_system_u.acmlt_in_new_res[mid_res_acmlt_i*48+39:mid_res_acmlt_i*48+0],
					dut.conv_cal_sub_system_u.acmlt_in_org_mid_res[mid_res_acmlt_i*32+31:mid_res_acmlt_i*32+0]
				};
			assign acmlt_in_if[mid_res_acmlt_i].user[0] = 
				dut.conv_cal_sub_system_u.acmlt_in_first_item;
			assign acmlt_in_if[mid_res_acmlt_i].last = 1'b1;
			assign acmlt_in_if[mid_res_acmlt_i].valid = 
				dut.conv_cal_sub_system_u.acmlt_in_valid[mid_res_acmlt_i];
			assign acmlt_in_if[mid_res_acmlt_i].ready = 1'b1;
			
			initial
			begin
				uvm_config_db #(panda_axis_vif)::set(
					null,
					$sformatf("uvm_test_top.mid_res_acmlt_cal_obsv_env[%0d]", mid_res_acmlt_i),
					"acmlt_in_vif",
					acmlt_in_if[mid_res_acmlt_i]
				);
			end
		end
 	endgenerate
	
	assign dma_s2mm_strm_axis_if.data[FNL_RES_DATA_WIDTH-1:0] = m_axis_fnl_res_data;
	assign dma_s2mm_strm_axis_if.keep[FNL_RES_DATA_WIDTH/8-1:0] = m_axis_fnl_res_keep;
	assign dma_s2mm_strm_axis_if.last = m_axis_fnl_res_last;
	assign dma_s2mm_strm_axis_if.valid = m_axis_fnl_res_valid;
	assign m_axis_fnl_res_ready = dma_s2mm_strm_axis_if.ready;
	
	generic_conv_sim #(
		.MAC_ARRAY_CLK_RATE(MAC_ARRAY_CLK_RATE),
		.BN_ACT_CLK_RATE(BN_ACT_CLK_RATE),
		.ATOMIC_K(ATOMIC_K),
		.ATOMIC_C(ATOMIC_C),
		.BN_ACT_PRL_N(BN_ACT_PRL_N),
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH),
		.FNL_RES_DATA_WIDTH(FNL_RES_DATA_WIDTH),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.MAX_KERNAL_N(MAX_KERNAL_N),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		
		.en_mac_array(en_mac_array),
		.en_packer(en_packer),
		.en_bn_act_proc(en_bn_act_proc),
		
		.calfmt(calfmt),
		.conv_vertical_stride(conv_vertical_stride),
		.conv_horizontal_stride(conv_horizontal_stride),
		.cal_round(cal_round),
		.is_grp_conv_mode(is_grp_conv_mode),
		.group_n(group_n),
		.n_foreach_group(n_foreach_group),
		.data_size_foreach_group(data_size_foreach_group),
		.ifmap_baseaddr(ifmap_baseaddr),
		.ofmap_baseaddr(ofmap_baseaddr),
		.ifmap_w(ifmap_w),
		.ifmap_size(ifmap_size),
		.fmap_chn_n(fmap_chn_n),
		.fmap_ext_i_bottom(fmap_ext_i_bottom),
		.external_padding_left(external_padding_left),
		.external_padding_top(external_padding_top),
		.inner_padding_left_right(inner_padding_left_right),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.kernal_wgt_baseaddr(kernal_wgt_baseaddr),
		.kernal_shape(kernal_shape),
		.kernal_dilation_hzt_n(kernal_dilation_hzt_n),
		.kernal_w_dilated(kernal_w_dilated),
		.kernal_dilation_vtc_n(kernal_dilation_vtc_n),
		.kernal_h_dilated(kernal_h_dilated),
		.kernal_chn_n(kernal_chn_n),
		.cgrpn_foreach_kernal_set(cgrpn_foreach_kernal_set),
		.kernal_num_n(kernal_num_n),
		.kernal_set_n(kernal_set_n),
		.max_wgtblk_w(max_wgtblk_w),
		.fmbufbankn(fmbufbankn),
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		.sfc_n_each_wgtblk(sfc_n_each_wgtblk),
		.kbufgrpn(kbufgrpn),
		.mid_res_item_n_foreach_row(mid_res_item_n_foreach_row),
		.mid_res_buf_row_n_bufferable(mid_res_buf_row_n_bufferable),
		.bn_fixed_point_quat_accrc(bn_fixed_point_quat_accrc),
		.bn_is_a_eq_1(bn_is_a_eq_1),
		.bn_is_b_eq_0(bn_is_b_eq_0),
		
		.bn_mem_wen_a(bn_mem_wen_a),
		.bn_mem_addr_a(bn_mem_addr_a),
		.bn_mem_din_a(bn_mem_din_a),
		
		.kernal_access_blk_start(kernal_access_blk_start),
		.kernal_access_blk_idle(kernal_access_blk_idle),
		.kernal_access_blk_done(kernal_access_blk_done),
		
		.fmap_access_blk_start(fmap_access_blk_start),
		.fmap_access_blk_idle(fmap_access_blk_idle),
		.fmap_access_blk_done(fmap_access_blk_done),
		
		.fnl_res_trans_blk_start(fnl_res_trans_blk_start),
		.fnl_res_trans_blk_idle(fnl_res_trans_blk_idle),
		.fnl_res_trans_blk_done(fnl_res_trans_blk_done),
		
		.m0_dma_cmd_axis_data(m0_dma_cmd_axis_data),
		.m0_dma_cmd_axis_user(m0_dma_cmd_axis_user),
		.m0_dma_cmd_axis_last(m0_dma_cmd_axis_last),
		.m0_dma_cmd_axis_valid(m0_dma_cmd_axis_valid),
		.m0_dma_cmd_axis_ready(m0_dma_cmd_axis_ready),
		
		.s0_dma_strm_axis_data(s0_dma_strm_axis_data),
		.s0_dma_strm_axis_keep(s0_dma_strm_axis_keep),
		.s0_dma_strm_axis_last(s0_dma_strm_axis_last),
		.s0_dma_strm_axis_valid(s0_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.m1_dma_cmd_axis_data(m1_dma_cmd_axis_data),
		.m1_dma_cmd_axis_user(m1_dma_cmd_axis_user),
		.m1_dma_cmd_axis_last(m1_dma_cmd_axis_last),
		.m1_dma_cmd_axis_valid(m1_dma_cmd_axis_valid),
		.m1_dma_cmd_axis_ready(m1_dma_cmd_axis_ready),
		
		.s1_dma_strm_axis_data(s1_dma_strm_axis_data),
		.s1_dma_strm_axis_keep(s1_dma_strm_axis_keep),
		.s1_dma_strm_axis_last(s1_dma_strm_axis_last),
		.s1_dma_strm_axis_valid(s1_dma_strm_axis_valid),
		.s1_dma_strm_axis_ready(s1_dma_strm_axis_ready),
		
		.m_dma_s2mm_cmd_axis_data(m_dma_s2mm_cmd_axis_data),
		.m_dma_s2mm_cmd_axis_user(m_dma_s2mm_cmd_axis_user),
		.m_dma_s2mm_cmd_axis_valid(m_dma_s2mm_cmd_axis_valid),
		.m_dma_s2mm_cmd_axis_ready(m_dma_s2mm_cmd_axis_ready),
		
		.m_axis_fnl_res_data(m_axis_fnl_res_data),
		.m_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.m_axis_fnl_res_user(m_axis_fnl_res_user),
		.m_axis_fnl_res_last(m_axis_fnl_res_last),
		.m_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.m_axis_fnl_res_ready(m_axis_fnl_res_ready)
	);
	
endmodule
