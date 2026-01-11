`timescale 1ns / 1ps

module tb_batch_nml_mac_cell();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned encode_fp16(input real d);
	import "DPI-C" function int unsigned encode_fp32(input real d);
	import "DPI-C" function int unsigned fp32_mac(input int unsigned a, input int unsigned x, input int unsigned b);
	import "DPI-C" function real decode_fp16(input int unsigned fp16);
	import "DPI-C" function real decode_fp32(input int unsigned fp32);
	import "DPI-C" function real get_fixed36_exp(input longint frac, input int exp);
	
	/** 常量 **/
	// 运算数据格式的编码
	localparam BN_CAL_FMT_INT16 = 2'b00;
	localparam BN_CAL_FMT_INT32 = 2'b01;
	localparam BN_CAL_FMT_FP32 = 2'b10;
	
	/** 配置参数 **/
	localparam INT16_SUPPORTED = 1'b0; // 是否支持INT16运算数据格式
	localparam INT32_SUPPORTED = 1'b1; // 是否支持INT32运算数据格式
	localparam FP32_SUPPORTED = 1'b1; // 是否支持FP32运算数据格式
	localparam integer INFO_ALONG_WIDTH = 2; // 随路数据的位宽
	localparam logic[1:0] bn_calfmt = BN_CAL_FMT_FP32; // 运算数据格式
	localparam logic[4:0] fixed_point_quat_accrc = 5'd1; // 定点数量化精度
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
	reg[31:0] mac_cell_i_op_a; // 操作数A
	reg[31:0] mac_cell_i_op_x; // 操作数X
	reg[31:0] mac_cell_i_op_b; // 操作数B
	reg mac_cell_i_is_a_eq_1; // 参数A的实际值为1(标志)
	reg mac_cell_i_is_b_eq_0; // 参数B的实际值为0(标志)
	reg mac_cell_i_vld;
	
	reg[31:0] mac_cell_i_fp32_exp;
	reg[63:0] mac_cell_i_int32_exp;
	
	task rst_in_bus();
		mac_cell_i_fp32_exp <= # simulation_delay 32'dx;
		mac_cell_i_int32_exp <= # simulation_delay 64'dx;
		
		mac_cell_i_op_a <= # simulation_delay 32'dx;
		mac_cell_i_op_x <= # simulation_delay 32'dx;
		mac_cell_i_op_b <= # simulation_delay 32'dx;
		mac_cell_i_is_a_eq_1 <= # simulation_delay 1'bx;
		mac_cell_i_is_b_eq_0 <= # simulation_delay 1'bx;
		mac_cell_i_vld <= # simulation_delay 1'b0;
	endtask
	
	task drive_in_bus_fp(
		input real a, input real x, input real b, input bit is_a_eq_1, input bit is_b_eq_0, input int unsigned delay
	);
		int unsigned a_encoded;
		int unsigned x_encoded;
		int unsigned b_encoded;
		
		a_encoded = is_a_eq_1 ? 32'h3F800000:encode_fp32(a);
		x_encoded = encode_fp32(x);
		b_encoded = is_b_eq_0 ? 32'h00000000:encode_fp32(b);
		
		mac_cell_i_fp32_exp <= # simulation_delay fp32_mac(a_encoded, x_encoded, b_encoded);
		
		if(is_a_eq_1)
			mac_cell_i_op_a <= # simulation_delay 32'dx;
		else
			mac_cell_i_op_a <= # simulation_delay a_encoded;
		
		mac_cell_i_op_x <= # simulation_delay x_encoded;
		
		if(is_b_eq_0)
			mac_cell_i_op_b <= # simulation_delay 32'dx;
		else
			mac_cell_i_op_b <= # simulation_delay b_encoded;
		
		mac_cell_i_is_a_eq_1 <= # simulation_delay is_a_eq_1;
		mac_cell_i_is_b_eq_0 <= # simulation_delay is_b_eq_0;
		mac_cell_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task drive_in_bus_int32(
		input int a, input int x, input int b, input bit is_a_eq_1, input bit is_b_eq_0, input int unsigned delay
	);
		mac_cell_i_int32_exp <= # simulation_delay 
			(is_a_eq_1 ? longint'(x):((longint'(a) * longint'(x)) >>> fixed_point_quat_accrc)) + 
			(is_b_eq_0 ? 0:longint'(b));
		
		if(is_a_eq_1)
			mac_cell_i_op_a <= # simulation_delay 32'dx;
		else
			mac_cell_i_op_a <= # simulation_delay a;
		
		mac_cell_i_op_x <= # simulation_delay x;
		
		if(is_b_eq_0)
			mac_cell_i_op_b <= # simulation_delay 32'dx;
		else
			mac_cell_i_op_b <= # simulation_delay b;
		
		mac_cell_i_is_a_eq_1 <= # simulation_delay is_a_eq_1;
		mac_cell_i_is_b_eq_0 <= # simulation_delay is_b_eq_0;
		mac_cell_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task test_fp32();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		drive_in_bus_fp(0.7, 0.12, 93.55, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-19.0, 9.53, -7.9, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.5, 0.5, 0.25, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.5, 0.5, -0.25, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.5, 9.82, -0.77, 1'b1, 1'b0, 0);
		drive_in_bus_fp(0.5, 9.82, -0.77, 1'b0, 1'b1, 0);
		drive_in_bus_fp(0.5, 9.82, -0.77, 1'b1, 1'b1, 0);
		drive_in_bus_fp(1.0, 4.0, -2.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-1.0, 4.0, 2.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(3.333, 1789.12, -0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-3.333, 1789.12, -0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(3.333, -1789.12, -0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-3.333, -1789.12, -0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(3.333, 1789.12, 0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-3.333, 1789.12, 0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(3.333, -1789.12, 0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-3.333, -1789.12, 0.42, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1899.4, 240.11, -456064.93395, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1899.4, 240.1, 0.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1.0, 240.1, -1.2, 1'b0, 1'b0, 0);
		drive_in_bus_fp(4.124, -0.122, 2.24, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1.12, 0.42, 0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1.12, -0.42, 0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-1.12, 0.42, 0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-1.12, -0.42, 0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1.12, 0.42, -0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1.12, -0.42, -0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-1.12, 0.42, -0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(-1.12, -0.42, -0.321, 1'b0, 1'b0, 0);
		drive_in_bus_fp(9.86, -2.936, 28.9489, 1'b0, 1'b0, 0);
		drive_in_bus_fp(9.86, -2.936, 28.949, 1'b0, 1'b0, 0);
		drive_in_bus_fp(10.01, 299.8, -3001.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(10.01, 299.8, -3000.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(10.01, 299.8, -2999.998, 1'b0, 1'b0, 0);
		drive_in_bus_fp(1.0, 2.0, -1.0, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.5, 0.25, 0.875, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.5, -0.25, -0.375, 1'b0, 1'b0, 0);
		drive_in_bus_fp(0.872487, 2.62445, -1.78084E-20, 1'b0, 1'b0, 0);
	endtask
	
	task test_int32();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		drive_in_bus_int32(9325, 285, 999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(-9325, 285, 999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(9325, -285, 999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(-9325, -285, 999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(9325, 285, -999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(-9325, 285, -999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(9325, -285, -999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(-9325, -285, -999, 1'b0, 1'b0, 0);
		drive_in_bus_int32(9325, -285, -999, 1'b1, 1'b0, 0);
		drive_in_bus_int32(9325, -285, -999, 1'b0, 1'b1, 0);
		drive_in_bus_int32(9325, -285, -999, 1'b1, 1'b1, 0);
	endtask
	
	initial
	begin
		if(bn_calfmt == BN_CAL_FMT_FP32)
			test_fp32();
		else if(bn_calfmt == BN_CAL_FMT_INT32)
			test_int32();
	end
	
	/** 待测模块 **/
	// 乘加单元结果输出
	wire[31:0] mac_cell_o_res; // 计算结果
	wire[INFO_ALONG_WIDTH-1:0] mac_cell_o_info_along; // 随路数据
	wire mac_cell_o_vld;
	// 外部有符号乘法器
	wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))-1:0] mul_op_a; // 操作数A
	wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))-1:0] mul_op_b; // 操作数B
	wire[(INT16_SUPPORTED ? 4:3)-1:0] mul_ce; // 计算使能
	wire[(INT16_SUPPORTED ? 4*36:(INT32_SUPPORTED ? 64:50))-1:0] mul_res; // 计算结果
	
	batch_nml_mac_cell #(
		.INT16_SUPPORTED(INT16_SUPPORTED),
		.INT32_SUPPORTED(INT32_SUPPORTED),
		.FP32_SUPPORTED(FP32_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.bypass(1'b0),
		
		.bn_calfmt(bn_calfmt),
		.fixed_point_quat_accrc((bn_calfmt == BN_CAL_FMT_FP32) ? 5'dx:fixed_point_quat_accrc),
		
		.mac_cell_i_op_a(mac_cell_i_op_a),
		.mac_cell_i_op_x(mac_cell_i_op_x),
		.mac_cell_i_op_b(mac_cell_i_op_b),
		.mac_cell_i_is_a_eq_1(mac_cell_i_is_a_eq_1),
		.mac_cell_i_is_b_eq_0(mac_cell_i_is_b_eq_0),
		.mac_cell_i_info_along(2'b10),
		.mac_cell_i_vld(mac_cell_i_vld),
		
		.mac_cell_o_res(mac_cell_o_res),
		.mac_cell_o_info_along(mac_cell_o_info_along),
		.mac_cell_o_vld(mac_cell_o_vld),
		
		.mul_op_a(mul_op_a),
		.mul_op_b(mul_op_b),
		.mul_ce(mul_ce),
		.mul_res(mul_res)
	);
	
	genvar mul_i;
	generate
		if(INT16_SUPPORTED)
		begin:c_int16_supt
			for(mul_i = 0;mul_i < 4;mul_i = mul_i + 1)
			begin:mul_blk
				signed_mul #(
					.op_a_width(18),
					.op_b_width(18),
					.output_width(36),
					.simulation_delay(simulation_delay)
				)signed_mul_u(
					.clk(clk),
					
					.ce_s0_mul(mul_ce[mul_i]),
					
					.op_a(mul_op_a[mul_i*18+17:mul_i*18]),
					.op_b(mul_op_b[mul_i*18+17:mul_i*18]),
					
					.res(mul_res[mul_i*36+35:mul_i*36])
				);
			end
		end
		else
		begin:c_int16_not_supt
			reg signed[(INT32_SUPPORTED ? 64:50)-1:0] mul_res_r;
			reg signed[(INT32_SUPPORTED ? 64:50)-1:0] mul_res_d1;
			reg signed[(INT32_SUPPORTED ? 64:50)-1:0] mul_res_d2;
			
			assign mul_res = mul_res_d2;
			
			always @(posedge clk)
			begin
				if(mul_ce[0])
					mul_res_r <= # simulation_delay $signed(mul_op_a) * $signed(mul_op_b);
			end
			
			always @(posedge clk)
			begin
				if(mul_ce[1])
					mul_res_d1 <= # simulation_delay mul_res_r;
			end
			
			always @(posedge clk)
			begin
				if(mul_ce[2])
					mul_res_d2 <= # simulation_delay mul_res_d1;
			end
		end
	endgenerate
	
endmodule
