import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_cfg.svh"

`include "panda_test.svh"

module tb_conv_middle_res_info_packer();
	
	/** 配置参数 **/
	parameter integer ATOMIC_K = 2; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter int OFMAP_W = 2; // 输出特征图宽度
	parameter int KERNAL_W = 1; // (膨胀前)卷积核宽度
	parameter int CGRP_N_OF_FMAP_REGION_THAT_KERNAL_SET_SEL = 1; // 核组所选定特征图域的通道组数
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	panda_axis_if fm_cake_info_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if mac_array_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if pkt_out_axis_s(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial
	begin
		MidResInfoPackerCfg test_cfg;
		
		test_cfg = MidResInfoPackerCfg::type_id::create();
		void'(test_cfg.randomize() with {
			atomic_k == ATOMIC_K;
			
			ofmap_w == OFMAP_W;
			kernal_w == KERNAL_W;
			cgrp_n_of_fmap_region_that_kernal_set_sel == CGRP_N_OF_FMAP_REGION_THAT_KERNAL_SET_SEL;
			
			cal_round_n == 2;
		});
		
		uvm_config_db #(MidResInfoPackerCfg)::set(null, "", "test_cfg", test_cfg);
		
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(panda_axis_vif)::set(null, "", "fm_cake_info_vif_m", fm_cake_info_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "mac_array_vif_m", mac_array_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "pkt_out_vif_s", pkt_out_axis_s);
		
		run_test("conv_middle_res_info_packer_test");
	end
	
	/** 待测模块 **/
	// 使能信号
	wire en_packer; // 使能打包器
	// 特征图切块信息(AXIS从机)
	wire[7:0] s_fm_cake_info_axis_data; // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	wire s_fm_cake_info_axis_valid;
	wire s_fm_cake_info_axis_ready;
	// 乘加阵列得到的中间结果
	wire[ATOMIC_K*48-1:0] mac_array_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire mac_array_is_last_cal_round; // 是否最后1轮计算
	wire[ATOMIC_K-1:0] mac_array_res_mask; // 计算结果输出项掩码
	wire mac_array_res_vld; // 有效标志
	wire mac_array_res_rdy; // 就绪标志
	// 打包后的中间结果(AXIS主机)
	wire[ATOMIC_K*48-1:0] m_axis_pkt_out_data; // ATOMIC_K个中间结果
	                                           // ({指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[ATOMIC_K*6-1:0] m_axis_pkt_out_keep;
	wire[1:0] m_axis_pkt_out_user; // {初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_pkt_out_valid;
	wire m_axis_pkt_out_ready;
	
	assign en_packer = 1'b1;
	
	assign s_fm_cake_info_axis_data = fm_cake_info_axis_m.data[7:0];
	assign s_fm_cake_info_axis_valid = fm_cake_info_axis_m.valid;
	assign fm_cake_info_axis_m.ready = s_fm_cake_info_axis_ready;
	
	assign mac_array_res = mac_array_axis_m.data[ATOMIC_K*48-1:0];
	assign {mac_array_res_mask, mac_array_is_last_cal_round} = mac_array_axis_m.user[ATOMIC_K:0];
	assign mac_array_res_vld = mac_array_axis_m.valid;
	assign mac_array_axis_m.ready = mac_array_res_rdy;
	
	assign pkt_out_axis_s.data[ATOMIC_K*48-1:0] = m_axis_pkt_out_data;
	assign pkt_out_axis_s.keep[ATOMIC_K*6-1:0] = m_axis_pkt_out_keep;
	assign pkt_out_axis_s.user[1:0] = m_axis_pkt_out_user;
	assign pkt_out_axis_s.valid = m_axis_pkt_out_valid;
	assign m_axis_pkt_out_ready = pkt_out_axis_s.ready;
	
	conv_middle_res_info_packer #(
		.ATOMIC_K(ATOMIC_K),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		.aclken(1'b1),
		
		.en_packer(en_packer),
		
		.ofmap_w(OFMAP_W - 1),
		.kernal_w(KERNAL_W - 1),
		.cgrp_n_of_fmap_region_that_kernal_set_sel(CGRP_N_OF_FMAP_REGION_THAT_KERNAL_SET_SEL - 1),
		
		.s_fm_cake_info_axis_data(s_fm_cake_info_axis_data),
		.s_fm_cake_info_axis_valid(s_fm_cake_info_axis_valid),
		.s_fm_cake_info_axis_ready(s_fm_cake_info_axis_ready),
		
		.mac_array_res(mac_array_res),
		.mac_array_is_last_cal_round(mac_array_is_last_cal_round),
		.mac_array_res_mask(mac_array_res_mask),
		.mac_array_res_vld(mac_array_res_vld),
		.mac_array_res_rdy(mac_array_res_rdy),
		
		.m_axis_pkt_out_data(m_axis_pkt_out_data),
		.m_axis_pkt_out_keep(m_axis_pkt_out_keep),
		.m_axis_pkt_out_user(m_axis_pkt_out_user),
		.m_axis_pkt_out_valid(m_axis_pkt_out_valid),
		.m_axis_pkt_out_ready(m_axis_pkt_out_ready)
	);
	
endmodule
