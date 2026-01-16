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
本模块: (逐元素操作处理)数据枢纽

描述:
产生0号MM2S通道、1号MM2S通道、S2MM通道的DMA传输命令
从0号MM2S通道、1号MM2S通道的数据流生成(逐元素操作处理)操作数流
从(逐元素操作处理)结果流生成S2MM通道的数据流

操作数与结果位宽 = 8/16/32

处理结果收集器的输入项数 = 逐元素操作处理流水线条数(ELEMENT_WISE_PROC_PIPELINE_N) * 4 / 支持的最小的输出流项字节数
处理结果收集器的项位宽 = 支持的最小的输出流项字节数 * 8

注意:
仅在操作数A或B不是常量时, 可以发送1号MM2S通道的DMA传输命令

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2026/01/14
********************************************************************/


module element_wise_proc_data_hub #(
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer ELEMENT_WISE_PROC_PIPELINE_N = 4, // 逐元素操作处理流水线条数(1 | 2 | 4 | 8 | 16 | 32)
	parameter IN_STRM_WIDTH_1_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为1字节
	parameter IN_STRM_WIDTH_2_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为2字节
	parameter IN_STRM_WIDTH_4_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为4字节
	parameter OUT_STRM_WIDTH_1_BYTE_SUPPORTED = 1'b1, // 是否支持输出流项位宽为1字节
	parameter OUT_STRM_WIDTH_2_BYTE_SUPPORTED = 1'b1, // 是否支持输出流项位宽为2字节
	parameter OUT_STRM_WIDTH_4_BYTE_SUPPORTED = 1'b1, // 是否支持输出流项位宽为4字节
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 控制信号
	input wire en_data_hub, // 使能数据枢纽
	input wire on_send_mm2s_0_cmd, // 发送0号MM2S通道的DMA命令
	input wire on_send_mm2s_1_cmd, // 发送1号MM2S通道的DMA命令
	input wire on_send_s2mm_cmd, // 发送S2MM通道的DMA命令
	output wire mm2s_0_cmd_pending, // 等待0号MM2S通道的DMA命令传输完成(标志)
	output wire mm2s_1_cmd_pending, // 等待1号MM2S通道的DMA命令传输完成(标志)
	output wire s2mm_cmd_pending, // 等待S2MM通道的DMA命令传输完成(标志)
	
	// 运行时参数
	input wire[2:0] in_data_fmt, // 输入数据格式
	input wire[2:0] out_data_fmt, // 输出数据格式
	input wire is_op_a_eq_1, // 操作数A的实际值恒为1(标志)
	input wire is_op_b_eq_0, // 操作数B的实际值恒为0(标志)
	input wire is_op_a_const, // 操作数A为常量(标志)
	input wire is_op_b_const, // 操作数B为常量(标志)
	input wire[31:0] op_x_buf_baseaddr, // 操作数X缓存区基地址
	input wire[23:0] op_x_buf_len, // 操作数X缓存区大小
	input wire[31:0] op_a_b_buf_baseaddr, // 操作数A或B缓存区基地址
	input wire[23:0] op_a_b_buf_len, // 操作数A或B缓存区大小
	input wire[31:0] res_buf_baseaddr, // 结果缓存区基地址
	input wire[23:0] res_buf_len, // 结果缓存区大小
	
	// (逐元素操作处理)操作数流(AXIS主机)
	output wire[ELEMENT_WISE_PROC_PIPELINE_N*64-1:0] m_elm_proc_i_axis_data, // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	output wire[ELEMENT_WISE_PROC_PIPELINE_N*8-1:0] m_elm_proc_i_axis_keep,
	output wire m_elm_proc_i_axis_last,
	output wire m_elm_proc_i_axis_valid,
	input wire m_elm_proc_i_axis_ready,
	
	// (逐元素操作处理)结果流(AXIS从机)
	input wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] s_elm_proc_o_axis_data, // 每组数据(32位) -> {结果(32位)}
	input wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] s_elm_proc_o_axis_keep,
	input wire s_elm_proc_o_axis_last,
	input wire s_elm_proc_o_axis_valid,
	output wire s_elm_proc_o_axis_ready,
	
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
	
	/** 常量 **/
	// 输入数据格式的编码
	localparam IN_DATA_FMT_U8 = 3'b000;
	localparam IN_DATA_FMT_S8 = 3'b001;
	localparam IN_DATA_FMT_U16 = 3'b010;
	localparam IN_DATA_FMT_S16 = 3'b011;
	localparam IN_DATA_FMT_U32 = 3'b100;
	localparam IN_DATA_FMT_S32 = 3'b101;
	localparam IN_DATA_FMT_FP16 = 3'b110;
	localparam IN_DATA_FMT_NONE = 3'b111;
	// 输出数据格式的编码
	localparam OUT_DATA_FMT_U8 = 3'b000;
	localparam OUT_DATA_FMT_S8 = 3'b001;
	localparam OUT_DATA_FMT_U16 = 3'b010;
	localparam OUT_DATA_FMT_S16 = 3'b011;
	localparam OUT_DATA_FMT_U32 = 3'b100;
	localparam OUT_DATA_FMT_S32 = 3'b101;
	localparam OUT_DATA_FMT_FP16 = 3'b110;
	localparam OUT_DATA_FMT_NONE = 3'b111;
	
	/** DMA传输命令发送 **/
	reg mm2s_0_cmd_pending_r; // 等待0号MM2S通道的DMA命令传输完成(标志)
	reg mm2s_1_cmd_pending_r; // 等待1号MM2S通道的DMA命令传输完成(标志)
	reg s2mm_cmd_pending_r; // 等待S2MM通道的DMA命令传输完成(标志)
	
	assign m0_dma_cmd_axis_data = {
		op_x_buf_len,
		op_x_buf_baseaddr
	};
	assign m0_dma_cmd_axis_user = 1'b0;
	assign m0_dma_cmd_axis_last = 1'b1;
	assign m0_dma_cmd_axis_valid = en_data_hub & mm2s_0_cmd_pending_r;
	
	assign m1_dma_cmd_axis_data = {
		op_a_b_buf_len,
		op_a_b_buf_baseaddr
	};
	assign m1_dma_cmd_axis_user = 1'b0;
	assign m1_dma_cmd_axis_last = 1'b1;
	assign m1_dma_cmd_axis_valid = en_data_hub & mm2s_1_cmd_pending_r;
	
	assign m_dma_s2mm_cmd_axis_data = {
		res_buf_len,
		res_buf_baseaddr
	};
	assign m_dma_s2mm_cmd_axis_user = 1'b0;
	assign m_dma_s2mm_cmd_axis_valid = en_data_hub & s2mm_cmd_pending_r;
	
	assign mm2s_0_cmd_pending = mm2s_0_cmd_pending_r;
	assign mm2s_1_cmd_pending = mm2s_1_cmd_pending_r;
	assign s2mm_cmd_pending = s2mm_cmd_pending_r;
	
	// 等待0号MM2S通道的DMA命令传输完成(标志)
	always @(posedge aclk)
	begin
		if(~en_data_hub)
			mm2s_0_cmd_pending_r <= 1'b0;
		else if(
			mm2s_0_cmd_pending_r ? 
				(m0_dma_cmd_axis_valid & m0_dma_cmd_axis_ready):
				on_send_mm2s_0_cmd
		)
			mm2s_0_cmd_pending_r <= # SIM_DELAY ~mm2s_0_cmd_pending_r;
	end
	// 等待1号MM2S通道的DMA命令传输完成(标志)
	always @(posedge aclk)
	begin
		if(~en_data_hub)
			mm2s_1_cmd_pending_r <= 1'b0;
		else if(
			mm2s_1_cmd_pending_r ? 
				(m1_dma_cmd_axis_valid & m1_dma_cmd_axis_ready):
				(
					on_send_mm2s_1_cmd & 
					(~((is_op_a_eq_1 | is_op_a_const) & (is_op_b_eq_0 | is_op_b_const)))
				)
		)
			mm2s_1_cmd_pending_r <= # SIM_DELAY ~mm2s_1_cmd_pending_r;
	end
	// 等待S2MM通道的DMA命令传输完成(标志)
	always @(posedge aclk)
	begin
		if(~en_data_hub)
			s2mm_cmd_pending_r <= 1'b0;
		else if(
			s2mm_cmd_pending_r ? 
				(m_dma_s2mm_cmd_axis_valid & m_dma_s2mm_cmd_axis_ready):
				on_send_s2mm_cmd
		)
			s2mm_cmd_pending_r <= # SIM_DELAY ~s2mm_cmd_pending_r;
	end
	
	/**
	生成(逐元素操作处理)操作数流
	
	操作数位宽 = 8/16/32
	
	DMA(MM2S方向)数据流#0 -------------操作数X流--------------|
	                                                          |-------> (逐元素操作处理)操作数流
	DMA(MM2S方向)数据流#1 --------操作数A或B流(若存在)--------|
	**/
	// 总线操作数X数据流(AXIS从机)
	wire[MM2S_STREAM_DATA_WIDTH-1:0] s_bus_mm2s_op_x_axis_data;
	wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s_bus_mm2s_op_x_axis_keep;
	wire s_bus_mm2s_op_x_axis_last;
	wire s_bus_mm2s_op_x_axis_valid;
	wire s_bus_mm2s_op_x_axis_ready;
	// 总线操作数A或B数据流(AXIS从机)
	wire[MM2S_STREAM_DATA_WIDTH-1:0] s_bus_mm2s_op_a_b_axis_data;
	wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s_bus_mm2s_op_a_b_axis_keep;
	wire s_bus_mm2s_op_a_b_axis_last;
	wire s_bus_mm2s_op_a_b_axis_valid;
	wire s_bus_mm2s_op_a_b_axis_ready;
	// (逐元素操作处理)操作数X输入流(AXIS主机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] m_elm_proc_i_op_x_axis_data;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] m_elm_proc_i_op_x_axis_keep;
	wire m_elm_proc_i_op_x_axis_last;
	wire m_elm_proc_i_op_x_axis_valid;
	wire m_elm_proc_i_op_x_axis_ready;
	// (逐元素操作处理)操作数A或B输入流(AXIS主机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] m_elm_proc_i_op_a_b_axis_data;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] m_elm_proc_i_op_a_b_axis_keep;
	wire m_elm_proc_i_op_a_b_axis_last;
	wire m_elm_proc_i_op_a_b_axis_valid;
	wire m_elm_proc_i_op_a_b_axis_ready;
	// (逐元素操作处理)操作数流寄存器片输入(AXIS从机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*64-1:0] s_elm_proc_i_reg_axis_data; // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	wire[ELEMENT_WISE_PROC_PIPELINE_N*8-1:0] s_elm_proc_i_reg_axis_keep;
	wire s_elm_proc_i_reg_axis_last;
	wire s_elm_proc_i_reg_axis_valid;
	wire s_elm_proc_i_reg_axis_ready;
	// (逐元素操作处理)操作数流寄存器片输出(AXIS主机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*64-1:0] m_elm_proc_i_reg_axis_data; // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	wire[ELEMENT_WISE_PROC_PIPELINE_N*8-1:0] m_elm_proc_i_reg_axis_keep;
	wire m_elm_proc_i_reg_axis_last;
	wire m_elm_proc_i_reg_axis_valid;
	wire m_elm_proc_i_reg_axis_ready;
	
	assign m_elm_proc_i_axis_data = m_elm_proc_i_reg_axis_data;
	assign m_elm_proc_i_axis_keep = m_elm_proc_i_reg_axis_keep;
	assign m_elm_proc_i_axis_last = m_elm_proc_i_reg_axis_last;
	assign m_elm_proc_i_axis_valid = m_elm_proc_i_reg_axis_valid;
	assign m_elm_proc_i_reg_axis_ready = m_elm_proc_i_axis_ready;
	
	assign s_bus_mm2s_op_x_axis_data = s0_dma_strm_axis_data;
	assign s_bus_mm2s_op_x_axis_keep = s0_dma_strm_axis_keep;
	assign s_bus_mm2s_op_x_axis_last = s0_dma_strm_axis_last;
	assign s_bus_mm2s_op_x_axis_valid = s0_dma_strm_axis_valid;
	assign s0_dma_strm_axis_ready = s_bus_mm2s_op_x_axis_ready;
	
	assign s_bus_mm2s_op_a_b_axis_data = s1_dma_strm_axis_data;
	assign s_bus_mm2s_op_a_b_axis_keep = s1_dma_strm_axis_keep;
	assign s_bus_mm2s_op_a_b_axis_last = s1_dma_strm_axis_last;
	assign s_bus_mm2s_op_a_b_axis_valid = 
		(~((is_op_a_eq_1 | is_op_a_const) & (is_op_b_eq_0 | is_op_b_const))) & 
		s1_dma_strm_axis_valid;
	assign s1_dma_strm_axis_ready = 
		((is_op_a_eq_1 | is_op_a_const) & (is_op_b_eq_0 | is_op_b_const)) | 
		s_bus_mm2s_op_a_b_axis_ready;
	
	genvar in_ele_i;
	generate
		for(in_ele_i = 0;in_ele_i < ELEMENT_WISE_PROC_PIPELINE_N;in_ele_i = in_ele_i + 1)
		begin:in_ele_blk
			assign s_elm_proc_i_reg_axis_data[(in_ele_i+1)*64-1:in_ele_i*64] = 
				{
					m_elm_proc_i_op_a_b_axis_data[(in_ele_i+1)*32-1:in_ele_i*32],
					m_elm_proc_i_op_x_axis_data[(in_ele_i+1)*32-1:in_ele_i*32]
				};
			assign s_elm_proc_i_reg_axis_keep[(in_ele_i+1)*8-1:in_ele_i*8] = 
				{
					m_elm_proc_i_op_a_b_axis_keep[(in_ele_i+1)*4-1:in_ele_i*4],
					m_elm_proc_i_op_x_axis_keep[(in_ele_i+1)*4-1:in_ele_i*4]
				};
		end
	endgenerate
	
	assign s_elm_proc_i_reg_axis_last = m_elm_proc_i_op_x_axis_last;
	assign s_elm_proc_i_reg_axis_valid = 
		m_elm_proc_i_op_x_axis_valid & 
		(
			((is_op_a_eq_1 | is_op_a_const) & (is_op_b_eq_0 | is_op_b_const)) | 
			m_elm_proc_i_op_a_b_axis_valid
		);
	assign m_elm_proc_i_op_x_axis_ready = 
		s_elm_proc_i_reg_axis_ready & 
		(
			((is_op_a_eq_1 | is_op_a_const) & (is_op_b_eq_0 | is_op_b_const)) | 
			m_elm_proc_i_op_a_b_axis_valid
		);
	assign m_elm_proc_i_op_a_b_axis_ready = 
		((is_op_a_eq_1 | is_op_a_const) & (is_op_b_eq_0 | is_op_b_const)) | 
		(
			s_elm_proc_i_reg_axis_ready & 
			m_elm_proc_i_op_x_axis_valid
		);
	
	element_wise_proc_multi_width_in_strm_gen #(
		.BUS_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.ELEMENT_WISE_PROC_PIPELINE_N(ELEMENT_WISE_PROC_PIPELINE_N),
		.IN_STRM_WIDTH_1_BYTE_SUPPORTED(IN_STRM_WIDTH_1_BYTE_SUPPORTED),
		.IN_STRM_WIDTH_2_BYTE_SUPPORTED(IN_STRM_WIDTH_2_BYTE_SUPPORTED),
		.IN_STRM_WIDTH_4_BYTE_SUPPORTED(IN_STRM_WIDTH_4_BYTE_SUPPORTED),
		.SIM_DELAY(SIM_DELAY)
	)elm_proc_i_op_x_strm_gen(
		.aclk(aclk),
		.aclken(aclken),
		
		.en_in_strm_gen(en_data_hub),
		
		.in_data_fmt(in_data_fmt),
		
		.s_axis_data(s_bus_mm2s_op_x_axis_data),
		.s_axis_keep(s_bus_mm2s_op_x_axis_keep),
		.s_axis_last(s_bus_mm2s_op_x_axis_last),
		.s_axis_valid(s_bus_mm2s_op_x_axis_valid),
		.s_axis_ready(s_bus_mm2s_op_x_axis_ready),
		
		.m_axis_data(m_elm_proc_i_op_x_axis_data),
		.m_axis_keep(m_elm_proc_i_op_x_axis_keep),
		.m_axis_last(m_elm_proc_i_op_x_axis_last),
		.m_axis_valid(m_elm_proc_i_op_x_axis_valid),
		.m_axis_ready(m_elm_proc_i_op_x_axis_ready)
	);
	
	element_wise_proc_multi_width_in_strm_gen #(
		.BUS_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.ELEMENT_WISE_PROC_PIPELINE_N(ELEMENT_WISE_PROC_PIPELINE_N),
		.IN_STRM_WIDTH_1_BYTE_SUPPORTED(IN_STRM_WIDTH_1_BYTE_SUPPORTED),
		.IN_STRM_WIDTH_2_BYTE_SUPPORTED(IN_STRM_WIDTH_2_BYTE_SUPPORTED),
		.IN_STRM_WIDTH_4_BYTE_SUPPORTED(IN_STRM_WIDTH_4_BYTE_SUPPORTED),
		.SIM_DELAY(SIM_DELAY)
	)elm_proc_i_op_a_b_strm_gen(
		.aclk(aclk),
		.aclken(aclken),
		
		.en_in_strm_gen(en_data_hub),
		
		.in_data_fmt(in_data_fmt),
		
		.s_axis_data(s_bus_mm2s_op_a_b_axis_data),
		.s_axis_keep(s_bus_mm2s_op_a_b_axis_keep),
		.s_axis_last(s_bus_mm2s_op_a_b_axis_last),
		.s_axis_valid(s_bus_mm2s_op_a_b_axis_valid),
		.s_axis_ready(s_bus_mm2s_op_a_b_axis_ready),
		
		.m_axis_data(m_elm_proc_i_op_a_b_axis_data),
		.m_axis_keep(m_elm_proc_i_op_a_b_axis_keep),
		.m_axis_last(m_elm_proc_i_op_a_b_axis_last),
		.m_axis_valid(m_elm_proc_i_op_a_b_axis_valid),
		.m_axis_ready(m_elm_proc_i_op_a_b_axis_ready)
	);
	
	axis_reg_slice #(
		.data_width(ELEMENT_WISE_PROC_PIPELINE_N*64),
		.user_width(1),
		.forward_registered("true"),
		.back_registered("false"),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)elm_proc_i_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s_elm_proc_i_reg_axis_data),
		.s_axis_keep(s_elm_proc_i_reg_axis_keep),
		.s_axis_user(1'bx),
		.s_axis_last(s_elm_proc_i_reg_axis_last),
		.s_axis_valid(s_elm_proc_i_reg_axis_valid),
		.s_axis_ready(s_elm_proc_i_reg_axis_ready),
		
		.m_axis_data(m_elm_proc_i_reg_axis_data),
		.m_axis_keep(m_elm_proc_i_reg_axis_keep),
		.m_axis_user(),
		.m_axis_last(m_elm_proc_i_reg_axis_last),
		.m_axis_valid(m_elm_proc_i_reg_axis_valid),
		.m_axis_ready(m_elm_proc_i_reg_axis_ready)
	);
	
	/**
	生成(逐元素操作处理)结果流
	
	结果位宽 = 8/16/32
	**/
	// 收集器输入(AXIS从机)
	wire[ELEMENT_WISE_PROC_PIPELINE_N*8-1:0] s_collector_axis_data_1B;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*16-1:0] s_collector_axis_data_2B;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] s_collector_axis_data_4B;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] s_collector_axis_data;
	wire[ELEMENT_WISE_PROC_PIPELINE_N-1:0] s_collector_axis_keep_1B;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*2-1:0] s_collector_axis_keep_2B;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] s_collector_axis_keep_4B;
	wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] s_collector_axis_keep;
	wire s_collector_axis_last;
	wire s_collector_axis_valid;
	wire s_collector_axis_ready;
	// 收集器输出(AXIS主机)
	wire[S2MM_STREAM_DATA_WIDTH-1:0] m_collector_axis_data;
	wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_collector_axis_keep;
	wire m_collector_axis_last;
	wire m_collector_axis_valid;
	wire m_collector_axis_ready;
	
	assign s_collector_axis_data = 
		(
			{
				(ELEMENT_WISE_PROC_PIPELINE_N*32){
					OUT_STRM_WIDTH_1_BYTE_SUPPORTED & 
					(
						(out_data_fmt == OUT_DATA_FMT_U8) | 
						(out_data_fmt == OUT_DATA_FMT_S8)
					)
				}
			} & {{(ELEMENT_WISE_PROC_PIPELINE_N*24){1'bx}}, s_collector_axis_data_1B}
		) | 
		(
			{
				(ELEMENT_WISE_PROC_PIPELINE_N*32){
					OUT_STRM_WIDTH_2_BYTE_SUPPORTED & 
					(
						(out_data_fmt == OUT_DATA_FMT_U16) | 
						(out_data_fmt == OUT_DATA_FMT_S16) | 
						(out_data_fmt == OUT_DATA_FMT_FP16)
					)
				}
			} & {{(ELEMENT_WISE_PROC_PIPELINE_N*16){1'bx}}, s_collector_axis_data_2B}
		) | 
		(
			{
				(ELEMENT_WISE_PROC_PIPELINE_N*32){
					OUT_STRM_WIDTH_4_BYTE_SUPPORTED & 
					(
						(out_data_fmt == OUT_DATA_FMT_U32) | 
						(out_data_fmt == OUT_DATA_FMT_S32) | 
						(out_data_fmt == OUT_DATA_FMT_NONE)
					)
				}
			} & {s_collector_axis_data_4B}
		);
	assign s_collector_axis_keep = 
		(
			{
				(ELEMENT_WISE_PROC_PIPELINE_N*4){
					OUT_STRM_WIDTH_1_BYTE_SUPPORTED & 
					(
						(out_data_fmt == OUT_DATA_FMT_U8) | 
						(out_data_fmt == OUT_DATA_FMT_S8)
					)
				}
			} & (s_collector_axis_keep_1B | {(ELEMENT_WISE_PROC_PIPELINE_N*4){1'b0}})
		) | 
		(
			{
				(ELEMENT_WISE_PROC_PIPELINE_N*4){
					OUT_STRM_WIDTH_2_BYTE_SUPPORTED & 
					(
						(out_data_fmt == OUT_DATA_FMT_U16) | 
						(out_data_fmt == OUT_DATA_FMT_S16) | 
						(out_data_fmt == OUT_DATA_FMT_FP16)
					)
				}
			} & (s_collector_axis_keep_2B | {(ELEMENT_WISE_PROC_PIPELINE_N*4){1'b0}})
		) | 
		(
			{
				(ELEMENT_WISE_PROC_PIPELINE_N*4){
					OUT_STRM_WIDTH_4_BYTE_SUPPORTED & 
					(
						(out_data_fmt == OUT_DATA_FMT_U32) | 
						(out_data_fmt == OUT_DATA_FMT_S32) | 
						(out_data_fmt == OUT_DATA_FMT_NONE)
					)
				}
			} & s_collector_axis_keep_4B
		);
	assign s_collector_axis_last = s_elm_proc_o_axis_last;
	assign s_collector_axis_valid = s_elm_proc_o_axis_valid;
	assign s_elm_proc_o_axis_ready = s_collector_axis_ready;
	
	assign m_dma_strm_axis_data = m_collector_axis_data;
	assign m_dma_strm_axis_keep = m_collector_axis_keep;
	assign m_dma_strm_axis_last = m_collector_axis_last;
	assign m_dma_strm_axis_valid = m_collector_axis_valid;
	assign m_collector_axis_ready = m_dma_strm_axis_ready;
	
	genvar out_ele_i;
	generate
		for(out_ele_i = 0;out_ele_i < ELEMENT_WISE_PROC_PIPELINE_N;out_ele_i = out_ele_i + 1)
		begin:out_ele_blk
			assign s_collector_axis_data_1B[(out_ele_i+1)*8-1:out_ele_i*8] = 
				s_elm_proc_o_axis_data[out_ele_i*32+7:out_ele_i*32];
			assign s_collector_axis_data_2B[(out_ele_i+1)*16-1:out_ele_i*16] = 
				s_elm_proc_o_axis_data[out_ele_i*32+15:out_ele_i*32];
			assign s_collector_axis_data_4B[(out_ele_i+1)*32-1:out_ele_i*32] = 
				s_elm_proc_o_axis_data[out_ele_i*32+31:out_ele_i*32];
			
			assign s_collector_axis_keep_1B[out_ele_i] = s_elm_proc_o_axis_keep[out_ele_i*4];
			assign s_collector_axis_keep_2B[out_ele_i*2+1:out_ele_i*2] = {2{s_elm_proc_o_axis_keep[out_ele_i*4]}};
			assign s_collector_axis_keep_4B[out_ele_i*4+3:out_ele_i*4] = {4{s_elm_proc_o_axis_keep[out_ele_i*4]}};
		end
	endgenerate
	
	conv_final_data_collector #(
		.IN_ITEM_WIDTH(
			ELEMENT_WISE_PROC_PIPELINE_N * 
			(
				OUT_STRM_WIDTH_1_BYTE_SUPPORTED ? 
					4:
					(
						OUT_STRM_WIDTH_2_BYTE_SUPPORTED ? 
							2:
							1
					)
			)
		),
		.OUT_ITEM_WIDTH(
			S2MM_STREAM_DATA_WIDTH / 
			(
				OUT_STRM_WIDTH_1_BYTE_SUPPORTED ? 
					8:
					(
						OUT_STRM_WIDTH_2_BYTE_SUPPORTED ? 
							16:
							32
					)
			)
		),
		.DATA_WIDTH_FOREACH_ITEM(
			OUT_STRM_WIDTH_1_BYTE_SUPPORTED ? 
				8:
				(
					OUT_STRM_WIDTH_2_BYTE_SUPPORTED ? 
						16:
						32
				)
		),
		.HAS_USER("false"),
		.USER_WIDTH(1),
		.EN_COLLECTOR_OUT_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)element_wise_proc_res_collector(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.s_axis_collector_data(s_collector_axis_data),
		.s_axis_collector_keep(s_collector_axis_keep),
		.s_axis_collector_user(1'bx),
		.s_axis_collector_last(s_collector_axis_last),
		.s_axis_collector_valid(s_collector_axis_valid),
		.s_axis_collector_ready(s_collector_axis_ready),
		
		.m_axis_collector_data(m_collector_axis_data),
		.m_axis_collector_keep(m_collector_axis_keep),
		.m_axis_collector_user(),
		.m_axis_collector_last(m_collector_axis_last),
		.m_axis_collector_valid(m_collector_axis_valid),
		.m_axis_collector_ready(m_collector_axis_ready)
	);
	
endmodule
