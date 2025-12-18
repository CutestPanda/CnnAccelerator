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
本模块: 池化表面行缓存访问控制

描述:
根据计算参数和特征图参数, 产生"特征图表面行读请求"和"池化表面行信息"

组成 -> 特征图{切片[池化行组或池化域(表面行)]}

使用1个u16(共享)无符号乘法器和1个s18*s25(共享)有符号乘法器

注意：
输入特征图大小 = 输入特征图宽度 * 输入特征图高度

"特征图表面行读请求"仅对非填充行产生, 而"池化表面行信息"对每1行都产生

"特征图表面行读请求"里的"起始表面编号"和"待读取的表面个数 - 1"是不可用的

协议:
BLK CTRL
AXIS MASTER
REQ/GRANT

作者: 陈家耀
日期: 2025/12/11
********************************************************************/


module pool_sfc_row_buffer_access_ctrl #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	// [计算参数]
	input wire[1:0] pool_mode, // 池化模式
	input wire[2:0] pool_vertical_stride, // 池化垂直步长 - 1
	input wire[7:0] pool_window_h, // 池化窗口高度 - 1
	// [特征图参数]
	input wire[31:0] fmap_baseaddr, // 特征图数据基地址
	input wire is_16bit_data, // 是否16位特征图数据
	input wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	input wire[15:0] ifmap_h, // 输入特征图高度 - 1
	input wire[23:0] ifmap_size, // 输入特征图大小 - 1
	input wire[15:0] fmap_chn_n, // 通道数 - 1
	input wire[2:0] external_padding_top, // 上部外填充数
	input wire[15:0] ofmap_h, // 输出特征图高度 - 1
	
	// 块级控制
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
	// 池化表面行信息(AXIS主机)
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
	output wire[15:0] m_pool_sfc_row_info_axis_data,
	output wire m_pool_sfc_row_info_axis_valid,
	input wire m_pool_sfc_row_info_axis_ready,
	
	// 特征图表面行读请求(AXIS主机)
	/*
	请求格式 -> 
		{
			保留(6bit),
			是否重置缓存(1bit),
			实际表面行号(12bit),
			起始表面编号(12bit),
			待读取的表面个数 - 1(12bit),
			表面行基地址(32bit),
			表面行有效字节数(24bit),
			每个表面的有效数据个数 - 1(5bit)
		}
	*/
	output wire[103:0] m_fm_rd_req_axis_data,
	output wire m_fm_rd_req_axis_valid,
	input wire m_fm_rd_req_axis_ready,
	
	// (共享)无符号乘法器#0
	// [计算输入]
	output wire[15:0] mul0_op_a, // 操作数A
	output wire[15:0] mul0_op_b, // 操作数B
	output wire[3:0] mul0_tid, // 操作ID
	output wire mul0_req,
	input wire mul0_grant,
	// [计算结果]
	input wire[31:0] mul0_res,
	input wire[3:0] mul0_oid,
	input wire mul0_ovld,
	
	// (共享)有符号乘法器#1
	// [计算输入]
	output wire[17:0] mul1_op_a, // 操作数A
	output wire[24:0] mul1_op_b, // 操作数B
	output wire[3:0] mul1_tid, // 操作ID
	output wire mul1_req,
	input wire mul1_grant,
	// [计算结果]
	input wire[42:0] mul1_res,
	input wire[3:0] mul1_oid,
	input wire mul1_ovld
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
	// 补充运行时参数计算状态编码
	localparam integer EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE = 0;
	localparam integer EXTRA_PARAMS_CAL_STS_ONEHOT_REQ0 = 1;
	localparam integer EXTRA_PARAMS_CAL_STS_ONEHOT_RES0 = 2;
	localparam integer EXTRA_PARAMS_CAL_STS_ONEHOT_FNS = 3;
	// 池化域基地址更新状态编码
	localparam integer POOL_RGN_BASEADDR_UPD_STS_ONEHOT_UP_TO_DATE = 0;
	localparam integer POOL_RGN_BASEADDR_UPD_STS_ONEHOT_REQ = 1;
	localparam integer POOL_RGN_BASEADDR_UPD_STS_ONEHOT_RES = 2;
	localparam integer POOL_RGN_BASEADDR_UPD_STS_ONEHOT_WAIT_FOR_PARAMS = 3;
	// 池化表面行读请求生成状态编码
	localparam integer POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE = 0;
	localparam integer POOL_ROW_RD_REQ_GEN_STS_ONEHOT_RST_BUF = 1;
	localparam integer POOL_ROW_RD_REQ_GEN_STS_ONEHOT_UPD_ADDR = 2;
	localparam integer POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS = 3;
	localparam integer POOL_ROW_RD_REQ_GEN_STS_ONEHOT_DONE = 4;
	
	/** 内部配置 **/
	localparam MUL0_TID_CONST = 4'd5; // (共享)无符号乘法器#0操作ID
	localparam MUL1_TID_CONST = 4'd6; // (共享)无符号乘法器#1操作ID
	
	/** 补充运行时参数 **/
	reg[15:0] chn_n_of_last_slice; // 最后1个切片的通道数
	reg[15:0] chn_n_sub1_of_last_slice; // 最后1个切片的通道数 - 1
	reg[15:0] actual_ifmap_w; // 输入特征图宽度
	reg[23:0] actual_ifmap_size; // 输入特征图大小
	reg[23:0] row_bytes_n_of_last_slice; // 最后1个切片的行字节数
	wire row_bytes_n_of_last_slice_available; // 最后1个切片的行字节数(参数可用标志)
	wire[31:0] slice_addr_stride; // 切片地址跨度
	reg[3:0] extra_params_cal_sts; // 补充运行时参数计算状态
	
	// 计算: 最后1个切片的行字节数[23:0] = 输入特征图宽度[15:0] * (最后1个切片的通道数[15:0] * 特征点数据字节数[1:0])
	assign mul0_op_a = actual_ifmap_w[15:0];
	assign mul0_op_b = chn_n_of_last_slice[15:0] << (is_16bit_data ? 1:0);
	assign mul0_tid = MUL0_TID_CONST;
	assign mul0_req = aclken & extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_REQ0] & (~blk_idle);
	
	assign row_bytes_n_of_last_slice_available = extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_FNS];
	
	assign slice_addr_stride = ((actual_ifmap_size * ATOMIC_C) | 32'd0) << (is_16bit_data ? 1:0);
	
	// 最后1个切片的通道数, 最后1个切片的通道数 - 1, 输入特征图宽度, 输入特征图大小
	always @(posedge aclk)
	begin
		if(
			aclken & 
			extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE] & blk_idle & blk_start
		)
		begin
			if((ATOMIC_C == 1) | (&fmap_chn_n[clogb2(ATOMIC_C-1):0]))
			begin
				chn_n_of_last_slice <= # SIM_DELAY ATOMIC_C;
				chn_n_sub1_of_last_slice <= # SIM_DELAY ATOMIC_C - 1;
			end
			else
			begin
				chn_n_of_last_slice <= # SIM_DELAY (fmap_chn_n[clogb2(ATOMIC_C-1):0] + 1'b1) | 16'd0;
				chn_n_sub1_of_last_slice <= # SIM_DELAY fmap_chn_n[clogb2(ATOMIC_C-1):0] | 16'd0;
			end
			
			actual_ifmap_w <= # SIM_DELAY ifmap_w + 1'b1;
			
			actual_ifmap_size <= # SIM_DELAY ifmap_size + 1'b1;
		end
	end
	
	// 最后1个切片的行字节数
	always @(posedge aclk)
	begin
		if(mul0_ovld & (mul0_oid == MUL0_TID_CONST))
			row_bytes_n_of_last_slice <= # SIM_DELAY mul0_res[23:0];
	end
	
	// 补充运行时参数计算状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			extra_params_cal_sts <= 1 << EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE;
		else if(
			(extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_RES0] | aclken) & 
			(
				(extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE] & blk_idle & blk_start) | 
				(extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_REQ0] & (blk_idle | (mul0_req & mul0_grant))) | 
				(extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_RES0] & (blk_idle | (mul0_ovld & (mul0_oid == MUL0_TID_CONST)))) | 
				(extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_FNS] & (blk_idle | blk_done))
			)
		)
			extra_params_cal_sts <= # SIM_DELAY 
				(
					{4{extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE]}} & 
					(1 << EXTRA_PARAMS_CAL_STS_ONEHOT_REQ0)
				) | 
				(
					{4{extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_REQ0]}} & 
					(
						blk_idle ? 
							(1 << EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE):
							(1 << EXTRA_PARAMS_CAL_STS_ONEHOT_RES0)
					)
				) | 
				(
					{4{extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_RES0]}} & 
					(
						blk_idle ? 
							(1 << EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE):
							(1 << EXTRA_PARAMS_CAL_STS_ONEHOT_FNS)
					)
				) | 
				(
					{4{extra_params_cal_sts[EXTRA_PARAMS_CAL_STS_ONEHOT_FNS]}} & 
					(1 << EXTRA_PARAMS_CAL_STS_ONEHOT_IDLE)
				);
	end
	
	/** 池化进程控制 **/
	// [计数器组]
	reg signed[15:0] pool_rgn_base_rid; // 池化域起始行号(计数器)
	reg[7:0] pool_rgn_ofs_rid; // 池化域偏移行号(计数器)
	reg signed[15:0] pool_rid; // 待池化行号(计数器)
	reg[15:0] ofmap_rid; // 输出特征图行号(计数器)
	reg[15:0] chn_n_swept; // 扫过的通道数(计数器)
	// [计数器组的下一值]
	wire signed[15:0] pool_rgn_base_rid_nxt; // 下一池化域起始行号(计数值)
	wire[15:0] chn_n_swept_nxt; // 下一扫过的通道数(计数值)
	// [地址生成]
	reg[31:0] pool_slice_baseaddr; // 池化切片基地址
	reg[31:0] pool_row_addr; // 池化行地址
	wire[4:0] cur_row_depth; // 当前行深度
	wire[23:0] cur_row_bytes_n; // 当前行字节数
	reg[3:0] pool_rgn_baseaddr_upd_sts; // 池化域基地址更新状态
	// [标志组]
	wire is_first_solid_row_in_pool_rgn; // 是否池化域内的第1个非填充表面行
	wire is_last_solid_row_in_pool_rgn; // 是否池化域内的最后1个非填充表面行
	reg is_arrive_first_row_in_pool_rgn; // 位于池化域里的第1行(标志)
	wire is_arrive_last_row_in_pool_rgn; // 抵达池化域里的最后1行(标志)
	wire is_arrive_last_out_row; // 抵达最后1个输出行(标志)
	wire is_arrive_last_slice; // 抵达最后1个切片(标志)
	wire is_pool_row_in_padding_rgn; // 待池化行处于填充域(标志)
	// [控制信号]
	wire on_mov_to_nxt_row; // 移动到下1行(指示)
	reg on_cal_pool_rgn_baseaddr; // 计算池化域基地址(指示)
	
	assign mul1_op_a = {{2{pool_rid[15]}}, pool_rid[15:0]};
	assign mul1_op_b = {1'b0, cur_row_bytes_n[23:0]};
	assign mul1_tid = MUL1_TID_CONST;
	assign mul1_req = 
		aclken & 
		(
			(
				pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_UP_TO_DATE] & 
				on_cal_pool_rgn_baseaddr & 
				((~is_arrive_last_slice) | row_bytes_n_of_last_slice_available)
			) | 
			pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_REQ]
		) & 
		(~blk_idle);
	
	assign pool_rgn_base_rid_nxt = 
		(
			(blk_idle | is_arrive_last_out_row) ? 
				16'd0:
				pool_rgn_base_rid
		) + 
		(
			(blk_idle | is_arrive_last_out_row) ? 
				(~(external_padding_top | 16'd0)):
				(((pool_mode == POOL_MODE_UPSP) ? 3'd0:pool_vertical_stride) | 16'd0)
		) + 1'b1;
	assign chn_n_swept_nxt = 
		chn_n_swept + ATOMIC_C;
	
	assign cur_row_depth = 
		is_arrive_last_slice ? 
			chn_n_sub1_of_last_slice[4:0]:
			(ATOMIC_C - 1);
	assign cur_row_bytes_n = 
		is_arrive_last_slice ? 
			row_bytes_n_of_last_slice:
			(((actual_ifmap_w * ATOMIC_C) | 24'd0) << (is_16bit_data ? 1:0));
	
	assign is_first_solid_row_in_pool_rgn = (pool_rid == 16'd0) | ((~is_pool_row_in_padding_rgn) & is_arrive_first_row_in_pool_rgn);
	assign is_last_solid_row_in_pool_rgn = (pool_rid == ifmap_h) | ((~is_pool_row_in_padding_rgn) & is_arrive_last_row_in_pool_rgn);
	assign is_arrive_last_row_in_pool_rgn = (pool_mode == POOL_MODE_UPSP) | (pool_rgn_ofs_rid == pool_window_h);
	assign is_arrive_last_out_row = ofmap_rid == ofmap_h;
	assign is_arrive_last_slice = chn_n_swept_nxt > fmap_chn_n;
	assign is_pool_row_in_padding_rgn = 
		pool_rid[15] | // 待池化行号 < 0
		(pool_rid[14:0] > ifmap_h[14:0]); // 待池化行号 >= 输入特征图高度
	
	// 池化域起始行号(计数器), 输出特征图行号(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_mov_to_nxt_row & is_arrive_last_row_in_pool_rgn))
		)
		begin
			pool_rgn_base_rid <= # SIM_DELAY 
				pool_rgn_base_rid_nxt;
			
			ofmap_rid <= # SIM_DELAY 
				(blk_idle | is_arrive_last_out_row) ? 
					16'd0:
					(ofmap_rid + 1'b1);
		end
	end
	
	// 池化域偏移行号(计数器), 待池化行号(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | on_mov_to_nxt_row)
		)
		begin
			pool_rgn_ofs_rid <= # SIM_DELAY 
				(blk_idle | is_arrive_last_row_in_pool_rgn) ? 
					8'd0:
					(pool_rgn_ofs_rid + 1'b1);
			
			pool_rid <= # SIM_DELAY 
				(blk_idle | is_arrive_last_row_in_pool_rgn) ? 
					pool_rgn_base_rid_nxt:
					(pool_rid + 1'b1);
		end
	end
	
	// 扫过的通道数(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_mov_to_nxt_row & is_arrive_last_row_in_pool_rgn & is_arrive_last_out_row))
		)
			chn_n_swept <= # SIM_DELAY 
				(blk_idle | is_arrive_last_slice) ? 
					16'd0:
					chn_n_swept_nxt;
	end
	
	// 池化切片基地址
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_mov_to_nxt_row & is_arrive_last_row_in_pool_rgn & is_arrive_last_out_row))
		)
			pool_slice_baseaddr <= # SIM_DELAY 
				(blk_idle | is_arrive_last_slice) ? 
					fmap_baseaddr:
					(pool_slice_baseaddr + slice_addr_stride);
	end
	
	// 池化行地址
	always @(posedge aclk)
	begin
		if(
			(mul1_ovld & (mul1_oid == MUL1_TID_CONST)) | 
			(aclken & on_mov_to_nxt_row)
		)
			pool_row_addr <= # SIM_DELAY 
				(
					(mul1_ovld & (mul1_oid == MUL1_TID_CONST)) ? 
						pool_slice_baseaddr:
						pool_row_addr
				) + 
				(
					(mul1_ovld & (mul1_oid == MUL1_TID_CONST)) ? 
						mul1_res[31:0]:
						(cur_row_bytes_n | 32'd0)
				);
	end
	
	// 池化域基地址更新状态
	always @(posedge aclk)
	begin
		if(
			(pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_RES] | aclken) & 
			(
				blk_idle | 
				(pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_UP_TO_DATE] & on_cal_pool_rgn_baseaddr) | 
				(pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_REQ] & mul1_req & mul1_grant) | 
				(pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_RES] & (mul1_ovld & (mul1_oid == MUL1_TID_CONST))) | 
				(pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_WAIT_FOR_PARAMS] & row_bytes_n_of_last_slice_available)
			)
		)
			pool_rgn_baseaddr_upd_sts <= # SIM_DELAY 
				blk_idle ? 
					(1 << POOL_RGN_BASEADDR_UPD_STS_ONEHOT_UP_TO_DATE):
					(
						(
							{4{pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_UP_TO_DATE]}} & 
							(
								((~is_arrive_last_slice) | row_bytes_n_of_last_slice_available) ? 
									(
										mul1_grant ? 
											(1 << POOL_RGN_BASEADDR_UPD_STS_ONEHOT_RES):
											(1 << POOL_RGN_BASEADDR_UPD_STS_ONEHOT_REQ)
									):
									(1 << POOL_RGN_BASEADDR_UPD_STS_ONEHOT_WAIT_FOR_PARAMS)
							)
						) | 
						(
							{4{pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_REQ]}} & 
							(1 << POOL_RGN_BASEADDR_UPD_STS_ONEHOT_RES)
						) | 
						(
							{4{pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_RES]}} & 
							(1 << POOL_RGN_BASEADDR_UPD_STS_ONEHOT_UP_TO_DATE)
						) | 
						(
							{4{pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_WAIT_FOR_PARAMS]}} & 
							(1 << POOL_RGN_BASEADDR_UPD_STS_ONEHOT_REQ)
						)
					);
	end
	
	// 位于池化域里的第1行(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | on_mov_to_nxt_row)
		)
			is_arrive_first_row_in_pool_rgn <= # SIM_DELAY 
				blk_idle | is_arrive_last_row_in_pool_rgn;
	end
	
	/** 池化表面行信息与读请求生成 **/
	reg[4:0] pool_row_rd_req_gen_sts; // 池化表面行读请求生成状态
	wire no_need_to_send_fm_rd_req; // 不需要发送读请求(标志)
	reg to_suppress_fm_rd_req_tsf; // 镇压读请求的发送(标志)
	reg to_suppress_row_info_tsf; // 镇压行信息的发送(标志)
	reg to_terminate_info_or_req_gen; // 结束信息与请求生成(标志)
	
	assign blk_idle = pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE];
	assign blk_done = pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_DONE];
	
	assign m_pool_sfc_row_info_axis_data = {
		6'bxxxxxx, // 保留(6bit)
		cur_row_depth, // 表面行深度 - 1(5bit)
		is_last_solid_row_in_pool_rgn, // 是否池化域内的最后1个非填充表面行(1bit)
		is_first_solid_row_in_pool_rgn, // 是否池化域内的第1个非填充表面行(1bit)
		is_arrive_last_row_in_pool_rgn, // 是否池化域内的最后1个表面行(1bit)
		is_arrive_first_row_in_pool_rgn, // 是否池化域内的第1个表面行(1bit)
		is_pool_row_in_padding_rgn // 是否填充行(1bit)
	};
	assign m_pool_sfc_row_info_axis_valid = 
		aclken & pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & (~to_suppress_row_info_tsf);
	
	assign m_fm_rd_req_axis_data = {
		6'bxxxxxx, // 保留(6bit)
		pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_RST_BUF], // 是否重置缓存(1bit)
		pool_rid[11:0], // 实际表面行号(12bit)
		12'hxxx, // 起始表面编号(12bit)
		12'hxxx, // 待读取的表面个数 - 1(12bit)
		pool_row_addr, // 表面行基地址(32bit)
		cur_row_bytes_n, // 表面行有效字节数(24bit)
		cur_row_depth // 每个表面的有效数据个数 - 1(5bit)
	};
	assign m_fm_rd_req_axis_valid = 
		aclken & 
		(
			(
				pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
				(~no_need_to_send_fm_rd_req) & (~to_suppress_fm_rd_req_tsf)
			) | 
			pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_RST_BUF]
		);
	
	assign on_mov_to_nxt_row = 
		pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
		(
			(no_need_to_send_fm_rd_req | to_suppress_fm_rd_req_tsf | m_fm_rd_req_axis_ready) & 
			(to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready)
		);
	
	assign no_need_to_send_fm_rd_req = is_pool_row_in_padding_rgn;
	
	// 计算池化域基地址(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_cal_pool_rgn_baseaddr <= 1'b0;
		else if(
			aclken & 
			(
				on_cal_pool_rgn_baseaddr | 
				(
					(
						pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE] & 
						blk_start
					) | 
					(
						pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
						(
							(no_need_to_send_fm_rd_req | to_suppress_fm_rd_req_tsf | m_fm_rd_req_axis_ready) & 
							(to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready) & 
							is_arrive_last_row_in_pool_rgn & (~(is_arrive_last_out_row & is_arrive_last_slice))
						)
					)
				)
			)
		)
			on_cal_pool_rgn_baseaddr <= # SIM_DELAY ~on_cal_pool_rgn_baseaddr;
	end
	
	// 池化表面行读请求生成状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pool_row_rd_req_gen_sts <= 1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE;
		else if(
			aclken & 
			(
				(pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE] & blk_start) | 
				(pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_RST_BUF] & m_fm_rd_req_axis_ready) | 
				(
					pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_UPD_ADDR] & 
					(
						(~on_cal_pool_rgn_baseaddr) & 
						pool_rgn_baseaddr_upd_sts[POOL_RGN_BASEADDR_UPD_STS_ONEHOT_UP_TO_DATE]
					)
				) | 
				(
					pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
					(
						(no_need_to_send_fm_rd_req | to_suppress_fm_rd_req_tsf | m_fm_rd_req_axis_ready) & 
						(to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready) & 
						is_arrive_last_row_in_pool_rgn
					)
				) | 
				pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_DONE]
			)
		)
			pool_row_rd_req_gen_sts <= # SIM_DELAY 
				(
					{5{pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE]}} & 
					(1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_RST_BUF)
				) | 
				(
					{5{pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_RST_BUF]}} & 
					(
						to_terminate_info_or_req_gen ? 
							(1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_DONE):
							(1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_UPD_ADDR)
					)
				) | 
				(
					{5{pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_UPD_ADDR]}} & 
					(1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS)
				) | 
				(
					{5{pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS]}} & 
					(
						is_arrive_last_out_row ? 
							(1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_RST_BUF):
							(1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_UPD_ADDR)
					)
				) | 
				(
					{5{pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_DONE]}} & 
					(1 << POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE)
				);
	end
	
	// 镇压读请求的发送(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				blk_idle | 
				(
					/*
					to_suppress_fm_rd_req_tsf ? 
						(
							pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
							(to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready)
						):
						(
							pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
							(~no_need_to_send_fm_rd_req) & m_fm_rd_req_axis_ready & 
							(~(to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready))
						)
					*/
					pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
					(to_suppress_fm_rd_req_tsf | ((~no_need_to_send_fm_rd_req) & m_fm_rd_req_axis_ready)) & 
					((~to_suppress_fm_rd_req_tsf) ^ (to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready))
				)
			)
		)
			to_suppress_fm_rd_req_tsf <= # SIM_DELAY ~(blk_idle | to_suppress_fm_rd_req_tsf);
	end
	// 镇压行信息的发送(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				blk_idle | 
				(
					/*
					to_suppress_row_info_tsf ? 
						(
							pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
							(no_need_to_send_fm_rd_req | to_suppress_fm_rd_req_tsf | m_fm_rd_req_axis_ready)
						):
						(
							pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
							m_pool_sfc_row_info_axis_ready & 
							(~(no_need_to_send_fm_rd_req | to_suppress_fm_rd_req_tsf | m_fm_rd_req_axis_ready))
						)
					*/
					pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
					(to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready) & 
					((~to_suppress_row_info_tsf) ^ (no_need_to_send_fm_rd_req | to_suppress_fm_rd_req_tsf | m_fm_rd_req_axis_ready))
				)
			)
		)
			to_suppress_row_info_tsf <= # SIM_DELAY ~(blk_idle | to_suppress_row_info_tsf);
	end
	
	// 结束信息与请求生成(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_IDLE] & blk_start) | 
				(
					pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & 
					(
						(no_need_to_send_fm_rd_req | to_suppress_fm_rd_req_tsf | m_fm_rd_req_axis_ready) & 
						(to_suppress_row_info_tsf | m_pool_sfc_row_info_axis_ready) & 
						is_arrive_last_row_in_pool_rgn & is_arrive_last_out_row
					)
				)
			)
		)
			to_terminate_info_or_req_gen <= # SIM_DELAY 
				pool_row_rd_req_gen_sts[POOL_ROW_RD_REQ_GEN_STS_ONEHOT_TRANS] & is_arrive_last_slice;
	end
	
endmodule
