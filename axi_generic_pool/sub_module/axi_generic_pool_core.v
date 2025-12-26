/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-通用池化处理单元(核心)

描述:
包括寄存器配置接口、控制子系统(池化表面行缓存访问控制、(最终结果传输请求生成单元))、
计算子系统(池化表面行适配器、(池化中间结果更新与缓存)、(后乘加处理)、(输出数据舍入单元组))、(数据枢纽)、(最终结果数据收集器)

已将可共享部分(数据枢纽、最终结果传输请求生成单元、中间结果缓存、BN与激活单元、输出数据舍入单元组、最终结果数据收集器)引出

支持最大池化、平均池化
支持(最近邻)上采样
支持(非0常量)填充(由无复制的上采样模式来支持)
支持逐元素常量运算(由后乘加处理来支持)

注意：
后乘加并行数(POST_MAC_PRL_N)必须<=通道并行数(ATOMIC_C)

协议:
AXI-Lite SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/26
********************************************************************/


module axi_generic_pool_core #(
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter integer MAX_POOL_SUPPORTED = 1, // 是否支持最大池化
	parameter integer AVG_POOL_SUPPORTED = 0, // 是否支持平均池化
	parameter integer UP_SAMPLE_SUPPORTED = 1, // 是否支持上采样
	parameter integer POST_MAC_SUPPORTED = 0, // 是否支持后乘加处理
	parameter integer INT8_SUPPORTED = 0, // 是否支持INT8运算数据格式
	parameter integer INT16_SUPPORTED = 0, // 是否支持INT16运算数据格式
	parameter integer FP16_SUPPORTED = 1, // 是否支持FP16运算数据格式
	parameter integer EXT_PADDING_SUPPORTED = 1, // 是否支持外填充
	parameter integer NON_ZERO_CONST_PADDING_SUPPORTED = 0, // 是否支持非0常量填充模式
	parameter integer EN_PERF_MON = 1, // 是否支持性能监测
	parameter integer KEEP_FP32_OUT = 0, // 是否保持FP32输出
	parameter integer ATOMIC_C = 8, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer POST_MAC_PRL_N = 1, // 后乘加并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 8, // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 中间结果缓存MEM深度(16 | ...)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 使能信号
	output wire en_accelerator, // 使能加速器
	
	// 寄存器配置接口(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_araddr,
    input wire s_axi_lite_arvalid,
    output wire s_axi_lite_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_awaddr,
    input wire s_axi_lite_awvalid,
    output wire s_axi_lite_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_bvalid,
    input wire s_axi_lite_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_rdata,
    output wire[1:0] s_axi_lite_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_rvalid,
    input wire s_axi_lite_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_wdata,
    input wire s_axi_lite_wvalid,
    output wire s_axi_lite_wready,
	
	// 传输字节数监测
	// [MM2S通道]
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s_dma_strm_axis_keep,
	input wire s_dma_strm_axis_valid,
	input wire s_dma_strm_axis_ready,
	// [S2MM通道]
	input wire[S2MM_STREAM_DATA_WIDTH/8-1:0] s_axis_fnl_res_keep,
	input wire s_axis_fnl_res_valid,
	input wire s_axis_fnl_res_ready,
	
	// DMA命令完成指示
	input wire mm2s_cmd_done, // MM2S通道命令完成(指示)
	input wire s2mm_cmd_done, // S2MM通道命令完成(指示)
	
	// (共享)数据枢纽
	// [运行时参数]
	output wire[3:0] data_hub_fmbufcoln, // 每个表面行的表面个数类型
	output wire[9:0] data_hub_fmbufrown, // 可缓存的表面行数 - 1
	output wire data_hub_fmrow_random_rd_mode, // 是否处于表面行随机读取模式
	output wire data_hub_grp_conv_buf_mode, // 是否处于组卷积缓存模式
	output wire[7:0] data_hub_fmbufbankn, // 分配给特征图缓存的Bank数
	// [特征图表面行读请求(AXIS主机)]
	output wire[103:0] m_fm_rd_req_axis_data,
	output wire m_fm_rd_req_axis_valid,
	input wire m_fm_rd_req_axis_ready,
	// 特征图表面行随机读取(AXIS主机)
	output wire[15:0] m_fm_random_rd_axis_data, // 表面号
	output wire m_fm_random_rd_axis_last, // 标志本次读请求待读取的最后1个表面
	output wire m_fm_random_rd_axis_valid,
	input wire m_fm_random_rd_axis_ready,
	// [特征图表面行数据(AXIS从机)]
	input wire[ATOMIC_C*2*8-1:0] s_fm_sfc_row_axis_data,
	input wire s_fm_sfc_row_axis_last, // 标志本次读请求的最后1个表面
	input wire s_fm_sfc_row_axis_valid,
	output wire s_fm_sfc_row_axis_ready,
	
	// (共享)最终结果传输请求生成单元
	// [运行时参数]
	output wire[31:0] fnl_res_tr_req_gen_ofmap_baseaddr, // 输出特征图基地址
	output wire[15:0] fnl_res_tr_req_gen_ofmap_w, // 输出特征图宽度 - 1
	output wire[15:0] fnl_res_tr_req_gen_ofmap_h, // 输出特征图高度 - 1
	output wire[1:0] fnl_res_tr_req_gen_ofmap_data_type, // 输出特征图数据大小类型
	output wire[15:0] fnl_res_tr_req_gen_kernal_num_n, // 卷积核核数 - 1
	output wire[5:0] fnl_res_tr_req_gen_max_wgtblk_w, // 权重块最大宽度
	output wire fnl_res_tr_req_gen_is_grp_conv_mode, // 是否处于组卷积模式
	output wire fnl_res_tr_req_gen_en_send_sub_row_msg, // 是否输出子表面行信息
	// [块级控制]
	output wire fnl_res_tr_req_gen_blk_start,
	input wire fnl_res_tr_req_gen_blk_idle,
	input wire fnl_res_tr_req_gen_blk_done,
	
	// (共享)中间结果缓存
	// [运行时参数]
	output wire[1:0] mid_res_buf_calfmt, // 运算数据格式
	output wire[3:0] mid_res_buf_row_n_bufferable_dup, // 可缓存行数 - 1
	output wire[3:0] mid_res_buf_bank_n_foreach_ofmap_row, // 每个输出特征图行所占用的缓存MEM个数
	output wire[3:0] mid_res_buf_max_upd_latency, // 最大的更新时延
	output wire mid_res_buf_en_cal_round_ext, // 是否启用计算轮次拓展功能
	output wire[15:0] mid_res_buf_ofmap_w, // 输出特征图宽度 - 1
	output wire[1:0] mid_res_buf_pool_mode, // 池化模式
	// [性能监测]
	output wire en_upd_grp_run_cnt, // 使能更新单元组运行周期数计数器
	input wire[31:0] upd_grp_run_n, // 更新单元组运行周期数
	// [中间结果(AXIS主机)]
	output wire[ATOMIC_C*48-1:0] m_axis_ext_mid_res_data,
	output wire[ATOMIC_C*6-1:0] m_axis_ext_mid_res_keep,
	output wire[3:0] m_axis_ext_mid_res_user, // {本表面全0(标志), 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	output wire m_axis_ext_mid_res_last, // 本行最后1个中间结果(标志)
	output wire m_axis_ext_mid_res_valid,
	input wire m_axis_ext_mid_res_ready,
	// [最终结果(AXIS从机)]
	input wire[ATOMIC_C*32-1:0] s_axis_ext_fnl_res_data, // ATOMIC_C个最终结果(单精度浮点数或定点数)
	input wire[ATOMIC_C*4-1:0] s_axis_ext_fnl_res_keep,
	input wire s_axis_ext_fnl_res_last, // 本行最后1个最终结果(标志)
	input wire s_axis_ext_fnl_res_valid,
	output wire s_axis_ext_fnl_res_ready,
	
	// (共享)BN与激活单元
	// [使能信号]
	output wire en_bn_act_proc_dup, // 使能处理单元
	// [运行时参数]
	output wire[1:0] bn_act_calfmt, // 运算数据格式
	output wire bn_act_use_bn_unit, // 启用BN单元
	output wire bn_act_use_act_unit, // 启用激活单元
	output wire[4:0] bn_act_bn_fixed_point_quat_accrc, // (操作数A)定点数量化精度
	output wire bn_act_bn_is_a_eq_1, // 参数A的实际值为1(标志)
	output wire bn_act_bn_is_b_eq_0, // 参数B的实际值为0(标志)
	output wire bn_act_is_in_const_mac_mode, // 是否处于常量乘加模式
	output wire[31:0] bn_act_param_a_in_const_mac_mode, // 常量乘加模式下的参数A
	output wire[31:0] bn_act_param_b_in_const_mac_mode, // 常量乘加模式下的参数B
	// [后乘加处理输入(AXIS主机)]
	output wire[ATOMIC_C*32-1:0] m_axis_ext_bn_act_i_data, // 对于ATOMIC_C个最终结果 -> {单精度浮点数或定点数(32位)}
	output wire[ATOMIC_C*4-1:0] m_axis_ext_bn_act_i_keep,
	output wire[4:0] m_axis_ext_bn_act_i_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	output wire m_axis_ext_bn_act_i_last, // 本行最后1个最终结果(标志)
	output wire m_axis_ext_bn_act_i_valid,
	input wire m_axis_ext_bn_act_i_ready,
	// [后乘加处理结果(AXIS从机)]
	input wire[POST_MAC_PRL_N*32-1:0] s_axis_ext_bn_act_o_data, // 对于POST_MAC_PRL_N个最终结果 -> {浮点数或定点数}
	input wire[POST_MAC_PRL_N*4-1:0] s_axis_ext_bn_act_o_keep,
	input wire[4:0] s_axis_ext_bn_act_o_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	input wire s_axis_ext_bn_act_o_last, // 本行最后1个处理结果(标志)
	input wire s_axis_ext_bn_act_o_valid,
	output wire s_axis_ext_bn_act_o_ready,
	
	// (共享)输出数据舍入单元组
	// [运行时参数]
	output wire[1:0] round_calfmt, // 运算数据格式
	output wire[3:0] round_fixed_point_quat_accrc, // 定点数量化精度
	// [待舍入数据(AXIS主机)]
	output wire[ATOMIC_C*32-1:0] m_axis_ext_round_i_data, // ATOMIC_C个定点数或FP32
	output wire[ATOMIC_C*4-1:0] m_axis_ext_round_i_keep,
	output wire[4:0] m_axis_ext_round_i_user,
	output wire m_axis_ext_round_i_last,
	output wire m_axis_ext_round_i_valid,
	input wire m_axis_ext_round_i_ready,
	// [舍入后数据(AXIS从机)]
	input wire[ATOMIC_C*16-1:0] s_axis_ext_round_o_data, // ATOMIC_C个定点数或浮点数
	input wire[ATOMIC_C*2-1:0] s_axis_ext_round_o_keep,
	input wire[4:0] s_axis_ext_round_o_user,
	input wire s_axis_ext_round_o_last,
	input wire s_axis_ext_round_o_valid,
	output wire s_axis_ext_round_o_ready,
	
	// (共享)最终结果数据收集器
	// [待收集的数据流(AXIS主机)]
	output wire[ATOMIC_C*(KEEP_FP32_OUT ? 32:16)-1:0] m_axis_ext_collector_data,
	output wire[ATOMIC_C*(KEEP_FP32_OUT ? 4:2)-1:0] m_axis_ext_collector_keep,
	output wire m_axis_ext_collector_last,
	output wire m_axis_ext_collector_valid,
	input wire m_axis_ext_collector_ready
);
	
	/** 函数 **/
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 常量 **/
	// 池化模式的编码
	localparam POOL_MODE_AVG = 2'b00;
	localparam POOL_MODE_MAX = 2'b01;
	localparam POOL_MODE_UPSP = 2'b10;
	localparam POOL_MODE_NONE = 2'b11;
	// 后乘加处理的运算数据格式的编码
	localparam POST_MAC_CAL_FMT_INT16 = 2'b00;
	localparam POST_MAC_CAL_FMT_INT32 = 2'b01;
	localparam POST_MAC_CAL_FMT_FP32 = 2'b10;
	localparam POST_MAC_CAL_FMT_NONE = 2'b11;
	// 池化的运算数据格式的编码
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 寄存器配置接口 **/
	// 控制信号
	wire en_adapter; // 使能适配器
	wire en_post_mac; // 使能后乘加处理
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
	// [非0常量填充]
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
	// 块级控制
	// [池化表面行缓存访问控制]
	wire sfc_row_access_blk_start;
	wire sfc_row_access_blk_idle;
	wire sfc_row_access_blk_done;
	
	assign en_bn_act_proc_dup = en_post_mac;
	
	reg_if_for_generic_pool #(
		.ACCELERATOR_ID(ACCELERATOR_ID),
		.MAX_POOL_SUPPORTED(MAX_POOL_SUPPORTED ? 1'b1:1'b0),
		.AVG_POOL_SUPPORTED(AVG_POOL_SUPPORTED ? 1'b1:1'b0),
		.UP_SAMPLE_SUPPORTED(UP_SAMPLE_SUPPORTED ? 1'b1:1'b0),
		.POST_MAC_SUPPORTED(POST_MAC_SUPPORTED ? 1'b1:1'b0),
		.INT8_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT16_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP16_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.EXT_PADDING_SUPPORTED(EXT_PADDING_SUPPORTED ? 1'b1:1'b0),
		.NON_ZERO_CONST_PADDING_SUPPORTED(
			(EXT_PADDING_SUPPORTED && NON_ZERO_CONST_PADDING_SUPPORTED) ? 
				1'b1:
				1'b0
		),
		.EN_PERF_MON(EN_PERF_MON ? 1'b1:1'b0),
		.ATOMIC_C(ATOMIC_C),
		.POST_MAC_PRL_N(POST_MAC_PRL_N),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.SIM_DELAY(SIM_DELAY)
	)reg_if_for_generic_pool_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.s_axi_lite_araddr(s_axi_lite_araddr),
		.s_axi_lite_arvalid(s_axi_lite_arvalid),
		.s_axi_lite_arready(s_axi_lite_arready),
		.s_axi_lite_awaddr(s_axi_lite_awaddr),
		.s_axi_lite_awvalid(s_axi_lite_awvalid),
		.s_axi_lite_awready(s_axi_lite_awready),
		.s_axi_lite_bresp(s_axi_lite_bresp),
		.s_axi_lite_bvalid(s_axi_lite_bvalid),
		.s_axi_lite_bready(s_axi_lite_bready),
		.s_axi_lite_rdata(s_axi_lite_rdata),
		.s_axi_lite_rresp(s_axi_lite_rresp),
		.s_axi_lite_rvalid(s_axi_lite_rvalid),
		.s_axi_lite_rready(s_axi_lite_rready),
		.s_axi_lite_wdata(s_axi_lite_wdata),
		.s_axi_lite_wvalid(s_axi_lite_wvalid),
		.s_axi_lite_wready(s_axi_lite_wready),
		
		.en_accelerator(en_accelerator),
		.en_adapter(en_adapter),
		.en_upd_grp_run_cnt(en_upd_grp_run_cnt),
		.en_post_mac(en_post_mac),
		
		.upd_grp_run_n(upd_grp_run_n),
		
		.s_mm2s_strm_axis_keep(s_dma_strm_axis_keep),
		.s_mm2s_strm_axis_valid(s_dma_strm_axis_valid),
		.s_mm2s_strm_axis_ready(s_dma_strm_axis_ready),
		
		.s_s2mm_strm_axis_keep(s_axis_fnl_res_keep),
		.s_s2mm_strm_axis_valid(s_axis_fnl_res_valid),
		.s_s2mm_strm_axis_ready(s_axis_fnl_res_ready),
		
		.mm2s_cmd_done(mm2s_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done),
		
		.sfc_row_access_blk_start(sfc_row_access_blk_start),
		.sfc_row_access_blk_idle(sfc_row_access_blk_idle),
		.sfc_row_access_blk_done(sfc_row_access_blk_done),
		.fnl_res_tr_req_gen_blk_start(fnl_res_tr_req_gen_blk_start),
		.fnl_res_tr_req_gen_blk_idle(fnl_res_tr_req_gen_blk_idle),
		.fnl_res_tr_req_gen_blk_done(fnl_res_tr_req_gen_blk_done),
		
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
		.mid_res_buf_row_n_bufferable(mid_res_buf_row_n_bufferable)
	);
	
	/** 补充运行时参数 **/
	wire[15:0] ofmap_w_for_adapter; // 对适配器来说的"输出特征图宽度 - 1"
	wire[15:0] ofmap_h_for_sfc_row_access; // 对池化表面行缓存访问控制单元来说的"输出特征图高度 - 1"
	wire[3:0] bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的中间结果缓存MEM个数
	wire[1:0] post_mac_calfmt; // 后乘加处理的数据格式
	
	// 提示: 上采样水平复制量(upsample_horizontal_n)恒为1时, 始终为"输出特征图宽度 - 1"(ofmap_w)即可
	assign ofmap_w_for_adapter = 
		(pool_mode == POOL_MODE_UPSP) ? 
			ext_ifmap_w:
			ofmap_w;
	// 提示: 上采样垂直复制量(upsample_vertical_n)恒为1时, 始终为"输出特征图高度 - 1"(ofmap_h)即可
	assign ofmap_h_for_sfc_row_access = 
		(pool_mode == POOL_MODE_UPSP) ? 
			ext_ifmap_h:
			ofmap_h;
	assign bank_n_foreach_ofmap_row = 
		(ofmap_w[15:clogb2(RBUF_DEPTH)] | 4'd0) + 1'b1;
	assign post_mac_calfmt = 
		(calfmt == CAL_FMT_INT8)  ? POST_MAC_CAL_FMT_INT16:
		(calfmt == CAL_FMT_INT16) ? POST_MAC_CAL_FMT_INT32:
		(calfmt == CAL_FMT_FP16)  ? POST_MAC_CAL_FMT_FP32:
		                            POST_MAC_CAL_FMT_NONE;
	
	/** 池化表面行缓存访问控制 **/
	// 池化表面行信息(AXIS主机)
	wire[15:0] m_pool_sfc_row_info_axis_data;
	wire m_pool_sfc_row_info_axis_valid;
	wire m_pool_sfc_row_info_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] shared_mul0_op_a; // 操作数A
	wire[15:0] shared_mul0_op_b; // 操作数B
	wire[3:0] shared_mul0_tid; // 操作ID
	wire shared_mul0_req;
	wire shared_mul0_grant;
	// [计算结果]
	wire[31:0] shared_mul0_res;
	wire[3:0] shared_mul0_oid;
	wire shared_mul0_ovld;
	// (共享)有符号乘法器#1
	// [计算输入]
	wire[17:0] shared_mul1_op_a; // 操作数A
	wire[24:0] shared_mul1_op_b; // 操作数B
	wire[3:0] shared_mul1_tid; // 操作ID
	wire shared_mul1_req;
	wire shared_mul1_grant;
	// [计算结果]
	wire[42:0] shared_mul1_res;
	wire[3:0] shared_mul1_oid;
	wire shared_mul1_ovld;
	// 实际乘法器#0
	reg[17:0] mul0_op_a;
	reg[24:0] mul0_op_b;
	reg[3:0] mul0_tid;
	reg mul0_ce;
	wire[42:0] mul0_res;
	reg[3:0] mul0_oid;
	reg mul0_ovld;
	
	assign shared_mul0_grant = shared_mul0_req;
	assign shared_mul0_res = mul0_res[31:0];
	assign shared_mul0_oid = mul0_oid;
	assign shared_mul0_ovld = mul0_ovld;
	
	assign shared_mul1_grant = (~shared_mul0_req) & shared_mul1_req;
	assign shared_mul1_res = mul0_res;
	assign shared_mul1_oid = mul0_oid;
	assign shared_mul1_ovld = mul0_ovld;
	
	always @(posedge aclk)
	begin
		if(shared_mul0_req | shared_mul1_req)
		begin
			mul0_op_a <= # SIM_DELAY 
				shared_mul0_req ? 
					{2'b00, shared_mul0_op_a}:
					shared_mul1_op_a;
			mul0_op_b <= # SIM_DELAY 
				shared_mul0_req ? 
					{9'd0, shared_mul0_op_b}:
					shared_mul1_op_b;
			mul0_tid <= # SIM_DELAY 
				shared_mul0_req ? 
					shared_mul0_tid:
					shared_mul1_tid;
		end
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{mul0_ovld, mul0_ce} <= 2'b00;
		else
			{mul0_ovld, mul0_ce} <= # SIM_DELAY 
				{
					mul0_ce,
					shared_mul0_req | shared_mul1_req
				};
	end
	
	always @(posedge aclk)
	begin
		if(mul0_ce)
			mul0_oid <= # SIM_DELAY mul0_tid;
	end
	
	pool_sfc_row_buffer_access_ctrl #(
		.ATOMIC_C(ATOMIC_C),
		.SIM_DELAY(SIM_DELAY)
	)pool_sfc_row_buffer_access_ctrl_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.pool_mode(pool_mode),
		.pool_vertical_stride(pool_vertical_stride),
		.pool_window_h(pool_window_h),
		.fmap_baseaddr(ifmap_baseaddr),
		.is_16bit_data(is_16bit_data),
		.ifmap_w(ifmap_w),
		.ifmap_h(ifmap_h),
		.ifmap_size(ifmap_size),
		.fmap_chn_n(fmap_chn_n),
		.external_padding_top(external_padding_top),
		.ofmap_h(ofmap_h_for_sfc_row_access),
		
		.blk_start(sfc_row_access_blk_start),
		.blk_idle(sfc_row_access_blk_idle),
		.blk_done(sfc_row_access_blk_done),
		
		.m_pool_sfc_row_info_axis_data(m_pool_sfc_row_info_axis_data),
		.m_pool_sfc_row_info_axis_valid(m_pool_sfc_row_info_axis_valid),
		.m_pool_sfc_row_info_axis_ready(m_pool_sfc_row_info_axis_ready),
		
		.m_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		
		.mul0_op_a(shared_mul0_op_a),
		.mul0_op_b(shared_mul0_op_b),
		.mul0_tid(shared_mul0_tid),
		.mul0_req(shared_mul0_req),
		.mul0_grant(shared_mul0_grant),
		.mul0_res(shared_mul0_res),
		.mul0_oid(shared_mul0_oid),
		.mul0_ovld(shared_mul0_ovld),
		
		.mul1_op_a(shared_mul1_op_a),
		.mul1_op_b(shared_mul1_op_b),
		.mul1_tid(shared_mul1_tid),
		.mul1_req(shared_mul1_req),
		.mul1_grant(shared_mul1_grant),
		.mul1_res(shared_mul1_res),
		.mul1_oid(shared_mul1_oid),
		.mul1_ovld(shared_mul1_ovld)
	);
	
	/** 池化表面行适配器 **/
	// 池化表面行信息(AXIS从机)
	wire[15:0] s_pool_sfc_row_info_axis_data;
	wire s_pool_sfc_row_info_axis_valid;
	wire s_pool_sfc_row_info_axis_ready;
	// 待转换的特征图表面行数据(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_adapter_fm_axis_data;
	wire s_adapter_fm_axis_last; // 标志本次读请求的最后1个表面
	wire s_adapter_fm_axis_valid;
	wire s_adapter_fm_axis_ready;
	// 转换后的特征图表面行数据(AXIS主机)
	wire[ATOMIC_C*16-1:0] m_adapter_fm_axis_data; // ATOMIC_C个定点数或FP16
	wire[ATOMIC_C*2-1:0] m_adapter_fm_axis_keep;
	wire[2:0] m_adapter_fm_axis_user; // {本表面全0(标志), 初始化池化结果(标志), 最后1组池化表面(标志)}
	wire m_adapter_fm_axis_last; // 本行最后1个池化表面(标志)
	wire m_adapter_fm_axis_valid;
	wire m_adapter_fm_axis_ready;
	
	assign s_pool_sfc_row_info_axis_data = m_pool_sfc_row_info_axis_data;
	assign s_pool_sfc_row_info_axis_valid = m_pool_sfc_row_info_axis_valid;
	assign m_pool_sfc_row_info_axis_ready = s_pool_sfc_row_info_axis_ready;
	
	assign s_adapter_fm_axis_data = s_fm_sfc_row_axis_data;
	assign s_adapter_fm_axis_last = s_fm_sfc_row_axis_last;
	assign s_adapter_fm_axis_valid = s_fm_sfc_row_axis_valid;
	assign s_fm_sfc_row_axis_ready = s_adapter_fm_axis_ready;
	
	pool_sfc_row_adapter #(
		.ATOMIC_C(ATOMIC_C),
		.SIM_DELAY(SIM_DELAY)
	)pool_sfc_row_adapter_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.en_adapter(en_adapter),
		
		.pool_mode(pool_mode),
		.pool_horizontal_stride(pool_horizontal_stride),
		.pool_window_w(pool_window_w),
		.ifmap_w(ifmap_w),
		.external_padding_left(external_padding_left),
		.ofmap_w(ofmap_w_for_adapter),
		.upsample_horizontal_n(upsample_horizontal_n),
		.upsample_vertical_n(upsample_vertical_n),
		.non_zero_const_padding_mode(non_zero_const_padding_mode),
		.const_to_fill(const_to_fill),
		
		.s_pool_sfc_row_info_axis_data(s_pool_sfc_row_info_axis_data),
		.s_pool_sfc_row_info_axis_valid(s_pool_sfc_row_info_axis_valid),
		.s_pool_sfc_row_info_axis_ready(s_pool_sfc_row_info_axis_ready),
		
		.m_fm_random_rd_axis_data(m_fm_random_rd_axis_data),
		.m_fm_random_rd_axis_last(m_fm_random_rd_axis_last),
		.m_fm_random_rd_axis_valid(m_fm_random_rd_axis_valid),
		.m_fm_random_rd_axis_ready(m_fm_random_rd_axis_ready),
		
		.s_adapter_fm_axis_data(s_adapter_fm_axis_data),
		.s_adapter_fm_axis_last(s_adapter_fm_axis_last),
		.s_adapter_fm_axis_valid(s_adapter_fm_axis_valid),
		.s_adapter_fm_axis_ready(s_adapter_fm_axis_ready),
		
		.m_adapter_fm_axis_data(m_adapter_fm_axis_data),
		.m_adapter_fm_axis_keep(m_adapter_fm_axis_keep),
		.m_adapter_fm_axis_user(m_adapter_fm_axis_user),
		.m_adapter_fm_axis_last(m_adapter_fm_axis_last),
		.m_adapter_fm_axis_valid(m_adapter_fm_axis_valid),
		.m_adapter_fm_axis_ready(m_adapter_fm_axis_ready)
	);
	
	/** (外部)池化中间结果更新与缓存 **/
	assign m_axis_ext_mid_res_user = {m_adapter_fm_axis_user[2], 1'b1, m_adapter_fm_axis_user[1:0]};
	assign m_axis_ext_mid_res_last = m_adapter_fm_axis_last;
	assign m_axis_ext_mid_res_valid = m_adapter_fm_axis_valid;
	assign m_adapter_fm_axis_ready = m_axis_ext_mid_res_ready;
	
	genvar mid_res_i;
	generate
		for(mid_res_i = 0;mid_res_i < ATOMIC_C;mid_res_i = mid_res_i + 1)
		begin:mid_res_blk
			assign m_axis_ext_mid_res_data[(mid_res_i+1)*48-1:mid_res_i*48] = 
				{32'd0, m_adapter_fm_axis_data[(mid_res_i+1)*16-1:mid_res_i*16]};
			assign m_axis_ext_mid_res_keep[(mid_res_i+1)*6-1:mid_res_i*6] = 
				{6{m_adapter_fm_axis_keep[mid_res_i*2]}};
		end
	endgenerate
	
	/** (外部)后乘加处理 **/
	/**
	使能后乘加处理   -> (中间结果缓存)池化结果输出
	不使能后乘加处理 -> 无效
	**/
	assign m_axis_ext_bn_act_i_data = s_axis_ext_fnl_res_data;
	assign m_axis_ext_bn_act_i_keep = s_axis_ext_fnl_res_keep;
	assign m_axis_ext_bn_act_i_user = 5'dx;
	assign m_axis_ext_bn_act_i_last = s_axis_ext_fnl_res_last;
	assign m_axis_ext_bn_act_i_valid = en_post_mac & s_axis_ext_fnl_res_valid;
	
	/** (外部)输出数据舍入单元组 **/
	// [舍入单元组输入]
	wire[ATOMIC_C*32-1:0] s_axis_round_data; // ATOMIC_C个定点数或FP32
	wire[ATOMIC_C*4-1:0] s_axis_round_keep;
	wire s_axis_round_last; // 本行最后1个池化结果(标志)
	wire s_axis_round_valid;
	wire s_axis_round_ready;
	// [舍入单元组输出]
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 32:16)-1:0] m_axis_round_data; // ATOMIC_C个定点数或浮点数
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 4:2)-1:0] m_axis_round_keep;
	wire m_axis_round_last; // 本行最后1个池化结果(标志)
	wire m_axis_round_valid;
	wire m_axis_round_ready;
	
	/**
	使能后乘加处理   -> 后乘加处理输入
	不使能后乘加处理 -> 舍入单元组输入
	**/
	assign s_axis_ext_fnl_res_ready = 
		en_post_mac ? 
			m_axis_ext_bn_act_i_ready:
			s_axis_round_ready;
	
	/**
	使能后乘加处理   -> 舍入单元组输入
	不使能后乘加处理 -> 忽略
	**/
	assign s_axis_ext_bn_act_o_ready = 
		(~en_post_mac) | s_axis_round_ready;
	
	/**
	使能后乘加处理   -> 经过后乘加处理的结果
	不使能后乘加处理 -> (中间结果缓存)池化结果输出
	**/
	assign s_axis_round_data = 
		en_post_mac ? 
			(s_axis_ext_bn_act_o_data | {(ATOMIC_C*32){1'b0}}):
			s_axis_ext_fnl_res_data;
	assign s_axis_round_keep = 
		en_post_mac ? 
			(s_axis_ext_bn_act_o_keep | {(ATOMIC_C*4){1'b0}}):
			s_axis_ext_fnl_res_keep;
	assign s_axis_round_last = 
		en_post_mac ? 
			s_axis_ext_bn_act_o_last:
			s_axis_ext_fnl_res_last;
	assign s_axis_round_valid = 
		en_post_mac ? 
			s_axis_ext_bn_act_o_valid:
			s_axis_ext_fnl_res_valid;
	
	generate
		if(KEEP_FP32_OUT == 0)
		begin
			assign m_axis_ext_round_i_data = s_axis_round_data;
			assign m_axis_ext_round_i_keep = s_axis_round_keep;
			assign m_axis_ext_round_i_user = 5'dx;
			assign m_axis_ext_round_i_last = s_axis_round_last;
			assign m_axis_ext_round_i_valid = s_axis_round_valid;
			assign s_axis_round_ready = m_axis_ext_round_i_ready;
			
			assign m_axis_round_data = s_axis_ext_round_o_data;
			assign m_axis_round_keep = s_axis_ext_round_o_keep;
			assign m_axis_round_last = s_axis_ext_round_o_last;
			assign m_axis_round_valid = s_axis_ext_round_o_valid;
			assign s_axis_ext_round_o_ready = m_axis_round_ready;
		end
		else
		begin
			assign m_axis_ext_round_i_data = {(ATOMIC_C*32){1'bx}};
			assign m_axis_ext_round_i_keep = {(ATOMIC_C*4){1'bx}};
			assign m_axis_ext_round_i_user = 5'dx;
			assign m_axis_ext_round_i_last = 1'bx;
			assign m_axis_ext_round_i_valid = 1'b0;
			
			assign s_axis_ext_round_o_ready = 1'b1;
			
			assign m_axis_round_data = s_axis_round_data;
			assign m_axis_round_keep = s_axis_round_keep;
			assign m_axis_round_last = s_axis_round_last;
			assign m_axis_round_valid = s_axis_round_valid;
			assign s_axis_round_ready = m_axis_round_ready;
		end
	endgenerate
	
	/** (外部)最终结果数据收集器 **/
	assign m_axis_ext_collector_data = m_axis_round_data;
	assign m_axis_ext_collector_keep = m_axis_round_keep;
	assign m_axis_ext_collector_last = m_axis_round_last;
	assign m_axis_ext_collector_valid = m_axis_round_valid;
	assign m_axis_round_ready = m_axis_ext_collector_ready;
	
	/** 乘法器 **/
	signed_mul #(
		.op_a_width(18),
		.op_b_width(25),
		.output_width(43),
		.en_in_reg("false"),
		.en_out_reg("false"),
		.simulation_delay(SIM_DELAY)
	)mul_s18_s25_u0(
		.clk(aclk),
		
		.ce_in_reg(1'b0),
		.ce_mul(mul0_ce),
		.ce_out_reg(1'b0),
		
		.op_a(mul0_op_a),
		.op_b(mul0_op_b),
		
		.res(mul0_res)
	);
	
	/** 输出的运行时参数 **/
	assign data_hub_fmbufcoln = fmbufcoln;
	assign data_hub_fmbufrown = fmbufrown;
	assign data_hub_fmrow_random_rd_mode = 1'b1;
	assign data_hub_grp_conv_buf_mode = 1'b0;
	assign data_hub_fmbufbankn = CBUF_BANK_N;
	
	assign fnl_res_tr_req_gen_ofmap_baseaddr = ofmap_baseaddr;
	assign fnl_res_tr_req_gen_ofmap_w = ofmap_w;
	assign fnl_res_tr_req_gen_ofmap_h = ofmap_h;
	assign fnl_res_tr_req_gen_ofmap_data_type = ofmap_data_type;
	assign fnl_res_tr_req_gen_kernal_num_n = fmap_chn_n;
	assign fnl_res_tr_req_gen_max_wgtblk_w = ATOMIC_C;
	assign fnl_res_tr_req_gen_is_grp_conv_mode = 1'b0;
	assign fnl_res_tr_req_gen_en_send_sub_row_msg = 1'b0;
	
	assign mid_res_buf_calfmt = calfmt;
	assign mid_res_buf_row_n_bufferable_dup = mid_res_buf_row_n_bufferable;
	assign mid_res_buf_bank_n_foreach_ofmap_row = bank_n_foreach_ofmap_row;
	assign mid_res_buf_max_upd_latency = 2 + 6;
	assign mid_res_buf_en_cal_round_ext = 1'b0;
	assign mid_res_buf_ofmap_w = ofmap_w;
	assign mid_res_buf_pool_mode = pool_mode;
	
	assign bn_act_calfmt = post_mac_calfmt;
	assign bn_act_use_bn_unit = 1'b1;
	assign bn_act_use_act_unit = 1'b0;
	assign bn_act_bn_fixed_point_quat_accrc = post_mac_fixed_point_quat_accrc;
	assign bn_act_bn_is_a_eq_1 = post_mac_is_a_eq_1;
	assign bn_act_bn_is_b_eq_0 = post_mac_is_b_eq_0;
	assign bn_act_is_in_const_mac_mode = 1'b1;
	assign bn_act_param_a_in_const_mac_mode = post_mac_param_a;
	assign bn_act_param_b_in_const_mac_mode = post_mac_param_b;
	
	assign round_calfmt = calfmt;
	assign round_fixed_point_quat_accrc = 4'dx; // 警告: 运行时参数需要给出!!!
	
endmodule
