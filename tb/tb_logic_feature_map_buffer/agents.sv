`timescale 1ns / 1ps

`ifndef __AGENT_H

`define __AGENT_H

// 打开以下宏以启用agent
// `define BlkCtrlMstAgt
// `define AXIMstAgt
// `define AXISlvAgt
`define AXISMstAgt
`define AXISSlvAgt
// `define APBSlvAgt
// `define APBMstAgt
// `define AHBMstAgt
`define ReqAckMstAgt
// `define ICBMstAgt
// `define ICBSlvAgt

`include "transactions.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"

/** 代理:块级控制主机 **/
`ifdef BlkCtrlMstAgt
class BlkCtrlMasterAgent #(
	real out_drive_t = 1 // 输出驱动延迟量
)extends uvm_agent;
	
	// 组件
	local BlkCtrlSeqr sequencer; // 序列发生器
	local BlkCtrlMasterDriver #(.out_drive_t(out_drive_t)) driver; // 驱动器
	
	// 注册component
	`uvm_component_param_utils(BlkCtrlMasterAgent #(.out_drive_t(out_drive_t)))
	
	function new(string name = "BlkCtrlMasterAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.sequencer = BlkCtrlSeqr::type_id::create("sqr", this); // 创建sequencer
		this.driver = BlkCtrlMasterDriver #(.out_drive_t(out_drive_t))::type_id::create("drv", this); // 创建driver
		
		`uvm_info("BlkCtrlMasterAgent", "BlkCtrlMasterAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
	endfunction
	
endclass
`endif

/** 代理:AXI主机 **/
`ifdef AXIMstAgt
class AXIMasterAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_agent;
	
	// 组件
	local AXISequencer #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) sequencer; // 序列发生器
	local AXIMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) driver; // 驱动器
	local AXIMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width))) rd_trans_analysis_port;
	uvm_analysis_port #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width))) wt_trans_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AXIMasterAgent #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
	
	function new(string name = "AXIMasterAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = AXISequencer #(.addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width))::type_id::create("sqr", this); // 创建sequencer
		  this.driver = AXIMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width))::type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = AXIMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width))::type_id::create("mon", this); // 创建monitor
		
		`uvm_info("AXIMasterAgent", "AXIMasterAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.rd_trans_analysis_port = this.monitor.rd_trans_analysis_port;
		this.wt_trans_analysis_port = this.monitor.wt_trans_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:AXI从机 **/
`ifdef AXISlvAgt
class AXISlaveAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_agent;
	
	// 组件
	local AXISequencer #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) sequencer; // 序列发生器
	local AXISlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) driver; // 驱动器
	local AXIMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width))) rd_trans_analysis_port;
	uvm_analysis_port #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width))) wt_trans_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AXISlaveAgent #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
	
	function new(string name = "AXISlaveAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = AXISequencer #(.addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width))::type_id::create("sqr", this); // 创建sequencer
		  this.driver = AXISlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width))::type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = AXIMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width))::type_id::create("mon", this); // 创建monitor
		
		`uvm_info("AXISlaveAgent", "AXISlaveAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.rd_trans_analysis_port = this.monitor.rd_trans_analysis_port;
		this.wt_trans_analysis_port = this.monitor.wt_trans_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:AXIS主机 **/
`ifdef AXISMstAgt
class AXISMasterAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_agent;
	
	// 组件
	AXISSequencer #(.data_width(data_width), .user_width(user_width)) sequencer; // 序列发生器
	AXISMasterDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)) driver; // 驱动器
	AXISMonitor #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(AXISTrans #(.data_width(data_width), .user_width(user_width))) axis_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AXISMasterAgent #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISMasterAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = AXISSequencer #(.data_width(data_width), .user_width(user_width))::
			type_id::create("sqr", this); // 创建sequencer
		  this.driver = AXISMasterDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width))::
			type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = AXISMonitor #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width))::
			type_id::create("mon", this); // 创建monitor
		
		`uvm_info("AXISMasterAgent", "AXISMasterAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.axis_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:AXIS从机 **/
`ifdef AXISSlvAgt
class AXISSlaveAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_agent;
	
	// 配置参数
	bit use_sqr; // 是否使用Sequencer
	
	// 组件
	AXISSequencer #(.data_width(data_width), .user_width(user_width)) sequencer; // 序列发生器
	AXISSlaveDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)) driver; // 驱动器
	AXISMonitor #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(AXISTrans #(.data_width(data_width), .user_width(user_width))) axis_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AXISSlaveAgent #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISSlaveAgent", uvm_component parent = null);
		super.new(name, parent);
		
		this.use_sqr = 1'b0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
			if(this.use_sqr)
			begin
				this.sequencer = AXISSequencer #(.data_width(data_width), .user_width(user_width))::
					type_id::create("sqr", this); // 创建sequencer
			end
			
			this.driver = AXISSlaveDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width))::
				type_id::create("drv", this); // 创建driver
			this.driver.set_use_sqr(this.use_sqr);
		end
		
		this.monitor = AXISMonitor #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width))::
			type_id::create("mon", this); // 创建monitor
		
		`uvm_info("AXISSlaveAgent", "AXISSlaveAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if((this.is_active == UVM_ACTIVE) && this.use_sqr)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.axis_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:APB从机 **/
`ifdef APBSlvAgt
class APBSlaveAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_agent;
	
	// 组件
	local APBSequencer #(.addr_width(addr_width), .data_width(data_width)) sequencer; // 序列发生器
	local APBSlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)) driver; // 驱动器
	local APBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(APBTrans #(.addr_width(addr_width), .data_width(data_width))) apb_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(APBSlaveAgent #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "APBSlaveAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = APBSequencer #(.addr_width(addr_width), .data_width(data_width))::
			type_id::create("sqr", this); // 创建sequencer
		  this.driver = APBSlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))::
			type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = APBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))::
			type_id::create("mon", this); // 创建monitor
		
		`uvm_info("APBSlaveAgent", "APBSlaveAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.apb_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:APB主机 **/
`ifdef APBMstAgt
class APBMasterAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_agent;
	
	// 组件
	local APBSequencer #(.addr_width(addr_width), .data_width(data_width)) sequencer; // 序列发生器
	local APBMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)) driver; // 驱动器
	local APBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(APBTrans #(.addr_width(addr_width), .data_width(data_width))) apb_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(APBMasterAgent #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "APBMasterAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = APBSequencer #(.addr_width(addr_width), .data_width(data_width))::
			type_id::create("sqr", this); // 创建sequencer
		  this.driver = APBMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))::
			type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = APBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))::
			type_id::create("mon", this); // 创建monitor
		
		`uvm_info("APBMasterAgent", "APBMasterAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.apb_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:AHB主机 **/
`ifdef AHBMstAgt
class AHBMasterAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer slave_n = 1, // 从机个数
    integer addr_width = 32, // 地址位宽(10~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer burst_width = 3, // 突发类型位宽(0~3)
    integer prot_width = 4, // 保护类型位宽(0 | 4 | 7)
    integer master_width = 1 // 主机标识位宽(0~8)
)extends uvm_agent;
	
	// 组件
	local AHBSequencer #(.addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), 
		.prot_width(prot_width), .master_width(master_width)) sequencer; // 序列发生器
	local AHBMasterDriver #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)) driver; // 驱动器
	local AHBMonitor #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(AHBTrans #(.addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width))) ahb_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AHBMasterAgent #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)))
	
	function new(string name = "AHBMasterAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = AHBSequencer #(.addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), 
			.prot_width(prot_width), .master_width(master_width))::type_id::create("sqr", this); // 创建sequencer
		  this.driver = AHBMasterDriver #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), 
			.data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), 
			.master_width(master_width))::type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = AHBMonitor #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), 
			.data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width))::
			type_id::create("mon", this); // 创建monitor
		
		`uvm_info("AHBMasterAgent", "AHBMasterAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.ahb_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:req-ack主机 **/
`ifdef ReqAckMstAgt
class ReqAckMasterAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer req_payload_width = 32, // 请求数据位宽
	integer resp_payload_width = 32 // 响应数据位宽
)extends uvm_agent;
	
	// 组件
	ReqAckSequencer #(.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)) sequencer; // 序列发生器
	ReqAckMasterDriver #(.out_drive_t(out_drive_t), 
		.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)) driver; // 驱动器
	ReqAckMonitor #(.out_drive_t(out_drive_t), 
		.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(ReqAckTrans #(.req_payload_width(req_payload_width), 
		.resp_payload_width(resp_payload_width))) req_ack_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(ReqAckMasterAgent #(.out_drive_t(out_drive_t), .req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)))
	
	function new(string name = "ReqAckMasterAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = ReqAckSequencer #(.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width))
			::type_id::create("sqr", this); // 创建sequencer
		  this.driver = ReqAckMasterDriver #(.out_drive_t(out_drive_t), 
			.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width))
			::type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = ReqAckMonitor #(.out_drive_t(out_drive_t), 
			.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width))
			::type_id::create("mon", this); // 创建monitor
		
		`uvm_info("ReqAckMasterAgent", "ReqAckMasterAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.req_ack_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:ICB主机 **/
`ifdef ICBMstAgt
class ICBMasterAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)extends uvm_agent;
	
	// 组件
	ICBSequencer #(.addr_width(addr_width), .data_width(data_width)) sequencer; // 序列发生器
	ICBMasterDriver #(.out_drive_t(out_drive_t), 
		.addr_width(addr_width), .data_width(data_width)) driver; // 驱动器
	ICBMonitor #(.out_drive_t(out_drive_t), 
		.addr_width(addr_width), .data_width(data_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(ICBTrans #(.addr_width(addr_width), .data_width(data_width))) icb_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(ICBMasterAgent #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "ICBMasterAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = ICBSequencer #(.addr_width(addr_width), .data_width(data_width))
			::type_id::create("sqr", this); // 创建sequencer
		  this.driver = ICBMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))
			::type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = ICBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))
			::type_id::create("mon", this); // 创建monitor
		
		`uvm_info("ICBMasterAgent", "ICBMasterAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.icb_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

/** 代理:ICB从机 **/
`ifdef ICBSlvAgt
class ICBSlaveAgent #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)extends uvm_agent;
	
	// 组件
	ICBSequencer #(.addr_width(addr_width), .data_width(data_width)) sequencer; // 序列发生器
	ICBSlaveDriver #(.out_drive_t(out_drive_t), 
		.addr_width(addr_width), .data_width(data_width)) driver; // 驱动器
	ICBMonitor #(.out_drive_t(out_drive_t), 
		.addr_width(addr_width), .data_width(data_width)) monitor; // 监测器
	
	// 通信端口
	uvm_analysis_port #(ICBTrans #(.addr_width(addr_width), .data_width(data_width))) icb_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(ICBSlaveAgent #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "ICBSlaveAgent", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if (this.is_active == UVM_ACTIVE)
		begin
		  this.sequencer = ICBSequencer #(.addr_width(addr_width), .data_width(data_width))
			::type_id::create("sqr", this); // 创建sequencer
		  this.driver = ICBSlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))
			::type_id::create("drv", this); // 创建driver
		end
		
		this.monitor = ICBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width))
			::type_id::create("mon", this); // 创建monitor
		
		`uvm_info("ICBSlaveAgent", "ICBSlaveAgent built!", UVM_LOW)
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		if(this.is_active == UVM_ACTIVE)
			this.driver.seq_item_port.connect(this.sequencer.seq_item_export); // 连接sequence-port
		
		this.icb_analysis_port = this.monitor.in_analysis_port;
	endfunction
	
endclass
`endif

`endif
