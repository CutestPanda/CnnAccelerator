/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/


/********************************************************************
本模块: (逻辑)卷积核缓存

描述:
处于组卷积缓存模式 -> 
	物理卷积核缓存只有驻留区
	存储整个核组

不处于组卷积缓存模式 -> 
	将物理卷积核缓存分为驻留区和交换区
	若可缓存的通道组数 >= 实际通道组数, 则逻辑卷积核缓存全为驻留区, 否则设置2个交换区而其余为驻留区
	先将通道组存储在驻留区, 仅当驻留区满时才开始存储在交换区, 且优先存储在交换区#0
	要释放一个交换区通道组, 需要给出置换指示信号, 或者在发起权重块读请求时指定需要自动置换交换区通道组

支持的卷积核大小 -> 1x1, 3x3, 5x5, 7x7, 9x9, 11x11

注意：
暂不支持INT8运算数据格式

在输入通道组数据流中, 应当连续输入1个通道组的权重数据
在发起权重块读请求前, 应当检查这个权重块是否已缓存, 否则会在输出权重块数据流中给出错误标志

卷积核缓存ICB主机应当至少具有1clk的响应时延

在使用逻辑卷积核缓存前, 或者当切换核组时, 必须先重置(将rst_logic_kbuf置高)

处于组卷积缓存模式时, 必须保证物理卷积核缓存可存下整个核组

协议:
AXIS MASTER/SLAVE
ICB MASTER

作者: 陈家耀
日期: 2025/11/03
********************************************************************/


