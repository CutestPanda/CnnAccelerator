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
本模块: Sigmoid或tanh激活单元

描述:
Sigmoid(x) = 1 / (1 + e^(-x))
Tanh(x) = 2 * Sigmoid(2x) - 1 = (e^x - e^(-x)) / (e^x + e^(-x))

------------------------------------------------------
| 输入数据范围 | 量化点数 |  Sigmoid函数值查找表输出 |
------------------------------------------------------
|   [0, 2)     |   2048   | 定点数(Q16)              |
|              |          | 隐含的整数位(正数1)      |
|              |          | 隐含的指数偏移(2^-1)     |
|-------------------------|                          |
|   [2, 4)     |   1024   | 输出数据范围在[0.5, 1)内 |
|-------------------------|                          |
|   [4, 12)    |   1024   |                          |
------------------------------------------------------

无论是哪种运算数据格式, 都有时延 = 6clk

支持INT16、INT32、FP32三种运算数据格式

使用1个深度 = 4096、位宽 = 16的单口RAM作为查找表, 读时延 = 1clk

带有全局时钟使能

---------------------------------------------------------------
| 运算数据格式 |      操作数X量化精度      | 计算结果量化精度 |
---------------------------------------------------------------
|     INT16    | in_fixed_point_quat_accrc |       14         |
|--------------|                           |------------------|
|     INT32    |                           |       30         |
|--------------|---------------------------|------------------|
|     FP32     |          ---              |       ---        |
---------------------------------------------------------------

注意:
无

协议:
MEM MASTER

作者: 陈家耀
日期: 2026/01/11
********************************************************************/


