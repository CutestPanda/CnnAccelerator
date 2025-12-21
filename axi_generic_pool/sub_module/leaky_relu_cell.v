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
本模块: 泄露Relu激活单元

描述:
计算Leaky Relu -> 
----------------------------------
|       |  x >= 0时  |  x < 0时  |
|   y   |-------------------------
|       |     x      |    ax     |
----------------------------------

无论是哪种运算数据格式, 都有时延 = 5clk

支持INT16、INT32、FP32三种运算数据格式

----------------------------------------------------------
| 是否需要支持INT32运算数据格式 |       乘法器类型       |
----------------------------------------------------------
|              是               | s32, 时延 = 2clk       |
----------------------------------------------------------
|              否               | s25, 时延 = 2clk       |
----------------------------------------------------------

带有全局时钟使能

注意:
浮点运算未考虑INF和NAN

当运算数据格式为FP32时, 激活参数(act_param_alpha)必须是规则数

当运算数据格式为INT16或INT32时, 激活参数(act_param_alpha)的量化精度为fixed_point_quat_accrc

协议:
无

作者: 陈家耀
日期: 2025/12/19
********************************************************************/


module leaky_relu_cell #(
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
	input wire[1:0] act_calfmt, // 运算数据格式
	input wire[4:0] fixed_point_quat_accrc, // 定点数量化精度
	input wire[31:0] act_param_alpha, // 激活参数
	
	// 激活单元计算输入
	input wire[31:0] act_cell_i_op_x, // 操作数X
	input wire act_cell_i_pass, // 不作激活处理(标志)
	input wire[INFO_ALONG_WIDTH-1:0] act_cell_i_info_along, // 随路数据
	input wire act_cell_i_vld,
	
	// 激活单元结果输出
	output wire[31:0] act_cell_o_res, // 计算结果
	output wire[INFO_ALONG_WIDTH-1:0] act_cell_o_info_along, // 随路数据
	output wire act_cell_o_vld,
	
	// 外部有符号乘法器
	output wire[(INT32_SUPPORTED ? 32:25)-1:0] mul_op_a, // 操作数A
	output wire[(INT32_SUPPORTED ? 32:25)-1:0] mul_op_b, // 操作数B
	output wire[1:0] mul_ce, // 计算使能
	input wire[(INT32_SUPPORTED ? 64:50)-1:0] mul_res // 计算结果
);
	
	/** 常量 **/
	// 运算数据格式的编码
	localparam ACT_CAL_FMT_INT16 = 2'b00;
	localparam ACT_CAL_FMT_INT32 = 2'b01;
	localparam ACT_CAL_FMT_FP32 = 2'b10;
	localparam ACT_CAL_FMT_NONE = 2'b11;
	
	/** 运算数据格式 **/
	wire[1:0] act_calfmt_inner;
	
	assign act_calfmt_inner = 
		(INT16_SUPPORTED & (act_calfmt == ACT_CAL_FMT_INT16)) ? ACT_CAL_FMT_INT16:
		(INT32_SUPPORTED & (act_calfmt == ACT_CAL_FMT_INT32)) ? ACT_CAL_FMT_INT32:
		(FP32_SUPPORTED  & (act_calfmt == ACT_CAL_FMT_FP32))  ? ACT_CAL_FMT_FP32:
		                                                        ACT_CAL_FMT_NONE;
	
	/** 输入延迟链 **/
	reg[5:1] act_cell_i_vld_delayed; // 延迟的输入有效指示
	reg[5:1] act_cell_i_pass_delayed; // 延迟的不作激活处理标志
	reg[INFO_ALONG_WIDTH-1:0] act_cell_i_info_along_delayed[1:5]; // 延迟的随路数据
	reg[31:0] act_cell_i_op_x_delayed[1:5]; // 延迟的操作数X
	
	// 延迟的输入有效指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			act_cell_i_vld_delayed <= 5'b00000;
		else if(aclken)
			act_cell_i_vld_delayed <= # SIM_DELAY {act_cell_i_vld_delayed[4:1], act_cell_i_vld};
	end
	
	// 延迟的不作激活处理标志, 延迟的随路数据, 延迟的操作数X
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld)
		begin
			act_cell_i_pass_delayed[1] <= # SIM_DELAY act_cell_i_pass;
			act_cell_i_info_along_delayed[1] <= # SIM_DELAY act_cell_i_info_along;
			act_cell_i_op_x_delayed[1] <= # SIM_DELAY act_cell_i_op_x;
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[1])
		begin
			act_cell_i_pass_delayed[2] <= # SIM_DELAY act_cell_i_pass_delayed[1];
			act_cell_i_info_along_delayed[2] <= # SIM_DELAY act_cell_i_info_along_delayed[1];
			act_cell_i_op_x_delayed[2] <= # SIM_DELAY act_cell_i_op_x_delayed[1];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[2])
		begin
			act_cell_i_pass_delayed[3] <= # SIM_DELAY act_cell_i_pass_delayed[2];
			act_cell_i_info_along_delayed[3] <= # SIM_DELAY act_cell_i_info_along_delayed[2];
			act_cell_i_op_x_delayed[3] <= # SIM_DELAY act_cell_i_op_x_delayed[2];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[3])
		begin
			act_cell_i_pass_delayed[4] <= # SIM_DELAY act_cell_i_pass_delayed[3];
			act_cell_i_info_along_delayed[4] <= # SIM_DELAY act_cell_i_info_along_delayed[3];
			act_cell_i_op_x_delayed[4] <= # SIM_DELAY act_cell_i_op_x_delayed[3];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[4])
		begin
			act_cell_i_pass_delayed[5] <= # SIM_DELAY act_cell_i_pass_delayed[4];
			act_cell_i_info_along_delayed[5] <= # SIM_DELAY act_cell_i_info_along_delayed[4];
			act_cell_i_op_x_delayed[5] <= # SIM_DELAY act_cell_i_op_x_delayed[4];
		end
	end
	
	/**
	激活计算(整型格式)
	
	-------------------------------------------------------------------------------
	| 流水线级 |             操作                 |              备注             |
	-------------------------------------------------------------------------------
	|   1~3    | 计算:                            | 当操作数X >= 0时不执行计算    |
	|          |   激活参数[31:0] * 操作数X[31:0] |                               |
	-------------------------------------------------------------------------------
	|    4     | 舍入                             | 右移fixed_point_quat_accrc位, |
	|          |                                  | 直接截断                      |
	|          |                                  | 当操作数X >= 0时不执行计算    |
	-------------------------------------------------------------------------------
	|    5     | 溢出饱和化处理                   |                               |
	-------------------------------------------------------------------------------
	**/
	// [整型计算给出的乘法器端口]
	wire signed[31:0] int_mul_op_a; // 操作数A
	wire signed[31:0] int_mul_op_b; // 操作数B
	wire int_mul_ce; // 计算使能
	wire signed[63:0] int_mul_res; // 计算结果
	// [舍入]
	wire int_roundoff_i_vld;
	wire signed[63:0] int_roundoff_i_mul_res_rsh;
	reg signed[63:0] int_roundoff_amx; // 舍入后的ax(Q = 操作数X的量化精度)
	// [溢出饱和化处理]
	wire int_sat_i_vld;
	wire int_sat_i_pass;
	wire signed[31:0] int_sat_i_op_x; // 操作数X
	wire signed[63:0] int_sat_i_amx; // 舍入后的ax(Q = 操作数X的量化精度)
	wire int_sat_i_amx_ovf; // 舍入后的ax上溢标志
	wire int_sat_i_amx_udf; // 舍入后的ax下溢标志
	reg signed[31:0] int_sat_res; // 溢出饱和化处理后的结果(Q = 操作数X的量化精度)
	// [最终结果]
	wire int_fnl_o_vld;
	wire[INFO_ALONG_WIDTH-1:0] int_fnl_o_info_along;
	wire signed[31:0] int_fnl_o_res;
	
	assign int_mul_op_a = act_param_alpha;
	assign int_mul_op_b = act_cell_i_op_x;
	assign int_mul_ce = 
		aclken & 
		((act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)) & 
		act_cell_i_vld & (~act_cell_i_pass) & act_cell_i_op_x[31];
	assign int_mul_res = 
		INT32_SUPPORTED ? 
			mul_res[63:0]:
			{{14{mul_res[49]}}, mul_res[49:0]};
	
	assign int_roundoff_i_vld = 
		((act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)) & 
		act_cell_i_vld_delayed[3] & (~act_cell_i_pass_delayed[3]) & act_cell_i_op_x_delayed[3][31];
	assign int_roundoff_i_mul_res_rsh = int_mul_res >>> fixed_point_quat_accrc;
	
	assign int_sat_i_vld = 
		((act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)) & 
		act_cell_i_vld_delayed[4];
	assign int_sat_i_pass = act_cell_i_pass_delayed[4];
	assign int_sat_i_op_x = act_cell_i_op_x_delayed[4];
	assign int_sat_i_amx = int_roundoff_amx;
	assign int_sat_i_amx_ovf = 
		(~int_sat_i_amx[63]) & 
		(
			(|int_sat_i_amx[62:31]) | 
			((act_calfmt_inner == ACT_CAL_FMT_INT16) & (|int_sat_i_amx[30:15]))
		);
	assign int_sat_i_amx_udf = 
		int_sat_i_amx[63] & 
		(~(
			(&int_sat_i_amx[62:31]) & 
			((act_calfmt_inner == ACT_CAL_FMT_INT32) | (&int_sat_i_amx[30:15]))
		));
	
	assign int_fnl_o_vld = 
		((act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)) & 
		act_cell_i_vld_delayed[5];
	assign int_fnl_o_info_along = act_cell_i_info_along_delayed[5];
	assign int_fnl_o_res = int_sat_res;
	
	// 舍入后的ax(Q = 操作数X的量化精度)
	always @(posedge aclk)
	begin
		if(aclken & int_roundoff_i_vld)
			int_roundoff_amx <= # SIM_DELAY int_roundoff_i_mul_res_rsh;
	end
	
	// 溢出饱和化处理后的结果(Q = 操作数X的量化精度)
	always @(posedge aclk)
	begin
		if(aclken & int_sat_i_vld)
			int_sat_res <= # SIM_DELAY 
				(int_sat_i_pass | (~int_sat_i_op_x[31])) ? 
					int_sat_i_op_x:
					(
						(act_calfmt_inner == ACT_CAL_FMT_INT32) ? 
							{
								int_sat_i_amx[63],
								{31{~int_sat_i_amx_udf}} & ({31{int_sat_i_amx_ovf}} | int_sat_i_amx[30:0])
							}:
							{
								{17{int_sat_i_amx[63]}},
								{15{~int_sat_i_amx_udf}} & ({15{int_sat_i_amx_ovf}} | int_sat_i_amx[14:0])
							}
					);
	end
	
	/**
	激活计算(浮点格式)
	
	-------------------------------------------------------------------------------
	| 流水线级 |             操作                 |              备注             |
	-------------------------------------------------------------------------------
	|    1     | 计算: 指数相加 |计算:            | 当操作数X >= 0时不执行计算    |
	|----------|----------------|  尾数(s25)相乘  |                               |
	|   2~3    |                |                 |                               |
	----------------------------------------------|-------------------------------|
	|    4     | 四舍五入                         | 当操作数X >= 0时不执行计算    |
	|          |                                  | 向最近的偶数舍入              |
	-------------------------------------------------------------------------------
	|    5     | 标准化                           |                               |
	-------------------------------------------------------------------------------
	**/
	// [浮点计算给出的乘法器端口]
	wire signed[24:0] fp_mul_op_a; // 操作数A
	wire signed[24:0] fp_mul_op_b; // 操作数B
	wire fp_mul_ce; // 计算使能
	wire signed[49:0] fp_mul_res; // 计算结果
	// [单精度浮点数输入]
	wire signed[24:0] fp_i_alpha_mts; // 激活参数alpha的补码尾数(Q23, 在范围(-2, 2)内)
	wire signed[7:0] fp_i_alpha_exp; // 激活参数alpha的指数(在范围[-126, 127]内)
	wire signed[24:0] fp_i_op_x_mts; // 操作数X的补码尾数(Q23, 在范围(-2, 2)内)
	wire signed[7:0] fp_i_op_x_exp; // 操作数X的指数(在范围[-126, 127]内)
	// [指数相加]
	wire[3:0] fp_exp_add_i_vld;
	wire signed[7:0] fp_exp_add_i_op_a;
	wire signed[7:0] fp_exp_add_i_op_b;
	reg signed[8:0] fp_exp_add_res[0:3]; // 相加后的指数(在范围[-252, 254]内)
	// [四舍五入]
	wire fp_round_i_vld;
	wire signed[49:0] fp_round_i_mts; // 待舍入的尾数(Q46, 在范围(-4, 4)内)
	reg signed[25:0] fp_round_res; // 舍入后的尾数(Q23, 在范围(-4, 4)内)
	// [标准化]
	wire fp_nml_i_vld;
	wire fp_nml_i_pass;
	wire[31:0] fp_nml_i_op_x; // 操作数X
	wire signed[25:0] fp_nml_i_mts; // 待标准化的尾数(Q23, 在范围(-4, 4)内)
	wire signed[8:0] fp_nml_i_exp; // 待标准化的指数(在范围[-252, 254]内)
	wire signed[8:0] fp_nml_i_exp_compensated; // 标准化补偿后的指数(在范围[-252, 255]内)
	wire fp_nml_i_set_to_0; // 将结果设为0(标志)
	wire fp_nml_i_to_arsh1; // 将结果算术右移1位(标志)
	reg[31:0] fp_nml_res; // 标准化后的FP32
	// [最终结果]
	wire fp_fnl_o_vld;
	wire[INFO_ALONG_WIDTH-1:0] fp_fnl_o_info_along;
	wire signed[31:0] fp_fnl_o_res;
	
	assign fp_mul_op_a = fp_i_alpha_mts;
	assign fp_mul_op_b = fp_i_op_x_mts;
	assign fp_mul_ce = 
		aclken & 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld & (~act_cell_i_pass) & fp_i_op_x_mts[24];
	assign fp_mul_res = mul_res[49:0];
	
	/*
	当阶码为0时, 指数 = 阶码 + 8'b10000010 = 阶码 - 126
	当阶码不为0时, 指数 = 阶码 + 8'b10000001 = 阶码 - 127
	
	指数在[-126, 127]范围内
	*/
	assign fp_i_alpha_mts = 
		({25{act_param_alpha[31]}} ^ {1'b0, act_param_alpha[30:23] != 8'd0, act_param_alpha[22:0]}) + 
		(act_param_alpha[31] ? 1'b1:1'b0);
	assign fp_i_alpha_exp = act_param_alpha[30:23] + {6'b100000, act_param_alpha[30:23] == 8'd0, act_param_alpha[30:23] != 8'd0};
	assign fp_i_op_x_mts = 
		({25{act_cell_i_op_x[31]}} ^ {1'b0, act_cell_i_op_x[30:23] != 8'd0, act_cell_i_op_x[22:0]}) + 
		(act_cell_i_op_x[31] ? 1'b1:1'b0);
	assign fp_i_op_x_exp = act_cell_i_op_x[30:23] + {6'b100000, act_cell_i_op_x[30:23] == 8'd0, act_cell_i_op_x[30:23] != 8'd0};
	
	assign fp_exp_add_i_vld[0] = 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld & (~act_cell_i_pass) & act_cell_i_op_x[31];
	assign fp_exp_add_i_op_a = fp_i_alpha_exp;
	assign fp_exp_add_i_op_b = fp_i_op_x_exp;
	
	assign fp_exp_add_i_vld[1] = 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld_delayed[1] & (~act_cell_i_pass_delayed[1]) & act_cell_i_op_x_delayed[1][31];
	assign fp_exp_add_i_vld[2] = 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld_delayed[2] & (~act_cell_i_pass_delayed[2]) & act_cell_i_op_x_delayed[2][31];
	assign fp_exp_add_i_vld[3] = 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld_delayed[3] & (~act_cell_i_pass_delayed[3]) & act_cell_i_op_x_delayed[3][31];
	
	assign fp_round_i_vld = 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld_delayed[3] & (~act_cell_i_pass_delayed[3]) & act_cell_i_op_x_delayed[3][31];
	assign fp_round_i_mts = fp_mul_res;
	
	assign fp_nml_i_vld = 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld_delayed[4];
	assign fp_nml_i_pass = act_cell_i_pass_delayed[4];
	assign fp_nml_i_op_x = act_cell_i_op_x_delayed[4];
	assign fp_nml_i_mts = fp_round_res;
	assign fp_nml_i_exp = fp_exp_add_res[3];
	assign fp_nml_i_exp_compensated = 
		fp_nml_i_exp + (fp_nml_i_to_arsh1 ? 1'b1:1'b0);
	assign fp_nml_i_set_to_0 = 
		(fp_nml_i_exp_compensated < -9'sd126) | 
		// 操作数X是非规则数(包括0)时才会产生以下结果
		(fp_nml_i_mts[25:23] == 3'b000) | // [0, 1)
		((fp_nml_i_mts[25:23] == 3'b111) & (|fp_nml_i_mts[22:0])); // (-1, 0)
	assign fp_nml_i_to_arsh1 = 
		(fp_nml_i_mts[25:23] == 3'b010) | // [2, 3)
		(fp_nml_i_mts[25:23] == 3'b011) | // [3, 4)
		((fp_nml_i_mts[25:23] == 3'b110) & (~(|fp_nml_i_mts[22:0]))) | // -2
		(fp_nml_i_mts[25:23] == 3'b101) | // [-3, -2)
		(fp_nml_i_mts[25:23] == 3'b100); // (-4, -3)
	
	assign fp_fnl_o_vld = 
		(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
		act_cell_i_vld_delayed[5];
	assign fp_fnl_o_info_along = act_cell_i_info_along_delayed[5];
	assign fp_fnl_o_res = fp_nml_res;
	
	// 相加后的指数(在范围[-252, 254]内)
	always @(posedge aclk)
	begin
		if(aclken & fp_exp_add_i_vld[0])
			fp_exp_add_res[0] <= # SIM_DELAY 
				{fp_exp_add_i_op_a[7], fp_exp_add_i_op_a[7:0]} + 
				{fp_exp_add_i_op_b[7], fp_exp_add_i_op_b[7:0]};
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_exp_add_i_vld[1])
			fp_exp_add_res[1] <= # SIM_DELAY fp_exp_add_res[0];
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_exp_add_i_vld[2])
			fp_exp_add_res[2] <= # SIM_DELAY fp_exp_add_res[1];
	end
	always @(posedge aclk)
	begin
		if(aclken & fp_exp_add_i_vld[3])
			fp_exp_add_res[3] <= # SIM_DELAY fp_exp_add_res[2];
	end
	
	// 舍入后的尾数(Q23, 在范围(-4, 4)内)
	always @(posedge aclk)
	begin
		if(aclken & fp_round_i_vld)
			fp_round_res <= # SIM_DELAY 
				fp_round_i_mts[48:23] + 
				(
					(fp_round_i_mts[22] & ((|fp_round_i_mts[21:0]) | fp_round_i_mts[23])) ? 
						1'b1:
						1'b0
				);
	end
	
	// 标准化后的FP32
	always @(posedge aclk)
	begin
		if(aclken & fp_nml_i_vld)
		begin
			// 符号位
			fp_nml_res[31] <= # SIM_DELAY 
				(fp_nml_i_pass | (~fp_nml_i_op_x[31])) ? 
					fp_nml_i_op_x[31]:
					fp_nml_i_mts[25];
			// 阶码
			fp_nml_res[30:23] <= # SIM_DELAY 
				(fp_nml_i_pass | (~fp_nml_i_op_x[31])) ? 
					fp_nml_i_op_x[30:23]:
					(
						fp_nml_i_set_to_0 ? 
							8'd0:
							(fp_nml_i_exp_compensated[7:0] + 8'b01111111)
					);
			// 尾数
			fp_nml_res[22:0] <= # SIM_DELAY 
				(fp_nml_i_pass | (~fp_nml_i_op_x[31])) ? 
					fp_nml_i_op_x[22:0]:
					(
						fp_nml_i_set_to_0 ? 
							23'd0:
							(
								(
									{23{fp_nml_i_mts[25]}} ^ 
									(
										fp_nml_i_to_arsh1 ? 
											fp_nml_i_mts[23:1]:
											fp_nml_i_mts[22:0]
									)
								) + (fp_nml_i_mts[25] ? 1'b1:1'b0)
							)
					);
		end
	end
	
	/** 共享有符号乘法器#0 **/
	reg signed[31:0] shared_mul0_op_a;
	reg signed[31:0] shared_mul0_op_b;
	wire shared_mul0_i_vld;
	reg[1:0] shared_mul0_vld;
	
	assign mul_op_a = 
		INT32_SUPPORTED ? 
			shared_mul0_op_a:
			shared_mul0_op_a[24:0];
	assign mul_op_b = 
		INT32_SUPPORTED ? 
			shared_mul0_op_b:
			shared_mul0_op_b[24:0];
	assign mul_ce = 
		{2{aclken}} & shared_mul0_vld;
	
	assign shared_mul0_i_vld = 
		(((act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)) & int_mul_ce) | 
		((act_calfmt_inner == ACT_CAL_FMT_FP32) & fp_mul_ce);
	
	always @(posedge aclk)
	begin
		if(shared_mul0_i_vld)
		begin
			shared_mul0_op_a <= # SIM_DELAY 
				({32{(act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)}} & int_mul_op_a) | 
				({32{act_calfmt_inner == ACT_CAL_FMT_FP32}} & {{7{fp_mul_op_a[24]}}, fp_mul_op_a[24:0]});
			shared_mul0_op_b <= # SIM_DELAY 
				({32{(act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)}} & int_mul_op_b) | 
				({32{act_calfmt_inner == ACT_CAL_FMT_FP32}} & {{7{fp_mul_op_b[24]}}, fp_mul_op_b[24:0]});
		end
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			shared_mul0_vld <= 2'b00;
		else if(aclken)
			shared_mul0_vld <= # SIM_DELAY {shared_mul0_vld[0], shared_mul0_i_vld};
	end
	
	/** 激活单元结果输出 **/
	assign act_cell_o_res = 
		({32{(act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)}} & int_fnl_o_res) | 
		({32{act_calfmt_inner == ACT_CAL_FMT_FP32}} & fp_fnl_o_res);
	assign act_cell_o_info_along = 
		({INFO_ALONG_WIDTH{(act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)}} & int_fnl_o_info_along) | 
		({INFO_ALONG_WIDTH{act_calfmt_inner == ACT_CAL_FMT_FP32}} & fp_fnl_o_info_along);
	assign act_cell_o_vld = 
		(((act_calfmt_inner == ACT_CAL_FMT_INT16) | (act_calfmt_inner == ACT_CAL_FMT_INT32)) & int_fnl_o_vld) | 
		((act_calfmt_inner == ACT_CAL_FMT_FP32) & fp_fnl_o_vld);
	
endmodule
