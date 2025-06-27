`timescale 1ns / 1ps

module tb_surface_pos_logic_to_phy();
	
	/** 配置参数 **/
	// 运行时参数
	localparam bit[15:0] feature_map_width = 3; // 原始特征图宽度
	localparam bit[15:0] feature_map_height = 3; // 原始特征图高度
	localparam bit[2:0] external_padding_left = 1; // 左部外填充数
	localparam bit[2:0] external_padding_top = 1; // 上部外填充数
	localparam bit[2:0] inner_padding_top_bottom = 1; // 上下内填充数
	localparam bit[2:0] inner_padding_left_right = 1; // 左右内填充数
	localparam bit[15:0] ext_j_right = 
		feature_map_width + external_padding_left +
		(feature_map_width - 1) * inner_padding_left_right - 1; // 扩展后特征图的水平边界
	localparam bit[15:0] ext_i_bottom = 
		feature_map_height + external_padding_top + 
		(feature_map_height - 1) * inner_padding_top_bottom - 1; // 扩展后特征图的垂直边界
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
	logic blk_start;
	logic[15:0] blk_i_logic_x; // 逻辑x坐标
	logic[15:0] blk_i_logic_y; // 逻辑y坐标
	
	initial
	begin
		blk_start <= 1'b0;
		blk_i_logic_x <= 16'dx;
		blk_i_logic_y <= 16'dx;
		
		repeat(10)
			@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b1;
		blk_i_logic_x <= # simulation_delay 16'd5;
		blk_i_logic_y <= # simulation_delay 16'd3;
		
		@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b0;
		blk_i_logic_x <= # simulation_delay 16'dx;
		blk_i_logic_y <= # simulation_delay 16'dx;
		
		repeat(100)
			@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b1;
		blk_i_logic_x <= # simulation_delay 16'd2;
		blk_i_logic_y <= # simulation_delay 16'd5;
		
		@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b0;
		blk_i_logic_x <= # simulation_delay 16'dx;
		blk_i_logic_y <= # simulation_delay 16'dx;
		
		repeat(100)
			@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b1;
		blk_i_logic_x <= # simulation_delay 16'd2;
		blk_i_logic_y <= # simulation_delay 16'd4;
		
		@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b0;
		blk_i_logic_x <= # simulation_delay 16'dx;
		blk_i_logic_y <= # simulation_delay 16'dx;
		
		repeat(100)
			@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b1;
		blk_i_logic_x <= # simulation_delay 16'd0;
		blk_i_logic_y <= # simulation_delay 16'd1;
		
		@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b0;
		blk_i_logic_x <= # simulation_delay 16'dx;
		blk_i_logic_y <= # simulation_delay 16'dx;
		
		repeat(100)
			@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b1;
		blk_i_logic_x <= # simulation_delay 16'd2;
		blk_i_logic_y <= # simulation_delay 16'd6;
		
		@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b0;
		blk_i_logic_x <= # simulation_delay 16'dx;
		blk_i_logic_y <= # simulation_delay 16'dx;
		
		repeat(100)
			@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b1;
		blk_i_logic_x <= # simulation_delay 16'd1;
		blk_i_logic_y <= # simulation_delay 16'd2;
		
		@(posedge clk iff rst_n);
		
		blk_start <= # simulation_delay 1'b0;
		blk_i_logic_x <= # simulation_delay 16'dx;
		blk_i_logic_y <= # simulation_delay 16'dx;
	end
	
	/** 待测模块 **/
	surface_pos_logic_to_phy #(
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.ext_j_right(ext_j_right),
		.ext_i_bottom(ext_i_bottom),
		.external_padding_left(external_padding_left),
		.external_padding_top(external_padding_top),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.inner_padding_left_right(inner_padding_left_right),
		
		.blk_start(blk_start),
		.blk_idle(),
		.blk_i_logic_x(blk_i_logic_x),
		.blk_i_logic_y(blk_i_logic_y),
		.blk_done(),
		.blk_o_phy_x(),
		.blk_o_phy_y(),
		.blk_o_is_vld()
	);
	
endmodule
