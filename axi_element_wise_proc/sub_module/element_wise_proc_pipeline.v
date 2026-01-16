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
本模块: 逐元素操作处理流水线

描述:
1.流水线中的各个功能单元
(1)输入数据转换单元
------------------------------------------
|          执行模式           |   时延   |
------------------------------------------
|         FP16转FP32          |    2     |
------------------------------------------
| U8/S8/U16/S16/U32/S32转FP32 |    5     |
------------------------------------------
|            旁路             |    1     |
------------------------------------------

(2)二次幂计算单元
计算: 操作数X ^ 2
-------------------------------------
|       执行模式       |    时延    |
-------------------------------------
|  以S16/S32格式计算   |     8      |
-------------------------------------
|    以FP32格式计算    |     7      |
-------------------------------------
|         旁路         |     1      |
-------------------------------------

-------------------------------------
| 运算数据格式支持情况 | 乘法器位宽 |
-------------------------------------
| 支持INT32或FP32      | s32 * s32  |
-------------------------------------
| 不支持INT32与FP32    | s16 * s16  |
-------------------------------------

(3)乘加计算单元
计算: 操作数A * 操作数X + 操作数B
-------------------------------------
|       执行模式       |    时延    |
-------------------------------------
|  以S16/S32格式计算   |     8      |
-------------------------------------
|    以FP32格式计算    |     9      |
-------------------------------------
|         旁路         |     1      |
-------------------------------------

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

(4)输出数据转换单元
-------------------------------------
|       执行模式       |    时延    |
-------------------------------------
|      FP32转S33       |     4      |
-------------------------------------
|         旁路         |     1      |
-------------------------------------

(5)舍入单元
------------------------------------------
|          执行模式           |   时延   |
------------------------------------------
| S33转U8/S8/U16/S16/U32/S32  |    3     |
------------------------------------------
|         FP32转FP16          |    3     |
------------------------------------------
|            旁路             |    0     |
------------------------------------------

2.带有全局时钟使能

注意:
浮点运算未考虑INF和NAN

操作数A与操作数B不能同时为变量

当计算数据格式(cal_calfmt)为S16或S32时, 操作数B的定点数量化精度 = 操作数X的定点数量化精度(op_x_fixed_point_quat_accrc)

必须满足舍入单元输出定点数量化精度(round_out_fixed_point_quat_accrc) <= 舍入单元输入定点数量化精度(round_in_fixed_point_quat_accrc)
定点数舍入位数(fixed_point_rounding_digits) = 
	舍入单元输入定点数量化精度(round_in_fixed_point_quat_accrc) - 舍入单元输出定点数量化精度(round_out_fixed_point_quat_accrc)

协议:
无

作者: 陈家耀
日期: 2026/01/13
********************************************************************/


