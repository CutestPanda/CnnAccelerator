`timescale 1ns / 1ps

module tb_kernal_pos_logic_to_phy();
	
	/** 配置参数 **/
	// 运行时参数
	localparam bit[3:0] kernal_dilation_hzt_n = 1; // 水平膨胀量
	localparam bit[3:0] kernal_dilation_vtc_n = 1; // 垂直膨胀量
	localparam bit[3:0] kernal_w = 4 - 1; // (膨胀前)卷积核宽度 - 1
	localparam bit[3:0] kernal_h = 4 - 1; // (膨胀前)卷积核高度 - 1
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
	
	/** 函数 **/
	function int unsigned get_logic_kernal_size(
		input int unsigned kw, input int unsigned kh, 
		input int unsigned dlt_hn, input int unsigned dlt_vn
	);
		int unsigned w;
		int unsigned h;
		
		w = kw + (kw - 1) * dlt_hn;
		h = kh + (kh - 1) * dlt_vn;
		
		return w * h;		
	endfunction
	
	/** 测试激励 **/
	logic mv_to_nxt_logic_pt; // 移动到下1个逻辑卷积核点位
	logic mv_to_nxt_logic_pt_d; // 延迟1clk的移动到下1个逻辑卷积核点位
	
	localparam int unsigned logic_ksize = 
		get_logic_kernal_size(kernal_w + 1, kernal_h + 1, kernal_dilation_hzt_n, kernal_dilation_vtc_n);
	
	initial
	begin
		mv_to_nxt_logic_pt <= 1'b0;
		
		repeat(10)
			@(posedge clk iff rst_n);
		
		repeat(logic_ksize)
		begin
			repeat($urandom_range(0, 2))
				@(posedge clk iff rst_n);
			
			mv_to_nxt_logic_pt <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
			
			mv_to_nxt_logic_pt <= # simulation_delay 1'b0;
		end
		
		repeat(20)
			@(posedge clk iff rst_n);
		
		repeat(logic_ksize)
		begin
			repeat($urandom_range(0, 2))
				@(posedge clk iff rst_n);
			
			mv_to_nxt_logic_pt <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
			
			mv_to_nxt_logic_pt <= # simulation_delay 1'b0;
		end
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mv_to_nxt_logic_pt_d <= 1'b0;
		else
			mv_to_nxt_logic_pt_d <= # simulation_delay mv_to_nxt_logic_pt;
	end
	
	/** 待测模块 **/
	logic[7:0] kernal_logic_x; // 当前的逻辑卷积核x坐标
	logic[7:0] kernal_logic_y; // 当前的逻辑卷积核y坐标
	logic[7:0] kernal_phy_x; // 当前的物理卷积核x坐标
	logic[7:0] kernal_phy_y; // 当前的物理卷积核y坐标
	logic kernal_pt_valid; // 逻辑卷积核点有效标志
	
	always @(posedge clk)
	begin
		if(mv_to_nxt_logic_pt_d)
		begin
			$display("(logic_y, logic_x) = (%d, %d) (phy_y, phy_x) = (%d, %d) vld = %b", 
				kernal_logic_y, kernal_logic_x, kernal_phy_y, kernal_phy_x, kernal_pt_valid);
		end
	end
	
	kernal_pos_logic_to_phy #(
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.kernal_dilation_hzt_n(kernal_dilation_hzt_n),
		.kernal_dilation_vtc_n(kernal_dilation_vtc_n),
		.kernal_w(kernal_w),
		.kernal_h(kernal_h),
		
		.rst_cvt(1'b0),
		.mv_to_nxt_logic_pt(mv_to_nxt_logic_pt),
		.kernal_logic_x(kernal_logic_x),
		.kernal_logic_y(kernal_logic_y),
		.kernal_phy_x(kernal_phy_x),
		.kernal_phy_y(kernal_phy_y),
		.kernal_pt_valid(kernal_pt_valid)
	);
	
endmodule
