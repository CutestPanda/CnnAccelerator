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
本模块: 获取特征图/卷积核数据的DMA(MM2S方向)适配器

描述:
给DMA(MM2S方向)命令绑定"随路传输附加数据"
根据"每个表面的有效数据个数"从紧凑的数据流重新生成表面流

注意：
"每个表面的有效数据个数"必须<=ATOMIC_C

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/08/07
********************************************************************/


module conv_data_dma_mm2s_adapter #(
	parameter integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer EXTRA_DATA_WIDTH = 26, // 随路传输附加数据的位宽(必须>=1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// DMA(MM2S方向)命令流输入(AXIS从机)
	input wire[55:0] s_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	input wire[5+EXTRA_DATA_WIDTH-1:0] s_dma_cmd_axis_user, // {随路传输附加数据(EXTRA_DATA_WIDTH bit), 每个表面的有效数据个数 - 1(5bit)}
	input wire s_dma_cmd_axis_valid,
	output wire s_dma_cmd_axis_ready,
	
	// DMA(MM2S方向)数据流输入(AXIS从机)
	input wire[STREAM_DATA_WIDTH-1:0] s_dma_strm_axis_data,
	input wire[STREAM_DATA_WIDTH/8-1:0] s_dma_strm_axis_keep,
	input wire s_dma_strm_axis_last,
	input wire s_dma_strm_axis_valid,
	output wire s_dma_strm_axis_ready,
	
	// DMA(MM2S方向)命令流输出(AXIS主机)
	output wire[55:0] m_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m_dma_cmd_axis_last, // 帧尾标志
	output wire m_dma_cmd_axis_valid,
	input wire m_dma_cmd_axis_ready,
	
	// DMA(MM2S方向)数据流输出(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_dma_sfc_axis_data,
	output wire[EXTRA_DATA_WIDTH-1:0] m_dma_sfc_axis_user, // {随路传输附加数据(EXTRA_DATA_WIDTH bit)}
	output wire[ATOMIC_C*2-1:0] m_dma_sfc_axis_keep,
	output wire m_dma_sfc_axis_last,
	output wire m_dma_sfc_axis_valid,
	input wire m_dma_sfc_axis_ready
);
	
	/** 内部配置 **/
	localparam integer ACMP_EXTRA_DATA_FIFO_DEPTH = 8; // 随路传输附加数据fifo深度
	
	/** 随路传输附加数据fifo **/
	// [fifo写端口]
	wire acmp_extra_data_fifo_wen;
	wire[5+EXTRA_DATA_WIDTH-1:0] acmp_extra_data_fifo_din; // {随路传输附加数据(EXTRA_DATA_WIDTH bit), 每个表面的有效数据个数 - 1(5bit)}
	wire acmp_extra_data_fifo_full_n;
	// [fifo读端口]
	wire acmp_extra_data_fifo_ren;
	wire[5+EXTRA_DATA_WIDTH-1:0] acmp_extra_data_fifo_dout; // {随路传输附加数据(EXTRA_DATA_WIDTH bit), 每个表面的有效数据个数 - 1(5bit)}
	wire acmp_extra_data_fifo_empty_n;
	
	// 握手条件: aclken & s_dma_cmd_axis_valid & m_dma_cmd_axis_ready & acmp_extra_data_fifo_full_n
	assign s_dma_cmd_axis_ready = aclken & m_dma_cmd_axis_ready & acmp_extra_data_fifo_full_n;
	
	assign m_dma_cmd_axis_data = s_dma_cmd_axis_data;
	assign m_dma_cmd_axis_user = 1'b0; // 递增传输
	assign m_dma_cmd_axis_last = 1'b1; // 帧尾标志
	// 握手条件: aclken & s_dma_cmd_axis_valid & m_dma_cmd_axis_ready & acmp_extra_data_fifo_full_n
	assign m_dma_cmd_axis_valid = aclken & s_dma_cmd_axis_valid & acmp_extra_data_fifo_full_n;
	
	// 握手条件: aclken & s_dma_cmd_axis_valid & m_dma_cmd_axis_ready & acmp_extra_data_fifo_full_n
	assign acmp_extra_data_fifo_wen = aclken & s_dma_cmd_axis_valid & m_dma_cmd_axis_ready;
	assign acmp_extra_data_fifo_din = s_dma_cmd_axis_user;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(ACMP_EXTRA_DATA_FIFO_DEPTH),
		.fifo_data_width(5+EXTRA_DATA_WIDTH),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)acmp_extra_data_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(acmp_extra_data_fifo_wen),
		.fifo_din(acmp_extra_data_fifo_din),
		.fifo_full_n(acmp_extra_data_fifo_full_n),
		
		.fifo_ren(acmp_extra_data_fifo_ren),
		.fifo_dout(acmp_extra_data_fifo_dout),
		.fifo_empty_n(acmp_extra_data_fifo_empty_n)
	);
	
	/** 特征图/卷积核表面生成单元 **/
	// [特征图/卷积核数据流(AXIS从机)]
	wire[STREAM_DATA_WIDTH-1:0] s_stream_axis_data;
	wire[STREAM_DATA_WIDTH/8-1:0] s_stream_axis_keep;
	wire[5+EXTRA_DATA_WIDTH-1:0] s_stream_axis_user; // {随路传输附加数据(EXTRA_DATA_WIDTH bit), 每个表面的有效数据个数 - 1(5bit)}
	wire s_stream_axis_last;
	wire s_stream_axis_valid;
	wire s_stream_axis_ready;
	// [特征图/卷积核表面流(AXIS主机)]
	wire[ATOMIC_C*2*8-1:0] m_sfc_axis_data;
	wire[ATOMIC_C*2-1:0] m_sfc_axis_keep;
	wire[EXTRA_DATA_WIDTH-1:0] m_sfc_axis_user; // {随路传输附加数据(EXTRA_DATA_WIDTH bit)}
	wire m_sfc_axis_last;
	wire m_sfc_axis_valid;
	wire m_sfc_axis_ready;
	
	assign s_stream_axis_data = s_dma_strm_axis_data;
	assign s_stream_axis_keep = s_dma_strm_axis_keep;
	assign s_stream_axis_user = acmp_extra_data_fifo_dout;
	assign s_stream_axis_last = s_dma_strm_axis_last;
	// 握手条件: aclken & s_dma_strm_axis_valid & s_stream_axis_ready & acmp_extra_data_fifo_empty_n
	assign s_stream_axis_valid = aclken & s_dma_strm_axis_valid & acmp_extra_data_fifo_empty_n;
	
	// 握手条件: aclken & s_dma_strm_axis_valid & s_stream_axis_ready & acmp_extra_data_fifo_empty_n
	assign s_dma_strm_axis_ready = aclken & s_stream_axis_ready & acmp_extra_data_fifo_empty_n;
	
	assign m_dma_sfc_axis_data = m_sfc_axis_data;
	assign m_dma_sfc_axis_user = m_sfc_axis_user;
	assign m_dma_sfc_axis_keep = m_sfc_axis_keep;
	assign m_dma_sfc_axis_last = m_sfc_axis_last;
	// 握手条件: aclken & m_sfc_axis_valid & m_dma_sfc_axis_ready
	assign m_dma_sfc_axis_valid = aclken & m_sfc_axis_valid;
	
	// 握手条件: aclken & m_sfc_axis_valid & m_dma_sfc_axis_ready
	assign m_sfc_axis_ready = aclken & m_dma_sfc_axis_ready;
	
	// 握手条件: aclken & s_dma_strm_axis_valid & s_stream_axis_ready & s_dma_strm_axis_last & acmp_extra_data_fifo_empty_n
	assign acmp_extra_data_fifo_ren = aclken & s_dma_strm_axis_valid & s_stream_axis_ready & s_dma_strm_axis_last;
	
	conv_data_sfc_gen #(
		.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)conv_data_sfc_gen_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.s_stream_axis_data(s_stream_axis_data),
		.s_stream_axis_keep(s_stream_axis_keep),
		.s_stream_axis_user(s_stream_axis_user),
		.s_stream_axis_last(s_stream_axis_last),
		.s_stream_axis_valid(s_stream_axis_valid),
		.s_stream_axis_ready(s_stream_axis_ready),
		
		.m_sfc_axis_data(m_sfc_axis_data),
		.m_sfc_axis_keep(m_sfc_axis_keep),
		.m_sfc_axis_user(m_sfc_axis_user),
		.m_sfc_axis_last(m_sfc_axis_last),
		.m_sfc_axis_valid(m_sfc_axis_valid),
		.m_sfc_axis_ready(m_sfc_axis_ready)
	);
	
endmodule
