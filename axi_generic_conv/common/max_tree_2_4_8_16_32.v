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
本模块: 最大值求解树

描述:
n输入流水有符号最大值求解树

带有全局时钟使能

2级比较流水线 -> 
    第1级: 完成8输入比较
    第2级: 完成4输入比较

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/03/25
********************************************************************/


module max_tree_2_4_8_16_32 #(
    parameter integer cmp_input_n = 4, // 比较输入数量(2 | 4 | 8 | 16 | 32)
	parameter integer cmp_width = 4, // 比较位宽
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 比较输入
	input wire[cmp_input_n*cmp_width-1:0] cmp_in,
	input wire cmp_in_vld,
	
	// 比较输出
	output wire signed[cmp_width-1:0] cmp_out,
	output wire cmp_out_vld
);
    
    /** 比较输入 **/
	wire signed[cmp_width-1:0] cmp_in_arr[0:31];
	wire[31:0] cmp_in_mask;
	
	genvar cmp_in_i;
	generate
		for(cmp_in_i = 0;cmp_in_i < 32;cmp_in_i = cmp_in_i + 1)
		begin:cmp_in_blk
			assign cmp_in_arr[cmp_in_i] = 
				((cmp_in_i % (32/cmp_input_n)) == 0) ? 
					cmp_in[((cmp_in_i/(32/cmp_input_n))+1)*cmp_width-1:(cmp_in_i/(32/cmp_input_n))*cmp_width]:
					{1'b1, {(cmp_width-1){1'b0}}};
			assign cmp_in_mask[cmp_in_i] = 
				((cmp_in_i % (32/cmp_input_n)) == 0) ? 
					1'b1:
					1'b0;
		end
	endgenerate
	
	/** 第1~3级比较 **/
	wire signed[cmp_width-1:0] cmp_s1_res[0:15];
	wire[15:0] cmp_s1_mask;
	wire signed[cmp_width-1:0] cmp_s2_res[0:7];
	wire[7:0] cmp_s2_mask;
	reg signed[cmp_width-1:0] cmp_s3_res[0:3];
	reg[3:0] cmp_s3_mask;
	reg cmp_in_vld_d1;
	
	genvar cmp_s1_i;
	generate
		for(cmp_s1_i = 0;cmp_s1_i < 16;cmp_s1_i = cmp_s1_i + 1)
		begin:cmp_s1_blk
			assign cmp_s1_res[cmp_s1_i] = 
				(cmp_in_mask[cmp_s1_i*2] & (cmp_in_arr[cmp_s1_i*2] > cmp_in_arr[cmp_s1_i*2+1])) ? 
					cmp_in_arr[cmp_s1_i*2]:
					cmp_in_arr[cmp_s1_i*2+1];
			assign cmp_s1_mask[cmp_s1_i] = 
				cmp_in_mask[cmp_s1_i*2] | cmp_in_mask[cmp_s1_i*2+1];
		end
	endgenerate
	
	genvar cmp_s2_i;
	generate
		for(cmp_s2_i = 0;cmp_s2_i < 8;cmp_s2_i = cmp_s2_i + 1)
		begin:cmp_s2_blk
			assign cmp_s2_res[cmp_s2_i] = 
				(cmp_s1_mask[cmp_s2_i*2] & (cmp_s1_res[cmp_s2_i*2] > cmp_s1_res[cmp_s2_i*2+1])) ? 
					cmp_s1_res[cmp_s2_i*2]:
					cmp_s1_res[cmp_s2_i*2+1];
			assign cmp_s2_mask[cmp_s2_i] = 
				cmp_s1_mask[cmp_s2_i*2] | cmp_s1_mask[cmp_s2_i*2+1];
		end
	endgenerate
	
	genvar cmp_s3_i;
	generate
		for(cmp_s3_i = 0;cmp_s3_i < 4;cmp_s3_i = cmp_s3_i + 1)
		begin:cmp_s3_blk
			always @(posedge aclk)
			begin
				if(aclken & cmp_in_vld)
				begin
					cmp_s3_res[cmp_s3_i] <= # simulation_delay 
						(cmp_s2_mask[cmp_s3_i*2] & (cmp_s2_res[cmp_s3_i*2] > cmp_s2_res[cmp_s3_i*2+1])) ? 
							cmp_s2_res[cmp_s3_i*2]:
							cmp_s2_res[cmp_s3_i*2+1];
					
					cmp_s3_mask[cmp_s3_i] <= # simulation_delay 
						cmp_s2_mask[cmp_s3_i*2] | cmp_s2_mask[cmp_s3_i*2+1];
				end
			end
		end
	endgenerate
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cmp_in_vld_d1 <= 1'b0;
		else if(aclken)
			cmp_in_vld_d1 <= # simulation_delay cmp_in_vld;
	end
	
	/** 第4~5级比较 **/
	wire signed[cmp_width-1:0] cmp_s4_res[0:1];
	wire[1:0] cmp_s4_mask;
	reg signed[cmp_width-1:0] cmp_s5_res;
	reg cmp_in_vld_d2;
	
	assign cmp_s4_res[0] = 
		(cmp_s3_mask[0] & (cmp_s3_res[0] > cmp_s3_res[1])) ? 
			cmp_s3_res[0]:
			cmp_s3_res[1];
	assign cmp_s4_res[1] = 
		(cmp_s3_mask[2] & (cmp_s3_res[2] > cmp_s3_res[3])) ? 
			cmp_s3_res[2]:
			cmp_s3_res[3];
	
	assign cmp_s4_mask[0] = cmp_s3_mask[0] | cmp_s3_mask[1];
	assign cmp_s4_mask[1] = cmp_s3_mask[2] | cmp_s3_mask[3];
	
	always @(posedge aclk)
	begin
		if(aclken & cmp_in_vld_d1)
			cmp_s5_res <= # simulation_delay 
				(cmp_s4_mask[0] & (cmp_s4_res[0] > cmp_s4_res[1])) ? 
					cmp_s4_res[0]:
					cmp_s4_res[1];
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cmp_in_vld_d2 <= 1'b0;
		else if(aclken)
			cmp_in_vld_d2 <= # simulation_delay cmp_in_vld_d1;
	end
	
	/** 比较输出 **/
	assign cmp_out = cmp_s5_res;
	assign cmp_out_vld = cmp_in_vld_d2;
	
endmodule
