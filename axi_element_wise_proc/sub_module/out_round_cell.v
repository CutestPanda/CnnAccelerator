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
--------------------------------------------
|  待舍入数据格式  |     舍入后数据格式    |
--------------------------------------------
|       S33        | U8/S8/U16/S16/U32/S32 |
--------------------------------------------
|       FP32       |          FP16         |
--------------------------------------------

时延 = 3clk

舍入方式为四舍五入(向最近偶数舍入)

带有全局时钟使能

注意:
当运算数据格式为S33时, 操作数X的量化精度为in_fixed_point_quat_accrc, 结果的量化精度为out_fixed_point_quat_accrc
必须满足out_fixed_point_quat_accrc <= in_fixed_point_quat_accrc
定点数舍入位数(fixed_point_rounding_digits) = 
	输入定点数量化精度(in_fixed_point_quat_accrc) - 输出定点数量化精度(out_fixed_point_quat_accrc)

若旁路本单元, 则输入数据格式可为FP32、S32、U32、S16、U16、S8或U8

浮点运算未考虑INF和NAN

协议:
无

作者: 陈家耀
日期: 2026/01/12
********************************************************************/


module out_round_cell #(
	parameter USE_EXT_CE = 1'b0, // 使用外部使能信号
	parameter S33_ROUND_SUPPORTED = 1'b1, // 是否支持S33数据的舍入
	parameter FP32_ROUND_SUPPORTED = 1'b1, // 是否支持FP32数据的舍入
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 控制信号
	input wire bypass, // 旁路本单元
	input wire s0_ce, // 第0级使能
	input wire s1_ce, // 第1级使能
	input wire s2_ce, // 第2级使能
	
	// 运行时参数
	input wire[2:0] target_data_fmt, // 目标数据格式
	input wire[4:0] in_fixed_point_quat_accrc, // 输入定点数量化精度
	input wire[4:0] out_fixed_point_quat_accrc, // 输出定点数量化精度
	input wire[4:0] fixed_point_rounding_digits, // 定点数舍入位数
	
	// 舍入单元输入
	input wire[32:0] round_i_op_x, // 操作数X(定点数或FP32)
	input wire[INFO_ALONG_WIDTH-1:0] round_i_info_along, // 随路数据
	input wire round_i_vld,
	
	// 舍入单元处理结果
	output wire[31:0] round_o_res, // 结果(定点数或FP16或FP32)
	output wire[INFO_ALONG_WIDTH-1:0] round_o_info_along, // 随路数据
	output wire round_o_vld
);
	
	/** 常量 **/
	// 目标数据格式的编码
	localparam TARGET_DATA_FMT_U8 = 3'b000;
	localparam TARGET_DATA_FMT_S8 = 3'b001;
	localparam TARGET_DATA_FMT_U16 = 3'b010;
	localparam TARGET_DATA_FMT_S16 = 3'b011;
	localparam TARGET_DATA_FMT_U32 = 3'b100;
	localparam TARGET_DATA_FMT_S32 = 3'b101;
	localparam TARGET_DATA_FMT_FP16 = 3'b110;
	localparam TARGET_DATA_FMT_NONE = 3'b111;
	
	/** 运算数据格式 **/
	wire[2:0] target_data_fmt_inner;
	
	assign target_data_fmt_inner = 
		(S33_ROUND_SUPPORTED  & (target_data_fmt == TARGET_DATA_FMT_U8))   ? TARGET_DATA_FMT_U8:
		(S33_ROUND_SUPPORTED  & (target_data_fmt == TARGET_DATA_FMT_S8))   ? TARGET_DATA_FMT_S8:
		(S33_ROUND_SUPPORTED  & (target_data_fmt == TARGET_DATA_FMT_U16))  ? TARGET_DATA_FMT_U16:
		(S33_ROUND_SUPPORTED  & (target_data_fmt == TARGET_DATA_FMT_S16))  ? TARGET_DATA_FMT_S16:
		(S33_ROUND_SUPPORTED  & (target_data_fmt == TARGET_DATA_FMT_U32))  ? TARGET_DATA_FMT_U32:
		(S33_ROUND_SUPPORTED  & (target_data_fmt == TARGET_DATA_FMT_S32))  ? TARGET_DATA_FMT_S32:
		(FP32_ROUND_SUPPORTED & (target_data_fmt == TARGET_DATA_FMT_FP16)) ? TARGET_DATA_FMT_FP16:
		                                                                     TARGET_DATA_FMT_NONE;
	
	/** 输入延迟链 **/
	reg[3:1] round_i_vld_delayed;
	reg[INFO_ALONG_WIDTH-1:0] round_i_info_along_delayed[1:3];
	reg[32:0] round_i_op_x_delayed[1:3];
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			round_i_vld_delayed <= 3'b000;
		else if(aclken & (~USE_EXT_CE))
			round_i_vld_delayed <= # SIM_DELAY {round_i_vld_delayed[2:1], round_i_vld};
	end
	
	always @(posedge aclk)
	begin
		if(aclken & (USE_EXT_CE ? s0_ce:round_i_vld))
		begin
			round_i_info_along_delayed[1] <= # SIM_DELAY round_i_info_along;
			round_i_op_x_delayed[1] <= # SIM_DELAY round_i_op_x;
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & (USE_EXT_CE ? s1_ce:round_i_vld_delayed[1]))
		begin
			round_i_info_along_delayed[2] <= # SIM_DELAY round_i_info_along_delayed[1];
			round_i_op_x_delayed[2] <= # SIM_DELAY round_i_op_x_delayed[1];
		end
	end
	always @(posedge aclk)
	begin
		if(aclken & (USE_EXT_CE ? s2_ce:round_i_vld_delayed[2]))
		begin
			round_i_info_along_delayed[3] <= # SIM_DELAY round_i_info_along_delayed[2];
			round_i_op_x_delayed[3] <= # SIM_DELAY round_i_op_x_delayed[2];
		end
	end
	
	/** 共享加法器#0 **/
	wire[32:0] shared_adder_op_a;
	wire shared_adder_op_b;
	wire[32:0] shared_adder_res;
	
	assign shared_adder_res = shared_adder_op_a + shared_adder_op_b;
	
	/**
	整型格式的舍入
	
	-----------------------------------------------------------
	| 流水线级 |        完成的内容        |        备注       |
	-----------------------------------------------------------
	|    1     | 对定点数作(舍入)算术右移 |                   |
	|          | 确定舍入进位             |                   |
	-----------------------------------------------------------
	|    2     | 作舍入进位的加法运算     |                   |
	-----------------------------------------------------------
	|    3     | 溢出判断与饱和化处理     |                   |
	-----------------------------------------------------------
	**/
	// [舍入算术右移]
	wire s33_arsh_i_vld;
	wire signed[33:0] s33_arsh_i_op; // 待算术右移的定点数(Q = in_fixed_point_quat_accrc + 1)
	reg s33_arsh_carry_to_fwd_flag; // 四舍五入向前进位(标志)
	reg signed[32:0] s33_arsh_res; // 算术右移后的定点数(Q = out_fixed_point_quat_accrc)
	// [舍入进位加法]
	wire s33_round_add_i_vld;
	wire[32:0] s33_shared_adder_op_a;
	wire s33_shared_adder_op_b;
	reg signed[32:0] s33_round_res; // 四舍五入后的定点数(Q = out_fixed_point_quat_accrc)
	// [溢出判断与饱和化处理]
	wire s33_sat_i_vld;
	wire signed[32:0] s33_sat_i_op; // 待作溢出判断与饱和化处理的定点数(Q = out_fixed_point_quat_accrc)
	wire[32:0] s33_sat_i_ovf_jdg_mask; // 溢出判断掩码
	wire s33_sat_i_up_ovf_flag; // 上溢标志
	wire s33_sat_i_down_ovf_flag; // 下溢标志
	wire[31:0] s33_sat_i_up_ovf_value; // 上溢值
	wire[31:0] s33_sat_i_down_ovf_value; // 下溢值
	reg[31:0] s33_sat_res; // 溢出判断与饱和化处理后的结果
	// [最终结果]
	wire s33_fnl_o_vld;
	wire[INFO_ALONG_WIDTH-1:0] s33_fnl_info_along;
	wire[31:0] s33_fnl_res;
	
	assign s33_arsh_i_vld = 
		(
			(target_data_fmt_inner == TARGET_DATA_FMT_U8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U32) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S32)
		) & 
		(
			USE_EXT_CE ? 
				s0_ce:
				round_i_vld
		);
	assign s33_arsh_i_op = {round_i_op_x[32:0], 1'b0};
	
	assign s33_round_add_i_vld = 
		(
			(target_data_fmt_inner == TARGET_DATA_FMT_U8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U32) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S32)
		) & 
		(
			USE_EXT_CE ? 
				s1_ce:
				round_i_vld_delayed[1]
		);
	assign s33_shared_adder_op_a = s33_arsh_res[32:0];
	assign s33_shared_adder_op_b = s33_arsh_carry_to_fwd_flag;
	
	assign s33_sat_i_vld = 
		(
			(target_data_fmt_inner == TARGET_DATA_FMT_U8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U32) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S32)
		) & 
		(
			USE_EXT_CE ? 
				s2_ce:
				round_i_vld_delayed[2]
		);
	assign s33_sat_i_op = 
		s33_round_res;
	assign s33_sat_i_ovf_jdg_mask = 
		({33{target_data_fmt_inner == TARGET_DATA_FMT_S32}} & 33'h0_80000000) | // [31]
		({33{target_data_fmt_inner == TARGET_DATA_FMT_U32}} & 33'h0_00000000) | // NONE
		({33{target_data_fmt_inner == TARGET_DATA_FMT_S16}} & 33'h0_ffff8000) | // [31:15]
		({33{target_data_fmt_inner == TARGET_DATA_FMT_U16}} & 33'h0_ffff0000) | // [31:16]
		({33{target_data_fmt_inner == TARGET_DATA_FMT_S8}}  & 33'h0_ffffff80) | // [31:7]
		({33{target_data_fmt_inner == TARGET_DATA_FMT_U8}}  & 33'h0_ffffff00);  // [31:8]
	assign s33_sat_i_up_ovf_flag = 
		(~s33_sat_i_op[32]) & 
		(|(s33_sat_i_op[31:0] & s33_sat_i_ovf_jdg_mask[31:0]));
	assign s33_sat_i_down_ovf_flag = 
		s33_sat_i_op[32] & 
		(
			(target_data_fmt_inner == TARGET_DATA_FMT_U32) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U8) | 
			((s33_sat_i_op[31:0] & s33_sat_i_ovf_jdg_mask[31:0]) != s33_sat_i_ovf_jdg_mask[31:0])
		);
	assign s33_sat_i_up_ovf_value = 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_S32}} & 32'h7fffffff) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_U32}} & 32'hffffffff) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_S16}} & 32'h00007fff) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_U16}} & 32'h0000ffff) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_S8}}  & 32'h0000007f) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_U8}}  & 32'h000000ff);
	assign s33_sat_i_down_ovf_value = 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_S32}} & 32'h80000000) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_U32}} & 32'h00000000) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_S16}} & 32'hffff8000) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_U16}} & 32'h00000000) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_S8}}  & 32'hffffff80) | 
		({32{target_data_fmt_inner == TARGET_DATA_FMT_U8}}  & 32'h00000000);
	
	assign s33_fnl_o_vld = 
		(
			(target_data_fmt_inner == TARGET_DATA_FMT_U8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S8) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S16) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_U32) | 
			(target_data_fmt_inner == TARGET_DATA_FMT_S32)
		) & 
		round_i_vld_delayed[3];
	assign s33_fnl_info_along = round_i_info_along_delayed[3];
	assign s33_fnl_res = s33_sat_res;
	
	// 四舍五入向前进位(标志)
	always @(posedge aclk)
	begin
		if(aclken & s33_arsh_i_vld)
			s33_arsh_carry_to_fwd_flag <= # SIM_DELAY 
				(fixed_point_rounding_digits != 5'd0) & 
				(
					(|(s33_arsh_i_op & (34'd1 << fixed_point_rounding_digits))) & // 舍入位 = 1
					(
						(|(s33_arsh_i_op & ((34'd1 << fixed_point_rounding_digits) - 34'd1))) | // 保护位不全0
						(|(s33_arsh_i_op & (34'd2 << fixed_point_rounding_digits))) // 舍入后LSB = 1
					)
				);
	end
	// 算术右移后的定点数(Q = out_fixed_point_quat_accrc)
	always @(posedge aclk)
	begin
		if(aclken & s33_arsh_i_vld)
			s33_arsh_res <= # SIM_DELAY 
				$signed(s33_arsh_i_op[33:1]) >>> fixed_point_rounding_digits;
	end
	
	// 四舍五入后的定点数(Q = out_fixed_point_quat_accrc)
	always @(posedge aclk)
	begin
		if(aclken & s33_round_add_i_vld)
			s33_round_res <= # SIM_DELAY shared_adder_res[32:0];
	end
	
	// 溢出判断与饱和化处理后的结果
	always @(posedge aclk)
	begin
		if(aclken & s33_sat_i_vld)
			s33_sat_res <= # SIM_DELAY 
				({32{s33_sat_i_up_ovf_flag}} & s33_sat_i_up_ovf_value[31:0]) | 
				({32{s33_sat_i_down_ovf_flag}} & s33_sat_i_down_ovf_value[31:0]) | 
				({32{~(s33_sat_i_up_ovf_flag | s33_sat_i_down_ovf_flag)}} & s33_sat_i_op[31:0]);
	end
	
	/**
	浮点格式的舍入
	
	-----------------------------------------------------------
	| 流水线级 |        完成的内容        |        备注       |
	-----------------------------------------------------------
	|    1     | 对尾数作四舍五入         | Q23 -> Q10        |
	|          | (向最近偶数舍入)         |                   |
	-----------------------------------------------------------
	|    2     | 重新标准化               | 算术右移1位或不变 |
	-----------------------------------------------------------
	|    3     | 结果延迟补偿             |                   |
	-----------------------------------------------------------
	**/
	// [对尾数作四舍五入(向最近偶数舍入)]
	wire fp_round_i_vld;
	wire[7:0] fp_round_i_ec; // FP32原始阶码
	wire[24:0] fp_round_i_mts; // 待舍入的尾数(Q23)
	wire fp_round_i_carry_to_fwd; // 向前进位(标志)
	wire[32:0] fp_shared_adder_op_a;
	wire fp_shared_adder_op_b;
	reg[11:0] fp_round_res_mts; // 舍入后的尾数(Q10)
	reg[7:0] fp_round_res_ec; // 延迟1clk的FP32原始阶码
	// [重新标准化]
	wire fp_nml_i_vld;
	wire fp_nml_i_is_op_x_neg_flag; // 操作数X是负数(标志)
	wire[11:0] fp_nml_i_mts; // 待标准化的尾数(Q10)
	wire[7:0] fp_nml_i_ec; // 待处理的FP32原始阶码
	wire[7:0] fp_nml_i_ec_cps; // 补偿后的FP32阶码
	wire fp_nml_i_to_arsh; // 算术右移1位(标志)
	wire fp_nml_i_set_to_0; // 将结果设为0(标志)
	wire fp_nml_i_set_to_max; // 将结果设为最大值(标志)
	reg[15:0] fp_nml_res; // 标准化后的FP16结果
	// [结果延迟补偿]
	wire fp_delay_i_vld;
	wire[15:0] fp_delay_i_data; // 待延迟的FP16数据
	reg[15:0] fp_delay_res; // 延迟1clk的FP16结果
	// [最终结果]
	wire fp_fnl_o_vld;
	wire[INFO_ALONG_WIDTH-1:0] fp_fnl_info_along;
	wire[31:0] fp_fnl_res;
	
	assign fp_round_i_vld = 
		(target_data_fmt_inner == TARGET_DATA_FMT_FP16) & 
		(
			USE_EXT_CE ? 
				s0_ce:
				round_i_vld
		);
	assign fp_round_i_ec = round_i_op_x[30:23];
	assign fp_round_i_mts = {1'b0, fp_round_i_ec != 8'd0, round_i_op_x[22:0]};
	assign fp_round_i_carry_to_fwd = 
		fp_round_i_mts[12] & // 舍入位 = 1
		(
			(|fp_round_i_mts[11:0]) | // 保护位不全0
			fp_round_i_mts[13] // 舍入后LSB = 1
		);
	assign fp_shared_adder_op_a = fp_round_i_mts[24:13] | 33'd0;
	assign fp_shared_adder_op_b = fp_round_i_carry_to_fwd;
	
	assign fp_nml_i_vld = 
		(target_data_fmt_inner == TARGET_DATA_FMT_FP16) & 
		(
			USE_EXT_CE ? 
				s1_ce:
				round_i_vld_delayed[1]
		);
	assign fp_nml_i_is_op_x_neg_flag = round_i_op_x_delayed[1][31];
	assign fp_nml_i_mts = fp_round_res_mts;
	assign fp_nml_i_ec = fp_round_res_ec;
	assign fp_nml_i_ec_cps = fp_nml_i_ec + fp_nml_i_to_arsh;
	assign fp_nml_i_to_arsh = fp_nml_i_mts[11:10] != 2'b01; // 不在范围[1, 2)内
	assign fp_nml_i_set_to_0 = 
		(fp_nml_i_ec < 8'd113) | // 指数 < -14
		(fp_nml_i_mts[11:10] == 2'b00); // 尾数在范围[0, 1)内
	assign fp_nml_i_set_to_max = fp_nml_i_ec_cps > 8'd142; // 指数 > 15
	
	assign fp_delay_i_vld = 
		(target_data_fmt_inner == TARGET_DATA_FMT_FP16) & 
		(
			USE_EXT_CE ? 
				s2_ce:
				round_i_vld_delayed[2]
		);
	assign fp_delay_i_data = fp_nml_res;
	
	assign fp_fnl_o_vld = 
		(target_data_fmt_inner == TARGET_DATA_FMT_FP16) & 
		round_i_vld_delayed[3];
	assign fp_fnl_info_along = round_i_info_along_delayed[3];
	assign fp_fnl_res = {16'd0, fp_delay_res};
	
	// 舍入后的尾数(Q10), 延迟1clk的FP32原始阶码
	always @(posedge aclk)
	begin
		if(aclken & fp_round_i_vld)
		begin
			fp_round_res_mts <= # SIM_DELAY shared_adder_res[11:0];
			fp_round_res_ec <= # SIM_DELAY fp_round_i_ec;
		end
	end
	
	// 标准化后的FP16结果
	always @(posedge aclk)
	begin
		if(aclken & fp_nml_i_vld)
		begin
			// 符号位
			fp_nml_res[15] <= # SIM_DELAY fp_nml_i_is_op_x_neg_flag;
			
			// 阶码
			fp_nml_res[14:10] <= # SIM_DELAY 
				fp_nml_i_set_to_0 ? 
					5'd0:
					(
						fp_nml_i_set_to_max ? 
							5'd30:
							(fp_nml_i_ec_cps - 127 + 15)
					);
			
			// 尾数
			fp_nml_res[9:0] <= # SIM_DELAY 
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
					);
		end
	end
	
	// 延迟1clk的FP16结果
	always @(posedge aclk)
	begin
		if(aclken & fp_delay_i_vld)
			fp_delay_res <= # SIM_DELAY fp_delay_i_data;
	end
	
	/** 计算单元复用 **/
	assign shared_adder_op_a = 
		(target_data_fmt_inner == TARGET_DATA_FMT_FP16) ? 
			fp_shared_adder_op_a:
			s33_shared_adder_op_a;
	assign shared_adder_op_b = 
		(target_data_fmt_inner == TARGET_DATA_FMT_FP16) ? 
			fp_shared_adder_op_b:
			s33_shared_adder_op_b;
	
	/** 舍入单元处理结果 **/
	assign round_o_res = 
		bypass ? 
			round_i_op_x[31:0]:
			(
				(target_data_fmt_inner == TARGET_DATA_FMT_FP16) ? 
					fp_fnl_res:
					s33_fnl_res
			);
	assign round_o_info_along = 
		bypass ? 
			round_i_info_along:
			(
				(target_data_fmt_inner == TARGET_DATA_FMT_FP16) ? 
					fp_fnl_info_along:
					s33_fnl_info_along
			);
	assign round_o_vld = 
		bypass ? 
			round_i_vld:
			(
				(target_data_fmt_inner == TARGET_DATA_FMT_FP16) ? 
					fp_fnl_o_vld:
					s33_fnl_o_vld
			);
	
endmodule
