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
本模块: 输出数据舍入单元组

描述:
ATOMIC_K个输出数据舍入单元

提供逐级反压

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/25
********************************************************************/


module out_round_group #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter INT8_SUPPORTED = 1'b0, // 是否支持INT8运算数据格式
	parameter INT16_SUPPORTED = 1'b1, // 是否支持INT16运算数据格式
	parameter FP16_SUPPORTED = 1'b1, // 是否支持FP16运算数据格式
	parameter integer USER_WIDTH = 1, // USER信号的位宽(必须>=1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire[3:0] fixed_point_quat_accrc, // 定点数量化精度
	
	// 舍入单元组输入(AXIS从机)
	input wire[ATOMIC_K*32-1:0] s_axis_round_data, // ATOMIC_K个定点数或FP32
	input wire[ATOMIC_K*4-1:0] s_axis_round_keep,
	input wire[USER_WIDTH-1:0] s_axis_round_user,
	input wire s_axis_round_last,
	input wire s_axis_round_valid,
	output wire s_axis_round_ready,
	
	// 舍入单元组输出(AXIS主机)
	output wire[ATOMIC_K*16-1:0] m_axis_round_data, // ATOMIC_K个定点数或浮点数
	output wire[ATOMIC_K*2-1:0] m_axis_round_keep,
	output wire[USER_WIDTH-1:0] m_axis_round_user,
	output wire m_axis_round_last,
	output wire m_axis_round_valid,
	input wire m_axis_round_ready
);
	
	/** 流水线控制 **/
	// [第0级]
	wire[ATOMIC_K-1:0] round_mask_s0;
	wire[USER_WIDTH-1:0] round_user_s0;
	wire round_last_s0;
	wire round_valid_s0;
	wire round_ready_s0;
	wire[ATOMIC_K-1:0] round_ce_s0;
	// [第1级]
	reg[ATOMIC_K-1:0] round_mask_s1;
	reg[USER_WIDTH-1:0] round_user_s1;
	reg round_last_s1;
	reg round_valid_s1;
	wire round_ready_s1;
	wire[ATOMIC_K-1:0] round_ce_s1;
	// [第2级]
	reg[ATOMIC_K-1:0] round_mask_s2;
	reg[USER_WIDTH-1:0] round_user_s2;
	reg round_last_s2;
	reg round_valid_s2;
	wire round_ready_s2;
	
	assign s_axis_round_ready = aclken & round_ready_s0;
	
	assign m_axis_round_user = round_user_s2;
	assign m_axis_round_last = round_last_s2;
	assign m_axis_round_valid = aclken & round_valid_s2;
	
	assign round_user_s0 = s_axis_round_user;
	assign round_last_s0 = s_axis_round_last;
	assign round_valid_s0 = s_axis_round_valid;
	
	assign round_ready_s0 = (~round_valid_s1) | round_ready_s1;
	assign round_ready_s1 = (~round_valid_s2) | round_ready_s2;
	assign round_ready_s2 = m_axis_round_ready;
	
	always @(posedge aclk)
	begin
		if(aclken & round_valid_s0 & round_ready_s0)
		begin
			round_mask_s1 <= # SIM_DELAY round_mask_s0;
			round_user_s1 <= # SIM_DELAY round_user_s0;
			round_last_s1 <= # SIM_DELAY round_last_s0;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			round_valid_s1 <= 1'b0;
		else if(aclken & round_ready_s0)
			round_valid_s1 <= # SIM_DELAY round_valid_s0;
	end
	
	always @(posedge aclk)
	begin
		if(aclken & round_valid_s1 & round_ready_s1)
		begin
			round_mask_s2 <= # SIM_DELAY round_mask_s1;
			round_user_s2 <= # SIM_DELAY round_user_s1;
			round_last_s2 <= # SIM_DELAY round_last_s1;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			round_valid_s2 <= 1'b0;
		else if(aclken & round_ready_s1)
			round_valid_s2 <= # SIM_DELAY round_valid_s1;
	end
	
	genvar round_i;
	generate
		for(round_i = 0;round_i < ATOMIC_K;round_i = round_i + 1)
		begin:round_blk
			assign m_axis_round_keep[round_i*2+1:round_i*2] = {2{round_mask_s2[round_i]}};
			
			assign round_mask_s0[round_i] = s_axis_round_keep[round_i*4];
			
			assign round_ce_s0[round_i] = aclken & round_valid_s0 & round_ready_s0 & round_mask_s0[round_i];
			assign round_ce_s1[round_i] = aclken & round_valid_s1 & round_ready_s1 & round_mask_s1[round_i];
			
			out_round_cell #(
				.USE_EXT_CE(1'b1),
				.INT8_SUPPORTED(INT8_SUPPORTED),
				.INT16_SUPPORTED(INT16_SUPPORTED),
				.FP16_SUPPORTED(FP16_SUPPORTED),
				.INFO_ALONG_WIDTH(1),
				.SIM_DELAY(SIM_DELAY)
			)out_round_cell_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.calfmt(calfmt),
				.fixed_point_quat_accrc(fixed_point_quat_accrc),
				
				.s0_ce(round_ce_s0[round_i]),
				.s1_ce(round_ce_s1[round_i]),
				
				.round_i_op_x(s_axis_round_data[round_i*32+31:round_i*32]),
				.round_i_info_along(1'bx),
				.round_i_vld(1'bx),
				
				.round_o_res(m_axis_round_data[round_i*16+15:round_i*16]),
				.round_o_info_along(),
				.round_o_vld()
			);
		end
	endgenerate
	
endmodule
