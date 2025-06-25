`timescale 1ns / 1ps

module tb_div_u16_u3();
	
	/** 配置参数 **/
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 测试激励 **/
	// 除法器输入
	reg[23:0] s_axis_data; // {保留(5bit), 除数(3bit), 被除数(16bit)}
	reg s_axis_valid;
	wire s_axis_ready;
	
	initial
	begin
		s_axis_data <= {5'dx, 3'dx, 16'dx};
		s_axis_valid <= 1'b0;
		
		repeat(10)
		begin
			@(posedge clk iff rst_n);
		end
		
		s_axis_data <= # simulation_delay {5'dx, 3'd3, 16'd100};
		s_axis_valid <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		s_axis_data <= # simulation_delay {5'dx, 3'dx, 16'dx};
		s_axis_valid <= # simulation_delay 1'b0;
		
		repeat(20)
		begin
			@(posedge clk iff rst_n);
		end
		
		s_axis_data <= # simulation_delay {5'dx, 3'd2, 16'd64};
		s_axis_valid <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		s_axis_data <= # simulation_delay {5'dx, 3'dx, 16'dx};
		s_axis_valid <= # simulation_delay 1'b0;
		
		repeat(20)
		begin
			@(posedge clk iff rst_n);
		end
		
		s_axis_data <= # simulation_delay {5'dx, 3'd1, 16'd79};
		s_axis_valid <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		s_axis_data <= # simulation_delay {5'dx, 3'dx, 16'dx};
		s_axis_valid <= # simulation_delay 1'b0;
		
		repeat(20)
		begin
			@(posedge clk iff rst_n);
		end
		
		s_axis_data <= # simulation_delay {5'dx, 3'd3, 16'd2};
		s_axis_valid <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		s_axis_data <= # simulation_delay {5'dx, 3'dx, 16'dx};
		s_axis_valid <= # simulation_delay 1'b0;
	end
	
	/** 待测模块 **/
	// 除法器输出
	wire[23:0] m_axis_data; // {保留(5bit), 余数(3bit), 商(16bit)}
	wire m_axis_valid;
	wire m_axis_ready;
	
	assign m_axis_ready = 1'b1;
	
	div_u16_u3 #(
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.s_axis_data(s_axis_data),
		.s_axis_valid(s_axis_valid),
		.s_axis_ready(s_axis_ready),
		
		.m_axis_data(m_axis_data),
		.m_axis_valid(m_axis_valid),
		.m_axis_ready(m_axis_ready)
	);
	
endmodule
