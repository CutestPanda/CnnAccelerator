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
本模块: 加法树

描述:
n输入流水有符号加法树

带有全局时钟使能

   加法输入数量   流水线级数   有效的输出位宽
-------------------------------------------------
        2             1          add_width+1
		4             2          add_width+2
		8             3          add_width+3
		16            4          add_width+4
		32            5          add_width+5

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/03/24
********************************************************************/


module add_tree_2_4_8_16_32 #(
    parameter integer add_input_n = 16, // 加法输入数量(2 | 4 | 8 | 16 | 32)
	parameter integer add_width = 32, // 加法位宽
	parameter USE_DSP_MACRO = "false", // 是否使用DSP单元作为加法器
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 加法输入
	input wire[add_input_n*add_width-1:0] add_in,
	input wire add_in_vld,
	
	// 加法输出
	output wire signed[add_width+5-1:0] add_out,
	output wire add_out_vld
);
    
	/** 常量 **/
	localparam USE_DSP_ATRB = (USE_DSP_MACRO == "true") ? "yes":"no";
	
    /** 第1级流水线 **/
	wire signed[add_width-1:0] add_s0_in[0:31];
	wire add_s0_in_vld;
	(* use_dsp=USE_DSP_ATRB *)reg signed[add_width+1-1:0] add_s0_out[0:15];
	reg add_s0_out_vld;
	
	genvar add_s0_i;
	generate
		for(add_s0_i = 0;add_s0_i < 16;add_s0_i = add_s0_i + 1)
		begin:add_s0_blk
			always @(posedge aclk)
			begin
				if(aclken & add_s0_in_vld)
					add_s0_out[add_s0_i] <= # simulation_delay add_s0_in[add_s0_i*2] + add_s0_in[add_s0_i*2+1];
			end
		end
	endgenerate
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			add_s0_out_vld <= 1'b0;
		else if(aclken)
			add_s0_out_vld <= # simulation_delay add_s0_in_vld;
	end
	
	/** 第2级流水线 **/
	wire signed[add_width+1-1:0] add_s1_in[0:15];
	wire add_s1_in_vld;
	(* use_dsp=USE_DSP_ATRB *)reg signed[add_width+2-1:0] add_s1_out[0:7];
	reg add_s1_out_vld;
	
	genvar add_s1_i;
	generate
		for(add_s1_i = 0;add_s1_i < 8;add_s1_i = add_s1_i + 1)
		begin:add_s1_blk
			always @(posedge aclk)
			begin
				if(aclken & add_s1_in_vld)
					add_s1_out[add_s1_i] <= # simulation_delay add_s1_in[add_s1_i*2] + add_s1_in[add_s1_i*2+1];
			end
		end
	endgenerate
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			add_s1_out_vld <= 1'b0;
		else if(aclken)
			add_s1_out_vld <= # simulation_delay add_s1_in_vld;
	end
	
	/** 第3级流水线 **/
	wire signed[add_width+2-1:0] add_s2_in[0:7];
	wire add_s2_in_vld;
	(* use_dsp=USE_DSP_ATRB *)reg signed[add_width+3-1:0] add_s2_out[0:3];
	reg add_s2_out_vld;
	
	genvar add_s2_i;
	generate
		for(add_s2_i = 0;add_s2_i < 4;add_s2_i = add_s2_i + 1)
		begin:add_s2_blk
			always @(posedge aclk)
			begin
				if(aclken & add_s2_in_vld)
					add_s2_out[add_s2_i] <= # simulation_delay add_s2_in[add_s2_i*2] + add_s2_in[add_s2_i*2+1];
			end
		end
	endgenerate
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			add_s2_out_vld <= 1'b0;
		else if(aclken)
			add_s2_out_vld <= # simulation_delay add_s2_in_vld;
	end
	
	/** 第4级流水线 **/
	wire signed[add_width+3-1:0] add_s3_in[0:3];
	wire add_s3_in_vld;
	(* use_dsp=USE_DSP_ATRB *)reg signed[add_width+4-1:0] add_s3_out[0:1];
	reg add_s3_out_vld;
	
	genvar add_s3_i;
	generate
		for(add_s3_i = 0;add_s3_i < 2;add_s3_i = add_s3_i + 1)
		begin:add_s3_blk
			always @(posedge aclk)
			begin
				if(aclken & add_s3_in_vld)
					add_s3_out[add_s3_i] <= # simulation_delay add_s3_in[add_s3_i*2] + add_s3_in[add_s3_i*2+1];
			end
		end
	endgenerate
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			add_s3_out_vld <= 1'b0;
		else if(aclken)
			add_s3_out_vld <= # simulation_delay add_s3_in_vld;
	end
	
	/** 第5级流水线 **/
	wire signed[add_width+4-1:0] add_s4_in[0:1];
	wire add_s4_in_vld;
	(* use_dsp=USE_DSP_ATRB *)reg signed[add_width+5-1:0] add_s4_out;
	reg add_s4_out_vld;
	
	assign add_out = add_s4_out;
	assign add_out_vld = add_s4_out_vld;
	
	always @(posedge aclk)
	begin
		if(aclken & add_s4_in_vld)
			add_s4_out <= # simulation_delay add_s4_in[0] + add_s4_in[1];
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			add_s4_out_vld <= 1'b0;
		else if(aclken)
			add_s4_out_vld <= # simulation_delay add_s4_in_vld;
	end
	
	/** 加法树输入 **/
	genvar add_s0_in_i;
	generate
		for(add_s0_in_i = 0;add_s0_in_i < 32;add_s0_in_i = add_s0_in_i + 1)
		begin:add_s0_in_blk
			if(add_input_n == 32)
				assign add_s0_in[add_s0_in_i] = $signed(add_in[(add_s0_in_i+1)*add_width-1:add_s0_in_i*add_width]);
			else
				assign add_s0_in[add_s0_in_i] = {add_width{1'bx}};
		end
	endgenerate
	
	genvar add_s1_in_i;
	generate
		for(add_s1_in_i = 0;add_s1_in_i < 16;add_s1_in_i = add_s1_in_i + 1)
		begin:add_s1_in_blk
			if(add_input_n == 16)
				assign add_s1_in[add_s1_in_i] = $signed(add_in[(add_s1_in_i+1)*add_width-1:add_s1_in_i*add_width]);
			else
				assign add_s1_in[add_s1_in_i] = add_s0_out[add_s1_in_i];
		end
	endgenerate
	
	genvar add_s2_in_i;
	generate
		for(add_s2_in_i = 0;add_s2_in_i < 8;add_s2_in_i = add_s2_in_i + 1)
		begin:add_s2_in_blk
			if(add_input_n == 8)
				assign add_s2_in[add_s2_in_i] = $signed(add_in[(add_s2_in_i+1)*add_width-1:add_s2_in_i*add_width]);
			else
				assign add_s2_in[add_s2_in_i] = add_s1_out[add_s2_in_i];
		end
	endgenerate
	
	genvar add_s3_in_i;
	generate
		for(add_s3_in_i = 0;add_s3_in_i < 4;add_s3_in_i = add_s3_in_i + 1)
		begin:add_s3_in_blk
			if(add_input_n == 4)
				assign add_s3_in[add_s3_in_i] = $signed(add_in[(add_s3_in_i+1)*add_width-1:add_s3_in_i*add_width]);
			else
				assign add_s3_in[add_s3_in_i] = add_s2_out[add_s3_in_i];
		end
	endgenerate
	
	genvar add_s4_in_i;
	generate
		for(add_s4_in_i = 0;add_s4_in_i < 2;add_s4_in_i = add_s4_in_i + 1)
		begin:add_s4_in_blk
			if(add_input_n == 2)
				assign add_s4_in[add_s4_in_i] = $signed(add_in[(add_s4_in_i+1)*add_width-1:add_s4_in_i*add_width]);
			else
				assign add_s4_in[add_s4_in_i] = add_s3_out[add_s4_in_i];
		end
	endgenerate
	
	assign add_s0_in_vld = (add_input_n == 32) ? add_in_vld:1'b0;
	assign add_s1_in_vld = (add_input_n == 16) ? add_in_vld:add_s0_out_vld;
	assign add_s2_in_vld = (add_input_n == 8) ? add_in_vld:add_s1_out_vld;
	assign add_s3_in_vld = (add_input_n == 4) ? add_in_vld:add_s2_out_vld;
	assign add_s4_in_vld = (add_input_n == 2) ? add_in_vld:add_s3_out_vld;
	
endmodule