module logic_kernal_buffer #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire grp_conv_buf_mode, // 是否处于组卷积缓存模式
	input wire[2:0] kbufgrpsz, // 每个通道组的权重块个数的类型
	input wire[2:0] sfc_n_each_wgtblk, // 每个权重块的表面个数的类型
	input wire[7:0] kbufgrpn, // 可缓存的通道组数 - 1
	
	// 核组参数
	input wire[9:0] cgrpn, // 实际通道组数 - 1
	
	// 控制信号
	input wire rst_logic_kbuf, // 重置逻辑卷积核缓存
	// 说明: 仅当"不处于组卷积缓存模式"时可用
	input wire[1:0] sw_rgn_rplc, // 置换交换区通道组({通道组#1, 通道组#0})
	
	// 状态信号
	/*********** 说明: 以下仅当"不处于组卷积缓存模式"时有效 ***********/
	output wire[8:0] rsv_rgn_vld_grpn, // 驻留区有效通道组数
	output wire[1:0] sw_rgn_vld, // 交换区通道组有效({通道组#1, 通道组#0})
	output wire[9:0] sw_rgn0_grpid, // 交换区通道组#0实际通道组号
	output wire[9:0] sw_rgn1_grpid, // 交换区通道组#1实际通道组号
	output wire has_sw_rgn, // 是否存在交换区
	/*********** 说明: 以上仅当"不处于组卷积缓存模式"时有效 ***********/
	output wire rsv_rgn_full, // 驻留区满标志
	output wire[3:0] cgrp_stored_rd_req_eid, // 新存入通道组对应的读请求项索引
	output wire cgrp_stored_vld, // 通道组存储完成
	
	// 输入通道组数据流(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_in_cgrp_axis_data,
	input wire[ATOMIC_C*2-1:0] s_in_cgrp_axis_keep,
	input wire[14:0] s_in_cgrp_axis_user, // {读请求项索引(4bit), 实际通道组号(10bit), 标志通道组的最后1个权重块(1bit)}
	input wire s_in_cgrp_axis_last, // 标志权重块的最后1个表面
	input wire s_in_cgrp_axis_valid,
	output wire s_in_cgrp_axis_ready,
	
	// 权重块读请求(AXIS从机)
	/*
	说明: 
		"自动置换交换区通道组"仅当"不处于组卷积缓存模式"时可用
		
		请求格式 -> 
			{
				保留(2bit), 
				是否需要自动置换交换区通道组(1bit), 
				实际通道组号(10bit), 
				权重块编号(7bit), 
				起始表面编号(7bit), 
				待读取的表面个数 - 1(5bit)
			}
	*/
	input wire[31:0] s_rd_req_axis_data,
	input wire s_rd_req_axis_valid,
	output wire s_rd_req_axis_ready,
	// 输出权重块数据流(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_out_wgtblk_axis_data,
	output wire m_out_wgtblk_axis_user, // 标志权重块未找到
	output wire m_out_wgtblk_axis_last, // 标志本次读请求的最后1个表面
	output wire m_out_wgtblk_axis_valid,
	input wire m_out_wgtblk_axis_ready,
	
	// 卷积核缓存ICB主机#0
	// 命令通道
	output wire[31:0] m0_kbuf_cmd_addr,
	output wire m0_kbuf_cmd_read, // const -> 1'b0
	output wire[ATOMIC_C*2*8-1:0] m0_kbuf_cmd_wdata,
	output wire[ATOMIC_C*2-1:0] m0_kbuf_cmd_wmask, // const -> {(ATOMIC_C*2){1'b1}}
	output wire m0_kbuf_cmd_valid,
	input wire m0_kbuf_cmd_ready,
	// 响应通道
	input wire[ATOMIC_C*2*8-1:0] m0_kbuf_rsp_rdata, // ignored
	input wire m0_kbuf_rsp_err, // ignored
	input wire m0_kbuf_rsp_valid,
	output wire m0_kbuf_rsp_ready, // const -> 1'b1
	
	// 卷积核缓存ICB主机#1
	// 命令通道
	output wire[31:0] m1_kbuf_cmd_addr,
	output wire m1_kbuf_cmd_read, // const -> 1'b1
	output wire[ATOMIC_C*2*8-1:0] m1_kbuf_cmd_wdata, // not care
	output wire[ATOMIC_C*2-1:0] m1_kbuf_cmd_wmask, // not care
	output wire m1_kbuf_cmd_valid,
	input wire m1_kbuf_cmd_ready,
	// 响应通道
	input wire[ATOMIC_C*2*8-1:0] m1_kbuf_rsp_rdata,
	input wire m1_kbuf_rsp_err, // ignored
	input wire m1_kbuf_rsp_valid,
	output wire m1_kbuf_rsp_ready,
	
	// 错误指示
	output wire wt_rsv_rgn_actual_gid_mismatch // 写驻留区时实际通道组号不符合要求
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 常量 **/
	// 每个通道组的权重块个数的类型编码
	localparam KBUFGRPSZ_1 = 3'b000; // 1x1
	localparam KBUFGRPSZ_9 = 3'b001; // 3x3
	localparam KBUFGRPSZ_25 = 3'b010; // 5x5
	localparam KBUFGRPSZ_49 = 3'b011; // 7x7
	localparam KBUFGRPSZ_81 = 3'b100; // 9x9
	localparam KBUFGRPSZ_121 = 3'b101; // 11x11
	// 每个权重块的表面个数的类型编码
	localparam WGTBLK_SFC_N_1 = 3'b000; // 1个表面
	localparam WGTBLK_SFC_N_2 = 3'b001; // 2个表面
	localparam WGTBLK_SFC_N_4 = 3'b010; // 4个表面
	localparam WGTBLK_SFC_N_8 = 3'b011; // 8个表面
	localparam WGTBLK_SFC_N_16 = 3'b100; // 16个表面
	localparam WGTBLK_SFC_N_32 = 3'b101; // 32个表面
	localparam WGTBLK_SFC_N_64 = 3'b110; // 64个表面
	localparam WGTBLK_SFC_N_128 = 3'b111; // 128个表面
	// 读取权重块状态常量
	localparam RD_WGTBLK_STS_IDLE = 3'b001;
	localparam RD_WGTBLK_STS_NOT_FOUND = 3'b010;
	localparam RD_WGTBLK_STS_TRANS = 3'b100;
	
	/** 内部参数 **/
	wire[2:0] sfc_n_each_wgtblk_lshn; // 每个权重块的表面个数导致的左移量
	wire[31:0] kernal_blk_addr_stride; // 权重块地址跨度
	wire[4:0] kernal_blk_addr_stride_lshn; // 权重块地址跨度导致的左移量
	wire[7:0] kbufgrpn_sub1; // 可缓存的通道组数 - 2
	wire[6:0] wtblkn_in_cgrp; // 通道组内的权重块个数
	wire[31:0] sw_rgn0_baseaddr; // 交换区通道组#0基址
	wire[31:0] sw_rgn1_baseaddr; // 交换区通道组#1基址
	
	assign sfc_n_each_wgtblk_lshn = 
		(sfc_n_each_wgtblk == WGTBLK_SFC_N_1)   ? 3'b000:
		(sfc_n_each_wgtblk == WGTBLK_SFC_N_2)   ? 3'b001:
		(sfc_n_each_wgtblk == WGTBLK_SFC_N_4)   ? 3'b010:
		(sfc_n_each_wgtblk == WGTBLK_SFC_N_8)   ? 3'b011:
		(sfc_n_each_wgtblk == WGTBLK_SFC_N_16)  ? 3'b100:
		(sfc_n_each_wgtblk == WGTBLK_SFC_N_32)  ? 3'b101:
		(sfc_n_each_wgtblk == WGTBLK_SFC_N_64)  ? 3'b110:
		                                          3'b111;
	assign kernal_blk_addr_stride = 
		(1 << sfc_n_each_wgtblk_lshn) * ATOMIC_C * 2;
	assign kernal_blk_addr_stride_lshn = 
		{2'b00, sfc_n_each_wgtblk_lshn} + (
			(ATOMIC_C == 1)  ? 5'd1:
			(ATOMIC_C == 2)  ? 5'd2:
			(ATOMIC_C == 4)  ? 5'd3:
			(ATOMIC_C == 8)  ? 5'd4:
			(ATOMIC_C == 16) ? 5'd5:
							   5'd6
		);
	assign kbufgrpn_sub1 = 
		kbufgrpn - 8'd1;
	assign wtblkn_in_cgrp = 
		(kbufgrpsz == KBUFGRPSZ_1)  ?   7'd1:
		(kbufgrpsz == KBUFGRPSZ_9)  ?   7'd9:
		(kbufgrpsz == KBUFGRPSZ_25) ?  7'd25:
		(kbufgrpsz == KBUFGRPSZ_49) ?  7'd49:
		(kbufgrpsz == KBUFGRPSZ_81) ?  7'd81:
									  7'd121;
	
	assign sw_rgn0_baseaddr = ((kbufgrpn_sub1 * wtblkn_in_cgrp) | 32'h0000_0000) << kernal_blk_addr_stride_lshn;
	assign sw_rgn1_baseaddr = ((kbufgrpn * wtblkn_in_cgrp) | 32'h0000_0000) << kernal_blk_addr_stride_lshn;
	
	/** 通道组缓存情况 **/
	// [驻留区]
	reg[8:0] rsv_rgn_vld_grpn_r; // 驻留区有效通道组数
	wire rsv_rgn_wen; // 驻留区写使能
	// [交换区]
	reg sw_rgn0_vld_r; // 交换区通道组#0有效
	reg sw_rgn1_vld_r; // 交换区通道组#1有效
	reg[9:0] sw_rgn0_grpid_r; // 交换区通道组#0实际通道组号
	reg[9:0] sw_rgn1_grpid_r; // 交换区通道组#1实际通道组号
	wire sw_rgn0_wen; // 交换区通道组#0写使能
	wire sw_rgn1_wen; // 交换区通道组#1写使能
	wire on_auto_rplc_sw_rgn0; // 自动置换交换区通道组#0(指示)
	wire on_auto_rplc_sw_rgn1; // 自动置换交换区通道组#1(指示)
	
	assign rsv_rgn_vld_grpn = rsv_rgn_vld_grpn_r;
	assign sw_rgn_vld = {sw_rgn1_vld_r, sw_rgn0_vld_r};
	assign sw_rgn0_grpid = sw_rgn0_grpid_r;
	assign sw_rgn1_grpid = sw_rgn1_grpid_r;
	// 说明: 若可缓存的通道组数 >= 实际通道组数, 则卷积核缓存可以存储整个核组的权重数据, 此时无需设置交换区
	assign has_sw_rgn = {2'b00, kbufgrpn} < cgrpn;
	
	// 驻留区有效通道组数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rsv_rgn_vld_grpn_r <= 9'd0;
		else if(aclken & (rst_logic_kbuf | rsv_rgn_wen))
			rsv_rgn_vld_grpn_r <= # SIM_DELAY 
				rst_logic_kbuf ? 
					9'd0:
					(rsv_rgn_vld_grpn_r + 9'd1);
	end
	
	// 交换区通道组#0有效
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			sw_rgn0_vld_r <= 1'b0;
		else if(aclken & (sw_rgn0_wen | rst_logic_kbuf | ((~grp_conv_buf_mode) & sw_rgn_rplc[0]) | on_auto_rplc_sw_rgn0))
			sw_rgn0_vld_r <= # SIM_DELAY 
				sw_rgn0_wen | (~(rst_logic_kbuf | ((~grp_conv_buf_mode) & sw_rgn_rplc[0]) | on_auto_rplc_sw_rgn0));
	end
	// 交换区通道组#1有效
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			sw_rgn1_vld_r <= 1'b0;
		else if(aclken & (sw_rgn1_wen | rst_logic_kbuf | ((~grp_conv_buf_mode) & sw_rgn_rplc[1]) | on_auto_rplc_sw_rgn1))
			sw_rgn1_vld_r <= # SIM_DELAY 
				sw_rgn1_wen | (~(rst_logic_kbuf | ((~grp_conv_buf_mode) & sw_rgn_rplc[1]) | on_auto_rplc_sw_rgn1));
	end
	
	/** 写通道组 **/
	wire s_in_cgrp_axis_user_last_blk; // 标志通道组的最后1个权重块
	wire[9:0] s_in_cgrp_axis_user_actual_gid; // 实际通道组号
	wire[3:0] s_in_cgrp_axis_user_rd_req_eid; // 读请求项索引
	wire[ATOMIC_C*2*8-1:0] in_cgrp_sfc_data_mask; // 输入通道组表面数据掩码
	wire kbuf_full; // 卷积核缓存满标志
	reg in_cgrp_passing; // 放行输入通道组(标志)
	reg in_cgrp_store_to_rsv_rgn; // 将输入通道组存入驻留区(标志)
	reg in_cgrp_store_to_sw_rgn0; // 将输入通道组存入交换区通道组#0(标志)
	reg in_cgrp_store_to_sw_rgn1; // 将输入通道组存入交换区通道组#1(标志)
	reg[31:0] kbuf_to_wt_cgrp_baseaddr; // 卷积核缓存区待写通道组基址
	reg[31:0] kbuf_to_wt_cgrp_ofsaddr; // 卷积核缓存区待写表面偏移地址
	reg[31:0] rsv_rgn_to_wt_cgrp_baseaddr; // 待写驻留区通道组基址
	reg[15:0] onroad_kbuf_wt_sfc_n; // 滞外的待写表面个数(计数器)
	wire[15:0] onroad_kbuf_wt_sfc_n_nxt; // 下一滞外的待写表面个数(计数器)
	reg submit_wt_cgrp_pending; // 提交待写通道组(等待标志)
	reg[9:0] submit_wt_cgrp_actual_gid; // 待提交写通道组的实际组号
	reg[3:0] submit_wt_cgrp_rd_req_eid; // 待提交写通道组的读请求项索引
	reg wt_rsv_rgn_actual_gid_mismatch_r; // 写驻留区时实际通道组号不符合要求
	
	assign rsv_rgn_full = 
		grp_conv_buf_mode ? 
			// 断言: 处于组卷积缓存模式时, 卷积核缓存可存下整个核组
			(rsv_rgn_vld_grpn_r >= (cgrpn[8:0] + 9'd1)): // 驻留区有效通道组数 >= 实际通道组数
			(
				has_sw_rgn ? 
					((rsv_rgn_vld_grpn_r + 9'd1) >= {1'b0, kbufgrpn}): // 驻留区有效通道组数 >= 可缓存的通道组数 - 2
					(rsv_rgn_vld_grpn_r > {1'b0, kbufgrpn})            // 驻留区有效通道组数 >= 可缓存的通道组数
			);
	assign cgrp_stored_rd_req_eid = submit_wt_cgrp_rd_req_eid;
	assign cgrp_stored_vld = 
		aclken & (~rst_logic_kbuf) & 
		submit_wt_cgrp_pending & (~in_cgrp_passing) & (onroad_kbuf_wt_sfc_n_nxt == 16'd0);
	
	// 握手条件: aclken & in_cgrp_passing & s_in_cgrp_axis_valid & m0_kbuf_cmd_ready
	assign s_in_cgrp_axis_ready = aclken & in_cgrp_passing & m0_kbuf_cmd_ready;
	
	assign m0_kbuf_cmd_addr = 
		(kbuf_to_wt_cgrp_baseaddr & (~(ATOMIC_C*2-1))) + 
		(kbuf_to_wt_cgrp_ofsaddr & (~(ATOMIC_C*2-1)));
	assign m0_kbuf_cmd_read = 1'b0;
	assign m0_kbuf_cmd_wdata = s_in_cgrp_axis_data & in_cgrp_sfc_data_mask;
	assign m0_kbuf_cmd_wmask = {(ATOMIC_C*2){1'b1}};
	// 握手条件: aclken & in_cgrp_passing & s_in_cgrp_axis_valid & m0_kbuf_cmd_ready
	assign m0_kbuf_cmd_valid = aclken & in_cgrp_passing & s_in_cgrp_axis_valid;
	
	assign m0_kbuf_rsp_ready = aclken;
	
	assign wt_rsv_rgn_actual_gid_mismatch = wt_rsv_rgn_actual_gid_mismatch_r;
	
	assign {rsv_rgn_wen, sw_rgn0_wen, sw_rgn1_wen} = 
		{3{cgrp_stored_vld}} & 
		{in_cgrp_store_to_rsv_rgn, in_cgrp_store_to_sw_rgn0, in_cgrp_store_to_sw_rgn1};
	
	assign {
		s_in_cgrp_axis_user_rd_req_eid, 
		s_in_cgrp_axis_user_actual_gid, 
		s_in_cgrp_axis_user_last_blk
	} = s_in_cgrp_axis_user;
	
	genvar in_cgrp_sfc_data_mask_i;
	generate
		for(in_cgrp_sfc_data_mask_i = 0;in_cgrp_sfc_data_mask_i < ATOMIC_C*2;
			in_cgrp_sfc_data_mask_i = in_cgrp_sfc_data_mask_i + 1)
		begin:in_cgrp_sfc_data_mask_blk
			assign in_cgrp_sfc_data_mask[in_cgrp_sfc_data_mask_i*8+7:in_cgrp_sfc_data_mask_i*8] = 
				{8{s_in_cgrp_axis_keep[in_cgrp_sfc_data_mask_i]}};
		end
	endgenerate
	
	assign kbuf_full = 
		rsv_rgn_full & 
		(
			// 如果处于组卷积缓存模式或者没有交换区, 则不使用交换区
			grp_conv_buf_mode | (~has_sw_rgn) | 
			(sw_rgn0_vld_r & sw_rgn1_vld_r)
		);
	
	assign onroad_kbuf_wt_sfc_n_nxt = 
		(
			aclken & 
			(
				rst_logic_kbuf | 
				((m0_kbuf_cmd_valid & m0_kbuf_cmd_ready) ^ (m0_kbuf_rsp_valid & m0_kbuf_rsp_ready))
			)
		) ? 
			(
				rst_logic_kbuf ? 
					16'd0:
					(
						(m0_kbuf_rsp_valid & m0_kbuf_rsp_ready) ? 
							(onroad_kbuf_wt_sfc_n - 16'd1):
							(onroad_kbuf_wt_sfc_n + 16'd1)
					)
			):
			onroad_kbuf_wt_sfc_n;
	
	// 交换区通道组#0实际通道组号
	always @(posedge aclk)
	begin
		if(aclken & sw_rgn0_wen)
			sw_rgn0_grpid_r <= # SIM_DELAY submit_wt_cgrp_actual_gid;
	end
	// 交换区通道组#1实际通道组号
	always @(posedge aclk)
	begin
		if(aclken & sw_rgn1_wen)
			sw_rgn1_grpid_r <= # SIM_DELAY submit_wt_cgrp_actual_gid;
	end
	
	// 放行输入通道组(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			in_cgrp_passing <= 1'b0;
		else if(aclken)
			in_cgrp_passing <= # SIM_DELAY 
				(~rst_logic_kbuf) & (
					in_cgrp_passing ? 
						(~(s_in_cgrp_axis_valid & s_in_cgrp_axis_ready & s_in_cgrp_axis_last & s_in_cgrp_axis_user_last_blk)):
						((onroad_kbuf_wt_sfc_n == 16'd0) & (~kbuf_full))
				);
	end
	
	// 将输入通道组存入驻留区(标志), 将输入通道组存入交换区通道组#0(标志), 将输入通道组存入交换区通道组#1(标志), 卷积核缓存区待写通道组基址
	always @(posedge aclk)
	begin
		if(
			aclken & (~rst_logic_kbuf) & (~in_cgrp_passing) & 
			(onroad_kbuf_wt_sfc_n == 16'd0) & (~kbuf_full)
		)
		begin
			in_cgrp_store_to_rsv_rgn <= # SIM_DELAY ~rsv_rgn_full;
			// 说明: 优先存储在交换区#0
			in_cgrp_store_to_sw_rgn0 <= # SIM_DELAY rsv_rgn_full & (~sw_rgn0_vld_r);
			in_cgrp_store_to_sw_rgn1 <= # SIM_DELAY rsv_rgn_full & sw_rgn0_vld_r;
			
			kbuf_to_wt_cgrp_baseaddr <= # SIM_DELAY 
				(~rsv_rgn_full) ? 
					rsv_rgn_to_wt_cgrp_baseaddr:
					(
						(~sw_rgn0_vld_r) ? 
							sw_rgn0_baseaddr:
							sw_rgn1_baseaddr
					);
		end
	end
	
	// 卷积核缓存区待写表面偏移地址
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(in_cgrp_passing)
			begin
				if(s_in_cgrp_axis_valid & s_in_cgrp_axis_ready)
				begin
					kbuf_to_wt_cgrp_ofsaddr <= # SIM_DELAY 
						s_in_cgrp_axis_last ? 
							// 说明: 递增权重块号, 清零权重块内地址
							((kbuf_to_wt_cgrp_ofsaddr + kernal_blk_addr_stride) & (~(kernal_blk_addr_stride - 1))):
							// 说明: 仅递增权重块内地址
							(kbuf_to_wt_cgrp_ofsaddr + ATOMIC_C * 2);
				end
			end
			else if((~rst_logic_kbuf) & (onroad_kbuf_wt_sfc_n == 16'd0) & (~kbuf_full))
				kbuf_to_wt_cgrp_ofsaddr <= # SIM_DELAY 32'd0;
		end
	end
	
	// 待写驻留区通道组基址
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rsv_rgn_to_wt_cgrp_baseaddr <= 32'd0;
		else if(aclken & (rst_logic_kbuf | rsv_rgn_wen))
			rsv_rgn_to_wt_cgrp_baseaddr <= # SIM_DELAY 
				rst_logic_kbuf ? 
					32'd0:
					(rsv_rgn_to_wt_cgrp_baseaddr + ((wtblkn_in_cgrp | 32'h0000_0000) << kernal_blk_addr_stride_lshn));
	end
	
	// 滞外的待写表面个数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			onroad_kbuf_wt_sfc_n <= 16'd0;
		else
			onroad_kbuf_wt_sfc_n <= # SIM_DELAY onroad_kbuf_wt_sfc_n_nxt;
	end
	
	// 提交待写通道组(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			submit_wt_cgrp_pending <= 1'b0;
		else if(aclken)
			submit_wt_cgrp_pending <= # SIM_DELAY 
				(~rst_logic_kbuf) & (
					submit_wt_cgrp_pending ? 
						(~((~in_cgrp_passing) & (onroad_kbuf_wt_sfc_n_nxt == 16'd0))):
						(s_in_cgrp_axis_valid & s_in_cgrp_axis_ready & s_in_cgrp_axis_last & s_in_cgrp_axis_user_last_blk)
				);
	end
	
	// 待提交写通道组的实际组号, 待提交写通道组的读请求项索引
	always @(posedge aclk)
	begin
		if(aclken & s_in_cgrp_axis_valid & s_in_cgrp_axis_ready & s_in_cgrp_axis_last & s_in_cgrp_axis_user_last_blk)
		begin
			submit_wt_cgrp_actual_gid <= # SIM_DELAY s_in_cgrp_axis_user_actual_gid;
			submit_wt_cgrp_rd_req_eid <= # SIM_DELAY s_in_cgrp_axis_user_rd_req_eid;
		end
	end
	
	// 写驻留区时实际通道组号不符合要求
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wt_rsv_rgn_actual_gid_mismatch_r <= 1'b0;
		else if(
			aclken & 
			(rst_logic_kbuf | (~wt_rsv_rgn_actual_gid_mismatch_r))
		)
			wt_rsv_rgn_actual_gid_mismatch_r <= # SIM_DELAY 
				(~rst_logic_kbuf) & 
				(~grp_conv_buf_mode) & rsv_rgn_wen & (submit_wt_cgrp_actual_gid != {1'b0, rsv_rgn_vld_grpn_r});
	end
	
	/** 读通道组 **/
	wire[4:0] s_rd_req_axis_data_sfc_to_rd; // 待读取的表面个数 - 1
	wire[6:0] s_rd_req_axis_data_start_sid; // 起始表面编号
	wire[6:0] s_rd_req_axis_data_bid; // 权重块编号
	wire[9:0] s_rd_req_axis_data_actual_gid; // 实际通道组号
	wire s_rd_req_axis_data_auto_rplc_sw_rgn; // 是否需要自动置换交换区通道组
	wire[7:0] access_rsv_rgn_cgid; // 当前访问的驻留区通道组号
	wire find_wtblk_in_rsv_rgn; // 在驻留区找到权重块(标志)
	wire find_wtblk_in_sw_rgn0; // 在交换区通道组#0找到权重块(标志)
	wire find_wtblk_in_sw_rgn1; // 在交换区通道组#1找到权重块(标志)
	reg[31:0] rd_wtblk_cgrp_baseaddr; // 通道组基地址
	reg[31:0] rd_wtblk_sfc_baseaddr; // 待读取权重块的表面基地址
	reg[4:0] wtblk_to_rd_sfc_n; // 待读取权重块的表面个数 - 1
	reg[5:0] sfc_rd_cmd_dsptc_n; // 已派发的表面读命令个数
	reg[5:0] sfc_rd_resp_acpt_n; // 已接受的表面读响应个数
	reg[2:0] rd_wtblk_sts; // 读取权重块状态
	reg auto_rplc_sw_rgn0; // 自动置换交换区通道组#0(标志)
	reg auto_rplc_sw_rgn1; // 自动置换交换区通道组#1(标志)
	
	assign s_rd_req_axis_ready = (~rst_logic_kbuf) & aclken & (rd_wtblk_sts == RD_WGTBLK_STS_IDLE);
	
	assign m_out_wgtblk_axis_data = m1_kbuf_rsp_rdata;
	assign m_out_wgtblk_axis_user = rd_wtblk_sts == RD_WGTBLK_STS_NOT_FOUND;
	assign m_out_wgtblk_axis_last = 
		(rd_wtblk_sts == RD_WGTBLK_STS_NOT_FOUND) | (sfc_rd_resp_acpt_n == {1'b0, wtblk_to_rd_sfc_n});
	/*
	握手条件: 
		aclken & (
			((rd_wtblk_sts == RD_WGTBLK_STS_TRANS) & (sfc_rd_resp_acpt_n <= {1'b0, wtblk_to_rd_sfc_n}) & m1_kbuf_rsp_valid) | 
			(rd_wtblk_sts == RD_WGTBLK_STS_NOT_FOUND)
		) & m_out_wgtblk_axis_ready
	*/
	assign m_out_wgtblk_axis_valid = 
		aclken & (
			((rd_wtblk_sts == RD_WGTBLK_STS_TRANS) & (sfc_rd_resp_acpt_n <= {1'b0, wtblk_to_rd_sfc_n}) & m1_kbuf_rsp_valid) | 
			(rd_wtblk_sts == RD_WGTBLK_STS_NOT_FOUND)
		);
	
	assign m1_kbuf_cmd_addr = 
		rd_wtblk_cgrp_baseaddr + rd_wtblk_sfc_baseaddr + (sfc_rd_cmd_dsptc_n * ATOMIC_C * 2);
	assign m1_kbuf_cmd_read = 1'b1;
	assign m1_kbuf_cmd_wdata = {(ATOMIC_C*2*8){1'bx}};
	assign m1_kbuf_cmd_wmask = {(ATOMIC_C*2){1'bx}};
	assign m1_kbuf_cmd_valid = 
		aclken & (rd_wtblk_sts == RD_WGTBLK_STS_TRANS) & 
		(sfc_rd_cmd_dsptc_n <= {1'b0, wtblk_to_rd_sfc_n});
	
	/*
	握手条件: 
		aclken & (rd_wtblk_sts == RD_WGTBLK_STS_TRANS) & 
		(sfc_rd_resp_acpt_n <= {1'b0, wtblk_to_rd_sfc_n}) & 
		m1_kbuf_rsp_valid & m_out_wgtblk_axis_ready
	*/
	assign m1_kbuf_rsp_ready = 
		aclken & (rd_wtblk_sts == RD_WGTBLK_STS_TRANS) & 
		(sfc_rd_resp_acpt_n <= {1'b0, wtblk_to_rd_sfc_n}) & m_out_wgtblk_axis_ready;
	
	assign {on_auto_rplc_sw_rgn0, on_auto_rplc_sw_rgn1} = 
		{auto_rplc_sw_rgn0, auto_rplc_sw_rgn1} & 
		{2{m1_kbuf_rsp_valid & m1_kbuf_rsp_ready & (sfc_rd_resp_acpt_n == {1'b0, wtblk_to_rd_sfc_n})}};
	
	assign {
		s_rd_req_axis_data_auto_rplc_sw_rgn, 
		s_rd_req_axis_data_actual_gid, 
		s_rd_req_axis_data_bid, 
		s_rd_req_axis_data_start_sid, 
		s_rd_req_axis_data_sfc_to_rd
	} = s_rd_req_axis_data[29:0];
	
	assign access_rsv_rgn_cgid = s_rd_req_axis_data_actual_gid[7:0];
	
	assign find_wtblk_in_rsv_rgn = s_rd_req_axis_data_actual_gid < {1'b0, rsv_rgn_vld_grpn_r};
	assign find_wtblk_in_sw_rgn0 = sw_rgn0_vld_r & (s_rd_req_axis_data_actual_gid == sw_rgn0_grpid_r);
	assign find_wtblk_in_sw_rgn1 = sw_rgn1_vld_r & (s_rd_req_axis_data_actual_gid == sw_rgn1_grpid_r);
	
	// 通道组基地址, 待读取权重块的表面基地址, 待读取权重块的表面个数 - 1
	always @(posedge aclk)
	begin
		if(aclken & (~rst_logic_kbuf) & s_rd_req_axis_valid & s_rd_req_axis_ready)
		begin
			rd_wtblk_cgrp_baseaddr <= # SIM_DELAY 
				(find_wtblk_in_sw_rgn0 | find_wtblk_in_sw_rgn1) ? 
					(
						find_wtblk_in_sw_rgn0 ? 
							sw_rgn0_baseaddr:
							sw_rgn1_baseaddr
					):
					(((access_rsv_rgn_cgid * wtblkn_in_cgrp) | 32'h0000_0000) << kernal_blk_addr_stride_lshn);
			rd_wtblk_sfc_baseaddr <= # SIM_DELAY 
				// 权重块偏移地址
				((s_rd_req_axis_data_bid | 32'h0000_0000) << kernal_blk_addr_stride_lshn) + 
				// 表面偏移地址
				(s_rd_req_axis_data_start_sid * ATOMIC_C * 2);
			
			wtblk_to_rd_sfc_n <= # SIM_DELAY s_rd_req_axis_data_sfc_to_rd;
		end
	end
	
	// 已派发的表面读命令个数
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(rst_logic_kbuf | ((rd_wtblk_sts == RD_WGTBLK_STS_IDLE) & s_rd_req_axis_valid & s_rd_req_axis_ready))
				sfc_rd_cmd_dsptc_n <= # SIM_DELAY 6'd0;
			else if((rd_wtblk_sts == RD_WGTBLK_STS_TRANS) & m1_kbuf_cmd_valid & m1_kbuf_cmd_ready)
				sfc_rd_cmd_dsptc_n <= # SIM_DELAY sfc_rd_cmd_dsptc_n + 6'd1;
		end
	end
	// 已接受的表面读响应个数
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(rst_logic_kbuf | ((rd_wtblk_sts == RD_WGTBLK_STS_IDLE) & s_rd_req_axis_valid & s_rd_req_axis_ready))
				sfc_rd_resp_acpt_n <= # SIM_DELAY 6'd0;
			else if((rd_wtblk_sts == RD_WGTBLK_STS_TRANS) & m1_kbuf_rsp_valid & m1_kbuf_rsp_ready)
				sfc_rd_resp_acpt_n <= # SIM_DELAY sfc_rd_resp_acpt_n + 6'd1;
		end
	end
	
	// 读取权重块状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_wtblk_sts <= RD_WGTBLK_STS_IDLE;
		else if(aclken)
		begin
			if(rst_logic_kbuf)
				rd_wtblk_sts <= # SIM_DELAY RD_WGTBLK_STS_IDLE;
			else
			begin
				case(rd_wtblk_sts)
					RD_WGTBLK_STS_IDLE:
					begin
						if(s_rd_req_axis_valid & s_rd_req_axis_ready)
							rd_wtblk_sts <= # SIM_DELAY 
								(find_wtblk_in_rsv_rgn | find_wtblk_in_sw_rgn0 | find_wtblk_in_sw_rgn1) ? 
									RD_WGTBLK_STS_TRANS:
									RD_WGTBLK_STS_NOT_FOUND;
					end
					RD_WGTBLK_STS_NOT_FOUND:
					begin
						if(m_out_wgtblk_axis_valid & m_out_wgtblk_axis_ready)
							rd_wtblk_sts <= # SIM_DELAY RD_WGTBLK_STS_IDLE;
					end
					RD_WGTBLK_STS_TRANS:
						if(m1_kbuf_rsp_valid & m1_kbuf_rsp_ready & (sfc_rd_resp_acpt_n == {1'b0, wtblk_to_rd_sfc_n}))
							rd_wtblk_sts <= # SIM_DELAY RD_WGTBLK_STS_IDLE;
					default:
						rd_wtblk_sts <= # SIM_DELAY RD_WGTBLK_STS_IDLE;
				endcase
			end
		end
	end
	
	// 自动置换交换区通道组#0(标志), 自动置换交换区通道组#1(标志)
	always @(posedge aclk)
	begin
		if(s_rd_req_axis_valid & s_rd_req_axis_ready)
		begin
			auto_rplc_sw_rgn0 <= # SIM_DELAY 
				(~grp_conv_buf_mode) & s_rd_req_axis_data_auto_rplc_sw_rgn & find_wtblk_in_sw_rgn0;
			auto_rplc_sw_rgn1 <= # SIM_DELAY 
				(~grp_conv_buf_mode) & s_rd_req_axis_data_auto_rplc_sw_rgn & (~find_wtblk_in_sw_rgn0) & find_wtblk_in_sw_rgn1;
		end
	end
	
endmodule
