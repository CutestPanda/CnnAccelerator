`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 导入C函数 **/
import "DPI-C" function int unsigned get_fp16(input int log_fid, input real d);
import "DPI-C" function void print_fp16(input int log_fid, input int unsigned fp16);
import "DPI-C" function real get_fp32(input int unsigned fp32);
import "DPI-C" function real get_fixed36_exp(input longint frac, input int exp);

/** 环境:卷积中间结果累加与缓存 **/
class ConvMidResAcmltEnv #(
	integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	/** 常量 **/
	// 运算数据格式
	localparam bit[1:0] CAL_FMT_INT8 = 2'b00;
	localparam bit[1:0] CAL_FMT_INT16 = 2'b01;
	localparam bit[1:0] CAL_FMT_FP16 = 2'b10;
	
	/** 配置参数 **/
	localparam bit[11:0] ofmw = 40; // 输出特征图宽度
	localparam int unsigned test_pkt_n = 8; // 测试最终结果数据包个数
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(ATOMIC_K*48), .user_width(2)) m_axis_mid_res_agt; // 中间结果输入AXIS主机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(ATOMIC_K*32), .user_width(0)) s_axis_fnl_res_agt; // 最终结果输出AXIS从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(ATOMIC_K*48), .user_width(2))) m_axis_mid_res_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(ATOMIC_K*32), .user_width(0))) s_axis_fnl_res_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(ATOMIC_K*48), .user_width(2))) m_axis_mid_res_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(ATOMIC_K*32), .user_width(0))) s_axis_fnl_res_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(ATOMIC_K*48), .user_width(2)) m_axis_mid_res_trans;
	local AXISTrans #(.data_width(ATOMIC_K*32), .user_width(0)) s_axis_fnl_res_trans;
	
	// 测试案例
	local bit[1:0] calfmt; // 运算数据格式
	local int unsigned mid_res_tid; // 中间结果事务ID
	local int unsigned mid_res_pid; // 中间结果包ID
	local int unsigned fnl_res_tid; // 最终结果事务ID
	
	// 结果比较
	local real mid_res_buf[0:test_pkt_n-1][0:ofmw*ATOMIC_K-1]; // 中间结果缓存
	
	// 日志文件句柄
	int log_fid;
	
	// 注册component
	`uvm_component_param_utils(ConvMidResAcmltEnv #(.ATOMIC_K(ATOMIC_K), .simulation_delay(simulation_delay)))
	
	function new(string name = "ConvMidResAcmltEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_mid_res_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(ATOMIC_K*48), .user_width(2))::
			type_id::create("agt1", this);
		this.m_axis_mid_res_agt.is_active = UVM_ACTIVE;
		this.s_axis_fnl_res_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(ATOMIC_K*32), .user_width(0))::
			type_id::create("agt2", this);
		this.s_axis_fnl_res_agt.use_sqr = 1'b0;
		this.s_axis_fnl_res_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axis_mid_res_trans_port = new("m_axis_mid_res_trans_port", this);
		this.s_axis_fnl_res_trans_port = new("s_axis_fnl_res_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_mid_res_agt_fifo = new("m_axis_mid_res_agt_fifo", this);
		this.s_axis_fnl_res_agt_fifo = new("s_axis_fnl_res_agt_fifo", this);
		
		// 获取配置参数
		if(!uvm_config_db #(bit[1:0])::get(this, "", "calfmt", this.calfmt))
		begin
			this.calfmt = CAL_FMT_FP16;
			
			`uvm_error("ConvMidResAcmltEnv", "cannot get calfmt(default = CAL_FMT_FP16)!")
		end
		this.mid_res_tid = 0;
		this.mid_res_pid = 0;
		this.fnl_res_tid = 0;
		
		// 打开日志文件
		this.log_fid = $fopen("log.txt");
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_mid_res_agt.axis_analysis_port.connect(this.m_axis_mid_res_agt_fifo.analysis_export);
		this.m_axis_mid_res_trans_port.connect(this.m_axis_mid_res_agt_fifo.blocking_get_export);
		this.s_axis_fnl_res_agt.axis_analysis_port.connect(this.s_axis_fnl_res_agt_fifo.analysis_export);
		this.s_axis_fnl_res_trans_port.connect(this.s_axis_fnl_res_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_mid_res_trans_port.get(this.m_axis_mid_res_trans);
				this.dispose_mid_res_trans(this.m_axis_mid_res_trans);
			end
			forever
			begin
				this.s_axis_fnl_res_trans_port.get(this.s_axis_fnl_res_trans);
				this.dispose_fnl_res_trans(this.s_axis_fnl_res_trans);
			end
		join
	endtask
	
	local function void dispose_mid_res_trans(ref AXISTrans #(.data_width(ATOMIC_K*48), .user_width(2)) trans);
		$fdisplay(this.log_fid, "********* MidRes(%d) *********", this.mid_res_tid);
		
		$fdisplay(this.log_fid, "-- first = %d last = %d", trans.user[0][1], trans.user[0][0]);
		
		for(int i = 0;i < trans.data_n;i++)
		begin
			automatic bit[ATOMIC_K*48-1:0] data = trans.data[i];
			
			$fdisplay(this.log_fid, "-- item(%d)", i);
			
			for(int j = 0;j < ATOMIC_K;j++)
			begin
				if(this.calfmt == CAL_FMT_FP16)
				begin
					automatic real f32 = get_fixed36_exp(longint'($signed(data[36:0])), int'($signed({1'b0, data[47:40]})));
					
					$fdisplay(this.log_fid, "exp = %d, frac = %d, fp32 = %f", data[47:40], $signed(data[36:0]), f32);
					
					if(trans.user[0][1])
						this.mid_res_buf[this.mid_res_pid][i * ATOMIC_K + j] = f32;
					else
						this.mid_res_buf[this.mid_res_pid][i * ATOMIC_K + j] += f32;
				end
				else
				begin
					$fdisplay(this.log_fid, "int32 = %d", $signed(data[36:0]));
					
					if(trans.user[0][1])
						this.mid_res_buf[this.mid_res_pid][i * ATOMIC_K + j] = real'($signed(data[36:0]));
					else
						this.mid_res_buf[this.mid_res_pid][i * ATOMIC_K + j] += real'($signed(data[36:0]));
				end
				
				data >>= 48;
			end
		end
		
		$fdisplay(this.log_fid, "******************************");
		$fdisplay(this.log_fid, "");
		
		if(trans.user[0][0])
			this.mid_res_pid++;
		
		this.mid_res_tid++;
	endfunction
	
	local function void dispose_fnl_res_trans(ref AXISTrans #(.data_width(ATOMIC_K*32), .user_width(0)) trans);
		$fdisplay(this.log_fid, "********* FnlRes(%d) *********", this.fnl_res_tid);
		
		for(int i = 0;i < trans.data_n;i++)
		begin
			automatic bit[ATOMIC_K*32-1:0] data = trans.data[i];
			
			$fdisplay(this.log_fid, "-- item(%d)", i);
			
			for(int j = 0;j < ATOMIC_K;j++)
			begin
				if(this.calfmt == CAL_FMT_FP16)
				begin
					automatic real f32 = get_fp32(data[31:0]);
					
					$fdisplay(this.log_fid, "fp32 = %f, err = %f", f32, this.mid_res_buf[this.fnl_res_tid][i * ATOMIC_K + j] - f32);
				end
				else
				begin
					$fdisplay(this.log_fid, "int32 = %d", $signed(data[31:0]));
					
					$fdisplay(this.log_fid, "int32 = %d, err = %f", $signed(data[31:0]), 
						this.mid_res_buf[this.fnl_res_tid][i * ATOMIC_K + j] - real'($signed(data[31:0])));
				end
				
				data >>= 32;
			end
		end
		
		$fdisplay(this.log_fid, "******************************");
		$fdisplay(this.log_fid, "");
		
		this.fnl_res_tid++;
		
		if(this.fnl_res_tid >= this.test_pkt_n)
			$fclose(this.log_fid);
	endfunction
	
endclass
	
`endif
