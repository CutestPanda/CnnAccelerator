import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_trans.svh"

`include "panda_ext_scoreboard.svh"

`include "panda_test.svh"

module tb_fmap_sfc_row_access_req_gen();
	
	/** 配置参数 **/
	parameter integer ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	panda_blk_ctrl_if blk_ctrl_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if fmap_rd_req_axis_s(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial begin
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "blk_ctrl_vif_m", blk_ctrl_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "rd_req_axis_vif_s", fmap_rd_req_axis_s);
		
		run_test("fmap_sfc_row_access_req_gen_test");
	end
	
	/** 待测模块 **/
	// 运行时参数
	// [计算参数]
	wire[2:0] conv_vertical_stride; // 卷积垂直步长 - 1
	// [组卷积模式]
	wire is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] n_foreach_group; // 每组的通道数 - 1
	wire[31:0] data_size_foreach_group; // 每组的数据量
	// [特征图参数]
	wire[31:0] fmap_baseaddr; // 特征图数据基地址
	wire is_16bit_data; // 是否16位特征图数据
	wire[15:0] ifmap_w; // 输入特征图宽度 - 1
	wire[23:0] ifmap_size; // 输入特征图大小 - 1
	wire[15:0] ofmap_h; // 输出特征图高度 - 1
	wire[15:0] fmap_chn_n; // 通道数 - 1
	wire[15:0] ext_i_bottom; // 扩展后特征图的垂直边界
	wire[2:0] external_padding_top; // 上部外填充数
	wire[2:0] inner_padding_top_bottom; // 上下内填充数
	// [卷积核参数]
	wire[15:0] kernal_set_n; // 核组个数 - 1
	wire[3:0] kernal_dilation_vtc_n; // 垂直膨胀量
	wire[3:0] kernal_w; // (膨胀前)卷积核宽度 - 1
	wire[3:0] kernal_h; // (膨胀前)卷积核高度 - 1
	wire[4:0] kernal_h_dilated; // (膨胀后)卷积核高度 - 1
	// 块级控制
	wire blk_start;
	wire blk_idle;
	wire blk_done;
	// 特征图表面行读请求(AXIS主机)
	wire[103:0] m_fm_rd_req_axis_data;
	wire m_fm_rd_req_axis_valid;
	wire m_fm_rd_req_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] mul0_op_a; // 操作数A
	wire[15:0] mul0_op_b; // 操作数B
	wire[3:0] mul0_tid; // 操作ID
	wire mul0_req;
	wire mul0_grant;
	// [计算结果]
	reg[31:0] mul0_res;
	reg[3:0] mul0_oid;
	reg mul0_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] mul1_op_a; // 操作数A
	wire[23:0] mul1_op_b; // 操作数B
	wire[3:0] mul1_tid; // 操作ID
	wire mul1_req;
	wire mul1_grant;
	// [计算结果]
	reg[39:0] mul1_res;
	reg[3:0] mul1_oid;
	reg mul1_ovld;
	
	assign {
		kernal_h_dilated, kernal_h, kernal_w, kernal_dilation_vtc_n, kernal_set_n,
		inner_padding_top_bottom, external_padding_top, ext_i_bottom, fmap_chn_n, ofmap_h, ifmap_size, ifmap_w, is_16bit_data,
		fmap_baseaddr, data_size_foreach_group, n_foreach_group, is_grp_conv_mode, conv_vertical_stride
	} = blk_ctrl_m.params[211:0];
	assign blk_start = blk_ctrl_m.start;
	assign blk_ctrl_m.idle = blk_idle;
	assign blk_ctrl_m.done = blk_done;
	
	assign fmap_rd_req_axis_s.data = m_fm_rd_req_axis_data;
	assign fmap_rd_req_axis_s.valid = m_fm_rd_req_axis_valid;
	assign m_fm_rd_req_axis_ready = fmap_rd_req_axis_s.ready;
	
	assign mul0_grant = mul0_req;
	assign mul1_grant = mul1_req;
	
	always @(posedge clk_if.clk_p or negedge rst_if.reset_n)
	begin
		if(~rst_if.reset_n)
			mul0_ovld <= 1'b0;
		else
			mul0_ovld <= mul0_req;
	end
	
	always @(posedge clk_if.clk_p)
	begin
		if(mul0_req)
		begin
			mul0_res <= mul0_op_a * mul0_op_b;
			mul0_oid <= mul0_tid;
		end
	end
	
	always @(posedge clk_if.clk_p or negedge rst_if.reset_n)
	begin
		if(~rst_if.reset_n)
			mul1_ovld <= 1'b0;
		else
			mul1_ovld <= mul1_req;
	end
	
	always @(posedge clk_if.clk_p)
	begin
		if(mul1_req)
		begin
			mul1_res <= mul1_op_a * mul1_op_b;
			mul1_oid <= mul1_tid;
		end
	end
	
	fmap_sfc_row_access_req_gen #(
		.ATOMIC_C(ATOMIC_C),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		.aclken(1'b1),
		
		.conv_vertical_stride(conv_vertical_stride),
		.is_grp_conv_mode(is_grp_conv_mode),
		.n_foreach_group(n_foreach_group),
		.data_size_foreach_group(data_size_foreach_group),
		.fmap_baseaddr(fmap_baseaddr),
		.is_16bit_data(is_16bit_data),
		.ifmap_w(ifmap_w),
		.ifmap_size(ifmap_size),
		.ofmap_h(ofmap_h),
		.fmap_chn_n(fmap_chn_n),
		.ext_i_bottom(ext_i_bottom),
		.external_padding_top(external_padding_top),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.kernal_set_n(kernal_set_n),
		.kernal_dilation_vtc_n(kernal_dilation_vtc_n),
		.kernal_w(kernal_w),
		.kernal_h_dilated(kernal_h_dilated),
		
		.blk_start(blk_start),
		.blk_idle(blk_idle),
		.blk_done(blk_done),
		
		.m_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		
		.mul0_op_a(mul0_op_a),
		.mul0_op_b(mul0_op_b),
		.mul0_tid(mul0_tid),
		.mul0_req(mul0_req),
		.mul0_grant(mul0_grant),
		
		.mul0_res(mul0_res),
		.mul0_oid(mul0_oid),
		.mul0_ovld(mul0_ovld),
		
		.mul1_op_a(mul1_op_a),
		.mul1_op_b(mul1_op_b),
		.mul1_tid(mul1_tid),
		.mul1_req(mul1_req),
		.mul1_grant(mul1_grant),
		
		.mul1_res(mul1_res),
		.mul1_oid(mul1_oid),
		.mul1_ovld(mul1_ovld)
	);
	
endmodule
