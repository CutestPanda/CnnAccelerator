`timescale 1ns / 1ps
/********************************************************************
本模块: 乘法器DSP单元

描述:
有符号乘加器: mul_out = op_a * op_b
时延 = 1clk

注意：
对于xilinx系列FPGA, 1个DSP单元可以完成计算:
	P[42:0] = A[24:0] * B[17:0]

协议:
无

作者: 陈家耀
日期: 2024/11/06
********************************************************************/


module mul #(
	parameter integer op_a_width = 16, // 操作数A位宽(含1位符号位)
	parameter integer op_b_width = 16, // 操作数B位宽(含1位符号位)
	parameter integer output_width = 32, // 输出位宽(含1位符号位)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	
	// 使能
	input wire ce_s0_mul,
	
	// 乘加器输入
	input wire signed[op_a_width-1:0] op_a,
	input wire signed[op_b_width-1:0] op_b,
	
	// 乘加器输出
	output wire signed[output_width-1:0] res
);
    
	wire signed[op_a_width-1:0] mul_in1;
	wire signed[op_b_width-1:0] mul_in2;
	reg signed[(op_a_width+op_b_width)-1:0] mul_res;
	
	assign res = mul_res;
	
	assign mul_in1 = op_a;
	assign mul_in2 = op_b;
	
	always @(posedge clk)
	begin
		if(ce_s0_mul)
			mul_res <= # simulation_delay mul_in1 * mul_in2;
	end
	
endmodule
