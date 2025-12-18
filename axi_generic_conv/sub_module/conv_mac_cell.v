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
本模块: 卷积乘加单元

描述:
ATOMIC_C个乘法器实现特征图数据和卷积核权重相乘
ATOMIC_C输入加法器实现通道累加

支持INT16、FP16两种运算数据格式

带有全局时钟使能

时延 = 
	计算INT16时 -> 2 + log2(ATOMIC_C)
	计算FP16时  -> 4 + log2(ATOMIC_C)

FP16模式时, 尾数偏移为-50

注意：
外部有符号乘法器的计算时延 = 1clk
暂不支持INT8运算数据格式

协议:
无

作者: 陈家耀
日期: 2025/11/27
********************************************************************/


module conv_mac_cell #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter EN_SMALL_FP16 = "true", // 是否处理极小FP16
	parameter integer INFO_ALONG_WIDTH = 2, // 随路数据的位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	
	// 乘加单元计算输入
	input wire[ATOMIC_C*16-1:0] mac_in_ftm, // 特征图数据
	input wire[ATOMIC_C*16-1:0] mac_in_wgt, // 卷积核权重
	input wire mac_in_ftm_masked, // 特征图数据(无效标志)
	input wire[INFO_ALONG_WIDTH-1:0] mac_in_info_along, // 随路数据
	input wire mac_in_valid, // 输入有效指示
	
	// 乘加单元结果输出
	output wire[7:0] mac_out_exp, // 指数部分(仅当运算数据格式为FP16时有效)
	output wire signed[39:0] mac_out_frac, // 尾数部分或定点数
	output wire[INFO_ALONG_WIDTH-1:0] mac_out_info_along, // 随路数据
	output wire mac_out_valid, // 输出有效指示
	
	// 外部有符号乘法器
	output wire[ATOMIC_C*16-1:0] mul_op_a, // 操作数A
	output wire[ATOMIC_C*16-1:0] mul_op_b, // 操作数B
	output wire mul_ce, // 计算使能
	input wire[ATOMIC_C*32-1:0] mul_res // 计算结果
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 常量 **/
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 外部有符号乘法器 **/
	wire signed[15:0] mul_op_a_arr[0:ATOMIC_C-1]; // 操作数A
	wire signed[15:0] mul_op_b_arr[0:ATOMIC_C-1]; // 操作数B
	wire signed[31:0] mul_res_arr[0:ATOMIC_C-1]; // 计算结果
	
	genvar mul_i;
	generate
		for(mul_i = 0;mul_i < ATOMIC_C;mul_i = mul_i + 1)
		begin:mul_blk
			assign mul_op_a[mul_i*16+15:mul_i*16] = mul_op_a_arr[mul_i];
			assign mul_op_b[mul_i*16+15:mul_i*16] = mul_op_b_arr[mul_i];
			assign mul_res_arr[mul_i] = $signed(mul_res[mul_i*32+31:mul_i*32]);
		end
	endgenerate
	
	/** 乘加单元计算输入 **/
	wire[15:0] mac_in_ftm_arr[0:ATOMIC_C-1]; // 特征图数据
	wire[15:0] mac_in_wgt_arr[0:ATOMIC_C-1]; // 卷积核权重
	
	genvar mac_in_i;
	generate
		for(mac_in_i = 0;mac_in_i < ATOMIC_C;mac_in_i = mac_in_i + 1)
		begin:mac_in_blk
			assign mac_in_ftm_arr[mac_in_i] = mac_in_ftm[mac_in_i*16+15:mac_in_i*16];
			assign mac_in_wgt_arr[mac_in_i] = mac_in_wgt[mac_in_i*16+15:mac_in_i*16];
		end
	endgenerate
	
	/** 加法树 **/
	// 加法树输入
	wire signed[31:0] add_tree_in_arr[0:ATOMIC_C-1];
	wire[ATOMIC_C*32-1:0] add_tree_in;
	wire add_tree_in_mask;
	wire add_tree_in_valid;
	// 加法树输出
	wire signed[36:0] add_tree_out;
	wire add_tree_out_mask;
	wire add_tree_out_valid;
	
	genvar add_tree_in_i;
	generate
		for(add_tree_in_i = 0;add_tree_in_i < ATOMIC_C;add_tree_in_i = add_tree_in_i + 1)
		begin:add_tree_in_blk
			assign add_tree_in[add_tree_in_i*32+31:add_tree_in_i*32] = add_tree_in_arr[add_tree_in_i];
		end
	endgenerate
	
	generate
		if(ATOMIC_C != 1)
		begin
			add_tree_2_4_8_16_32 #(
				.add_input_n(ATOMIC_C),
				.add_width(32),
				.simulation_delay(SIM_DELAY)
			)add_tree_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.add_in(add_tree_in),
				.add_in_vld(add_tree_in_valid),
				
				.add_out(add_tree_out),
				.add_out_vld(add_tree_out_valid)
			);
			
			ram_based_shift_regs #(
				.data_width(1),
				.delay_n(clogb2(ATOMIC_C)),
				.shift_type("ff"),
				.en_output_register_init("false"),
				.simulation_delay(SIM_DELAY)
			)delay_for_mask_along_with_add_tree_u(
				.clk(aclk),
				.resetn(aresetn),
				
				.shift_in(add_tree_in_mask),
				.ce(aclken),
				.shift_out(add_tree_out_mask)
			);
		end
		else
		begin
			assign add_tree_out = $signed(add_tree_in);
			assign add_tree_out_mask = add_tree_in_mask;
			assign add_tree_out_valid = add_tree_in_valid;
		end
	endgenerate
	
	/** 输入有效指示延迟链 **/
	reg mac_in_valid_d1; // 延迟1clk的输入有效指示
	reg mac_in_valid_d2; // 延迟2clk的输入有效指示
	reg mac_in_valid_d3; // 延迟3clk的输入有效指示
	reg mac_in_valid_d4; // 延迟4clk的输入有效指示
	
	// 延迟1~4clk的输入有效指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{mac_in_valid_d4, mac_in_valid_d3, mac_in_valid_d2, mac_in_valid_d1} <= 4'b0000;
		else if(aclken)
			{mac_in_valid_d4, mac_in_valid_d3, mac_in_valid_d2, mac_in_valid_d1} <= # SIM_DELAY 
				{mac_in_valid_d3, mac_in_valid_d2, mac_in_valid_d1, mac_in_valid};
	end
	
	/** 特征图数据(无效标志)延迟链 **/
	reg mac_in_ftm_masked_d1; // 延迟1clk的特征图数据(无效标志)
	reg mac_in_ftm_masked_d2; // 延迟2clk的特征图数据(无效标志)
	reg mac_in_ftm_masked_d3; // 延迟3clk的特征图数据(无效标志)
	reg mac_in_ftm_masked_d4; // 延迟4clk的特征图数据(无效标志)
	
	// 延迟1clk的特征图数据(无效标志)
	always @(posedge aclk)
	begin
		if(aclken & mac_in_valid)
			mac_in_ftm_masked_d1 <= # SIM_DELAY mac_in_ftm_masked;
	end
	// 延迟2clk的特征图数据(无效标志)
	always @(posedge aclk)
	begin
		if(aclken & mac_in_valid_d1)
			mac_in_ftm_masked_d2 <= # SIM_DELAY mac_in_ftm_masked_d1;
	end
	// 延迟3clk的特征图数据(无效标志)
	always @(posedge aclk)
	begin
		if(aclken & mac_in_valid_d2)
			mac_in_ftm_masked_d3 <= # SIM_DELAY mac_in_ftm_masked_d2;
	end
	// 延迟4clk的特征图数据(无效标志)
	always @(posedge aclk)
	begin
		if(aclken & mac_in_valid_d3)
			mac_in_ftm_masked_d4 <= # SIM_DELAY mac_in_ftm_masked_d3;
	end
	
	/** INT16计算 **/
	// 延迟1clk的特征图数据和卷积核权重
	reg signed[15:0] ftm_d1_int16[0:ATOMIC_C-1];
	reg signed[15:0] wgt_d1_int16[0:ATOMIC_C-1];
	// 外部有符号乘法器
	wire signed[15:0] mul_op_a_int16_arr[0:ATOMIC_C-1]; // 操作数A
	wire signed[15:0] mul_op_b_int16_arr[0:ATOMIC_C-1]; // 操作数B
	wire mul_ce_int16; // 计算使能
	// 加法树输入
	wire signed[31:0] add_tree_in_int16_arr[0:ATOMIC_C-1];
	wire add_tree_in_int16_mask;
	wire add_tree_in_int16_valid;
	// 乘加单元结果输出
	wire signed[39:0] mac_out_frac_int16; // 定点数
	wire mac_out_int16_mask;
	wire mac_out_int16_valid;
	
	assign mul_ce_int16 = mac_in_valid_d1 & (~mac_in_ftm_masked_d1);
	assign add_tree_in_int16_mask = mac_in_ftm_masked_d2;
	assign add_tree_in_int16_valid = mac_in_valid_d2;
	
	assign mac_out_frac_int16 = {{3{add_tree_out[36]}}, add_tree_out};
	assign mac_out_int16_mask = add_tree_out_mask;
	assign mac_out_int16_valid = add_tree_out_valid;
	
	genvar cal_int16_i;
	generate
		for(cal_int16_i = 0;cal_int16_i < ATOMIC_C;cal_int16_i = cal_int16_i + 1)
		begin:cal_int16_blk
			assign mul_op_a_int16_arr[cal_int16_i] = ftm_d1_int16[cal_int16_i];
			assign mul_op_b_int16_arr[cal_int16_i] = wgt_d1_int16[cal_int16_i];
			
			assign add_tree_in_int16_arr[cal_int16_i] = mul_res_arr[cal_int16_i];
			
			// 延迟1clk的特征图数据和卷积核权重
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_INT16) & mac_in_valid & (~mac_in_ftm_masked))
				begin
					ftm_d1_int16[cal_int16_i] <= # SIM_DELAY $signed(mac_in_ftm_arr[cal_int16_i]);
					wgt_d1_int16[cal_int16_i] <= # SIM_DELAY $signed(mac_in_wgt_arr[cal_int16_i]);
				end
			end
		end
	endgenerate
	
	/**
	FP16计算
	
	第1级流水线: 生成MTS, 生成单点乘积的符号位, 计算特征图数据与卷积核权重的高3位阶码的和
	第2级流水线: 尾数相乘, 计算FUNC(阶段#1)
	第3级流水线: 生成带符号位的MTSO, 计算FUNC(阶段#2)
	第4级流水线: 生成右移的MTSO
	第4~(4 + log2(ATOMIC_C))级流水线: 通道累加
	**/
	// 外部有符号乘法器
	wire signed[15:0] mul_op_a_fp16_arr[0:ATOMIC_C-1]; // 操作数A
	wire signed[15:0] mul_op_b_fp16_arr[0:ATOMIC_C-1]; // 操作数B
	wire mul_ce_fp16; // 计算使能
	// 加法树输入
	wire signed[31:0] add_tree_in_fp16_arr[0:ATOMIC_C-1];
	wire add_tree_in_fp16_mask;
	wire add_tree_in_fp16_valid;
	// 最大值求解树
	wire signed[4:0] max_cmp_tree_in_arr[0:ATOMIC_C-1]; // 比较输入(数组)
	wire[ATOMIC_C*5-1:0] max_cmp_tree_in; // 比较输入
	wire max_cmp_tree_in_valid; // 输入有效指示
	wire signed[4:0] max_cmp_tree_out; // 比较输出
	// 乘加单元结果输出
	wire[7:0] mac_out_exp_fp16; // 指数部分
	wire signed[39:0] mac_out_frac_fp16; // 尾数部分
	wire mac_out_fp16_mask;
	wire mac_out_fp16_valid;
	// FP16输入
	wire fp16_s_f[0:ATOMIC_C-1]; // 特征图数据的符号位
	wire[4:0] fp16_e_f[0:ATOMIC_C-1]; // 特征图数据的指数位
	wire[9:0] fp16_m_f[0:ATOMIC_C-1]; // 特征图数据的尾数位
	wire fp16_s_w[0:ATOMIC_C-1]; // 卷积核权重的符号位
	wire[4:0] fp16_e_w[0:ATOMIC_C-1]; // 卷积核权重的指数位
	wire[9:0] fp16_m_w[0:ATOMIC_C-1]; // 卷积核权重的尾数位
	// MTS
	reg[13:0] fp16_mts_f[0:ATOMIC_C-1]; // 特征图数据的MTS
	reg[13:0] fp16_mts_w[0:ATOMIC_C-1]; // 卷积核权重的MTS
	// 单点乘积的符号位
	reg fp16_mtso_sign[0:ATOMIC_C-1]; // MTSO的符号位
	reg fp16_mtso_sign_d1[0:ATOMIC_C-1]; // 延迟1clk的MTSO的符号位
	// 特征图数据与卷积核权重的高3位阶码的和
	reg[3:0] fp16_e_h3_f_add_w[0:ATOMIC_C-1]; // 高3位阶码的和
	reg[3:0] fp16_e_h3_f_add_w_d1[0:ATOMIC_C-1]; // 延迟1clk的高3位阶码的和
	reg[3:0] fp16_e_h3_f_add_w_d2[0:ATOMIC_C-1]; // 延迟2clk的高3位阶码的和
	// MTSO
	wire[3:0] fp16_func; // FUNC
	reg[3:0] fp16_func_d1; // 延迟1clk的FUNC
	wire[5:0] fp16_set[0:ATOMIC_C-1]; // MTSO右移位数
	reg signed[28:0] fp16_signed_mtso[0:ATOMIC_C-1]; // 原始的有符号MTSO
	reg signed[28:0] fp16_shifted_mtso[0:ATOMIC_C-1]; // 右移的有符号MTSO
	
	assign mul_ce_fp16 = mac_in_valid_d1 & (~mac_in_ftm_masked_d1);
	
	assign add_tree_in_fp16_mask = mac_in_ftm_masked_d4;
	assign add_tree_in_fp16_valid = mac_in_valid_d4;
	
	assign max_cmp_tree_in_valid = (calfmt == CAL_FMT_FP16) & mac_in_valid_d1 & (~mac_in_ftm_masked_d1);
	
	assign mac_out_frac_fp16 = {{3{add_tree_out[36]}}, add_tree_out};
	assign mac_out_fp16_mask = add_tree_out_mask;
	assign mac_out_fp16_valid = add_tree_out_valid;
	
	assign fp16_func = max_cmp_tree_out[3:0];
	
	genvar fp16_in_i;
	generate
		for(fp16_in_i = 0;fp16_in_i < ATOMIC_C;fp16_in_i = fp16_in_i + 1)
		begin:fp16_in_blk
			assign {fp16_s_f[fp16_in_i], fp16_e_f[fp16_in_i], fp16_m_f[fp16_in_i]} = 
				mac_in_ftm_arr[fp16_in_i];
			assign {fp16_s_w[fp16_in_i], fp16_e_w[fp16_in_i], fp16_m_w[fp16_in_i]} = 
				mac_in_wgt_arr[fp16_in_i];
		end
	endgenerate
	
	genvar fp16_mts_i;
	generate
		for(fp16_mts_i = 0;fp16_mts_i < ATOMIC_C;fp16_mts_i = fp16_mts_i + 1)
		begin:fp16_mts_blk
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid & (~mac_in_ftm_masked))
					fp16_mts_f[fp16_mts_i] <= # SIM_DELAY 
						{3'b000, (EN_SMALL_FP16 == "false") | (fp16_e_f[fp16_mts_i] != 5'b00000), fp16_m_f[fp16_mts_i]} << 
							(
								((EN_SMALL_FP16 == "false") | (fp16_e_f[fp16_mts_i] != 5'b00000)) ? 
									fp16_e_f[fp16_mts_i][1:0]:
									2'b01
							);
			end
			
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid & (~mac_in_ftm_masked))
					fp16_mts_w[fp16_mts_i] <= # SIM_DELAY 
						{3'b000, (EN_SMALL_FP16 == "false") | (fp16_e_w[fp16_mts_i] != 5'b00000), fp16_m_w[fp16_mts_i]} << 
							(
								((EN_SMALL_FP16 == "false") | (fp16_e_w[fp16_mts_i] != 5'b00000)) ? 
									fp16_e_w[fp16_mts_i][1:0]:
									2'b01
							);
			end
		end
	endgenerate
	
	genvar fp16_mtso_sign_i;
	generate
		for(fp16_mtso_sign_i = 0;fp16_mtso_sign_i < ATOMIC_C;fp16_mtso_sign_i = fp16_mtso_sign_i + 1)
		begin:fp16_mtso_sign_blk
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid & (~mac_in_ftm_masked))
					fp16_mtso_sign[fp16_mtso_sign_i] <= # SIM_DELAY fp16_s_f[fp16_mtso_sign_i] ^ fp16_s_w[fp16_mtso_sign_i];
			end
			
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid_d1 & (~mac_in_ftm_masked_d1))
					fp16_mtso_sign_d1[fp16_mtso_sign_i] <= # SIM_DELAY fp16_mtso_sign[fp16_mtso_sign_i];
			end
		end
	endgenerate
	
	genvar fp16_mts_mul_i;
	generate
		for(fp16_mts_mul_i = 0;fp16_mts_mul_i < ATOMIC_C;fp16_mts_mul_i = fp16_mts_mul_i + 1)
		begin:fp16_mts_mul_blk
			assign mul_op_a_fp16_arr[fp16_mts_mul_i] = {2'b00, fp16_mts_f[fp16_mts_mul_i]};
			assign mul_op_b_fp16_arr[fp16_mts_mul_i] = {2'b00, fp16_mts_w[fp16_mts_mul_i]};
		end
	endgenerate
	
	genvar fp16_e_h3_f_add_w_i;
	generate
		for(fp16_e_h3_f_add_w_i = 0;fp16_e_h3_f_add_w_i < ATOMIC_C;fp16_e_h3_f_add_w_i = fp16_e_h3_f_add_w_i + 1)
		begin:fp16_e_h3_f_add_w_blk
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid & (~mac_in_ftm_masked))
					fp16_e_h3_f_add_w[fp16_e_h3_f_add_w_i] <= # SIM_DELAY 
						fp16_e_f[fp16_e_h3_f_add_w_i][4:2] + fp16_e_w[fp16_e_h3_f_add_w_i][4:2];
			end
			
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid_d1 & (~mac_in_ftm_masked_d1))
					fp16_e_h3_f_add_w_d1[fp16_e_h3_f_add_w_i] <= # SIM_DELAY 
						fp16_e_h3_f_add_w[fp16_e_h3_f_add_w_i];
			end
			
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid_d2 & (~mac_in_ftm_masked_d2))
					fp16_e_h3_f_add_w_d2[fp16_e_h3_f_add_w_i] <= # SIM_DELAY 
						fp16_e_h3_f_add_w_d1[fp16_e_h3_f_add_w_i];
			end
		end
	endgenerate
	
	genvar fp16_signed_mtso_i;
	generate
		for(fp16_signed_mtso_i = 0;fp16_signed_mtso_i < ATOMIC_C;fp16_signed_mtso_i = fp16_signed_mtso_i + 1)
		begin:fp16_signed_mtso_blk
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid_d2 & (~mac_in_ftm_masked_d2))
					fp16_signed_mtso[fp16_signed_mtso_i] <= # SIM_DELAY 
						fp16_mtso_sign_d1[fp16_signed_mtso_i] ? 
							({1'b1, ~mul_res_arr[fp16_signed_mtso_i][27:0]} + 1'b1):
							{1'b0, mul_res_arr[fp16_signed_mtso_i][27:0]};
			end
		end
	endgenerate
	
	genvar max_cmp_tree_in_i;
	generate
		for(max_cmp_tree_in_i = 0;max_cmp_tree_in_i < ATOMIC_C;max_cmp_tree_in_i = max_cmp_tree_in_i + 1)
		begin:max_cmp_tree_in_blk
			assign max_cmp_tree_in_arr[max_cmp_tree_in_i] = 
				{1'b0, fp16_e_h3_f_add_w[max_cmp_tree_in_i]};
			assign max_cmp_tree_in[max_cmp_tree_in_i*5+4:max_cmp_tree_in_i*5] = 
				max_cmp_tree_in_arr[max_cmp_tree_in_i];
		end
	endgenerate
	
	generate
		if(ATOMIC_C != 1)
		begin
			max_tree_2_4_8_16_32 #(
				.cmp_input_n(ATOMIC_C),
				.cmp_width(5),
				.simulation_delay(SIM_DELAY)
			)max_tree_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.cmp_in(max_cmp_tree_in),
				.cmp_in_vld(max_cmp_tree_in_valid),
				
				.cmp_out(max_cmp_tree_out),
				.cmp_out_vld()
			);
		end
		else
		begin
			reg[4:0] max_cmp_tree_in_d1; // 延迟1clk的比较输入
			reg[4:0] max_cmp_tree_in_d2; // 延迟2clk的比较输入
			reg max_cmp_tree_in_valid_d1; // 延迟1clk的输入有效指示
			reg max_cmp_tree_in_valid_d2; // 延迟2clk的输入有效指示
			
			assign max_cmp_tree_out = max_cmp_tree_in_d2;
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					{max_cmp_tree_in_valid_d2, max_cmp_tree_in_valid_d1} <= 2'b00;
				else if(aclken)
					{max_cmp_tree_in_valid_d2, max_cmp_tree_in_valid_d1} <= # SIM_DELAY 
						{max_cmp_tree_in_valid_d1, max_cmp_tree_in_valid};
			end
			
			always @(posedge aclk)
			begin
				if(aclken & max_cmp_tree_in_valid)
					max_cmp_tree_in_d1 <= # SIM_DELAY max_cmp_tree_in;
			end
			
			always @(posedge aclk)
			begin
				if(aclken & max_cmp_tree_in_valid_d1)
					max_cmp_tree_in_d2 <= # SIM_DELAY max_cmp_tree_in_d1;
			end
		end
	endgenerate
	
	genvar fp16_shifted_mtso_i;
	generate
		for(fp16_shifted_mtso_i = 0;fp16_shifted_mtso_i < ATOMIC_C;fp16_shifted_mtso_i = fp16_shifted_mtso_i + 1)
		begin:fp16_shifted_mtso_blk
			assign fp16_set[fp16_shifted_mtso_i] = 
				// 右移位数的范围: [0, 14] * 4
				{fp16_func - fp16_e_h3_f_add_w_d2[fp16_shifted_mtso_i], 2'b00};
			
			always @(posedge aclk)
			begin
				if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid_d3 & (~mac_in_ftm_masked_d3))
				begin
					if(fp16_set[fp16_shifted_mtso_i] >= 6'd32)
						fp16_shifted_mtso[fp16_shifted_mtso_i] <= # SIM_DELAY 29'd0;
					else
						fp16_shifted_mtso[fp16_shifted_mtso_i] <= # SIM_DELAY 
							// 算术右移0位
							(fp16_set[fp16_shifted_mtso_i] == 6'd0) ? fp16_signed_mtso[fp16_shifted_mtso_i]:
							// 算术右移4位
							(fp16_set[fp16_shifted_mtso_i] == 6'd4)  ? {
																	       {4{fp16_signed_mtso[fp16_shifted_mtso_i][28]}}, 
																		   fp16_signed_mtso[fp16_shifted_mtso_i][28:4]
																	   }:
							// 算术右移8位
							(fp16_set[fp16_shifted_mtso_i] == 6'd8)  ? {
																	       {8{fp16_signed_mtso[fp16_shifted_mtso_i][28]}}, 
																		   fp16_signed_mtso[fp16_shifted_mtso_i][28:8]
																	   }:
							// 算术右移12位
							(fp16_set[fp16_shifted_mtso_i] == 6'd12) ? {
																	       {12{fp16_signed_mtso[fp16_shifted_mtso_i][28]}}, 
																		   fp16_signed_mtso[fp16_shifted_mtso_i][28:12]
																	   }:
							// 算术右移16位
							(fp16_set[fp16_shifted_mtso_i] == 6'd16) ? {
																	       {16{fp16_signed_mtso[fp16_shifted_mtso_i][28]}}, 
																		   fp16_signed_mtso[fp16_shifted_mtso_i][28:16]
																	   }:
							// 算术右移20位
							(fp16_set[fp16_shifted_mtso_i] == 6'd20) ? {
																	       {20{fp16_signed_mtso[fp16_shifted_mtso_i][28]}}, 
																		   fp16_signed_mtso[fp16_shifted_mtso_i][28:20]
																	   }:
							// 算术右移24位
							(fp16_set[fp16_shifted_mtso_i] == 6'd24) ? {
																	       {24{fp16_signed_mtso[fp16_shifted_mtso_i][28]}}, 
																		   fp16_signed_mtso[fp16_shifted_mtso_i][28:24]
																	   }:
							// 算术右移28位
																	   {
																	       {28{fp16_signed_mtso[fp16_shifted_mtso_i][28]}}, 
																		   fp16_signed_mtso[fp16_shifted_mtso_i][28:28]
																	   };
				end
			end
		end
	endgenerate
	
	genvar fp16_chn_acumm_i;
	generate
		for(fp16_chn_acumm_i = 0;fp16_chn_acumm_i < ATOMIC_C;fp16_chn_acumm_i = fp16_chn_acumm_i + 1)
		begin:fp16_chn_acumm_blk
			assign add_tree_in_fp16_arr[fp16_chn_acumm_i] = 
				{{3{fp16_shifted_mtso[fp16_chn_acumm_i][28]}}, fp16_shifted_mtso[fp16_chn_acumm_i]};
		end
	endgenerate
	
	generate
		if(ATOMIC_C != 1)
		begin
			ram_based_shift_regs #(
				.data_width(8),
				.delay_n(
					(ATOMIC_C == 2)  ? 1:
					(ATOMIC_C == 4)  ? 2:
					(ATOMIC_C == 8)  ? 3:
					(ATOMIC_C == 16) ? 4:
					                   5
				),
				.shift_type("ff"),
				.en_output_register_init("false"),
				.simulation_delay(SIM_DELAY)
			)delay_for_fp16_func_u(
				.clk(aclk),
				.resetn(aresetn),
				
				.shift_in({2'b00, fp16_func_d1, 2'b00}),
				.ce(aclken & (calfmt == CAL_FMT_FP16)),
				.shift_out(mac_out_exp_fp16)
			);
		end
		else
		begin
			assign mac_out_exp_fp16 = {2'b00, fp16_func_d1, 2'b00};
		end
	endgenerate
	
	always @(posedge aclk)
	begin
		if(aclken & (calfmt == CAL_FMT_FP16) & mac_in_valid_d3 & (~mac_in_ftm_masked_d3))
			fp16_func_d1 <= # SIM_DELAY fp16_func;
	end
	
	/** 乘法器复用 **/
	assign mul_ce = 
		aclken & (
			((calfmt == CAL_FMT_FP16) & mul_ce_fp16) | 
			((calfmt == CAL_FMT_INT16) & mul_ce_int16)
		);
	
	genvar mul_reuse_i;
	generate
		for(mul_reuse_i = 0;mul_reuse_i < ATOMIC_C;mul_reuse_i = mul_reuse_i + 1)
		begin:mul_reuse_blk
			assign mul_op_a_arr[mul_reuse_i] = 
				(calfmt == CAL_FMT_FP16) ? 
					mul_op_a_fp16_arr[mul_reuse_i]:
					mul_op_a_int16_arr[mul_reuse_i];
			assign mul_op_b_arr[mul_reuse_i] = 
				(calfmt == CAL_FMT_FP16) ? 
					mul_op_b_fp16_arr[mul_reuse_i]:
					mul_op_b_int16_arr[mul_reuse_i];
		end
	endgenerate
	
	/** 加法树复用 **/
	assign add_tree_in_mask = 
		aclken & (
			((calfmt == CAL_FMT_FP16) & add_tree_in_fp16_mask) | 
			((calfmt == CAL_FMT_INT16) & add_tree_in_int16_mask)
		);
	assign add_tree_in_valid = 
		aclken & (
			((calfmt == CAL_FMT_FP16) & add_tree_in_fp16_valid) | 
			((calfmt == CAL_FMT_INT16) & add_tree_in_int16_valid)
		);
	
	genvar add_tree_reuse_i;
	generate
		for(add_tree_reuse_i = 0;add_tree_reuse_i < ATOMIC_C;add_tree_reuse_i = add_tree_reuse_i + 1)
		begin:add_tree_reuse_blk
			assign add_tree_in_arr[add_tree_reuse_i] = 
				(calfmt == CAL_FMT_FP16) ? 
					add_tree_in_fp16_arr[add_tree_reuse_i]:
					add_tree_in_int16_arr[add_tree_reuse_i];
		end
	endgenerate
	
	/** 结果输出 **/
	wire[INFO_ALONG_WIDTH-1:0] mac_out_info_along_fp16; // 计算FP16时的随路数据输出
	wire[INFO_ALONG_WIDTH-1:0] mac_out_info_along_int16; // 计算INT16时的随路数据输出
	
	assign mac_out_exp = 
		((calfmt == CAL_FMT_FP16) & (~mac_out_fp16_mask)) ? 
			mac_out_exp_fp16:
			8'd24;
	assign mac_out_frac = 
		(calfmt == CAL_FMT_FP16) ? 
			(mac_out_fp16_mask ? 40'd0:mac_out_frac_fp16):
			(mac_out_int16_mask ? 40'd0:mac_out_frac_int16);
	assign mac_out_info_along = 
		(calfmt == CAL_FMT_FP16) ? 
			mac_out_info_along_fp16:
			mac_out_info_along_int16;
	assign mac_out_valid = 
		aclken & (
			((calfmt == CAL_FMT_FP16) & mac_out_fp16_valid) | 
			((calfmt == CAL_FMT_INT16) & mac_out_int16_valid)
		);
	
	ram_based_shift_regs #(
		.data_width(INFO_ALONG_WIDTH),
		.delay_n(
			(ATOMIC_C == 1)  ? 1:
			(ATOMIC_C == 2)  ? 2:
			(ATOMIC_C == 4)  ? 3:
			(ATOMIC_C == 8)  ? 4:
			(ATOMIC_C == 16) ? 5:
							   6
		),
		.shift_type("ff"),
		.en_output_register_init("false"),
		.simulation_delay(SIM_DELAY)
	)delay_for_info_along_int16_u(
		.clk(aclk),
		.resetn(aresetn),
		
		.shift_in(mac_in_info_along),
		.ce(aclken),
		.shift_out(mac_out_info_along_int16)
	);
	
	ram_based_shift_regs #(
		.data_width(INFO_ALONG_WIDTH),
		.delay_n(3),
		.shift_type("ff"),
		.en_output_register_init("false"),
		.simulation_delay(SIM_DELAY)
	)delay_for_info_along_fp16_u(
		.clk(aclk),
		.resetn(aresetn),
		
		.shift_in(mac_out_info_along_int16),
		.ce(aclken & (calfmt == CAL_FMT_FP16)),
		.shift_out(mac_out_info_along_fp16)
	);
	
endmodule
