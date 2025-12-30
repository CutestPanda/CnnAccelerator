`timescale 1ns / 1ps

module tb_sigmoid_cell();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned encode_fp16(input real d);
	import "DPI-C" function int unsigned encode_fp32(input real d);
	import "DPI-C" function int unsigned fp32_mac(input int unsigned a, input int unsigned x, input int unsigned b);
	import "DPI-C" function real decode_fp16(input int unsigned fp16);
	import "DPI-C" function real decode_fp32(input int unsigned fp32);
	import "DPI-C" function real get_fixed36_exp(input longint frac, input int exp);
	
	/** 常量 **/
	// 运算数据格式的编码
	localparam ACT_CAL_FMT_INT16 = 2'b00;
	localparam ACT_CAL_FMT_INT32 = 2'b01;
	localparam ACT_CAL_FMT_FP32 = 2'b10;
	localparam ACT_CAL_FMT_NONE = 2'b11;
	
	/** 配置参数 **/
	localparam INT16_SUPPORTED = 1'b1; // 是否支持INT16运算数据格式
	localparam INT32_SUPPORTED = 1'b1; // 是否支持INT32运算数据格式
	localparam FP32_SUPPORTED = 1'b1; // 是否支持FP32运算数据格式
	localparam integer INFO_ALONG_WIDTH = 2; // 随路数据的位宽
	localparam LUT_MEM_INIT_FILENAME = "act_sigmoid.txt"; // Sigmoid查找表存储器初始化文件路径
	// 运算数据格式
	localparam logic[1:0] act_calfmt = ACT_CAL_FMT_FP32;
	// 输入定点数量化精度
	localparam logic[4:0] in_fixed_point_quat_accrc = 
		(act_calfmt == ACT_CAL_FMT_FP32)  ? 5'dx:
		(act_calfmt == ACT_CAL_FMT_INT32) ? 5'd8:
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
	reg[31:0] act_cell_i_op_x; // 操作数X
	reg act_cell_i_pass; // 不作激活处理(标志)
	reg act_cell_i_vld;
	
	task rst_in_bus();
		act_cell_i_op_x <= # simulation_delay 32'dx;
		act_cell_i_pass <= # simulation_delay 1'bx;
		act_cell_i_vld <= # simulation_delay 1'b0;
	endtask
	
	task drive_in_bus_fp(
		input real x, input bit pass, input int unsigned delay
	);
		int unsigned x_encoded;
		
		x_encoded = encode_fp32(x);
		
		act_cell_i_op_x <= # simulation_delay x_encoded;
		
		act_cell_i_pass <= # simulation_delay pass;
		act_cell_i_vld <= # simulation_delay 1'b1;
		
		@(posedge clk);
		
		rst_in_bus();
		
		repeat(delay)
			@(posedge clk);
	endtask
	
	task drive_in_bus_int32(
		input int x, input bit pass, input int unsigned delay
	);
		act_cell_i_op_x <= # simulation_delay x;
		
		act_cell_i_pass <= # simulation_delay pass;
		act_cell_i_vld <= # simulation_delay 1'b1;
		
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
		drive_in_bus_fp(0.001, 1'b0, 0);
		drive_in_bus_fp(0.2, 1'b0, 0);
		drive_in_bus_fp(0.0, 1'b0, 0);
		
		drive_in_bus_fp(-1.6, 1'b0, 0);
		drive_in_bus_fp(-9.6, 1'b0, 0);
		drive_in_bus_fp(-44.9, 1'b0, 0);
		drive_in_bus_fp(-0.001, 1'b0, 0);
		drive_in_bus_fp(-0.2, 1'b0, 0);
		drive_in_bus_fp(0.0, 1'b0, 0);
		
		drive_in_bus_fp(1.6, 1'b1, 0);
		drive_in_bus_fp(9.6, 1'b1, 0);
		drive_in_bus_fp(44.9, 1'b1, 0);
		drive_in_bus_fp(0.001, 1'b1, 0);
		drive_in_bus_fp(0.2, 1'b1, 0);
		drive_in_bus_fp(0.0, 1'b1, 0);
		
		drive_in_bus_fp(-1.6, 1'b1, 0);
		drive_in_bus_fp(-9.6, 1'b1, 0);
		drive_in_bus_fp(-44.9, 1'b1, 0);
		drive_in_bus_fp(-0.001, 1'b1, 0);
		drive_in_bus_fp(-0.2, 1'b1, 0);
		drive_in_bus_fp(0.0, 1'b1, 0);
	endtask
	
	task test_int32();
		rst_in_bus();
		
		@(posedge clk iff rst_n);
		
		drive_in_bus_int32(40, 1'b0, 0);
		drive_in_bus_int32(803, 1'b0, 0);
		drive_in_bus_int32(0, 1'b0, 0);
		
		drive_in_bus_int32(-40, 1'b0, 0);
		drive_in_bus_int32(-803, 1'b0, 0);
		drive_in_bus_int32(0, 1'b0, 0);
		
		drive_in_bus_int32(40, 1'b1, 0);
		drive_in_bus_int32(803, 1'b1, 0);
		drive_in_bus_int32(0, 1'b1, 0);
		
		drive_in_bus_int32(-40, 1'b1, 0);
		drive_in_bus_int32(-803, 1'b1, 0);
		drive_in_bus_int32(0, 1'b1, 0);
	endtask
	
	initial
	begin
		if(act_calfmt == ACT_CAL_FMT_FP32)
			test_fp32();
		else if(act_calfmt == ACT_CAL_FMT_INT32)
			test_int32();
		else if(act_calfmt == ACT_CAL_FMT_INT16)
			test_int32();
	end
	
	/** 待测模块 **/
	// 查找表
	wire lut_mem_clk_a;
	wire lut_mem_ren_a;
	wire[11:0] lut_mem_addr_a;
	wire[15:0] lut_mem_dout_a;
	
	sigmoid_cell #(
		.INT16_SUPPORTED(INT16_SUPPORTED),
		.INT32_SUPPORTED(INT32_SUPPORTED),
		.FP32_SUPPORTED(FP32_SUPPORTED),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.act_calfmt(act_calfmt),
		.in_fixed_point_quat_accrc(in_fixed_point_quat_accrc),
		
		.act_cell_i_op_x(act_cell_i_op_x),
		.act_cell_i_pass(act_cell_i_pass),
		.act_cell_i_info_along(2'b01),
		.act_cell_i_vld(act_cell_i_vld),
		
		.act_cell_o_res(),
		.act_cell_o_info_along(),
		.act_cell_o_vld(),
		
		.lut_mem_clk_a(lut_mem_clk_a),
		.lut_mem_ren_a(lut_mem_ren_a),
		.lut_mem_addr_a(lut_mem_addr_a),
		.lut_mem_dout_a(lut_mem_dout_a)
	);
	
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("read_first"),
		.mem_width(16),
		.mem_depth(4096),
		.INIT_FILE(LUT_MEM_INIT_FILENAME),
		.byte_write_mode("false"),
		.simulation_delay(simulation_delay)
	)lut_mem_u(
		.clk(lut_mem_clk_a),
		
		.en(lut_mem_ren_a),
		.wen(1'b0),
		.addr(lut_mem_addr_a),
		.din(16'hxxxx),
		.dout(lut_mem_dout_a)
	);
	
endmodule
