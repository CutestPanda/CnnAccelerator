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
本模块: (逐元素操作)输入数据转换单元

描述:
将FP16或S33转换为FP32

带有全局时钟使能

---------------------------
| 输入数据格式 |   时延   |
---------------------------
|     FP16     |    2     |
---------------------------
|      S33     |    5     |
---------------------------

注意:
浮点运算未考虑INF和NAN
输入的非规则FP16被视为0

若旁路本单元, 则实际的输入数据格式只能是s16或s32或FP32

当输入数据格式为s33时, 操作数X的量化精度为fixed_point_quat_accrc, 实际类型(u8/s8/u16/s16/u32/s32)由integer_type确定

仅s33转fp32时需要作四舍五入

协议:
无

作者: 陈家耀
日期: 2026/01/08
********************************************************************/


module element_wise_in_data_cvt_cell #(
	parameter EN_ROUND = 1'b1, // 是否需要进行四舍五入
	parameter FP16_IN_DATA_SUPPORTED = 1'b1, // 是否支持FP16输入数据格式
	parameter S33_IN_DATA_SUPPORTED = 1'b1, // 是否支持S33输入数据格式
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
	input wire[1:0] in_data_fmt, // 输入数据格式
	input wire[5:0] fixed_point_quat_accrc, // 定点数量化精度
	input wire[2:0] integer_type, // 整数类型
	
	// 转换单元输入
	input wire[31:0] cvt_cell_i_op_x, // 操作数X
	input wire cvt_cell_i_pass, // 直接传递操作数X(标志)
	input wire[INFO_ALONG_WIDTH-1:0] cvt_cell_i_info_along, // 随路数据
	input wire cvt_cell_i_vld,
	
	// 转换单元输出
	output wire[31:0] cvt_cell_o_res, // 计算结果
	output wire[INFO_ALONG_WIDTH-1:0] cvt_cell_o_info_along, // 随路数据
	output wire cvt_cell_o_vld
);
	
	/** 常量 **/
	// 输入数据格式的编码
	localparam IN_DATA_FMT_FP16 = 2'b00;
	localparam IN_DATA_FMT_S33 = 2'b01;
	localparam IN_DATA_FMT_NONE = 2'b10;
	// 整数类型的编码
	localparam INTEGER_TYPE_U8 = 3'b000;
	localparam INTEGER_TYPE_S8 = 3'b001;
	localparam INTEGER_TYPE_U16 = 3'b010;
	localparam INTEGER_TYPE_S16 = 3'b011;
	localparam INTEGER_TYPE_U32 = 3'b100;
	localparam INTEGER_TYPE_S32 = 3'b101;
	
	/** 输入数据格式 **/
	wire[1:0] in_data_fmt_inner;
	
	assign in_data_fmt_inner = 
		(FP16_IN_DATA_SUPPORTED & (in_data_fmt == IN_DATA_FMT_FP16)) ? IN_DATA_FMT_FP16:
		(S33_IN_DATA_SUPPORTED  & (in_data_fmt == IN_DATA_FMT_S33))  ? IN_DATA_FMT_S33:
		                                                               IN_DATA_FMT_NONE;
	
	/** 输入信号延迟链 **/
	reg[4:1] cvt_cell_i_vld_delayed;
	reg[4:1] cvt_cell_i_pass_delayed;
	reg[INFO_ALONG_WIDTH-1:0] cvt_cell_i_info_along_delayed[1:4];
	reg[31:0] cvt_cell_i_op_x_delayed[1:4];
	
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
	FP16转换为FP32
	
	---------------------------------------------------------------------
	| 流水线级 |        完成的内容         |            备注            |
	---------------------------------------------------------------------
	|    1     | 转换为FP32                | 非规则FP16被视为0          |
	---------------------------------------------------------------------
	**/
	// [转换为FP32]
	wire fp16_cvt_in_vld;
	wire fp16_cvt_in_pass;
	wire[31:0] fp16_cvt_in_op_x;
	wire fp16_cvt_in_fp32_sign; // 转换为FP32的符号位
	wire[7:0] fp16_cvt_in_fp32_ec; // 转换为FP32的阶码
	wire[22:0] fp16_cvt_in_fp32_mts; // 转换为FP32的尾数(不含隐藏整数位)
	reg[31:0] fp16_cvt_res; // 转换结果
	// [最终结果]
	wire fp16_out_vld;
	wire[31:0] fp16_out_res;
	wire[INFO_ALONG_WIDTH-1:0] fp16_out_info_along;
	
	assign fp16_cvt_in_vld = (in_data_fmt_inner == IN_DATA_FMT_FP16) & cvt_cell_i_vld;
	assign fp16_cvt_in_pass = cvt_cell_i_pass;
	assign fp16_cvt_in_op_x = cvt_cell_i_op_x[31:0];
	assign fp16_cvt_in_fp32_sign = 
		cvt_cell_i_op_x[15];
	assign fp16_cvt_in_fp32_ec = 
		(cvt_cell_i_op_x[14:10] == 5'd0) ? 
			8'd0:
			((cvt_cell_i_op_x[14:10] | 8'd0) + (8'd127 - 8'd15));
	assign fp16_cvt_in_fp32_mts = 
		(cvt_cell_i_op_x[14:10] == 5'd0) ? 
			23'd0:
			{cvt_cell_i_op_x[9:0], 13'd0};
	
	assign fp16_out_vld = (in_data_fmt_inner == IN_DATA_FMT_FP16) & cvt_cell_i_vld_delayed[1];
	assign fp16_out_res = fp16_cvt_res;
	assign fp16_out_info_along = cvt_cell_i_info_along_delayed[1];
	
	// 转换结果
	always @(posedge aclk)
	begin
		if(aclken & fp16_cvt_in_vld)
			fp16_cvt_res <= # SIM_DELAY 
				fp16_cvt_in_pass ? 
					fp16_cvt_in_op_x:
					{fp16_cvt_in_fp32_sign, fp16_cvt_in_fp32_ec, fp16_cvt_in_fp32_mts};
	end
	
	/**
	S33转换为FP32
	
	----------------------------------------------------------------------
	| 流水线级 |        完成的内容         |            备注             |
	----------------------------------------------------------------------
	|    1     | 生成标准化模式独热码      |                             |
	----------------------------------------------------------------------
	|    2     | 定点数标准化              | 对定点数作左移, 得到xx.xxxx |
	|          |                           | (整数位有2位, 小数位有31位) |
	|          |                           | 形式的定点数                |
	----------------------------------------------------------------------
	|    3     | 阶码与绝对尾数构建        |                             |
	----------------------------------------------------------------------
	|    4     | 对绝对尾数作              |                             |
	|          | 四舍五入(向最近偶数舍入)  |                             |
	----------------------------------------------------------------------
	**/
	// [生成标准化模式独热码]
	wire s33_pattern_gen_in_vld;
	wire s33_pattern_gen_in_pass;
	wire signed[32:0] s33_pattern_gen_in_op_x;
	wire[32:0] s33_pattern_gen_in_op_x_rvs; // 位颠倒的操作数X
	reg[31:0] s33_pattern_gen_onehot; // 生成的标准化模式独热码
	// [定点数标准化]
	wire s33_nml_in_vld;
	wire s33_nml_in_pass;
	wire signed[32:0] s33_nml_in_op_x;
	wire[4:0] s33_nml_in_lsh_n;
	reg signed[6:0] s33_nml_exp; // 标准化后的指数(在范围[-63, 31]内)
	reg signed[32:0] s33_nml_mts; // 标准化后的尾数
	// [阶码与绝对尾数构建]
	wire s33_build_in_vld;
	wire s33_build_in_pass;
	wire s33_build_in_set_to_0_flag; // 将结果设为0(标志)
	wire s33_build_in_arsh1_flag; // 算术右移1位(标志)
	wire signed[32:0] s33_build_in_mts_cps; // 补偿后的尾数(Q31)
	reg s33_build_sign; // 构建的符号位
	reg[7:0] s33_build_ec; // 构建的阶码
	reg[32:0] s33_build_mts; // 构建的绝对尾数(Q31)
	// [对绝对尾数作四舍五入]
	wire s33_round_in_vld;
	wire s33_round_in_pass;
	wire[31:0] s33_round_in_op_x;
	wire s33_round_to_fwd_carry_flag; // 四舍五入向前进位(标志)
	reg[31:0] s33_round_res; // 转换结果
	// [最终结果]
	wire s33_out_vld;
	wire[31:0] s33_out_res;
	wire[INFO_ALONG_WIDTH-1:0] s33_out_info_along;
	
	assign s33_pattern_gen_in_vld = (in_data_fmt_inner == IN_DATA_FMT_S33) & cvt_cell_i_vld;
	assign s33_pattern_gen_in_pass = cvt_cell_i_pass;
	assign s33_pattern_gen_in_op_x = 
		({33{integer_type == INTEGER_TYPE_U8}} & {25'd0, cvt_cell_i_op_x[7:0]}) | 
		({33{integer_type == INTEGER_TYPE_S8}} & {{25{cvt_cell_i_op_x[7]}}, cvt_cell_i_op_x[7:0]}) | 
		({33{integer_type == INTEGER_TYPE_U16}} & {17'd0, cvt_cell_i_op_x[15:0]}) | 
		({33{integer_type == INTEGER_TYPE_S16}} & {{17{cvt_cell_i_op_x[15]}}, cvt_cell_i_op_x[15:0]}) | 
		({33{integer_type == INTEGER_TYPE_U32}} & {1'b0, cvt_cell_i_op_x[31:0]}) | 
		({33{integer_type == INTEGER_TYPE_S32}} & {cvt_cell_i_op_x[31], cvt_cell_i_op_x[31:0]});
	assign s33_pattern_gen_in_op_x_rvs = {
		s33_pattern_gen_in_op_x[0], s33_pattern_gen_in_op_x[1], s33_pattern_gen_in_op_x[2], s33_pattern_gen_in_op_x[3],
		s33_pattern_gen_in_op_x[4], s33_pattern_gen_in_op_x[5], s33_pattern_gen_in_op_x[6], s33_pattern_gen_in_op_x[7],
		s33_pattern_gen_in_op_x[8], s33_pattern_gen_in_op_x[9], s33_pattern_gen_in_op_x[10], s33_pattern_gen_in_op_x[11],
		s33_pattern_gen_in_op_x[12], s33_pattern_gen_in_op_x[13], s33_pattern_gen_in_op_x[14], s33_pattern_gen_in_op_x[15],
		s33_pattern_gen_in_op_x[16], s33_pattern_gen_in_op_x[17], s33_pattern_gen_in_op_x[18], s33_pattern_gen_in_op_x[19],
		s33_pattern_gen_in_op_x[20], s33_pattern_gen_in_op_x[21], s33_pattern_gen_in_op_x[22], s33_pattern_gen_in_op_x[23],
		s33_pattern_gen_in_op_x[24], s33_pattern_gen_in_op_x[25], s33_pattern_gen_in_op_x[26], s33_pattern_gen_in_op_x[27],
		s33_pattern_gen_in_op_x[28], s33_pattern_gen_in_op_x[29], s33_pattern_gen_in_op_x[30], s33_pattern_gen_in_op_x[31],
		s33_pattern_gen_in_op_x[32]
	};
	
	assign s33_nml_in_vld = (in_data_fmt_inner == IN_DATA_FMT_S33) & cvt_cell_i_vld_delayed[1];
	assign s33_nml_in_pass = cvt_cell_i_pass_delayed[1];
	assign s33_nml_in_op_x = 
		{
			(
				(integer_type == INTEGER_TYPE_S8) | 
				(integer_type == INTEGER_TYPE_S16) | 
				(integer_type == INTEGER_TYPE_S32)
			) & cvt_cell_i_op_x_delayed[1][31],
			cvt_cell_i_op_x_delayed[1][31:0]
		};
	assign s33_nml_in_lsh_n = 
		({5{s33_pattern_gen_onehot[0]}}  & 5'd0)  | 
		({5{s33_pattern_gen_onehot[1]}}  & 5'd1)  | 
		({5{s33_pattern_gen_onehot[2]}}  & 5'd2)  | 
		({5{s33_pattern_gen_onehot[3]}}  & 5'd3)  | 
		({5{s33_pattern_gen_onehot[4]}}  & 5'd4)  | 
		({5{s33_pattern_gen_onehot[5]}}  & 5'd5)  | 
		({5{s33_pattern_gen_onehot[6]}}  & 5'd6)  | 
		({5{s33_pattern_gen_onehot[7]}}  & 5'd7)  | 
		({5{s33_pattern_gen_onehot[8]}}  & 5'd8)  | 
		({5{s33_pattern_gen_onehot[9]}}  & 5'd9)  | 
		({5{s33_pattern_gen_onehot[10]}} & 5'd10) | 
		({5{s33_pattern_gen_onehot[11]}} & 5'd11) | 
		({5{s33_pattern_gen_onehot[12]}} & 5'd12) | 
		({5{s33_pattern_gen_onehot[13]}} & 5'd13) | 
		({5{s33_pattern_gen_onehot[14]}} & 5'd14) | 
		({5{s33_pattern_gen_onehot[15]}} & 5'd15) | 
		({5{s33_pattern_gen_onehot[16]}} & 5'd16) | 
		({5{s33_pattern_gen_onehot[17]}} & 5'd17) | 
		({5{s33_pattern_gen_onehot[18]}} & 5'd18) | 
		({5{s33_pattern_gen_onehot[19]}} & 5'd19) | 
		({5{s33_pattern_gen_onehot[20]}} & 5'd20) | 
		({5{s33_pattern_gen_onehot[21]}} & 5'd21) | 
		({5{s33_pattern_gen_onehot[22]}} & 5'd22) | 
		({5{s33_pattern_gen_onehot[23]}} & 5'd23) | 
		({5{s33_pattern_gen_onehot[24]}} & 5'd24) | 
		({5{s33_pattern_gen_onehot[25]}} & 5'd25) | 
		({5{s33_pattern_gen_onehot[26]}} & 5'd26) | 
		({5{s33_pattern_gen_onehot[27]}} & 5'd27) | 
		({5{s33_pattern_gen_onehot[28]}} & 5'd28) | 
		({5{s33_pattern_gen_onehot[29]}} & 5'd29) | 
		({5{s33_pattern_gen_onehot[30]}} & 5'd30) | 
		({5{s33_pattern_gen_onehot[31]}} & 5'd31);
	
	assign s33_build_in_vld = (in_data_fmt_inner == IN_DATA_FMT_S33) & cvt_cell_i_vld_delayed[2];
	assign s33_build_in_pass = cvt_cell_i_pass_delayed[2];
	assign s33_build_in_set_to_0_flag = (s33_nml_mts[32:31] == 2'b00) || (s33_nml_mts[32:31] == 2'b11);
	assign s33_build_in_arsh1_flag = (s33_nml_mts[32:31] == 2'b10) & (s33_nml_mts[30:0] == 31'd0);
	assign s33_build_in_mts_cps = 
		s33_build_in_arsh1_flag ? 
			{s33_nml_mts[32], s33_nml_mts[32:1]}:
			s33_nml_mts[32:0];
	
	assign s33_round_in_vld = (in_data_fmt_inner == IN_DATA_FMT_S33) & cvt_cell_i_vld_delayed[3];
	assign s33_round_in_pass = cvt_cell_i_pass_delayed[3];
	assign s33_round_in_op_x = cvt_cell_i_op_x_delayed[3][31:0];
	assign s33_round_to_fwd_carry_flag = EN_ROUND & s33_build_mts[7] & ((|s33_build_mts[6:0]) | s33_build_mts[8]);
	
	assign s33_out_vld = (in_data_fmt_inner == IN_DATA_FMT_S33) & cvt_cell_i_vld_delayed[4];
	assign s33_out_res = s33_round_res;
	assign s33_out_info_along = cvt_cell_i_info_along_delayed[4];
	
	// 生成的标准化模式独热码
	always @(posedge aclk)
	begin
		if(aclken & s33_pattern_gen_in_vld & (~s33_pattern_gen_in_pass))
			/*
			当操作数X < 0时, 从MSB开始找第1个"0"的位置;当操作数X >= 0时, 从MSB开始找第1个"1"的位置
			
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
			s33_pattern_gen_onehot <= # SIM_DELAY 
				({32{s33_pattern_gen_in_op_x_rvs[0]}} ^ s33_pattern_gen_in_op_x_rvs[32:1]) & 
				((~({32{s33_pattern_gen_in_op_x_rvs[0]}} ^ s33_pattern_gen_in_op_x_rvs[32:1])) + 1'b1);
	end
	
	// 标准化后的指数(在范围[-63, 31]内)
	always @(posedge aclk)
	begin
		if(aclken & s33_nml_in_vld & (~s33_nml_in_pass))
			s33_nml_exp <= # SIM_DELAY 
				7'sd31 - (fixed_point_quat_accrc | 7'd0) - (s33_nml_in_lsh_n | 7'd0);
	end
	// 标准化后的尾数
	always @(posedge aclk)
	begin
		if(aclken & s33_nml_in_vld & (~s33_nml_in_pass))
			s33_nml_mts <= # SIM_DELAY 
				s33_nml_in_op_x << s33_nml_in_lsh_n;
	end
	
	// 构建的符号位, 构建的阶码, 构建的绝对尾数(Q31)
	always @(posedge aclk)
	begin
		if(aclken & s33_build_in_vld & (~s33_build_in_pass))
		begin
			s33_build_sign <= # SIM_DELAY s33_nml_mts[32];
			
			s33_build_ec <= # SIM_DELAY 
				s33_build_in_set_to_0_flag ? 
					8'd0:
					(
						{s33_nml_exp[6], s33_nml_exp[6:0]} + 
						// s33_build_in_arsh1_flag ? 8'd128:8'd127
						{s33_build_in_arsh1_flag, {7{~s33_build_in_arsh1_flag}}}
					);
			
			s33_build_mts <= # SIM_DELAY 
				s33_build_in_set_to_0_flag ? 
					33'd0:
					(({33{s33_nml_mts[32]}} ^ s33_build_in_mts_cps) + s33_nml_mts[32]);
		end
	end
	
	// 转换结果
	always @(posedge aclk)
	begin
		if(aclken & s33_round_in_vld)
		begin
			if(s33_round_in_pass)
				s33_round_res <= # SIM_DELAY s33_round_in_op_x;
			else
			begin
				s33_round_res[31] <= # SIM_DELAY s33_build_sign;
				s33_round_res[30:23] <= # SIM_DELAY s33_build_ec + ((&s33_build_mts[30:8]) & s33_round_to_fwd_carry_flag);
				s33_round_res[22:0] <= # SIM_DELAY s33_build_mts[30:8] + s33_round_to_fwd_carry_flag;
			end
		end
	end
	
	/** 转换单元输出 **/
	reg[31:0] cvt_cell_o_res_r; // 计算结果
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
					(
						((in_data_fmt_inner == IN_DATA_FMT_FP16) & fp16_out_vld) | 
						((in_data_fmt_inner == IN_DATA_FMT_S33) & s33_out_vld)
					);
	end
	
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				bypass ? 
					cvt_cell_i_vld:
					(
						((in_data_fmt_inner == IN_DATA_FMT_FP16) & fp16_out_vld) | 
						((in_data_fmt_inner == IN_DATA_FMT_S33) & s33_out_vld)
					)
			)
		)
		begin
			cvt_cell_o_res_r <= # SIM_DELAY 
				bypass ? 
					cvt_cell_i_op_x[31:0]:
					(
						({32{in_data_fmt_inner == IN_DATA_FMT_FP16}} & fp16_out_res) | 
						({32{in_data_fmt_inner == IN_DATA_FMT_S33}} & s33_out_res)
					);
			
			cvt_cell_o_info_along_r <= # SIM_DELAY 
				bypass ? 
					cvt_cell_i_info_along:
					(
						({INFO_ALONG_WIDTH{in_data_fmt_inner == IN_DATA_FMT_FP16}} & fp16_out_info_along) | 
						({INFO_ALONG_WIDTH{in_data_fmt_inner == IN_DATA_FMT_S33}} & s33_out_info_along)
					);
		end
	end
	
endmodule
