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
本模块: AXI-通用卷积处理单元(顶层)

描述:
包括寄存器配置接口、BN参数MEM控制器、控制子系统、数据枢纽、计算子系统

支持普通卷积(包括全连接层)、组卷积(包括深度可分离卷积)、转置卷积(转换为合适的特征图填充与卷积步长来实现)
支持特征图外填充与内填充
支持卷积核膨胀
支持计算轮次拓展
支持批归一化处理
支持Leaky-Relu激活

注意：
需要外接2个DMA(MM2S)通道和1个DMA(S2MM)通道

可将SRAM和乘法器的接口引出, 在SOC层面再连接, 以实现SRAM和乘法器的共享

BN与激活并行数(BN_ACT_PRL_N)必须<=核并行数(ATOMIC_K)

协议:
AXI-Lite SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/31
********************************************************************/


module axi_generic_conv #(
	parameter integer MAC_ARRAY_CLK_RATE = 1, // 计算核心时钟倍率(>=1)
	parameter integer BN_ACT_CLK_RATE = 1, // BN与激活单元的时钟倍率(>=1)
	parameter integer MID_RES_BUF_CLK_RATE = 1, // 中间结果缓存时钟倍率(1 | 2 | 4 | 8)
	parameter integer BN_SUPPORTED = 1, // 是否支持批归一化处理
	parameter integer LEAKY_RELU_SUPPORTED = 1, // 是否支持Leaky-Relu激活
	parameter integer SIGMOID_SUPPORTED = 1, // 是否支持Sigmoid激活
	parameter integer INT8_SUPPORTED = 0, // 是否支持INT8
	parameter integer INT16_SUPPORTED = 0, // 是否支持INT16
	parameter integer FP16_SUPPORTED = 1, // 是否支持FP16
	parameter integer LARGE_V_STRD_SUPPORTED = 1, // 是否支持>1的卷积垂直步长
	parameter integer LARGE_H_STRD_SUPPORTED = 1, // 是否支持>1的卷积水平步长
	parameter integer GRP_CONV_SUPPORTED = 0, // 是否支持组卷积
	parameter integer EXT_PADDING_SUPPORTED = 1, // 是否支持外填充
	parameter integer INNER_PADDING_SUPPORTED = 0, // 是否支持内填充
	parameter integer KERNAL_DILATION_SUPPORTED = 0, // 是否支持卷积核膨胀
	parameter integer EN_PERF_MON = 1, // 是否支持性能监测
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter integer FP32_KEEP = 0, // 是否保持FP32输出
	parameter integer ATOMIC_K = 4, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1, // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2, // 最大的计算轮次(1~16)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer PHY_BUF_USE_TRUE_DUAL_PORT_SRAM = 0, // 物理缓存是否使用真双口RAM
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 1024, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer MAX_KERNAL_N = 1024, // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer RBUF_BANK_N = 8, // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 中间结果缓存MEM深度(16 | ...)
	parameter SIGMOID_LUT_MEM_INIT_FILE = "act_sigmoid.txt", // sigmoid函数值查找表存储器的初始化文件路径
	parameter integer USE_DSP_MACRO_FOR_ADD_TREE_IN_MAC_ARRAY = 0, // 是否使用DSP单元作为乘加阵列里的加法器
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	// 计算核心时钟和复位
	input wire mac_array_aclk,
	input wire mac_array_aresetn,
	// BN与激活单元时钟和复位
	input wire bn_act_aclk,
	input wire bn_act_aresetn,
	// 中间结果缓存时钟和复位
	input wire mid_res_buf_aclk,
	input wire mid_res_buf_aresetn,
	
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
	
	// BN参数存储器(AXI从机)
    // 读地址通道
    input wire[31:0] s_axi_araddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_arburst,
    input wire[3:0] s_axi_arcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_arlen,
    input wire s_axi_arlock, // ignored
    input wire[2:0] s_axi_arprot, // ignored
    input wire[2:0] s_axi_arsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // 写地址通道
    input wire[31:0] s_axi_awaddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_awburst,
    input wire[3:0] s_axi_awcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_awlen,
    input wire s_axi_awlock, // ignored
    input wire[2:0] s_axi_awprot, // ignored
    input wire[2:0] s_axi_awsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // 写响应通道
    output wire[1:0] s_axi_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // 读数据通道
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // 写数据通道
    input wire[31:0] s_axi_wdata,
    input wire s_axi_wlast,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
	
	// DMA命令完成指示
	input wire mm2s_0_cmd_done, // 0号MM2S通道命令完成(指示)
	input wire mm2s_1_cmd_done, // 1号MM2S通道命令完成(指示)
	input wire s2mm_cmd_done, // S2MM通道命令完成(指示)
	
	// DMA(MM2S方向)命令流#0(AXIS主机)
	output wire[55:0] m0_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m0_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m0_dma_cmd_axis_last, // 帧尾标志
	output wire m0_dma_cmd_axis_valid,
	input wire m0_dma_cmd_axis_ready,
	// DMA(MM2S方向)数据流#0(AXIS从机)
	input wire[MM2S_STREAM_DATA_WIDTH-1:0] s0_dma_strm_axis_data,
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s0_dma_strm_axis_keep,
	input wire s0_dma_strm_axis_last,
	input wire s0_dma_strm_axis_valid,
	output wire s0_dma_strm_axis_ready,
	
	// DMA(MM2S方向)命令流#1(AXIS主机)
	output wire[55:0] m1_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m1_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m1_dma_cmd_axis_last, // 帧尾标志
	output wire m1_dma_cmd_axis_valid,
	input wire m1_dma_cmd_axis_ready,
	// DMA(MM2S方向)数据流#1(AXIS从机)
	input wire[MM2S_STREAM_DATA_WIDTH-1:0] s1_dma_strm_axis_data,
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s1_dma_strm_axis_keep,
	input wire s1_dma_strm_axis_last,
	input wire s1_dma_strm_axis_valid,
	output wire s1_dma_strm_axis_ready,
	
	// DMA(S2MM方向)命令流(AXIS主机)
	output wire[55:0] m_dma_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_s2mm_cmd_axis_user, // 固定(1'b1)/递增(1'b0)传输(1bit)
	output wire m_dma_s2mm_cmd_axis_valid,
	input wire m_dma_s2mm_cmd_axis_ready,
	
	// 最终结果数据流(AXIS主机)
	output wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_fnl_res_data,
	output wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep,
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready
);
	
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
	
	/** 内部参数 **/
	// 特征图缓存的缓存行号的位宽
	localparam integer LG_FMBUF_BUFFER_RID_WIDTH = clogb2(MAX_FMBUF_ROWN);
	// 批归一化与激活处理结果fifo的位宽
	localparam integer BN_ACT_PROC_RES_FIFO_WIDTH = BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5;
	// BN乘法器的位宽
	localparam integer BN_MUL_OP_WIDTH = INT8_SUPPORTED ? 4*18:(INT16_SUPPORTED ? 32:25);
	localparam integer BN_MUL_CE_WIDTH = INT8_SUPPORTED ? 4:3;
	localparam integer BN_MUL_RES_WIDTH = INT8_SUPPORTED ? 4*36:(INT16_SUPPORTED ? 64:50);
	// 泄露Relu乘法器的位宽
	localparam integer LEAKY_RELU_MUL_OP_WIDTH = INT16_SUPPORTED ? 32:25;
	localparam integer LEAKY_RELU_MUL_CE_WIDTH = 2;
	localparam integer LEAKY_RELU_MUL_RES_WIDTH = INT16_SUPPORTED ? 64:50;
	
	/** AXI-通用卷积处理单元(核心) **/
	// (共享)数据枢纽
	// [运行时参数]
	wire[3:0] data_hub_fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] data_hub_fmbufrown; // 可缓存的表面行数 - 1
	wire data_hub_is_grp_conv_mode; // 是否处于组卷积缓存模式
	wire[2:0] data_hub_kernal_shape; // 卷积核形状
	wire[2:0] data_hub_sfc_n_each_wgtblk; // 每个权重块的表面个数的类型
	wire[7:0] data_hub_kbufgrpn; // 可缓存的通道组数 - 1
	wire[7:0] data_hub_fmbufbankn; // 分配给特征图缓存的Bank数
	// [特征图表面行读请求(AXIS主机)]
	wire[103:0] m_fm_rd_req_axis_data;
	wire m_fm_rd_req_axis_valid;
	wire m_fm_rd_req_axis_ready;
	// [卷积核权重块读请求(AXIS主机)]
	wire[103:0] m_kwgtblk_rd_req_axis_data;
	wire m_kwgtblk_rd_req_axis_valid;
	wire m_kwgtblk_rd_req_axis_ready;
	// [特征图表面行数据(AXIS从机)]
	wire[ATOMIC_C*2*8-1:0] s_fm_sfc_row_axis_data;
	wire s_fm_sfc_row_axis_last; // 标志本次读请求的最后1个表面
	wire s_fm_sfc_row_axis_valid;
	wire s_fm_sfc_row_axis_ready;
	// [卷积核权重块数据(AXIS从机)]
	wire[ATOMIC_C*2*8-1:0] s_kernal_wgtblk_axis_data;
	wire s_kernal_wgtblk_axis_last; // 标志本次读请求的最后1个表面
	wire s_kernal_wgtblk_axis_valid;
	wire s_kernal_wgtblk_axis_ready;
	// (共享)最终结果传输请求生成单元
	// [运行时参数]
	wire[31:0] fnl_res_tr_req_gen_ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] fnl_res_tr_req_gen_ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] fnl_res_tr_req_gen_ofmap_h; // 输出特征图高度 - 1
	wire[1:0] fnl_res_tr_req_gen_ofmap_data_type; // 输出特征图数据大小类型
	wire[15:0] fnl_res_tr_req_gen_kernal_num_n; // 卷积核核数 - 1
	wire[5:0] fnl_res_tr_req_gen_max_wgtblk_w; // 权重块最大宽度
	wire fnl_res_tr_req_gen_is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] fnl_res_tr_req_gen_n_foreach_group; // 每组的通道数/核数 - 1
	// [块级控制]
	wire fnl_res_trans_blk_start;
	wire fnl_res_trans_blk_idle;
	wire fnl_res_trans_blk_done;
	// (共享)中间结果缓存
	// [使能信号]
	wire en_mid_res_buf_dup; // 使能中间结果缓存
	// [运行时参数]
	wire[1:0] mid_res_buf_calfmt; // 运算数据格式
	wire[3:0] mid_res_buf_row_n_bufferable_dup; // 可缓存行数 - 1
	wire[3:0] mid_res_buf_bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的缓存MEM个数
	wire[3:0] mid_res_buf_max_upd_latency; // 最大的更新时延
	// [中间结果(AXIS主机)]
	wire[ATOMIC_K*48-1:0] m_axis_ext_mid_res_data;
	wire[ATOMIC_K*6-1:0] m_axis_ext_mid_res_keep;
	wire[2:0] m_axis_ext_mid_res_user; // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_ext_mid_res_last; // 本行最后1个中间结果(标志)
	wire m_axis_ext_mid_res_valid;
	wire m_axis_ext_mid_res_ready;
	// [最终结果(AXIS从机)]
	wire[ATOMIC_K*32-1:0] s_axis_ext_fnl_res_data; // ATOMIC_K个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_K*4-1:0] s_axis_ext_fnl_res_keep;
	wire[4:0] s_axis_ext_fnl_res_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_ext_fnl_res_last; // 本行最后1个最终结果(标志)
	wire s_axis_ext_fnl_res_valid;
	wire s_axis_ext_fnl_res_ready;
	// (共享)BN与激活单元
	// [使能信号]
	wire en_bn_act_proc_dup; // 使能处理单元
	// [运行时参数]
	wire[1:0] bn_act_calfmt; // 运算数据格式
	wire bn_act_use_bn_unit; // 启用BN单元
	wire[2:0] bn_act_act_func_type; // 激活函数类型
	wire[4:0] bn_act_bn_fixed_point_quat_accrc; // (批归一化操作数A)定点数量化精度
	wire bn_act_bn_is_a_eq_1; // 批归一化参数A的实际值为1(标志)
	wire bn_act_bn_is_b_eq_0; // 批归一化参数B的实际值为0(标志)
	wire[4:0] bn_act_leaky_relu_fixed_point_quat_accrc; // (泄露Relu激活参数)定点数量化精度
	wire[31:0] bn_act_leaky_relu_param_alpha; // 泄露Relu激活参数
	wire[4:0] bn_act_sigmoid_fixed_point_quat_accrc; // (Sigmoid输入)定点数量化精度
	// [卷积最终结果(AXIS主机)]
	wire[ATOMIC_K*32-1:0] m_axis_ext_bn_act_i_data; // 对于ATOMIC_K个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[ATOMIC_K*4-1:0] m_axis_ext_bn_act_i_keep;
	wire[4:0] m_axis_ext_bn_act_i_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_ext_bn_act_i_last; // 本行最后1个最终结果(标志)
	wire m_axis_ext_bn_act_i_valid;
	wire m_axis_ext_bn_act_i_ready;
	// [经过BN与激活处理的结果(AXIS从机)]
	wire[BN_ACT_PRL_N*32-1:0] s_axis_ext_bn_act_o_data; // 对于BN_ACT_PRL_N个最终结果 -> {浮点数或定点数}
	wire[BN_ACT_PRL_N*4-1:0] s_axis_ext_bn_act_o_keep;
	wire[4:0] s_axis_ext_bn_act_o_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_ext_bn_act_o_last; // 本行最后1个处理结果(标志)
	wire s_axis_ext_bn_act_o_valid;
	wire s_axis_ext_bn_act_o_ready;
	// [BN参数MEM接口]
	wire bn_mem_clk_a;
	wire bn_mem_en_a;
	wire[7:0] bn_mem_wen_a;
	wire[15:0] bn_mem_addr_a;
	wire[63:0] bn_mem_din_a; // {参数B(32bit), 参数A(32bit)}
	wire[63:0] bn_mem_dout_a; // {参数B(32bit), 参数A(32bit)}
	// (共享)输出数据舍入单元组
	// [运行时参数]
	wire[1:0] round_calfmt; // 运算数据格式
	wire[3:0] round_fixed_point_quat_accrc; // 定点数量化精度
	// [待舍入数据(AXIS主机)]
	wire[ATOMIC_K*32-1:0] m_axis_ext_round_i_data; // ATOMIC_K个定点数或FP32
	wire[ATOMIC_K*4-1:0] m_axis_ext_round_i_keep;
	wire[4:0] m_axis_ext_round_i_user;
	wire m_axis_ext_round_i_last;
	wire m_axis_ext_round_i_valid;
	wire m_axis_ext_round_i_ready;
	// [舍入后数据(AXIS从机)]
	wire[ATOMIC_K*16-1:0] s_axis_ext_round_o_data; // ATOMIC_K个定点数或浮点数
	wire[ATOMIC_K*2-1:0] s_axis_ext_round_o_keep;
	wire[4:0] s_axis_ext_round_o_user;
	wire s_axis_ext_round_o_last;
	wire s_axis_ext_round_o_valid;
	wire s_axis_ext_round_o_ready;
	// (共享)最终结果数据收集器
	// [待收集的数据流(AXIS主机)]
	wire[ATOMIC_K*(FP32_KEEP ? 32:16)-1:0] m_axis_ext_collector_data;
	wire[ATOMIC_K*(FP32_KEEP ? 4:2)-1:0] m_axis_ext_collector_keep;
	wire m_axis_ext_collector_last;
	wire m_axis_ext_collector_valid;
	wire m_axis_ext_collector_ready;
	
	axi_generic_conv_core #(
		.MAC_ARRAY_CLK_RATE(MAC_ARRAY_CLK_RATE),
		.MID_RES_BUF_CLK_RATE(MID_RES_BUF_CLK_RATE),
		.BN_SUPPORTED(BN_SUPPORTED),
		.LEAKY_RELU_SUPPORTED(LEAKY_RELU_SUPPORTED),
		.SIGMOID_SUPPORTED(SIGMOID_SUPPORTED),
		.INT8_SUPPORTED(INT8_SUPPORTED),
		.INT16_SUPPORTED(INT16_SUPPORTED),
		.FP16_SUPPORTED(FP16_SUPPORTED),
		.LARGE_V_STRD_SUPPORTED(LARGE_V_STRD_SUPPORTED),
		.LARGE_H_STRD_SUPPORTED(LARGE_H_STRD_SUPPORTED),
		.GRP_CONV_SUPPORTED(GRP_CONV_SUPPORTED),
		.EXT_PADDING_SUPPORTED(EXT_PADDING_SUPPORTED),
		.INNER_PADDING_SUPPORTED(INNER_PADDING_SUPPORTED),
		.KERNAL_DILATION_SUPPORTED(KERNAL_DILATION_SUPPORTED),
		.EN_PERF_MON(EN_PERF_MON),
		.ACCELERATOR_ID(ACCELERATOR_ID),
		.FP32_KEEP(FP32_KEEP),
		.ATOMIC_K(ATOMIC_K),
		.ATOMIC_C(ATOMIC_C),
		.BN_ACT_PRL_N(BN_ACT_PRL_N),
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.MAX_KERNAL_N(MAX_KERNAL_N),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.USE_DSP_MACRO_FOR_ADD_TREE_IN_MAC_ARRAY(USE_DSP_MACRO_FOR_ADD_TREE_IN_MAC_ARRAY),
		.SIM_DELAY(SIM_DELAY)
	)axi_generic_conv_core_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		.mac_array_aclk(mac_array_aclk),
		.mac_array_aresetn(mac_array_aresetn),
		.mac_array_aclken(1'b1),
		
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
		
		.s_axi_araddr(s_axi_araddr),
		.s_axi_arburst(s_axi_arburst),
		.s_axi_arcache(s_axi_arcache),
		.s_axi_arlen(s_axi_arlen),
		.s_axi_arlock(s_axi_arlock),
		.s_axi_arprot(s_axi_arprot),
		.s_axi_arsize(s_axi_arsize),
		.s_axi_arvalid(s_axi_arvalid),
		.s_axi_arready(s_axi_arready),
		.s_axi_awaddr(s_axi_awaddr),
		.s_axi_awburst(s_axi_awburst),
		.s_axi_awcache(s_axi_awcache),
		.s_axi_awlen(s_axi_awlen),
		.s_axi_awlock(s_axi_awlock),
		.s_axi_awprot(s_axi_awprot),
		.s_axi_awsize(s_axi_awsize),
		.s_axi_awvalid(s_axi_awvalid),
		.s_axi_awready(s_axi_awready),
		.s_axi_bresp(s_axi_bresp),
		.s_axi_bvalid(s_axi_bvalid),
		.s_axi_bready(s_axi_bready),
		.s_axi_rdata(s_axi_rdata),
		.s_axi_rlast(s_axi_rlast),
		.s_axi_rresp(s_axi_rresp),
		.s_axi_rvalid(s_axi_rvalid),
		.s_axi_rready(s_axi_rready),
		.s_axi_wdata(s_axi_wdata),
		.s_axi_wlast(s_axi_wlast),
		.s_axi_wstrb(s_axi_wstrb),
		.s_axi_wvalid(s_axi_wvalid),
		.s_axi_wready(s_axi_wready),
		
		.s0_dma_strm_axis_keep(s0_dma_strm_axis_keep),
		.s0_dma_strm_axis_valid(s0_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.s1_dma_strm_axis_keep(s1_dma_strm_axis_keep),
		.s1_dma_strm_axis_valid(s1_dma_strm_axis_valid),
		.s1_dma_strm_axis_ready(s1_dma_strm_axis_ready),
		
		.s_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.s_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.s_axis_fnl_res_ready(m_axis_fnl_res_ready),
		
		.data_hub_fmbufcoln(data_hub_fmbufcoln),
		.data_hub_fmbufrown(data_hub_fmbufrown),
		.data_hub_is_grp_conv_mode(data_hub_is_grp_conv_mode),
		.data_hub_kernal_shape(data_hub_kernal_shape),
		.data_hub_sfc_n_each_wgtblk(data_hub_sfc_n_each_wgtblk),
		.data_hub_kbufgrpn(data_hub_kbufgrpn),
		.data_hub_fmbufbankn(data_hub_fmbufbankn),
		.m_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		.m_kwgtblk_rd_req_axis_data(m_kwgtblk_rd_req_axis_data),
		.m_kwgtblk_rd_req_axis_valid(m_kwgtblk_rd_req_axis_valid),
		.m_kwgtblk_rd_req_axis_ready(m_kwgtblk_rd_req_axis_ready),
		.s_fm_sfc_row_axis_data(s_fm_sfc_row_axis_data),
		.s_fm_sfc_row_axis_last(s_fm_sfc_row_axis_last),
		.s_fm_sfc_row_axis_valid(s_fm_sfc_row_axis_valid),
		.s_fm_sfc_row_axis_ready(s_fm_sfc_row_axis_ready),
		.s_kernal_wgtblk_axis_data(s_kernal_wgtblk_axis_data),
		.s_kernal_wgtblk_axis_last(s_kernal_wgtblk_axis_last),
		.s_kernal_wgtblk_axis_valid(s_kernal_wgtblk_axis_valid),
		.s_kernal_wgtblk_axis_ready(s_kernal_wgtblk_axis_ready),
		
		.fnl_res_tr_req_gen_ofmap_baseaddr(fnl_res_tr_req_gen_ofmap_baseaddr),
		.fnl_res_tr_req_gen_ofmap_w(fnl_res_tr_req_gen_ofmap_w),
		.fnl_res_tr_req_gen_ofmap_h(fnl_res_tr_req_gen_ofmap_h),
		.fnl_res_tr_req_gen_ofmap_data_type(fnl_res_tr_req_gen_ofmap_data_type),
		.fnl_res_tr_req_gen_kernal_num_n(fnl_res_tr_req_gen_kernal_num_n),
		.fnl_res_tr_req_gen_max_wgtblk_w(fnl_res_tr_req_gen_max_wgtblk_w),
		.fnl_res_tr_req_gen_is_grp_conv_mode(fnl_res_tr_req_gen_is_grp_conv_mode),
		.fnl_res_tr_req_gen_n_foreach_group(fnl_res_tr_req_gen_n_foreach_group),
		.fnl_res_trans_blk_start(fnl_res_trans_blk_start),
		.fnl_res_trans_blk_idle(fnl_res_trans_blk_idle),
		.fnl_res_trans_blk_done(fnl_res_trans_blk_done),
		
		.en_mid_res_buf_dup(en_mid_res_buf_dup),
		.mid_res_buf_calfmt(mid_res_buf_calfmt),
		.mid_res_buf_row_n_bufferable_dup(mid_res_buf_row_n_bufferable_dup),
		.mid_res_buf_bank_n_foreach_ofmap_row(mid_res_buf_bank_n_foreach_ofmap_row),
		.mid_res_buf_max_upd_latency(mid_res_buf_max_upd_latency),
		.m_axis_ext_mid_res_data(m_axis_ext_mid_res_data),
		.m_axis_ext_mid_res_keep(m_axis_ext_mid_res_keep),
		.m_axis_ext_mid_res_user(m_axis_ext_mid_res_user),
		.m_axis_ext_mid_res_last(m_axis_ext_mid_res_last),
		.m_axis_ext_mid_res_valid(m_axis_ext_mid_res_valid),
		.m_axis_ext_mid_res_ready(m_axis_ext_mid_res_ready),
		.s_axis_ext_fnl_res_data(s_axis_ext_fnl_res_data),
		.s_axis_ext_fnl_res_keep(s_axis_ext_fnl_res_keep),
		.s_axis_ext_fnl_res_user(s_axis_ext_fnl_res_user),
		.s_axis_ext_fnl_res_last(s_axis_ext_fnl_res_last),
		.s_axis_ext_fnl_res_valid(s_axis_ext_fnl_res_valid),
		.s_axis_ext_fnl_res_ready(s_axis_ext_fnl_res_ready),
		
		.en_bn_act_proc_dup(en_bn_act_proc_dup),
		.bn_act_calfmt(bn_act_calfmt),
		.bn_act_use_bn_unit(bn_act_use_bn_unit),
		.bn_act_act_func_type(bn_act_act_func_type),
		.bn_act_bn_fixed_point_quat_accrc(bn_act_bn_fixed_point_quat_accrc),
		.bn_act_bn_is_a_eq_1(bn_act_bn_is_a_eq_1),
		.bn_act_bn_is_b_eq_0(bn_act_bn_is_b_eq_0),
		.bn_act_leaky_relu_fixed_point_quat_accrc(bn_act_leaky_relu_fixed_point_quat_accrc),
		.bn_act_leaky_relu_param_alpha(bn_act_leaky_relu_param_alpha),
		.bn_act_sigmoid_fixed_point_quat_accrc(bn_act_sigmoid_fixed_point_quat_accrc),
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
		.bn_mem_clk_a(bn_mem_clk_a),
		.bn_mem_en_a(bn_mem_en_a),
		.bn_mem_wen_a(bn_mem_wen_a),
		.bn_mem_addr_a(bn_mem_addr_a),
		.bn_mem_din_a(bn_mem_din_a),
		.bn_mem_dout_a(bn_mem_dout_a),
		
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
		.m_axis_ext_collector_ready(m_axis_ext_collector_ready),
		
		.mm2s_0_cmd_done(mm2s_0_cmd_done),
		.mm2s_1_cmd_done(mm2s_1_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done)
	);
	
	/** 卷积数据枢纽 **/
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
	)conv_data_hub_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.fmbufcoln(data_hub_fmbufcoln),
		.fmbufrown(data_hub_fmbufrown),
		.fmrow_random_rd_mode(1'b0),
		.grp_conv_buf_mode(data_hub_is_grp_conv_mode),
		.kbufgrpsz(data_hub_kernal_shape),
		.sfc_n_each_wgtblk(data_hub_sfc_n_each_wgtblk),
		.kbufgrpn(data_hub_kbufgrpn),
		.fmbufbankn(data_hub_fmbufbankn),
		
		.s_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.s_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.s_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		
		.s_fm_random_rd_axis_data(16'dx),
		.s_fm_random_rd_axis_last(1'bx),
		.s_fm_random_rd_axis_valid(1'b0),
		.s_fm_random_rd_axis_ready(),
		
		.s_kwgtblk_rd_req_axis_data(m_kwgtblk_rd_req_axis_data),
		.s_kwgtblk_rd_req_axis_valid(m_kwgtblk_rd_req_axis_valid),
		.s_kwgtblk_rd_req_axis_ready(m_kwgtblk_rd_req_axis_ready),
		
		.m_fm_fout_axis_data(s_fm_sfc_row_axis_data),
		.m_fm_fout_axis_last(s_fm_sfc_row_axis_last),
		.m_fm_fout_axis_valid(s_fm_sfc_row_axis_valid),
		.m_fm_fout_axis_ready(s_fm_sfc_row_axis_ready),
		
		.m_kout_wgtblk_axis_data(s_kernal_wgtblk_axis_data),
		.m_kout_wgtblk_axis_last(s_kernal_wgtblk_axis_last),
		.m_kout_wgtblk_axis_valid(s_kernal_wgtblk_axis_valid),
		.m_kout_wgtblk_axis_ready(s_kernal_wgtblk_axis_ready),
		
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
	
	/** 卷积中间结果累加与缓存 **/
	// 中间结果缓存MEM主接口
	wire mid_res_mem_clk_a;
	wire[RBUF_BANK_N-1:0] mid_res_mem_wen_a;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_a;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_din_a;
	wire mid_res_mem_clk_b;
	wire[RBUF_BANK_N-1:0] mid_res_mem_ren_b;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_b;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_dout_b;
	// 中间结果累加单元组
	wire acmlt_aclk;
	wire acmlt_aresetn;
	wire acmlt_aclken;
	// [累加单元组输入]
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE*48-1:0] acmlt_in_new_res; // 新结果
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE*32-1:0] acmlt_in_org_mid_res; // 原中间结果
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE+2-1:0] acmlt_in_info_along[0:ATOMIC_K/MID_RES_BUF_CLK_RATE-1]; // 随路数据
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_in_mask; // 项掩码
	wire acmlt_in_first_item; // 是否第1项(标志)
	wire acmlt_in_last_grp; // 是否最后1组(标志)
	wire acmlt_in_last_res; // 本行最后1个中间结果(标志)
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_in_valid; // 输入有效指示
	// [累加单元组输出]
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE*32-1:0] acmlt_out_data; // 单精度浮点数或定点数
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE+2-1:0] acmlt_out_info_along[0:ATOMIC_K/MID_RES_BUF_CLK_RATE-1]; // 随路数据
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_out_mask; // 输出项掩码
	wire acmlt_out_last_grp; // 是否最后1组(标志)
	wire acmlt_out_last_res; // 本行最后1个中间结果(标志)
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_out_valid; // 输出有效指示
	
	assign {acmlt_out_last_res, acmlt_out_last_grp, acmlt_out_mask} = acmlt_out_info_along[0];
	
	genvar acmlt_i;
	generate
		for(acmlt_i = 0;acmlt_i < ATOMIC_K/MID_RES_BUF_CLK_RATE;acmlt_i = acmlt_i + 1)
		begin:acmlt_blk
			assign acmlt_in_info_along[acmlt_i] = 
				(acmlt_i == 0) ? 
					{acmlt_in_last_res, acmlt_in_last_grp, acmlt_in_mask}:
					{(ATOMIC_K/MID_RES_BUF_CLK_RATE+2){1'bx}};
			
			conv_middle_res_accumulate #(
				.EN_SMALL_FP32("true"),
				.INFO_ALONG_WIDTH(ATOMIC_K/MID_RES_BUF_CLK_RATE+2),
				.SIM_DELAY(SIM_DELAY)
			)conv_middle_res_accumulate_u(
				.aclk(acmlt_aclk),
				.aresetn(acmlt_aresetn),
				.aclken(acmlt_aclken),
				
				.calfmt(mid_res_buf_calfmt),
				
				.acmlt_in_exp(acmlt_in_new_res[acmlt_i*48+47:acmlt_i*48+40]),
				.acmlt_in_frac(acmlt_in_new_res[acmlt_i*48+39:acmlt_i*48+0]),
				.acmlt_in_org_mid_res(acmlt_in_org_mid_res[acmlt_i*32+31:acmlt_i*32+0]),
				.acmlt_in_first_item(acmlt_in_first_item),
				.acmlt_in_info_along(acmlt_in_info_along[acmlt_i]),
				.acmlt_in_valid(acmlt_in_valid[acmlt_i]),
				
				.acmlt_out_data(acmlt_out_data[acmlt_i*32+31:acmlt_i*32+0]),
				.acmlt_out_info_along(acmlt_out_info_along[acmlt_i]),
				.acmlt_out_valid(acmlt_out_valid[acmlt_i])
			);
		end
		
		if(MID_RES_BUF_CLK_RATE == 1)
		begin
			conv_middle_res_acmlt_buf #(
				.TSF_N_FOREACH_SFC(1),
				.ATOMIC_K(ATOMIC_K),
				.RBUF_BANK_N(RBUF_BANK_N),
				.RBUF_DEPTH(RBUF_DEPTH),
				.INFO_ALONG_WIDTH(1),
				.SIM_DELAY(SIM_DELAY)
			)conv_middle_res_acmlt_buf_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(1'b1),
				
				.calfmt(mid_res_buf_calfmt),
				.row_n_bufferable(mid_res_buf_row_n_bufferable_dup),
				.bank_n_foreach_ofmap_row(mid_res_buf_bank_n_foreach_ofmap_row),
				.max_upd_latency(mid_res_buf_max_upd_latency),
				.en_cal_round_ext(1'b1),
				.ofmap_w(16'dx),
				
				.s_axis_mid_res_data(m_axis_ext_mid_res_data),
				.s_axis_mid_res_keep(m_axis_ext_mid_res_keep),
				.s_axis_mid_res_user({1'b0, m_axis_ext_mid_res_user}),
				.s_axis_mid_res_last(m_axis_ext_mid_res_last),
				.s_axis_mid_res_valid(m_axis_ext_mid_res_valid),
				.s_axis_mid_res_ready(m_axis_ext_mid_res_ready),
				
				.m_axis_fnl_res_data(s_axis_ext_fnl_res_data),
				.m_axis_fnl_res_keep(s_axis_ext_fnl_res_keep),
				.m_axis_fnl_res_user(s_axis_ext_fnl_res_user),
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
				
				.acmlt_aclk(acmlt_aclk),
				.acmlt_aresetn(acmlt_aresetn),
				.acmlt_aclken(acmlt_aclken),
				.acmlt_in_new_res(acmlt_in_new_res),
				.acmlt_in_org_mid_res(acmlt_in_org_mid_res),
				.acmlt_in_mask(acmlt_in_mask),
				.acmlt_in_first_item(acmlt_in_first_item),
				.acmlt_in_last_grp(acmlt_in_last_grp),
				.acmlt_in_last_res(acmlt_in_last_res),
				.acmlt_in_info_along(),
				.acmlt_in_valid(acmlt_in_valid),
				
				.acmlt_out_data(acmlt_out_data),
				.acmlt_out_mask(acmlt_out_mask),
				.acmlt_out_last_grp(acmlt_out_last_grp),
				.acmlt_out_last_res(acmlt_out_last_res),
				.acmlt_out_to_upd_mem(1'b1),
				.acmlt_out_valid(acmlt_out_valid)
			);
		end
		else
		begin
			async_conv_middle_res_acmlt_buf #(
				.BUF_CLK_RATE(MID_RES_BUF_CLK_RATE),
				.ATOMIC_K(ATOMIC_K),
				.RBUF_BANK_N(RBUF_BANK_N),
				.RBUF_DEPTH(RBUF_DEPTH),
				.INFO_ALONG_WIDTH(1),
				.SIM_DELAY(SIM_DELAY)
			)conv_middle_res_acmlt_buf_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(1'b1),
				.mid_res_buf_aclk(mid_res_buf_aclk),
				.mid_res_buf_aresetn(mid_res_buf_aresetn),
				.mid_res_buf_aclken(1'b1),
				
				.runtime_params_vld(en_mid_res_buf_dup),
				
				.calfmt(mid_res_buf_calfmt),
				.row_n_bufferable(mid_res_buf_row_n_bufferable_dup),
				.bank_n_foreach_ofmap_row(mid_res_buf_bank_n_foreach_ofmap_row),
				.max_upd_latency(mid_res_buf_max_upd_latency),
				.en_cal_round_ext(1'b1),
				.ofmap_w(16'dx),
				
				.s_axis_mid_res_data(m_axis_ext_mid_res_data),
				.s_axis_mid_res_keep(m_axis_ext_mid_res_keep),
				.s_axis_mid_res_user({1'b0, m_axis_ext_mid_res_user}),
				.s_axis_mid_res_last(m_axis_ext_mid_res_last),
				.s_axis_mid_res_valid(m_axis_ext_mid_res_valid),
				.s_axis_mid_res_ready(m_axis_ext_mid_res_ready),
				
				.m_axis_fnl_res_data(s_axis_ext_fnl_res_data),
				.m_axis_fnl_res_keep(s_axis_ext_fnl_res_keep),
				.m_axis_fnl_res_user(s_axis_ext_fnl_res_user),
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
				
				.acmlt_aclk(acmlt_aclk),
				.acmlt_aresetn(acmlt_aresetn),
				.acmlt_aclken(acmlt_aclken),
				.acmlt_in_new_res(acmlt_in_new_res),
				.acmlt_in_org_mid_res(acmlt_in_org_mid_res),
				.acmlt_in_mask(acmlt_in_mask),
				.acmlt_in_first_item(acmlt_in_first_item),
				.acmlt_in_last_grp(acmlt_in_last_grp),
				.acmlt_in_last_res(acmlt_in_last_res),
				.acmlt_in_info_along(),
				.acmlt_in_valid(acmlt_in_valid),
				
				.acmlt_out_data(acmlt_out_data),
				.acmlt_out_mask(acmlt_out_mask),
				.acmlt_out_last_grp(acmlt_out_last_grp),
				.acmlt_out_last_res(acmlt_out_last_res),
				.acmlt_out_to_upd_mem(1'b1),
				.acmlt_out_valid(acmlt_out_valid)
			);
		end
	endgenerate
	
	/** 最终结果传输请求生成单元 **/
	// 子表面行信息(AXIS主机)
	wire[15:0] m_sub_row_msg_axis_data; // {输出通道号(16bit)}
	wire m_sub_row_msg_axis_last; // 整个输出特征图的最后1个子表面行(标志)
	wire m_sub_row_msg_axis_valid;
	wire m_sub_row_msg_axis_ready;
	// DMA命令(AXIS主机)
	wire[55:0] m_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[24:0] m_dma_cmd_axis_user; // {命令ID(24bit), 固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_dma_cmd_axis_valid;
	wire m_dma_cmd_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] fnl_res_trans_mul0_op_a; // 操作数A
	wire[23:0] fnl_res_trans_mul0_op_b; // 操作数B
	wire[3:0] fnl_res_trans_mul0_tid; // 操作ID
	wire fnl_res_trans_mul0_req;
	wire fnl_res_trans_mul0_grant;
	// [计算结果]
	wire[39:0] fnl_res_trans_mul0_res;
	wire[3:0] fnl_res_trans_mul0_oid;
	wire fnl_res_trans_mul0_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] fnl_res_trans_mul1_op_a; // 操作数A
	wire[23:0] fnl_res_trans_mul1_op_b; // 操作数B
	wire[3:0] fnl_res_trans_mul1_tid; // 操作ID
	wire fnl_res_trans_mul1_req;
	wire fnl_res_trans_mul1_grant;
	// [计算结果]
	wire[39:0] fnl_res_trans_mul1_res;
	wire[3:0] fnl_res_trans_mul1_oid;
	wire fnl_res_trans_mul1_ovld;
	// 乘法器(u16*u24)
	// [计算端口]
	wire[15:0] mul2_op_a; // 操作数A
	wire[23:0] mul2_op_b; // 操作数B
	wire mul2_ce; // 计算使能
	wire[39:0] mul2_res; // 计算结果
	// [延迟1clk的乘法器输入]
	reg[15:0] fnl_res_trans_shared_mul_op_a_d1;
	reg[23:0] fnl_res_trans_shared_mul_op_b_d1;
	reg[3:0] fnl_res_trans_shared_mul_tid_d1;
	reg fnl_res_trans_shared_mul_req_d1;
	// [延迟2clk的乘法器输入]
	reg[3:0] fnl_res_trans_shared_mul_tid_d2;
	reg fnl_res_trans_shared_mul_req_d2;
	
	assign m_dma_s2mm_cmd_axis_data = m_dma_cmd_axis_data;
	assign m_dma_s2mm_cmd_axis_user = m_dma_cmd_axis_user[0];
	assign m_dma_s2mm_cmd_axis_valid = m_dma_cmd_axis_valid;
	assign m_dma_cmd_axis_ready = m_dma_s2mm_cmd_axis_ready;
	
	assign mul2_op_a = fnl_res_trans_shared_mul_op_a_d1;
	assign mul2_op_b = fnl_res_trans_shared_mul_op_b_d1;
	assign mul2_ce = fnl_res_trans_shared_mul_req_d1;
	
	assign fnl_res_trans_mul0_grant = fnl_res_trans_mul0_req;
	assign fnl_res_trans_mul0_res = mul2_res;
	assign fnl_res_trans_mul0_oid = fnl_res_trans_shared_mul_tid_d2;
	assign fnl_res_trans_mul0_ovld = fnl_res_trans_shared_mul_req_d2;
	
	assign fnl_res_trans_mul1_grant = (~fnl_res_trans_mul0_req) & fnl_res_trans_mul1_req;
	assign fnl_res_trans_mul1_res = mul2_res;
	assign fnl_res_trans_mul1_oid = fnl_res_trans_shared_mul_tid_d2;
	assign fnl_res_trans_mul1_ovld = fnl_res_trans_shared_mul_req_d2;
	
	always @(posedge aclk)
	begin
		if(fnl_res_trans_mul0_req | fnl_res_trans_mul1_req)
			{
				fnl_res_trans_shared_mul_op_a_d1,
				fnl_res_trans_shared_mul_op_b_d1,
				fnl_res_trans_shared_mul_tid_d1
			} <= # SIM_DELAY 
				fnl_res_trans_mul0_req ? 
					{
						fnl_res_trans_mul0_op_a,
						fnl_res_trans_mul0_op_b,
						fnl_res_trans_mul0_tid
					}:
					{
						fnl_res_trans_mul1_op_a,
						fnl_res_trans_mul1_op_b,
						fnl_res_trans_mul1_tid
					};
	end
	
	always @(posedge aclk)
	begin
		if(fnl_res_trans_shared_mul_req_d1)
			fnl_res_trans_shared_mul_tid_d2 <= # SIM_DELAY fnl_res_trans_shared_mul_tid_d1;
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{fnl_res_trans_shared_mul_req_d2, fnl_res_trans_shared_mul_req_d1} <= 2'b00;
		else
			{fnl_res_trans_shared_mul_req_d2, fnl_res_trans_shared_mul_req_d1} <= # SIM_DELAY 
				{fnl_res_trans_shared_mul_req_d1, fnl_res_trans_mul0_req | fnl_res_trans_mul1_req};
	end
	
	fnl_res_trans_req_gen #(
		.ATOMIC_K(ATOMIC_K),
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
		.n_foreach_group(fnl_res_tr_req_gen_n_foreach_group),
		.en_send_sub_row_msg(1'b1),
		
		.blk_start(fnl_res_trans_blk_start),
		.blk_idle(fnl_res_trans_blk_idle),
		.blk_done(fnl_res_trans_blk_done),
		
		.m_sub_row_msg_axis_data(m_sub_row_msg_axis_data),
		.m_sub_row_msg_axis_last(m_sub_row_msg_axis_last),
		.m_sub_row_msg_axis_valid(m_sub_row_msg_axis_valid),
		.m_sub_row_msg_axis_ready(m_sub_row_msg_axis_ready),
		
		.m_dma_cmd_axis_data(m_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m_dma_cmd_axis_user),
		.m_dma_cmd_axis_valid(m_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m_dma_cmd_axis_ready),
		
		.mul0_op_a(fnl_res_trans_mul0_op_a),
		.mul0_op_b(fnl_res_trans_mul0_op_b),
		.mul0_tid(fnl_res_trans_mul0_tid),
		.mul0_req(fnl_res_trans_mul0_req),
		.mul0_grant(fnl_res_trans_mul0_grant),
		.mul0_res(fnl_res_trans_mul0_res),
		.mul0_oid(fnl_res_trans_mul0_oid),
		.mul0_ovld(fnl_res_trans_mul0_ovld),
		
		.mul1_op_a(fnl_res_trans_mul1_op_a),
		.mul1_op_b(fnl_res_trans_mul1_op_b),
		.mul1_tid(fnl_res_trans_mul1_tid),
		.mul1_req(fnl_res_trans_mul1_req),
		.mul1_grant(fnl_res_trans_mul1_grant),
		.mul1_res(fnl_res_trans_mul1_res),
		.mul1_oid(fnl_res_trans_mul1_oid),
		.mul1_ovld(fnl_res_trans_mul1_ovld)
	);
	
	/** BN与激活单元 **/
	// BN乘法器组
	wire bn_mul_clk;
	wire[BN_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_op_a; // 操作数A
	wire[BN_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_op_b; // 操作数B
	wire[BN_MUL_CE_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_ce; // 计算使能
	wire[BN_MUL_RES_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_res; // 计算结果
	// 泄露Relu乘法器组
	wire leaky_relu_mul_clk;
	wire[LEAKY_RELU_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_op_a; // 操作数A
	wire[LEAKY_RELU_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_op_b; // 操作数B
	wire[LEAKY_RELU_MUL_CE_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_ce; // 计算使能
	wire[LEAKY_RELU_MUL_RES_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_res; // 计算结果
	// BN参数MEM主接口
	wire bn_mem_clk_b;
	wire bn_mem_ren_b;
	wire[15:0] bn_mem_addr_b;
	wire[63:0] bn_mem_dout_b; // {参数B(32bit), 参数A(32bit)}
	// 处理结果fifo(MEM主接口)
	wire proc_res_fifo_mem_clk_a;
	wire proc_res_fifo_mem_wen_a;
	wire[8:0] proc_res_fifo_mem_addr_a;
	wire[BN_ACT_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_din_a;
	wire proc_res_fifo_mem_clk_b;
	wire proc_res_fifo_mem_ren_b;
	wire[8:0] proc_res_fifo_mem_addr_b;
	wire[BN_ACT_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_dout_b;
	// Sigmoid函数值查找表(MEM主接口)
	wire sigmoid_lut_mem_clk_a;
	wire[BN_ACT_PRL_N-1:0] sigmoid_lut_mem_ren_a;
	wire[12*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_addr_a;
	wire[16*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_dout_a;
	
	conv_bn_act_proc #(
		.BN_ACT_CLK_RATE(BN_ACT_CLK_RATE),
		.FP32_KEEP(1'b1),
		.ATOMIC_K(ATOMIC_K),
		.BN_ACT_PRL_N(BN_ACT_PRL_N),
		.INT16_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT32_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP32_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.SIM_DELAY(SIM_DELAY)
	)conv_bn_act_proc_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		.bn_act_aclk(bn_act_aclk),
		.bn_act_aresetn(bn_act_aresetn),
		.bn_act_aclken(1'b1),
		
		.en_bn_act_proc(en_bn_act_proc_dup),
		
		.calfmt(bn_act_calfmt),
		.use_bn_unit(bn_act_use_bn_unit),
		.act_func_type(bn_act_act_func_type),
		.bn_fixed_point_quat_accrc(bn_act_bn_fixed_point_quat_accrc),
		.bn_is_a_eq_1(bn_act_bn_is_a_eq_1),
		.bn_is_b_eq_0(bn_act_bn_is_b_eq_0),
		.is_in_const_mac_mode(1'b0),
		.param_a_in_const_mac_mode(32'hxxxxxxxx),
		.param_b_in_const_mac_mode(32'hxxxxxxxx),
		.leaky_relu_fixed_point_quat_accrc(bn_act_leaky_relu_fixed_point_quat_accrc),
		.leaky_relu_param_alpha(bn_act_leaky_relu_param_alpha),
		.sigmoid_fixed_point_quat_accrc(bn_act_sigmoid_fixed_point_quat_accrc),
		
		.s_sub_row_msg_axis_data(m_sub_row_msg_axis_data),
		.s_sub_row_msg_axis_last(m_sub_row_msg_axis_last),
		.s_sub_row_msg_axis_valid(m_sub_row_msg_axis_valid),
		.s_sub_row_msg_axis_ready(m_sub_row_msg_axis_ready),
		
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
		
		.bn_mem_clk_b(bn_mem_clk_b),
		.bn_mem_ren_b(bn_mem_ren_b),
		.bn_mem_addr_b(bn_mem_addr_b),
		.bn_mem_dout_b(bn_mem_dout_b),
		
		.proc_res_fifo_mem_clk_a(proc_res_fifo_mem_clk_a),
		.proc_res_fifo_mem_wen_a(proc_res_fifo_mem_wen_a),
		.proc_res_fifo_mem_addr_a(proc_res_fifo_mem_addr_a),
		.proc_res_fifo_mem_din_a(proc_res_fifo_mem_din_a),
		.proc_res_fifo_mem_clk_b(proc_res_fifo_mem_clk_b),
		.proc_res_fifo_mem_ren_b(proc_res_fifo_mem_ren_b),
		.proc_res_fifo_mem_addr_b(proc_res_fifo_mem_addr_b),
		.proc_res_fifo_mem_dout_b(proc_res_fifo_mem_dout_b),
		
		.mul0_clk(bn_mul_clk),
		.mul0_op_a(bn_mul_op_a),
		.mul0_op_b(bn_mul_op_b),
		.mul0_ce(bn_mul_ce),
		.mul0_res(bn_mul_res),
		
		.mul1_clk(leaky_relu_mul_clk),
		.mul1_op_a(leaky_relu_mul_op_a),
		.mul1_op_b(leaky_relu_mul_op_b),
		.mul1_ce(leaky_relu_mul_ce),
		.mul1_res(leaky_relu_mul_res),
		
		.sigmoid_lut_mem_clk_a(sigmoid_lut_mem_clk_a),
		.sigmoid_lut_mem_ren_a(sigmoid_lut_mem_ren_a),
		.sigmoid_lut_mem_addr_a(sigmoid_lut_mem_addr_a),
		.sigmoid_lut_mem_dout_a(sigmoid_lut_mem_dout_a)
	);
	
	/** 输出数据舍入单元组 **/
	out_round_group #(
		.ATOMIC_K(ATOMIC_K),
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
		.IN_ITEM_WIDTH(ATOMIC_K),
		.OUT_ITEM_WIDTH(S2MM_STREAM_DATA_WIDTH/(FP32_KEEP ? 32:16)),
		.DATA_WIDTH_FOREACH_ITEM(FP32_KEEP ? 32:16),
		.HAS_USER("false"),
		.USER_WIDTH(1),
		.EN_COLLECTOR_OUT_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)conv_final_data_collector_u(
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
	)mul_u16_u24_u1(
		.clk(aclk),
		
		.ce_s0_mul(mul2_ce),
		
		.op_a(mul2_op_a),
		.op_b(mul2_op_b),
		
		.res(mul2_res)
	);
	
	genvar bn_act_mul_i;
	generate
		for(bn_act_mul_i = 0;bn_act_mul_i < BN_ACT_PRL_N;bn_act_mul_i = bn_act_mul_i + 1)
		begin:leaky_relu_mul_blk
			signed_mul #(
				.op_a_width(INT16_SUPPORTED ? 32:25),
				.op_b_width(INT16_SUPPORTED ? 32:25),
				.output_width(INT16_SUPPORTED ? 64:50),
				.en_in_reg("false"),
				.en_out_reg("true"),
				.simulation_delay(SIM_DELAY)
			)leaky_relu_mul_u(
				.clk(leaky_relu_mul_clk),
				
				.ce_in_reg(1'b0),
				.ce_mul(leaky_relu_mul_ce[bn_act_mul_i*2+0]),
				.ce_out_reg(leaky_relu_mul_ce[bn_act_mul_i*2+1]),
				
				.op_a(leaky_relu_mul_op_a[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
				.op_b(leaky_relu_mul_op_b[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
				
				.res(leaky_relu_mul_res[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 64:50)-1:bn_act_mul_i*(INT16_SUPPORTED ? 64:50)])
			);
		end
		
		if(INT8_SUPPORTED)
		begin:case_bn_act_int16_supported
			for(bn_act_mul_i = 0;bn_act_mul_i < 4 * BN_ACT_PRL_N;bn_act_mul_i = bn_act_mul_i + 1)
			begin:bn_mul_blk_a
				signed_mul #(
					.op_a_width(18),
					.op_b_width(18),
					.output_width(36),
					.en_in_reg("false"),
					.en_out_reg("false"),
					.simulation_delay(SIM_DELAY)
				)bn_mul_u(
					.clk(bn_mul_clk),
					
					.ce_in_reg(1'b0),
					.ce_mul(bn_mul_ce[bn_act_mul_i]),
					.ce_out_reg(1'b0),
					
					.op_a(bn_mul_op_a[(bn_act_mul_i+1)*18-1:bn_act_mul_i*18]),
					.op_b(bn_mul_op_b[(bn_act_mul_i+1)*18-1:bn_act_mul_i*18]),
					
					.res(bn_mul_res[(bn_act_mul_i+1)*36-1:bn_act_mul_i*36])
				);
			end
		end
		else
		begin:case_bn_act_int16_not_supported
			for(bn_act_mul_i = 0;bn_act_mul_i < BN_ACT_PRL_N;bn_act_mul_i = bn_act_mul_i + 1)
			begin:bn_mul_blk_b
				signed_mul #(
					.op_a_width(INT16_SUPPORTED ? 32:25),
					.op_b_width(INT16_SUPPORTED ? 32:25),
					.output_width(INT16_SUPPORTED ? 64:50),
					.en_in_reg("true"),
					.en_out_reg("true"),
					.simulation_delay(SIM_DELAY)
				)bn_mul_u(
					.clk(bn_mul_clk),
					
					.ce_in_reg(bn_mul_ce[bn_act_mul_i*3+0]),
					.ce_mul(bn_mul_ce[bn_act_mul_i*3+1]),
					.ce_out_reg(bn_mul_ce[bn_act_mul_i*3+2]),
					
					.op_a(bn_mul_op_a[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
					.op_b(bn_mul_op_b[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
					
					.res(bn_mul_res[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 64:50)-1:bn_act_mul_i*(INT16_SUPPORTED ? 64:50)])
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
				.mem_width(ATOMIC_K*4*8+ATOMIC_K),
				.mem_depth(RBUF_DEPTH),
				.INIT_FILE("no_init"),
				.simulation_delay(SIM_DELAY)
			)mid_res_ram_u(
				.clk(mid_res_mem_clk_a),
				
				.wen_a(mid_res_mem_wen_a[mid_res_mem_i]),
				.addr_a(mid_res_mem_addr_a[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.din_a(mid_res_mem_din_a[(mid_res_mem_i+1)*(ATOMIC_K*4*8+ATOMIC_K)-1:mid_res_mem_i*(ATOMIC_K*4*8+ATOMIC_K)]),
				
				.ren_b(mid_res_mem_ren_b[mid_res_mem_i]),
				.addr_b(mid_res_mem_addr_b[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.dout_b(mid_res_mem_dout_b[(mid_res_mem_i+1)*(ATOMIC_K*4*8+ATOMIC_K)-1:mid_res_mem_i*(ATOMIC_K*4*8+ATOMIC_K)])
			);
		end
	endgenerate
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(LG_FMBUF_BUFFER_RID_WIDTH),
		.mem_depth(4096),
		.INIT_FILE("no_init"),
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
		.INIT_FILE("no_init"),
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
	
	bram_simple_dual_port_async #(
		.style("LOW_LATENCY"),
		.mem_width(BN_ACT_PROC_RES_FIFO_WIDTH),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)bn_act_proc_res_fifo_ram_u(
		.clk_a(proc_res_fifo_mem_clk_a),
		.clk_b(proc_res_fifo_mem_clk_b),
		
		.wen_a(proc_res_fifo_mem_wen_a),
		.addr_a(proc_res_fifo_mem_addr_a),
		.din_a(proc_res_fifo_mem_din_a),
		
		.ren_b(proc_res_fifo_mem_ren_b),
		.addr_b(proc_res_fifo_mem_addr_b),
		.dout_b(proc_res_fifo_mem_dout_b)
	);
	
	bram_true_dual_port_async #(
		.mem_width(64),
		.mem_depth(MAX_KERNAL_N),
		.INIT_FILE("no_init"),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("true"),
		.simulation_delay(SIM_DELAY)
	)bn_param_ram_u(
		.clk_a(bn_mem_clk_a),
		.clk_b(bn_mem_clk_b),
		
		.ena(bn_mem_en_a),
		.wea(bn_mem_wen_a),
		.addra(bn_mem_addr_a),
		.dina(bn_mem_din_a),
		.douta(bn_mem_dout_a),
		
		.enb(bn_mem_ren_b),
		.web(8'b0000_0000),
		.addrb(bn_mem_addr_b),
		.dinb(64'dx),
		.doutb(bn_mem_dout_b)
	);
	
	genvar sigmoid_lut_mem_i;
	generate
		for(sigmoid_lut_mem_i = 0;sigmoid_lut_mem_i < BN_ACT_PRL_N;sigmoid_lut_mem_i = sigmoid_lut_mem_i + 1)
		begin:sigmoid_lut_mem_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(16),
				.mem_depth(4096),
				.INIT_FILE(SIGMOID_LUT_MEM_INIT_FILE),
				.byte_write_mode("false"),
				.simulation_delay(SIM_DELAY)
			)sigmoid_lut_mem_u(
				.clk(sigmoid_lut_mem_clk_a),
				
				.en(sigmoid_lut_mem_ren_a[sigmoid_lut_mem_i]),
				.wen(1'b0),
				.addr(sigmoid_lut_mem_addr_a[12*(sigmoid_lut_mem_i+1)-1:12*sigmoid_lut_mem_i]),
				.din(),
				.dout(sigmoid_lut_mem_dout_a[16*(sigmoid_lut_mem_i+1)-1:16*sigmoid_lut_mem_i])
			);
		end
	endgenerate
	
endmodule
