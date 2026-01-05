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
本模块: 池化中间结果更新单元

描述:
支持INT8、INT16、FP16三种运算数据格式

带有全局时钟使能

-----------------------
|   数据格式   | 时延 |
-----------------------
| INT8或INT16  |  2   |
-----------------------
|     FP16     |  6   |
-----------------------

--------------------------------------------------------------------
|    池化模式    | 是否第1项 | 是否空表面 |          操作          |
--------------------------------------------------------------------
|     上采样     |    ---    |     0      | 输出"零结果"           |
|                |           |------------|------------------------|
|                |           |     1      | 输出(标准化后的)       |
|                |           |            | "新结果"               |
--------------------------------------------------------------------
|    最大池化    |    0      |     0      | 输出"新结果"和         |
|                |           |            | "原中间结果"的较大者   |
|                |--------------------------------------------------
|                |    0      |     1      | 输出"零结果"和         |
|                |           |            | "原中间结果"的较大者   |
|                |--------------------------------------------------
|                |    1      |     0      | 输出(标准化后的)       |
|                |           |            | "新结果"               |
|                |--------------------------------------------------
|                |    1      |     1      | 输出"零结果"           |
--------------------------------------------------------------------
|    平均池化    |    0      |     0      | 输出"新结果"与         |
|                |           |            | "原中间结果"的和       |
|                |--------------------------------------------------
|                |    0      |     1      | 无需更新               |
|                |--------------------------------------------------
|                |    1      |     0      | 输出(标准化后的)       |
|                |           |            | "新结果"               |
|                |--------------------------------------------------
|                |    1      |     1      | 输出"零结果"           |
--------------------------------------------------------------------

注意：
浮点运算未考虑INF和NAN

协议:
无

作者: 陈家耀
日期: 2025/12/07
********************************************************************/