module sigmoid_tanh_cell #(
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
	
	// 控制信号
	input wire bypass, // 旁路本单元
	
	// 运行时参数
	input wire[2:0] act_func_type, // 激活函数类型
	input wire[1:0] act_calfmt, // 运算数据格式
	input wire[4:0] in_fixed_point_quat_accrc, // 输入定点数量化精度
	
	// 激活单元计算输入
	input wire[31:0] act_cell_i_op_x, // 操作数X
	input wire act_cell_i_pass, // 不作激活处理(标志)
	input wire[INFO_ALONG_WIDTH-1:0] act_cell_i_info_along, // 随路数据
	input wire act_cell_i_vld,
	
	// 激活单元结果输出
	output wire[31:0] act_cell_o_res, // 计算结果
	output wire[INFO_ALONG_WIDTH-1:0] act_cell_o_info_along, // 随路数据
	output wire act_cell_o_vld,
	
	// 查找表
	output wire lut_mem_clk_a,
	output wire lut_mem_ren_a,
	output wire[11:0] lut_mem_addr_a,
	input wire[15:0] lut_mem_dout_a
);
	
	/** 常量 **/
	// 激活函数类型的编码
	localparam ACT_FUNC_TYPE_LEAKY_RELU = 3'b000; // 泄露Relu
	localparam ACT_FUNC_TYPE_SIGMOID = 3'b001; // sigmoid
	localparam ACT_FUNC_TYPE_TANH = 3'b010; // tanh
	localparam ACT_FUNC_TYPE_NONE = 3'b111;
	// 激活模式的编码
	localparam ACT_MODE_SIGMOID = 2'b00;
	localparam ACT_MODE_TANH = 2'b01;
	localparam ACT_MODE_NONE = 2'b10;
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
	
	/** 激活模式 **/
	wire[1:0] act_mode; // 激活模式
	
	assign act_mode = 
		(act_func_type == ACT_FUNC_TYPE_SIGMOID) ? ACT_MODE_SIGMOID:
		(act_func_type == ACT_FUNC_TYPE_TANH)    ? ACT_MODE_TANH:
		                                           ACT_MODE_NONE;
	
	/** 输入信号延迟链 **/
	reg[5:1] act_cell_i_vld_delayed; // 延迟的输入有效指示
	reg[5:1] act_cell_i_pass_delayed; // 延迟的不作激活处理标志
	reg[31:0] act_cell_i_op_x_delayed[1:5]; // 延迟的操作数X
	reg[INFO_ALONG_WIDTH-1:0] act_cell_i_info_along_delayed[1:5]; // 延迟的随路数据
	
	// 延迟的输入有效指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			act_cell_i_vld_delayed <= 5'b00000;
		else if(aclken)
			act_cell_i_vld_delayed <= # SIM_DELAY {
				act_cell_i_vld_delayed[4],
				act_cell_i_vld_delayed[3],
				act_cell_i_vld_delayed[2],
				act_cell_i_vld_delayed[1],
				act_cell_i_vld
			};
	end
	
	// 延迟的不作激活处理标志, 延迟的操作数X, 延迟的随路数据
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld)
		begin
			act_cell_i_pass_delayed[1] <= # SIM_DELAY act_cell_i_pass;
			act_cell_i_op_x_delayed[1] <= # SIM_DELAY act_cell_i_op_x;
			act_cell_i_info_along_delayed[1] <= # SIM_DELAY act_cell_i_info_along;
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[1])
		begin
			act_cell_i_pass_delayed[2] <= # SIM_DELAY act_cell_i_pass_delayed[1];
			act_cell_i_op_x_delayed[2] <= # SIM_DELAY act_cell_i_op_x_delayed[1];
			act_cell_i_info_along_delayed[2] <= # SIM_DELAY act_cell_i_info_along_delayed[1];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[2])
		begin
			act_cell_i_pass_delayed[3] <= # SIM_DELAY act_cell_i_pass_delayed[2];
			act_cell_i_op_x_delayed[3] <= # SIM_DELAY act_cell_i_op_x_delayed[2];
			act_cell_i_info_along_delayed[3] <= # SIM_DELAY act_cell_i_info_along_delayed[2];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[3])
		begin
			act_cell_i_pass_delayed[4] <= # SIM_DELAY act_cell_i_pass_delayed[3];
			act_cell_i_op_x_delayed[4] <= # SIM_DELAY act_cell_i_op_x_delayed[3];
			act_cell_i_info_along_delayed[4] <= # SIM_DELAY act_cell_i_info_along_delayed[3];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & act_cell_i_vld_delayed[4])
		begin
			act_cell_i_pass_delayed[5] <= # SIM_DELAY act_cell_i_pass_delayed[4];
			act_cell_i_op_x_delayed[5] <= # SIM_DELAY act_cell_i_op_x_delayed[4];
			act_cell_i_info_along_delayed[5] <= # SIM_DELAY act_cell_i_info_along_delayed[4];
		end
	end
	
	/**
	第1级流水线: 生成待查定点数
	
	待查定点数的量化精度 = 10
	待查定点数是abs(输入浮点或定点数)
	**/
	wire query_fixed_gen_i_vld;
	wire query_fixed_gen_i_pass;
	wire[31:0] query_fixed_gen_i_op_x;
	wire[31:0] query_fixed_gen_i_org_fixed; // 原始定点数
	wire[63:0] query_fixed_gen_i_fixed_to_be_shifted; // 待移位的定点数
	wire[4:0] query_fixed_gen_i_shift_mode; // 移位模式
	reg[63:0] query_fixed_gen_res_shifted; // 移位后的待查定点数(Q32)
	
	assign query_fixed_gen_i_vld = act_cell_i_vld;
	assign query_fixed_gen_i_pass = act_cell_i_pass;
	assign query_fixed_gen_i_op_x = act_cell_i_op_x;
	
	assign query_fixed_gen_i_org_fixed = 
		({32{act_calfmt_inner == ACT_CAL_FMT_FP32}} & {9'd1, query_fixed_gen_i_op_x[22:0]}) | // Q = 23
		(
			{32{(act_calfmt_inner == ACT_CAL_FMT_INT16) & (act_calfmt_inner == ACT_CAL_FMT_INT32)}} & 
			(({32{query_fixed_gen_i_op_x[31]}} ^ query_fixed_gen_i_op_x) + query_fixed_gen_i_op_x[31])
		); // Q = in_fixed_point_quat_accrc
	assign query_fixed_gen_i_fixed_to_be_shifted = 
		(
			{64{act_calfmt_inner == ACT_CAL_FMT_FP32}} & 
			{23'd0, query_fixed_gen_i_org_fixed, 9'd0}
		) | // Q = 32
		(
			{64{(act_calfmt_inner == ACT_CAL_FMT_INT16) & (act_calfmt_inner == ACT_CAL_FMT_INT32)}} & 
			{10'd0, query_fixed_gen_i_org_fixed, 22'd0}
		); // Q = in_fixed_point_quat_accrc + 22
	assign query_fixed_gen_i_shift_mode = 
		({5{(act_calfmt_inner == ACT_CAL_FMT_FP32) & (query_fixed_gen_i_op_x[30:23] >= 8'd131)}} & 5'd6) | // 左移4位
		(
			{5{
				(act_calfmt_inner == ACT_CAL_FMT_FP32) & 
				(query_fixed_gen_i_op_x[30:23] > 8'd115) & (query_fixed_gen_i_op_x[30:23] < 8'd131)
			}} & 
			((8'd127 + 8'd10 - query_fixed_gen_i_op_x[30:23]) & 8'b00011111)
		) | // 左移1~3位/不变/右移1~11位
		({5{(act_calfmt_inner == ACT_CAL_FMT_FP32) & (query_fixed_gen_i_op_x[30:23] <= 8'd115)}} & 5'd22) | // 右移12位
		(
			{5{(act_calfmt_inner == ACT_CAL_FMT_INT16) & (act_calfmt_inner == ACT_CAL_FMT_INT32)}} & 
			in_fixed_point_quat_accrc
		); // 左移1~10位/不变/右移1~21
	
	// 移位后的待查定点数(Q32)
	always @(posedge aclk)
	begin
		if(aclken & query_fixed_gen_i_vld & (~query_fixed_gen_i_pass))
			query_fixed_gen_res_shifted <= # SIM_DELAY 
				(query_fixed_gen_i_shift_mode >= 5'd10) ? 
					(query_fixed_gen_i_fixed_to_be_shifted >> (query_fixed_gen_i_shift_mode - 5'd10)):
					(query_fixed_gen_i_fixed_to_be_shifted << (5'd10 - query_fixed_gen_i_shift_mode));
	end
	
	/**
	第2级流水线: 四舍五入(向最近偶数舍入)
	**/
	wire round_i_vld;
	wire round_i_pass;
	wire[64:0] round_i_fixed_to_query; // 待查定点数(Q32)
	wire[17:0] round_i_fixed_op; // 待舍入的定点数(整数位 = 4, 小数位 = 10, 保护位 = 4)
	wire round_i_ovf_flag; // 定点数(在查表范围内)上溢标志
	wire round_i_to_fwd_carry; // 向前进位标志
	reg[13:0] round_res_fixed; // 舍入后的待查定点数(Q10)
	reg round_res_ovf_flag; // 待查定点数上溢标志
	
	assign round_i_vld = act_cell_i_vld_delayed[1];
	assign round_i_pass = act_cell_i_pass_delayed[1];
	assign round_i_fixed_to_query = 
		(act_mode == ACT_MODE_SIGMOID) ? 
			{1'b0, query_fixed_gen_res_shifted[63:0]}: // Sigmoid模式: 查询Sigmoid(x)
			{query_fixed_gen_res_shifted[63:0], 1'b0}; // Tanh模式: 查询Sigmoid(2x)
	assign round_i_fixed_op = {round_i_fixed_to_query[35:32], round_i_fixed_to_query[31:18]};
	
	assign round_i_ovf_flag = 
		(round_i_fixed_to_query[64:32] >= 33'd12) | 
		(
			({round_i_fixed_to_query[35:32], round_i_fixed_to_query[31:22]} == {4'd11, 10'b1111111111}) & 
			round_i_to_fwd_carry
		);
	assign round_i_to_fwd_carry = round_i_fixed_op[3] & ((round_i_fixed_op[2:0] != 3'b000) | round_i_fixed_op[4]);
	
	// 舍入后的待查定点数(Q10)
	always @(posedge aclk)
	begin
		if(aclken & round_i_vld & (~round_i_pass) & (~round_i_ovf_flag))
			round_res_fixed <= # SIM_DELAY round_i_fixed_op[17:4] + round_i_to_fwd_carry;
	end
	
	// 待查定点数上溢标志
	always @(posedge aclk)
	begin
		if(aclken & round_i_vld & (~round_i_pass))
			round_res_ovf_flag <= # SIM_DELAY round_i_ovf_flag;
	end
	
	/**
	第3级流水线: 查Sigmoid函数值表
	
	------------------------------------------------------
	| 输入数据范围 | 量化点数 |        查找表输出        |
	------------------------------------------------------
	|   [0, 2)     |   2048   | 定点数(Q16)              |
	|              |          | 隐含的整数位(正数1)      |
	|              |          | 隐含的指数偏移(2^-1)     |
	|-------------------------|                          |
	|   [2, 4)     |   1024   | 输出数据范围在[0.5, 1)内 |
	|-------------------------|                          |
	|   [4, 12)    |   1024   |                          |
	------------------------------------------------------
	**/
	wire lookup_i_vld;
	wire lookup_i_pass;
	wire[13:0] lookup_i_fixed_op; // 待查定点数(Q10)
	wire lookup_i_ovf_flag; // 待查定点数上溢标志
	reg lookup_res_set_to_1_flag; // 将查表结果设为1(标志)
	
	assign lut_mem_clk_a = aclk;
	assign lut_mem_ren_a = aclken & lookup_i_vld & (~lookup_i_pass) & (~lookup_i_ovf_flag);
	assign lut_mem_addr_a = 
		(|lookup_i_fixed_op[13:12]) ? 
			(12'd3072 + {lookup_i_fixed_op[13], lookup_i_fixed_op[11:3]}): // 输入数据范围 -> [4, 12)
			(
				lookup_i_fixed_op[11] ? 
					(12'd2048 + lookup_i_fixed_op[10:1]): // 输入数据范围 -> [2, 4)
					(12'd0 + {1'b0, lookup_i_fixed_op[10:0]}) // 输入数据范围 -> [0, 2)
			);
	
	assign lookup_i_vld = act_cell_i_vld_delayed[2];
	assign lookup_i_pass = act_cell_i_pass_delayed[2];
	assign lookup_i_fixed_op = round_res_fixed;
	assign lookup_i_ovf_flag = round_res_ovf_flag;
	
	// 将查表结果设为1(标志)
	always @(posedge aclk)
	begin
		if(aclken & lookup_i_vld & (~lookup_i_pass))
			lookup_res_set_to_1_flag <= # SIM_DELAY lookup_i_ovf_flag;
	end
	
	/**
	第4级流水线: 得到定点数表示的Sigmoid函数值
	**/
	wire func_value_i_vld;
	wire func_value_i_pass;
	wire func_value_i_set_to_1_flag;
	wire func_value_i_is_op_x_neg; // 操作数X是负数(标志)
	wire[17:0] func_value_i_lut; // 查表结果(Q17)
	reg[18:0] func_value_fixed; // 定点数表示的Sigmoid函数值(Q17)
	
	assign func_value_i_vld = act_cell_i_vld_delayed[3];
	assign func_value_i_pass = act_cell_i_pass_delayed[3];
	assign func_value_i_set_to_1_flag = lookup_res_set_to_1_flag;
	assign func_value_i_is_op_x_neg = act_cell_i_op_x_delayed[3][31];
	
	assign func_value_i_lut = 
		func_value_i_set_to_1_flag ? 
			{1'b1, 17'd0}:
			{1'b0, 1'b1, lut_mem_dout_a[15:0]};
	
	// 定点数表示的Sigmoid函数值(Q17)
	always @(posedge aclk)
	begin
		if(aclken & func_value_i_vld & (~func_value_i_pass))
			func_value_fixed <= # SIM_DELAY 
				(act_mode == ACT_MODE_SIGMOID) ? 
					// Sigmoid模式: 因为Sigmoid函数关于点(x = 0, y = 0.5)对称, 当操作数X是负数时, Sigmoid函数值 = 1 - 查表结果
					(
						func_value_i_is_op_x_neg ? 
							({2'b01, 17'd0} - {1'b0, func_value_i_lut}):
							{1'b0, func_value_i_lut}
					):
					// Tanh模式: Tanh函数值的绝对值 = 2 * 查表结果 - 1
					({func_value_i_lut, 1'b0} - {2'b01, 17'd0});
	end
	
	/**
	第5级流水线: 格式化输出
	
	-----------------------------------
	| 运算数据格式 | 计算结果量化精度 |
	-----------------------------------
	|     INT16    |       14         |
	|--------------|------------------|
	|     INT32    |       30         |
	|--------------|------------------|
	|     FP32     |   单精度浮点数   |
	-----------------------------------
	**/
	wire format_i_vld;
	wire format_i_pass;
	wire[31:0] format_i_op_x;
	wire format_i_is_op_x_neg; // 操作数X是负数(标志)
	wire[17:0] format_i_fixed; // 待格式化的定点数(Q17)
	wire[17:0] format_i_fixed_rvs; // 位颠倒的待格式化的定点数(Q17)
	wire[17:0] format_i_fixed_first_1_onehot; // 待格式化的定点数从MSB开始第1个"1"的位置独热码
	wire[24:0] format_i_ext_fixed_for_fp32_nml; // 为FP32标准化而扩展的定点数(Q23)
	wire[24:0] format_i_fp32_mts_nml; // 标准化后的FP32尾数(Q23)
	wire[7:0] format_i_fp32_ec_nml; // 标准化后的FP32阶码
	reg[31:0] format_res; // 格式化后的数据
	
	assign format_i_vld = act_cell_i_vld_delayed[4];
	assign format_i_pass = act_cell_i_pass_delayed[4];
	assign format_i_op_x = act_cell_i_op_x_delayed[4];
	assign format_i_is_op_x_neg = act_cell_i_op_x_delayed[4][31];
	assign format_i_fixed = func_value_fixed[17:0];
	
	assign format_i_fixed_rvs = {
		format_i_fixed[0], format_i_fixed[1], format_i_fixed[2],
		format_i_fixed[3], format_i_fixed[4], format_i_fixed[5],
		format_i_fixed[6], format_i_fixed[7], format_i_fixed[8],
		format_i_fixed[9], format_i_fixed[10], format_i_fixed[11],
		format_i_fixed[12], format_i_fixed[13], format_i_fixed[14],
		format_i_fixed[15], format_i_fixed[16], format_i_fixed[17]
	};
	/*
	从MSB开始找第1个"1"的位置
	
	((~A) + 1) & A就是从LSB开始第1个"1"的位置独热码, 比如:
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
	assign format_i_fixed_first_1_onehot = ((~format_i_fixed_rvs) + 1'b1) & format_i_fixed_rvs;
	assign format_i_ext_fixed_for_fp32_nml = {1'b0, format_i_fixed, 6'd0};
	assign format_i_fp32_mts_nml = 
		({25{format_i_fixed_first_1_onehot[0]}}  & (format_i_ext_fixed_for_fp32_nml << 0)) | 
		({25{format_i_fixed_first_1_onehot[1]}}  & (format_i_ext_fixed_for_fp32_nml << 1)) | 
		({25{format_i_fixed_first_1_onehot[2]}}  & (format_i_ext_fixed_for_fp32_nml << 2)) | 
		({25{format_i_fixed_first_1_onehot[3]}}  & (format_i_ext_fixed_for_fp32_nml << 3)) | 
		({25{format_i_fixed_first_1_onehot[4]}}  & (format_i_ext_fixed_for_fp32_nml << 4)) | 
		({25{format_i_fixed_first_1_onehot[5]}}  & (format_i_ext_fixed_for_fp32_nml << 5)) | 
		({25{format_i_fixed_first_1_onehot[6]}}  & (format_i_ext_fixed_for_fp32_nml << 6)) | 
		({25{format_i_fixed_first_1_onehot[7]}}  & (format_i_ext_fixed_for_fp32_nml << 7)) | 
		({25{format_i_fixed_first_1_onehot[8]}}  & (format_i_ext_fixed_for_fp32_nml << 8)) | 
		({25{format_i_fixed_first_1_onehot[9]}}  & (format_i_ext_fixed_for_fp32_nml << 9)) | 
		({25{format_i_fixed_first_1_onehot[10]}} & (format_i_ext_fixed_for_fp32_nml << 10)) | 
		({25{format_i_fixed_first_1_onehot[11]}} & (format_i_ext_fixed_for_fp32_nml << 11)) | 
		({25{format_i_fixed_first_1_onehot[12]}} & (format_i_ext_fixed_for_fp32_nml << 12)) | 
		({25{format_i_fixed_first_1_onehot[13]}} & (format_i_ext_fixed_for_fp32_nml << 13)) | 
		({25{format_i_fixed_first_1_onehot[14]}} & (format_i_ext_fixed_for_fp32_nml << 14)) | 
		({25{format_i_fixed_first_1_onehot[15]}} & (format_i_ext_fixed_for_fp32_nml << 15)) | 
		({25{format_i_fixed_first_1_onehot[16]}} & (format_i_ext_fixed_for_fp32_nml << 16)) | 
		({25{format_i_fixed_first_1_onehot[17]}} & (format_i_ext_fixed_for_fp32_nml << 17));
	assign format_i_fp32_ec_nml = 
		({8{format_i_fixed_first_1_onehot[0]}}  & 8'd127) | 
		({8{format_i_fixed_first_1_onehot[1]}}  & 8'd126) | 
		({8{format_i_fixed_first_1_onehot[2]}}  & 8'd125) | 
		({8{format_i_fixed_first_1_onehot[3]}}  & 8'd124) | 
		({8{format_i_fixed_first_1_onehot[4]}}  & 8'd123) | 
		({8{format_i_fixed_first_1_onehot[5]}}  & 8'd122) | 
		({8{format_i_fixed_first_1_onehot[6]}}  & 8'd121) | 
		({8{format_i_fixed_first_1_onehot[7]}}  & 8'd120) | 
		({8{format_i_fixed_first_1_onehot[8]}}  & 8'd119) | 
		({8{format_i_fixed_first_1_onehot[9]}}  & 8'd118) | 
		({8{format_i_fixed_first_1_onehot[10]}} & 8'd117) | 
		({8{format_i_fixed_first_1_onehot[11]}} & 8'd116) | 
		({8{format_i_fixed_first_1_onehot[12]}} & 8'd115) | 
		({8{format_i_fixed_first_1_onehot[13]}} & 8'd114) | 
		({8{format_i_fixed_first_1_onehot[14]}} & 8'd113) | 
		({8{format_i_fixed_first_1_onehot[15]}} & 8'd112) | 
		({8{format_i_fixed_first_1_onehot[16]}} & 8'd111) | 
		({8{format_i_fixed_first_1_onehot[17]}} & 8'd110);
	
	// 格式化后的数据
	always @(posedge aclk)
	begin
		if(aclken & format_i_vld)
			format_res <= # SIM_DELAY 
				format_i_pass ? 
					format_i_op_x:
					(
						(
							{32{act_calfmt_inner == ACT_CAL_FMT_FP32}} & 
							{
								(act_mode == ACT_MODE_TANH) & format_i_is_op_x_neg, // Tanh是奇函数, 满足Tanh(x) = -Tanh(-x)
								format_i_fp32_ec_nml[7:0],
								format_i_fp32_mts_nml[22:0]
							}
						) | 
						(
							{32{act_calfmt_inner == ACT_CAL_FMT_INT16}} & 
							(
								(
									{32{(act_mode == ACT_MODE_TANH) & format_i_is_op_x_neg}} ^ // Tanh是奇函数, 满足Tanh(x) = -Tanh(-x)
									{16'd0, 1'b0, format_i_fixed[17:3]} // Q14
								) + ((act_mode == ACT_MODE_TANH) & format_i_is_op_x_neg)
							)
						) | 
						(
							{32{act_calfmt_inner == ACT_CAL_FMT_INT32}} & 
							(
								(
									{32{(act_mode == ACT_MODE_TANH) & format_i_is_op_x_neg}} ^ // Tanh是奇函数, 满足Tanh(x) = -Tanh(-x)
									{1'b0, format_i_fixed[17:0], 13'd0} // Q30
								) + ((act_mode == ACT_MODE_TANH) & format_i_is_op_x_neg)
							)
						)
					);
	end
	
	/** 激活单元结果输出 **/
	reg[31:0] act_cell_o_res_r; // 计算结果
	reg[INFO_ALONG_WIDTH-1:0] act_cell_o_info_along_r; // 随路数据
	reg act_cell_o_vld_r;
	
	assign act_cell_o_res = act_cell_o_res_r;
	assign act_cell_o_info_along = act_cell_o_info_along_r;
	assign act_cell_o_vld = act_cell_o_vld_r;
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			act_cell_o_vld_r <= 1'b0;
		else if(aclken)
			act_cell_o_vld_r <= # SIM_DELAY 
				bypass ? 
					act_cell_i_vld:
					act_cell_i_vld_delayed[5];
	end
	
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				bypass ? 
					act_cell_i_vld:
					act_cell_i_vld_delayed[5]
			)
		)
		begin
			act_cell_o_res_r <= # SIM_DELAY 
				bypass ? 
					act_cell_i_op_x:
					format_res;
			
			act_cell_o_info_along_r <= # SIM_DELAY 
				bypass ? 
					act_cell_i_info_along:
					act_cell_i_info_along_delayed[5];
		end
	end
	
endmodule
