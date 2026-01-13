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
本模块: (逐元素操作)输出数据转换单元

描述:
将FP32转换为s33

带有全局时钟使能

时延 = 4clk

注意:
浮点运算未考虑INF和NAN

若旁路本单元, 则实际的输入数据格式只能是s16或s32或FP32

转换输出定点数(s33)的量化精度为fixed_point_quat_accrc

协议:
无

作者: 陈家耀
日期: 2026/01/13
********************************************************************/


module element_wise_out_data_cvt_cell #(
	parameter EN_ROUND = 1'b1, // 是否需要进行四舍五入
	parameter S33_OUT_DATA_SUPPORTED = 1'b1, // 是否支持S33输出数据格式
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 控制信号
	input wire bypass, // 旁路本单元
	
	// 运行时参数
	input wire[1:0] out_data_fmt, // 输出数据格式
	input wire[5:0] fixed_point_quat_accrc, // 定点数量化精度
	
	// 转换单元输入
	input wire[31:0] cvt_cell_i_op_x, // 操作数X
	input wire cvt_cell_i_pass, // 直接传递操作数X(标志)
	input wire[INFO_ALONG_WIDTH-1:0] cvt_cell_i_info_along, // 随路数据
	input wire cvt_cell_i_vld,
	
	// 转换单元输出
	output wire[32:0] cvt_cell_o_res, // 计算结果
	output wire[INFO_ALONG_WIDTH-1:0] cvt_cell_o_info_along, // 随路数据
	output wire cvt_cell_o_vld
);
	
	/** 常量 **/
	// 输入数据格式的编码
	localparam OUT_DATA_FMT_S33 = 2'b00;
	localparam OUT_DATA_FMT_NONE = 2'b10;
	
	/** 输入数据格式 **/
	wire[1:0] out_data_fmt_inner;
	
	assign out_data_fmt_inner = 
		(S33_OUT_DATA_SUPPORTED & (out_data_fmt == OUT_DATA_FMT_S33)) ? OUT_DATA_FMT_S33:
		                                                                OUT_DATA_FMT_NONE;
	
	/** 输入信号延迟链 **/
	reg[4:1] cvt_cell_i_vld_delayed;
	reg[4:1] cvt_cell_i_pass_delayed;
	reg[INFO_ALONG_WIDTH-1:0] cvt_cell_i_info_along_delayed[1:4];
	reg[32:0] cvt_cell_i_op_x_delayed[1:4];
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cvt_cell_i_vld_delayed <= 4'b0000;
		else if(aclken)
			cvt_cell_i_vld_delayed <= # SIM_DELAY 
				{cvt_cell_i_vld_delayed[3:1], cvt_cell_i_vld};
	end
	
	genvar payload_delayed_i;
	generate
		for(payload_delayed_i = 0;payload_delayed_i < 4;payload_delayed_i = payload_delayed_i + 1)
		begin:payload_delayed_blk
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						(payload_delayed_i == 0) ? 
							cvt_cell_i_vld:
							cvt_cell_i_vld_delayed[payload_delayed_i]
					)
				)
				begin
					cvt_cell_i_pass_delayed[payload_delayed_i + 1] <= # SIM_DELAY 
						(payload_delayed_i == 0) ? 
							cvt_cell_i_pass:
							cvt_cell_i_pass_delayed[payload_delayed_i];
					
					cvt_cell_i_info_along_delayed[payload_delayed_i + 1] <= # SIM_DELAY 
						(payload_delayed_i == 0) ? 
							cvt_cell_i_info_along:
							cvt_cell_i_info_along_delayed[payload_delayed_i];
					
					cvt_cell_i_op_x_delayed[payload_delayed_i + 1] <= # SIM_DELAY 
						(payload_delayed_i == 0) ? 
							cvt_cell_i_op_x:
							cvt_cell_i_op_x_delayed[payload_delayed_i];
				end
			end
		end
	endgenerate
	
	/**
	FP32转s33
	
	---------------------------------------------------------------------
	| 流水线级 |        完成的内容         |            备注            |
	---------------------------------------------------------------------
	|    1     | 得到尾数移位模式          |                            |
	---------------------------------------------------------------------
	|    2     | 生成常规转换结果          | "FP32实际指数"在范围       |
	|          |                           | [-输出定点数的量化精度 -1, |
	|          |                           | -输出定点数的量化精度 + 31]|
	|          |                           | 内时, 常规转换结果有效     |
	---------------------------------------------------------------------
	|    3     | 四舍五入(向最近偶数舍入)  |                            |
	---------------------------------------------------------------------
	**/
	// [得到尾数移位模式]
	wire s33_shift_pattern_gen_in_vld;
	wire s33_shift_pattern_gen_in_pass;
	wire[31:0] s33_shift_pattern_gen_in_op_x;
	wire[8:0] s33_shift_pattern_gen_in_ec_add_q; // 输入FP32的阶码 + 输出定点数的量化精度
	wire signed[25:0] s33_shift_pattern_gen_in_org_mts; // 原始尾数(Q24)
	reg s33_shift_pattern_gen_set_to_ovf_v_flag; // 将转换结果设为溢出值(标志)
	reg s33_shift_pattern_gen_set_to_zero_flag; // 将转换结果设为0(标志)
	reg[4:0] s33_shift_pattern_gen_lsh_n; // 尾数左移位数
	reg signed[25:0] s33_shift_pattern_gen_mts_to_lsh; // 待左移的尾数(Q24)
	// [生成常规转换结果]
	wire s33_cvt_in_vld;
	wire s33_cvt_in_pass;
	wire signed[56:0] s33_cvt_in_sfix_to_lsh; // 待左移的定点数(Q24)
	reg signed[56:0] s33_cvt_normal_res; // 常规转换结果(Q = 24 + fixed_point_quat_accrc)
	reg s33_cvt_set_to_ovf_v_flag; // 将转换结果设为溢出值(标志)
	reg s33_cvt_set_to_zero_flag; // 将转换结果设为0(标志)
	// [四舍五入(向最近偶数舍入)]
	wire s33_round_in_vld;
	wire s33_round_in_pass;
	wire[31:0] s33_round_in_op_x;
	wire s33_round_in_to_fwd_carry_flag; // 四舍五入向前进位(标志)
	reg signed[32:0] s33_round_res; // 四舍五入后的结果
	// [最终结果]
	wire s33_fnl_out_vld;
	wire[INFO_ALONG_WIDTH-1:0] s33_fnl_out_info_along;
	wire signed[32:0] s33_fnl_out_res;
	
	assign s33_shift_pattern_gen_in_vld = (out_data_fmt_inner == OUT_DATA_FMT_S33) & cvt_cell_i_vld;
	assign s33_shift_pattern_gen_in_pass = cvt_cell_i_pass;
	assign s33_shift_pattern_gen_in_op_x = cvt_cell_i_op_x;
	assign s33_shift_pattern_gen_in_ec_add_q = s33_shift_pattern_gen_in_op_x[30:23] + fixed_point_quat_accrc;
	assign s33_shift_pattern_gen_in_org_mts = 
		// 当输入的FP32是非规则数时, 必定将转换结果设为0, 因此原始尾数的生成不用考虑FP32是非规则数的情况
		({26{s33_shift_pattern_gen_in_op_x[31]}} ^ {1'b0, 1'b1, s33_shift_pattern_gen_in_op_x[22:0], 1'b0}) + 
			s33_shift_pattern_gen_in_op_x[31];
	
	assign s33_cvt_in_vld = (out_data_fmt_inner == OUT_DATA_FMT_S33) & cvt_cell_i_vld_delayed[1];
	assign s33_cvt_in_pass = cvt_cell_i_pass_delayed[1];
	assign s33_cvt_in_sfix_to_lsh = 
		{{31{s33_shift_pattern_gen_mts_to_lsh[25]}}, s33_shift_pattern_gen_mts_to_lsh[25:0]};
	
	assign s33_round_in_vld = (out_data_fmt_inner == OUT_DATA_FMT_S33) & cvt_cell_i_vld_delayed[2];
	assign s33_round_in_pass = cvt_cell_i_pass_delayed[2];
	assign s33_round_in_op_x = cvt_cell_i_op_x_delayed[2][31:0];
	assign s33_round_in_to_fwd_carry_flag = 
		EN_ROUND & 
		s33_cvt_normal_res[23] & 
		((|s33_cvt_normal_res[22:0]) | s33_cvt_normal_res[24]);
	
	assign s33_fnl_out_vld = (out_data_fmt_inner == OUT_DATA_FMT_S33) & cvt_cell_i_vld_delayed[3];
	assign s33_fnl_out_info_along = cvt_cell_i_info_along_delayed[3];
	assign s33_fnl_out_res = s33_round_res;
	
	// 将转换结果设为溢出值(标志), 将转换结果设为0(标志), 尾数左移位数, 待左移的尾数(Q24)
	always @(posedge aclk)
	begin
		if(aclken & s33_shift_pattern_gen_in_vld & (~s33_shift_pattern_gen_in_pass))
		begin
			s33_shift_pattern_gen_set_to_ovf_v_flag <= # SIM_DELAY 
				// 当"FP32实际指数 >= 32 - 输出定点数的量化精度"时, 将转换结果设为溢出值
				s33_shift_pattern_gen_in_ec_add_q >= (127 + 32);
			
			s33_shift_pattern_gen_set_to_zero_flag <= # SIM_DELAY 
				// 当"FP32实际指数 <= -2 - 输出定点数的量化精度"时, 将转换结果设为0
				s33_shift_pattern_gen_in_ec_add_q <= (127 - 2);
			
			s33_shift_pattern_gen_lsh_n <= # SIM_DELAY 
				((s33_shift_pattern_gen_in_ec_add_q >= 127) & (s33_shift_pattern_gen_in_ec_add_q <= (127 + 31))) ? 
					// 当"FP32实际指数"在范围[-输出定点数的量化精度, -输出定点数的量化精度 + 31]内时, 对尾数左移得到转换结果
					(s33_shift_pattern_gen_in_ec_add_q - 127):
					5'd0;
			
			s33_shift_pattern_gen_mts_to_lsh <= # SIM_DELAY 
				(s33_shift_pattern_gen_in_ec_add_q == (127 - 1)) ? 
					// 当"FP32实际指数 = -1 - 输出定点数的量化精度"时, 将原始尾数算术右移1位
					{s33_shift_pattern_gen_in_org_mts[25], s33_shift_pattern_gen_in_org_mts[25:1]}:
					s33_shift_pattern_gen_in_org_mts[25:0];
		end
	end
	
	// 常规转换结果(Q = 24 + fixed_point_quat_accrc), 将转换结果设为溢出值(标志), 将转换结果设为0(标志)
	always @(posedge aclk)
	begin
		if(aclken & s33_cvt_in_vld & (~s33_cvt_in_pass))
		begin
			s33_cvt_normal_res <= # SIM_DELAY 
				s33_cvt_in_sfix_to_lsh << s33_shift_pattern_gen_lsh_n;
			
			s33_cvt_set_to_ovf_v_flag <= # SIM_DELAY s33_shift_pattern_gen_set_to_ovf_v_flag;
			
			s33_cvt_set_to_zero_flag <= # SIM_DELAY s33_shift_pattern_gen_set_to_zero_flag;
		end
	end
	
	// 四舍五入后的结果
	always @(posedge aclk)
	begin
		if(aclken & s33_round_in_vld)
		begin
			s33_round_res <= # SIM_DELAY 
				s33_round_in_pass ? 
					{1'b0, s33_round_in_op_x[31:0]}:
					(
						(s33_cvt_set_to_ovf_v_flag | s33_cvt_set_to_zero_flag) ? 
							/*
							s33_cvt_set_to_zero_flag ? 
								33'h0_0000_0000:
								(
									s33_round_in_op_x[31] ? 
										33'h1_0000_0000:
										33'h0_ffff_ffff
								)
							*/
							({33{~s33_cvt_set_to_zero_flag}} & {s33_round_in_op_x[31], {32{~s33_round_in_op_x[31]}}}):
							(s33_cvt_normal_res[56:24] + s33_round_in_to_fwd_carry_flag)
					);
		end
	end
	
	/** 转换单元输出 **/
	reg[32:0] cvt_cell_o_res_r; // 计算结果
	reg[INFO_ALONG_WIDTH-1:0] cvt_cell_o_info_along_r; // 随路数据
	reg cvt_cell_o_vld_r;
	
	assign cvt_cell_o_res = cvt_cell_o_res_r;
	assign cvt_cell_o_info_along = cvt_cell_o_info_along_r;
	assign cvt_cell_o_vld = cvt_cell_o_vld_r;
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cvt_cell_o_vld_r <= 1'b0;
		else if(aclken)
			cvt_cell_o_vld_r <= # SIM_DELAY 
				bypass ? 
					cvt_cell_i_vld:
					((out_data_fmt_inner == OUT_DATA_FMT_S33) & s33_fnl_out_vld);
	end
	
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				bypass ? 
					cvt_cell_i_vld:
					((out_data_fmt_inner == OUT_DATA_FMT_S33) & s33_fnl_out_vld)
			)
		)
		begin
			cvt_cell_o_res_r <= # SIM_DELAY 
				bypass ? 
					{cvt_cell_i_op_x[31], cvt_cell_i_op_x[31:0]}:
					({33{out_data_fmt_inner == OUT_DATA_FMT_S33}} & s33_fnl_out_res);
			
			cvt_cell_o_info_along_r <= # SIM_DELAY 
				bypass ? 
					cvt_cell_i_info_along:
					({INFO_ALONG_WIDTH{out_data_fmt_inner == OUT_DATA_FMT_S33}} & s33_fnl_out_info_along);
		end
	end
	
endmodule
