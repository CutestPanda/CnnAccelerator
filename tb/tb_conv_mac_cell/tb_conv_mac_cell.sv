`timescale 1ns / 1ps

module tb_conv_mac_cell();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned get_fp16(input int log_fid, input real d);
	import "DPI-C" function void print_fp16(input int log_fid, input int unsigned fp16);
	
	/** 常量 **/
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	localparam integer EN_SMALL_FP16 = "true"; // 是否处理极小FP16
	// 运行时参数
	localparam bit[1:0] CALFMT = CAL_FMT_FP16; // 运算数据格式
	// 测试配置
	localparam int unsigned TEST_N = 20; // 测试数据个数
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
	
	/** 主任务 **/
	// 乘加阵列计算输入
	reg[15:0] mac_in_ftm_arr[0:ATOMIC_C-1]; // 特征图数据(数组)
	reg[15:0] mac_in_wgt_arr[0:ATOMIC_C-1]; // 卷积核权重(数组)
	reg mac_in_valid; // 输入有效指示
	// 乘加阵列结果输出
	wire[7:0] mac_out_exp; // 指数部分(仅当运算数据格式为FP16时有效)
	wire signed[39:0] mac_out_frac; // 尾数部分或定点数
	wire mac_out_valid;
	// 日志文件句柄
	int log_fid;
	// 计算结果编号
	int unsigned res_id = 0;
	// 参考结果
	real ref_v = 0.0;
	
	generate
		if(CALFMT == CAL_FMT_FP16)
		begin
			initial
			begin
				log_fid = $fopen("log.txt");
				
				mac_in_valid <= 1'b0;
				
				@(posedge clk iff rst_n);
				
				repeat(TEST_N)
				begin
					automatic int unsigned wait_n = $urandom_range(0, 6);
					ref_v = 0.0;
					
					repeat(wait_n)
					begin
						@(posedge clk iff rst_n);
					end
					
					$fdisplay(log_fid, "************* input *************");
					for(int i = 0;i < ATOMIC_C;i++)
					begin
						automatic real ftm = $urandom_range(1, 65536) / 4096.0 - 12.0;
						automatic real wgt = $urandom_range(1, 65536) / 32768.0 - 1.0;
						automatic int unsigned ftm_int;
						automatic int unsigned wgt_int;
						
						if($urandom_range(0, 3) == 0)
							ftm = 0.0;
						if($urandom_range(0, 3) == 0)
							wgt = 0.0;
						
						ftm_int = get_fp16(log_fid, ftm);
						wgt_int = get_fp16(log_fid, wgt);
						
						mac_in_ftm_arr[i] <= # simulation_delay ftm_int[15:0];
						mac_in_wgt_arr[i] <= # simulation_delay wgt_int[15:0];
						
						$fdisplay(log_fid, "ftm = %f", ftm);
						$fdisplay(log_fid, "wgt = %f", wgt);
						
						ref_v += ftm * wgt;
					end
					$fdisplay(log_fid, "ref_v = %f", ref_v);
					$fdisplay(log_fid, "");
					
					mac_in_valid <= # simulation_delay 1'b1;
					
					@(posedge clk iff rst_n);
					
					mac_in_valid <= # simulation_delay 1'b0;
				end
			end
			
			initial
			begin
				forever
				begin
					@(posedge clk iff rst_n);
					
					if(mac_out_valid)
					begin
						$fdisplay(log_fid, "************* res *************");
						$fdisplay(log_fid, "res_exp = %d", mac_out_exp);
						$fdisplay(log_fid, "res_frac = %d", $signed(mac_out_frac));
						$fdisplay(log_fid, "");
						
						res_id++;
						
						if(res_id == TEST_N)
							$fclose(log_fid);
					end
				end
			end
		end
		else if(CALFMT == CAL_FMT_INT16)
		begin
			initial
			begin
				mac_in_valid <= 1'b0;
				
				@(posedge clk iff rst_n);
				
				repeat(TEST_N)
				begin
					automatic int unsigned wait_n = $urandom_range(0, 6);
					
					repeat(wait_n)
					begin
						@(posedge clk iff rst_n);
					end
					
					$fdisplay(log_fid, "************* input *************");
					for(int i = 0;i < ATOMIC_C;i++)
					begin
						automatic int unsigned ftm = $urandom_range(0, 20) - 10;
						automatic int unsigned wgt = $urandom_range(0, 20) - 10;
						
						mac_in_ftm_arr[i] <= # simulation_delay ftm;
						mac_in_wgt_arr[i] <= # simulation_delay wgt;
						
						$fdisplay(log_fid, "cid = %d, ftm = %d, wgt = %d", i, $signed(ftm), $signed(wgt));
					end
					$fdisplay(log_fid, "");
					
					mac_in_valid <= # simulation_delay 1'b1;
					
					@(posedge clk iff rst_n);
					
					mac_in_valid <= # simulation_delay 1'b0;
				end
			end
			
			initial
			begin
				forever
				begin
					@(posedge clk iff rst_n);
					
					if(mac_out_valid)
					begin
						$fdisplay(log_fid, "************* res *************");
						$fdisplay(log_fid, "res = %d", $signed(mac_out_frac));
						
						res_id++;
						
						if(res_id == TEST_N)
							$fclose(log_fid);
					end
				end
			end
		end
		else
		begin
			initial
			begin
				$error("CAL_FMT_INT8 is not supported!");
			end
		end
	endgenerate
	
	/** 待测模块 **/
	// 外部有符号乘法器
	wire[ATOMIC_C*16-1:0] mul_op_a; // 操作数A
	wire[ATOMIC_C*16-1:0] mul_op_b; // 操作数B
	wire mul_ce; // 计算使能
	wire[ATOMIC_C*32-1:0] mul_res; // 计算结果
	// 乘加阵列计算输入
	wire[ATOMIC_C*16-1:0] mac_in_ftm; // 特征图数据
	wire[ATOMIC_C*16-1:0] mac_in_wgt; // 卷积核权重
	
	genvar mul_i;
	generate
		for(mul_i = 0;mul_i < ATOMIC_C;mul_i = mul_i + 1)
		begin:mul_blk
			signed_mul #(
				.op_a_width(16),
				.op_b_width(16),
				.output_width(32),
				.simulation_delay(simulation_delay)
			)mul_u(
				.clk(clk),
				
				.ce_s0_mul(mul_ce),
				
				.op_a(mul_op_a[16*mul_i+15:16*mul_i]),
				.op_b(mul_op_b[16*mul_i+15:16*mul_i]),
				
				.res(mul_res[32*mul_i+31:32*mul_i])
			);
		end
	endgenerate
	
	genvar mac_in_i;
	generate
		for(mac_in_i = 0;mac_in_i < ATOMIC_C;mac_in_i = mac_in_i + 1)
		begin:mac_in_blk
			assign mac_in_ftm[16*mac_in_i+15:16*mac_in_i] = mac_in_ftm_arr[mac_in_i];
			assign mac_in_wgt[16*mac_in_i+15:16*mac_in_i] = mac_in_wgt_arr[mac_in_i];
		end
	endgenerate
	
	conv_mac_cell #(
		.ATOMIC_C(ATOMIC_C),
		.EN_SMALL_FP16(EN_SMALL_FP16),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.calfmt(CALFMT),
		
		.mac_in_ftm(mac_in_ftm),
		.mac_in_wgt(mac_in_wgt),
		.mac_in_valid(mac_in_valid),
		
		.mac_out_exp(mac_out_exp),
		.mac_out_frac(mac_out_frac),
		.mac_out_valid(mac_out_valid),
		
		.mul_op_a(mul_op_a),
		.mul_op_b(mul_op_b),
		.mul_ce(mul_ce),
		.mul_res(mul_res)
	);
	
endmodule
