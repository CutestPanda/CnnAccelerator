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
本模块: AXI-通用池化处理单元(顶层模块)

描述:
包括寄存器配置接口、控制子系统(池化表面行缓存访问控制、最终结果传输请求生成单元)、
计算子系统(池化表面行适配器、池化中间结果更新与缓存、后乘加处理、输出数据舍入单元组)、数据枢纽、最终结果数据收集器

支持最大池化、平均池化
支持(最近邻)上采样
支持(非0常量)填充(由无复制的上采样模式来支持)
支持逐元素常量运算(由后乘加处理来支持)

注意：
需要外接1个DMA(MM2S)通道和1个DMA(S2MM)通道

可将SRAM和乘法器的接口引出, 在SOC层面再连接, 以实现SRAM和乘法器的共享

后乘加并行数(POST_MAC_PRL_N)必须<=通道并行数(ATOMIC_C)

协议:
AXI-Lite SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/26
********************************************************************/


module axi_generic_pool #(
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
	parameter integer PHY_BUF_USE_TRUE_DUAL_PORT_SRAM = 0, // 物理缓存是否使用真双口RAM
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
	
	// S2MM方向DMA命令(AXIS主机)
	output wire[55:0] m_dma_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_s2mm_cmd_axis_user, // 固定(1'b1)/递增(1'b0)传输(1bit)
	output wire m_dma_s2mm_cmd_axis_valid,
	input wire m_dma_s2mm_cmd_axis_ready,
	// 最终结果数据流(AXIS主机)
	output wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_fnl_res_data,
	output wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep,
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready,
	
	// DMA(MM2S方向)命令流(AXIS主机)
	output wire[55:0] m_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m_dma_cmd_axis_last, // 帧尾标志
	output wire m_dma_cmd_axis_valid,
	input wire m_dma_cmd_axis_ready,
	// DMA(MM2S方向)数据流(AXIS从机)
	input wire[MM2S_STREAM_DATA_WIDTH-1:0] s_dma_strm_axis_data,
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s_dma_strm_axis_keep,
	input wire s_dma_strm_axis_last,
	input wire s_dma_strm_axis_valid,
	output wire s_dma_strm_axis_ready,
	
	// DMA命令完成指示
	input wire mm2s_cmd_done, // MM2S通道命令完成(指示)
	input wire s2mm_cmd_done // S2MM通道命令完成(指示)
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
	
	/** 内部参数 **/
	// 特征图缓存的缓存行号的位宽
	localparam integer LG_FMBUF_BUFFER_RID_WIDTH = clogb2(MAX_FMBUF_ROWN);
	// 后乘加处理的乘法器位宽
	localparam integer POST_MAC_MUL_OP_WIDTH = INT8_SUPPORTED ? 4*18:(INT16_SUPPORTED ? 32:25);
	localparam integer POST_MAC_MUL_CE_WIDTH = INT8_SUPPORTED ? 4:3;
	localparam integer POST_MAC_MUL_RES_WIDTH = INT8_SUPPORTED ? 4*36:(INT16_SUPPORTED ? 64:50);
	// 后乘加处理结果fifo的位宽
	localparam integer POST_MAC_PROC_RES_FIFO_WIDTH = POST_MAC_PRL_N*32+POST_MAC_PRL_N+1+5;
	
	/** AXI-通用池化处理单元(核心) **/
	// (共享)数据枢纽
	// [运行时参数]
	wire[3:0] data_hub_fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] data_hub_fmbufrown; // 可缓存的表面行数 - 1
	wire data_hub_fmrow_random_rd_mode; // 是否处于表面行随机读取模式
	wire data_hub_grp_conv_buf_mode; // 是否处于组卷积缓存模式
	wire[7:0] data_hub_fmbufbankn; // 分配给特征图缓存的Bank数
	// [特征图表面行读请求(AXIS主机)]
	wire[103:0] m_fm_rd_req_axis_data;
	wire m_fm_rd_req_axis_valid;
	wire m_fm_rd_req_axis_ready;
	// 特征图表面行随机读取(AXIS主机)
	wire[15:0] m_fm_random_rd_axis_data; // 表面号
	wire m_fm_random_rd_axis_last; // 标志本次读请求待读取的最后1个表面
	wire m_fm_random_rd_axis_valid;
	wire m_fm_random_rd_axis_ready;
	// [特征图表面行数据(AXIS从机)]
	wire[ATOMIC_C*2*8-1:0] s_fm_sfc_row_axis_data;
	wire s_fm_sfc_row_axis_last; // 标志本次读请求的最后1个表面
	wire s_fm_sfc_row_axis_valid;
	wire s_fm_sfc_row_axis_ready;
	// (共享)最终结果传输请求生成单元
	// [运行时参数]
	wire[31:0] fnl_res_tr_req_gen_ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] fnl_res_tr_req_gen_ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] fnl_res_tr_req_gen_ofmap_h; // 输出特征图高度 - 1
	wire[1:0] fnl_res_tr_req_gen_ofmap_data_type; // 输出特征图数据大小类型
	wire[15:0] fnl_res_tr_req_gen_kernal_num_n; // 卷积核核数 - 1
	wire[5:0] fnl_res_tr_req_gen_max_wgtblk_w; // 权重块最大宽度
	wire fnl_res_tr_req_gen_is_grp_conv_mode; // 是否处于组卷积模式
	wire fnl_res_tr_req_gen_en_send_sub_row_msg; // 是否输出子表面行信息
	// [块级控制]
	wire fnl_res_tr_req_gen_blk_start;
	wire fnl_res_tr_req_gen_blk_idle;
	wire fnl_res_tr_req_gen_blk_done;
	// (共享)中间结果缓存
	// [运行时参数]
	wire[1:0] mid_res_buf_calfmt; // 运算数据格式
	wire[3:0] mid_res_buf_row_n_bufferable_dup; // 可缓存行数 - 1
	wire[3:0] mid_res_buf_bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的缓存MEM个数
	wire[3:0] mid_res_buf_max_upd_latency; // 最大的更新时延
	wire mid_res_buf_en_cal_round_ext; // 是否启用计算轮次拓展功能
	wire[15:0] mid_res_buf_ofmap_w; // 输出特征图宽度 - 1
	wire[1:0] mid_res_buf_pool_mode; // 池化模式
	// [性能监测]
	wire en_upd_grp_run_cnt; // 使能更新单元组运行周期数计数器
	wire[31:0] upd_grp_run_n; // 更新单元组运行周期数
	// [中间结果(AXIS主机)]
	wire[ATOMIC_C*48-1:0] m_axis_ext_mid_res_data;
	wire[ATOMIC_C*6-1:0] m_axis_ext_mid_res_keep;
	wire[3:0] m_axis_ext_mid_res_user; // {本表面全0(标志), 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_ext_mid_res_last; // 本行最后1个中间结果(标志)
	wire m_axis_ext_mid_res_valid;
	wire m_axis_ext_mid_res_ready;
	// [最终结果(AXIS从机)]
	wire[ATOMIC_C*32-1:0] s_axis_ext_fnl_res_data; // ATOMIC_C个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_C*4-1:0] s_axis_ext_fnl_res_keep;
	wire s_axis_ext_fnl_res_last; // 本行最后1个最终结果(标志)
	wire s_axis_ext_fnl_res_valid;
	wire s_axis_ext_fnl_res_ready;
	// (共享)BN与激活单元
	// [使能信号]
	wire en_bn_act_proc_dup; // 使能处理单元
	// [运行时参数]
	wire[1:0] bn_act_calfmt; // 运算数据格式
	wire bn_act_use_bn_unit; // 启用BN单元
	wire bn_act_use_act_unit; // 启用激活单元
	wire[4:0] bn_act_bn_fixed_point_quat_accrc; // (操作数A)定点数量化精度
	wire bn_act_bn_is_a_eq_1; // 参数A的实际值为1(标志)
	wire bn_act_bn_is_b_eq_0; // 参数B的实际值为0(标志)
	wire bn_act_is_in_const_mac_mode; // 是否处于常量乘加模式
	wire[31:0] bn_act_param_a_in_const_mac_mode; // 常量乘加模式下的参数A
	wire[31:0] bn_act_param_b_in_const_mac_mode; // 常量乘加模式下的参数B
	// [后乘加处理输入(AXIS主机)]
	wire[ATOMIC_C*32-1:0] m_axis_ext_bn_act_i_data; // 对于ATOMIC_C个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[ATOMIC_C*4-1:0] m_axis_ext_bn_act_i_keep;
	wire[4:0] m_axis_ext_bn_act_i_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_ext_bn_act_i_last; // 本行最后1个最终结果(标志)
	wire m_axis_ext_bn_act_i_valid;
	wire m_axis_ext_bn_act_i_ready;
	// [后乘加处理结果(AXIS从机)]
	wire[POST_MAC_PRL_N*32-1:0] s_axis_ext_bn_act_o_data; // 对于POST_MAC_PRL_N个最终结果 -> {浮点数或定点数}
	wire[POST_MAC_PRL_N*4-1:0] s_axis_ext_bn_act_o_keep;
	wire[4:0] s_axis_ext_bn_act_o_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_ext_bn_act_o_last; // 本行最后1个处理结果(标志)
	wire s_axis_ext_bn_act_o_valid;
	wire s_axis_ext_bn_act_o_ready;
	// (共享)输出数据舍入单元组
	// [运行时参数]
	wire[1:0] round_calfmt; // 运算数据格式
	wire[3:0] round_fixed_point_quat_accrc; // 定点数量化精度
	// [待舍入数据(AXIS主机)]
	wire[ATOMIC_C*32-1:0] m_axis_ext_round_i_data; // ATOMIC_C个定点数或FP32
	wire[ATOMIC_C*4-1:0] m_axis_ext_round_i_keep;
	wire[4:0] m_axis_ext_round_i_user;
	wire m_axis_ext_round_i_last;
	wire m_axis_ext_round_i_valid;
	wire m_axis_ext_round_i_ready;
	// [舍入后数据(AXIS从机)]
	wire[ATOMIC_C*16-1:0] s_axis_ext_round_o_data; // ATOMIC_C个定点数或浮点数
	wire[ATOMIC_C*2-1:0] s_axis_ext_round_o_keep;
	wire[4:0] s_axis_ext_round_o_user;
	wire s_axis_ext_round_o_last;
	wire s_axis_ext_round_o_valid;
	wire s_axis_ext_round_o_ready;
	// (共享)最终结果数据收集器
	// [待收集的数据流(AXIS主机)]
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 32:16)-1:0] m_axis_ext_collector_data;
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 4:2)-1:0] m_axis_ext_collector_keep;
	wire m_axis_ext_collector_last;
	wire m_axis_ext_collector_valid;
	wire m_axis_ext_collector_ready;
	
	axi_generic_pool_core #(
		.ACCELERATOR_ID(ACCELERATOR_ID),
		.MAX_POOL_SUPPORTED(MAX_POOL_SUPPORTED),
		.AVG_POOL_SUPPORTED(AVG_POOL_SUPPORTED),
		.UP_SAMPLE_SUPPORTED(UP_SAMPLE_SUPPORTED),
		.POST_MAC_SUPPORTED(POST_MAC_SUPPORTED),
		.INT8_SUPPORTED(INT8_SUPPORTED),
		.INT16_SUPPORTED(INT16_SUPPORTED),
		.FP16_SUPPORTED(FP16_SUPPORTED),
		.EXT_PADDING_SUPPORTED(EXT_PADDING_SUPPORTED),
		.NON_ZERO_CONST_PADDING_SUPPORTED(NON_ZERO_CONST_PADDING_SUPPORTED),
		.EN_PERF_MON(EN_PERF_MON),
		.KEEP_FP32_OUT(KEEP_FP32_OUT),
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
	)axi_generic_pool_core_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
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
		
		.s_dma_strm_axis_keep(s_dma_strm_axis_keep),
		.s_dma_strm_axis_valid(s_dma_strm_axis_valid),
		.s_dma_strm_axis_ready(s_dma_strm_axis_ready),
		
		.s_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.s_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.s_axis_fnl_res_ready(m_axis_fnl_res_ready),
		
		.mm2s_cmd_done(mm2s_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done),
		
		.data_hub_fmbufcoln(data_hub_fmbufcoln),
		.data_hub_fmbufrown(data_hub_fmbufrown),
		.data_hub_fmrow_random_rd_mode(data_hub_fmrow_random_rd_mode),
		.data_hub_grp_conv_buf_mode(data_hub_grp_conv_buf_mode),
		.data_hub_fmbufbankn(data_hub_fmbufbankn),
		.m_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		.m_fm_random_rd_axis_data(m_fm_random_rd_axis_data),
		.m_fm_random_rd_axis_last(m_fm_random_rd_axis_last),
		.m_fm_random_rd_axis_valid(m_fm_random_rd_axis_valid),
		.m_fm_random_rd_axis_ready(m_fm_random_rd_axis_ready),
		.s_fm_sfc_row_axis_data(s_fm_sfc_row_axis_data),
		.s_fm_sfc_row_axis_last(s_fm_sfc_row_axis_last),
		.s_fm_sfc_row_axis_valid(s_fm_sfc_row_axis_valid),
		.s_fm_sfc_row_axis_ready(s_fm_sfc_row_axis_ready),
		
		.fnl_res_tr_req_gen_ofmap_baseaddr(fnl_res_tr_req_gen_ofmap_baseaddr),
		.fnl_res_tr_req_gen_ofmap_w(fnl_res_tr_req_gen_ofmap_w),
		.fnl_res_tr_req_gen_ofmap_h(fnl_res_tr_req_gen_ofmap_h),
		.fnl_res_tr_req_gen_ofmap_data_type(fnl_res_tr_req_gen_ofmap_data_type),
		.fnl_res_tr_req_gen_kernal_num_n(fnl_res_tr_req_gen_kernal_num_n),
		.fnl_res_tr_req_gen_max_wgtblk_w(fnl_res_tr_req_gen_max_wgtblk_w),
		.fnl_res_tr_req_gen_is_grp_conv_mode(fnl_res_tr_req_gen_is_grp_conv_mode),
		.fnl_res_tr_req_gen_en_send_sub_row_msg(fnl_res_tr_req_gen_en_send_sub_row_msg),
		.fnl_res_tr_req_gen_blk_start(fnl_res_tr_req_gen_blk_start),
		.fnl_res_tr_req_gen_blk_idle(fnl_res_tr_req_gen_blk_idle),
		.fnl_res_tr_req_gen_blk_done(fnl_res_tr_req_gen_blk_done),
		
		.mid_res_buf_calfmt(mid_res_buf_calfmt),
		.mid_res_buf_row_n_bufferable_dup(mid_res_buf_row_n_bufferable_dup),
		.mid_res_buf_bank_n_foreach_ofmap_row(mid_res_buf_bank_n_foreach_ofmap_row),
		.mid_res_buf_max_upd_latency(mid_res_buf_max_upd_latency),
		.mid_res_buf_en_cal_round_ext(mid_res_buf_en_cal_round_ext),
		.mid_res_buf_ofmap_w(mid_res_buf_ofmap_w),
		.mid_res_buf_pool_mode(mid_res_buf_pool_mode),
		.en_upd_grp_run_cnt(en_upd_grp_run_cnt),
		.upd_grp_run_n(upd_grp_run_n),
		.m_axis_ext_mid_res_data(m_axis_ext_mid_res_data),
		.m_axis_ext_mid_res_keep(m_axis_ext_mid_res_keep),
		.m_axis_ext_mid_res_user(m_axis_ext_mid_res_user),
		.m_axis_ext_mid_res_last(m_axis_ext_mid_res_last),
		.m_axis_ext_mid_res_valid(m_axis_ext_mid_res_valid),
		.m_axis_ext_mid_res_ready(m_axis_ext_mid_res_ready),
		.s_axis_ext_fnl_res_data(s_axis_ext_fnl_res_data),
		.s_axis_ext_fnl_res_keep(s_axis_ext_fnl_res_keep),
		.s_axis_ext_fnl_res_last(s_axis_ext_fnl_res_last),
		.s_axis_ext_fnl_res_valid(s_axis_ext_fnl_res_valid),
		.s_axis_ext_fnl_res_ready(s_axis_ext_fnl_res_ready),
		
		.en_bn_act_proc_dup(en_bn_act_proc_dup),
		.bn_act_calfmt(bn_act_calfmt),
		.bn_act_use_bn_unit(bn_act_use_bn_unit),
		.bn_act_use_act_unit(bn_act_use_act_unit),
		.bn_act_bn_fixed_point_quat_accrc(bn_act_bn_fixed_point_quat_accrc),
		.bn_act_bn_is_a_eq_1(bn_act_bn_is_a_eq_1),
		.bn_act_bn_is_b_eq_0(bn_act_bn_is_b_eq_0),
		.bn_act_is_in_const_mac_mode(bn_act_is_in_const_mac_mode),
		.bn_act_param_a_in_const_mac_mode(bn_act_param_a_in_const_mac_mode),
		.bn_act_param_b_in_const_mac_mode(bn_act_param_b_in_const_mac_mode),
		.m_axis_ext_bn_act_i_data(m_axis_ext_bn_act_i_data),
		.m_axis_ext_bn_act_i_keep(m_axis_ext_bn_act_i_keep),
		.m_axis_ext_bn_act_i_user(m_axis_ext_bn_act_i_user),
		.m_axis_ext_bn_act_i_last(m_axis_ext_bn_act_i_last),
		.m_axis_ext_bn_act_i_valid(m_axis_ext_bn_act_i_valid),
		.m_axis_ext_bn_act_i_ready(m_axis_ext_bn_act_i_ready),
		.s_axis_ext_bn_act_o_data(s_axis_ext_bn_act_o_data),
		.s_axis_ext_bn_act_o_keep(s_axis_ext_bn_act_o_keep),
		.s_axis_ext_bn_act_o_user(s_axis_ext_bn_act_o_user),
		.s_axis_ext_bn_act_o_last(s_axis_ext_bn_act_o_last),
		.s_axis_ext_bn_act_o_valid(s_axis_ext_bn_act_o_valid),
		.s_axis_ext_bn_act_o_ready(s_axis_ext_bn_act_o_ready),
		
		.round_calfmt(round_calfmt),
		.round_fixed_point_quat_accrc(round_fixed_point_quat_accrc),
		.m_axis_ext_round_i_data(m_axis_ext_round_i_data),
		.m_axis_ext_round_i_keep(m_axis_ext_round_i_keep),
		.m_axis_ext_round_i_user(m_axis_ext_round_i_user),
		.m_axis_ext_round_i_last(m_axis_ext_round_i_last),
		.m_axis_ext_round_i_valid(m_axis_ext_round_i_valid),
		.m_axis_ext_round_i_ready(m_axis_ext_round_i_ready),
		.s_axis_ext_round_o_data(s_axis_ext_round_o_data),
		.s_axis_ext_round_o_keep(s_axis_ext_round_o_keep),
		.s_axis_ext_round_o_user(s_axis_ext_round_o_user),
		.s_axis_ext_round_o_last(s_axis_ext_round_o_last),
		.s_axis_ext_round_o_valid(s_axis_ext_round_o_valid),
		.s_axis_ext_round_o_ready(s_axis_ext_round_o_ready),
		
		.m_axis_ext_collector_data(m_axis_ext_collector_data),
		.m_axis_ext_collector_keep(m_axis_ext_collector_keep),
		.m_axis_ext_collector_last(m_axis_ext_collector_last),
		.m_axis_ext_collector_valid(m_axis_ext_collector_valid),
		.m_axis_ext_collector_ready(m_axis_ext_collector_ready)
	);
	
	/** 池化数据枢纽 **/
	// 实际表面行号映射表MEM主接口
	wire actual_rid_mp_tb_mem_clk;
	wire actual_rid_mp_tb_mem_wen_a;
	wire[11:0] actual_rid_mp_tb_mem_addr_a;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_din_a;
	wire actual_rid_mp_tb_mem_ren_b;
	wire[11:0] actual_rid_mp_tb_mem_addr_b;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_dout_b;
	// 缓存行号映射表MEM主接口
	wire buffer_rid_mp_tb_mem_clk;
	wire buffer_rid_mp_tb_mem_wen_a;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_a;
	wire[11:0] buffer_rid_mp_tb_mem_din_a;
	wire buffer_rid_mp_tb_mem_ren_b;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_b;
	wire[11:0] buffer_rid_mp_tb_mem_dout_b;
	// 物理缓存的MEM主接口
	wire phy_conv_buf_mem_clk_a;
	wire[CBUF_BANK_N-1:0] phy_conv_buf_mem_en_a;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] phy_conv_buf_mem_wen_a;
	wire[CBUF_BANK_N*16-1:0] phy_conv_buf_mem_addr_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_din_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_dout_a;
	wire phy_conv_buf_mem_clk_b;
	wire[CBUF_BANK_N-1:0] phy_conv_buf_mem_en_b;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] phy_conv_buf_mem_wen_b;
	wire[CBUF_BANK_N*16-1:0] phy_conv_buf_mem_addr_b;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_din_b;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_dout_b;
	
	conv_data_hub #(
		.STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.FM_RD_REQ_PRE_ACPT_N(4),
		.KWGTBLK_RD_REQ_PRE_ACPT_N(4),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.LG_FMBUF_BUFFER_RID_WIDTH(LG_FMBUF_BUFFER_RID_WIDTH),
		.EN_REG_SLICE_IN_FM_RD_REQ("true"),
		.EN_REG_SLICE_IN_KWGTBLK_RD_REQ("true"),
		.PHY_BUF_USE_TRUE_DUAL_PORT_SRAM(PHY_BUF_USE_TRUE_DUAL_PORT_SRAM ? "true":"false"),
		.SIM_DELAY(SIM_DELAY)
	)pool_data_hub_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.fmbufcoln(data_hub_fmbufcoln),
		.fmbufrown(data_hub_fmbufrown),
		.fmrow_random_rd_mode(data_hub_fmrow_random_rd_mode),
		.grp_conv_buf_mode(data_hub_grp_conv_buf_mode),
		.kbufgrpsz(3'bxxx),
		.sfc_n_each_wgtblk(3'bxxx),
		.kbufgrpn(8'hxx),
		.fmbufbankn(data_hub_fmbufbankn),
		
		.s_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.s_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.s_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		
		.s_fm_random_rd_axis_data(m_fm_random_rd_axis_data),
		.s_fm_random_rd_axis_last(m_fm_random_rd_axis_last),
		.s_fm_random_rd_axis_valid(m_fm_random_rd_axis_valid),
		.s_fm_random_rd_axis_ready(m_fm_random_rd_axis_ready),
		
		.s_kwgtblk_rd_req_axis_data(104'dx),
		.s_kwgtblk_rd_req_axis_valid(1'b0),
		.s_kwgtblk_rd_req_axis_ready(),
		
		.m_fm_fout_axis_data(s_fm_sfc_row_axis_data),
		.m_fm_fout_axis_last(s_fm_sfc_row_axis_last),
		.m_fm_fout_axis_valid(s_fm_sfc_row_axis_valid),
		.m_fm_fout_axis_ready(s_fm_sfc_row_axis_ready),
		
		.m_kout_wgtblk_axis_data(),
		.m_kout_wgtblk_axis_last(),
		.m_kout_wgtblk_axis_valid(),
		.m_kout_wgtblk_axis_ready(1'b1),
		
		.m0_dma_cmd_axis_data(m_dma_cmd_axis_data),
		.m0_dma_cmd_axis_user(m_dma_cmd_axis_user),
		.m0_dma_cmd_axis_last(m_dma_cmd_axis_last),
		.m0_dma_cmd_axis_valid(m_dma_cmd_axis_valid),
		.m0_dma_cmd_axis_ready(m_dma_cmd_axis_ready),
		
		.s0_dma_strm_axis_data(s_dma_strm_axis_data),
		.s0_dma_strm_axis_keep(s_dma_strm_axis_keep),
		.s0_dma_strm_axis_last(s_dma_strm_axis_last),
		.s0_dma_strm_axis_valid(s_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s_dma_strm_axis_ready),
		
		.m1_dma_cmd_axis_data(),
		.m1_dma_cmd_axis_user(),
		.m1_dma_cmd_axis_last(),
		.m1_dma_cmd_axis_valid(),
		.m1_dma_cmd_axis_ready(1'b1),
		
		.s1_dma_strm_axis_data({MM2S_STREAM_DATA_WIDTH{1'bx}}),
		.s1_dma_strm_axis_keep({(MM2S_STREAM_DATA_WIDTH/8){1'bx}}),
		.s1_dma_strm_axis_last(1'bx),
		.s1_dma_strm_axis_valid(1'b0),
		.s1_dma_strm_axis_ready(),
		
		.actual_rid_mp_tb_mem_clk(actual_rid_mp_tb_mem_clk),
		.actual_rid_mp_tb_mem_wen_a(actual_rid_mp_tb_mem_wen_a),
		.actual_rid_mp_tb_mem_addr_a(actual_rid_mp_tb_mem_addr_a),
		.actual_rid_mp_tb_mem_din_a(actual_rid_mp_tb_mem_din_a),
		.actual_rid_mp_tb_mem_ren_b(actual_rid_mp_tb_mem_ren_b),
		.actual_rid_mp_tb_mem_addr_b(actual_rid_mp_tb_mem_addr_b),
		.actual_rid_mp_tb_mem_dout_b(actual_rid_mp_tb_mem_dout_b),
		
		.buffer_rid_mp_tb_mem_clk(buffer_rid_mp_tb_mem_clk),
		.buffer_rid_mp_tb_mem_wen_a(buffer_rid_mp_tb_mem_wen_a),
		.buffer_rid_mp_tb_mem_addr_a(buffer_rid_mp_tb_mem_addr_a),
		.buffer_rid_mp_tb_mem_din_a(buffer_rid_mp_tb_mem_din_a),
		.buffer_rid_mp_tb_mem_ren_b(buffer_rid_mp_tb_mem_ren_b),
		.buffer_rid_mp_tb_mem_addr_b(buffer_rid_mp_tb_mem_addr_b),
		.buffer_rid_mp_tb_mem_dout_b(buffer_rid_mp_tb_mem_dout_b),
		
		.phy_conv_buf_mem_clk_a(phy_conv_buf_mem_clk_a),
		.phy_conv_buf_mem_en_a(phy_conv_buf_mem_en_a),
		.phy_conv_buf_mem_wen_a(phy_conv_buf_mem_wen_a),
		.phy_conv_buf_mem_addr_a(phy_conv_buf_mem_addr_a),
		.phy_conv_buf_mem_din_a(phy_conv_buf_mem_din_a),
		.phy_conv_buf_mem_dout_a(phy_conv_buf_mem_dout_a),
		.phy_conv_buf_mem_clk_b(phy_conv_buf_mem_clk_b),
		.phy_conv_buf_mem_en_b(phy_conv_buf_mem_en_b),
		.phy_conv_buf_mem_wen_b(phy_conv_buf_mem_wen_b),
		.phy_conv_buf_mem_addr_b(phy_conv_buf_mem_addr_b),
		.phy_conv_buf_mem_din_b(phy_conv_buf_mem_din_b),
		.phy_conv_buf_mem_dout_b(phy_conv_buf_mem_dout_b)
	);
	
	/** 最终结果传输请求生成单元 **/
	// DMA命令(AXIS主机)
	wire[55:0] m_fnl_res_tr_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[24:0] m_fnl_res_tr_dma_cmd_axis_user; // {命令ID(24bit), 固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_fnl_res_tr_dma_cmd_axis_valid;
	wire m_fnl_res_tr_dma_cmd_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] shared_mul2_op_a; // 操作数A
	wire[23:0] shared_mul2_op_b; // 操作数B
	wire[3:0] shared_mul2_tid; // 操作ID
	wire shared_mul2_req;
	wire shared_mul2_grant;
	// [计算结果]
	wire[39:0] shared_mul2_res;
	wire[3:0] shared_mul2_oid;
	wire shared_mul2_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] shared_mul3_op_a; // 操作数A
	wire[23:0] shared_mul3_op_b; // 操作数B
	wire[3:0] shared_mul3_tid; // 操作ID
	wire shared_mul3_req;
	wire shared_mul3_grant;
	// [计算结果]
	wire[39:0] shared_mul3_res;
	wire[3:0] shared_mul3_oid;
	wire shared_mul3_ovld;
	// 实际乘法器#1
	reg[15:0] mul1_op_a;
	reg[23:0] mul1_op_b;
	reg[3:0] mul1_tid;
	reg mul1_ce;
	wire[39:0] mul1_res;
	reg[3:0] mul1_oid;
	reg mul1_ovld;
	
	assign m_dma_s2mm_cmd_axis_data = m_fnl_res_tr_dma_cmd_axis_data;
	assign m_dma_s2mm_cmd_axis_user = m_fnl_res_tr_dma_cmd_axis_user[0];
	assign m_dma_s2mm_cmd_axis_valid = m_fnl_res_tr_dma_cmd_axis_valid;
	assign m_fnl_res_tr_dma_cmd_axis_ready = m_dma_s2mm_cmd_axis_ready;
	
	assign shared_mul2_grant = shared_mul2_req;
	assign shared_mul2_res = mul1_res;
	assign shared_mul2_oid = mul1_oid;
	assign shared_mul2_ovld = mul1_ovld;
	
	assign shared_mul3_grant = (~shared_mul2_req) & shared_mul3_req;
	assign shared_mul3_res = mul1_res;
	assign shared_mul3_oid = mul1_oid;
	assign shared_mul3_ovld = mul1_ovld;
	
	always @(posedge aclk)
	begin
		if(shared_mul2_req | shared_mul3_req)
		begin
			mul1_op_a <= # SIM_DELAY 
				shared_mul2_req ? 
					shared_mul2_op_a:
					shared_mul3_op_a;
			mul1_op_b <= # SIM_DELAY 
				shared_mul2_req ? 
					shared_mul2_op_b:
					shared_mul3_op_b;
			mul1_tid <= # SIM_DELAY 
				shared_mul2_req ? 
					shared_mul2_tid:
					shared_mul3_tid;
		end
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{mul1_ovld, mul1_ce} <= 2'b00;
		else
			{mul1_ovld, mul1_ce} <= # SIM_DELAY 
				{
					mul1_ce,
					shared_mul2_req | shared_mul3_req
				};
	end
	
	always @(posedge aclk)
	begin
		if(mul1_ce)
			mul1_oid <= # SIM_DELAY mul1_tid;
	end
	
	fnl_res_trans_req_gen #(
		.ATOMIC_K(ATOMIC_C),
		.SIM_DELAY(SIM_DELAY)
	)fnl_res_trans_req_gen_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.ofmap_baseaddr(fnl_res_tr_req_gen_ofmap_baseaddr),
		.ofmap_w(fnl_res_tr_req_gen_ofmap_w),
		.ofmap_h(fnl_res_tr_req_gen_ofmap_h),
		.ofmap_data_type(fnl_res_tr_req_gen_ofmap_data_type),
		.kernal_num_n(fnl_res_tr_req_gen_kernal_num_n),
		.max_wgtblk_w(fnl_res_tr_req_gen_max_wgtblk_w),
		.is_grp_conv_mode(fnl_res_tr_req_gen_is_grp_conv_mode),
		.n_foreach_group(16'dx),
		.en_send_sub_row_msg(fnl_res_tr_req_gen_en_send_sub_row_msg),
		
		.blk_start(fnl_res_tr_req_gen_blk_start),
		.blk_idle(fnl_res_tr_req_gen_blk_idle),
		.blk_done(fnl_res_tr_req_gen_blk_done),
		
		.m_sub_row_msg_axis_data(),
		.m_sub_row_msg_axis_last(),
		.m_sub_row_msg_axis_valid(),
		.m_sub_row_msg_axis_ready(1'b1),
		
		.m_dma_cmd_axis_data(m_fnl_res_tr_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m_fnl_res_tr_dma_cmd_axis_user),
		.m_dma_cmd_axis_valid(m_fnl_res_tr_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m_fnl_res_tr_dma_cmd_axis_ready),
		
		.mul0_op_a(shared_mul2_op_a),
		.mul0_op_b(shared_mul2_op_b),
		.mul0_tid(shared_mul2_tid),
		.mul0_req(shared_mul2_req),
		.mul0_grant(shared_mul2_grant),
		.mul0_res(shared_mul2_res),
		.mul0_oid(shared_mul2_oid),
		.mul0_ovld(shared_mul2_ovld),
		
		.mul1_op_a(shared_mul3_op_a),
		.mul1_op_b(shared_mul3_op_b),
		.mul1_tid(shared_mul3_tid),
		.mul1_req(shared_mul3_req),
		.mul1_grant(shared_mul3_grant),
		.mul1_res(shared_mul3_res),
		.mul1_oid(shared_mul3_oid),
		.mul1_ovld(shared_mul3_ovld)
	);
	
	/** 池化中间结果更新与缓存 **/
	// 中间结果缓存MEM主接口
	wire mid_res_mem_clk_a;
	wire[RBUF_BANK_N-1:0] mid_res_mem_wen_a;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_a;
	wire[RBUF_BANK_N*(ATOMIC_C*4*8+ATOMIC_C)-1:0] mid_res_mem_din_a;
	wire mid_res_mem_clk_b;
	wire[RBUF_BANK_N-1:0] mid_res_mem_ren_b;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_b;
	wire[RBUF_BANK_N*(ATOMIC_C*4*8+ATOMIC_C)-1:0] mid_res_mem_dout_b;
	// 池化中间结果更新单元
	// [更新单元组输入]
	wire[ATOMIC_C*48-1:0] pool_upd_i_new_res; // 新结果
	wire[ATOMIC_C*32-1:0] pool_upd_i_org_mid_res; // 原中间结果
	wire[3+ATOMIC_C-1:0] pool_upd_i_info_along[0:ATOMIC_C-1]; // 随路数据
	wire[ATOMIC_C-1:0] pool_upd_i_mask; // 项掩码
	wire pool_upd_i_first_item; // 是否第1项(标志)
	wire pool_upd_i_last_grp; // 是否最后1组(标志)
	wire pool_upd_i_last_res; // 本行最后1个中间结果(标志)
	wire pool_upd_i_is_zero_sfc; // 是否空表面(标志)
	wire[ATOMIC_C-1:0] pool_upd_i_valid; // 输入有效指示
	// [更新单元组输出]
	wire[ATOMIC_C*32-1:0] pool_upd_o_data; // 单精度浮点数或定点数
	wire[3+ATOMIC_C-1:0] pool_upd_o_info_along[0:ATOMIC_C-1]; // 随路数据
	wire[ATOMIC_C-1:0] pool_upd_o_mask; // 输出项掩码
	wire pool_upd_o_last_grp; // 是否最后1组(标志)
	wire pool_upd_o_last_res; // 本行最后1个中间结果(标志)
	wire pool_upd_o_to_upd_mem; // 更新缓存MEM(标志)
	wire[ATOMIC_C-1:0] pool_upd_o_valid; // 输出有效指示
	// [性能监测]
	reg[31:0] upd_grp_run_cnt; // 更新单元组运行周期数(计数器)
	
	assign {pool_upd_o_to_upd_mem, pool_upd_o_last_grp, pool_upd_o_last_res, pool_upd_o_mask} = 
		pool_upd_o_info_along[0];
	
	assign upd_grp_run_n = upd_grp_run_cnt;
	
	// 更新单元组运行周期数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			upd_grp_run_cnt <= 32'd0;
		else if(
			(~en_upd_grp_run_cnt) | pool_upd_o_valid[0]
		)
			upd_grp_run_cnt <= # SIM_DELAY 
				en_upd_grp_run_cnt ? 
					(upd_grp_run_cnt + 1'b1):
					32'd0;
	end
	
	conv_middle_res_acmlt_buf #(
		.ATOMIC_K(ATOMIC_C),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.INFO_ALONG_WIDTH(1),
		.SIM_DELAY(SIM_DELAY)
	)pool_middle_res_buf_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.calfmt(mid_res_buf_calfmt),
		.row_n_bufferable(mid_res_buf_row_n_bufferable_dup),
		.bank_n_foreach_ofmap_row(mid_res_buf_bank_n_foreach_ofmap_row),
		.max_upd_latency(mid_res_buf_max_upd_latency),
		.en_cal_round_ext(mid_res_buf_en_cal_round_ext),
		.ofmap_w(mid_res_buf_ofmap_w),
		
		.s_axis_mid_res_data(m_axis_ext_mid_res_data),
		.s_axis_mid_res_keep(m_axis_ext_mid_res_keep),
		.s_axis_mid_res_user(m_axis_ext_mid_res_user),
		.s_axis_mid_res_last(m_axis_ext_mid_res_last),
		.s_axis_mid_res_valid(m_axis_ext_mid_res_valid),
		.s_axis_mid_res_ready(m_axis_ext_mid_res_ready),
		
		.m_axis_fnl_res_data(s_axis_ext_fnl_res_data),
		.m_axis_fnl_res_keep(s_axis_ext_fnl_res_keep),
		.m_axis_fnl_res_user(),
		.m_axis_fnl_res_last(s_axis_ext_fnl_res_last),
		.m_axis_fnl_res_valid(s_axis_ext_fnl_res_valid),
		.m_axis_fnl_res_ready(s_axis_ext_fnl_res_ready),
		
		.mem_clk_a(mid_res_mem_clk_a),
		.mem_wen_a(mid_res_mem_wen_a),
		.mem_addr_a(mid_res_mem_addr_a),
		.mem_din_a(mid_res_mem_din_a),
		.mem_clk_b(mid_res_mem_clk_b),
		.mem_ren_b(mid_res_mem_ren_b),
		.mem_addr_b(mid_res_mem_addr_b),
		.mem_dout_b(mid_res_mem_dout_b),
		
		.acmlt_in_new_res(pool_upd_i_new_res),
		.acmlt_in_org_mid_res(pool_upd_i_org_mid_res),
		.acmlt_in_mask(pool_upd_i_mask),
		.acmlt_in_first_item(pool_upd_i_first_item),
		.acmlt_in_last_grp(pool_upd_i_last_grp),
		.acmlt_in_last_res(pool_upd_i_last_res),
		.acmlt_in_info_along(pool_upd_i_is_zero_sfc),
		.acmlt_in_valid(pool_upd_i_valid),
		
		.acmlt_out_data(pool_upd_o_data),
		.acmlt_out_mask(pool_upd_o_mask),
		.acmlt_out_last_grp(pool_upd_o_last_grp),
		.acmlt_out_last_res(pool_upd_o_last_res),
		.acmlt_out_to_upd_mem(pool_upd_o_to_upd_mem),
		.acmlt_out_valid(pool_upd_o_valid[0])
	);
	
	genvar mid_res_i;
	generate
		for(mid_res_i = 0;mid_res_i < ATOMIC_C;mid_res_i = mid_res_i + 1)
		begin:mid_res_blk
			assign pool_upd_i_info_along[mid_res_i] = 
				(mid_res_i == 0) ? 
					{
						((mid_res_buf_pool_mode == POOL_MODE_UPSP) | pool_upd_i_first_item) | 
						((mid_res_buf_pool_mode == POOL_MODE_MAX) | (~pool_upd_i_is_zero_sfc)),
						pool_upd_i_last_grp,
						pool_upd_i_last_res,
						pool_upd_i_mask
					}:
					{(3+ATOMIC_C){1'bx}};
			
			pool_middle_res_upd #(
				.INFO_ALONG_WIDTH(ATOMIC_C+3),
				.SIM_DELAY(SIM_DELAY)
			)pool_middle_res_upd_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(1'b1),
				
				.pool_mode(mid_res_buf_pool_mode),
				.calfmt(mid_res_buf_calfmt),
				
				.pool_upd_in_data(pool_upd_i_new_res[mid_res_i*48+15:mid_res_i*48]),
				.pool_upd_in_org_mid_res(pool_upd_i_org_mid_res[mid_res_i*32+31:mid_res_i*32]),
				.pool_upd_in_is_first_item(pool_upd_i_first_item),
				.pool_upd_in_is_zero_sfc(pool_upd_i_is_zero_sfc),
				.pool_upd_in_info_along(pool_upd_i_info_along[mid_res_i]),
				.pool_upd_in_valid(pool_upd_i_valid[mid_res_i]),
				
				.pool_upd_out_data(pool_upd_o_data[mid_res_i*32+31:mid_res_i*32]),
				.pool_upd_out_info_along(pool_upd_o_info_along[mid_res_i]),
				.pool_upd_out_valid(pool_upd_o_valid[mid_res_i])
			);
		end
	endgenerate
	
	/** 后乘加处理 **/
	// 后乘加处理的乘法器组
	wire[POST_MAC_MUL_OP_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_op_a; // 操作数A
	wire[POST_MAC_MUL_OP_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_op_b; // 操作数B
	wire[POST_MAC_MUL_CE_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_ce; // 计算使能
	wire[POST_MAC_MUL_RES_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_res; // 计算结果
	// 处理结果fifo(MEM主接口)
	wire proc_res_fifo_mem_clk;
	wire proc_res_fifo_mem_wen_a;
	wire[8:0] proc_res_fifo_mem_addr_a;
	wire[POST_MAC_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_din_a;
	wire proc_res_fifo_mem_ren_b;
	wire[8:0] proc_res_fifo_mem_addr_b;
	wire[POST_MAC_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_dout_b;
	
	conv_bn_act_proc #(
		.FP32_KEEP(1'b1),
		.ATOMIC_K(ATOMIC_C),
		.BN_ACT_PRL_N(POST_MAC_PRL_N),
		.INT16_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT32_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP32_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.SIM_DELAY(SIM_DELAY)
	)post_mac_proc_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.en_bn_act_proc(en_bn_act_proc_dup),
		
		.calfmt(bn_act_calfmt),
		.use_bn_unit(bn_act_use_bn_unit),
		.use_act_unit(bn_act_use_act_unit),
		.bn_fixed_point_quat_accrc(bn_act_bn_fixed_point_quat_accrc),
		.bn_is_a_eq_1(bn_act_bn_is_a_eq_1),
		.bn_is_b_eq_0(bn_act_bn_is_b_eq_0),
		.is_in_const_mac_mode(bn_act_is_in_const_mac_mode),
		.param_a_in_const_mac_mode(bn_act_param_a_in_const_mac_mode),
		.param_b_in_const_mac_mode(bn_act_param_b_in_const_mac_mode),
		.leaky_relu_fixed_point_quat_accrc(5'dx),
		.leaky_relu_param_alpha(32'hxxxxxxxx),
		
		.s_sub_row_msg_axis_data(16'hxxxx),
		.s_sub_row_msg_axis_last(1'bx),
		.s_sub_row_msg_axis_valid(1'b0),
		.s_sub_row_msg_axis_ready(),
		
		.s_axis_fnl_res_data(m_axis_ext_bn_act_i_data),
		.s_axis_fnl_res_keep(m_axis_ext_bn_act_i_keep),
		.s_axis_fnl_res_user(m_axis_ext_bn_act_i_user),
		.s_axis_fnl_res_last(m_axis_ext_bn_act_i_last),
		.s_axis_fnl_res_valid(m_axis_ext_bn_act_i_valid),
		.s_axis_fnl_res_ready(m_axis_ext_bn_act_i_ready),
		
		.m_axis_bn_act_res_data(s_axis_ext_bn_act_o_data),
		.m_axis_bn_act_res_keep(s_axis_ext_bn_act_o_keep),
		.m_axis_bn_act_res_user(s_axis_ext_bn_act_o_user),
		.m_axis_bn_act_res_last(s_axis_ext_bn_act_o_last),
		.m_axis_bn_act_res_valid(s_axis_ext_bn_act_o_valid),
		.m_axis_bn_act_res_ready(s_axis_ext_bn_act_o_ready),
		
		.bn_mem_clk_b(),
		.bn_mem_ren_b(),
		.bn_mem_addr_b(),
		.bn_mem_dout_b(64'dx),
		
		.proc_res_fifo_mem_clk(proc_res_fifo_mem_clk),
		.proc_res_fifo_mem_wen_a(proc_res_fifo_mem_wen_a),
		.proc_res_fifo_mem_addr_a(proc_res_fifo_mem_addr_a),
		.proc_res_fifo_mem_din_a(proc_res_fifo_mem_din_a),
		.proc_res_fifo_mem_ren_b(proc_res_fifo_mem_ren_b),
		.proc_res_fifo_mem_addr_b(proc_res_fifo_mem_addr_b),
		.proc_res_fifo_mem_dout_b(proc_res_fifo_mem_dout_b),
		
		.mul0_op_a(post_mac_mul_op_a),
		.mul0_op_b(post_mac_mul_op_b),
		.mul0_ce(post_mac_mul_ce),
		.mul0_res(post_mac_mul_res),
		
		.mul1_op_a(),
		.mul1_op_b(),
		.mul1_ce(),
		.mul1_res({(POST_MAC_PRL_N*(INT16_SUPPORTED ? 64:50)){1'bx}})
	);
	
	/** 输出数据舍入单元组 **/
	out_round_group #(
		.ATOMIC_K(ATOMIC_C),
		.INT8_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT16_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP16_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.USER_WIDTH(5),
		.SIM_DELAY(SIM_DELAY)
	)out_round_group_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.calfmt(round_calfmt),
		.fixed_point_quat_accrc(round_fixed_point_quat_accrc),
		
		.s_axis_round_data(m_axis_ext_round_i_data),
		.s_axis_round_keep(m_axis_ext_round_i_keep),
		.s_axis_round_user(m_axis_ext_round_i_user),
		.s_axis_round_last(m_axis_ext_round_i_last),
		.s_axis_round_valid(m_axis_ext_round_i_valid),
		.s_axis_round_ready(m_axis_ext_round_i_ready),
		
		.m_axis_round_data(s_axis_ext_round_o_data),
		.m_axis_round_keep(s_axis_ext_round_o_keep),
		.m_axis_round_user(s_axis_ext_round_o_user),
		.m_axis_round_last(s_axis_ext_round_o_last),
		.m_axis_round_valid(s_axis_ext_round_o_valid),
		.m_axis_round_ready(s_axis_ext_round_o_ready)
	);
	
	/** 最终结果数据收集器 **/
	conv_final_data_collector #(
		.IN_ITEM_WIDTH(ATOMIC_C),
		.OUT_ITEM_WIDTH(S2MM_STREAM_DATA_WIDTH/(KEEP_FP32_OUT ? 32:16)),
		.DATA_WIDTH_FOREACH_ITEM(KEEP_FP32_OUT ? 32:16),
		.HAS_USER("false"),
		.USER_WIDTH(1),
		.EN_COLLECTOR_OUT_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)pool_final_data_collector_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.s_axis_collector_data(m_axis_ext_collector_data),
		.s_axis_collector_keep(m_axis_ext_collector_keep),
		.s_axis_collector_user(1'bx),
		.s_axis_collector_last(m_axis_ext_collector_last),
		.s_axis_collector_valid(m_axis_ext_collector_valid),
		.s_axis_collector_ready(m_axis_ext_collector_ready),
		
		.m_axis_collector_data(m_axis_fnl_res_data),
		.m_axis_collector_keep(m_axis_fnl_res_keep),
		.m_axis_collector_user(),
		.m_axis_collector_last(m_axis_fnl_res_last),
		.m_axis_collector_valid(m_axis_fnl_res_valid),
		.m_axis_collector_ready(m_axis_fnl_res_ready)
	);
	
	/** 乘法器 **/
	unsigned_mul #(
		.op_a_width(16),
		.op_b_width(24),
		.output_width(40),
		.simulation_delay(SIM_DELAY)
	)mul_u16_u24_u0(
		.clk(aclk),
		
		.ce_s0_mul(mul1_ce),
		
		.op_a(mul1_op_a),
		.op_b(mul1_op_b),
		
		.res(mul1_res)
	);
	
	genvar post_mac_mul_i;
	generate
		if(INT8_SUPPORTED)
		begin:case_post_mac_int16_supported
			for(post_mac_mul_i = 0;post_mac_mul_i < 4 * POST_MAC_PRL_N;post_mac_mul_i = post_mac_mul_i + 1)
			begin:post_mac_mul_blk_a
				signed_mul #(
					.op_a_width(18),
					.op_b_width(18),
					.output_width(36),
					.en_in_reg("false"),
					.en_out_reg("false"),
					.simulation_delay(SIM_DELAY)
				)post_mac_mul_u(
					.clk(aclk),
					
					.ce_in_reg(1'b0),
					.ce_mul(post_mac_mul_ce[post_mac_mul_i]),
					.ce_out_reg(1'b0),
					
					.op_a(post_mac_mul_op_a[(post_mac_mul_i+1)*18-1:post_mac_mul_i*18]),
					.op_b(post_mac_mul_op_b[(post_mac_mul_i+1)*18-1:post_mac_mul_i*18]),
					
					.res(post_mac_mul_res[(post_mac_mul_i+1)*36-1:post_mac_mul_i*36])
				);
			end
		end
		else
		begin:case_post_mac_int16_not_supported
			for(post_mac_mul_i = 0;post_mac_mul_i < POST_MAC_PRL_N;post_mac_mul_i = post_mac_mul_i + 1)
			begin:post_mac_mul_blk_b
				signed_mul #(
					.op_a_width(INT16_SUPPORTED ? 32:25),
					.op_b_width(INT16_SUPPORTED ? 32:25),
					.output_width(INT16_SUPPORTED ? 64:50),
					.en_in_reg("true"),
					.en_out_reg("true"),
					.simulation_delay(SIM_DELAY)
				)post_mac_mul_u(
					.clk(aclk),
					
					.ce_in_reg(post_mac_mul_ce[post_mac_mul_i*3+0]),
					.ce_mul(post_mac_mul_ce[post_mac_mul_i*3+1]),
					.ce_out_reg(post_mac_mul_ce[post_mac_mul_i*3+2]),
					
					.op_a(post_mac_mul_op_a[(post_mac_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:post_mac_mul_i*(INT16_SUPPORTED ? 32:25)]),
					.op_b(post_mac_mul_op_b[(post_mac_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:post_mac_mul_i*(INT16_SUPPORTED ? 32:25)]),
					
					.res(post_mac_mul_res[(post_mac_mul_i+1)*(INT16_SUPPORTED ? 64:50)-1:post_mac_mul_i*(INT16_SUPPORTED ? 64:50)])
				);
			end
		end
	endgenerate
	
	/** SRAM **/
	genvar mid_res_mem_i;
	generate
		for(mid_res_mem_i = 0;mid_res_mem_i < RBUF_BANK_N;mid_res_mem_i = mid_res_mem_i + 1)
		begin:mem_blk
			bram_simple_dual_port #(
				.style("LOW_LATENCY"),
				.mem_width(ATOMIC_C*4*8+ATOMIC_C),
				.mem_depth(RBUF_DEPTH),
				.INIT_FILE("default"),
				.simulation_delay(SIM_DELAY)
			)mid_res_ram_u(
				.clk(mid_res_mem_clk_a),
				
				.wen_a(mid_res_mem_wen_a[mid_res_mem_i]),
				.addr_a(mid_res_mem_addr_a[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.din_a(mid_res_mem_din_a[(mid_res_mem_i+1)*(ATOMIC_C*4*8+ATOMIC_C)-1:mid_res_mem_i*(ATOMIC_C*4*8+ATOMIC_C)]),
				
				.ren_b(mid_res_mem_ren_b[mid_res_mem_i]),
				.addr_b(mid_res_mem_addr_b[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.dout_b(mid_res_mem_dout_b[(mid_res_mem_i+1)*(ATOMIC_C*4*8+ATOMIC_C)-1:mid_res_mem_i*(ATOMIC_C*4*8+ATOMIC_C)])
			);
		end
	endgenerate
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(LG_FMBUF_BUFFER_RID_WIDTH),
		.mem_depth(4096),
		.INIT_FILE("random"),
		.simulation_delay(SIM_DELAY)
	)actual_rid_mp_tb_ram_u(
		.clk(actual_rid_mp_tb_mem_clk),
		
		.wen_a(actual_rid_mp_tb_mem_wen_a),
		.addr_a(actual_rid_mp_tb_mem_addr_a),
		.din_a(actual_rid_mp_tb_mem_din_a),
		
		.ren_b(actual_rid_mp_tb_mem_ren_b),
		.addr_b(actual_rid_mp_tb_mem_addr_b),
		.dout_b(actual_rid_mp_tb_mem_dout_b)
	);
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(12),
		.mem_depth(2 ** LG_FMBUF_BUFFER_RID_WIDTH),
		.INIT_FILE("random"),
		.simulation_delay(SIM_DELAY)
	)buffer_rid_mp_tb_ram_u(
		.clk(buffer_rid_mp_tb_mem_clk),
		
		.wen_a(buffer_rid_mp_tb_mem_wen_a),
		.addr_a(buffer_rid_mp_tb_mem_addr_a),
		.din_a(buffer_rid_mp_tb_mem_din_a),
		
		.ren_b(buffer_rid_mp_tb_mem_ren_b),
		.addr_b(buffer_rid_mp_tb_mem_addr_b),
		.dout_b(buffer_rid_mp_tb_mem_dout_b)
	);
	
	genvar phy_conv_buf_mem_i;
	generate
		for(phy_conv_buf_mem_i = 0;phy_conv_buf_mem_i < CBUF_BANK_N;phy_conv_buf_mem_i = phy_conv_buf_mem_i + 1)
		begin:phy_conv_buf_mem_blk
			if(PHY_BUF_USE_TRUE_DUAL_PORT_SRAM)
			begin
				bram_true_dual_port #(
					.mem_width(ATOMIC_C*2*8),
					.mem_depth(CBUF_DEPTH_FOREACH_BANK),
					.INIT_FILE("no_init"),
					.read_write_mode("read_first"),
					.use_output_register("false"),
					.en_byte_write("true"),
					.simulation_delay(SIM_DELAY)
				)phy_conv_buf_ram_u(
					.clk(phy_conv_buf_mem_clk_a),
					
					.ena(phy_conv_buf_mem_en_a[phy_conv_buf_mem_i]),
					.wea(phy_conv_buf_mem_wen_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2-1:phy_conv_buf_mem_i*ATOMIC_C*2]),
					.addra(phy_conv_buf_mem_addr_a[phy_conv_buf_mem_i*16+clogb2(CBUF_DEPTH_FOREACH_BANK-1):phy_conv_buf_mem_i*16]),
					.dina(phy_conv_buf_mem_din_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					.douta(phy_conv_buf_mem_dout_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					
					.enb(phy_conv_buf_mem_en_b[phy_conv_buf_mem_i]),
					.web(phy_conv_buf_mem_wen_b[(phy_conv_buf_mem_i+1)*ATOMIC_C*2-1:phy_conv_buf_mem_i*ATOMIC_C*2]),
					.addrb(phy_conv_buf_mem_addr_b[phy_conv_buf_mem_i*16+clogb2(CBUF_DEPTH_FOREACH_BANK-1):phy_conv_buf_mem_i*16]),
					.dinb(phy_conv_buf_mem_din_b[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					.doutb(phy_conv_buf_mem_dout_b[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8])
				);
			end
			else
			begin
				assign phy_conv_buf_mem_dout_b = {(CBUF_BANK_N*ATOMIC_C*2*8){1'bx}};
				
				bram_single_port #(
					.style("LOW_LATENCY"),
					.rw_mode("read_first"),
					.mem_width(ATOMIC_C*2*8),
					.mem_depth(CBUF_DEPTH_FOREACH_BANK),
					.INIT_FILE("no_init"),
					.byte_write_mode("true"),
					.simulation_delay(SIM_DELAY)
				)phy_conv_buf_ram_u(
					.clk(phy_conv_buf_mem_clk_a),
					
					.en(phy_conv_buf_mem_en_a[phy_conv_buf_mem_i]),
					.wen(phy_conv_buf_mem_wen_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2-1:phy_conv_buf_mem_i*ATOMIC_C*2]),
					.addr(phy_conv_buf_mem_addr_a[phy_conv_buf_mem_i*16+clogb2(CBUF_DEPTH_FOREACH_BANK-1):phy_conv_buf_mem_i*16]),
					.din(phy_conv_buf_mem_din_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					.dout(phy_conv_buf_mem_dout_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8])
				);
			end
		end
	endgenerate
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(POST_MAC_PROC_RES_FIFO_WIDTH),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)post_mac_proc_res_fifo_ram_u(
		.clk(proc_res_fifo_mem_clk),
		
		.wen_a(proc_res_fifo_mem_wen_a),
		.addr_a(proc_res_fifo_mem_addr_a),
		.din_a(proc_res_fifo_mem_din_a),
		
		.ren_b(proc_res_fifo_mem_ren_b),
		.addr_b(proc_res_fifo_mem_addr_b),
		.dout_b(proc_res_fifo_mem_dout_b)
	);
	
endmodule