module element_wise_proc_pipeline #(
	// 处理流水线全局配置
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽
	// 输入数据转换单元配置
	parameter IN_DATA_CVT_EN_ROUND = 1'b1, // 是否需要进行四舍五入
	parameter IN_DATA_CVT_FP16_IN_DATA_SUPPORTED = 1'b0, // 是否支持FP16输入数据格式
	parameter IN_DATA_CVT_S33_IN_DATA_SUPPORTED = 1'b1, // 是否支持S33输入数据格式
	// 计算单元配置
	parameter CAL_EN_ROUND = 1'b0, // 是否需要进行四舍五入
	parameter CAL_INT16_SUPPORTED = 1'b0, // 是否支持INT16运算数据格式
	parameter CAL_INT32_SUPPORTED = 1'b0, // 是否支持INT32运算数据格式
	parameter CAL_FP32_SUPPORTED = 1'b1, // 是否支持FP32运算数据格式
	// 输出数据转换单元配置
	parameter OUT_DATA_CVT_EN_ROUND = 1'b1, // 是否需要进行四舍五入
	parameter OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED = 1'b1, // 是否支持S33输出数据格式
	// 舍入单元配置
	parameter ROUND_S33_ROUND_SUPPORTED = 1'b1, // 是否支持S33数据的舍入
	parameter ROUND_FP32_ROUND_SUPPORTED = 1'b1, // 是否支持FP32数据的舍入
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 执行单元旁路
	input wire in_data_cvt_unit_bypass, // 旁路输入数据转换单元
	input wire pow2_cell_bypass, // 旁路二次幂计算单元
	input wire mac_cell_bypass, // 旁路乘加计算单元
	input wire out_data_cvt_unit_bypass, // 旁路输出数据转换单元
	input wire round_cell_bypass, // 旁路舍入单元
	
	// 运行时参数
	input wire[2:0] in_data_fmt, // 输入数据格式
	input wire[1:0] cal_calfmt, // 计算数据格式
	input wire[2:0] out_data_fmt, // 输出数据格式
	input wire[5:0] in_fixed_point_quat_accrc, // 输入定点数量化精度
	input wire[4:0] op_x_fixed_point_quat_accrc, // 操作数X的定点数量化精度
	input wire[4:0] op_a_fixed_point_quat_accrc, // 操作数A的定点数量化精度
	input wire is_op_a_eq_1, // 操作数A的实际值恒为1(标志)
	input wire is_op_b_eq_0, // 操作数B的实际值恒为0(标志)
	input wire is_op_a_const, // 操作数A为常量(标志)
	input wire is_op_b_const, // 操作数B为常量(标志)
	input wire[31:0] op_a_const_val, // 操作数A的常量值
	input wire[31:0] op_b_const_val, // 操作数B的常量值
	input wire[5:0] s33_cvt_fixed_point_quat_accrc, // 转换为S33输出数据的定点数量化精度
	input wire[4:0] round_in_fixed_point_quat_accrc, // 舍入单元输入定点数量化精度
	input wire[4:0] round_out_fixed_point_quat_accrc, // 舍入单元输出定点数量化精度
	input wire[4:0] fixed_point_rounding_digits, // 定点数舍入位数
	
	// 处理流水线输入
	input wire[31:0] proc_i_op_x, // 操作数X
	input wire[31:0] proc_i_op_a, // 操作数A
	input wire[31:0] proc_i_op_b, // 操作数B
	input wire[INFO_ALONG_WIDTH-1:0] proc_i_info_along, // 随路数据
	input wire proc_i_vld,
	
	// 处理流水线输出
	output wire[31:0] proc_o_res, // 结果
	output wire[INFO_ALONG_WIDTH-1:0] proc_o_info_along, // 随路数据
	output wire proc_o_vld,
	
	// 外部有符号乘法器#0
	output wire mul0_clk,
	output wire[((CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 32:16)-1:0] mul0_op_a, // 操作数A
	output wire[((CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 32:16)-1:0] mul0_op_b, // 操作数B
	output wire[2:0] mul0_ce, // 计算使能
	input wire[((CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 64:32)-1:0] mul0_res, // 计算结果
	
	// 外部有符号乘法器#1
	output wire mul1_clk,
	output wire[(CAL_INT16_SUPPORTED ? 4*18:(CAL_INT32_SUPPORTED ? 32:25))-1:0] mul1_op_a, // 操作数A
	output wire[(CAL_INT16_SUPPORTED ? 4*18:(CAL_INT32_SUPPORTED ? 32:25))-1:0] mul1_op_b, // 操作数B
	output wire[(CAL_INT16_SUPPORTED ? 4:3)-1:0] mul1_ce, // 计算使能
	input wire[(CAL_INT16_SUPPORTED ? 4*36:(CAL_INT32_SUPPORTED ? 64:50))-1:0] mul1_res // 计算结果
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
	
	/**
	输入数据转换单元
	
	FP16转FP32
	U8/S8/U16/S16/U32/S32转FP32
	**/
	// 运行时参数
	wire[1:0] in_data_cvt_in_data_fmt; // 输入数据格式
	wire[2:0] in_data_cvt_integer_type; // 整数类型
	// 转换单元输入
	wire[31:0] in_data_cvt_cell_i_op_x; // 操作数X
	wire in_data_cvt_cell_i_pass; // 直接传递操作数X(标志)
	wire[32+32+INFO_ALONG_WIDTH-1:0] in_data_cvt_cell_i_info_along; // {操作数A, 操作数B, 随路数据}
	wire in_data_cvt_cell_i_vld;
	// 转换单元输出
	wire[31:0] in_data_cvt_cell_o_res; // 计算结果
	wire[32+32+INFO_ALONG_WIDTH-1:0] in_data_cvt_cell_o_info_along; // {操作数A, 操作数B, 随路数据}
	wire in_data_cvt_cell_o_vld;
	
	assign in_data_cvt_in_data_fmt = 
		((in_data_fmt == IN_DATA_FMT_FP16) | (in_data_fmt == IN_DATA_FMT_NONE)) ? 2'b00: // FP16格式
		                                                                          2'b01; // S33格式
	assign in_data_cvt_integer_type = 
		in_data_fmt;
	
	assign in_data_cvt_cell_i_op_x = proc_i_op_x;
	assign in_data_cvt_cell_i_pass = 1'b0;
	assign in_data_cvt_cell_i_info_along[32+32+INFO_ALONG_WIDTH-1:32+INFO_ALONG_WIDTH] = 
		(is_op_a_const | is_op_a_eq_1) ? 
			op_a_const_val:
			proc_i_op_a;
	assign in_data_cvt_cell_i_info_along[32+INFO_ALONG_WIDTH-1:INFO_ALONG_WIDTH] = 
		(is_op_b_const | is_op_b_eq_0) ? 
			op_b_const_val:
			proc_i_op_b;
	assign in_data_cvt_cell_i_info_along[INFO_ALONG_WIDTH-1:0] = 
		proc_i_info_along;
	assign in_data_cvt_cell_i_vld = proc_i_vld;
	
	element_wise_in_data_cvt_cell #(
		.EN_ROUND(IN_DATA_CVT_EN_ROUND),
		.FP16_IN_DATA_SUPPORTED(IN_DATA_CVT_FP16_IN_DATA_SUPPORTED),
		.S33_IN_DATA_SUPPORTED(IN_DATA_CVT_S33_IN_DATA_SUPPORTED),
		.INFO_ALONG_WIDTH(32+32+INFO_ALONG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)in_data_cvt_cell_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.bypass(in_data_cvt_unit_bypass),
		
		.in_data_fmt(in_data_cvt_in_data_fmt),
		.fixed_point_quat_accrc(in_fixed_point_quat_accrc),
		.integer_type(in_data_cvt_integer_type),
		
		.cvt_cell_i_op_x(in_data_cvt_cell_i_op_x),
		.cvt_cell_i_pass(in_data_cvt_cell_i_pass),
		.cvt_cell_i_info_along(in_data_cvt_cell_i_info_along),
		.cvt_cell_i_vld(in_data_cvt_cell_i_vld),
		
		.cvt_cell_o_res(in_data_cvt_cell_o_res),
		.cvt_cell_o_info_along(in_data_cvt_cell_o_info_along),
		.cvt_cell_o_vld(in_data_cvt_cell_o_vld)
	);
	
	/**
	二次幂计算单元
	
	计算: 操作数X ^ 2
	**/
	// 二次幂计算单元计算输入
	wire[31:0] pow2_cell_i_op_x; // 操作数X
	wire pow2_cell_i_pass; // 直接传递操作数X(标志)
	wire[32+32+INFO_ALONG_WIDTH-1:0] pow2_cell_i_info_along; // {操作数A, 操作数B, 随路数据}
	wire pow2_cell_i_vld;
	// 二次幂计算单元结果输出
	wire[31:0] pow2_cell_o_res; // 计算结果
	wire[32+32+INFO_ALONG_WIDTH-1:0] pow2_cell_o_info_along; // {操作数A, 操作数B, 随路数据}
	wire pow2_cell_o_vld;
	
	assign pow2_cell_i_op_x = in_data_cvt_cell_o_res;
	assign pow2_cell_i_pass = 1'b0;
	assign pow2_cell_i_info_along = in_data_cvt_cell_o_info_along;
	assign pow2_cell_i_vld = in_data_cvt_cell_o_vld;
	
	pow2_cell #(
		.INT16_SUPPORTED(CAL_INT16_SUPPORTED),
		.INT32_SUPPORTED(CAL_INT32_SUPPORTED),
		.FP32_SUPPORTED(CAL_FP32_SUPPORTED),
		.INFO_ALONG_WIDTH(32+32+INFO_ALONG_WIDTH),
		.EN_ROUND(CAL_EN_ROUND),
		.SIM_DELAY(SIM_DELAY)
	)pow2_cell_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.bypass(pow2_cell_bypass),
		
		.pow2_calfmt(cal_calfmt),
		.fixed_point_quat_accrc(op_x_fixed_point_quat_accrc),
		
		.pow2_cell_i_op_x(pow2_cell_i_op_x),
		.pow2_cell_i_pass(pow2_cell_i_pass),
		.pow2_cell_i_info_along(pow2_cell_i_info_along),
		.pow2_cell_i_vld(pow2_cell_i_vld),
		
		.pow2_cell_o_res(pow2_cell_o_res),
		.pow2_cell_o_info_along(pow2_cell_o_info_along),
		.pow2_cell_o_vld(pow2_cell_o_vld),
		
		.mul_clk(mul0_clk),
		.mul_op_a(mul0_op_a),
		.mul_op_b(mul0_op_b),
		.mul_ce(mul0_ce),
		.mul_res(mul0_res)
	);
	
	/**
	乘加计算单元
	
	计算: 操作数A * 操作数X + 操作数B
	**/
	// 乘加单元计算输入
	wire[31:0] mac_cell_i_op_a; // 操作数A
	wire[31:0] mac_cell_i_op_x; // 操作数X
	wire[31:0] mac_cell_i_op_b; // 操作数B
	wire mac_cell_i_is_a_eq_1; // 参数A的实际值为1(标志)
	wire mac_cell_i_is_b_eq_0; // 参数B的实际值为0(标志)
	wire[INFO_ALONG_WIDTH-1:0] mac_cell_i_info_along; // 随路数据
	wire mac_cell_i_vld;
	// 乘加单元结果输出
	wire[31:0] mac_cell_o_res; // 计算结果
	wire[INFO_ALONG_WIDTH-1:0] mac_cell_o_info_along; // 随路数据
	wire mac_cell_o_vld;
	
	assign mac_cell_i_op_a = pow2_cell_o_info_along[32+32+INFO_ALONG_WIDTH-1:32+INFO_ALONG_WIDTH];
	assign mac_cell_i_op_b = pow2_cell_o_info_along[32+INFO_ALONG_WIDTH-1:INFO_ALONG_WIDTH];
	assign mac_cell_i_op_x = pow2_cell_o_res;
	assign mac_cell_i_is_a_eq_1 = is_op_a_eq_1;
	assign mac_cell_i_is_b_eq_0 = is_op_b_eq_0;
	assign mac_cell_i_info_along = pow2_cell_o_info_along[INFO_ALONG_WIDTH-1:0];
	assign mac_cell_i_vld = pow2_cell_o_vld;
	
	batch_nml_mac_cell #(
		.INT16_SUPPORTED(CAL_INT16_SUPPORTED),
		.INT32_SUPPORTED(CAL_INT32_SUPPORTED),
		.FP32_SUPPORTED(CAL_FP32_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)mac_cell_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.bypass(mac_cell_bypass),
		
		.bn_calfmt(cal_calfmt),
		.fixed_point_quat_accrc(op_a_fixed_point_quat_accrc),
		
		.mac_cell_i_op_a(mac_cell_i_op_a),
		.mac_cell_i_op_x(mac_cell_i_op_x),
		.mac_cell_i_op_b(mac_cell_i_op_b),
		.mac_cell_i_is_a_eq_1(mac_cell_i_is_a_eq_1),
		.mac_cell_i_is_b_eq_0(mac_cell_i_is_b_eq_0),
		.mac_cell_i_info_along(mac_cell_i_info_along),
		.mac_cell_i_vld(mac_cell_i_vld),
		
		.mac_cell_o_res(mac_cell_o_res),
		.mac_cell_o_info_along(mac_cell_o_info_along),
		.mac_cell_o_vld(mac_cell_o_vld),
		
		.mul_clk(mul1_clk),
		.mul_op_a(mul1_op_a),
		.mul_op_b(mul1_op_b),
		.mul_ce(mul1_ce),
		.mul_res(mul1_res)
	);
	
	/**
	输出数据转换单元
	
	FP32转S33
	**/
	// 运行时参数
	wire[1:0] out_data_cvt_out_data_fmt; // 输出数据格式
	// 转换单元输入
	wire[31:0] out_data_cvt_cell_i_op_x; // 操作数X
	wire out_data_cvt_cell_i_pass; // 直接传递操作数X(标志)
	wire[INFO_ALONG_WIDTH-1:0] out_data_cvt_cell_i_info_along; // 随路数据
	wire out_data_cvt_cell_i_vld;
	// 转换单元输出
	wire[32:0] out_data_cvt_cell_o_res; // 计算结果
	wire[INFO_ALONG_WIDTH-1:0] out_data_cvt_cell_o_info_along; // 随路数据
	wire out_data_cvt_cell_o_vld;
	
	assign out_data_cvt_out_data_fmt = 
		(
			(out_data_fmt == OUT_DATA_FMT_U8) | 
			(out_data_fmt == OUT_DATA_FMT_S8) | 
			(out_data_fmt == OUT_DATA_FMT_U16) | 
			(out_data_fmt == OUT_DATA_FMT_S16) | 
			(out_data_fmt == OUT_DATA_FMT_U32) | 
			(out_data_fmt == OUT_DATA_FMT_S32)
		) ? 
			2'b00: // S33格式
			2'b10; // 无效格式
	
	assign out_data_cvt_cell_i_op_x = mac_cell_o_res;
	assign out_data_cvt_cell_i_pass = 1'b0;
	assign out_data_cvt_cell_i_info_along = mac_cell_o_info_along;
	assign out_data_cvt_cell_i_vld = mac_cell_o_vld;
	
	element_wise_out_data_cvt_cell #(
		.EN_ROUND(OUT_DATA_CVT_EN_ROUND),
		.S33_OUT_DATA_SUPPORTED(OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)out_data_cvt_cell_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.bypass(out_data_cvt_unit_bypass),
		
		.out_data_fmt(out_data_cvt_out_data_fmt),
		.fixed_point_quat_accrc(s33_cvt_fixed_point_quat_accrc),
		
		.cvt_cell_i_op_x(out_data_cvt_cell_i_op_x),
		.cvt_cell_i_pass(out_data_cvt_cell_i_pass),
		.cvt_cell_i_info_along(out_data_cvt_cell_i_info_along),
		.cvt_cell_i_vld(out_data_cvt_cell_i_vld),
		
		.cvt_cell_o_res(out_data_cvt_cell_o_res),
		.cvt_cell_o_info_along(out_data_cvt_cell_o_info_along),
		.cvt_cell_o_vld(out_data_cvt_cell_o_vld)
	);
	
	/**
	舍入单元
	
	S33转U8/S8/U16/S16/U32/S32
	FP32转FP16
	**/
	// 使能信号
	wire round_unit_s0_ce; // 第0级使能
	reg round_unit_s1_ce; // 第1级使能
	reg round_unit_s2_ce; // 第2级使能
	reg round_unit_s3_ce; // 第3级使能
	// 舍入单元输入
	wire[32:0] round_i_op_x; // 操作数X(定点数或FP32)
	wire[INFO_ALONG_WIDTH-1:0] round_i_info_along; // 随路数据
	wire round_i_vld;
	// 舍入单元处理结果
	wire[31:0] round_o_res; // 结果(定点数或FP16或FP32)
	wire[INFO_ALONG_WIDTH-1:0] round_o_info_along; // 随路数据
	wire round_o_vld;
	
	assign proc_o_res = round_o_res;
	assign proc_o_info_along = round_o_info_along;
	assign proc_o_vld = 
		round_cell_bypass ? 
			round_unit_s0_ce:
			round_unit_s3_ce;
	
	assign round_unit_s0_ce = out_data_cvt_cell_o_vld;
	
	assign round_i_op_x = out_data_cvt_cell_o_res;
	assign round_i_info_along = out_data_cvt_cell_o_info_along;
	assign round_i_vld = out_data_cvt_cell_o_vld;
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{round_unit_s3_ce, round_unit_s2_ce, round_unit_s1_ce} <= 3'b000;
		else if(aclken)
			{round_unit_s3_ce, round_unit_s2_ce, round_unit_s1_ce} <= # SIM_DELAY 
				{round_unit_s2_ce, round_unit_s1_ce, round_unit_s0_ce};
	end
	
	out_round_cell #(
		.USE_EXT_CE(1'b1),
		.S33_ROUND_SUPPORTED(ROUND_S33_ROUND_SUPPORTED),
		.FP32_ROUND_SUPPORTED(ROUND_FP32_ROUND_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)round_cell_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.bypass(round_cell_bypass),
		.s0_ce(round_unit_s0_ce),
		.s1_ce(round_unit_s1_ce),
		.s2_ce(round_unit_s2_ce),
		
		.target_data_fmt(out_data_fmt),
		.in_fixed_point_quat_accrc(round_in_fixed_point_quat_accrc),
		.out_fixed_point_quat_accrc(round_out_fixed_point_quat_accrc),
		.fixed_point_rounding_digits(fixed_point_rounding_digits),
		
		.round_i_op_x(round_i_op_x),
		.round_i_info_along(round_i_info_along),
		.round_i_vld(round_i_vld),
		
		.round_o_res(round_o_res),
		.round_o_info_along(round_o_info_along),
		.round_o_vld(round_o_vld)
	);
	
endmodule
