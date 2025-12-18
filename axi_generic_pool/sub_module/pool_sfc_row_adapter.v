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

`timescale 1ns / 1ps
/********************************************************************
本模块: 池化表面行适配器

描述:
表面行随机读命令端 -> 对池化域的非填充点, 产生特征图表面行随机读命令
表面行数据端 -> 对池化域的非填充点, 从前置特征图缓存中得到数据; 对池化域的填充点, 直接给出填充数据

表面行组处理过程 -> 
	最大/平均池化模式时, 池化窗口y方向{表面行[池化窗口x方向(输出点)]}
	上采样模式时, 垂直复制{表面行[输出点(水平复制)]}

注意：
平均池化模式时, 不输出填充行的填充数据, 忽略填充行的信息
最大池化模式时, 不输出非池化域首行或最后1行的填充行的填充数据, 忽略这些无效填充行的信息, 并对每个填充行只输出1轮(无论池化窗口宽度是多少)

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/12
********************************************************************/


module pool_sfc_row_adapter #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 控制信号
	input wire en_adapter, // 使能适配器
	
	// 运行时参数
	// [计算参数]
	input wire[1:0] pool_mode, // 池化模式
	input wire[2:0] pool_horizontal_stride, // 池化水平步长 - 1
	input wire[7:0] pool_window_w, // 池化窗口宽度 - 1
	// [特征图参数]
	input wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	input wire[2:0] external_padding_left, // 左部外填充数
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	// [上采样参数]
	input wire[7:0] upsample_horizontal_n, // 上采样水平复制量 - 1
	input wire[7:0] upsample_vertical_n, // 上采样垂直复制量 - 1
	input wire non_zero_const_padding_mode, // 是否处于非0常量填充模式
	input wire[15:0] const_to_fill, // 待填充的常量
	
	// 池化表面行信息(AXIS从机)
	/*
	{
		保留(6bit),
		表面行深度 - 1(5bit),
		是否池化域内的最后1个非填充表面行(1bit),
		是否池化域内的第1个非填充表面行(1bit),
		是否池化域内的最后1个表面行(1bit),
		是否池化域内的第1个表面行(1bit),
		是否填充行(1bit)
	}
	*/
	input wire[15:0] s_pool_sfc_row_info_axis_data,
	input wire s_pool_sfc_row_info_axis_valid,
	output wire s_pool_sfc_row_info_axis_ready,
	
	// 特征图表面行随机读取(AXIS主机)
	output wire[15:0] m_fm_random_rd_axis_data, // 表面号
	output wire m_fm_random_rd_axis_last, // 标志本次读请求待读取的最后1个表面
	output wire m_fm_random_rd_axis_valid,
	input wire m_fm_random_rd_axis_ready,
	
	// 待转换的特征图表面行数据(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_adapter_fm_axis_data,
	input wire s_adapter_fm_axis_last, // 标志本次读请求的最后1个表面
	input wire s_adapter_fm_axis_valid,
	output wire s_adapter_fm_axis_ready,
	// 转换后的特征图表面行数据(AXIS主机)
	output wire[ATOMIC_C*16-1:0] m_adapter_fm_axis_data, // ATOMIC_C个定点数或FP16
	output wire[ATOMIC_C*2-1:0] m_adapter_fm_axis_keep,
	output wire[2:0] m_adapter_fm_axis_user, // {本表面全0(标志), 初始化池化结果(标志), 最后1组池化表面(标志)}
	output wire m_adapter_fm_axis_last, // 本行最后1个池化表面(标志)
	output wire m_adapter_fm_axis_valid,
	input wire m_adapter_fm_axis_ready
);
	
	/** 函数 **/
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
	// 池化模式的编码
	localparam POOL_MODE_AVG = 2'b00;
	localparam POOL_MODE_MAX = 2'b01;
	localparam POOL_MODE_UPSP = 2'b10;
	localparam POOL_MODE_NONE = 2'b11;
	// 池化表面行信息fifo数据各字段的起始索引
	localparam integer SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID = 0;
	localparam integer SFC_ROW_INFO_FIFO_DATA_IS_FIRST_ROW_IN_POOL_RGN_SID = 1;
	localparam integer SFC_ROW_INFO_FIFO_DATA_IS_LAST_ROW_IN_POOL_RGN_SID = 2;
	localparam integer SFC_ROW_INFO_FIFO_DATA_IS_FIRST_SOLID_ROW_IN_POOL_RGN_SID = 3;
	localparam integer SFC_ROW_INFO_FIFO_DATA_IS_LAST_SOLID_ROW_IN_POOL_RGN_SID = 4;
	localparam integer SFC_ROW_INFO_FIFO_DATA_SFC_ROW_DEPTH_SID = 5;
	
	/** 池化表面行信息fifo **/
	// [写端口]
	wire sfc_row_info_fifo_wen;
	wire[9:0] sfc_row_info_fifo_din;
	wire sfc_row_info_fifo_full_n;
	// [读端口]
	wire sfc_row_info_fifo_ren;
	wire[9:0] sfc_row_info_fifo_dout;
	wire sfc_row_info_fifo_empty_n;
	
	assign s_pool_sfc_row_info_axis_ready = aclken & en_adapter & sfc_row_info_fifo_full_n;
	
	assign sfc_row_info_fifo_wen = aclken & en_adapter & s_pool_sfc_row_info_axis_valid;
	assign sfc_row_info_fifo_din = s_pool_sfc_row_info_axis_data[9:0];
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(16),
		.fifo_data_width(10),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)sfc_row_info_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(sfc_row_info_fifo_wen),
		.fifo_din(sfc_row_info_fifo_din),
		.fifo_full(),
		.fifo_full_n(sfc_row_info_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(sfc_row_info_fifo_ren),
		.fifo_dout(sfc_row_info_fifo_dout),
		.fifo_empty(),
		.fifo_empty_n(sfc_row_info_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** 特征图表面行随机读命令fifo **/
	// [写端口]
	wire fm_random_rd_cmd_fifo_wen;
	wire[16:0] fm_random_rd_cmd_fifo_din; // {标志本次读请求待读取的最后1个表面(1bit), 表面号(16bit)}
	wire fm_random_rd_cmd_fifo_full_n;
	// [读端口]
	wire fm_random_rd_cmd_fifo_ren;
	wire[16:0] fm_random_rd_cmd_fifo_dout; // {标志本次读请求待读取的最后1个表面(1bit), 表面号(16bit)}
	wire fm_random_rd_cmd_fifo_empty_n;
	// [寄存器片]
	wire[15:0] s_fm_random_rd_cmd_reg_axis_data; // 表面号
	wire s_fm_random_rd_cmd_reg_axis_last; // 标志本次读请求待读取的最后1个表面
	wire s_fm_random_rd_cmd_reg_axis_valid;
	wire s_fm_random_rd_cmd_reg_axis_ready;
	wire[15:0] m_fm_random_rd_cmd_reg_axis_data; // 表面号
	wire m_fm_random_rd_cmd_reg_axis_last; // 标志本次读请求待读取的最后1个表面
	wire m_fm_random_rd_cmd_reg_axis_valid;
	wire m_fm_random_rd_cmd_reg_axis_ready;
	
	assign m_fm_random_rd_axis_data = m_fm_random_rd_cmd_reg_axis_data;
	assign m_fm_random_rd_axis_last = m_fm_random_rd_cmd_reg_axis_last;
	assign m_fm_random_rd_axis_valid = m_fm_random_rd_cmd_reg_axis_valid;
	
	assign m_fm_random_rd_cmd_reg_axis_ready = m_fm_random_rd_axis_ready;
	
	assign {s_fm_random_rd_cmd_reg_axis_last, s_fm_random_rd_cmd_reg_axis_data} = fm_random_rd_cmd_fifo_dout;
	assign s_fm_random_rd_cmd_reg_axis_valid = fm_random_rd_cmd_fifo_empty_n;
	assign fm_random_rd_cmd_fifo_ren = s_fm_random_rd_cmd_reg_axis_ready;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(32),
		.fifo_data_width(17),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)fm_random_rd_cmd_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(fm_random_rd_cmd_fifo_wen),
		.fifo_din(fm_random_rd_cmd_fifo_din),
		.fifo_full(),
		.fifo_full_n(fm_random_rd_cmd_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(fm_random_rd_cmd_fifo_ren),
		.fifo_dout(fm_random_rd_cmd_fifo_dout),
		.fifo_empty(),
		.fifo_empty_n(fm_random_rd_cmd_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	axis_reg_slice #(
		.data_width(16),
		.user_width(1),
		.forward_registered("true"),
		.back_registered("false"),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)fm_random_rd_cmd_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s_fm_random_rd_cmd_reg_axis_data),
		.s_axis_keep(2'bxx),
		.s_axis_user(1'bx),
		.s_axis_last(s_fm_random_rd_cmd_reg_axis_last),
		.s_axis_valid(s_fm_random_rd_cmd_reg_axis_valid),
		.s_axis_ready(s_fm_random_rd_cmd_reg_axis_ready),
		
		.m_axis_data(m_fm_random_rd_cmd_reg_axis_data),
		.m_axis_keep(),
		.m_axis_user(),
		.m_axis_last(m_fm_random_rd_cmd_reg_axis_last),
		.m_axis_valid(m_fm_random_rd_cmd_reg_axis_valid),
		.m_axis_ready(m_fm_random_rd_cmd_reg_axis_ready)
	);
	
	/** 特征图表面行随机读取控制 **/
	// [事务(许可)积分]
	reg[31:0] random_rd_tr_credit; // 表面行随机读事务积分
	reg has_random_rd_tr_credit; // 有表面行随机读事务积分(标志)
	wire on_incr_random_rd_tr_credit; // 增加1个表面行随机读事务积分(指示)
	wire on_consume_random_rd_tr_credit; // 消耗1个表面行随机读事务积分(指示)
	// [计数器组]
	reg signed[15:0] pre_buf_logic_x; // 逻辑x坐标(计数器)
	reg[15:0] pre_buf_out_x; // 输出x坐标(计数器)
	reg[7:0] post_buf_pool_window_x_or_ups_vtc_rpc_n; // 池化窗口x坐标或上采样垂直复制次数(计数器)
	// [下一计数值]
	wire[7:0] post_buf_pool_window_x_nxt; // 下一池化窗口x坐标(计数值)
	// [标志组]
	wire pre_buf_is_at_out_row_end; // 处于输出行尾(标志)
	wire pre_buf_is_at_pool_window_last_col; // 处于池化窗口的最后1列(标志)
	wire pre_buf_is_last_ups_vtc_rpc; // 上采样最后1次垂直复制(标志)
	wire pre_buf_is_last_round_for_random_rd; // 最后1轮随机读(标志)
	wire pre_buf_is_padding_pt; // 是否填充点(标志)
	// [控制信号]
	wire pre_buf_on_mov_to_nxt_pt; // 移动到下1个输出点(指示)
	
	assign fm_random_rd_cmd_fifo_wen = 
		aclken & en_adapter & has_random_rd_tr_credit & (~pre_buf_is_padding_pt);
	assign fm_random_rd_cmd_fifo_din = {
		pre_buf_is_last_round_for_random_rd & 
		(
			pre_buf_is_at_out_row_end | 
			// 下1个输出点进入右部填充域
			(
				(~pre_buf_logic_x[15]) & 
				((pre_buf_logic_x[14:0] + (((pool_mode == POOL_MODE_UPSP) ? 3'd0:pool_horizontal_stride) | 15'd0) + 1'b1) > ifmap_w[14:0])
			)
		), // 标志本次读请求待读取的最后1个表面(1bit)
		{1'b0, pre_buf_logic_x[14:0]} // 表面号(16bit)
	};
	
	assign on_incr_random_rd_tr_credit = 
		sfc_row_info_fifo_wen & sfc_row_info_fifo_full_n & 
		(~sfc_row_info_fifo_din[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID]);
	assign on_consume_random_rd_tr_credit = 
		pre_buf_on_mov_to_nxt_pt & pre_buf_is_last_round_for_random_rd & pre_buf_is_at_out_row_end;
	
	assign post_buf_pool_window_x_nxt = 
		((~en_adapter) | (pool_mode == POOL_MODE_UPSP) | pre_buf_is_at_pool_window_last_col) ? 
			8'd0:
			(post_buf_pool_window_x_or_ups_vtc_rpc_n + 1'b1);
	
	assign pre_buf_is_at_out_row_end = pre_buf_out_x == ofmap_w;
	assign pre_buf_is_at_pool_window_last_col = post_buf_pool_window_x_or_ups_vtc_rpc_n == pool_window_w;
	assign pre_buf_is_last_ups_vtc_rpc = post_buf_pool_window_x_or_ups_vtc_rpc_n == upsample_vertical_n;
	assign pre_buf_is_last_round_for_random_rd = 
		(((pool_mode == POOL_MODE_MAX) | (pool_mode == POOL_MODE_AVG)) & pre_buf_is_at_pool_window_last_col) | 
		((pool_mode == POOL_MODE_UPSP) & pre_buf_is_last_ups_vtc_rpc);
	assign pre_buf_is_padding_pt = pre_buf_logic_x[15] | (pre_buf_logic_x[14:0] > ifmap_w[14:0]);
	
	assign pre_buf_on_mov_to_nxt_pt = 
		aclken & en_adapter & has_random_rd_tr_credit & 
		(pre_buf_is_padding_pt | fm_random_rd_cmd_fifo_full_n);
	
	// 表面行随机读事务积分
	always @(posedge aclk)
	begin
		if(
			aclken & 
			((~en_adapter) | (on_incr_random_rd_tr_credit ^ on_consume_random_rd_tr_credit))
		)
			random_rd_tr_credit <= # SIM_DELAY 
				en_adapter ? 
					// on_consume_random_rd_tr_credit ? (random_rd_tr_credit - 1):(random_rd_tr_credit + 1)
					(random_rd_tr_credit + {{31{on_consume_random_rd_tr_credit}}, 1'b1}):
					32'd0;
	end
	// 有表面行随机读事务积分(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			has_random_rd_tr_credit <= 1'b0;
		else if(
			aclken & 
			((~en_adapter) | (on_incr_random_rd_tr_credit ^ on_consume_random_rd_tr_credit))
		)
			has_random_rd_tr_credit <= # SIM_DELAY (~on_consume_random_rd_tr_credit) | (random_rd_tr_credit != 32'd1);
	end
	
	// 逻辑x坐标(计数器), 输出x坐标(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			((~en_adapter) | pre_buf_on_mov_to_nxt_pt)
		)
		begin
			pre_buf_logic_x <= # SIM_DELAY 
				/*
				((~en_adapter) | pre_buf_is_at_out_row_end) ? 
					((~(external_padding_left | 16'd0)) + (post_buf_pool_window_x_nxt | 16'd0) + 1'b1): // -左部外填充数 + 下一池化窗口x坐标
					(pre_buf_logic_x + (((pool_mode == POOL_MODE_UPSP) ? 3'd0:pool_horizontal_stride) | 16'd0) + 1'b1) // += 池化水平步长, ++
				*/
				(
					((~en_adapter) | pre_buf_is_at_out_row_end) ? 
						(~(external_padding_left | 16'd0)):
						pre_buf_logic_x
				) + 
				(
					((~en_adapter) | pre_buf_is_at_out_row_end) ? 
						(post_buf_pool_window_x_nxt | 16'd0):
						(((pool_mode == POOL_MODE_UPSP) ? 3'd0:pool_horizontal_stride) | 16'd0)
				) + 1'b1;
			
			pre_buf_out_x <= # SIM_DELAY 
				((~en_adapter) | pre_buf_is_at_out_row_end) ? 
					16'd0:
					(pre_buf_out_x + 1'b1);
		end
	end
	
	// 池化窗口x坐标或上采样垂直复制次数(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			((~en_adapter) | (pre_buf_on_mov_to_nxt_pt & pre_buf_is_at_out_row_end))
		)
			post_buf_pool_window_x_or_ups_vtc_rpc_n <= # SIM_DELAY 
				((~en_adapter) | pre_buf_is_last_round_for_random_rd) ? 
					8'd0:
					(post_buf_pool_window_x_or_ups_vtc_rpc_n + 1'b1);
	end
	
	/** 生成转换后的特征图表面行 **/
	// [计数器组]
	reg signed[15:0] post_buf_logic_x; // 逻辑x坐标(计数器)
	reg[15:0] post_buf_out_x; // 输出x坐标(计数器)
	reg[7:0] post_buf_pool_window_x_or_ups_hrzt_rpc_n; // 池化窗口x坐标或上采样水平复制次数(计数器)
	reg[7:0] post_buf_ups_vtc_rpc_n; // 上采样垂直复制次数(计数器)
	// [下一计数值]
	wire[7:0] post_buf_pool_window_x_or_ups_hrzt_rpc_n_nxt; // 下一池化窗口x坐标或上采样水平复制次数(计数值)
	// [标志组]
	wire post_buf_is_at_out_row_end; // 处于输出行尾(标志)
	wire post_buf_is_at_pool_window_first_col; // 处于池化窗口的第1列(标志)
	wire post_buf_is_at_pool_window_last_col; // 处于池化窗口的最后1列(标志)
	wire post_buf_is_last_ups_hrzt_rpc; // 上采样最后1次水平复制(标志)
	wire post_buf_is_last_ups_vtc_rpc; // 上采样最后1次垂直复制(标志)
	wire post_buf_is_padding_pt; // 是否填充点(标志)
	// [控制信号]
	wire post_buf_on_mov_to_nxt_pt; // 移动到下1个输出点(指示)
	
	assign s_adapter_fm_axis_ready = 
		aclken & en_adapter & 
		sfc_row_info_fifo_empty_n & 
		(~sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID]) & (~post_buf_is_padding_pt) & // 不属于填充点
		((pool_mode != POOL_MODE_UPSP) | post_buf_is_last_ups_hrzt_rpc) & // 上采样模式下需要作水平复制
		m_adapter_fm_axis_ready;
	
	assign m_adapter_fm_axis_data = 
		(
			(pool_mode == POOL_MODE_UPSP) & non_zero_const_padding_mode & 
			(sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID] | post_buf_is_padding_pt)
		) ? 
			{ATOMIC_C{const_to_fill}}: // 填充非0常量
			s_adapter_fm_axis_data;
	assign m_adapter_fm_axis_keep = 
		(ATOMIC_C == 1) ? 
			2'b11:
			(
				{(ATOMIC_C*2){1'b1}} >> 
					{
						~sfc_row_info_fifo_dout[
							SFC_ROW_INFO_FIFO_DATA_SFC_ROW_DEPTH_SID+clogb2(ATOMIC_C-1):
							SFC_ROW_INFO_FIFO_DATA_SFC_ROW_DEPTH_SID
						], 1'b0
					} // 右移(ATOMIC_C - 表面行深度)*2位
			);
	// 最后1组池化表面(标志)
	assign m_adapter_fm_axis_user[0] = 
		(
			(pool_mode == POOL_MODE_AVG) & 
			sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_LAST_SOLID_ROW_IN_POOL_RGN_SID] & post_buf_is_at_pool_window_last_col
		) | 
		(
			(pool_mode == POOL_MODE_MAX) & 
			sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_LAST_ROW_IN_POOL_RGN_SID] & post_buf_is_at_pool_window_last_col
		) | 
		(pool_mode == POOL_MODE_UPSP);
	// 初始化池化结果(标志)
	assign m_adapter_fm_axis_user[1] = 
		(
			(pool_mode == POOL_MODE_AVG) & 
			sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_FIRST_SOLID_ROW_IN_POOL_RGN_SID] & post_buf_is_at_pool_window_first_col
		) | 
		(
			(pool_mode == POOL_MODE_MAX) & 
			sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_FIRST_ROW_IN_POOL_RGN_SID] & post_buf_is_at_pool_window_first_col
		) | 
		(pool_mode == POOL_MODE_UPSP);
	// 本表面全0(标志)
	assign m_adapter_fm_axis_user[2] = 
		(~((pool_mode == POOL_MODE_UPSP) & non_zero_const_padding_mode)) & // 上采样模式下填充非0常量, 则本表面非0
		(sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID] | post_buf_is_padding_pt); // 属于填充点
	assign m_adapter_fm_axis_last = 
		((pool_mode != POOL_MODE_UPSP) | post_buf_is_last_ups_hrzt_rpc) & // 上采样模式下需要作水平复制
		post_buf_is_at_out_row_end;
	assign m_adapter_fm_axis_valid = 
		aclken & en_adapter & 
		sfc_row_info_fifo_empty_n & 
		(~(
			// 平均池化模式时, 跳过填充行
			((pool_mode == POOL_MODE_AVG) & sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID]) | 
			// 最大池化模式时, 跳过不是池化域首行或最后1行的填充行
			(
				(pool_mode == POOL_MODE_MAX) & sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID] & 
				(~(
					sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_FIRST_ROW_IN_POOL_RGN_SID] | 
					sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_LAST_ROW_IN_POOL_RGN_SID]
				))
			)
		)) & 
		// 对于非填充点, 需要从前置特征图缓存中得到数据
		(sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID] | post_buf_is_padding_pt | s_adapter_fm_axis_valid);
	
	assign sfc_row_info_fifo_ren = 
		aclken & en_adapter & 
		(
			// 平均池化模式时, 跳过填充行
			((pool_mode == POOL_MODE_AVG) & sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID]) | 
			// 最大池化模式时, 跳过不是池化域首行或最后1行的填充行
			(
				(pool_mode == POOL_MODE_MAX) & sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID] & 
				(~(
					sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_FIRST_ROW_IN_POOL_RGN_SID] | 
					sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_LAST_ROW_IN_POOL_RGN_SID]
				))
			) | 
			(
				post_buf_on_mov_to_nxt_pt & 
				((pool_mode != POOL_MODE_UPSP) | post_buf_is_last_ups_hrzt_rpc) & // 上采样模式下需要作水平复制
				post_buf_is_at_out_row_end & 
				(
					(((pool_mode == POOL_MODE_AVG) | (pool_mode == POOL_MODE_MAX)) & post_buf_is_at_pool_window_last_col) | 
					((pool_mode == POOL_MODE_UPSP) & post_buf_is_last_ups_vtc_rpc)
				)
			)
		);
	
	assign post_buf_pool_window_x_or_ups_hrzt_rpc_n_nxt = 
		(
			((pool_mode == POOL_MODE_UPSP) & post_buf_is_last_ups_hrzt_rpc) | 
			(((pool_mode == POOL_MODE_AVG) | (pool_mode == POOL_MODE_MAX)) & post_buf_is_at_pool_window_last_col)
		) ? 
			8'd0:
			(post_buf_pool_window_x_or_ups_hrzt_rpc_n + 1'b1);
	
	assign post_buf_is_at_out_row_end = post_buf_out_x == ofmap_w;
	assign post_buf_is_at_pool_window_first_col = post_buf_pool_window_x_or_ups_hrzt_rpc_n == 8'd0;
	assign post_buf_is_at_pool_window_last_col = 
		// 最大池化模式时, 无论池化窗口宽度是多少, 填充行只都只输出1轮
		((pool_mode == POOL_MODE_MAX) & sfc_row_info_fifo_dout[SFC_ROW_INFO_FIFO_DATA_IS_PADDING_ROW_SID]) | 
		(post_buf_pool_window_x_or_ups_hrzt_rpc_n == pool_window_w);
	assign post_buf_is_last_ups_hrzt_rpc = post_buf_pool_window_x_or_ups_hrzt_rpc_n == upsample_horizontal_n;
	assign post_buf_is_last_ups_vtc_rpc = post_buf_ups_vtc_rpc_n == upsample_vertical_n;
	assign post_buf_is_padding_pt = post_buf_logic_x[15] | (post_buf_logic_x[14:0] > ifmap_w[14:0]);
	
	assign post_buf_on_mov_to_nxt_pt = m_adapter_fm_axis_valid & m_adapter_fm_axis_ready;
	
	// 逻辑x坐标(计数器), 输出x坐标(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(~en_adapter) | 
				(post_buf_on_mov_to_nxt_pt & ((pool_mode != POOL_MODE_UPSP) | post_buf_is_last_ups_hrzt_rpc))
			)
		)
		begin
			post_buf_logic_x <= # SIM_DELAY 
				/*
				en_adapter ? 
					(
						post_buf_is_at_out_row_end ? 
							((~(external_padding_left | 16'd0)) + (post_buf_pool_window_x_or_ups_hrzt_rpc_n_nxt | 16'd0) + 1'b1): // -左部外填充数 + 下一池化窗口x坐标
							(post_buf_logic_x + (((pool_mode == POOL_MODE_UPSP) ? 3'd0:pool_horizontal_stride) | 16'd0) + 1'b1) // += 池化水平步长, ++
					):
					((~(external_padding_left | 16'd0)) + 1'b1) // -左部外填充数
				*/
				(
					((~en_adapter) | post_buf_is_at_out_row_end) ? 
						(~(external_padding_left | 16'd0)):
						post_buf_logic_x
				) + 
				(
					en_adapter ? 
						(
							post_buf_is_at_out_row_end ? 
								(post_buf_pool_window_x_or_ups_hrzt_rpc_n_nxt | 16'd0):
								(((pool_mode == POOL_MODE_UPSP) ? 3'd0:pool_horizontal_stride) | 16'd0)
						):
						16'd0
				) + 1'b1;
			
			post_buf_out_x <= # SIM_DELAY 
				((~en_adapter) | post_buf_is_at_out_row_end) ? 
					16'd0:
					(post_buf_out_x + 1'b1);
		end
	end
	
	// 池化窗口x坐标或上采样水平复制次数(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(~en_adapter) | 
				(post_buf_on_mov_to_nxt_pt & ((pool_mode == POOL_MODE_UPSP) | post_buf_is_at_out_row_end))
			)
		)
			post_buf_pool_window_x_or_ups_hrzt_rpc_n <= # SIM_DELAY 
				en_adapter ? 
					post_buf_pool_window_x_or_ups_hrzt_rpc_n_nxt:
					8'd0;
	end
	
	// 上采样垂直复制次数(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(~en_adapter) | 
				((pool_mode == POOL_MODE_UPSP) & post_buf_on_mov_to_nxt_pt & post_buf_is_last_ups_hrzt_rpc & post_buf_is_at_out_row_end)
			)
		)
			post_buf_ups_vtc_rpc_n <= # SIM_DELAY 
				((~en_adapter) | post_buf_is_last_ups_vtc_rpc) ? 
					8'd0:
					(post_buf_ups_vtc_rpc_n + 1'b1);
	end
	
endmodule
