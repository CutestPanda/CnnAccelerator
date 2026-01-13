`timescale 1ns / 1ps

module tb_element_wise_in_data_cvt_cell();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned encode_fp16(input real d);
	import "DPI-C" function int unsigned encode_fp32(input real d);
	import "DPI-C" function int unsigned fp32_mac(input int unsigned a, input int unsigned x, input int unsigned b);
	import "DPI-C" function real decode_fp16(input int unsigned fp16);
	import "DPI-C" function real decode_fp32(input int unsigned fp32);
	import "DPI-C" function real get_fixed36_exp(input longint frac, input int exp);
	
	/** 常量 **/
	// 输入数据格式的编码
	localparam IN_DATA_FMT_FP16 = 2'b00;
	localparam IN_DATA_FMT_S33 = 2'b01;
	localparam IN_DATA_FMT_NONE = 2'b10;
	// 整数类型的编码
	localparam INTEGER_TYPE_U8 = 3'b000;
	localparam INTEGER_TYPE_S8 = 3'b001;
	localparam INTEGER_TYPE_U16 = 3'b010;
	localparam INTEGER_TYPE_S16 = 3'b011;
	localparam INTEGER_TYPE_U32 = 3'b100;
	localparam INTEGER_TYPE_S32 = 3'b101;
	
	/** 配置参数 **/
	localparam EN_ROUND = 1'b1; // 是否需要进行四舍五入
	localparam FP16_IN_DATA_SUPPORTED = 1'b1; // 是否支持FP16输入数据格式
	localparam S33_IN_DATA_SUPPORTED = 1'b1; // 是否支持S33输入数据格式
	localparam integer INFO_ALONG_WIDTH = 2; // 随路数据的位宽
	// 运算数据格式
	localparam logic[1:0] in_data_fmt = IN_DATA_FMT_S33;
	// 整数类型
	localparam logic[2:0] integer_type = INTEGER_TYPE_S16;
	// 定点数量化精度
	localparam logic[5:0] fixed_point_quat_accrc = 
		(in_data_fmt == IN_DATA_FMT_FP16)  ? 6'dx:
		                                     6'd8;
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
		
		x_encoded = encode_fp16(x);
		
		cvt_cell_i_op_x <= # simulation_delay x_encoded[15:0] | 32'd0;
		
		cvt_cell_i_pass <= # simulation_delay pass;
		cvt_cell_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task drive_in_bus_int32(
		input int x, input bit pass, input int unsigned delay
	);
		cvt_cell_i_op_x <= # simulation_delay x;
		
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
	
	task test_int32();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		drive_in_bus_int32(40, 1'b0, 0);
		drive_in_bus_int32(803, 1'b0, 0);
		drive_in_bus_int32(0, 1'b0, 0);
		drive_in_bus_int32(1901, 1'b0, 0);
		drive_in_bus_int32(256, 1'b0, 0);
		drive_in_bus_int32(512, 1'b0, 0);
		drive_in_bus_int32(67108895, 1'b0, 0);
		
		drive_in_bus_int32(-40, 1'b0, 0);
		drive_in_bus_int32(-803, 1'b0, 0);
		drive_in_bus_int32(0, 1'b0, 0);
		drive_in_bus_int32(-1901, 1'b0, 0);
		drive_in_bus_int32(-256, 1'b0, 0);
		drive_in_bus_int32(-512, 1'b0, 0);
		drive_in_bus_int32(-67108895, 1'b0, 0);
		
		drive_in_bus_int32(40, 1'b1, 0);
		drive_in_bus_int32(803, 1'b1, 0);
		drive_in_bus_int32(0, 1'b1, 0);
		drive_in_bus_int32(1901, 1'b1, 0);
		
		drive_in_bus_int32(-40, 1'b1, 0);
		drive_in_bus_int32(-803, 1'b1, 0);
		drive_in_bus_int32(0, 1'b1, 0);
		drive_in_bus_int32(-1901, 1'b1, 0);
	endtask
	
	initial
	begin
		if(in_data_fmt == IN_DATA_FMT_FP16)
			test_fp32();
		else if(in_data_fmt == IN_DATA_FMT_S33)
			test_int32();
	end
	
	/** 待测模块 **/
	element_wise_in_data_cvt_cell #(
		.EN_ROUND(EN_ROUND),
		.FP16_IN_DATA_SUPPORTED(FP16_IN_DATA_SUPPORTED),
		.S33_IN_DATA_SUPPORTED(S33_IN_DATA_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.bypass(1'b0),
		
		.in_data_fmt(in_data_fmt),
		.integer_type(integer_type),
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
