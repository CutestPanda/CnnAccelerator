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
本模块: 卷积乘加阵列

描述:
ATOMIC_K个卷积乘加单元

带有全局时钟使能

带有卷积核权重乒乓缓存, 可存储2个权重块

使用ATOMIC_K*ATOMIC_C个s16*s16乘法器实现特征图数据和卷积核权重相乘
使用ATOMIC_K个ATOMIC_C输入、32位加法器实现通道累加

 运算数据格式  |     计算时延
--------------------------------
   INT16   | 1 + log2(ATOMIC_C)
   FP16    | 4 + log2(ATOMIC_C)
   INT8    |      暂不支持

注意：
外部有符号乘法器的计算时延 = 1clk

协议:
无

作者: 陈家耀
日期: 2025/07/06
********************************************************************/


module conv_mac_array #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
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
	
	// 乘加阵列输入
	// [特征图]
	input wire[ATOMIC_C*16-1:0] array_i_ftm_sfc, // 特征图表面(数据)
	input wire[INFO_ALONG_WIDTH-1:0] array_i_ftm_info_along, // 随路数据
	input wire array_i_ftm_sfc_last, // 卷积核参数对应的最后1个特征图表面(标志)
	input wire array_i_ftm_sfc_vld, // 有效指示
	output wire array_i_kernal_buf_empty_n, // 卷积核权重缓存空(标志)
	// [卷积核]
	input wire[ATOMIC_C*16-1:0] array_i_kernal_sfc, // 卷积核表面(数据)
	input wire array_i_kernal_sfc_last, // 卷积核权重块对应的最后1个表面(标志)
	input wire[ATOMIC_K-1:0] array_i_kernal_sfc_id, // 卷积核表面在权重块中的独热码编号
	input wire array_i_kernal_sfc_vld, // 有效指示
	output wire array_i_kernal_buf_full_n, // 卷积核权重缓存满(标志)
	
	// 乘加阵列输出
	output wire[ATOMIC_K*48-1:0] array_o_res, // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	output wire[INFO_ALONG_WIDTH-1:0] array_o_res_info_along, // 随路数据
	output wire array_o_res_vld, // 有效指示
	
	// 外部有符号乘法器
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_a, // 操作数A
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_b, // 操作数B
	output wire[ATOMIC_K-1:0] mul_ce, // 计算使能
	input wire[ATOMIC_K*ATOMIC_C*32-1:0] mul_res // 计算结果
);
	
	/** 卷积核权重乒乓缓存 **/
	reg kernal_buf_wsel; // 写选择
	reg kernal_buf_rsel; // 读选择
	reg[1:0] kernal_buf_stored; // 存储有效标志
	reg[ATOMIC_K-1:0] kernal_buf_loaded_sfc_vec; // 已加载表面(标志向量)
	reg[ATOMIC_K*ATOMIC_C*16-1:0] kernal_buf_data[0:1]; // 缓存的卷积核权重(数据)
	
	assign array_i_kernal_buf_empty_n = kernal_buf_stored != 2'b00;
	assign array_i_kernal_buf_full_n = kernal_buf_stored != 2'b11;
	
	// 写选择
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_buf_wsel <= 1'b0;
		else if(aclken & array_i_kernal_sfc_vld & array_i_kernal_sfc_last & array_i_kernal_buf_full_n)
			kernal_buf_wsel <= # SIM_DELAY ~kernal_buf_wsel;
	end
	
	// 读选择
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_buf_rsel <= 1'b0;
		else if(aclken & array_i_ftm_sfc_vld & array_i_ftm_sfc_last & array_i_kernal_buf_empty_n)
			kernal_buf_rsel <= # SIM_DELAY ~kernal_buf_rsel;
	end
	
	// 存储有效标志
	genvar kernal_buf_stored_i;
	generate
		for(kernal_buf_stored_i = 0;kernal_buf_stored_i < 2;kernal_buf_stored_i = kernal_buf_stored_i + 1)
		begin:kernal_buf_stored_blk
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					kernal_buf_stored[kernal_buf_stored_i] <= 1'b0;
				else if(
					aclken & 
					// 断言: 写和读某个卷积核权重缓存不会同时发生
					(
						(
							array_i_kernal_sfc_vld & array_i_kernal_sfc_last & array_i_kernal_buf_full_n & 
							(kernal_buf_wsel == kernal_buf_stored_i)
						) | 
						(
							array_i_ftm_sfc_vld & array_i_ftm_sfc_last & array_i_kernal_buf_empty_n & 
							(kernal_buf_rsel == kernal_buf_stored_i)
						)
					)
				)
					kernal_buf_stored[kernal_buf_stored_i] <= # SIM_DELAY 
						array_i_kernal_sfc_vld & array_i_kernal_sfc_last & array_i_kernal_buf_full_n & 
						(kernal_buf_wsel == kernal_buf_stored_i);
			end
		end
	endgenerate
	
	genvar kernal_buf_sfc_i;
	generate
		for(kernal_buf_sfc_i = 0;kernal_buf_sfc_i < ATOMIC_K * 2;kernal_buf_sfc_i = kernal_buf_sfc_i + 1)
		begin:kernal_buf_sfc_blk
			// 已加载表面(标志)
			if(kernal_buf_sfc_i < ATOMIC_K)
			begin
				always @(posedge aclk or negedge aresetn)
				begin
					if(~aresetn)
						kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i] <= 1'b0;
					else if(
						aclken & 
						array_i_kernal_sfc_vld & array_i_kernal_buf_full_n & 
						(array_i_kernal_sfc_last | (~kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i]))
					)
						kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i] <= # SIM_DELAY 
							(~array_i_kernal_sfc_last) & array_i_kernal_sfc_id[kernal_buf_sfc_i];
				end
			end
			
			// 缓存的卷积核权重(数据)
			always @(posedge aclk)
			begin
				if(
					aclken & 
					array_i_kernal_sfc_vld & array_i_kernal_buf_full_n & 
					(kernal_buf_wsel == (kernal_buf_sfc_i/ATOMIC_K)) & 
					(
						(array_i_kernal_sfc_last & (~kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i%ATOMIC_K])) | 
						array_i_kernal_sfc_id[kernal_buf_sfc_i%ATOMIC_K]
					)
				)
					kernal_buf_data[kernal_buf_sfc_i/ATOMIC_K][((kernal_buf_sfc_i%ATOMIC_K)+1)*(ATOMIC_C*16)-1:
						(kernal_buf_sfc_i%ATOMIC_K)*(ATOMIC_C*16)] <= # SIM_DELAY 
							// 说明: 每加载完1个卷积核权重块, 对未加载的表面作填0处理
							{(ATOMIC_C*16){
								~(
									array_i_kernal_sfc_last & (~kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i%ATOMIC_K]) & 
									(~array_i_kernal_sfc_id[kernal_buf_sfc_i%ATOMIC_K])
								)
							}} & 
							array_i_kernal_sfc;
			end
		end
	endgenerate
	
	/** 乘加阵列 **/
	wire mac_in_valid; // 输入有效指示
	wire[ATOMIC_K*ATOMIC_C*16-1:0] kernal_buf_data_cur; // 当前选择的卷积核权重(数据)
	wire[ATOMIC_K-1:0] array_o_res_vld_vec; // 计算结果输出有效(指示向量)
	wire[INFO_ALONG_WIDTH-1:0] mac_out_info_along_arr[0:ATOMIC_K-1]; // 随路数据(数组)
	
	assign array_o_res_info_along = mac_out_info_along_arr[0];
	// 断言: array_o_res_vld_vec只能是{ATOMIC_K{1'b1}}或{ATOMIC_K{1'b0}}
	assign array_o_res_vld = array_o_res_vld_vec[0];
	
	assign kernal_buf_data_cur = kernal_buf_data[kernal_buf_rsel];
	assign mac_in_valid = array_i_ftm_sfc_vld & array_i_kernal_buf_empty_n;
	
	genvar mac_cell_i;
	generate
		for(mac_cell_i = 0;mac_cell_i < ATOMIC_K;mac_cell_i = mac_cell_i + 1)
		begin:mac_array_blk
			conv_mac_cell #(
				.ATOMIC_C(ATOMIC_C),
				.EN_SMALL_FP16(EN_SMALL_FP16),
				.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
				.SIM_DELAY(SIM_DELAY)
			)mac_cell_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.calfmt(calfmt),
				
				.mac_in_ftm(array_i_ftm_sfc),
				.mac_in_wgt(kernal_buf_data_cur[(mac_cell_i+1)*(ATOMIC_C*16)-1:mac_cell_i*(ATOMIC_C*16)]),
				.mac_in_info_along(array_i_ftm_info_along),
				.mac_in_valid(mac_in_valid),
				
				.mac_out_exp(array_o_res[mac_cell_i*48+47:mac_cell_i*48+40]),
				.mac_out_frac(array_o_res[mac_cell_i*48+39:mac_cell_i*48+0]),
				.mac_out_info_along(mac_out_info_along_arr[mac_cell_i]),
				.mac_out_valid(array_o_res_vld_vec[mac_cell_i]),
				
				.mul_op_a(mul_op_a[(mac_cell_i+1)*(ATOMIC_C*16)-1:mac_cell_i*(ATOMIC_C*16)]),
				.mul_op_b(mul_op_b[(mac_cell_i+1)*(ATOMIC_C*16)-1:mac_cell_i*(ATOMIC_C*16)]),
				.mul_ce(mul_ce[mac_cell_i]),
				.mul_res(mul_res[(mac_cell_i+1)*(ATOMIC_C*32)-1:mac_cell_i*(ATOMIC_C*32)])
			);
		end
	endgenerate
	
endmodule
