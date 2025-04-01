`timescale 1ns / 1ps

module tb_conv_middle_res_accumulate();
	
	/** 导入C函数 **/
	import "DPI-C" function int unsigned get_fp16(input int log_fid, input real d);
	import "DPI-C" function void print_fp16(input int log_fid, input int unsigned fp16);
	import "DPI-C" function void print_fp32(input int log_fid, input int unsigned fp32);
	
	/** 常量 **/
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 配置参数 **/
	// 待测模块配置
	localparam EN_SMALL_FP32 = "false"; // 是否处理极小FP32
	// 运行时参数
	localparam bit[1:0] CALFMT = CAL_FMT_FP16; // 运算数据格式
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
	// {定点数(37位), 原中间结果(32位), 是否第1项标志(1位)}
	bit[69:0] int16_stim_arr[];
	// {指数部分(8位), 尾数部分(37位), 原中间结果(32位), 是否第1项标志(1位)}
	bit[77:0] fp16_stim_arr[];
	
	initial
	begin
		int16_stim_arr = new[10];
		
		int16_stim_arr[0][69:33] = $signed(252);
		int16_stim_arr[0][32:1] = $signed(100);
		int16_stim_arr[0][0] = 1'b1;
		
		int16_stim_arr[1][69:33] = $signed(-252);
		int16_stim_arr[1][32:1] = $signed(100);
		int16_stim_arr[1][0] = 1'b1;
		
		int16_stim_arr[2][69:33] = $signed(37'sd2 ** 33);
		int16_stim_arr[2][32:1] = $signed(100);
		int16_stim_arr[2][0] = 1'b1;
		
		int16_stim_arr[3][69:33] = $signed(-(37'sd2 ** 33));
		int16_stim_arr[3][32:1] = $signed(100);
		int16_stim_arr[3][0] = 1'b1;
		
		int16_stim_arr[4][69:33] = $signed((37'sd2 ** 31) - 1);
		int16_stim_arr[4][32:1] = $signed(100);
		int16_stim_arr[4][0] = 1'b0;
		
		int16_stim_arr[5][69:33] = $signed(-(37'sd2 ** 31));
		int16_stim_arr[5][32:1] = $signed(-100);
		int16_stim_arr[5][0] = 1'b0;
		
		int16_stim_arr[6][69:33] = $signed(7);
		int16_stim_arr[6][32:1] = $signed(8);
		int16_stim_arr[6][0] = 1'b0;
		
		int16_stim_arr[7][69:33] = $signed(-6);
		int16_stim_arr[7][32:1] = $signed(-15);
		int16_stim_arr[7][0] = 1'b0;
		
		int16_stim_arr[8][69:33] = $signed(9);
		int16_stim_arr[8][32:1] = $signed(-4);
		int16_stim_arr[8][0] = 1'b0;
		
		int16_stim_arr[9][69:33] = $signed(-34);
		int16_stim_arr[9][32:1] = $signed(12);
		int16_stim_arr[9][0] = 1'b0;
	end
	
	initial
	begin
		fp16_stim_arr = new[9];
		
		fp16_stim_arr[0][77:70] = 8'd28;
		fp16_stim_arr[0][69:33] = $signed(-47593944); // -11.3472805
		fp16_stim_arr[0][32:1] = 0;
		fp16_stim_arr[0][0] = 1'b1;
		
		fp16_stim_arr[1][77:70] = 8'd28;
		fp16_stim_arr[1][69:33] = $signed(9652630); // 2.301366329
		fp16_stim_arr[1][32:1] = 0;
		fp16_stim_arr[1][0] = 1'b1;
		
		fp16_stim_arr[2][77:70] = 8'd28;
		fp16_stim_arr[2][69:33] = $signed(-14147720); // -3.3730793
		fp16_stim_arr[2][32:1] = 32'hC2BD947B; // -94.79
		fp16_stim_arr[2][0] = 1'b0;
		
		fp16_stim_arr[3][77:70] = 8'd28;
		fp16_stim_arr[3][69:33] = $signed(9652630); // 2.301366329
		fp16_stim_arr[3][32:1] = 32'h3D8B4396; // 0.068
		fp16_stim_arr[3][0] = 1'b0;
		
		fp16_stim_arr[4][77:70] = 8'd28;
		fp16_stim_arr[4][69:33] = $signed(-14775660); // -3.522791862
		fp16_stim_arr[4][32:1] = 32'h40666666; // 3.6
		fp16_stim_arr[4][0] = 1'b0;
		
		fp16_stim_arr[5][77:70] = 8'd28;
		fp16_stim_arr[5][69:33] = $signed(32778064); // 7.814899445
		fp16_stim_arr[5][32:1] = 32'hC48596E1; // -1068.715
		fp16_stim_arr[5][0] = 1'b0;
		
		fp16_stim_arr[6][77:70] = 8'd28;
		fp16_stim_arr[6][69:33] = $signed(-32778064); // -7.814899445
		fp16_stim_arr[6][32:1] = 32'hC48596E1; // -1068.715
		fp16_stim_arr[6][0] = 1'b0;
		
		fp16_stim_arr[7][77:70] = 8'd24;
		fp16_stim_arr[7][69:33] = $signed(85784448); // 1.278287888
		fp16_stim_arr[7][32:1] = 32'hC2C63333; // -99.1
		fp16_stim_arr[7][0] = 1'b0;
		
		fp16_stim_arr[8][77:70] = 8'd24;
		fp16_stim_arr[8][69:33] = $signed(-85784448); // -1.278287888
		fp16_stim_arr[8][32:1] = 32'h3FA39581; // 1.278
		fp16_stim_arr[8][0] = 1'b0;
	end
	
	/** 主任务 **/
	// 中间结果累加输入
	reg[7:0] acmlt_in_exp; // 指数部分(仅当运算数据格式为FP16时有效)
	reg signed[39:0] acmlt_in_frac; // 尾数部分或定点数
	reg[31:0] acmlt_in_org_mid_res; // 原中间结果
	reg acmlt_in_first_item; // 是否第1项(标志)
	reg acmlt_in_valid; // 输入有效指示
	// 中间结果累加输出
	wire[31:0] acmlt_out_data; // 单精度浮点数或定点数
	wire acmlt_out_valid; // 输出有效指示
	// 日志文件句柄
	int log_fid;
	// 计算结果编号
	int unsigned res_id = 0;
	
	generate
		if(CALFMT == CAL_FMT_FP16)
		begin
			initial
			begin
				log_fid = $fopen("log.txt");
				
				acmlt_in_valid <= 1'b0;
				
				@(posedge clk iff rst_n);
				
				for(int i = 0;i < fp16_stim_arr.size();i++)
				begin
					automatic int unsigned wait_n = $urandom_range(0, 6);
					
					repeat(wait_n)
					begin
						@(posedge clk iff rst_n);
					end
					
					$fdisplay(log_fid, "************* input *************");
					$fdisplay(log_fid, "acmlt_in_exp = %d", fp16_stim_arr[i][77:70]);
					$fdisplay(log_fid, "acmlt_in_frac = %d", $signed(fp16_stim_arr[i][69:33]));
					$fdisplay(log_fid, "acmlt_in_org_mid_res = %8.8x", fp16_stim_arr[i][32:1]);
					$fdisplay(log_fid, "acmlt_in_first_item = %b", fp16_stim_arr[i][0]);
					$fdisplay(log_fid, "");
					
					acmlt_in_exp <= # simulation_delay fp16_stim_arr[i][77:70];
					acmlt_in_frac <= # simulation_delay $signed(fp16_stim_arr[i][69:33]);
					acmlt_in_org_mid_res <= # simulation_delay fp16_stim_arr[i][32:1];
					acmlt_in_first_item <= # simulation_delay fp16_stim_arr[i][0];
					acmlt_in_valid <= # simulation_delay 1'b1;
					
					@(posedge clk iff rst_n);
					
					acmlt_in_valid <= # simulation_delay 1'b0;
				end
			end
			
			initial
			begin
				forever
				begin
					@(posedge clk iff rst_n);
					
					if(acmlt_out_valid)
					begin
						$fdisplay(log_fid, "************* res *************");
						print_fp32(log_fid, acmlt_out_data);
						$fdisplay(log_fid, "");
						
						res_id++;
						
						if(res_id == fp16_stim_arr.size())
							$fclose(log_fid);
					end
				end
			end
		end
		else if(CALFMT == CAL_FMT_INT16)
		begin
			initial
			begin
				log_fid = $fopen("log.txt");
				
				acmlt_in_valid <= 1'b0;
				
				@(posedge clk iff rst_n);
				
				for(int i = 0;i < int16_stim_arr.size();i++)
				begin
					automatic int unsigned wait_n = $urandom_range(0, 6);
					
					repeat(wait_n)
					begin
						@(posedge clk iff rst_n);
					end
					
					$fdisplay(log_fid, "************* input *************");
					$fdisplay(log_fid, "acmlt_in_frac = %d", $signed(int16_stim_arr[i][69:33]));
					$fdisplay(log_fid, "acmlt_in_org_mid_res = %d", $signed(int16_stim_arr[i][32:1]));
					$fdisplay(log_fid, "acmlt_in_first_item = %b", int16_stim_arr[i][0]);
					$fdisplay(log_fid, "");
					
					acmlt_in_frac <= # simulation_delay $signed(int16_stim_arr[i][69:33]);
					acmlt_in_org_mid_res <= # simulation_delay $signed(int16_stim_arr[i][32:1]);
					acmlt_in_first_item <= # simulation_delay int16_stim_arr[i][0];
					acmlt_in_valid <= # simulation_delay 1'b1;
					
					@(posedge clk iff rst_n);
					
					acmlt_in_valid <= # simulation_delay 1'b0;
				end
			end
			
			initial
			begin
				forever
				begin
					@(posedge clk iff rst_n);
					
					if(acmlt_out_valid)
					begin
						$fdisplay(log_fid, "************* res *************");
						$fdisplay(log_fid, "res_int32 = %d", $signed(acmlt_out_data));
						$fdisplay(log_fid, "");
						
						res_id++;
						
						if(res_id == int16_stim_arr.size())
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
	conv_middle_res_accumulate #(
		.EN_SMALL_FP32(EN_SMALL_FP32),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.calfmt(CALFMT),
		
		.acmlt_in_exp(acmlt_in_exp),
		.acmlt_in_frac(acmlt_in_frac),
		.acmlt_in_org_mid_res(acmlt_in_org_mid_res),
		.acmlt_in_first_item(acmlt_in_first_item),
		.acmlt_in_valid(acmlt_in_valid),
		
		.acmlt_out_data(acmlt_out_data),
		.acmlt_out_valid(acmlt_out_valid)
	);
	
endmodule
