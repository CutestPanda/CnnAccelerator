`ifndef __PANDA_IF_H
`define __PANDA_IF_H

`include "panda_defines.svh"

interface panda_icb_if(
	input bit clk,
	input bit rst_n
);
	
	logic[`PANDA_ICB_MAX_ADDR_WIDTH-1:0] cmd_addr;
	logic cmd_read;
	logic[`PANDA_ICB_MAX_DATA_WIDTH-1:0] cmd_wdata;
	logic[`PANDA_ICB_MAX_DATA_WIDTH/8-1:0] cmd_wmask;
	logic cmd_valid;
	logic cmd_ready;
	
	logic[`PANDA_ICB_MAX_DATA_WIDTH-1:0] rsp_rdata;
	logic rsp_err;
	logic rsp_valid;
	logic rsp_ready;
	
	clocking master_cb @(posedge clk);
		output cmd_addr;
		output cmd_read;
		output cmd_wdata;
		output cmd_wmask;
		output cmd_valid;
		input cmd_ready;
		input rsp_rdata;
		input rsp_err;
		input rsp_valid;
		output rsp_ready;
	endclocking
	
	clocking slave_cb @(posedge clk);
		input cmd_addr;
		input cmd_read;
		input cmd_wdata;
		input cmd_wmask;
		input cmd_valid;
		output cmd_ready;
		output rsp_rdata;
		output rsp_err;
		output rsp_valid;
		input rsp_ready;
	endclocking
	
	clocking monitor_cb @(posedge clk);
		input rst_n;
		input cmd_addr;
		input cmd_read;
		input cmd_wdata;
		input cmd_wmask;
		input cmd_valid;
		input cmd_ready;
		input rsp_rdata;
		input rsp_err;
		input rsp_valid;
		input rsp_ready;
	endclocking
	
endinterface

interface panda_axis_if(
	input bit clk,
	input bit rst_n
);
	
	logic[`PANDA_AXIS_MAX_DATA_WIDTH-1:0] data;
	logic[`PANDA_AXIS_MAX_DATA_WIDTH/8-1:0] keep;
	logic[`PANDA_AXIS_MAX_DATA_WIDTH/8-1:0] strb;
	logic last;
	logic[`PANDA_AXIS_MAX_USER_WIDTH-1:0] user;
	logic valid;
	logic ready;
	
	clocking master_cb @(posedge clk);
		output data;
		output keep;
		output strb;
		output last;
		output user;
		output valid;
		input ready;
	endclocking
	
	clocking slave_cb @(posedge clk);
		input data;
		input keep;
		input strb;
		input last;
		input user;
		input valid;
		output ready;
	endclocking
	
	clocking monitor_cb @(posedge clk);
		input rst_n;
		input data;
		input keep;
		input strb;
		input last;
		input user;
		input valid;
		input ready;
	endclocking
	
endinterface

interface panda_blk_ctrl_if(
	input bit clk,
	input bit rst_n
);
	
	logic[`PANDA_BLK_CTRL_MAX_PARAMS_WIDTH-1:0] params;
	logic start;
	logic idle;
	logic done;
	
	clocking master_cb @(posedge clk);
		output params;
		output start;
		input idle;
		input done;
	endclocking
	
	clocking slave_cb @(posedge clk);
		input params;
		input start;
		output idle;
		output done;
	endclocking
	
	clocking monitor_cb @(posedge clk);
		input rst_n;
		input params;
		input start;
		input idle;
		input done;
	endclocking
	
endinterface

`endif
