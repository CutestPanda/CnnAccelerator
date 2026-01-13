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
本模块: 二次幂计算单元

描述:
计算x^2

支持INT16、INT32、FP32三种运算数据格式

带有全局时钟使能

-------------------------------------
| 运算数据格式支持情况 | 乘法器位宽 |
-------------------------------------
| 支持INT32或FP32      | s32 * s32  |
-------------------------------------
| 不支持INT32与FP32    | s16 * s16  |
-------------------------------------

-------------------------------------
|     运算数据格式     |    时延    |
-------------------------------------
|     INT16或INT32     |     8      |
-------------------------------------
|         FP32         |     7      |
-------------------------------------

注意:
浮点运算未考虑INF和NAN
若操作数X < 2^-63, 则将结果设为0

外部有符号乘法器的时延 = 3clk

当运算数据格式为INT16或INT32时, 操作数X的量化精度为fixed_point_quat_accrc

协议:
无

作者: 陈家耀
日期: 2026/01/07
********************************************************************/


module pow2_cell #(
	parameter INT16_SUPPORTED = 1'b0, // 是否支持INT16运算数据格式
	parameter INT32_SUPPORTED = 1'b1, // 是否支持INT32运算数据格式
	parameter FP32_SUPPORTED = 1'b1, // 是否支持FP32运算数据格式
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽
	parameter EN_ROUND = 1'b1, // 是否需要进行四舍五入
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 控制信号
	input wire bypass, // 旁路本单元
	
	// 运行时参数
	input wire[1:0] pow2_calfmt, // 运算数据格式
	input wire[4:0] fixed_point_quat_accrc, // 定点数量化精度
	
	// 二次幂计算单元计算输入
	input wire[31:0] pow2_cell_i_op_x, // 操作数X
	input wire pow2_cell_i_pass, // 直接传递操作数X(标志)
	input wire[INFO_ALONG_WIDTH-1:0] pow2_cell_i_info_along, // 随路数据
	input wire pow2_cell_i_vld,
	
	// 二次幂计算单元结果输出
	output wire[31:0] pow2_cell_o_res, // 计算结果
	output wire[INFO_ALONG_WIDTH-1:0] pow2_cell_o_info_along, // 随路数据
	output wire pow2_cell_o_vld,
	
	// 外部有符号乘法器
	output wire mul_clk,
	output wire[((INT32_SUPPORTED | FP32_SUPPORTED) ? 32:16)-1:0] mul_op_a, // 操作数A
	output wire[((INT32_SUPPORTED | FP32_SUPPORTED) ? 32:16)-1:0] mul_op_b, // 操作数B
	output wire[2:0] mul_ce, // 计算使能
	input wire[((INT32_SUPPORTED | FP32_SUPPORTED) ? 64:32)-1:0] mul_res // 计算结果
);
	
	/** 常量 **/
	// 外部有符号乘法器的位宽
	localparam integer MUL_OP_WIDTH = (INT32_SUPPORTED | FP32_SUPPORTED) ? 32:16; // 操作数位宽
	localparam integer MUL_RES_WIDTH = MUL_OP_WIDTH * 2; // 结果位宽
	// 运算数据格式的编码
	localparam POW2_CAL_FMT_INT16 = 2'b00;
	localparam POW2_CAL_FMT_INT32 = 2'b01;
	localparam POW2_CAL_FMT_FP32 = 2'b10;
	localparam POW2_CAL_FMT_NONE = 2'b11;
	
	/** 运算数据格式 **/
	wire[1:0] pow2_calfmt_inner;
	
	assign pow2_calfmt_inner = 
		(INT16_SUPPORTED & (pow2_calfmt == POW2_CAL_FMT_INT16)) ? POW2_CAL_FMT_INT16:
		(INT32_SUPPORTED & (pow2_calfmt == POW2_CAL_FMT_INT32)) ? POW2_CAL_FMT_INT32:
		(FP32_SUPPORTED  & (pow2_calfmt == POW2_CAL_FMT_FP32))  ? POW2_CAL_FMT_FP32:
		                                                          POW2_CAL_FMT_NONE;
	
	/** 输入信号延迟链 **/
	reg[7:1] pow2_cell_i_vld_delayed;
	reg[7:1] pow2_cell_i_pass_delayed;
	reg[31:0] pow2_cell_i_op_x_delayed[1:7];
	reg[INFO_ALONG_WIDTH-1:0] pow2_cell_i_info_along_delayed[1:7];
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pow2_cell_i_vld_delayed <= 7'b0000000;
		else if(aclken)
			pow2_cell_i_vld_delayed <= # SIM_DELAY 
				{pow2_cell_i_vld_delayed[6:1], pow2_cell_i_vld};
	end
	
	genvar payload_delayed_i;
	generate
		for(payload_delayed_i = 0;payload_delayed_i < 7;payload_delayed_i = payload_delayed_i + 1)
		begin:payload_delayed_blk
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						(payload_delayed_i == 0) ? 
							pow2_cell_i_vld:
							pow2_cell_i_vld_delayed[payload_delayed_i]
					)
				)
					pow2_cell_i_pass_delayed[payload_delayed_i+1] <= # SIM_DELAY 
						(payload_delayed_i == 0) ? 
							pow2_cell_i_pass:
							pow2_cell_i_pass_delayed[payload_delayed_i];
			end
			
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						(payload_delayed_i == 0) ? 
							pow2_cell_i_vld:
							pow2_cell_i_vld_delayed[payload_delayed_i]
					)
				)
					pow2_cell_i_op_x_delayed[payload_delayed_i+1] <= # SIM_DELAY 
						(payload_delayed_i == 0) ? 
							pow2_cell_i_op_x:
							pow2_cell_i_op_x_delayed[payload_delayed_i];
			end
			
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						(payload_delayed_i == 0) ? 
							pow2_cell_i_vld:
							pow2_cell_i_vld_delayed[payload_delayed_i]
					)
				)
					pow2_cell_i_info_along_delayed[payload_delayed_i+1] <= # SIM_DELAY 
						(payload_delayed_i == 0) ? 
							pow2_cell_i_info_along:
							pow2_cell_i_info_along_delayed[payload_delayed_i];
			end
		end
	endgenerate
	
	/** 共享递增器#0 **/
	wire signed[31:0] shared_incr_0_op_a;
	wire shared_incr_0_op_b;
	wire signed[31:0] shared_incr_0_res;
	
	assign shared_incr_0_res = shared_incr_0_op_a + shared_incr_0_op_b;
	
	/**
	整型运算
	
	---------------------------------------------------------------------
	| 流水线级 |        完成的内容         |            备注            |
	---------------------------------------------------------------------
	|   1~4    | 计算: 操作数X * 操作数X   | s16 * s16或s32 * s32       |
	---------------------------------------------------------------------
	|    5     | 四舍五入(向最近偶数舍入)  |                            |
	---------------------------------------------------------------------
	|    6     | 溢出判断                  |                            |
	|          | 计算: 平方结果 + 舍入进位 |                            |
	---------------------------------------------------------------------
	|    7     | 溢出饱和化处理            |                            |
	---------------------------------------------------------------------
	**/
	// [计算整数相乘]
	wire signed[MUL_OP_WIDTH-1:0] int_mul_op;
	wire int_mul_in_vld;
	wire signed[63:0] int_mul_res;
	// [四舍五入(向最近偶数舍入)]
	wire int_round_in_vld;
	wire int_round_in_pass;
	wire[33:0] int_round_in_lsb_mask; // 最低有效位掩码
	wire[33:0] int_round_in_round_bit_mask; // 舍入位掩码
	wire[33:0] int_round_in_guard_bit_mask; // 保护位掩码
	reg int_round_to_fwd_carry; // 四舍五入向前进位(标志)
	reg signed[63:0] int_round_arsh_res; // 算术右移后的平方结果
	// [溢出判断]
	wire int_sat_s1_in_vld;
	wire int_sat_s1_in_pass;
	wire signed[31:0] int_shared_incr_0_op_a;
	wire int_shared_incr_0_op_b;
	reg int_sat_s1_in_ovf_flag; // 上溢标志
	reg signed[31:0] int_sat_s1_carry_added; // 四舍五入的平方结果
	// [溢出饱和化处理]
	wire int_sat_s2_in_vld;
	wire int_sat_s2_in_pass;
	wire signed[31:0] int_sat_s2_in_op_x;
	reg signed[31:0] int_sat_s2_res; // 溢出饱和化处理后的结果
	// [最终结果]
	wire int_fnl_out_vld;
	wire signed[31:0] int_fnl_out_res; // 最终的计算结果
	wire[INFO_ALONG_WIDTH-1:0] int_fnl_out_info_along;
	
	generate
		if(MUL_OP_WIDTH == 32)
		begin
			assign int_mul_op = 
				(pow2_calfmt_inner == POW2_CAL_FMT_INT16) ? 
					{{16{pow2_cell_i_op_x[15]}}, pow2_cell_i_op_x[15:0]}:
					pow2_cell_i_op_x[31:0];
			assign int_mul_res = 
				mul_res[63:0];
		end
		else
		begin
			assign int_mul_op = pow2_cell_i_op_x[15:0];
			assign int_mul_res = 
				{32'd0, mul_res[31:0]};
		end
	endgenerate
	
	assign int_mul_in_vld = 
		((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & 
		pow2_cell_i_vld & (~pow2_cell_i_pass);
	
	assign int_round_in_vld = 
		((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & 
		pow2_cell_i_vld_delayed[4];
	assign int_round_in_pass = pow2_cell_i_pass_delayed[4];
	assign int_round_in_lsb_mask = {32'd1, 1'b0, 1'b0} << fixed_point_quat_accrc;
	assign int_round_in_round_bit_mask = {32'd0, 1'b1, 1'b0} << fixed_point_quat_accrc;
	assign int_round_in_guard_bit_mask = ({32'd0, 1'b1, 1'b0} << fixed_point_quat_accrc) - 1;
	
	assign int_sat_s1_in_vld = 
		((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & 
		pow2_cell_i_vld_delayed[5];
	assign int_sat_s1_in_pass = pow2_cell_i_pass_delayed[5];
	assign int_shared_incr_0_op_a = int_round_arsh_res[31:0];
	assign int_shared_incr_0_op_b = int_round_to_fwd_carry;
	
	assign int_sat_s2_in_vld = 
		((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & 
		pow2_cell_i_vld_delayed[6];
	assign int_sat_s2_in_pass = pow2_cell_i_pass_delayed[6];
	assign int_sat_s2_in_op_x = pow2_cell_i_op_x_delayed[6];
	
	assign int_fnl_out_vld = 
		((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & 
		pow2_cell_i_vld_delayed[7];
	assign int_fnl_out_res = 
		int_sat_s2_res;
	assign int_fnl_out_info_along = 
		pow2_cell_i_info_along_delayed[7];
	
	// 四舍五入向前进位(标志)
	always @(posedge aclk)
	begin
		if(aclken & int_round_in_vld & (~int_round_in_pass))
			int_round_to_fwd_carry <= # SIM_DELAY 
				EN_ROUND & 
				(|({int_mul_res[31:0], 2'b00} & int_round_in_round_bit_mask)) & // 舍入位为1
				(
					(|({int_mul_res[31:0], 2'b00} & int_round_in_guard_bit_mask)) | // 保护位不全0
					(|({int_mul_res[31:0], 2'b00} & int_round_in_lsb_mask)) // LSB为1
				);
	end
	// 算术右移后的平方结果
	always @(posedge aclk)
	begin
		if(aclken & int_round_in_vld & (~int_round_in_pass))
			int_round_arsh_res <= # SIM_DELAY 
				// 平方结果必定非负, 使用逻辑右移即可
				int_mul_res >> fixed_point_quat_accrc;
	end
	
	// 上溢标志
	always @(posedge aclk)
	begin
		if(aclken & int_sat_s1_in_vld & (~int_sat_s1_in_pass))
			int_sat_s1_in_ovf_flag <= # SIM_DELAY 
				// 算术右移后的平方结果必定非负, 无需检查符号位
				(
					(pow2_calfmt_inner == POW2_CAL_FMT_INT32) & 
					((|int_round_arsh_res[62:31]) | ((&int_round_arsh_res[30:0]) & int_round_to_fwd_carry))
				) | 
				(
					(pow2_calfmt_inner == POW2_CAL_FMT_INT16) & 
					((|int_round_arsh_res[62:15]) | ((&int_round_arsh_res[14:0]) & int_round_to_fwd_carry))
				);
	end
	// 四舍五入的平方结果
	always @(posedge aclk)
	begin
		if(aclken & int_sat_s1_in_vld & (~int_sat_s1_in_pass))
			int_sat_s1_carry_added <= # SIM_DELAY 
				shared_incr_0_res;
	end
	
	// 溢出饱和化处理后的结果
	always @(posedge aclk)
	begin
		if(aclken & int_sat_s2_in_vld)
			int_sat_s2_res <= # SIM_DELAY 
				int_sat_s2_in_pass ? 
					int_sat_s2_in_op_x:
					(
						(
							{32{pow2_calfmt_inner == POW2_CAL_FMT_INT32}} & 
							(
								int_sat_s1_in_ovf_flag ? 
									32'h7fff_ffff:
									int_sat_s1_carry_added
							)
						) | 
						(
							{32{pow2_calfmt_inner == POW2_CAL_FMT_INT16}} & 
							(
								int_sat_s1_in_ovf_flag ? 
									32'h0000_7fff:
									int_sat_s1_carry_added
							)
						)
					);
	end
	
	/**
	浮点运算
	
	---------------------------------------------------------------------
	| 流水线级 |        完成的内容         |            备注            |
	---------------------------------------------------------------------
	|   1~4    | 计算: 尾数相乘            | s25 * s25                  |
	---------------------------------------------------------------------
	|    5     | 四舍五入(向最近偶数舍入)  |                            |
	---------------------------------------------------------------------
	|    6     | 右规与浮点数打包          |                            |
	---------------------------------------------------------------------
	**/
	// [尾数相乘]
	wire signed[MUL_OP_WIDTH-1:0] fp_mul_op;
	wire fp_mul_in_vld;
	wire[49:0] fp_mul_res;
	// [四舍五入(向最近偶数舍入)]
	wire fp_round_in_vld;
	wire fp_round_in_pass;
	wire fp_round_in_to_fwd_carry; // 四舍五入向前进位(标志)
	wire signed[31:0] fp_shared_incr_0_op_a;
	wire fp_shared_incr_0_op_b;
	reg[25:0] fp_round_res; // 四舍五入后的尾数相乘结果(Q23)
	// [右规与浮点数打包]
	wire fp_pack_in_vld;
	wire fp_pack_in_pass;
	wire[31:0] fp_pack_in_op_x;
	reg fp_pack_sign; // 打包后的符号位
	reg[24:0] fp_pack_mts; // 右规后的尾数(Q23)
	reg[7:0] fp_pack_ec; // 右规后的阶码
	// [最终结果]
	wire fp_fnl_out_vld;
	wire[31:0] fp_fnl_out_res; // 最终的计算结果
	wire[INFO_ALONG_WIDTH-1:0] fp_fnl_out_info_along;
	
	generate
		if(MUL_OP_WIDTH == 32)
		begin
			assign fp_mul_op = {7'd0, 1'b0, pow2_cell_i_op_x[30:23] != 8'd0, pow2_cell_i_op_x[22:0]};
			assign fp_mul_in_vld = 
				(pow2_calfmt_inner == POW2_CAL_FMT_FP32) & 
				pow2_cell_i_vld & (~pow2_cell_i_pass);
			assign fp_mul_res = mul_res[49:0];
		end
		else
		begin
			assign fp_mul_op = {MUL_OP_WIDTH{1'bx}};
			assign fp_mul_in_vld = 1'b0;
			assign fp_mul_res = 64'dx;
		end
	endgenerate
	
	assign fp_round_in_vld = 
		(pow2_calfmt_inner == POW2_CAL_FMT_FP32) & 
		pow2_cell_i_vld_delayed[4];
	assign fp_round_in_pass = pow2_cell_i_pass_delayed[4];
	assign fp_round_in_to_fwd_carry = 
		EN_ROUND & 
		fp_mul_res[22] & // 舍入位为1
		(
			(|fp_mul_res[21:0]) | // 保护位不全0
			fp_mul_res[23] // LSB为1
		);
	assign fp_shared_incr_0_op_a = fp_mul_res[48:23] | 32'd0;
	assign fp_shared_incr_0_op_b = fp_round_in_to_fwd_carry;
	
	assign fp_pack_in_vld = 
		(pow2_calfmt_inner == POW2_CAL_FMT_FP32) & 
		pow2_cell_i_vld_delayed[5];
	assign fp_pack_in_pass = pow2_cell_i_pass_delayed[5];
	assign fp_pack_in_op_x = pow2_cell_i_op_x_delayed[5];
	
	assign fp_fnl_out_vld = 
		(pow2_calfmt_inner == POW2_CAL_FMT_FP32) & 
		pow2_cell_i_vld_delayed[6];
	assign fp_fnl_out_res = 
		{fp_pack_sign, fp_pack_ec[7:0], fp_pack_mts[22:0]};
	assign fp_fnl_out_info_along = 
		pow2_cell_i_info_along_delayed[6];
	
	// 四舍五入后的尾数相乘结果(Q23)
	always @(posedge aclk)
	begin
		if(aclken & fp_round_in_vld & (~fp_round_in_pass))
			fp_round_res <= # SIM_DELAY 
				shared_incr_0_res[25:0];
	end
	
	// 打包后的符号位
	always @(posedge aclk)
	begin
		if(aclken & fp_pack_in_vld)
			fp_pack_sign <= # SIM_DELAY 
				fp_pack_in_pass & fp_pack_in_op_x[31];
	end
	
	// 右规后的尾数(Q23)
	always @(posedge aclk)
	begin
		if(aclken & fp_pack_in_vld)
			fp_pack_mts <= # SIM_DELAY 
				fp_pack_in_pass ? 
					{1'b0, fp_pack_in_op_x[30:23] != 8'd0, fp_pack_in_op_x[22:0]}:
					(
						(fp_pack_in_op_x[30:23] < 8'd64) ? 
							// 操作数X < 2^-63, 将右规后的尾数设为0
							{1'b0, 1'b0, 23'd0}:
							(
								fp_round_res[24] ? 
									// 四舍五入后的尾数相乘结果在范围[2, 4)内, 对其右移1位
									fp_round_res[25:1]:
									// 四舍五入后的尾数相乘结果在范围[1, 2)内
									fp_round_res[24:0]
							)
					);
	end
	// 右规后的阶码
	always @(posedge aclk)
	begin
		if(aclken & fp_pack_in_vld)
			fp_pack_ec <= # SIM_DELAY 
				fp_pack_in_pass ? 
					fp_pack_in_op_x[30:23]:
					(
						(fp_pack_in_op_x[30:23] < 8'd64) ? 
							// 操作数X < 2^-63, 将右规后的阶码设为0
							8'd0:
							(
								fp_round_res[24] ? 
									// 四舍五入后的尾数相乘结果在范围[2, 4)内, 右规后的指数 = 原指数 * 2 + 1
									({fp_pack_in_op_x[30:23], 1'b0} - 127 + 1):
									// 四舍五入后的尾数相乘结果在范围[1, 2)内, 右规后的指数 = 原指数 * 2
									({fp_pack_in_op_x[30:23], 1'b0} - 127)
							)
					);
	end
	
	/** 计算单元复用 **/
	reg[MUL_OP_WIDTH-1:0] mul_op_r;
	reg[2:0] mul_ce_r;
	
	assign mul_clk = aclk;
	assign mul_op_a = mul_op_r;
	assign mul_op_b = mul_op_r;
	assign mul_ce = {3{aclken}} & mul_ce_r;
	
	assign shared_incr_0_op_a = 
		({32{(pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)}} & int_shared_incr_0_op_a) | 
		({32{pow2_calfmt_inner == POW2_CAL_FMT_FP32}} & fp_shared_incr_0_op_a);
	assign shared_incr_0_op_b = 
		(((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & int_shared_incr_0_op_b) | 
		((pow2_calfmt_inner == POW2_CAL_FMT_FP32) & fp_shared_incr_0_op_b);
	
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & int_mul_in_vld) | 
				((pow2_calfmt_inner == POW2_CAL_FMT_FP32) & fp_mul_in_vld)
			)
		)
			mul_op_r <= # SIM_DELAY 
				({MUL_OP_WIDTH{(pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)}} & int_mul_op) | 
				({MUL_OP_WIDTH{pow2_calfmt_inner == POW2_CAL_FMT_FP32}} & fp_mul_op);
	end
	
	always @(posedge aclk)
	begin
		if(aclken)
			mul_ce_r <= # SIM_DELAY 
				{
					mul_ce_r[1:0],
					(((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & int_mul_in_vld) | 
					((pow2_calfmt_inner == POW2_CAL_FMT_FP32) & fp_mul_in_vld)
				};
	end
	
	/** 二次幂计算单元结果输出 **/
	reg[31:0] pow2_cell_o_res_r;
	reg[INFO_ALONG_WIDTH-1:0] pow2_cell_o_info_along_r;
	reg pow2_cell_o_vld_r;
	
	assign pow2_cell_o_res = pow2_cell_o_res_r;
	assign pow2_cell_o_info_along = pow2_cell_o_info_along_r;
	assign pow2_cell_o_vld = pow2_cell_o_vld_r;
	
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				bypass ? 
					pow2_cell_i_vld:
					(
						(((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & int_fnl_out_vld) | 
						((pow2_calfmt_inner == POW2_CAL_FMT_FP32) & fp_fnl_out_vld)
					)
			)
		)
		begin
			pow2_cell_o_res_r <= # SIM_DELAY 
				bypass ? 
					pow2_cell_i_op_x:
					(
						({32{(pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)}} & int_fnl_out_res) | 
						({32{pow2_calfmt_inner == POW2_CAL_FMT_FP32}} & fp_fnl_out_res)
					);
			
			pow2_cell_o_info_along_r <= # SIM_DELAY 
				bypass ? 
					pow2_cell_i_info_along:
					(
						({INFO_ALONG_WIDTH{(pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)}} & int_fnl_out_info_along) | 
						({INFO_ALONG_WIDTH{pow2_calfmt_inner == POW2_CAL_FMT_FP32}} & fp_fnl_out_info_along)
					);
		end
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pow2_cell_o_vld_r <= 1'b0;
		else if(aclken)
			pow2_cell_o_vld_r <= # SIM_DELAY 
				bypass ? 
					pow2_cell_i_vld:
					(
						(((pow2_calfmt_inner == POW2_CAL_FMT_INT32) | (pow2_calfmt_inner == POW2_CAL_FMT_INT16)) & int_fnl_out_vld) | 
						((pow2_calfmt_inner == POW2_CAL_FMT_FP32) & fp_fnl_out_vld)
					);
	end
	
endmodule
