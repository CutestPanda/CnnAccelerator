import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_defines.svh"

`include "utils.svh"

`include "panda_data_obj.svh"
`include "panda_ext_trans.svh"

`include "panda_ext_scoreboard.svh"

`include "panda_test.svh"

module tb_conv_mac_array();
	
	/** 常量 **/
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 配置参数 **/
	parameter integer MAX_CAL_ROUND = 2; // 最大的计算轮次(1~16)
	parameter integer ATOMIC_K = 8; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter EN_SMALL_FP16 = "true"; // 是否处理极小FP16
	parameter integer INFO_ALONG_WIDTH = 4; // 随路数据的位宽(必须>=1)
	parameter USE_INNER_SFC_CNT = "true"; // 是否使用内部表面计数器
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	panda_axis_if array_i_ftm_if_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if array_i_kernal_if_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if array_o_if_s(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial begin
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(panda_axis_vif)::set(null, "", "array_i_ftm_vif_m", array_i_ftm_if_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "array_i_kernal_vif_m", array_i_kernal_if_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "array_o_vif_s", array_o_if_s);
		
		run_test("conv_mac_array_test");
	end
	
	/** 待测模块 **/
	// 使能信号
	wire en_mac_array; // 使能乘加阵列
	// 运行时参数
	wire[1:0] calfmt; // 运算数据格式
	wire[3:0] cal_round; // 计算轮次 - 1
	// 乘加阵列输入
	// [特征图]
	wire[ATOMIC_C*16-1:0] array_i_ftm_sfc; // 特征图表面(数据)
	wire[INFO_ALONG_WIDTH-1:0] array_i_ftm_info_along; // 随路数据
	wire array_i_ftm_sfc_last; // 卷积核参数对应的最后1个特征图表面(标志)
	wire array_i_ftm_sfc_vld; // 有效标志
	wire array_i_ftm_sfc_rdy; // 就绪标志
	// [卷积核]
	wire[ATOMIC_C*16-1:0] array_i_kernal_sfc; // 卷积核表面(数据)
	wire array_i_kernal_sfc_last; // 卷积核权重块对应的最后1个表面(标志)
	// 说明: 仅当不使用内部表面计数器(USE_INNER_SFC_CNT == "false")时可用
	wire[MAX_CAL_ROUND*ATOMIC_K-1:0] array_i_kernal_sfc_id; // 卷积核表面在权重块中的独热码编号
	wire array_i_kernal_sfc_vld; // 有效指示
	wire array_i_kernal_buf_full_n; // 卷积核权重缓存满(标志)
	// 乘加阵列输出
	wire[ATOMIC_K*48-1:0] array_o_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[3:0] array_o_cal_round_id; // 计算轮次编号
	wire array_o_is_last_cal_round; // 是否最后1轮计算
	wire[INFO_ALONG_WIDTH-1:0] array_o_res_info_along; // 随路数据
	wire[ATOMIC_K-1:0] array_o_res_mask; // 计算结果输出项掩码
	wire array_o_res_vld; // 有效标志
	wire array_o_res_rdy; // 就绪标志
	// 外部有符号乘法器
	wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_a; // 操作数A
	wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_b; // 操作数B
	wire[ATOMIC_K-1:0] mul_ce; // 计算使能
	wire[ATOMIC_K*ATOMIC_C*32-1:0] mul_res; // 计算结果
	
	assign en_mac_array = 1'b1;
	
	assign calfmt = CAL_FMT_FP16;
	assign cal_round = MAX_CAL_ROUND - 1;
	
	assign array_i_ftm_sfc = array_i_ftm_if_m.data[ATOMIC_C*16-1:0];
	assign array_i_ftm_info_along = array_i_ftm_if_m.user[INFO_ALONG_WIDTH-1:0];
	assign array_i_ftm_sfc_last = array_i_ftm_if_m.last;
	assign array_i_ftm_sfc_vld = array_i_ftm_if_m.valid;
	assign array_i_ftm_if_m.ready = array_i_ftm_sfc_rdy;
	
	assign array_i_kernal_sfc = array_i_kernal_if_m.data[ATOMIC_C*16-1:0];
	assign array_i_kernal_sfc_last = array_i_kernal_if_m.last;
	assign array_i_kernal_sfc_id = {(MAX_CAL_ROUND*ATOMIC_K){1'bx}};
	assign array_i_kernal_sfc_vld = array_i_kernal_if_m.valid;
	assign array_i_kernal_if_m.ready = array_i_kernal_buf_full_n;
	
	assign array_o_if_s.data[ATOMIC_K*48-1:0] = array_o_res;
	assign array_o_if_s.user[ATOMIC_K+INFO_ALONG_WIDTH+4+1-1:0] = 
		{array_o_res_mask, array_o_res_info_along, array_o_cal_round_id, array_o_is_last_cal_round};
	assign array_o_if_s.valid = array_o_res_vld;
	assign array_o_res_rdy = array_o_if_s.ready;
	
	genvar mul_i;
	generate
		for(mul_i = 0;mul_i < ATOMIC_K*ATOMIC_C;mul_i = mul_i + 1)
		begin:mul_blk
			mul #(
				.op_a_width(16),
				.op_b_width(16),
				.output_width(32),
				.simulation_delay(0)
			)mul_u(
				.clk(clk_if.clk_p),
				
				.ce_s0_mul(mul_ce[mul_i/ATOMIC_C]),
				
				.op_a(mul_op_a[16*mul_i+15:16*mul_i]),
				.op_b(mul_op_b[16*mul_i+15:16*mul_i]),
				
				.res(mul_res[32*mul_i+31:32*mul_i])
			);
		end
	endgenerate
	
	conv_mac_array #(
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.ATOMIC_K(ATOMIC_K),
		.ATOMIC_C(ATOMIC_C),
		.EN_SMALL_FP16(EN_SMALL_FP16),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.USE_INNER_SFC_CNT(USE_INNER_SFC_CNT),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		.aclken(1'b1),
		
		.en_mac_array(en_mac_array),
		
		.calfmt(calfmt),
		.cal_round(cal_round),
		
		.array_i_ftm_sfc(array_i_ftm_sfc),
		.array_i_ftm_info_along(array_i_ftm_info_along),
		.array_i_ftm_sfc_last(array_i_ftm_sfc_last),
		.array_i_ftm_sfc_vld(array_i_ftm_sfc_vld),
		.array_i_ftm_sfc_rdy(array_i_ftm_sfc_rdy),
		
		.array_i_kernal_sfc(array_i_kernal_sfc),
		.array_i_kernal_sfc_last(array_i_kernal_sfc_last),
		.array_i_kernal_sfc_id(array_i_kernal_sfc_id),
		.array_i_kernal_sfc_vld(array_i_kernal_sfc_vld),
		.array_i_kernal_buf_full_n(array_i_kernal_buf_full_n),
		
		.array_o_res(array_o_res),
		.array_o_cal_round_id(array_o_cal_round_id),
		.array_o_is_last_cal_round(array_o_is_last_cal_round),
		.array_o_res_info_along(array_o_res_info_along),
		.array_o_res_mask(array_o_res_mask),
		.array_o_res_vld(array_o_res_vld),
		.array_o_res_rdy(array_o_res_rdy),
		
		.mul_op_a(mul_op_a),
		.mul_op_b(mul_op_b),
		.mul_ce(mul_ce),
		.mul_res(mul_res)
	);
	
endmodule
