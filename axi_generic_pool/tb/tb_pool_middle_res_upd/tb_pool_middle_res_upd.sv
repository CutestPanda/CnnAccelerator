`timescale 1ns / 1ps

module tb_pool_middle_res_upd();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned encode_fp16(input real d);
	import "DPI-C" function int unsigned encode_fp32(input real d);
	import "DPI-C" function real decode_fp16(input int unsigned fp16);
	import "DPI-C" function real decode_fp32(input int unsigned fp32);
	
	/** 常量 **/
	// 池化模式的编码
	localparam POOL_MODE_AVG = 2'b00;
	localparam POOL_MODE_MAX = 2'b01;
	localparam POOL_MODE_UPSP = 2'b10;
	localparam POOL_MODE_NONE = 2'b11;
	// 运算数据格式的编码
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	localparam CAL_FMT_NONE = 2'b11;
	
	/** 配置参数 **/
	// 运行时参数
	localparam logic[1:0] pool_mode = POOL_MODE_MAX; // 池化模式
	localparam logic[1:0] calfmt = CAL_FMT_FP16; // 运算数据格式
	// 仿真参数
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
	
	/** 主任务 **/
	reg[15:0] pool_upd_in_data; // 定点数或FP16
	reg[31:0] pool_upd_in_org_mid_res; // 原中间结果
	reg pool_upd_in_is_first_item; // 是否第1项(标志)
	reg pool_upd_in_is_zero_sfc; // 是否空表面(标志)
	reg pool_upd_in_valid; // 输入有效指示
	
	task rst_in_bus();
		pool_upd_in_data <= # simulation_delay 16'dx;
		pool_upd_in_org_mid_res <= # simulation_delay 32'dx;
		
		pool_upd_in_is_first_item <= # simulation_delay 1'bx;
		pool_upd_in_is_zero_sfc <= # simulation_delay 1'bx;
		
		pool_upd_in_valid <= # simulation_delay 1'b0;
	endtask
	
	task drive_in_bus_fp(
		input real org_r, input real new_r, input bit is_first_item, input bit is_zero_sfc, input int unsigned delay
	);
		pool_upd_in_data <= # simulation_delay is_zero_sfc ? 16'dx:encode_fp16(new_r);
		pool_upd_in_org_mid_res <= # simulation_delay is_first_item ? 32'dx:encode_fp32(org_r);
		
		pool_upd_in_is_first_item <= # simulation_delay is_first_item;
		pool_upd_in_is_zero_sfc <= # simulation_delay is_zero_sfc;
		
		pool_upd_in_valid <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task drive_in_bus_int(
		input int unsigned org_r, input int unsigned new_r, input bit is_first_item, input bit is_zero_sfc, input int unsigned delay
	);
		pool_upd_in_data <= # simulation_delay is_zero_sfc ? 16'dx:new_r;
		pool_upd_in_org_mid_res <= # simulation_delay is_first_item ? 32'dx:org_r;
		
		pool_upd_in_is_first_item <= # simulation_delay is_first_item;
		pool_upd_in_is_zero_sfc <= # simulation_delay is_zero_sfc;
		
		pool_upd_in_valid <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task test_fp32_max_pool_upsample();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		// org_r, new_r, is_first_item, is_zero_sfc, delay
		drive_in_bus_fp(3.57, -5.78, 1'b0, 1'b0, 0);
		drive_in_bus_fp(3.57, 0.253, 1'b0, 1'b0, 0);
		drive_in_bus_fp(3.57, 0.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(3.57, -0.253, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(-3.57, -5.78, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-3.57, -3.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-3.57, -99.6, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-3.57, -3.5, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(-6.3, 7.54, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.0, 7.54, 1'b0, 1'b0, 0);
		drive_in_bus_fp(7.0, 7.54, 1'b0, 1'b0, 0);
		drive_in_bus_fp(7.5, 7.54, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(-8.97, -7.54, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-8.0, -7.54, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-7.0, -7.54, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-6.7, -7.54, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.0, -7.54, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(3.57, 99.9, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, 3.57, 1'b1, 1'b0, 0);
		drive_in_bus_fp(3.57, -99.9, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, -3.57, 1'b1, 1'b0, 0);
		drive_in_bus_fp(3.57, 0.0, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, 0.46, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, -0.46, 1'b1, 1'b0, 0);
		
		drive_in_bus_fp(3.57, 99.9, 1'b0, 1'b1, 0);
		drive_in_bus_fp(-3.57, 99.9, 1'b0, 1'b1, 0);
		drive_in_bus_fp(-1.24, 99.9, 1'b0, 1'b1, 0);
		drive_in_bus_fp(1.24, 99.9, 1'b0, 1'b1, 0);
		
		drive_in_bus_fp(-3.57, 99.9, 1'b1, 1'b1, 0);
		drive_in_bus_fp(3.57, 99.9, 1'b1, 1'b1, 0);
		drive_in_bus_fp(-3.57, -99.9, 1'b1, 1'b1, 0);
	endtask
	
	task test_fp32_avg_pool();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		// org_r, new_r, is_first_item, is_zero_sfc, delay
		drive_in_bus_fp(0.125, -0.125, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.126, -0.125, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(4.23, 8.71, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-4.23, 8.71, 1'b0, 1'b0, 0);
		drive_in_bus_fp(4.23, -8.71, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-4.23, -8.71, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(4.0, 2.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-4.0, 2.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(4.0, -2.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-4.0, -2.0, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(0.5, 0.5, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-0.5, 0.5, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.5, -0.5, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-0.5, -0.5, 1'b0, 1'b0, 0);
		
		drive_in_bus_fp(3.57, 99.9, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, 3.57, 1'b1, 1'b0, 0);
		drive_in_bus_fp(3.57, -99.9, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, -3.57, 1'b1, 1'b0, 0);
		drive_in_bus_fp(3.57, 0.0, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, 0.46, 1'b1, 1'b0, 0);
		drive_in_bus_fp(99.9, -0.46, 1'b1, 1'b0, 0);
		
		drive_in_bus_fp(3.57, 99.9, 1'b0, 1'b1, 0);
		drive_in_bus_fp(-3.57, 99.9, 1'b0, 1'b1, 0);
		drive_in_bus_fp(-1.24, 99.9, 1'b0, 1'b1, 0);
		drive_in_bus_fp(1.24, 99.9, 1'b0, 1'b1, 0);
		
		drive_in_bus_fp(-3.57, 99.9, 1'b1, 1'b1, 0);
		drive_in_bus_fp(3.57, 99.9, 1'b1, 1'b1, 0);
		drive_in_bus_fp(-3.57, -99.9, 1'b1, 1'b1, 0);
	endtask
	
	task test_int_max_pool_upsample();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		// org_r, new_r, is_first_item, is_zero_sfc, delay
		drive_in_bus_int(357, -578, 1'b0, 1'b0, 0);
		drive_in_bus_int(357, 253, 1'b0, 1'b0, 0);
		drive_in_bus_int(357, 0, 1'b0, 1'b0, 0);
		drive_in_bus_int(357, -253, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(-357, -578, 1'b0, 1'b0, 0);
		drive_in_bus_int(-357, -30, 1'b0, 1'b0, 0);
		drive_in_bus_int(-357, -996, 1'b0, 1'b0, 0);
		drive_in_bus_int(-357, -35, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(-63, 754, 1'b0, 1'b0, 0);
		drive_in_bus_int(0, 754, 1'b0, 1'b0, 0);
		drive_in_bus_int(9, 754, 1'b0, 1'b0, 0);
		drive_in_bus_int(75, 754, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(-897, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(-800, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(-700, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(-670, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(0, -754, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(357, 9990, 1'b1, 1'b0, 0);
		drive_in_bus_int(999, 357, 1'b1, 1'b0, 0);
		drive_in_bus_int(357, -9990, 1'b1, 1'b0, 0);
		drive_in_bus_int(9990, -357, 1'b1, 1'b0, 0);
		drive_in_bus_int(357, 0, 1'b1, 1'b0, 0);
		drive_in_bus_int(9990, 46, 1'b1, 1'b0, 0);
		drive_in_bus_int(9990, -46, 1'b1, 1'b0, 0);
		
		drive_in_bus_int(357, 9990, 1'b0, 1'b1, 0);
		drive_in_bus_int(-357, 9990, 1'b0, 1'b1, 0);
		drive_in_bus_int(-124, 9990, 1'b0, 1'b1, 0);
		drive_in_bus_int(124, 9990, 1'b0, 1'b1, 0);
		
		drive_in_bus_int(-357, 9990, 1'b1, 1'b1, 0);
		drive_in_bus_int(357, 9990, 1'b1, 1'b1, 0);
		drive_in_bus_int(-357, -9990, 1'b1, 1'b1, 0);
	endtask
	
	task test_int_avg_pool();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		// org_r, new_r, is_first_item, is_zero_sfc, delay
		drive_in_bus_int(125, -125, 1'b0, 1'b0, 0);
		drive_in_bus_int(126, -125, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(30000, 30000, 1'b0, 1'b0, 0);
		drive_in_bus_int(-30000, -30000, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(357, -578, 1'b0, 1'b0, 0);
		drive_in_bus_int(357, 253, 1'b0, 1'b0, 0);
		drive_in_bus_int(357, 0, 1'b0, 1'b0, 0);
		drive_in_bus_int(357, -253, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(-357, -578, 1'b0, 1'b0, 0);
		drive_in_bus_int(-357, -30, 1'b0, 1'b0, 0);
		drive_in_bus_int(-357, -996, 1'b0, 1'b0, 0);
		drive_in_bus_int(-357, -35, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(-63, 754, 1'b0, 1'b0, 0);
		drive_in_bus_int(0, 754, 1'b0, 1'b0, 0);
		drive_in_bus_int(9, 754, 1'b0, 1'b0, 0);
		drive_in_bus_int(75, 754, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(-897, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(-800, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(-700, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(-670, -754, 1'b0, 1'b0, 0);
		drive_in_bus_int(0, -754, 1'b0, 1'b0, 0);
		
		drive_in_bus_int(357, 9990, 1'b1, 1'b0, 0);
		drive_in_bus_int(999, 357, 1'b1, 1'b0, 0);
		drive_in_bus_int(357, -9990, 1'b1, 1'b0, 0);
		drive_in_bus_int(9990, -357, 1'b1, 1'b0, 0);
		drive_in_bus_int(357, 0, 1'b1, 1'b0, 0);
		drive_in_bus_int(9990, 46, 1'b1, 1'b0, 0);
		drive_in_bus_int(9990, -46, 1'b1, 1'b0, 0);
		
		drive_in_bus_int(357, 9990, 1'b0, 1'b1, 0);
		drive_in_bus_int(-357, 9990, 1'b0, 1'b1, 0);
		drive_in_bus_int(-124, 9990, 1'b0, 1'b1, 0);
		drive_in_bus_int(124, 9990, 1'b0, 1'b1, 0);
		
		drive_in_bus_int(-357, 9990, 1'b1, 1'b1, 0);
		drive_in_bus_int(357, 9990, 1'b1, 1'b1, 0);
		drive_in_bus_int(-357, -9990, 1'b1, 1'b1, 0);
	endtask
	
	initial
	begin
		if(calfmt == CAL_FMT_FP16)
		begin
			if(pool_mode == POOL_MODE_MAX || pool_mode == POOL_MODE_UPSP)
				test_fp32_max_pool_upsample();
			else if(pool_mode == POOL_MODE_AVG)
				test_fp32_avg_pool();
		end
		else if(calfmt == CAL_FMT_INT16 || calfmt == CAL_FMT_INT8)
		begin
			if(pool_mode == POOL_MODE_MAX || pool_mode == POOL_MODE_UPSP)
				test_int_max_pool_upsample();
			else if(pool_mode == POOL_MODE_AVG)
				test_int_avg_pool();
		end
	end
	
	/** 待测模块 **/
	pool_middle_res_upd #(
		.INFO_ALONG_WIDTH(2),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.pool_mode(pool_mode),
		.calfmt(calfmt),
		
		.pool_upd_in_data(pool_upd_in_data),
		.pool_upd_in_org_mid_res(pool_upd_in_org_mid_res),
		.pool_upd_in_is_first_item(pool_upd_in_is_first_item),
		.pool_upd_in_is_zero_sfc(pool_upd_in_is_zero_sfc),
		.pool_upd_in_info_along(2'b01),
		.pool_upd_in_valid(pool_upd_in_valid),
		
		.pool_upd_out_data(),
		.pool_upd_out_info_along(),
		.pool_upd_out_valid()
	);
	
endmodule
