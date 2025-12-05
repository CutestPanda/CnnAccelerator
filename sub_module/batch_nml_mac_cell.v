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
本模块: 批归一化乘加单元

描述:
计算ax + b

支持INT16、INT32、FP32三种运算数据格式

带有全局时钟使能

-------------------------------------------------------------------------------------
| 是否支持INT16运算数据格式 | 是否支持INT32运算数据格式 |      乘法器使用情况       |
-------------------------------------------------------------------------------------
|              是           |             ---           | 当运算数据格式为INT16时   |
|                           |                           | 仅使用s18乘法器#0,        |
|                           |                           | 其余情况使用4个s18乘法器  |
-------------------------------------------------------------------------------------
|              否           |              是           | 固定使用1个s32乘法器      |
|                           |---------------------------|---------------------------|
|                           |              否           | 固定使用1个s25乘法器      |
-------------------------------------------------------------------------------------

-----------------------
|   数据格式   | 时延 |
-----------------------
| INT16或INT32 |  7   |
-----------------------
|     FP32     |  8   |
-----------------------

注意:
--------------------------------------------------------------
|   是否支持INT16运算数据格式   | 外部有符号乘法器的计算时延 |
--------------------------------------------------------------
|              是               |              1             |
--------------------------------------------------------------
|              否               |              3             |
--------------------------------------------------------------

浮点运算未考虑INF和NAN

协议:
无

作者: 陈家耀
日期: 2025/12/04
********************************************************************/


