`timescale 1ns / 1ps

module tb_out_round_cell();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned encode_fp16(input real d);
	import "DPI-C" function int unsigned encode_fp32(input real d);
	import "DPI-C" function int unsigned fp32_mac(input int unsigned a, input int unsigned x, input int unsigned b);
	import "DPI-C" function real decode_fp16(input int unsigned fp16);
	import "DPI-C" function real decode_fp32(input int unsigned fp32);
	import "DPI-C" function real get_fixed36_exp(input longint frac, input int exp);
	
	/** 常量 **/
	// 目标数据格式的编码
	localparam TARGET_DATA_FMT_U8 = 3'b000;
	localparam TARGET_DATA_FMT_S8 = 3'b001;
	localparam TARGET_DATA_FMT_U16 = 3'b010;
	localparam TARGET_DATA_FMT_S16 = 3'b011;
	localparam TARGET_DATA_FMT_U32 = 3'b100;
	localparam TARGET_DATA_FMT_S32 = 3'b101;
	localparam TARGET_DATA_FMT_FP16 = 3'b110;
	localparam TARGET_DATA_FMT_NONE = 3'b111;
	
	/** 配置参数 **/
	localparam S33_ROUND_SUPPORTED = 1'b1; // 是否支持S33数据的舍入
	localparam FP32_ROUND_SUPPORTED = 1'b1; // 是否支持FP32数据的舍入
	localparam integer INFO_ALONG_WIDTH = 2; // 随路数据的位宽
	// 运行时参数
	localparam logic[2:0] target_data_fmt = TARGET_DATA_FMT_FP16; // 目标数据格式
	localparam logic[4:0] in_fixed_point_quat_accrc = 12; // 输入定点数量化精度
	localparam logic[4:0] out_fixed_point_quat_accrc = 8; // 输出定点数量化精度
	localparam logic[4:0] fixed_point_rounding_digits = in_fixed_point_quat_accrc - out_fixed_point_quat_accrc; // 定点数舍入位数
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
	reg[32:0] round_i_op_x; // 操作数X(定点数或FP32)
	reg round_i_vld;
	
	task rst_in_bus();
		round_i_op_x <= # simulation_delay 33'dx;
		round_i_vld <= # simulation_delay 1'b0;
	endtask
	
	task drive_in_bus_fp(
		input real x, input int unsigned delay
	);
		int unsigned x_encoded;
		
		x_encoded = encode_fp32(x);
		
		round_i_op_x <= # simulation_delay {1'b0, x_encoded};
		
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task drive_in_bus_int32(
		input int x, input bit pass, input int unsigned delay
	);
		round_i_op_x <= # simulation_delay {x[31], x};
		
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task test_fp32();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		round_i_op_x <= # simulation_delay {1'b0, 1'b1, 8'd123, 23'b1111111111_1000000000000};
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_op_x <= # simulation_delay {1'b0, 1'b0, 8'd123, 23'b1111111111_1000000000000};
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_vld <= # simulation_delay 1'b0;
	endtask
	
	task test_int32();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		round_i_op_x <= # simulation_delay 1200;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		round_i_op_x <= # simulation_delay -1200;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		round_i_op_x <= # simulation_delay 26829;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_op_x <= # simulation_delay -26829;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_op_x <= # simulation_delay 405504;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_op_x <= # simulation_delay -405504;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_op_x <= # simulation_delay 26578944;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_op_x <= # simulation_delay -26578944;
		round_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		round_i_vld <= # simulation_delay 1'b0;
	endtask
	
	initial
	begin
		if(target_data_fmt == TARGET_DATA_FMT_FP16)
			test_fp32();
		else if(
			(target_data_fmt == TARGET_DATA_FMT_U8) || 
			(target_data_fmt == TARGET_DATA_FMT_S8) || 
			(target_data_fmt == TARGET_DATA_FMT_U16) || 
			(target_data_fmt == TARGET_DATA_FMT_S16) || 
			(target_data_fmt == TARGET_DATA_FMT_U32) || 
			(target_data_fmt == TARGET_DATA_FMT_S32)
		)
			test_int32();
	end
	
	/** 待测模块 **/
	out_round_cell #(
		.USE_EXT_CE(1'b0),
		.S33_ROUND_SUPPORTED(S33_ROUND_SUPPORTED),
		.FP32_ROUND_SUPPORTED(FP32_ROUND_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.bypass(1'b0),
		.s0_ce(1'b0),
		.s1_ce(1'b0),
		.s2_ce(1'b0),
		
		.target_data_fmt(target_data_fmt),
		.in_fixed_point_quat_accrc(in_fixed_point_quat_accrc),
		.out_fixed_point_quat_accrc(out_fixed_point_quat_accrc),
		.fixed_point_rounding_digits(fixed_point_rounding_digits),
		
		.round_i_op_x(round_i_op_x),
		.round_i_info_along(2'b01),
		.round_i_vld(round_i_vld),
		
		.round_o_res(),
		.round_o_info_along(),
		.round_o_vld()
	);
	
endmodule
