`timescale 1ns / 1ps
/********************************************************************
本模块: 多周期简单除法器

描述:
被除数 -> 16位无符号数, 除数 -> 3位无符号数
对除数为1或2的情况作了特殊加速

注意：
除数只能是[1, 7]

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/06/25
********************************************************************/


module div_u16_u3 #(
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 除法器输入
	input wire[23:0] s_axis_data, // {保留(5bit), 除数(3bit), 被除数(16bit)}
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 除法器输出
	output wire[23:0] m_axis_data, // {保留(5bit), 余数(3bit), 商(16bit)}
	output wire m_axis_valid,
	input wire m_axis_ready
);
    
	reg[15:0] dividend; // 被除数
	reg[17:0] cmp; // 待比较数
	reg[15:0] quotient; // 商
	reg[3:0] divisor_lsh_n; // 除数的左移位数
	reg[2:0] cal_sts; // 计算状态(3'b001 -> 空闲, 3'b010 -> 计算中, 3'b100 -> 输出有效)
	
	assign s_axis_ready = aclken & cal_sts[0];
	
	assign m_axis_data = {
		5'bxxxxx, 
		dividend[2:0], // 余数
		quotient // 商
	};
	assign m_axis_valid = aclken & cal_sts[2];
	
	// 被除数
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(s_axis_valid & s_axis_ready)
				dividend <= # SIM_DELAY 
					(s_axis_data[18:16] == 3'b001) ? 16'd0:
					(s_axis_data[18:16] == 3'b010) ? {15'd0, s_axis_data[0]}:
					                                 s_axis_data[15:0];
			else if(cal_sts[1] & ({2'b00, dividend} >= cmp))
				dividend <= # SIM_DELAY dividend - cmp[15:0];
		end
	end
	
	// 待比较数
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(s_axis_valid & s_axis_ready)
				cmp <= # SIM_DELAY {s_axis_data[18:16], 15'd0};
			else if(cal_sts[1])
				cmp <= # SIM_DELAY cmp >> 1;
		end
	end
	
	// 商
	genvar qut_i;
	generate
		for(qut_i = 0;qut_i < 16;qut_i = qut_i + 1)
		begin:qut_blk
			always @(posedge aclk)
			begin
				if(
					aclken & (
						(s_axis_valid & s_axis_ready) | 
						(cal_sts[1] & (divisor_lsh_n == qut_i))
					)
				)
					quotient[qut_i] <= # SIM_DELAY 
						(s_axis_valid & s_axis_ready) ? 
							(
								(s_axis_data[18:16] == 3'b001) ? s_axis_data[qut_i]:
								(s_axis_data[18:16] == 3'b010) ? ((qut_i != 15) & s_axis_data[qut_i+1]):
								                                 1'b0
							):
							({2'b00, dividend} >= cmp);
			end
		end
	endgenerate
	
	// 除数的左移位数
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(s_axis_valid & s_axis_ready)
				divisor_lsh_n <= # SIM_DELAY 4'd15;
			else if(cal_sts[1])
				divisor_lsh_n <= # SIM_DELAY divisor_lsh_n - 4'd1;
		end
	end
	
	// 计算状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cal_sts <= 3'b001;
		else if(
			aclken & (
				(cal_sts[0] & s_axis_valid) | 
				(cal_sts[1] & ((divisor_lsh_n == 4'd0) | ({2'b00, dividend} == cmp))) | 
				(cal_sts[2] & m_axis_ready)
			)
		)
			cal_sts <= # SIM_DELAY 
				(
					cal_sts[0] & 
					((s_axis_data[18:16] == 3'b001) | (s_axis_data[18:16] == 3'b010))
				) ? 
					3'b100:
					((cal_sts << 1) | (cal_sts >> 2));
	end
	
endmodule