module batch_nml_mac_cell #(
	parameter INT16_SUPPORTED = 1'b0, // 是否支持INT16运算数据格式
	parameter INT32_SUPPORTED = 1'b1, // 是否支持INT32运算数据格式
	parameter FP32_SUPPORTED = 1'b1, // 是否支持FP32运算数据格式
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] bn_calfmt, // 运算数据格式
	input wire[4:0] fixed_point_quat_accrc, // 定点数量化精度
	
	// 乘加单元计算输入
	input wire[31:0] mac_cell_i_op_a, // 操作数A
	input wire[31:0] mac_cell_i_op_x, // 操作数X
	input wire[31:0] mac_cell_i_op_b, // 操作数B
	input wire mac_cell_i_is_a_eq_1, // 参数A的实际值为1(标志)
	input wire mac_cell_i_is_b_eq_0, // 参数B的实际值为0(标志)
	input wire[INFO_ALONG_WIDTH-1:0] mac_cell_i_info_along, // 随路数据
	input wire mac_cell_i_vld,
	
	// 乘加单元结果输出
	output wire[31:0] mac_cell_o_res, // 计算结果
	output wire[INFO_ALONG_WIDTH-1:0] mac_cell_o_info_along, // 随路数据
	output wire mac_cell_o_vld,
	
	// 外部有符号乘法器
	output wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))-1:0] mul_op_a, // 操作数A
	output wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))-1:0] mul_op_b, // 操作数B
	output wire[(INT16_SUPPORTED ? 4:3)-1:0] mul_ce, // 计算使能
	input wire[(INT16_SUPPORTED ? 4*36:(INT32_SUPPORTED ? 64:50))-1:0] mul_res // 计算结果
);
	
	/** 常量 **/
	// 运算数据格式的编码
	localparam BN_CAL_FMT_INT16 = 2'b00;
	localparam BN_CAL_FMT_INT32 = 2'b01;
	localparam BN_CAL_FMT_FP32 = 2'b10;
	localparam BN_CAL_FMT_NONE = 2'b11;
	
	/** 运算数据格式 **/
	wire[1:0] bn_calfmt_inner;
	
	assign bn_calfmt_inner = 
		(INT16_SUPPORTED & (bn_calfmt == BN_CAL_FMT_INT16)) ? BN_CAL_FMT_INT16:
		(INT32_SUPPORTED & (bn_calfmt == BN_CAL_FMT_INT32)) ? BN_CAL_FMT_INT32:
		(FP32_SUPPORTED & (bn_calfmt == BN_CAL_FMT_FP32))   ? BN_CAL_FMT_FP32:
		                                                      BN_CAL_FMT_NONE;
	
	/** 共享乘法器 **/
	// [整型运算给出的乘法器输入]
	wire[17:0] int_mac_mul_op_a[3:0];
	wire[17:0] int_mac_mul_op_b[3:0];
	wire[3:0] int_mac_mul_ce;
	// [浮点运算给出的乘法器输入]
	wire[17:0] fp_mac_mul_op_a[3:0];
	wire[17:0] fp_mac_mul_op_b[3:0];
	wire[3:0] fp_mac_mul_ce;
	// [外部有符号乘法器输入]
	reg[17:0] mul_op_a_r[3:0];
	reg[17:0] mul_op_b_r[3:0];
	reg[3:0] mul_in_vld_r;
	
	assign mul_op_a = 
		INT16_SUPPORTED ? 
			{mul_op_a_r[3], mul_op_a_r[2], mul_op_a_r[1], mul_op_a_r[0]}:
			{mul_op_a_r[2][(INT32_SUPPORTED ? 16:9)-1:0], mul_op_a_r[0][15:0]};
	assign mul_op_b = 
		INT16_SUPPORTED ? 
			{mul_op_b_r[3], mul_op_b_r[2], mul_op_b_r[1], mul_op_b_r[0]}:
			{mul_op_b_r[1][(INT32_SUPPORTED ? 16:9)-1:0], mul_op_b_r[0][15:0]};
	
	genvar mul_in_i;
	generate
		for(mul_in_i = 0;mul_in_i < 4;mul_in_i = mul_in_i + 1)
		begin:mul_in_blk
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
							fp_mac_mul_ce[mul_in_i]:
							int_mac_mul_ce[mul_in_i]
					)
				)
				begin
					mul_op_a_r[mul_in_i] <= # SIM_DELAY 
						(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
							fp_mac_mul_op_a[mul_in_i]:
							int_mac_mul_op_a[mul_in_i];
					
					mul_op_b_r[mul_in_i] <= # SIM_DELAY 
						(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
							fp_mac_mul_op_b[mul_in_i]:
							int_mac_mul_op_b[mul_in_i];
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					mul_in_vld_r[mul_in_i] <= 1'b0;
				else if(aclken)
					mul_in_vld_r[mul_in_i] <= # SIM_DELAY 
						(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
							fp_mac_mul_ce[mul_in_i]:
							int_mac_mul_ce[mul_in_i];
			end
		end
	endgenerate
	
	/** 共享加法器#0 **/
	// [整型运算给出的加法器输入]
	wire signed[31:0] int_mac_add_op_a;
	wire signed[31:0] int_mac_add_op_b;
	// [浮点运算给出的加法器输入]
	wire signed[31:0] fp_mac_add_op_a;
	wire signed[31:0] fp_mac_add_op_b;
	// [加法器]
	wire signed[31:0] shared_adder0_op_a;
	wire signed[31:0] shared_adder0_op_b;
	wire signed[32:0] shared_adder0_res;
	
	assign shared_adder0_op_a = 
		(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
			fp_mac_add_op_a:
			int_mac_add_op_a;
	assign shared_adder0_op_b = 
		(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
			fp_mac_add_op_b:
			int_mac_add_op_b;
	
	assign shared_adder0_res = 
		{shared_adder0_op_a[31], shared_adder0_op_a} + 
		{shared_adder0_op_b[31], shared_adder0_op_b};
	
	/** 共享移位器#0 **/
	wire signed[31:0] shared_sh0_op_a;
	wire[4:0] shared_sh0_op_b;
	wire signed[31:0] shared_sh0_res;
	
	assign shared_sh0_res = $signed(shared_sh0_op_a) >>> shared_sh0_op_b;
	
	/** 输入有效指示延迟链 **/
	reg[8:1] mac_cell_i_vld_delayed; // 延迟的输入有效指示
	
	// 延迟的输入有效指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mac_cell_i_vld_delayed <= 8'b00000000;
		else if(aclken)
			mac_cell_i_vld_delayed <= # SIM_DELAY {mac_cell_i_vld_delayed[7:1], mac_cell_i_vld};
	end
	
	/** 参数特例标志延迟链 **/
	reg[4:1] mac_cell_i_is_a_eq_1_delayed; // 延迟的参数A的实际值为1(标志)
	reg[6:1] mac_cell_i_is_b_eq_0_delayed; // 延迟的参数B的实际值为0(标志)
	
	// 延迟的参数A的实际值为1(标志)
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld)
			mac_cell_i_is_a_eq_1_delayed[1] <= # SIM_DELAY mac_cell_i_is_a_eq_1;
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[1])
			mac_cell_i_is_a_eq_1_delayed[2] <= # SIM_DELAY mac_cell_i_is_a_eq_1_delayed[1];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[2])
			mac_cell_i_is_a_eq_1_delayed[3] <= # SIM_DELAY mac_cell_i_is_a_eq_1_delayed[2];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[3])
			mac_cell_i_is_a_eq_1_delayed[4] <= # SIM_DELAY mac_cell_i_is_a_eq_1_delayed[3];
	end
	
	// 延迟的参数B的实际值为0(标志)
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld)
			mac_cell_i_is_b_eq_0_delayed[1] <= # SIM_DELAY mac_cell_i_is_b_eq_0;
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[1])
			mac_cell_i_is_b_eq_0_delayed[2] <= # SIM_DELAY mac_cell_i_is_b_eq_0_delayed[1];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[2])
			mac_cell_i_is_b_eq_0_delayed[3] <= # SIM_DELAY mac_cell_i_is_b_eq_0_delayed[2];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[3])
			mac_cell_i_is_b_eq_0_delayed[4] <= # SIM_DELAY mac_cell_i_is_b_eq_0_delayed[3];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[4])
			mac_cell_i_is_b_eq_0_delayed[5] <= # SIM_DELAY mac_cell_i_is_b_eq_0_delayed[4];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[5])
			mac_cell_i_is_b_eq_0_delayed[6] <= # SIM_DELAY mac_cell_i_is_b_eq_0_delayed[5];
	end
	
	/** 操作数延迟链 **/
	reg signed[31:0] mac_cell_i_op_x_delayed[1:4]; // 延迟的操作数X
	reg signed[31:0] mac_cell_i_op_b_delayed[1:6]; // 延迟的操作数B
	
	// 延迟的操作数X
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld)
			mac_cell_i_op_x_delayed[1] <= # SIM_DELAY mac_cell_i_op_x;
	end
	
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[1])
			mac_cell_i_op_x_delayed[2] <= # SIM_DELAY mac_cell_i_op_x_delayed[1];
	end
	
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[2])
			mac_cell_i_op_x_delayed[3] <= # SIM_DELAY mac_cell_i_op_x_delayed[2];
	end
	
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[3])
			mac_cell_i_op_x_delayed[4] <= # SIM_DELAY mac_cell_i_op_x_delayed[3];
	end
	
	// 延迟的操作数B
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld & (~mac_cell_i_is_b_eq_0))
			mac_cell_i_op_b_delayed[1] <= # SIM_DELAY mac_cell_i_op_b;
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[1] & (~mac_cell_i_is_b_eq_0_delayed[1]))
			mac_cell_i_op_b_delayed[2] <= # SIM_DELAY mac_cell_i_op_b_delayed[1];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[2] & (~mac_cell_i_is_b_eq_0_delayed[2]))
			mac_cell_i_op_b_delayed[3] <= # SIM_DELAY mac_cell_i_op_b_delayed[2];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[3] & (~mac_cell_i_is_b_eq_0_delayed[3]))
			mac_cell_i_op_b_delayed[4] <= # SIM_DELAY mac_cell_i_op_b_delayed[3];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[4] & (~mac_cell_i_is_b_eq_0_delayed[4]))
			mac_cell_i_op_b_delayed[5] <= # SIM_DELAY mac_cell_i_op_b_delayed[4];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[5] & (~mac_cell_i_is_b_eq_0_delayed[5]))
			mac_cell_i_op_b_delayed[6] <= # SIM_DELAY mac_cell_i_op_b_delayed[5];
	end
	
	/** 随路数据延迟链 **/
	reg[INFO_ALONG_WIDTH-1:0] mac_cell_i_info_along_delayed[1:8];
	
	// 延迟的随路数据
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			mac_cell_i_info_along_delayed[1] <= # SIM_DELAY mac_cell_i_info_along;
			mac_cell_i_info_along_delayed[2] <= # SIM_DELAY mac_cell_i_info_along_delayed[1];
			mac_cell_i_info_along_delayed[3] <= # SIM_DELAY mac_cell_i_info_along_delayed[2];
			mac_cell_i_info_along_delayed[4] <= # SIM_DELAY mac_cell_i_info_along_delayed[3];
			mac_cell_i_info_along_delayed[5] <= # SIM_DELAY mac_cell_i_info_along_delayed[4];
			mac_cell_i_info_along_delayed[6] <= # SIM_DELAY mac_cell_i_info_along_delayed[5];
			mac_cell_i_info_along_delayed[7] <= # SIM_DELAY mac_cell_i_info_along_delayed[6];
			mac_cell_i_info_along_delayed[8] <= # SIM_DELAY mac_cell_i_info_along_delayed[7];
		end
	end
	
	/**
	部分积求和
	
	         |<---16--->|<---16--->|<---16--->|<---16--->|
	部分积#0                       |*********************|
	部分积#1 |----------**********************|
	部分积#2 |----------**********************|
	部分积#3 |*********************|
	
	2级流水线
	**/
	wire partial_product_adder_in_vld;
	wire partial_product_adder_in_vld_d1;
	wire partial_product_adder_out_vld;
	wire partial_product_adder_in_mask;
	wire partial_product_adder_in_mask_d1;
	wire[31:0] partial_product_arr[3:0]; // 部分积
	reg[31:0] partial_product_d1[3:0]; // 延迟1clk的部分积
	reg[31:0] partial_product_d2[3:0]; // 延迟2clk的部分积
	reg[47:0] partial_product_add_0; // 第1次求和的部分积
	reg[47:0] partial_product_add_1; // 第2次求和的部分积
	wire signed[63:0] partial_product_add_res; // 部分积求和结果
	
	assign mul_ce = 
		INT16_SUPPORTED ? 
			({4{aclken}} & mul_in_vld_r):
			(
				{3{aclken}} & 
				{
					partial_product_adder_in_vld_d1 & (~partial_product_adder_in_mask_d1),
					partial_product_adder_in_vld & (~partial_product_adder_in_mask),
					mul_in_vld_r[0]
				}
			);
	
	assign partial_product_adder_in_vld = mac_cell_i_vld_delayed[2];
	assign partial_product_adder_in_vld_d1 = mac_cell_i_vld_delayed[3];
	assign partial_product_adder_out_vld = mac_cell_i_vld_delayed[4];
	
	assign partial_product_adder_in_mask = (bn_calfmt_inner == BN_CAL_FMT_INT16) | mac_cell_i_is_a_eq_1_delayed[2];
	assign partial_product_adder_in_mask_d1 = (bn_calfmt_inner == BN_CAL_FMT_INT16) | mac_cell_i_is_a_eq_1_delayed[3];
	
	assign partial_product_arr[0] = INT16_SUPPORTED ? mul_res[0*36+31:0*36]:32'dx;
	assign partial_product_arr[1] = INT16_SUPPORTED ? mul_res[1*36+31:1*36]:32'dx;
	assign partial_product_arr[2] = INT16_SUPPORTED ? mul_res[2*36+31:2*36]:32'dx;
	assign partial_product_arr[3] = INT16_SUPPORTED ? mul_res[3*36+31:3*36]:32'dx;
	
	assign partial_product_add_res = 
		INT16_SUPPORTED ? 
			(
				(bn_calfmt_inner == BN_CAL_FMT_INT16) ? 
					{{32{partial_product_d2[0][31]}}, partial_product_d2[0][31:0]}:
					{partial_product_add_1[47:0], partial_product_d2[0][15:0]}
			):
			{
				INT32_SUPPORTED ? 
					mul_res[63:50]:
					{14{mul_res[49]}},
				mul_res[49:0]
			};
	
	// 延迟1clk的部分积
	always @(posedge aclk)
	begin
		if(aclken & partial_product_adder_in_vld & (~partial_product_adder_in_mask))
		begin
			partial_product_d1[0] <= # SIM_DELAY partial_product_arr[0];
			partial_product_d1[1] <= # SIM_DELAY partial_product_arr[1];
			partial_product_d1[2] <= # SIM_DELAY partial_product_arr[2];
			partial_product_d1[3] <= # SIM_DELAY partial_product_arr[3];
		end
	end
	
	// 延迟2clk的部分积
	always @(posedge aclk)
	begin
		if(aclken & partial_product_adder_in_vld_d1 & (~partial_product_adder_in_mask_d1))
		begin
			partial_product_d2[0] <= # SIM_DELAY partial_product_d1[0];
			partial_product_d2[1] <= # SIM_DELAY partial_product_d1[1];
			partial_product_d2[2] <= # SIM_DELAY partial_product_d1[2];
			partial_product_d2[3] <= # SIM_DELAY partial_product_d1[3];
		end
	end
	
	// 第1次求和的部分积
	always @(posedge aclk)
	begin
		if(aclken & partial_product_adder_in_vld & (~partial_product_adder_in_mask))
			partial_product_add_0 <= # SIM_DELAY 
				{partial_product_arr[3][31:0], partial_product_arr[0][31:16]} + 
				{{16{partial_product_arr[1][31]}}, partial_product_arr[1][31:0]};
	end
	
	// 第2次求和的部分积
	always @(posedge aclk)
	begin
		if(aclken & partial_product_adder_in_vld_d1 & (~partial_product_adder_in_mask_d1))
			partial_product_add_1 <= # SIM_DELAY 
				partial_product_add_0[47:0] + 
				{{16{partial_product_d1[2][31]}}, partial_product_d1[2][31:0]};
	end
	
	/**
	整型(INT16或INT32)乘加
	
	--------------------------------------------------------------------------
	| 流水线级 |              完成的逻辑             |         备注          |
	--------------------------------------------------------------------------
	|   1~2    | 计算部分积:                         | 当运算数据格式为INT16 |
	|          |   操作数A[15:0] * 操作数X[15:0]     | 时, A[15:0] * X[15:0] |
	|          |   操作数A[15:0] * 操作数X[31:16]    | 为有符号相乘, 否则为  |
	|          |   操作数A[31:16] * 操作数X[15:0]    | 无符号相乘            |
	|          |   操作数A[31:16] * 操作数X[31:16]   |                       |
	|          |                                     | 若不需要支持          |           
	-------------------------------------------------| INT16运算数据格式, 则 |
	|   3~4    | 对部分积作求和                      | 使用外部s32乘法器     |
	--------------------------------------------------------------------------
	|    5     | 舍入, 对齐小数点                    |                       |
	--------------------------------------------------------------------------
	|    6     | 将A * X的结果限制到32位有符号数     |                       |
	--------------------------------------------------------------------------
	|    7     | 加上B, 溢出饱和化处理               |                       |
	--------------------------------------------------------------------------
	**/
	// [A * X的结果]
	wire int_mac_dec_pt_align_in_vld;
	wire int_mac_dec_pt_align_in_is_a_eq_1;
	wire signed[31:0] int_mac_dec_pt_align_in_op_x;
	wire signed[63:0] int_mac_dec_pt_align_in_mul_res;
	wire signed[63:0] int_mac_dec_pt_align_in_mul_res_shifted;
	reg signed[63:0] int_mac_amx;
	// [将A * X的结果限制到32位有符号数]
	wire int_mac_amx_lmt_in_vld;
	wire signed[63:0] int_mac_amx_lmt_in_amx;
	wire int_mac_amx_lmt_amx_up_ovf;
	wire int_mac_amx_lmt_amx_down_ovf;
	reg signed[31:0] int_mac_amx_lmt_res;
	// [加上B的结果, 最终结果]
	wire int_mac_final_in_vld;
	wire int_mac_final_in_is_b_eq_0;
	wire int_mac_final_out_vld;
	wire[INFO_ALONG_WIDTH-1:0] int_mac_final_out_info_along;
	wire int_mac_final_add_res_up_ovf;
	wire int_mac_final_add_res_down_ovf;
	reg signed[31:0] int_mac_final_res;
	
	// 操作数A[15:0] * 操作数X[15:0]
	assign int_mac_mul_op_a[0] = {{2{(bn_calfmt_inner == BN_CAL_FMT_INT16) & mac_cell_i_op_a[15]}}, mac_cell_i_op_a[15:0]};
	assign int_mac_mul_op_b[0] = {{2{(bn_calfmt_inner == BN_CAL_FMT_INT16) & mac_cell_i_op_x[15]}}, mac_cell_i_op_x[15:0]};
	// 操作数A[15:0] * 操作数X[31:16]
	assign int_mac_mul_op_a[1] = {2'b00, mac_cell_i_op_a[15:0]};
	assign int_mac_mul_op_b[1] = {{2{mac_cell_i_op_x[31]}}, mac_cell_i_op_x[31:16]};
	// 操作数A[31:16] * 操作数X[15:0]
	assign int_mac_mul_op_a[2] = {{2{mac_cell_i_op_a[31]}}, mac_cell_i_op_a[31:16]};
	assign int_mac_mul_op_b[2] = {2'b00, mac_cell_i_op_x[15:0]};
	// 操作数A[31:16] * 操作数X[31:16]
	assign int_mac_mul_op_a[3] = {{2{mac_cell_i_op_a[31]}}, mac_cell_i_op_a[31:16]};
	assign int_mac_mul_op_b[3] = {{2{mac_cell_i_op_x[31]}}, mac_cell_i_op_x[31:16]};
	
	assign int_mac_mul_ce = {4{mac_cell_i_vld & (~mac_cell_i_is_a_eq_1)}} & {{3{bn_calfmt_inner != BN_CAL_FMT_INT16}}, 1'b1};
	
	assign int_mac_add_op_a = 
		int_mac_final_in_vld ? 
			int_mac_amx_lmt_res:
			32'h0000_0000;
	assign int_mac_add_op_b = 
		(int_mac_final_in_vld & (~int_mac_final_in_is_b_eq_0)) ? 
			mac_cell_i_op_b_delayed[6]:
			32'h0000_0000;
	
	assign int_mac_dec_pt_align_in_vld = mac_cell_i_vld_delayed[4];
	assign int_mac_dec_pt_align_in_is_a_eq_1 = mac_cell_i_is_a_eq_1_delayed[4];
	assign int_mac_dec_pt_align_in_op_x = mac_cell_i_op_x_delayed[4];
	assign int_mac_dec_pt_align_in_mul_res = partial_product_add_res;
	assign int_mac_dec_pt_align_in_mul_res_shifted = $signed(int_mac_dec_pt_align_in_mul_res) >>> fixed_point_quat_accrc;
	
	assign int_mac_amx_lmt_in_vld = mac_cell_i_vld_delayed[5];
	assign int_mac_amx_lmt_in_amx = int_mac_amx;
	assign int_mac_amx_lmt_amx_up_ovf = (~int_mac_amx_lmt_in_amx[63]) & (|int_mac_amx_lmt_in_amx[63:31]);
	assign int_mac_amx_lmt_amx_down_ovf = int_mac_amx_lmt_in_amx[63] & (~(&int_mac_amx_lmt_in_amx[63:31]));
	
	assign int_mac_final_in_vld = mac_cell_i_vld_delayed[6];
	assign int_mac_final_in_is_b_eq_0 = mac_cell_i_is_b_eq_0_delayed[6];
	assign int_mac_final_out_vld = mac_cell_i_vld_delayed[7];
	assign int_mac_final_out_info_along = mac_cell_i_info_along_delayed[7];
	assign int_mac_final_add_res_up_ovf = 
		(bn_calfmt_inner == BN_CAL_FMT_INT16) ? 
			((~shared_adder0_res[32]) & (|shared_adder0_res[32:15])):
			((~shared_adder0_res[32]) & shared_adder0_res[31]);
	assign int_mac_final_add_res_down_ovf = 
		(bn_calfmt_inner == BN_CAL_FMT_INT16) ? 
			(shared_adder0_res[32] & (~(&shared_adder0_res[32:15]))):
			(shared_adder0_res[32] & (~shared_adder0_res[31]));
	
	// A * X的结果
	always @(posedge aclk)
	begin
		if(aclken & int_mac_dec_pt_align_in_vld)
			int_mac_amx <= # SIM_DELAY 
				int_mac_dec_pt_align_in_is_a_eq_1 ? 
					{{32{int_mac_dec_pt_align_in_op_x[31]}}, int_mac_dec_pt_align_in_op_x}:
					int_mac_dec_pt_align_in_mul_res_shifted;
	end
	
	// (限幅后)A * X的结果
	always @(posedge aclk)
	begin
		if(aclken & int_mac_amx_lmt_in_vld)
			int_mac_amx_lmt_res <= # SIM_DELAY 
				{
					int_mac_amx_lmt_in_amx[63],
					{31{~int_mac_amx_lmt_amx_down_ovf}} & ({31{int_mac_amx_lmt_amx_up_ovf}} | int_mac_amx_lmt_in_amx[30:0])
				};
	end
	
	// 最终结果
	always @(posedge aclk)
	begin
		if(aclken & int_mac_final_in_vld)
			int_mac_final_res <= # SIM_DELAY 
				{
					shared_adder0_res[32],
					{31{~int_mac_final_add_res_down_ovf}} & ({31{int_mac_final_add_res_up_ovf}} | shared_adder0_res[30:0])
				};
	end
	
	/**
	单精度浮点乘加
	
	--------------------------------------------------------------------------
	| 流水线级 |              完成的逻辑             |         备注          |
	--------------------------------------------------------------------------
	|    1     | 得到尾数相乘的部分积 | 得到AX的指数 | 25位有符号数乘法      |
	-----------|                      |--------------|                       |
	|    2     |                      | AX与B对阶    | 若不需要支持          |
	-------------------------------------------------| INT16运算数据格式, 则 |
	|   3~4    | 对部分积作求和                      | 使用外部s32乘法器     |
	--------------------------------------------------------------------------
	|    5     | 对阶右移                            |                       |
	--------------------------------------------------------------------------
	|    6     | 尾数相加                            |                       |
	--------------------------------------------------------------------------
	|    7     | 标准化                              |                       |
	--------------------------------------------------------------------------
	|    8     | 打包与下溢处理                      |                       |
	--------------------------------------------------------------------------
	**/
	// [输入浮点数的各个部分]
	// (操作数A)
	wire fp_mac_i_op_a_s; // 符号位
	wire[7:0] fp_mac_i_op_a_ec; // 阶码
	wire signed[7:0] fp_mac_i_op_a_exp; // 指数
	wire[22:0] fp_mac_i_op_a_m; // 尾数
	wire signed[24:0] fp_mac_i_op_a_f; // 补码形式的定点尾数(Q23)
	// (操作数X)
	wire fp_mac_i_op_x_s; // 符号位
	wire[7:0] fp_mac_i_op_x_ec; // 阶码
	wire signed[7:0] fp_mac_i_op_x_exp; // 指数
	wire[22:0] fp_mac_i_op_x_m; // 尾数
	wire signed[24:0] fp_mac_i_op_x_f; // 补码形式的定点尾数(Q23)
	reg signed[24:0] fp_mac_i_op_x_f_delayed[1:4]; // 延迟的补码形式的定点尾数(Q23)
	// (操作数B)
	wire fp_mac_i_op_b_s; // 符号位
	wire[4:1] fp_mac_i_op_b_s_delayed; // 延迟的符号位
	wire[7:0] fp_mac_i_op_b_ec; // 阶码
	wire[7:0] fp_mac_i_op_b_ec_delayed[1:4]; // 延迟的阶码
	wire signed[7:0] fp_mac_i_op_b_exp; // 指数
	wire signed[7:0] fp_mac_i_op_b_exp_delayed[1:4]; // 延迟的指数
	wire[22:0] fp_mac_i_op_b_m; // 尾数
	wire[22:0] fp_mac_i_op_b_m_delayed[1:4]; // 延迟的尾数
	wire signed[24:0] fp_mac_i_op_b_f; // 补码形式的定点尾数(Q23)
	wire signed[24:0] fp_mac_i_op_b_f_delayed[1:4]; // 延迟的补码形式的定点尾数(Q23)
	// [AX与B对阶]
	wire fp_mac_exp_alignment_in_vld;
	wire fp_mac_exp_alignment_in_is_b_eq_0;
	wire[5:1] fp_mac_exp_alignment_in_vld_delayed;
	wire fp_mac_is_exp_of_ax_gth_b; // AX的指数 > B的指数(标志)
	reg[4:2] fp_mac_is_exp_of_ax_gth_b_delayed; // 延迟的"AX的指数 > B的指数(标志)"
	wire signed[8:0] fp_mac_exp_aligned; // 对阶后的指数
	reg signed[8:0] fp_mac_exp_aligned_delayed[2:7]; // 延迟的对阶后的指数
	wire[8:0] fp_mac_exp_abs_diff; // AX与B指数的绝对差值
	reg[8:0] fp_mac_exp_abs_diff_delayed[2:4]; // 延迟的AX与B指数的绝对差值
	wire fp_mac_exp_algm_rsh_in_vld;
	wire fp_mac_exp_algm_rsh_in_is_b_eq_0;
	reg signed[31:0] fp_mac_ax_f_after_exp_algm; // 对阶后AX的定点尾数(补码形式, Q29)
	reg signed[31:0] fp_mac_b_f_after_exp_algm; // 对阶后B的定点尾数(补码形式, Q29)
	// [AX运算结果]
	wire fp_mac_ax_exp_in_vld;
	wire[3:1] fp_mac_ax_exp_in_vld_delayed;
	wire fp_mac_ax_exp_in_is_a_eq_1;
	wire[4:1] fp_mac_ax_exp_in_is_a_eq_1_delayed;
	reg signed[8:0] fp_mac_ax_exp_res; // 指数
	wire signed[48:0] fp_mac_ax_f; // 补码形式的定点尾数(Q46)
	// [(AX + B)定点尾数相加]
	wire fp_mac_f_add_in_vld;
	wire fp_mac_f_add_in_is_b_eq_0;
	reg signed[32:0] fp_mac_f_added; // 相加后的定点尾数(Q29, 在范围(-6, 6)内)
	wire signed[32:0] fp_mac_f_added_rvs;
	// [标准化]
	wire fp_mac_nml_in_vld;
	wire[31:0] fp_mac_nml_shift_n_onehot;
	reg signed[32:0] fp_mac_nml_res; // 标准化之后的尾数(Q29)
	reg signed[5:0] fp_mac_nml_exp_var; // 标准化导致的指数变化量(在范围[-29, 2]内)
	// [打包与下溢处理]
	wire fp_mac_pack_in_vld;
	wire fp_mac_pack_out_vld;
	wire[INFO_ALONG_WIDTH-1:0] fp_mac_pack_out_info_along;
	wire signed[9:0] fp_mac_pack_exp; // 打包后的指数
	wire fp_mac_pack_underflow; // 下溢标志
	reg[31:0] fp_mac_fp32_packed; // 打包后的浮点数
	
	// 补码形式的定点尾数A[15:0] * 补码形式的定点尾数X[15:0]
	assign fp_mac_mul_op_a[0] = {2'b00, fp_mac_i_op_a_f[15:0]};
	assign fp_mac_mul_op_b[0] = {2'b00, fp_mac_i_op_x_f[15:0]};
	// 补码形式的定点尾数A[15:0] * 补码形式的定点尾数X[24:16]
	assign fp_mac_mul_op_a[1] = {2'b00, fp_mac_i_op_a_f[15:0]};
	assign fp_mac_mul_op_b[1] = {{9{fp_mac_i_op_x_f[24]}}, fp_mac_i_op_x_f[24:16]};
	// 补码形式的定点尾数A[24:16] * 补码形式的定点尾数X[15:0]
	assign fp_mac_mul_op_a[2] = {{9{fp_mac_i_op_a_f[24]}}, fp_mac_i_op_a_f[24:16]};
	assign fp_mac_mul_op_b[2] = {2'b00, fp_mac_i_op_x_f[15:0]};
	// 补码形式的定点尾数A[24:16] * 补码形式的定点尾数X[24:16]
	assign fp_mac_mul_op_a[3] = {{9{fp_mac_i_op_a_f[24]}}, fp_mac_i_op_a_f[24:16]};
	assign fp_mac_mul_op_b[3] = {{9{fp_mac_i_op_x_f[24]}}, fp_mac_i_op_x_f[24:16]};
	
	assign fp_mac_mul_ce = {4{mac_cell_i_vld & (~mac_cell_i_is_a_eq_1)}};
	
	assign fp_mac_add_op_a = 
		fp_mac_f_add_in_vld ? 
			fp_mac_ax_f_after_exp_algm:
			32'h0000_0000;
	assign fp_mac_add_op_b = 
		(fp_mac_f_add_in_vld & (~fp_mac_f_add_in_is_b_eq_0)) ? 
			fp_mac_b_f_after_exp_algm:
			32'h0000_0000;
	
	assign shared_sh0_op_a = 
		fp_mac_exp_algm_rsh_in_vld ? 
			(
				fp_mac_is_exp_of_ax_gth_b_delayed[4] ? 
					{fp_mac_i_op_b_f_delayed[4][24], fp_mac_i_op_b_f_delayed[4][24:0], 6'd0}:
					fp_mac_ax_f[48:17]
			):
			32'h0000_0000;
	assign shared_sh0_op_b = 
		fp_mac_exp_algm_rsh_in_vld ? 
			fp_mac_exp_abs_diff_delayed[4][4:0]:
			5'd0;
	
	assign {fp_mac_i_op_a_s, fp_mac_i_op_a_ec, fp_mac_i_op_a_m} = mac_cell_i_op_a;
	assign {fp_mac_i_op_x_s, fp_mac_i_op_x_ec, fp_mac_i_op_x_m} = mac_cell_i_op_x;
	assign {fp_mac_i_op_b_s, fp_mac_i_op_b_ec, fp_mac_i_op_b_m} = mac_cell_i_op_b;
	
	/*
	当阶码为0时, 指数 = 阶码 + 8'b10000010 = 阶码 - 126
	当阶码不为0时, 指数 = 阶码 + 8'b10000001 = 阶码 - 127
	
	指数在[-126, 127]范围内
	*/
	assign fp_mac_i_op_a_exp = fp_mac_i_op_a_ec + {6'b100000, fp_mac_i_op_a_ec == 8'd0, fp_mac_i_op_a_ec != 8'd0};
	assign fp_mac_i_op_x_exp = fp_mac_i_op_x_ec + {6'b100000, fp_mac_i_op_x_ec == 8'd0, fp_mac_i_op_x_ec != 8'd0};
	assign fp_mac_i_op_b_exp = fp_mac_i_op_b_ec + {6'b100000, fp_mac_i_op_b_ec == 8'd0, fp_mac_i_op_b_ec != 8'd0};
	
	assign fp_mac_i_op_a_f = 
		({25{fp_mac_i_op_a_s}} ^ {1'b0, fp_mac_i_op_a_ec != 8'd0, fp_mac_i_op_a_m}) + fp_mac_i_op_a_s;
	assign fp_mac_i_op_x_f = 
		({25{fp_mac_i_op_x_s}} ^ {1'b0, fp_mac_i_op_x_ec != 8'd0, fp_mac_i_op_x_m}) + fp_mac_i_op_x_s;
	assign fp_mac_i_op_b_f = 
		({25{fp_mac_i_op_b_s}} ^ {1'b0, fp_mac_i_op_b_ec != 8'd0, fp_mac_i_op_b_m}) + fp_mac_i_op_b_s;
	
	genvar fp_mac_i_op_b_delay_i;
	generate
		for(fp_mac_i_op_b_delay_i = 1;fp_mac_i_op_b_delay_i <= 4;fp_mac_i_op_b_delay_i = fp_mac_i_op_b_delay_i + 1)
		begin:fp_mac_i_op_b_delay_blk
			assign {
				fp_mac_i_op_b_s_delayed[fp_mac_i_op_b_delay_i],
				fp_mac_i_op_b_ec_delayed[fp_mac_i_op_b_delay_i],
				fp_mac_i_op_b_m_delayed[fp_mac_i_op_b_delay_i]
			} = mac_cell_i_op_b_delayed[fp_mac_i_op_b_delay_i];
			
			/*
			当阶码为0时, 指数 = 阶码 + 8'b10000010 = 阶码 - 126
			当阶码不为0时, 指数 = 阶码 + 8'b10000001 = 阶码 - 127
			
			指数在[-126, 127]范围内
			*/
			assign fp_mac_i_op_b_exp_delayed[fp_mac_i_op_b_delay_i] = 
				fp_mac_i_op_b_ec_delayed[fp_mac_i_op_b_delay_i] + 
				{
					6'b100000,
					fp_mac_i_op_b_ec_delayed[fp_mac_i_op_b_delay_i] == 8'd0,
					fp_mac_i_op_b_ec_delayed[fp_mac_i_op_b_delay_i] != 8'd0
				};
			
			assign fp_mac_i_op_b_f_delayed[fp_mac_i_op_b_delay_i] = 
				(
					{25{fp_mac_i_op_b_s_delayed[fp_mac_i_op_b_delay_i]}} ^ 
					{1'b0, fp_mac_i_op_b_ec_delayed[fp_mac_i_op_b_delay_i] != 8'd0, fp_mac_i_op_b_m_delayed[fp_mac_i_op_b_delay_i]}
				) + fp_mac_i_op_b_s_delayed[fp_mac_i_op_b_delay_i];
		end
	endgenerate
	
	assign fp_mac_exp_alignment_in_vld = mac_cell_i_vld_delayed[1];
	assign fp_mac_exp_alignment_in_is_b_eq_0 = mac_cell_i_is_b_eq_0_delayed[1];
	assign fp_mac_exp_alignment_in_vld_delayed = 
		{
			mac_cell_i_vld_delayed[6],
			mac_cell_i_vld_delayed[5],
			mac_cell_i_vld_delayed[4],
			mac_cell_i_vld_delayed[3],
			mac_cell_i_vld_delayed[2]
		};
	assign fp_mac_is_exp_of_ax_gth_b = 
		fp_mac_exp_alignment_in_is_b_eq_0 | (fp_mac_ax_exp_res > fp_mac_i_op_b_exp_delayed[1]);
	assign fp_mac_exp_aligned = 
		fp_mac_is_exp_of_ax_gth_b ? 
			fp_mac_ax_exp_res:
			{fp_mac_i_op_b_exp_delayed[1][7], fp_mac_i_op_b_exp_delayed[1][7:0]};
	assign fp_mac_exp_abs_diff = 
		fp_mac_is_exp_of_ax_gth_b ? 
			(fp_mac_ax_exp_res - {fp_mac_i_op_b_exp_delayed[1][7], fp_mac_i_op_b_exp_delayed[1][7:0]}):
			({fp_mac_i_op_b_exp_delayed[1][7], fp_mac_i_op_b_exp_delayed[1][7:0]} - fp_mac_ax_exp_res);
	
	assign fp_mac_exp_algm_rsh_in_vld = mac_cell_i_vld_delayed[4];
	assign fp_mac_exp_algm_rsh_in_is_b_eq_0 = mac_cell_i_is_b_eq_0_delayed[4];
	
	assign fp_mac_ax_exp_in_vld = mac_cell_i_vld;
	assign fp_mac_ax_exp_in_vld_delayed = 
		{
			mac_cell_i_vld_delayed[3],
			mac_cell_i_vld_delayed[2],
			mac_cell_i_vld_delayed[1]
		};
	assign fp_mac_ax_exp_in_is_a_eq_1 = mac_cell_i_is_a_eq_1;
	assign fp_mac_ax_exp_in_is_a_eq_1_delayed = 
		{
			mac_cell_i_is_a_eq_1_delayed[4],
			mac_cell_i_is_a_eq_1_delayed[3],
			mac_cell_i_is_a_eq_1_delayed[2],
			mac_cell_i_is_a_eq_1_delayed[1]
		};
	assign fp_mac_ax_f = 
		fp_mac_ax_exp_in_is_a_eq_1_delayed[4] ? 
			{fp_mac_i_op_x_f_delayed[4][24], fp_mac_i_op_x_f_delayed[4][24:0], 23'd0}:
			partial_product_add_res[48:0];
	
	assign fp_mac_f_add_in_vld = mac_cell_i_vld_delayed[5];
	assign fp_mac_f_add_in_is_b_eq_0 = mac_cell_i_is_b_eq_0_delayed[5];
	assign fp_mac_f_added_rvs = 
		{
			fp_mac_f_added[0], fp_mac_f_added[1], fp_mac_f_added[2], fp_mac_f_added[3],
			fp_mac_f_added[4], fp_mac_f_added[5], fp_mac_f_added[6], fp_mac_f_added[7],
			fp_mac_f_added[8], fp_mac_f_added[9], fp_mac_f_added[10], fp_mac_f_added[11],
			fp_mac_f_added[12], fp_mac_f_added[13], fp_mac_f_added[14], fp_mac_f_added[15],
			fp_mac_f_added[16], fp_mac_f_added[17], fp_mac_f_added[18], fp_mac_f_added[19],
			fp_mac_f_added[20], fp_mac_f_added[21], fp_mac_f_added[22], fp_mac_f_added[23],
			fp_mac_f_added[24], fp_mac_f_added[25], fp_mac_f_added[26], fp_mac_f_added[27],
			fp_mac_f_added[28], fp_mac_f_added[29], fp_mac_f_added[30], fp_mac_f_added[31],
			fp_mac_f_added[32]
		};
	
	assign fp_mac_nml_in_vld = mac_cell_i_vld_delayed[6];
	/*
	当"相加后的定点尾数" < 0时, 从MSB开始找第1个"0"的位置;当"相加后的定点尾数" >= 0时, 从MSB开始找第1个"1"的位置
	
	((~A) + 1) & A就是第1个"1"的位置独热码, 比如:
		---------------------------------
		|   A   | A的补码 | A & A的补码 |
		---------------------------------
		| 1000  |  1000   |    1000     |
		---------------------------------
		| 0000  |  0000   |    0000     |
		---------------------------------
		| 0110  |  1010   |    0010     |
		---------------------------------
		| 0111  |  1001   |    0001     |
		---------------------------------
		| 0101  |  1011   |    0001     |
		---------------------------------
	*/
	assign fp_mac_nml_shift_n_onehot = 
		({32{fp_mac_f_added_rvs[0]}} ^ fp_mac_f_added_rvs[32:1]) & 
		((~({32{fp_mac_f_added_rvs[0]}} ^ fp_mac_f_added_rvs[32:1])) + 1'b1);
	
	assign fp_mac_pack_in_vld = mac_cell_i_vld_delayed[7];
	assign fp_mac_pack_out_vld = mac_cell_i_vld_delayed[8];
	assign fp_mac_pack_out_info_along = mac_cell_i_info_along_delayed[8];
	assign fp_mac_pack_exp = 
		{fp_mac_exp_aligned_delayed[7][8], fp_mac_exp_aligned_delayed[7][8:0]} + {{4{fp_mac_nml_exp_var[5]}}, fp_mac_nml_exp_var[5:0]};
	assign fp_mac_pack_underflow = 
		(fp_mac_pack_exp < -10'sd126) | (fp_mac_nml_res[30:29] == 2'b00);
	
	// 延迟的操作数X的补码形式定点尾数
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld)
			fp_mac_i_op_x_f_delayed[1] <= # SIM_DELAY fp_mac_i_op_x_f;
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[1])
			fp_mac_i_op_x_f_delayed[2] <= # SIM_DELAY fp_mac_i_op_x_f_delayed[1];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[2])
			fp_mac_i_op_x_f_delayed[3] <= # SIM_DELAY fp_mac_i_op_x_f_delayed[2];
	end
	always @(posedge aclk)
	begin
		if(aclken & mac_cell_i_vld_delayed[3])
			fp_mac_i_op_x_f_delayed[4] <= # SIM_DELAY fp_mac_i_op_x_f_delayed[3];
	end
	
	// 延迟的对阶结果
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_alignment_in_vld)
		begin
			fp_mac_is_exp_of_ax_gth_b_delayed[2] <= # SIM_DELAY fp_mac_is_exp_of_ax_gth_b;
			fp_mac_exp_aligned_delayed[2] <= # SIM_DELAY fp_mac_exp_aligned;
			fp_mac_exp_abs_diff_delayed[2] <= # SIM_DELAY fp_mac_exp_abs_diff;
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_alignment_in_vld_delayed[1])
		begin
			fp_mac_is_exp_of_ax_gth_b_delayed[3] <= # SIM_DELAY fp_mac_is_exp_of_ax_gth_b_delayed[2];
			fp_mac_exp_aligned_delayed[3] <= # SIM_DELAY fp_mac_exp_aligned_delayed[2];
			fp_mac_exp_abs_diff_delayed[3] <= # SIM_DELAY fp_mac_exp_abs_diff_delayed[2];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_alignment_in_vld_delayed[2])
		begin
			fp_mac_is_exp_of_ax_gth_b_delayed[4] <= # SIM_DELAY fp_mac_is_exp_of_ax_gth_b_delayed[3];
			fp_mac_exp_aligned_delayed[4] <= # SIM_DELAY fp_mac_exp_aligned_delayed[3];
			fp_mac_exp_abs_diff_delayed[4] <= # SIM_DELAY fp_mac_exp_abs_diff_delayed[3];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_alignment_in_vld_delayed[3])
		begin
			fp_mac_exp_aligned_delayed[5] <= # SIM_DELAY fp_mac_exp_aligned_delayed[4];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_alignment_in_vld_delayed[4])
		begin
			fp_mac_exp_aligned_delayed[6] <= # SIM_DELAY fp_mac_exp_aligned_delayed[5];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_alignment_in_vld_delayed[5])
		begin
			fp_mac_exp_aligned_delayed[7] <= # SIM_DELAY fp_mac_exp_aligned_delayed[6];
		end
	end
	
	// 对阶后AX的定点尾数(补码形式, Q29)
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_algm_rsh_in_vld)
			fp_mac_ax_f_after_exp_algm <= # SIM_DELAY 
				fp_mac_is_exp_of_ax_gth_b_delayed[4] ? 
					fp_mac_ax_f[48:17]:
					(
						(fp_mac_exp_abs_diff_delayed[4] >= 9'd32) ? 
							32'd0:
							shared_sh0_res[31:0]
					);
	end
	
	// 对阶后B的定点尾数(补码形式, Q29)
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_exp_algm_rsh_in_vld & (~fp_mac_exp_algm_rsh_in_is_b_eq_0))
			fp_mac_b_f_after_exp_algm <= # SIM_DELAY 
				fp_mac_is_exp_of_ax_gth_b_delayed[4] ? 
					(
						(fp_mac_exp_abs_diff_delayed[4] >= 9'd32) ? 
							32'd0:
							shared_sh0_res[31:0]
					):
					{fp_mac_i_op_b_f_delayed[4][24], fp_mac_i_op_b_f_delayed[4][24:0], 6'd0};
	end
	
	// AX的指数
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_ax_exp_in_vld)
			fp_mac_ax_exp_res <= # SIM_DELAY 
				fp_mac_ax_exp_in_is_a_eq_1 ? 
					{fp_mac_i_op_x_exp[7], fp_mac_i_op_x_exp[7:0]}:
					(
						({9{~fp_mac_ax_exp_in_is_a_eq_1}} & {fp_mac_i_op_a_exp[7], fp_mac_i_op_a_exp[7:0]}) + 
						({9{~fp_mac_ax_exp_in_is_a_eq_1}} & {fp_mac_i_op_x_exp[7], fp_mac_i_op_x_exp[7:0]})
					);
	end
	
	// 相加后的定点尾数(Q29)
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_f_add_in_vld)
			fp_mac_f_added <= # SIM_DELAY shared_adder0_res;
	end
	
	// 标准化之后的尾数(Q29)
	// 标准化导致的指数变化量(在范围[-29, 2]内)
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_nml_in_vld)
		begin
			fp_mac_nml_res <= # SIM_DELAY 
				(
					({33{fp_mac_nml_shift_n_onehot[0]}} & {{2{fp_mac_f_added[32]}}, fp_mac_f_added[32:2]}) | // 算术右移2位
					({33{fp_mac_nml_shift_n_onehot[1]}} & {fp_mac_f_added[32], fp_mac_f_added[32:1]}) | // 算术右移1位
					({33{fp_mac_nml_shift_n_onehot[2]}} & fp_mac_f_added) | 
					({33{fp_mac_nml_shift_n_onehot[3]}} & (fp_mac_f_added << 1)) | 
					({33{fp_mac_nml_shift_n_onehot[4]}} & (fp_mac_f_added << 2)) | 
					({33{fp_mac_nml_shift_n_onehot[5]}} & (fp_mac_f_added << 3)) | 
					({33{fp_mac_nml_shift_n_onehot[6]}} & (fp_mac_f_added << 4)) | 
					({33{fp_mac_nml_shift_n_onehot[7]}} & (fp_mac_f_added << 5)) | 
					({33{fp_mac_nml_shift_n_onehot[8]}} & (fp_mac_f_added << 6)) | 
					({33{fp_mac_nml_shift_n_onehot[9]}} & (fp_mac_f_added << 7)) | 
					({33{fp_mac_nml_shift_n_onehot[10]}} & (fp_mac_f_added << 8)) | 
					({33{fp_mac_nml_shift_n_onehot[11]}} & (fp_mac_f_added << 9)) | 
					({33{fp_mac_nml_shift_n_onehot[12]}} & (fp_mac_f_added << 10)) | 
					({33{fp_mac_nml_shift_n_onehot[13]}} & (fp_mac_f_added << 11)) | 
					({33{fp_mac_nml_shift_n_onehot[14]}} & (fp_mac_f_added << 12)) | 
					({33{fp_mac_nml_shift_n_onehot[15]}} & (fp_mac_f_added << 13)) | 
					({33{fp_mac_nml_shift_n_onehot[16]}} & (fp_mac_f_added << 14)) | 
					({33{fp_mac_nml_shift_n_onehot[17]}} & (fp_mac_f_added << 15)) | 
					({33{fp_mac_nml_shift_n_onehot[18]}} & (fp_mac_f_added << 16)) | 
					({33{fp_mac_nml_shift_n_onehot[19]}} & (fp_mac_f_added << 17)) | 
					({33{fp_mac_nml_shift_n_onehot[20]}} & (fp_mac_f_added << 18)) | 
					({33{fp_mac_nml_shift_n_onehot[21]}} & (fp_mac_f_added << 19)) | 
					({33{fp_mac_nml_shift_n_onehot[22]}} & (fp_mac_f_added << 20)) | 
					({33{fp_mac_nml_shift_n_onehot[23]}} & (fp_mac_f_added << 21)) | 
					({33{fp_mac_nml_shift_n_onehot[24]}} & (fp_mac_f_added << 22)) | 
					({33{fp_mac_nml_shift_n_onehot[25]}} & (fp_mac_f_added << 23)) | 
					({33{fp_mac_nml_shift_n_onehot[26]}} & (fp_mac_f_added << 24)) | 
					({33{fp_mac_nml_shift_n_onehot[27]}} & (fp_mac_f_added << 25)) | 
					({33{fp_mac_nml_shift_n_onehot[28]}} & (fp_mac_f_added << 26)) | 
					({33{fp_mac_nml_shift_n_onehot[29]}} & (fp_mac_f_added << 27)) | 
					({33{fp_mac_nml_shift_n_onehot[30]}} & (fp_mac_f_added << 28)) | 
					({33{fp_mac_nml_shift_n_onehot[31] | (~(|fp_mac_nml_shift_n_onehot))}} & (fp_mac_f_added << 29))
				) | 
				{4'd0, 22'd0, fp_mac_f_added[32], 6'd0};
			
			fp_mac_nml_exp_var <= # SIM_DELAY 
				({6{fp_mac_nml_shift_n_onehot[0]}} & 6'b000010) | // 2
				({6{fp_mac_nml_shift_n_onehot[1]}} & 6'b000001) | // 1
				({6{fp_mac_nml_shift_n_onehot[2]}} & 6'b000000) | // 0
				({6{fp_mac_nml_shift_n_onehot[3]}} & 6'b111111) | // -1
				({6{fp_mac_nml_shift_n_onehot[4]}} & 6'b111110) | // -2
				({6{fp_mac_nml_shift_n_onehot[5]}} & 6'b111101) | // -3
				({6{fp_mac_nml_shift_n_onehot[6]}} & 6'b111100) | // -4
				({6{fp_mac_nml_shift_n_onehot[7]}} & 6'b111011) | // -5
				({6{fp_mac_nml_shift_n_onehot[8]}} & 6'b111010) | // -6
				({6{fp_mac_nml_shift_n_onehot[9]}} & 6'b111001) | // -7
				({6{fp_mac_nml_shift_n_onehot[10]}} & 6'b111000) | // -8
				({6{fp_mac_nml_shift_n_onehot[11]}} & 6'b110111) | // -9
				({6{fp_mac_nml_shift_n_onehot[12]}} & 6'b110110) | // -10
				({6{fp_mac_nml_shift_n_onehot[13]}} & 6'b110101) | // -11
				({6{fp_mac_nml_shift_n_onehot[14]}} & 6'b110100) | // -12
				({6{fp_mac_nml_shift_n_onehot[15]}} & 6'b110011) | // -13
				({6{fp_mac_nml_shift_n_onehot[16]}} & 6'b110010) | // -14
				({6{fp_mac_nml_shift_n_onehot[17]}} & 6'b110001) | // -15
				({6{fp_mac_nml_shift_n_onehot[18]}} & 6'b110000) | // -16
				({6{fp_mac_nml_shift_n_onehot[19]}} & 6'b101111) | // -17
				({6{fp_mac_nml_shift_n_onehot[20]}} & 6'b101110) | // -18
				({6{fp_mac_nml_shift_n_onehot[21]}} & 6'b101101) | // -19
				({6{fp_mac_nml_shift_n_onehot[22]}} & 6'b101100) | // -20
				({6{fp_mac_nml_shift_n_onehot[23]}} & 6'b101011) | // -21
				({6{fp_mac_nml_shift_n_onehot[24]}} & 6'b101010) | // -22
				({6{fp_mac_nml_shift_n_onehot[25]}} & 6'b101001) | // -23
				({6{fp_mac_nml_shift_n_onehot[26]}} & 6'b101000) | // -24
				({6{fp_mac_nml_shift_n_onehot[27]}} & 6'b100111) | // -25
				({6{fp_mac_nml_shift_n_onehot[28]}} & 6'b100110) | // -26
				({6{fp_mac_nml_shift_n_onehot[29]}} & 6'b100101) | // -27
				({6{fp_mac_nml_shift_n_onehot[30]}} & 6'b100100) | // -28
				({6{fp_mac_nml_shift_n_onehot[31] | (~(|fp_mac_nml_shift_n_onehot))}} & 6'b100011); // -29
		end
	end
	
	// 打包后的浮点数
	always @(posedge aclk)
	begin
		if(aclken & fp_mac_pack_in_vld)
		begin
			// 符号位
			fp_mac_fp32_packed[31] <= # SIM_DELAY fp_mac_nml_res[32];
			// 阶码
			fp_mac_fp32_packed[30:23] <= # SIM_DELAY 
				fp_mac_pack_underflow ? 
					8'h00:
					(fp_mac_pack_exp[7:0] + 8'd127);
			// 尾数
			fp_mac_fp32_packed[22:0] <= # SIM_DELAY 
				({23{fp_mac_nml_res[32]}} ^ fp_mac_nml_res[28:6]) + fp_mac_nml_res[32];
		end
	end
	
	/** 乘加单元结果输出 **/
	assign mac_cell_o_res = 
		(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
			fp_mac_fp32_packed:
			int_mac_final_res;
	assign mac_cell_o_info_along = 
		(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
			fp_mac_pack_out_info_along:
			int_mac_final_out_info_along;
	assign mac_cell_o_vld = 
		(bn_calfmt_inner == BN_CAL_FMT_FP32) ? 
			fp_mac_pack_out_vld:
			int_mac_final_out_vld;
	
endmodule
