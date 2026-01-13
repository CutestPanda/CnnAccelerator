`timescale 1ns / 1ps

module tb_pow2_cell();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned encode_fp16(input real d);
	import "DPI-C" function int unsigned encode_fp32(input real d);
	import "DPI-C" function int unsigned fp32_mac(input int unsigned a, input int unsigned x, input int unsigned b);
	import "DPI-C" function real decode_fp16(input int unsigned fp16);
	import "DPI-C" function real decode_fp32(input int unsigned fp32);
	import "DPI-C" function real get_fixed36_exp(input longint frac, input int exp);
	
	/** 常量 **/
	// 运算数据格式的编码
	localparam POW2_CAL_FMT_INT16 = 2'b00;
	localparam POW2_CAL_FMT_INT32 = 2'b01;
	localparam POW2_CAL_FMT_FP32 = 2'b10;
	localparam POW2_CAL_FMT_NONE = 2'b11;
	
	/** 配置参数 **/
	localparam INT16_SUPPORTED = 1'b1; // 是否支持INT16运算数据格式
	localparam INT32_SUPPORTED = 1'b1; // 是否支持INT32运算数据格式
	localparam FP32_SUPPORTED = 1'b1; // 是否支持FP32运算数据格式
	localparam integer INFO_ALONG_WIDTH = 2; // 随路数据的位宽
	localparam EN_ROUND = 1'b1; // 是否需要进行四舍五入
	// 运算数据格式
	localparam logic[1:0] pow2_calfmt = POW2_CAL_FMT_FP32;
	// 定点数量化精度
	localparam logic[4:0] fixed_point_quat_accrc = 
		(pow2_calfmt == POW2_CAL_FMT_FP32)  ? 5'dx:
		(pow2_calfmt == POW2_CAL_FMT_INT32) ? 5'd8:
		                                      5'd5;
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
	reg[31:0] pow2_cell_i_op_x; // 操作数X
	reg pow2_cell_i_pass; // 不作激活处理(标志)
	reg pow2_cell_i_vld;
	
	task rst_in_bus();
		pow2_cell_i_op_x <= # simulation_delay 32'dx;
		pow2_cell_i_pass <= # simulation_delay 1'bx;
		pow2_cell_i_vld <= # simulation_delay 1'b0;
	endtask
	
	task drive_in_bus_fp(
		input real x, input bit pass, input int unsigned delay
	);
		int unsigned x_encoded;
		
		x_encoded = encode_fp32(x);
		
		pow2_cell_i_op_x <= # simulation_delay x_encoded;
		
		pow2_cell_i_pass <= # simulation_delay pass;
		pow2_cell_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task drive_in_bus_int32(
		input int x, input bit pass, input int unsigned delay
	);
		pow2_cell_i_op_x <= # simulation_delay x;
		
		pow2_cell_i_pass <= # simulation_delay pass;
		pow2_cell_i_vld <= # simulation_delay 1'b1;
		
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
		
		drive_in_bus_fp(-1.6, 1'b0, 0);
		drive_in_bus_fp(-9.6, 1'b0, 0);
		drive_in_bus_fp(-44.9, 1'b0, 0);
		drive_in_bus_fp(-0.01, 1'b0, 0);
		drive_in_bus_fp(0.0, 1'b0, 0);
		
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
		
		drive_in_bus_int32(-40, 1'b0, 0);
		drive_in_bus_int32(-803, 1'b0, 0);
		drive_in_bus_int32(0, 1'b0, 0);
		drive_in_bus_int32(-1901, 1'b0, 0);
		
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
		if(pow2_calfmt == POW2_CAL_FMT_FP32)
			test_fp32();
		else if(pow2_calfmt == POW2_CAL_FMT_INT32)
			test_int32();
		else if(pow2_calfmt == POW2_CAL_FMT_INT16)
			test_int32();
	end
	
	/** 待测模块 **/
	// 外部有符号乘法器
	wire mul_clk;
	wire[((INT32_SUPPORTED | FP32_SUPPORTED) ? 32:16)-1:0] mul_op_a; // 操作数A
	wire[((INT32_SUPPORTED | FP32_SUPPORTED) ? 32:16)-1:0] mul_op_b; // 操作数B
	wire[2:0] mul_ce; // 计算使能
	wire[((INT32_SUPPORTED | FP32_SUPPORTED) ? 64:32)-1:0] mul_res; // 计算结果
	
	pow2_cell #(
		.INT16_SUPPORTED(INT16_SUPPORTED),
		.INT32_SUPPORTED(INT32_SUPPORTED),
		.FP32_SUPPORTED(FP32_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.EN_ROUND(EN_ROUND),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.bypass(1'b0),
		
		.pow2_calfmt(pow2_calfmt),
		.fixed_point_quat_accrc(fixed_point_quat_accrc),
		
		.pow2_cell_i_op_x(pow2_cell_i_op_x),
		.pow2_cell_i_pass(pow2_cell_i_pass),
		.pow2_cell_i_info_along(2'b01),
		.pow2_cell_i_vld(pow2_cell_i_vld),
		
		.pow2_cell_o_res(),
		.pow2_cell_o_info_along(),
		.pow2_cell_o_vld(),
		
		.mul_clk(mul_clk),
		.mul_op_a(mul_op_a),
		.mul_op_b(mul_op_b),
		.mul_ce(mul_ce),
		.mul_res(mul_res)
	);
	
	signed_mul #(
		.op_a_width((INT32_SUPPORTED | FP32_SUPPORTED) ? 32:16),
		.op_b_width((INT32_SUPPORTED | FP32_SUPPORTED) ? 32:16),
		.output_width((INT32_SUPPORTED | FP32_SUPPORTED) ? 64:32),
		.en_in_reg("true"),
		.en_out_reg("true"),
		.simulation_delay(simulation_delay)
	)signed_mul_u(
		.clk(mul_clk),
		
		.ce_in_reg(mul_ce[0]),
		.ce_mul(mul_ce[1]),
		.ce_out_reg(mul_ce[2]),
		
		.op_a(mul_op_a),
		.op_b(mul_op_b),
		
		.res(mul_res)
	);
	
endmodule
