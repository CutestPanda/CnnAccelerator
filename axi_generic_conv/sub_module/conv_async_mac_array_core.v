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
本模块: (异步)卷积乘加阵列计算核心

描述:
输入异步fifo -> 卷积乘加阵列 -> 输出异步fifo

输入端作跨时钟域并串转换, 输出端作跨时钟域串并转换, 乘加单元数量为ATOMIC_K/MAC_ARRAY_CLK_RATE

注意：
核并行数(ATOMIC_K)必须能被计算核心时钟倍率(MAC_ARRAY_CLK_RATE)整除

协议:
无

作者: 陈家耀
日期: 2025/12/30
********************************************************************/


module conv_async_mac_array_core #(
	parameter integer MAC_ARRAY_CLK_RATE = 1, // 计算核心时钟倍率(>=1)
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽(必须>=1)
	parameter EN_SMALL_FP16 = "true", // 是否处理极小FP16
	parameter USE_DSP_MACRO_FOR_ADD_TREE = "false", // 是否使用DSP单元作为加法器
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	// 计算核心时钟和复位
	input wire mac_array_aclk,
	input wire mac_array_aresetn,
	input wire mac_array_aclken,
	
	// 使能信号
	input wire en_mac_array, // 使能乘加阵列
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	
	// 计算核心输入数据流
	input wire[ATOMIC_C*16-1:0] array_i_ftm_sfc_data, // 特征图表面(数据)
	input wire[ATOMIC_K*ATOMIC_C*16-1:0] array_i_kernal_wgtblk_data, // 卷积核权重块(数据)
	input wire array_i_ftm_sfc_masked, // 特征图表面(无效标志)
	input wire[ATOMIC_K-1:0] array_i_kernal_mask, // 卷积核权重(掩码)
	input wire[INFO_ALONG_WIDTH-1:0] array_i_info_along, // 随路数据
	input wire array_i_vld,
	output wire array_i_rdy,
	
	// 计算核心输出数据流
	output wire[ATOMIC_K*48-1:0] array_o_res, // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	output wire[INFO_ALONG_WIDTH-1:0] array_o_info_along, // 随路数据
	output wire array_o_vld,
	input wire array_o_rdy,
	
	// 外部有符号乘法器
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_a, // 操作数A
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_b, // 操作数B
	output wire[ATOMIC_K-1:0] mul_ce, // 计算使能
	input wire[ATOMIC_K*ATOMIC_C*32-1:0] mul_res // 计算结果
);
	
	// 计算log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
	
	/** 使能信号和运行时参数 **/
	reg en_mac_array_d1;
	reg en_mac_array_d2;
	reg en_mac_array_d3;
	reg en_mac_array_d4;
	wire on_en_mac_array_posedge;
	
	assign on_en_mac_array_posedge = en_mac_array_d3 & (~en_mac_array_d4);
	
	// 跨时钟域: ... -> en_mac_array_d1
	always @(posedge mac_array_aclk or negedge mac_array_aresetn)
	begin
		if(~mac_array_aresetn)
			{en_mac_array_d4, en_mac_array_d3, en_mac_array_d2, en_mac_array_d1} <= 4'b0000;
		else if(mac_array_aclken)
			{en_mac_array_d4, en_mac_array_d3, en_mac_array_d2, en_mac_array_d1} <= # SIM_DELAY 
				{en_mac_array_d3, en_mac_array_d2, en_mac_array_d1, en_mac_array};
	end
	
	/** 输入异步fifo **/
	// [fifo写端口]
	wire in_async_fifo_wen;
	wire in_async_fifo_full_n;
	wire[ATOMIC_C*16-1:0] in_async_fifo_din_ftm_sfc_data; // 特征图表面(数据)
	wire[ATOMIC_K*ATOMIC_C*16-1:0] in_async_fifo_din_kernal_wgtblk_data; // 卷积核权重块(数据)
	wire in_async_fifo_din_ftm_sfc_masked; // 特征图表面(无效标志)
	wire[ATOMIC_K-1:0] in_async_fifo_din_kernal_mask; // 卷积核权重(掩码)
	wire[INFO_ALONG_WIDTH-1:0] in_async_fifo_din_info_along; // 随路数据
	// [fifo读端口]
	wire in_async_fifo_ren;
	wire in_async_fifo_empty_n;
	wire[ATOMIC_C*16-1:0] in_async_fifo_dout_ftm_sfc_data; // 特征图表面(数据)
	wire[ATOMIC_K*ATOMIC_C*16-1:0] in_async_fifo_dout_kernal_wgtblk_data; // 卷积核权重块(数据)
	wire in_async_fifo_dout_ftm_sfc_masked; // 特征图表面(无效标志)
	wire[ATOMIC_K-1:0] in_async_fifo_dout_kernal_mask; // 卷积核权重(掩码)
	wire[INFO_ALONG_WIDTH-1:0] in_async_fifo_dout_info_along; // 随路数据
	
	assign array_i_rdy = aclken & in_async_fifo_full_n;
	
	assign in_async_fifo_wen = aclken & array_i_vld;
	assign in_async_fifo_din_ftm_sfc_data = array_i_ftm_sfc_data;
	assign in_async_fifo_din_kernal_wgtblk_data = array_i_kernal_wgtblk_data;
	assign in_async_fifo_din_ftm_sfc_masked = array_i_ftm_sfc_masked;
	assign in_async_fifo_din_kernal_mask = array_i_kernal_mask;
	assign in_async_fifo_din_info_along = array_i_info_along;
	
	/*
	跨时钟域:
		in_async_fifo_u/async_fifo_u/rptr_gray_at_r[*] -> in_async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]
		in_async_fifo_u/async_fifo_u/wptr_gray_at_w[*] -> in_async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]
		... -> in_async_fifo_u/axis_reg_slice_u/axis_reg_slice_core_u/fwd_payload[*]
	*/
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.ram_type("lutram"),
		.depth(32),
		.data_width(ATOMIC_C*16 + ATOMIC_K*ATOMIC_C*16 + 1 + ATOMIC_K + INFO_ALONG_WIDTH),
		.simulation_delay(SIM_DELAY)
	)in_async_fifo_u(
		.clk_wt(aclk),
		.rst_n_wt(aresetn),
		.clk_rd(mac_array_aclk),
		.rst_n_rd(mac_array_aresetn),
		
		.fifo_wen(in_async_fifo_wen),
		.fifo_full(),
		.fifo_full_n(in_async_fifo_full_n),
		.fifo_din(
			{
				in_async_fifo_din_ftm_sfc_data,
				in_async_fifo_din_kernal_wgtblk_data,
				in_async_fifo_din_ftm_sfc_masked,
				in_async_fifo_din_kernal_mask,
				in_async_fifo_din_info_along
			}
		),
		.data_cnt_wt(),
		.fifo_ren(in_async_fifo_ren),
		.fifo_empty(),
		.fifo_empty_n(in_async_fifo_empty_n),
		.fifo_dout(
			{
				in_async_fifo_dout_ftm_sfc_data,
				in_async_fifo_dout_kernal_wgtblk_data,
				in_async_fifo_dout_ftm_sfc_masked,
				in_async_fifo_dout_kernal_mask,
				in_async_fifo_dout_info_along
			}
		),
		.data_cnt_rd()
	);
	
	/** 卷积乘加阵列 **/
	// [轮次控制]
	reg[clogb2(MAC_ARRAY_CLK_RATE-1):0] mac_round_cnt; // 轮次计数器
	wire to_pass_cal_data; // 允许放行计算数据(标志)
	// [阵列输入]
	reg[ATOMIC_C*16-1:0] mac_in_ftm; // 特征图数据
	reg[(ATOMIC_K/MAC_ARRAY_CLK_RATE)*ATOMIC_C*16-1:0] mac_in_wgt; // 卷积核权重
	reg[ATOMIC_K/MAC_ARRAY_CLK_RATE-1:0] mac_in_kernal_mask; // 权重表面掩码
	reg mac_in_ftm_masked; // 特征图数据(无效标志)
	reg[INFO_ALONG_WIDTH-1:0] mac_in_info_along; // 随路数据
	reg mac_in_valid; // 阵列输入有效指示
	// [阵列输出]
	wire[(ATOMIC_K/MAC_ARRAY_CLK_RATE)*48-1:0] mac_out_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[INFO_ALONG_WIDTH-1:0] mac_out_info_along[0:ATOMIC_K/MAC_ARRAY_CLK_RATE-1]; // 随路数据
	wire[ATOMIC_K/MAC_ARRAY_CLK_RATE-1:0] mac_out_valid; // 输出有效指示
	
	assign in_async_fifo_ren = 
		mac_array_aclken & en_mac_array_d4 & 
		to_pass_cal_data & (mac_round_cnt == (MAC_ARRAY_CLK_RATE - 1));
	
	// 轮次计数器
	always @(posedge mac_array_aclk)
	begin
		if(~en_mac_array_d4)
			mac_round_cnt <= # SIM_DELAY 0;
		else if(mac_array_aclken & to_pass_cal_data & in_async_fifo_empty_n)
			mac_round_cnt <= # SIM_DELAY 
				(mac_round_cnt == (MAC_ARRAY_CLK_RATE - 1)) ? 
					0:
					(mac_round_cnt + 1);
	end
	
	// 特征图数据, 卷积核权重, 权重表面掩码, 特征图数据(无效标志), 随路数据
	always @(posedge mac_array_aclk)
	begin
		if(mac_array_aclken & en_mac_array_d4 & to_pass_cal_data & in_async_fifo_empty_n)
		begin
			mac_in_ftm <= # SIM_DELAY in_async_fifo_dout_ftm_sfc_data;
			mac_in_wgt <= # SIM_DELAY 
				in_async_fifo_dout_kernal_wgtblk_data >> (ATOMIC_K*ATOMIC_C*16/MAC_ARRAY_CLK_RATE * mac_round_cnt);
			mac_in_kernal_mask <= # SIM_DELAY 
				in_async_fifo_dout_kernal_mask >> (ATOMIC_K/MAC_ARRAY_CLK_RATE * mac_round_cnt);
			mac_in_ftm_masked <= # SIM_DELAY in_async_fifo_dout_ftm_sfc_masked;
			mac_in_info_along <= # SIM_DELAY in_async_fifo_dout_info_along;
		end
	end
	
	// 阵列输入有效指示
	always @(posedge mac_array_aclk or negedge mac_array_aresetn)
	begin
		if(~mac_array_aresetn)
			mac_in_valid <= 1'b0;
		else if(mac_array_aclken)
			mac_in_valid <= # SIM_DELAY en_mac_array_d4 & to_pass_cal_data & in_async_fifo_empty_n;
	end
	
	genvar mac_cell_i;
	generate
		for(mac_cell_i = 0;mac_cell_i < ATOMIC_K;mac_cell_i = mac_cell_i + 1)
		begin:mac_cell_blk
			if(mac_cell_i < ATOMIC_K/MAC_ARRAY_CLK_RATE)
			begin
				conv_mac_cell #(
					.ATOMIC_C(ATOMIC_C),
					.EN_SMALL_FP16(EN_SMALL_FP16),
					.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
					.USE_DSP_MACRO_FOR_ADD_TREE(USE_DSP_MACRO_FOR_ADD_TREE),
					.SIM_DELAY(SIM_DELAY)
				)conv_mac_cell_u(
					.aclk(mac_array_aclk),
					.aresetn(mac_array_aresetn),
					.aclken(mac_array_aclken),
					
					.calfmt(calfmt),
					
					.mac_in_ftm(mac_in_ftm),
					.mac_in_wgt(mac_in_wgt[(mac_cell_i+1)*ATOMIC_C*16-1:mac_cell_i*ATOMIC_C*16]),
					.mac_in_ftm_masked(mac_in_ftm_masked | (~mac_in_kernal_mask[mac_cell_i])),
					.mac_in_info_along(mac_in_info_along),
					.mac_in_valid(mac_in_valid & ((mac_cell_i == 0) | mac_in_kernal_mask[mac_cell_i])),
					
					.mac_out_exp(mac_out_res[48*mac_cell_i+47:48*mac_cell_i+40]),
					.mac_out_frac(mac_out_res[48*mac_cell_i+39:48*mac_cell_i+0]),
					.mac_out_info_along(mac_out_info_along[mac_cell_i]),
					.mac_out_valid(mac_out_valid[mac_cell_i]),
					
					.mul_op_a(mul_op_a[ATOMIC_C*16*(mac_cell_i+1)-1:ATOMIC_C*16*mac_cell_i]),
					.mul_op_b(mul_op_b[ATOMIC_C*16*(mac_cell_i+1)-1:ATOMIC_C*16*mac_cell_i]),
					.mul_ce(mul_ce[mac_cell_i]),
					.mul_res(mul_res[ATOMIC_C*32*(mac_cell_i+1)-1:ATOMIC_C*32*mac_cell_i])
				);
			end
			else
			begin
				assign mul_op_a[ATOMIC_C*16*(mac_cell_i+1)-1:ATOMIC_C*16*mac_cell_i] = {(ATOMIC_C*16){1'bx}};
				assign mul_op_b[ATOMIC_C*16*(mac_cell_i+1)-1:ATOMIC_C*16*mac_cell_i] = {(ATOMIC_C*16){1'bx}};
				assign mul_ce[mac_cell_i] = 1'b0;
			end
		end
	endgenerate
	
	/** 输出异步fifo **/
	// [输出轮次控制]
	reg[MAC_ARRAY_CLK_RATE-1:0] mac_o_round_cnt; // 输出轮次计数器
	reg[ATOMIC_K*48-1:0] mac_res_saved; // 暂存的计算结果
	// [fifo写端口]
	wire out_async_fifo_wen;
	wire out_async_fifo_full_n;
	wire[5:0] out_async_fifo_data_cnt_wt;
	wire[ATOMIC_K*48-1:0] out_async_fifo_din_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[INFO_ALONG_WIDTH-1:0] out_async_fifo_din_info_along; // 随路数据
	// [fifo读端口]
	wire out_async_fifo_ren;
	wire out_async_fifo_empty_n;
	wire[ATOMIC_K*48-1:0] out_async_fifo_dout_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[INFO_ALONG_WIDTH-1:0] out_async_fifo_dout_info_along; // 随路数据
	
	assign array_o_res = out_async_fifo_dout_res;
	assign array_o_info_along = out_async_fifo_dout_info_along;
	assign array_o_vld = aclken & out_async_fifo_empty_n;
	
	assign out_async_fifo_ren = aclken & array_o_rdy;
	
	assign to_pass_cal_data = out_async_fifo_data_cnt_wt < (32 - 16);
	
	assign out_async_fifo_wen = 
		mac_array_aclken & en_mac_array_d4 & mac_out_valid[0] & mac_o_round_cnt[MAC_ARRAY_CLK_RATE-1];
	assign out_async_fifo_din_res = 
		{mac_out_res, mac_res_saved[ATOMIC_K*48-ATOMIC_K*48/MAC_ARRAY_CLK_RATE-1:0]};
	assign out_async_fifo_din_info_along = mac_out_info_along[0];
	
	// 输出轮次计数器
	always @(posedge mac_array_aclk)
	begin
		if(~en_mac_array_d4)
			mac_o_round_cnt <= 1;
		else if(mac_array_aclken & mac_out_valid[0])
			mac_o_round_cnt <= # SIM_DELAY (mac_o_round_cnt << 1) | (mac_o_round_cnt >> (MAC_ARRAY_CLK_RATE-1));
	end
	
	// 暂存的计算结果
	genvar mac_res_saved_i;
	generate
		for(mac_res_saved_i = 0;mac_res_saved_i < MAC_ARRAY_CLK_RATE;mac_res_saved_i = mac_res_saved_i + 1)
		begin:mac_res_saved_blk
			always @(posedge mac_array_aclk)
			begin
				if(mac_array_aclken & en_mac_array_d4 & mac_out_valid[0] & mac_o_round_cnt[mac_res_saved_i])
					mac_res_saved[(mac_res_saved_i+1)*(ATOMIC_K*48/MAC_ARRAY_CLK_RATE)-1:mac_res_saved_i*(ATOMIC_K*48/MAC_ARRAY_CLK_RATE)] <= # SIM_DELAY 
						mac_out_res;
			end
		end
	endgenerate
	
	/*
	跨时钟域:
		out_async_fifo_u/async_fifo_u/rptr_gray_at_r[*] -> out_async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]
		out_async_fifo_u/async_fifo_u/wptr_gray_at_w[*] -> out_async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]
		... -> out_async_fifo_u/axis_reg_slice_u/axis_reg_slice_core_u/fwd_payload[*]
	*/
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.ram_type("lutram"),
		.depth(32),
		.data_width(ATOMIC_K*48 + INFO_ALONG_WIDTH),
		.simulation_delay(SIM_DELAY)
	)out_async_fifo_u(
		.clk_wt(mac_array_aclk),
		.rst_n_wt(mac_array_aresetn),
		.clk_rd(aclk),
		.rst_n_rd(aresetn),
		
		.fifo_wen(out_async_fifo_wen),
		.fifo_full(),
		.fifo_full_n(out_async_fifo_full_n),
		.fifo_din(
			{
				out_async_fifo_din_res,
				out_async_fifo_din_info_along
			}
		),
		.data_cnt_wt(out_async_fifo_data_cnt_wt),
		.fifo_ren(out_async_fifo_ren),
		.fifo_empty(),
		.fifo_empty_n(out_async_fifo_empty_n),
		.fifo_dout(
			{
				out_async_fifo_dout_res,
				out_async_fifo_dout_info_along
			}
		),
		.data_cnt_rd()
	);
	
endmodule
