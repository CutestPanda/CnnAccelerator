`timescale 1ns / 1ps

/** 接口:块级控制 **/
interface BlkCtrl #(
	real out_drive_t = 1 // 输出驱动延迟量
)(
	input clk,
	input rst_n
);

	logic start;
	logic ready;
	logic idle;
	logic done;
	logic to_continue;
	
	clocking cb_master @(posedge clk);
		output # out_drive_t start, to_continue;
	endclocking
	
	clocking cb_slave @(posedge clk);
		output # out_drive_t ready, idle, done;
	endclocking
	
	modport master(
		input clk, rst_n,
        input ready, idle, done,
        clocking cb_master);
	
	modport slave(
		input clk, rst_n,
        input start, to_continue,
        clocking cb_slave);
	
	modport monitor(
		input clk, rst_n,
        input start, ready, idle, done, to_continue);
	
endinterface

/** 接口:AXI **/
interface AXI #(
    real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽(1~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)(
    input clk,
	input rst_n
);
	
    // 读地址通道(AR)
    logic[addr_width-1:0] araddr;
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    logic[1:0] arburst;
    logic[3:0] arcache;
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    logic[7:0] arlen;
    logic arlock;
    logic[2:0] arprot;
    logic[2:0] arsize;
    logic arvalid;
    logic arready;
    
    // 写地址通道(AW)
    logic[addr_width-1:0] awaddr;
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    logic[1:0] awburst;
    logic[3:0] awcache;
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    logic[7:0] awlen;
    logic awlock;
    logic[2:0] awprot;
    logic[2:0] awsize;
    logic awvalid;
    logic awready;
    
    // 写响应通道(B)
    logic[bresp_width-1:0] bresp;
    logic bvalid;
    logic bready;
    
    // 读数据通道(R)
    logic[data_width-1:0] rdata;
    logic rlast;
    logic[rresp_width-1:0] rresp;
    logic rvalid;
    logic rready;
    
    // 写数据通道(W)
    logic[data_width-1:0] wdata;
    logic wlast;
    logic[data_width/8-1:0] wstrb;
    logic wvalid;
    logic wready;
    
    clocking cb_master @(posedge clk);
        output #out_drive_t araddr, arburst, arcache, arlen, arlock, arprot, arsize, arvalid;
        output #out_drive_t awaddr, awburst, awcache, awlen, awlock, awprot, awsize, awvalid;
        output #out_drive_t bready;
        output #out_drive_t rready;
        output #out_drive_t wdata, wlast, wstrb, wvalid;
    endclocking
    
    clocking cb_slave @(posedge clk);
        output #out_drive_t arready;
        output #out_drive_t awready;
        output #out_drive_t bresp, bvalid;
        output #out_drive_t rdata, rlast, rresp, rvalid;
        output #out_drive_t wready;
    endclocking
    
    modport master(
		input clk, rst_n,
        input arvalid, arready,
        input awvalid, awready,
        input bresp, bvalid, bready,
        input rdata, rlast, rresp, rvalid, rready,
        input wvalid, wready,
        clocking cb_master);
    
    modport slave(
		input clk, rst_n,
        input araddr, arburst, arcache, arlen, arlock, arprot, arsize, arvalid, arready,
        input awaddr, awburst, awcache, awlen, awlock, awprot, awsize, awvalid, awready,
        input bvalid, bready,
        input rvalid, rready,
        input wdata, wlast, wstrb, wvalid, wready,
        clocking cb_slave);
    
    modport monitor(
		input clk, rst_n,
        input araddr, arburst, arcache, arlen, arlock, arprot, arsize, arvalid, arready,
        input awaddr, awburst, awcache, awlen, awlock, awprot, awsize, awvalid, awready,
        input bresp, bvalid, bready,
        input rdata, rlast, rresp, rvalid, rready,
        input wdata, wlast, wstrb, wvalid, wready
    );
    
endinterface

/** 接口:APB **/
interface APB #(
    real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)(
    input clk,
	input rst_n
);
    
    logic[addr_width-1:0] paddr;
    logic[2:0] pprot;
    logic pnse;
    logic pselx;
    logic penable;
    logic pwrite;
    logic[data_width-1:0] pwdata;
    logic[data_width/8-1:0] pstrb;
    logic pready;
    logic[data_width-1:0] prdata;
    logic pslverr;
    logic pwakeup;
    
	// 时钟块
    clocking cb_master @(posedge clk);
        output #out_drive_t paddr, pprot, pnse;
        output #out_drive_t pselx, penable, pwrite;
        output #out_drive_t pwdata, pstrb;
        output #out_drive_t pwakeup;
    endclocking
    
    clocking cb_slave @(posedge clk);
        output #out_drive_t pready, prdata, pslverr;
    endclocking
    
	// 端口
    modport master(
		input clk, rst_n,
        input pready, prdata, pslverr,
        clocking cb_master);
    
    modport slave(
		input clk, rst_n,
        input paddr, pprot, pnse,
        input pselx, penable, pwrite,
        input pwdata, pstrb,
        input pready,
        input pwakeup,
        clocking cb_slave);
    
    modport monitor(
		input clk, rst_n,
        input paddr, pprot, pnse,
        input pselx, penable, pwrite,
        input pwdata, pstrb,
        input pready, prdata, pslverr,
        input pwakeup);
    
endinterface

/** 接口:AXIS **/
interface AXIS #(
    real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)(
    input clk,
	input rst_n
);
	
    logic[data_width-1:0] data;
    logic[data_width/8-1:0] keep;
	logic[data_width/8-1:0] strb;
    logic last;
    logic[user_width-1:0] user;
    logic valid;
    logic ready;
    
    clocking cb_master @(posedge clk);
        output #out_drive_t data, keep, strb, last, user, valid;
    endclocking
    
    clocking cb_slave @(posedge clk);
        output #out_drive_t ready;
    endclocking
    
    modport master(
		input clk, rst_n,
        input valid, ready,
        clocking cb_master
    );
    
    modport slave(
		input clk, rst_n,
        input data, keep, strb, last, user,
        input valid, ready,
        clocking cb_slave
    );
    
    modport monitor(
		input clk, rst_n,
        input data, keep, strb, last, user,
        input valid, ready
    );
    
endinterface

/** 接口:AHB **/
interface AHB #(
    real out_drive_t = 1, // 输出驱动延迟量
    integer slave_n = 1, // 从机个数
    integer addr_width = 32, // 地址位宽(10~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer burst_width = 3, // 突发类型位宽(0~3)
    integer prot_width = 4, // 保护类型位宽(0 | 4 | 7)
    integer master_width = 1 // 主机标识位宽(0~8)
)(
    input clk,
	input rst_n
);
	
	function integer clogb2(input integer bit_depth);
        integer temp;
    begin
		if(bit_depth > 0)
		begin
			temp = bit_depth;
			
			for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
				temp = temp >> 1;
		end
		else
			clogb2 = 0;
    end
    endfunction
	
	// 地址和控制信号
    logic[addr_width-1:0] haddr;
    logic[burst_width-1:0] hburst;
    logic hmastllock;
    logic[prot_width-1:0] hprot;
    logic[2:0] hsize;
    logic hnonsec;
    logic hexcl;
    logic[master_width-1:0] hmaster;
    logic[1:0] htrans;
    logic hwrite;
    // 数据信号
    logic[data_width-1:0] hwdata;
    logic[data_width/8-1:0] hwstrb;
    logic[data_width-1:0] hrdata_out[slave_n-1:0];
    logic hready_out[slave_n-1:0];
    logic hresp_out[slave_n-1:0];
    logic hexokay_out[slave_n-1:0];
    // MUX输出
    logic[data_width-1:0] hrdata;
    logic hready;
    logic hresp;
    logic hexokay;
    // 地址译码器输出
    logic[slave_n-1:0] hsel;
    logic[clogb2(slave_n-1):0] muxsel;
	
	// MUX
	// 选择的是上一次传输的从机
    assign hrdata = hrdata_out[muxsel];
    assign hready = hready_out[muxsel];
    assign hresp = hresp_out[muxsel];
    assign hexokay = hexokay_out[muxsel];
	
	clocking cb_master @(posedge clk);
        output #out_drive_t haddr, hburst, hmastllock, hprot, hsize,
            hnonsec, hexcl, hmaster, htrans, hwrite;
        output #out_drive_t hwdata, hwstrb;
    endclocking
    
    clocking cb_slave @(posedge clk);
        output #out_drive_t hrdata_out, hready_out, hresp_out, hexokay_out;
    endclocking
    
    clocking cb_dec @(posedge clk);
        output #out_drive_t hsel, muxsel;
    endclocking
	
	modport master(
        input clk, rst_n,
        input htrans,
        input hrdata, hready, hresp, hexokay,
        clocking cb_master);
   
    modport slave(
        input clk, rst_n,
        input haddr, hburst, hmastllock, hprot, hsize,
            hnonsec, hexcl, hmaster, htrans, hwrite,
        input hwdata, hwstrb,
        input hready, hready_out,
		input hsel,
        clocking cb_slave);
    
    modport dec(
        input clk, rst_n,
        input haddr,
        input hready,
        clocking cb_dec);
    
    modport monitor(
        input clk, rst_n,
        input haddr, hburst, hmastllock, hprot, hsize,
            hnonsec, hexcl, hmaster, htrans, hwrite,
        input hwdata, hwstrb,
        input hrdata, hready, hresp, hexokay,
		input hsel);
	
endinterface

/** 接口:双端口SRAM **/
interface DPSram #(
    real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽
)(
    input clk,
	input rst_n
);

	logic ena;
	logic wea;
	logic[addr_width-1:0] addra;
	logic[data_width-1:0] dina;
	logic[data_width-1:0] douta;
	
	logic enb;
	logic web;
	logic[addr_width-1:0] addrb;
	logic[data_width-1:0] dinb;
	logic[data_width-1:0] doutb;
	
	clocking cb_master @(posedge clk);
        output #out_drive_t ena, wea, addra, dina;
		output #out_drive_t enb, web, addrb, dinb;
    endclocking
    
    clocking cb_slave @(posedge clk);
        output #out_drive_t douta;
		output #out_drive_t doutb;
    endclocking
	
	modport master(
		input clk, rst_n, 
        input douta, doutb, 
        clocking cb_master
    );
	
	modport slave(
		input clk, rst_n, 
		input ena, wea, addra, dina, 
		input enb, web, addrb, dinb, 
        clocking cb_slave
    );
	
	modport monitor(
		input clk, rst_n,
		input ena, wea, addra, dina, douta, 
		input enb, web, addrb, dinb, doutb
    );
	
endinterface

/** 接口:fifo **/
interface FIFO #(
    real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32 // 数据位宽
)(
    input clk,
	input rst_n
);

	logic wen;
	logic full;
	logic full_n;
	logic almost_full;
	logic almost_full_n;
	logic[data_width-1:0] din;
	
	logic ren;
	logic empty;
	logic empty_n;
	logic almost_empty;
	logic almost_empty_n;
	logic[data_width-1:0] dout;
	
	clocking cb_master @(posedge clk);
        output #out_drive_t wen, din;
		output #out_drive_t ren;
    endclocking
	
	clocking cb_slave @(posedge clk);
        output #out_drive_t full, full_n, almost_full, almost_full_n;
		output #out_drive_t empty, empty_n, almost_empty, almost_empty_n, dout;
    endclocking
	
	modport master(
		input clk, rst_n, 
        input full, full_n, almost_full, almost_full_n, 
		input empty, empty_n, almost_empty, almost_empty_n, dout, 
        clocking cb_master
    );
	
	modport slave(
		input clk, rst_n, 
		input wen, din, 
		input ren, 
        clocking cb_slave
    );
	
	modport monitor(
		input clk, rst_n,
		input wen, din, full, full_n, almost_full, almost_full_n, 
		input ren, empty, empty_n, almost_empty, almost_empty_n, dout
    );

endinterface

/** 接口:req-ack **/
interface ReqAck #(
    real out_drive_t = 1, // 输出驱动延迟量
    integer req_payload_width = 32, // 请求数据位宽
	integer resp_payload_width = 32 // 响应数据位宽
)(
    input clk,
	input rst_n
);
	
	logic req;
	logic[req_payload_width-1:0] req_payload;
	
	logic ack;
	logic[resp_payload_width-1:0] resp_payload;
	
	clocking cb_master @(posedge clk);
        output #out_drive_t req, req_payload;
    endclocking
	
	clocking cb_slave @(posedge clk);
        output #out_drive_t ack, resp_payload;
    endclocking
	
	modport master(
		input clk, rst_n, 
        input ack, resp_payload, 
        clocking cb_master
    );
	
	modport slave(
		input clk, rst_n, 
		input req, req_payload, 
        clocking cb_slave
    );
	
	modport monitor(
		input clk, rst_n, 
		input req, req_payload, 
        input ack, resp_payload
    );
	
endinterface

/** 接口:ICB **/
interface ICB #(
    real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)(
    input clk,
	input rst_n
);
	
	logic[addr_width-1:0] cmd_addr;
	logic cmd_read;
	logic[data_width-1:0] cmd_wdata;
	logic[data_width/8-1:0] cmd_wmask;
	logic cmd_valid;
	logic cmd_ready;
	
	logic[data_width-1:0] rsp_rdata;
	logic rsp_err;
	logic rsp_valid;
	logic rsp_ready;
	
	clocking cb_master @(posedge clk);
        output #out_drive_t cmd_addr, cmd_read, cmd_wdata, cmd_wmask, cmd_valid;
		output #out_drive_t rsp_ready;
    endclocking
	
	clocking cb_slave @(posedge clk);
        output #out_drive_t cmd_ready;
		output #out_drive_t rsp_rdata, rsp_err, rsp_valid;
    endclocking
	
	modport master(
		input clk, rst_n, 
        input cmd_valid, cmd_ready, 
		input rsp_rdata, rsp_err, rsp_valid, rsp_ready,
        clocking cb_master
    );
	
	modport slave(
		input clk, rst_n, 
		input cmd_addr, cmd_read, cmd_wdata, cmd_wmask, cmd_valid, cmd_ready, 
		input rsp_valid, rsp_ready, 
        clocking cb_slave
    );
	
	modport monitor(
		input clk, rst_n, 
		input cmd_addr, cmd_read, cmd_wdata, cmd_wmask, cmd_valid, cmd_ready, 
		input rsp_rdata, rsp_err, rsp_valid, rsp_ready
    );
	
endinterface

/** 接口:特征图/卷积核表面生成单元覆盖率采集 **/
interface ConvDataSfcGenCvgSmpIf #(
	integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	integer EXTRA_DATA_WIDTH = 4 // 随路传输附加数据的位宽(必须>=1)
)(
    input clk,
	input rst_n
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
	// 半字缓存区的大小
	localparam HW_BUF_LEN = 
		(STREAM_DATA_WIDTH > (ATOMIC_C*2*8)) ? 
			(STREAM_DATA_WIDTH/16*2):
			(ATOMIC_C*2);
	
	logic strm_pkt_msg_fifo_wen;
	logic[11+EXTRA_DATA_WIDTH-1:0] strm_pkt_msg_fifo_din; // {每个表面的有效数据个数(6bit), 随路传输附加数据(EXTRA_DATA_WIDTH bit), 
	                                                      //     每个表面的有效数据个数 - 1(5bit)}
	logic strm_pkt_msg_fifo_full_n;
	logic strm_pkt_msg_fifo_ren;
	logic[11+EXTRA_DATA_WIDTH-1:0] strm_pkt_msg_fifo_dout; // {每个表面的有效数据个数(6bit), 随路传输附加数据(EXTRA_DATA_WIDTH bit), 
	                                                       //     每个表面的有效数据个数 - 1(5bit)}
	logic strm_pkt_msg_fifo_empty_n;
	
	logic s_stream_axis_hs;
	logic m_sfc_axis_hs;
	
	logic[clogb2(HW_BUF_LEN):0] hw_stored_cnt; // 已存储的半字(计数器)
	logic[clogb2(HW_BUF_LEN-1):0] hw_buf_wptr; // 半字缓存区写指针
	logic[clogb2(HW_BUF_LEN-1):0] hw_buf_rptr; // 半字缓存区读指针
	
	logic[clogb2(STREAM_DATA_WIDTH/16-1):0] vld_hw_n_sub1_of_cur_strm_trans; // 当前传输的有效半字数 - 1
	
	covergroup strm_pkt_msg_fifo_wr_cvg;
		coverpoint strm_pkt_msg_fifo_din[4:0] {
			bins v[] = {[0:ATOMIC_C-1]};
			illegal_bins others = default;
		}
	endgroup
	
	covergroup strm_pkt_msg_fifo_rd_cvg;
		coverpoint strm_pkt_msg_fifo_dout[4:0]{
			bins v[] = {[0:ATOMIC_C-1]};
			illegal_bins others = default;
		}
	endgroup
	
	covergroup hw_buf_upd_cvg;
		coverpoint hw_stored_cnt{
			bins v[] = {[0:HW_BUF_LEN]};
			illegal_bins others = default;
		}
		
		coverpoint hw_buf_wptr{
			bins v[] = {[0:HW_BUF_LEN-1]};
		}
		
		coverpoint hw_buf_rptr{
			bins v[] = {[0:HW_BUF_LEN-1]};
		}
	endgroup
	
	covergroup hw_buf_wr_cvg;
		coverpoint vld_hw_n_sub1_of_cur_strm_trans{
			bins v[] = {[0:STREAM_DATA_WIDTH/16-1]};
		}
	endgroup
	
	initial
	begin
		automatic strm_pkt_msg_fifo_wr_cvg c1 = new();
		automatic strm_pkt_msg_fifo_rd_cvg c2 = new();
		automatic hw_buf_upd_cvg c3 = new();
		automatic hw_buf_wr_cvg c4 = new();
		
		fork
			forever
			begin
				@(posedge clk iff rst_n);
				
				if(strm_pkt_msg_fifo_wen & strm_pkt_msg_fifo_full_n)
					c1.sample();
				
				if(strm_pkt_msg_fifo_ren & strm_pkt_msg_fifo_empty_n)
					c2.sample();
			end
			
			forever
			begin
				@(posedge clk iff rst_n);
				
				if(s_stream_axis_hs | m_sfc_axis_hs)
					c3.sample();
			end
			
			forever
			begin
				@(posedge clk iff rst_n);
				
				if(s_stream_axis_hs)
					c4.sample();
			end
		join
	end
	
endinterface
