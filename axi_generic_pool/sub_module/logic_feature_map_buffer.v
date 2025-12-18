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
本模块: (逻辑)特征图缓存

描述:
将物理特征图缓存分为若干个表面行区域
每个表面行区域都能独立地激活/置换

支持读请求后自动置换表面行
支持表面行随机读取

记录实际表面行号与缓存行号之间的双向映射 -> 
	1个实际表面行号映射表MEM(简单双口, 位宽 = BUFFER_RID_WIDTH, 深度 = 4K)
	1个缓存行号映射表MEM(简单双口, 位宽 = 12, 深度 = MAX_FMBUF_ROWN)
	1个缓存表面行有效标志寄存器组(位宽 = 1, 深度 = MAX_FMBUF_ROWN)

表面行检索具有2clk的时延

注意：
暂不支持INT8运算数据格式

在输入特征图表面行数据流中, 应当连续输入1个表面行的表面数据
写特征图表面行时, 会等待直到这个表面行无效

在发起特征图表面行读请求前, 应当检查这个表面行是否已缓存, 否则会在特征图表面行数据流中给出错误标志
必须保证访问逻辑特征图缓存的行号<=表面行数-1(fmbufrown)

在使用逻辑特征图缓存前, 必须先重置(将rst_logic_fmbuf置高)

实际表面行号映射表MEM读延迟 = 1clk, 缓存行号映射表MEM读延迟 = 1clk

仿真时应对实际表面行号映射表MEM和缓存行号映射表MEM进行初始化, 但在实际运行时是不需要的

协议:
AXIS MASTER/SLAVE
ICB MASTER
MEM MASTER

作者: 陈家耀
日期: 2025/12/10
********************************************************************/


