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
本模块: 输出数据舍入单元

描述:
---------------------------------------
|  待舍入数据格式  |  舍入后数据格式  |
---------------------------------------
|      INT16       |       INT8       |
---------------------------------------
|      INT32       |      INT16       |
---------------------------------------
|       FP32       |       FP16       |
---------------------------------------

时延 = 2clk

舍入方式为四舍五入(向偶数舍入)

支持INT8、INT16、FP16三种运算数据格式

带有全局时钟使能

注意:
当运算数据格式为INT8或INT16时, 操作数X的量化精度为2*fixed_point_quat_accrc

浮点运算未考虑INF和NAN

协议:
无

作者: 陈家耀
日期: 2025/12/22
********************************************************************/


module out_round_cell #(
	parameter INT8_SUPPORTED = 1'b0, // 是否支持INT8运算数据格式
	parameter INT16_SUPPORTED = 1'b1, // 是否支持INT16运算数据格式
	parameter FP16_SUPPORTED = 1'b1, // 是否支持FP16运算数据格式
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire[3:0] fixed_point_quat_accrc, // 定点数量化精度
	
	// 舍入单元输入
	input wire[31:0] round_i_op_x, // 操作数X(定点数或FP32)
	input wire[INFO_ALONG_WIDTH-1:0] round_i_info_along, // 随路数据
	input wire round_i_vld,
	
	// 舍入单元处理结果
	output wire[15:0] round_o_res, // 结果(定点数或FP16)
	output wire[INFO_ALONG_WIDTH-1:0] round_o_info_along, // 随路数据
	output wire round_o_vld
);
	
	/** 常量 **/
	// 运算数据格式的编码
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	localparam CAL_FMT_NONE = 2'b11;
	
	/** 运算数据格式 **/
	wire[1:0] calfmt_inner;
	
	assign calfmt_inner = 
		(INT8_SUPPORTED  & (calfmt == CAL_FMT_INT8))  ? CAL_FMT_INT8:
		(INT16_SUPPORTED & (calfmt == CAL_FMT_INT16)) ? CAL_FMT_INT16:
		(FP16_SUPPORTED  & (calfmt == CAL_FMT_FP16))  ? CAL_FMT_FP16:
		                                                CAL_FMT_NONE;
	
	/** 输入延迟链 **/
	reg[2:1] round_i_vld_delayed;
	reg[INFO_ALONG_WIDTH-1:0] round_i_info_along_delayed[1:2];
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			round_i_vld_delayed <= 2'b00;
		else if(aclken)
			round_i_vld_delayed <= # SIM_DELAY {round_i_vld_delayed[1], round_i_vld};
	end
	
	always @(posedge aclk)
	begin
		if(aclken & round_i_vld)
			round_i_info_along_delayed[1] <= # SIM_DELAY round_i_info_along;
	end
	
	always @(posedge aclk)
	begin
		if(aclken & round_i_vld_delayed[1])
			round_i_info_along_delayed[2] <= # SIM_DELAY round_i_info_along_delayed[1];
	end
	
	/** 共享加法器#0 **/
	wire[32:0] shared_adder_op_a;
	wire shared_adder_op_b;
	wire[32:0] shared_adder_res;
	
	assign shared_adder_res = shared_adder_op_a + shared_adder_op_b;
	
	/**
	整型格式的舍入:
		四舍五入(向偶数舍入)
		作溢出饱和化处理
	**/
	// [四舍五入(向偶数舍入)]
	wire int_round_i_vld;
	wire signed[31:0] int_round_i_op; // 待舍入的定点数(Q = 2*fixed_point_quat_accrc)
	wire signed[31:0] int_round_i_op_arsh; // 算术右移后的定点数(Q = fixed_point_quat_accrc)
	wire int_round_i_carry_to_fwd; // 向前进位(标志)
	reg signed[32:0] int_round_res; // 舍入后的结果(Q = fixed_point_quat_accrc)
	// [溢出饱和化处理]
	wire int_sat_i_vld;
	wire signed[32:0] int_sat_i_op; // 待溢出饱和化处理的定点数(Q = fixed_point_quat_accrc)
	wire int_sat_i_ovf; // 定点数上溢(标志)
	wire int_sat_i_udf; // 定点数下溢(标志)
	reg signed[15:0] int_sat_res; // 溢出饱和化处理后的结果(Q = fixed_point_quat_accrc)
	// [最终结果]
	wire int_fnl_o_vld;
	wire[INFO_ALONG_WIDTH-1:0] int_fnl_info_along;
	wire signed[15:0] int_fnl_res;
	
	assign int_round_i_vld = 
		((calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)) & 
		round_i_vld;
	assign int_round_i_op = round_i_op_x;
	assign int_round_i_op_arsh = int_round_i_op >>> fixed_point_quat_accrc;
	assign int_round_i_carry_to_fwd = 
		(|({int_round_i_op, 2'b00} & ({32'd0, 2'b10} << fixed_point_quat_accrc))) & // 舍入位 = 1
		(
			(|({int_round_i_op, 2'b00} & (({32'd0, 2'b10} << fixed_point_quat_accrc) - 1))) | // 保护位不全0
			(|({int_round_i_op, 2'b00} & ({32'd1, 2'b00} << fixed_point_quat_accrc))) // 舍入后LSB = 1
		);
	
	assign int_sat_i_vld = 
		((calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)) & 
		round_i_vld_delayed[1];
	assign int_sat_i_op = int_round_res;
	assign int_sat_i_ovf = 
		(~int_sat_i_op[32]) & 
		(
			(|int_sat_i_op[31:15]) | 
			((calfmt_inner == CAL_FMT_INT8) & (|int_sat_i_op[14:7]))
		);
	assign int_sat_i_udf = 
		int_sat_i_op[32] & 
		(
			(~(&int_sat_i_op[31:15])) | 
			((calfmt_inner == CAL_FMT_INT8) & (~(&int_sat_i_op[14:7])))
		);
	
	assign int_fnl_o_vld = 
		((calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)) & 
		round_i_vld_delayed[2];
	assign int_fnl_info_along = round_i_info_along_delayed[2];
	assign int_fnl_res = int_sat_res;
	
	// 舍入后的结果(Q = fixed_point_quat_accrc)
	always @(posedge aclk)
	begin
		if(aclken & int_round_i_vld)
			int_round_res <= # SIM_DELAY shared_adder_res;
	end
	
	// 溢出饱和化处理后的结果(Q = fixed_point_quat_accrc)
	always @(posedge aclk)
	begin
		if(aclken & int_sat_i_vld)
		begin
			int_sat_res <= # SIM_DELAY 
				(calfmt_inner == CAL_FMT_INT16) ? 
					{int_sat_i_op[32], {15{~int_sat_i_udf}} & ({15{int_sat_i_ovf}} | int_sat_i_op[14:0])}:
					{{9{int_sat_i_op[32]}}, {7{~int_sat_i_udf}} & ({7{int_sat_i_ovf}} | int_sat_i_op[6:0])};
		end
	end
	
	/**
	浮点格式的舍入:
		对尾数作四舍五入(向偶数舍入)
		重新标准化
	**/
	// [对尾数作四舍五入(向偶数舍入)]
	wire fp_round_i_vld;
	wire[7:0] fp_round_i_ec; // FP32原始阶码
	wire signed[24:0] fp_round_i_mts; // 待舍入的尾数(Q23)
	wire fp_round_i_carry_to_fwd; // 向前进位(标志)
	reg signed[12:0] fp_round_res_mts; // 舍入后的尾数(Q10)
	reg[7:0] fp_round_res_ec; // 延迟1clk的FP32原始阶码
	// [重新标准化]
	wire fp_nml_i_vld;
	wire signed[12:0] fp_nml_i_mts; // 待标准化的尾数(Q10)
	wire[7:0] fp_nml_i_ec; // 待处理的FP32原始阶码
	wire[7:0] fp_nml_i_ec_cps; // 补偿后的FP32阶码
	wire fp_nml_i_to_arsh; // 算术右移1位(标志)
	wire fp_nml_i_set_to_0; // 将结果设为0(标志)
	wire fp_nml_i_set_to_max; // 将结果设为最大值(标志)
	reg[15:0] fp_nml_res; // 标准化后的结果
	// [最终结果]
	wire fp_fnl_o_vld;
	wire[INFO_ALONG_WIDTH-1:0] fp_fnl_info_along;
	wire[15:0] fp_fnl_res;
	
	assign fp_round_i_vld = 
		(calfmt_inner == CAL_FMT_FP16) & 
		round_i_vld;
	assign fp_round_i_ec = round_i_op_x[30:23];
	assign fp_round_i_mts = 
		({25{round_i_op_x[31]}} ^ {1'b0, fp_round_i_ec != 8'd0, round_i_op_x[22:0]}) + round_i_op_x[31];
	assign fp_round_i_carry_to_fwd = 
		fp_round_i_mts[12] & // 舍入位 = 1
		(
			(|fp_round_i_mts[11:0]) | // 保护位不全0
			fp_round_i_mts[13] // 舍入后LSB = 1
		);
	
	assign fp_nml_i_vld = 
		(calfmt_inner == CAL_FMT_FP16) & 
		round_i_vld_delayed[1];
	assign fp_nml_i_mts = fp_round_res_mts;
	assign fp_nml_i_ec = fp_round_res_ec;
	assign fp_nml_i_ec_cps = fp_nml_i_ec + fp_nml_i_to_arsh;
	assign fp_nml_i_to_arsh = 
		(fp_nml_i_mts[12:10] != 3'b001) & // 不在范围[1, 2)内
		(~((fp_nml_i_mts[12:10] == 3'b110) & (|fp_nml_i_mts[9:0]))) & // 不在范围(-2, -1)
		(~((fp_nml_i_mts[12:10] == 3'b111) & (fp_nml_i_mts[9:0] == 10'd0))); // 不是-1
	assign fp_nml_i_set_to_0 = 
		(fp_nml_i_ec < 8'd113) | // 指数 < -14
		(fp_nml_i_mts[12:10] == 3'b000) | // 尾数在范围[0, 1)内
		((fp_nml_i_mts[12:10] == 3'b111) & (|fp_nml_i_mts[9:0])); // 尾数在范围(-1, 0]内
	assign fp_nml_i_set_to_max = fp_nml_i_ec_cps > 8'd142;
	
	assign fp_fnl_o_vld = 
		(calfmt_inner == CAL_FMT_FP16) & 
		round_i_vld_delayed[2];
	assign fp_fnl_info_along = round_i_info_along_delayed[2];
	assign fp_fnl_res = fp_nml_res;
	
	// 舍入后的尾数(Q10), 延迟1clk的FP32原始阶码
	always @(posedge aclk)
	begin
		if(aclken & fp_round_i_vld)
		begin
			fp_round_res_mts <= # SIM_DELAY shared_adder_res[12:0];
			fp_round_res_ec <= # SIM_DELAY fp_round_i_ec;
		end
	end
	
	// 标准化后的结果
	always @(posedge aclk)
	begin
		if(aclken & fp_nml_i_vld)
		begin
			// 符号位
			fp_nml_res[15] <= # SIM_DELAY fp_nml_i_mts[12];
			
			// 阶码
			fp_nml_res[14:10] <= # SIM_DELAY 
				fp_nml_i_set_to_0 ? 
					5'd0:
					(
						fp_nml_i_set_to_max ? 
							5'd30:
							(fp_nml_i_ec_cps - 8'd112)
					);
			
			// 尾数
			fp_nml_res[9:0] <= # SIM_DELAY 
				(
					{10{fp_nml_i_mts[12]}} ^ 
					(
						fp_nml_i_set_to_0 ? 
							10'd0:
							(
								fp_nml_i_set_to_max ? 
									10'b11111_11111:
									(
										fp_nml_i_to_arsh ? 
											fp_nml_i_mts[10:1]:
											fp_nml_i_mts[9:0]
									)
							)
					)
				) + fp_nml_i_mts[12];
		end
	end
	
	/** 舍入单元处理结果 **/
	assign round_o_res = 
		({16{calfmt_inner == CAL_FMT_FP16}} & fp_fnl_res) | 
		({16{(calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)}} & int_fnl_res);
	assign round_o_info_along = 
		({INFO_ALONG_WIDTH{calfmt_inner == CAL_FMT_FP16}} & fp_fnl_info_along) | 
		({INFO_ALONG_WIDTH{(calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)}} & int_fnl_info_along);
	assign round_o_vld = 
		((calfmt_inner == CAL_FMT_FP16) & fp_fnl_o_vld) | 
		(((calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)) & int_fnl_o_vld);
	
	assign shared_adder_op_a = 
		({33{calfmt_inner == CAL_FMT_FP16}} & {{21{fp_round_i_mts[24]}}, fp_round_i_mts[24:13]}) | 
		({33{(calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)}} & {int_round_i_op_arsh[31], int_round_i_op_arsh[31:0]});
	assign shared_adder_op_b = 
		((calfmt_inner == CAL_FMT_FP16) & fp_round_i_carry_to_fwd) | 
		(((calfmt_inner == CAL_FMT_INT8) | (calfmt_inner == CAL_FMT_INT16)) & int_round_i_carry_to_fwd);
	
endmodule
