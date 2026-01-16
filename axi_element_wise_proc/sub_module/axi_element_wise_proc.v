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
本模块: AXI-逐元素操作处理单元(顶层模块)

描述:
输入数据转换(FP16转FP32、U8/S8/U16/S16/U32/S32转FP32) -> 二次幂计算(操作数X ^ 2) -> 
	乘加计算(操作数A * 操作数X + 操作数B) -> 输出数据转换(FP32转S33) -> 
	舍入单元(S33转U8/S8/U16/S16/U32/S32、FP32转FP16)

注意：
需要外接2个DMA(MM2S)通道和1个DMA(S2MM)通道

可将乘法器的接口引出, 在SOC层面再连接, 以实现乘法器的共享

操作数A与操作数B不能同时为变量

协议:
AXI-Lite SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2026/01/15
********************************************************************/


module axi_element_wise_proc #(
	// 逐元素操作处理全局配置
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter integer MM2S_STREAM_DATA_WIDTH = 128, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 128, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer ELEMENT_WISE_PROC_PIPELINE_N = 4, // 逐元素操作处理流水线条数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer FU_CLK_RATE = 2, // 功能单元的时钟倍率(1 | 2 | 4 | 8)
	// 输入与输出项字节数配置
	parameter integer IN_STRM_WIDTH_1_BYTE_SUPPORTED = 1, // 是否支持输入流项位宽为1字节
	parameter integer IN_STRM_WIDTH_2_BYTE_SUPPORTED = 1, // 是否支持输入流项位宽为2字节
	parameter integer IN_STRM_WIDTH_4_BYTE_SUPPORTED = 1, // 是否支持输入流项位宽为4字节
	parameter integer OUT_STRM_WIDTH_1_BYTE_SUPPORTED = 1, // 是否支持输出流项位宽为1字节
	parameter integer OUT_STRM_WIDTH_2_BYTE_SUPPORTED = 1, // 是否支持输出流项位宽为2字节
	parameter integer OUT_STRM_WIDTH_4_BYTE_SUPPORTED = 1, // 是否支持输出流项位宽为4字节
	// 输入数据转换单元配置
	parameter integer EN_IN_DATA_CVT = 1, // 启用输入数据转换单元
	parameter integer IN_DATA_CVT_EN_ROUND = 1, // 是否需要进行四舍五入
	parameter integer IN_DATA_CVT_FP16_IN_DATA_SUPPORTED = 0, // 是否支持FP16输入数据格式
	parameter integer IN_DATA_CVT_S33_IN_DATA_SUPPORTED = 1, // 是否支持S33输入数据格式
	// 计算单元配置
	parameter integer EN_POW2_CAL_UNIT = 1, // 启用二次幂计算单元
	parameter integer EN_MAC_UNIT = 1, // 启用乘加计算单元
	parameter integer CAL_EN_ROUND = 1, // 是否需要进行四舍五入
	parameter integer CAL_INT16_SUPPORTED = 0, // 是否支持INT16运算数据格式
	parameter integer CAL_INT32_SUPPORTED = 0, // 是否支持INT32运算数据格式
	parameter integer CAL_FP32_SUPPORTED = 1, // 是否支持FP32运算数据格式
	// 输出数据转换单元配置
	parameter integer EN_OUT_DATA_CVT = 1, // 启用输出数据转换单元
	parameter integer OUT_DATA_CVT_EN_ROUND = 1, // 是否需要进行四舍五入
	parameter integer OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED = 1, // 是否支持S33输出数据格式
	// 舍入单元配置
	parameter integer EN_ROUND_UNIT = 1, // 启用舍入单元
	parameter integer ROUND_S33_ROUND_SUPPORTED = 1, // 是否支持S33数据的舍入
	parameter integer ROUND_FP32_ROUND_SUPPORTED = 1, // 是否支持FP32数据的舍入
	// 性能监测
	parameter integer EN_PERF_MON = 1, // 是否支持性能监测
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	// 处理时钟和复位
	input wire proc_aclk,
	input wire proc_aresetn,
	
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
	// DMA(S2MM方向)数据流(AXIS主机)
	output wire[S2MM_STREAM_DATA_WIDTH-1:0] m_dma_strm_axis_data,
	output wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_dma_strm_axis_keep,
	output wire m_dma_strm_axis_last,
	output wire m_dma_strm_axis_valid,
	input wire m_dma_strm_axis_ready
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
	// 有符号乘法器的位宽
	localparam integer MUL0_OP_WIDTH = (CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 32:16;
	localparam integer MUL0_CE_WIDTH = 3;
	localparam integer MUL0_RES_WIDTH = (CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 64:32;
	localparam integer MUL1_OP_WIDTH = CAL_INT16_SUPPORTED ? 4*18:(CAL_INT32_SUPPORTED ? 32:25);
	localparam integer MUL1_CE_WIDTH = CAL_INT16_SUPPORTED ? 4:3;
	localparam integer MUL1_RES_WIDTH = CAL_INT16_SUPPORTED ? 4*36:(CAL_INT32_SUPPORTED ? 64:50);
	
	/** 寄存器配置接口 **/
	// 控制/状态
	wire en_accelerator; // 使能加速器
	wire en_data_hub; // 使能数据枢纽
	wire en_proc_core; // 使能处理核心
	wire on_send_mm2s_0_cmd; // 发送0号MM2S通道的DMA命令
	wire on_send_mm2s_1_cmd; // 发送1号MM2S通道的DMA命令
	wire on_send_s2mm_cmd; // 发送S2MM通道的DMA命令
	wire mm2s_0_cmd_pending; // 等待0号MM2S通道的DMA命令传输完成(标志)
	wire mm2s_1_cmd_pending; // 等待1号MM2S通道的DMA命令传输完成(标志)
	wire s2mm_cmd_pending; // 等待S2MM通道的DMA命令传输完成(标志)
	// 运行时参数
	// [执行单元旁路]
	wire in_data_cvt_unit_bypass; // 旁路输入数据转换单元
	wire pow2_cell_bypass; // 旁路二次幂计算单元
	wire mac_cell_bypass; // 旁路乘加计算单元
	wire out_data_cvt_unit_bypass; // 旁路输出数据转换单元
	wire round_cell_bypass; // 旁路舍入单元
	// [缓存区基地址与大小]
	wire[31:0] op_x_buf_baseaddr; // 操作数X缓存区基地址
	wire[23:0] op_x_buf_len; // 操作数X缓存区大小
	wire[31:0] op_a_b_buf_baseaddr; // 操作数A或B缓存区基地址
	wire[23:0] op_a_b_buf_len; // 操作数A或B缓存区大小
	wire[31:0] res_buf_baseaddr; // 结果缓存区基地址
	wire[23:0] res_buf_len; // 结果缓存区大小
	// [数据格式]
	wire[2:0] in_data_fmt; // 输入数据格式
	wire[1:0] cal_calfmt; // 计算数据格式
	wire[2:0] out_data_fmt; // 输出数据格式
	// [定点数量化精度]
	wire[5:0] in_fixed_point_quat_accrc; // 输入定点数量化精度
	wire[4:0] op_x_fixed_point_quat_accrc; // 操作数X的定点数量化精度
	wire[4:0] op_a_fixed_point_quat_accrc; // 操作数A的定点数量化精度
	wire[5:0] s33_cvt_fixed_point_quat_accrc; // 转换为S33输出数据的定点数量化精度
	wire[4:0] round_in_fixed_point_quat_accrc; // 舍入单元输入定点数量化精度
	wire[4:0] round_out_fixed_point_quat_accrc; // 舍入单元输出定点数量化精度
	wire[4:0] fixed_point_rounding_digits; // 定点数舍入位数
	// [操作数A或B]
	wire is_op_a_eq_1; // 操作数A的实际值恒为1(标志)
	wire is_op_b_eq_0; // 操作数B的实际值恒为0(标志)
	wire is_op_a_const; // 操作数A为常量(标志)
	wire is_op_b_const; // 操作数B为常量(标志)
	wire[31:0] op_a_const_val; // 操作数A的常量值
	wire[31:0] op_b_const_val; // 操作数B的常量值
	
	reg_if_for_element_wise_proc #(
		.ACCELERATOR_ID(ACCELERATOR_ID),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.ELEMENT_WISE_PROC_PIPELINE_N(ELEMENT_WISE_PROC_PIPELINE_N),
		.IN_STRM_WIDTH_1_BYTE_SUPPORTED(IN_STRM_WIDTH_1_BYTE_SUPPORTED ? 1'b1:1'b0),
		.IN_STRM_WIDTH_2_BYTE_SUPPORTED(IN_STRM_WIDTH_2_BYTE_SUPPORTED ? 1'b1:1'b0),
		.IN_STRM_WIDTH_4_BYTE_SUPPORTED(IN_STRM_WIDTH_4_BYTE_SUPPORTED ? 1'b1:1'b0),
		.OUT_STRM_WIDTH_1_BYTE_SUPPORTED(OUT_STRM_WIDTH_1_BYTE_SUPPORTED ? 1'b1:1'b0),
		.OUT_STRM_WIDTH_2_BYTE_SUPPORTED(OUT_STRM_WIDTH_2_BYTE_SUPPORTED ? 1'b1:1'b0),
		.OUT_STRM_WIDTH_4_BYTE_SUPPORTED(OUT_STRM_WIDTH_4_BYTE_SUPPORTED ? 1'b1:1'b0),
		.EN_IN_DATA_CVT(EN_IN_DATA_CVT ? 1'b1:1'b0),
		.IN_DATA_CVT_FP16_IN_DATA_SUPPORTED(IN_DATA_CVT_FP16_IN_DATA_SUPPORTED ? 1'b1:1'b0),
		.IN_DATA_CVT_S33_IN_DATA_SUPPORTED(IN_DATA_CVT_S33_IN_DATA_SUPPORTED ? 1'b1:1'b0),
		.EN_POW2_CAL_UNIT(EN_POW2_CAL_UNIT ? 1'b1:1'b0),
		.EN_MAC_UNIT(EN_MAC_UNIT ? 1'b1:1'b0),
		.CAL_INT16_SUPPORTED(CAL_INT16_SUPPORTED ? 1'b1:1'b0),
		.CAL_INT32_SUPPORTED(CAL_INT32_SUPPORTED ? 1'b1:1'b0),
		.CAL_FP32_SUPPORTED(CAL_FP32_SUPPORTED ? 1'b1:1'b0),
		.EN_OUT_DATA_CVT(EN_OUT_DATA_CVT ? 1'b1:1'b0),
		.OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED(OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED ? 1'b1:1'b0),
		.EN_ROUND_UNIT(EN_ROUND_UNIT ? 1'b1:1'b0),
		.ROUND_S33_ROUND_SUPPORTED(ROUND_S33_ROUND_SUPPORTED ? 1'b1:1'b0),
		.ROUND_FP32_ROUND_SUPPORTED(ROUND_FP32_ROUND_SUPPORTED ? 1'b1:1'b0),
		.EN_PERF_MON(EN_PERF_MON ? 1'b1:1'b0),
		.SIM_DELAY(SIM_DELAY)
	)reg_if_for_element_wise_proc_u(
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
		.en_data_hub(en_data_hub),
		.en_proc_core(en_proc_core),
		.on_send_mm2s_0_cmd(on_send_mm2s_0_cmd),
		.on_send_mm2s_1_cmd(on_send_mm2s_1_cmd),
		.on_send_s2mm_cmd(on_send_s2mm_cmd),
		.mm2s_0_cmd_pending(mm2s_0_cmd_pending),
		.mm2s_1_cmd_pending(mm2s_1_cmd_pending),
		.s2mm_cmd_pending(s2mm_cmd_pending),
		
		.mm2s_0_cmd_done(mm2s_0_cmd_done),
		.mm2s_1_cmd_done(mm2s_1_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done),
		
		.in_data_cvt_unit_bypass(in_data_cvt_unit_bypass),
		.pow2_cell_bypass(pow2_cell_bypass),
		.mac_cell_bypass(mac_cell_bypass),
		.out_data_cvt_unit_bypass(out_data_cvt_unit_bypass),
		.round_cell_bypass(round_cell_bypass),
		.op_x_buf_baseaddr(op_x_buf_baseaddr),
		.op_x_buf_len(op_x_buf_len),
		.op_a_b_buf_baseaddr(op_a_b_buf_baseaddr),
		.op_a_b_buf_len(op_a_b_buf_len),
		.res_buf_baseaddr(res_buf_baseaddr),
		.res_buf_len(res_buf_len),
		.in_data_fmt(in_data_fmt),
		.cal_calfmt(cal_calfmt),
		.out_data_fmt(out_data_fmt),
		.in_fixed_point_quat_accrc(in_fixed_point_quat_accrc),
		.op_x_fixed_point_quat_accrc(op_x_fixed_point_quat_accrc),
		.op_a_fixed_point_quat_accrc(op_a_fixed_point_quat_accrc),
		.s33_cvt_fixed_point_quat_accrc(s33_cvt_fixed_point_quat_accrc),
		.round_in_fixed_point_quat_accrc(round_in_fixed_point_quat_accrc),
		.round_out_fixed_point_quat_accrc(round_out_fixed_point_quat_accrc),
		.fixed_point_rounding_digits(fixed_point_rounding_digits),
		.is_op_a_eq_1(is_op_a_eq_1),
		.is_op_b_eq_0(is_op_b_eq_0),
		.is_op_a_const(is_op_a_const),
		.is_op_b_const(is_op_b_const),
		.op_a_const_val(op_a_const_val),
		.op_b_const_val(op_b_const_val)
	);
	
	/** (逐元素操作处理)数据枢纽 **/
	// (逐元素操作处理)操作数流(AXIS主机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*64-1:0] m_elm_proc_i_axis_data; // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	wire[ELEMENT_WISE_PROC_PIPELINE_N*8-1:0] m_elm_proc_i_axis_keep;
	wire m_elm_proc_i_axis_last;
	wire m_elm_proc_i_axis_valid;
	wire m_elm_proc_i_axis_ready;
	// (逐元素操作处理)结果流(AXIS从机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] s_elm_proc_o_axis_data; // 每组数据(32位) -> {结果(32位)}
	wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] s_elm_proc_o_axis_keep;
	wire s_elm_proc_o_axis_last;
	wire s_elm_proc_o_axis_valid;
	wire s_elm_proc_o_axis_ready;
	
	element_wise_proc_data_hub #(
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.ELEMENT_WISE_PROC_PIPELINE_N(ELEMENT_WISE_PROC_PIPELINE_N),
		.IN_STRM_WIDTH_1_BYTE_SUPPORTED(IN_STRM_WIDTH_1_BYTE_SUPPORTED ? 1'b1:1'b0),
		.IN_STRM_WIDTH_2_BYTE_SUPPORTED(IN_STRM_WIDTH_2_BYTE_SUPPORTED ? 1'b1:1'b0),
		.IN_STRM_WIDTH_4_BYTE_SUPPORTED(IN_STRM_WIDTH_4_BYTE_SUPPORTED ? 1'b1:1'b0),
		.OUT_STRM_WIDTH_1_BYTE_SUPPORTED(OUT_STRM_WIDTH_1_BYTE_SUPPORTED ? 1'b1:1'b0),
		.OUT_STRM_WIDTH_2_BYTE_SUPPORTED(OUT_STRM_WIDTH_2_BYTE_SUPPORTED ? 1'b1:1'b0),
		.OUT_STRM_WIDTH_4_BYTE_SUPPORTED(OUT_STRM_WIDTH_4_BYTE_SUPPORTED ? 1'b1:1'b0),
		.SIM_DELAY(SIM_DELAY)
	)element_wise_proc_data_hub_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.en_data_hub(en_data_hub),
		.on_send_mm2s_0_cmd(on_send_mm2s_0_cmd),
		.on_send_mm2s_1_cmd(on_send_mm2s_1_cmd),
		.on_send_s2mm_cmd(on_send_s2mm_cmd),
		.mm2s_0_cmd_pending(mm2s_0_cmd_pending),
		.mm2s_1_cmd_pending(mm2s_1_cmd_pending),
		.s2mm_cmd_pending(s2mm_cmd_pending),
		
		.in_data_fmt(in_data_fmt),
		.out_data_fmt(out_data_fmt),
		.is_op_a_eq_1(is_op_a_eq_1),
		.is_op_b_eq_0(is_op_b_eq_0),
		.is_op_a_const(is_op_a_const),
		.is_op_b_const(is_op_b_const),
		.op_x_buf_baseaddr(op_x_buf_baseaddr),
		.op_x_buf_len(op_x_buf_len),
		.op_a_b_buf_baseaddr(op_a_b_buf_baseaddr),
		.op_a_b_buf_len(op_a_b_buf_len),
		.res_buf_baseaddr(res_buf_baseaddr),
		.res_buf_len(res_buf_len),
		
		.m_elm_proc_i_axis_data(m_elm_proc_i_axis_data),
		.m_elm_proc_i_axis_keep(m_elm_proc_i_axis_keep),
		.m_elm_proc_i_axis_last(m_elm_proc_i_axis_last),
		.m_elm_proc_i_axis_valid(m_elm_proc_i_axis_valid),
		.m_elm_proc_i_axis_ready(m_elm_proc_i_axis_ready),
		
		.s_elm_proc_o_axis_data(s_elm_proc_o_axis_data),
		.s_elm_proc_o_axis_keep(s_elm_proc_o_axis_keep),
		.s_elm_proc_o_axis_last(s_elm_proc_o_axis_last),
		.s_elm_proc_o_axis_valid(s_elm_proc_o_axis_valid),
		.s_elm_proc_o_axis_ready(s_elm_proc_o_axis_ready),
		
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
		
		.m_dma_strm_axis_data(m_dma_strm_axis_data),
		.m_dma_strm_axis_keep(m_dma_strm_axis_keep),
		.m_dma_strm_axis_last(m_dma_strm_axis_last),
		.m_dma_strm_axis_valid(m_dma_strm_axis_valid),
		.m_dma_strm_axis_ready(m_dma_strm_axis_ready)
	);
	
	/** (异步)逐元素操作处理核心 **/
	// (逐元素操作处理)操作数流(AXIS从机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*64-1:0] s_elm_proc_i_axis_data; // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	wire[ELEMENT_WISE_PROC_PIPELINE_N*8-1:0] s_elm_proc_i_axis_keep;
	wire s_elm_proc_i_axis_last;
	wire s_elm_proc_i_axis_valid;
	wire s_elm_proc_i_axis_ready;
	// (逐元素操作处理)结果流(AXIS主机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] m_elm_proc_o_axis_data; // 每组数据(32位) -> {结果(32位)}
	wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] m_elm_proc_o_axis_keep;
	wire m_elm_proc_o_axis_last;
	wire m_elm_proc_o_axis_valid;
	wire m_elm_proc_o_axis_ready;
	// 外部有符号乘法器#0
	wire mul0_clk;
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL0_OP_WIDTH)-1:0] mul0_op_a; // 操作数A
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL0_OP_WIDTH)-1:0] mul0_op_b; // 操作数B
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL0_CE_WIDTH)-1:0] mul0_ce; // 计算使能
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL0_RES_WIDTH)-1:0] mul0_res; // 计算结果
	// 外部有符号乘法器#1
	wire mul1_clk;
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL1_OP_WIDTH)-1:0] mul1_op_a; // 操作数A
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL1_OP_WIDTH)-1:0] mul1_op_b; // 操作数B
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL1_CE_WIDTH)-1:0] mul1_ce; // 计算使能
	wire[(ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE*MUL1_RES_WIDTH)-1:0] mul1_res; // 计算结果
	
	assign s_elm_proc_i_axis_data = m_elm_proc_i_axis_data;
	assign s_elm_proc_i_axis_keep = m_elm_proc_i_axis_keep;
	assign s_elm_proc_i_axis_last = m_elm_proc_i_axis_last;
	assign s_elm_proc_i_axis_valid = m_elm_proc_i_axis_valid;
	assign m_elm_proc_i_axis_ready = s_elm_proc_i_axis_ready;
	
	assign s_elm_proc_o_axis_data = m_elm_proc_o_axis_data;
	assign s_elm_proc_o_axis_keep = m_elm_proc_o_axis_keep;
	assign s_elm_proc_o_axis_last = m_elm_proc_o_axis_last;
	assign s_elm_proc_o_axis_valid = m_elm_proc_o_axis_valid;
	assign m_elm_proc_o_axis_ready = s_elm_proc_o_axis_ready;
	
	async_element_wise_proc #(
		.PROC_PIPELINE_N(ELEMENT_WISE_PROC_PIPELINE_N),
		.FU_CLK_RATE(FU_CLK_RATE),
		.IN_DATA_CVT_EN_ROUND(IN_DATA_CVT_EN_ROUND ? 1'b1:1'b0),
		.IN_DATA_CVT_FP16_IN_DATA_SUPPORTED(IN_DATA_CVT_FP16_IN_DATA_SUPPORTED ? 1'b1:1'b0),
		.IN_DATA_CVT_S33_IN_DATA_SUPPORTED(IN_DATA_CVT_S33_IN_DATA_SUPPORTED ? 1'b1:1'b0),
		.CAL_EN_ROUND(CAL_EN_ROUND ? 1'b1:1'b0),
		.CAL_INT16_SUPPORTED(CAL_INT16_SUPPORTED ? 1'b1:1'b0),
		.CAL_INT32_SUPPORTED(CAL_INT32_SUPPORTED ? 1'b1:1'b0),
		.CAL_FP32_SUPPORTED(CAL_FP32_SUPPORTED ? 1'b1:1'b0),
		.OUT_DATA_CVT_EN_ROUND(OUT_DATA_CVT_EN_ROUND ? 1'b1:1'b0),
		.OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED(OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED ? 1'b1:1'b0),
		.ROUND_S33_ROUND_SUPPORTED(ROUND_S33_ROUND_SUPPORTED ? 1'b1:1'b0),
		.ROUND_FP32_ROUND_SUPPORTED(ROUND_FP32_ROUND_SUPPORTED ? 1'b1:1'b0),
		.SIM_DELAY(SIM_DELAY)
	)async_element_wise_proc_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.fu_aclk(proc_aclk),
		.fu_aresetn(proc_aresetn),
		.fu_aclken(1'b1),
		
		.en_proc_core(en_proc_core),
		
		.in_data_cvt_unit_bypass(in_data_cvt_unit_bypass),
		.pow2_cell_bypass(pow2_cell_bypass),
		.mac_cell_bypass(mac_cell_bypass),
		.out_data_cvt_unit_bypass(out_data_cvt_unit_bypass),
		.round_cell_bypass(round_cell_bypass),
		
		.in_data_fmt(in_data_fmt),
		.cal_calfmt(cal_calfmt),
		.out_data_fmt(out_data_fmt),
		.in_fixed_point_quat_accrc(in_fixed_point_quat_accrc),
		.op_x_fixed_point_quat_accrc(op_x_fixed_point_quat_accrc),
		.op_a_fixed_point_quat_accrc(op_a_fixed_point_quat_accrc),
		.is_op_a_eq_1(is_op_a_eq_1),
		.is_op_b_eq_0(is_op_b_eq_0),
		.is_op_a_const(is_op_a_const),
		.is_op_b_const(is_op_b_const),
		.op_a_const_val(op_a_const_val),
		.op_b_const_val(op_b_const_val),
		.s33_cvt_fixed_point_quat_accrc(s33_cvt_fixed_point_quat_accrc),
		.round_in_fixed_point_quat_accrc(round_in_fixed_point_quat_accrc),
		.round_out_fixed_point_quat_accrc(round_out_fixed_point_quat_accrc),
		.fixed_point_rounding_digits(fixed_point_rounding_digits),
		
		.s_axis_data(s_elm_proc_i_axis_data),
		.s_axis_keep(s_elm_proc_i_axis_keep),
		.s_axis_last(s_elm_proc_i_axis_last),
		.s_axis_valid(s_elm_proc_i_axis_valid),
		.s_axis_ready(s_elm_proc_i_axis_ready),
		
		.m_axis_data(m_elm_proc_o_axis_data),
		.m_axis_keep(m_elm_proc_o_axis_keep),
		.m_axis_last(m_elm_proc_o_axis_last),
		.m_axis_valid(m_elm_proc_o_axis_valid),
		.m_axis_ready(m_elm_proc_o_axis_ready),
		
		.mul0_clk(mul0_clk),
		.mul0_op_a(mul0_op_a),
		.mul0_op_b(mul0_op_b),
		.mul0_ce(mul0_ce),
		.mul0_res(mul0_res),
		
		.mul1_clk(mul1_clk),
		.mul1_op_a(mul1_op_a),
		.mul1_op_b(mul1_op_b),
		.mul1_ce(mul1_ce),
		.mul1_res(mul1_res)
	);
	
	/** 乘法器 **/
	genvar pow2_mul_i;
	generate
		for(pow2_mul_i = 0;pow2_mul_i < ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE;pow2_mul_i = pow2_mul_i + 1)
		begin:pow2_mul_blk
			signed_mul #(
				.op_a_width(CAL_INT32_SUPPORTED ? 32:(CAL_FP32_SUPPORTED ? 25:16)),
				.op_b_width(CAL_INT32_SUPPORTED ? 32:(CAL_FP32_SUPPORTED ? 25:16)),
				.output_width(CAL_INT32_SUPPORTED ? 64:(CAL_FP32_SUPPORTED ? 50:32)),
				.en_in_reg("true"),
				.en_out_reg("true"),
				.simulation_delay(SIM_DELAY)
			)pow2_mul_u(
				.clk(mul0_clk),
				
				.ce_in_reg(mul0_ce[pow2_mul_i*3+0]),
				.ce_mul(mul0_ce[pow2_mul_i*3+1]),
				.ce_out_reg(mul0_ce[pow2_mul_i*3+2]),
				
				.op_a(
					mul0_op_a[
						pow2_mul_i*MUL0_OP_WIDTH+(CAL_INT32_SUPPORTED ? 32:(CAL_FP32_SUPPORTED ? 25:16))-1:
						pow2_mul_i*MUL0_OP_WIDTH
					]
				),
				.op_b(
					mul0_op_b[
						pow2_mul_i*MUL0_OP_WIDTH+(CAL_INT32_SUPPORTED ? 32:(CAL_FP32_SUPPORTED ? 25:16))-1:
						pow2_mul_i*MUL0_OP_WIDTH
					]
				),
				
				.res(
					mul0_res[
						pow2_mul_i*MUL0_RES_WIDTH+(CAL_INT32_SUPPORTED ? 64:(CAL_FP32_SUPPORTED ? 50:32))-1:
						pow2_mul_i*MUL0_RES_WIDTH
					]
				)
			);
		end
	endgenerate
	
	genvar mac_mul_i;
	generate
		if(CAL_INT16_SUPPORTED)
		begin:case_mac_int16_supported
			for(mac_mul_i = 0;mac_mul_i < 4 * ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE;mac_mul_i = mac_mul_i + 1)
			begin:mac_mul_blk_a
				signed_mul #(
					.op_a_width(18),
					.op_b_width(18),
					.output_width(36),
					.en_in_reg("false"),
					.en_out_reg("false"),
					.simulation_delay(SIM_DELAY)
				)mac_mul_u(
					.clk(mul1_clk),
					
					.ce_in_reg(1'b0),
					.ce_mul(mul1_ce[mac_mul_i]),
					.ce_out_reg(1'b0),
					
					.op_a(mul1_op_a[(mac_mul_i+1)*18-1:mac_mul_i*18]),
					.op_b(mul1_op_b[(mac_mul_i+1)*18-1:mac_mul_i*18]),
					
					.res(mul1_res[(mac_mul_i+1)*36-1:mac_mul_i*36])
				);
			end
		end
		else
		begin:case_mac_int16_not_supported
			for(mac_mul_i = 0;mac_mul_i < ELEMENT_WISE_PROC_PIPELINE_N/FU_CLK_RATE;mac_mul_i = mac_mul_i + 1)
			begin:mac_mul_blk_b
				signed_mul #(
					.op_a_width(MUL1_OP_WIDTH),
					.op_b_width(MUL1_OP_WIDTH),
					.output_width(MUL1_RES_WIDTH),
					.en_in_reg("true"),
					.en_out_reg("true"),
					.simulation_delay(SIM_DELAY)
				)mac_mul_u(
					.clk(mul1_clk),
					
					.ce_in_reg(mul1_ce[mac_mul_i*3+0]),
					.ce_mul(mul1_ce[mac_mul_i*3+1]),
					.ce_out_reg(mul1_ce[mac_mul_i*3+2]),
					
					.op_a(mul1_op_a[(mac_mul_i+1)*MUL1_OP_WIDTH-1:mac_mul_i*MUL1_OP_WIDTH]),
					.op_b(mul1_op_b[(mac_mul_i+1)*MUL1_OP_WIDTH-1:mac_mul_i*MUL1_OP_WIDTH]),
					
					.res(mul1_res[(mac_mul_i+1)*MUL1_RES_WIDTH-1:mac_mul_i*MUL1_RES_WIDTH])
				);
			end
		end
	endgenerate
	
endmodule