module logic_feature_map_buffer #(
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BUFFER_RID_WIDTH = 9, // 缓存行号的位宽(3~10, 应为clogb2(MAX_FMBUF_ROWN))
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[3:0] fmbufcoln, // 每个表面行的表面个数类型
	input wire[9:0] fmbufrown, // 表面行数 - 1
	input wire fmrow_random_rd_mode, // 是否处于表面行随机读取模式
	
	// 控制/状态
	input wire rst_logic_fmbuf, // 重置逻辑特征图缓存
	input wire sfc_row_rplc_req, // 表面行置换请求
	input wire[9:0] sfc_rid_to_rplc, // 待置换的表面行编号
	output wire[3:0] sfc_row_stored_rd_req_eid, // 新存入表面行对应的读请求项索引
	output wire sfc_row_stored_vld, // 表面行存储完成
	
	// 表面行检索
	// [检索输入]
	input wire sfc_row_search_i_req, // 检索请求
	input wire[11:0] sfc_row_search_i_rid, // 待检索的实际表面行号
	// [检索输出]
	output wire sfc_row_search_o_vld, // 检索结果有效
	output wire[9:0] sfc_row_search_o_buf_id, // 检索得到的缓存号
	output wire sfc_row_search_o_found, // 找到待检索的表面行(标志)
	
	// 特征图表面行数据输入(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_fin_axis_data,
	input wire[ATOMIC_C*2-1:0] s_fin_axis_keep,
	input wire[25:0] s_fin_axis_user, // {读请求项索引(4bit), 实际表面行号(12bit), 表面行的缓存编号(10bit)}
	input wire s_fin_axis_last, // 标志当前表面行的最后1个表面
	input wire s_fin_axis_valid,
	output wire s_fin_axis_ready,
	
	// 特征图表面行读请求(AXIS从机)
	/*
	请求格式 -> 
		{
			保留(5bit),
			是否需要自动置换表面行(1bit),
			表面行的缓存编号(10bit),
			起始表面编号(12bit),
			待读取的表面个数 - 1(12bit)
		}
	*/
	input wire[39:0] s_rd_req_axis_data,
	input wire s_rd_req_axis_valid,
	output wire s_rd_req_axis_ready,
	// 特征图表面行随机读取(AXIS从机)
	input wire[15:0] s_random_rd_axis_data, // 表面号
	input wire s_random_rd_axis_last, // 标志本次读请求待读取的最后1个表面
	input wire s_random_rd_axis_valid,
	output wire s_random_rd_axis_ready,
	// 特征图表面行数据输出(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_fout_axis_data,
	output wire m_fout_axis_user, // 标志表面行未缓存
	output wire m_fout_axis_last, // 标志本次读请求的最后1个表面
	output wire m_fout_axis_valid,
	input wire m_fout_axis_ready,
	
	// 特征图缓存ICB主机#0
	// [命令通道]
	output wire[31:0] m0_fmbuf_cmd_addr,
	output wire m0_fmbuf_cmd_read, // const -> 1'b0
	output wire[ATOMIC_C*2*8-1:0] m0_fmbuf_cmd_wdata,
	output wire[ATOMIC_C*2-1:0] m0_fmbuf_cmd_wmask, // const -> {(ATOMIC_C*2){1'b1}}
	output wire m0_fmbuf_cmd_valid,
	input wire m0_fmbuf_cmd_ready,
	// [响应通道]
	input wire[ATOMIC_C*2*8-1:0] m0_fmbuf_rsp_rdata, // ignored
	input wire m0_fmbuf_rsp_err, // ignored
	input wire m0_fmbuf_rsp_valid,
	output wire m0_fmbuf_rsp_ready, // const -> 1'b1
	
	// 特征图缓存ICB主机#1
	// [命令通道]
	output wire[31:0] m1_fmbuf_cmd_addr,
	output wire m1_fmbuf_cmd_read, // const -> 1'b1
	output wire[ATOMIC_C*2*8-1:0] m1_fmbuf_cmd_wdata, // not care
	output wire[ATOMIC_C*2-1:0] m1_fmbuf_cmd_wmask, // not care
	output wire m1_fmbuf_cmd_valid,
	input wire m1_fmbuf_cmd_ready,
	// [响应通道]
	input wire[ATOMIC_C*2*8-1:0] m1_fmbuf_rsp_rdata,
	input wire m1_fmbuf_rsp_err,
	input wire m1_fmbuf_rsp_valid,
	output wire m1_fmbuf_rsp_ready,
	
	// 实际表面行号映射表MEM
	// 说明: 实际表面行号 ----映射----> 缓存行号
	output wire actual_rid_mp_tb_mem_clk,
	// [写端口]
	output wire actual_rid_mp_tb_mem_wen_a,
	output wire[11:0] actual_rid_mp_tb_mem_addr_a,
	output wire[BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_din_a,
	// [读端口]
	output wire actual_rid_mp_tb_mem_ren_b,
	output wire[11:0] actual_rid_mp_tb_mem_addr_b,
	input wire[BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_dout_b,
	
	// 缓存行号映射表MEM
	// 说明: 缓存行号 ----映射----> 实际表面行号
	output wire buffer_rid_mp_tb_mem_clk,
	// [写端口]
	output wire buffer_rid_mp_tb_mem_wen_a,
	output wire[BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_a,
	output wire[11:0] buffer_rid_mp_tb_mem_din_a,
	// [读端口]
	output wire buffer_rid_mp_tb_mem_ren_b,
	output wire[BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_b,
	input wire[11:0] buffer_rid_mp_tb_mem_dout_b
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
	// 每个表面行的表面个数类型编码
	localparam FMBUFCOLN_4 = 4'b0000;
	localparam FMBUFCOLN_8 = 4'b0001;
	localparam FMBUFCOLN_16 = 4'b0010;
	localparam FMBUFCOLN_32 = 4'b0011;
	localparam FMBUFCOLN_64 = 4'b0100;
	localparam FMBUFCOLN_128 = 4'b0101;
	localparam FMBUFCOLN_256 = 4'b0110;
	localparam FMBUFCOLN_512 = 4'b0111;
	localparam FMBUFCOLN_1024 = 4'b1000;
	localparam FMBUFCOLN_2048 = 4'b1001;
	localparam FMBUFCOLN_4096 = 4'b1010;
	// 写特征图状态常量
	localparam WTFM_STS_IDLE = 2'b00;
	localparam WTFM_STS_TRANS = 2'b01;
	localparam WTFM_STS_UPD_FLAG = 2'b11;
	// 读特征图状态常量
	localparam RDFM_STS_IDLE = 3'b000;
	localparam RDFM_STS_FLAG_JUDGE = 3'b001;
	localparam RDFM_STS_ROW_INVALID = 3'b010;
	localparam RDFM_STS_TRANS = 3'b011;
	localparam RDFM_STS_UPD_FLAG = 3'b100;
	
	/** 补充运行时参数 **/
	wire[3:0] fmbufcoln_lshn; // 表面行缓存宽度导致的左移量
	
	assign fmbufcoln_lshn = 
		(fmbufcoln == FMBUFCOLN_4)    ? 4'd2:
		(fmbufcoln == FMBUFCOLN_8)    ? 4'd3:
		(fmbufcoln == FMBUFCOLN_16)   ? 4'd4:
		(fmbufcoln == FMBUFCOLN_32)   ? 4'd5:
		(fmbufcoln == FMBUFCOLN_64)   ? 4'd6:
		(fmbufcoln == FMBUFCOLN_128)  ? 4'd7:
		(fmbufcoln == FMBUFCOLN_256)  ? 4'd8:
		(fmbufcoln == FMBUFCOLN_512)  ? 4'd9:
		(fmbufcoln == FMBUFCOLN_1024) ? 4'd10:
		(fmbufcoln == FMBUFCOLN_2048) ? 4'd11:
		                                4'd12;
	
	/** 表面行有效标志 **/
	reg sfc_row_vld_flags[0:MAX_FMBUF_ROWN-1]; // 表面行有效标志(存储实体)
	wire wtfm_activate_req; // 写特征图激活表面行(请求)
	wire[clogb2(MAX_FMBUF_ROWN-1):0] wtfm_activate_rid; // 写特征图待激活表面行的编号
	wire rdfm_rplc_req; // 读特征图自动置换表面行(请求)
	wire[clogb2(MAX_FMBUF_ROWN-1):0] rdfm_rplc_rid; // 读特征图待自动置换表面行的编号
	
	genvar sfc_row_vld_i;
	generate
		for(sfc_row_vld_i = 0;sfc_row_vld_i < MAX_FMBUF_ROWN;sfc_row_vld_i = sfc_row_vld_i + 1)
		begin:sfc_row_vld_flags_blk
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					sfc_row_vld_flags[sfc_row_vld_i] <= 1'b0;
				else if(
					aclken & 
					(
						rst_logic_fmbuf | 
						(wtfm_activate_req & (wtfm_activate_rid == sfc_row_vld_i)) | 
						(rdfm_rplc_req & (rdfm_rplc_rid == sfc_row_vld_i)) | 
						(sfc_row_rplc_req & (sfc_rid_to_rplc[clogb2(MAX_FMBUF_ROWN-1):0] == sfc_row_vld_i))
					)
				)
					sfc_row_vld_flags[sfc_row_vld_i] <= # SIM_DELAY 
						// "重置逻辑特征图缓存"或"置换表面行"导致的清零优先级更高
						(~(
							rst_logic_fmbuf | 
							(rdfm_rplc_req & (rdfm_rplc_rid == sfc_row_vld_i)) | 
							(sfc_row_rplc_req & (sfc_rid_to_rplc[clogb2(MAX_FMBUF_ROWN-1):0] == sfc_row_vld_i))
						)) & 
						(wtfm_activate_req & (wtfm_activate_rid == sfc_row_vld_i));
			end
		end
	endgenerate
	
	/** 写特征图 **/
	wire[ATOMIC_C*2*8-1:0] in_fm_data_mask; // 输入特征图表面数据掩码
	reg[1:0] wtfm_sts; // 写特征图状态
	wire fmrow_to_wt_is_vld; // 待写表面行是否有效
	reg[31:0] wt_fmbuf_addr; // 写特征图缓存地址
	reg wt_fmbuf_bus_cmd_fns; // 写特征图缓存总线命令事务完成(标志)
	reg[12:0] wt_fmbuf_trans_sfc; // 写特征图缓存正在传输的表面数
	reg[clogb2(MAX_FMBUF_ROWN-1):0] wtfm_rid; // 写特征图表面行号
	reg[3:0] wtfm_rd_req_eid; // 写特征图表面行对应的读请求项索引
	
	assign sfc_row_stored_rd_req_eid = wtfm_rd_req_eid;
	assign sfc_row_stored_vld = aclken & (~rst_logic_fmbuf) & (wtfm_sts == WTFM_STS_UPD_FLAG);
	
	// 握手条件: aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & s_fin_axis_valid & m0_fmbuf_cmd_ready
	assign s_fin_axis_ready = aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & m0_fmbuf_cmd_ready;
	
	assign m0_fmbuf_cmd_addr = wt_fmbuf_addr;
	assign m0_fmbuf_cmd_read = 1'b0;
	assign m0_fmbuf_cmd_wdata = s_fin_axis_data & in_fm_data_mask;
	assign m0_fmbuf_cmd_wmask = {(ATOMIC_C*2){1'b1}};
	// 握手条件: aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & s_fin_axis_valid & m0_fmbuf_cmd_ready
	assign m0_fmbuf_cmd_valid = aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & s_fin_axis_valid;
	
	assign m0_fmbuf_rsp_ready = aclken;
	
	assign wtfm_activate_req = (~rst_logic_fmbuf) & (wtfm_sts == WTFM_STS_UPD_FLAG);
	assign wtfm_activate_rid = wtfm_rid;
	
	genvar in_fm_data_mask_i;
	generate
		for(in_fm_data_mask_i = 0;in_fm_data_mask_i < ATOMIC_C*2;in_fm_data_mask_i = in_fm_data_mask_i + 1)
		begin:in_fm_data_mask_blk
			assign in_fm_data_mask[in_fm_data_mask_i*8+7:in_fm_data_mask_i*8] = 
				{8{s_fin_axis_keep[in_fm_data_mask_i]}};
		end
	endgenerate
	
	assign fmrow_to_wt_is_vld = sfc_row_vld_flags[s_fin_axis_user[clogb2(MAX_FMBUF_ROWN-1):0]];
	
	// 写特征图状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wtfm_sts <= WTFM_STS_IDLE;
		else if(aclken)
		begin
			if(rst_logic_fmbuf)
				wtfm_sts <= # SIM_DELAY WTFM_STS_IDLE;
			else
			begin
				case(wtfm_sts)
					WTFM_STS_IDLE:
						if(s_fin_axis_valid & (~fmrow_to_wt_is_vld))
							wtfm_sts <= # SIM_DELAY WTFM_STS_TRANS;
					WTFM_STS_TRANS:
						if(wt_fmbuf_bus_cmd_fns & (wt_fmbuf_trans_sfc == 13'd0))
							wtfm_sts <= # SIM_DELAY WTFM_STS_UPD_FLAG;
					WTFM_STS_UPD_FLAG:
						wtfm_sts <= # SIM_DELAY WTFM_STS_IDLE;
					default:
						wtfm_sts <= # SIM_DELAY WTFM_STS_IDLE;
				endcase
			end
		end
	end
	
	// 写特征图缓存地址
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(
				(wtfm_sts == WTFM_STS_IDLE) & 
				(s_fin_axis_valid & (~fmrow_to_wt_is_vld))
			)
				wt_fmbuf_addr <= # SIM_DELAY 
					((s_fin_axis_user[clogb2(MAX_FMBUF_ROWN-1):0] | 32'h0000_0000) << fmbufcoln_lshn) * ATOMIC_C * 2;
			else if(m0_fmbuf_cmd_valid & m0_fmbuf_cmd_ready)
				wt_fmbuf_addr <= # SIM_DELAY 
					wt_fmbuf_addr + ATOMIC_C * 2;
		end
	end
	
	// 写特征图缓存总线命令事务完成(标志)
	always @(posedge aclk)
	begin
		if(aclken & (rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE) | (~wt_fmbuf_bus_cmd_fns)))
			wt_fmbuf_bus_cmd_fns <= # SIM_DELAY 
				(~(rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE))) & 
				(s_fin_axis_valid & s_fin_axis_ready & s_fin_axis_last);
	end
	
	// 写特征图缓存正在传输的表面数
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE) | 
				((m0_fmbuf_cmd_valid & m0_fmbuf_cmd_ready) ^ (m0_fmbuf_rsp_valid & m0_fmbuf_rsp_ready))
			)
		)
			wt_fmbuf_trans_sfc <= # SIM_DELAY 
				{13{~(rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE))}} & 
				/*
				(m0_fmbuf_rsp_valid & m0_fmbuf_rsp_ready) ? 
					(wt_fmbuf_trans_sfc - 13'd1):
					(wt_fmbuf_trans_sfc + 13'd1)
				*/
				(
					
					wt_fmbuf_trans_sfc + 
					{{12{m0_fmbuf_rsp_valid & m0_fmbuf_rsp_ready}}, 1'b1}
				);
	end
	
	// 写特征图表面行号
	always @(posedge aclk)
	begin
		if(aclken & s_fin_axis_valid & s_fin_axis_ready & s_fin_axis_last)
			wtfm_rid <= # SIM_DELAY s_fin_axis_user[clogb2(MAX_FMBUF_ROWN-1):0];
	end
	
	// 写特征图表面行对应的读请求项索引
	always @(posedge aclk)
	begin
		if(aclken & s_fin_axis_valid & s_fin_axis_ready & s_fin_axis_last)
			wtfm_rd_req_eid <= # SIM_DELAY s_fin_axis_user[25:22];
	end
	
	/** 读特征图 **/
	wire s_rd_req_axis_data_auto_rplc; // 是否需要自动置换表面行
	wire[9:0] s_rd_req_axis_data_rid; // 表面行的缓存编号
	wire[11:0] s_rd_req_axis_data_start_sfc_id; // 起始表面编号
	wire[11:0] s_rd_req_axis_data_sfc_n; // 待读取的表面个数 - 1
	reg[2:0] rdfm_sts; // 读特征图状态
	reg fmrow_to_rd_is_vld; // 待读表面行是否有效
	reg[31:0] rd_fmbuf_addr; // 读特征图缓存地址
	reg auto_rplc_sfc_row_after_rd; // 锁存的自动置换表面行标志
	reg[9:0] sfc_rid_to_rd; // 锁存的待读取表面行编号
	reg[11:0] sfc_n_to_rd; // 锁存的"待读取表面数 - 1"
	reg[12:0] sfc_rd_cmd_n_sent; // 已发送的表面读命令
	reg[12:0] sfc_rd_resp_n_recv; // 已接收的表面读响应
	reg to_suppress_random_rd; // 镇压随机读取(标志)
	
	// 握手条件: aclken & s_rd_req_axis_valid & (rdfm_sts == RDFM_STS_FLAG_JUDGE)
	assign s_rd_req_axis_ready = aclken & (rdfm_sts == RDFM_STS_FLAG_JUDGE);
	
	/*
	握手条件:
		s_random_rd_axis_valid & 
		(
			(~fmrow_random_rd_mode) | 
			(aclken & (rdfm_sts == RDFM_STS_TRANS) & (~to_suppress_random_rd) & m1_fmbuf_cmd_ready)
		)
	*/
	assign s_random_rd_axis_ready = 
		(~fmrow_random_rd_mode) | 
		(aclken & (rdfm_sts == RDFM_STS_TRANS) & (~to_suppress_random_rd) & m1_fmbuf_cmd_ready);
	
	assign m_fout_axis_data = 
		m1_fmbuf_rsp_rdata;
	assign m_fout_axis_user = 
		rdfm_sts == RDFM_STS_ROW_INVALID;
	assign m_fout_axis_last = 
		(rdfm_sts == RDFM_STS_ROW_INVALID) | 
		(((~fmrow_random_rd_mode) | to_suppress_random_rd) & (sfc_rd_resp_n_recv == {1'b0, sfc_n_to_rd}));
	/*
	握手条件:
		aclken & (
			(rdfm_sts == RDFM_STS_ROW_INVALID) | 
			((rdfm_sts == RDFM_STS_TRANS) & m1_fmbuf_rsp_valid)
		) & m_fout_axis_ready
	*/
	assign m_fout_axis_valid = 
		aclken & (
			(rdfm_sts == RDFM_STS_ROW_INVALID) | 
			((rdfm_sts == RDFM_STS_TRANS) & m1_fmbuf_rsp_valid)
		);
	
	assign m1_fmbuf_cmd_addr = 
		rd_fmbuf_addr + 
		(fmrow_random_rd_mode ? (s_random_rd_axis_data | 32'd0):32'd0) * ATOMIC_C * 2;
	assign m1_fmbuf_cmd_read = 1'b1;
	assign m1_fmbuf_cmd_wdata = {(ATOMIC_C*2*8){1'bx}};
	assign m1_fmbuf_cmd_wmask = {(ATOMIC_C*2){1'bx}};
	/*
	握手条件:
		aclken & (rdfm_sts == RDFM_STS_TRANS) & 
		(
			fmrow_random_rd_mode ? 
				(s_random_rd_axis_valid & (~to_suppress_random_rd)):
				(sfc_rd_cmd_n_sent <= {1'b0, sfc_n_to_rd})
		) & 
		m1_fmbuf_cmd_ready
	*/
	assign m1_fmbuf_cmd_valid = 
		aclken & (rdfm_sts == RDFM_STS_TRANS) & 
		(
			fmrow_random_rd_mode ? 
				(s_random_rd_axis_valid & (~to_suppress_random_rd)):
				(sfc_rd_cmd_n_sent <= {1'b0, sfc_n_to_rd})
		);
	
	/*
	握手条件: 
		aclken & (rdfm_sts == RDFM_STS_TRANS) & m1_fmbuf_rsp_valid & 
		m_fout_axis_ready
	*/
	assign m1_fmbuf_rsp_ready = 
		aclken & (rdfm_sts == RDFM_STS_TRANS) & m_fout_axis_ready;
	
	assign rdfm_rplc_req = (~rst_logic_fmbuf) & (rdfm_sts == RDFM_STS_UPD_FLAG);
	assign rdfm_rplc_rid = sfc_rid_to_rd[clogb2(MAX_FMBUF_ROWN-1):0];
	
	assign {s_rd_req_axis_data_auto_rplc, s_rd_req_axis_data_rid, s_rd_req_axis_data_start_sfc_id, s_rd_req_axis_data_sfc_n} = 
		s_rd_req_axis_data[34:0];
	
	// 读特征图状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rdfm_sts <= RDFM_STS_IDLE;
		else if(aclken)
		begin
			if(rst_logic_fmbuf)
				rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
			else
			begin
				case(rdfm_sts)
					RDFM_STS_IDLE:
						if(s_rd_req_axis_valid)
							rdfm_sts <= # SIM_DELAY RDFM_STS_FLAG_JUDGE;
					RDFM_STS_FLAG_JUDGE:
						rdfm_sts <= # SIM_DELAY 
							(
								(s_rd_req_axis_data_rid[clogb2(MAX_FMBUF_ROWN-1):0] <= fmbufrown[clogb2(MAX_FMBUF_ROWN-1):0]) & 
								fmrow_to_rd_is_vld
							) ? 
								RDFM_STS_TRANS:
								RDFM_STS_ROW_INVALID;
					RDFM_STS_ROW_INVALID:
						if(m_fout_axis_ready)
							rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
					RDFM_STS_TRANS:
						if(
							m1_fmbuf_rsp_valid & m1_fmbuf_rsp_ready & 
							((~fmrow_random_rd_mode) | to_suppress_random_rd) & 
							(sfc_rd_resp_n_recv == {1'b0, sfc_n_to_rd})
						)
							rdfm_sts <= # SIM_DELAY 
								auto_rplc_sfc_row_after_rd ? 
									RDFM_STS_UPD_FLAG:
									RDFM_STS_IDLE;
					RDFM_STS_UPD_FLAG:
						rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
					default:
						rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
				endcase
			end
		end
	end
	
	// 待读表面行是否有效
	always @(posedge aclk)
	begin
		if(aclken & (rdfm_sts == RDFM_STS_IDLE) & s_rd_req_axis_valid)
			fmrow_to_rd_is_vld <= # SIM_DELAY sfc_row_vld_flags[s_rd_req_axis_data_rid[clogb2(MAX_FMBUF_ROWN-1):0]];
	end
	
	// 读特征图缓存地址
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(
				((rdfm_sts == RDFM_STS_IDLE) & s_rd_req_axis_valid) | 
				((~fmrow_random_rd_mode) & m1_fmbuf_cmd_valid & m1_fmbuf_cmd_ready)
			)
				rd_fmbuf_addr <= # SIM_DELAY 
					(rdfm_sts == RDFM_STS_IDLE) ? 
						(
							(
								((s_rd_req_axis_data_rid[clogb2(MAX_FMBUF_ROWN-1):0] | 32'h0000_0000) << fmbufcoln_lshn) + 
								(fmrow_random_rd_mode ? 12'd0:s_rd_req_axis_data_start_sfc_id)
							) * ATOMIC_C * 2
						):
						(rd_fmbuf_addr + ATOMIC_C * 2);
		end
	end
	
	// 锁存的自动置换表面行标志, 锁存的待读取表面行编号
	always @(posedge aclk)
	begin
		if(s_rd_req_axis_valid & s_rd_req_axis_ready)
		begin
			auto_rplc_sfc_row_after_rd <= # SIM_DELAY s_rd_req_axis_data_auto_rplc;
			sfc_rid_to_rd <= # SIM_DELAY s_rd_req_axis_data_rid;
		end
	end
	// 锁存的"待读取表面数 - 1"
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if(
				(s_rd_req_axis_valid & s_rd_req_axis_ready) | 
				(fmrow_random_rd_mode & s_random_rd_axis_valid & s_random_rd_axis_ready)
			)
				sfc_n_to_rd <= # SIM_DELAY 
					fmrow_random_rd_mode ? 
						(
							(rdfm_sts == RDFM_STS_TRANS) ? 
								(sfc_n_to_rd + 1'b1):
								12'b1111_1111_1111
						):
						s_rd_req_axis_data_sfc_n;
		end
	end
	
	// 已发送的表面读命令
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(~fmrow_random_rd_mode) & 
			(
				(rst_logic_fmbuf | (rdfm_sts == RDFM_STS_FLAG_JUDGE)) | 
				(m1_fmbuf_cmd_valid & m1_fmbuf_cmd_ready)
			)
		)
			sfc_rd_cmd_n_sent <= # SIM_DELAY 
				{13{~(rst_logic_fmbuf | (rdfm_sts == RDFM_STS_FLAG_JUDGE))}} & 
				(sfc_rd_cmd_n_sent + 13'd1);
	end
	// 已接收的表面读响应
	always @(posedge aclk)
	begin
		if(aclken & (
			(rst_logic_fmbuf | (rdfm_sts == RDFM_STS_FLAG_JUDGE)) | 
			(m1_fmbuf_rsp_valid & m1_fmbuf_rsp_ready)
		))
			sfc_rd_resp_n_recv <= # SIM_DELAY 
				{13{~(rst_logic_fmbuf | (rdfm_sts == RDFM_STS_FLAG_JUDGE))}} & 
				(sfc_rd_resp_n_recv + 13'd1);
	end
	
	// 镇压随机读取(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			fmrow_random_rd_mode & 
			(
				(rst_logic_fmbuf | (rdfm_sts == RDFM_STS_FLAG_JUDGE)) | 
				(s_random_rd_axis_valid & s_random_rd_axis_ready)
			)
		)
			to_suppress_random_rd <= # SIM_DELAY 
				(~(rst_logic_fmbuf | (rdfm_sts == RDFM_STS_FLAG_JUDGE))) & s_random_rd_axis_last;
	end
	
	/** 表面行检索 **/
	reg sfc_row_search_i_req_d1; // 延迟1clk的表面行检索请求
	reg sfc_row_search_i_req_d2; // 延迟2clk的表面行检索请求
	reg[11:0] sfc_row_search_i_rid_d1; // 延迟1clk的待检索的实际表面行号
	reg[11:0] sfc_row_search_i_rid_d2; // 延迟2clk的待检索的实际表面行号
	reg[BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_dout_d1; // 延迟1clk的实际表面行号映射表MEM读数据
	reg sfc_row_search_o_buffered; // 检索的表面行已缓存
	
	assign sfc_row_search_o_vld = sfc_row_search_i_req_d2;
	assign sfc_row_search_o_buf_id = actual_rid_mp_tb_mem_dout_d1 | 10'b00_0000_0000;
	assign sfc_row_search_o_found = sfc_row_search_o_buffered & (buffer_rid_mp_tb_mem_dout_b == sfc_row_search_i_rid_d2);
	
	// 延迟1clk的表面行检索请求, 延迟2clk的表面行检索请求
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{sfc_row_search_i_req_d2, sfc_row_search_i_req_d1} <= 2'b00;
		else if(aclken)
			{sfc_row_search_i_req_d2, sfc_row_search_i_req_d1} <= # SIM_DELAY 
				{sfc_row_search_i_req_d1, sfc_row_search_i_req};
	end
	// 延迟1clk的待检索的实际表面行号, 延迟2clk的待检索的实际表面行号
	always @(posedge aclk)
	begin
		if(aclken)
			{sfc_row_search_i_rid_d2, sfc_row_search_i_rid_d1} <= # SIM_DELAY 
				{sfc_row_search_i_rid_d1, sfc_row_search_i_rid};
	end
	
	// 延迟1clk的实际表面行号映射表MEM读数据
	always @(posedge aclk)
	begin
		if(aclken & sfc_row_search_i_req_d1)
			actual_rid_mp_tb_mem_dout_d1 <= # SIM_DELAY actual_rid_mp_tb_mem_dout_b;
	end
	
	// 检索的表面行已缓存
	always @(posedge aclk)
	begin
		if(aclken & sfc_row_search_i_req_d1)
			sfc_row_search_o_buffered <= # SIM_DELAY sfc_row_vld_flags[actual_rid_mp_tb_mem_dout_b];
	end
	
	/**
	实际表面行号映射表MEM
	
	从(部分的)实际表面行号映射到缓存号
	**/
	assign actual_rid_mp_tb_mem_clk = aclk;
	
	assign actual_rid_mp_tb_mem_wen_a = aclken & s_fin_axis_valid & s_fin_axis_ready & s_fin_axis_last;
	assign actual_rid_mp_tb_mem_addr_a = s_fin_axis_user[21:10];
	assign actual_rid_mp_tb_mem_din_a = s_fin_axis_user[BUFFER_RID_WIDTH-1:0];
	
	assign actual_rid_mp_tb_mem_ren_b = aclken & sfc_row_search_i_req;
	assign actual_rid_mp_tb_mem_addr_b = sfc_row_search_i_rid;
	
	/**
	缓存行号映射表MEM
	
	从缓存号映射到(部分的)实际表面行号
	**/
	assign buffer_rid_mp_tb_mem_clk = aclk;
	
	assign buffer_rid_mp_tb_mem_wen_a = aclken & s_fin_axis_valid & s_fin_axis_ready & s_fin_axis_last;
	assign buffer_rid_mp_tb_mem_addr_a = s_fin_axis_user[BUFFER_RID_WIDTH-1:0];
	assign buffer_rid_mp_tb_mem_din_a = s_fin_axis_user[21:10];
	
	assign buffer_rid_mp_tb_mem_ren_b = aclken & sfc_row_search_i_req_d1;
	assign buffer_rid_mp_tb_mem_addr_b = actual_rid_mp_tb_mem_dout_b;
	
endmodule
