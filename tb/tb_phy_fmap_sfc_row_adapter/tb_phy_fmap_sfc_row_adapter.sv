import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_cfg.svh"

`include "panda_test.svh"

module tb_phy_fmap_sfc_row_adapter();
	
	/** 配置参数 **/
	parameter int ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter EN_ROW_AXIS_REG_SLICE = "true"; // 是否在物理特征图表面行数据AXIS接口插入寄存器片
	parameter EN_MAC_ARRAY_AXIS_REG_SLICE = "true"; // 是否在乘加阵列计算数据AXIS接口插入寄存器片
	parameter int CONV_HORIZONTAL_STRIDE = 1; // 卷积水平步长
	parameter int EXTERNAL_PADDING_LEFT = 0; // 左部外填充数
	parameter int EXTERNAL_PADDING_RIGHT = 0; // 右部外填充数
	parameter int INNER_PADDING_LEFT_RIGHT = 0; // 左右内填充数
	parameter int IFMAP_W = 10; // 输入特征图宽度
	parameter int KERNAL_DILATION_HZT_N = 0; // 水平膨胀量
	parameter int KERNAL_W = 3; // (膨胀前)卷积核宽度
	parameter int KERNAL_W_DILATED = KERNAL_W + (KERNAL_W-1)*KERNAL_DILATION_HZT_N; // (膨胀后)卷积核宽度
	parameter int OFMAP_W = 
		((EXTERNAL_PADDING_LEFT + IFMAP_W + (IFMAP_W - 1) * 
			INNER_PADDING_LEFT_RIGHT + EXTERNAL_PADDING_RIGHT) - KERNAL_W_DILATED) / CONV_HORIZONTAL_STRIDE + 1; // 输出特征图宽度
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	panda_axis_if rst_adapter_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if incr_traffic_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if fmap_row_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if mac_array_axis_s(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial
	begin
		PhyFmapSfcRowAdapterCfg test_cfg;
		
		test_cfg = PhyFmapSfcRowAdapterCfg::type_id::create();
		void'(test_cfg.randomize() with {
			atomic_c == ATOMIC_C;
			
			conv_horizontal_stride == CONV_HORIZONTAL_STRIDE;
			
			external_padding_left == EXTERNAL_PADDING_LEFT;
			external_padding_right == EXTERNAL_PADDING_RIGHT;
			inner_padding_left_right == INNER_PADDING_LEFT_RIGHT;
			ifmap_w == IFMAP_W;
			
			kernal_dilation_hzt_n == KERNAL_DILATION_HZT_N;
			kernal_w == KERNAL_W;
		});
		
		uvm_config_db #(PhyFmapSfcRowAdapterCfg)::set(null, "", "test_cfg", test_cfg);
		
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(panda_axis_vif)::set(null, "", "rst_adapter_vif_m", rst_adapter_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "incr_traffic_vif_m", incr_traffic_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "fmap_row_axis_vif_m", fmap_row_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "mac_array_axis_vif_s", mac_array_axis_s);
		
		run_test("phy_fmap_sfc_row_adapter_test");
	end
	
	/** 待测模块 **/
	// 重置适配器
	wire rst_adapter;
	// 特征图表面行流量
	wire on_incr_phy_row_traffic; // 增加1个物理特征图表面行流量(指示)
	wire[27:0] row_n_submitted_to_mac_array; // 已向乘加阵列提交的行数
	// 物理特征图表面行数据(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_fmap_row_axis_data;
	wire s_fmap_row_axis_last; // 标志物理特征图行的最后1个表面
	wire s_fmap_row_axis_valid;
	wire s_fmap_row_axis_ready;
	// 乘加阵列计算数据(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_mac_array_axis_data;
	wire m_mac_array_axis_last; // 卷积核参数对应的最后1个特征图表面(标志)
	wire m_mac_array_axis_user; // 标志本表面全0
	wire m_mac_array_axis_valid;
	wire m_mac_array_axis_ready;
	
	assign rst_adapter = rst_adapter_axis_m.valid;
	assign rst_adapter_axis_m.ready = 1'b1;
	
	assign on_incr_phy_row_traffic = incr_traffic_axis_m.valid;
	assign incr_traffic_axis_m.ready = 1'b1;
	
	assign s_fmap_row_axis_data = fmap_row_axis_m.data[ATOMIC_C*2*8-1:0];
	assign s_fmap_row_axis_last = fmap_row_axis_m.last;
	assign s_fmap_row_axis_valid = fmap_row_axis_m.valid;
	assign fmap_row_axis_m.ready = s_fmap_row_axis_ready;
	
	assign mac_array_axis_s.data[ATOMIC_C*2*8-1:0] = m_mac_array_axis_data;
	assign mac_array_axis_s.last = m_mac_array_axis_last;
	assign mac_array_axis_s.user[0] = m_mac_array_axis_user;
	assign mac_array_axis_s.valid = m_mac_array_axis_valid;
	assign m_mac_array_axis_ready = mac_array_axis_s.ready;
	
	phy_fmap_sfc_row_adapter #(
		.ATOMIC_C(ATOMIC_C),
		.EN_ROW_AXIS_REG_SLICE(EN_ROW_AXIS_REG_SLICE),
		.EN_MAC_ARRAY_AXIS_REG_SLICE(EN_MAC_ARRAY_AXIS_REG_SLICE),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		.aclken(1'b1),
		
		.rst_adapter(rst_adapter),
		
		.conv_horizontal_stride(CONV_HORIZONTAL_STRIDE - 1),
		.external_padding_left(EXTERNAL_PADDING_LEFT),
		.inner_padding_left_right(INNER_PADDING_LEFT_RIGHT),
		.ifmap_w(IFMAP_W - 1),
		.ofmap_w(OFMAP_W - 1),
		.kernal_dilation_hzt_n(KERNAL_DILATION_HZT_N),
		.kernal_w(KERNAL_W - 1),
		.kernal_w_dilated(KERNAL_W_DILATED - 1),
		
		.on_incr_phy_row_traffic(on_incr_phy_row_traffic),
		.row_n_submitted_to_mac_array(row_n_submitted_to_mac_array),
		
		.s_fmap_row_axis_data(s_fmap_row_axis_data),
		.s_fmap_row_axis_last(s_fmap_row_axis_last),
		.s_fmap_row_axis_valid(s_fmap_row_axis_valid),
		.s_fmap_row_axis_ready(s_fmap_row_axis_ready),
		
		.m_mac_array_axis_data(m_mac_array_axis_data),
		.m_mac_array_axis_last(m_mac_array_axis_last),
		.m_mac_array_axis_user(m_mac_array_axis_user),
		.m_mac_array_axis_valid(m_mac_array_axis_valid),
		.m_mac_array_axis_ready(m_mac_array_axis_ready)
	);
	
endmodule