module pool_middle_res_upd #(
	parameter integer INFO_ALONG_WIDTH = 2, // 随路数据的位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] pool_mode, // 池化模式
	input wire[1:0] calfmt, // 运算数据格式
	
	// 池化结果更新输入
	input wire[15:0] pool_upd_in_data, // 定点数或FP16
	input wire[31:0] pool_upd_in_org_mid_res, // 原中间结果
	input wire pool_upd_in_is_first_item, // 是否第1项(标志)
	input wire pool_upd_in_is_zero_sfc, // 是否空表面(标志)
	input wire[INFO_ALONG_WIDTH-1:0] pool_upd_in_info_along, // 随路数据
	input wire pool_upd_in_valid, // 输入有效指示
	
	// 池化结果更新输出
	output wire[31:0] pool_upd_out_data, // 单精度浮点数或定点数
	output wire[INFO_ALONG_WIDTH-1:0] pool_upd_out_info_along, // 随路数据
	output wire pool_upd_out_valid // 输出有效指示
);
	
	/** 常量 **/
	// 池化模式的编码
	localparam POOL_MODE_AVG = 2'b00;
	localparam POOL_MODE_MAX = 2'b01;
	localparam POOL_MODE_UPSP = 2'b10;
	localparam POOL_MODE_NONE = 2'b11;
	// 运算数据格式的编码
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	localparam CAL_FMT_NONE = 2'b11;
	
	/** 输入有效指示延迟链 **/
	reg[6:1] pool_upd_in_valid_delayed;
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pool_upd_in_valid_delayed <= 6'b000000;
		else if(aclken)
			pool_upd_in_valid_delayed <= # SIM_DELAY {pool_upd_in_valid_delayed[5:1], pool_upd_in_valid};
	end
	
	/** 输入操作数延迟链 **/
	reg[15:0] pool_upd_in_new_res_delayed[1:4];
	reg[31:0] pool_upd_in_org_mid_res_delayed[1:4];
	
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid)
		begin
			pool_upd_in_new_res_delayed[1] <= # SIM_DELAY pool_upd_in_data;
			pool_upd_in_org_mid_res_delayed[1] <= # SIM_DELAY pool_upd_in_org_mid_res;
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[1])
		begin
			pool_upd_in_new_res_delayed[2] <= # SIM_DELAY pool_upd_in_new_res_delayed[1];
			pool_upd_in_org_mid_res_delayed[2] <= # SIM_DELAY pool_upd_in_org_mid_res_delayed[1];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[2])
		begin
			pool_upd_in_new_res_delayed[3] <= # SIM_DELAY pool_upd_in_new_res_delayed[2];
			pool_upd_in_org_mid_res_delayed[3] <= # SIM_DELAY pool_upd_in_org_mid_res_delayed[2];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[3])
		begin
			pool_upd_in_new_res_delayed[4] <= # SIM_DELAY pool_upd_in_new_res_delayed[3];
			pool_upd_in_org_mid_res_delayed[4] <= # SIM_DELAY pool_upd_in_org_mid_res_delayed[3];
		end
	end
	
	/** 输入特例标志延迟链 **/
	reg[5:1] pool_upd_in_is_first_item_delayed;
	reg[5:1] pool_upd_in_is_zero_sfc_delayed;
	
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid)
		begin
			pool_upd_in_is_first_item_delayed[1] <= # SIM_DELAY pool_upd_in_is_first_item;
			pool_upd_in_is_zero_sfc_delayed[1] <= # SIM_DELAY pool_upd_in_is_zero_sfc;
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[1])
		begin
			pool_upd_in_is_first_item_delayed[2] <= # SIM_DELAY pool_upd_in_is_first_item_delayed[1];
			pool_upd_in_is_zero_sfc_delayed[2] <= # SIM_DELAY pool_upd_in_is_zero_sfc_delayed[1];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[2])
		begin
			pool_upd_in_is_first_item_delayed[3] <= # SIM_DELAY pool_upd_in_is_first_item_delayed[2];
			pool_upd_in_is_zero_sfc_delayed[3] <= # SIM_DELAY pool_upd_in_is_zero_sfc_delayed[2];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[3])
		begin
			pool_upd_in_is_first_item_delayed[4] <= # SIM_DELAY pool_upd_in_is_first_item_delayed[3];
			pool_upd_in_is_zero_sfc_delayed[4] <= # SIM_DELAY pool_upd_in_is_zero_sfc_delayed[3];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[4])
		begin
			pool_upd_in_is_first_item_delayed[5] <= # SIM_DELAY pool_upd_in_is_first_item_delayed[4];
			pool_upd_in_is_zero_sfc_delayed[5] <= # SIM_DELAY pool_upd_in_is_zero_sfc_delayed[4];
		end
	end
	
	/** 随路数据延迟链 **/
	reg[INFO_ALONG_WIDTH-1:0] pool_upd_in_info_along_delayed[1:6];
	
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid)
			pool_upd_in_info_along_delayed[1] <= # SIM_DELAY pool_upd_in_info_along;
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[1])
			pool_upd_in_info_along_delayed[2] <= # SIM_DELAY pool_upd_in_info_along_delayed[1];
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[2])
			pool_upd_in_info_along_delayed[3] <= # SIM_DELAY pool_upd_in_info_along_delayed[2];
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[3])
			pool_upd_in_info_along_delayed[4] <= # SIM_DELAY pool_upd_in_info_along_delayed[3];
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[4])
			pool_upd_in_info_along_delayed[5] <= # SIM_DELAY pool_upd_in_info_along_delayed[4];
	end
	always @(posedge aclk)
	begin
		if(aclken & pool_upd_in_valid_delayed[5])
			pool_upd_in_info_along_delayed[6] <= # SIM_DELAY pool_upd_in_info_along_delayed[5];
	end
	
	/**
	共享加法器#0
	
	26位有符号加法器
	**/
	wire signed[24:0] shared_adder0_op_a;
	wire signed[24:0] shared_adder0_op_b;
	wire shared_adder0_ce;
	wire signed[25:0] shared_adder0_res;
	
	assign shared_adder0_res = 
		(
			shared_adder0_ce ? 
				{shared_adder0_op_a[24], shared_adder0_op_a[24:0]}:
				26'd0
		) + 
		(
			shared_adder0_ce ? 
				{shared_adder0_op_b[24], shared_adder0_op_b[24:0]}:
				26'd0
		);
	
	/**
	共享取负数单元#0
	
	25位取负数单元
	**/
	wire signed[24:0] shared_neg0_op_a;
	wire shared_neg0_op_b;
	wire shared_neg0_ce;
	wire signed[24:0] shared_neg0_res;
	
	assign shared_neg0_res = 
		shared_neg0_ce ? 
			(({25{shared_neg0_op_b}} ^ shared_neg0_op_a) + (shared_neg0_op_b ? 1'b1:1'b0)):
			25'd0;
	
	/**
	整型(INT8或INT16)池化更新
	
	--------------------------------------------------------------------------
	| 流水线级 |              完成的逻辑             |         备注          |
	--------------------------------------------------------------------------
	|    1     | 计算: 原中间结果 +/- 新结果         | 平均池化时作加法计算, |
	|          |                                     | 最大池化时作减法计算  |
	--------------------------------------------------------------------------
	|    2     | 在"原中间结果"和"新结果"中          | 平均池化时作选较大者  |
	|          | 选出较大者, 或作溢出饱和化处理      | 处理, 最大池化时作溢出|
	|          |                                     | 饱和化处理            |
	--------------------------------------------------------------------------
	**/
	// [整型运算给出的共享加法器#0端口]
	wire signed[24:0] int_shared_adder0_op_a;
	wire signed[24:0] int_shared_adder0_op_b;
	wire int_shared_adder0_ce;
	// [整型运算给出的共享取负数单元#0端口]
	wire signed[24:0] int_shared_neg0_op_a;
	wire int_shared_neg0_op_b;
	wire int_shared_neg0_ce;
	// [相加或相减后的中间结果]
	wire int_added_in_vld;
	wire int_added_in_is_first_item;
	wire int_added_in_is_zero_sfc;
	reg signed[16:0] int_added_res;
	// [选出较大者或作溢出饱和化处理后的中间结果]
	wire int_max_sel_or_sat_hdl_in_vld;
	wire int_max_sel_or_sat_hdl_in_is_first_item;
	wire int_max_sel_or_sat_hdl_in_is_zero_sfc;
	wire[15:0] int_max_sel_or_sat_hdl_in_new_res;
	wire[31:0] int_max_sel_or_sat_hdl_in_org_mid_res;
	wire int_max_sel_or_sat_hdl_ovf_flag; // 上溢标志
	wire int_max_sel_or_sat_hdl_udf_flag; // 下溢标志
	wire int_max_sel_or_sat_hdl_is_org_mid_res_geq_new_res; // 原中间结果 >= 新结果(标志)
	reg signed[15:0] int_max_sel_or_sat_hdl_res;
	// [更新后的结果]
	wire int_fnl_out_vld;
	wire signed[31:0] int_fnl_res;
	wire[INFO_ALONG_WIDTH-1:0] int_fnl_info_along;
	
	assign int_shared_adder0_op_a = 
		{{9{pool_upd_in_org_mid_res[15]}}, pool_upd_in_org_mid_res[15:0]};
	assign int_shared_adder0_op_b = 
		shared_neg0_res[24:0];
	assign int_shared_adder0_ce = 
		aclken & 
		pool_upd_in_valid & 
		((pool_mode == POOL_MODE_AVG) | (pool_mode == POOL_MODE_MAX)) & 
		(~(pool_upd_in_is_first_item | pool_upd_in_is_zero_sfc));
	
	assign int_shared_neg0_op_a = {{9{pool_upd_in_data[15]}}, pool_upd_in_data[15:0]};
	assign int_shared_neg0_op_b = pool_mode == POOL_MODE_MAX;
	assign int_shared_neg0_ce = int_shared_adder0_ce;
	
	assign int_added_in_vld = pool_upd_in_valid;
	assign int_added_in_is_first_item = pool_upd_in_is_first_item;
	assign int_added_in_is_zero_sfc = pool_upd_in_is_zero_sfc;
	
	assign int_max_sel_or_sat_hdl_in_vld = pool_upd_in_valid_delayed[1];
	assign int_max_sel_or_sat_hdl_in_is_first_item = pool_upd_in_is_first_item_delayed[1];
	assign int_max_sel_or_sat_hdl_in_is_zero_sfc = pool_upd_in_is_zero_sfc_delayed[1];
	assign int_max_sel_or_sat_hdl_in_new_res = pool_upd_in_new_res_delayed[1];
	assign int_max_sel_or_sat_hdl_in_org_mid_res = pool_upd_in_org_mid_res_delayed[1];
	assign int_max_sel_or_sat_hdl_ovf_flag = 
		(~int_added_res[16]) & 
		(
			int_added_res[15] | 
			((calfmt == CAL_FMT_INT8) & (|int_added_res[14:7]))
		);
	assign int_max_sel_or_sat_hdl_udf_flag = 
		int_added_res[16] & 
		(
			(~int_added_res[15]) | 
			((calfmt == CAL_FMT_INT8) & (~(&int_added_res[14:7])))
		);
	assign int_max_sel_or_sat_hdl_is_org_mid_res_geq_new_res = ~int_added_res[16];
	
	assign int_fnl_out_vld = pool_upd_in_valid_delayed[2];
	assign int_fnl_res = {{16{int_max_sel_or_sat_hdl_res[15]}}, int_max_sel_or_sat_hdl_res[15:0]};
	assign int_fnl_info_along = pool_upd_in_info_along_delayed[2];
	
	// 相加或相减后的中间结果
	always @(posedge aclk)
	begin
		if(int_shared_adder0_ce)
			int_added_res <= # SIM_DELAY shared_adder0_res[16:0];
	end
	
	// 选出较大者或作溢出饱和化处理后的中间结果
	always @(posedge aclk)
	begin
		if(
			aclken & 
			int_max_sel_or_sat_hdl_in_vld & 
			(
				((pool_mode == POOL_MODE_UPSP) | int_max_sel_or_sat_hdl_in_is_first_item) | 
				((pool_mode == POOL_MODE_MAX) | (~int_max_sel_or_sat_hdl_in_is_zero_sfc))
			)
		)
			int_max_sel_or_sat_hdl_res <= # SIM_DELAY 
				((pool_mode == POOL_MODE_UPSP) | int_max_sel_or_sat_hdl_in_is_first_item) ? 
					(
						int_max_sel_or_sat_hdl_in_is_zero_sfc ? 
							16'd0:
							int_max_sel_or_sat_hdl_in_new_res
					):
					(
						(pool_mode == POOL_MODE_MAX) ? 
							(
								(int_max_sel_or_sat_hdl_in_is_zero_sfc | int_max_sel_or_sat_hdl_is_org_mid_res_geq_new_res) ? 
									(
										(int_max_sel_or_sat_hdl_in_is_zero_sfc & int_max_sel_or_sat_hdl_in_org_mid_res[15]) ? 
											16'd0:
											int_max_sel_or_sat_hdl_in_org_mid_res[15:0]
									):
									int_max_sel_or_sat_hdl_in_new_res
							):
							(
								(calfmt == CAL_FMT_INT8) ? 
									{
										{9{int_added_res[16]}},
										{7{~int_max_sel_or_sat_hdl_udf_flag}} & 
											({7{int_max_sel_or_sat_hdl_ovf_flag}} | int_added_res[6:0])
									}:
									{
										int_added_res[16],
										{15{~int_max_sel_or_sat_hdl_udf_flag}} & 
											({15{int_max_sel_or_sat_hdl_ovf_flag}} | int_added_res[14:0])
									}
							)
					);
	end
	
	/**
	浮点(FP16)池化更新
	
	--------------------------------------------------------------------------
	| 流水线级 |              完成的逻辑             |         备注          |
	--------------------------------------------------------------------------
	|    1     | 确定较大的指数和右移位数            | 平均池化时, 计算      |
	-------------------------------------------------| 原中间结果 + 新结果   |
	|    2     | 对阶右移                            |                       |
	-------------------------------------------------| 最大池化时, 计算      |
	|    3     | 尾数求和                            | 原中间结果 - 新结果   |
	--------------------------------------------------------------------------
	|    4     | 标准化(>>>1, <<0~29)                |                       |
	--------------------------------------------------------------------------
	|    5     | 修正(>>>1), 下溢处理                |                       |
	|          | 选出较大者                          |                       |
	--------------------------------------------------------------------------
	|    6     | 浮点数打包                          |                       |
	--------------------------------------------------------------------------
	**/
	// [浮点运算给出的共享加法器#0端口]
	wire signed[24:0] fp_shared_adder0_op_a;
	wire signed[24:0] fp_shared_adder0_op_b;
	wire fp_shared_adder0_ce;
	// [浮点运算给出的共享取负数单元#0端口]
	wire signed[24:0] fp_shared_neg0_op_a;
	wire fp_shared_neg0_op_b;
	wire fp_shared_neg0_ce;
	// [浮点操作数输入]
	wire signed[7:0] fp_upd_i_org_res_exp; // 原中间结果的指数(在[-126, 127]范围内)
	wire signed[24:0] fp_upd_i_org_res_mts; // 原中间结果的补码形式尾数(Q23)
	wire signed[4:0] fp_upd_i_new_res_exp; // 新结果的指数(在[-14, 15]范围内)
	wire signed[11:0] fp_upd_i_new_res_mts; // 新结果的补码形式尾数(Q10)
	// [确定较大的指数和右移位数]
	wire fp_pre_align_in_vld;
	wire fp_pre_align_in_is_first_item;
	wire fp_pre_align_in_is_zero_sfc;
	wire fp_pre_align_in_is_org_res_exp_gth_new_res; // 原中间结果的指数更大(标志)
	wire signed[7:0] fp_pre_align_in_exp; // 对齐到的指数(在[-126, 127]范围内)
	wire[7:0] fp_pre_align_in_rsh_n; // 右移位数
	reg fp_pre_align_is_org_res_exp_gth_new_res; // 原中间结果的指数更大(标志)
	reg signed[7:0] fp_pre_align_exp; // 对齐到的指数(在[-126, 127]范围内)
	reg[7:0] fp_pre_align_rsh_n; // 右移位数
	reg signed[24:0] fp_pre_align_org_res_mts; // 延迟1clk的原中间结果的补码形式尾数(Q23)
	reg signed[11:0] fp_pre_align_new_res_mts; // 延迟1clk的新结果的补码形式尾数(Q10)
	reg signed[4:0] fp_pre_align_new_res_exp; // 延迟1clk的新结果的指数(在[-14, 15]范围内)
	// [对阶右移]
	wire fp_align_rsh_in_vld;
	wire fp_align_rsh_in_is_first_item;
	wire fp_align_rsh_in_is_zero_sfc;
	wire[4:0] fp_align_rsh_in_rsh_n; // 右移位数
	wire signed[31:0] fp_align_rsh_in_mts_to_sh; // 待右移的尾数(Q30)
	wire signed[31:0] fp_align_rsh_in_mts_shifted; // 右移后的尾数(Q30)
	reg signed[31:0] fp_align_rsh_org_res; // 对阶后的原中间结果(Q30)
	reg signed[31:0] fp_align_rsh_new_res; // 对阶后的新结果(Q30)
	reg signed[7:0] fp_align_rsh_exp; // 对阶后的指数(在[-126, 127]范围内)
	reg signed[4:0] fp_align_rsh_new_res_exp; // 延迟2clk的新结果的指数(在[-14, 15]范围内)
	(*dont_touch="true"*)reg signed[30:0] fp_align_rsh_new_res_mts; // 延迟2clk的新结果的补码形式尾数(Q29)
	// [尾数求和]
	wire fp_added_in_vld;
	wire fp_added_in_is_first_item;
	wire fp_added_in_is_zero_sfc;
	wire fp_added_in_org_mid_res_geq0;
	reg signed[7:0] fp_added_exp; // 延迟1clk的对阶后的指数(在[-126, 127]范围内)
	reg signed[31:0] fp_added_mts; // 求和后的尾数(Q29)
	wire signed[31:0] fp_added_mts_rvs; // 位翻转的求和后的尾数(Q29)
	reg fp_added_is_org_mid_res_geq_new_res; // 原中间结果 >= 新结果(标志)
	// [标准化]
	wire fp_nml_in_vld;
	wire fp_nml_in_is_first_item;
	wire fp_nml_in_is_zero_sfc;
	wire[30:0] fp_nml_in_shift_n_onehot;
	reg signed[31:0] fp_nml_mts; // 标准化之后的尾数(Q29)
	reg signed[8:0] fp_nml_exp; // 标准化之后的指数(在范围[-155, 128]内)
	reg fp_nml_is_org_mid_res_geq_new_res; // 延迟1clk的"原中间结果 >= 新结果"(标志)
	// [修正, 下溢处理, 选出较大者]
	wire fp_fix_in_vld;
	wire fp_fix_in_is_first_item;
	wire fp_fix_in_is_zero_sfc;
	wire[31:0] fp_fix_in_org_mid_res;
	wire fp_fix_in_to_corr_flag; // 需要进行修正(标志)
	wire fp_fix_in_udf_flag; // 下溢标志
	wire signed[31:0] fp_fix_in_mts; // 修正后的尾数(Q29)
	wire signed[8:0] fp_fix_in_exp; // 修正后的指数(在范围[-155, 129]内)
	reg signed[24:0] fp_fix_mts; // 修正后的尾数(Q23)
	reg fp_fix_mts_inv_flag; // 修正后的尾数需要取负数(标志)
	reg[7:0] fp_fix_ec; // 修正后的阶码
	// [浮点数打包]
	wire fp_pack_in_vld;
	wire fp_pack_in_is_first_item;
	wire fp_pack_in_is_zero_sfc;
	reg fp_pack_sgn; // 打包后的符号位
	reg[7:0] fp_pack_ec; // 打包后的阶码
	reg[22:0] fp_pack_mts; // 打包后的尾数
	// [更新后的结果]
	wire fp_fnl_out_vld;
	wire[31:0] fp_fnl_res;
	wire[INFO_ALONG_WIDTH-1:0] fp_fnl_info_along;
	
	assign fp_shared_adder0_op_a = fp_align_rsh_org_res[31:7];
	assign fp_shared_adder0_op_b = fp_align_rsh_new_res[31:7];
	assign fp_shared_adder0_ce = 
		aclken & 
		pool_upd_in_valid_delayed[2] & 
		((pool_mode == POOL_MODE_AVG) | (pool_mode == POOL_MODE_MAX)) & 
		(~(pool_upd_in_is_first_item_delayed[2] | pool_upd_in_is_zero_sfc_delayed[2]));
	
	assign fp_shared_neg0_op_a = {1'b0, pool_upd_in_org_mid_res[30:23] != 8'd0, pool_upd_in_org_mid_res[22:0]};
	assign fp_shared_neg0_op_b = pool_upd_in_org_mid_res[31];
	assign fp_shared_neg0_ce = 
		aclken & 
		pool_upd_in_valid & 
		((pool_mode == POOL_MODE_AVG) | (pool_mode == POOL_MODE_MAX)) & 
		(~(pool_upd_in_is_first_item | pool_upd_in_is_zero_sfc));
	
	/*
	当阶码为0时, 指数 = 阶码 + 8'b10000010 = 阶码 - 126
	当阶码不为0时, 指数 = 阶码 + 8'b10000001 = 阶码 - 127
	
	指数在[-126, 127]范围内
	*/
	assign fp_upd_i_org_res_exp = pool_upd_in_org_mid_res[30:23] + 8'b10000001 + ((pool_upd_in_org_mid_res[30:23] == 8'd0) ? 1'b1:1'b0);
	assign fp_upd_i_org_res_mts = shared_neg0_res[24:0];
	
	/*
	当阶码为0时, 指数 = 阶码 + 5'b10010 = 阶码 - 14
	当阶码不为0时, 指数 = 阶码 + 5'b10001 = 阶码 - 15
	
	指数在[-14, 15]范围内
	*/
	assign fp_upd_i_new_res_exp = pool_upd_in_data[14:10] + 5'b10001 + ((pool_upd_in_data[14:10] == 5'd0) ? 1'b1:1'b0);
	assign fp_upd_i_new_res_mts = 
		(
			{12{(pool_mode == POOL_MODE_MAX) ^ pool_upd_in_data[15]}} ^ 
			{1'b0, pool_upd_in_data[14:10] != 5'd0, pool_upd_in_data[9:0]}
		) + 
		(((pool_mode == POOL_MODE_MAX) ^ pool_upd_in_data[15]) ? 1'b1:1'b0);
	
	assign fp_pre_align_in_vld = pool_upd_in_valid;
	assign fp_pre_align_in_is_first_item = pool_upd_in_is_first_item;
	assign fp_pre_align_in_is_zero_sfc = pool_upd_in_is_zero_sfc;
	assign fp_pre_align_in_is_org_res_exp_gth_new_res = 
		$signed(fp_upd_i_org_res_exp) > $signed(fp_upd_i_new_res_exp);
	assign fp_pre_align_in_exp = 
		fp_pre_align_in_is_org_res_exp_gth_new_res ? 
			fp_upd_i_org_res_exp[7:0]:
			{{3{fp_upd_i_new_res_exp[4]}}, fp_upd_i_new_res_exp[4:0]};
	assign fp_pre_align_in_rsh_n = 
		(
			fp_pre_align_in_is_org_res_exp_gth_new_res ? 
				fp_upd_i_org_res_exp[7:0]:
				{{3{fp_upd_i_new_res_exp[4]}}, fp_upd_i_new_res_exp[4:0]}
		) - 
		(
			fp_pre_align_in_is_org_res_exp_gth_new_res ? 
				{{3{fp_upd_i_new_res_exp[4]}}, fp_upd_i_new_res_exp[4:0]}:
				fp_upd_i_org_res_exp[7:0]
		);
	
	assign fp_align_rsh_in_vld = pool_upd_in_valid_delayed[1];
	assign fp_align_rsh_in_is_first_item = pool_upd_in_is_first_item_delayed[1];
	assign fp_align_rsh_in_is_zero_sfc = pool_upd_in_is_zero_sfc_delayed[1];
	assign fp_align_rsh_in_rsh_n = 
		(fp_pre_align_rsh_n >= 8'd24) ? 
			5'd24:
			fp_pre_align_rsh_n[4:0];
	assign fp_align_rsh_in_mts_to_sh = 
		fp_pre_align_is_org_res_exp_gth_new_res ? 
			{fp_pre_align_new_res_mts[11:0], 20'd0}:
			{fp_pre_align_org_res_mts[24:0], 7'd0};
	assign fp_align_rsh_in_mts_shifted = 
		fp_align_rsh_in_mts_to_sh >>> fp_align_rsh_in_rsh_n;
	
	assign fp_added_in_vld = pool_upd_in_valid_delayed[2];
	assign fp_added_in_is_first_item = pool_upd_in_is_first_item_delayed[2];
	assign fp_added_in_is_zero_sfc = pool_upd_in_is_zero_sfc_delayed[2];
	assign fp_added_in_org_mid_res_geq0 = ~pool_upd_in_org_mid_res_delayed[2][31];
	assign fp_added_mts_rvs = 
		{
			fp_added_mts[0], fp_added_mts[1], fp_added_mts[2], fp_added_mts[3],
			fp_added_mts[4], fp_added_mts[5], fp_added_mts[6], fp_added_mts[7],
			fp_added_mts[8], fp_added_mts[9], fp_added_mts[10], fp_added_mts[11],
			fp_added_mts[12], fp_added_mts[13], fp_added_mts[14], fp_added_mts[15],
			fp_added_mts[16], fp_added_mts[17], fp_added_mts[18], fp_added_mts[19],
			fp_added_mts[20], fp_added_mts[21], fp_added_mts[22], fp_added_mts[23],
			fp_added_mts[24], fp_added_mts[25], fp_added_mts[26], fp_added_mts[27],
			fp_added_mts[28], fp_added_mts[29], fp_added_mts[30], fp_added_mts[31]
		};
	
	assign fp_nml_in_vld = pool_upd_in_valid_delayed[3];
	assign fp_nml_in_is_first_item = pool_upd_in_is_first_item_delayed[3];
	assign fp_nml_in_is_zero_sfc = pool_upd_in_is_zero_sfc_delayed[3];
	/*
	当"求和后的尾数" < 0时, 从MSB开始找第1个"0"的位置;当"求和后的尾数" >= 0时, 从MSB开始找第1个"1"的位置
	
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
	assign fp_nml_in_shift_n_onehot = 
		({31{fp_added_mts_rvs[0]}} ^ fp_added_mts_rvs[31:1]) & 
		((~({31{fp_added_mts_rvs[0]}} ^ fp_added_mts_rvs[31:1])) + 1'b1);
	
	assign fp_fix_in_vld = pool_upd_in_valid_delayed[4];
	assign fp_fix_in_is_first_item = pool_upd_in_is_first_item_delayed[4];
	assign fp_fix_in_is_zero_sfc = pool_upd_in_is_zero_sfc_delayed[4];
	assign fp_fix_in_org_mid_res = pool_upd_in_org_mid_res_delayed[4];
	assign fp_fix_in_to_corr_flag = (fp_nml_mts[31:29] == 3'b110) & (fp_nml_mts[28:6] == 23'd0);
	assign fp_fix_in_udf_flag = (fp_fix_in_exp < -9'sd126) | (fp_nml_mts[31:29] == 3'b000);
	assign fp_fix_in_mts = fp_nml_mts[31:0];
	assign fp_fix_in_exp = fp_nml_exp + (fp_fix_in_to_corr_flag ? 1'b1:1'b0);
	
	assign fp_pack_in_vld = pool_upd_in_valid_delayed[5];
	assign fp_pack_in_is_first_item = pool_upd_in_is_first_item_delayed[5];
	assign fp_pack_in_is_zero_sfc = pool_upd_in_is_zero_sfc_delayed[5];
	
	assign fp_fnl_out_vld = pool_upd_in_valid_delayed[6];
	assign fp_fnl_res = {fp_pack_sgn, fp_pack_ec, fp_pack_mts};
	assign fp_fnl_info_along = pool_upd_in_info_along_delayed[6];
	
	// 原中间结果的指数更大(标志), 对齐到的指数(在[-126, 127]范围内), 右移位数, 延迟1clk的原中间结果的补码形式尾数(Q23)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_pre_align_in_vld & 
			((pool_mode == POOL_MODE_AVG) | (pool_mode == POOL_MODE_MAX)) & 
			(~(fp_pre_align_in_is_first_item | fp_pre_align_in_is_zero_sfc))
		)
		begin
			fp_pre_align_is_org_res_exp_gth_new_res <= # SIM_DELAY fp_pre_align_in_is_org_res_exp_gth_new_res;
			fp_pre_align_exp <= # SIM_DELAY fp_pre_align_in_exp;
			fp_pre_align_rsh_n <= # SIM_DELAY fp_pre_align_in_rsh_n;
			fp_pre_align_org_res_mts <= # SIM_DELAY fp_upd_i_org_res_mts;
		end
	end
	// 延迟1clk的新结果的补码形式尾数(Q10), 延迟1clk的新结果的指数(在[-14, 15]范围内)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_pre_align_in_vld & 
			(~fp_pre_align_in_is_zero_sfc)
		)
		begin
			fp_pre_align_new_res_mts <= # SIM_DELAY fp_upd_i_new_res_mts;
			fp_pre_align_new_res_exp <= # SIM_DELAY fp_upd_i_new_res_exp;
		end
	end
	
	// 对阶后的原中间结果(Q30),  对阶后的新结果(Q30), 对阶后的指数(在[-126, 127]范围内)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_align_rsh_in_vld & 
			((pool_mode == POOL_MODE_AVG) | (pool_mode == POOL_MODE_MAX)) & 
			(~(fp_align_rsh_in_is_first_item | fp_align_rsh_in_is_zero_sfc))
		)
		begin
			fp_align_rsh_org_res <= # SIM_DELAY 
				fp_pre_align_is_org_res_exp_gth_new_res ? 
					{fp_pre_align_org_res_mts[24:0], 7'd0}:
					fp_align_rsh_in_mts_shifted;
			fp_align_rsh_new_res <= # SIM_DELAY 
				fp_pre_align_is_org_res_exp_gth_new_res ? 
					fp_align_rsh_in_mts_shifted:
					{fp_pre_align_new_res_mts[11:0], 20'd0};
			fp_align_rsh_exp <= # SIM_DELAY 
				fp_pre_align_exp;
		end
	end
	// 延迟2clk的新结果的指数(在[-14, 15]范围内), 延迟2clk的新结果的补码形式尾数(Q29)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_align_rsh_in_vld & 
			(~fp_align_rsh_in_is_zero_sfc)
		)
		begin
			fp_align_rsh_new_res_exp <= # SIM_DELAY fp_pre_align_new_res_exp;
			fp_align_rsh_new_res_mts <= # SIM_DELAY {fp_pre_align_new_res_mts, 19'd0};
		end
	end
	
	// 延迟1clk的对阶后的指数(在[-126, 127]范围内), 求和后的尾数(Q29)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_added_in_vld & 
			(~fp_added_in_is_zero_sfc)
		)
		begin
			fp_added_exp <= # SIM_DELAY 
				(
					((pool_mode == POOL_MODE_UPSP) | fp_added_in_is_first_item) | 
					((pool_mode == POOL_MODE_MAX) & shared_adder0_res[25])
				) ? 
					{{3{fp_align_rsh_new_res_exp[4]}}, fp_align_rsh_new_res_exp[4:0]}:
					fp_align_rsh_exp;
			
			fp_added_mts <= # SIM_DELAY 
				(
					((pool_mode == POOL_MODE_UPSP) | fp_added_in_is_first_item) | 
					((pool_mode == POOL_MODE_MAX) & shared_adder0_res[25])
				) ? 
					{fp_align_rsh_new_res_mts[30], fp_align_rsh_new_res_mts[30:0]}:
					{shared_adder0_res[25:0], fp_align_rsh_org_res[6:1] | fp_align_rsh_new_res[6:1]};
		end
	end
	
	// 原中间结果 >= 新结果(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_added_in_vld & 
			(pool_mode == POOL_MODE_MAX) & 
			(~fp_added_in_is_first_item)
		)
			fp_added_is_org_mid_res_geq_new_res <= # SIM_DELAY 
				fp_added_in_is_zero_sfc ? 
					fp_added_in_org_mid_res_geq0:
					(~shared_adder0_res[25]);
	end
	
	// 标准化之后的尾数(Q29), 标准化之后的指数(在范围[-155, 128]内)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_nml_in_vld & 
			(~fp_nml_in_is_zero_sfc)
		)
		begin
			fp_nml_mts <= # SIM_DELAY 
				({32{fp_nml_in_shift_n_onehot[0]}} & {fp_added_mts[31], fp_added_mts[31:1]}) | // 算术右移1位
				({32{fp_nml_in_shift_n_onehot[1]}} & fp_added_mts) | 
				({32{fp_nml_in_shift_n_onehot[2]}} & (fp_added_mts << 1)) | 
				({32{fp_nml_in_shift_n_onehot[3]}} & (fp_added_mts << 2)) | 
				({32{fp_nml_in_shift_n_onehot[4]}} & (fp_added_mts << 3)) | 
				({32{fp_nml_in_shift_n_onehot[5]}} & (fp_added_mts << 4)) | 
				({32{fp_nml_in_shift_n_onehot[6]}} & (fp_added_mts << 5)) | 
				({32{fp_nml_in_shift_n_onehot[7]}} & (fp_added_mts << 6)) | 
				({32{fp_nml_in_shift_n_onehot[8]}} & (fp_added_mts << 7)) | 
				({32{fp_nml_in_shift_n_onehot[9]}} & (fp_added_mts << 8)) | 
				({32{fp_nml_in_shift_n_onehot[10]}} & (fp_added_mts << 9)) | 
				({32{fp_nml_in_shift_n_onehot[11]}} & (fp_added_mts << 10)) | 
				({32{fp_nml_in_shift_n_onehot[12]}} & (fp_added_mts << 11)) | 
				({32{fp_nml_in_shift_n_onehot[13]}} & (fp_added_mts << 12)) | 
				({32{fp_nml_in_shift_n_onehot[14]}} & (fp_added_mts << 13)) | 
				({32{fp_nml_in_shift_n_onehot[15]}} & (fp_added_mts << 14)) | 
				({32{fp_nml_in_shift_n_onehot[16]}} & (fp_added_mts << 15)) | 
				({32{fp_nml_in_shift_n_onehot[17]}} & (fp_added_mts << 16)) | 
				({32{fp_nml_in_shift_n_onehot[18]}} & (fp_added_mts << 17)) | 
				({32{fp_nml_in_shift_n_onehot[19]}} & (fp_added_mts << 18)) | 
				({32{fp_nml_in_shift_n_onehot[20]}} & (fp_added_mts << 19)) | 
				({32{fp_nml_in_shift_n_onehot[21]}} & (fp_added_mts << 20)) | 
				({32{fp_nml_in_shift_n_onehot[22]}} & (fp_added_mts << 21)) | 
				({32{fp_nml_in_shift_n_onehot[23]}} & (fp_added_mts << 22)) | 
				({32{fp_nml_in_shift_n_onehot[24]}} & (fp_added_mts << 23)) | 
				({32{fp_nml_in_shift_n_onehot[25]}} & (fp_added_mts << 24)) | 
				({32{fp_nml_in_shift_n_onehot[26]}} & (fp_added_mts << 25)) | 
				({32{fp_nml_in_shift_n_onehot[27]}} & (fp_added_mts << 26)) | 
				({32{fp_nml_in_shift_n_onehot[28]}} & (fp_added_mts << 27)) | 
				({32{fp_nml_in_shift_n_onehot[29]}} & (fp_added_mts << 28)) | 
				({32{fp_nml_in_shift_n_onehot[30] | (~(|fp_nml_in_shift_n_onehot))}} & (fp_added_mts << 29));
			
			fp_nml_exp <= # SIM_DELAY 
				{fp_added_exp[7], fp_added_exp[7:0]} + 
				(
					({9{fp_nml_in_shift_n_onehot[0]}}  & 9'b000000001) | // 1
					({9{fp_nml_in_shift_n_onehot[1]}}  & 9'b000000000) | // 0
					({9{fp_nml_in_shift_n_onehot[2]}}  & 9'b111111111) | // -1
					({9{fp_nml_in_shift_n_onehot[3]}}  & 9'b111111110) | // -2
					({9{fp_nml_in_shift_n_onehot[4]}}  & 9'b111111101) | // -3
					({9{fp_nml_in_shift_n_onehot[5]}}  & 9'b111111100) | // -4
					({9{fp_nml_in_shift_n_onehot[6]}}  & 9'b111111011) | // -5
					({9{fp_nml_in_shift_n_onehot[7]}}  & 9'b111111010) | // -6
					({9{fp_nml_in_shift_n_onehot[8]}}  & 9'b111111001) | // -7
					({9{fp_nml_in_shift_n_onehot[9]}}  & 9'b111111000) | // -8
					({9{fp_nml_in_shift_n_onehot[10]}} & 9'b111110111) | // -9
					({9{fp_nml_in_shift_n_onehot[11]}} & 9'b111110110) | // -10
					({9{fp_nml_in_shift_n_onehot[12]}} & 9'b111110101) | // -11
					({9{fp_nml_in_shift_n_onehot[13]}} & 9'b111110100) | // -12
					({9{fp_nml_in_shift_n_onehot[14]}} & 9'b111110011) | // -13
					({9{fp_nml_in_shift_n_onehot[15]}} & 9'b111110010) | // -14
					({9{fp_nml_in_shift_n_onehot[16]}} & 9'b111110001) | // -15
					({9{fp_nml_in_shift_n_onehot[17]}} & 9'b111110000) | // -16
					({9{fp_nml_in_shift_n_onehot[18]}} & 9'b111101111) | // -17
					({9{fp_nml_in_shift_n_onehot[19]}} & 9'b111101110) | // -18
					({9{fp_nml_in_shift_n_onehot[20]}} & 9'b111101101) | // -19
					({9{fp_nml_in_shift_n_onehot[21]}} & 9'b111101100) | // -20
					({9{fp_nml_in_shift_n_onehot[22]}} & 9'b111101011) | // -21
					({9{fp_nml_in_shift_n_onehot[23]}} & 9'b111101010) | // -22
					({9{fp_nml_in_shift_n_onehot[24]}} & 9'b111101001) | // -23
					({9{fp_nml_in_shift_n_onehot[25]}} & 9'b111101000) | // -24
					({9{fp_nml_in_shift_n_onehot[26]}} & 9'b111100111) | // -25
					({9{fp_nml_in_shift_n_onehot[27]}} & 9'b111100110) | // -26
					({9{fp_nml_in_shift_n_onehot[28]}} & 9'b111100101) | // -27
					({9{fp_nml_in_shift_n_onehot[29]}} & 9'b111100100) | // -28
					({9{fp_nml_in_shift_n_onehot[30] | (~(|fp_nml_in_shift_n_onehot))}} & 9'b111100011) // -29
				);
		end
	end
	
	// 延迟1clk的"原中间结果 >= 新结果"(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_nml_in_vld & 
			(pool_mode == POOL_MODE_MAX) & 
			(~fp_nml_in_is_first_item)
		)
			fp_nml_is_org_mid_res_geq_new_res <= # SIM_DELAY 
				fp_added_is_org_mid_res_geq_new_res;
	end
	
	// 修正后的尾数(Q23), 修正后的尾数需要取负数(标志), 修正后的阶码
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_fix_in_vld & 
			(
				((pool_mode == POOL_MODE_UPSP) | fp_fix_in_is_first_item) | 
				((pool_mode == POOL_MODE_MAX) | (~fp_fix_in_is_zero_sfc))
			)
		)
		begin
			if((pool_mode == POOL_MODE_UPSP) | fp_fix_in_is_first_item) // 载入本项
			begin
				fp_fix_mts <= # SIM_DELAY 
					(fp_fix_in_is_zero_sfc | fp_fix_in_udf_flag) ? 
						25'd0:
						fp_fix_in_mts[30:6];
				
				fp_fix_mts_inv_flag <= # SIM_DELAY pool_mode == POOL_MODE_MAX;
				
				fp_fix_ec <= # SIM_DELAY 
					(fp_fix_in_is_zero_sfc | fp_fix_in_udf_flag) ? 
						8'd0:
						(fp_fix_in_exp[7:0] + 8'd127);
			end
			else
			begin
				if(pool_mode == POOL_MODE_MAX)
				begin
					if(fp_nml_is_org_mid_res_geq_new_res) // 原中间结果 >= 新结果
					begin
						fp_fix_mts <= # SIM_DELAY 
							(
								{25{fp_fix_in_org_mid_res[31]}} ^ 
								{1'b0, fp_fix_in_org_mid_res[30:23] != 8'd0, fp_fix_in_org_mid_res[22:0]}
							) + 
							(fp_fix_in_org_mid_res[31] ? 1'b1:1'b0);
						
						fp_fix_mts_inv_flag <= # SIM_DELAY 1'b0;
						
						fp_fix_ec <= # SIM_DELAY fp_fix_in_org_mid_res[30:23];
					end
					else // 原中间结果 < 新结果
					begin
						if(fp_fix_in_is_zero_sfc)
						begin
							fp_fix_mts <= # SIM_DELAY 25'd0;
							
							fp_fix_mts_inv_flag <= # SIM_DELAY 1'b0;
							
							fp_fix_ec <= # SIM_DELAY 8'd0;
						end
						else
						begin
							fp_fix_mts <= # SIM_DELAY 
								fp_fix_in_udf_flag ? 
									25'd0:
									fp_fix_in_mts[30:6];
							
							fp_fix_mts_inv_flag <= # SIM_DELAY 1'b1;
							
							fp_fix_ec <= # SIM_DELAY 
								fp_fix_in_udf_flag ? 
									8'd0:
									(fp_fix_in_exp[7:0] + 8'd127);
						end
					end
				end
				else
				begin
					fp_fix_mts <= # SIM_DELAY 
						fp_fix_in_udf_flag ? 
							25'd0:
							fp_fix_in_mts[30:6];
					
					fp_fix_mts_inv_flag <= # SIM_DELAY 1'b0;
					
					fp_fix_ec <= # SIM_DELAY 
						fp_fix_in_udf_flag ? 
							8'd0:
							(fp_fix_in_exp[7:0] + 8'd127);
				end
			end
		end
	end
	
	// 打包后的符号位, 打包后的阶码, 打包后的尾数
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fp_pack_in_vld & 
			(
				((pool_mode == POOL_MODE_UPSP) | fp_pack_in_is_first_item) | 
				((pool_mode == POOL_MODE_MAX) | (~fp_pack_in_is_zero_sfc))
			)
		)
		begin
			fp_pack_sgn <= # SIM_DELAY fp_fix_mts[24] ^ fp_fix_mts_inv_flag;
			fp_pack_ec <= # SIM_DELAY fp_fix_ec[7:0];
			fp_pack_mts <= # SIM_DELAY 
				({23{fp_fix_mts[24]}} ^ fp_fix_mts[22:0]) + (fp_fix_mts[24] ? 1'b1:1'b0);
		end
	end
	
	/** 计算单元复用 **/
	assign shared_adder0_op_a = 
		(calfmt == CAL_FMT_FP16) ? 
			fp_shared_adder0_op_a:
			int_shared_adder0_op_a;
	assign shared_adder0_op_b = 
		(calfmt == CAL_FMT_FP16) ? 
			fp_shared_adder0_op_b:
			int_shared_adder0_op_b;
	assign shared_adder0_ce = 
		((calfmt == CAL_FMT_FP16) & fp_shared_adder0_ce) | 
		(((calfmt == CAL_FMT_INT16) | (calfmt == CAL_FMT_INT8)) & int_shared_adder0_ce);
	
	assign shared_neg0_op_a = 
		(calfmt == CAL_FMT_FP16) ? 
			fp_shared_neg0_op_a:
			int_shared_neg0_op_a;
	assign shared_neg0_op_b = 
		(calfmt == CAL_FMT_FP16) ? 
			fp_shared_neg0_op_b:
			int_shared_neg0_op_b;
	assign shared_neg0_ce = 
		((calfmt == CAL_FMT_FP16) & fp_shared_neg0_ce) | 
		(((calfmt == CAL_FMT_INT16) | (calfmt == CAL_FMT_INT8)) & int_shared_neg0_ce);
	
	/** 池化结果更新输出 **/
	assign  pool_upd_out_data = 
		(calfmt == CAL_FMT_FP16) ? 
			fp_fnl_res:
			int_fnl_res;
	assign pool_upd_out_info_along = 
		(calfmt == CAL_FMT_FP16) ? 
			fp_fnl_info_along:
			int_fnl_info_along;
	assign pool_upd_out_valid = 
		((calfmt == CAL_FMT_FP16) & fp_fnl_out_vld) | 
		(((calfmt == CAL_FMT_INT16) | (calfmt == CAL_FMT_INT8)) & int_fnl_out_vld);
	
endmodule
