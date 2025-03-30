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
本模块: 卷积中间结果累加单元

描述:
支持INT16、FP16两种运算数据格式

带有全局时钟使能

注意：
暂不支持INT8运算数据格式

协议:
无

作者: 陈家耀
日期: 2025/03/29
********************************************************************/


module conv_middle_res_accumulate #(
	parameter EN_SMALL_FP32 = "false", // 是否处理极小FP32
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	
	// 中间结果累加输入
	input wire[7:0] acmlt_in_exp, // 指数部分(仅当运算数据格式为FP16时有效)
	input wire signed[39:0] acmlt_in_frac, // 尾数部分或定点数
	input wire[31:0] acmlt_in_org_mid_res, // 原中间结果
	input wire acmlt_in_first_item, // 是否第1项(标志)
	input wire acmlt_in_valid, // 输入有效指示
	
	// 中间结果累加输出
	output wire[31:0] acmlt_out_data, // 单精度浮点数或定点数
	output wire acmlt_out_valid // 输出有效指示
);
	
	/** 常量 **/
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 复用的有符号加法器 **/
	wire signed[36:0] adder_0_op1; // 操作数1
	wire signed[31:0] adder_0_op2; // 操作数2
	wire adder_0_ce; // 计算使能
	reg signed[37:0] adder_0_out; // 计算结果
	
	always @(posedge aclk)
	begin
		if(adder_0_ce)
			adder_0_out <= # SIM_DELAY adder_0_op1 + adder_0_op2;
	end
	
	/**
	复用的算术右移单元
	
	可实现算术右移0~39位
	
	第1级流水线: 粗粒度算术右移(0 | 8 | 16 | 24 | 32)
	第2级流水线: 细粒度算术右移(0~7)
	**/
	wire signed[39:0] ars_op1; // 操作数1
	wire[5:0] ars_op2; // 操作数2
	wire ars_ce0; // 第1级流水线计算使能
	wire ars_ce1; // 第2级流水线计算使能
	reg signed[79:0] ars_coarse_res; // 粗粒度移位结果
	reg[2:0] ars_op2_d1; // 延迟1clk的操作数2
	reg signed[79:0] ars_res; // 移位结果
	
	// 粗粒度移位结果
	always @(posedge aclk)
	begin
		if(ars_ce0)
			ars_coarse_res <= # SIM_DELAY 
				$signed({ars_op1, 40'd0}) >>> (
					(ars_op2[5:3] == 3'b000) ? 6'd0:
					(ars_op2[5:3] == 3'b001) ? 6'd8:
					(ars_op2[5:3] == 3'b010) ? 6'd16:
					(ars_op2[5:3] == 3'b011) ? 6'd24:
					                           6'd32
				);
	end
	// 延迟1clk的操作数2
	always @(posedge aclk)
	begin
		if(ars_ce0)
			ars_op2_d1 <= # SIM_DELAY ars_op2[2:0];
	end
	
	// 移位结果
	always @(posedge aclk)
	begin
		if(ars_ce1)
			ars_res <= # SIM_DELAY ars_coarse_res >>> ars_op2_d1;
	end
	
	/** 输入有效指示延迟链 **/
	reg acmlt_in_valid_d1; // 延迟1clk的输入有效指示
	reg acmlt_in_valid_d2; // 延迟2clk的输入有效指示
	reg acmlt_in_valid_d3; // 延迟3clk的输入有效指示
	reg acmlt_in_valid_d4; // 延迟4clk的输入有效指示
	
	// 延迟1~4clk的输入有效指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{acmlt_in_valid_d4, acmlt_in_valid_d3, acmlt_in_valid_d2, acmlt_in_valid_d1} <= 4'b0000;
		else if(aclken)
			{acmlt_in_valid_d4, acmlt_in_valid_d3, acmlt_in_valid_d2, acmlt_in_valid_d1} <= # SIM_DELAY 
				{acmlt_in_valid_d3, acmlt_in_valid_d2, acmlt_in_valid_d1, acmlt_in_valid};
	end
	
	/**
	INT16累加
	
	第1级流水线: 计算(原中间结果 + 定点数)
	第2级流水线: 判断新的中间结果是否溢出并对其作限幅
	**/
	// 累加输入
	wire signed[36:0] acmlt_in_int16; // 定点数
	wire signed[31:0] acmlt_in_org_mid_res_int16; // 原中间结果
	wire acmlt_in_first_item_int16; // 是否第1项(标志)
	// 复用的有符号加法器输入
	wire signed[36:0] adder_0_op1_int16; // 操作数1
	wire signed[31:0] adder_0_op2_int16; // 操作数2
	wire adder_0_ce_int16; // 计算使能
	// 累加计算
	wire signed[37:0] acmlt_org_mid_res_add_new_int16; // 原中间结果 + 定点数
	reg signed[36:0] acmlt_in_int16_d1; // 延迟1clk的定点数
	reg signed acmlt_in_first_item_int16_d1; // 延迟1clk的是否第1项(标志)
	wire signed[37:0] acmlt_new_mid_res_int16; // 新的中间结果
	wire acmlt_is_new_mid_res_up_ovf_int16; // 新的中间结果向上溢出(标志)
	wire acmlt_is_new_mid_res_down_ovf_int16; // 新的中间结果向下溢出(标志)
	reg signed[31:0] acmlt_new_mid_res_amp_lmt_int16; // 限幅后的新中间结果
	// 累加输出
	wire[31:0] acmlt_out_data_int16; // 定点数
	wire acmlt_out_valid_int16; // 输出有效指示
	
	assign acmlt_in_int16 = $signed(acmlt_in_frac[36:0]);
	assign acmlt_in_org_mid_res_int16 = $signed(acmlt_in_org_mid_res);
	assign acmlt_in_first_item_int16 = acmlt_in_first_item;
	
	assign adder_0_op1_int16 = acmlt_in_int16;
	assign adder_0_op2_int16 = acmlt_in_org_mid_res_int16;
	assign adder_0_ce_int16 = acmlt_in_valid;
	
	assign acmlt_org_mid_res_add_new_int16 = adder_0_out;
	
	assign acmlt_new_mid_res_int16 = 
		acmlt_in_first_item_int16_d1 ? 
			{acmlt_in_int16_d1[36], acmlt_in_int16_d1}:
			acmlt_org_mid_res_add_new_int16;
	assign acmlt_is_new_mid_res_up_ovf_int16 = (~acmlt_new_mid_res_int16[37]) & (acmlt_new_mid_res_int16[36:31] != 6'b000000);
	assign acmlt_is_new_mid_res_down_ovf_int16 = acmlt_new_mid_res_int16[37] & (acmlt_new_mid_res_int16[36:31] != 6'b111111);
	
	assign acmlt_out_data_int16 = acmlt_new_mid_res_amp_lmt_int16;
	assign acmlt_out_valid_int16 = acmlt_in_valid_d2;
	
	// 延迟1clk的定点数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_INT16) & acmlt_in_valid)
			acmlt_in_int16_d1 <= # SIM_DELAY acmlt_in_int16;
	end
	// 延迟1clk的是否第1项(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_INT16) & acmlt_in_valid)
			acmlt_in_first_item_int16_d1 <= # SIM_DELAY acmlt_in_first_item_int16;
	end
	
	// 限幅后的新中间结果
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_INT16) & acmlt_in_valid_d1)
			acmlt_new_mid_res_amp_lmt_int16 <= # SIM_DELAY {
				acmlt_new_mid_res_int16[37], 
				{31{~acmlt_is_new_mid_res_down_ovf_int16}} & ({31{acmlt_is_new_mid_res_up_ovf_int16}} | acmlt_new_mid_res_int16[30:0])
			};
	end
	
	/**
	FP16累加
	
	待累加数的指数偏置为50, 原中间结果的指数偏置为127
	
	第1级流水线: 生成补码形式的原中间结果尾数, 计算abs(原中间结果的绝对指数 - 待累加数的绝对指数), 
		生成待累加数的绝对指数, 生成原中间结果的绝对指数
	第2级流水线: 
	**/
	// 累加输入
	wire[5:0] acmlt_in_exp_fp16; // 待累加数的阶码部分
	wire signed[36:0] acmlt_in_frac_fp16; // 待累加数的尾数部分
	wire[7:0] acmlt_in_org_mid_res_exp_fp16; // 原中间结果的阶码部分
	wire signed[24:0] acmlt_in_org_mid_res_frac_fp16; // 原中间结果的尾数部分
	wire acmlt_in_is_org_mid_res_dnm; // 原中间结果是否为非规则浮点数(标志)
	wire acmlt_in_first_item_fp16; // 是否第1项(标志)
	// 复用的有符号加法器输入
	wire signed[36:0] adder_0_op1_fp16; // 操作数1
	wire signed[31:0] adder_0_op2_fp16; // 操作数2
	wire adder_0_ce_fp16; // 计算使能
	// 累加计算
	wire signed[8:0] acmlt_org_mid_res_sub_in_exp_fp16; // 原中间结果的绝对指数 - 待累加数的绝对指数
	reg acmlt_is_org_mid_res_exp_lth_in_fp16; // 原中间结果的绝对指数 < 待累加数的绝对指数
	reg[7:0] acmlt_abs_org_mid_res_sub_in_exp_fp16; // abs(原中间结果的绝对指数 - 待累加数的绝对指数)
	reg signed[6:0] acmlt_in_abs_exp_fp16; // 待累加数的绝对指数
	reg signed[8:0] acmlt_in_org_mid_res_abs_exp_fp16; // 原中间结果的绝对指数
	reg signed[36:0] acmlt_in_frac_cp2_fp16; // 补码形式的待累加数尾数
	reg signed[24:0] acmlt_in_org_mid_res_frac_cp2_fp16; // 补码形式的原中间结果尾数
	// 累加输出
	wire[31:0] acmlt_out_data_fp16; // 单精度浮点数
	wire acmlt_out_valid_fp16; // 输出有效指示
	
	assign acmlt_in_exp_fp16 = acmlt_in_exp[5:0];
	assign acmlt_in_frac_fp16 = acmlt_in_frac[36:0];
	assign acmlt_in_org_mid_res_exp_fp16 = 
		acmlt_in_is_org_mid_res_dnm ? 
			8'd1:
			acmlt_in_org_mid_res[30:23];
	assign acmlt_in_org_mid_res_frac_fp16 = 
		acmlt_in_org_mid_res[31] ? 
			((~{1'b0, ~acmlt_in_is_org_mid_res_dnm, acmlt_in_org_mid_res[22:0]}) + 1'b1):
			{1'b0, ~acmlt_in_is_org_mid_res_dnm, acmlt_in_org_mid_res[22:0]};
	assign acmlt_in_is_org_mid_res_dnm = (EN_SMALL_FP32 == "true") & (acmlt_in_org_mid_res[30:23] == 8'd0);
	assign acmlt_in_first_item_fp16 = acmlt_in_first_item;
	
	assign acmlt_org_mid_res_sub_in_exp_fp16 = 
		// [原中间结果的阶码部分 - (127 + 23)] - (待累加数的阶码部分 - 50) = 
		//     (原中间结果的阶码部分 - 150) - (待累加数的阶码部分 - 50)
		$signed({1'b0, acmlt_in_org_mid_res_exp_fp16}) - $signed({3'b000, acmlt_in_exp_fp16}) - 9'sd100;
	
	// 原中间结果的绝对指数 < 待累加数的绝对指数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid)
			acmlt_is_org_mid_res_exp_lth_in_fp16 <= # SIM_DELAY acmlt_org_mid_res_sub_in_exp_fp16[8];
	end
	// abs(原中间结果的绝对指数 - 待累加数的绝对指数)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid)
			acmlt_abs_org_mid_res_sub_in_exp_fp16 <= # SIM_DELAY 
				acmlt_org_mid_res_sub_in_exp_fp16[8] ? 
					((~acmlt_org_mid_res_sub_in_exp_fp16[7:0]) + 1'b1):
					acmlt_org_mid_res_sub_in_exp_fp16[7:0];
	end
	// 待累加数的绝对指数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid)
			acmlt_in_abs_exp_fp16 <= # SIM_DELAY $signed({1'b0, acmlt_in_exp_fp16}) - 7'sd50;
	end
	// 原中间结果的绝对指数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid)
			acmlt_in_org_mid_res_abs_exp_fp16 <= # SIM_DELAY $signed({1'b0, acmlt_in_org_mid_res_exp_fp16}) - 9'sd127;
	end
	// 补码形式的待累加数尾数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid)
			acmlt_in_frac_cp2_fp16 <= # SIM_DELAY acmlt_in_frac_fp16;
	end
	// 补码形式的原中间结果尾数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid)
			acmlt_in_org_mid_res_frac_cp2_fp16 <= # SIM_DELAY acmlt_in_org_mid_res_frac_fp16;
	end
	
endmodule
