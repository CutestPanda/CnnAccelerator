import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_defines.svh"
`include "panda_ext_trans.svh"

`include "panda_ext_scoreboard.svh"

`include "panda_test.svh"

module tb_kernal_access_req_gen();
	
	/** 配置参数 **/
	parameter integer ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	panda_blk_ctrl_if blk_ctrl_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if kwgtblk_rd_req_axis_s(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial begin
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "blk_ctrl_vif_m", blk_ctrl_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "kwgtblk_rd_req_axis_vif_s", kwgtblk_rd_req_axis_s);
		
		run_test("kernal_access_req_gen_test");
	end
	
	/** 待测模块 **/
	// 运行时参数
	wire is_16bit_wgt; // 是否16位权重数据
	wire[31:0] kernal_wgt_baseaddr; // 卷积核权重基地址
	wire[15:0] kernal_chn_n; // 通道数 - 1
	wire[15:0] kernal_num_n; // 核数 - 1
	wire[2:0] kernal_shape; // 卷积核形状
	wire[15:0] ofmap_h; // 输出特征图高度 - 1
	wire is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] n_foreach_group; // 每组的通道数/核数 - 1
	wire[15:0] group_n; // 分组数 - 1
	wire[15:0] cgrpn_foreach_kernal_set; // 每个核组的通道组数 - 1
	wire[5:0] max_wgtblk_w; // 权重块最大宽度
	// 块级控制
	wire blk_start;
	wire blk_idle;
	wire blk_done;
	// 卷积核权重块读请求(AXIS主机)
	wire[103:0] m_kwgtblk_rd_req_axis_data;
	wire m_kwgtblk_rd_req_axis_valid;
	wire m_kwgtblk_rd_req_axis_ready;
	// 共享无符号乘法器
	// [通道#0]
	wire[15:0] shared_mul_c0_op_a; // 操作数A
	wire[15:0] shared_mul_c0_op_b; // 操作数B
	wire[3:0] shared_mul_c0_tid; // 操作ID
	wire shared_mul_c0_req;
	wire shared_mul_c0_grant;
	// [计算结果]
	reg[31:0] shared_mul_res;
	reg[3:0] shared_mul_oid;
	reg shared_mul_ovld;
	
	assign blk_start = blk_ctrl_m.start;
	assign blk_ctrl_m.idle = blk_idle;
	assign blk_ctrl_m.done = blk_done;
	
	assign {
		max_wgtblk_w,
		cgrpn_foreach_kernal_set, group_n, n_foreach_group, is_grp_conv_mode, ofmap_h, kernal_shape, kernal_num_n,
		kernal_chn_n, kernal_wgt_baseaddr, is_16bit_wgt
	} = blk_ctrl_m.params[138:0];
	
	assign kwgtblk_rd_req_axis_s.data = m_kwgtblk_rd_req_axis_data;
	assign kwgtblk_rd_req_axis_s.valid = m_kwgtblk_rd_req_axis_valid;
	assign m_kwgtblk_rd_req_axis_ready = kwgtblk_rd_req_axis_s.ready;
	
	assign shared_mul_c0_grant = shared_mul_c0_req;
	
	always @(posedge clk_if.clk_p or negedge rst_if.reset_n)
	begin
		if(~rst_if.reset_n)
			shared_mul_ovld <= 1'b0;
		else
			shared_mul_ovld <= shared_mul_c0_req;
	end
	
	always @(posedge clk_if.clk_p)
	begin
		if(shared_mul_c0_req)
		begin
			shared_mul_res <= shared_mul_c0_op_a * shared_mul_c0_op_b;
			shared_mul_oid <= shared_mul_c0_tid;
		end
	end
	
	kernal_access_req_gen #(
		.ATOMIC_C(ATOMIC_C),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		.aclken(1'b1),
		
		.is_16bit_wgt(is_16bit_wgt),
		.kernal_wgt_baseaddr(kernal_wgt_baseaddr),
		.kernal_chn_n(kernal_chn_n),
		.kernal_num_n(kernal_num_n),
		.kernal_shape(kernal_shape),
		.ofmap_h(ofmap_h),
		.is_grp_conv_mode(is_grp_conv_mode),
		.n_foreach_group(n_foreach_group),
		.group_n(group_n),
		.cgrpn_foreach_kernal_set(cgrpn_foreach_kernal_set),
		.max_wgtblk_w(max_wgtblk_w),
		
		.blk_start(blk_start),
		.blk_idle(blk_idle),
		.blk_done(blk_done),
		
		.m_kwgtblk_rd_req_axis_data(m_kwgtblk_rd_req_axis_data),
		.m_kwgtblk_rd_req_axis_valid(m_kwgtblk_rd_req_axis_valid),
		.m_kwgtblk_rd_req_axis_ready(m_kwgtblk_rd_req_axis_ready),
		
		.shared_mul_c0_op_a(shared_mul_c0_op_a),
		.shared_mul_c0_op_b(shared_mul_c0_op_b),
		.shared_mul_c0_tid(shared_mul_c0_tid),
		.shared_mul_c0_req(shared_mul_c0_req),
		.shared_mul_c0_grant(shared_mul_c0_grant),
		.shared_mul_res(shared_mul_res),
		.shared_mul_oid(shared_mul_oid),
		.shared_mul_ovld(shared_mul_ovld)
	);
	
endmodule
