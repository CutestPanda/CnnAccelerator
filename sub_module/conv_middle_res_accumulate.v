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
计算FP43(有符号尾数37位, 指数6位)与FP32的和
支持INT16、FP16两种运算数据格式
带有全局时钟使能

时延 = 
	计算INT16时 -> 2
	计算FP16时  -> 9

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
	
	可实现算术右移0~63位
	
	第1级流水线: 粗粒度算术右移(0 | 8 | 16 | 24 | 32 | 40 | 48 | 56)
	第2级流水线: 细粒度算术右移(0 | 1 | 2  | 3  | 4  | 5  | 6  | 7 )
	**/
	wire signed[39:0] ars_op1; // 操作数1
	wire[5:0] ars_op2; // 操作数2
	wire ars_clr; // 结果置零(标志)
	wire ars_ce0; // 第1级流水线计算使能
	wire ars_ce1; // 第2级流水线计算使能
	reg signed[79:0] ars_coarse_res; // 粗粒度移位结果
	reg[2:0] ars_op2_d1; // 延迟1clk的操作数2
	reg ars_clr_d1; // 延迟1clk的结果置零(标志)
	reg signed[79:0] ars_res; // 移位结果
	
	// 粗粒度移位结果
	always @(posedge aclk)
	begin
		if(ars_ce0 & (~ars_clr))
			ars_coarse_res <= # SIM_DELAY 
				$signed({ars_op1, 40'd0}) >>> (
					(ars_op2[5:3] == 3'b000) ? 6'd0:
					(ars_op2[5:3] == 3'b001) ? 6'd8:
					(ars_op2[5:3] == 3'b010) ? 6'd16:
					(ars_op2[5:3] == 3'b011) ? 6'd24:
					(ars_op2[5:3] == 3'b100) ? 6'd32:
					(ars_op2[5:3] == 3'b101) ? 6'd40:
					(ars_op2[5:3] == 3'b110) ? 6'd48:
					                           6'd56
				);
	end
	// 延迟1clk的操作数2
	always @(posedge aclk)
	begin
		if(ars_ce0)
			ars_op2_d1 <= # SIM_DELAY ars_op2[2:0];
	end
	// 延迟1clk的结果置零(标志)
	always @(posedge aclk)
	begin
		if(ars_ce0)
			ars_clr_d1 <= # SIM_DELAY ars_clr;
	end
	
	// 移位结果
	always @(posedge aclk)
	begin
		if(ars_ce1)
			ars_res <= # SIM_DELAY {80{~ars_clr_d1}} & (ars_coarse_res >>> ars_op2_d1);
	end
	
	/** 输入有效指示延迟链 **/
	reg acmlt_in_valid_d1; // 延迟1clk的输入有效指示
	reg acmlt_in_valid_d2; // 延迟2clk的输入有效指示
	reg acmlt_in_valid_d3; // 延迟3clk的输入有效指示
	reg acmlt_in_valid_d4; // 延迟4clk的输入有效指示
	reg acmlt_in_valid_d5; // 延迟5clk的输入有效指示
	reg acmlt_in_valid_d6; // 延迟6clk的输入有效指示
	reg acmlt_in_valid_d7; // 延迟7clk的输入有效指示
	reg acmlt_in_valid_d8; // 延迟8clk的输入有效指示
	reg acmlt_in_valid_d9; // 延迟9clk的输入有效指示
	
	// 延迟1~9clk的输入有效指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{
				acmlt_in_valid_d9, acmlt_in_valid_d8, acmlt_in_valid_d7, 
				acmlt_in_valid_d6, acmlt_in_valid_d5, acmlt_in_valid_d4, 
				acmlt_in_valid_d3, acmlt_in_valid_d2, acmlt_in_valid_d1
			} <= 9'b0_0000_0000;
		else if(aclken)
			{
				acmlt_in_valid_d9, acmlt_in_valid_d8, acmlt_in_valid_d7, 
				acmlt_in_valid_d6, acmlt_in_valid_d5, acmlt_in_valid_d4, 
				acmlt_in_valid_d3, acmlt_in_valid_d2, acmlt_in_valid_d1
			} <= # SIM_DELAY {
				acmlt_in_valid_d8, acmlt_in_valid_d7, acmlt_in_valid_d6, 
				acmlt_in_valid_d5, acmlt_in_valid_d4, acmlt_in_valid_d3, 
				acmlt_in_valid_d2, acmlt_in_valid_d1, acmlt_in_valid
			};
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
	// 累加计算(第1级流水线)
	wire signed[37:0] acmlt_org_mid_res_add_new_int16; // 原中间结果 + 定点数
	reg signed[36:0] acmlt_in_int16_d1; // 延迟1clk的定点数
	reg signed acmlt_in_first_item_int16_d1; // 延迟1clk的是否第1项(标志)
	wire signed[37:0] acmlt_new_mid_res_int16; // 新的中间结果
	wire acmlt_is_new_mid_res_up_ovf_int16; // 新的中间结果向上溢出(标志)
	wire acmlt_is_new_mid_res_down_ovf_int16; // 新的中间结果向下溢出(标志)
	// 累加计算(第2级流水线)
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
	
	第1级流水线: 
		生成补码形式的待累加数尾数, 生成补码形式的原中间结果尾数, 
		计算abs(原中间结果的绝对指数 - 待累加数的绝对指数), 
		生成待累加数的绝对指数, 生成原中间结果的绝对指数
	第2级流水线: 
		计算max(原中间结果的绝对指数, 待累加数的绝对指数)
		生成绝对指数更大的浮点数的尾数
		对阶算术右移(阶段1: 粗粒度算术右移)
	第3级流水线: 
		对阶算术右移(阶段2: 粗粒度算术右移)
	第4级流水线: 
		尾数求和
	第5级流水线: 
		标准化阶段1
	第6级流水线: 
		标准化阶段2
	第7级流水线: 
		标准化阶段3
	第8级流水线: 
		标准化阶段4
	第9级流水线: 
		生成原码形式的尾数
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
	// 累加计算(第0级流水线)
	wire signed[8:0] acmlt_org_mid_res_sub_in_exp_fp16; // 原中间结果的绝对指数 - 待累加数的绝对指数
	// 累加计算(第1级流水线)
	reg acmlt_is_org_mid_res_exp_lth_in_fp16; // (原中间结果的绝对指数 < 待累加数的绝对指数)(标志)
	reg[7:0] acmlt_abs_org_mid_res_sub_in_exp_fp16; // abs(原中间结果的绝对指数 - 待累加数的绝对指数)
	reg signed[6:0] acmlt_in_abs_exp_fp16; // 待累加数的绝对指数
	reg signed[8:0] acmlt_in_org_mid_res_abs_exp_fp16; // 原中间结果的绝对指数
	reg signed[36:0] acmlt_in_frac_cp2_fp16; // 补码形式的待累加数尾数
	reg signed[24:0] acmlt_in_org_mid_res_frac_cp2_fp16; // 补码形式的原中间结果尾数
	reg acmlt_in_first_item_fp16_d1; // 延迟1clk的是否第1项(标志)
	// 累加计算(第2级流水线)
	reg signed[8:0] acmlt_exp_larger_fp16; // max(原中间结果的绝对指数, 待累加数的绝对指数)
	reg signed[36:0] acmlt_frac_exp_lg_fp16; // 绝对指数更大的浮点数的尾数
	reg acmlt_is_org_mid_res_exp_lth_in_fp16_d1; // 延迟1clk的(原中间结果的绝对指数 < 待累加数的绝对指数)(标志)
	reg acmlt_in_first_item_fp16_d2; // 延迟2clk的是否第1项(标志)
	// 累加计算(第3级流水线)
	reg signed[36:0] acmlt_frac_exp_lg_fp16_d1; // 延迟1clk的绝对指数更大的浮点数的尾数
	reg signed[8:0] acmlt_exp_larger_fp16_d1; // 延迟1clk的max(原中间结果的绝对指数, 待累加数的绝对指数)
	reg acmlt_is_org_mid_res_exp_lth_in_fp16_d2; // 延迟2clk的(原中间结果的绝对指数 < 待累加数的绝对指数)(标志)
	reg acmlt_in_first_item_fp16_d3; // 延迟3clk的是否第1项(标志)
	// 累加计算(第4级流水线)
	wire signed[60:0] acmlt_frac_sum; // 求和后的尾数(Q23)
	reg[39:0] acmlt_frac_shifted_fp16; // 移出的尾数
	reg signed[36:0] acmlt_frac_exp_lg_fp16_d2; // 延迟2clk的绝对指数更大的浮点数的尾数
	reg signed[8:0] acmlt_exp_larger_fp16_d2; // 延迟2clk的max(原中间结果的绝对指数, 待累加数的绝对指数)
	reg acmlt_in_first_item_fp16_d4; // 延迟4clk的是否第1项(标志)
	// 累加计算(第5级流水线)
	reg signed[42:0] acmlt_frac_nml_s1; // 标准化阶段1后的尾数(Q23)
	reg signed[8:0] acmlt_exp_nml_s1; // 标准化阶段1后的绝对指数
	// 累加计算(第6级流水线)
	reg signed[33:0] acmlt_frac_nml_s2; // 标准化阶段2后的尾数(Q23)
	reg signed[8:0] acmlt_exp_nml_s2; // 标准化阶段2后的绝对指数
	// 累加计算(第7级流水线)
	reg signed[29:0] acmlt_frac_nml_s3; // 标准化阶段3后的尾数(Q23)
	reg signed[8:0] acmlt_exp_nml_s3; // 标准化阶段3后的绝对指数
	// 累加计算(第8级流水线)
	reg signed[24:0] acmlt_frac_nml_s4; // 标准化阶段4后的尾数(Q23)
	reg signed[8:0] acmlt_exp_nml_s4; // 标准化阶段4后的绝对指数
	// 累加输出
	reg[31:0] acmlt_out_data_fp16; // 单精度浮点数
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
	
	assign ars_op1 = 
		acmlt_is_org_mid_res_exp_lth_in_fp16 ? 
			// 原中间结果的绝对指数 < 待累加数的绝对指数, 对原中间结果作算术右移
			{{15{acmlt_in_org_mid_res_frac_cp2_fp16[24]}}, acmlt_in_org_mid_res_frac_cp2_fp16}:
			// 原中间结果的绝对指数 >= 待累加数的绝对指数, 对待累加数作算术右移
			{{3{acmlt_in_frac_cp2_fp16[36]}}, acmlt_in_frac_cp2_fp16};
	assign ars_op2 = 
		(acmlt_abs_org_mid_res_sub_in_exp_fp16 > 8'd63) ? 
			6'd63:
			acmlt_abs_org_mid_res_sub_in_exp_fp16[5:0];
	assign ars_clr = acmlt_abs_org_mid_res_sub_in_exp_fp16 > 8'd63;
	assign ars_ce0 = aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d1 & (~acmlt_in_first_item_fp16_d1);
	assign ars_ce1 = aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d2 & (~acmlt_in_first_item_fp16_d2);
	
	assign adder_0_op1_fp16 = 
		acmlt_is_org_mid_res_exp_lth_in_fp16_d2 ? 
			acmlt_frac_exp_lg_fp16_d1: // 原中间结果的绝对指数 < 待累加数的绝对指数
			ars_res[76:40]; // 原中间结果的绝对指数 >= 待累加数的绝对指数
	assign adder_0_op2_fp16 = 
		acmlt_is_org_mid_res_exp_lth_in_fp16_d2 ? 
			{{7{ars_res[64]}}, ars_res[64:40]}: // 原中间结果的绝对指数 < 待累加数的绝对指数
			{{7{acmlt_frac_exp_lg_fp16_d1[24]}}, acmlt_frac_exp_lg_fp16_d1[24:0]}; // 原中间结果的绝对指数 >= 待累加数的绝对指数
	assign adder_0_ce_fp16 = aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d3 & (~acmlt_in_first_item_fp16_d3);
	
	assign acmlt_frac_sum[60:23] = 
		acmlt_in_first_item_fp16_d4 ? 
			{acmlt_frac_exp_lg_fp16_d2[36], acmlt_frac_exp_lg_fp16_d2}:
			adder_0_out;
	assign acmlt_frac_sum[22:0] = acmlt_frac_shifted_fp16[39:17] | 23'd1; // 末位恒置1
	
	assign acmlt_out_valid_fp16 = acmlt_in_valid_d9;
	
	// (原中间结果的绝对指数 < 待累加数的绝对指数)(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid & (~acmlt_in_first_item_fp16))
			acmlt_is_org_mid_res_exp_lth_in_fp16 <= # SIM_DELAY acmlt_org_mid_res_sub_in_exp_fp16[8];
	end
	// 延迟1clk的(原中间结果的绝对指数 < 待累加数的绝对指数)(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d1 & (~acmlt_in_first_item_fp16_d1))
			acmlt_is_org_mid_res_exp_lth_in_fp16_d1 <= # SIM_DELAY acmlt_is_org_mid_res_exp_lth_in_fp16;
	end
	// 延迟2clk的(原中间结果的绝对指数 < 待累加数的绝对指数)(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d2 & (~acmlt_in_first_item_fp16_d2))
			acmlt_is_org_mid_res_exp_lth_in_fp16_d2 <= # SIM_DELAY acmlt_is_org_mid_res_exp_lth_in_fp16_d1;
	end
	
	// abs(原中间结果的绝对指数 - 待累加数的绝对指数)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid & (~acmlt_in_first_item_fp16))
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
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid & (~acmlt_in_first_item_fp16))
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
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid & (~acmlt_in_first_item_fp16))
			acmlt_in_org_mid_res_frac_cp2_fp16 <= # SIM_DELAY acmlt_in_org_mid_res_frac_fp16;
	end
	
	// max(原中间结果的绝对指数, 待累加数的绝对指数)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d1)
			acmlt_exp_larger_fp16 <= # SIM_DELAY 
				(acmlt_in_first_item_fp16_d1 | acmlt_is_org_mid_res_exp_lth_in_fp16) ? 
					{{2{acmlt_in_abs_exp_fp16[6]}}, acmlt_in_abs_exp_fp16}:
					acmlt_in_org_mid_res_abs_exp_fp16;
	end
	// 延迟1clk的max(原中间结果的绝对指数, 待累加数的绝对指数)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d2)
			acmlt_exp_larger_fp16_d1 <= # SIM_DELAY acmlt_exp_larger_fp16;
	end
	// 延迟2clk的max(原中间结果的绝对指数, 待累加数的绝对指数)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d3)
			acmlt_exp_larger_fp16_d2 <= # SIM_DELAY acmlt_exp_larger_fp16_d1;
	end
	
	// 绝对指数更大的浮点数的尾数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d1)
			acmlt_frac_exp_lg_fp16 <= # SIM_DELAY 
				(acmlt_in_first_item_fp16_d1 | acmlt_is_org_mid_res_exp_lth_in_fp16) ? 
					acmlt_in_frac_cp2_fp16:
					{{12{acmlt_in_org_mid_res_frac_cp2_fp16[24]}}, acmlt_in_org_mid_res_frac_cp2_fp16};
	end
	// 延迟1clk的绝对指数更大的浮点数的尾数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d2)
			acmlt_frac_exp_lg_fp16_d1 <= # SIM_DELAY acmlt_frac_exp_lg_fp16;
	end
	// 延迟2clk的绝对指数更大的浮点数的尾数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d3)
			acmlt_frac_exp_lg_fp16_d2 <= # SIM_DELAY acmlt_frac_exp_lg_fp16_d1;
	end
	
	// 延迟1clk的是否第1项(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid)
			acmlt_in_first_item_fp16_d1 <= # SIM_DELAY acmlt_in_first_item_fp16;
	end
	// 延迟2clk的是否第1项(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d1)
			acmlt_in_first_item_fp16_d2 <= # SIM_DELAY acmlt_in_first_item_fp16_d1;
	end
	// 延迟3clk的是否第1项(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d2)
			acmlt_in_first_item_fp16_d3 <= # SIM_DELAY acmlt_in_first_item_fp16_d2;
	end
	// 延迟4clk的是否第1项(标志)
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d3)
			acmlt_in_first_item_fp16_d4 <= # SIM_DELAY acmlt_in_first_item_fp16_d3;
	end
	
	// 移出的尾数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d3)
			acmlt_frac_shifted_fp16 <= # SIM_DELAY {40{~acmlt_in_first_item_fp16_d3}} & ars_res[39:0];
	end
	
	// 标准化阶段1后的尾数(Q23)
	// 标准化阶段1后的绝对指数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d4)
		begin
			if(acmlt_frac_sum[60])
			begin
				if(acmlt_frac_sum[59:42] != 18'hfffff) // 整数部分<-2^19
				begin
					acmlt_frac_nml_s1 <= # SIM_DELAY acmlt_frac_sum >>> 18;
					acmlt_exp_nml_s1 <= # SIM_DELAY acmlt_exp_larger_fp16_d2 + 9'sd18;
				end
				else // 整数部分>=-2^19
				begin
					acmlt_frac_nml_s1 <= # SIM_DELAY acmlt_frac_sum[42:0];
					acmlt_exp_nml_s1 <= # SIM_DELAY acmlt_exp_larger_fp16_d2;
				end
			end
			else
			begin
				if(acmlt_frac_sum[59:42] != 18'h00000) // 整数部分>=2^19
				begin
					acmlt_frac_nml_s1 <= # SIM_DELAY acmlt_frac_sum >>> 18;
					acmlt_exp_nml_s1 <= # SIM_DELAY acmlt_exp_larger_fp16_d2 + 9'sd18;
				end
				else // 整数部分<2^19
				begin
					acmlt_frac_nml_s1 <= # SIM_DELAY acmlt_frac_sum[42:0];
					acmlt_exp_nml_s1 <= # SIM_DELAY acmlt_exp_larger_fp16_d2;
				end
			end
		end
	end
	
	// 标准化阶段2后的尾数(Q23)
	// 标准化阶段2后的绝对指数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d5)
		begin
			if(acmlt_frac_nml_s1[42])
			begin
				if(acmlt_frac_nml_s1[41:33] != 10'hfff) // 整数部分<-2^10
				begin
					acmlt_frac_nml_s2 <= # SIM_DELAY acmlt_frac_nml_s1 >>> 9;
					acmlt_exp_nml_s2 <= # SIM_DELAY acmlt_exp_nml_s1 + 9'sd9;
				end
				else // 整数部分>=-2^10
				begin
					acmlt_frac_nml_s2 <= # SIM_DELAY acmlt_frac_nml_s1[33:0];
					acmlt_exp_nml_s2 <= # SIM_DELAY acmlt_exp_nml_s1;
				end
			end
			else
			begin
				if(acmlt_frac_nml_s1[41:33] != 10'h000) // 整数部分>=2^10
				begin
					acmlt_frac_nml_s2 <= # SIM_DELAY acmlt_frac_nml_s1 >>> 9;
					acmlt_exp_nml_s2 <= # SIM_DELAY acmlt_exp_nml_s1 + 9'sd9;
				end
				else // 整数部分<2^10
				begin
					acmlt_frac_nml_s2 <= # SIM_DELAY acmlt_frac_nml_s1[33:0];
					acmlt_exp_nml_s2 <= # SIM_DELAY acmlt_exp_nml_s1;
				end
			end
		end
	end
	
	// 标准化阶段3后的尾数(Q23)
	// 标准化阶段3后的绝对指数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d6)
		begin
			if(acmlt_frac_nml_s2[33])
			begin
				if(acmlt_frac_nml_s2[32:28] != 5'b11111) // 整数部分<-2^5
				begin
					acmlt_frac_nml_s3 <= # SIM_DELAY acmlt_frac_nml_s2 >>> 4;
					acmlt_exp_nml_s3 <= # SIM_DELAY acmlt_exp_nml_s2 + 9'sd4;
				end
				else // 整数部分>=-2^5
				begin
					acmlt_frac_nml_s3 <= # SIM_DELAY {acmlt_frac_nml_s2[28], acmlt_frac_nml_s2[28:0]};
					acmlt_exp_nml_s3 <= # SIM_DELAY acmlt_exp_nml_s2;
				end
			end
			else
			begin
				if(acmlt_frac_nml_s2[32:28] != 5'b00000) // 整数部分>=2^5
				begin
					acmlt_frac_nml_s3 <= # SIM_DELAY acmlt_frac_nml_s2 >>> 4;
					acmlt_exp_nml_s3 <= # SIM_DELAY acmlt_exp_nml_s2 + 9'sd4;
				end
				else // 整数部分<2^5
				begin
					acmlt_frac_nml_s3 <= # SIM_DELAY {acmlt_frac_nml_s2[28], acmlt_frac_nml_s2[28:0]};
					acmlt_exp_nml_s3 <= # SIM_DELAY acmlt_exp_nml_s2;
				end
			end
		end
	end
	
	// 标准化阶段4后的尾数(Q23)
	// 标准化阶段4后的绝对指数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d7)
		begin
			if(acmlt_frac_nml_s3[29])
			begin
				if($signed(acmlt_frac_nml_s3[29:23]) < -32)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 5;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd5;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) < -16)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 4;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd4;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) < -8)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 3;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd3;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) < -4)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 2;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd2;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) < -2)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 1;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd1;
				end
				else
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3;
				end
			end
			else
			begin
				if($signed(acmlt_frac_nml_s3[29:23]) >= 32)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 5;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd5;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) >= 16)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 4;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd4;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) >= 8)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 3;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd3;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) >= 4)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 2;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd2;
				end
				else if($signed(acmlt_frac_nml_s3[29:23]) >= 2)
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3 >>> 1;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3 + 9'sd1;
				end
				else
				begin
					acmlt_frac_nml_s4 <= # SIM_DELAY acmlt_frac_nml_s3;
					acmlt_exp_nml_s4 <= # SIM_DELAY acmlt_exp_nml_s3;
				end
			end
		end
	end
	
	// 累加输出的单精度浮点数
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & acmlt_in_valid_d8)
		begin
			acmlt_out_data_fp16[31] <= # SIM_DELAY acmlt_frac_nml_s4[24];
			acmlt_out_data_fp16[30:23] <= # SIM_DELAY acmlt_exp_nml_s4 + 9'sd127;
			acmlt_out_data_fp16[22:0] <= # SIM_DELAY 
				acmlt_frac_nml_s4[24] ? 
					((~acmlt_frac_nml_s4[22:0]) + 1'b1):
					acmlt_frac_nml_s4[22:0];
		end
	end
	
	/** 复用的有符号加法器输入 **/
	assign adder_0_op1 = 
		(calfmt == CAL_FMT_FP16) ? 
			adder_0_op1_fp16:
			adder_0_op1_int16;
	assign adder_0_op2 = 
		(calfmt == CAL_FMT_FP16) ? 
			adder_0_op2_fp16:
			adder_0_op2_int16;
	assign adder_0_ce = 
		((calfmt == CAL_FMT_FP16) & adder_0_ce_fp16) | 
		((calfmt == CAL_FMT_INT16) & adder_0_ce_int16);
	
	/** 中间结果累加输出 **/
	assign acmlt_out_data = 
		(calfmt == CAL_FMT_FP16) ? 
			acmlt_out_data_fp16:
			acmlt_out_data_int16;
	assign acmlt_out_valid = 
		((calfmt == CAL_FMT_FP16) & acmlt_out_valid_fp16) | 
		((calfmt == CAL_FMT_INT16) & acmlt_out_valid_int16);
	
endmodule
