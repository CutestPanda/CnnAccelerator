`timescale 1ns / 1ps

module tb_element_wise_out_data_cvt_cell();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned encode_fp16(input real d);
	import "DPI-C" function int unsigned encode_fp32(input real d);
	import "DPI-C" function int unsigned fp32_mac(input int unsigned a, input int unsigned x, input int unsigned b);
	import "DPI-C" function real decode_fp16(input int unsigned fp16);
	import "DPI-C" function real decode_fp32(input int unsigned fp32);
	import "DPI-C" function real get_fixed36_exp(input longint frac, input int exp);
	
	/** 常量 **/
	// 输入数据格式的编码
	localparam OUT_DATA_FMT_S33 = 2'b00;
	localparam OUT_DATA_FMT_NONE = 2'b10;
	
	/** 配置参数 **/
	localparam EN_ROUND = 1'b1; // 是否需要进行四舍五入
	localparam S33_OUT_DATA_SUPPORTED = 1'b1; // 是否支持S33输出数据格式
	localparam integer INFO_ALONG_WIDTH = 2; // 随路数据的位宽
	// 运算数据格式
	localparam logic[1:0] out_data_fmt = OUT_DATA_FMT_S33;
	// 定点数量化精度
	localparam logic[5:0] fixed_point_quat_accrc = 6'd16;
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
	reg[31:0] cvt_cell_i_op_x; // 操作数X
	reg cvt_cell_i_pass; // 不作激活处理(标志)
	reg cvt_cell_i_vld;
	
	task rst_in_bus();
		cvt_cell_i_op_x <= # simulation_delay 32'dx;
		cvt_cell_i_pass <= # simulation_delay 1'bx;
		cvt_cell_i_vld <= # simulation_delay 1'b0;
	endtask
	
	task drive_in_bus_fp(
		input real x, input bit pass, input int unsigned delay
	);
		int unsigned x_encoded;
		
		x_encoded = encode_fp32(x);
		
		cvt_cell_i_op_x <= # simulation_delay x_encoded;
		
		cvt_cell_i_pass <= # simulation_delay pass;
		cvt_cell_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task test_fp32();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		drive_in_bus_fp(1.6, 1'b0, 0);
		drive_in_bus_fp(9.6, 1'b0, 0);
		drive_in_bus_fp(44.9, 1'b0, 0);
		drive_in_bus_fp(0.01, 1'b0, 0);
		drive_in_bus_fp(0.0, 1'b0, 0);
		drive_in_bus_fp(1.0, 1'b0, 0);
		drive_in_bus_fp(2.0, 1'b0, 0);
		
		drive_in_bus_fp(-1.6, 1'b0, 0);
		drive_in_bus_fp(-9.6, 1'b0, 0);
		drive_in_bus_fp(-44.9, 1'b0, 0);
		drive_in_bus_fp(-0.01, 1'b0, 0);
		drive_in_bus_fp(0.0, 1'b0, 0);
		drive_in_bus_fp(-1.0, 1'b0, 0);
		drive_in_bus_fp(-2.0, 1'b0, 0);
		
		drive_in_bus_fp(1.6, 1'b1, 0);
		drive_in_bus_fp(9.6, 1'b1, 0);
		drive_in_bus_fp(44.9, 1'b1, 0);
		drive_in_bus_fp(0.01, 1'b1, 0);
		drive_in_bus_fp(0.0, 1'b1, 0);
		
		drive_in_bus_fp(-1.6, 1'b1, 0);
		drive_in_bus_fp(-9.6, 1'b1, 0);
		drive_in_bus_fp(-44.9, 1'b1, 0);
		drive_in_bus_fp(-0.01, 1'b1, 0);
		drive_in_bus_fp(0.0, 1'b1, 0);
	endtask
	
	initial
	begin
		if(out_data_fmt == OUT_DATA_FMT_S33)
			test_fp32();
	end
	
	/** 待测模块 **/
	element_wise_out_data_cvt_cell #(
		.EN_ROUND(EN_ROUND),
		.S33_OUT_DATA_SUPPORTED(S33_OUT_DATA_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.bypass(1'b0),
		
		.out_data_fmt(out_data_fmt),
		.fixed_point_quat_accrc(fixed_point_quat_accrc),
		
		.cvt_cell_i_op_x(cvt_cell_i_op_x),
		.cvt_cell_i_pass(cvt_cell_i_pass),
		.cvt_cell_i_info_along(2'b01),
		.cvt_cell_i_vld(cvt_cell_i_vld),
		
		.cvt_cell_o_res(),
		.cvt_cell_o_info_along(),
		.cvt_cell_o_vld()
	);
	
endmodule
