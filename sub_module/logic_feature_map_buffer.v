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
每个表面行区域都能独立地存入/置换
使用1个单端口的表面行有效标志存储器

注意：
暂不支持INT8运算数据格式

在输入特征图表面行数据流中, 应当连续输入1个表面行的表面数据
写特征图表面行时, 会等待直到这个表面行无效, 因此, 若这个表面行始终未被置换, 那么就会一直阻塞住

在发起特征图表面行读请求前, 应当检查这个表面行是否已缓存, 否则会在特征图表面行数据流中给出错误标志
必须保证访问逻辑特征图缓存的行号<=表面行数-1(fmbufrown)

在使用逻辑特征图缓存前, 必须先重置(将rst_logic_fmbuf置高)

外接的表面行有效标志MEM的读时延 = 1clk

协议:
AXIS MASTER/SLAVE
ICB MASTER
MEM MASTER

作者: 陈家耀
日期: 2025/06/23
********************************************************************/


module logic_feature_map_buffer #(
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[2:0] fmbufcoln, // 每个表面行的表面个数类型
	input wire[9:0] fmbufrown, // 表面行数 - 1
	
	// 控制/状态
	input wire rst_logic_fmbuf, // 重置逻辑特征图缓存
	input wire sfc_row_rplc_req, // 表面行置换请求
	input wire[9:0] sfc_rid_to_rplc, // 待置换的表面行编号
	output wire sfc_row_rplc_pending, // 表面行置换等待标志
	output wire init_fns, // 初始化完成(标志)
	
	// 特征图表面行数据输入(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_fin_axis_data,
	input wire[9:0] s_fin_axis_user, // 表面行的缓存编号
	input wire s_fin_axis_last, // 标志当前表面行的最后1个表面
	input wire s_fin_axis_valid,
	output wire s_fin_axis_ready,
	
	// 特征图表面行读请求(AXIS从机)
	/*
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
	// 特征图表面行数据输出(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_fout_axis_data,
	output wire m_fout_axis_user, // 标志表面行未缓存
	output wire m_fout_axis_last, // 标志本次读请求的最后1个表面
	output wire m_fout_axis_valid,
	input wire m_fout_axis_ready,
	
	// 特征图缓存ICB从机#0
	// 命令通道
	output wire[31:0] m0_fmbuf_cmd_addr,
	output wire m0_fmbuf_cmd_read, // const -> 1'b0
	output wire[ATOMIC_C*2*8-1:0] m0_fmbuf_cmd_wdata,
	output wire[ATOMIC_C*2-1:0] m0_fmbuf_cmd_wmask, // const -> {(ATOMIC_C*2){1'b1}}
	output wire m0_fmbuf_cmd_valid,
	input wire m0_fmbuf_cmd_ready,
	// 响应通道
	input wire[ATOMIC_C*2*8-1:0] m0_fmbuf_rsp_rdata, // ignored
	input wire m0_fmbuf_rsp_err, // ignored
	input wire m0_fmbuf_rsp_valid,
	output wire m0_fmbuf_rsp_ready, // const -> 1'b1
	
	// 特征图缓存ICB从机#1
	// 命令通道
	output wire[31:0] m1_fmbuf_cmd_addr,
	output wire m1_fmbuf_cmd_read, // const -> 1'b1
	output wire[ATOMIC_C*2*8-1:0] m1_fmbuf_cmd_wdata, // not care
	output wire[ATOMIC_C*2-1:0] m1_fmbuf_cmd_wmask, // not care
	output wire m1_fmbuf_cmd_valid,
	input wire m1_fmbuf_cmd_ready,
	// 响应通道
	input wire[ATOMIC_C*2*8-1:0] m1_fmbuf_rsp_rdata,
	input wire m1_fmbuf_rsp_err, // ignored
	input wire m1_fmbuf_rsp_valid,
	output wire m1_fmbuf_rsp_ready,
	
	// 表面行有效标志MEM
	output wire sfc_row_vld_flag_mem_clk,
	output wire sfc_row_vld_flag_mem_en,
	output wire sfc_row_vld_flag_mem_wen,
	output wire[9:0] sfc_row_vld_flag_mem_addr,
	output wire sfc_row_vld_flag_mem_din,
	input wire sfc_row_vld_flag_mem_dout
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
	localparam FMBUFCOLN_32 = 3'b000;
	localparam FMBUFCOLN_64 = 3'b001;
	localparam FMBUFCOLN_128 = 3'b010;
	localparam FMBUFCOLN_256 = 3'b011;
	localparam FMBUFCOLN_512 = 3'b100;
	localparam FMBUFCOLN_1024 = 3'b101;
	localparam FMBUFCOLN_2048 = 3'b110;
	localparam FMBUFCOLN_4096 = 3'b111;
	// 写特征图状态常量
	localparam WTFM_STS_IDLE = 2'b00;
	localparam WTFM_STS_WAIT_RPLC = 2'b01;
	localparam WTFM_STS_TRANS = 2'b10;
	localparam WTFM_STS_UPD_FLAG = 2'b11;
	// 读特征图状态常量
	localparam RDFM_STS_IDLE = 3'b000;
	localparam RDFM_STS_FLAG_JUDGE = 3'b001;
	localparam RDFM_STS_ROW_INVALID = 3'b010;
	localparam RDFM_STS_TRANS = 3'b011;
	localparam RDFM_STS_UPD_FLAG = 3'b100;
	
	/** 表面行有效标志 **/
	// [初始化有效标志]
	wire init_vld_flag_en;
	wire init_vld_flag_wen;
	reg[clogb2(MAX_FMBUF_ROWN-1):0] init_vld_flag_addr;
	wire init_vld_flag_din;
	reg init_vld_flag_fns;
	// [写特征图访问有效标志]
	wire wtfm_access_en;
	wire wtfm_access_wen;
	wire[clogb2(MAX_FMBUF_ROWN-1):0] wtfm_access_addr;
	wire wtfm_access_din;
	wire wtfm_access_dout;
	// [读特征图访问有效标志]
	wire rdfm_access_en;
	wire rdfm_access_wen;
	wire[clogb2(MAX_FMBUF_ROWN-1):0] rdfm_access_addr;
	wire rdfm_access_din;
	wire rdfm_access_dout;
	// [表面行置换访问有效标志]
	wire sfc_row_rplc_access_en;
	wire sfc_row_rplc_access_wen;
	reg[clogb2(MAX_FMBUF_ROWN-1):0] sfc_row_rplc_access_addr;
	wire sfc_row_rplc_access_din;
	// [表面行有效标志读写仲裁]
	wire init_vld_flag_req; // 初始化有效标志(请求)
	wire wtfm_access_req; // 写特征图访问(请求)
	wire rdfm_access_req; // 读特征图访问(请求)
	wire sfc_row_rplc_access_req; // 表面行置换访问(请求)
	wire init_vld_flag_granted; // 初始化有效标志(许可)
	wire wtfm_access_granted; // 写特征图访问(许可)
	wire rdfm_access_granted; // 读特征图访问(许可)
	wire sfc_row_rplc_access_granted; // 表面行置换访问(许可)
	
	assign sfc_row_vld_flag_mem_clk = aclk;
	assign sfc_row_vld_flag_mem_en = 
		aclken & (init_vld_flag_en | wtfm_access_en | rdfm_access_en | sfc_row_rplc_access_en);
	assign sfc_row_vld_flag_mem_wen = 
		(init_vld_flag_granted & init_vld_flag_wen) | 
		(wtfm_access_granted & wtfm_access_wen) | 
		(rdfm_access_granted & rdfm_access_wen) | 
		(sfc_row_rplc_access_granted & sfc_row_rplc_access_wen);
	assign sfc_row_vld_flag_mem_addr = 
		({10{init_vld_flag_granted}} & (init_vld_flag_addr | 10'd0)) | 
		({10{wtfm_access_granted}} & (wtfm_access_addr | 10'd0)) | 
		({10{rdfm_access_granted}} & (rdfm_access_addr | 10'd0)) | 
		({10{sfc_row_rplc_access_granted}} & (sfc_row_rplc_access_addr | 10'd0));
	assign sfc_row_vld_flag_mem_din = 
		(init_vld_flag_granted & init_vld_flag_din) | 
		(wtfm_access_granted & wtfm_access_din) | 
		(rdfm_access_granted & rdfm_access_din) | 
		(sfc_row_rplc_access_granted & sfc_row_rplc_access_din);
	
	assign wtfm_access_dout = sfc_row_vld_flag_mem_dout;
	assign rdfm_access_dout = sfc_row_vld_flag_mem_dout;
	
	/*
	优先级从高到低: 
		初始化有效标志
		写特征图访问
		读特征图访问
		表面行置换请求
	*/
	assign init_vld_flag_granted = 
		init_vld_flag_req;
	assign wtfm_access_granted = 
		(~init_vld_flag_req) & wtfm_access_req;
	assign rdfm_access_granted = 
		(~init_vld_flag_req) & (~wtfm_access_req) & rdfm_access_req;
	assign sfc_row_rplc_access_granted = 
		(~init_vld_flag_req) & (~wtfm_access_req) & (~rdfm_access_req) & sfc_row_rplc_access_req;
	
	/** 初始化有效标志 **/
	assign init_fns = init_vld_flag_fns;
	
	assign init_vld_flag_en = init_vld_flag_req;
	assign init_vld_flag_wen = 1'b1;
	assign init_vld_flag_din = 1'b0;
	
	assign init_vld_flag_req = (~rst_logic_fmbuf) & (~init_vld_flag_fns);
	
	// 初始化有效标志写地址
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			init_vld_flag_addr <= 0;
		else if(aclken & (rst_logic_fmbuf | init_vld_flag_granted))
			init_vld_flag_addr <= # SIM_DELAY {(clogb2(MAX_FMBUF_ROWN-1)+1){~rst_logic_fmbuf}} & (init_vld_flag_addr + 1);
	end
	// 初始化有效标志完成
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			init_vld_flag_fns <= 1'b0;
		else if(aclken & (rst_logic_fmbuf | ((~init_vld_flag_fns) & init_vld_flag_granted)))
			init_vld_flag_fns <= # SIM_DELAY (~rst_logic_fmbuf) & (init_vld_flag_addr == (MAX_FMBUF_ROWN-1));
	end
	
	/** 表面行置换 **/
	reg sfc_row_rplc_access_pending; // 表面行置换访问有效标志(等待标志)
	wire on_sfc_row_rplc; // 表面行被置换(指示)
	wire[clogb2(MAX_FMBUF_ROWN-1):0] on_sfc_rplc_rid; // 当前被置换表面行的编号
	
	assign sfc_row_rplc_pending = sfc_row_rplc_access_pending;
	
	assign sfc_row_rplc_access_en = sfc_row_rplc_access_req;
	assign sfc_row_rplc_access_wen = 1'b1;
	assign sfc_row_rplc_access_din = 1'b0;
	
	assign sfc_row_rplc_access_req = (~rst_logic_fmbuf) & sfc_row_rplc_access_pending;
	
	assign on_sfc_row_rplc = sfc_row_rplc_access_granted | (rdfm_access_granted & rdfm_access_wen);
	assign on_sfc_rplc_rid = 
		sfc_row_rplc_access_granted ? sfc_row_rplc_access_addr:rdfm_access_addr;
	
	// 表面行置换访问有效标志MEM写地址
	always @(posedge aclk)
	begin
		if(aclken & sfc_row_rplc_req)
			sfc_row_rplc_access_addr <= # SIM_DELAY sfc_rid_to_rplc[clogb2(MAX_FMBUF_ROWN-1):0];
	end
	
	// 表面行置换访问有效标志(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			sfc_row_rplc_access_pending <= 1'b0;
		else if(aclken & (
			rst_logic_fmbuf | (
				sfc_row_rplc_access_pending ? 
					sfc_row_rplc_access_granted:
					sfc_row_rplc_req
			)
		))
			sfc_row_rplc_access_pending <= # SIM_DELAY (~rst_logic_fmbuf) & (~sfc_row_rplc_access_pending);
	end
	
	/** 写特征图 **/
	reg[1:0] wtfm_sts; // 写特征图状态
	reg wtfm_query_vld_flag_available_n; // 写特征图时查询的表面行有效标志不可用(标志)
	reg[31:0] wt_fmbuf_addr; // 写特征图缓存地址
	reg wt_fmbuf_bus_cmd_fns; // 写特征图缓存总线命令事务完成(标志)
	reg[12:0] wt_fmbuf_trans_sfc; // 写特征图缓存正在传输的表面数
	reg[clogb2(MAX_FMBUF_ROWN-1):0] wtfm_rid; // 写特征图表面行号
	
	// 握手条件: aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & s_fin_axis_valid & m0_fmbuf_cmd_ready
	assign s_fin_axis_ready = aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & m0_fmbuf_cmd_ready;
	
	assign m0_fmbuf_cmd_addr = wt_fmbuf_addr;
	assign m0_fmbuf_cmd_read = 1'b0;
	assign m0_fmbuf_cmd_wdata = s_fin_axis_data;
	assign m0_fmbuf_cmd_wmask = {(ATOMIC_C*2){1'b1}};
	// 握手条件: aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & s_fin_axis_valid & m0_fmbuf_cmd_ready
	assign m0_fmbuf_cmd_valid = aclken & (~wt_fmbuf_bus_cmd_fns) & (wtfm_sts == WTFM_STS_TRANS) & s_fin_axis_valid;
	
	assign m0_fmbuf_rsp_ready = aclken;
	
	assign wtfm_access_en = wtfm_access_req;
	assign wtfm_access_wen = wtfm_sts == WTFM_STS_UPD_FLAG;
	assign wtfm_access_addr = 
		(wtfm_sts == WTFM_STS_UPD_FLAG) ? 
			wtfm_rid:
			s_fin_axis_user[clogb2(MAX_FMBUF_ROWN-1):0];
	assign wtfm_access_din = 1'b1;
	
	assign wtfm_access_req = 
		(~rst_logic_fmbuf) & (
			((wtfm_sts == WTFM_STS_IDLE) & s_fin_axis_valid) | // 读有效标志
			(wtfm_sts == WTFM_STS_UPD_FLAG) // 更新有效标志
		);
	
	// 写特征图状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wtfm_sts <= WTFM_STS_IDLE;
		if(aclken)
		begin
			if(rst_logic_fmbuf)
				wtfm_sts <= # SIM_DELAY WTFM_STS_IDLE;
			else
			begin
				case(wtfm_sts)
					WTFM_STS_IDLE:
						if(s_fin_axis_valid & wtfm_access_granted)
							wtfm_sts <= # SIM_DELAY WTFM_STS_WAIT_RPLC;
					WTFM_STS_WAIT_RPLC:
						if(
							(s_fin_axis_user <= fmbufrown) & (
								((~wtfm_query_vld_flag_available_n) & (~wtfm_access_dout)) | 
								(on_sfc_row_rplc & (on_sfc_rplc_rid == s_fin_axis_user[clogb2(MAX_FMBUF_ROWN-1):0]))
							)
						)
							wtfm_sts <= # SIM_DELAY WTFM_STS_TRANS;
					WTFM_STS_TRANS:
						if(wt_fmbuf_bus_cmd_fns & (wt_fmbuf_trans_sfc == 13'd0))
							wtfm_sts <= # SIM_DELAY WTFM_STS_UPD_FLAG;
					WTFM_STS_UPD_FLAG:
						if(wtfm_access_granted)
							wtfm_sts <= # SIM_DELAY WTFM_STS_IDLE;
					default:
						wtfm_sts <= # SIM_DELAY WTFM_STS_IDLE;
				endcase
			end
		end
	end
	
	// 写特征图时查询的表面行有效标志不可用(标志)
	always @(posedge aclk)
	begin
		if(aclken & (rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE) | (~wtfm_query_vld_flag_available_n)))
			wtfm_query_vld_flag_available_n <= # SIM_DELAY 
				(~(rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE))) & (wtfm_sts == WTFM_STS_WAIT_RPLC);
	end
	
	// 写特征图缓存地址
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if((wtfm_sts == WTFM_STS_IDLE) & (s_fin_axis_valid & wtfm_access_granted))
				wt_fmbuf_addr <= # SIM_DELAY 
					((s_fin_axis_user[clogb2(MAX_FMBUF_ROWN-1):0] | 32'h0000_0000) << (
						(fmbufcoln == FMBUFCOLN_32)   ? 5:
						(fmbufcoln == FMBUFCOLN_64)   ? 6:
						(fmbufcoln == FMBUFCOLN_128)  ? 7:
						(fmbufcoln == FMBUFCOLN_256)  ? 8:
						(fmbufcoln == FMBUFCOLN_512)  ? 9:
						(fmbufcoln == FMBUFCOLN_1024) ? 10:
						(fmbufcoln == FMBUFCOLN_2048) ? 11:
														12
					)) * ATOMIC_C * 2;
			else if(m0_fmbuf_cmd_valid & m0_fmbuf_cmd_ready)
				wt_fmbuf_addr <= # SIM_DELAY wt_fmbuf_addr + ATOMIC_C * 2;
		end
	end
	
	// 写特征图缓存总线命令事务完成(标志)
	always @(posedge aclk)
	begin
		if(aclken & (rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE) | (~wt_fmbuf_bus_cmd_fns)))
			wt_fmbuf_bus_cmd_fns <= # SIM_DELAY 
				(~(rst_logic_fmbuf | (wtfm_sts == WTFM_STS_IDLE))) & (s_fin_axis_valid & s_fin_axis_ready & s_fin_axis_last);
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
	
	/** 读特征图 **/
	wire s_rd_req_axis_data_auto_rplc; // 是否需要自动置换表面行
	wire[9:0] s_rd_req_axis_data_rid; // 表面行的缓存编号
	wire[11:0] s_rd_req_axis_data_start_sfc_id; // 起始表面编号
	wire[11:0] s_rd_req_axis_data_sfc_n; // 待读取的表面个数 - 1
	reg[2:0] rdfm_sts; // 读特征图状态
	reg[31:0] rd_fmbuf_addr; // 读特征图缓存地址
	reg auto_rplc_sfc_row_after_rd; // 锁存的自动置换表面行标志
	reg[9:0] sfc_rid_to_rd; // 锁存的待读取表面行编号
	reg[11:0] sfc_n_to_rd; // 锁存的(待读取表面数 - 1)
	reg[12:0] sfc_rd_cmd_n_sent; // 已发送的表面读命令
	reg[12:0] sfc_rd_resp_n_recv; // 已接收的表面读响应
	
	// 握手条件: aclken & (rdfm_sts == RDFM_STS_FLAG_JUDGE) & s_rd_req_axis_valid
	assign s_rd_req_axis_ready = aclken & (rdfm_sts == RDFM_STS_FLAG_JUDGE);
	
	assign m_fout_axis_data = m1_fmbuf_rsp_rdata;
	assign m_fout_axis_user = rdfm_sts == RDFM_STS_ROW_INVALID;
	assign m_fout_axis_last = (rdfm_sts == RDFM_STS_ROW_INVALID) | (sfc_rd_resp_n_recv == {1'b0, sfc_n_to_rd});
	/*
	握手条件:
		aclken & (
			(rdfm_sts == RDFM_STS_ROW_INVALID) | 
			((rdfm_sts == RDFM_STS_TRANS) & (sfc_rd_resp_n_recv <= {1'b0, sfc_n_to_rd}) & m1_fmbuf_rsp_valid)
		) & m_fout_axis_ready
	*/
	assign m_fout_axis_valid = 
		aclken & (
			(rdfm_sts == RDFM_STS_ROW_INVALID) | 
			((rdfm_sts == RDFM_STS_TRANS) & (sfc_rd_resp_n_recv <= {1'b0, sfc_n_to_rd}) & m1_fmbuf_rsp_valid)
		);
	
	assign m1_fmbuf_cmd_addr = rd_fmbuf_addr;
	assign m1_fmbuf_cmd_read = 1'b1;
	assign m1_fmbuf_cmd_wdata = {(ATOMIC_C*2*8){1'bx}};
	assign m1_fmbuf_cmd_wmask = {(ATOMIC_C*2){1'bx}};
	// 握手条件: aclken & (rdfm_sts == RDFM_STS_TRANS) & (sfc_rd_cmd_n_sent <= {1'b0, sfc_n_to_rd}) & m1_fmbuf_cmd_ready
	assign m1_fmbuf_cmd_valid = aclken & (rdfm_sts == RDFM_STS_TRANS) & (sfc_rd_cmd_n_sent <= {1'b0, sfc_n_to_rd});
	
	/* 握手条件: 
		aclken & (rdfm_sts == RDFM_STS_TRANS) & (sfc_rd_resp_n_recv <= {1'b0, sfc_n_to_rd}) & m1_fmbuf_rsp_valid & 
		m_fout_axis_ready
	*/
	assign m1_fmbuf_rsp_ready = 
		aclken & (rdfm_sts == RDFM_STS_TRANS) & (sfc_rd_resp_n_recv <= {1'b0, sfc_n_to_rd}) & m_fout_axis_ready;
	
	assign rdfm_access_en = rdfm_access_req;
	assign rdfm_access_wen = rdfm_sts == RDFM_STS_UPD_FLAG;
	assign rdfm_access_addr = 
		(rdfm_sts == RDFM_STS_UPD_FLAG) ? 
			sfc_rid_to_rd[clogb2(MAX_FMBUF_ROWN-1):0]:
			s_rd_req_axis_data_rid[clogb2(MAX_FMBUF_ROWN-1):0];
	assign rdfm_access_din = 1'b0;
	
	assign rdfm_access_req = 
		(~rst_logic_fmbuf) & (
			((rdfm_sts == RDFM_STS_IDLE) & s_rd_req_axis_valid) | // 读有效标志
			(rdfm_sts == RDFM_STS_UPD_FLAG) // 自动清零有效标志
		);
	
	assign {s_rd_req_axis_data_auto_rplc, s_rd_req_axis_data_rid, s_rd_req_axis_data_start_sfc_id, s_rd_req_axis_data_sfc_n} = 
		s_rd_req_axis_data[34:0];
	
	// 读特征图状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rdfm_sts <= RDFM_STS_IDLE;
		if(aclken)
		begin
			if(rst_logic_fmbuf)
				rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
			else
			begin
				case(rdfm_sts)
					RDFM_STS_IDLE:
						if(s_rd_req_axis_valid & rdfm_access_granted)
							rdfm_sts <= # SIM_DELAY RDFM_STS_FLAG_JUDGE;
					RDFM_STS_FLAG_JUDGE:
						rdfm_sts <= # SIM_DELAY 
							((s_rd_req_axis_data_rid <= fmbufrown) & rdfm_access_dout) ? 
								RDFM_STS_TRANS:RDFM_STS_ROW_INVALID;
					RDFM_STS_ROW_INVALID:
						if(m_fout_axis_ready)
							rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
					RDFM_STS_TRANS:
						if(m1_fmbuf_rsp_valid & m1_fmbuf_rsp_ready & (sfc_rd_resp_n_recv == {1'b0, sfc_n_to_rd}))
							rdfm_sts <= # SIM_DELAY auto_rplc_sfc_row_after_rd ? RDFM_STS_UPD_FLAG:RDFM_STS_IDLE;
					RDFM_STS_UPD_FLAG:
						if(rdfm_access_granted)
							rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
					default:
						rdfm_sts <= # SIM_DELAY RDFM_STS_IDLE;
				endcase
			end
		end
	end
	
	// 读特征图缓存地址
	always @(posedge aclk)
	begin
		if(aclken)
		begin
			if((rdfm_sts == RDFM_STS_IDLE) & (s_rd_req_axis_valid & rdfm_access_granted))
				rd_fmbuf_addr <= # SIM_DELAY 
					(((s_rd_req_axis_data_rid[clogb2(MAX_FMBUF_ROWN-1):0] | 32'h0000_0000) << (
						(fmbufcoln == FMBUFCOLN_32)   ? 5:
						(fmbufcoln == FMBUFCOLN_64)   ? 6:
						(fmbufcoln == FMBUFCOLN_128)  ? 7:
						(fmbufcoln == FMBUFCOLN_256)  ? 8:
						(fmbufcoln == FMBUFCOLN_512)  ? 9:
						(fmbufcoln == FMBUFCOLN_1024) ? 10:
						(fmbufcoln == FMBUFCOLN_2048) ? 11:
														12
					)) + s_rd_req_axis_data_start_sfc_id) * ATOMIC_C * 2;
			else if(m1_fmbuf_cmd_valid & m1_fmbuf_cmd_ready)
				rd_fmbuf_addr <= # SIM_DELAY rd_fmbuf_addr + ATOMIC_C * 2;
		end
	end
	
	// 锁存的自动置换表面行标志, 锁存的待读取表面行编号, 锁存的(待读取表面数 - 1)
	always @(posedge aclk)
	begin
		if(s_rd_req_axis_valid & s_rd_req_axis_ready)
		begin
			auto_rplc_sfc_row_after_rd <= # SIM_DELAY s_rd_req_axis_data_auto_rplc;
			sfc_rid_to_rd <= # SIM_DELAY s_rd_req_axis_data_rid;
			sfc_n_to_rd <= # SIM_DELAY s_rd_req_axis_data_sfc_n;
		end
	end
	
	// 已发送的表面读命令
	always @(posedge aclk)
	begin
		if(aclken & (
			(rst_logic_fmbuf | (rdfm_sts == RDFM_STS_FLAG_JUDGE)) | 
			(m1_fmbuf_cmd_valid & m1_fmbuf_cmd_ready)
		))
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
	
endmodule
