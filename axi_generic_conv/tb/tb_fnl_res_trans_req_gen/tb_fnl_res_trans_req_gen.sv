import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_defines.svh"
`include "utils.svh"

`include "panda_ext_trans.svh"

`include "panda_ext_scoreboard.svh"

`include "panda_test.svh"

module tb_fnl_res_trans_req_gen();
	
	/** 配置参数 **/
	parameter integer ATOMIC_K = 4; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	panda_blk_ctrl_if blk_ctrl_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if req_axis_s(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if msg_axis_s(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial begin
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(panda_blk_ctrl_vif)::set(null, "", "blk_ctrl_vif_m", blk_ctrl_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "req_axis_vif_s", req_axis_s);
		uvm_config_db #(panda_axis_vif)::set(null, "", "msg_axis_vif_s", msg_axis_s);
		
		run_test("fnl_res_trans_req_gen_test");
	end
	
	/** 乘法器 **/
	wire ce_umul0;
	wire[15:0] umul0_op_a;
	wire[23:0] umul0_op_b;
	wire[3:0] umul0_id_i;
	wire[39:0] umul0_res;
	reg[3:0] umul0_id_o;
	reg umul0_vld_o;
	
	always @(posedge clk_if.clk_p)
	begin
		if(ce_umul0)
			umul0_id_o <= umul0_id_i;
	end
	
	always @(posedge clk_if.clk_p or negedge rst_if.reset_n)
	begin
		if(~rst_if.reset_n)
			umul0_vld_o <= 1'b0;
		else
			umul0_vld_o <= ce_umul0;
	end
	
	unsigned_mul #(
		.op_a_width(16),
		.op_b_width(24),
		.output_width(40),
		.simulation_delay(0)
	)unsigned_mul_u0(
		.clk(clk_if.clk_p),
		
		.ce_s0_mul(ce_umul0),
		
		.op_a(umul0_op_a),
		.op_b(umul0_op_b),
		.res(umul0_res)
	);
	
	/** 待测模块 **/
	// 运行时参数
	wire[31:0] ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] ofmap_h; // 输出特征图高度 - 1
	wire[1:0] ofmap_data_type; // 输出特征图数据大小类型
	wire[15:0] kernal_num_n; // 卷积核核数 - 1
	wire[5:0] max_wgtblk_w; // 权重块最大宽度
	wire is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] group_n; // 分组数 - 1
	wire[15:0] n_foreach_group; // 每组的通道数/核数 - 1
	// 块级控制
	wire blk_start;
	wire blk_idle;
	wire blk_done;
	// 子表面行信息(AXIS主机)
	wire[15:0] m_sub_row_msg_axis_data; // {输出通道号(16bit)}
	wire m_sub_row_msg_axis_last; // 整个输出特征图的最后1个子表面行(标志)
	wire m_sub_row_msg_axis_valid;
	wire m_sub_row_msg_axis_ready;
	// DMA命令(AXIS主机)
	wire[55:0] m_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[24:0] m_dma_cmd_axis_user; // {命令ID(24bit), 固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_dma_cmd_axis_valid;
	wire m_dma_cmd_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] mul0_op_a; // 操作数A
	wire[23:0] mul0_op_b; // 操作数B
	wire[3:0] mul0_tid; // 操作ID
	wire mul0_req;
	wire mul0_grant;
	// [计算结果]
	wire[39:0] mul0_res;
	wire[3:0] mul0_oid;
	wire mul0_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] mul1_op_a; // 操作数A
	wire[23:0] mul1_op_b; // 操作数B
	wire[3:0] mul1_tid; // 操作ID
	wire mul1_req;
	wire mul1_grant;
	// [计算结果]
	wire[39:0] mul1_res;
	wire[3:0] mul1_oid;
	wire mul1_ovld;
	
	assign ce_umul0 = mul0_req | mul1_req;
	assign umul0_op_a = mul0_req ? mul0_op_a:mul1_op_a;
	assign umul0_op_b = mul0_req ? mul0_op_b:mul1_op_b;
	assign umul0_id_i = mul0_req ? mul0_tid:mul1_tid;
	
	assign mul0_grant = mul0_req;
	assign mul0_res = umul0_res;
	assign mul0_oid = umul0_id_o;
	assign mul0_ovld = umul0_vld_o;
	
	assign mul1_grant = mul1_req & (~mul0_req);
	assign mul1_res = umul0_res;
	assign mul1_oid = umul0_id_o;
	assign mul1_ovld = umul0_vld_o;
	
	assign blk_start = blk_ctrl_m.start;
	assign blk_ctrl_m.idle = blk_idle;
	assign blk_ctrl_m.done = blk_done;
	
	assign {
		n_foreach_group, group_n, is_grp_conv_mode,
		max_wgtblk_w, kernal_num_n, ofmap_data_type,
		ofmap_h, ofmap_w, ofmap_baseaddr
	} = blk_ctrl_m.params[120:0];
	
	assign msg_axis_s.data[15:0] = m_sub_row_msg_axis_data;
	assign msg_axis_s.last = m_sub_row_msg_axis_last;
	assign msg_axis_s.valid = m_sub_row_msg_axis_valid;
	assign m_sub_row_msg_axis_ready = msg_axis_s.ready;
	
	assign req_axis_s.data[55:0] = m_dma_cmd_axis_data;
	assign req_axis_s.user[24:0] = m_dma_cmd_axis_user;
	assign req_axis_s.valid = m_dma_cmd_axis_valid;
	assign m_dma_cmd_axis_ready = req_axis_s.ready;
	
	fnl_res_trans_req_gen #(
		.ATOMIC_K(ATOMIC_K),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		.aclken(1'b1),
		
		.ofmap_baseaddr(ofmap_baseaddr),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.kernal_num_n(kernal_num_n),
		.max_wgtblk_w(max_wgtblk_w),
		.is_grp_conv_mode(is_grp_conv_mode),
		.group_n(group_n),
		.n_foreach_group(n_foreach_group),
		
		.blk_start(blk_start),
		.blk_idle(blk_idle),
		.blk_done(blk_done),
		
		.m_sub_row_msg_axis_data(m_sub_row_msg_axis_data),
		.m_sub_row_msg_axis_last(m_sub_row_msg_axis_last),
		.m_sub_row_msg_axis_valid(m_sub_row_msg_axis_valid),
		.m_sub_row_msg_axis_ready(m_sub_row_msg_axis_ready),
		
		.m_dma_cmd_axis_data(m_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m_dma_cmd_axis_user),
		.m_dma_cmd_axis_valid(m_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m_dma_cmd_axis_ready),
		
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
